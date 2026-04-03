#run {
    set_build_options_dc(.{do_output = false});
    if !generate_peel_bridge_bindings() {
        compiler_set_workspace_status(.FAILED);
    }
}

generate_peel_bridge_bindings :: () -> bool {
    using opts: Generate_Bindings_Options;

    generate_library_declarations = false;
    generate_compile_time_struct_checks = false;
    log_unsupported = true;

    array_add(*source_files, "/Users/kev/src/blender/source/blender/io/peel/peel_bridge.h");
    array_add(*extra_clang_arguments, "-x", "c++");

    return generate_bindings(opts, "peel_bridge_bindings.jai");
}

#scope_file

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
