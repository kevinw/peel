Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Animated_Batch :: struct {
    batch_index: s32;
    node_index: s32;
    skin_matrix_start: u32;
    skin_matrix_count: u32;
}

Running_Lizard_Instance :: struct {
    instance_index: u32;
    node_index: s32;
    mesh_index: u32;
}

Stone_Physics_Placement :: struct {
    position: Vector3;
    rotation: Quaternion;
    scale: float;
}

Scene_Instance_CPU :: struct {
    world: Matrix4;
    tint: Vector4;
    shadow_view_proj_0: Vector4;
    shadow_view_proj_1: Vector4;
    shadow_view_proj_2: Vector4;
    shadow_view_proj_3: Vector4;
    shadow_meta: Vector4;
}

Scene_Draw_Params_CPU :: struct {
    vertices: Gpu_Ptr;
    indices: Gpu_Ptr;
    materials: Gpu_Ptr;
    instances: Gpu_Ptr;
    skin_matrices: Gpu_Ptr; // points to 4 Vector4 rows per bone
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    camera_pos: Vector3;
    _pad1: float;
    material_index: u32;
    sampler_index: u32;
    skin_matrix_count: u32;
    _pad2: u32;
    _pad3: u32;
}

Ground_Draw_Params_CPU :: struct {
    vertices: Gpu_Ptr;
    indices: Gpu_Ptr;
    instances: Gpu_Ptr;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    camera_pos: Vector3;
    _pad1: float;
    sampler_index: u32;
    base_color_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    _pad2: u32;
}

graphics_pipeline: Gpu_Pipeline;
ground_pipeline: Gpu_Pipeline;
shadow_pipeline: Gpu_Pipeline;
debug_shadow_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
scene_geo: Scene_Geo;
shadow_map: Shadow_Map;
running_lizard_controller: Character_Controller;
running_lizard_anim: Scene_Anim_State;
running_lizard_clip_index: s32 = -1;
running_lizard_root: Matrix4 = Matrix4_Identity;
running_lizard_scale: float = 1.0;
running_lizard_ground_y: float = 0.5;
scene_instances: Gpu_View(Scene_Instance_CPU);
scene_draw_params: Gpu_View(Scene_Draw_Params_CPU);
scene_skin_matrices: Gpu_View(Vector4);
scene_depth_texture: Gpu_Texture;
scene_depth_view: Gpu_Texture_View;
scene_depth_w: u32;
scene_depth_h: u32;
ground_vertices: Gpu_View(Scene_Vertex);
ground_indices: Gpu_View(u32);
ground_instance: Gpu_Buffer(Scene_Instance_CPU);
ground_shadow_params: Gpu_Buffer(Scene_Draw_Params_CPU);
ground_draw_params: Gpu_Buffer(Ground_Draw_Params_CPU);
ground_texture: Gpu_Texture;
ground_texture_view: Gpu_Texture_View;
ground_sampler: Gpu_Sampler;
ground_normal_texture: Gpu_Texture;
ground_normal_texture_view: Gpu_Texture_View;
ground_roughness_texture: Gpu_Texture;
ground_roughness_texture_view: Gpu_Texture_View;
ground_ao_texture: Gpu_Texture;
ground_ao_texture_view: Gpu_Texture_View;
ground_index_count: u32;
ground_physics_body: u32;
ground_physics_body_valid: bool;
stone_physics_bodies: [..]u32;
stone_base_shapes: [..]Physics.Collider_Shape;
stone_scaled_shapes: [..]Physics.Collider_Shape;
scene_batches: [..]Draw_Batch;
animated_batches: [..]Animated_Batch;
running_lizard_instances: [..]Running_Lizard_Instance;
scene_debug_logged: bool;
autopilot_enabled: bool;
physics_gizmos_enabled: bool;
show_shadow_debug: bool;
shadow_debug_isolate_animated: bool;
shadow_debug_disable_skinning: bool;
shadow_debug_selected_animated_batch: s32 = -1;
physics_g_was_down: bool;
player_control_mode: bool = true;
p_was_down: bool;
orbit_yaw: float = 0.0;
orbit_pitch: float = -0.32;
orbit_distance: float = 8.5;
orbit_prev_mouse: Vector2;
orbit_have_prev_mouse: bool;
gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;

scene_camera: Editor_Camera = .{
    position = .{0.0, 7.0, 12.5},
    yaw = 0.0,
    pitch = -0.36,
    move_speed = 8.0,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0058,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

on_dll_init :: () {
    Gizmo.init(*gizmo_ctx);
    gizmo_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Failed to initialize Gizmo_Render for model scene.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
    Physics.configure_test_environment(
        spawn_spheres = false,
        include_static_box = false,
        create_floor = false,
        floor_half_extent = .{24.0, 1.0, 24.0},
        floor_center = .{0.0, -1.0, 0.0});
    Physics.init();
    Physics.debug_draw_enabled = false;

    graphics_source := cast([]u8) get_transpiled(.METAL, model_scene_vertex_main, model_scene_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for model scene shaders.");
    ground_source := cast([]u8) get_transpiled(.METAL, ground_vertex_main, ground_fragment_main);
    assert(ground_source.count > 0, "Transpilation failed for model scene ground shaders.");
    shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_shadow_vertex_main, model_scene_shadow_fragment_main);
    assert(shadow_source.count > 0, "Transpilation failed for model scene shadow shaders.");
    debug_shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_debug_shadow_vertex_main, model_scene_debug_shadow_fragment_main);
    assert(debug_shadow_source.count > 0, "Transpilation failed for model scene shadow debug shaders.");

    main_raster: Gpu_Raster_Desc = .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    };
    shadow_raster: Gpu_Raster_Desc = .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R32_SFLOAT},
        ],
    };

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, main_raster);
    assert(graphics_pipeline != 0, "Model scene graphics pipeline creation failed.");
    ground_pipeline = gpu_create_graphics_pipeline(ground_source, main_raster);
    assert(ground_pipeline != 0, "Model scene ground pipeline creation failed.");
    shadow_pipeline = gpu_create_graphics_pipeline(shadow_source, shadow_raster);
    assert(shadow_pipeline != 0, "Model scene shadow pipeline creation failed.");
    debug_shadow_pipeline = gpu_create_graphics_pipeline(debug_shadow_source, main_raster);
    assert(debug_shadow_pipeline != 0, "Model scene shadow debug pipeline creation failed.");
    shadow_map_init(*shadow_map);

    model_paths := string.[
        "./models/teapot.obj",
        "./models/nerdy+lizard+3d+model.glb",
        "./models/Lizard run.glb",
        "./models/Low Poly Stones/Mesh/ST_Stone1.fbx",
        "./models/Low Poly Stones/Mesh/ST_Stone2.fbx",
        "./models/Low Poly Stones/Mesh/ST_Stone3.fbx",
        "./models/Low Poly Stones/Mesh/ST_Stone4.fbx",
        "./models/Low Poly Stones/Mesh/ST_Stone5.fbx",
    ];
    scene_geo_init(*scene_geo, model_paths);

    teapot_model := scene_geo_model_index_by_name(*scene_geo, "teapot");
    lizard_model := scene_geo_model_index_by_name(*scene_geo, "nerdy+lizard+3d+model");
    running_lizard_model := scene_geo_model_index_by_name(*scene_geo, "Lizard run");
    stone_models := s32.[
        scene_geo_model_index_by_name(*scene_geo, "ST_Stone1"),
        scene_geo_model_index_by_name(*scene_geo, "ST_Stone2"),
        scene_geo_model_index_by_name(*scene_geo, "ST_Stone3"),
        scene_geo_model_index_by_name(*scene_geo, "ST_Stone4"),
        scene_geo_model_index_by_name(*scene_geo, "ST_Stone5"),
    ];
    assert(teapot_model >= 0 && lizard_model >= 0 && running_lizard_model >= 0, "Failed to resolve core Scene_Geo model indices.");
    for stone_models assert(it >= 0, "Failed to resolve stone Scene_Geo model index %.", it_index);
    hero_lizard_bounds := scene_geo_model_bounds(*scene_geo, lizard_model);
    hero_lizard_size := hero_lizard_bounds.max - hero_lizard_bounds.min;
    hero_lizard_max_extent := max(max(hero_lizard_size.x, hero_lizard_size.y), hero_lizard_size.z);
    running_lizard_bounds := scene_geo_model_bounds(*scene_geo, running_lizard_model);
    running_lizard_size := running_lizard_bounds.max - running_lizard_bounds.min;
    running_lizard_max_extent := max(max(running_lizard_size.x, running_lizard_size.y), running_lizard_size.z);
    hero_lizard_world_scale := 12.0;
    running_lizard_target_extent := hero_lizard_max_extent * hero_lizard_world_scale * 0.4;
    running_lizard_scale = ifx running_lizard_max_extent > 0.0 then running_lizard_target_extent / running_lizard_max_extent else 1.0;
    running_lizard_ground_y = -running_lizard_bounds.min.y * running_lizard_scale - 0.2;
    running_lizard_model_info := scene_geo.models[running_lizard_model];
    assert(running_lizard_model_info.anim_clip_count > 0, "Running lizard model has no imported animation clips.");
    running_lizard_clip_index = cast(s32) running_lizard_model_info.anim_clip_start;
    scene_anim_init(*running_lizard_anim, *scene_geo, running_lizard_model, running_lizard_clip_index);
    character_controller_init_in_system(
        *running_lizard_controller,
        Physics.physics.system,
        .{-6.8, running_lizard_ground_y, -9.5},
        visual_yaw_offset = 0.0);

    root_transforms: [..]Matrix4;
    instances_cpu: [..]Scene_Instance_CPU;
    defer array_free(root_transforms);
    defer array_free(instances_cpu);

    total_skin_matrix_count: s64 = 0;

    array_add(*root_transforms, make_translation_matrix4(.{4.9, 1.1, -5.6}) * make_scale_matrix4(.{12.0, 12.0, 12.0}));
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, lizard_model, root_transforms);
    array_reset(*root_transforms);

    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    for node_index: running_lizard_model_info.node_start .. running_lizard_model_info.node_start + running_lizard_model_info.node_count - 1 {
        node := scene_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            mesh := scene_geo.meshes[mesh_index];
            batch := array_add(*scene_batches);
            batch.mesh_index = mesh_index;
            batch.first_instance = cast(u32) instances_cpu.count;
            batch.instance_count = 1;

            instance_world := running_lizard_root;
            node_local_index := cast(s32) node_index - cast(s32) running_lizard_model_info.node_start;
            if node_local_index >= 0 && node_local_index < running_lizard_anim.worlds.count {
                instance_world = running_lizard_root * running_lizard_anim.worlds[node_local_index];
            } else if mesh.skin_bone_count == 0 {
                instance_world = running_lizard_root * node.world;
            }
            instance_index := cast(u32) instances_cpu.count;
            array_add(*instances_cpu, .{
                world = instance_world,
                tint = .{1.0, 0.96, 0.96, 1.0},
                shadow_view_proj_0 = .{1.0, 0.0, 0.0, 0.0},
                shadow_view_proj_1 = .{0.0, 1.0, 0.0, 0.0},
                shadow_view_proj_2 = .{0.0, 0.0, 1.0, 0.0},
                shadow_view_proj_3 = .{0.0, 0.0, 0.0, 1.0},
            });
            array_add(*running_lizard_instances, .{
                instance_index = instance_index,
                node_index = cast(s32) node_index,
                mesh_index = mesh_index,
            });

            if mesh.skin_bone_count > 0 {
                array_add(*animated_batches, .{
                    batch_index = cast(s32) scene_batches.count - 1,
                    node_index = cast(s32) node_index,
                    skin_matrix_start = cast(u32) total_skin_matrix_count,
                    skin_matrix_count = mesh.skin_bone_count,
                });
                total_skin_matrix_count += mesh.skin_bone_count;
            }
        }
    }

    append_floating_teapot_transforms(*root_transforms);
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, teapot_model, root_transforms, tint = .{0.94, 0.78, 0.48, 1.0});
    for stone_models {
        array_reset(*root_transforms);
        stone_placements: [..]Stone_Physics_Placement;
        defer array_free(stone_placements);
        stone_bounds := scene_geo_model_bounds(*scene_geo, it);
        stone_size := stone_bounds.max - stone_bounds.min;
        stone_max_extent := max(max(stone_size.x, stone_size.y), stone_size.z);
        stone_base_scale := ifx stone_max_extent > 0.0 then 2.2 / stone_max_extent else 1.0;
        append_scattered_stone_transforms(*root_transforms, *stone_placements, cast(u32) it_index, stone_models.count, stone_base_scale);
        scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, it, root_transforms, tint = .{0.92, 0.9, 0.88, 1.0});

        base_shape := build_model_mesh_collider_shape(scene_geo, it);
        array_add(*stone_base_shapes, base_shape);
        for stone_placements {
            scaled_shape := Physics.create_scaled_shape(base_shape, .{it.scale, it.scale, it.scale});
            array_add(*stone_scaled_shapes, scaled_shape);
            body := Physics.create_static_body_from_shape(scaled_shape, it.position, it.rotation);
            array_add(*stone_physics_bodies, body);
        }
    }

    init_ground_plane();

    arena_bytes :=
        instances_cpu.count * size_of(Scene_Instance_CPU) +
        scene_batches.count * size_of(Scene_Draw_Params_CPU) +
        total_skin_matrix_count * 4 * size_of(Vector4) +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "model scene arena");
    assert(gpu_arena.cpu != null, "Model scene arena creation failed.");

    scene_instances = gpu_alloc_view(*gpu_arena, Scene_Instance_CPU, instances_cpu.count);
    if instances_cpu.count > 0 {
        memcpy(scene_instances.cpu.data, instances_cpu.data, instances_cpu.count * size_of(Scene_Instance_CPU));
    }

    if total_skin_matrix_count > 0 {
        scene_skin_matrices = gpu_alloc_view(*gpu_arena, Vector4, total_skin_matrix_count * 4);
    }

    scene_draw_params = gpu_alloc_view(*gpu_arena, Scene_Draw_Params_CPU, scene_batches.count);
    for batch: scene_batches {
        mesh := scene_geo.meshes[batch.mesh_index];
        scene_draw_params.cpu[it_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = scene_instances.gpu + (batch.first_instance * size_of(Scene_Instance_CPU)).(Gpu_Ptr),
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            camera_pos = scene_camera.position,
            material_index = mesh.material_index,
            sampler_index = 0,
            skin_matrix_count = 0,
        };
    }
    for animated_batches {
        batch_index := cast(s64) it.batch_index;
        scene_draw_params.cpu[batch_index].skin_matrices = scene_skin_matrices.gpu + (it.skin_matrix_start * 4 * size_of(Vector4)).(Gpu_Ptr);
        scene_draw_params.cpu[batch_index].skin_matrix_count = it.skin_matrix_count;
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    controller_deinit(*running_lizard_controller);
    for stone_physics_bodies Physics.destroy_body(it);
    array_free(stone_physics_bodies);
    for * stone_scaled_shapes Physics.destroy_shape(it);
    array_free(stone_scaled_shapes);
    for * stone_base_shapes Physics.destroy_shape(it);
    array_free(stone_base_shapes);
    if ground_physics_body_valid {
        Physics.destroy_body(ground_physics_body);
        ground_physics_body_valid = false;
        ground_physics_body = 0;
    }
    Physics.deinit();
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
    if debug_shadow_pipeline != 0 gpu_free_pipeline(debug_shadow_pipeline);
    if shadow_pipeline != 0 gpu_free_pipeline(shadow_pipeline);
    if ground_pipeline != 0 gpu_free_pipeline(ground_pipeline);
    shadow_map_deinit(*shadow_map);
    if ground_ao_texture_view != 0 gpu_free_texture_view(ground_ao_texture_view);
    if ground_ao_texture != 0 gpu_free(ground_ao_texture);
    if ground_sampler != 0 gpu_free(ground_sampler);
    if ground_roughness_texture_view != 0 gpu_free_texture_view(ground_roughness_texture_view);
    if ground_roughness_texture != 0 gpu_free(ground_roughness_texture);
    if ground_normal_texture_view != 0 gpu_free_texture_view(ground_normal_texture_view);
    if ground_normal_texture != 0 gpu_free(ground_normal_texture);
    if ground_texture_view != 0 gpu_free_texture_view(ground_texture_view);
    if ground_texture != 0 gpu_free(ground_texture);
    if ground_draw_params.cpu != null gpu_free(cast(*void) ground_draw_params.cpu);
    if ground_shadow_params.cpu != null gpu_free(cast(*void) ground_shadow_params.cpu);
    if ground_instance.cpu != null gpu_free(cast(*void) ground_instance.cpu);
    if ground_indices.cpu.data != null gpu_free(cast(*void) ground_indices.cpu.data);
    if ground_vertices.cpu.data != null gpu_free(cast(*void) ground_vertices.cpu.data);
    scene_anim_deinit(*running_lizard_anim);
    array_free(running_lizard_instances);
    array_free(animated_batches);
    array_free(scene_batches);
    scene_geo_deinit(*scene_geo);
    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    io := ImGui.GetIO();
    g_down := (Input.input_button_states[cast(Input.Key_Code) #char "G"] & .DOWN) != 0;
    if g_down && !physics_g_was_down {
        physics_gizmos_enabled = !physics_gizmos_enabled;
        Physics.debug_draw_enabled = physics_gizmos_enabled;
    }
    physics_g_was_down = g_down;
    p_down := (Input.input_button_states[cast(Input.Key_Code) #char "P"] & .DOWN) != 0;
    if p_down && !p_was_down {
        player_control_mode = !player_control_mode;
    }
    p_was_down = p_down;

    if app_ui_enabled {
        using ImGui;
        if Begin("Model Scene", flags = .NoCollapse | .AlwaysAutoResize) {
            Text("Mode: %", ifx player_control_mode then "Player Control" else "Camera Control");
            Checkbox("Autopilot", *autopilot_enabled);
            if Checkbox("Physics Gizmos", *physics_gizmos_enabled) {
                Physics.debug_draw_enabled = physics_gizmos_enabled;
            }
            Checkbox("Show Shadow Debug", *show_shadow_debug);
            Checkbox("Isolate Animated Shadow Batch", *shadow_debug_isolate_animated);
            Checkbox("Disable Shadow Skinning", *shadow_debug_disable_skinning);
            if animated_batches.count > 0 {
                max_batch_index := cast(s32) animated_batches.count - 1;
                if shadow_debug_selected_animated_batch > max_batch_index shadow_debug_selected_animated_batch = max_batch_index;
                ImGui.SliderInt("Shadow Animated Batch", *shadow_debug_selected_animated_batch, -1, max_batch_index);
            }
            Separator();
            Text("Toggle Mode: P");
            if player_control_mode {
                Text("Move Lizard: WASD");
                Text("Orbit Camera: RMB drag");
            } else {
                Text("Fly Camera: WASD/QE");
                Text("Look Camera: RMB drag");
            }
            Text("Toggle Gizmos: G");
        }
        End();
    }

    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    if player_control_mode {
        if right_down && mouse_ok && !io.WantCaptureMouse {
            mouse := Vector2.{cast(float) mx, cast(float) my};
            if orbit_have_prev_mouse {
                delta := mouse - orbit_prev_mouse;
                orbit_yaw += delta.x * scene_camera.mouse_sensitivity;
                orbit_pitch += delta.y * scene_camera.mouse_sensitivity;
                orbit_pitch = clamp(orbit_pitch, -1.2, 0.35);
            }
            orbit_prev_mouse = mouse;
            orbit_have_prev_mouse = true;
        } else {
            orbit_have_prev_mouse = false;
        }
    } else {
        _ = editor_camera_update(*scene_camera, dt, mx, my, mouse_ok,
            allow_move = !io.WantCaptureKeyboard,
            allow_look = right_down && !io.WantCaptureMouse);
    }

    controller_forward, controller_right, controller_up: Vector3;
    if player_control_mode {
        controller_forward = .{sin(orbit_yaw), 0.0, -cos(orbit_yaw)};
        controller_right = .{cos(orbit_yaw), 0.0, sin(orbit_yaw)};
        controller_up = .{0.0, 1.0, 0.0};
    } else {
        editor_camera_basis(*scene_camera, *controller_forward, *controller_right, *controller_up);
    }
    controller_forward.y = 0.0;
    controller_right.y = 0.0;
    normalize(*controller_forward, fallback = .{0.0, 0.0, -1.0});
    normalize(*controller_right, fallback = .{1.0, 0.0, 0.0});

    desired_move := Vector3.{0.0, 0.0, 0.0};
    if player_control_mode {
        if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN desired_move += controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN desired_move -= controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN desired_move -= controller_right;
        if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN desired_move += controller_right;
    }
    if autopilot_enabled && dot(desired_move, desired_move) < 1.0e-6 {
        autopilot_center := Vector3.{-6.8, running_lizard_ground_y, -9.5};
        autopilot_radius := 3.8;
        autopilot_target := autopilot_center + .{
            cos(cast(float) time * 0.35) * autopilot_radius,
            0.0,
            sin(cast(float) time * 0.35) * autopilot_radius,
        };
        desired_move = autopilot_target - character_controller_position(*running_lizard_controller);
    }

    Gizmo.begin_frame(*gizmo_ctx);
    character_controller_update_in_system(*running_lizard_controller, Physics.physics.system, desired_move, dt);
    Physics.tick(dt);
    if physics_gizmos_enabled {
        append_lizard_physics_gizmos();
    }

    if player_control_mode {
        player_focus := character_controller_position(*running_lizard_controller) + .{0.0, 0.95, 0.0};
        orbit_dir := Vector3.{
            sin(orbit_yaw) * cos(orbit_pitch),
            sin(orbit_pitch),
            -cos(orbit_yaw) * cos(orbit_pitch),
        };
        normalize(*orbit_dir, fallback = .{0.0, -0.25, 1.0});
        scene_camera.position = player_focus - orbit_dir * orbit_distance;
        editor_camera_set_look_at(*scene_camera, player_focus);
    }

    view := editor_camera_make_view(*scene_camera);
    aspect := ifx win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := make_projection_matrix(PI / 3.2, aspect, 0.05, 250.0);
    view_proj := proj * view;
    viewport := Vector2.{max(1.0, cast(float) win_w), max(1.0, cast(float) win_h)};

    shadow_map.light_dir = normalize(Vector3.{0.35, -1.0, 0.25});
    shadow_map.center = .{0.0, 2.0, -12.0};
    shadow_map.extent = 18.0;
    shadow_map.distance = 20.0;
    shadow_map.near_plane = 0.1;
    shadow_map.far_plane = 48.0;
    shadow_map.bias = 0.0035;
    shadow_map_update_view_proj(*shadow_map);
    shadow_binding := shadow_map_binding(*shadow_map);

    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    scene_anim_sample(
        *running_lizard_anim,
        *scene_geo,
        running_lizard_clip_index,
        running_lizard_controller.animation_time,
        running_lizard_controller.animation_blend);
    running_lizard_model := scene_geo.models[running_lizard_anim.model_index];
    for running_lizard_instances {
        node_local_index := it.node_index - cast(s32) running_lizard_model.node_start;
        instance_world := running_lizard_root;
        if node_local_index >= 0 && node_local_index < running_lizard_anim.worlds.count {
            instance_world = running_lizard_root * running_lizard_anim.worlds[node_local_index];
        }
        scene_instances.cpu[it.instance_index].world = instance_world;
    }
    for animated_batches {
        batch := scene_batches[it.batch_index];
        mesh := scene_geo.meshes[batch.mesh_index];
        skin_start := cast(s64) it.skin_matrix_start * 4;
        skin_end := skin_start + cast(s64) it.skin_matrix_count * 4;
        dst := scene_skin_matrices.cpu;
        dst.data += skin_start;
        dst.count = skin_end - skin_start;
        written := scene_anim_write_skin_matrices(dst, *scene_geo, *running_lizard_anim, mesh, it.node_index);
        assert(written == it.skin_matrix_count);
    }

    for *scene_instances.cpu {
        it.shadow_view_proj_0 = shadow_map.view_proj.v[0];
        it.shadow_view_proj_1 = shadow_map.view_proj.v[1];
        it.shadow_view_proj_2 = shadow_map.view_proj.v[2];
        it.shadow_view_proj_3 = shadow_map.view_proj.v[3];
        it.shadow_meta = shadow_binding;
    }
    ground_instance.cpu.shadow_view_proj_0 = shadow_map.view_proj.v[0];
    ground_instance.cpu.shadow_view_proj_1 = shadow_map.view_proj.v[1];
    ground_instance.cpu.shadow_view_proj_2 = shadow_map.view_proj.v[2];
    ground_instance.cpu.shadow_view_proj_3 = shadow_map.view_proj.v[3];
    ground_instance.cpu.shadow_meta = shadow_binding;

    for *scene_draw_params.cpu {
        it.view_proj = view_proj;
        it.camera_pos = scene_camera.position;
        it.light_dir = shadow_map.light_dir;
    }
    ground_shadow_params.cpu.view_proj = view_proj;
    ground_shadow_params.cpu.camera_pos = scene_camera.position;
    ground_shadow_params.cpu.light_dir = shadow_map.light_dir;
    ground_draw_params.cpu.view_proj = view_proj;
    ground_draw_params.cpu.camera_pos = scene_camera.position;
    ground_draw_params.cpu.light_dir = shadow_map.light_dir;

    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, view_proj);

    if !scene_debug_logged scene_debug_logged = true;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    {
        saved_shadow_skin_counts: [..]u32;
        defer array_free(saved_shadow_skin_counts);
        if shadow_debug_disable_skinning {
            saved_shadow_skin_counts.allocator = temp;
            array_resize(*saved_shadow_skin_counts, animated_batches.count);
            for animated_batches {
                batch_index := cast(s64) it.batch_index;
                saved_shadow_skin_counts[it_index] = scene_draw_params.cpu[batch_index].skin_matrix_count;
                scene_draw_params.cpu[batch_index].skin_matrix_count = 0;
            }
        }

        gpu_begin_scoped_render_pass(cmd_buff, .{
            depth_target = .{
                view = shadow_map.depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{
                    depth = 1.0,
                    stencil = 0,
                },
            },
            color_targets = .[
                .{
                    view = shadow_map.map_view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[1.0, 1.0, 1.0, 1.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, shadow_pipeline);
        draw_result := gpu_draw_instanced_direct(cmd_buff, ground_shadow_params.gpu, ground_index_count, 1);
        assert(draw_result == .SUCCESS, "Model scene ground shadow draw failed.");
        for batch: scene_batches {
            if shadow_debug_isolate_animated {
                animated_index := find_animated_batch_index_for_batch(cast(s32) it_index);
                if animated_index < 0 continue;
                if shadow_debug_selected_animated_batch >= 0 && animated_index != shadow_debug_selected_animated_batch continue;
            }
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
            assert(draw_result == .SUCCESS, "Model scene shadow draw failed.");
        }

        if shadow_debug_disable_skinning {
            for animated_batches {
                batch_index := cast(s64) it.batch_index;
                scene_draw_params.cpu[batch_index].skin_matrix_count = saved_shadow_skin_counts[it_index];
            }
        }
    }

    {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            depth_target = .{
                view = scene_depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{
                    depth = 1.0,
                    stencil = 0,
                },
            },
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.06, 0.08, 0.11, 1.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, ground_pipeline);
        draw_result := gpu_draw_instanced_direct(cmd_buff, ground_draw_params.gpu, ground_index_count, 1);
        assert(draw_result == .SUCCESS, "Model scene ground draw failed.");

        gpu_set_pipeline(cmd_buff, graphics_pipeline);

        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
            assert(draw_result == .SUCCESS, "Model scene draw failed.");
        }

        if physics_gizmos_enabled {
            draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .TEST);
            assert(draw_result == .SUCCESS, "Physics gizmo draw failed.");
        }

        if show_shadow_debug {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_shadow_pipeline);
            draw_result := gpu_draw_instanced_direct(cmd_buff, scene_draw_params.gpu, 6, 1);
            assert(draw_result == .SUCCESS, "Model scene shadow debug draw failed.");
        }
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

ensure_scene_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if scene_depth_view != 0 && scene_depth_w == width && scene_depth_h == height return;

    res, scene_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS);
    assert(scene_depth_texture != 0, "Model scene depth texture creation failed.");

    scene_depth_view = gpu_texture_view(scene_depth_texture);
    assert(scene_depth_view != 0, "Model scene depth view creation failed.");
    scene_depth_w = width;
    scene_depth_h = height;
    gpu_commit_residency();
}

append_lizard_physics_gizmos :: () {
    lizard_pos := character_controller_position(*running_lizard_controller);
    lizard_forward := Vector3.{
        sin(running_lizard_controller.facing_yaw),
        0.0,
        cos(running_lizard_controller.facing_yaw),
    };
    Gizmo.draw_sphere(*gizmo_ctx, lizard_pos + .{0.0, 0.45, 0.0}, 0.42, color = .{0.98, 0.84, 0.22, 0.95}, thickness = 1.75);
    Gizmo.draw_arrow(*gizmo_ctx,
        lizard_pos + .{0.0, 0.45, 0.0},
        lizard_pos + .{0.0, 0.45, 0.0} + lizard_forward * 1.3,
        color = .{1.0, 0.48, 0.18, 0.95},
        thickness = 2.0,
        head_size = 0.16);
}

find_animated_batch_index_for_batch :: (batch_index: s32) -> s32 {
    for animated_batches {
        if it.batch_index == batch_index return cast(s32) it_index;
    }
    return -1;
}

GROUND_COLOR_PATH :: "./textures/Ground104_1K-JPG/Ground104_1K-JPG_Color.jpg";
GROUND_NORMAL_PATH :: "./textures/Ground104_1K-JPG/Ground104_1K-JPG_NormalGL.jpg";
GROUND_ROUGHNESS_PATH :: "./textures/Ground104_1K-JPG/Ground104_1K-JPG_Roughness.jpg";
GROUND_AO_PATH :: "./textures/Ground104_1K-JPG/Ground104_1K-JPG_AmbientOcclusion.jpg";
GROUND_GRID_X :: 112;
GROUND_GRID_Z :: 112;
GROUND_PHYSICS_GRID_X :: GROUND_GRID_X / 4;
GROUND_PHYSICS_GRID_Z :: GROUND_GRID_Z / 4;
GROUND_SIZE_X :: 48.0;
GROUND_SIZE_Z :: 46.0;
GROUND_CENTER_Z :: -12.0;
FLOATING_TEAPOT_COUNT :: 8;
SCATTERED_STONE_COUNT :: 150;

init_ground_plane :: () {
    ground_texture, ground_texture_view = load_texture_rgba8(GROUND_COLOR_PATH);
    ground_normal_texture, ground_normal_texture_view = load_texture_rgba8(GROUND_NORMAL_PATH);
    ground_roughness_texture, ground_roughness_texture_view = load_texture_rgba8(GROUND_ROUGHNESS_PATH);
    ground_ao_texture, ground_ao_texture_view = load_texture_rgba8(GROUND_AO_PATH);
    ground_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .REPEAT,
        address_mode_v = .REPEAT,
        address_mode_w = .REPEAT,
    });
    assert(ground_sampler != 0, "Model scene ground sampler creation failed.");

    ground_vertices_cpu: [..]Scene_Vertex;
    ground_indices_cpu: [..]u32;
    ground_height_samples: [..]float;
    defer array_free(ground_vertices_cpu);
    defer array_free(ground_indices_cpu);
    defer array_free(ground_height_samples);
    build_ground_plane_mesh(*ground_vertices_cpu, *ground_indices_cpu);
    build_ground_height_samples(*ground_height_samples, GROUND_PHYSICS_GRID_X, GROUND_PHYSICS_GRID_Z);

    assert(GROUND_PHYSICS_GRID_X == GROUND_PHYSICS_GRID_Z, "Jolt heightfield path currently expects a square physics grid.");
    sample_count := cast(u32) GROUND_PHYSICS_GRID_X + 1;
    cell_size_x := GROUND_SIZE_X / cast(float) GROUND_PHYSICS_GRID_X;
    cell_size_z := GROUND_SIZE_Z / cast(float) GROUND_PHYSICS_GRID_Z;
    ground_physics_body = Physics.create_static_heightfield(
        ground_height_samples,
        sample_count,
        .{-GROUND_SIZE_X * 0.5, 0.0, -GROUND_SIZE_Z * 0.5 + GROUND_CENTER_Z},
        .{cell_size_x, 1.0, cell_size_z});
    ground_physics_body_valid = true;

    ground_vertices = gpu_alloc_view(Scene_Vertex, ground_vertices_cpu.count, label = "model scene ground vertices");
    ground_indices = gpu_alloc_view(u32, ground_indices_cpu.count, label = "model scene ground indices");
    ground_instance = gpu_alloc_buffer(Scene_Instance_CPU, label = "model scene ground instance");
    ground_shadow_params = gpu_alloc_buffer(Scene_Draw_Params_CPU, label = "model scene ground shadow params");
    ground_draw_params = gpu_alloc_buffer(Ground_Draw_Params_CPU, label = "model scene ground params");

    memcpy(ground_vertices.cpu.data, ground_vertices_cpu.data, ground_vertices_cpu.count * size_of(Scene_Vertex));
    memcpy(ground_indices.cpu.data, ground_indices_cpu.data, ground_indices_cpu.count * size_of(u32));

    ground_instance.cpu.* = .{
        world = Matrix4_Identity,
        tint = .{1.0, 1.0, 1.0, 1.0},
        shadow_view_proj_0 = .{1.0, 0.0, 0.0, 0.0},
        shadow_view_proj_1 = .{0.0, 1.0, 0.0, 0.0},
        shadow_view_proj_2 = .{0.0, 0.0, 1.0, 0.0},
        shadow_view_proj_3 = .{0.0, 0.0, 0.0, 1.0},
    };
    ground_shadow_params.cpu.* = .{
        vertices = ground_vertices.gpu,
        indices = ground_indices.gpu,
        materials = 0,
        instances = ground_instance.gpu,
        skin_matrices = 0,
        view_proj = Matrix4_Identity,
        light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
        camera_pos = scene_camera.position,
        material_index = 0,
        sampler_index = cast(u32) ground_sampler - 1,
        skin_matrix_count = 0,
    };
    ground_draw_params.cpu.* = .{
        vertices = ground_vertices.gpu,
        indices = ground_indices.gpu,
        instances = ground_instance.gpu,
        view_proj = Matrix4_Identity,
        light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
        camera_pos = scene_camera.position,
        sampler_index = cast(u32) ground_sampler - 1,
        base_color_texture_index = cast(u32) ground_texture_view - 1,
        normal_texture_index = cast(u32) ground_normal_texture_view - 1,
        roughness_texture_index = cast(u32) ground_roughness_texture_view - 1,
        ao_texture_index = cast(u32) ground_ao_texture_view - 1,
    };
    ground_index_count = cast(u32) ground_indices.cpu.count;
}

append_floating_teapot_transforms :: (root_transforms: *[..]Matrix4) {
    random_seed(cast(u64) 0x74ea0701);
    for 0..FLOATING_TEAPOT_COUNT {
        angle := random_get_within_range(0.0, 2.0 * PI);
        radius := random_get_within_range(16.0, 23.0);
        x := cos(angle) * radius;
        z := sin(angle) * radius + GROUND_CENTER_Z;
        y := random_get_within_range(5.0, 8.5);
        scale := random_get_within_range(0.35, 0.7);
        yaw := random_get_within_range(0.0, 2.0 * PI);
        q: Quaternion;
        set_from_axis_and_angle(*q, .{0.0, 1.0, 0.0}, yaw);
        array_add(root_transforms,
            make_translation_matrix4(.{x, y, z})
            * rotation_matrix(Matrix4, q)
            * make_scale_matrix4(.{scale, scale, scale}));
    }
}

append_scattered_stone_transforms :: (root_transforms: *[..]Matrix4, placements: *[..]Stone_Physics_Placement, variant_index: u32, variant_count: s64, base_scale: float) {
    target_count := SCATTERED_STONE_COUNT / variant_count;
    if cast(s64) variant_index < SCATTERED_STONE_COUNT % variant_count target_count += 1;

    accepted: s64 = 0;
    random_seed(cast(u64) 0x5eedC0de + cast(u64) variant_index * 0x9E3779B97F4A7C15);
    while accepted < target_count {
        x := random_get_within_range(-GROUND_SIZE_X * 0.42, GROUND_SIZE_X * 0.42);
        z := random_get_within_range(-GROUND_SIZE_Z * 0.44, GROUND_SIZE_Z * 0.44) + GROUND_CENTER_Z;

        central_exclusion := abs(x) < 4.8 && z > -18.0 && z < 5.0;
        hero_exclusion := length(.{x - 4.9, z + 5.6}) < 4.0;
        runner_exclusion := length(.{x + 6.8, z + 9.5}) < 4.5;
        teapot_exclusion := abs(x) < 14.0 && z > -18.0 && z < -3.0;
        if central_exclusion || hero_exclusion || runner_exclusion || teapot_exclusion {
            continue;
        }

        y := ground_height_at(x, z) + 0.015;
        scale := base_scale * random_get_within_range(0.8, 1.35);
        rotation_y := random_get_within_range(0.0, 2.0 * PI);
        q: Quaternion;
        set_from_axis_and_angle(*q, .{0.0, 1.0, 0.0}, rotation_y);
        array_add(placements, .{
            position = .{x, y, z},
            rotation = q,
            scale = scale,
        });
        array_add(root_transforms,
            make_translation_matrix4(.{x, y, z})
            * rotation_matrix(Matrix4, q)
            * make_scale_matrix4(.{scale, scale, scale}));
        accepted += 1;
    }
}

build_ground_plane_mesh :: (vertices: *[..]Scene_Vertex, indices: *[..]u32) {
    vertices.allocator = temp;
    indices.allocator = temp;
    array_reserve(vertices, (GROUND_GRID_X + 1) * (GROUND_GRID_Z + 1));
    array_reserve(indices, GROUND_GRID_X * GROUND_GRID_Z * 6);

    for z_step: 0..GROUND_GRID_Z {
        v := cast(float) z_step / cast(float) GROUND_GRID_Z;
        z := lerp(-GROUND_SIZE_Z * 0.5, GROUND_SIZE_Z * 0.5, v) + GROUND_CENTER_Z;
        for x_step: 0..GROUND_GRID_X {
            u := cast(float) x_step / cast(float) GROUND_GRID_X;
            x := lerp(-GROUND_SIZE_X * 0.5, GROUND_SIZE_X * 0.5, u);
            y := ground_height_at(x, z);
            n := ground_normal_at(x, z);
            array_add(vertices, .{
                position = .{x, y, z, 1.0},
                normal = .{n.x, n.y, n.z, 0.0},
                tangent = .{1.0, 0.0, 0.0, 1.0},
                uv = .{u * 13.0, v * 13.0},
            });
        }
    }

    stride := GROUND_GRID_X + 1;
    for z_step: 0..GROUND_GRID_Z-1 {
        for x_step: 0..GROUND_GRID_X-1 {
            i0 := cast(u32) (z_step * stride + x_step);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            array_add(indices, i0, i2, i1);
            array_add(indices, i1, i2, i3);
        }
    }
}

build_ground_height_samples :: (samples: *[..]float, grid_x: s64, grid_z: s64) {
    samples.allocator = temp;
    array_reserve(samples, (grid_x + 1) * (grid_z + 1));

    for z_step: 0..grid_z {
        v := cast(float) z_step / cast(float) grid_z;
        z := lerp(-GROUND_SIZE_Z * 0.5, GROUND_SIZE_Z * 0.5, v) + GROUND_CENTER_Z;
        for x_step: 0..grid_x {
            u := cast(float) x_step / cast(float) grid_x;
            x := lerp(-GROUND_SIZE_X * 0.5, GROUND_SIZE_X * 0.5, u);
            array_add(samples, ground_height_at(x, z));
        }
    }
}

build_model_mesh_collider_shape :: (geo: Scene_Geo, model_index: s32) -> Physics.Collider_Shape {
    model := geo.models[model_index];
    verts: [..]Vector3;
    tris: [..]u32;
    verts.allocator = temp;
    tris.allocator = temp;

    for mesh_index: model.mesh_start .. model.mesh_start + model.mesh_count - 1 {
        mesh := geo.meshes[mesh_index];
        vertex_base := cast(u32) verts.count;
        index_end := mesh.first_index + mesh.index_count;
        for idx_index: mesh.first_index .. index_end - 1 {
            vertex_index := geo.indices.cpu[idx_index];
            position4 := geo.vertices.cpu[vertex_index].position;
            array_add(*verts, .{position4.x, position4.y, position4.z});
            array_add(*tris, vertex_base + cast(u32) (idx_index - mesh.first_index));
        }
    }

    assert(verts.count > 0 && tris.count > 0, "Stone collider source mesh is empty for model %.", model.name);
    return Physics.create_mesh_shape(verts, tris);
}

ground_height_at :: (x: float, z: float) -> float {
    ridge := sin(x * 0.23 + z * 0.09) * 0.16;
    swell := cos(z * 0.18 - x * 0.05) * 0.11;
    warp := sin((x + z) * 0.11) * 0.07 + cos((x - z) * 0.07) * 0.05;
    flatten := 1.0 - smoothstep(0.0, 6.0, abs(x) * 0.38);
    return ridge + swell + warp - flatten * 0.05;
}

ground_normal_at :: (x: float, z: float) -> Vector3 {
    eps := 0.15;
    h_l := ground_height_at(x - eps, z);
    h_r := ground_height_at(x + eps, z);
    h_d := ground_height_at(x, z - eps);
    h_u := ground_height_at(x, z + eps);
    n := Vector3.{h_l - h_r, eps * 2.0, h_d - h_u};
    return normalize(n);
}

hash01 :: (x: u32) -> float {
    phase := cast(float) x * 12.9898 + 78.233;
    value := sin(phase) * cast(float) 43758.5453;
    return value - floor(value);
}

load_texture_rgba8 :: (path: string) -> Gpu_Texture, Gpu_Texture_View {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0, tprint("Failed to load texture: %", path));

    texture_result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(texture_result == .SUCCESS, tprint("Texture creation failed for %: %", path, texture_result));
    assert(texture != 0, tprint("Texture handle invalid for %", path));

    bgra_pixels: [..]u8;
    bgra_pixels.allocator = temp;
    array_resize(*bgra_pixels, cast(s64) width * cast(s64) height * 4);
    memcpy(bgra_pixels.data, pixels, bgra_pixels.count);
    i := 0;
    while i < bgra_pixels.count {
        r := bgra_pixels[i + 0];
        g := bgra_pixels[i + 1];
        b := bgra_pixels[i + 2];
        a := bgra_pixels[i + 3];
        bgra_pixels[i + 0] = b;
        bgra_pixels[i + 1] = g;
        bgra_pixels[i + 2] = r;
        bgra_pixels[i + 3] = a;
        i += 4;
    }
    gpu_copy_to_texture(texture, bgra_pixels.data);

    view := gpu_texture_view(texture);
    assert(view != 0, tprint("Texture view creation failed for %", path));

    return texture, view;
}

#load "../character_controller.jai";
#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../shadowmap.jai";
#load "../scene_geo.jai";
#load "../scene_anim.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
Physics :: #import "Physics";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Random";
#import "stb_image";
#import "Math";
#load "shaders/model_scene_shader.jai";
