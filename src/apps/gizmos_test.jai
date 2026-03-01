gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;

build_demo_gizmos :: () {
    t := cast(float) time;
    orbit := Vector3.{cos(t * 1.2) * 0.85, 0.2 + sin(t * 0.9) * 0.25, sin(t * 1.2) * 0.85};
    //box_center := Vector3.{sin(t * 0.7) * 0.65, -0.15, cos(t * 0.7) * 0.65};
    box_center := Vector3.{};
    
    Gizmo.begin_frame(*gizmo_ctx);
    using Gizmo;
    #if 0 {
        // axes
        draw_line(*gizmo_ctx, {0, 0, 0}, {0, 1, 0}, color=.{0, 1, 0, 1}, thickness=2);
        draw_line(*gizmo_ctx, {0, 0, 0}, {1, 0, 0}, color=.{1, 0, 0, 1}, thickness=2);
        draw_line(*gizmo_ctx, {0, 0, 0}, {0, 0, 1}, color=.{0, 0, 1, 1}, thickness=2);
    }

    draw_grid_xz(*gizmo_ctx,
        center = .{0.0, 0.0, 0.0},
        half_extent = 2.4,
        spacing = 0.2,
        major_every = 5,
        line_thickness = 1.0);

    draw_arrow(*gizmo_ctx, .{0.0, 0.0, 0.0}, orbit, .{0.96, 0.74, 0.30, 1.0}, 3.0, 0.12);
    draw_sphere(*gizmo_ctx, orbit, 0.22, .{0.35, 0.82, 0.96, 1.0}, 2.0, 32);
    draw_triangle(*gizmo_ctx, .{-0.45, -0.05, 0.10}, .{-0.10, 0.38, -0.05}, .{0.12, -0.10, -0.12}, .{0.22, 0.72, 0.95, 0.55});
    draw_triangle(*gizmo_ctx, .{0.30, 0.05, 0.32}, .{0.55, 0.38, 0.20}, .{0.72, 0.02, 0.08}, .{0.96, 0.88, 0.25, 1.0}, filled = false, thickness = 2.0);
    draw_box(*gizmo_ctx, box_center, .{0.22, 0.18, 0.22}, .{0.94, 0.42, 0.42, 1.0}, 3.0);
    draw_handle(*gizmo_ctx, .{0.0, 0.0, 0.0}, 0.12, .{0.92, 0.92, 0.92, 1.0}, 2.0);
}

on_dll_init :: () {
    Gizmo.init(*gizmo_ctx);
    render_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(render_ok, "Failed to initialize Gizmo_Render module.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
} @on_dll_init

on_unload :: () {
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

tick :: () {
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
