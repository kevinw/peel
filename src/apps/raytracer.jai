WRITE_SHADER_OUTPUT :: true;

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
raytracer_params_cpu: *Raytracer_Params;
raytracer_params_gpu: Gpu_Ptr;
raytracer_gizmo_ctx: Gizmo.Gizmo_Context;
raytracer_gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
raytracer_manip_ctx: Manip_Context;
raytracer_objects: [..]Manip_Object;
raytracer_object_reflectivity: [2]float = .[0.24, 0.32];
raytracer_edit_objects := true;
raytracer_left_was_down := false;

PITCH_MAX :: PI / 2.1;
FOV_FACTOR :: 0.85;

raytracer_camera: Editor_Camera = .{
    position = .{0.0, 0.75, 1.95},
    move_speed = 5.0,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.006,
    pitch_min = -PITCH_MAX,
    pitch_max = PITCH_MAX,
};

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, raytracer_vertex_main, raytracer_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for raytracer graphics shaders.");
    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, raytracer_vertex_main, raytracer_fragment_main);
    assert(graphics_ok, "Raytracer graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "raytracer arena");
    raytracer_params_cpu, raytracer_params_gpu = gpu_arena_alloc(*gpu_arena, Raytracer_Params);
    raytracer_params_cpu.* = .{};
    raytracer_objects.allocator = context.allocator;
    array_add(*raytracer_objects, .{
        name = "Cube A",
        position = .{-2.85, -0.35, -6.2},
        half_extents = .{0.55, 0.55, 0.55},
        color = .{0.25, 0.92, 0.45, 1.0},
    });
    array_add(*raytracer_objects, .{
        name = "Cube B",
        position = .{2.95, -0.15, -6.7},
        half_extents = .{0.70, 0.45, 0.70},
        color = .{0.95, 0.48, 0.14, 1.0},
    });

    Gizmo.init(*raytracer_gizmo_ctx);
    gizmo_ok := Gizmo_Render.init(*raytracer_gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Raytracer gizmo renderer init failed.");
    Gizmo_Render.bind_gizmo(*raytracer_gizmo_render_ctx, *raytracer_gizmo_ctx);
    raytracer_sync_objects_to_params();

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    array_free(raytracer_objects);
    Gizmo_Render.deinit(*raytracer_gizmo_render_ctx);
    Gizmo.deinit(*raytracer_gizmo_ctx);
} @on_unload

app_ui_open := true;

app_ui :: () {
    if !app_ui_enabled return;
    using,except(Viewport) _ :: #import "ImGui";
    Persist :: #import,file "../ui/persist_controls.jai";
    inspect_globals();

    window_flags: WindowFlags = .AlwaysAutoResize | .NoFocusOnAppearing;
    if Begin("Raytracing", *app_ui_open, window_flags) {
        Text("Controls - RMB: mouse look");
        Checkbox("Edit Objects", *raytracer_edit_objects);
        if raytracer_edit_objects {
            Text("Mode: 1=Translate 2=Rotate 3=Scale");
            Text("Space: 4=World 5=Local");
            Text("Selected: %", raytracer_manip_ctx.selected_index);
            Text("Manip % / %", raytracer_manip_ctx.mode, raytracer_manip_ctx.space);
        }
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        raytracer_params_cpu.aspect = cast(float) win_w / cast(float) win_h;
        raytracer_params_cpu.inv_viewport = .{
            1.0 / cast(float) win_w,
            1.0 / cast(float) win_h,
        };
    }
    app_ui();
    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;
        if !raytracer_edit_objects continue;
        if key_code == #char "1" raytracer_manip_ctx.mode = .TRANSLATE;
        if key_code == #char "2" raytracer_manip_ctx.mode = .ROTATE;
        if key_code == #char "3" raytracer_manip_ctx.mode = .SCALE;
        if key_code == #char "4" raytracer_manip_ctx.space = .WORLD;
        if key_code == #char "5" raytracer_manip_ctx.space = .LOCAL;
    }

    io := ImGui.GetIO();
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_pressed := left_down && !raytracer_left_was_down;
    left_released := !left_down && raytracer_left_was_down;
    raytracer_left_was_down = left_down;

    _ = editor_camera_update(*raytracer_camera, dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = mouse_ok && dims_ok && win_w > 0 && win_h > 0 && right_down && !io.WantCaptureMouse);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*raytracer_camera, *cam_forward, *cam_right, *cam_up);

    raytracer_params_cpu.camera_pos = raytracer_camera.position;
    raytracer_params_cpu.time = cast(float) frame_count * (1.0 / 60.0);
    raytracer_params_cpu.cam_forward = cam_forward;
    raytracer_params_cpu.cam_right = cam_right;
    raytracer_params_cpu.cam_up = cam_up;
    raytracer_sync_objects_to_params();

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.0, 0.0, 0.0, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced(cmd_buff, 0, raytracer_params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Raytracer draw failed: %", draw_result));


    if raytracer_edit_objects && dims_ok && win_w > 0 && win_h > 0 {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        // Must match shader ray setup: rd = forward + right * p.x * 0.85 + up * p.y * 0.85
        // => tan(fov_y / 2) == 0.85
        fov_y := 2.0 * atan(FOV_FACTOR);
        view := editor_camera_make_view(*raytracer_camera);
        proj := make_projection_matrix(fov_y, viewport.x / max(viewport.y, 1.0), 0.05, 100.0);
        Gizmo_Render.gizmo_render_set_view_projection(*raytracer_gizmo_render_ctx, proj * view);

        frame := Manip_Frame_Input.{
            viewport = viewport,
            camera_pos = raytracer_camera.position,
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
        Gizmo.begin_frame(*raytracer_gizmo_ctx);
        _ = manip_update(*raytracer_manip_ctx, *raytracer_gizmo_ctx, raytracer_objects, frame);
        raytracer_sync_objects_to_params();

        gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*raytracer_gizmo_render_ctx, cmd_buff, *raytracer_gizmo_ctx, viewport, depth_mode = .NONE);
        assert(gizmo_draw_result == .SUCCESS, tprint("Raytracer gizmo draw failed: %", gizmo_draw_result));
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../editor_camera.jai";
#load "../ui/manip.jai";
#import "Math";
Input :: #import "Input";
ImGui :: #import "ImGui";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";

raytracer_sync_objects_to_params :: () {
    if raytracer_objects.count < 2 return;
    a := raytracer_objects[0];
    b := raytracer_objects[1];
    raytracer_params_cpu.cube0_center_refl = .{a.position.x, a.position.y, a.position.z, raytracer_object_reflectivity[0]};
    raytracer_params_cpu.cube0_half_pad = .{a.half_extents.x * a.scale.x, a.half_extents.y * a.scale.y, a.half_extents.z * a.scale.z, 0.0};
    raytracer_params_cpu.cube0_color_pad = .{a.color.x, a.color.y, a.color.z, 0.0};
    raytracer_params_cpu.cube0_rotation = .{a.rotation.x, a.rotation.y, a.rotation.z, a.rotation.w};

    raytracer_params_cpu.cube1_center_refl = .{b.position.x, b.position.y, b.position.z, raytracer_object_reflectivity[1]};
    raytracer_params_cpu.cube1_half_pad = .{b.half_extents.x * b.scale.x, b.half_extents.y * b.scale.y, b.half_extents.z * b.scale.z, 0.0};
    raytracer_params_cpu.cube1_color_pad = .{b.color.x, b.color.y, b.color.z, 0.0};
    raytracer_params_cpu.cube1_rotation = .{b.rotation.x, b.rotation.y, b.rotation.z, b.rotation.w};
}

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/raytracer_shader.jai";
