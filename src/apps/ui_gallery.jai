#load "../SGPU_App_Common.jai";

ui_gallery_open := true;
ui_gallery_input_buffer: [256] u8;
ui_gallery_text_changed := false;
ui_gallery_text_active := false;
ui_gallery_text_focused := false;
ui_gallery_text_hovered := false;
ui_gallery_text_edited := false;

on_dll_init :: () {
    // Initial demo text. ImGui expects a zero-terminated editable buffer.
    seed := "Type here...";
    copy_count := min(seed.count, ui_gallery_input_buffer.count - 1);
    for i: 0..copy_count-1 {
        ui_gallery_input_buffer[i] = seed[i];
    }
    ui_gallery_input_buffer[copy_count] = 0;
} @on_dll_init

draw_ui :: () {
    using,except(Viewport) ImGui;

    window_flags: WindowFlags = .NoFocusOnAppearing;
    if Begin("UI Gallery", *ui_gallery_open, window_flags) {
        Text("Textbox input test");
        ui_gallery_text_changed = InputText("Text", ui_gallery_input_buffer.data, ui_gallery_input_buffer.count);
        ui_gallery_text_active = IsItemActive();
        ui_gallery_text_focused = IsItemFocused();
        ui_gallery_text_hovered = IsItemHovered();
        ui_gallery_text_edited = IsItemEdited();
    }
    End();

    if Begin("Input Debug", null, .AlwaysAutoResize | .NoFocusOnAppearing) {
        io := GetIO();
        Text("Text changed: %", ui_gallery_text_changed);
        Text("Text active/focused/hovered/edited: %/%/%/%", ui_gallery_text_active, ui_gallery_text_focused, ui_gallery_text_hovered, ui_gallery_text_edited);
        Text("io.WantCaptureMouse: %", io.WantCaptureMouse);
        Text("io.WantCaptureKeyboard: %", io.WantCaptureKeyboard);
        Text("io.WantTextInput: %", io.WantTextInput);
        Text("io.AppFocusLost: %", io.AppFocusLost);
        Text("io.MousePos: (%.1f, %.1f)", io.MousePos.x, io.MousePos.y);
        Text("io.MouseDelta: (%.2f, %.2f)", io.MouseDelta.x, io.MouseDelta.y);
        Text("io.KeyCtrl/Shift/Alt/Super: %/%/%/%", io.KeyCtrl, io.KeyShift, io.KeyAlt, io.KeySuper);
        Text("InputQueueCharacters.Size: %", io.InputQueueCharacters.Size);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.05, 0.05, 0.07, 1.0],
            }
        ]
    });

    draw_ui();

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#import "Math";
ImGui :: #import "ImGui";
