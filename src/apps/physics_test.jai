gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;

build_demo_gizmos :: () {
    t := cast(float) time;
    Gizmo.begin_frame(*gizmo_ctx);
    #if 1 {
        // axes
        Gizmo.draw_line(*gizmo_ctx, {0, 0, 0}, {0, 1, 0}, color=.{0, 1, 0, 1}, thickness=2);
        Gizmo.draw_line(*gizmo_ctx, {0, 0, 0}, {1, 0, 0}, color=.{1, 0, 0, 1}, thickness=2);
        Gizmo.draw_line(*gizmo_ctx, {0, 0, 0}, {0, 0, 1}, color=.{0, 0, 1, 1}, thickness=2);
    }
    Gizmo.draw_grid_xz(*gizmo_ctx,
        center = .{0.0, 0.0, 0.0},
        half_extent = 2.4,
        spacing = 0.2,
        major_every = 5,
        line_thickness = 1.0);
    for Physics.world.spheres {
        Gizmo.draw_sphere(*gizmo_ctx, it.pos, it.radius, color=.{1, 0, 1, 1}, thickness=2.0, rotation=it.rot);
    }
}

on_dll_init :: () {
    Gizmo.init(*gizmo_ctx);
    render_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(render_ok, "Failed to initialize Gizmo_Render module.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
    
    Physics.init();
} @on_dll_init

on_unload :: () {
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

tick :: () {
    Physics.tick(dt);
    
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    build_demo_gizmos();

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    viewport := Vector2.{2000.0, 1500.0};
    if dims_ok && win_w > 0 && win_h > 0 {
        viewport = .{cast(float) win_w, cast(float) win_h};
    }

    aspect := viewport.x / max(viewport.y, 1.0);
    t := cast(float)time;
    speed := 0.2;
    cam_pos := Vector3.{sin(t*speed)*3.0, 1.6, cos(t*speed)*3.0};
    view := make_look_at_matrix(
        viewpoint = cam_pos,//.{2.5, 1.6, 2.8},
        look_at = .{0.0, -0.1, 0.0},
        reference_up_vector = .{0.0, 1.0, 0.0},
        x_is_forward = false);
    proj := make_projection_matrix(PI / 3.0, aspect, 0.05, 100.0);
    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, proj * view);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.045, 0.048, 0.056, 1.0],
            }
        ]
    });

    draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .NONE);
    assert(draw_result == .SUCCESS, tprint("Gizmos draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

#load "../SGPU_App_Common.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
#import "Math";
#import "Window_Creation";
Physics :: #import "Physics";
