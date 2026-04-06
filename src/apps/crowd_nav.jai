Draw_Data :: struct {
    params_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

Crowd_Nav_Draw_Params_CPU :: struct {
    vertices: Gpu_Ptr;
    states: Gpu_Ptr;
    view_proj: Matrix4;
    light_dir: Vector3;
    time: float;
}

Crowd_Nav_Floor_Params_CPU :: struct {
    view_proj: Matrix4;
}

Crowd_Nav_Compute_Control_CPU :: struct {
    dt: float;
    time: float;
    use_b_as_src: u32;
    _pad0: u32;
    obstacle0: Vector4;
    obstacle1: Vector4;
    obstacle2: Vector4;
    obstacle3: Vector4;
}

graphics_pipeline: Gpu_Pipeline;
floor_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

crowd_vertices: Gpu_View(Crowd_Nav_Vertex);
crowd_state_storage: Gpu_View(Crowd_Nav_State);
crowd_state: AB_Buffer([CROWD_INSTANCE_COUNT]Crowd_Nav_State);
crowd_params: Gpu_Buffer(Crowd_Nav_Draw_Params_CPU);
floor_params: Gpu_Buffer(Crowd_Nav_Floor_Params_CPU);
crowd_compute_control_ring: Gpu_Frame_Ring(Crowd_Nav_Compute_Control_CPU);

crowd_draw: Draw_Data;
floor_draw: Draw_Data;

crowd_nav_ui_open := true;
crowd_nav_camera: Editor_Camera = .{
    position = .{0.0, 8.0, 10.5},
    yaw = 0.0,
    pitch = -0.46,
    move_speed = 6.0,
    boost_multiplier = 2.4,
    mouse_sensitivity = 0.0056,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};
crowd_nav_orbit_target := Vector3.{0.0, 0.65, 0.0};
crowd_nav_orbit_drag_active := false;
crowd_nav_orbit_distance: float = 10.5;
crowd_nav_orbit_prev_mouse: Vector2;
crowd_nav_orbit_have_prev_mouse := false;
crowd_nav_obstacles := Crowd_Nav_Obstacle.[
    .{center = .{-2.2, -1.1}, radius = 1.1},
    .{center = .{ 2.4, -1.8}, radius = 1.35},
    .{center = .{-1.0,  2.2}, radius = 0.95},
    .{center = .{ 2.8,  2.0}, radius = 1.15},
];

crowd_nav_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 160.0}, .FirstUseEver);
    if Begin("Crowd Nav", *crowd_nav_ui_open, flags = .NoCollapse) {
        Text("GPU crowd prototype");
        Text("RMB look, WASDQE fly, Alt+LMB orbit");
        Text("Agents: %", CROWD_AGENT_COUNT);
        Text("Obstacles: %", CROWD_OBSTACLE_COUNT);
    }
    End();
}

on_dll_init :: () {
    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM}, ],
    };
    floor_raster := raster_desc;
    floor_raster.cull = .NONE;

    SHR.gfx_pipeline(*graphics_pipeline, raster_desc, crowd_nav_vertex_main, crowd_nav_fragment_main);
    SHR.gfx_pipeline(*floor_pipeline, floor_raster, crowd_nav_floor_vertex_main, crowd_nav_floor_fragment_main);
    SHR.compute_pipeline(*compute_pipeline, crowd_nav_step_compute);

    gpu_arena = gpu_make_arena(1024 * 1024, label = "crowd nav arena");
    crowd_vertices = gpu_alloc_view(*gpu_arena, Crowd_Nav_Vertex, 18);
    crowd_state_storage = gpu_alloc_view(*gpu_arena, Crowd_Nav_State, CROWD_INSTANCE_COUNT * 2);
    crowd_params = gpu_alloc_buffer(*gpu_arena, Crowd_Nav_Draw_Params_CPU);
    floor_params = gpu_alloc_buffer(*gpu_arena, Crowd_Nav_Floor_Params_CPU);
    crowd_compute_control_ring = sgpu_make_frame_ring(*gpu_arena, Crowd_Nav_Compute_Control_CPU);

    crowd_nav_init_mesh();
    crowd_nav_seed_state();

    crowd_draw = .{
        params_gpu = crowd_params.gpu,
        num_vertices = 18,
        num_instances = CROWD_INSTANCE_COUNT,
    };
    floor_draw = .{
        params_gpu = floor_params.gpu,
        num_vertices = 6,
        num_instances = 1,
    };

    editor_camera_set_look_at(*crowd_nav_camera, crowd_nav_orbit_target);
    crowd_nav_camera.position = crowd_nav_orbit_target - crowd_nav_camera_forward(crowd_nav_camera) * crowd_nav_orbit_distance;

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled crowd_nav_ui();

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    io := ImGui.GetIO();
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    left_pressed := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .START) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    alt_down := (Input.input_button_states[Input.Key_Code.ALT] & .DOWN) != 0;

    orbit_start := alt_down && left_pressed && !io.WantCaptureMouse && !right_down && mouse_ok;
    if orbit_start {
        crowd_nav_orbit_prev_mouse = .{cast(float) mx, cast(float) my};
        crowd_nav_orbit_have_prev_mouse = true;
        crowd_nav_orbit_distance = max(distance(crowd_nav_camera.position, crowd_nav_orbit_target), 1.2);
        crowd_nav_orbit_drag_active = true;
    }

    if crowd_nav_orbit_drag_active {
        if !alt_down || !left_down || io.WantCaptureMouse || !mouse_ok {
            crowd_nav_orbit_drag_active = false;
            crowd_nav_orbit_have_prev_mouse = false;
        } else {
            crowd_nav_orbit_update_camera(.{cast(float) mx, cast(float) my});
        }
    }

    _ = editor_camera_update(*crowd_nav_camera, cast(float) dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput && !crowd_nav_orbit_drag_active,
        allow_look = right_down && !io.WantCaptureMouse && !crowd_nav_orbit_drag_active,
        allow_zoom = !io.WantCaptureMouse && !crowd_nav_orbit_drag_active);

    view := editor_camera_make_view(*crowd_nav_camera);
    aspect := ifx dims_ok && win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := editor_camera_make_projection(*crowd_nav_camera, aspect, 0.05, 80.0);
    view_proj := proj * view;
    light_dir := normalize(Vector3.{0.45, -1.0, 0.35});

    control := sgpu_frame_ring_slot(*crowd_compute_control_ring);
    control.cpu.* = .{
        dt = cast(float) dt,
        time = cast(float) time,
        use_b_as_src = ifx crowd_state.src_is_a then cast(u32) 0 else cast(u32) 1,
        obstacle0 = .{crowd_nav_obstacles[0].center.x, crowd_nav_obstacles[0].center.y, crowd_nav_obstacles[0].radius, 0.0},
        obstacle1 = .{crowd_nav_obstacles[1].center.x, crowd_nav_obstacles[1].center.y, crowd_nav_obstacles[1].radius, 0.0},
        obstacle2 = .{crowd_nav_obstacles[2].center.x, crowd_nav_obstacles[2].center.y, crowd_nav_obstacles[2].radius, 0.0},
        obstacle3 = .{crowd_nav_obstacles[3].center.x, crowd_nav_obstacles[3].center.y, crowd_nav_obstacles[3].radius, 0.0},
    };

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Crowd nav compute set pipeline failed: %", result));
    gpu_dispatch_buffers(cmd_buff, .[crowd_state_storage.gpu, control.gpu], .[(CROWD_AGENT_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*crowd_state);

    crowd_params.cpu.* = .{
        vertices = crowd_vertices.gpu,
        states = ab_buffer_src_gpu(*crowd_state),
        view_proj = view_proj,
        light_dir = light_dir,
        time = cast(float) time,
    };
    floor_params.cpu.view_proj = view_proj;

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.05, 0.06, 0.075, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});

    gpu_set_pipeline(cmd_buff, floor_pipeline);
    floor_draw_result := gpu_draw_instanced_direct(cmd_buff, floor_draw.params_gpu, floor_draw.num_vertices, floor_draw.num_instances);
    assert(floor_draw_result == .SUCCESS, tprint("Crowd nav floor draw failed: %", floor_draw_result));

    gpu_set_pipeline(cmd_buff, graphics_pipeline);
    draw_result := gpu_draw_instanced_direct(cmd_buff, crowd_draw.params_gpu, crowd_draw.num_vertices, crowd_draw.num_instances);
    assert(draw_result == .SUCCESS, tprint("Crowd nav draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

crowd_nav_init_mesh :: () {
    verts := Crowd_Nav_Vertex.[
        .{pos = .{ 0.0, 0.34,  0.48, 0.0}, normal = .{0.0, 0.45, 0.89, 0.0}},
        .{pos = .{-0.22, 0.08, -0.30, 0.0}, normal = .{0.0, 0.45, 0.89, 0.0}},
        .{pos = .{ 0.22, 0.08, -0.30, 0.0}, normal = .{0.0, 0.45, 0.89, 0.0}},

        .{pos = .{ 0.0, -0.28,  0.22, 0.0}, normal = .{0.0, -0.18, 0.98, 0.0}},
        .{pos = .{ 0.22, 0.08, -0.30, 0.0}, normal = .{0.0, -0.18, 0.98, 0.0}},
        .{pos = .{-0.22, 0.08, -0.30, 0.0}, normal = .{0.0, -0.18, 0.98, 0.0}},

        .{pos = .{ 0.0, 0.34,  0.48, 0.0}, normal = .{0.94, 0.33, -0.08, 0.0}},
        .{pos = .{ 0.22, 0.08, -0.30, 0.0}, normal = .{0.94, 0.33, -0.08, 0.0}},
        .{pos = .{ 0.0, -0.28,  0.22, 0.0}, normal = .{0.94, 0.33, -0.08, 0.0}},

        .{pos = .{ 0.0, 0.34,  0.48, 0.0}, normal = .{-0.94, 0.33, -0.08, 0.0}},
        .{pos = .{ 0.0, -0.28,  0.22, 0.0}, normal = .{-0.94, 0.33, -0.08, 0.0}},
        .{pos = .{-0.22, 0.08, -0.30, 0.0}, normal = .{-0.94, 0.33, -0.08, 0.0}},

        .{pos = .{-0.18, 0.04, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},
        .{pos = .{ 0.18, 0.04, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},
        .{pos = .{ 0.14, 0.20, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},

        .{pos = .{-0.18, 0.04, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},
        .{pos = .{ 0.14, 0.20, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},
        .{pos = .{-0.14, 0.20, -0.30, 0.0}, normal = .{0.0, 0.0, -1.0, 0.0}},
    ];
    for verts crowd_vertices.cpu[it_index] = it;
}

crowd_nav_seed_state :: () {
    palette :: Vector4.[
        .{0.93, 0.45, 0.38, 1.0},
        .{0.98, 0.72, 0.33, 1.0},
        .{0.47, 0.82, 0.58, 1.0},
        .{0.36, 0.68, 0.92, 1.0},
        .{0.69, 0.55, 0.94, 1.0},
    ];

    state_a_cpu := cast(*[CROWD_INSTANCE_COUNT]Crowd_Nav_State) crowd_state_storage.cpu.data;
    state_b_cpu := cast(*[CROWD_INSTANCE_COUNT]Crowd_Nav_State) (crowd_state_storage.cpu.data + CROWD_INSTANCE_COUNT);

    for 0..CROWD_AGENT_COUNT-1 {
        lane := cast(float) (it % 27);
        row := cast(float) (it / 27);
        pos := Vector2.{-7.2 + lane * 0.56, -5.8 + row * 0.32};
        pos += .{random_get_within_range(-0.12, 0.12), random_get_within_range(-0.12, 0.12)};
        target_index := cast(u32) ((it / 36) % 4);
        target := Vector2.{-6.5, -5.3};
        if target_index == {
        case 1; target = .{ 6.0, -4.2};
        case 2; target = .{ 5.7,  5.1};
        case 3; target = .{-5.9,  4.7};
        }
        dir := target - pos;
        normalize(*dir, fallback = .{1.0, 0.0});
        speed := random_get_within_range(1.05, 1.95);
        tint := palette[it % palette.count];
        state_a_cpu.*[it] = .{
            motion = .{pos.x, pos.y, dir.x * speed, dir.y * speed},
            sim0 = .{cast(float) target_index, 0.0, speed, 0.0},
            sim1 = .{cast(float) it, 0.34, 0.44, 0.5},
            sim2 = .{0.0, tint.x, tint.y, tint.z},
        };
    }

    for obstacle, obstacle_index: crowd_nav_obstacles {
        idx := CROWD_AGENT_COUNT + obstacle_index;
        state_a_cpu.*[idx] = .{
            motion = .{obstacle.center.x, obstacle.center.y, 0.0, 0.0},
            sim0 = .{0.0, 1.0, 0.0, 0.0},
            sim1 = .{cast(float) idx, obstacle.radius * 1.7, 1.6, obstacle.radius * 1.7},
            sim2 = .{obstacle.radius, 0.23, 0.25, 0.29},
        };
    }

    state_b_cpu.* = state_a_cpu.*;

    bytes_per_state := CROWD_INSTANCE_COUNT * size_of(Crowd_Nav_State);
    crowd_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = crowd_state_storage.gpu,
        b_gpu = crowd_state_storage.gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };
}

crowd_nav_camera_forward :: (camera: Editor_Camera) -> Vector3 {
    cam := camera;
    forward, right, up: Vector3;
    editor_camera_basis(cam, *forward, *right, *up);
    return forward;
}

crowd_nav_orbit_update_camera :: (mouse_pos: Vector2) {
    if !crowd_nav_orbit_have_prev_mouse {
        crowd_nav_orbit_prev_mouse = mouse_pos;
        crowd_nav_orbit_have_prev_mouse = true;
        return;
    }

    delta := mouse_pos - crowd_nav_orbit_prev_mouse;
    crowd_nav_orbit_prev_mouse = mouse_pos;
    if abs(delta.x) < 0.0001 && abs(delta.y) < 0.0001 return;

    crowd_nav_camera.yaw += delta.x * crowd_nav_camera.mouse_sensitivity;
    crowd_nav_camera.pitch += delta.y * crowd_nav_camera.mouse_sensitivity;
    crowd_nav_camera.pitch = clamp(crowd_nav_camera.pitch, crowd_nav_camera.pitch_min, crowd_nav_camera.pitch_max);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(crowd_nav_camera, *cam_forward, *cam_right, *cam_up);
    crowd_nav_camera.position = crowd_nav_orbit_target - cam_forward * crowd_nav_orbit_distance;
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/crowd_nav_shader.jai";
#import "ImGui";
Input :: #import "Input";
#import "Random";
