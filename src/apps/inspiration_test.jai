#load "../SGPU_App_Common.jai";

on_dll_init :: () {
    inspiration_board_set_open(true);
} @on_dll_init

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
                clear_color._float = .[0.06, 0.065, 0.075, 1.0],
            }
        ]
    });

    if app_ui_enabled {
        using ImGui;
        SetNextWindowPos(.{18.0, 18.0}, .FirstUseEver);
        if Begin("Inspiration Test", null, .AlwaysAutoResize | .NoFocusOnAppearing) {
            Text("F4 toggles the inspiration board.");
            Text("Drag image files into the board window.");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
ImGui :: #import "ImGui";
