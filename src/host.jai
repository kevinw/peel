/*

Main entry point.

When SINGLE_BINARY is true, we don't have an "app" DLL and just call an update function.

Otherwise, we know how to load a DLL and call out to it in a loop, and know how to copy globals from one DLL to another.

During development, we can get a live reload of our code by putting almost everything in a DLL, and having a thin host program reload a new DLL when we
build it. This is that thin host program.

Note: this host doesn't even open a window, or initialize a graphics API.

*/

#load "app_list.jai";
#if OS == .MACOS && !SINGLE_BINARY {
    #load "Peel_MacOS_Runtime.jai";
}

main :: () {
    start := seconds_since_init();

    VERBOSE :: true;

    #if !RELEASE {
        Debug.init();
        Debug.set_report_mode(interactive = false);

        setup_env_vars();
    }

    // Install our custom logger
    new_ctx := context;
    new_ctx.logger = our_logger;
    push_context,defer_pop new_ctx;

    defer {
        #if MEMORY_DEBUGGER {
            log("---- host leak report ----");
            report_memory_leaks();
        }
    }

    path := String.path_strip_filename(System.get_path_of_running_executable());
    set_working_directory(path);

    args := get_command_line_arguments();
    defer { array_free(args); }


    #if OS == .WINDOWS {
        if !array_find(args, "--skip-path-setup") {
            if !do_path_setup_for_dlls("../modules") {
                return;
            }
        }
    }

    USAGE_MESSAGE :: #run sprint("usage: % --app app_name", HOST_OUTPUT_EXECUTABLE_NAME);

    library_filename := "";
    defer if library_filename.count > 0 free(library_filename);
    max_frames: int = 0;

    // parse args
    {
        next_is_app_dll := false;
        next_is_max_frames := false;
        for args {
            if next_is_app_dll {
                library_filename = copy_string(it);
                next_is_app_dll = false;
            } else if next_is_max_frames {
                max_frames = String.string_to_int(it);
                next_is_max_frames = false;
            } else if it == {
                case "--app";
                    #if SINGLE_BINARY {
                        log_error("Cannot use --app with host/app built as a single binary");
                        exit(1);
                    }
                    if next_is_app_dll {
                        log_error(USAGE_MESSAGE);
                        exit(1);
                    }
                    next_is_app_dll = true;
                case "--max-frames";
                    next_is_max_frames = true;
            }
        }
    }


    env_max_frames, did_parse := try_parse_env_int("PEEL_MAX_FRAMES");
    if did_parse {
        if max_frames == 0
            max_frames = env_max_frames;
        else
            max_frames = min(env_max_frames, max_frames);
    } else {
    }


    #if !SINGLE_BINARY {
        // Decide which app DLL to load.
        if !library_filename {
            first_app_jai := active_app_filename();
            log("Warning: because no --app was specified, using the first app in APP_LIST: %", first_app_jai);
            library_filename = sprint("%.%", app_dll_basename_for_source_file(first_app_jai), DLL_EXTENSION);
        }

        if !library_filename {
            log_error(USAGE_MESSAGE);
            exit(1);
        }

        app := app_library_load(library_filename, VERBOSE);
        if !app.is_valid {
            log_error("App not loaded correctly, abort!");
            exit(1);
        }

    } else {
        // Otherwise, we're just building as a single binary. The "App" struct can just be a function pointer to our update function.
        the_app_update_function :: on_host_message;

        Single_Binary_App :: struct {
            on_host_message :: the_app_update_function;
        }

        app := Single_Binary_App.{};
    }

    init_ctx: Init_Ctx;
    init_ctx.max_frames = max_frames;
    #if !SINGLE_BINARY {
    host_max_frames = max_frames;
    }
    #if OS == .MACOS && !SINGLE_BINARY {
        host_runtime = host_macos_runtime_init(2500, 2000, "");
        init_ctx.runtime = host_runtime;
    }

    init_res := app.on_host_message({type = .Init, init_ctx = init_ctx});
    if !init_res.success {
        log_error("App not initialized correctly, abort!");
        exit(1);
    }

    defer {
        #if !RELEASE || MEMORY_DEBUGGER { // can skip teardown in release builds...the OS will do this for us :)
            #if !SINGLE_BINARY {
                host_app_build_shutdown();
            }
            app.on_host_message(.{type = .Quit});
            app.on_host_message(.{type = .Unload});
            reset_temporary_storage();
            #if !SINGLE_BINARY {
                app_library_unload(*app, verbose=VERBOSE);
            }
        }
    }

    //
    // The main host loop
    //
    while true {
        ctx: App_Update_Ctx;
        #if !SINGLE_BINARY {
            host_app_build_apply_status_to_update_ctx(*ctx);
        }
        app.on_host_message(.{type = .Update, update_ctx = *ctx});

        if ctx.app_return_flags & .Quit {
            break;
        }

        else if !did_render_first_frame {
            did_render_first_frame = true;
            now := seconds_since_init();
            duration := now - start;
            log("First frame rendered in % seconds", duration);
        }

        #if !SINGLE_BINARY {
            handle_app_live_reload(*app, *ctx, *library_filename, verbose=VERBOSE);
        }
    }

    if library_filename {
        free(library_filename);
        library_filename = "";
    }
}

#scope_file

setup_env_vars :: () {
    #if RELEASE return;

    #if OS == .MACOS {
        if !perf_gpu_validation_enabled() return;

        using,only(setenv) POSIX :: #import "POSIX";
        setenv("MTL_SHADER_VALIDATION", "1", 1);
        setenv("MTL_SHADER_VALIDATION_REPORT_TO_STDERR", "1", 1);
        setenv("MTL_LOG_TO_STDERR", "1", 1);
        setenv("MTL_DEBUG_LAYER", "1", 1);
        setenv("MTL_LOG_LEVEL", "MTLLogLevelDebug", 1);
        setenv("MTL_LOG_BUFFER_SIZE", "2048", 1);
    }
}

#if OS == .MACOS {
    perf_gpu_validation_enabled :: () -> bool {
        using,only(getenv) POSIX :: #import "POSIX";
        v := getenv("PEEL_GPU_VALIDATION");
        if v == null return true;
        if v[0] == #char "0" return false;
        return true;
    }
} else {
    perf_gpu_validation_enabled :: () -> bool {
        return false;
    }
}


our_logger :: (message: string, data: *void, info: Log_Info) {
    if !message then return;

    to_standard_error := (info.common_flags & .ERROR) != 0;

    before_color := "";
    after_color := "";
    if to_standard_error {
        before_color = "\e[1;31m";
        after_color = "\e[0m";
    }

    if message[message.count-1] != #char "\n" {
        write_strings(before_color, message, after_color, "\n", to_standard_error = to_standard_error);
    } else {
        write_strings(before_color, message, after_color, to_standard_error = to_standard_error);
    }
}

#if !SINGLE_BINARY {
host_runtime: Host_Runtime_Ptrs;
host_max_frames: int;


recompile_ourselves :: () {
    #if OS == .MACOS JAI_EXECUTABLE :: "jai-macos";
    else             JAI_EXECUTABLE :: "jai";
    res := Process.run_command(JAI_EXECUTABLE, "build.jai", "-", "-onlyapp", working_directory="..");
    if res.exit_code == 0
        log("Recompiled ourselves successfully.\n", flags=.VERBOSE_ONLY);
}

looks_like_app_dll :: (it: string) -> bool {
    return (String.starts_with(it, "./app_") || String.starts_with(it, ".\\app_")) && String.ends_with(it, tprint(".%", DLL_EXTENSION));
}

find_newest_app_dll :: () -> string {
    newest_modtime := APOLLO_TIME_FOR_JAN_1_1970;
    newest_filename := "";
    for File_Utilities.file_list(".", recursive=false, follow_directory_symlinks=false,, allocator=temp) {
        if looks_like_app_dll(it) {
            modtime, size := File_Utilities.file_modtime_and_size(it);
            if modtime > newest_modtime {
                newest_modtime = modtime;
                newest_filename = copy_string(it);
            }
        }
    }

    return newest_filename;
}

handle_app_live_reload :: (app: *App, ctx: *App_Update_Ctx, library_filename: *string, verbose := false) {
    host_app_build_handle_completion(ctx, library_filename);

    if ctx.app_return_flags & .Recompile
        recompile_ourselves();
    if ctx.app_return_flags & .Build_And_Load_App {
        host_app_build_queue(ctx.app_return_data.build_app);
        ctx.app_return_data.build_app = "";
    }
    if ctx.app_return_flags & .Load_App {
        if library_filename.*.count != 0 free(library_filename.*);
        library_filename.* = sprint("%.%", ctx.app_return_data.load_app, DLL_EXTENSION);
    }

    // Free ctx.app_return_data.load_app later.
    load_app_str :=  ifx ctx.app_return_flags & .Load_App ctx.app_return_data.load_app;
    defer if load_app_str free(load_app_str);

    if app_library_changed(app) || ctx.app_return_flags & .Reload || ctx.app_return_flags & .Load_App {
        new_app := app_library_load(library_filename.*, verbose);
        next_init_ctx: Init_Ctx;
        next_init_ctx.max_frames = host_max_frames;
        if ctx.app_return_flags & .Load_App && app.is_valid {
            next_init_ctx.keep_window_device_and_sdl = true;
            #if OS == .MACOS {
                next_init_ctx.runtime = host_runtime;
            } else {
                next_init_ctx.runtime = gather_runtime_ptrs_for_app(app);
            }
        }
        if app.is_valid {
            if !(ctx.app_return_flags & .Load_App) {
                // When we're just reloading, copy over the globals.
                app_library_copy(app, *new_app);
                reload_pointer_check_after_copy(app, *new_app);
            } else {
                app.on_host_message(.{type = .Quit});
            }
            app.on_host_message(.{type = .Unload});
            app_library_unload(app, verbose);
        }
        if new_app.is_valid {
            app.* = new_app;
            if ctx.app_return_flags & .Load_App && ctx.app_return_data.load_app {
                app.on_host_message(.{type = .Init, init_ctx = next_init_ctx});
                ctx.app_return_data.load_app = "";
            } else {
                app.on_host_message(.{type = .Reload});
            }
        }
    }
}

gather_runtime_ptrs_for_app :: (app: *App) -> Host_Runtime_Ptrs {
    runtime: Host_Runtime_Ptrs;
    ok: bool;

    runtime.window, ok = app_library_get_global_pointer(app, "window");
    if !ok {
        log_error("Host: failed to find runtime global 'window' when switching apps.");
    }

    #if OS == .MACOS {
        runtime.gfx_device, ok = app_library_get_global_pointer(app, "mtl_device");
        if !ok {
            log_error("Host: failed to find runtime global 'mtl_device' when switching apps.");
        }
    }

    return runtime;
}


#import "app_loader";
#load "host_build.jai";
#load "reload_pointer_check.jai";
Process :: #import "Process";

} // !SINGLE_BINARY

#load "./Program_Parameters_Common.jai";

String :: #import "String";
System :: #import "System";
File :: #import "File";
File_Utilities :: #import "File_Utilities";
#import "Basic";
#import "Host_App_Common";
#if OS == {
case .WINDOWS; #load "./Windows_DLL_Paths.jai";
case .MACOS;   #import "Objective_C";
}
Debug :: #import "Debug"(USE_GRAPHICS=false);
did_render_first_frame := false;
#import "Env_Vars";
