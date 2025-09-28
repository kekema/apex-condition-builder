# apex-condition-builder
<p>Region plugin wrapping jQuery QueryBuilder enabling you to visually build logical conditions like filter- and rule conditions.
It has customizations for styling, incorporating of APEX components like Date Picker and Popup LOV, and the building of the actual conditions is supported by server-side PL/SQL code (as to further defend against SQL injection, next to the use of prepared statements).</p>
<p>For jQuery QueryBuilder, see: https://github.com/mistic100/jQuery-QueryBuilder</p>
<p>
<img src="./condition-builder.jpg" height="100%" width="100%">
</p>

See this [blog item](https://karelekema.hashnode.dev/oracle-apex-condition-builder-plugin) for an overview of the functionality. 
<p>
After importing the plugin, you can create a page with a new region, and select 'LIB4X - Condition Builder' as the region type:
</p>

<img width="60%" height="60%" alt="image" src="https://github.com/user-attachments/assets/052d71a5-9daf-4ad2-ad9d-dc5dfd6449da" />

Region Attributes:

<img width="60%" height="60%" alt="image" src="https://github.com/user-attachments/assets/96e0722d-d8e7-4af7-a24b-a74ec3fd0d04" />


```
function(options)
{
    options.queryBuilder.filters = cb.filters;
    options.queryBuilder.rules = cb.rules;
    return options;
}
```

For the example, lets define the filters and the rules in: Page - Function and Global Variable Declaration:

```
let cb = {};
cb.rules = {
    condition: 'AND',
    rules: [
    {
        id: 'prjtag',
        operator: 'equal',
        value: 'Medium-risk'
    }, 
    {
        id: 'prjcategory',
        operator: 'not_equal',
        value: 4
    },     
    {
        id: 'prjcompletiondate',
        operator: 'less_or_equal',
        value: '12/31/2024'
    },
    {
        id: 'prjbudget',
        operator: 'between',
        value: [100000,200000]
    },
    {
        id: 'prjstatus',
        operator: 'in',
        value: ['ASSIGNED','IN-PROGRESS']
    },               
    {
        condition: 'OR',
        rules: [
        {
            id: 'taskid',
            operator: 'equal',
            value: 93,
            displayValue: 'Configure production data load procedures'
        },
        {
            id: 'taskassignee',
            operator: 'equal',
            value: 6
        },        
        {
            id: 'taskcompleted',
            operator: 'equal',
            value: 'N'
        },
        {
            id: 'taskcompletiondatetime',
            operator: 'less_or_equal',
            value: '06/01/2024 12:00:00'
        },
        {
            id: 'taskhourlyrate',
            operator: 'less_or_equal',
            value: 72.65
        }]
    }]
};
cb.filters = [
    {
        id: 'prjtag',
        field: 'PRJ_TAG',
        label: 'Project Tag',
        type: 'string',
        value_separator: ','
    }, 
    {
        id: 'prjcategory',
        field: 'PRJ_CATEGORY',
        label: 'Project Category',
        type: 'integer',
        input: 'select',
        values: {
            1: 'Maintenance',
            2: 'Construction',
            3: 'Installation',
            4: 'Utility',
            5: 'Energy',
            6: 'Telecom'
        },
        operators: ['equal', 'not_equal', 'is_null', 'is_not_null']
    }, 
    {
        id: 'prjcompletiondate',
        field: 'PRJ_COMPLETION_DATE',
        label: 'Project Completion Date',
        type: 'date',
        operators: ['equal', 'not_equal', 'less', 'less_or_equal', 'greater', 'greater_or_equal', 'between', 'not_between', 'is_empty', 'is_not_empty']        
    },
    {
        id: 'prjbudget',
        field: 'PRJ_BUDGET',
        label: 'Project Budget',
        type: 'double',  
        apex:{    
            formatMask: '999G999G999G999G990'
        },     
        input: 'number',
        operators: ['equal', 'not_equal', 'less', 'less_or_equal', 'greater', 'greater_or_equal', 'between', 'not_between', 'is_null', 'is_not_null']         
    }, 
    {
        id: 'prjstatus',
        field: 'PRJ_STATUS',
        label: 'Project Status',
        type: 'string',
        input: 'checkbox',
        values: {
            'ASSIGNED': 'Assigned',
            'IN-PROGRESS': 'In Progress',
            'COMPLETED': 'Completed',
            'ARCHIVED': 'Archived'
        },
        vertical: false,
        operators: ['in', 'not_in']
    },         
    {
        id: 'taskid',
        field: 'TASK_ID',
        label: 'Task',
        type: 'integer',     
        input: 'select',            
        apex:{
            referenceItem: 'P10_TASK',
            width: 50
        },
        operators: ['equal', 'not_equal']           
    },         
    {
        id: 'taskcompleted',
        field: 'TASK_COMPLETED',
        label: 'Task Completed',
        type: 'string',
        input: 'radio',        
        values: {
            'N': 'No',
            'Y': 'Yes'
        },
        operators: ['equal', 'not_equal']
    }, 
    {
        id: 'taskcompletiondatetime',
        field: 'TASK_COMPLETION_DATETIME',
        label: 'Task Completion',
        type: 'datetime',     
        apex: {
            formatMask: 'MM/DD/YYYY HH24:MI:SS'
        },  
        operators: ['less_or_equal', 'greater_or_equal', 'between']           
    },
    {
        id: 'taskassignee',
        field: 'TASK_ASSIGNEE',
        label: 'Task Assignee',
        type: 'integer',
        input: 'select',
        apex:{
            referenceItem: 'P10_ASSIGNEE'
        },
        operators: ['equal', 'not_equal', 'is_null', 'is_not_null']
    },
    {
        id: 'taskhourlyrate',
        field: 'TASK_HOURLY_RATE',
        label: 'Task Hourly Rate',
        type: 'double',  
        apex:{    
            formatMask: '999G999G999G999G990D00'
        },     
        input: 'number',
        operators: ['less_or_equal', 'greater_or_equal', 'between'],
        validation:{
            min: 22,
            max: 95
        }                 
    }                         
];
```
For a description on the configuration options, see the [jQuery QueryBuilder documentation](https://querybuilder.js.org/index.html). The config can be set client-side like in above example, however it can also be done server-side using the Initialization PL/SQL Block. See the inline help for an example. 

In few places, an APEX extension is supported. For integer/double/date filter types, you can specify a formatMask. For filters with input 'select', instead of specifying values, you can reference an APEX item - which can be here an APEX item of type 'Select' or 'Popup LOV'. An approach can be to have these items in a hidden subregion:

<img width="30%" height="30%" alt="image" src="https://github.com/user-attachments/assets/616beacf-f14b-43af-81b7-abc24906689f" />

For any 'Popup LOV' item, configure the 'Display As' settings as 'Modal Dialog'. In addition, leave the 'Multiple Values' setting to 'No'. In case you want to enable multiple values, you can do so via the jQuery QueryBuilder [filter attribute](https://querybuilder.js.org/#filters) 'multiple' by setting that one to true. This will extend the Popup LOV field and make it a list manager:

<img width="80%" height="80%" alt="image" src="https://github.com/user-attachments/assets/b6ad9b07-e11d-4ca8-b41e-881c6d695496" />

Another extension is enabling a link to a lookup page by clicking on an icon next to the rule:

<img width="35%" height="35%" alt="image" src="https://github.com/user-attachments/assets/d865cde2-fe69-4814-9249-25fa837a6de6" />

This might be a page with additional info or drilldown on the rule (value). You can configure as a url to a regular webpage, or you can configure an APEX page to be opened. The filter id and rule value can be used to substitute placeholders.
You can configure the lookup as part of a filter definition, eg:

```
    {
        id: 'category',
        label: 'Category',
        type: 'integer',
        input: 'select',
        multiple: false,
        values: {
            1: 'Books',
            2: 'Movies',
            3: 'Music',
            4: 'Tools',
            5: 'Goodies',
            6: 'Clothes'
        },
        operators: ['equal', 'not_equal', 'in', 'not_in', 'between', 'is_null', 'is_not_null'],
        apex:{
            lookup:{
                icon: 'fa fa-info-square-o',  // optional, default is 'fa fa-info-square-o'
                // Either configure a url:     
                url: 'https://www.google.com/search?q={filter.id}+{rule.value}',
                target: 'myPopup',    // optional, default is '_blank'
                windowFeatures: 'left=100,top=100,width=1000,height=750',    // optional
                // the url will be opened with window.open(url, target, windowFeatures)
                // OR: configure a pageId:
                pageId:78,
                itemNames:['P78_FILTER_ID', 'P78_RULE_VALUE'], // optional
                itemValues:['{filter.id}', '{rule.value}']     // optional
                // the page will be opened using apex.navigation.openInNewWindow(url), which opens in a new tab
                // in the target page, have 'Page Access Protection' as 'unrestricted' so no checksum is required           
            }
        }
    }
```

For rules, there is also a small extension: in case of rules where you reference an APEX item of type 'Popup LOV', or the rule has input by means of 'select', 'radio' or 'checkbox', the rule will have next to the value(s) also the displayValue(s). This is used to properly render a rule with 'Popup LOV' enabled, and to be able to compose human readable conditions (Display Conditions).

Now, you can add a 'Build' button to the region as to build the actual conditions:

<img width="30%" height="30%" alt="image" src="https://github.com/user-attachments/assets/b48e4f44-ee30-4d9c-bdd4-857dbe8c98dc" />

First JavaScript action:

```
apex.item('P10_SERVER_ERROR').setValue('');
apex.message.clearErrors();
if (apex.region('cb_demo').validate())
{
    let jsonResult = apex.region('cb_demo').getRules();
    apex.item('P10_DEFINITION').setValue(JSON.stringify(jsonResult, null, 2));
}
else
{
    apex.message.showErrors( [
        {
            type:       "error",
            location:   "page",
            message:    "Validation errors",
            unsafe:     false
        }
    ] );     
}
```

The apex.region('cb_demo').getRules() calls the jQuery QueryBuilder getRules() API as to arrive at the JSON definition of the Rule Set, which makes up the composite Condition. This definition is used in the next step in PL/SQL:

```
declare
    l_condition_rec lib4x_condition.t_condition_rec;
begin
    apex_util.set_session_state('P10_SERVER_ERROR', null);  
    l_condition_rec := lib4x_condition.build(:P10_DEFINITION, false, true);
    apex_util.set_session_state('P10_DISPLAY_CONDITION', l_condition_rec.display_condition);
    apex_util.set_session_state('P10_FILTER_CONDITION', l_condition_rec.filter_condition);
    apex_util.set_session_state('P10_RULE_CONDITION', l_condition_rec.rule_condition);
    apex_util.set_session_state('P10_PARAMETERS', l_condition_rec.display_params);
exception
    when others then
        apex_util.set_session_state('P10_SERVER_ERROR', SQLERRM);
end;
```

<img width="80%" height="80%" alt="image" src="https://github.com/user-attachments/assets/6efbbc6d-b388-4915-bfbc-0d749d3efe83" />

The pl/sql code is in the LIB4X_CONDITION package. The source you find in the src/plsql folder.

As last step, we give in JavaScript the feedback:

```
let serverError = apex.item('P10_SERVER_ERROR').getValue();
if (serverError)
{
    apex.message.showErrors(
        {
            type:       "error",
            location:   "page",
            message:    serverError
        }
    );
}
else
{
    apex.message.showPageSuccess( "Condition build succesfully" );
}
```

The region interface supports the following methods:

create(options): can be used instead of the JavaScript Initialization Function (region attributes)<br>
getRules(): get the condition definition. Calls queryBuilder.getRules()<br>
setRules(rules, options): calls queryBuilder.setRules(rules, options)<br>
validate(options): calls queryBuilder.validate(options)<br>
reset(): calls queryBuilder.reset()<br>
undo(): reverts the changes to last set undo point<br>
setUndoPoint(): set undo point as used by undo()<br>

The LIB4X_CONDITION PL/SQL package supports 2 functions: build and evaluate. For more info, see the package inline documentation.

<h3>Plugin versions</h3>
Version 1.0.0 - build under APEX 24.1<br>
Version 1.1.0 - build under APEX 24.2 - has the Initialization PL/SQL Block attribute added<br>
Version 1.2.0 - build under APEX 24.2 - implements the QueryBuilder 'multiple' filter attribute for rule inputs where a Popup LOV is used by applying a List Manager

<h3>Third-Party Libraries and Licenses</h3>

This software uses:<br>
[jQuery QueryBuilder](https://querybuilder.js.org/api/), which is licensed under the MIT License.<br>
Copyright (c) 2014-2018 Damien Sorel<br>
[License](https://github.com/mistic100/jQuery-QueryBuilder/blob/dev/LICENSE) | [Project](https://github.com/mistic100/jQuery-QueryBuilder)

[interact.js](https://interactjs.io/), which is licensed under the MIT License.<br>
Copyright (c) 2012-present Taye Adeyemi<br>
[License](https://github.com/taye/interact.js/blob/main/LICENSE) | [Project](https://github.com/taye/interact.js)






