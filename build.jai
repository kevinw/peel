// Builds and optionally runs a peel "app".

Build_Script_Opts :: struct {
    run                     : bool;   @"?Run after building"
    run_args                : string; @"?Args to pass to app run after building (in quotes)"
    dll                     : bool;   @"?Build app code as a split binary live reload DLL"
    shader_only             : bool;   @"?Typecheck + transpile shaders only (no binary output)"
    shader_entry_ids        : string; @"?Comma-separated manifest entry ids to transpile (use with -shader_only)"
    release                 : bool;   @"?Build in release mode with optimizations"
    codex                   : bool;   @"?Add the Codex metaprogram plugin"
    iprof                   : bool;   @"?Add the IProf metaprogram plugin"
    verbose                 : bool;   @"?Print verbose output for the build process"
    perf                    : bool;   @"?Show a compiler performance report"
    timings                 : bool;   @"?Show extra timings"
    tracy                   : bool;   @"?Compile with Tracy profiling"

    // used internally (todo: move elsewhere)
    sub_build               : bool;
    output_exe              : string;
}

USE_PARALLEL_BUILD_WHEN_BUILDING_ALL :: true;
THIS_SCRIPT_PATH            :: #run String.path_join(#filepath, "build.jai");
HOST_JAI_ROOT               :: "src/host.jai";
APPS_DIR                    :: "src/apps";
OUTPUT_PATH                 :: "dist";        // The directory where the program binary goes.
LIVE_RELOAD_HOST_EXE_NAME   :: "peel";        // The name of the live reload host executable.
BUILD_IS_FOR_IDE            :: #exists(JAILS_DIAGNOSTICS_BUILD); // Whether the build is for the IDE's error display. (Jails language server runs the build to check for errors.)

#load "src/app_list.jai";

#if OS == .MACOS {
    MACOS_MAJOR_VERSION_FOR_RELEASE_BUILD :: 15;
    MACOS_MAJOR_VERSION_FOR_DEBUG_BUILD :: 36;
    entitlements_file :: #run String.path_join(OUTPUT_PATH, "debug-entitlements.plist");
}
PLATFORM_DIR :: #run get_platform_dir(OS); // win, macos, linux

#run,stallable {
    start_time := current_time_monotonic();
    set_build_options_dc(.{ do_output = false });
    set_working_directory(#filepath);

    cmd_line_args := get_build_options().compile_time_command_line;

    // Command line arguments to this build script.
    success, script_opts, is_set, free_args := Command_Line.parse_arguments(Build_Script_Opts,
        flags=.SHOW_HELP_ON_ERROR | .ALIGN_HELP | .FREE_ARGUMENTS_ALLOWED,
        args=cmd_line_args);
    if !success {
        exit_with_error("Failed to parse command line arguments");
    }

    script_opts.run = is_set.run;

    apps_to_build: [..]string;
    {
        array_add(*apps_to_build, ..free_args);
        if apps_to_build.count == 0 {
            log("Building all apps in src/app_list.jai's APP_FILES: (%)", String.join(..APP_FILES, separator=", "));
            if !BUILD_IS_FOR_IDE && USE_PARALLEL_BUILD_WHEN_BUILDING_ALL && !script_opts.sub_build {
                parallel_build_all_and_exit(cmd_line_args, script_opts);
            }
            for APP_FILES {
                array_add(*apps_to_build, tprint("%/%", APPS_DIR, it));
            }
        }
        for apps_to_build {
            if !file_exists(it) {
                exit_with_error(tprint("Error: Specified app file \"%\" does not exist", it));
            }
        }
    }
    if is_set.dll && apps_to_build.count > 1 {
        exit_with_error("Error: Cannot build multiple apps as a DLL");
    }
    if is_set.shader_entry_ids && !is_set.shader_only {
        exit_with_error("Error: -shader_entry_ids requires -shader_only.");
    }
    if script_opts.tracy {
        if is_set.dll exit_with_error("Error: Cannot currently use Tracy plugin when building a live-reload DLL.");
    }

    if script_opts.release || environment_specifies_release_build() set_release_build(*script_opts);

    make_directory_if_it_does_not_exist(OUTPUT_PATH, recursive = true); // Create the output dir.

    #if OS == .WINDOWS {
        if !do_path_setup_for_dlls("modules", make_paths_absolute = true) {
            exit_with_error("Failed to setup PATH for DLLs");
            return;
        }
        module_paths_already_set_in_environment = true;
    }

    if script_opts.shader_only {
        for apps_to_build {
            if !build_shader_only(script_opts, it) {
                exit_with_error("Failed to shader-only build app '%'.", it);
            }
        }
        return;
    }

    // All builds will depend on the contents of this build.jai file, as well as all their source files.
    #if !BUILD_IS_FOR_IDE {
        Build_Manifest.mark_meta_dependency(THIS_SCRIPT_PATH);
    }

    dll_host_was_running := !BUILD_IS_FOR_IDE && script_opts.dll && check_if_host_is_running(script_opts, LIVE_RELOAD_HOST_EXE_NAME);

    for app_to_build: apps_to_build {
        host_build_strings: [..]string;

        if !script_opts.dll  {
            array_add(*host_build_strings, tprint("#load \"%\";\n", app_to_build));
            array_add(*host_build_strings, tprint("TRACY_PROFILER_ENABLED :: %;", script_opts.tracy));
            script_opts.output_exe = String.path_strip_extension(String.path_filename(app_to_build));
        } else {
            script_opts.output_exe = LIVE_RELOAD_HOST_EXE_NAME;
        }
        defer script_opts.output_exe = "";

        if !build_host(script_opts, include_app_plugins=!script_opts.dll, app_filename=app_to_build, build_strings=host_build_strings) {
            exit_with_error();
        }

        if script_opts.dll break; // We only need one host when we're building dll.
    }

    // Build the DLL(s).
    if script_opts.dll {
        if !build_jdll("Game_Sound", "src/dlls/Game_Sound.jai", script_opts) {
            exit_with_error("Failed to build the DLL for '%'", "Game_Sound");
        }
        for apps_to_build {
            if !build_app(script_opts, app_filename=it) {
                exit_with_error("Failed to build the app for '%'", it);
            }
        }
    }

    if !script_opts.sub_build {
        log("Built in % seconds.", to_float64_seconds(current_time_monotonic() - start_time));
    }

    // Start the host if it's not already running.
    #if !BUILD_IS_FOR_IDE {
        if !script_opts.run {
            if script_opts.verbose log("Not running the app, because script_opts.run was false.");
        } else if dll_host_was_running {
            log("Not running the app, because the host is already running.");
        } else {
            if script_opts.verbose log("Running the app...");
            abs_output_path := get_absolute_path(OUTPUT_PATH);
            if !abs_output_path exit_with_error("Failed to get absolute path of output path: '%'", OUTPUT_PATH);
            set_working_directory(abs_output_path);

            output_exe: string;
            if script_opts.dll output_exe = LIVE_RELOAD_HOST_EXE_NAME;
            else output_exe = String.path_strip_extension(String.path_filename(apps_to_build[0]));

            path_to_host_exe := tprint("./%", output_exe);
            host_args: [..]string;
            array_add(*host_args, path_to_host_exe);
            if OS == .WINDOWS && module_paths_already_set_in_environment {
                // If this build script is launching the host directly, we can tell the host to skip adding its own module paths, since we already had to add them for the build process (in case any compile time code wanted to call those DLLs).
                array_add(*host_args, "--skip-path-setup");
            }
            if script_opts.dll {
                app_filename := apps_to_build[0];
                array_add(*host_args, "--app", get_output_dll_filename_for_main_app_source_file(app_filename));
            }
            if script_opts.run_args {
                args_splitted_by_space := String.split(script_opts.run_args, #char " ");
                array_add(*host_args, ..args_splitted_by_space);
            }
            if script_opts.verbose {
                log("RUNNING in %: %", abs_output_path, String.join(..host_args, separator=" "));
            }
            res, stdout, stderr := run_command(..host_args);
            if script_opts.verbose log("App exited.");
        }
    } else {
        if script_opts.verbose log("Not running the app, because we're building for the IDE.");
    }
}

determine_current_macos_major_version :: () -> u8 {
    res, output_str, err_str := run_command("sw_vers", "--productVersion", capture_and_return_output = true);
    if res.type != .EXITED || res.exit_code != 0 || !output_str {
        exit_with_error("error running 'sw_vers' to determine macos version");
    }

    dot_idx := String.find_index_from_left(output_str, ".");
    if dot_idx == -1 {
        exit_with_error("expected a version string like '26.0.1' from swver, but got: '%'", output_str);
    }

    output_str.count = dot_idx;

    major_ver_int, success := string_to_int(output_str);
    if !success || major_ver_int <= 0 || major_ver_int >= 255 {
        exit_with_error("failed to intify version string");
    }

    return cast(u8)major_ver_int;
}

common_options :: (workspace: Workspace, result_output_type: type_of(Build_Options.output_type), output_dir: string = OUTPUT_PATH, script_opts: Build_Script_Opts) -> Build_Options {
    using options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *options);

    #if OS == .MACOS {
        modules_paths: [..]string;
        array_add(*modules_paths, "modules/sgpu/modules");
        array_add(*modules_paths, ..import_path);
        import_path = modules_paths;
    }

    output_path = output_dir;
    os_target   = OS;
    cpu_target  = CPU;
    #if BUILD_IS_FOR_IDE output_type = .NO_OUTPUT;
    else output_type = result_output_type;

    if 0 {
        if result_output_type == .DYNAMIC_LIBRARY text_output_flags = .OUTPUT_TIMING_INFO;
        else text_output_flags = 0;
    } else {
        text_output_flags = 0;
    }

    #if OS != .MACOS {
        if !script_opts.release backend = .X64;
    }

    #if OS == .MACOS {
        //macos_version_major: u8;
        //if script_opts.release macos_version_major = MACOS_MAJOR_VERSION_FOR_RELEASE_BUILD;
        //else                   macos_version_major = MACOS_MAJOR_VERSION_FOR_DEBUG_BUILD;

        //minimum_os_version=.{major=macos_version_major, minor=0};
        //log("Minimum OS version set to macOS %", macos_version_major);

        if result_output_type == .EXECUTABLE {
            // Patch the output binary's rpaths so that it can find the dylibs we link to.
            linker_args: [..]string;
            for get_dynamic_library_paths() array_add(*linker_args, "-rpath", it);
            array_add(*linker_args, ..additional_linker_arguments);
            additional_linker_arguments = linker_args;
        }
    }

    return options;
}

get_dynamic_library_paths :: () -> []string /* temp allocated */ {
    path_to_jai_modules :: #run compiler_get_base_path();

    local_module :: (s: string) -> string { return tprint("./modules/%", s); }
    jai_module   :: (s: string) -> string { return String.path_join(path_to_jai_modules, "modules", s); }

    // cross platform--needs a "win" or "linux" or "macos" directory on the end of these. see platform_dir below.
    local_module_dll_paths :: string.[
        "ImGui",
        "assimp/lib",
        "JoltC/lib",
        "Game_Sound/lib",
        //"SDL3/lib",
        //"SDL_gpu_ext/lib",
        //"ImGuizmo/lib",
        //"im3d/lib",
    ];

    #if OS == .MACOS mac_specific_dylib_paths :: string.[
        //"sgpu/modules/slang/mac",
    ];

    results: [..]string;
    results.allocator = temp;

    platform_name := get_shortened_platform_name_for_filesystem(OS);

    all_paths: [..]string;
    all_paths.allocator = temp;
    array_add(*all_paths, ..local_module_dll_paths);
    #if OS == .MACOS array_add(*all_paths, ..mac_specific_dylib_paths);

    //
    // TODO: for actual release builds, we're going to have to copy dlls/dylibs. or build static!
    //
    for all_paths {
        path: string = local_module(it);
        if !String.ends_with(path, "mac") { // HACK
            path = String.path_join(path, platform_name);
        }
        if !file_exists(path)  exit_with_error("Error: expected dll path to exist: '%' (current working directory: '%')", path, get_working_directory());

        path_relative_to_dist_dir := String.path_join("..", path);
        array_add(*results, path_relative_to_dist_dir);
    }

    #if OS == .MACOS {
        jai_stdlib_dll_paths :: string.[
            "Objective_C/LightweightRenderingView"
        ];
        for jai_stdlib_dll_paths {
            path := jai_module(it);
            //if !file_exists(path) exit_with_error("Expected dynamic library path to exist: '%'", path);
            array_add(*results, path);
        }
    }

    return results;
}

build_jdll :: (output_name: string, source_file: string, script_opts: Build_Script_Opts) -> (success: bool) {
    plugins: [..]*Metaprogram_Plugin;
    add_common_plugins(*plugins, script_opts);
    check_for_unnecessary_build: bool;

    if BUILD_IS_FOR_IDE {
        check_for_unnecessary_build = false;
    } else {
        check_for_unnecessary_build = script_opts.dll;
        array_add(*plugins, Build_Manifest.get_plugin());
        // TODO: include JDLL source in build manifest implicit dependencies!
        array_add(*plugins, JDLL.get_plugin());
    }

    result := build_artifact(
        workspace_name = tprint("Build jdll %", output_name),
        .DYNAMIC_LIBRARY,
        output_name,
        plugins,
        source_file,
        tprint("modules/%/%", output_name, PLATFORM_DIR),
        script_opts,
        check_for_unnecessary_build=check_for_unnecessary_build
    );
    return result != .failed;
}

log_build_result :: (output_name: string, output_type: type_of(Build_Options.output_type), start_time: float64, result: Build_Artifact_Result, verbose := false) {
    duration := seconds_since_init() - start_time;
    duration_formatter := FormatFloat.{trailing_width = 3, value = duration};

    ext := "";
    if output_type == {
    case .EXECUTABLE;
        #if OS == .WINDOWS ext = ".exe";
    case .DYNAMIC_LIBRARY;
        ext = tprint(".%", DLL_EXTENSION);
    case .NO_OUTPUT;
        ext = "";
    case;
        exit_with_error(tprint("TODO: implement extension string for %", output_type));
    }
    filename_on_disk := ifx output_type == .NO_OUTPUT then tprint("% (shader-only)", output_name) else tprint("%/%%", OUTPUT_PATH, output_name, ext);

    if #complete result == {
    case .skipped; if verbose log      ("No build required for %", filename_on_disk);
    case .failed;  log_error("Build FAILED for %", filename_on_disk);
    case .success; log      ("Built %%% seconds", filename_on_disk, "\t", duration_formatter);
    }
}

#if OS == {
    case .MACOS;   DLL_EXTENSION :: "dylib";
    case .WINDOWS; DLL_EXTENSION :: "dll";
    case .LINUX;   DLL_EXTENSION :: "so";
    case; #assert false "please implement this for this platform";
}

get_output_dll_filename_for_main_app_source_file :: (source_file: string) -> string {
    return tprint("%.%", String.path_strip_extension(String.path_filename(source_file)), DLL_EXTENSION);
}

check_if_host_is_running :: (script_opts: Build_Script_Opts, output_exe: string) -> bool {
    #if OS == .MACOS {
        res, stdout, stderr, timeout := run_command("./tools/check_if_running.sh", output_exe, capture_and_return_output = true);
        if timeout exit_with_error("Timeout reached while checking if host is running");
        if stderr print("stderr: %\n", stderr);
        //if stdout print("stdout: %", stdout);
        if res.type != .EXITED exit_with_error("pgrep did not exit");
        return res.exit_code == 0;
    } else #if OS == .WINDOWS {
        // @Perf - this is slow because of tasklist.exe. Maybe we should have the host grab a file lock.
        res, stdout, stderr, timeout := run_command("tasklist", "/fi", tprint("IMAGENAME eq %", output_exe), capture_and_return_output = true);
        if timeout exit_with_error("Timeout reached while checking if host is running");
        if stderr print("stderr: %\n", stderr);
        if String.find_index_from_left(stdout, "No tasks are running") != -1
            return false;
        if String.find_index_from_left(stdout, output_exe) == -1
            return true;
        if stdout print("stdout:\n%\n", stdout);
        if res.type != .EXITED exit_with_error("tasklist did not exit");
        exit_with_error("Could not discover if the host is running.");
        return false;
    } else {
        log("WARNING: on %, we don't know how to check if the host is running... returning false.", OS);
        return false;
    }
}

add_host_plugins :: (plugins: *[..]*Metaprogram_Plugin, script_opts: Build_Script_Opts) {
    #if BUILD_IS_FOR_IDE return;

    build_manifest_plugin := Build_Manifest.get_plugin();
    Build_Manifest.mark_dependency(build_manifest_plugin, THIS_SCRIPT_PATH);
    build_manifest_plugin.on_event = host_build_manifest_event;

    userdata := New(Build_Script_Opts);
    userdata.* = script_opts;
    build_manifest_plugin.on_event_userdata = userdata;

    array_add(plugins, build_manifest_plugin);

    if script_opts.tracy {
        Tracy :: #import "tracy";
        tracy_plugin := cast(*Tracy.My_Plugin)Tracy.get_plugin();
        tracy_plugin.should_instrument = (body: *Code_Procedure_Body) -> bool {
            filename := body.enclosing_load.fully_pathed_filename;
            if String.ends_with(filename, "shader.jai") return false;
            if String.ends_with(filename, "ShaderFuncs/module.jai") return false;
            return true;
        }
        should_instrument: (body: *Code_Procedure_Body) -> bool;
        array_add(plugins, tracy_plugin);
    }
}

host_build_manifest_event :: (p: *Build_Manifest.Build_Manifest_Metaprogram_Plugin, evt: Build_Manifest.Build_Manifest_Event, userdata: *void) {
    if evt == {
    case .Executable_Was_Built;
        // For Mac debug builds, we use `codesign` to sign the executable with
        // entitlements allowing Instruments to mark allocations. Here we add a
        // "build dependency" on the entitlements file, and make sure the code
        // signing happens before the Build_Manifest plugin marks the
        // modification time of the executable.
        #if OS == .MACOS {
            if !userdata return;

            script_opts := cast(*Build_Script_Opts)userdata;
            if script_opts.release return; // Codesigning as of now is for debug entitlements.

            output_exe := String.path_join(OUTPUT_PATH, script_opts.output_exe);
            if script_opts.verbose log("Codesigning host executable for get-tasks: %", output_exe);
            abs_entitlements_file := get_absolute_path(entitlements_file);
            assert(abs_entitlements_file != "", tprint("Could not resolve absolute path for entitlements file: %", entitlements_file));
            res, stdout, stderr := run_command("codesign", "--force", "--sign", "-", "--entitlements", abs_entitlements_file, "--timestamp=none", output_exe, capture_and_return_output=true);
            if res.type != .EXITED || res.exit_code != 0 {
                if stdout.count > 0 { log("%", stdout); }
                if stderr.count > 0 { log_error("%", stderr); }
                exit_with_error("codesign failed");
            }
            Build_Manifest.mark_dependency(p, abs_entitlements_file);
        }
    }
}

add_common_plugins :: (plugins: *[..] *Metaprogram_Plugin, script_opts: Build_Script_Opts) {
    if script_opts.perf {
        PR :: #import "Performance_Report";
        array_add(plugins, PR.get_plugin());
    }
}

add_app_plugins :: (plugins: *[..] *Metaprogram_Plugin,
    script_opts: Build_Script_Opts,
    app_filename: string = "",
    shader_entry_ids_filter: string = "",
    shader_only := false, // true if we're doing a shader-only build
    build_strings: *[..]string,
) {
    if !shader_only && !BUILD_IS_FOR_IDE {
        // Notes globals in the game's dll so that we can reload them automatically when the dll is recompiled.
        Globals_Reload :: #import "Globals_Reload";
        p := Globals_Reload.get_plugin();
        array_add(plugins, p);
        array_add(build_strings, "GLOBALS_RELOAD_PLUGIN_INCLUDED :: true;");
    } else {
        array_add(build_strings, "GLOBALS_RELOAD_PLUGIN_INCLUDED :: false;");
    }
    #if !BUILD_IS_FOR_IDE {

        if script_opts.codex {
            Codex :: #import "Codex";
            array_add(plugins, Codex.get_plugin());
        }
        if script_opts.iprof {
            IProf :: #import "Iprof";
            array_add(plugins, IProf.get_plugin());
        }
    }
    {
        Event_Functions_Metaprogram :: #import "Event_Functions_Metaprogram";
        array_add(plugins, Event_Functions_Metaprogram.get_plugin());
    }
    {
        Init_Metaprogram :: #import "Init_Metaprogram";
        array_add(plugins, Init_Metaprogram.get_plugin());
    }
    {
        JSL :: #import "Jai-Shader-Transpiler";
        plugin := JSL.get_plugin();
        // plugin.output_shaders = true;
        // plugin.timings_enabled = true;
        if app_filename.count != 0 {
            plugin.manifest_app_name = String.path_strip_extension(String.path_filename(app_filename));
        }
        plugin.shader_entry_ids_filter = shader_entry_ids_filter;
        array_add(plugins, plugin);
    }
}

build_host :: (script_opts: Build_Script_Opts, include_app_plugins: bool = false, app_filename: string = "", build_strings: []string = .[]) -> bool {
    local_build_strings: [..]string;

    plugins: [..] *Metaprogram_Plugin;
    add_common_plugins(*plugins, script_opts);
    if include_app_plugins {
        add_app_plugins(*plugins, script_opts, app_filename=app_filename, build_strings=*local_build_strings);
    }
    add_host_plugins(*plugins, script_opts);

    array_add(*local_build_strings, ..build_strings);
    array_add(*local_build_strings, tprint("HOST_OUTPUT_EXECUTABLE_NAME :: \"%\";", script_opts.output_exe));
    #if OS == .MACOS {
        array_add(*local_build_strings, "PEEL_MACOS_RUNTIME_OWNER :: true;");
    }
    if !script_opts.dll {
        array_add(*local_build_strings, tprint("APP_NAME :: \"%\";", script_opts.output_exe));
    }

    result := build_artifact("Build host",
        .EXECUTABLE, script_opts.output_exe, plugins, HOST_JAI_ROOT, OUTPUT_PATH, script_opts,
        check_for_unnecessary_build=script_opts.dll,
        build_strings=local_build_strings);

    return result != Build_Artifact_Result.failed;
}

build_app :: (script_opts: Build_Script_Opts, app_filename: string) -> bool {
    // Since the build can generate a lot debug and temporary files if you use it a lot,
    // we do some clean up to not keep too much garbage.
    visit_files(OUTPUT_PATH, recursive = false, null, delete_app_files_visitor, visit_files = true, visit_directories = true);

    plugins: [..] *Metaprogram_Plugin;
    plugins.allocator = temp;
    add_common_plugins(*plugins, script_opts);

    build_strings: [..]string;
    array_add(*build_strings, sprint("APP_NAME :: \"%\";", app_filename));
    array_add(*build_strings, tprint("TRACY_PROFILER_ENABLED :: %;", script_opts.tracy));
    #if OS == .MACOS {
        array_add(*build_strings, "PEEL_MACOS_RUNTIME_OWNER :: false;");
    }
    add_app_plugins(*plugins, script_opts, app_filename=app_filename, build_strings=*build_strings);

    app_output_executable_name := String.path_strip_extension(String.path_filename(app_filename));

    result := build_artifact(
        workspace_name = tprint("Build app %", app_output_executable_name),
        .DYNAMIC_LIBRARY, app_output_executable_name, plugins, app_filename, OUTPUT_PATH, script_opts,
        build_strings=build_strings);

    return result != .failed;
};

build_shader_only :: (script_opts: Build_Script_Opts, app_filename: string) -> bool {
    plugins: [..] *Metaprogram_Plugin;
    plugins.allocator = temp;
    add_common_plugins(*plugins, script_opts);
    build_strings: [..]string;
    array_add(*build_strings, sprint("APP_NAME :: \"%\";", app_filename));
    add_app_plugins(*plugins, script_opts, app_filename=app_filename, shader_entry_ids_filter=script_opts.shader_entry_ids, shader_only=true, build_strings=*build_strings);

    app_name := String.path_strip_extension(String.path_filename(app_filename));
    result := build_artifact(workspace_name = tprint("Build shaders %", app_name),
        .NO_OUTPUT, app_name, plugins, app_filename, OUTPUT_PATH, script_opts, build_strings=build_strings);

    return result != .failed;
}

Build_Artifact_Result :: enum { success; skipped; failed; }

build_artifact :: (workspace_name: string,
                   output_type: type_of(Build_Options.output_type),
                   output_filename: string,
                   plugins: [] *Metaprogram_Plugin,
                   source_filename: string,
                   output_dir: string = OUTPUT_PATH,
                   script_opts: Build_Script_Opts,
                   check_for_unnecessary_build := false,
                   build_strings: []string = .[],
)
-> Build_Artifact_Result {
    assert(output_filename != "");
    result: Build_Artifact_Result = .failed;

    begin := seconds_since_init();
    defer log_build_result(output_filename, output_type, begin, result, script_opts.verbose);

    workspace := compiler_create_workspace(workspace_name);
    defer compiler_destroy_workspace(workspace);
    //log("% - %", workspace_name, workspace);

    make_directory_if_it_does_not_exist(output_dir, recursive=true);

    {
        options: Build_Options = common_options(workspace, output_type, output_dir, script_opts);
        options.output_executable_name = output_filename;
        options.intermediate_path = sprint(".build/%", output_filename); // so parallel builds don't clobber each other.
        if script_opts.release {
            set_optimization(*options, .VERY_OPTIMIZED);
            options.array_bounds_check = .OFF;
            options.stack_trace = false;
        } else {
            set_optimization(*options, .DEBUG);
        }
        set_build_options(options, workspace);

        // Now that we have the actual build options setup for the compiler, we
        // can use them to ask Build_Manifest if we can skip the build.
        if !BUILD_IS_FOR_IDE && check_for_unnecessary_build &&
        Build_Manifest.can_skip_build(options) {
            result = .skipped;
            return result;
        }
    }


    intercept_flags: Intercept_Flags = 0;
    for plugins it.workspace = workspace;
    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);
    compiler_begin_intercept(workspace, intercept_flags);
    defer {
        compiler_end_intercept(workspace);
        for plugins if it.finish   it.finish  (it);
        for plugins if it.shutdown it.shutdown(it);
    }
    for plugins      if it.add_source it.add_source(it);
    add_build_string(tprint("SINGLE_BINARY :: %;\n", !script_opts.dll), workspace);
    add_build_string(tprint("RELEASE :: %;\n", script_opts.release), workspace);
    for build_strings add_build_string(it, workspace);
    add_build_file(source_filename, workspace);

    while true {
        message := compiler_wait_for_message();
        for plugins if it.message it.message(it, message);
        if message.kind == {
            case .COMPLETE; {
                message_complete := cast(*Message_Complete) message;
                result = ifx message_complete.error_code == .NONE then .success else .failed;
                break;
            }
        }
    }

    return result;
}

exit_with_error :: (message: string = "", fmt_args: ..Any) {
    if message log_error(message, ..fmt_args);
    compiler_set_workspace_status(.FAILED, get_current_workspace());
    exit(1);
}

delete_app_files_visitor :: (info: *File_Visit_Info, user_data: *void) {
    f := info.short_name;

    if !f || !String.starts_with(f, "app_")
        return;

    f.count -= 1;

    looks_like_a_dll_temp_file := false;
    #if OS == .MACOS {
        looks_like_a_dll_temp_file = String.ends_with(f, ".dylib.temp.");
    } else #if OS == .WINDOWS {
        looks_like_a_dll_temp_file = String.ends_with(f, ".dll.temp.");
    }

    if looks_like_a_dll_temp_file {
        // log("deleting %", info.full_name);
        if info.is_directory delete_directory(info.full_name);
        else file_delete(info.full_name);
    }
}

#scope_file

set_release_build :: (using opts: *Build_Script_Opts) {
    release = true;
    if dll exit_with_error("Cannot currently build a live-reload DLL in release mode.");
}

get_platform_dir :: (platform_tag: Operating_System_Tag) -> string {
    return sprint("lib/%", get_shortened_platform_name_for_filesystem(platform_tag));
}

get_shortened_platform_name_for_filesystem :: (platform_tag: Operating_System_Tag) -> string {
    if platform_tag == .WINDOWS return "win";
    name := sprint("%", platform_tag);
    String.to_lower_in_place(name);
    return name;
}

environment_specifies_release_build :: () -> bool {
    #if OS == .MACOS {
        using,only(getenv) POSIX :: #import "POSIX";
        if getenv("XCODE_VERSION_MINOR") != null && getenv("TARGET_NAME") != null {
            configuration := to_string(getenv("CONFIGURATION"));
            if configuration == "Release" {
                log("Building from XCode. CONFIGURATION=%, so setting release build.", configuration);
                return true;
            }
        }
    }
    return false;
}

parallel_build_all_and_exit :: (cmd_line_args: []string, script_opts: Build_Script_Opts) {
    args_list: [..][]string;
    for APP_FILES {
        args: [..]string;
        array_add(*args, "jai", "build.jai", "-", "-sub_build");
        array_add(*args, ..cmd_line_args);
        array_add(*args, tprint("%/%", APPS_DIR, it));

        array_add(*args_list, args);
    }

    start_time := current_time_monotonic();
    all_ok := parallel_run(args_list);
    if all_ok {
        // For now it doesn't make sense to log the build time if we're running everything at once, since
        // we won't actually know the "finish" time until the last window is closed.
        if !script_opts.run {
            log("OK: Built everything in % seconds.", to_float64_seconds(current_time_monotonic() - start_time));
        }

        exit(0);
    } else {
        log_error("Parallel build failed.");
        exit(1);
    }
}

#import "Basic";
#import "File";
#import "Compiler";
#import "File_Utilities"; // for visit_files
#import "Process";
#import "Parallel_Run";
#import "Compile_Time_Shader_Build";
Command_Line :: #import "Command_Line";
String :: #import "String";
#if OS == .WINDOWS #load "src/Windows_DLL_Paths.jai";
Build_Manifest :: #import "Build_Manifest";
JDLL :: #import "JDLL";
module_paths_already_set_in_environment := false;
