window.lib4x = window.lib4x || {};
window.lib4x.axt = window.lib4x.axt || {};

/*
 * Region plugin wrapping jQuery QueryBuilder enabling to visually build logical conditions like filter- and rule conditions.
 * It has customizations for styling, incorporating of APEX components like Date Picker and Popup LOV, and the building of 
 * the actual conditions is supported by server-side PL/SQL code (as to further defend against SQL injection, next to the use of prepared statements).
 * For jQuery QueryBuilder, see: https://github.com/mistic100/jQuery-QueryBuilder
 */
lib4x.axt.conditionBuilder = (function($) {
    
    const C_LIB4X_CB = 'lib4x-cb';
    const C_LIB4X_CB_NUMBER = 'lib4x-cb-number';
    const QB_EXT = '_qb';
    let undoPoint = {};

    let queryBuilderModule = (function() 
    {
        let initQB = function(cbStaticId, cbStaticIdQb, options) {
            let qb$ = $('#' + cbStaticIdQb);          
            qb$.on("afterInit.queryBuilder", (jQueryEvent) => { 
                let filters = qb$[0].queryBuilder.settings.filters;
                filters.forEach((filter)=>{
                    if (filter.apex && filter.apex.formatMask)
                    {
                        // specify data.formatmask so we will have the formatmask also
                        // available while outputting JSON / SQL
                        // for consistency, the formatmask is just taken from data.formatmask everywhere
                        filter.data = filter.data || {};
                        filter.data.formatMask = filter.apex.formatMask;
                    }
                    if (filter.type.includes('date'))
                    {
                        // for date or datetime, use date picker by createDateInput function
                        // unless developer has specified already a function
                        if (typeof filter.input !== 'function')
                        {
                            filter.input = utilityModule.createDateInput;
                        }
                        filter.validation = filter.validation || {};
                        let isFunction = (filter.validation.callback && typeof filter.validation.callback === 'function');
                        if (!isFunction)
                        {
                            filter.validation.callback = utilityModule.validateDateValue;
                        }
                    }
                    if (filter.apex && filter.apex.referenceItem && apex.item(filter.apex.referenceItem))
                    {
                        if (typeof filter.input !== 'function')
                        {
                            let itemType = apex.item(filter.apex.referenceItem).item_type;
                            if (itemType && itemType.endsWith('_LOV'))
                            {
                                filter.input = utilityModule.createLovInput;
                            }
                        }
                    }                     
                    if (filter.input == 'number')
                    {
                        if (typeof filter.input !== 'function')
                        {
                            filter.input = utilityModule.createNumberInput;
                        }
                    }                   
                })
                let sqlOperators = qb$[0].queryBuilder.settings.sqlOperators;
                if (sqlOperators)
                {
                    if (sqlOperators.is_empty)
                    {
                        sqlOperators.is_empty.op = sqlOperators.is_null.op;
                    }
                    if (sqlOperators.is_not_empty)
                    {
                        sqlOperators.is_not_empty.op = sqlOperators.is_not_null.op;
                    }                
                }
            })
            qb$.on('getRuleFilterSelect.queryBuilder.filter getRuleOperatorSelect.queryBuilder.filter getRuleValueSelect.queryBuilder.filter', function(html, arg2, arg3){
                html.value = html.value.replace('form-select', 'form-select apex-item-select');
            });    
            qb$.on('getRuleValueSelect.queryBuilder.filter', function(html, name, rule){
                // In the filter definition, an apex item can be specified.
                // This can be a select item in a hidden region. The options from this 
                // item will be cloned and copied into the rule value field.
                if (rule.filter.apex && rule.filter.apex.referenceItem)
                {
                    html.value = $($.parseHTML(html.value)[0]).append($('#'+ rule.filter.apex.referenceItem + ' > option').clone())[0].outerHTML;
                }
            });             
            qb$.on('getRuleInput.queryBuilder.filter', function(html, rule, name){
                if (rule.filter.input == 'text')
                {
                    html.value = html.value.replace('form-control', 'form-control apex-item-text');
                }
                if (rule.filter.input == 'number')
                {
                    html.value = html.value.replace('form-control', 'form-control apex-item-text');
                }  
                if (rule.filter.input == "textarea")
                {
                    html.value = html.value.replace('form-control', 'form-control apex-item-textarea');
                }      
            }); 
            qb$.on('getRuleValue.queryBuilder.filter', function(jQueryEvent, rule){
                if (rule.$el.find('.rule-value-container input').hasClass(C_LIB4X_CB_NUMBER))
                {
                    if (jQueryEvent.value)
                    {
                        let formatMask = rule.filter.data?.formatMask;
                        if (formatMask)
                        {
                            if (rule.operator.nb_inputs == 1) 
                            {
                                jQueryEvent.value = apex.locale.toNumber(jQueryEvent.value, formatMask);
                            }
                            else if (rule.operator.nb_inputs > 1) 
                            {
                                jQueryEvent.value.forEach(function(value, index){
                                    if (jQueryEvent.value[index])
                                    {
                                        jQueryEvent.value[index] = apex.locale.toNumber(jQueryEvent.value[index], formatMask);
                                    }
                                });
                            }
                        }                        
                    }
                }
            });
            qb$.on('jsonToRule.queryBuilder.filter', function(jQueryEvent, json){
                // in case of a rule with LOV, also set the display value(s) in the rule
                let rule = jQueryEvent.value;
                if (rule.filter?.apex?.referenceItem)
                {
                    let itemType = apex.item(rule.filter.apex.referenceItem).item_type;
                    if (itemType && itemType.endsWith('_LOV'))
                    {
                        if (rule.operator.nb_inputs == 1) 
                        {
                            let displayValue = json.displayValue;
                            rule.$el.find('#' + rule.id + '_value_0_lov').val(displayValue);
                        }
                        else if (rule.operator.nb_inputs > 1) 
                        {      
                            for (let i = 0; i < rule.operator.nb_inputs; i++)
                            {
                                let displayValue = json.displayValue[i];
                                rule.$el.find('#' + rule.id + '_value_' + i + '_lov').val(displayValue);
                            }                                                    
                        }                   
                    }
                }              
            });
            qb$.on('ruleToJson.queryBuilder.filter', function(jQueryEvent, rule){
                // include the label
                jQueryEvent.value.label = rule.filter.label ? rule.filter.label : rule.filter.field;
                // in case of in operator with type string, the splitted values might have leading/trailing spaces to be trimmed 
                if ((jQueryEvent.value?.operator == 'in') && (jQueryEvent.value?.type == 'string') && jQueryEvent.value?.value)
                {
                    if (Array.isArray(jQueryEvent.value.value))
                    {
                        jQueryEvent.value.value = jQueryEvent.value.value.map(str => str.trim());
                    }
                }
                // in case of a rule with LOV, include also the displayValue(s) in the json
                if (rule.filter?.apex?.referenceItem)
                {
                    let itemType = apex.item(rule.filter.apex.referenceItem).item_type;
                    if (itemType && itemType.endsWith('_LOV'))
                    {
                        if (rule.operator.nb_inputs == 1) 
                        {
                            let displayValue = rule.$el.find('#' + rule.id + '_value_0_lov').val();
                            jQueryEvent.value.displayValue = displayValue;
                        }
                        else if (rule.operator.nb_inputs > 1) 
                        {
                            jQueryEvent.value.displayValue = [];
                            for (let i = 0; i < rule.operator.nb_inputs; i++)
                            {
                                let displayValue = rule.$el.find('#' + rule.id + '_value_' + i + '_lov').val();
                                jQueryEvent.value.displayValue[i] = displayValue;
                            }
                        }                        
                    }
                }
                // in case of a rule with a 'select' input, include also the displayValue(s) in the json
                if (rule.filter.input == 'select')
                {
                    if (rule.operator.nb_inputs == 1) 
                    {
                        let displayValue = rule.$el.find('select[name="' + rule.id + '_value_0"]  option[value="' + rule.value + '"]').text();
                        jQueryEvent.value.displayValue = displayValue;
                    }
                    else if (rule.operator.nb_inputs > 1) 
                    {
                        jQueryEvent.value.displayValue = [];
                        for (let i = 0; i < rule.operator.nb_inputs; i++)
                        {
                            let displayValue = rule.$el.find('select[name="' + rule.id + '_value_' + i + '"]  option[value="' + rule.value[i] + '"]').text();
                            jQueryEvent.value.displayValue[i] = displayValue;
                        }
                    }                     
                }
                // in case of a rule with a 'radio' input, include also the displayValue(s) in the json
                if (rule.filter.input == 'radio')
                {
                    if (rule.operator.nb_inputs == 1) 
                    {
                        let displayValue = rule.filter.values[rule.value];
                        jQueryEvent.value.displayValue = displayValue;
                    }
                    else if (rule.operator.nb_inputs > 1) 
                    {
                        jQueryEvent.value.displayValue = [];
                        for (let i = 0; i < rule.operator.nb_inputs; i++)
                        {
                            let displayValue = rule.filter.values[rule.value[i]];
                            jQueryEvent.value.displayValue[i] = displayValue;
                        }
                    }
                }
                // in case of a rule with a 'checkbox' input, include also the displayValue(s) in the json
                if (rule.filter.input == 'checkbox')
                {
                    // only nb_inputs 1 makes sense
                    if (rule.operator.nb_inputs == 1) 
                    {
                        // one or more checkboxes can be checked
                        jQueryEvent.value.displayValue = [];
                        for (let i = 0; i < rule.value.length; i++)
                        {
                            let displayValue = rule.filter.values[rule.value[i]];
                            jQueryEvent.value.displayValue[i] = displayValue;
                        }                        
                    }
                }                
            });         
            qb$.on('ruleToSQL.queryBuilder.filter', function(expression, rule, value, valueWrapper){
                // add Oracle specific syntax elements
                if (rule?.type.includes('date'))
                {
                    if (expression.value)
                    {
                        let formatMask = rule.data?.formatMask ? rule.data?.formatMask : apex.locale.getDateFormat();
                        if (formatMask == 'DS')
                        {
                            formatMask = apex.locale.getDSDateFormat();
                        }
                        else if (formatMask == 'DL')
                        {
                            formatMask = apex.locale.getDLDateFormat();
                        }
                        if ((rule.operator != 'in') && (rule.operator != 'not_in'))
                        {
                            let values = expression.value.match(/:\w+/g) || []; // get bind variables
                            values.forEach(function(value, index){
                                expression.value = expression.value.replace(value, "TO_DATE(" + value + ", '" + formatMask + "')");
                            });
                        }
                        else
                        {
                            expression.value = expression.value.replace(/^\S+/, "TO_CHAR(" + expression.value.split(" ")[0] + ", '" + formatMask + "')");
                        }
                    }
                }
            });
            qb$.on('groupToJson.queryBuilder.filter', function(jQueryEvent, group){
                // for the root group, add the default date format
                if (group.id == group.model.root.id)
                {
                    jQueryEvent.value.dateFormat = util.locale.getDateFormat();
                }
            });                 
            qb$.on('change', '.'+C_LIB4X_CB_NUMBER, function(jQueryEvent, data){
                let formatMask = $(this).attr('data-format');
                if (formatMask)
                {
                    let formattedValue = apex.locale.formatNumber($(this).val(), formatMask);
                    if (formattedValue && formattedValue != 'NaN')
                    {
                        $(this).val(formattedValue.trim());
                    }
                }
            });           
            qb$.on('click', '.a-Button--popupLOV', function(jQueryEvent, data){
                // An lov input has a related hidden apex lov item. Upon button click, we
                // simulate the click on the hidden item as to open the lov dialog. 
                // Upon lov item value change, we take the value and assign it to
                // the rule input.
                let lovItem = $(this).attr('lovitem');
                let ruleLovId = $(this).attr('id').replace("_btn", "");
                if (lovItem)
                {
                    apex.item(lovItem).element.off('change.lib4x-cb').on('change.lib4x-cb', function(jQueryEvent, data){
                        let lovValue = apex.item(lovItem).getValue();
                        let displayValue = apex.item(lovItem).displayValueFor(lovValue);
                        // QB is listening to the change event as to set the value on the rule in the model.
                        $('#'+ruleLovId+'_hiddenvalue').val(lovValue).trigger('change');
                        $('#'+ruleLovId).val(displayValue);
                    });
                    apex.item(lovItem).element.next("button").click();
                }
            });
            let qbOptions = options.queryBuilder;
            if (!qbOptions.plugins)
            {
                qbOptions.plugins = {};
            }
            if (!Object.hasOwn(qbOptions.plugins, 'sortable'))
            {
                qbOptions.plugins.sortable = {icon: 'fa fa-bars'};
            }
            if (!Object.hasOwn(qbOptions.plugins, 'not-group'))
            {
                qbOptions.plugins['not-group'] = {
                    icon_checked: 'fa fa-check-square-o',
                    icon_unchecked: 'fa fa-square-o'
                };
            }
            // qbOptions.plugins['invert'] = null;
            // below is on how to have booleans as 1/0 (default) or as true/false
            //qbOptions.plugins['sql-support'] = {boolean_as_integer: false};   // default is true
            if (!qbOptions.icons)
            {
                qbOptions.icons = {
                    add_group: 'fa fa-plus-square',
                    add_rule: 'fa fa-plus-circle',
                    remove_group: 'fa fa-minus-square',
                    remove_rule: 'fa fa-minus-circle',
                    //remove_group: 'fa fa-remove',
                    //remove_rule: 'fa fa-remove',            
                    error: 'fa fa-exclamation-triangle'
                };
            }
            if (!qbOptions.lang_code)
            {
                let langCode = apex.locale.getLanguage();
                if (langCode.includes('-') && langCode.length == 5)
                {
                    // a langcode like pt-br: make it pt-BR
                    langCode = langCode.slice(0,-2) + langCode.slice(-2).toUpperCase();
                }
                qbOptions.lang_code = langCode;
                // the translation file (if any) is loaded server-side in the plugin
                // qb has by default the 'en' file loaded
            }
            qbOptions.lang = qbOptions.lang || {};
            qbOptions.lang.delete_rule = ' ';
            qbOptions.lang.delete_group = ' ';
            if (qbOptions.lang_code.startsWith('en'))
            {
                // EN: replace 'Add Rule'/'Add Group' by 'Row'/'Group'
                qbOptions.lang.add_rule = 'Row';
                qbOptions.lang.add_group = 'Group';
            }     
            if (!qbOptions.select_placeholder)
            {
                qbOptions.select_placeholder = '';
            }
            qb$.queryBuilder(qbOptions);   
            if (qbOptions.rules)
            {
                undoPoint[cbStaticId] = qbOptions.rules;
            }                                    
        }

        return{
            initQB: initQB
        }
    })();   

    let utilityModule = (function()
    {
        /*
         * createDateInput
         * Can be used in a Filter definition for the 'input' attribute.
         * It returns the HTML for an APEX alike date input field.
         * The date format is as per apex.locale.getDateFormat().
         */
        let createDateInput = function(rule, input_name)
        {
            let formatMask = rule.filter.data?.formatMask;
            formatMask = formatMask ? formatMask : apex.locale.getDateFormat();
            let showTime = (rule.filter.type.includes('time'));
            let size = rule.filter.apex?.width ? rule.filter.apex.width : showTime ? 20 : 15;            
            return '<a-date-picker id="' + input_name + '_id' + '" change-month="true" change-year="true" display-as="popup" display-weeks="none" format="' + formatMask + '" previous-next-distance="one-month" show-days-outside-month="visible" show-on="image" show-time="' + showTime + '" time-increment-minute="15" today-button="false" valid-example="1/28/2025" year-selection-range="5" class="apex-item-datepicker--popup"><input aria-haspopup="dialog" class="apex-item-text apex-item-datepicker" name="' + input_name + '" size="' + size + '" type="text" id="' + input_name + '_id_input' + '" aria-expanded="false"><button aria-haspopup="dialog" aria-label="Select Date" class="a-Button a-Button--calendar" tabindex="-1" title="Select Date" type="button" aria-controls="' + input_name + '_id_input' + '" aria-expanded="false"><span class="a-Icon icon-calendar"></span></button></a-date-picker>';
        }

        let createNumberInput = function(rule, input_name)
        {
            let formatMask = rule.filter.data?.formatMask;
            let dataFormat = "";
            if (formatMask)
            {
                dataFormat = 'data-format="' + formatMask + '" ';
            }
            let size = rule.filter.apex?.width ? rule.filter.apex.width : 15;
            return '<input type="text" id="' + input_name + '_id' + '" name="' + input_name + '" class="number_field apex-item-text u-textStart ' + C_LIB4X_CB_NUMBER + '" value="" size="' + size + '" ' + dataFormat + 'inputmode="decimal"></input>';           
        }

        let createLovInput = function(rule, input_name)
        {
            let size = rule.filter.apex?.width ? rule.filter.apex.width : 25;
            return '<div class="apex-item-group apex-item-group--popup-lov"><input type="hidden" name="' + input_name + '" id="' + input_name + '_lov_hiddenvalue"><input type="text" id="' + input_name + '_lov" class="apex-item-text apex-item-popup-lov" size="' + size + '" readonly role="combobox" aria-autocomplete="list" aria-expanded="false" aria-haspopup="dialog"><button type="button" class="a-Button a-Button--popupLOV" id="' + input_name + '_lov_btn" lovitem="' + rule.filter.apex.referenceItem + '"><span class="a-Icon icon-popup-lov"></span></button></div>';
        }

        /*
         * validateDateValue
         * Can be used in a Filter definition for the validation callback as to perform
         * a custom validation which is here a native APEX date validation.
         * For most rule operators, the value will be one element, but for some operators,
         * like 'between', there will be two elements in an array. In that case, the
         * callback will validate both values. Also it will be validated then if the
         * first date is not after the second date.
         * The return value will be true in case the value(s) are valid, or else the return
         * will be the validation error message.
         */
        let validateDateValue = function(value, rule) 
        {
            let filter = rule.filter;
            let operator = rule.operator;
            let validation = filter.validation || {};
            let result = true;
            let tempValue;

            if (rule.operator.nb_inputs === 1) 
            {
                value = [value];
            }
            for (let i = 0; i < operator.nb_inputs; i++) 
            {
                if (!operator.multiple && $.isArray(value[i]) && value[i].length > 1) 
                {
                    result = ['operator_not_multiple', operator.type, this.translate('operators', operator.type)];
                    break;
                }  
                else
                {
                    tempValue = $.isArray(value[i]) ? value[i] : [value[i]];
                    for (var j = 0; j < tempValue.length; j++) 
                    {   
                        if (tempValue[j] === undefined || tempValue[j].length === 0) 
                        {
                            if (!validation.allow_empty_value) 
                            {
                                result = ['datetime_empty'];
                                break;
                            }
                        }
                        // Though the field is not defined/registered as an apex item 
                        // (item not present in the apex metadata / the id is unequal to the name),
                        // we can still use the apex item interface as to validate the field
                        let itemId = rule.id + '_value_' + i + '_id';
                        result = apex.item(itemId).getValidity().valid;
                        if (!result)
                        {
                            result = apex.item(itemId).getValidationMessage().trim();
                            result = result.charAt(0).toUpperCase() + result.slice(1);
                            break;
                        }
                    }
                }
            }
            if (result === true)
            {
                if ((rule.operator.type === 'between' || rule.operator.type === 'not_between') && value.length === 2) 
                {
                    // check if the first date is not after the second date
                    if (value[0] && value[1])
                    {
                        let formatMask = rule.filter.data?.formatMask;
                        formatMask = formatMask ? formatMask : apex.locale.getDateFormat();
                        let date0 = apex.date.parse(value[0], formatMask);
                        let date1 = apex.date.parse(value[1], formatMask);
                        if (date0 > date1)
                        {
                            result = ['datetime_between_invalid', value[0], value[1]];
                        }
                    }
                }
            }
            return result;
        }      
        
        /*
         * In case of starting dialogs from an inline dialog, no overlay is appearing to the inline dialog. The overlay is actually 
         * created (on the page body), but the z-index is lower than the inline dialog. By having next code, the z-index will be 
         * corrected and the overlay will cover the inline dialog.
         * A filterClass can be given as to restrict the check to certain dialogs only.
         */
        let enableInlineDialogOverlay = function(filterClass) 
        {
            $(apex.gPageContext$).on('dialogcreate', function(jQueryEvent, data) {
                let target$ = $(jQueryEvent.target);
                if (typeof filterClass === 'undefined' || filterClass === null || target$.closest('.ui-dialog').hasClass(filterClass))
                {
                    setTimeout(()=>{
                        if ($('.ui-widget-overlay').length > 1)
                        {
                            let maxZIndex = 0;
                            $('.ui-widget-overlay').not(":last").each(function() {
                                let zIndex = parseInt($(this).css('z-index'));
                                maxZIndex = (zIndex > maxZIndex) ? zIndex : maxZIndex;
                            });        
                            let lastZIndex = parseInt($('.ui-widget-overlay').last().css('z-index'));    
                            if (lastZIndex <= maxZIndex)
                            {
                                $('.ui-widget-overlay').last().css('z-index', maxZIndex + 1);
                                target$.dialog('moveToTop');   
                            }
                        }     
                    }, 10);
                }
            });             
        }

        return{
            createDateInput: createDateInput,
            createNumberInput: createNumberInput,
            createLovInput: createLovInput,
            validateDateValue: validateDateValue,
            enableInlineDialogOverlay: enableInlineDialogOverlay
        }        
    })();

    // ==util module
    let util = {   
        locale:
        {
            getDateFormat: function()
            {
                let dateFormat = apex.locale.getDateFormat();
                if (dateFormat == 'DS')
                {
                    dateFormat = apex.locale.getDSDateFormat();
                }
                else if (dateFormat == 'DL')
                {
                    dateFormat = apex.locale.getDLDateFormat();
                }     
                return dateFormat;           
            }
        }
    };     
    
    function initMessages()
    {
        // here we can have the labels and messages for which the developer should be 
        // able to config translations in APEX
        // currently, no labels or messages are applicable
        // example:
        /*apex.lang.addMessages({
            'LIB4X.CB.COL_EXP_GRP': 'Collapse/Expand Groups',
            'LIB4X.CB.COL_GRP': 'Collapse Groups',
            'LIB4X.CB.EXP_GRP': 'Expand Groups',
            'LIB4X.CB.Q_VAL_ERR_CLOSE_DIALOG': 'Data has validation errors. Close Dialog?'
        });*/      
    }

    function getMessage(key) {
        return apex.lang.getMessage('LIB4X.RB.' + key);
    }    

    /*
     * Main plugin init function
     */
    let init = function(cbStaticId, initFunc)
    {
        initMessages();
        let cbStaticIdQb = cbStaticId + QB_EXT;
        // tag the region as being a CB
        $('#'+cbStaticId).addClass(C_LIB4X_CB);
        let options = {};     
        options.queryBuilder = {};
        if (initFunc)
        {
            // call init function
            options = initFunc(options);
        }
        // create region interface
        // by apex.region('<static id>').widget()[0].queryBuilder, the queryBuilder can be reached
        // by apex.region('<static id>').widget().queryBuilder(..), the queryBuilder API can be used
        // to get the current settings: apex.region('<static id>').widget()[0].queryBuilder.settings
        apex.region.create(cbStaticId, {
            type: "ConditionBuilder",
            widget: function() {
                return $('#' + cbStaticIdQb);
            },
            create: function(options) {
                if (this.widget()[0].queryBuilder)
                {
                    this.destroy();
                }
                queryBuilderModule.initQB(cbStaticId, cbStaticIdQb, options);
            },
            destroy: function()
            {
                if (this.widget()[0].queryBuilder)
                {
                    this.widget().queryBuilder('destroy');
                }
            },
            getRules: function(options)
            {
                return this.widget().queryBuilder('getRules', options);
            },
            getSQL: function(stmt, nl, data)
            {
                return this.widget().queryBuilder('getSQL', stmt, nl, data);
            },            
            setRules: function(rules, options)
            {
                this.widget().queryBuilder('setRules', rules, options);
            },
            validate: function(options)
            {
                return this.widget().queryBuilder('validate', options);
            },
            reset: function()
            {
                this.widget().queryBuilder('reset');
            },
            undo: function()
            {
                if (undoPoint[cbStaticId])
                {
                    this.widget().queryBuilder('setRules', undoPoint[cbStaticId]);
                }
                else
                {
                    this.reset();
                }
            },
            setUndoPoint: function()
            {
                undoPoint[cbStaticId] = this.widget().queryBuilder('getRules');
            }     
        });   
        // if options have been given via the init func and filters are known,
        // call initQB. Else, the CB can be created later by calling region create method.
        if (options.queryBuilder?.filters)
        {  
            queryBuilderModule.initQB(cbStaticId, cbStaticIdQb, options);
        }
    };

    return{
        _init: init,
        enableInlineDialogOverlay: utilityModule.enableInlineDialogOverlay
    }
})(apex.jQuery);
