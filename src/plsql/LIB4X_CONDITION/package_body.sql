create or replace package body LIB4X_CONDITION as

  -- cached cursors for condition evaluation
  type t_cached_cursors is table of number index by t_condition;
  g_cached_cursors t_cached_cursors;
  
  /*
   * Given a QueryBuilder(qb) rules definition, the function builds both a 
   * filter- and a rule condition. Typically, a filter condition can be used
   * in a query where clause. A rule condition can be evaluated for example
   * using claim data. 
   * Example (named) filter condition:
   *  (customer_id = :customer_id1 AND order_date between :order_date1 AND :order_date2)
   * The param list will have values for customer_id1, order_date1 and order_date2
   * Example rule condition:
   *  (:insured_amount < 5000 OR (:region = 'SOUTH' AND :last_claim_date < TO_DATE('1/01/2020', 'fmMM/DD/RRRR'))
   */ 
  function build 
  ( p_qb_rules_json               in clob,              -- QueryBuilder rules definition as json
    p_param_values_as_strings     in boolean := false,  -- eg dates will be string params, where the condition will contain TO_DATE()
    p_new_lines                   in boolean := false   -- use new lines 
  ) return t_condition_rec 
  is
    type t_field_seq is table of pls_integer index by varchar2(50);
    type t_condition_variants is table of t_condition index by pls_integer;
  
    -- Condition Types
    CT_DISPLAY                  pls_integer := 1;
    CT_FILTER                   pls_integer := 2;
    CT_RULE                     pls_integer := 3;  
    NUMBER_OF_CT                pls_integer := 3;
    
    l_condition_rec             t_condition_rec;                    -- return value
    l_sp                        char(1);                            -- parts separator: space or new line
    l_indent_level              pls_integer := 0;
    l_cond_type_idx             pls_integer;
    l_params                    t_param_list;
    l_param_names               apex_application_global.vc_arr2;    -- is initialized automatically
    l_param_string_values       apex_application_global.vc_arr2;    -- is initialized automatically
    l_param_idx                 pls_integer := 0;
    l_date_format               varchar2(50);                       -- will hold the global defined date format
    l_bind_seq                 t_field_seq := t_field_seq();
    l_error_message             varchar2(100);
         
    /*
     * Process all rules given a qb rules group and returns the
     * conditions as per all condition types (variants). When a subgroup is
     * encountered, the function will be called recursively.
     * While processing, also the param lists will be constructed.
     */
    function parse_rules(p_rules_obj json_object_t) return t_condition_variants
    is
        type t_output is table of t_condition index by pls_integer;
        type t_part is table of varchar2(4000) index by pls_integer;
        type t_parts is table of t_part index by pls_integer;
        type t_simple_op is table of varchar2(10) index by varchar2(20);
        type t_null_op is table of varchar2(20) index by varchar2(20);
        type t_binary_op is table of varchar2(20) index by varchar2(20);
        type t_in_op is table of varchar2(10) index by varchar2(10);
        type t_field is table of varchar2(100) index by pls_integer;
        type t_operand is table of varchar2(200) index by pls_integer;
        
        l_and_or_condition          varchar2(10);               -- as defined on the qb rules group level
        l_not                       boolean;
        l_rules_arr                 json_array_t;
        l_rule_obj                  json_object_t;
        l_id                        varchar2(100);
        l_field                     t_field;
        l_type                      varchar2(50);
        l_operator                  varchar2(50);
        l_output                    t_output;
        l_condition_variants        t_condition_variants;
        l_subcondition_variants     t_condition_variants;
        l_rules_arr_idx             pls_integer;    
        l_value_idx                 pls_integer;
        l_part                      t_part;                     -- each rule makes up a part of the condition
        l_parts                     t_parts;                    -- all parts making up the condition
        l_parts_idx                 pls_integer := 0;           -- start with 0
        l_simple_op                 t_simple_op := t_simple_op();
        l_null_op                   t_null_op := t_null_op();   
        l_binary_op                 t_binary_op := t_binary_op();     
        l_in_op                     t_in_op := t_in_op();
        l_operand                   t_operand;                  -- operand unary operator
        l_operand1                  t_operand;                  -- operand 1 binary operator
        l_operand2                  t_operand;                  -- operand 2 binary operator
        l_indent                    varchar2(100);
        
        /*
         * Function to arrive at the operands given the qb rule value(s).
         * It will return for all condition types.
         * For the named condition, also the param list will be build.
         * Eg, for a rule like: name equal 'Finance', the operand for the
         * named condition will be :name1 (or :name2, etc)
         * In case of multiple values (like in case of between or in operator),
         * the function to be called for each value by passing the value index.
         */
        function parse_operand(p_rule_obj json_object_t, p_value_idx pls_integer) return t_operand
        as
            l_field             varchar2(100);
            l_bind_var          varchar2(100);
            l_operator          varchar2(50);
            l_number_value      number;
            l_string_value      varchar2(4000);
            l_date_value        date;
            l_boolean_value     boolean;
            l_display_value     varchar2(4000);
            l_array             json_array_t;
            l_param_name        varchar2(100);
            l_param_value       anydata;
            l_type              varchar2(50);
            l_format_mask       varchar2(50);
            l_data_obj          json_object_t;
            l_operand           t_operand;
            
            function boolean_to_char(l_boolean in boolean) return varchar2 is
            begin
              return
                case boolean_as_integer
                  when true then
                    case l_boolean
                      when true then '1'
                      when false then '0'
                      else 'NULL'
                    end
                  when false then
                    case l_boolean
                      when true then 'TRUE'
                      when false then 'FALSE'
                      else 'NULL'
                    end
               end;
            end;
            
            function number_to_char(l_number in number, l_type in varchar2) return varchar2 is
            begin
                return 
                  case l_type 
                    when 'integer' then to_char(l_number, 'FM9999999999999999999999999999999999')
                    when 'double' then to_char(l_number, 'FM9999999999999999999999999999999990.0099999999', 'NLS_NUMERIC_CHARACTERS = ''.,''')
                  end;
            end;
            
        begin
            l_field := p_rule_obj.get_String('field');
            l_bind_var := REPLACE(l_field, '.', '_');
            l_operator := p_rule_obj.get_String('operator');
            l_type := p_rule_obj.get_String('type');
            if (l_type in ('date', 'datetime')) then
                -- assign the rules definition global date format and then check if there is
                -- a specific format in a potentially present data child object
                l_format_mask := l_date_format;
                if (p_rule_obj.has('data')) then
                    l_data_obj := p_rule_obj.get_object('data');
                    if l_data_obj.has('formatMask') then
                        l_format_mask := l_data_obj.get_string('formatMask');
                    end if;
                end if;
            end if;            
            
            -- keep registration of sequentially numbered bind variables
            if l_bind_seq.exists(l_bind_var) then
                l_bind_seq(l_bind_var) := l_bind_seq(l_bind_var) + 1;
            else
                l_bind_seq(l_bind_var) := 1;
            end if;  
            l_param_name := l_bind_var || '_' || l_bind_seq(l_bind_var);
            l_param_idx := l_param_idx + 1;
            l_params(l_param_idx).param_name := l_param_name;   -- for typed values
            l_param_names(l_param_idx) := l_param_name;         -- for string values
            
            -- collect value for the param lists
            if p_rule_obj.has('value') then
                if l_type in ('integer', 'double') then
                    if p_rule_obj.get('value').is_Array() then
                        l_array := p_rule_obj.get_Array('value');
                        l_number_value := l_array.get_Number(p_value_idx);
                    else
                        l_number_value := p_rule_obj.get_Number('value');
                    end if;
                    l_string_value := number_to_char(l_number_value, l_type);
                    l_param_value := anydata.ConvertNumber(l_number_value);
                elsif l_type = 'boolean' then
                    if p_rule_obj.get('value').is_Array() then
                        l_array := p_rule_obj.get_Array('value');
                        l_boolean_value := l_array.get_Boolean(p_value_idx);
                    else
                        l_boolean_value := p_rule_obj.get_Boolean('value');
                    end if;
                    l_string_value := boolean_to_char(l_boolean_value);
                    l_number_value := sys.diutil.bool_to_int(l_boolean_value);                    
                    if boolean_as_integer then
                        l_param_value := anydata.ConvertNumber(l_number_value);  
                    else
                        -- there is no ConvertBoolean
                        l_param_value := anydata.ConvertVarchar2(l_string_value);  
                    end if;
                elsif l_type = 'string' then
                    if p_rule_obj.get('value').is_Array() then
                        l_array := p_rule_obj.get_Array('value');
                        l_string_value := l_array.get_String(p_value_idx);                    
                    else
                        l_string_value := p_rule_obj.get_String('value');
                    end if;  
                    if (l_operator in ('contains', 'not_contains')) then
                        l_string_value := '%' || l_string_value || '%';
                    elsif (l_operator in ('begins_with', 'not_begins_with')) then
                        l_string_value := l_string_value || '%';
                    elsif (l_operator in ('ends_with', 'not_ends_with')) then
                        l_string_value := '%' || l_string_value;    
                    end if;                    
                    l_param_value := anydata.ConvertVarchar2(l_string_value);
                elsif l_type in ('date', 'datetime') then
                    if p_rule_obj.get('value').is_Array() then
                        l_array := p_rule_obj.get_Array('value');
                        l_string_value := l_array.get_String(p_value_idx);                    
                    else
                        l_string_value := p_rule_obj.get_String('value');
                    end if;
                    l_date_value := to_date(l_string_value, l_format_mask);
                    l_param_value := anydata.ConvertDate(l_date_value);
                end if;
                l_params(l_param_idx).param_value := l_param_value; 
                l_param_string_values(l_param_idx) := l_string_value;
            end if;  
            if p_rule_obj.has('displayValue') then
                if p_rule_obj.get('displayValue').is_Array() then
                    l_array := p_rule_obj.get_Array('displayValue');
                    l_display_value := l_array.get_String(p_value_idx); 
                else
                    l_display_value := p_rule_obj.get_String('displayValue');
                end if;
            end if;
            
            -- fill operand for all condition types
            if l_display_value is not null then
                l_operand(CT_DISPLAY) := '''' || l_display_value || '''';
            else
                l_operand(CT_DISPLAY) := l_string_value;    
                if l_type in ('string', 'date', 'datetime') then
                    l_operand(CT_DISPLAY) := '''' || l_operand(CT_DISPLAY) || '''';
                end if;                
            end if;
            l_operand(CT_FILTER) := ':' || l_param_name;
            l_operand(CT_RULE) := l_operand(CT_FILTER);   -- will be same
            -- in case of date/datetime type, add TO_DATE if needed
            if (l_type in ('date', 'datetime')) then
                --l_operand(CT_DISPLAY) := 'TO_DATE( ' || l_operand(CT_DISPLAY) || ', ''' || l_format_mask || ''' )';
                if p_param_values_as_strings then
                    l_operand(CT_FILTER) := 'TO_DATE( ' || l_operand(CT_FILTER) || ', ''' || l_format_mask || ''' )';
                    l_operand(CT_RULE) := 'TO_DATE( ' || l_operand(CT_RULE) || ', ''' || l_format_mask || ''' )';
                end if;
            end if;
            return l_operand;
        end parse_operand;
        
    begin
        -- set up arrays for all operators as per simple/null/binary/in categories
        l_simple_op('less') := '<';
        l_simple_op('less_or_equal') := '<=';
        l_simple_op('greater') := '>';
        l_simple_op('greater_or_equal') := '>=';        
        l_simple_op('equal') := '=';
        l_simple_op('not_equal') := '!=';
        l_simple_op('contains') := 'LIKE';
        l_simple_op('begins_with') := 'LIKE';
        l_simple_op('ends_with') := 'LIKE';
        l_simple_op('not_contains') := 'NOT LIKE';
        l_simple_op('not_begins_with') := 'NOT LIKE';
        l_simple_op('not_ends_with') := 'NOT LIKE';
        
        l_null_op('is_null') := 'IS NULL';
        l_null_op('is_not_null') := 'IS NOT NULL';
        l_null_op('is_empty') := 'IS NULL';     -- Oracle doesn't differentiate between empty strings and NULL
        l_null_op('is_not_empty') := 'IS NOT NULL';     
        
        l_binary_op('between') := 'BETWEEN';
        l_binary_op('not_between') := 'NOT BETWEEN';
        
        l_in_op('in') := 'IN';
        l_in_op('not_in') := 'NOT IN';        
        
        if (p_rules_obj.has('dateFormat')) then
            -- will serve as the global, default date format
            l_date_format := p_rules_obj.get_String('dateFormat');
        end if;
        l_and_or_condition := p_rules_obj.get_String('condition');
        l_not := p_rules_obj.get_Boolean('not');
        l_indent := '';
        if p_new_lines then
            l_indent := RPAD(CHR(9), l_indent_level, CHR(9));
        end if;        
        -- get and process all rules in the rule group
        l_rules_arr := p_rules_obj.get_Array('rules');
        for l_rules_arr_idx in 0 .. l_rules_arr.get_size - 1 loop
            l_rule_obj := TREAT (l_rules_arr.get(l_rules_arr_idx) AS json_object_t);
            -- check if the rule is a group
            -- for a subgroup, call parse_rules recursively
            if l_rule_obj.has('rules') then
                l_parts_idx := l_parts_idx + 1;
                if p_new_lines then
                    l_indent_level := l_indent_level + 1;
                end if;
                l_subcondition_variants := parse_rules(l_rule_obj);
                if p_new_lines then
                    l_indent_level := l_indent_level - 1;
                end if;                
                for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                    l_parts(l_cond_type_idx)(l_parts_idx) := '(' || l_sp || l_subcondition_variants(l_cond_type_idx) || l_sp || l_indent || ')';
                end loop;
            else
                -- process specific rule
                l_id := l_rule_obj.get_String('id');
                l_field(CT_DISPLAY) := l_rule_obj.get_String('label');
                if l_field(CT_DISPLAY) is null then
                    l_field(CT_DISPLAY) := l_rule_obj.get_String('field');
                end if;
                l_field(CT_FILTER) := l_rule_obj.get_String('field');
                l_field(CT_RULE) := l_rule_obj.get_String('field');
                l_operator := l_rule_obj.get_String('operator');
                l_type := l_rule_obj.get_String('type');
                if l_type = 'date' then
                    l_field(CT_FILTER) := 'TRUNC('||  l_field(CT_FILTER) || ')';
                end if;

                -- compose the condition part as per the rule definition: it's field, operator and value(s)
                if l_simple_op.exists(l_operator) then
                    l_operand := parse_operand(l_rule_obj, null);
                    for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                        l_part(l_cond_type_idx) := l_field(l_cond_type_idx) || ' ' || l_simple_op(l_operator) || ' ' || l_operand(l_cond_type_idx);
                    end loop;
                elsif l_null_op.exists(l_operator) then
                    for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                        l_part(l_cond_type_idx) := l_field(l_cond_type_idx) || ' ' || l_null_op(l_operator);
                    end loop;                    
                elsif l_binary_op.exists(l_operator) then
                    l_operand1 := parse_operand(l_rule_obj, 0);
                    l_operand2 := parse_operand(l_rule_obj, 1);
                    for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                        l_part(l_cond_type_idx) := l_field(l_cond_type_idx) || ' ' || l_binary_op(l_operator) || ' ' || l_operand1(l_cond_type_idx) || ' AND ' || l_operand2(l_cond_type_idx);
                    end loop;                       
                elsif l_in_op.exists(l_operator) then 
                    for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                        l_part(l_cond_type_idx) := l_field(l_cond_type_idx) || ' ' || l_in_op(l_operator) || ' ( ';
                    end loop;                      
                    if l_rule_obj.get('value').is_Array() then
                        for l_value_index in 0 .. l_rule_obj.get_Array('value').get_size - 1 LOOP
                            if (l_value_index > 0) then
                                for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                                    l_part(l_cond_type_idx) := l_part(l_cond_type_idx) || ', ';
                                end loop;  
                            end if;
                            l_operand := parse_operand(l_rule_obj, l_value_index);
                            for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                                l_part(l_cond_type_idx) := l_part(l_cond_type_idx) || l_operand(l_cond_type_idx);
                            end loop;                              
                        end loop;   
                    else
                        l_operand := parse_operand(l_rule_obj, null);
                        for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                            l_part(l_cond_type_idx) := l_part(l_cond_type_idx) || l_operand(l_cond_type_idx);
                        end loop;                            
                    end if;
                    for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                        l_part(l_cond_type_idx) := l_part(l_cond_type_idx) || ' )';
                    end loop; 
                end if;
                -- for rule conditions, prefix the field with ':' as that one will be for value substitution
                l_part(CT_RULE) := ':' || l_part(CT_RULE);
                l_parts_idx := l_parts_idx + 1;
                for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
                    l_parts(l_cond_type_idx)(l_parts_idx) := l_part(l_cond_type_idx);
                end loop;
            end if;
        end loop;
             
        -- concat the condition parts into the full condition strings
        for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
            l_parts_idx := l_parts(l_cond_type_idx).first; 
            l_output(l_cond_type_idx) := l_indent;
            if l_not then
                l_output(l_cond_type_idx) := l_output(l_cond_type_idx) || 'NOT ( ';
            end if;
            l_output(l_cond_type_idx) := l_output(l_cond_type_idx) || l_parts(l_cond_type_idx)(l_parts_idx);
            while l_parts_idx is not null loop 
              l_parts_idx := l_parts(l_cond_type_idx).next(l_parts_idx);
              if (l_parts_idx is not null) then
                l_output(l_cond_type_idx) := l_output(l_cond_type_idx) || ' ' || l_and_or_condition || l_sp || l_indent || l_parts(l_cond_type_idx)(l_parts_idx); 
              end if;
            end loop;
            if l_not then
                l_output(l_cond_type_idx) := l_output(l_cond_type_idx) || ' )';
            end if;
        end loop;       
        -- populate and return the condition variants as per the results
        for l_cond_type_idx in 1 .. NUMBER_OF_CT loop
            l_condition_variants(l_cond_type_idx) := l_output(l_cond_type_idx);
        end loop;
        return l_condition_variants;
    end parse_rules;

    function compose_display_params
    ( p_params_as_strings   t_param_list_strings
    ) return t_display_params is
        l_result    t_display_params;
        l_index     pls_integer;
    begin
        l_result := '';
        for l_index in 1 .. p_params_as_strings.param_names.count loop
            l_result := l_result || p_params_as_strings.param_names(l_index) || ': ' || p_params_as_strings.param_values(l_index) || chr(10);
        end loop;
        return l_result;
    end compose_display_params;
    
  begin
    declare
        l_rules_obj                 json_object_t;
        l_params_as_strings         t_param_list_strings; 
        l_condition_variants        t_condition_variants;     
        l_filter_condition          t_condition;    
        l_rule_condition            t_condition;
        l_invalid_rules             exception;
    begin
        if p_new_lines then
            l_sp := chr(10);
        else
            l_sp := ' ';
        end if;
        l_params := t_param_list();
        -- param_names and param_values are initialized automatically as per apex_application_global.vc_arr2
        if p_qb_rules_json is not null then
            l_rules_obj := json_object_t.parse(p_qb_rules_json);
            if not l_rules_obj.get_Boolean('valid') then
                raise l_invalid_rules; 
            end if;
            l_condition_variants := parse_rules(l_rules_obj);
            l_params_as_strings.param_names := l_param_names;
            l_params_as_strings.param_values := l_param_string_values; 
            l_condition_rec := t_condition_rec(l_condition_variants(CT_DISPLAY), l_condition_variants(CT_FILTER), 
                    l_condition_variants(CT_RULE), l_params, l_params_as_strings, compose_display_params(l_params_as_strings));
        end if;    
    exception
        when l_invalid_rules then
            l_error_message := 'One or more rules are invalid';      
        when others then
            l_error_message := 'Not able to build condition';
            apex_debug.error('Error raised: '|| DBMS_UTILITY.FORMAT_ERROR_BACKTRACE || ' - '||sqlerrm);            
            apex_debug.error('Error raised in: '|| $$plsql_unit ||' at line ' || $$plsql_line || ' - '||sqlerrm);            
    end; 
    if l_error_message is not null then
        apex_debug.error('Error "%s"'||chr(10)||'while building condition for ruleset: '||chr(10)||'%s', l_error_message, p_qb_rules_json);
        raise_application_error(error_number, l_error_message);
    end if;
    return l_condition_rec;  
  end build;
  
  /*
   * Can be used to evaluate rule conditions. 
   * For example, when you have a rule saying: 'When the order amount > $1000, discount will be 10%'.
   * So the rule condition is: (:order_amount > 1000)
   * where 'order_amount' will be param name, and 1000 the param value.
   * When the condition evaluates to true, 1 is returned; otherwise 0 is returned.
   */
  function evaluate
  ( p_condition in t_condition,         -- rule condition
    p_left_params in t_param_list,      -- list of left params (typed values)
    p_right_params in t_param_list      -- list of right params (typed values)  
  ) return number is                    -- return 1 or 0
      l_cursor              number;
      l_result              number;
      l_number              number;
      l_date                date;
      l_varchar2            varchar2(4000);
      l_params              t_param_list;
      l_params_idx          pls_integer;
      l_param_name          varchar2(128);
      l_param_value         anydata;
      l_error_message       varchar2(100);
      
      function merge_params(p_left_params in t_param_list, p_right_params in t_param_list) return t_param_list is
        l_index             PLS_INTEGER;
        l_new_index         PLS_INTEGER;
        l_merged_params     t_param_list;
      begin
        l_new_index := 1;  -- Start index for merged array
        for l_index in p_left_params.first ..  p_left_params.last loop
            l_merged_params(l_new_index) :=  p_left_params(l_index);
            l_new_index := l_new_index + 1;
        end loop;
    
        -- Merge p_right_params into l_merged_params
        for l_index IN p_right_params.first .. p_right_params.last loop
            l_merged_params(l_new_index) := p_right_params(l_index);
            l_new_index := l_new_index + 1;
        end loop;
        return l_merged_params;
      end;
  begin
    begin
        -- get existing cursor or set up a new one
        begin
          l_cursor := g_cached_cursors(p_condition);
        exception when no_data_found then
          l_cursor := dbms_sql.open_cursor;
          dbms_sql.parse(l_cursor, 'declare l_result number; begin :l_result:=case when ('||p_condition||') then 1 else 0 end; end;', dbms_sql.native);
          g_cached_cursors(p_condition) := l_cursor;
        end;
        -- bind the result variable
        dbms_sql.bind_variable(l_cursor, 'l_result', l_result);
        l_params := merge_params(p_left_params, p_right_params);
        -- bind the params
        for l_params_idx in 1 .. l_params.count loop
          l_param_name := l_params(l_params_idx).param_name;
          if (instr(upper(p_condition), ':'||upper(l_param_name)) > 0) then
            -- make use of bind_variable overloaded procedures for various types
            l_param_value := l_params(l_params_idx).param_value;
            case l_param_value.gettypeName
            when 'SYS.NUMBER' then
              if (l_param_value.getNumber(l_number) = dbms_types.success) then
                 dbms_sql.bind_variable(l_cursor, l_param_name, l_number);
              end if;
            when 'SYS.DATE' then
              if (l_param_value.getDate(l_date) = dbms_types.success) then
                 dbms_sql.bind_variable(l_cursor, l_param_name, l_date);
              end if;
            when 'SYS.VARCHAR2' then
              if (l_param_value.getVarchar2(l_varchar2) = dbms_types.success) THEN
                 dbms_sql.bind_variable(l_cursor, l_param_name, l_varchar2);
              end if;
            else
              null;
            end case;     
          end if;
        end loop;
        -- execute
        l_result:=dbms_sql.execute(l_cursor);
        -- get result
        dbms_sql.variable_value(l_cursor, 'l_result', l_result);
      exception
        when others then
           l_error_message := 'Not able to evaluate condition';
           apex_debug.error('Error raised: '|| DBMS_UTILITY.FORMAT_ERROR_BACKTRACE || ' - '||sqlerrm);            
           apex_debug.error('Error raised in: '|| $$plsql_unit ||' at line ' || $$plsql_line || ' - '||sqlerrm);           
      end;
      if l_error_message is not null then
          apex_debug.error('Error "%s"'||chr(10)||'while evaluating condition: '||chr(10)||'%s', l_error_message, p_condition);          
          raise_application_error(error_number, l_error_message);
      end if; 
      return l_result;
  end;  
  
  procedure test_build
  as
    l_qb_rules_json     clob;
    l_condition_rec     t_condition_rec;
    l_params_idx        pls_integer;
    
    function anydata_to_string(
      p_anydata in anydata
    ) return varchar2
    is
      l_typeid          pls_integer;
      l_anytype         anytype;
      l_result_code     pls_integer;
    begin
      l_typeid := p_anydata.GetType(typ => l_anytype);
      case l_typeid
      when dbms_types.typecode_number then
        declare
          l_value number;
        begin
          l_result_code := p_anydata.GetNumber(l_value);
          return to_char(l_value);
        end;
      when dbms_types.typecode_varchar2 then
        declare
          l_value varchar2(4000);
        begin
          l_result_code := p_anydata.GetVarchar2(l_value);
          return l_value;
        end;
      when dbms_types.typecode_date then
        declare
          l_value date;
        begin
          l_result_code := p_anydata.GetDate(l_value);
          return to_char(l_value, 'YYYY-MM-DD HH24:MI:SS');
        end;
      end case;
      return null;
    end anydata_to_string;

  begin
    l_qb_rules_json := '{
        "condition": "AND",
        "rules": [
            {
                "id": "price",
                "field": "price",
                "type": "double",
                "input": "number",
                "operator": "less",
                "value": 10.1
            },
            {
                "condition": "OR",
                "rules": [
                    {
                        "id": "category",
                        "field": "category",
                        "type": "integer",
                        "input": "select",
                        "operator": "equal",
                        "value": 2
                    },
                    {
                        "id": "category",
                        "field": "category",
                        "type": "integer",
                        "input": "select",
                        "operator": "equal",
                        "value": 1
                    },
                    {
                        "id": "customnumber",
                        "field": "customnumber",
                        "type": "double",
                        "operator": "equal",
                        "value": 123656.78,
                        "data": {
                            "formatMask": "999G999G999G999G990D00"
                        }
                    },
                    {
                        "id": "customnumber",
                        "field": "customnumber",
                        "type": "integer",
                        "operator": "not_in",
                        "value": [1,2,6,11],
                        "data": {
                            "formatMask": "999G999G999G999G990D00"
                        }
                    },
                    {
                        "condition": "OR",
                        "rules": [
                            {
                                "id": "customtext",
                                "field": "customtext",
                                "type": "string",
                                "operator": "contains",
                                "value": "Karel"
                            },
                            {
                                "id": "customtext",
                                "field": "customtext",
                                "type": "string",
                                "operator": "is_not_empty"
                            },
                            {
                                "id": "cb",
                                "field": "cb",
                                "type": "integer",
                                "input": "checkbox",
                                "operator": "equal",
                                "value": 5
                            },
                            {
                              "id": "customdate",
                              "field": "customdate",
                              "type": "date",
                              "operator": "between",
                              "value": [
                                "2/11/2025",
                                "2/12/2025"
                              ]
                            }                            
                        ],
                        "not": false
                    }
                ],
                "not": false
            }
        ],
        "dateFormat": "fmMM/DD/RRRR",
        "not": false,
        "valid": true
    }';
    l_condition_rec := build(l_qb_rules_json, false, true);
    dbms_output.put_line('Display Condition: ' || chr(10) || l_condition_rec.display_condition || chr(10));
    dbms_output.put_line('Filter Condition: ' || chr(10) || l_condition_rec.filter_condition || chr(10));
    dbms_output.put_line('Rule Condition: ' || chr(10) || l_condition_rec.rule_condition || chr(10));
    for l_params_idx in 1 .. l_condition_rec.params.count loop
        dbms_output.put_line('Param name: ' || l_condition_rec.params(l_params_idx).param_name);
        dbms_output.put_line('Param value: ' || anydata_to_string(l_condition_rec.params(l_params_idx).param_value));
        dbms_output.put_line('Param name (string): ' || l_condition_rec.params_as_strings.param_names(l_params_idx));
        dbms_output.put_line('Param value (string): ' || l_condition_rec.params_as_strings.param_values(l_params_idx));        
    end loop; 
    dbms_output.put_line('Display Params: ' || chr(10) || l_condition_rec.display_params);
  end test_build;  
  
  procedure test_evaluate
  as
    l_qb_rules_json     clob;
    l_condition_rec     t_condition_rec;
    l_params            t_param_list;
    l_eval_result       number;
  begin
    l_qb_rules_json := '{
        "condition": "AND",
        "rules": [
            {
                "id": "price",
                "field": "price",
                "type": "double",
                "input": "number",
                "operator": "less",
                "value": 14.1
            },
            {
              "id": "customdate",
              "field": "customdate",
              "type": "date",
              "operator": "between",
              "value": [
                "2/10/2025",
                "2/12/2025"
              ]
            }            
        ],
        "dateFormat": "fmMM/DD/RRRR",
        "not": false,
        "valid": true
    }';
    l_condition_rec := build(l_qb_rules_json, false, false); 
    dbms_output.put_line('Condition for evaluation: ' || l_condition_rec.rule_condition);  
    l_params(1).param_name := 'price';
    l_params(1).param_value := anydata.ConvertNumber(11.1);
    l_params(2).param_name := 'customdate';
    l_params(2).param_value := anydata.ConvertDate(TO_DATE('2/11/2025', 'fmMM/DD/RRRR'));    
    l_eval_result := evaluate(l_condition_rec.rule_condition, l_params, l_condition_rec.params);
    dbms_output.put_line('Evaluation result: ' || l_eval_result);  
  end test_evaluate; 
end LIB4X_CONDITION;
