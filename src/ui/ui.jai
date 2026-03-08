#load "./inspect.jai";

current_ui_render_frame: UI_Render_Frame_Info;
ui_frame_sync_semaphore: Gpu_Semaphore;
fonts: struct {
    main: *ImFont;
    mono: *ImFont;

    MAIN_SIZE :: 15.0;
    LARGE_SIZE :: 35.0;
}
ui_opts: struct {

    // State for a window which shows all global variables and allows searching/filtering them by name or module.
    globals: struct {
        show: bool = true;
        search_text: string;
    }
};

ui_init :: () {
    ImGui.CreateContext();
    io := GetIO();

    #if OS == .MACOS {
        ui_device = gpu_get_native_device();
        assert(ui_device != null, "ui_init: failed to get sgpu native Metal device.");
        ns_window := cast(*NSWindow)window;
        view := NSWindow.contentView(ns_window);
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

ui_get_monospace_font :: () -> *ImGui.ImFont {
    return fonts.mono;
}

// Per frame UI info to be passed from ui_render_pre to ui_render
UI_Render_Frame_Info :: struct {
    ready: bool;
}

ui_cancel_pending_frame :: (using ui_render_frame_info: *UI_Render_Frame_Info) {
    if ready {
        EndFrame();
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

        ShowDemoWindow(null);
        call_event_functions(.ui);
        Render();

        if !skip_render {
            native_cmd_buff := gpu_get_native_command_buffer(cmd_buff);
            assert(native_cmd_buff != null, "ui_render: failed to get native Metal4 command buffer.");

            gpu_begin_scoped_render_pass(cmd_buff, .{
                color_targets = .[
                    .{
                        view = gpu_current_swapchain_view(),
                        load_op = .LOAD,
                        store_op = .STORE,
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

#scope_file

using ImGui :: #import "ImGui";
using,only(file_exists) _ :: #import "File_Utilities";
Env_Vars :: #import "Env_Vars";

#if OS == .MACOS {
    #import "Metal";
    ui_device: *MTLDevice;
}

load_ui_font :: (io: *ImGui.IO, font_size_px: float) -> *ImGui.ImFont {
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
