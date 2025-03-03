procedure render (
    p_plugin in            apex_plugin.t_plugin,
    p_region in            apex_plugin.t_region,
    p_param  in            apex_plugin.t_region_render_param,
    p_result in out nocopy apex_plugin.t_region_render_result )
is 
    l_region_id             varchar2(50); 
    l_lang                  varchar2(5); 
    l_loc_transl_files      varchar2(200);
begin
    if apex_application.g_debug then
        apex_plugin_util.debug_region(p_plugin => p_plugin, p_region => p_region);
    end if;
    l_region_id := apex_escape.html_attribute(p_region.static_id);
    -- get location of any translation files
    l_loc_transl_files := nvl(p_region.attributes.get_varchar2('attr_qb_loc_transl_files'), '#WORKSPACE_FILES#i18n/query-builder');
    if substr(l_loc_transl_files, -1) != '/' then
        l_loc_transl_files := l_loc_transl_files || '/';
    end if;
 
    sys.htp.p('<div id="' || l_region_id || '_qb"></div>');

    -- for language unequal to 'en', include the corresponding
    -- qb translation file in the page
    l_lang := nvl(apex_application.g_browser_language, 'en');
    if (l_lang != 'en') then
        if ((instr(l_lang, '-') > 0) and (length(l_lang) = 5)) then
            l_lang := substr(l_lang, 1, length(l_lang) - 2) || upper(substr(l_lang, -2));
        end if;

        -- QB language files can be taken from https://github.com/mistic100/jQuery-QueryBuilder/tree/master/dist/i18n
        -- and placed in workspace files or any location as configured by l_loc_transl_files
        apex_javascript.add_library(
              p_name      => 'query-builder.' || l_lang,
              p_check_to_add_minified => false,     -- to be sure, as no minified version might be present and it also doesn't matter much
              p_directory => l_loc_transl_files,
              p_version   => NULL
        );
    end if;
 
    -- When specifying the library declaratively, it fails to load the minified version. So using the API:
    apex_javascript.add_library(
          p_name      => 'lib4x-conditionbuilder',
          p_check_to_add_minified => true,
          --p_directory => '#WORKSPACE_FILES#javascript/',          
          p_directory => p_plugin.file_prefix || 'js/',
          p_version   => NULL
    );  

    -- this one is not having the check minified parameter
    apex_css.add_file (
        p_name => 'lib4x-conditionbuilder'||case when v('DEBUG') = 'NO' then '.min' end,
        --p_directory => '#WORKSPACE_FILES#css/'
        p_directory => p_plugin.file_prefix || 'css/' 
    );    

    -- add call to init in js
    apex_javascript.add_inline_code(
        p_code => apex_string.format(
            'lib4x.axt.conditionBuilder._init("%s", '
            , l_region_id
        ) || p_region.init_javascript_code || ');'
    );    
end;
