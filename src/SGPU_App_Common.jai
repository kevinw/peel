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
ui_timeline_value: u64 = 0;
shader_reload_ctx: SHR.Shader_Hot_Reload;
max_frames: int = 0;
reload_on_frame: int = 0;
pending_objc_reinit_after_reload := false;
perf_capture_cpu_ms_sum: float64 = 0;
perf_capture_gpu_ms_sum: float64 = 0;
perf_capture_count: s64 = 0;
perf_capture_gpu_count: s64 = 0;
perf_capture_reported := false;
shader_reload_snapshot_mode := false;
shader_reload_snapshot_before_done := false;
shader_reload_snapshot_after_pending := false;
shader_reload_snapshot_after_done := false;
shader_reload_snapshot_after_min_frame: s64 = 0;

PERF_CAPTURE_START_FRAME :: 5;
PERF_CAPTURE_END_FRAME :: 30;
PERF_CAPTURE_MIN_FPS :: 10.0;
#if READBACK_ENABLED {
    readback_stats: Readback_Stats;
}

using,except(Viewport) _ :: #import "sgpu"()(SLANG_COMPILER=false);

AB_Buffer :: struct($T: Type) {
    a_cpu: *T;
    b_cpu: *T;
    a_gpu: Gpu_Ptr;
    b_gpu: Gpu_Ptr;
    src_is_a: bool;
}

ab_buffer_src_cpu :: (buffer: *AB_Buffer($T)) -> *T #expand {
    if buffer.src_is_a return buffer.a_cpu;
    return buffer.b_cpu;
}

ab_buffer_dst_cpu :: (buffer: *AB_Buffer($T)) -> *T #expand {
    if buffer.src_is_a return buffer.b_cpu;
    return buffer.a_cpu;
}

ab_buffer_src_gpu :: (buffer: *AB_Buffer($T)) -> Gpu_Ptr #expand {
    if buffer.src_is_a return buffer.a_gpu;
    return buffer.b_gpu;
}

ab_buffer_dst_gpu :: (buffer: *AB_Buffer($T)) -> Gpu_Ptr #expand {
    if buffer.src_is_a return buffer.b_gpu;
    return buffer.a_gpu;
}

ab_buffer_advance :: (buffer: *AB_Buffer($T)) #expand {
    buffer.src_is_a = !buffer.src_is_a;
}

sgpu_frame_ring_index :: (frame_number: s64 = -1) -> s64 {
    if frame_number < 0 frame_number = cast(s64) gpu_submission_frame_index();
    idx := frame_number % SGPU_FRAMES_IN_FLIGHT;
    if idx < 0 idx += SGPU_FRAMES_IN_FLIGHT;
    return idx;
}

sgpu_arena_alloc_frame_ring :: (arena: *Gpu_Arena, $T: Type, min_alignment: s64 = 16) -> (*[SGPU_FRAMES_IN_FLIGHT] T, Gpu_Ptr) {
    cpu_ring, gpu_ring := gpu_arena_alloc(arena, [SGPU_FRAMES_IN_FLIGHT] T, min_alignment);
    return cpu_ring, gpu_ring;
}

sgpu_frame_ring_cpu_slot :: (ring: *[SGPU_FRAMES_IN_FLIGHT] $T, frame_number: s64 = -1) -> *T #expand {
    idx := sgpu_frame_ring_index(frame_number);
    return cast(*T) ring + idx;
}

sgpu_frame_ring_gpu_slot :: (ring_base_gpu: Gpu_Ptr, $T: Type, frame_number: s64 = -1) -> Gpu_Ptr #expand {
    idx := sgpu_frame_ring_index(frame_number);
    return ring_base_gpu + (idx * size_of(T)).(Gpu_Ptr);
}

gpu_begin_scoped_render_pass :: (cmd_buf: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc) #expand {
    gpu_begin_render_pass(cmd_buf, desc);
    `defer gpu_end_render_pass(cmd_buf);
}

sgpu_set_debug_status :: (status: string) {
    if sgpu_debug_status == status return;
    if sgpu_debug_status.count != 0 {
        free(sgpu_debug_status);
        sgpu_debug_status = "";
    }
    if status.count != 0 sgpu_debug_status = copy_string(status);
}

submit_and_present_with_ui :: (cmd_buff: Gpu_Command_Buffer) {
    //
    // interleave metal and metal4 here. todo: we can go back to a more normal
    // "flow" once we make a Metal4 imgui backend.
    //
    app_done_value := ui_timeline_value + 1;
    ui_done_value  := ui_timeline_value + 2;
    ui_semaphore   := ui_get_sync_semaphore();
    assert(ui_semaphore != 0, "UI sync semaphore not initialized.");

    gpu_submit_swapchain_no_present(cmd_buff, signals=.[.{ui_semaphore, app_done_value}]);

    ui_render(app_done_value, ui_done_value, current_ui_render_frame);
    current_ui_render_frame = {};

    gpu_present_current_swapchain(waits=.[.{ui_semaphore, ui_done_value}]);

    ui_timeline_value = ui_done_value;
}

app_swapchain_acquire :: () -> Gpu_Result, Gpu_Texture_View {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if swapchain_image != 0 {
        current_ui_render_frame = ui_render_pre();
    }
    return result, swapchain_image;
}

app_update :: (update_ctx: *App_Update_Ctx) {
    auto_release_temp();

    #if OS == .MACOS {
        if pending_objc_reinit_after_reload {
            init_all_objective_c_selector_structs();
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
    if frame_count >= PERF_CAPTURE_START_FRAME && frame_count <= PERF_CAPTURE_END_FRAME {
        perf_capture_cpu_ms_sum += cpu_frame_ms;
        perf_capture_count += 1;
        if gpu_frame_ms >= 0.0 {
            perf_capture_gpu_ms_sum += gpu_frame_ms;
            perf_capture_gpu_count += 1;
        }
    }

    Input.update_window_events();
    for Input.get_window_resizes() {
        if it.window == window {
            gpu_swapchain_resize();
        }
    }

    for Input.events_this_frame {
        using it;
        if type == {
            case .QUIT;
                app_quit_requested = true;
            case .KEYBOARD;
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
            if shader_reload_snapshot_mode && did_rebuild && rebuild_ok {
                shader_reload_snapshot_after_pending = true;
                shader_reload_snapshot_after_min_frame = cast(s64) frame_count + 1;
            }
        }

        #if READBACK_ENABLED {
            swapchain_image := gpu_current_swapchain_view();
            if swapchain_image == 0 {
                log_error("Error: READBACK_ENABLED but no gpu_current_swapchain_view()");
            } else {
                per_frame_debug(*readback_stats, cast(s64)frame_count, swapchain_image);
                if shader_reload_snapshot_mode && frame_count >= 2 {
                    if !shader_reload_snapshot_before_done {
                        readback_stats_dump_snapshot(*readback_stats, swapchain_image, cast(s64) frame_count, tprint("%_shader_reload_before", APP_NAME), APP_NAME);
                        shader_reload_snapshot_before_done = true;
                    } else if shader_reload_snapshot_after_pending && !shader_reload_snapshot_after_done && cast(s64) frame_count >= shader_reload_snapshot_after_min_frame {
                        readback_stats_dump_snapshot(*readback_stats, swapchain_image, cast(s64) frame_count, tprint("%_shader_reload_after", APP_NAME), APP_NAME);
                        shader_reload_snapshot_after_done = true;
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

create_window_and_init_sgpu :: () {
    #if OS == .MACOS {
        window = create_metal_window(2500, 2000, "hello peel");
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
    }
}

host_quit :: (quit_ctx: Quit_Ctx) {
    #if !RELEASE { // let OS do cleanup for us in release mode.
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
    shader_reload_snapshot_mode = false;
    shader_reload_snapshot_before_done = false;
    shader_reload_snapshot_after_pending = false;
    shader_reload_snapshot_after_done = false;
    shader_reload_snapshot_after_min_frame = 0;
    env_reload_snapshot_mode, did_parse_reload_snapshot_mode := Env_Vars.try_parse_env_int("PEEL_SHADER_RELOAD_SNAPSHOT");
    if did_parse_reload_snapshot_mode {
        shader_reload_snapshot_mode = env_reload_snapshot_mode > 0;
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
        if shader_reload_snapshot_mode {
            gpu_set_swapchain_framebuffer_only(false);
        }
    }

    SHR.shader_hot_reload_init_auto(*shader_reload_ctx,
        app_source_file = APP_NAME,
        poll_every_frames = 15,
        log_prefix = "SHADER_RELOAD",
        enabled_by_default = !RELEASE || shader_reload_snapshot_mode);

    call_event_functions(.dll_init);

    return true;
}

dummy_on_resize :: () {  } @on_window_resize
shader_reload_on_ui :: () { SHR.shader_hot_reload_imgui(*shader_reload_ctx, ui_get_monospace_font()); } @on_ui

#scope_file

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
    } @on_reload

    dll_unload :: () {
        // This is a hack to get live reloading working with Jai's Input module's NSApplication and NSWindow delegates.
        if window NSWindow.setDelegate(window, null);
        NSApplication.setDelegate(NSApp, null);

        remove_old_objc_class("App_Delegate");
        remove_old_objc_class("Window_Delegate");
    } @on_unload
    }


    #scope_file
    remove_old_objc_class :: (name: *u8) {
        old_class := objc_getClass(name);
        if old_class {
            objc_disposeClassPair(old_class);
        }
    }
}

#load "App_Common.jai";
#load "ui.jai";
#scope_file
#load "measure_fps.jai";
#load "readback_stats.jai";
#if OS != .MACOS #import "Window_Creation";
#if OS == .MACOS #load "Metal_Window_Creation.jai";
String :: #import "String";
Env_Vars :: #import "Env_Vars";
SHR :: #import,file "shader_hot_reload.jai";
