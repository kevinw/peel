#import "Jai-Shader-Transpiler";
#load "../scene_pick.jai";

Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Indexed_Indirect_Draw_Args :: struct #type_info_none {
    vertex_count: u32;
    instance_count: u32;
    vertex_start: u32;
    base_instance: u32;
}

Enemy_Collider_Kind :: enum u8 {
    SPHERE;
    CAPSULE;
}

Enemy_Spawn_Params :: struct {
    enabled: bool = true;
    target_alive: s32 = 10;
    spawn_rate: float = 12.0;
    spawn_radius_min: float = 8.0;
    spawn_radius_max: float = 28.0;
    despawn_radius: float = 88.0;
    move_speed: float = 2.9;
    climb_speed_ratio: float = 0.75;
    min_head_size: float = 0.78;
    max_head_size: float = 1.28;
    touch_damage_per_second: float = 11.0;
}

Auto_Fire_Params :: struct {
    enabled: bool = true;
    shots_per_second: float = 2.0;
    projectile_speed: float = 18.0;
    projectile_radius: float = 0.18;
    projectile_life: float = 2.0;
}

Enemy_Runtime :: struct {
    active: bool;
    body_id: u32;
    shape: *Shape;
    hp: float;
    hit_flash_t: float;
    yaw: float;
    visual_scale: float;
    collider_scale: float;
    collider_kind: Enemy_Collider_Kind;
    _pad0: [3]u8;
    tint: Vector4;
}

Projectile_Runtime :: struct {
    active: bool;
    _pad0: [3]u8;
    life_remaining: float;
    position: Vector3;
    velocity: Vector3;
}

Enemy_Render_Mesh :: struct {
    node_index: s32;
    base_mesh_index: u32;
    lod_mesh_start: u32;
    lod_mesh_count: u32;
}

Enemy_Draw_Group :: struct {
    render_mesh_index: u32;
    lod_level: u32;
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Animated_Batch :: struct {
    batch_index: s32;
    node_index: s32;
    skin_matrix_start: u32;
    skin_matrix_count: u32;
    source: enum u32 { PLAYER; MEDIAPIPE_DEMO; };
}

shadow_skip_batch: [..]bool;
batch_pick_object_ids: [..]u32;
batch_compiled_node_indices: [..]s32;

Running_Lizard_Instance :: struct {
    instance_index: u32;
    node_index: s32;
    mesh_index: u32;
}

Mediapipe_Demo_Instance :: struct {
    instance_index: u32;
    node_index: s32;
    mesh_index: u32;
}

Mediapipe_Face_Instance :: struct {
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

Scene_Draw_Params_CPU      :: CPU_Struct(Scene_Draw_Params);
Ground_Draw_Params_CPU     :: CPU_Struct(Ground_Draw_Params);
Model_Scene_Sky_Params_CPU :: CPU_Struct(Model_Scene_Sky_Params);
Grass_Shadow_Params_CPU    :: CPU_Struct(Grass_Shadow_Params);

graphics_pipeline: Gpu_Pipeline;
pick_pipeline: Gpu_Pipeline;
ground_pipeline: Gpu_Pipeline;
shadow_pipeline: Gpu_Pipeline;
grass_pipeline: Gpu_Pipeline;
grass_shadow_pipeline: Gpu_Pipeline;
debug_shadow_pipeline: Gpu_Pipeline;
debug_pick_pipeline: Gpu_Pipeline;
sky_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
scene_geo: Scene_Geo;
shadow_map: Shadow_Map;
running_lizard_controller: Character_Controller;
running_lizard_anim: Scene_Anim_State;
mediapipe_body_anim: Scene_Anim_State;
running_lizard_clip_index: s32 = -1;
running_lizard_root: Matrix4 = Matrix4_Identity;
mediapipe_body_root: Matrix4 = Matrix4_Identity;
running_lizard_scale: float = 1.0;
running_lizard_ground_y: float = 0.5;
mediapipe_body_scale: float = 1.0;
mediapipe_demo_focus: Vector3 = .{0.0, 2.3, -6.2};
scene_instances: Gpu_View(Scene_Instance);
scene_draw_params: Gpu_View(Scene_Draw_Params_CPU);
scene_skin_matrices: Gpu_View(Vector4);
scene_morph_weights: Gpu_View(float);
enemy_gpu_arena: Gpu_Arena;
enemy_instances: Gpu_View(Scene_Instance);
enemy_draw_params: Gpu_View(Scene_Draw_Params_CPU);
enemy_indirect_args: Gpu_View(Indexed_Indirect_Draw_Args);
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
grass_shadow_params: Gpu_Buffer(Grass_Shadow_Params_CPU);
sky_draw_params: Gpu_Buffer(Model_Scene_Sky_Params_CPU);
debug_pick_params: Gpu_Buffer(Scene_Draw_Params_CPU);
grass_instance_count: u32;
render_grass: bool = true;
scene_shadows_enabled: bool = true;
mediapipe_body_casts_shadows: bool = true;
mediapipe_face_casts_shadows: bool = true;
ground_physics_body: u32;
ground_physics_body_valid: bool;
stone_physics_bodies: [..]u32;
stone_base_shapes: [..]Physics.Collider_Shape;
stone_scaled_shapes: [..]Physics.Collider_Shape;
scene_batches: [..]Draw_Batch;
animated_batches: [..]Animated_Batch;
running_lizard_instances: [..]Running_Lizard_Instance;
running_lizard_attachment_instances: [..]Running_Lizard_Attachment_Instance;
mediapipe_demo_instances: [..]Mediapipe_Demo_Instance;
mediapipe_face_instances: [..]Mediapipe_Face_Instance;
mediapipe_body_model_index: s32 = -1;
mediapipe_face_model_index: s32 = -1;
enemy_mask_model_index: s32 = -1;
mediapipe_body_mesh_index: s32 = -1;
mediapipe_face_mesh_index: s32 = -1;
mediapipe_face_node_index: s32 = -1;
mediapipe_face_root: Matrix4 = Matrix4_Identity;
mediapipe_body_hips_node_index: s32 = -1;
mediapipe_body_torso_node_index: s32 = -1;
mediapipe_body_neck_node_index: s32 = -1;
mediapipe_body_head_node_index: s32 = -1;
mediapipe_body_upper_arm_l_node_index: s32 = -1;
mediapipe_body_upper_arm_r_node_index: s32 = -1;
mediapipe_body_forearm_l_node_index: s32 = -1;
mediapipe_body_forearm_r_node_index: s32 = -1;
mediapipe_body_thigh_l_node_index: s32 = -1;
mediapipe_body_thigh_r_node_index: s32 = -1;
mediapipe_body_shin_l_node_index: s32 = -1;
mediapipe_body_shin_r_node_index: s32 = -1;
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
show_pick_debug: bool;
physics_g_was_down: bool;
control_mode: enum { Player; Editor; } = .Player;
model_scene_sun_strength: float = 1.0;
time_of_day: float = 0.4;
p_was_down: bool;
orbit_yaw: float = 0.0;
orbit_pitch: float = -0.32;
orbit_distance: float = 8.5;
orbit_prev_mouse: Vector2;
orbit_have_prev_mouse: bool;
left_was_down: bool;
gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
gizmo_overlay_ctx: Gizmo.Gizmo_Context;
gizmo_overlay_render_ctx: Gizmo_Render.Gizmo_Render_Context;
enemy_spawn_params: Enemy_Spawn_Params = .{};
auto_fire_params: Auto_Fire_Params = .{};
player_health: float = 100.0;
enemy_spawn_accumulator: float;
player_shot_accumulator: float;
enemy_collider_radius: float = 0.45;
enemy_collider_half_height: float = 0.0;
enemy_collider_kind: Enemy_Collider_Kind = .SPHERE;
enemy_model_scale: float = 1.0;
enemy_model_root_offset_y: float;
enemy_shape: *Shape;
enemy_max_count: s32 = 256;
enemy_alive_count: s32;
enemy_runtime: [..]Enemy_Runtime;
projectile_runtime: [..]Projectile_Runtime;
enemy_render_meshes: [..]Enemy_Render_Mesh;
enemy_draw_groups: [..]Enemy_Draw_Group;
enemy_visible_count_debug: s32;
enemy_render_instance_count_debug: s32;
projectile_active_count: s32;
enemy_debug_next_log_time: float;
render_enemy_masks: bool = true;
enemy_direct_draw_debug: bool = true;
projectile_max_count: s32 = 256;

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
    Gizmo.init(*gizmo_overlay_ctx);
    gizmo_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Failed to initialize Gizmo_Render for model scene.");
    overlay_gizmo_ok := Gizmo_Render.init(*gizmo_overlay_render_ctx, max_lines = 65536);
    assert(overlay_gizmo_ok, "Failed to initialize overlay Gizmo_Render for model scene.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
    Gizmo_Render.bind_gizmo(*gizmo_overlay_render_ctx, *gizmo_overlay_ctx);
    Physics.configure_test_environment(
        spawn_spheres = false,
        include_static_box = false,
        create_floor = false,
        floor_half_extent = .{24.0, 1.0, 24.0},
        floor_center = .{0.0, -1.0, 0.0});
    Physics.init();
    Physics.debug_draw_enabled = false;

    graphics_source     := cast([]u8) get_transpiled(.METAL, model_scene_vertex_main, model_scene_fragment_main);
    pick_source         := cast([]u8) get_transpiled(.METAL, model_scene_vertex_main, model_scene_pick_fragment_main);
    ground_source       := cast([]u8) get_transpiled(.METAL, ground_vertex_main, ground_fragment_main);
    shadow_source       := cast([]u8) get_transpiled(.METAL, model_scene_shadow_vertex_main, model_scene_shadow_fragment_main);
    grass_source        := cast([]u8) get_transpiled(.METAL, model_scene_grass_vertex_main, model_scene_grass_fragment_main);
    grass_shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_grass_shadow_vertex_main, model_scene_grass_shadow_fragment_main);
    debug_shadow_source := cast([]u8) get_transpiled(.METAL, model_scene_debug_shadow_vertex_main, model_scene_debug_shadow_fragment_main);
    debug_pick_source   := cast([]u8) get_transpiled(.METAL, model_scene_debug_shadow_vertex_main, model_scene_debug_pick_fragment_main);
    sky_source          := cast([]u8) get_transpiled(.METAL, model_scene_sky_vertex_main, model_scene_sky_fragment_main);

    main_raster: Gpu_Raster_Desc = .{
        cull = .CW,
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
    pick_raster := main_raster;
    pick_raster.color_targets = .[
        .{format = .B8G8R8A8_UNORM},
    ];

    graphics_pipeline     = gpu_create_graphics_pipeline(graphics_source, main_raster);
    pick_pipeline         = gpu_create_graphics_pipeline(pick_source, pick_raster);
    ground_pipeline       = gpu_create_graphics_pipeline(ground_source, main_raster);
    shadow_pipeline       = gpu_create_graphics_pipeline(shadow_source, shadow_raster);
    grass_pipeline        = gpu_create_graphics_pipeline(grass_source, grass_main_raster);
    grass_shadow_pipeline = gpu_create_graphics_pipeline(grass_shadow_source, shadow_raster);
    debug_shadow_pipeline = gpu_create_graphics_pipeline(debug_shadow_source, main_raster);
    debug_pick_pipeline   = gpu_create_graphics_pipeline(debug_pick_source, main_raster);
    sky_pipeline          = gpu_create_graphics_pipeline(sky_source, grass_main_raster);
    shadow_map_init(*shadow_map);
    sky_draw_params = gpu_alloc_buffer(Model_Scene_Sky_Params_CPU, label = "model scene sky params");
    debug_pick_params = gpu_alloc_buffer(Scene_Draw_Params_CPU, label = "model scene debug pick params");
    mediapipe_body_casts_shadows = false;
    mediapipe_face_casts_shadows = false;

    scene_palette_models = Scene_File.scan_scene_palette_models();
    scene_manip_objects.allocator = context.allocator;
    scene_manip_node_indices.allocator = context.allocator;
    running_lizard_attachment_instances.allocator = context.allocator;
    mediapipe_demo_instances.allocator = context.allocator;
    mediapipe_face_instances.allocator = context.allocator;
    shadow_skip_batch.allocator = context.allocator;
    batch_pick_object_ids.allocator = context.allocator;
    batch_compiled_node_indices.allocator = context.allocator;
    enemy_runtime.allocator = context.allocator;
    projectile_runtime.allocator = context.allocator;
    enemy_render_meshes.allocator = context.allocator;
    enemy_draw_groups.allocator = context.allocator;
    scene_doc, compiled_scene = Scene_File.load_compiled_scene_cached(SCENE_ROOT_PATH);
    init_scene_geo_from_palette();
    rebuild_scene_runtime();
    scene_manip_objects_dirty = true;
    scene_manip_apply_pending = false;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
        ensure_scene_pick_target(cast(u32) win_w, cast(u32) win_h);
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
    Gizmo_Render.deinit(*gizmo_overlay_render_ctx);
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_overlay_ctx);
    Gizmo.deinit(*gizmo_ctx);
    gpu_delete(*debug_pick_params);
    gpu_delete(*sky_draw_params);
    if sky_pipeline != 0 gpu_free_pipeline(sky_pipeline);
    if debug_pick_pipeline != 0 gpu_free_pipeline(debug_pick_pipeline);
    if debug_shadow_pipeline != 0 gpu_free_pipeline(debug_shadow_pipeline);
    if grass_shadow_pipeline != 0 gpu_free_pipeline(grass_shadow_pipeline);
    if grass_pipeline != 0 gpu_free_pipeline(grass_pipeline);
    if pick_pipeline != 0 gpu_free_pipeline(pick_pipeline);
    if shadow_pipeline != 0 gpu_free_pipeline(shadow_pipeline);
    if ground_pipeline != 0 gpu_free_pipeline(ground_pipeline);
    shadow_map_deinit(*shadow_map);
    array_free(running_lizard_instances);
    array_free(running_lizard_attachment_instances);
    array_free(mediapipe_demo_instances);
    array_free(mediapipe_face_instances);
    array_free(shadow_skip_batch);
    array_free(batch_pick_object_ids);
    array_free(batch_compiled_node_indices);
    array_free(enemy_runtime);
    array_free(projectile_runtime);
    array_free(enemy_render_meshes);
    array_free(enemy_draw_groups);
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
    _, p_pressed := input_down("P");
    if p_pressed toggle_control_mode();

    if app_ui_enabled {
        using ImGui;
        if Begin("Model Scene", flags = .NoCollapse | .AlwaysAutoResize) {
            Checkbox("Autopilot", *autopilot_enabled);
            if Checkbox("Physics Gizmos", *physics_gizmos_enabled) {
                Physics.debug_draw_enabled = physics_gizmos_enabled;
            }
            Checkbox("Render Grass", *render_grass);
            Checkbox("Scene Shadows", *scene_shadows_enabled);
            Checkbox("Enemy Horde", *enemy_spawn_params.enabled);
            Checkbox("Render Enemy Masks", *render_enemy_masks);
            Checkbox("Enemy Direct Draw", *enemy_direct_draw_debug);
            Checkbox("Auto Fire", *auto_fire_params.enabled);
            Persist.SliderInt("Enemy Target", *enemy_spawn_params.target_alive, 0, enemy_max_count, "%d");
            Persist.SliderFloat("Enemy Spawn Rate", *enemy_spawn_params.spawn_rate, 0.0, 600.0, "%.0f/s");
            Persist.SliderFloat("Enemy Speed", *enemy_spawn_params.move_speed, 0.5, 6.0, "%.2f");
            Persist.SliderFloat("Climb Speed Ratio", *enemy_spawn_params.climb_speed_ratio, 0.0, 1.5, "%.2f");
            Persist.SliderFloat("Min Head Size", *enemy_spawn_params.min_head_size, 0.4, 1.5, "%.2f");
            Persist.SliderFloat("Max Head Size", *enemy_spawn_params.max_head_size, 0.5, 2.0, "%.2f");
            Persist.SliderFloat("Enemy Touch DPS", *enemy_spawn_params.touch_damage_per_second, 0.0, 40.0, "%.1f");
            Persist.SliderFloat("Shots / Sec", *auto_fire_params.shots_per_second, 0.0, 10.0, "%.1f");
            if Checkbox("Mediapipe Body Casts Shadows", *mediapipe_body_casts_shadows) {
                rebuild_scene_runtime();
            }
            if Checkbox("Mediapipe Face Casts Shadows", *mediapipe_face_casts_shadows) {
                rebuild_scene_runtime();
            }
            Checkbox("Show Shadow Debug", *show_shadow_debug);
            Checkbox("Show Pick Debug", *show_pick_debug);
            SliderFloat("Sun Strength", *model_scene_sun_strength, 0.0, 3.0, "%.2f");
            Text("Player Health: %.1f", player_health);
            Text("Enemies Alive: % / %", enemy_alive_count, enemy_spawn_params.target_alive);
            Text("Projectiles: %", projectile_active_count);

            using Persist;
            Persist.SliderFloat("Time of Day", *time_of_day, 0.0, 1.0, "%.2f px");
            if Button("Focus Mediapipe Demo") {
                control_mode = .Editor;
                scene_camera.position = mediapipe_demo_focus + .{-3.4, 1.9, 4.8};
                editor_camera_set_look_at(*scene_camera, mediapipe_demo_focus);
            }
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
                //Text("%", ifx scene_dirty then "Scene Dirty" else "Scene Saved");
                //Separator();
                //Text("Selection Debug");
                //Text("Picked Object ID: %", scene_pick.last_object_id);
                //Text("Picked Scene Node: %", scene_pick.last_scene_node_index);
                //Text("Manip Selected Index: %", scene_manip_ctx.selected_index);
                //Text("Manip Object Count: %", scene_manip_objects.count);
                //Text("Pick Requests: %", scene_pick.request_count);
                //Text("Pick Applies: %", scene_pick.apply_count);
                //Text("Last Request Frame: %", scene_pick.last_request_frame);
                //Text("Last Apply Frame: %", scene_pick.last_apply_frame);
                //Text("Last Pick Pixel: %, %", scene_pick.last_applied_x, scene_pick.last_applied_y);
                pickable_batch_count: s64;
                for batch_pick_object_ids if it != 0 pickable_batch_count += 1;
                //Text("Pickable Batches: % / %", pickable_batch_count, batch_pick_object_ids.count);
                picked_manip_index := -1;
                if scene_pick.last_scene_node_index >= 0 {
                    for scene_manip_node_indices {
                        if it == scene_pick.last_scene_node_index {
                            picked_manip_index = cast(s32) it_index;
                            break;
                        }
                    }
                }
                //Text("Picked Node Manip Index: %", picked_manip_index);
                if scene_manip_ctx.selected_index >= 0 && cast(s64) scene_manip_ctx.selected_index < scene_manip_node_indices.count {
                    selected_scene_node_index := scene_manip_node_indices[scene_manip_ctx.selected_index];
                    Text("Manip Scene Node: %", selected_scene_node_index);
                    if selected_scene_node_index >= 0 && selected_scene_node_index < scene_doc.nodes.count {
                        Text("Manip Node Name: %", scene_doc.nodes[selected_scene_node_index].name);
                    }
                }
                //Text("Pick Pending: %", scene_pick.pending);
                if scene_place_palette_index >= 0 {
                    Text("Placing: %", String.path_filename(scene_palette_models[scene_place_palette_index]));
                    SameLine();
                    if Button("Cancel Placement") scene_place_palette_index = -1;
                }
                if BeginChild("Palette", .{340.0, 220.0}) {
                    PushPopFont(fonts.mono, fonts.MAIN_SIZE);
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
        }
        End();
    }

    right_down := input_down(.MOUSE_BUTTON_RIGHT);
    left_down, left_pressed := input_down(.MOUSE_BUTTON_LEFT);
    _, middle_pressed := input_down(.MOUSE_BUTTON_MIDDLE);
    left_released := !left_down && left_was_down;
    left_was_down = left_down;

    if middle_pressed toggle_control_mode();

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
    Gizmo.begin_frame(*gizmo_overlay_ctx);
    character_controller_update_in_system(*running_lizard_controller, Physics.physics.system, desired_move, dt);
    update_enemy_horde(dt);
    Physics.tick(dt);
    update_auto_fire_and_projectiles(dt);
    if physics_gizmos_enabled {
        append_lizard_physics_gizmos();
        append_enemy_debug_gizmos();
    }
    append_projectile_gizmos();

    if control_mode == .Editor && dims_ok && win_w > 0 && win_h > 0 {
        if scene_manip_objects_dirty {
            scene_rebuild_manip_objects();
            scene_manip_objects_dirty = false;
        }
        process_scene_pick_result_if_ready();
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
            manip_result := manip_update(*scene_manip_ctx, *gizmo_ctx, scene_manip_objects, frame, *gizmo_overlay_ctx);
            if manip_result.changed {
                scene_manip_apply_pending = true;
                scene_apply_manip_live_to_runtime();
            }
            if left_pressed && !io.WantCaptureMouse && !scene_manip_ctx.active {
                queue_scene_pick_request(cast(s32) mx, cast(s32) my);
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

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*scene_camera, *cam_forward, *cam_right, *cam_up);
    view := editor_camera_make_view(*scene_camera);
    aspect := ifx win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := make_projection_matrix(PI / 3.2, aspect, 0.05, 250.0);
    view_proj := proj * view;
    viewport := Vector2.{max(1.0, cast(float) win_w), max(1.0, cast(float) win_h)};
    ensure_scene_pick_target(cast(u32) max(1, win_w), cast(u32) max(1, win_h));

    time_of_day = clamp(time_of_day, 0.0, 1.0);
    model_scene_sun_strength = clamp(model_scene_sun_strength, 0.0, 3.0);
    sun_dir := model_scene_sun_direction(time_of_day);
    shadow_map.light_dir = -sun_dir;
    shadow_map.center = .{0.0, 2.0, -12.0};
    shadow_map.extent = 18.0;
    shadow_map.distance = 20.0;
    shadow_map.near_plane = 0.1;
    shadow_map.far_plane = 48.0;
    shadow_map.bias = 0.0035;
    shadow_map_update_view_proj(*shadow_map);
    shadow_binding := ifx scene_shadows_enabled then shadow_map_binding(*shadow_map) else Vector4.{0.0, 0.0, 2.0, 0.0};
    refresh_enemy_horde_render_state(view_proj, shadow_binding, scene_camera.position);
    if cast(float) time >= enemy_debug_next_log_time {
        log("ENEMY_HORDE alive=% visible=% render_instances=% groups=% health=% target=% enabled=%",
            enemy_alive_count,
            enemy_visible_count_debug,
            enemy_render_instance_count_debug,
            enemy_draw_groups.count,
            player_health,
            enemy_spawn_params.target_alive,
            enemy_spawn_params.enabled);
        enemy_debug_next_log_time = cast(float) time + 1.0;
    }

    if sky_draw_params.cpu != null {
        sky_draw_params.cpu.* = .{
            camera_right_proj_x = .{cam_right.x, cam_right.y, cam_right.z, proj._11},
            camera_up_proj_y = .{cam_up.x, cam_up.y, cam_up.z, proj._22},
            camera_forward_time_of_day = vec4(cam_forward, time_of_day),
            light_dir_sun_strength = .{shadow_map.light_dir.x, shadow_map.light_dir.y, shadow_map.light_dir.z, model_scene_sun_strength},
        };
    }

    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    scene_anim_sample(
        *running_lizard_anim,
        *scene_geo,
        running_lizard_clip_index,
        running_lizard_controller.animation_time,
        running_lizard_controller.animation_blend);
    update_mediapipe_demo_pose(cast(float) time);
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
        written: s64;
        if #complete it.source == {
        case .PLAYER;
            written = scene_anim_write_skin_matrices(dst, *scene_geo, *running_lizard_anim, mesh, it.node_index);
        case .MEDIAPIPE_DEMO;
            written = scene_anim_write_skin_matrices(dst, *scene_geo, *mediapipe_body_anim, mesh, it.node_index);
        }
        assert(written == it.skin_matrix_count);
    }
    if scene_morph_weights.cpu.data != null {
        for mesh_index: running_lizard_model.mesh_start .. running_lizard_model.mesh_start + running_lizard_model.mesh_count - 1 {
            mesh := scene_geo.meshes[mesh_index];
            if mesh.morph_target_count == 0 continue;
            dst := scene_morph_weights.cpu;
            dst.data += mesh.morph_target_start;
            dst.count = mesh.morph_target_count;
            written := scene_anim_write_morph_weights(dst, *scene_geo, *running_lizard_anim, mesh);
            assert(written == mesh.morph_target_count);
        }
        write_mediapipe_demo_morph_weights(cast(float) time);
    }

    for * scene_instances.cpu {
        it.shadow_view_proj = shadow_map.view_proj;
        it.shadow_meta = shadow_binding;
    }
    ground_instance.shadow_view_proj = shadow_map.view_proj;
    ground_instance.shadow_meta = shadow_binding;

    for *scene_draw_params.cpu {
        it.view_proj = view_proj;
        it.camera_pos = scene_camera.position;
        it.light_dir = shadow_map.light_dir;
        it.sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0};
    }
    ground_shadow_params.view_proj = view_proj;
    ground_shadow_params.camera_pos = scene_camera.position;
    ground_shadow_params.light_dir = shadow_map.light_dir;
    ground_shadow_params.sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0};
    ground_draw_params.view_proj = view_proj;
    ground_draw_params.camera_pos = scene_camera.position;
    ground_draw_params.light_dir = shadow_map.light_dir;
    ground_draw_params.sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0};
    if grass_draw_params.cpu != null {
        lizard_pos := character_controller_position(*running_lizard_controller);
        grass_shadow_params.shadow_view_proj = shadow_map.view_proj;
        grass_shadow_params.ground_size_center_z_time = .{active_ground.size_x, active_ground.size_z, active_ground.center_z, cast(float) time};
        grass_shadow_params.ground_shape = .{active_ground.ridge, active_ground.swell, active_ground.warp, 0.0};
        grass_shadow_params.player_pos_radius = .{lizard_pos.x, running_lizard_controller.facing_yaw, lizard_pos.z, 1.9};
        grass_draw_params.shadow_view_proj = grass_shadow_params.cpu.shadow_view_proj;
        grass_draw_params.ground_size_center_z_time = grass_shadow_params.cpu.ground_size_center_z_time;
        grass_draw_params.ground_shape = grass_shadow_params.cpu.ground_shape;
        grass_draw_params.grass_grid_height_width = grass_shadow_params.cpu.grass_grid_height_width;
        grass_draw_params.player_pos_radius = grass_shadow_params.cpu.player_pos_radius;
        grass_draw_params.view_proj = view_proj;
        grass_draw_params.camera_pos = scene_camera.position;
        grass_draw_params.light_dir = shadow_map.light_dir;
        grass_draw_params.sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0};
        grass_draw_params.shadow_meta = shadow_binding;
    }

    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, view_proj);
    Gizmo_Render.gizmo_render_set_view_projection(*gizmo_overlay_render_ctx, view_proj);

    if !scene_debug_logged scene_debug_logged = true;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);

    if scene_shadows_enabled {
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
            if it_index < shadow_skip_batch.count && shadow_skip_batch[it_index] continue;
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }
        if render_enemy_masks && enemy_draw_groups.count > 0 && enemy_draw_params.cpu.data != null && enemy_indirect_args.cpu.data != null {
            for group: enemy_draw_groups {
                if group.instance_count == 0 continue;
                params_gpu := enemy_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
                mesh := scene_geo.meshes[group.mesh_index];
                if enemy_direct_draw_debug {
                    draw_result = gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, group.instance_count);
                } else {
                    args_gpu := enemy_indirect_args.gpu + (it_index * size_of(Indexed_Indirect_Draw_Args)).(Gpu_Ptr);
                    draw_result = gpu_draw_instanced_indirect(cmd_buff, params_gpu, params_gpu, args_gpu);
                }
            }
        }
    }

    if scene_pick.render_this_frame && scene_pick.view != 0 {
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
                    view = scene_pick.view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.0, 0.0, 0.0, 0.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, pick_pipeline);
        for batch: scene_batches {
            if it_index >= batch_pick_object_ids.count || batch_pick_object_ids[it_index] == 0 continue;
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }
    }

    if debug_pick_params.cpu != null {
        debug_pick_params.cpu.* = .{
            vertices = 0,
            indices = 0,
            materials = 0,
            instances = 0,
            morph_vertex_deltas = 0,
            morph_weights = 0,
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = .{0.0, 0.0, 0.0},
            sun_params = .{0.0, 0.0, 0.0, 0.0},
            camera_pos = .{0.0, 0.0, 0.0},
            material_index = cast(u32) ground_sampler - 1,
            object_id = ifx scene_pick.view != 0 then gpu_texture_view_index(scene_pick.view) else 0,
            mesh_base_vertex = 0,
            skin_matrix_count = 0,
            morph_target_count = 0,
            morph_vertex_count = 0,
        };
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
                    clear_color._float = .[0.01, 0.01, 0.015, 1.0],
                },
            ],
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, sky_pipeline);
        if sky_draw_params.cpu != null {
            gpu_draw_instanced_direct(cmd_buff, sky_draw_params.gpu, 6, 1);
        }
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, ground_pipeline);
        gpu_draw_instanced_direct(cmd_buff, ground_draw_params.gpu, ground_index_count, 1);
        if render_grass && grass_draw_params.cpu != null && grass_instance_count > 0 {
            gpu_set_pipeline(cmd_buff, grass_pipeline);
            gpu_draw_instanced_direct(cmd_buff, grass_draw_params.gpu, 6, grass_instance_count);
        }

        gpu_set_pipeline(cmd_buff, graphics_pipeline);

        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }
        if render_enemy_masks && enemy_draw_groups.count > 0 && enemy_draw_params.cpu.data != null && enemy_indirect_args.cpu.data != null {
            for group: enemy_draw_groups {
                if group.instance_count == 0 continue;
                params_gpu := enemy_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
                mesh := scene_geo.meshes[group.mesh_index];
                if enemy_direct_draw_debug {
                    gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, group.instance_count);
                } else {
                    args_gpu := enemy_indirect_args.gpu + (it_index * size_of(Indexed_Indirect_Draw_Args)).(Gpu_Ptr);
                    gpu_draw_instanced_indirect(cmd_buff, params_gpu, params_gpu, args_gpu);
                }
            }
        }

        should_draw_gizmos := physics_gizmos_enabled || control_mode == .Editor || projectile_active_count > 0;
        if should_draw_gizmos {
            Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .TEST);
            Gizmo_Render.gizmo_render_draw(*gizmo_overlay_render_ctx, cmd_buff, *gizmo_overlay_ctx, viewport, depth_mode = .NONE);
        }

        if show_shadow_debug {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_shadow_pipeline);
            gpu_draw_instanced_direct(cmd_buff, scene_draw_params.gpu, 6, 1);
        }
        if show_pick_debug && debug_pick_params.cpu != null {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_pick_pipeline);
            gpu_draw_instanced_direct(cmd_buff, debug_pick_params.gpu, 6, 1);
        }
    }

    submit_and_present_with_ui(cmd_buff);
    scene_pick.render_this_frame = false;
} @on_tick

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


#scope_file

ensure_scene_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 {
        return;
    }
    if scene_depth_view != 0 && scene_depth_w == width && scene_depth_h == height {
        return; // no change needed.
    }

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

append_enemy_debug_gizmos :: () {
    drawn: s32;
    for enemy_runtime {
        if !it.active continue;
        pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        scaled_collider_radius := enemy_collider_radius * it.collider_scale;
        scaled_collider_half_height := enemy_collider_half_height * it.collider_scale;
        Gizmo.draw_sphere(*gizmo_ctx, pos, scaled_collider_radius, color = .{1.0, 0.18, 0.18, 0.55}, thickness = 1.25);
        if #complete it.collider_kind == {
        case .CAPSULE;
            top := pos + .{0.0, scaled_collider_half_height, 0.0};
            bottom := pos - .{0.0, scaled_collider_half_height, 0.0};
            Gizmo.draw_line(*gizmo_ctx, top, bottom, color = .{1.0, 0.3, 0.3, 0.4}, thickness = 1.0);
        case .SPHERE;
            //
        }
        drawn += 1;
        if drawn >= 24 break;
    }
}

append_projectile_gizmos :: () {
    for projectile_runtime {
        if !it.active continue;
        Gizmo.draw_sphere(*gizmo_ctx, it.position, auto_fire_params.projectile_radius, color = .{0.98, 0.92, 0.38, 0.92}, thickness = 2.0);
        vel_len := length(it.velocity);
        if vel_len > 0.001 {
            tail := it.position - it.velocity / vel_len * 0.3;
            Gizmo.draw_line(*gizmo_ctx, tail, it.position, color = .{1.0, 0.78, 0.22, 0.72}, thickness = 2.0);
        }
    }
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
    append_unique_model_path(*model_paths, "/Users/kev/src/three-mediapipe-rig/public/sample.glb");
    append_unique_model_path(*model_paths, "/Users/kev/src/three-mediapipe-rig/public/mediapipe-canonical-face.glb");
    scene_geo_init(*scene_geo, model_paths);
}

rebuild_scene_runtime :: () {
    auto_release_temp();
    clear_scene_runtime_resources();

    root_transforms: [..]Matrix4;
    root_transforms.allocator = temp;
    instances_cpu: [..]Scene_Instance;
    instances_cpu.allocator = temp;
    collider_model_indices: [..]s32;
    collider_model_indices.allocator = temp;

    array_reset(*scene_batches);
    array_reset(*batch_pick_object_ids);
    array_reset(*batch_compiled_node_indices);
    array_reset(*animated_batches);
    array_reset(*shadow_skip_batch);
    array_reset(*running_lizard_instances);
    array_reset(*running_lizard_attachment_instances);
    array_reset(*mediapipe_demo_instances);
    array_reset(*mediapipe_face_instances);
    running_lizard_compiled_root_node_index = -1;
    running_lizard_clip_index = -1;
    running_lizard_scale = 1.0;
    running_lizard_ground_y = 0.0;
    mediapipe_body_model_index = -1;
    mediapipe_face_model_index = -1;
    enemy_mask_model_index = -1;
    mediapipe_body_mesh_index = -1;
    mediapipe_face_mesh_index = -1;
    mediapipe_face_node_index = -1;
    mediapipe_body_hips_node_index = -1;
    mediapipe_body_torso_node_index = -1;
    mediapipe_body_neck_node_index = -1;
    mediapipe_body_head_node_index = -1;
    mediapipe_body_upper_arm_l_node_index = -1;
    mediapipe_body_upper_arm_r_node_index = -1;
    mediapipe_body_forearm_l_node_index = -1;
    mediapipe_body_forearm_r_node_index = -1;
    mediapipe_body_thigh_l_node_index = -1;
    mediapipe_body_thigh_r_node_index = -1;
    mediapipe_body_shin_l_node_index = -1;
    mediapipe_body_shin_r_node_index = -1;
    autopilot_enabled = false;
    active_ground = .{};
    enemy_alive_count = 0;
    enemy_spawn_accumulator = 0.0;
    player_shot_accumulator = 0.0;
    player_health = 100.0;
    projectile_active_count = 0;

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
            start_batch_count := scene_batches.count;
            scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, model_index, root_transforms);
            append_pick_ids_for_new_batches(start_batch_count, compiled_node_pick_object_id(cast(s32) it_index));
            append_compiled_node_indices_for_new_batches(start_batch_count, cast(s32) it_index);
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
            start_batch_count := scene_batches.count;
            scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, model_index, root_transforms);
            append_pick_ids_for_new_batches(start_batch_count, compiled_node_pick_object_id(cast(s32) it_index));
            append_compiled_node_indices_for_new_batches(start_batch_count, cast(s32) it_index);
        case .NONE;
            // nothing to do.
        }
    }

    if ground_enabled {
        active_ground.size_x = max(active_ground.size_x, 120.0);
        active_ground.size_z = max(active_ground.size_z, 120.0);
        active_ground.render_grid_x = max(active_ground.render_grid_x, 160);
        active_ground.render_grid_z = max(active_ground.render_grid_z, 160);
        active_ground.physics_grid_x = max(active_ground.physics_grid_x, 128);
        active_ground.physics_grid_z = max(active_ground.physics_grid_z, 128);
        init_ground_plane(active_ground);
    }
    while shadow_skip_batch.count < scene_batches.count array_add(*shadow_skip_batch, false);
    while batch_pick_object_ids.count < scene_batches.count array_add(*batch_pick_object_ids, 0);
    while batch_compiled_node_indices.count < scene_batches.count array_add(*batch_compiled_node_indices, -1);
    append_mediapipe_demo_instances(*instances_cpu, *total_skin_matrix_count);

    arena_bytes :=
        max(cast(s64) 1, instances_cpu.count) * size_of(Scene_Instance) +
        max(cast(s64) 1, scene_batches.count) * size_of(Scene_Draw_Params_CPU) +
        max(cast(s64) 1, total_skin_matrix_count * 4) * size_of(Vector4) +
        max(cast(s64) 1, scene_geo.morph_targets.count) * size_of(float) +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "model scene arena");
    assert(gpu_arena.cpu != null, "Model scene arena creation failed.");

    scene_instances = gpu_alloc_view(*gpu_arena, Scene_Instance, instances_cpu.count);
    if instances_cpu.count > 0 memcpy(scene_instances.cpu.data, instances_cpu.data, instances_cpu.count * size_of(Scene_Instance));

    if total_skin_matrix_count > 0 scene_skin_matrices = gpu_alloc_view(*gpu_arena, Vector4, total_skin_matrix_count * 4);
    if scene_geo.morph_targets.count > 0 {
        scene_morph_weights = gpu_alloc_view(*gpu_arena, float, scene_geo.morph_targets.count);
        for scene_geo.morph_targets {
            scene_morph_weights.cpu[it_index] = it.default_weight;
        }
    }

    scene_draw_params = gpu_alloc_view(*gpu_arena, Scene_Draw_Params_CPU, scene_batches.count);
    for batch: scene_batches {
        mesh := scene_geo.meshes[batch.mesh_index];
        scene_draw_params.cpu[it_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = scene_instances.gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr),
            morph_vertex_deltas = 0,
            morph_weights = 0,
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            material_index = mesh.material_index,
            object_id = batch_pick_object_ids[it_index],
            mesh_base_vertex = mesh.base_vertex,
            skin_matrix_count = 0,
            morph_target_count = mesh.morph_target_count,
            morph_vertex_count = mesh.vertex_count,
        };
        if mesh.morph_target_count > 0 {
            first_target := scene_geo.morph_targets[mesh.morph_target_start];
            scene_draw_params.cpu[it_index].morph_vertex_deltas = scene_geo.morph_vertex_deltas.gpu + (first_target.vertex_delta_start * size_of(Scene_Morph_Vertex_Delta)).(Gpu_Ptr);
            scene_draw_params.cpu[it_index].morph_weights = scene_morph_weights.gpu + (mesh.morph_target_start * size_of(float)).(Gpu_Ptr);
        }
    }
    for animated_batches {
        batch_index := cast(s64) it.batch_index;
        scene_draw_params.cpu[batch_index].skin_matrices = scene_skin_matrices.gpu + (it.skin_matrix_start * 4 * size_of(Vector4)).(Gpu_Ptr);
        scene_draw_params.cpu[batch_index].skin_matrix_count = it.skin_matrix_count;
    }

    init_enemy_horde_runtime();
    gpu_commit_residency();
}

clear_scene_runtime_resources :: () {
    controller_deinit(*running_lizard_controller);
    scene_anim_deinit(*running_lizard_anim);
    scene_anim_deinit(*mediapipe_body_anim);

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
    deinit(*scene_pick);

    gpu_delete(*ground_ao_texture_view);
    gpu_delete(*ground_ao_texture);
    gpu_delete(*ground_sampler);
    gpu_delete(*grass_draw_params);
    gpu_delete(*grass_shadow_params);
    gpu_delete(*ground_roughness_texture_view);
    gpu_delete(*ground_roughness_texture);
    gpu_delete(*ground_normal_texture_view);
    gpu_delete(*ground_texture_view);
    gpu_delete(*ground_texture);
    gpu_delete(*ground_draw_params);
    gpu_delete(*ground_shadow_params);
    gpu_delete(*ground_instance);
    gpu_delete(*ground_indices);
    gpu_delete(*ground_vertices);
    gpu_delete(*ground_normal_texture);
    grass_instance_count = 0;
    ground_index_count = 0;

    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
    gpu_arena = .{};
    scene_instances = .{};
    scene_draw_params = .{};
    scene_skin_matrices = .{};
    scene_morph_weights = .{};
    if enemy_shape != null {
        Shape_Destroy(enemy_shape);
        enemy_shape = null;
    }
    if enemy_gpu_arena.cpu != null gpu_free_arena(enemy_gpu_arena);
    enemy_gpu_arena = .{};
    enemy_instances = .{};
    enemy_draw_params = .{};
    enemy_indirect_args = .{};
    for enemy_runtime {
        if !it.active continue;
        Physics.destroy_body(it.body_id);
        if it.shape != null && it.shape != enemy_shape Shape_Destroy(it.shape);
    }
    array_reset(*enemy_runtime);
    array_reset(*projectile_runtime);
    array_reset(*enemy_render_meshes);
    array_reset(*enemy_draw_groups);
    enemy_alive_count = 0;
    projectile_active_count = 0;
    player_shot_accumulator = 0.0;
    enemy_collider_radius = 0.45;
    enemy_collider_half_height = 0.0;
    enemy_collider_kind = .SPHERE;
    enemy_model_scale = 1.0;
    enemy_model_root_offset_y = 0.0;

    array_reset(*running_lizard_instances);
    array_reset(*mediapipe_demo_instances);
    array_reset(*animated_batches);
    array_reset(*scene_batches);
    array_reset(*batch_pick_object_ids);
    array_reset(*batch_compiled_node_indices);
}

append_compiled_scatter_instances :: (instances_cpu: *[..]Scene_Instance, root_transforms: *[..]Matrix4, total_skin_matrix_count: *s64, collider_model_indices: *[..]s32, node_index: s32) {
    node := compiled_scene.nodes[node_index];
    random_seed(node.scatter.seed);
    for 1..node.scatter.count {
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
        start_batch_count := scene_batches.count;
        scene_geo_append_model_instances(*scene_batches, instances_cpu, *scene_geo, model_index, root_transforms.*, tint = .{0.92, 0.9, 0.88, 1.0});
        append_pick_ids_for_new_batches(start_batch_count, 0);
        append_compiled_node_indices_for_new_batches(start_batch_count, -1);

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
            array_add(*batch_pick_object_ids, 0);
            array_add(*batch_compiled_node_indices, -1);

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
                    source = .PLAYER,
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
                        array_add(*batch_pick_object_ids, 0);
                        array_add(*batch_compiled_node_indices, -1);

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

append_mediapipe_demo_instances :: (instances_cpu: *[..]Scene_Instance, total_skin_matrix_count: *s64) {
    mediapipe_body_model_index = scene_geo_model_index_by_name(*scene_geo, "sample");
    mediapipe_face_model_index = scene_geo_model_index_by_name(*scene_geo, "mediapipe-canonical-face");

    if mediapipe_body_model_index >= 0 {
        scene_anim_init(*mediapipe_body_anim, *scene_geo, mediapipe_body_model_index, -1);
        mediapipe_body_scale = scale_model_to_target_extent(mediapipe_body_model_index, 8.0);
        body_bounds := scene_geo_model_bounds(*scene_geo, mediapipe_body_model_index);
        body_ground_y := -body_bounds.min.y * mediapipe_body_scale;
        body_pos := Vector3.{0.0, body_ground_y, -5.8};
        mediapipe_body_root = make_trs_matrix(body_pos, quat_from_euler_deg(.{0.0, 180.0, 0.0}), .{mediapipe_body_scale, mediapipe_body_scale, mediapipe_body_scale});

        body_model := scene_geo.models[mediapipe_body_model_index];
        mediapipe_body_mesh_index = find_model_mesh_index_by_node_name(mediapipe_body_model_index, "body");
        mediapipe_body_hips_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "hips");
        mediapipe_body_torso_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "torso");
        mediapipe_body_neck_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "neck");
        mediapipe_body_head_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "head");
        mediapipe_body_upper_arm_l_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "upper_arm.L");
        mediapipe_body_upper_arm_r_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "upper_arm.R");
        mediapipe_body_forearm_l_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "forearm.L");
        mediapipe_body_forearm_r_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "forearm.R");
        mediapipe_body_thigh_l_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "thigh.L");
        mediapipe_body_thigh_r_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "thigh.R");
        mediapipe_body_shin_l_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "shin.L");
        mediapipe_body_shin_r_node_index = find_mesh_skin_bone_node_index(mediapipe_body_mesh_index, "shin.R");

        for geo_node_index: body_model.node_start .. body_model.node_start + body_model.node_count - 1 {
            geo_node := scene_geo.nodes[geo_node_index];
            if geo_node.mesh_ref_count == 0 continue;
            for mesh_ref_offset: 0..geo_node.mesh_ref_count-1 {
                mesh_index := scene_geo.node_mesh_refs[geo_node.first_mesh_ref + mesh_ref_offset];
                mesh := scene_geo.meshes[mesh_index];
                batch := array_add(*scene_batches);
                batch.mesh_index = mesh_index;
                batch.first_instance = cast(u32) instances_cpu.count;
                batch.instance_count = 1;
                array_add(*batch_pick_object_ids, 0);
                array_add(*shadow_skip_batch, !mediapipe_body_casts_shadows);
                array_add(*batch_compiled_node_indices, -1);

                instance_index := cast(u32) instances_cpu.count;
                array_add(instances_cpu, .{
                    world = mediapipe_body_root,
                    tint = .{1.0, 1.0, 1.0, 1.0},
                    shadow_view_proj = Matrix4_Identity,
                });
                array_add(*mediapipe_demo_instances, .{
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
                        source = .MEDIAPIPE_DEMO,
                    });
                    total_skin_matrix_count.* += mesh.skin_bone_count;
                }
            }
        }
    }

    if mediapipe_body_model_index >= 0 {
        mediapipe_face_node_index = scene_geo_model_node_index_by_name(*scene_geo, mediapipe_body_model_index, "face.001");
        if mediapipe_face_node_index >= 0 {
            face_node := scene_geo.nodes[mediapipe_face_node_index];
            if face_node.mesh_ref_count > 0 {
                mediapipe_face_mesh_index = cast(s32) scene_geo.node_mesh_refs[face_node.first_mesh_ref];
                face_scale := scale_model_to_target_extent(mediapipe_body_model_index, 3.0);
                mediapipe_face_root = make_trs_matrix(.{5.4, 2.6, -6.4}, quat_from_euler_deg(.{0.0, 200.0, 0.0}), .{face_scale, face_scale, face_scale});

                mesh := scene_geo.meshes[mediapipe_face_mesh_index];
                batch := array_add(*scene_batches);
                batch.mesh_index = cast(u32) mediapipe_face_mesh_index;
                batch.first_instance = cast(u32) instances_cpu.count;
                batch.instance_count = 1;
                array_add(*batch_pick_object_ids, 0);
                array_add(*shadow_skip_batch, !mediapipe_face_casts_shadows);
                array_add(*batch_compiled_node_indices, -1);

                instance_index := cast(u32) instances_cpu.count;
                array_add(instances_cpu, .{
                    world = mediapipe_face_root,
                    tint = .{1.0, 1.0, 1.0, 1.0},
                    shadow_view_proj = Matrix4_Identity,
                });
                array_add(*mediapipe_face_instances, .{
                    instance_index = instance_index,
                    node_index = mediapipe_face_node_index,
                    mesh_index = cast(u32) mediapipe_face_mesh_index,
                });

                if mesh.skin_bone_count > 0 {
                    array_add(*animated_batches, .{
                        batch_index = cast(s32) scene_batches.count - 1,
                        node_index = mediapipe_face_node_index,
                        skin_matrix_start = cast(u32) total_skin_matrix_count.*,
                        skin_matrix_count = mesh.skin_bone_count,
                        source = .MEDIAPIPE_DEMO,
                    });
                    total_skin_matrix_count.* += mesh.skin_bone_count;
                }
            }
        }
    }
}

update_mediapipe_demo_pose :: (t: float) {
    if mediapipe_body_model_index < 0 return;

    scene_anim_sample(*mediapipe_body_anim, *scene_geo, -1, t, 1.0);

    pose_t := t;
    apply_mediapipe_demo_bone_offset(mediapipe_body_hips_node_index, quat_from_euler_deg(.{0.0, sin(pose_t * 0.55) * 10.0, 0.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_torso_node_index, quat_from_euler_deg(.{sin(pose_t * 0.8) * 10.0, 0.0, sin(pose_t * 0.5) * 9.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_neck_node_index, quat_from_euler_deg(.{sin(pose_t * 0.9) * 9.0, sin(pose_t * 0.7) * 18.0, 0.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_head_node_index, quat_from_euler_deg(.{sin(pose_t * 1.0) * 14.0, sin(pose_t * 0.6 + 0.6) * 28.0, sin(pose_t * 0.8) * 7.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_upper_arm_l_node_index, quat_from_euler_deg(.{-40.0 + sin(pose_t * 1.7) * 28.0, 0.0, -52.0 + sin(pose_t * 1.3) * 22.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_upper_arm_r_node_index, quat_from_euler_deg(.{-24.0 + sin(pose_t * 1.9 + 1.4) * 38.0, 0.0, 52.0 + sin(pose_t * 1.2 + 0.4) * 26.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_forearm_l_node_index, quat_from_euler_deg(.{-36.0 + sin(pose_t * 2.1 + 0.4) * 26.0, 0.0, -18.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_forearm_r_node_index, quat_from_euler_deg(.{-54.0 + sin(pose_t * 2.2 + 1.0) * 34.0, 0.0, 18.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_thigh_l_node_index, quat_from_euler_deg(.{sin(pose_t * 1.4) * 14.0, 0.0, 0.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_thigh_r_node_index, quat_from_euler_deg(.{sin(pose_t * 1.4 + PI) * 14.0, 0.0, 0.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_shin_l_node_index, quat_from_euler_deg(.{max(0.0, sin(pose_t * 1.4 + 0.25)) * 18.0, 0.0, 0.0}));
    apply_mediapipe_demo_bone_offset(mediapipe_body_shin_r_node_index, quat_from_euler_deg(.{max(0.0, sin(pose_t * 1.4 + PI + 0.25)) * 18.0, 0.0, 0.0}));

    set_model_morph_wave_weights(*mediapipe_body_anim, mediapipe_body_model_index, t, 0.0);
    scene_anim_recompute_worlds(*mediapipe_body_anim, *scene_geo);

    body_model := scene_geo.models[mediapipe_body_model_index];
    for mediapipe_demo_instances {
        node_local_index := it.node_index - cast(s32) body_model.node_start;
        instance_world := mediapipe_body_root;
        if node_local_index >= 0 && node_local_index < mediapipe_body_anim.worlds.count {
            instance_world = mediapipe_body_root * mediapipe_body_anim.worlds[node_local_index];
        }
        scene_instances.cpu[it.instance_index].world = instance_world;
    }
    for mediapipe_face_instances {
        node_local_index := it.node_index - cast(s32) body_model.node_start;
        instance_world := mediapipe_face_root;
        if node_local_index >= 0 && node_local_index < mediapipe_body_anim.worlds.count {
            instance_world = mediapipe_face_root * mediapipe_body_anim.worlds[node_local_index];
        }
        scene_instances.cpu[it.instance_index].world = instance_world;
    }
}

write_mediapipe_demo_morph_weights :: (t: float) {
    if mediapipe_body_model_index >= 0 {
        for mesh_index: scene_geo.models[mediapipe_body_model_index].mesh_start .. scene_geo.models[mediapipe_body_model_index].mesh_start + scene_geo.models[mediapipe_body_model_index].mesh_count - 1 {
            mesh := scene_geo.meshes[mesh_index];
            if mesh.morph_target_count == 0 continue;
            dst := scene_morph_weights.cpu;
            dst.data += mesh.morph_target_start;
            dst.count = mesh.morph_target_count;
            written := scene_anim_write_morph_weights(dst, *scene_geo, *mediapipe_body_anim, mesh);
            assert(written == mesh.morph_target_count);
        }
    }

    _ = t;
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

decompose_matrix_trs :: (m: Matrix4) -> (pos: Vector3, rot: Vector3, scl: Vector3) {
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

append_unique_model_path :: (paths: *[..]string, model_path: string) {
    for paths.* if it == model_path return;
    array_add(paths, model_path);
}

find_model_mesh_index_by_node_name :: (model_index: s32, node_name: string) -> s32 {
    if model_index < 0 return -1;
    model := scene_geo.models[model_index];
    target_node_index := scene_geo_model_node_index_by_name(*scene_geo, model_index, node_name);
    if target_node_index < 0 return -1;
    node := scene_geo.nodes[target_node_index];
    if node.mesh_ref_count <= 0 return -1;
    return cast(s32) scene_geo.node_mesh_refs[node.first_mesh_ref];
}

find_mesh_skin_bone_node_index :: (mesh_index: s32, node_name: string) -> s32 {
    if mesh_index < 0 return -1;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.skin_bone_count <= 0 return -1;
    for i: 0..mesh.skin_bone_count-1 {
        skin_bone := scene_geo.mesh_skin_bones[mesh.skin_bone_start + i];
        if scene_geo.node_names[skin_bone.node_index] == node_name return skin_bone.node_index;
    }
    return -1;
}

find_mesh_morph_target_index_by_name :: (mesh_index: s32, target_name: string) -> s32 {
    if mesh_index < 0 return -1;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.morph_target_count <= 0 return -1;
    for local_index: 0..mesh.morph_target_count-1 {
        global_index := mesh.morph_target_start + cast(u32) local_index;
        if global_index >= scene_geo.morph_target_names.count continue;
        if scene_geo.morph_target_names[global_index] == target_name return cast(s32) global_index;
    }
    return -1;
}

set_named_morph_weight :: (state: *Scene_Anim_State, mesh_index: s32, target_name: string, weight: float) {
    target_index := find_mesh_morph_target_index_by_name(mesh_index, target_name);
    if target_index < 0 return;
    state.morph_weights[target_index] = clamp(weight, 0.0, 1.0);
}

scale_model_to_target_extent :: (model_index: s32, target_extent: float) -> float {
    bounds := scene_geo_model_bounds(*scene_geo, model_index);
    size := bounds.max - bounds.min;
    max_extent := max(max(size.x, size.y), size.z);
    return ifx max_extent > 0.0 then target_extent / max_extent else 1.0;
}

init_enemy_horde_runtime :: () {
    enemy_mask_model_index = scene_geo_model_index_by_name(*scene_geo, "mask");
    if enemy_mask_model_index < 0 return;

    bounds := scene_geo_model_bounds(*scene_geo, enemy_mask_model_index);
    size := bounds.max - bounds.min;
    enemy_model_scale = scale_model_to_target_extent(enemy_mask_model_index, 3.1);
    scaled_size := size * enemy_model_scale;
    diameter_xz := max(scaled_size.x, scaled_size.z);
    enemy_collider_radius = max(0.24, diameter_xz * 0.32);
    enemy_collider_half_height = max(0.0, (scaled_size.y - enemy_collider_radius * 2.0) * 0.5);
    enemy_collider_kind = ifx enemy_collider_half_height > enemy_collider_radius * 0.4 then .CAPSULE else .SPHERE;
    enemy_model_root_offset_y = -bounds.min.y * enemy_model_scale - (enemy_collider_radius + enemy_collider_half_height) + 0.75;
    if #complete enemy_collider_kind == {
    case .SPHERE;
        enemy_shape = cast(*Shape) SphereShape_Create(enemy_collider_radius);
    case .CAPSULE;
        enemy_shape = cast(*Shape) CapsuleShape_Create(enemy_collider_half_height, enemy_collider_radius);
    }
    assert(enemy_shape != null, "Failed to create enemy collider shape.");

    array_resize(*enemy_runtime, enemy_max_count);
    for *enemy_runtime it.* = .{};
    array_resize(*projectile_runtime, projectile_max_count);
    for *projectile_runtime it.* = .{};

    array_reset(*enemy_render_meshes);
    mask_model := scene_geo.models[enemy_mask_model_index];
    for node_index: mask_model.node_start .. mask_model.node_start + mask_model.node_count - 1 {
        node := scene_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            mesh := scene_geo.meshes[mesh_index];
            array_add(*enemy_render_meshes, .{
                node_index = cast(s32) node_index,
                base_mesh_index = mesh_index,
                lod_mesh_start = mesh.lod_mesh_start,
                lod_mesh_count = mesh.lod_mesh_count,
            });
        }
    }
    if enemy_render_meshes.count == 0 return;
    log("ENEMY_HORDE init model=% render_meshes=% collider=% radius=% half_height=% scale=%",
        scene_geo.models[enemy_mask_model_index].name,
        enemy_render_meshes.count,
        enemy_collider_kind,
        enemy_collider_radius,
        enemy_collider_half_height,
        enemy_model_scale);

    array_reset(*enemy_draw_groups);
    max_group_count: s64;
    for enemy_render_meshes max_group_count += 1 + cast(s64) it.lod_mesh_count;
    for render_mesh: enemy_render_meshes {
        lod_count := 1 + cast(s32) render_mesh.lod_mesh_count;
        for lod_level: 0..lod_count-1 {
            mesh_index := render_mesh.base_mesh_index;
            if lod_level > 0 mesh_index = render_mesh.lod_mesh_start + cast(u32) (lod_level - 1);
            array_add(*enemy_draw_groups, .{
                render_mesh_index = cast(u32) it_index,
                lod_level = cast(u32) lod_level,
                mesh_index = mesh_index,
            });
        }
    }

    max_instance_count := cast(s64) enemy_max_count * enemy_render_meshes.count;
    arena_bytes :=
        max(cast(s64) 1, max_instance_count) * size_of(Scene_Instance) +
        max(cast(s64) 1, enemy_draw_groups.count) * size_of(Scene_Draw_Params_CPU) +
        max(cast(s64) 1, enemy_draw_groups.count) * size_of(Indexed_Indirect_Draw_Args) +
        1024;
    enemy_gpu_arena = gpu_make_arena(arena_bytes, label = "model scene enemy arena");
    assert(enemy_gpu_arena.cpu != null, "Failed to create enemy arena.");
    enemy_instances = gpu_alloc_view(*enemy_gpu_arena, Scene_Instance, max_instance_count);
    enemy_draw_params = gpu_alloc_view(*enemy_gpu_arena, Scene_Draw_Params_CPU, enemy_draw_groups.count);
    enemy_indirect_args = gpu_alloc_view(*enemy_gpu_arena, Indexed_Indirect_Draw_Args, enemy_draw_groups.count);

    for group, group_index: enemy_draw_groups {
        mesh := scene_geo.meshes[group.mesh_index];
        enemy_draw_params.cpu[group_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = 0,
            morph_vertex_deltas = 0,
            morph_weights = 0,
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            material_index = mesh.material_index,
            object_id = 0,
            mesh_base_vertex = mesh.base_vertex,
            skin_matrix_count = 0,
            morph_target_count = 0,
            morph_vertex_count = 0,
        };
        enemy_indirect_args.cpu[group_index] = .{
            vertex_count = mesh.index_count,
            instance_count = 0,
            vertex_start = 0,
            base_instance = 0,
        };
    }

    PhysicsSystem_OptimizeBroadPhase(Physics.physics.system);
}

spawn_enemy :: (spawn_index: s32) -> bool {
    if enemy_shape == null || !enemy_spawn_params.enabled return false;
    if spawn_index < 0 || spawn_index >= enemy_runtime.count return false;
    if enemy_runtime[spawn_index].active return false;

    player_pos := character_controller_position(*running_lizard_controller);
    spawn_seed := cast(u32) spawn_index * 2654435761 + cast(u32) floor(time * 11.0);
    spawn_angle := running_lizard_controller.facing_yaw + lerp(-1.9, 1.9, hash01(cast(u32) floor(time * 37.0) + cast(u32) spawn_index * 17));
    spawn_radius := lerp(enemy_spawn_params.spawn_radius_min, enemy_spawn_params.spawn_radius_max,
        hash01(spawn_seed));
    spawn_pos := player_pos + .{cos(spawn_angle) * spawn_radius, 0.0, sin(spawn_angle) * spawn_radius};
    min_head_size := min(enemy_spawn_params.min_head_size, enemy_spawn_params.max_head_size);
    max_head_size := max(enemy_spawn_params.min_head_size, enemy_spawn_params.max_head_size);
    size_variation := lerp(min_head_size, max_head_size, hash01(spawn_seed ^ 0x9e3779b9));
    scaled_collider_radius := enemy_collider_radius * size_variation;
    scaled_collider_half_height := enemy_collider_half_height * size_variation;
    spawn_pos.y = ground_height_at(active_ground, spawn_pos.x, spawn_pos.z) + scaled_collider_radius + scaled_collider_half_height + 0.04;
    spawn_pos_jph := cast,force(RVec3) spawn_pos;
    hue_variation := hash01(spawn_seed ^ 0x85ebca6b);
    brightness_variation := lerp(0.88, 1.18, hash01(spawn_seed ^ 0xc2b2ae35));
    tint := lerp(Vector4.{0.92, 0.76, 0.72, 1.0}, Vector4.{1.58, 0.46, 0.36, 1.0}, hue_variation) * brightness_variation;
    tint.w = 1.0;

    enemy_body_shape := enemy_shape;
    if abs(size_variation - 1.0) > 0.001 {
        scale_vec := Vec3.{size_variation, size_variation, size_variation};
        enemy_body_shape = cast(*Shape) ScaledShape_Create(enemy_shape, *scale_vec);
        assert(enemy_body_shape != null, "Enemy scaled shape creation failed.");
    }

    body_settings := BodyCreationSettings_Create3(enemy_body_shape, *spawn_pos_jph, null, .Dynamic, Physics.Layers.MOVING);
    assert(body_settings != null, "Enemy body settings creation failed.");
    defer BodyCreationSettings_Destroy(body_settings);
    BodyCreationSettings_SetGravityFactor(body_settings, 0.0);
    BodyCreationSettings_SetFriction(body_settings, 0.0);
    BodyCreationSettings_SetLinearDamping(body_settings, 8.0);
    BodyCreationSettings_SetAngularDamping(body_settings, 8.0);
    BodyCreationSettings_SetAllowedDOFs(body_settings,
        cast(AllowedDOFs) (AllowedDOFs.TranslationX | AllowedDOFs.TranslationY | AllowedDOFs.TranslationZ | AllowedDOFs.RotationY));
    BodyCreationSettings_SetMotionQuality(body_settings, .LinearCast);

    body_id := BodyInterface_CreateAndAddBody(Physics.physics.body_interface, body_settings, .Activate);
    BodyInterface_SetUserData(Physics.physics.body_interface, body_id, cast(u64) spawn_index + 1);

    enemy_runtime[spawn_index] = .{
        active = true,
        body_id = body_id,
        shape = enemy_body_shape,
        hp = 3.0,
        hit_flash_t = 0.0,
        yaw = spawn_angle + PI,
        visual_scale = enemy_model_scale * size_variation,
        collider_scale = size_variation,
        collider_kind = enemy_collider_kind,
        tint = tint,
    };
    enemy_alive_count += 1;
    return true;
}

update_enemy_horde :: (dt: float) {
    if enemy_runtime.count == 0 return;
    enemy_spawn_params.target_alive = clamp(enemy_spawn_params.target_alive, 0, enemy_max_count);
    enemy_spawn_params.climb_speed_ratio = max(0.0, enemy_spawn_params.climb_speed_ratio);
    if enemy_spawn_params.min_head_size > enemy_spawn_params.max_head_size {
        temp := enemy_spawn_params.min_head_size;
        enemy_spawn_params.min_head_size = enemy_spawn_params.max_head_size;
        enemy_spawn_params.max_head_size = temp;
    }

    player_pos := character_controller_position(*running_lizard_controller);
    active_contacts: s32;
    for *enemy_runtime {
        if !it.active continue;
        it.hit_flash_t = max(0.0, it.hit_flash_t - dt);

        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        scaled_collider_radius := enemy_collider_radius * it.collider_scale;
        scaled_collider_half_height := enemy_collider_half_height * it.collider_scale;
        to_player := player_pos - body_pos;
        planar_to_player := Vector3.{to_player.x, 0.0, to_player.z};
        planar_dist := length(planar_to_player);
        if planar_dist > enemy_spawn_params.despawn_radius {
            Physics.destroy_body(it.body_id);
            it.* = .{};
            enemy_alive_count -= 1;
            continue;
        }

        if planar_dist > 0.001 {
            move_dir := planar_to_player / planar_dist;
            desired_ground_y := ground_height_at(active_ground, body_pos.x, body_pos.z) + scaled_collider_radius + scaled_collider_half_height + 0.04;
            target_vel := move_dir * enemy_spawn_params.move_speed;
            actual_velocity: Vec3;
            BodyInterface_GetLinearVelocity(Physics.physics.body_interface, it.body_id, *actual_velocity);
            planar_velocity := Vector3.{actual_velocity.x, 0.0, actual_velocity.z};
            planar_speed := length(planar_velocity);
            vertical_correction := (desired_ground_y - body_pos.y) * 10.0;
            climb_speed := enemy_spawn_params.move_speed * enemy_spawn_params.climb_speed_ratio;
            is_blocked := planar_speed < enemy_spawn_params.move_speed * 0.55 && planar_dist > scaled_collider_radius * 1.5;
            if is_blocked {
                target_vel.y = max(vertical_correction, climb_speed);
            } else {
                target_vel.y = vertical_correction;
            }
            target_vel_jph := cast,force(Vec3) target_vel;
            BodyInterface_SetLinearVelocity(Physics.physics.body_interface, it.body_id, *target_vel_jph);
            desired_yaw := it.yaw;
            if planar_speed > 0.05 {
                facing_dir := planar_velocity / planar_speed;
                desired_yaw = atan2(facing_dir.x, facing_dir.z);
            } else {
                desired_yaw = atan2(move_dir.x, move_dir.z);
            }
            it.yaw = smooth_yaw_towards(it.yaw, desired_yaw, dt, turn_speed = 12.0);
            rot := quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI, 0.0});
            rot_jph := cast,force(Quat) rot;
            body_pos_jph := cast,force(RVec3) body_pos;
            BodyInterface_SetPositionAndRotationWhenChanged(Physics.physics.body_interface, it.body_id, *body_pos_jph, *rot_jph, .Activate);
        } else {
            zero_vel := Vec3.{0.0, 0.0, 0.0};
            BodyInterface_SetLinearVelocity(Physics.physics.body_interface, it.body_id, *zero_vel);
        }

        if running_lizard_controller.character != null && CharacterVirtual_HasCollidedWithBody(running_lizard_controller.character, it.body_id) {
            active_contacts += 1;
        }
    }

    if active_contacts > 0 && player_health > 0.0 {
        player_health = max(0.0, player_health - cast(float) active_contacts * enemy_spawn_params.touch_damage_per_second * dt);
    }

    if !enemy_spawn_params.enabled return;

    enemy_spawn_accumulator += enemy_spawn_params.spawn_rate * dt;
    desired_spawns := cast(s32) floor(enemy_spawn_accumulator);
    enemy_spawn_accumulator -= cast(float) desired_spawns;
    if enemy_alive_count >= enemy_spawn_params.target_alive return;

    spawns_remaining := min(desired_spawns, enemy_spawn_params.target_alive - enemy_alive_count);
    for *enemy_runtime {
        if spawns_remaining <= 0 break;
        if it.active continue;
        did_spawn := spawn_enemy(cast(s32) it_index);
        if did_spawn spawns_remaining -= 1;
    }
}

kill_enemy :: (enemy_index: s32) {
    if enemy_index < 0 || enemy_index >= enemy_runtime.count return;
    enemy := *enemy_runtime[enemy_index];
    if !enemy.active return;
    Physics.destroy_body(enemy.body_id);
    if enemy.shape != null && enemy.shape != enemy_shape Shape_Destroy(enemy.shape);
    enemy_runtime[enemy_index] = .{};
    enemy_alive_count = max(cast(s32) 0, enemy_alive_count - 1);
}

find_closest_enemy_to_player :: (player_pos: Vector3) -> s32 {
    best_index: s32 = -1;
    best_dist_sq := 1.0e30;
    for enemy_runtime {
        if !it.active continue;
        enemy_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        to_enemy := enemy_pos - player_pos;
        dist_sq := dot(to_enemy, to_enemy);
        if dist_sq < best_dist_sq {
            best_dist_sq = dist_sq;
            best_index = cast(s32) it_index;
        }
    }
    return best_index;
}

spawn_player_projectile :: (origin: Vector3, dir: Vector3) -> bool {
    if dot(dir, dir) < 1.0e-8 return false;
    for *projectile_runtime {
        if it.active continue;
        it.* = .{
            active = true,
            life_remaining = auto_fire_params.projectile_life,
            position = origin,
            velocity = normalize(dir) * auto_fire_params.projectile_speed,
        };
        projectile_active_count += 1;
        return true;
    }
    return false;
}

projectile_hits_enemy :: (projectile_pos: Vector3, projectile_radius: float, enemy_index: s32) -> bool {
    if enemy_index < 0 || enemy_index >= enemy_runtime.count return false;
    enemy := enemy_runtime[enemy_index];
    if !enemy.active return false;

    enemy_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, enemy.body_id);
    scaled_collider_radius := enemy_collider_radius * enemy.collider_scale;
    scaled_collider_half_height := enemy_collider_half_height * enemy.collider_scale;
    combined_radius := projectile_radius + scaled_collider_radius;
    if #complete enemy.collider_kind == {
    case .SPHERE;
        return length(projectile_pos - enemy_pos) <= combined_radius;
    case .CAPSULE;
        segment_a := enemy_pos + .{0.0, scaled_collider_half_height, 0.0};
        segment_b := enemy_pos - .{0.0, scaled_collider_half_height, 0.0};
        segment := segment_b - segment_a;
        segment_len_sq := dot(segment, segment);
        t := ifx segment_len_sq > 1.0e-8 then clamp(dot(projectile_pos - segment_a, segment) / segment_len_sq, 0.0, 1.0) else 0.0;
        closest := segment_a + segment * t;
        return length(projectile_pos - closest) <= combined_radius;
    }
    return false;
}

update_auto_fire_and_projectiles :: (dt: float) {
    projectile_active_count = 0;
    for *projectile_runtime {
        if !it.active continue;
        it.life_remaining -= dt;
        if it.life_remaining <= 0.0 {
            it.* = .{};
            continue;
        }

        next_pos := it.position + it.velocity * dt;
        hit_enemy_index: s32 = -1;
        for enemy_runtime {
            if !it.active continue;
            if projectile_hits_enemy(next_pos, auto_fire_params.projectile_radius, cast(s32) it_index) {
                hit_enemy_index = cast(s32) it_index;
                break;
            }
        }

        if hit_enemy_index >= 0 {
            enemy := *enemy_runtime[hit_enemy_index];
            enemy.hp -= 1.0;
            enemy.hit_flash_t = 0.16;
            if enemy.hp <= 0.0 {
                kill_enemy(hit_enemy_index);
            }
            it.* = .{};
            continue;
        }

        it.position = next_pos;
        projectile_active_count += 1;
    }

    if !auto_fire_params.enabled || auto_fire_params.shots_per_second <= 0.0 return;
    if enemy_alive_count <= 0 return;

    player_shot_accumulator += auto_fire_params.shots_per_second * dt;
    shots_to_fire := cast(s32) floor(player_shot_accumulator);
    if shots_to_fire <= 0 return;
    player_shot_accumulator -= cast(float) shots_to_fire;

    player_pos := character_controller_position(*running_lizard_controller);
    origin := player_pos + .{0.0, 0.95, 0.0};
    for 0..shots_to_fire-1 {
        target_enemy_index := find_closest_enemy_to_player(player_pos);
        if target_enemy_index < 0 break;
        target_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, enemy_runtime[target_enemy_index].body_id);
        target_pos.y += enemy_collider_half_height + enemy_collider_radius * 0.35;
        spawn_player_projectile(origin, target_pos - origin);
    }
}

enemy_lod_level_for_distance :: (render_mesh: Enemy_Render_Mesh, distance_to_camera: float) -> s32 {
    if render_mesh.lod_mesh_count <= 0 return 0;
    if render_mesh.lod_mesh_count == 1 {
        if distance_to_camera >= 18.0 return 1;
        return 0;
    }
    if distance_to_camera >= 42.0 return 2;
    if distance_to_camera >= 18.0 return 1;
    return 0;
}

refresh_enemy_horde_render_state :: (view_proj: Matrix4, shadow_binding: Vector4, camera_pos: Vector3) {
    if enemy_runtime.count == 0 || enemy_draw_groups.count == 0 || enemy_instances.cpu.data == null return;
    enemy_visible_count_debug = 0;
    enemy_render_instance_count_debug = 0;

    for *enemy_draw_groups {
        it.first_instance = 0;
        it.instance_count = 0;
    }

    group_instance_counts: [..]u32;
    group_instance_counts.allocator = temp;
    array_resize(*group_instance_counts, enemy_draw_groups.count);
    for *group_instance_counts it.* = 0;

    mask_model := scene_geo.models[enemy_mask_model_index];
    visible_enemy_count: s32;
    for *enemy_runtime {
        if !it.active continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        to_camera := camera_pos - body_pos;
        distance_to_camera := length(to_camera);
        if distance_to_camera > enemy_spawn_params.despawn_radius continue;
        visible_enemy_count += 1;
        for render_mesh, render_mesh_index: enemy_render_meshes {
            lod_level := enemy_lod_level_for_distance(render_mesh, distance_to_camera);
            group_index := enemy_draw_group_index(render_mesh_index, lod_level);
            if group_index >= 0 group_instance_counts[group_index] += 1;
        }
    }

    running_first_instance: u32;
    for *enemy_draw_groups {
        it.first_instance = running_first_instance;
        it.instance_count = group_instance_counts[it_index];
        running_first_instance += it.instance_count;
    }

    group_write_offsets: [..]u32;
    group_write_offsets.allocator = temp;
    array_resize(*group_write_offsets, enemy_draw_groups.count);
    for *group_write_offsets it.* = enemy_draw_groups[it_index].first_instance;

    for *enemy_runtime {
        if !it.active continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        to_camera := camera_pos - body_pos;
        distance_to_camera := length(to_camera);
        if distance_to_camera > enemy_spawn_params.despawn_radius continue;

        actual_velocity: Vec3;
        BodyInterface_GetLinearVelocity(Physics.physics.body_interface, it.body_id, *actual_velocity);
        visual_root_pos := body_pos + .{0.0, enemy_model_root_offset_y * (it.visual_scale / max(enemy_model_scale, 0.001)), 0.0};
        visual_scale: Vector3 = .{it.visual_scale, it.visual_scale, it.visual_scale};
        world_root := make_trs_matrix(visual_root_pos, quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI + 225.0, 0.0}), visual_scale);
        for render_mesh, render_mesh_index: enemy_render_meshes {
            lod_level := enemy_lod_level_for_distance(render_mesh, distance_to_camera);
            group_index := enemy_draw_group_index(render_mesh_index, lod_level);
            if group_index < 0 continue;
            write_index := group_write_offsets[group_index];
            group_write_offsets[group_index] += 1;
            node_local_index := render_mesh.node_index - cast(s32) mask_model.node_start;
            world := world_root;
            if node_local_index >= 0 {
                world = world_root * scene_geo.nodes[render_mesh.node_index].world;
            }
            flash_mix := clamp(it.hit_flash_t * 9.0, 0.0, 1.0);
            tint := lerp(it.tint, Vector4.{3.2, 3.2, 3.2, 1.0}, flash_mix);
            enemy_instances.cpu[write_index] = .{
                world = world,
                tint = tint,
                shadow_view_proj = shadow_map.view_proj,
                shadow_meta = shadow_binding,
            };
            enemy_render_instance_count_debug += 1;
        }
    }
    enemy_visible_count_debug = visible_enemy_count;

    for group, group_index: enemy_draw_groups {
        mesh := scene_geo.meshes[group.mesh_index];
        enemy_draw_params.cpu[group_index].indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr);
        enemy_draw_params.cpu[group_index].instances = enemy_instances.gpu + (group.first_instance * size_of(Scene_Instance)).(Gpu_Ptr);
        enemy_draw_params.cpu[group_index].view_proj = view_proj;
        enemy_draw_params.cpu[group_index].camera_pos = camera_pos;
        enemy_draw_params.cpu[group_index].light_dir = shadow_map.light_dir;
        enemy_draw_params.cpu[group_index].sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0};
        enemy_draw_params.cpu[group_index].material_index = mesh.material_index;
        enemy_draw_params.cpu[group_index].mesh_base_vertex = mesh.base_vertex;
        enemy_indirect_args.cpu[group_index] = .{
            vertex_count = mesh.index_count,
            instance_count = group.instance_count,
            vertex_start = 0,
            base_instance = 0,
        };
    }
}

enemy_draw_group_index :: (render_mesh_index: s64, lod_level: s32) -> s32 {
    running_index: s32;
    for enemy_render_meshes {
        lod_count := 1 + cast(s32) it.lod_mesh_count;
        if it_index == render_mesh_index {
            if lod_level < 0 || lod_level >= lod_count return -1;
            return running_index + lod_level;
        }
        running_index += lod_count;
    }
    return -1;
}

apply_mediapipe_demo_bone_offset :: (node_index: s32, rotation_offset: Quaternion) {
    if node_index < 0 return;
    local_index := node_index - cast(s32) scene_geo.models[mediapipe_body_model_index].node_start;
    if local_index < 0 || local_index >= mediapipe_body_anim.locals.count return;
    local := *mediapipe_body_anim.locals[local_index];
    local.rotation = rotation_offset * local.rotation;
    normalize_or_identity(*local.rotation);
}

set_model_morph_wave_weights :: (state: *Scene_Anim_State, model_index: s32, t: float, phase: float) {
    if model_index < 0 return;
    model := scene_geo.models[model_index];
    for mesh_index: model.mesh_start .. model.mesh_start + model.mesh_count - 1 {
        mesh := scene_geo.meshes[mesh_index];
        if mesh.morph_target_count == 0 continue;
        for local_index: 0..mesh.morph_target_count-1 {
            state.morph_weights[mesh.morph_target_start + local_index] = 0.0;
        }
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeBlinkLeft",  clamp(0.5 + 0.5 * sin(t * 1.7 + phase), 0.0, 1.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeBlinkRight", clamp(0.5 + 0.5 * sin(t * 1.7 + phase + 1.7), 0.0, 1.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeSquintLeft", 0.12 + 0.10 * sin(t * 1.1 + phase + 0.2));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeSquintRight", 0.12 + 0.10 * sin(t * 1.1 + phase + 1.1));
        set_named_morph_weight(state, cast(s32) mesh_index, "browInnerUp", 0.2 + 0.18 * sin(t * 0.7 + phase));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthSmileLeft", 0.2 + 0.18 * sin(t * 0.9 + phase + 2.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthSmileRight", 0.2 + 0.18 * sin(t * 0.9 + phase + 3.3));
        set_named_morph_weight(state, cast(s32) mesh_index, "jawOpen", 0.18 + 0.16 * sin(t * 1.2 + phase + 0.8));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthFunnel", 0.12 + 0.12 * sin(t * 0.6 + phase + 1.3));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeWideLeft", 0.05 + 0.08 * sin(t * 1.0 + phase + 0.5));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeWideRight", 0.05 + 0.08 * sin(t * 1.0 + phase + 1.0));
    }
}

scene_apply_manip_live_to_runtime :: () {
    if scene_manip_ctx.selected_index < 0 return;
    selected := cast(s64) scene_manip_ctx.selected_index;
    if selected >= scene_manip_objects.count return;

    node_index := scene_manip_node_indices[selected];
    compiled_index := find_compiled_node_for_source(scene_doc.source_path, scene_doc.nodes[node_index].name);
    if compiled_index < 0 return;

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

    compiled_node := *compiled_scene.nodes[compiled_index];
    compiled_node.local_position = local_pos;
    compiled_node.local_rotation_deg = local_rot_deg;
    compiled_node.local_scale = local_scale;
    scene_recompute_compiled_worlds();
    scene_refresh_runtime_instance_worlds_from_compiled();
    scene_dirty = true;
}

scene_refresh_runtime_instance_worlds_from_compiled :: () {
    for batch: scene_batches {
        if it_index >= batch_compiled_node_indices.count continue;
        compiled_index := batch_compiled_node_indices[it_index];
        if compiled_index < 0 || compiled_index >= compiled_scene.nodes.count continue;
        compiled_node := compiled_scene.nodes[compiled_index];
        instance_world := compiled_node.world;
        if compiled_node.asset_index >= 0 {
            instance_world = instance_world * compiled_asset_import_matrix(compiled_scene.assets[compiled_node.asset_index]);
        }
        for instance_i: 0..batch.instance_count-1 {
            scene_instances.cpu[batch.first_instance + instance_i].world = instance_world;
        }
    }
}

scene_recompute_compiled_worlds :: () {
    for node_index: 0..compiled_scene.nodes.count-1 {
        node := *compiled_scene.nodes[node_index];
        local := make_trs_matrix(node.local_position, quat_from_euler_deg(node.local_rotation_deg), node.local_scale);
        node.world = local;
        if node.parent_index >= 0 node.world = compiled_scene.nodes[node.parent_index].world * local;
    }
}

scene_apply_manip_back_to_doc :: () {
    scene_apply_manip_live_to_runtime();
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

append_pick_ids_for_new_batches :: (start_batch_count: s64, object_id: u32) {
    while batch_pick_object_ids.count < start_batch_count array_add(*batch_pick_object_ids, 0);
    while batch_pick_object_ids.count < scene_batches.count array_add(*batch_pick_object_ids, object_id);
}

append_compiled_node_indices_for_new_batches :: (start_batch_count: s64, compiled_node_index: s32) {
    while batch_compiled_node_indices.count < start_batch_count array_add(*batch_compiled_node_indices, -1);
    while batch_compiled_node_indices.count < scene_batches.count array_add(*batch_compiled_node_indices, compiled_node_index);
}

compiled_node_pick_object_id :: (compiled_node_index: s32) -> u32 {
    if compiled_node_index < 0 || compiled_node_index >= compiled_scene.nodes.count return 0;
    node := compiled_scene.nodes[compiled_node_index];
    if node.source_kind != .ROOT_SCENE return 0;
    if node.source_node_index < 0 || node.source_node_index >= scene_doc.nodes.count return 0;
    return cast(u32) node.source_node_index + 1;
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

metal_stage_entry_name :: (metal: []u8, stage_keyword: string) -> string {
    source := cast(string) metal;
    stage_pattern := tprint("% ", stage_keyword);
    stage_index := String.find_index_from_left(source, stage_pattern);
    assert(stage_index >= 0, "Failed to find Metal stage keyword '%' in shader source.", stage_keyword);

    token_start := stage_index + stage_pattern.count;
    while token_start < source.count && source[token_start] == #char " " token_start += 1;
    while token_start < source.count && source[token_start] != #char " " token_start += 1; // skip return type
    while token_start < source.count && source[token_start] == #char " " token_start += 1;

    token_end := token_start;
    while token_end < source.count && source[token_end] != #char "(" && source[token_end] != #char " " token_end += 1;
    assert(token_end > token_start, "Failed to parse Metal % entry point name.", stage_keyword);
    return string.{count = token_end - token_start, data = source.data + token_start};
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
    grass_shadow_params = gpu_alloc_buffer(Grass_Shadow_Params_CPU, label = "model scene grass shadow params");
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
        morph_vertex_deltas = 0,
        morph_weights = 0,
        skin_matrices = 0,
        view_proj = Matrix4_Identity,
        light_dir = normalize(.{0.35, -1.0, 0.25}),
        sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0},
        camera_pos = scene_camera.position,
        material_index = 0,
        object_id = 0,
        mesh_base_vertex = 0,
        skin_matrix_count = 0,
        morph_target_count = 0,
        morph_vertex_count = 0,
    };
    ground_draw_params.cpu.* = .{
        vertices = ground_vertices.gpu,
        indices = ground_indices.gpu,
        instances = ground_instance.gpu,
        view_proj = Matrix4_Identity,
        light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
        sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0},
        camera_pos = scene_camera.position,
        sampler_index = cast(u32) ground_sampler - 1,
        base_color_texture_index = gpu_texture_view_index(ground_texture_view),
        normal_texture_index = gpu_texture_view_index(ground_normal_texture_view),
        roughness_texture_index = gpu_texture_view_index(ground_roughness_texture_view),
        ao_texture_index = gpu_texture_view_index(ground_ao_texture_view),
    };
    grass_grid_x := max(1, ground.render_grid_x * 4 / 3 * 3);
    grass_grid_z := max(1, ground.render_grid_z * 4 / 3 * 3);
    grass_instance_count = cast(u32) grass_grid_x * cast(u32) grass_grid_z;
    grass_shadow_params.cpu.* = .{
        shadow_view_proj = Matrix4_Identity,
        ground_size_center_z_time = .{ground.size_x, ground.size_z, ground.center_z, 0.0},
        ground_shape = .{ground.ridge, ground.swell, ground.warp, 0.0},
        grass_grid_height_width = .{cast(float) grass_grid_x, cast(float) grass_grid_z, 0.33, 0.24},
        player_pos_radius = .{0.0, 0.0, 0.0, 1.7},
    };
    grass_draw_params.cpu.* = .{
        view_proj = Matrix4_Identity,
        shadow_view_proj = Matrix4_Identity,
        light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
        sun_params = .{model_scene_sun_strength, time_of_day, 0.0, 0.0},
        camera_pos = scene_camera.position,
        shadow_meta = .{0.0, 0.0, 0.0, 0.0},
        ground_size_center_z_time = grass_shadow_params.cpu.ground_size_center_z_time,
        ground_shape = grass_shadow_params.cpu.ground_shape,
        grass_grid_height_width = grass_shadow_params.cpu.grass_grid_height_width,
        player_pos_radius = grass_shadow_params.cpu.player_pos_radius,
    };
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

model_scene_sun_direction :: (time_of_day: float) -> Vector3 {
    tau := cast(float) 6.28318530718;
    phase := (time_of_day - 0.25) * tau;
    elevation := sin(phase) * cast(float) 0.92;
    horizontal := sqrt(max(1.0 - elevation * elevation, 0.0001));
    return normalize(Vector3.{cos(phase) * horizontal, elevation, sin(phase) * horizontal * 0.55});
}

wrap_angle_pi :: (angle: float) -> float {
    wrapped := angle;
    while wrapped > PI  wrapped -= PI * 2.0;
    while wrapped < -PI wrapped += PI * 2.0;
    return wrapped;
}

smooth_yaw_towards :: (current: float, target: float, dt: float, turn_speed: float) -> float {
    max_step := max(0.0, turn_speed) * dt;
    delta := wrap_angle_pi(target - current);
    if abs(delta) <= max_step return current + delta;
    step_sign := ifx delta < 0.0 then -1.0 else 1.0;
    return current + step_sign * max_step;
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

toggle_control_mode :: () {
    if #complete control_mode == {
    case .Player; control_mode = .Editor;
    case .Editor; control_mode = .Player;
    }
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
JPH :: #import "JoltC";
using JPH;
ai :: #import "assimp";
String :: #import "String";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Random";
#import "stb_image";
#import "Math";
#load "shaders/model_scene_shader.jai";

Persist :: #import,file "../ui/persist_controls.jai";
