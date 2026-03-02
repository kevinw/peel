//
// App enters a "mini mode" when it loses focus, which makes it smaller and
// moves it to the corner of the screen, for live reload during development.
//

MINI_MODE_WIDTH_PX  :: 1152;
MINI_MODE_HEIGHT_PX :: 648;
MINI_MODE_MARGIN_PX :: 16;
MINI_MODE_UNFOCUS_STREAK_FRAMES :: 1;

app_window_focus_initialized := false;
app_window_has_focus := false;
app_window_unfocused_streak: int = 0;
app_mini_mode_active := false;
#if OS == .MACOS {
    macos_window_focus_hooks_installed := false;
}

handle_focus_transition_after_input_update :: () {
    #if OS != .MACOS return;
    if !window return;

    focus_now := Input.input_application_has_focus;

    if !app_window_focus_initialized {
        app_window_focus_initialized = true;
        app_window_has_focus = focus_now;
        app_window_unfocused_streak = 0;
        return;
    }

    if focus_now {
        app_window_unfocused_streak = 0;
        if app_window_has_focus return;
        app_window_has_focus = true;
        exit_mini_mode_window();
        return;
    }


    if !app_window_has_focus return;

    app_window_unfocused_streak += 1;
    if app_window_unfocused_streak < MINI_MODE_UNFOCUS_STREAK_FRAMES return;

    app_window_has_focus = false;
    log("calling enter_mini_mode");
    enter_mini_mode_window();
}


#if OS == .MACOS {

    enter_mini_mode_window :: () {
        if !window return;
        if app_mini_mode_active return;

        ns_window := cast(*NSWindow) window;
        saved_window.frame = NSWindow.frame(ns_window);
        saved_window.level = NSWindow.level(ns_window);
        saved_window.style_mask = NSWindow.styleMask(ns_window);
        saved_window.state_valid = true;

        screen := window_screen(ns_window);
        if !screen screen = NSScreen.mainScreen();
        if !screen return;

        pixels_to_points_factor := cast(CGFloat) 1 / NSScreen.backingScaleFactor(screen);
        mini_w := cast(CGFloat) MINI_MODE_WIDTH_PX * pixels_to_points_factor;
        mini_h := cast(CGFloat) MINI_MODE_HEIGHT_PX * pixels_to_points_factor;
        margin := cast(CGFloat) MINI_MODE_MARGIN_PX * pixels_to_points_factor;

        NSWindow.setContentSize(ns_window, .{ mini_w, mini_h });

        screen_frame := NSScreen.frame(screen);
        frame := NSWindow.frame(ns_window);
        target_x := screen_frame.origin.x + screen_frame.size.width - frame.size.width - margin;
        target_y := screen_frame.origin.y + screen_frame.size.height - frame.size.height - margin;
        NSWindow.setFrameOrigin(ns_window, .{ target_x, target_y });

        NSWindow.setLevel(ns_window, cast(NSWindowLevel) kCGFloatingWindowLevel);
        NSWindow.setStyleMask(ns_window, NSWindowStyleMaskBorderless);
        NSWindow.orderFront(ns_window, null);
        app_mini_mode_active = true;
    }

    exit_mini_mode_window :: () {
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

    window_screen :: (window: *NSWindow) -> *NSScreen {
        if !window return null;
        get_screen: (*void, Selector) -> *NSScreen #c_call;
        get_screen = xx objc_msgSend;
        return get_screen(window, selector("screen"));
    }
}

#scope_file
Input :: #import "Input";

#if OS == .MACOS {
    saved_window: struct {
        frame: NSRect = ---;
        level: NSWindowLevel = 0;
        style_mask: NSWindowStyleMask = 0;
        state_valid := false;

    }
}
