create or replace package LIB4X_CONDITION as 

    boolean_as_integer      boolean := true;        -- for Oracle 23c, this can be either true or false
    error_number            number  := -20000;      -- for raising application exceptions
    
    -- for building a param list holding typed values
    type t_param_rec is record 
    ( param_name  varchar2(128),
      param_value anydata
    );
    type t_param_list is table of t_param_rec index by pls_integer;
    
    -- for building a param list holding string values
    type t_param_list_strings is record
    ( param_names   apex_application_global.vc_arr2,
      param_values  apex_application_global.vc_arr2
    );
    
    subtype t_display_params is varchar2(4000);
    
    -- type for any type of condition string
    subtype t_condition is varchar2(32767);
    -- end result when building a condition
    type t_condition_rec is record
    (
      display_condition         t_condition,            -- can be used for display purposes
      filter_condition          t_condition,
      rule_condition            t_condition,
      params                    t_param_list,           -- can be used for dbms_sql query, has typed values
      params_as_strings         t_param_list_strings,   -- can be used for apex collection query, has string values
      display_params            t_display_params
    );
    
   /*
    * Given a QueryBuilder(qb) rules definition, the function builds both a 
    * filter- and a rule condition. Typically, a filter condition can be used
    * in a query where clause. A rule condition can be evaluated for example
    * using claim data. 
    * Example (named) filter condition:
    *  (customer_id = :customer_id1 AND order_date between :order_date1 AND :order_date2)
    * Example rule condition:
    *  (:insured_amount < :insured_amount_1 OR (:region = :region_1 AND :last_claim_date < TO_DATE(:last_claim_date_1, 'fmMM/DD/RRRR'))
    */     
    function build 
    ( p_qb_rules_json               in clob,              -- query builder rules definition, json format
      p_param_values_as_strings     in boolean := false,  -- eg dates will be string params, where the condition will contain TO_DATE()
      p_new_lines                   in boolean := false   -- use new lines       
    ) return t_condition_rec;
    
    /*
     * Can be used to evaluate rule conditions. 
     * For example, when you have a rule saying: 'When the order amount > $1000, discount will be 10%'.
     * So the rule condition is: (:order_amount > :order_amount_1)
     * where 'order_amount' will be param name with value from the order, and 
     * order_amount_1 will be param name with value 1000.
     * The param values should be typed values.
     * When the condition evaluates to true, 1 is returned; otherwise 0 is returned.
     */    
    function evaluate
    ( p_condition in t_condition,         -- rule condition
      p_left_params in t_param_list,      -- list of left params (typed values)
      p_right_params in t_param_list      -- list of right params (typed values)      
    ) return number;

    procedure test_build;
    procedure test_evaluate;
  
end LIB4X_CONDITION;
