#load "App_Common.jai";

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

#import "sgpu"()(SLANG_COMPILER=false);

gpu_begin_scoped_render_pass :: (cmd_buf: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc) #expand {
    gpu_begin_render_pass(cmd_buf, desc);
    `defer gpu_end_render_pass(cmd_buf);
}

app_update :: (update_ctx: *App_Update_Ctx) {
    auto_release_temp();

    #if OS == .MACOS {
        pool := objc_init(objc_alloc(NSAutoreleasePool));
        defer release(pool);
    }

    time = seconds_since_init();
    dt = cast(float)(time - last_time);
    last_time = time;

    #if !RELEASE {
        if window && frame_count % (60 * 3) == 0 {
            title := human_readable_bytes(current_memory_usage_bytes(),, temp);
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

    call_event_functions(.tick);

    if max_frames > 0 && frame_count > max_frames {
        log("Hit max frame count (%), exiting.", max_frames);
        update_ctx.app_return_flags |= .Quit;
        return;
    }
}

create_window_and_init_sgpu :: () {
    width :s32 = 1600;
    height :s32 = 1000;

    window = create_window(width, height, "hello peel");

    result := gpu_init();
    assert(result == .SUCCESS);

    window_type: Native_Window_Type;
    #if      OS == .WINDOWS then window_type = .WIN32;
    else #if OS == .LINUX   then window_type = .X11;
    else #if OS == .MACOS   then window_type = .COCOA;
    else assert(false, "Unsupported OS");

    gpu_init_swapchain(cast(u64)window, window_type);
}

host_quit :: (quit_ctx: Quit_Ctx) {
    // @Perf probably not necessary in release builds.
    gpu_destroy_swapchain();
    gpu_shutdown();
}

max_frames: int = 0;

host_init :: (init_ctx: Init_Ctx) -> bool {
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
