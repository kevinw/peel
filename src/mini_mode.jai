//
// App enters a "mini mode" when it becomes occluded, which makes it smaller
// and moves it to the corner of the screen, for live reload during development.
//

MINI_MODE_ENABLE_ON :: enum {
    Unfocus;
    Occluded;
}

MINI_MODE_ENABLE_ON_DEFAULT     :: MINI_MODE_ENABLE_ON.Occluded;
MINI_MODE_ENABLED               :: !RELEASE;
MINI_MODE_MAX_SIZE_PX           :: 1300;
MINI_MODE_MARGIN_PX             :: 16;
MINI_MODE_UNFOCUS_STREAK_FRAMES :: 1;

app_window_focus_initialized := false;
app_window_has_focus := false;
app_window_unfocused_streak: int = 0;
app_window_occlusion_initialized := false;
app_window_is_occluded := false;
app_window_was_occluded := false;
app_mini_mode_active := false;

handle_focus_transition_after_input_update :: () {
    #if OS != .MACOS return;
    #if !MINI_MODE_ENABLED return;
    if !window return;

    mini_mode_note_window_occluded(window_is_occluded(cast(*NSWindow) window));

    if !mini_mode_allowed_now() {
        if app_mini_mode_active exit_mini_mode_window();
        app_window_unfocused_streak = 0;
        app_window_has_focus = window_has_focus(cast(*NSWindow) window);
        app_window_was_occluded = app_window_is_occluded;
        return;
    }

    focus_now := window_has_focus(cast(*NSWindow) window);

    if !app_window_focus_initialized {
        app_window_focus_initialized = true;
        app_window_has_focus = focus_now;
        app_window_unfocused_streak = 0;
        return;
    }

    if focus_now {
        app_window_unfocused_streak = 0;
        app_window_has_focus = true;
        if app_mini_mode_active exit_mini_mode_window();
        return;
    }

    app_window_has_focus = false;

    if MINI_MODE_ENABLE_ON_DEFAULT != .Occluded return;
    if !app_window_occlusion_initialized return;
    if !app_window_is_occluded {
        app_window_was_occluded = false;
        return;
    }
    if app_window_was_occluded return;

    app_window_was_occluded = true;
    enter_mini_mode_window();
}

mini_mode_note_window_occluded :: (occluded: bool) {
    #if OS != .MACOS return;
    #if !MINI_MODE_ENABLED return;

    if !app_window_occlusion_initialized {
        app_window_occlusion_initialized = true;
        app_window_is_occluded = occluded;
        app_window_was_occluded = occluded;
        return;
    }

    app_window_is_occluded = occluded;
    if !occluded app_window_was_occluded = false;
}


#if OS == .MACOS {

    enter_mini_mode_window :: () {
        #if !MINI_MODE_ENABLED return;
        if !window return;
        if app_mini_mode_active return;
        if doing_peel_diagnostic() return;

        ns_window := cast(*NSWindow) window;
        saved_window.frame = NSWindow.frame(ns_window);
        saved_window.level = NSWindow.level(ns_window);
        saved_window.style_mask = NSWindow.styleMask(ns_window);
        saved_window.state_valid = true;

        screen := window_screen(ns_window);
        if !screen screen = NSScreen.mainScreen();
        if !screen return;

        pixels_to_points_factor := cast(CGFloat) 1 / NSScreen.backingScaleFactor(screen);
        mini_size := mini_mode_size_for_saved_window(saved_window.frame.size, pixels_to_points_factor);
        margin := cast(CGFloat) MINI_MODE_MARGIN_PX * pixels_to_points_factor;

        NSWindow.setContentSize(ns_window, mini_size);

        screen_frame := NSScreen.frame(screen);
        frame := NSWindow.frame(ns_window);
        target_x := screen_frame.origin.x + screen_frame.size.width - frame.size.width - margin;
        target_y := screen_frame.origin.y + screen_frame.size.height - frame.size.height - margin;
        NSWindow.setFrameOrigin(ns_window, .{ target_x, target_y });

        NSWindow.setStyleMask(ns_window, NSWindowStyleMaskBorderless);

        frame_countdown = 15;
        app_mini_mode_active = true;
    }

    mini_mode_tick :: () {
        if frame_countdown <= 0 return;
        if doing_peel_diagnostic() return;

        frame_countdown -= 1;
        if frame_countdown == 0 {
            ns_window := cast(*NSWindow) window;
            NSWindow.setLevel(ns_window, cast(NSWindowLevel) kCGFloatingWindowLevel);
            NSWindow.orderFront(ns_window, null);
        }
    } @on_tick

    exit_mini_mode_window :: () {
        frame_countdown = 0;
        #if !MINI_MODE_ENABLED return;
        if !window return;
        if !app_mini_mode_active return;

        ns_window := cast(*NSWindow) window;
        if saved_window.state_valid {
            NSWindow.setStyleMask(ns_window, saved_window.style_mask);
            NSWindow.setFrame    (ns_window, saved_window.frame, YES);
            NSWindow.setLevel    (ns_window, saved_window.level);
        } else {
            NSWindow.setStyleMask(ns_window,
                NSWindowStyleMaskTitled |
                NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable |
                NSWindowStyleMaskResizable);
            NSWindow.setLevel(ns_window, cast(NSWindowLevel) kCGNormalWindowLevel);
        }

        app_mini_mode_active = false;
    }

}

#scope_file
Input :: #import "Input";

mini_mode_allowed_now :: () -> bool {
    if snapshot.enabled return false;
    if doing_peel_diagnostic() return false;

    #if READBACK_ENABLED {
        if readback_stats_needs_swapchain_readback(*readback_stats) return false;
    }

    if doing_peel_diagnostic() return false;

    return true;
}


#if OS == .MACOS {
    mini_mode_size_for_saved_window :: (window_size: NSSize, pixels_to_points_factor: CGFloat) -> NSSize {
        max_w := cast(CGFloat) MINI_MODE_MAX_SIZE_PX * pixels_to_points_factor;
        max_h := cast(CGFloat) MINI_MODE_MAX_SIZE_PX * pixels_to_points_factor;

        source_w := window_size.width;
        source_h := window_size.height;
        if source_w <= 0 || source_h <= 0 {
            return .{ max_w, max_h };
        }

        scale := min(max_w / source_w, max_h / source_h);
        scale = min(scale, cast(CGFloat) 1.0);

        return .{
            source_w * scale,
            source_h * scale,
        };
    }

    window_screen :: (window: *NSWindow) -> *NSScreen {
        if !window return null;
        get_screen: (*void, Selector) -> *NSScreen #c_call;
        get_screen = xx objc_msgSend;
        return get_screen(window, selector("screen"));
    }
    saved_window: struct {
        frame: NSRect = ---;
        level: NSWindowLevel = 0;
        style_mask: NSWindowStyleMask = 0;
        state_valid := false;

    }
}

frame_countdown := 0;
