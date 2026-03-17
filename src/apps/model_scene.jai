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

Running_Lizard_Attachment_Instance :: struct {
    instance_index: u32;
    geo_node_index: s32;
    attachment_node_index: s32;
    _pad0: s32;
    attachment_offset: Matrix4;
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
grass_pipeline: Gpu_Pipeline;
grass_shadow_pipeline: Gpu_Pipeline;
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
scene_instances: Gpu_View(Scene_Instance);
scene_draw_params: Gpu_View(Scene_Draw_Params_CPU);
scene_skin_matrices: Gpu_View(Vector4);
scene_depth_texture: Gpu_Texture;
scene_depth_view: Gpu_Texture_View;
scene_depth_w: u32;
scene_depth_h: u32;
ground_vertices: Gpu_View(Scene_Vertex);
ground_indices: Gpu_View(u32);
ground_instance: Gpu_Buffer(Scene_Instance);
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
active_ground: Scene_File.Scene_Procedural_Ground_Desc;
grass_draw_params: Gpu_Buffer(Grass_Draw_Params);
grass_shadow_params: Gpu_Buffer(Grass_Draw_Params);
grass_instance_count: u32;
render_grass: bool = true;
ground_physics_body: u32;
ground_physics_body_valid: bool;
stone_physics_bodies: [..]u32;
stone_base_shapes: [..]Physics.Collider_Shape;
stone_scaled_shapes: [..]Physics.Collider_Shape;
scene_batches: [..]Draw_Batch;
animated_batches: [..]Animated_Batch;
running_lizard_instances: [..]Running_Lizard_Instance;
running_lizard_attachment_instances: [..]Running_Lizard_Attachment_Instance;
running_lizard_compiled_root_node_index: s32 = -1;
scene_doc: Scene_File.Scene_Document;
compiled_scene: Scene_File.Compiled_Scene;
scene_palette_models: [..]string;
scene_manip_ctx: Manip_Context;
scene_manip_objects: [..]Manip_Object;
scene_manip_node_indices: [..]s32;
scene_manip_objects_dirty: bool = true;
scene_manip_apply_pending: bool;
scene_dirty: bool;
scene_place_palette_index: s32 = -1;
scene_debug_logged: bool;
autopilot_enabled: bool;
physics_gizmos_enabled: bool;
show_shadow_debug: bool;
physics_g_was_down: bool;
control_mode: enum { Player; Editor; } = .Player;
p_was_down: bool;
orbit_yaw: float = 0.0;
orbit_pitch: float = -0.32;
orbit_distance: float = 8.5;
orbit_prev_mouse: Vector2;
orbit_have_prev_mouse: bool;
left_was_down: bool;
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
    ground_source := cast([]u8) get_transpiled(.METAL, ground_vertex_main, ground_fragment_main);
    shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_shadow_vertex_main, model_scene_shadow_fragment_main);
    grass_source := cast([]u8) get_transpiled(.METAL, model_scene_grass_vertex_main, model_scene_grass_fragment_main);
    grass_shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_grass_shadow_vertex_main, model_scene_grass_shadow_fragment_main);
    debug_shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_debug_shadow_vertex_main, model_scene_debug_shadow_fragment_main);

    main_raster: Gpu_Raster_Desc = .{
        cull = .CCW,
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
    grass_main_raster := main_raster;
    grass_main_raster.cull = .NONE;

    graphics_pipeline     = gpu_create_graphics_pipeline(graphics_source, main_raster);
    ground_pipeline       = gpu_create_graphics_pipeline(ground_source, main_raster);
    shadow_pipeline       = gpu_create_graphics_pipeline(shadow_source, shadow_raster);
    grass_pipeline        = gpu_create_graphics_pipeline(grass_source, grass_main_raster);
    grass_shadow_pipeline = gpu_create_graphics_pipeline(grass_shadow_source, shadow_raster);
    debug_shadow_pipeline = gpu_create_graphics_pipeline(debug_shadow_source, main_raster);
    shadow_map_init(*shadow_map);

    scene_palette_models = Scene_File.scan_scene_palette_models();
    scene_manip_objects.allocator = context.allocator;
    scene_manip_node_indices.allocator = context.allocator;
    running_lizard_attachment_instances.allocator = context.allocator;
    scene_doc, compiled_scene = Scene_File.load_compiled_scene_cached(SCENE_ROOT_PATH);
    init_scene_geo_from_palette();
    rebuild_scene_runtime();
    scene_manip_objects_dirty = true;
    scene_manip_apply_pending = false;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    clear_scene_runtime_resources();
    Scene_File.deinit(*scene_doc);
    Scene_File.deinit(*compiled_scene);
    for scene_palette_models free(it);
    array_free(scene_palette_models);
    array_free(scene_manip_node_indices);
    array_free(scene_manip_objects);
    array_free(stone_physics_bodies);
    array_free(stone_scaled_shapes);
    array_free(stone_base_shapes);
    Physics.deinit();
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
    if debug_shadow_pipeline != 0 gpu_free_pipeline(debug_shadow_pipeline);
    if grass_shadow_pipeline != 0 gpu_free_pipeline(grass_shadow_pipeline);
    if grass_pipeline != 0 gpu_free_pipeline(grass_pipeline);
    if shadow_pipeline != 0 gpu_free_pipeline(shadow_pipeline);
    if ground_pipeline != 0 gpu_free_pipeline(ground_pipeline);
    shadow_map_deinit(*shadow_map);
    array_free(running_lizard_instances);
    array_free(running_lizard_attachment_instances);
    array_free(animated_batches);
    array_free(scene_batches);
    scene_geo_deinit(*scene_geo);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
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
        if #complete control_mode == {
        case .Player; control_mode = .Editor;
        case .Editor; control_mode = .Player;
        }
    }
    p_was_down = p_down;

    if app_ui_enabled {
        using ImGui;
        if Begin("Model Scene", flags = .NoCollapse | .AlwaysAutoResize) {
            Checkbox("Autopilot", *autopilot_enabled);
            if Checkbox("Physics Gizmos", *physics_gizmos_enabled) {
                Physics.debug_draw_enabled = physics_gizmos_enabled;
            }
            Checkbox("Render Grass", *render_grass);
            Checkbox("Show Shadow Debug", *show_shadow_debug);
            if animated_batches.count > 0 {
                max_batch_index := cast(s32) animated_batches.count - 1;
            }
            Separator();
            if Button("Save Scene") {
                scene_dirty = !Scene_File.save_scene_document(scene_doc);
            }
            SameLine();
            if Button("Reload Scene") {
                Scene_File.deinit(*compiled_scene);
                compiled_scene = Scene_File.recompile_scene_document(scene_doc);
                rebuild_scene_runtime();
                scene_manip_objects_dirty = true;
                scene_manip_apply_pending = false;
                scene_dirty = false;
            }
            is_editor := control_mode == .Editor;
            if toggle("Toggle Editor (P)", *is_editor) {
                control_mode = ifx is_editor then .Editor else .Player;
            }
            if control_mode == .Editor {
                Text("%", ifx scene_dirty then "Scene Dirty" else "Scene Saved");
                if scene_place_palette_index >= 0 {
                    Text("Placing: %", String.path_filename(scene_palette_models[scene_place_palette_index]));
                    SameLine();
                    if Button("Cancel Placement") scene_place_palette_index = -1;
                }
                if BeginChild("Palette", .{340.0, 220.0}) {
                    for scene_palette_models {
                        selected := cast(s32) it_index == scene_place_palette_index;
                        label := String.path_filename(it);
                        if Selectable(temp_c_string(label), selected) {
                            scene_place_palette_index = cast(s32) it_index;
                        }
                    }
                }
                EndChild();
                Separator();
            }
            if #complete control_mode == {
            case .Player;
                Text("Move Lizard: WASD / Orbit Camera: RMB drag");
            case .Editor;
                Text("Fly Camera: WASD/QE - Look Camera: RMB drag");
                Text("Edit: LMB select/drag gizmo");
            }
            Text("Toggle Gizmos: G");
        }
        End();
    }

    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    left_pressed := left_down && !left_was_down;
    left_released := !left_down && left_was_down;
    left_was_down = left_down;

    controller_forward, controller_right, controller_up: Vector3;
    if #complete control_mode == {
    case .Player;
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
        controller_forward = .{sin(orbit_yaw), 0.0, -cos(orbit_yaw)};
        controller_right = .{cos(orbit_yaw), 0.0, sin(orbit_yaw)};
        controller_up = .{0.0, 1.0, 0.0};
    case .Editor;
        _ = editor_camera_update(*scene_camera, dt, mx, my, mouse_ok,
            allow_move = !io.WantCaptureKeyboard,
            allow_look = right_down && !io.WantCaptureMouse);
        editor_camera_basis(*scene_camera, *controller_forward, *controller_right, *controller_up);
    }

    controller_forward.y = 0.0;
    controller_right.y = 0.0;
    normalize(*controller_forward, fallback = .{0.0, 0.0, -1.0});
    normalize(*controller_right, fallback = .{1.0, 0.0, 0.0});

    desired_move: Vector3;
    if #complete control_mode == {
    case .Player;
        if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN desired_move += controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN desired_move -= controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN desired_move -= controller_right;
        if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN desired_move += controller_right;
    case .Editor;
        //
    }

    if autopilot_enabled && dot(desired_move, desired_move) < 1.0e-6 {
        autopilot_center := Vector3.{-6.8, running_lizard_ground_y, -9.5};
        autopilot_radius := 3.8;
        autopilot_target := autopilot_center + .{
            cos(cast(float) time * 0.35) * autopilot_radius, 0.0, sin(cast(float) time * 0.35) * autopilot_radius,
        };
        desired_move = autopilot_target - character_controller_position(*running_lizard_controller);
    }

    Gizmo.begin_frame(*gizmo_ctx);
    character_controller_update_in_system(*running_lizard_controller, Physics.physics.system, desired_move, dt);
    Physics.tick(dt);
    if physics_gizmos_enabled {
        append_lizard_physics_gizmos();
    }

    if control_mode == .Editor && dims_ok && win_w > 0 && win_h > 0 {
        if scene_manip_objects_dirty {
            scene_rebuild_manip_objects();
            scene_manip_objects_dirty = false;
        }
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(*scene_camera, *cam_forward, *cam_right, *cam_up);
        frame := Manip_Frame_Input.{
            viewport = .{cast(float) win_w, cast(float) win_h},
            camera_pos = scene_camera.position,
            camera_forward = cam_forward,
            camera_right = cam_right,
            camera_up = cam_up,
            fov_y = PI / 3.2,
            mouse_pos = .{cast(float) mx, cast(float) my},
            mouse_valid = mouse_ok,
            mouse_down = left_down,
            mouse_pressed = left_pressed,
            mouse_released = left_released,
            block_mouse = io.WantCaptureMouse,
        };
        if scene_place_palette_index >= 0 && left_pressed && !io.WantCaptureMouse {
            scene_place_selected_palette_at_cursor(frame);
        } else {
            manip_result := manip_update(*scene_manip_ctx, *gizmo_ctx, scene_manip_objects, frame);
            if manip_result.changed {
                scene_manip_apply_pending = true;
            }
            if scene_manip_apply_pending && left_released {
                scene_apply_manip_back_to_doc();
                scene_manip_apply_pending = false;
            }
        }
    }

    if control_mode == .Player {
        player_focus := character_controller_position(*running_lizard_controller) + .{0.0, 0.95, 0.0};
        orbit_dir := Vector3.{ sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), -cos(orbit_yaw) * cos(orbit_pitch) };
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
    for running_lizard_attachment_instances {
        attachment_world := running_lizard_root;
        attachment_local_index := it.attachment_node_index - cast(s32) running_lizard_model.node_start;
        if attachment_local_index >= 0 && attachment_local_index < running_lizard_anim.worlds.count {
            attachment_world = running_lizard_root * running_lizard_anim.worlds[attachment_local_index];
        }
        scene_instances.cpu[it.instance_index].world = attachment_world * it.attachment_offset * scene_geo.nodes[it.geo_node_index].world;
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
        it.shadow_view_proj = shadow_map.view_proj;
        it.shadow_meta = shadow_binding;
    }
    ground_instance.cpu.shadow_view_proj = shadow_map.view_proj;
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
    if grass_draw_params.cpu != null {
        lizard_pos := character_controller_position(*running_lizard_controller);
        grass_shadow_params.cpu.view_proj = view_proj;
        grass_shadow_params.cpu.shadow_view_proj = shadow_map.view_proj;
        grass_shadow_params.cpu.camera_pos = scene_camera.position;
        grass_shadow_params.cpu.light_dir = shadow_map.light_dir;
        grass_shadow_params.cpu.shadow_meta = shadow_binding;
        grass_shadow_params.cpu.ground_size_center_z_time = .{active_ground.size_x, active_ground.size_z, active_ground.center_z, cast(float) time};
        grass_shadow_params.cpu.ground_shape = .{active_ground.ridge, active_ground.swell, active_ground.warp, 0.0};
        grass_shadow_params.cpu.player_pos_radius = .{lizard_pos.x, lizard_pos.y, lizard_pos.z, 1.9};
        grass_draw_params.cpu.* = grass_shadow_params.cpu.*;
    }

    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, view_proj);

    if !scene_debug_logged scene_debug_logged = true;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);

    {
        saved_shadow_skin_counts: [..]u32;
        defer array_free(saved_shadow_skin_counts);

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
        if render_grass && grass_shadow_params.cpu != null && grass_instance_count > 0 {
            gpu_set_pipeline(cmd_buff, grass_shadow_pipeline);
            draw_result = gpu_draw_instanced_direct(cmd_buff, grass_shadow_params.gpu, 6, grass_instance_count);
            gpu_set_pipeline(cmd_buff, shadow_pipeline);
        }
        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
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
        if render_grass && grass_draw_params.cpu != null && grass_instance_count > 0 {
            gpu_set_pipeline(cmd_buff, grass_pipeline);
            draw_result = gpu_draw_instanced_direct(cmd_buff, grass_draw_params.gpu, 6, grass_instance_count);
        }

        gpu_set_pipeline(cmd_buff, graphics_pipeline);

        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }

        if physics_gizmos_enabled {
            draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .TEST);
        }

        if show_shadow_debug {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_shadow_pipeline);
            draw_result := gpu_draw_instanced_direct(cmd_buff, scene_draw_params.gpu, 6, 1);
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
    scene_depth_view = gpu_texture_view(scene_depth_texture);
    scene_depth_w = width;
    scene_depth_h = height;
    gpu_commit_residency();
}

append_lizard_physics_gizmos :: () {
    lizard_pos := character_controller_position(*running_lizard_controller);
    lizard_forward := Vector3.{ sin(running_lizard_controller.facing_yaw), 0.0, cos(running_lizard_controller.facing_yaw) };
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

init_scene_geo_from_palette :: () {
    model_paths: [..]string;
    model_paths.allocator = temp;
    for scene_palette_models array_add(*model_paths, it);
    scene_geo_init(*scene_geo, model_paths);
}

rebuild_scene_runtime :: () {
    clear_scene_runtime_resources();

    root_transforms: [..]Matrix4;
    root_transforms.allocator = temp;
    instances_cpu: [..]Scene_Instance;
    instances_cpu.allocator = temp;
    collider_model_indices: [..]s32;
    collider_model_indices.allocator = temp;

    array_reset(*scene_batches);
    array_reset(*animated_batches);
    array_reset(*running_lizard_instances);
    array_reset(*running_lizard_attachment_instances);
    running_lizard_compiled_root_node_index = -1;
    running_lizard_clip_index = -1;
    running_lizard_scale = 1.0;
    running_lizard_ground_y = 0.0;
    autopilot_enabled = false;
    active_ground = .{};

    total_skin_matrix_count: s64 = 0;
    ground_enabled := false;

    for compiled_scene.nodes {
        if it.ground.enabled {
            ground_enabled = true;
            active_ground = it.ground;
            continue;
        }

        if it.scatter.enabled {
            append_compiled_scatter_instances(*instances_cpu, *root_transforms, *total_skin_matrix_count, *collider_model_indices, cast(s32) it_index);
            continue;
        }

        if running_lizard_compiled_root_node_index >= 0 && compiled_node_is_under_player_root(cast(s32) it_index) {
            continue;
        }

        if #complete it.render_kind == {
        case .MESH;
            if it.asset_index < 0 continue;
            model_index := scene_model_index_for_compiled_asset(it.asset_index);
            if model_index < 0 continue;
            array_reset(*root_transforms);
            array_add(*root_transforms, it.world * compiled_asset_import_matrix(compiled_scene.assets[it.asset_index]));
            scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, model_index, root_transforms);
            continue;
        case .SKINNED_MESH;
            if it.behavior.type_name == "Player_Controller" {
                running_lizard_scale, running_lizard_ground_y = init_player_from_compiled_node(*instances_cpu, *total_skin_matrix_count, cast(s32) it_index);
                autopilot_enabled = it.behavior.autopilot;
                continue;
            }

            if it.asset_index < 0 continue;
            model_index := scene_model_index_for_compiled_asset(it.asset_index);
            if model_index < 0 continue;
            array_reset(*root_transforms);
            array_add(*root_transforms, it.world * compiled_asset_import_matrix(compiled_scene.assets[it.asset_index]));
            scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, model_index, root_transforms);
        case .NONE;
            // nothing to do.
        }
    }

    if ground_enabled init_ground_plane(active_ground);

    arena_bytes :=
        max(cast(s64) 1, instances_cpu.count) * size_of(Scene_Instance) +
        max(cast(s64) 1, scene_batches.count) * size_of(Scene_Draw_Params_CPU) +
        max(cast(s64) 1, total_skin_matrix_count * 4) * size_of(Vector4) +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "model scene arena");
    assert(gpu_arena.cpu != null, "Model scene arena creation failed.");

    scene_instances = gpu_alloc_view(*gpu_arena, Scene_Instance, instances_cpu.count);
    if instances_cpu.count > 0 memcpy(scene_instances.cpu.data, instances_cpu.data, instances_cpu.count * size_of(Scene_Instance));

    if total_skin_matrix_count > 0 scene_skin_matrices = gpu_alloc_view(*gpu_arena, Vector4, total_skin_matrix_count * 4);

    scene_draw_params = gpu_alloc_view(*gpu_arena, Scene_Draw_Params_CPU, scene_batches.count);
    for batch: scene_batches {
        mesh := scene_geo.meshes[batch.mesh_index];
        scene_draw_params.cpu[it_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = scene_instances.gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr),
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

    gpu_commit_residency();
}

clear_scene_runtime_resources :: () {
    controller_deinit(*running_lizard_controller);
    scene_anim_deinit(*running_lizard_anim);

    for stone_physics_bodies Physics.destroy_body(it);
    array_reset(*stone_physics_bodies);
    for *stone_scaled_shapes Physics.destroy_shape(it);
    array_reset(*stone_scaled_shapes);
    for *stone_base_shapes Physics.destroy_shape(it);
    array_reset(*stone_base_shapes);

    if ground_physics_body_valid {
        Physics.destroy_body(ground_physics_body);
        ground_physics_body_valid = false;
        ground_physics_body = 0;
    }

    if scene_depth_view != 0 {
        gpu_free_texture_view(scene_depth_view);
        scene_depth_view = 0;
    }
    if scene_depth_texture != 0 {
        gpu_free(scene_depth_texture);
        scene_depth_texture = 0;
    }
    scene_depth_w = 0;
    scene_depth_h = 0;



    if ground_ao_texture_view != 0 gpu_free_texture_view(ground_ao_texture_view);
    if ground_ao_texture != 0 gpu_free(ground_ao_texture);
    gpu_delete(*ground_sampler);
    gpu_delete(*grass_draw_params);
    gpu_delete(*grass_shadow_params);
    if ground_roughness_texture_view != 0 gpu_free_texture_view(ground_roughness_texture_view);
    if ground_roughness_texture != 0 gpu_free(ground_roughness_texture);
    if ground_normal_texture_view != 0 gpu_free_texture_view(ground_normal_texture_view);
    if ground_normal_texture != 0 gpu_free(ground_normal_texture);
    if ground_texture_view != 0 gpu_free_texture_view(ground_texture_view);
    if ground_texture != 0 gpu_free(ground_texture);
    gpu_delete(*ground_draw_params);
    gpu_delete(*ground_shadow_params);
    gpu_delete(*ground_instance);
    gpu_delete(*ground_indices);
    gpu_delete(*ground_vertices);
    ground_texture = 0;
    ground_texture_view = 0;
    ground_normal_texture = 0;
    ground_normal_texture_view = 0;
    ground_roughness_texture = 0;
    ground_roughness_texture_view = 0;
    ground_ao_texture = 0;
    ground_ao_texture_view = 0;
    grass_instance_count = 0;
    ground_index_count = 0;

    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
    gpu_arena = .{};
    scene_instances = .{};
    scene_draw_params = .{};
    scene_skin_matrices = .{};

    array_reset(*running_lizard_instances);
    array_reset(*animated_batches);
    array_reset(*scene_batches);
}

append_compiled_scatter_instances :: (instances_cpu: *[..]Scene_Instance, root_transforms: *[..]Matrix4, total_skin_matrix_count: *s64, collider_model_indices: *[..]s32, node_index: s32) {
    node := compiled_scene.nodes[node_index];
    random_seed(node.scatter.seed);
    for 0..node.scatter.count-1 {
        if node.scatter.assets.count == 0 break;
        asset_name := node.scatter.assets[cast(s64) (random_get_within_range(0.0, cast(float) node.scatter.assets.count))];
        asset_index := compiled_scene_find_asset_index_by_name_for_runtime(asset_name);
        if asset_index < 0 continue;
        model_index := scene_model_index_for_compiled_asset(asset_index);
        if model_index < 0 continue;

        x := random_get_within_range(node.scatter.x_min, node.scatter.x_max);
        z := random_get_within_range(node.scatter.z_min, node.scatter.z_max);
        y := random_get_within_range(node.scatter.y_min, node.scatter.y_max);
        if node.scatter.mode == .GROUND {
            y = ground_height_at(ground_plane_desc, x, z) + node.scatter.ground_y_offset;
        }
        yaw_deg := random_get_within_range(node.scatter.yaw_min_deg, node.scatter.yaw_max_deg);
        target_extent := random_get_within_range(node.scatter.scale_min, node.scatter.scale_max);
        asset := compiled_scene.assets[asset_index];
        model_scale := normalized_model_scale(asset, model_index, target_extent);
        q: Quaternion;
        set_from_axis_and_angle(*q, .{0.0, 1.0, 0.0}, yaw_deg * PI / 180.0);

        scatter_world := node.world
            * make_trs_matrix(.{x, y, z}, q, model_scale)
            * compiled_asset_import_matrix(asset);

        array_reset(root_transforms);
        array_add(root_transforms, scatter_world);
        scene_geo_append_model_instances(*scene_batches, instances_cpu, *scene_geo, model_index, root_transforms.*, tint = .{0.92, 0.9, 0.88, 1.0});

        base_shape := get_or_create_collider_base_shape(collider_model_indices, model_index);
        scaled_shape := Physics.create_scaled_shape(base_shape, asset_import_scale(asset) * model_scale);
        array_add(*stone_scaled_shapes, scaled_shape);
        world_pos, world_rot_deg, world_scale_vec := decompose_matrix_trs(scatter_world);
        _ = world_scale_vec;
        body := Physics.create_static_body_from_shape(scaled_shape, world_pos, quat_from_euler_deg(world_rot_deg));
        array_add(*stone_physics_bodies, body);
    }
}

get_or_create_collider_base_shape :: (collider_model_indices: *[..]s32, model_index: s32) -> Physics.Collider_Shape {
    for collider_model_indices.* {
        if it == model_index return stone_base_shapes[it_index];
    }
    shape := build_model_mesh_collider_shape(scene_geo, model_index);
    array_add(collider_model_indices, model_index);
    array_add(*stone_base_shapes, shape);
    return shape;
}

init_player_from_compiled_node :: (instances_cpu: *[..]Scene_Instance, total_skin_matrix_count: *s64, node_index: s32) -> float, float {
    node := compiled_scene.nodes[node_index];
    running_lizard_compiled_root_node_index = node_index;
    assert(node.asset_index >= 0, "Player controller node '%' is missing an asset.", node.name);
    model_index := scene_model_index_for_compiled_asset(node.asset_index);
    assert(model_index >= 0, "Failed to resolve player model '%'.", node.name);
    clip_name := ifx node.clip_name.count > 0 then node.clip_name else "Run";
    clip_index := scene_geo_model_clip_index_by_name(*scene_geo, model_index, clip_name);
    if clip_index < 0 clip_index = cast(s32) scene_geo.models[model_index].anim_clip_start;
    running_lizard_clip_index = clip_index;
    scene_anim_init(*running_lizard_anim, *scene_geo, model_index, clip_index);

    start_pos, start_rot_deg, start_scale := decompose_matrix_trs(node.world * compiled_asset_import_matrix(compiled_scene.assets[node.asset_index]));
    running_lizard_scale = max(max(start_scale.x, start_scale.y), start_scale.z);
    running_lizard_bounds := scene_geo_model_bounds(*scene_geo, model_index);
    running_lizard_ground_y = -running_lizard_bounds.min.y * running_lizard_scale - 0.2;

    character_controller_init_in_system(
        *running_lizard_controller,
        Physics.physics.system,
        .{start_pos.x, running_lizard_ground_y, start_pos.z},
        visual_yaw_offset = start_rot_deg.y * PI / 180.0);

    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    running_lizard_model_info := scene_geo.models[model_index];
    for geo_node_index: running_lizard_model_info.node_start .. running_lizard_model_info.node_start + running_lizard_model_info.node_count - 1 {
        geo_node := scene_geo.nodes[geo_node_index];
        if geo_node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..geo_node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[geo_node.first_mesh_ref + mesh_ref_offset];
            mesh := scene_geo.meshes[mesh_index];
            batch := array_add(*scene_batches);
            batch.mesh_index = mesh_index;
            batch.first_instance = cast(u32) instances_cpu.count;
            batch.instance_count = 1;

            instance_index := cast(u32) instances_cpu.count;
            array_add(instances_cpu, .{
                world = running_lizard_root,
                tint = .{1.0, 1.0, 1.0, 1.0},
                shadow_view_proj = Matrix4_Identity,
                //shadow_view_proj_0 = .{1.0, 0.0, 0.0, 0.0},
                //shadow_view_proj_1 = .{0.0, 1.0, 0.0, 0.0},
                //shadow_view_proj_2 = .{0.0, 0.0, 1.0, 0.0},
                //shadow_view_proj_3 = .{0.0, 0.0, 0.0, 1.0},
            });
            array_add(*running_lizard_instances, .{
                instance_index = instance_index,
                node_index = cast(s32) geo_node_index,
                mesh_index = mesh_index,
            });

            if mesh.skin_bone_count > 0 {
                array_add(*animated_batches, .{
                    batch_index = cast(s32) scene_batches.count - 1,
                    node_index = cast(s32) geo_node_index,
                    skin_matrix_start = cast(u32) total_skin_matrix_count.*,
                    skin_matrix_count = mesh.skin_bone_count,
                });
                total_skin_matrix_count.* += mesh.skin_bone_count;
            }
        }
    }

    attachment_node_index := node.first_child_index;
    while attachment_node_index >= 0 {
        attachment_node := compiled_scene.nodes[attachment_node_index];
        if attachment_node.render_kind == .MESH && attachment_node.asset_index >= 0 {
            attachment_model_index := scene_model_index_for_compiled_asset(attachment_node.asset_index);
            if attachment_model_index >= 0 {
                anchor_geo_node_index := running_lizard_model_info.root_node_index;
                if attachment_node.attach_node_name.count > 0 {
                    resolved_anchor := scene_geo_model_node_index_by_name(*scene_geo, model_index, attachment_node.attach_node_name);
                    if resolved_anchor >= 0 {
                        anchor_geo_node_index = resolved_anchor;
                    } else {
                        log("PLAYER_ATTACH unresolved attach_node '%' on '%', falling back to player root.", attachment_node.attach_node_name, attachment_node.name);
                    }
                }
                attachment_offset :=
                    make_trs_matrix(attachment_node.local_position, quat_from_euler_deg(attachment_node.local_rotation_deg), attachment_node.local_scale)
                    * compiled_asset_import_matrix(compiled_scene.assets[attachment_node.asset_index]);
                attachment_model := scene_geo.models[attachment_model_index];
                for geo_node_index: attachment_model.node_start .. attachment_model.node_start + attachment_model.node_count - 1 {
                    geo_node := scene_geo.nodes[geo_node_index];
                    if geo_node.mesh_ref_count == 0 continue;
                    for mesh_ref_offset: 0..geo_node.mesh_ref_count-1 {
                        mesh_index := scene_geo.node_mesh_refs[geo_node.first_mesh_ref + mesh_ref_offset];
                        batch := array_add(*scene_batches);
                        batch.mesh_index = mesh_index;
                        batch.first_instance = cast(u32) instances_cpu.count;
                        batch.instance_count = 1;

                        instance_index := cast(u32) instances_cpu.count;
                        array_add(instances_cpu, .{
                            world = running_lizard_root * attachment_offset * scene_geo.nodes[geo_node_index].world,
                            tint = .{1.0, 1.0, 1.0, 1.0},
                            shadow_view_proj = Matrix4_Identity,
                        });
                        array_add(*running_lizard_attachment_instances, .{
                            instance_index = instance_index,
                            geo_node_index = cast(s32) geo_node_index,
                            attachment_node_index = anchor_geo_node_index,
                            attachment_offset = attachment_offset,
                        });
                    }
                }
            }
        }
        attachment_node_index = compiled_scene.nodes[attachment_node_index].next_sibling_index;
    }

    return running_lizard_scale, running_lizard_ground_y;
}

scene_model_index_for_compiled_asset :: (asset_index: s32) -> s32 {
    if asset_index < 0 || asset_index >= compiled_scene.assets.count return -1;
    asset := compiled_scene.assets[asset_index];
    model_name := String.path_strip_extension(String.path_filename(asset.model_path));
    return scene_geo_model_index_by_name(*scene_geo, model_name);
}

compiled_asset_import_matrix :: (asset: Scene_File.Scene_Asset_Desc) -> Matrix4 {
    return rotation_matrix(Matrix4, quat_from_euler_deg(asset.import_settings.rotation_deg))
        * make_scale_matrix4(asset.import_settings.scale);
}

compiled_scene_find_asset_index_by_name_for_runtime :: (asset_name: string) -> s32 {
    for compiled_scene.assets if it.name == asset_name return cast(s32) it_index;
    return -1;
}

normalized_model_scale :: (asset: Scene_File.Scene_Asset_Desc, model_index: s32, target_extent: float) -> float {
    bounds := scene_geo_model_bounds(*scene_geo, model_index);
    size := bounds.max - bounds.min;
    import_scale := asset_import_scale(asset);
    scaled_size := size * import_scale;
    max_extent := max(max(scaled_size.x, scaled_size.y), scaled_size.z);
    return ifx max_extent > 0.0 then target_extent / max_extent else 1.0;
}

asset_import_scale :: (asset: Scene_File.Scene_Asset_Desc) -> Vector3 {
    scale := asset.import_settings.scale;
    if abs(scale.x) <= 1.0e-6 scale.x = 1.0;
    if abs(scale.y) <= 1.0e-6 scale.y = 1.0;
    if abs(scale.z) <= 1.0e-6 scale.z = 1.0;
    return abs(scale);
}

decompose_matrix_trs :: (m: Matrix4) -> Vector3, Vector3, Vector3 {
    ai_scale: ai.Vector3D;
    ai_rotation: ai.Vector3D;
    ai_position: ai.Vector3D;
    temp_m := m;
    ai.Matrix4DecomposeIntoScalingEulerAnglesPosition(cast(*ai.Matrix4x4) *temp_m, *ai_scale, *ai_rotation, *ai_position);
    return
        cast,force(Vector3) ai_position,
        cast,force(Vector3) ai_rotation * (180.0 / PI),
        cast,force(Vector3) ai_scale;
}

quat_from_euler_deg :: (deg: Vector3) -> Quaternion {
    radians := deg * (PI / 180.0);
    hx := radians.x * 0.5;
    hy := radians.y * 0.5;
    hz := radians.z * 0.5;
    cx := cos(hx); sx := sin(hx);
    cy := cos(hy); sy := sin(hy);
    cz := cos(hz); sz := sin(hz);
    qx := Quaternion.{x = sx, y = 0.0, z = 0.0, w = cx};
    qy := Quaternion.{x = 0.0, y = sy, z = 0.0, w = cy};
    qz := Quaternion.{x = 0.0, y = 0.0, z = sz, w = cz};
    q := qz * qy * qx;
    normalize_or_identity(*q);
    return q;
}

scene_rebuild_manip_objects :: () {
    array_reset(*scene_manip_objects);
    array_reset(*scene_manip_node_indices);

    for scene_doc.nodes {
        if it.ground.enabled || it.scatter.enabled continue;
        if it.render_kind == .NONE && it.instance_scene_path.count == 0 continue;
        compiled_index := find_compiled_node_for_source(scene_doc.source_path, it.name);
        if compiled_index < 0 continue;
        compiled_node := compiled_scene.nodes[compiled_index];
        pos, rot_deg, scale := decompose_matrix_trs(compiled_node.world);

        half_extents := Vector3.{0.4, 0.4, 0.4};
        if compiled_node.asset_index >= 0 {
            model_index := scene_model_index_for_compiled_asset(compiled_node.asset_index);
            if model_index >= 0 {
                bounds := scene_geo_model_bounds(*scene_geo, model_index);
                size := bounds.max - bounds.min;
                base_extent := max(max(size.x, size.y), size.z);
                if base_extent > 0.0 {
                    import_scale := asset_import_scale(compiled_scene.assets[compiled_node.asset_index]);
                    object_scale := scale * import_scale;
                    half_extents = 0.5 * size * max(max(object_scale.x, object_scale.y), object_scale.z) / base_extent;
                }
            }
        }

        array_add(*scene_manip_objects, .{
            name = it.name,
            position = pos,
            rotation = quat_from_euler_deg(rot_deg),
            scale = scale,
            half_extents = max(half_extents, Vector3.{0.2, 0.2, 0.2}),
            color = .{0.85, 0.8, 0.35, 1.0},
        });
        array_add(*scene_manip_node_indices, cast(s32) it_index);
    }
}

scene_apply_manip_back_to_doc :: () {
    if scene_manip_ctx.selected_index < 0 return;
    selected := cast(s64) scene_manip_ctx.selected_index;
    if selected >= scene_manip_objects.count return;
    node_index := scene_manip_node_indices[selected];
    obj := scene_manip_objects[selected];
    doc_node := *scene_doc.nodes[node_index];

    world := make_trs_matrix(obj.position, obj.rotation, obj.scale);
    parent_world := Matrix4_Identity;
    if doc_node.parent_index >= 0 {
        parent_compiled_index := find_compiled_node_for_source(scene_doc.source_path, scene_doc.nodes[doc_node.parent_index].name);
        if parent_compiled_index >= 0 parent_world = compiled_scene.nodes[parent_compiled_index].world;
    }
    inv_ok, parent_inv := inverse(parent_world);
    assert(inv_ok, "Failed to invert parent transform during scene manipulation.");
    local := parent_inv * world;
    local_pos, local_rot_deg, local_scale := decompose_matrix_trs(local);
    doc_node.position = local_pos;
    doc_node.rotation_deg = local_rot_deg;
    doc_node.scale = local_scale;
    scene_dirty = true;

    Scene_File.deinit(*compiled_scene);
    compiled_scene = Scene_File.recompile_scene_document(scene_doc);
    rebuild_scene_runtime();
    scene_manip_objects_dirty = true;
}

scene_place_selected_palette_at_cursor :: (frame: Manip_Frame_Input) {
    if scene_place_palette_index < 0 || cast(s64) scene_place_palette_index >= scene_palette_models.count {
        log("SCENE_PLACE aborted: invalid palette index=% model_count=%", scene_place_palette_index, scene_palette_models.count);
        return;
    }
    ray_origin, ray_dir, ray_ok := scene_mouse_world_ray(frame);
    log("SCENE_PLACE ray: ok=% origin=% dir=% mouse=% viewport=%", ray_ok, ray_origin, ray_dir, frame.mouse_pos, frame.viewport);
    if !ray_ok return;
    hit, p := scene_ray_intersect_plane(ray_origin, ray_dir, .{0.0, 0.0, 0.0}, .{0.0, 1.0, 0.0});
    log("SCENE_PLACE plane hit: hit=% point=%", hit, p);
    if !hit return;
    p.y = ground_height_at(ground_plane_desc, p.x, p.z);
    model_path := scene_palette_models[scene_place_palette_index];
    log("SCENE_PLACE placing model=% at point=%", model_path, p);
    new_node := Scene_File.place_palette_model(*scene_doc, scene_palette_models[scene_place_palette_index], p);
    log("SCENE_PLACE new node index=% total_nodes=%", new_node, scene_doc.nodes.count);
    scene_dirty = true;
    scene_place_palette_index = -1;
    Scene_File.deinit(*compiled_scene);
    compiled_scene = Scene_File.recompile_scene_document(scene_doc);
    log("SCENE_PLACE recompiled scene: compiled_nodes=% compiled_assets=%", compiled_scene.nodes.count, compiled_scene.assets.count);
    rebuild_scene_runtime();
    scene_manip_objects_dirty = true;
    scene_rebuild_manip_objects();
    scene_manip_objects_dirty = false;
    for scene_manip_node_indices if it == new_node scene_manip_ctx.selected_index = cast(s32) it_index;
    log("SCENE_PLACE selected manip index=%", scene_manip_ctx.selected_index);
}

find_compiled_node_for_source :: (source_path: string, node_name: string) -> s32 {
    for compiled_scene.nodes {
        if it.source_path == source_path && it.name == node_name return cast(s32) it_index;
    }
    return -1;
}

compiled_node_is_under_player_root :: (node_index: s32) -> bool {
    if running_lizard_compiled_root_node_index < 0 return false;
    if node_index == running_lizard_compiled_root_node_index return false;
    probe := compiled_scene.nodes[node_index].parent_index;
    while probe >= 0 {
        if probe == running_lizard_compiled_root_node_index return true;
        probe = compiled_scene.nodes[probe].parent_index;
    }
    return false;
}

scene_mouse_world_ray :: (frame: Manip_Frame_Input) -> Vector3, Vector3, bool {
    if !frame.mouse_valid {
        log("SCENE_PLACE ray failed: mouse invalid");
        return .{}, .{}, false;
    }
    if frame.viewport.x <= 1.0 || frame.viewport.y <= 1.0 {
        log("SCENE_PLACE ray failed: viewport too small=%", frame.viewport);
        return .{}, .{}, false;
    }
    nx := ((frame.mouse_pos.x + 0.5) / frame.viewport.x) * 2.0 - 1.0;
    ny := ((frame.mouse_pos.y + 0.5) / frame.viewport.y) * 2.0 - 1.0;
    aspect := frame.viewport.x / max(frame.viewport.y, 1.0);
    tan_half_fov := tan(frame.fov_y * 0.5);
    dir := frame.camera_forward + frame.camera_right * (nx * aspect * tan_half_fov) + frame.camera_up * (ny * tan_half_fov);
    normalize(*dir, fallback = frame.camera_forward);
    return frame.camera_pos, dir, true;
}

scene_ray_intersect_plane :: (ray_origin: Vector3, ray_dir: Vector3, plane_origin: Vector3, plane_normal: Vector3) -> bool, Vector3 {
    denom := dot(ray_dir, plane_normal);
    if abs(denom) <= 0.00001 {
        log("SCENE_PLACE plane miss: parallel denom=%", denom);
        return false, .{};
    }
    t := dot(plane_origin - ray_origin, plane_normal) / denom;
    if t <= 0.00001 {
        log("SCENE_PLACE plane miss: behind origin t=%", t);
        return false, .{};
    }
    return true, ray_origin + ray_dir * t;
}

SCENE_ROOT_PATH :: "./scenes/model_scene.scene";

ground_plane_desc: Scene_File.Scene_Procedural_Ground_Desc;

init_ground_plane :: (ground: Scene_File.Scene_Procedural_Ground_Desc) {
    ground_plane_desc = ground;

    ground_texture, ground_texture_view = load_texture_rgba8(ground.base_color_path);
    ground_normal_texture, ground_normal_texture_view = load_texture_rgba8(ground.normal_path);
    ground_roughness_texture, ground_roughness_texture_view = load_texture_rgba8(ground.roughness_path);
    ground_ao_texture, ground_ao_texture_view = load_texture_rgba8(ground.ao_path);
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
    build_ground_plane_mesh(*ground_vertices_cpu, *ground_indices_cpu, ground);
    build_ground_height_samples(*ground_height_samples, ground.physics_grid_x, ground.physics_grid_z, ground);

    assert(ground.physics_grid_x == ground.physics_grid_z, "Jolt heightfield path currently expects a square physics grid.");
    sample_count := cast(u32) ground.physics_grid_x + 1;
    cell_size_x := ground.size_x / cast(float) ground.physics_grid_x;
    cell_size_z := ground.size_z / cast(float) ground.physics_grid_z;
    ground_physics_body = Physics.create_static_heightfield(
        ground_height_samples,
        sample_count,
        .{-ground.size_x * 0.5, 0.0, -ground.size_z * 0.5 + ground.center_z},
        .{cell_size_x, 1.0, cell_size_z});
    ground_physics_body_valid = true;

    ground_vertices = gpu_alloc_view(Scene_Vertex, ground_vertices_cpu.count, label = "model scene ground vertices");
    ground_indices = gpu_alloc_view(u32, ground_indices_cpu.count, label = "model scene ground indices");
    ground_instance = gpu_alloc_buffer(Scene_Instance, label = "model scene ground instance");
    ground_shadow_params = gpu_alloc_buffer(Scene_Draw_Params_CPU, label = "model scene ground shadow params");
    ground_draw_params = gpu_alloc_buffer(Ground_Draw_Params_CPU, label = "model scene ground params");
    grass_shadow_params = gpu_alloc_buffer(Grass_Draw_Params, label = "model scene grass shadow params");
    grass_draw_params = gpu_alloc_buffer(Grass_Draw_Params, label = "model scene grass params");

    memcpy(ground_vertices.cpu.data, ground_vertices_cpu.data, ground_vertices_cpu.count * size_of(Scene_Vertex));
    memcpy(ground_indices.cpu.data, ground_indices_cpu.data, ground_indices_cpu.count * size_of(u32));

    ground_instance.cpu.* = .{
        world = Matrix4_Identity,
        tint = .{1.0, 1.0, 1.0, 1.0},
        shadow_view_proj = Matrix4_Identity,
    };
    ground_shadow_params.cpu.* = .{
        vertices = ground_vertices.gpu,
        indices = ground_indices.gpu,
        materials = 0,
        instances = ground_instance.gpu,
        skin_matrices = 0,
        view_proj = Matrix4_Identity,
        light_dir = normalize(.{0.35, -1.0, 0.25}),
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
    grass_grid_x := max(1, ground.render_grid_x * 4 / 3 * 3);
    grass_grid_z := max(1, ground.render_grid_z * 4 / 3 * 3);
    grass_instance_count = cast(u32) grass_grid_x * cast(u32) grass_grid_z;
    grass_shadow_params.cpu.* = .{
        view_proj = Matrix4_Identity,
        shadow_view_proj = Matrix4_Identity,
        light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
        camera_pos = scene_camera.position,
        shadow_meta = .{0.0, 0.0, 0.0, 0.0},
        ground_size_center_z_time = .{ground.size_x, ground.size_z, ground.center_z, 0.0},
        ground_shape = .{ground.ridge, ground.swell, ground.warp, 0.0},
        grass_grid_height_width = .{cast(float) grass_grid_x, cast(float) grass_grid_z, 0.33, 0.24},
        player_pos_radius = .{0.0, 0.0, 0.0, 1.9},
    };
    grass_draw_params.cpu.* = grass_shadow_params.cpu.*;
    ground_index_count = cast(u32) ground_indices.cpu.count;
}

build_ground_plane_mesh :: (vertices: *[..]Scene_Vertex, indices: *[..]u32, ground: Scene_File.Scene_Procedural_Ground_Desc) {
    vertices.allocator = temp;
    indices.allocator = temp;
    array_reserve(vertices, (ground.render_grid_x + 1) * (ground.render_grid_z + 1));
    array_reserve(indices, ground.render_grid_x * ground.render_grid_z * 6);

    for z_step: 0..ground.render_grid_z {
        v := cast(float) z_step / cast(float) ground.render_grid_z;
        z := lerp(-ground.size_z * 0.5, ground.size_z * 0.5, v) + ground.center_z;
        for x_step: 0..ground.render_grid_x {
            u := cast(float) x_step / cast(float) ground.render_grid_x;
            x := lerp(-ground.size_x * 0.5, ground.size_x * 0.5, u);
            y := ground_height_at(ground, x, z);
            n := ground_normal_at(ground, x, z);
            array_add(vertices, .{
                position = .{x, y, z, 1.0},
                normal = .{n.x, n.y, n.z, 0.0},
                tangent = .{1.0, 0.0, 0.0, 1.0},
                uv = .{u * 13.0, v * 13.0},
            });
        }
    }

    stride := ground.render_grid_x + 1;
    for z_step: 0..ground.render_grid_z-1 {
        for x_step: 0..ground.render_grid_x-1 {
            i0 := cast(u32) (z_step * stride + x_step);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            array_add(indices, i0, i2, i1);
            array_add(indices, i1, i2, i3);
        }
    }
}

build_ground_height_samples :: (samples: *[..]float, grid_x: s64, grid_z: s64, ground: Scene_File.Scene_Procedural_Ground_Desc) {
    samples.allocator = temp;
    array_reserve(samples, (grid_x + 1) * (grid_z + 1));

    for z_step: 0..grid_z {
        v := cast(float) z_step / cast(float) grid_z;
        z := lerp(-ground.size_z * 0.5, ground.size_z * 0.5, v) + ground.center_z;
        for x_step: 0..grid_x {
            u := cast(float) x_step / cast(float) grid_x;
            x := lerp(-ground.size_x * 0.5, ground.size_x * 0.5, u);
            array_add(samples, ground_height_at(ground, x, z));
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

ground_height_at :: (ground: Scene_File.Scene_Procedural_Ground_Desc, x: float, z: float) -> float {
    ridge := sin(x * 0.23 + z * 0.09) * ground.ridge;
    swell := cos(z * 0.18 - x * 0.05) * ground.swell;
    warp := sin((x + z) * 0.11) * ground.warp + cos((x - z) * 0.07) * ground.warp;
    flatten := 1.0 - smoothstep(0.0, 6.0, abs(x) * 0.38);
    return ridge + swell + warp - flatten * 0.05;
}

ground_normal_at :: (desc: Scene_File.Scene_Procedural_Ground_Desc, x: float, z: float) -> Vector3 {
    eps := 0.15;
    h_l := ground_height_at(desc, x - eps, z);
    h_r := ground_height_at(desc, x + eps, z);
    h_d := ground_height_at(desc, x, z - eps);
    h_u := ground_height_at(desc, x, z + eps);
    return normalize({h_l - h_r, eps * 2.0, h_d - h_u});
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
        format = .R8G8B8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });

    bgra_pixels: [..]u8;
    bgra_pixels.allocator = temp;
    array_resize(*bgra_pixels, cast(s64) width * cast(s64) height * 4);
    memcpy(bgra_pixels.data, pixels, bgra_pixels.count);

    gpu_copy_to_texture(texture, bgra_pixels.data);

    view := gpu_texture_view(texture);
    return texture, view;
}

make_trs_matrix :: (pos: Vector3, rot: Quaternion, scale: Vector3) -> Matrix4 {
    return make_translation_matrix4(pos) *
        rotation_matrix(Matrix4, rot) *
        make_scale_matrix4(scale);
}

make_trs_matrix :: (pos: Vector3, rot: Quaternion, scale: float) -> Matrix4 {
    return make_translation_matrix4(pos) *
        rotation_matrix(Matrix4, rot) *
        make_scale_matrix4(.{scale, scale, scale});
}

#load "../character_controller.jai";
#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../ui/manip.jai";
#load "../ui/toggle_widget.jai";
#load "../shadowmap.jai";
#load "../scene_geo.jai";
#load "../scene_anim.jai";
Scene_File :: #import,file "../scene_file.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
Physics :: #import "Physics";
ai :: #import "assimp";
String :: #import "String";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Random";
#import "stb_image";
#import "Math";
#load "shaders/model_scene_shader.jai";
