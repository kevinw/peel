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
        ui_command_queue = ui_device.newCommandQueue(ui_device);
        assert(ui_command_queue != null, "ui_init: failed to create UI command queue.");
        ui_sync_semaphore = gpu_create_semaphore(0);
        assert(ui_sync_semaphore != 0, "ui_init: failed to create UI sync semaphore.");
    } else {
        assert(false, "TODO: ui_init for platform %", OS);
    }

    load_ui_font(GetIO(), 14.0);
} @on_dll_init

ui_get_sync_semaphore :: () -> Gpu_Semaphore {
    return ui_sync_semaphore;
}

ui_render :: (wait_value: u64, signal_value: u64) {
    ns_window := cast(*NSWindow)window;
    view := NSWindow.contentView(ns_window);
    ImGui.ImplOSX_NewFrame(view);
    pass := objc_new(MTLRenderPassDescriptor);
    defer release(pass);
    color_attachments := pass.colorAttachments(pass);
    {
        drawable_texture := gpu_get_native_texture(gpu_current_swapchain_view());
        assert(drawable_texture != null);
        using color_attachment := color_attachments.objectAtIndexedSubscript(color_attachments, 0);
        setTexture    (color_attachment, drawable_texture);
        setLoadAction (color_attachment, .Load);
        setStoreAction(color_attachment, .Store);
    }

    ImGui.ImplMetal_NewFrame(pass);
    // Keep boids color output intact and overlay UI in a second pass.
    {
        color_attachments := pass.colorAttachments(pass);
        using color_attachment := color_attachments.objectAtIndexedSubscript(color_attachments, 0);
        setLoadAction (color_attachment, .Load);
        setStoreAction(color_attachment, .Store);
    }
    NewFrame();
    ShowDemoWindow(null);
    Render();

    // encode gpu commands
    command_buffer := ui_command_queue.commandBuffer(ui_command_queue);
    assert(command_buffer != null);
    sync_event := gpu_get_native_shared_event(ui_sync_semaphore);
    assert(sync_event != null);
    command_buffer.encodeWaitForEvent(command_buffer, sync_event, wait_value);

    render_encoder := command_buffer.renderCommandEncoderWithDescriptor(command_buffer, pass);
    {
        render_encoder.pushDebugGroup(render_encoder, to_temp_nsstring("ImGui render"));
        defer render_encoder.popDebugGroup(render_encoder);
        draw_data := GetDrawData();
        ImplMetal_RenderDrawData(draw_data, command_buffer, render_encoder);
        render_encoder.endEncoding(render_encoder);
    }

    command_buffer.encodeSignalEvent(command_buffer, sync_event, signal_value);
    command_buffer.commit(command_buffer);
}

#scope_file
using ImGui :: #import "ImGui";
using,only(file_exists) _ :: #import "File_Utilities";
#if OS == .MACOS {
    #import "Metal";
    ui_device: *MTLDevice;
    ui_command_queue: *MTLCommandQueue;
    ui_sync_semaphore: Gpu_Semaphore;
}

load_ui_font :: (io: *ImGui.IO, font_size_px: float) -> bool {
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
            if io.Fonts.AddFontFromFileTTF(io.Fonts, temp_c_string(it), font_size_px) != null {
                return true;
            }
        }
    }

    cfg: ImFontConfig;
    cfg.SizePixels = font_size_px;
    io.Fonts.AddFontDefault(io.Fonts, *cfg);
    return false;
}
