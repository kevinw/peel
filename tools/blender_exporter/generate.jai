#import "Basic";
#import "Bindings_Generator";
#import "Compiler";

// Generates Jai bindings for the on-disk .peelscene file format shared with Blender's
// native exporter. This is the importer-side contract; export no longer goes through a Jai dylib.
#run {
    set_build_options_dc(.{do_output = false});
    if !generate_peel_scene_format_bindings() {
        compiler_set_workspace_status(.FAILED);
    }
}

generate_peel_scene_format_bindings :: () -> bool {
    using opts: Generate_Bindings_Options;

    generate_library_declarations = false;
    generate_compile_time_struct_checks = false;
    log_unsupported = true;

    set_working_directory("tools/blender_exporter");
    array_add(*source_files, "../blender/source/blender/io/peel/peel_scene_format.h");
    array_add(*extra_clang_arguments, "-x", "c++");

    return generate_bindings(opts, "peel_scene_format_bindings.jai");
}
