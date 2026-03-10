READBACK_ENABLED :: !RELEASE;
SGPU_FRAMES_IN_FLIGHT :: 3;
LIVE_RELOAD_ENABLED :: !RELEASE;

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

last_window_size: V2(u32);
window: *void; // TODO
sgpu_debug_status: string;

shader_reload_ctx: SHR.Shader_Hot_Reload;
max_frames: int;
reload_on_frame: int;
pending_objc_reinit_after_reload := false;
perf_capture_cpu_ms_sum: float64;
perf_capture_gpu_ms_sum: float64;
perf_capture_count: s64;
perf_capture_gpu_count: s64;
perf_capture_reported := false;
app_ui_enabled := true;

snapshot: struct {
    enabled := false;
    before_done := false;
    after_pending := false;
    after_done := false;
    after_min_frame: s64 = 0;
}

#if OS == .MACOS {
    macos_window_focus_hooks_installed := false;
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

    #if OS == .MACOS {
        if pending_objc_reinit_after_reload {
            init_all_objective_c_selector_structs();
            install_macos_window_focus_hooks();
            if NSApp {
                NSApplication.setDelegate(NSApp, context._macos_create_app_delegate());
            }
            if window {
                NSWindow.setDelegate(window, context._macos_create_window_delegate());
            }
            pending_objc_reinit_after_reload = false;
        }
        pool := objc_new(NSAutoreleasePool);
        defer release(pool);
    }

    time = seconds_since_init();
    dt = cast(float)(time - last_time);
    editor_dt = dt;
    last_time = time;
    cpu_frame_ms := dt * 1000.0;
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
    for Input.get_window_resizes() {
        if it.window == window {
            gpu_swapchain_resize();
        }
    }

    ui_has_keyboard := ui_wants_keyboard();
    for Input.events_this_frame {
        using it;
        if type == {
            case .QUIT;
                app_quit_requested = true;
            case .KEYBOARD;
                if key_code == .F1 && key_pressed {
                    app_ui_enabled = !app_ui_enabled;
                    if !app_ui_enabled ui_cancel_pending_frame(*current_ui_render_frame);
                    continue;
                }

                if ui_has_keyboard continue;

                if key_code == #char "R" && key_pressed {
                    update_ctx.app_return_flags |= .Reload;
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
        window = create_metal_window(2500, 2000, "", window_delegate_hack_callback=install_macos_window_focus_hooks);
        ensure_macos_window_frontmost(window);
    } else {
        window = create_window(2500, 2000, "hello peel");
    }
    result := gpu_init();
    assert(result == .SUCCESS);
    gpu_init_swapchain(xx window);


    #if OS == .MACOS {
        // HACK to make sure the window appears before we begin gpu stuff, which may cause it not to raise.
        // there's probably a better fix for this!
        ensure_macos_window_frontmost(window);
        Input.update_window_events();
        app_window_focus_initialized = false;
        app_window_has_focus = false;
        app_window_unfocused_streak = 0;
        app_window_occlusion_initialized = false;
        app_window_is_occluded = false;
        app_window_was_occluded = false;
        mini_mode_note_window_occluded(window_is_occluded(cast(*NSWindow) window));
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
    snapshot = {};
    env_reload_snapshot_mode, did_parse_reload_snapshot_mode := Env_Vars.try_parse_env_int("PEEL_SHADER_RELOAD_SNAPSHOT");
    if did_parse_reload_snapshot_mode {
        snapshot.enabled = env_reload_snapshot_mode > 0;
    }

    env_disable_ui, did_parse_disable_ui := Env_Vars.try_parse_env_int("PEEL_DISABLE_UI");
    if did_parse_disable_ui {
        app_ui_enabled = env_disable_ui <= 0;
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

    wait_for_initial_focus_before_dll_init();

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

#scope_file

app_should_render_ui :: () -> bool {
    return app_ui_enabled;
}

wait_for_initial_focus_before_dll_init :: () {
    #if OS != .MACOS return;
    if !window return;

    STARTUP_FOCUS_WAIT_MAX_MS :: 4000;
    STARTUP_FOCUS_WAIT_STEP_MS :: 10;

    attempts := STARTUP_FOCUS_WAIT_MAX_MS / STARTUP_FOCUS_WAIT_STEP_MS;
    for i: 0..attempts-1 {
        Input.update_window_events();
        if Input.input_application_has_focus {
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
    set_window_title :: NSWindow.setTitle;

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
        pending_objc_reinit_after_reload = true;
        macos_window_focus_hooks_installed = false;
    } @on_reload

    dll_unload :: () {
        // This is a hack to get live reloading working with Jai's Input module's NSApplication and NSWindow delegates.
        if window NSWindow.setDelegate(window, null);
        NSApplication.setDelegate(NSApp, null);
        macos_window_focus_hooks_installed = false;

        remove_old_objc_class("App_Delegate");
        remove_old_objc_class("Window_Delegate");
    } @on_unload
    }


    #scope_file
    Window_Delegate_Focus_Hooks :: struct {
        using #as nsobject: NSObject;

        windowDidBecomeKey :: (using self: *Window_Delegate_Focus_Hooks, _sel: Selector, notification: *NSNotification) #c_call {
            _ = self;
            _ = notification;
            Input.input_application_has_focus = true;
        } @selector(windowDidBecomeKey:)

        windowDidResignKey :: (using self: *Window_Delegate_Focus_Hooks, _sel: Selector, notification: *NSNotification) #c_call {
            _ = self;
            _ = notification;
            if NSApp {
                key_window := NSApplication.keyWindow(NSApp);
                main_window := NSApplication.mainWindow(NSApp);
                Input.input_application_has_focus = key_window != null || main_window != null;
            } else {
                Input.input_application_has_focus = false;
            }
        } @selector(windowDidResignKey:)

        windowDidChangeOcclusionState :: (using self: *Window_Delegate_Focus_Hooks, _sel: Selector, notification: *NSNotification) #c_call {
            push_context {
                _ = self;
                ns_window := cast(*NSWindow) notification.object(notification);
                if ns_window == window {
                    is_occluded := window_is_occluded(ns_window);
                    mini_mode_note_window_occluded(is_occluded);
                }
            }
        } @selector(windowDidChangeOcclusionState:)
    }

    install_macos_window_focus_hooks :: () {
        if macos_window_focus_hooks_installed return;
        wd_class := objc_getClass("Window_Delegate");
        if !wd_class return;
        using Window_Delegate_Focus_Hooks;
        objc_add_instance_method(wd_class, windowDidBecomeKey, "windowDidBecomeKey:");
        objc_add_instance_method(wd_class, windowDidResignKey, "windowDidResignKey:");
        objc_add_instance_method(wd_class, windowDidChangeOcclusionState, "windowDidChangeOcclusionState:");
        macos_window_focus_hooks_installed = true;
    }

    remove_old_objc_class :: (name: *u8) {
        old_class := objc_getClass(name);
        if old_class {
            objc_disposeClassPair(old_class);
        }
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
#if OS == .MACOS #load "Metal_Window_Creation.jai";
String :: #import "String";
Env_Vars :: #import "Env_Vars";
SHR :: #import,file "shader_hot_reload.jai";
#load "GPU_Tools.jai";
