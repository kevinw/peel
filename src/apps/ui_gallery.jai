#load "../SGPU_App_Common.jai";

ui_gallery_open := true;
ui_gallery_input_buffer: [256] u8;
ui_gallery_text_changed := false;
ui_gallery_text_active := false;
ui_gallery_text_focused := false;
ui_gallery_text_hovered := false;
ui_gallery_text_edited := false;
ui_gallery_toggle_enabled := true;
ui_gallery_knob_value: float = 0.42;
ui_gallery_curve_points: [16] ImGui.ImVec2;
ui_gallery_curve_selection: s32 = -1;
ui_gallery_curve_initialized := false;

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

        Separator();
        Text("Widget test");
        _ = toggle("Enabled", *ui_gallery_toggle_enabled, .{56.0, 0.0}, true, 0.09);
        SameLine();
        _ = knob("Value##gallery", *ui_gallery_knob_value, 0.0, 1.0, 0.005, "%.3f", .WIPER_DOT, 58.0, .ValueTooltip | .AlwaysClamp);
        SameLine();
        Text("Knob: %.3f", ui_gallery_knob_value);

        if !ui_gallery_curve_initialized {
            ui_gallery_curve_points[0] = .{0.0, 0.0};
            ui_gallery_curve_points[1] = .{1.0, 1.0};
            ui_gallery_curve_points[2].x = CURVE_TERMINATOR;
            ui_gallery_curve_initialized = true;
        }
        _ = curve("Curve##gallery", .{360.0, 140.0}, ui_gallery_curve_points.count, ui_gallery_curve_points.data, *ui_gallery_curve_selection);
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
#load "../ui/curve_editor.jai";
#load "../ui/knob.jai";
#load "../ui/toggle_widget.jai";
#import "Math";
ImGui :: #import "ImGui";
