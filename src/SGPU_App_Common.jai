READBACK_ENABLED :: !RELEASE;

#if READBACK_ENABLED {
    readback_stats: Readback_Stats;
}

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

#import "sgpu"()(SLANG_COMPILER=false);

SGPU_FRAMES_IN_FLIGHT :: 3;

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

app_update :: (update_ctx: *App_Update_Ctx) {
    auto_release_temp();

    #if OS == .MACOS {
        pool := objc_new(NSAutoreleasePool);
        defer release(pool);
    }

    time = seconds_since_init();
    dt = cast(float)(time - last_time);
    last_time = time;

    #if !RELEASE {
        if window && frame_count % 10 == 0 {
            mem_text := human_readable_bytes(current_memory_usage_bytes(),, temp);
            title := mem_text;
            if sgpu_debug_status.count != 0 {
                title = tprint("% | %", mem_text, sgpu_debug_status);
            }
            set_window_title(window, title);
        }
    }

    frame_count += 1;

    Input.update_window_events();
    for Input.get_window_resizes() {
        if it.window == window {
            gpu_swapchain_resize();
        }
    }
    for Input.events_this_frame {
        if it.type == {
            case .QUIT;
                app_quit_requested = true;
            case .KEYBOARD;
                if it.key_code == #char "R" {
                    update_ctx.app_return_flags |= .Reload;
                }
        }
    }
    if app_quit_requested {
        update_ctx.app_return_flags |= .Quit;
        return;
    }

    {
        call_event_functions(.tick);
        #if READBACK_ENABLED {
            swapchain_image := gpu_current_swapchain_view();
            if swapchain_image == 0 {
                log_error("Error: READBACK_ENABLED but no gpu_current_swapchain_view()");
            } else {
                per_frame_debug(*readback_stats, cast(s64)frame_count, swapchain_image);
            }
        }
    }

    if max_frames > 0 && frame_count > max_frames {
        log("Hit max frame count (%), exiting.", max_frames);
        update_ctx.app_return_flags |= .Quit;
        return;
    }
}

create_window_and_init_sgpu :: () {
    window = create_window(2000, 1500, "hello peel");
    result := gpu_init();
    assert(result == .SUCCESS);
    gpu_init_swapchain(xx window);
}

host_quit :: (quit_ctx: Quit_Ctx) {
    #if !RELEASE { // let OS do cleanup for us in release mode.
        gpu_destroy_swapchain();
        gpu_shutdown();
        if sgpu_debug_status.count != 0 {
            free(sgpu_debug_status);
            sgpu_debug_status = "";
        }
    }
}

max_frames: int = 0;

host_init :: (init_ctx: Init_Ctx) -> bool {
    #if !RELEASE && OS == .MACOS {
        using,only(setenv) POSIX :: #import "POSIX";
        setenv("MTL_LOG_TO_STDERR", "1", 1);
        setenv("MTL_DEBUG_LAYER", "1", 1);
        setenv("MTL_LOG_LEVEL", "MTLLogLevelDebug", 1);
        setenv("MTL_LOG_BUFFER_SIZE", "2048", 1);
    }

    max_frames = init_ctx.max_frames;
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

    #if READBACK_ENABLED frame_debug_init(*readback_stats);
    call_event_functions(.dll_init);

    return true;
}

dummy_on_resize :: () {  } @on_window_resize

#scope_file
#if OS == .WINDOWS  #import "Windows_Utils";
else #if OS == .MACOS #import "MacOS_Tools";
#import "General_Utils";
Input :: #import "Input";
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
        r := NSRect.{ .{0, 0}, .{ xx width, xx height }};
        r = window.convertRectToBacking(window, .{.{0, 0}, .{xx width, xx height}});
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
}

#load "App_Common.jai";
#scope_file
#load "readback_stats.jai";
#import "Window_Creation";
