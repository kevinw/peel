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

graphics_pipeline: Gpu_Pipeline;
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
scene_batches: [..]Draw_Batch;
animated_batches: [..]Animated_Batch;
running_lizard_instances: [..]Running_Lizard_Instance;
scene_debug_logged: bool;
autopilot_enabled: bool;
physics_gizmos_enabled: bool;
show_shadow_debug: bool = true;
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
        floor_half_extent = .{24.0, 1.0, 24.0},
        floor_center = .{0.0, -1.0, 0.0});
    Physics.init();
    Physics.debug_draw_enabled = false;

    graphics_source := cast([]u8) get_transpiled(.METAL, model_scene_vertex_main, model_scene_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for model scene shaders.");
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
    shadow_pipeline = gpu_create_graphics_pipeline(shadow_source, shadow_raster);
    assert(shadow_pipeline != 0, "Model scene shadow pipeline creation failed.");
    debug_shadow_pipeline = gpu_create_graphics_pipeline(debug_shadow_source, main_raster);
    assert(debug_shadow_pipeline != 0, "Model scene shadow debug pipeline creation failed.");
    shadow_map_init(*shadow_map);

    model_paths := string.[
        "./models/teapot.obj",
        "./models/nerdy+lizard+3d+model.glb",
        "./models/Lizard run.glb",
    ];
    scene_geo_init(*scene_geo, model_paths);

    teapot_model := scene_geo_model_index_by_name(*scene_geo, "teapot");
    lizard_model := scene_geo_model_index_by_name(*scene_geo, "nerdy+lizard+3d+model");
    running_lizard_model := scene_geo_model_index_by_name(*scene_geo, "Lizard run");
    assert(teapot_model >= 0 && lizard_model >= 0 && running_lizard_model >= 0, "Failed to resolve Scene_Geo model indices.");
    hero_lizard_bounds := scene_geo_model_bounds(*scene_geo, lizard_model);
    hero_lizard_size := hero_lizard_bounds.max - hero_lizard_bounds.min;
    hero_lizard_max_extent := max(max(hero_lizard_size.x, hero_lizard_size.y), hero_lizard_size.z);
    running_lizard_bounds := scene_geo_model_bounds(*scene_geo, running_lizard_model);
    running_lizard_size := running_lizard_bounds.max - running_lizard_bounds.min;
    running_lizard_max_extent := max(max(running_lizard_size.x, running_lizard_size.y), running_lizard_size.z);
    hero_lizard_world_scale := 12.0;
    running_lizard_target_extent := hero_lizard_max_extent * hero_lizard_world_scale * 0.4;
    running_lizard_scale = ifx running_lizard_max_extent > 0.0 then running_lizard_target_extent / running_lizard_max_extent else 1.0;
    running_lizard_ground_y = -running_lizard_bounds.min.y * running_lizard_scale + 0.7;
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

    grid_w :: 20;
    grid_h :: 25;
    spacing := 1.15;
    for y: 0..grid_h-1 {
        for x: 0..grid_w-1 {
            tx := (cast(float) x - cast(float) (grid_w - 1) * 0.5) * spacing;
            tz := (cast(float) y - cast(float) (grid_h - 1) * 0.5) * spacing - 16.0;
            height := sin(cast(float) x * 0.45) * 0.18 + cos(cast(float) y * 0.32) * 0.12;
            scale := 0.09 + 0.018 * sin(cast(float) (x + y) * 0.37);
            array_add(*root_transforms, make_translation_matrix4(.{tx, height, tz}) * make_scale_matrix4(.{scale, scale, scale}));
        }
    }
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, teapot_model, root_transforms, tint = .{0.94, 0.78, 0.48, 1.0});

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
            sampler_index = cast(u32) scene_geo.sampler - 1,
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
    Physics.deinit();
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
    if debug_shadow_pipeline != 0 gpu_free_pipeline(debug_shadow_pipeline);
    if shadow_pipeline != 0 gpu_free_pipeline(shadow_pipeline);
    shadow_map_deinit(*shadow_map);
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

    for *scene_draw_params.cpu {
        it.view_proj = view_proj;
        it.camera_pos = scene_camera.position;
        it.light_dir = shadow_map.light_dir;
    }

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
        for batch: scene_batches {
            if shadow_debug_isolate_animated {
                animated_index := find_animated_batch_index_for_batch(cast(s32) it_index);
                if animated_index < 0 continue;
                if shadow_debug_selected_animated_batch >= 0 && animated_index != shadow_debug_selected_animated_batch continue;
            }
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result := gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
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
        gpu_set_pipeline(cmd_buff, graphics_pipeline);

        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result := gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
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
#import "Math";
#load "shaders/model_scene_shader.jai";
