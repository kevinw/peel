#run {
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace();
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "peel_blender_exporter";
    options.output_type = .DYNAMIC_LIBRARY;
    options.output_path = tprint("%/.build", #filepath);
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("peel_blender_exporter.jai", w);

    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE {
            mc := cast(*Message_Complete) message;
            if mc.error_code != .NONE exit(1);
            break;
        }
    }

    compiler_end_intercept(w);
}

#import "Compiler";
#import "Basic";
