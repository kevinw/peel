
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

app_update :: (update_ctx: *App_Update_Ctx) {
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
            #if OS == .MACOS {
                backend_metal_window_did_resize(window, it.width, it.height);
            }
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
    reset_temporary_storage();
}

host_quit :: (quit_ctx: Quit_Ctx) {
    log("host_quit!");
}

host_init :: (init_ctx: Init_Ctx) -> bool {
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
    call_event_functions(.dll_init);
    return true;
}

#scope_file
#if OS == .WINDOWS  #import "Windows_Utils";
else #if OS == .MACOS #import "MacOS_Tools";
#import "General_Utils";
Input :: #import "Input";
