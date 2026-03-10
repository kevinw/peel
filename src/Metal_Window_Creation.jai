#if OS == .MACOS {
    ObjC :: #import "Objective_C";
    sgpu_macos_application_initialized := false;
    sgpu_macos_activation_pumped := false;
    peel_input_view_class: ObjC.Class;

    peel_input_view_accepts_first_responder :: (self: *NSView, _cmd: Selector) -> BOOL #c_call {
        _ = self; _ = _cmd;
        return YES;
    }

    peel_input_view_key_down :: (self: *NSView, _cmd: Selector, event: *NSEvent) #c_call {
        _ = self; _ = _cmd;
        if !event return;

        push_context {
            if ImGui.GetCurrentContext() != null {
                io := ImGui.GetIO();
                if io.WantTextInput {
                    chars := NSEvent.characters(event);
                    if chars != null && NSString.length(chars) > 0 {
                        utf8 := NSString.UTF8String(chars);
                        if utf8 != null {
                            io.AddInputCharactersUTF8(io, utf8);
                        }
                    }
                }
            }
        }
    }

    ensure_peel_input_view_class :: () -> ObjC.Class {
        if peel_input_view_class return peel_input_view_class;

        existing := ObjC.objc_getClass("PeelInputViewV2");
        if existing {
            peel_input_view_class = existing;
            return existing;
        }

        super := ObjC.objc_getClass("NSView");
        assert(super != null, "NSView class not found.");

        cls := ObjC.objc_allocateClassPair(super, "PeelInputViewV2", 0);
        assert(cls != null, "Failed to allocate PeelInputView class.");

        ObjC.objc_add_instance_method(cls, peel_input_view_accepts_first_responder, "acceptsFirstResponder");
        ObjC.objc_add_instance_method(cls, peel_input_view_key_down, "keyDown:");
        ObjC.objc_finalize_class(cls);

        peel_input_view_class = cls;
        return cls;
    }

    set_nsview_layer :: (view: *NSView, layer: *CALayer) {
        set_layer: (*void, Selector, *CALayer) -> void #c_call;
        set_layer = xx objc_msgSend;
        set_layer(view, selector("setLayer:"), layer);
    }

    set_nswindow_background_black :: (window: *NSWindow) {
        if !window return;

        nscolor_class := objc_getClass("NSColor");
        if !nscolor_class return;

        get_black_color: (*void, Selector) -> *void #c_call;
        get_black_color = xx objc_msgSend;
        black_color := get_black_color(nscolor_class, selector("blackColor"));
        if !black_color return;

        set_bg_color: (*void, Selector, *void) -> void #c_call;
        set_bg_color = xx objc_msgSend;
        set_bg_color(window, selector("setBackgroundColor:"), black_color);

        set_opaque: (*void, Selector, BOOL) -> void #c_call;
        set_opaque = xx objc_msgSend;
        set_opaque(window, selector("setOpaque:"), YES);
    }

    set_metal_layer_background_black :: (metal_layer: *void) {
        if !metal_layer return;

        nscolor_class := objc_getClass("NSColor");
        if !nscolor_class return;

        get_black_color: (*void, Selector) -> *void #c_call;
        get_black_color = xx objc_msgSend;
        black_color := get_black_color(nscolor_class, selector("blackColor"));
        if !black_color return;

        get_cg_color: (*void, Selector) -> *void #c_call;
        get_cg_color = xx objc_msgSend;
        cg_black := get_cg_color(black_color, selector("CGColor"));
        if !cg_black return;

        set_bg_color: (*void, Selector, *void) -> void #c_call;
        set_bg_color = xx objc_msgSend;
        set_bg_color(metal_layer, selector("setBackgroundColor:"), cg_black);

        set_opaque: (*void, Selector, BOOL) -> void #c_call;
        set_opaque = xx objc_msgSend;
        set_opaque(metal_layer, selector("setOpaque:"), YES);
    }

    init_macos_app_for_sgpu :: () {
        if sgpu_macos_application_initialized return;

        init_all_objective_c_selector_structs();
        NSApplication.sharedApplication();

        dg := context._macos_create_app_delegate();
        NSApplication.setDelegate(NSApp, dg);

        menu_bar := objc_init(objc_alloc(NSMenu));
        autorelease(menu_bar);
        NSApp.setMainMenu(NSApp, menu_bar);

        S :: NSString.getTempString;

        app_menu_item := menu_bar.addItemWithTitle(menu_bar, S(""), null, S(""));
        autorelease(app_menu_item);

        app_menu := objc_init(objc_alloc(NSMenu));
        autorelease(app_menu);

        fullscreen_item := app_menu.addItemWithTitle(app_menu, S("Enter Full Screen"), selector("toggleFullScreen:"), S("f"));
        NSMenuItem.setKeyEquivalentModifierMask(fullscreen_item, NSEventModifierFlagControl | NSEventModifierFlagCommand);
        app_menu.addItemWithTitle(app_menu, S("Quit"), selector("terminate:"), S("q"));
        app_menu_item.setSubmenu(app_menu_item, app_menu);

        NSApplication.setAppleMenu(NSApp, app_menu);
        NSApplication.finishLaunching(NSApp);
        NSApplication.setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);
        NSApplication.activateIgnoringOtherApps(NSApp, YES);

        sgpu_macos_application_initialized = true;
    }

    #scope_export
    ensure_macos_window_frontmost :: (window: *NSWindow) {
        if !NSApp || !window return;

        NSApplication.setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);
        NSApplication.activateIgnoringOtherApps(NSApp, YES);
        NSWindow.makeKeyAndOrderFront(window, null);
        NSWindow.orderFront(window, null);
    }

    create_metal_window :: (width: int, height: int, window_name: string, window_x := -1, window_y := -1, window_delegate_hack_callback: ()) -> *NSWindow {
        init_macos_app_for_sgpu();

        // On macOS window geometry is in points, while we want pixel-sized inputs.
        target_screen := NSScreen.mainScreen();
        pixels_to_points_factor := cast(CGFloat) 1 / NSScreen.backingScaleFactor(target_screen);
        target_frame: NSRect = ---;
        target_frame.origin = .{ xx window_x * pixels_to_points_factor, xx window_y * pixels_to_points_factor };
        target_frame.size = .{ xx width * pixels_to_points_factor, xx height * pixels_to_points_factor };

        window := NSWindow.initWithContentRect(objc_alloc(NSWindow), target_frame,
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered, NO, target_screen);
        autorelease(window);
        NSWindow.setReleasedWhenClosed(window, NO);
        NSWindow.setTitle(window, window_name);

        // HACK: create a delegate, so the class lives in Objective C's runtime.
        // then install our special focus/occlusion methods on it via the callback.
        wd := context._macos_create_window_delegate();
        window_delegate_hack_callback();

        NSWindow.setDelegate(window, wd);
        NSWindow.setCollectionBehavior(window, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged);
        set_nswindow_background_black(window);

        input_view_class := ensure_peel_input_view_class();
        view := cast(*NSView) objc_init(objc_alloc(input_view_class));
        NSView.setWantsLayer(view, YES);
        autorelease(view);

        metal_layer_class := objc_getClass("CAMetalLayer");
        assert(metal_layer_class != null, "CAMetalLayer class not found.");
        metal_layer := objc_init(objc_alloc(metal_layer_class));
        assert(metal_layer != null, "Failed to create CAMetalLayer.");
        autorelease(metal_layer);
        set_metal_layer_background_black(metal_layer);
        set_nsview_layer(view, cast(*CALayer) metal_layer);

        NSWindow.setContentView(window, view);
        NSWindow.makeFirstResponder(window, view);
        NSWindow.makeKeyAndOrderFront(window, null);

        if window_x == -1 && window_y == -1 {
            NSWindow.center(window);
        }

        // Keep a hard activation pass here for terminal-launched + heavy-startup apps.
        ensure_macos_window_frontmost(window);
        sgpu_macos_activation_pumped = true;
        mini_mode_note_window_occluded(window_is_occluded(window));

        return window;
    }

    #scope_export
    get_mouse_pointer_position :: (window: *NSWindow, right_handed: bool) -> x: int, y: int, success: bool {
        pt := NSWindow.mouseLocationOutsideOfEventStream(window);

        view := NSWindow.contentView(window);
        backing_pt := NSView.convertPointToBacking(view, pt);

        if !right_handed {
            frame := NSView.frame(view);
            fb := NSView.convertRectToBacking(view, frame);
            backing_pt.y = fb.size.height - backing_pt.y;
        }

        return cast(int) backing_pt.x, cast(int) backing_pt.y, true;
    }

    get_mouse_pointer_position :: inline (right_handed := false) -> x: int, y: int, success: bool {
        if !NSApp return 0, 0, false;

        win := NSApplication.keyWindow(NSApp);
        if !win win = NSApplication.mainWindow(NSApp);
        if !win return 0, 0, false;

        x, y, success := get_mouse_pointer_position(win, right_handed);
        return x, y, success;
    }

    #scope_export
    get_dimensions :: (window: Window_Type, right_handed: bool) -> (x: s32, y: s32, width: s32, height: s32, success := true) {
        view := NSWindow.contentView(window);
        frame := NSView.frame(view);
        fb := NSView.convertRectToBacking(view, frame);

        y := ifx right_handed then fb.origin.y + fb.size.height else fb.origin.y;
        return cast(s32) fb.origin.x, cast(s32) y, cast(s32) fb.size.width, cast(s32) fb.size.height;
    }

    window_is_occluded :: (window: *NSWindow) -> bool {
        if !window return false;
        get_occlusion_state: (*void, Selector) -> NSUInteger #c_call;
        get_occlusion_state = xx objc_msgSend;
        NSWindowOcclusionStateVisible :: cast(NSUInteger) 1 << 1;
        occlusion_state := get_occlusion_state(window, selector("occlusionState"));
        return (occlusion_state & NSWindowOcclusionStateVisible) == 0;
    }
}

ImGui :: #import "ImGui";
