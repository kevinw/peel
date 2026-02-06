#import "Compiler";

/*
#run {
    set_build_options_dc(.{ do_output = false });
    set_working_directory(path_join(#filepath, ".."));
    build_metal();
}
*/

#if OS == .MACOS {

build_metal :: (input_files: []string, output_library_path: string,
    debug_symbols := true, enable_logging := false, verbose := true)
-> bool {
    start := seconds_since_init();

    args: [..]string;
    args.allocator = temp;
    array_add(*args, "xcrun", "-sdk", "macosx", "metal", "-o", output_library_path);
    if debug_symbols {
        array_add(*args, "-frecord-sources=flat");
        array_add(*args, "-frecord-sources");
        array_add(*args, "-gline-tables-only");
    }
    if enable_logging {
        array_add(*args, "-fmetal-enable-logging"); // watch out! causes a perf hit
    }
    if verbose {
        array_add(*args, "-v");
    }
    for input_files {
        array_add(*args, it);
    }

    process_result, output_string, error_string, timeout_reached := run_command(..args, capture_and_return_output = true);
    if process_result.type != .EXITED || process_result.exit_code != 0 || timeout_reached {
        log_error("Could not compile metal shaders.\n%", error_string);
        return false;
    }

    // log("%", output_string);
    // log("%", error_string);

    duration := seconds_since_init() - start;
    log("Metal shaders compiled into % (%s).", output_library_path, duration);

    // reflect_library(path_to_library);

    return true;
}

}

#scope_file
#import "Process";
#import "Basic";
#import "String";
#import "File_Utilities";
#import "File";
#if OS == .MACOS {
    //#import "Metal_Reflection";
}
