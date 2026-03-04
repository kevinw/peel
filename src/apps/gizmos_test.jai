gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
manip_ctx: Manip_Context;
gizmo_objects: [..]Manip_Object;
gizmos_test_camera: Editor_Camera = .{
    position = .{-2.2, 1.8, 2.6},
    yaw = 0.72,
    pitch = -0.22,
    move_speed = 3.8,
    boost_multiplier = 2.2,
    mouse_sensitivity = 0.0062,
    move_planar = false,
};
gizmos_test_left_was_down := false;

gizmos_test_ui :: () {
    using ImGui;

    SetNextWindowPos(.{20.0, 20.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 230.0}, .FirstUseEver);
    if Begin("Gizmos Test", flags = .NoCollapse) {
        Text("LMB: select + drag handles");
        Text("Modes: 1=Translate 2=Rotate 3=Scale");
        Text("Space: 4=World 5=Local");
        Text("Camera: RMB look, WASDQE fly, Shift boost");
        Text("Selected object: %", manip_ctx.selected_index);
        Text("Mode: %", manip_mode_name(manip_ctx.mode));
        Text("Space: %", manip_space_name(manip_ctx.space));

        selected := cast(s64) manip_ctx.selected_index;
        if selected >= 0 && selected < gizmo_objects.count {
            obj := cast(*Manip_Object) gizmo_objects.data + selected;
            euler := quat_to_euler_xyz(obj.rotation);
            changed := false;
            changed |= SliderFloat("Euler X", *euler.x, -PI, PI);
            changed |= SliderFloat("Euler Y", *euler.y, -PI, PI);
            changed |= SliderFloat("Euler Z", *euler.z, -PI, PI);
            if changed {
                obj.rotation = quat_from_euler_xyz(euler);
            }
            Text("Quat: %.3f %.3f %.3f %.3f", obj.rotation.x, obj.rotation.y, obj.rotation.z, obj.rotation.w);
        }
    }
    End();
} @on_ui

build_demo_gizmos :: (frame: Manip_Frame_Input) {
    t := cast(float) time;
    orbit := Vector3.{cos(t * 1.2) * 0.85, 0.2 + sin(t * 0.9) * 0.25, sin(t * 1.2) * 0.85};

    Gizmo.begin_frame(*gizmo_ctx);
    using Gizmo;

    draw_grid_xz(*gizmo_ctx,
        center = .{0.0, 0.0, 0.0},
        half_extent = 2.8,
        spacing = 0.2,
        major_every = 5,
        line_thickness = 1.0);

    draw_arrow(*gizmo_ctx, .{0.0, 0.0, 0.0}, orbit, .{0.96, 0.74, 0.30, 1.0}, 3.0, 0.12);
    draw_sphere(*gizmo_ctx, orbit, 0.22, .{0.35, 0.82, 0.96, 1.0}, 2.0, 32);

    _ = manip_update(*manip_ctx, *gizmo_ctx, gizmo_objects, frame);
}

on_dll_init :: () {
    Gizmo.init(*gizmo_ctx);
    render_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(render_ok, "Failed to initialize Gizmo_Render module.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);

    gizmo_objects.allocator = context.allocator;

    array_add(*gizmo_objects, .{
        name = "Box A",
        position = .{-0.8, 0.3, -0.2},
        half_extents = .{0.22, 0.22, 0.22},
        color = .{0.92, 0.45, 0.35, 1.0},
    });
    array_add(*gizmo_objects, .{
        name = "Box B",
        position = .{0.2, 0.25, 0.4},
        half_extents = .{0.20, 0.28, 0.20},
        color = .{0.35, 0.86, 0.55, 1.0},
    });
    array_add(*gizmo_objects, .{
        name = "Box C",
        position = .{0.95, 0.4, -0.35},
        half_extents = .{0.25, 0.18, 0.25},
        color = .{0.35, 0.62, 0.96, 1.0},
    });
    array_add(*gizmo_objects, .{
        name = "Box D",
        position = .{-0.25, 0.18, 0.95},
        half_extents = .{0.18, 0.18, 0.18},
        color = .{0.95, 0.82, 0.38, 1.0},
    });
} @on_dll_init

on_unload :: () {
    array_free(gizmo_objects);
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;
        if key_code == #char "1" manip_ctx.mode = .TRANSLATE;
        if key_code == #char "2" manip_ctx.mode = .ROTATE;
        if key_code == #char "3" manip_ctx.mode = .SCALE;
        if key_code == #char "4" manip_ctx.space = .WORLD;
        if key_code == #char "5" manip_ctx.space = .LOCAL;
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    viewport := Vector2.{2000.0, 1500.0};
    if dims_ok && win_w > 0 && win_h > 0 {
        viewport = .{cast(float) win_w, cast(float) win_h};
    }
    aspect := viewport.x / max(viewport.y, 1.0);

    mx, my, mouse_ok := get_mouse_pointer_position(cast(Window_Type) window, true);
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_pressed := left_down && !gizmos_test_left_was_down;
    left_released := !left_down && gizmos_test_left_was_down;
    gizmos_test_left_was_down = left_down;

    using,only(GetIO) _ :: #import "ImGui";
    io := GetIO();

    _ = editor_camera_update(*gizmos_test_camera, editor_dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = right_down && !io.WantCaptureMouse);

    cam_pos := gizmos_test_camera.position;
    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*gizmos_test_camera, *cam_forward, *cam_right, *cam_up);

    fov_y := PI / 3.0;
    view := editor_camera_make_view(*gizmos_test_camera);
    proj := make_projection_matrix(fov_y, aspect, 0.05, 100.0);
    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, proj * view);

    frame := Manip_Frame_Input.{
        viewport = viewport,
        camera_pos = cam_pos,
        camera_forward = cam_forward,
        camera_right = cam_right,
        camera_up = cam_up,
        fov_y = fov_y,
        mouse_pos = .{cast(float) mx, cast(float) my},
        mouse_valid = mouse_ok,
        mouse_down = left_down,
        mouse_pressed = left_pressed,
        mouse_released = left_released,
        block_mouse = io.WantCaptureMouse,
    };

    build_demo_gizmos(frame);

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
#load "../editor_camera.jai";
#load "../ui/manip.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Math";

manip_mode_name :: (mode: Manip_Mode) -> string {
    if mode == .TRANSLATE return "Translate";
    if mode == .ROTATE return "Rotate";
    if mode == .SCALE return "Scale";
    return "Unknown";
}

manip_space_name :: (space: Manip_Space) -> string {
    if space == .WORLD return "World";
    if space == .LOCAL return "Local";
    return "Unknown";
}
