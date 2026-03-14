// Download, build and generate bindings for imgui_test_engine

GITHUB_REPO       :: "ocornut/imgui_test_engine";
GITHUB_BRANCH     :: "main";
PATH_TO_IMGUI_SRC :: "../ImGui/src/imgui";

#run {
    set_build_options_dc(.{do_output = false});

    project: Project_Options;
    #if OS == .MACOS {
        array_add(*project.platform_artifacts, "libimgui_test_engine.dylib");
    } else {
        #assert false "TODO: discover build DLL for this platform";
    }

    init_from_github_clone(*project, repo=GITHUB_REPO, branch=GITHUB_BRANCH);
    project.bindings_options_callback = (using opts: *Generate_Bindings_Options, paths: Build_Project_Paths) {
        array_add(*source_files,
            "imgui_test_engine/imgui_te_engine.h",
            "imgui_test_engine/imgui_te_ui.h",
            "imgui_test_engine/imgui_te_utils.h",
            "imgui_test_engine/imgui_te_exporters.h",
        );
        array_add(*include_paths,
            tprint("%", paths.src),
            resolved_imgui_src_dir,
        );
    };
    ok, result := build_and_generate_bindings(project, .{
        build_cpp = {
            files = .[join(#filepath, "imgui_test_engine.cpp")],
            extra = .[
                join("-I", resolved_imgui_src_dir), // include dir for imgui
                join("-I", BUILD_CPP_SRC_DIR_SENTINEL),
            ],
        },
        verbose = true,
    });
    if !ok fail_and_exit("Failed to build and generate bindings");
    log("OK. Generated bindings in %", result.generated_bindings_filename);
}

resolved_imgui_src_dir :: #run -> string {
    path := path_join(#filepath, PATH_TO_IMGUI_SRC);
    imgui_header_path := path_join(path, "imgui.h");
    if !file_exists(imgui_header_path) {
        fail_and_exit("Could not find imgui.h at %", imgui_header_path);
    }
    return path;
}

#import,file "../CMake_Module/module.jai";
#import "Bindings_Generator";
#load "../Bindings_Common.jai";
#import "Compiler";
#import "Basic";
String :: #import "String";
