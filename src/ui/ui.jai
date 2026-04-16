#load "./inspect.jai";
#load "./report.jai";

current_ui_render_frame: UI_Render_Frame_Info;
ui_frame_sync_semaphore: Gpu_Semaphore;

fonts: struct {
    main: *ImGui.ImFont;
    mono: *ImGui.ImFont;
    #overlay(mono) monospace: *ImGui.ImFont;

    MAIN_SIZE :: 16.0;
    LARGE_SIZE :: 35.0;
}

ui_opts: struct {
    // State for a window which shows all global variables and allows searching/filtering them by name or module.
    globals: struct {
        show: bool = false;
        search_text: string;
    }
    show_imgui_demo: bool; // Show the imgui demo window (very useful widget/control examples)
};

ui_init :: () {
    using ImGui;
    ImGui.CreateContext();
    io := GetIO();
    io.ConfigFlags_ |= .DockingEnable;

    style := ImGui.GetStyle();
    style.WindowRounding = 5.0;

    #if OS == .MACOS {
        init_all_objective_c_selector_structs();
        ui_device = gpu_get_native_device();
        assert(ui_device != null, "ui_init: failed to get sgpu native Metal device.");
        ns_window := cast(*NSWindow)window;
        view := NSWindow.contentView(ns_window);
        // Let the custom Peel NSView yield cursor ownership to ImGui while UI is active.
        peel_set_custom_cursor_handling(true);
        ImGui.ImplOSX_Init(view);
        ImGui.ImplMetal_Init(ui_device);
        ui_frame_sync_semaphore = gpu_create_semaphore(0);
        assert(ui_frame_sync_semaphore != 0, "ui_init: failed to create ImGui Metal4 frame sync semaphore.");
        ImGui.ImplMetal4_ConfigureFrameSynchronization(gpu_get_native_shared_event(ui_frame_sync_semaphore), SGPU_FRAMES_IN_FLIGHT);
    } else {
        assert(false, "TODO: ui_init for platform %", OS);
    }

    fonts.main = load_ui_font(GetIO(), fonts.MAIN_SIZE);
    fonts.mono = load_ui_monospace_font(GetIO(), fonts.MAIN_SIZE);
} @on_dll_init

ui_quit :: () {
    using ImGui;

    ui_cancel_pending_frame(*current_ui_render_frame);

    if GetCurrentContext() == null {
        ui_frame_sync_semaphore = 0;
        #if OS == .MACOS {
            ui_device = null;
        }
        fonts = .{};
        return;
    }

    #if OS == .MACOS {
        ImplMetal_Shutdown();
        ImplOSX_Shutdown();
        if ui_frame_sync_semaphore != 0 {
            gpu_destroy_semaphore(ui_frame_sync_semaphore);
            ui_frame_sync_semaphore = 0;
        }
        ui_device = null;
    }

    DestroyContext();
    fonts = .{};
} @on_quit

ui_reload :: () {
    current_ui_render_frame = .{};
} @on_reload

ui_get_monospace_font :: () -> *ImGui.ImFont {
    return fonts.mono;
}

// Per frame UI info to be passed from ui_render_pre to ui_render
UI_Render_Frame_Info :: struct {
    ready: bool;
}

ui_cancel_pending_frame :: (using ui_render_frame_info: *UI_Render_Frame_Info) {
    if ready {
        ImGui.EndFrame();
        ready = false;
    }
}

ui_render_pre :: () -> UI_Render_Frame_Info {
    frame_info: UI_Render_Frame_Info;
#if OS == .MACOS {
    ns_window := cast(*NSWindow)window;
    view := NSWindow.contentView(ns_window);
    ImGui.ImplOSX_NewFrame(view);
    NewFrame();
    if app_main_dock_enabled {
        DockSpaceOverViewport();
        ui_prepare_game_view_windows();
    }
    frame_info.ready = true;
} else {
    assert(false, "TODO: ui render setup for this platform");
    NewFrame();
}
    return frame_info;
}

ui_render :: (cmd_buff: Gpu_Command_Buffer, ui_render_frame_info: *UI_Render_Frame_Info, frame_value: u64, skip_render := false) {
    if !ui_render_frame_info.ready {
        return;
    }

    #if OS == .MACOS {
        drawable_texture := gpu_get_native_texture(gpu_current_swapchain_view());
        assert(drawable_texture != null);

        pass := objc_new(MTL4RenderPassDescriptor);
        defer release(pass);
        color_attachments := MTL4RenderPassDescriptor.colorAttachments(pass);
        {
            using color_attachment := color_attachments.objectAtIndexedSubscript(color_attachments, 0);
            setTexture(color_attachment, drawable_texture);
            setLoadAction(color_attachment, .Load);
            setStoreAction(color_attachment, .Store);
        }
        ImGui.ImplMetal4_NewFrame(pass);

        if app_ui_enabled {
            if ui_opts.show_imgui_demo ShowDemoWindow(*ui_opts.show_imgui_demo);
            if ui_opts.globals.show    inspect_globals(*ui_opts.globals.show);
            call_event_functions(.ui);
        }
        call_event_functions(.overlay_ui);

        Render();

        if !skip_render {
            native_cmd_buff := gpu_get_native_command_buffer(cmd_buff);
            assert(native_cmd_buff != null, "ui_render: failed to get native Metal4 command buffer.");

            gpu_begin_scoped_render_pass(cmd_buff, .{
                color_targets = .[
                    .{
                        view = gpu_current_swapchain_view(),
                        load_op = ifx app_should_render_to_game_view() then .CLEAR else .LOAD,
                        store_op = .STORE,
                        clear_color._float = .[0.06, 0.065, 0.075, 1.0],
                    }
                ]
            });

            render_encoder := gpu_get_native_render_encoder(cmd_buff);
            assert(render_encoder != null, "ui_render: failed to get sgpu Metal4 render encoder.");
            MTL4CommandEncoder.pushDebugGroup(render_encoder, to_temp_nsstring("ImGui render"));
            defer MTL4CommandEncoder.popDebugGroup(render_encoder);

            ImplMetal4_RenderDrawData(GetDrawData(), native_cmd_buff, render_encoder);
        }
    }

    ui_render_frame_info.ready = false;
}

ui_on_frame_submitted :: (frame_value: u64) {
    #if OS == .MACOS {
        if ui_frame_sync_semaphore != 0 {
            main_queue := gpu_get_queue(.MAIN, 0);
            gpu_signal_semaphore(main_queue, ui_frame_sync_semaphore, frame_value);
        }
    }
}

dummy_on_ui :: () { } @on_ui
dummy_on_overlay_ui :: () { } @on_overlay_ui

#scope_file

using ImGui :: #import "ImGui";
using,only(file_exists) _ :: #import "File_Utilities";
Env_Vars :: #import "Env_Vars";

GAME_VIEW_FALLBACK_RENDER_WIDTH  : u32 : 640;
GAME_VIEW_FALLBACK_RENDER_HEIGHT : u32 : 360;
GAME_VIEW_OVERLAY_WIDTH_POINTS   :: 320.0;
GAME_VIEW_OVERLAY_MARGIN_POINTS  :: 18.0;

#if OS == .MACOS {
    #import "Metal";
    ui_device: *MTLDevice;
}

load_ui_font :: (io: *ImGui.IO, font_size_px: float) -> *ImGui.ImFont {
    using ImGui;

    #if OS == .MACOS {
        candidates :: string.[
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/SFPro.ttf",
            "/System/Library/Fonts/Avenir Next.ttc",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ];
    } else #if OS == .WINDOWS {
        candidates :: string.[
            "C:/Windows/Fonts/segoeui.ttf",
            "C:/Windows/Fonts/arial.ttf",
        ];
    } else {
        candidates :: string.[
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        ];
    }

    for candidates {
        if file_exists(it) {
            font := io.Fonts.AddFontFromFileTTF(io.Fonts, temp_c_string(it), font_size_px);
            if font != null {
                return font;
            }
        }
    }

    cfg: ImFontConfig;
    cfg.SizePixels = font_size_px;
    return io.Fonts.AddFontDefault(io.Fonts, *cfg);
}

ui_prepare_game_view_windows :: () {
    if !app_should_render_to_game_view() return;

    game_view.visible_this_frame = false;
    game_view.hovered_this_frame = false;
    game_view.focused_this_frame = false;
    game_view.image_min_screen = .{};
    game_view.image_max_screen = .{};
    game_view.requested_width = GAME_VIEW_FALLBACK_RENDER_WIDTH;
    game_view.requested_height = GAME_VIEW_FALLBACK_RENDER_HEIGHT;

    ui_draw_game_window_panel();

    if !game_view.visible_this_frame {
        ui_draw_game_window_overlay();
    }
}

ui_draw_game_window_panel :: () {
    using ImGui;

    vp := GetMainViewport();
    SetNextWindowSize(ImVec2.{max(vp.WorkSize.x * 0.8, 640.0), max(vp.WorkSize.y * 0.8, 400.0)}, .FirstUseEver);
    PushStyleVar(.WindowPadding, .{0, 0});
    PushStyleVar(.WindowBorderSize, 0.0);
    defer PopStyleVar(2);

    panel_visible := Begin("Game Window", flags = .NoScrollbar | .NoScrollWithMouse);
    game_view.hovered_this_frame = IsWindowHovered(.RootAndChildWindows);
    game_view.focused_this_frame = IsWindowFocused(.RootAndChildWindows);
    collapsed := IsWindowCollapsed();

    if panel_visible && !collapsed {
        game_view.visible_this_frame = true;

        SHOW_RENDER_SIZE :: false;
        #if SHOW_RENDER_SIZE {
        if BeginCombo("Render Size", temp_c_string(game_view_size_mode_label(game_view.mode))) {
            selected_match := game_view.mode == .MATCH_WINDOW;
            if Selectable("Match Window", selected_match) {
                game_view.mode = .MATCH_WINDOW;
            }

            selected_1080p := game_view.mode == .FIXED_1080P;
            if Selectable("1920 x 1080", selected_1080p) {
                game_view.mode = .FIXED_1080P;
            }
            EndCombo();
        }
        }

        avail := GetContentRegionAvail();
        bounds := ImVec2.{max(avail.x, 1.0), max(avail.y, 1.0)};
        ui_set_game_view_render_request(bounds);
        ui_draw_game_view_image("##game_window_view", bounds, game_view.mode == .FIXED_1080P);
    }

    End();
}

ui_draw_game_window_overlay :: () {
    using ImGui;

    vp := GetMainViewport();
    overlay_width := GAME_VIEW_OVERLAY_WIDTH_POINTS;
    overlay_height := overlay_width * cast(float) GAME_VIEW_FALLBACK_RENDER_HEIGHT / cast(float) GAME_VIEW_FALLBACK_RENDER_WIDTH;
    pos := ImVec2.{
        vp.WorkPos.x + vp.WorkSize.x - overlay_width - GAME_VIEW_OVERLAY_MARGIN_POINTS,
        vp.WorkPos.y + vp.WorkSize.y - overlay_height - GAME_VIEW_OVERLAY_MARGIN_POINTS,
    };
    SetNextWindowPos(pos, .Always);
    SetNextWindowSize(ImVec2.{overlay_width, overlay_height}, .Always);
    PushStyleVar(.WindowPadding, .{0, 0});
    PushStyleVar(.WindowBorderSize, 0.0);
    defer PopStyleVar(2);

    flags: WindowFlags = .NoDecoration | .NoDocking | .NoMove | .NoSavedSettings | .NoFocusOnAppearing | .NoNav;
    if Begin("Game Preview Overlay", flags = flags) {
        ui_draw_game_view_image("##game_overlay_view", ImVec2.{overlay_width, overlay_height}, preserve_aspect=true);
    }
    End();
}

ui_draw_game_view_image :: (id: *u8, bounds: ImVec2, preserve_aspect: bool) {
    using ImGui;

    draw_bounds := bounds;
    draw_bounds.x = max(draw_bounds.x, 1.0);
    draw_bounds.y = max(draw_bounds.y, 1.0);

    min := GetCursorScreenPos();
    InvisibleButton(id, draw_bounds);
    max_pos := ImVec2.{min.x + draw_bounds.x, min.y + draw_bounds.y};

    draw_list := GetWindowDrawList();
    ImDrawList.AddRectFilled(draw_list, min, max_pos, GetColorU32(ImVec4.{0.02, 0.02, 0.025, 1.0}), 0.0);

    if game_view.view == 0 || game_view.width == 0 || game_view.height == 0 {
        ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "Game view not ready");
        return;
    }

    native_texture := gpu_get_native_texture(game_view.view);
    if native_texture == null {
        ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "Game view texture unavailable");
        return;
    }

    tex_ref := ImTextureRef.{_TexID = cast(ImTextureID) native_texture};
    image_min := min;
    image_max := max_pos;
    if preserve_aspect {
        fit_min, fit_max := ui_fit_rect(min, draw_bounds, cast(float) game_view.width, cast(float) game_view.height);
        image_min = fit_min;
        image_max = fit_max;
    }
    game_view.image_min_screen = .{image_min.x, image_min.y};
    game_view.image_max_screen = .{image_max.x, image_max.y};
    ImDrawList.AddImage(draw_list, tex_ref, image_min, image_max);
}

ui_set_game_view_render_request :: (bounds: ImVec2) {
    using ImGui;

    io := GetIO();
    scale_x := max(io.DisplayFramebufferScale.x, 1.0);
    scale_y := max(io.DisplayFramebufferScale.y, 1.0);

    if game_view.mode == .FIXED_1080P {
        game_view.requested_width = 1920;
        game_view.requested_height = 1080;
        return;
    }

    game_view.requested_width = max(cast(u32) floor(bounds.x * scale_x + 0.5), 1);
    game_view.requested_height = max(cast(u32) floor(bounds.y * scale_y + 0.5), 1);
}

game_view_size_mode_label :: (mode: Game_View_Size_Mode) -> string {
    if mode == .FIXED_1080P return "1920 x 1080";
    return "Match Window";
}

ui_fit_rect :: (origin: ImVec2, bounds: ImVec2, image_w: float, image_h: float) -> ImVec2, ImVec2 {
    scale_x := bounds.x / image_w;
    scale_y := bounds.y / image_h;
    scale := min(scale_x, scale_y);
    fit_w := image_w * scale;
    fit_h := image_h * scale;
    offset_x := (bounds.x - fit_w) * 0.5;
    offset_y := (bounds.y - fit_h) * 0.5;
    return ImVec2.{origin.x + offset_x, origin.y + offset_y}, ImVec2.{origin.x + offset_x + fit_w, origin.y + offset_y + fit_h};
}

load_ui_monospace_font :: (io: *ImGui.IO, font_size_px: float) -> *ImGui.ImFont {
    #if OS == .MACOS {
        candidates :: string.[
            "/Library/Fonts/Myna-Regular.ttf",
            "/System/Library/Fonts/Myna.ttf",
            "/System/Library/Fonts/Monaco.ttf",
            "/Library/Fonts/Consolas.ttf",
            "/System/Library/Fonts/SFNSMono.ttf",
            "/System/Library/Fonts/SFMono-Regular.otf",
            "/System/Library/Fonts/Menlo.ttc",
            "/System/Library/Fonts/Courier.ttc",
        ];
    } else #if OS == .WINDOWS {
        candidates :: string.[
            "C:/Windows/Fonts/Myna.ttf",
            "C:/Windows/Fonts/monaco.ttf",
            "C:/Windows/Fonts/consola.ttf",
            "C:/Windows/Fonts/consolab.ttf",
            "C:/Windows/Fonts/cour.ttf",
        ];
    } else {
        candidates :: string.[
            "/usr/share/fonts/truetype/myna/Myna-Regular.ttf",
            "/usr/share/fonts/truetype/monaco/Monaco.ttf",
            "/usr/share/fonts/truetype/msttcorefonts/consola.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        ];
    }

    for candidates {
        if !file_exists(it) continue;
        font := io.Fonts.AddFontFromFileTTF(io.Fonts, temp_c_string(it), font_size_px);
        if font != null return font;
    }
    return fonts.main;;
}
