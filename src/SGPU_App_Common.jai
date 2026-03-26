READBACK_ENABLED :: !RELEASE;
SGPU_FRAMES_IN_FLIGHT :: 3;
LIVE_RELOAD_ENABLED :: !RELEASE;

ImGui :: #import "ImGui";

// APP_NAME is like src/apps/boids.jai
// APP_STEM is like boids
APP_STEM :: #run String.path_strip_extension(String.path_filename(APP_NAME));

app_needs_recompile: string;
app_quit_requested := false;
did_init := false;

delta_time_multiplier: float = 1.0;
dt: float; // delta time for gameplay (modifiable by delta_time_multiplier)
editor_dt: float; // delta time for editor
last_time: float64;
time: float64;
frame_count: int;

time_scale: float = 1;
edit_time_scale: float = 1;

last_window_size: V2(u32);
window: *void; // TODO
sgpu_debug_status: string;

shader_reload_ctx: SHR.Shader_Hot_Reload;
max_frames: int;
reload_on_frame: int;
perf_capture_cpu_ms_sum: float64;
perf_capture_gpu_ms_sum: float64;
perf_capture_count: s64;
perf_capture_gpu_count: s64;
perf_capture_reported := false;
app_ui_enabled := true;
app_browser_open := false;
app_browser_requested_app: string;
host_build_target: string;
host_build_error: string;
host_build_state: App_Update_Ctx.Host_Build_State;
startup_load_app_target: string;
startup_load_app_frame: int;

snapshot: struct {
    enabled := false;
    before_done := false;
    after_pending := false;
    after_done := false;
    after_min_frame: s64 = 0;
}

PERF_CAPTURE_START_FRAME :: 5;
PERF_CAPTURE_END_FRAME :: 30;
PERF_CAPTURE_MIN_FPS :: 10.0;
#if READBACK_ENABLED {
    readback_stats: Readback_Stats;
}


sgpu_set_debug_status :: (status: string) {
    if sgpu_debug_status == status return;
    if sgpu_debug_status.count != 0 {
        free(sgpu_debug_status);
        sgpu_debug_status = "";
    }
    if status.count != 0 sgpu_debug_status = copy_string(status);
}

submit_and_present_with_ui :: (cmd_buff: Gpu_Command_Buffer, waits: [] Gpu_Timeline_Pair = .[]) {
    if !app_should_render_ui() {
        current_ui_render_frame = {};
        gpu_submit_and_present(cmd_buff, waits = waits);
        return;
    }

    ui_frame_value := gpu_submission_frame_index() + 1;
    gpu_end_render_pass_with_transition(cmd_buff, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);

    ui_render(cmd_buff, *current_ui_render_frame, ui_frame_value, skip_render=app_mini_mode_active);
    current_ui_render_frame = {};

    gpu_submit_and_present(cmd_buff, waits = waits);
    ui_on_frame_submitted(ui_frame_value);
}

app_swapchain_acquire :: () -> Gpu_Result, Gpu_Texture_View {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if swapchain_image != 0 {
        if app_should_render_ui() {
            current_ui_render_frame = ui_render_pre();
        } else {
            current_ui_render_frame = {};
        }
    }
    return result, swapchain_image;
}

app_update :: (update_ctx: *App_Update_Ctx) {
    auto_release_temp();
    #if #exists(TRACY_PROFILER_ENABLED) {
        #if TRACY_PROFILER_ENABLED Tracy.FrameMark();
    }

    #if OS == .MACOS {
        pool := objc_new(NSAutoreleasePool);
        defer release(pool);
    }

    app_assign_host_build_status(update_ctx.host_build_state, update_ctx.host_build_target, update_ctx.host_build_error);

    time = seconds_since_init();
    dt = cast(float)(time - last_time);
    editor_dt = dt;
    last_time = time;
    cpu_frame_ms := dt * 1000.0;

    dt *= time_scale;
    editor_dt *= edit_time_scale;

    gpu_frame_ms := gpu_last_frame_gpu_ms();
    perf_push_cpu_frame_ms(cpu_frame_ms);
    perf_set_latest_gpu_frame_ms(gpu_frame_ms);

    if window && frame_count % PERF_TITLE_UPDATE_EVERY_FRAMES == 0 {
        perf_text := perf_title_text();
        title := tprint("% | %", APP_STEM, perf_text);

        #if !RELEASE {
            mem_text := human_readable_bytes(current_memory_usage_bytes(),, temp);
            title = tprint("% | % | %", APP_STEM, perf_text, mem_text);
            if sgpu_debug_status.count != 0 {
                title = tprint("% | % | % | %", APP_STEM, perf_text, mem_text, sgpu_debug_status);
            }
        }

        set_window_title(window, title);
    }

    frame_count += 1;
    perf_capture(cpu_frame_ms, gpu_frame_ms);

    Input.update_window_events();
    handle_focus_transition_after_input_update();
    #if OS == .MACOS {
        _, _, current_w, current_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
        if dims_ok {
            current_size := V2(u32).{xx current_w, xx current_h};
            if current_size.x != last_window_size.x || current_size.y != last_window_size.y {
                last_window_size = current_size;
                if frame_count > 1 {
                    gpu_swapchain_resize();
                }
            }
        }
    } else {
        for Input.get_window_resizes() {
            if it.window == window {
                gpu_swapchain_resize();
            }
        }
    }

    ui_has_keyboard := ui_wants_keyboard();
    for Input.events_this_frame {
        using it;
        if type == {
            case .QUIT;
                app_quit_requested = true;
            case .KEYBOARD;
                if !ui_has_keyboard && key_pressed {
                    if key_code == {
                    case .F1;
                        toggle_all_ui();
                    case .F2;
                        ui_opts.globals.show ^= true;
                        app_ui_enabled |= ui_opts.globals.show;
                    case .F3;
                        ui_opts.show_imgui_demo ^= true;
                    case .F4;
                        inspiration_board_toggle();
                    case .ESCAPE;
                        #if !SINGLE_BINARY {
                            app_browser_open = !app_browser_open;
                            app_ui_enabled |= app_browser_open;
                        }

                    // Reload app dll
                    case #char "R";
                        #if !SINGLE_BINARY update_ctx.app_return_flags |= .Reload;

                    // Modify time scale with minus/plus
                    case #char "-";
                        modify_delta_time_multiplier(0.5);
                    case 43 /* equals-plus */;
                        modify_delta_time_multiplier(2.0);

                    }
                }
        }
    }

    process_input_events(*inspiration_board, Input.events_this_frame);

    #if OS == .MACOS && !SINGLE_BINARY {
        dropped_file: string;
        while peel_take_dropped_file(*dropped_file) {
            log("Inspiration DnD: app polled host dropped file '%'", dropped_file);
            inspiration_board_note_dropped_file(dropped_file);
            // @Leak: `peel_take_dropped_file` currently returns a string allocated while executing
            // in the host runtime service context, so freeing it from the DLL side trips Basic's
            // allocator ownership checks. Keep it alive for now until the drop-file handoff uses
            // a shared allocator or an explicit host-side release callback.
            dropped_file = "";
        }
    }

    #if OS == .MACOS && !SINGLE_BINARY {
        if peel_take_quit_requested() {
            app_quit_requested = true;
        }
    }

    if app_should_render_ui() {
        using,only(GetCurrentContext, GetIO) ImGui_Text_Input :: #import "ImGui";
        if GetCurrentContext() != null {
            io := GetIO();
            for Input.events_this_frame {
                if it.type == .TEXT_INPUT {
                    io.AddInputCharacter(io, it.utf32);
                }
            }
        }
    }

    if reload_on_frame > 0 && frame_count == reload_on_frame {
        log("PEEL_RELOAD_ON_FRAME triggering reload at frame %.", frame_count);
        update_ctx.app_return_flags |= .Reload;
        reload_on_frame = 0; // one-shot trigger
    }

    if app_quit_requested {
        update_ctx.app_return_flags |= .Quit;
        return;
    }

    {
        call_event_functions(.tick);

        // tick shader reload
        {
            did_rebuild, swapped_all, rebuild_ok := SHR.shader_hot_reload_tick(*shader_reload_ctx, cast(s64)frame_count);
            sgpu_set_debug_status(SHR.shader_hot_reload_status_line(*shader_reload_ctx));
            if did_rebuild && !rebuild_ok {
                log_error("SHADER_RELOAD build failed; keeping current runtime shaders.");
            } else if did_rebuild && !swapped_all {
                log_error("SHADER_RELOAD build succeeded but pipeline swap was partial.");
            }
            if snapshot.enabled && did_rebuild && rebuild_ok {
                snapshot.after_pending = true;
                snapshot.after_min_frame = cast(s64) frame_count + 1;
            }
        }

        #if READBACK_ENABLED {
            swapchain_image := gpu_current_swapchain_view();
            if swapchain_image == 0 {
                log_error("Error: READBACK_ENABLED but no gpu_current_swapchain_view()");
            } else {
                per_frame_debug(*readback_stats, cast(s64)frame_count, swapchain_image);
                if snapshot.enabled && frame_count >= 2 {
                    if !snapshot.before_done {
                        readback_stats_dump_snapshot(*readback_stats, swapchain_image, cast(s64) frame_count, tprint("%_shader_reload_before", APP_NAME), APP_NAME);
                        snapshot.before_done = true;
                    } else if snapshot.after_pending && !snapshot.after_done && cast(s64) frame_count >= snapshot.after_min_frame {
                        readback_stats_dump_snapshot(*readback_stats, swapchain_image, cast(s64) frame_count, tprint("%_shader_reload_after", APP_NAME), APP_NAME);
                        snapshot.after_done = true;
                        app_quit_requested = true;
                    }
                }
            }
        }
    }

    if app_browser_requested_app.count != 0 {
        update_ctx.app_return_flags |= .Build_And_Load_App;
        update_ctx.app_return_data.build_app = app_browser_requested_app;
        app_browser_requested_app = "";
    }

    if startup_load_app_target.count != 0 && frame_count >= startup_load_app_frame {
        log("PEEL_LOAD_APP_AFTER_STARTUP requesting app '%' at frame %.", startup_load_app_target, frame_count);
        update_ctx.app_return_flags |= .Load_App;
        update_ctx.app_return_data.load_app = startup_load_app_target;
        startup_load_app_target = "";
    }

    if max_frames > 0 && frame_count > max_frames {
        perf_capture_finish_and_check();
        log("Hit max frame count (%), exiting.", max_frames);
        update_ctx.app_return_flags |= .Quit;
        return;
    }
}

ui_wants_keyboard :: () -> bool {
    if !app_should_render_ui() return false;
    using,only(GetCurrentContext, GetIO) _ :: #import "ImGui";
    if GetCurrentContext() != null {
        io := GetIO();
        return io.WantCaptureKeyboard || io.WantTextInput;
    }
    return false;
}

create_window_and_init_sgpu :: () {
    #if OS == .MACOS {
        #if SINGLE_BINARY {
            window = create_metal_window(2500, 2000, "", window_delegate_hack_callback=single_binary_macos_window_delegate_init);
            ensure_macos_window_frontmost(window);
        } else {
            assert(window != null, "host_init: expected host-owned macOS window.");
            assert(mtl_device != null, "host_init: expected host-owned Metal device.");
            ensure_macos_window_frontmost(cast(*NSWindow) window);
        }
    } else {
        window = create_window(2500, 2000, "hello peel");
    }
    result := gpu_init();
    assert(result == .SUCCESS);
    gpu_init_swapchain(xx window);


    #if OS == .MACOS {
        // HACK to make sure the window appears before we begin gpu stuff, which may cause it not to raise.
        // there's probably a better fix for this!
        ensure_macos_window_frontmost(cast(*NSWindow) window);
        Input.update_window_events();
        app_window_focus_initialized = false;
        app_window_has_focus = false;
        app_window_unfocused_streak = 0;
        app_window_occlusion_initialized = false;
        app_window_is_occluded = false;
        app_window_was_occluded = false;
        mini_mode_note_window_occluded(window_is_occluded(cast(*NSWindow) window));
        _, _, initial_w, initial_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
        if dims_ok {
            last_window_size = .{xx initial_w, xx initial_h};
        } else {
            last_window_size = .{};
        }
    }
}

host_quit :: (quit_ctx: Quit_Ctx) {
    #if !RELEASE { // let OS do cleanup for us in release mode.

        main_queue := gpu_get_queue(.MAIN, 0); // TODO: we probably want to wait for other queues too, once we're using them.
        gpu_queue_wait_idle(main_queue);

        #if OS == .MACOS {
            init_all_objective_c_selector_structs();
        }
        gpu_destroy_swapchain();
        gpu_shutdown();
        if sgpu_debug_status.count != 0 {
            free(sgpu_debug_status);
            sgpu_debug_status = "";
        }

        if !quit_ctx.keep_window_device_and_sdl {
            #if OS != .MACOS {
            window = null;
            }
        }
    }
}

host_init :: (init_ctx: Init_Ctx) -> bool {
    #if !RELEASE && OS == .MACOS {
        using,only(setenv) POSIX :: #import "POSIX";
        if perf_gpu_validation_enabled() {
            setenv("MTL_LOG_TO_STDERR", "1", 1);
            setenv("MTL_DEBUG_LAYER", "1", 1);
            setenv("MTL_LOG_LEVEL", "MTLLogLevelDebug", 1);
            setenv("MTL_LOG_BUFFER_SIZE", "2048", 1);
        }
    }

    max_frames = init_ctx.max_frames;
    reload_on_frame = 0;
    env_reload_on_frame, did_parse_reload_on_frame := Env_Vars.try_parse_env_int("PEEL_RELOAD_ON_FRAME");
    if did_parse_reload_on_frame {
        if env_reload_on_frame > 0 {
            reload_on_frame = cast(int) env_reload_on_frame;
        } else {
            log_error("PEEL_RELOAD_ON_FRAME must be > 0; got %.", env_reload_on_frame);
        }
    }
    perf_capture_cpu_ms_sum = 0;
    perf_capture_gpu_ms_sum = 0;
    perf_capture_count = 0;
    perf_capture_gpu_count = 0;
    perf_capture_reported = false;
    app_ui_enabled = true;
    app_browser_open = false;
    app_browser_requested_app = "";
    host_build_target = "";
    host_build_error = "";
    host_build_state = .NONE;
    startup_load_app_target = "";
    startup_load_app_frame = 0;
    snapshot = {};
    env_reload_snapshot_mode, did_parse_reload_snapshot_mode := Env_Vars.try_parse_env_int("PEEL_SHADER_RELOAD_SNAPSHOT");
    if did_parse_reload_snapshot_mode {
        snapshot.enabled = env_reload_snapshot_mode > 0;
    }

    env_disable_ui, did_parse_disable_ui := Env_Vars.try_parse_env_int("PEEL_DISABLE_UI");
    if did_parse_disable_ui {
        app_ui_enabled = env_disable_ui <= 0;
    }

    #if !SINGLE_BINARY {
        using,only(getenv) POSIX_Getenv :: #import "POSIX";
        startup_load_app_c := POSIX_Getenv.getenv("PEEL_LOAD_APP_AFTER_STARTUP");
        if startup_load_app_c != null {
            requested_app := to_string(startup_load_app_c);
            if requested_app != APP_STEM {
                startup_load_app_target = copy_string(requested_app);
                startup_load_app_frame = 5;
                log("PEEL_LOAD_APP_AFTER_STARTUP armed for '%' at frame %.", startup_load_app_target, startup_load_app_frame);
            }
        }
    }

    if init_ctx.runtime.window != null {
        window = init_ctx.runtime.window;
    }
    #if OS == .MACOS {
        if init_ctx.runtime.gfx_device != null {
            mtl_device = cast(*MTLDevice) init_ctx.runtime.gfx_device;
        }
        #if !SINGLE_BINARY {
        macos_runtime_services_init(init_ctx.runtime.services);
        }
    }
    #if OS == {
        case .WINDOWS;
            #if !RELEASE {
                map_debug_output_to_stderr();
                enable_d3d12_debug_layer();
            }
        case .MACOS;
            init_all_objective_c_selector_structs();
    }

    last_time = seconds_since_init();

    create_window_and_init_sgpu();

    #if READBACK_ENABLED {
        frame_debug_init(*readback_stats);
        if snapshot.enabled {
            gpu_set_swapchain_framebuffer_only(false);
        }
    }

    if !init_ctx.keep_window_device_and_sdl && !doing_peel_diagnostic() {
        wait_for_initial_focus_before_dll_init();
    }

    SHR.shader_hot_reload_init_auto(*shader_reload_ctx,
        app_source_file = APP_NAME,
        poll_every_frames = 15,
        log_prefix = "SHADER_RELOAD",
        enabled_by_default = !RELEASE || snapshot.enabled,
        use_background_thread = false,
    );

    call_event_functions(.dll_init);

    return true;
}

dummy_on_resize :: () {  } @on_window_resize
shader_reload_on_ui :: () { SHR.shader_hot_reload_imgui(*shader_reload_ctx, ui_get_monospace_font()); } @on_ui

input_down :: inline ($s: string) -> (down: bool, pressed: bool)
#modify { return s.count == 1; }
{
    down, pressed := input_down(cast(Input.Key_Code)s[0]);
    return down, pressed;
}

input_down :: inline (code: Input.Key_Code) -> (down: bool, pressed: bool) {
    return (Input.input_button_states[code] & .DOWN) != 0, (Input.input_button_states[code] & .START) != 0;
}

input_pressed :: inline (code: Input.Key_Code) -> bool {
    return (Input.input_button_states[code] & .START) != 0;
}

#scope_file

app_should_render_ui :: () -> bool {
    return app_ui_enabled;
}

app_assign_host_build_status :: (state: App_Update_Ctx.Host_Build_State, target: string, error: string) {
    host_build_state = state;
    assign_string(*host_build_target, target);
    assign_string(*host_build_error, error);
    if state != .FAILED && host_build_error.count != 0 {
        free(host_build_error);
        host_build_error = "";
    }
}

assign_string :: (dst: *string, src: string) {
    if dst.*.count != 0 {
        free(dst.*);
        dst.* = "";
    }
    if src.count != 0 dst.* = copy_string(src);
}

#if OS == .MACOS && SINGLE_BINARY {
single_binary_macos_window_delegate_init :: () { }
}

wait_for_initial_focus_before_dll_init :: () {
    #if OS != .MACOS return;
    if !window return;

    STARTUP_FOCUS_WAIT_MAX_MS :: 4000;
    STARTUP_FOCUS_WAIT_STEP_MS :: 10;

    attempts := STARTUP_FOCUS_WAIT_MAX_MS / STARTUP_FOCUS_WAIT_STEP_MS;
    for i: 0..attempts-1 {
        Input.update_window_events();
        if window_has_focus(cast(*NSWindow) window) {
            app_window_focus_initialized = true;
            app_window_has_focus = true;
            app_window_unfocused_streak = 0;
            return;
        }

        if i % 20 == 0 ensure_macos_window_frontmost(window);
        sleep_milliseconds(STARTUP_FOCUS_WAIT_STEP_MS);
    }

    log_error("Initial focus wait timed out after %ms; continuing app init.", STARTUP_FOCUS_WAIT_MAX_MS);
}


perf_capture_finish_and_check :: () {
    if perf_capture_reported return;
    perf_capture_reported = true;
    if max_frames <= 0 return;
    if max_frames < PERF_CAPTURE_END_FRAME return;
    if perf_capture_count <= 0 return;

    avg_cpu_ms := cast(float) (perf_capture_cpu_ms_sum / cast(float64) perf_capture_count);
    avg_fps := 1000.0 / max(avg_cpu_ms, 0.0001);
    if perf_capture_gpu_count > 0 {
        avg_gpu_ms := cast(float) (perf_capture_gpu_ms_sum / cast(float64) perf_capture_gpu_count);
        log("PERF_AVG frames=%..% cpu_ms=% gpu_ms=% fps=%",
            PERF_CAPTURE_START_FRAME, PERF_CAPTURE_END_FRAME, avg_cpu_ms, avg_gpu_ms, avg_fps);
    } else {
        log("PERF_AVG frames=%..% cpu_ms=% fps=%",
            PERF_CAPTURE_START_FRAME, PERF_CAPTURE_END_FRAME, avg_cpu_ms, avg_fps);
    }

    assert(avg_fps >= PERF_CAPTURE_MIN_FPS,
        tprint("Performance regression: avg fps % is below threshold % (frames %..%).",
            avg_fps, PERF_CAPTURE_MIN_FPS, PERF_CAPTURE_START_FRAME, PERF_CAPTURE_END_FRAME));
}

perf_gpu_validation_enabled :: () -> bool {
    #if OS != .MACOS return true;
    using,only(getenv) POSIX :: #import "POSIX";
    v := getenv("PEEL_GPU_VALIDATION");
    if v == null return true;
    if v[0] == #char "0" return false;
    return true;
}

#if OS == .WINDOWS  #import "Windows_Utils";
else #if OS == .MACOS #import "MacOS_Tools";
#import "General_Utils";
Input :: #import "Input";
WT :: #import "Window_Type";
#scope_export
Window_Type :: WT.Window_Type;
#if OS == .MACOS {
    #import "Objective_C";
    #import "Objective_C/AppKit";
    #import "Metal";
    #import "Objective_C_Tools";
    init_all_objective_c_selector_structs :: () {
        init_objective_c();
        init_app_kit();
        init_core_graphics_runtime_constants();
        init_metal();
        init_objective_c_tools();
    }
    #if SINGLE_BINARY {
        set_window_title :: NSWindow.setTitle;
        window_has_focus :: (window: *NSWindow) -> bool {
            if !window || !NSApp return false;
            return NSApplication.keyWindow(NSApp) == window || NSApplication.mainWindow(NSApp) == window;
        }
    }

    backend_metal_window_did_resize :: (window: *NSWindow, width: s32, height: s32) {
        _ = width;
        _ = height;
        content_view := NSWindow.contentView(window);
        bounds := NSView.bounds(content_view);
        r := NSView.convertRectToBacking(content_view, bounds);
        layer := metal_layer(window);
        layer.setDrawableSize(layer, r.size);
        window.display(window);
        call_event_functions(.window_resize);
    }

    metal_layer :: (window: *NSWindow) -> *CAMetalLayer {
        content_view := NSWindow.contentView(window);
        // TODO: on debug builds, check that it's actually an instance of CAMetalLayer.
        return cast(*CAMetalLayer)content_view.layer(content_view);
    }

    #if LIVE_RELOAD_ENABLED {
    #scope_export
    reload_stdlib :: () {
    } @on_reload

    dll_unload :: () {
    } @on_unload
    }
}

perf_capture :: (cpu_frame_ms: float, gpu_frame_ms: float) {
    if frame_count >= PERF_CAPTURE_START_FRAME && frame_count <= PERF_CAPTURE_END_FRAME {
        perf_capture_cpu_ms_sum += cpu_frame_ms;
        perf_capture_count += 1;
        if gpu_frame_ms >= 0.0 {
            perf_capture_gpu_ms_sum += gpu_frame_ms;
            perf_capture_gpu_count += 1;
        }
    }
}

using,except(Viewport) _ :: #import "sgpu"()(SLANG_COMPILER=false);
#load "App_Common.jai";
#load "ui/ui.jai";
#scope_file
#load "measure_fps.jai";
#load "readback_stats.jai";
#load "mini_mode.jai";
#if OS != .MACOS #import "Window_Creation";
#if OS == .MACOS {
    #if SINGLE_BINARY {
        #load "Metal_Window_Creation.jai";
    } else {
        #load "Peel_MacOS_Runtime.jai";
    }
}
Env_Vars :: #import "Env_Vars";
SHR :: #import,file "shader_hot_reload.jai";
#load "GPU_Tools.jai";
#load "inspiration_board.jai";
#if !SINGLE_BINARY {
    #load "app_list.jai";
    #load "ui/app_browser.jai";
}
#if #exists(TRACY_PROFILER_ENABLED) {
    #if TRACY_PROFILER_ENABLED {
        Tracy :: #import "Tracy"(IMPORT_MODE=.CLIENT);
    }
}

toggle_all_ui :: () {
    app_ui_enabled = !app_ui_enabled;
    if !app_ui_enabled {
        app_browser_open = false;
        ui_cancel_pending_frame(*current_ui_render_frame);
    }
}

modify_delta_time_multiplier :: (factor: float) {
    time_scale *= factor;
    if abs(time_scale - 1.0) < 0.000001 {
        time_scale = 1.0;
    }
    report_replace("time_scale = %", delta_time_multiplier);
}

String :: #import "String";
