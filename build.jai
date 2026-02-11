/*

Builds and runs the host and the "app" dll.

*/

#load "src/app_list.jai";
THIS_SCRIPT_PATH :: #run String.path_join(#filepath, "build.jai");
HOST_JAI_ROOT :: "src/host.jai";

OUTPUT_PATH                 :: "dist";      // The directory where the program binary goes.
HOST_OUTPUT_EXECUTABLE_NAME :: "peel";      // The name of the host executable.
BUILD_IS_FOR_IDE            :: #exists(JAILS_DIAGNOSTICS_BUILD); // Whether the build is for the IDE's error display. (Jails language server runs the build to check for errors.)
VERBOSE                     :: false;       // Whether to print verbose output for the build process.
#if OS == .MACOS {
    MACOS_MAJOR_VERSION_FOR_RELEASE_BUILD :: 15;
    MACOS_MAJOR_VERSION_FOR_DEBUG_BUILD :: 36;
    entitlements_file :: #run String.path_join(OUTPUT_PATH, "debug-entitlements.plist");
}
PLATFORM_DIR :: #run get_platform_dir(OS); // win, macos, linux

Build_Script_Opts :: struct {
    run_program_after_build : bool = true;
    build_host              : bool = true;
    build_all_dlls          : bool;
    release                 : bool;
    skip_host_build         : bool;
    codex                   : bool;
    iprof                   : bool;
    single_binary           : bool;
}

#run,stallable {
    set_build_options_dc(.{ do_output = false });
    set_working_directory(#filepath);

    USAGE_MESSAGE :: #string END
Options:
    -all           Build all apps.
    -onlyapp       Only build the app DLL, not the host.
    -release       Build in release mode with optimizations.
    -skiphost      Skip building the host.
    -codex         Add the Codex metaprogram plugin.
    -iprof         Add the IProf metaprogram plugin.
    -slang_emit_line_directives Keep Slang `#line` directives in generated Metal/GLSL output.
    -norun         Don't run the program after building it.
    -help          Show this help message.
END;

    // Command line arguments to this build script.
    script_opts: Build_Script_Opts;

    for get_build_options().compile_time_command_line {
        if it == {
        case "-help";
            exit_with_success(USAGE_MESSAGE);
        case "-all";
            script_opts.build_all_dlls = true;
        case "-norun"; // Don't run the program after building it.
            script_opts.run_program_after_build = false;
        case "-onlyapp"; // Only build the app DLL, not the host.
            script_opts.build_host = false;
            script_opts.run_program_after_build = false;
        case "-release"; // Build the program in release mode with optimizations.
            set_release_build(*script_opts);
        case "-skiphost"; // Skip building the host.
            script_opts.skip_host_build = true;
        case "-codex";
            script_opts.codex = true;
        case "-iprof";
            script_opts.iprof = true;
            script_opts.single_binary = true;
        case "-slang_emit_line_directives"; #through;
            // Consumed by Jai-Shader-Transpiler plugin in compile-time code.
        case;
            log(USAGE_MESSAGE);
            log_error("Unknown argument #%: %\n", it_index, it);
            exit_with_error();
        }
    }

    #if OS == .MACOS {
        using,only(getenv) POSIX :: #import "POSIX";
        if getenv("XCODE_VERSION_MINOR") != null && getenv("TARGET_NAME") != null {
            configuration := to_string(getenv("CONFIGURATION"));
            if configuration == "Release" {
                log("Building from XCode. CONFIGURATION=%, so setting release build.", configuration);
                set_release_build(*script_opts);
            }
        }
    }

    // Create the output dir.
    make_directory_if_it_does_not_exist(OUTPUT_PATH, recursive = true);

    if script_opts.single_binary {
        assert(!script_opts.build_all_dlls);
    }

    // Build shaders.
    #if !BUILD_IS_FOR_IDE {
        #if OS == .MACOS && 0 {
            shader_input_files  :: string.[
                "dist/shaders/metal/triangle.metal",
                "modules/im3d/shaders/Im3d.metal"
            ];
            output_library_path :: "dist/default.metallib";

            Build_Manifest.external_build(shader_input_files, output_library_path, () {
                if !build_metal(shader_input_files, output_library_path) {
                    exit_with_error("Error building shaders.");
                }
            });
        }
    }

    app_filename := APP_FILES[0];

    #if OS == .WINDOWS {
        if !do_path_setup_for_dlls("modules", make_paths_absolute = true) {
            exit_with_error("Failed to setup PATH for DLLs");
            return;
        }
        module_paths_already_set_in_environment = true;
    }

    #if !BUILD_IS_FOR_IDE {
        // All builds will depend on the contents of this build.jai file, as well as all their source files.
        Build_Manifest.mark_meta_dependency(THIS_SCRIPT_PATH);
    }

    // Build the host if it's not already running.
    host_was_running := false;
    if script_opts.build_host {
        #if !BUILD_IS_FOR_IDE {
            host_was_running = check_if_host_is_running();
        }

        if !host_was_running && !script_opts.skip_host_build {
            include_app_plugins_for_app_filename: string;
            if script_opts.single_binary {
                include_app_plugins_for_app_filename = app_filename;
            }

            if !build_host(script_opts, include_app_plugins_for_app_filename) {
                exit_with_error("Failed to build the host");
            }
        } else {
            log("Skipping host build.");
        }
    }

    // Build the DLL(s).
    if !script_opts.single_binary {
        if !build_jdll("Game_Sound", "src/dlls/Game_Sound.jai", script_opts) {
            exit_with_error("Failed to build the DLL for '%'", "Game_Sound");
        }

        apps_to_build: [..]string;
        if script_opts.build_all_dlls {
            array_add(*apps_to_build, ..APP_FILES);
        } else {
            array_add(*apps_to_build, app_filename);
        }

        for apps_to_build {
            if !build_app(script_opts, app_filename=it) {
                exit_with_error("Failed to build the app for '%'", it);
            }
        }
    }

    // Start the host if it's not already running.
    #if !BUILD_IS_FOR_IDE {
        if !script_opts.run_program_after_build {
            #if VERBOSE log("Not running the app, because -norun was passed.");
        } else if host_was_running {
            log("Not running the app, because the host is already running.");
        } else {
            #if VERBOSE log("Running the app...");
            abs_output_path := get_absolute_path(OUTPUT_PATH);
            if !abs_output_path exit_with_error("Failed to get absolute path of output path: '%'", OUTPUT_PATH);
            set_working_directory(abs_output_path);
            path_to_host_exe := tprint("./%", HOST_OUTPUT_EXECUTABLE_NAME);
            host_args: [..]string;
            array_add(*host_args, path_to_host_exe);
            if OS == .WINDOWS && module_paths_already_set_in_environment {
                // If this build script is launching the host directly, we can tell the host to skip adding its own module paths, since we already had to add them for the build process (in case any compile time code wanted to call those DLLs).
                array_add(*host_args, "--skip-path-setup");
            }
            if !script_opts.single_binary {
                array_add(*host_args, "--app", get_output_dll_filename_for_main_app_source_file(app_filename));
            }
            res, stdout, stderr := run_command(..host_args);
            #if VERBOSE log("App exited.");
            if stderr log("Stderr: %", stderr);
            if stdout log("Stdout: %", stdout);
        }
    } else {
        #if VERBOSE log("Not running the app, because we're building for the IDE.");
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

            for get_dynamic_library_paths() {
                array_add(*linker_args, "-rpath", it);
            }
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
        //"ImGui",
        //"SDL3/lib",
        //"assimp/lib",
        //"JoltC/lib",
        //"SDL_gpu_ext/lib",
        //"ImGuizmo/lib",
        "Game_Sound/lib",
        //"im3d/lib",
    ];

    #if OS == .MACOS mac_specific_dylib_paths :: string.[
        "sgpu/modules/slang/mac",
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
    begin := seconds_since_init();

    plugins: [..]*Metaprogram_Plugin;
    check_for_unnecessary_build: bool;

    if BUILD_IS_FOR_IDE {
        check_for_unnecessary_build = false;
    } else {
        check_for_unnecessary_build = true;

        {
            p := Build_Manifest.get_plugin();
            array_add(*plugins, p);
        }
        {
            array_add(*plugins, JDLL.get_plugin());
        }
    }

    result := build_artifact(
        workspace_name = tprint("Build jdll %", output_name),
        .DYNAMIC_LIBRARY,
        output_name,
        plugins,
        source_file,
        tprint("modules/%/%", output_name, PLATFORM_DIR),
        script_opts,
        check_for_unnecessary_build=true
    );

    ok := result != Build_Artifact_Result.failed;
    if ok {
        duration := seconds_since_init() - begin;
        log("Build % (%)\t% seconds", output_name, result, duration);
    }

    return ok;
}

#if OS == {
    case .MACOS;   DLL_EXTENSION :: "dylib";
    case .WINDOWS; DLL_EXTENSION :: "dll";
    case .LINUX;   DLL_EXTENSION :: "so";
    case; #assert false "please implement this for this platform";
}

get_output_dll_filename_for_main_app_source_file :: (source_file: string) -> string {
    return tprint("%.%", String.path_strip_extension(source_file), DLL_EXTENSION);
}

check_if_host_is_running :: () -> bool {
    #if OS == .MACOS {
        res, stdout, stderr, timeout := run_command("./tools/check_if_running.sh", HOST_OUTPUT_EXECUTABLE_NAME, capture_and_return_output = true);
        if timeout exit_with_error("Timeout reached while checking if host is running");
        if stderr print("stderr: %\n", stderr);
        //if stdout print("stdout: %", stdout);
        if res.type != .EXITED exit_with_error("pgrep did not exit");
        return res.exit_code == 0;
    } else #if OS == .WINDOWS {
        // @Perf - this is slow because of tasklist.exe. Maybe we should have the host grab a file lock.
        res, stdout, stderr, timeout := run_command("tasklist", "/fi", tprint("IMAGENAME eq %", HOST_OUTPUT_EXECUTABLE_NAME), capture_and_return_output = true);
        if timeout exit_with_error("Timeout reached while checking if host is running");
        if stderr print("stderr: %\n", stderr);
        if String.find_index_from_left(stdout, "No tasks are running") != -1
            return false;
        if String.find_index_from_left(stdout, HOST_OUTPUT_EXECUTABLE_NAME) == -1
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
    #if BUILD_IS_FOR_IDE {
        return;
    }

    build_manifest_plugin := Build_Manifest.get_plugin();
    Build_Manifest.mark_dependency(build_manifest_plugin, THIS_SCRIPT_PATH);
    build_manifest_plugin.on_event = host_build_manifest_event;

    userdata := New(Build_Script_Opts);
    userdata.* = script_opts;
    build_manifest_plugin.on_event_userdata = userdata;

    array_add(plugins, build_manifest_plugin);
}

host_build_manifest_event :: (p: *Build_Manifest.Build_Manifest_Metaprogram_Plugin, evt: Build_Manifest.Build_Manifest_Event, userdata: *void) {
    if evt == {
    case .Executable_Was_Built;
        /* For Mac debug builds, we use `codesign` to sign the executable with entitlements allowing Instruments to mark allocations.
        Here we add a "build dependency" on the entitlements file, and make sure the code signing happens before the Build_Manifest
        plugin marks the modification time of the executable. */
        #if OS == .MACOS {
            if !userdata {
                return;
            }

            script_opts := cast(*Build_Script_Opts)userdata;
            if script_opts.release return;

            log("Codesigning host executable for get-tasks...");
            output_exe := String.path_join(OUTPUT_PATH, HOST_OUTPUT_EXECUTABLE_NAME);
            abs_entitlements_file := get_absolute_path(entitlements_file);
            assert(abs_entitlements_file != "", tprint("Could not resolve absolute path for entitlements file: %", entitlements_file));
            res := run_command("codesign", "--force", "--sign", "-", "--entitlements", abs_entitlements_file, "--timestamp=none", output_exe);
            if res.type != .EXITED || res.exit_code != 0 {
                exit_with_error("codesign failed");
            }
            Build_Manifest.mark_dependency(p, abs_entitlements_file);
        }
    }
}

add_app_plugins :: (plugins: *[..] *Metaprogram_Plugin, script_opts: Build_Script_Opts, app_filename: string) {
    {
        // Notes globals in the game's dll so that we can reload them automatically when the dll is recompiled.
        Globals_Reload :: #import "Globals_Reload";
        p := Globals_Reload.get_plugin();
        array_add(plugins, p);
    }
    {
        Event_Functions_Metaprogram :: #import "Event_Functions_Metaprogram";
        array_add(plugins, Event_Functions_Metaprogram.get_plugin());
    }

    #if !BUILD_IS_FOR_IDE {
        // Notes jai structs marked with @ShaderType and generates shader code for them.
        Shader_Metaprogram :: #import "Shader_Metaprogram";
        shader_metaprogram_plugin := cast(*Shader_Metaprogram.Shader_Metaprogram_Plugin) Shader_Metaprogram.get_plugin();
        shader_metaprogram_plugin.output_filename = tprint("%/shaders/shader_types{SUFFIX}.generated.hlsl", OUTPUT_PATH);
        shader_metaprogram_plugin.empty_suffix = copy_string(String.path_strip_extension(app_filename));
        array_add(plugins, shader_metaprogram_plugin);


    }
    // Jai-Shader-Transpiler
    {
        JSL :: #import "Jai-Shader-Transpiler";
        plugin := JSL.get_plugin();
        plugin.output_shaders = true;
        log("Using Jai-Shader-Transpiler plugin with output_shaders=%", plugin.output_shaders);
        array_add(plugins, plugin);
    }

    if script_opts.codex {
        Codex :: #import "Codex";
        array_add(plugins, Codex.get_plugin());
    }

    if script_opts.iprof {
        IProf :: #import "Iprof";
        array_add(plugins, IProf.get_plugin());
    }
}

build_host :: (script_opts: Build_Script_Opts, include_app_plugins_for_app_filename: string = "") -> bool {
    begin := seconds_since_init();

    plugins: [..] *Metaprogram_Plugin;

    if include_app_plugins_for_app_filename {
        // When building a single binary, we need to add the app plugins to the host.
        add_app_plugins(*plugins, script_opts, include_app_plugins_for_app_filename);
    }

    add_host_plugins(*plugins, script_opts);

    result := build_artifact("Build host",
        .EXECUTABLE, HOST_OUTPUT_EXECUTABLE_NAME, plugins, HOST_JAI_ROOT, OUTPUT_PATH, script_opts,
        check_for_unnecessary_build=true,
        build_strings=.[
            {"HOST_OUTPUT_EXECUTABLE_NAME", HOST_OUTPUT_EXECUTABLE_NAME}
        ]
    );

    ok := result != Build_Artifact_Result.failed;

    if ok {
        duration := seconds_since_init() - begin;
        log("Build host (%)\t% seconds", result, duration);
    }

    return ok;
}

build_app :: (script_opts: Build_Script_Opts, app_filename: string) -> bool {
    begin := seconds_since_init();

    #if VERBOSE {
        log("Building app '%'", app_filename);
        defer log("App built successfully.");
    }

    // Since the build can generate a lot debug and temporary files if you use it a lot,
    // we do some clean up to not keep too much garbage.
    visit_files(OUTPUT_PATH, recursive = false, null, delete_app_files_visitor, visit_files = true, visit_directories = true);

    plugins: [..] *Metaprogram_Plugin;
    add_app_plugins(*plugins, script_opts, app_filename);

    path_to_app_source_root    := tprint("%/%", PATH_TO_APP_FILES, app_filename);
    app_output_executable_name := String.path_strip_extension(app_filename);

    ok := .failed != build_artifact(
        workspace_name = tprint("Build app %", app_output_executable_name),
        .DYNAMIC_LIBRARY, app_output_executable_name, plugins, path_to_app_source_root, OUTPUT_PATH, script_opts);

    if ok {
        duration := seconds_since_init() - begin;
        log("Build %\t% seconds", app_output_executable_name, duration);
    }

    return ok;
};

Build_Artifact_Result :: enum { success; skipped; failed; }

Build_String :: struct {
    name: string;
    value: string;
}

build_artifact :: (workspace_name: string,
                   output_type: type_of(Build_Options.output_type),
                   output_filename: string,
                   plugins: [] *Metaprogram_Plugin,
                   source_filename: string,
                   output_dir: string = OUTPUT_PATH,
                   script_opts: Build_Script_Opts,
                   check_for_unnecessary_build := false,
                   build_strings: []Build_String = .[],
)
-> Build_Artifact_Result {
    workspace := compiler_create_workspace(workspace_name);
    defer compiler_destroy_workspace(workspace);
    //log("% - %", workspace_name, workspace);

    File :: #import "File";
    File.make_directory_if_it_does_not_exist(output_dir, recursive=true);

    {
        options: Build_Options;
        options = common_options(workspace, output_type, output_dir, script_opts);
        options.output_executable_name = output_filename;
        if script_opts.release {
            set_optimization(*options, .VERY_OPTIMIZED);
            options.array_bounds_check = .OFF;
            options.stack_trace = false;
        } else {
            set_optimization(*options, .DEBUG);
        }
        set_build_options(options, workspace);
        if !BUILD_IS_FOR_IDE && check_for_unnecessary_build && Build_Manifest.can_skip_build(options) {
            return .skipped;
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
    add_build_string(tprint("SINGLE_BINARY :: %;\n", script_opts.single_binary), workspace);
    add_build_string(tprint("RELEASE :: %;\n", script_opts.release), workspace);
    for build_strings {
        add_build_string(tprint("% :: \"%\";\n", it.name, it.value), workspace);
    }
    if script_opts.single_binary
        add_build_string(tprint("#load \"%/%\";\n", PATH_TO_APP_FILES, APP_FILES[0]), workspace);
    add_build_file(source_filename, workspace);

    result: Build_Artifact_Result = .success;
    while true {
        message := compiler_wait_for_message();
        for plugins if it.message it.message(it, message);
        if message.kind == {
            case .COMPLETE; {
                message_complete := cast(*Message_Complete) message;
                if message_complete.error_code != .NONE {
                    result = .failed;
                }
                break;
            }
        }
    }

    return result;
}

exit_with_success :: (message: string = "") {
    if message log(message);
    compiler_set_workspace_status(.OK, get_current_workspace());
    exit(0);
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
    single_binary = true;
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

#import "Basic";
#import "File";
#import "Compiler";
#import "File_Utilities"; // for visit_files
#import "Process";
#import "Compile_Time_Shader_Build";
String :: #import "String";
#if OS == .WINDOWS #load "src/Windows_DLL_Paths.jai";
Build_Manifest :: #import "Build_Manifest";
JDLL :: #import "JDLL";
module_paths_already_set_in_environment := false;
