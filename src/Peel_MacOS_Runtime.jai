#if OS != .MACOS return;

ObjC :: #import "Objective_C";
#import "Objective_C/AppKit";
#import "Metal";
#import "Objective_C_Tools";
#import "Host_App_Common";
String :: #import "String";

#if PEEL_MACOS_RUNTIME_OWNER {
    peel_host_application_initialized := false;
    peel_host_input_view_class: ObjC.Class;
    peel_host_input_view_superclass: ObjC.Class;
    peel_host_custom_cursor_handling := false;
    peel_host_quit_requested := false;
    peel_host_dropped_files: [..]string;

    peel_host_input_view_accepts_first_responder :: (self: *NSView, _cmd: Selector) -> BOOL #c_call {
        _ = self; _ = _cmd;
        return YES;
    }

    peel_host_input_view_key_down :: (self: *NSView, _cmd: Selector, event: *NSEvent) #c_call {
        _ = self;
        _ = _cmd;
        _ = event;
    }

    peel_host_input_view_reset_cursor_rects :: (self: *NSView, _cmd: Selector) #c_call {
        if peel_host_custom_cursor_handling return;

        super_call := ObjC.objc_super.{receiver = self, class = peel_host_input_view_superclass};
        reset_cursor_rects: (*ObjC.objc_super, Selector) -> void #c_call;
        reset_cursor_rects = xx ObjC.objc_msgSendSuper;
        reset_cursor_rects(*super_call, _cmd);
    }

    peel_host_input_view_cursor_update :: (self: *NSView, _cmd: Selector, event: *NSEvent) #c_call {
        if peel_host_custom_cursor_handling return;

        super_call := ObjC.objc_super.{receiver = self, class = peel_host_input_view_superclass};
        cursor_update: (*ObjC.objc_super, Selector, *NSEvent) -> void #c_call;
        cursor_update = xx ObjC.objc_msgSendSuper;
        cursor_update(*super_call, _cmd, event);
    }

    peel_host_input_view_dragging_entered :: (self: *NSView, _cmd: Selector, sender: id) -> NSDragOperation #c_call {
        _ = self; _ = _cmd;
        mask := NSDraggingInfo.draggingSourceOperationMask(sender);
        return mask & NSDragOperationGeneric;
    }

    peel_host_input_view_dragging_updated :: (self: *NSView, _cmd: Selector, sender: id) -> NSDragOperation #c_call {
        _ = self; _ = _cmd;
        mask := NSDraggingInfo.draggingSourceOperationMask(sender);
        return mask & NSDragOperationGeneric;
    }

    peel_host_input_view_wants_periodic_dragging_updates :: (self: *NSView, _cmd: Selector) -> BOOL #c_call {
        _ = self; _ = _cmd;
        return NO;
    }

    peel_host_input_view_prepare_for_drag_operation :: (self: *NSView, _cmd: Selector, sender: id) -> BOOL #c_call {
        _ = self; _ = _cmd; _ = sender;
        return YES;
    }

    peel_host_input_view_perform_drag_operation :: (self: *NSView, _cmd: Selector, sender: id) -> BOOL #c_call {
        _ = self; _ = _cmd;
        ctx: #Context;
        push_context,defer_pop ctx;
        log("Inspiration DnD: host performDragOperation");
        pasteboard := NSDraggingInfo.draggingPasteboard(sender);
        classes := NSArray(Class).arrayWithObject(class(NSURL));
        file_urls := NSPasteboard.readObjectsForClasses(pasteboard, classes, null, *NSURL);
        if file_urls == null return NO;
        num_urls := cast(s64) file_urls.count(file_urls);
        if num_urls <= 0 return NO;
        log("Inspiration DnD: host drop count=%", num_urls);

        for i: 0..num_urls-1 {
            url := file_urls.objectAtIndex(file_urls, xx i);
            objc_file_path := NSURL.path(url);
            file_path := to_string(objc_file_path);
            log("Inspiration DnD: host path '%'", file_path);
            if file_path array_add(*peel_host_dropped_files, copy_string(file_path));
        }
        return YES;
    }

    ensure_peel_host_input_view_class :: () -> ObjC.Class {
        if peel_host_input_view_class return peel_host_input_view_class;

        existing := ObjC.objc_getClass("PeelHostInputView");
        if existing {
            peel_host_input_view_class = existing;
            return existing;
        }

        super := ObjC.objc_getClass("NSView");
        assert(super != null, "NSView class not found.");
        peel_host_input_view_superclass = super;

        cls := ObjC.objc_allocateClassPair(super, "PeelHostInputView", 0);
        assert(cls != null, "Failed to allocate PeelHostInputView class.");

        ObjC.objc_add_instance_method(cls, peel_host_input_view_accepts_first_responder, "acceptsFirstResponder");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_key_down, "keyDown:");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_reset_cursor_rects, "resetCursorRects");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_cursor_update, "cursorUpdate:");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_dragging_entered, "draggingEntered:");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_dragging_updated, "draggingUpdated:");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_wants_periodic_dragging_updates, "wantsPeriodicDraggingUpdates");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_prepare_for_drag_operation, "prepareForDragOperation:");
        ObjC.objc_add_instance_method(cls, peel_host_input_view_perform_drag_operation, "performDragOperation:");
        ObjC.objc_finalize_class(cls);

        peel_host_input_view_class = cls;
        return cls;
    }

    Peel_Host_App_Delegate :: struct {
        using #as nsobject: NSObject;

        applicationShouldTerminate :: (using self: *Peel_Host_App_Delegate, _sel: Selector, sender: id) -> NSApplicationTerminateReply #c_call {
            _ = self;
            _ = sender;
            peel_host_quit_requested = true;
            return NSTerminateCancel;
        } @selector(applicationShouldTerminate:)

        applicationDidFinishLaunching :: (using self: *Peel_Host_App_Delegate, _sel: Selector, app: *NSApplication) #c_call {
            _ = self;
            _ = _sel;
            _ = app;
            NSApplication.setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);
            NSApplication.activateIgnoringOtherApps(NSApp, YES);
            NSApp.stop(NSApp, null);
        } @selector(applicationDidFinishLaunching:)
    }

    Peel_Host_Window_Delegate :: struct {
        using #as nsobject: NSObject;

        windowShouldClose :: (using self: *Peel_Host_Window_Delegate, _sel: Selector, sender: *NSWindow) -> BOOL #c_call {
            _ = self;
            _ = _sel;
            _ = sender;
            peel_host_quit_requested = true;
            return NO;
        } @selector(windowShouldClose:)
    }

    create_host_app_delegate :: () -> *Peel_Host_App_Delegate {
        existing := ObjC.objc_getClass("PeelHostAppDelegate");
        if !existing {
            cls := ObjC.objc_allocateClassPair(ObjC.objc_getClass("NSObject"), "PeelHostAppDelegate", 0);
            assert(cls != null, "Failed to allocate PeelHostAppDelegate.");
            using Peel_Host_App_Delegate;
            ObjC.objc_add_instance_method(cls, applicationShouldTerminate, "applicationShouldTerminate:");
            ObjC.objc_add_instance_method(cls, applicationDidFinishLaunching, "applicationDidFinishLaunching:");
            ObjC.objc_finalize_class(cls);
        }
        return cast(*Peel_Host_App_Delegate) objc_init(objc_alloc(ObjC.objc_getClass("PeelHostAppDelegate")));
    }

    create_host_window_delegate :: () -> *Peel_Host_Window_Delegate {
        existing := ObjC.objc_getClass("PeelHostWindowDelegate");
        if !existing {
            cls := ObjC.objc_allocateClassPair(ObjC.objc_getClass("NSObject"), "PeelHostWindowDelegate", 0);
            assert(cls != null, "Failed to allocate PeelHostWindowDelegate.");
            using Peel_Host_Window_Delegate;
            ObjC.objc_add_instance_method(cls, windowShouldClose, "windowShouldClose:");
            ObjC.objc_finalize_class(cls);
        }
        return cast(*Peel_Host_Window_Delegate) objc_init(objc_alloc(ObjC.objc_getClass("PeelHostWindowDelegate")));
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

    init_macos_app_runtime :: () {
        if peel_host_application_initialized return;

        NSApplication.sharedApplication();
        NSApplication.setDelegate(NSApp, cast(*NSApplicationDelegate) create_host_app_delegate());

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

        peel_host_application_initialized = true;
    }

    make_host_metal_content_view :: () -> *NSView {
        view_class := ensure_peel_host_input_view_class();
        view := cast(*NSView) objc_init(objc_alloc(view_class));
        NSView.setWantsLayer(view, YES);
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(view, types);
        autorelease(view);

        metal_layer_class := objc_getClass("CAMetalLayer");
        assert(metal_layer_class != null, "CAMetalLayer class not found.");
        metal_layer := objc_init(objc_alloc(metal_layer_class));
        assert(metal_layer != null, "Failed to create CAMetalLayer.");
        autorelease(metal_layer);
        set_metal_layer_background_black(metal_layer);
        set_nsview_layer(view, cast(*CALayer) metal_layer);

        return view;
    }

    host_set_window_title :: (window_ptr: *void, title: string) {
        if !window_ptr return;
        NSWindow.setTitle(cast(*NSWindow) window_ptr, title);
    }

    host_get_dimensions :: (window_ptr: *void, right_handed: bool) -> MacOS_Runtime_Dimensions {
        result: MacOS_Runtime_Dimensions;
        if !window_ptr return result;

        view := NSWindow.contentView(cast(*NSWindow) window_ptr);
        frame := NSView.frame(view);
        fb := NSView.convertRectToBacking(view, frame);

        result.success = true;
        result.x = cast(s32) fb.origin.x;
        result.y = ifx right_handed then cast(s32) (fb.origin.y + fb.size.height) else cast(s32) fb.origin.y;
        result.width = cast(s32) fb.size.width;
        result.height = cast(s32) fb.size.height;
        return result;
    }

    host_get_mouse_pointer_position :: (window_ptr: *void, right_handed: bool) -> MacOS_Runtime_Mouse_Position {
        result: MacOS_Runtime_Mouse_Position;
        if !window_ptr return result;

        window := cast(*NSWindow) window_ptr;
        pt := NSWindow.mouseLocationOutsideOfEventStream(window);
        view := NSWindow.contentView(window);
        backing_pt := NSView.convertPointToBacking(view, pt);

        if !right_handed {
            frame := NSView.frame(view);
            fb := NSView.convertRectToBacking(view, frame);
            backing_pt.y = fb.size.height - backing_pt.y;
        }

        result.success = true;
        result.x = cast(int) backing_pt.x;
        result.y = cast(int) backing_pt.y;
        return result;
    }

    host_window_is_occluded :: (window_ptr: *void) -> bool {
        if !window_ptr return false;
        get_occlusion_state: (*void, Selector) -> NSUInteger #c_call;
        get_occlusion_state = xx objc_msgSend;
        NSWindowOcclusionStateVisible :: cast(NSUInteger) 1 << 1;
        occlusion_state := get_occlusion_state(window_ptr, sel_registerName2("occlusionState"));
        return (occlusion_state & NSWindowOcclusionStateVisible) == 0;
    }

    host_window_has_focus :: (window_ptr: *void) -> bool {
        if !window_ptr || !NSApp return false;
        window := cast(*NSWindow) window_ptr;
        return NSApplication.keyWindow(NSApp) == window || NSApplication.mainWindow(NSApp) == window;
    }

    host_take_quit_requested :: () -> bool {
        was_requested := peel_host_quit_requested;
        peel_host_quit_requested = false;
        return was_requested;
    }

    host_take_dropped_file :: (out_path: *string) -> bool {
        if peel_host_dropped_files.count <= 0 return false;
        host_owned_path := peel_host_dropped_files[0];
        out_path.* = copy_string(host_owned_path);
        array_ordered_remove_by_index(*peel_host_dropped_files, 0);
        if host_owned_path.count != 0 free(host_owned_path);
        log("Inspiration DnD: host take dropped file '%', remaining=%", out_path.*, peel_host_dropped_files.count);
        return true;
    }

    host_set_custom_cursor_handling :: (window_ptr: *void, enabled: bool) {
        peel_host_custom_cursor_handling = enabled;

        if !window_ptr return;
        ns_window := cast(*NSWindow) window_ptr;
        view := NSWindow.contentView(ns_window);
        if !view return;

        invalidate_cursor_rects: (*void, Selector, *NSView) -> void #c_call;
        invalidate_cursor_rects = xx objc_msgSend;
        invalidate_cursor_rects(ns_window, sel_registerName2("invalidateCursorRectsForView:"), view);
    }

    host_ensure_window_frontmost :: (window_ptr: *void) {
        if !window_ptr || !NSApp return;
        window := cast(*NSWindow) window_ptr;
        NSApplication.setActivationPolicy(NSApp, NSApplicationActivationPolicyRegular);
        NSApplication.activateIgnoringOtherApps(NSApp, YES);
        NSWindow.makeKeyAndOrderFront(window, null);
        NSWindow.orderFront(window, null);
    }

    #scope_export
    host_macos_runtime_init :: (width: int, height: int, window_name: string) -> Host_Runtime_Ptrs {
        init_objective_c();
        init_app_kit();
        init_core_graphics_runtime_constants();
        init_metal();
        init_objective_c_tools();
        init_macos_app_runtime();

        target_screen := NSScreen.mainScreen();
        pixels_to_points_factor := cast(CGFloat) 1 / NSScreen.backingScaleFactor(target_screen);
        target_frame: NSRect = ---;
        target_frame.origin = .{0, 0};
        target_frame.size = .{xx width * pixels_to_points_factor, xx height * pixels_to_points_factor};

        window := NSWindow.initWithContentRect(objc_alloc(NSWindow), target_frame,
            NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable,
            NSBackingStoreBuffered, NO, target_screen);
        autorelease(window);
        NSWindow.setReleasedWhenClosed(window, NO);
        NSWindow.setTitle(window, window_name);
        NSWindow.setDelegate(window, cast(*NSObject) create_host_window_delegate());
        NSWindow.setCollectionBehavior(window, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged);
        set_nswindow_background_black(window);

        view := make_host_metal_content_view();
        NSWindow.setContentView(window, view);
        NSWindow.makeFirstResponder(window, view);
        NSWindow.makeKeyAndOrderFront(window, null);
        NSWindow.center(window);
        host_ensure_window_frontmost(window);

        runtime: Host_Runtime_Ptrs;
        runtime.window = window;
        runtime.gfx_device = MTLCreateSystemDefaultDevice();
        assert(runtime.gfx_device != null, "host_macos_runtime_init: MTLCreateSystemDefaultDevice returned null.");
        runtime.services = .{
            set_window_title = xx host_set_window_title,
            get_dimensions = xx host_get_dimensions,
            get_mouse_pointer_position = xx host_get_mouse_pointer_position,
            window_is_occluded = xx host_window_is_occluded,
            window_has_focus = xx host_window_has_focus,
            take_quit_requested = xx host_take_quit_requested,
            take_dropped_file = xx host_take_dropped_file,
            set_custom_cursor_handling = xx host_set_custom_cursor_handling,
            ensure_window_frontmost = xx host_ensure_window_frontmost,
        };
        return runtime;
    }
} else {
    host_runtime_services: MacOS_Runtime_Services;

    #scope_export
    macos_runtime_services_init :: (services: MacOS_Runtime_Services) {
        host_runtime_services = services;
    }

    #scope_export
    set_window_title :: (window: *void, title: string) {
        assert(host_runtime_services.set_window_title != null, "set_window_title: host runtime service is missing.");
        fn := cast((*void, string) -> void) host_runtime_services.set_window_title;
        fn(window, title);
    }

    #scope_export
    get_dimensions :: (window: Window_Type, right_handed: bool) -> (x: s32, y: s32, width: s32, height: s32, success := true) {
        assert(host_runtime_services.get_dimensions != null, "get_dimensions: host runtime service is missing.");
        fn := cast((*void, bool) -> MacOS_Runtime_Dimensions) host_runtime_services.get_dimensions;
        dims := fn(window, right_handed);
        return dims.x, dims.y, dims.width, dims.height, dims.success;
    }

    #scope_export
    get_mouse_pointer_position :: (window: *NSWindow, right_handed: bool) -> x: int, y: int, success: bool {
        assert(host_runtime_services.get_mouse_pointer_position != null, "get_mouse_pointer_position: host runtime service is missing.");
        fn := cast((*void, bool) -> MacOS_Runtime_Mouse_Position) host_runtime_services.get_mouse_pointer_position;
        pos := fn(window, right_handed);
        return pos.x, pos.y, pos.success;
    }

    #scope_export
    get_mouse_pointer_position :: inline (right_handed := false) -> x: int, y: int, success: bool {
        if !window return 0, 0, false;
        x, y, success := get_mouse_pointer_position(cast(*NSWindow) window, right_handed);
        return x, y, success;
    }

    #scope_export
    window_is_occluded :: (window: *NSWindow) -> bool {
        assert(host_runtime_services.window_is_occluded != null, "window_is_occluded: host runtime service is missing.");
        fn := cast((*void) -> bool) host_runtime_services.window_is_occluded;
        return fn(window);
    }

    #scope_export
    window_has_focus :: (window: *NSWindow) -> bool {
        assert(host_runtime_services.window_has_focus != null, "window_has_focus: host runtime service is missing.");
        fn := cast((*void) -> bool) host_runtime_services.window_has_focus;
        return fn(window);
    }

    #scope_export
    peel_take_quit_requested :: () -> bool {
        assert(host_runtime_services.take_quit_requested != null, "peel_take_quit_requested: host runtime service is missing.");
        fn := cast(() -> bool) host_runtime_services.take_quit_requested;
        return fn();
    }

    #scope_export
    peel_take_dropped_file :: (out_path: *string) -> bool {
        assert(host_runtime_services.take_dropped_file != null, "peel_take_dropped_file: host runtime service is missing.");
        fn := cast((*string) -> bool) host_runtime_services.take_dropped_file;
        return fn(out_path);
    }

    #scope_export
    peel_set_custom_cursor_handling :: (enabled: bool) {
        assert(host_runtime_services.set_custom_cursor_handling != null, "peel_set_custom_cursor_handling: host runtime service is missing.");
        fn := cast((*void, bool) -> void) host_runtime_services.set_custom_cursor_handling;
        fn(window, enabled);
    }

    #scope_export
    ensure_macos_window_frontmost :: (window: *NSWindow) {
        assert(host_runtime_services.ensure_window_frontmost != null, "ensure_macos_window_frontmost: host runtime service is missing.");
        fn := cast((*void) -> void) host_runtime_services.ensure_window_frontmost;
        fn(window);
    }
}
