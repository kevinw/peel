using app: struct {
    graphics_pipeline: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;
    params: Gpu_Frame_Param_Allocator(Raymarch_Params);
    using draw: Raymarch_Params = .{
        resolution = .{1280.0, 720.0},
        mouse_uv = .{0.5, 0.5},
    };
};

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, fullscreen_tri_vert, raymarch_fragment_main);
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, fullscreen_tri_vert, raymarch_fragment_main);
    assert(graphics_ok, "Raymarch graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "raymarch arena");
    params = sgpu_make_frame_param_allocator(*gpu_arena, Raymarch_Params);

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        resolution = {cast(float) win_w, cast(float) win_h};
    }
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := clamp(cast(float) mx / cast(float) win_w, 0, 1);
        v := clamp(cast(float) my / cast(float) win_h, 0, 1);
        mouse_uv = .{u, v};
    }
    current_time = cast(float) frame_count * (1.0 / 60.0);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.02, 0.03, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);
    draw_params := sgpu_frame_param_alloc(*app.params, draw);
    gpu_draw_instanced(cmd_buff, 0, draw_params.gpu, 3, 1);
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#import "Math";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/raymarch_shader.jai";
#load "../SGPU_App_Common.jai";
