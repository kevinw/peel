//
// step 1: build "mylib" dll/dylib from dll.jai
// step 2: build "program" exe from program.jai
//

#run {
    set_build_options_dc(.{do_output=false});

    // build the DLL
    {
        log("building dll");
        w := compiler_create_workspace();
        defer compiler_destroy_workspace(w);

        options := get_build_options(w);
        copy_commonly_propagated_fields(get_build_options(), *options);
        options.output_executable_name = "mylib";
        options.output_type            = .DYNAMIC_LIBRARY;
        set_build_options(options, w);

        compiler_begin_intercept(w);
        defer compiler_end_intercept(w);
        add_build_file("dll.jai", w);
        if !message_loop("dll") exit(1);
    }

    // build the main program
    {
        log("building program");
        w := compiler_create_workspace();
        defer compiler_destroy_workspace(w);

        options := get_build_options(w);
        copy_commonly_propagated_fields(get_build_options(), *options);
        options.output_executable_name = "program";
        options.output_type            = .EXECUTABLE;
        set_build_options(options, w);

        compiler_begin_intercept(w);
        defer compiler_end_intercept(w);
        add_build_file("program.jai", w);
        if !message_loop("program") exit(1);
    }
}

message_loop :: (name: string) -> bool {
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE {
            mc := cast(*Message_Complete) message;
            if mc.error_code != .NONE {
                log_error("% compilation failed", name);
                return false;
            }
            break;
        }
    }
    return true;
}

#import "Basic";
#import "Compiler";
