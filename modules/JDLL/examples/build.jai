#run,stallable {
    set_build_options_dc(.{do_output=false});

    // Build an example DLL/dylib.
    {
        plugins: [..]*Metaprogram_Plugin;

        jdll_plugin := JDLL.get_plugin();
        jdll_plugin.options.verbose = true;
        array_add(*plugins, jdll_plugin);

        workspace := compiler_create_workspace();
        options := get_build_options(workspace);
        copy_commonly_propagated_fields(get_build_options(), *options);
        options.output_executable_name = "example_jai_dynamic_library";
        options.output_type            = .DYNAMIC_LIBRARY;
        set_build_options(options, workspace);

        intercept_flags: Intercept_Flags = 0;
        for plugins it.workspace = workspace;
        for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);
        compiler_begin_intercept(workspace, intercept_flags);
        defer {
            compiler_end_intercept(workspace);
            for plugins if it.finish   it.finish  (it);
            for plugins if it.shutdown it.shutdown(it);
        }

        add_build_file("example_jai_dynamic_library.jai", workspace);
        for plugins      if it.add_source it.add_source(it);

        while true {
            message := compiler_wait_for_message();
            for plugins if it.message it.message(it, message);
            if message.kind == {
                case .COMPLETE; {
                    message_complete := cast(*Message_Complete) message;
                    ifx message_complete.error_code != .NONE {
                        log_error("Build failed.");
                        exit(1);
                    }
                    break;
                }
            }
        }
    }
}


#import "Compiler";
#import "Basic";
JDLL :: #import,file "../module.jai";  // #import "JDLL" in your code
