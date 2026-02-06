// TODO: use "get_dynamic_library_paths" from build.jai and pick either "windows" or "win" and stick with it.
_DLL_PATHS := string.[
    "Game_Sound/lib/win",
    /*
    "SDL3/lib/windows",
    "ImGui/windows",
    "assimp/lib/win",
    "ImGuizmo/lib/windows",
    "JoltC/lib/win",
    "im3d/lib/win",
    "SDL_gpu_ext/lib/win",
    */
];
do_path_setup_for_dlls :: (modules_dir: string, make_paths_absolute: bool = false) -> bool {
    final_paths: [..]string;
    final_paths.allocator = temp;
    for _DLL_PATHS {
        actual_path := String.path_join(modules_dir, it,, temp);
        if !file_exists(actual_path) {
            log_error("ERROR: expected DLL directory to exist: '%'", actual_path);
            return false;
        }

        array_add(*final_paths, actual_path);
    }

    return add_to_current_process_path(final_paths, replace_forward_slashes_with_backslashes=true, make_paths_absolute=make_paths_absolute);
}

#scope_file
#import "Basic";
String :: #import "String";
using,only(file_exists) File_Utilities :: #import "File_Utilities";
#import "Windows_Utils";
