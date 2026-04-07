init :: () {
    app_ui_enabled = false;
} @on_dll_init

tick :: () {
    _, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    gpu_submit_and_present(cmd_buff);
} @on_tick

#load "../SGPU_App_Common.jai";
