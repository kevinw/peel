#load "../linear_present.jai";

SCENE_ROOT_PATH :: "./scenes/model_scene.scene";

Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
    max_meshlet_count: u32;
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
Model_Scene_Meshlet_Params_CPU :: CPU_Struct(Model_Scene_Meshlet_Params);
using shaders: struct @init_group {
    graphics_shader: Shader(model_scene_vertex_main, model_scene_fragment_main, .{
        cull = .CW,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R16G16B16A16_SFLOAT},
        ],
    });
    pick_shader: Shader(model_scene_vertex_main, model_scene_pick_fragment_main, .{
        cull = .CW,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    });
    ground_shader: Shader(ground_vertex_main, ground_fragment_main, .{
        cull = .CW,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R16G16B16A16_SFLOAT},
        ],
    });
    ground_shadow_shader: Shader(ground_shadow_vertex_main, ground_shadow_fragment_main, .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R32_SFLOAT},
        ],
    });
    shadow_shader: Shader(model_scene_shadow_vertex_main, model_scene_shadow_fragment_main, .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R32_SFLOAT},
        ],
    });
    mesh_shader: Mesh_Shader(model_scene_mesh_main, model_scene_meshlet_fragment_main, .{
        raster_desc = .{
            cull = .CW,
            derive_attachment_formats_from_render_pass = true,
        },
        task_threads = .[1, 1, 1],
        mesh_threads = .[1, 1, 1],
        max_total_threadgroups_per_mesh_grid = 1024,
    }, model_scene_task_main);
    grass_shader: Shader(model_scene_grass_vertex_main, model_scene_grass_fragment_main, .{
        cull = .CCW,
        depth_format = .D32_SFLOAT,
        color_targets = .[ {format = .R16G16B16A16_SFLOAT}, ],
    });
    grass_shadow_shader: Shader(model_scene_grass_shadow_vertex_main, model_scene_grass_shadow_fragment_main, .{
        cull = .CCW,
        depth_format = .D32_SFLOAT,
        color_targets = .[ {format = .R32_SFLOAT}, ],
    });
    debug_shadow_shader: Shader(model_scene_debug_shadow_vertex_main, model_scene_debug_shadow_fragment_main, .{
        cull = .CW,
        depth_format = .D32_SFLOAT,
        color_targets = .[ {format = .R16G16B16A16_SFLOAT}, ],
    });
    debug_pick_shader: Shader(model_scene_debug_shadow_vertex_main, model_scene_debug_pick_fragment_main, .{
        cull = .CW,
        depth_format = .D32_SFLOAT,
        color_targets = .[ {format = .R16G16B16A16_SFLOAT}, ],
    });
    sky_shader: Shader(model_scene_sky_vertex_main, model_scene_sky_fragment_main, .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[ {format = .R16G16B16A16_SFLOAT}, ],
    });
};
gpu_arena: Gpu_Arena;
scene_geo: Scene_Geo;
shadow_map: Shadow_Map;
running_lizard_controller: Character_Controller;
running_lizard_anim_tree: Scene_Anim_Blend_Tree;
mediapipe_body_anim: Scene_Anim_State;
running_lizard_idle_clip_index: s32 = -1; // Resolved idle clip for the player model.
running_lizard_walk_clip_index: s32 = -1; // Resolved walk clip for the player model.
running_lizard_jump_clip_index: s32 = -1; // Resolved jump clip for the player model.
running_lizard_idle_player_index: s32 = -1; // Blend-tree leaf player sampling the idle clip.
running_lizard_walk_player_index: s32 = -1; // Blend-tree leaf player sampling the walk clip.
running_lizard_jump_player_index: s32 = -1; // Blend-tree leaf player sampling the jump clip.
running_lizard_locomotion_node_index: s32 = -1; // Blend node mixing idle and walk.
running_lizard_output_node_index: s32 = -1; // Final blend node mixing locomotion and jump.
running_lizard_move_alpha: float; // Smoothed idle-to-walk blend factor.
running_lizard_airborne_alpha: float; // Smoothed grounded-to-airborne blend factor.
running_lizard_root: Matrix4 = Matrix4_Identity; // World transform applied to the sampled player pose.
running_lizard_spawn_position: Vector3;
running_lizard_spawn_visual_yaw_offset: float = PI;
mediapipe_body_root: Matrix4 = Matrix4_Identity;
running_lizard_scale: float = 1.0;
running_lizard_ground_y: float = 0.5;
mediapipe_body_scale: float = 1.0;
mediapipe_demo_focus: Vector3 = .{0.0, 2.3, -6.2};
horde_runtime: Horde_Runtime;
horde_reset_pending: bool;
scene_rebuild_pending: bool;
scene_reload_pending: bool;
scene_static_instances: Gpu_View(Scene_Instance);
scene_dynamic_instances: Gpu_Frame_View(Scene_Instance);
scene_static_meshlet_instances: Gpu_View(Model_Scene_Meshlet_Instance);
scene_dynamic_meshlet_instances: Gpu_Frame_View(Model_Scene_Meshlet_Instance);
scene_static_instance_world_rows: Gpu_View(Vector4);
scene_dynamic_instance_world_rows: Gpu_Frame_View(Vector4);
scene_static_instance_tints: Gpu_View(Vector4);
scene_dynamic_instance_tints: Gpu_Frame_View(Vector4);
scene_static_instance_shadow_view_proj_rows: Gpu_View(Vector4);
scene_dynamic_instance_shadow_view_proj_rows: Gpu_Frame_View(Vector4);
scene_static_instance_shadow_metas: Gpu_View(Vector4);
scene_dynamic_instance_shadow_metas: Gpu_Frame_View(Vector4);
scene_draw_params: Gpu_Frame_View(Scene_Draw_Params_CPU);
scene_draw_params_template: []Scene_Draw_Params_CPU;
scene_skin_matrices: Gpu_Frame_View(Vector4);
scene_morph_weights: Gpu_Frame_View(float);
scene_meshlet_params: Gpu_Frame_Param_Allocator(Model_Scene_Meshlet_Params_CPU);
scene_meshes_gpu: Gpu_View(Scene_Mesh);
scene_depth: Texture_Ring;
scene_depth_w: u32;
scene_depth_h: u32;
scene_present: Linear_Present_State;
ground_vertices: Gpu_View(Scene_Vertex);
ground_indices: Gpu_View(u32);
ground_instance: Gpu_Buffer_Ring(Scene_Instance);
ground_shadow_params: Gpu_Buffer_Ring(Ground_Draw_Params_CPU);
ground_draw_params: Gpu_Buffer_Ring(Ground_Draw_Params_CPU);
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
grass_draw_params: Gpu_Buffer_Ring(Grass_Draw_Params);
grass_shadow_params: Gpu_Buffer_Ring(Grass_Shadow_Params_CPU);
sky_draw_params: Gpu_Buffer_Ring(Model_Scene_Sky_Params_CPU);
debug_pick_params: Gpu_Buffer_Ring(Scene_Draw_Params_CPU);
grass_instance_count: u32;
grass_shadow_instance_count: u32;
render_grass: bool = true;
grass_density_scale: float = 4.0;
grass_shadow_density_scale: float = 1.05;
grass_jitter: float = 0.28;
grass_blade_height: float = 0.22;
grass_fade_start: float = 10.0;
grass_fade_end: float = 26.0;
grass_far_shade_start: float = 16.0;
grass_shadow_fade_start: float = 7.0;
grass_shadow_fade_end: float = 16.0;
scene_shadows_enabled: bool = true;
mediapipe_body_casts_shadows: bool = true;
mediapipe_face_casts_shadows: bool = true;
ground_physics_body: u32;
ground_physics_body_valid: bool;
stone_physics_bodies: [..]u32;
stone_base_shapes: [..]Physics.Collider_Shape;
stone_scaled_shapes: [..]Physics.Collider_Shape;
scene_batches: [..]Draw_Batch;
scene_batch_uses_dynamic_instances: [..]bool;
animated_batches: [..]Animated_Batch;
running_lizard_instances: [..]Running_Lizard_Instance;
running_lizard_attachment_instances: [..]Running_Lizard_Attachment_Instance;
mediapipe_demo_instances: [..]Mediapipe_Demo_Instance;
mediapipe_face_instances: [..]Mediapipe_Face_Instance;
mediapipe_body_model_index: s32 = -1;
mediapipe_face_model_index: s32 = -1;
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
control_mode: enum { Player; Editor; } = .Player;
outdoor_rig: Outdoor_Rig = .{};
graphics_shader_constants: Model_Scene_Meshlet_Constants;
mesh_shader_constants: Model_Scene_Meshlet_Constants;
mesh_grid_limit: u32;
lod_screen_radius: float = 420.0;
lod_distance_power: float = 1.18;
orbit_yaw: float = 0.0;
orbit_pitch: float = -0.32;
orbit_distance: float = 8.5;
PLAYER_CAMERA_GROUND_CLEARANCE :: 0.15;
orbit_prev_mouse: Vector2;
orbit_have_prev_mouse: bool;
left_was_down: bool;
gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
gizmo_overlay_ctx: Gizmo.Gizmo_Context;
gizmo_overlay_render_ctx: Gizmo_Render.Gizmo_Render_Context;

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

    assert(linear_present_init(*scene_present, "model scene present"), "Failed to initialize model_scene present state.");
    shadow_map_init(*shadow_map);
    sky_draw_params = gpu_make_buffer_ring(Model_Scene_Sky_Params_CPU, label = "model scene sky params");
    debug_pick_params = gpu_make_buffer_ring(Scene_Draw_Params_CPU, label = "model scene debug pick params");
    mesh_grid_limit = gpu_get_mesh_pipeline_max_total_threadgroups_per_grid(mesh_shader.pipeline);
    if mesh_grid_limit == 0 mesh_grid_limit = 1024;
    mediapipe_body_casts_shadows = false;
    mediapipe_face_casts_shadows = false;

    scene_palette_models = Scene_File.scan_scene_palette_models();
    scene_doc, compiled_scene = Scene_File.load_compiled_scene_cached(SCENE_ROOT_PATH);
    init_scene_geo_from_palette();
    rebuild_scene_runtime();
    scene_manip_objects_dirty = true;
    scene_manip_apply_pending = false;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
        assert(linear_present_ensure_color_target(*scene_present, cast(u32) win_w, cast(u32) win_h), "Failed to create model_scene color target.");
        ensure_scene_pick_target(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

on_quit :: () {
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
    linear_present_deinit(*scene_present);
    linear_present_shutdown_shader();
    shadow_map_deinit(*shadow_map);
    array_free(running_lizard_instances);
    array_free(running_lizard_attachment_instances);
    array_free(mediapipe_demo_instances);
    array_free(mediapipe_face_instances);
    array_free(shadow_skip_batch);
    array_free(batch_pick_object_ids);
    array_free(batch_compiled_node_indices);
    deinit(*horde_runtime);
    array_free(animated_batches);
    array_free(scene_batches);
    array_free(scene_batch_uses_dynamic_instances);
    scene_geo_deinit(*scene_geo);
} @on_quit


tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    current_scene_draw_params := sgpu_frame_view_slot(*scene_draw_params);
    current_dynamic_instances: Gpu_View(Scene_Instance);
    if scene_dynamic_instances.items_per_frame > 0 {
        current_dynamic_instances = sgpu_frame_view_slot(*scene_dynamic_instances);
    }
    current_dynamic_meshlet_instances: Gpu_View(Model_Scene_Meshlet_Instance);
    if scene_dynamic_meshlet_instances.items_per_frame > 0 {
        current_dynamic_meshlet_instances = sgpu_frame_view_slot(*scene_dynamic_meshlet_instances);
    }
    current_dynamic_instance_world_rows: Gpu_View(Vector4);
    if scene_dynamic_instance_world_rows.items_per_frame > 0 {
        current_dynamic_instance_world_rows = sgpu_frame_view_slot(*scene_dynamic_instance_world_rows);
    }
    current_dynamic_instance_tints: Gpu_View(Vector4);
    if scene_dynamic_instance_tints.items_per_frame > 0 {
        current_dynamic_instance_tints = sgpu_frame_view_slot(*scene_dynamic_instance_tints);
    }
    current_dynamic_instance_shadow_view_proj_rows: Gpu_View(Vector4);
    if scene_dynamic_instance_shadow_view_proj_rows.items_per_frame > 0 {
        current_dynamic_instance_shadow_view_proj_rows = sgpu_frame_view_slot(*scene_dynamic_instance_shadow_view_proj_rows);
    }
    current_dynamic_instance_shadow_metas: Gpu_View(Vector4);
    if scene_dynamic_instance_shadow_metas.items_per_frame > 0 {
        current_dynamic_instance_shadow_metas = sgpu_frame_view_slot(*scene_dynamic_instance_shadow_metas);
    }
    current_skin_matrices: Gpu_View(Vector4);
    if scene_skin_matrices.items_per_frame > 0 {
        current_skin_matrices = sgpu_frame_view_slot(*scene_skin_matrices);
    }
    current_morph_weights: Gpu_View(float);
    if scene_morph_weights.items_per_frame > 0 {
        current_morph_weights = sgpu_frame_view_slot(*scene_morph_weights);
    }
    current_ground_instance := gpu_buffer_ring_slot(*ground_instance);
    current_ground_shadow_params := gpu_buffer_ring_slot(*ground_shadow_params);
    current_ground_draw_params := gpu_buffer_ring_slot(*ground_draw_params);
    current_grass_draw_params := gpu_buffer_ring_slot(*grass_draw_params);
    current_grass_shadow_params := gpu_buffer_ring_slot(*grass_shadow_params);
    current_sky_draw_params := gpu_buffer_ring_slot(*sky_draw_params);
    current_debug_pick_params := gpu_buffer_ring_slot(*debug_pick_params);

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
        assert(linear_present_ensure_color_target(*scene_present, cast(u32) win_w, cast(u32) win_h), "Failed to create model_scene color target.");
    }

    io := ImGui.GetIO();
    _, p_pressed := input_down("P");
    if p_pressed toggle_control_mode();

    grass_density_scale = clamp(grass_density_scale, 0.25, 9.0);
    grass_shadow_density_scale = clamp(grass_shadow_density_scale, 0.0, 2.0);
    grass_jitter = clamp(grass_jitter, 0.0, 0.8);
    grass_blade_height = clamp(grass_blade_height, 0.05, 0.5);
    grass_fade_start = clamp(grass_fade_start, 0.0, 128.0);
    grass_fade_end = clamp(grass_fade_end, grass_fade_start + 0.001, 160.0);
    grass_far_shade_start = clamp(grass_far_shade_start, grass_fade_start, grass_fade_end);
    grass_shadow_fade_start = clamp(grass_shadow_fade_start, 0.0, 128.0);
    grass_shadow_fade_end = clamp(grass_shadow_fade_end, grass_shadow_fade_start + 0.001, 160.0);

    if app_ui_enabled {
        using ImGui;
        if Begin("Model Scene", flags = .AlwaysAutoResize) {
            Checkbox("Autopilot", *autopilot_enabled);
            if Checkbox("Physics Gizmos", *physics_gizmos_enabled) {
                Physics.debug_draw_enabled = physics_gizmos_enabled;
            }
            SliderFloat("Mesh LOD Screen Radius", *lod_screen_radius, 8.0, 1024.0, "%.1f");
            SliderFloat("Mesh LOD Power", *lod_distance_power, 0.5, 2.0, "%.2f");
            if CollapsingHeader("Grass") {
                Checkbox("Render Grass", *render_grass);
                SliderFloat("Grass Density", *grass_density_scale, 0.25, 9.0, "%.2f");
                SliderFloat("Grass Shadow Density", *grass_shadow_density_scale, 0.0, 2.0, "%.2f");
                SliderFloat("Grass Fade Start", *grass_fade_start, 1.0, 64.0, "%.1f");
                SliderFloat("Grass Fade End", *grass_fade_end, 2.0, 96.0, "%.1f");
                SliderFloat("Grass Far Shade", *grass_far_shade_start, 1.0, 96.0, "%.1f");
                SliderFloat("Grass Shadow Fade Start", *grass_shadow_fade_start, 1.0, 64.0, "%.1f");
                SliderFloat("Grass Shadow Fade End", *grass_shadow_fade_end, 2.0, 96.0, "%.1f");
            }
            Checkbox("Scene Shadows", *scene_shadows_enabled);
            do_ui(*horde_runtime);
            if Checkbox("Mediapipe Body Casts Shadows", *mediapipe_body_casts_shadows) {
                scene_rebuild_pending = true;
            }
            if Checkbox("Mediapipe Face Casts Shadows", *mediapipe_face_casts_shadows) {
                scene_rebuild_pending = true;
            }
            Checkbox("Show Shadow Debug", *show_shadow_debug);
            Checkbox("Show Pick Debug", *show_pick_debug);
            albedo_debug := graphics_shader_constants.debug_mode == .ALBEDO;
            if Checkbox("Albedo Debug", *albedo_debug) {
                graphics_shader_constants.debug_mode = ifx albedo_debug then .ALBEDO else .SHADED;
                mesh_shader_constants.debug_mode = ifx albedo_debug then .ALBEDO else .SHADED;
            }
            do_ui(*outdoor_rig);
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
                scene_reload_pending = true;
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
        camera_dt := dt;
        if control_mode == .Editor {
            camera_dt = editor_dt;
        }

        _ = editor_camera_update(*scene_camera, camera_dt, mx, my, mouse_ok,
            allow_move = !io.WantCaptureKeyboard,
            allow_look = right_down && !io.WantCaptureMouse,
            allow_zoom = !io.WantCaptureMouse);
        editor_camera_basis(scene_camera, *controller_forward, *controller_right, *controller_up);
    }

    controller_forward.y = 0.0;
    controller_right.y = 0.0;
    normalize(*controller_forward, fallback = .{0.0, 0.0, -1.0});
    normalize(*controller_right, fallback = .{1.0, 0.0, 0.0});

    desired_move: Vector3;
    jump_pressed: bool;
    if #complete control_mode == {
    case .Player;
        if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN desired_move += controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN desired_move -= controller_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN desired_move -= controller_right;
        if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN desired_move += controller_right;
        for Input.events_this_frame {
            using it;
            if type == .KEYBOARD && key_pressed && key_code == #char " " {
                jump_pressed = true;
            }
        }
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
    if horde_runtime.player_health <= 0.0 {
        desired_move = .{};
        jump_pressed = false;
    }
    character_controller_update_in_system(*running_lizard_controller, Physics.physics.system, desired_move, dt, jump_pressed);
    update(*horde_runtime, dt);
    Physics.tick(dt);
    if horde_runtime.restart_requested {
        horde_reset_pending = true;
    }
    if physics_gizmos_enabled {
        append_lizard_physics_gizmos();
        draw_physics_debug(*horde_runtime, *gizmo_ctx);
    }
    draw_debug(*horde_runtime, *gizmo_ctx);

    if control_mode == .Editor && dims_ok && win_w > 0 && win_h > 0 {
        if scene_manip_objects_dirty {
            scene_rebuild_manip_objects();
            scene_manip_objects_dirty = false;
        }
        process_scene_pick_result_if_ready();
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(scene_camera, *cam_forward, *cam_right, *cam_up);
        frame := Manip_Frame_Input.{
            viewport = .{cast(float) win_w, cast(float) win_h},
            camera_pos = scene_camera.position,
            camera_forward = cam_forward,
            camera_right = cam_right,
            camera_up = cam_up,
            fov_y = scene_camera.fov_y,
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
        clamp_player_camera_above_ground(*scene_camera);
        editor_camera_set_look_at(*scene_camera, player_focus);
    }

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(scene_camera, *cam_forward, *cam_right, *cam_up);
    view := editor_camera_make_view(*scene_camera);
    aspect := ifx win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := editor_camera_make_projection(*scene_camera, aspect, 0.05, 250.0);
    view_proj := proj * view;
    viewport := Vector2.{max(1.0, cast(float) win_w), max(1.0, cast(float) win_h)};
    ensure_scene_pick_target(cast(u32) max(1, win_w), cast(u32) max(1, win_h));

    update(*outdoor_rig, *shadow_map);
    shadow_binding := ifx scene_shadows_enabled then shadow_map_binding(*shadow_map) else Vector4.{0.0, 0.0, 2.0, 0.0};
    prepare_render(*horde_runtime, view_proj, shadow_binding, scene_camera.position, outdoor_rig.sun_strength, outdoor_rig.time_of_day);
    maybe_log(*horde_runtime);

    fill_sky_params(outdoor_rig, current_sky_draw_params.cpu, cam_forward, cam_right, cam_up, proj, shadow_map.light_dir);

    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    update_player_animation_state(dt);
    scene_anim_blend_tree_advance(*running_lizard_anim_tree, dt);
    scene_anim_blend_tree_sample(*running_lizard_anim_tree, *scene_geo);
    update_mediapipe_demo_pose(cast(float) time, current_dynamic_instances.cpu);
    running_lizard_anim := scene_anim_blend_tree_output_state(*running_lizard_anim_tree);
    assert(running_lizard_anim != null, "Player animation blend tree output is missing.");
    running_lizard_model := scene_geo.models[running_lizard_anim.model_index];
    for running_lizard_instances {
        node_local_index := it.node_index - cast(s32) running_lizard_model.node_start;
        instance_world := running_lizard_root;
        if node_local_index >= 0 && node_local_index < running_lizard_anim.worlds.count {
            instance_world = running_lizard_root * running_lizard_anim.worlds[node_local_index];
        }
        current_dynamic_instances.cpu[it.instance_index].world = instance_world;
    }
    for running_lizard_attachment_instances {
        attachment_world := running_lizard_root;
        attachment_local_index := it.attachment_node_index - cast(s32) running_lizard_model.node_start;
        if attachment_local_index >= 0 && attachment_local_index < running_lizard_anim.worlds.count {
            attachment_world = running_lizard_root * running_lizard_anim.worlds[attachment_local_index];
        }
        current_dynamic_instances.cpu[it.instance_index].world = attachment_world * it.attachment_offset * scene_geo.nodes[it.geo_node_index].world;
    }
    for animated_batches {
        batch := scene_batches[it.batch_index];
        mesh := scene_geo.meshes[batch.mesh_index];
        skin_start := cast(s64) it.skin_matrix_start * 4;
        skin_end := skin_start + cast(s64) it.skin_matrix_count * 4;
        dst := current_skin_matrices.cpu;
        dst.data += skin_start;
        dst.count = skin_end - skin_start;
        written: s64;
        if #complete it.source == {
        case .PLAYER;
            written = scene_anim_write_skin_matrices(dst, *scene_geo, running_lizard_anim, mesh, it.node_index);
        case .MEDIAPIPE_DEMO;
            written = scene_anim_write_skin_matrices(dst, *scene_geo, *mediapipe_body_anim, mesh, it.node_index);
        }
        assert(written == it.skin_matrix_count);
    }
    if current_morph_weights.cpu.data != null {
        for mesh_index: running_lizard_model.mesh_start .. running_lizard_model.mesh_start + running_lizard_model.mesh_count - 1 {
            mesh := scene_geo.meshes[mesh_index];
            if mesh.morph_target_count == 0 continue;
            dst := current_morph_weights.cpu;
            dst.data += mesh.morph_target_start;
            dst.count = mesh.morph_target_count;
            written := scene_anim_write_morph_weights(dst, *scene_geo, running_lizard_anim, mesh);
            assert(written == mesh.morph_target_count);
        }
        write_mediapipe_demo_morph_weights(cast(float) time, current_morph_weights.cpu);
    }

    for * scene_static_instances.cpu {
        it.shadow_view_proj = shadow_map.view_proj;
        it.shadow_meta = shadow_binding;
    }
    for * current_dynamic_instances.cpu {
        it.shadow_view_proj = shadow_map.view_proj;
        it.shadow_meta = shadow_binding;
    }
    write_meshlet_instances(scene_static_instances.cpu, scene_static_meshlet_instances.cpu);
    write_meshlet_instances(current_dynamic_instances.cpu, current_dynamic_meshlet_instances.cpu);
    write_instance_meshlet_views(scene_static_instances.cpu, scene_static_instance_world_rows.cpu, scene_static_instance_tints.cpu, scene_static_instance_shadow_view_proj_rows.cpu, scene_static_instance_shadow_metas.cpu);
    write_instance_meshlet_views(current_dynamic_instances.cpu, current_dynamic_instance_world_rows.cpu, current_dynamic_instance_tints.cpu, current_dynamic_instance_shadow_view_proj_rows.cpu, current_dynamic_instance_shadow_metas.cpu);
    current_ground_instance.cpu.* = ground_instance.buffers[0].cpu.*;
    current_ground_instance.cpu.shadow_view_proj = shadow_map.view_proj;
    current_ground_instance.cpu.shadow_meta = shadow_binding;

    memcpy(current_scene_draw_params.cpu.data, scene_draw_params_template.data, current_scene_draw_params.cpu.count * size_of(Scene_Draw_Params_CPU));
    for batch: scene_batches {
        current_scene_draw_params.cpu[it_index].instances = ifx scene_batch_uses_dynamic_instances[it_index]
            then current_dynamic_instances.gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr)
            else scene_static_instances.gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr);
    }
    if current_morph_weights.cpu.data != null {
        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            if mesh.morph_target_count > 0 {
                current_scene_draw_params.cpu[it_index].morph_weights = current_morph_weights.gpu + (mesh.morph_target_start * size_of(float)).(Gpu_Ptr);
            }
        }
    }
    if current_skin_matrices.cpu.data != null {
        for anim_batch: animated_batches {
            current_scene_draw_params.cpu[anim_batch.batch_index].skin_matrices = current_skin_matrices.gpu + (anim_batch.skin_matrix_start * 4 * size_of(Vector4)).(Gpu_Ptr);
            current_scene_draw_params.cpu[anim_batch.batch_index].skin_matrix_count = anim_batch.skin_matrix_count;
        }
    }
    apply_scene_lighting(outdoor_rig, current_scene_draw_params.cpu, view_proj, scene_camera.position, shadow_map.light_dir);
    current_ground_shadow_params.cpu.* = ground_shadow_params.buffers[0].cpu.*;
    current_ground_draw_params.cpu.* = ground_draw_params.buffers[0].cpu.*;
    apply_ground_lighting(outdoor_rig, current_ground_shadow_params.cpu, current_ground_draw_params.cpu, view_proj, scene_camera.position, shadow_map.light_dir);
    lizard_pos := character_controller_position(*running_lizard_controller);
    current_grass_shadow_params.cpu.* = grass_shadow_params.buffers[0].cpu.*;
    current_grass_draw_params.cpu.* = grass_draw_params.buffers[0].cpu.*;
    apply_grass_lighting(outdoor_rig, current_grass_shadow_params.cpu, *current_grass_draw_params, active_ground, lizard_pos, running_lizard_controller.facing_yaw, cast(float) time, view_proj, scene_camera.position, shadow_map.light_dir, shadow_map.view_proj, shadow_binding);
    grass_grid_x := max(1, cast(s32) ceil(cast(float) active_ground.render_grid_x * grass_density_scale));
    grass_grid_z := max(1, cast(s32) ceil(cast(float) active_ground.render_grid_z * grass_density_scale));
    grass_shadow_grid_x := max(1, cast(s32) ceil(cast(float) active_ground.render_grid_x * grass_shadow_density_scale));
    grass_shadow_grid_z := max(1, cast(s32) ceil(cast(float) active_ground.render_grid_z * grass_shadow_density_scale));
    grass_instance_count = cast(u32) grass_grid_x * cast(u32) grass_grid_z;
    grass_shadow_instance_count = cast(u32) grass_shadow_grid_x * cast(u32) grass_shadow_grid_z;
    current_grass_shadow_params.cpu.grass_grid_height_width = .{cast(float) grass_shadow_grid_x, cast(float) grass_shadow_grid_z, grass_jitter, grass_blade_height};
    current_grass_shadow_params.cpu.camera_pos_fade_start = .{scene_camera.position.x, scene_camera.position.y, scene_camera.position.z, grass_shadow_fade_start};
    current_grass_shadow_params.cpu.fade_end_far_shade_shadow_end = .{grass_fade_end, grass_far_shade_start, grass_shadow_fade_end, 0.0};
    current_grass_draw_params.cpu.grass_grid_height_width = .{cast(float) grass_grid_x, cast(float) grass_grid_z, grass_jitter, grass_blade_height};
    current_grass_draw_params.cpu.camera_pos_fade_start = .{scene_camera.position.x, scene_camera.position.y, scene_camera.position.z, grass_fade_start};
    current_grass_draw_params.cpu.fade_end_far_shade_shadow_end = .{grass_fade_end, grass_far_shade_start, grass_shadow_fade_end, 0.0};

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
        gpu_set_pipeline(cmd_buff, ground_shadow_shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, current_ground_shadow_params.gpu, ground_index_count, 1);
        gpu_set_pipeline(cmd_buff, shadow_shader.pipeline);
        if render_grass && current_grass_shadow_params.cpu != null && grass_shadow_instance_count > 0 {
            gpu_set_pipeline(cmd_buff, grass_shadow_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, current_grass_shadow_params.gpu, 6, grass_shadow_instance_count);
            gpu_set_pipeline(cmd_buff, shadow_shader.pipeline);
        }
        for batch: scene_batches {
            if it_index < shadow_skip_batch.count && shadow_skip_batch[it_index] continue;
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := current_scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }
        draw_shadow(*horde_runtime, cmd_buff, shadow_shader.pipeline);
    }

    if scene_pick.render_this_frame && scene_pick.view != 0 {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            depth_target = .{
                view = texture_ring_current_view(*scene_depth),
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
        gpu_set_pipeline(cmd_buff, pick_shader.pipeline);
        for batch: scene_batches {
            if it_index >= batch_pick_object_ids.count || batch_pick_object_ids[it_index] == 0 continue;
            mesh := scene_geo.meshes[batch.mesh_index];
            params_gpu := current_scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        }
    }

    if current_debug_pick_params.cpu != null {
        current_debug_pick_params.cpu.* = .{
            view_proj = Matrix4_Identity,
            material_index = cast(u32) ground_sampler - 1,
            object_id = ifx scene_pick.view != 0 then gpu_texture_view_index(scene_pick.view) else 0,
        };
    }

    {
        main_pass_desc := Gpu_Render_Pass_Desc.{
            depth_target = .{
                view = texture_ring_current_view(*scene_depth),
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{
                    depth = 1.0,
                    stencil = 0,
                },
            },
            color_targets = .[
                .{
                    view = linear_present_current_color_view(*scene_present),
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.0, 0.0, 0.0, 1.0],
                },
            ],
        };
        gpu_begin_scoped_render_pass(cmd_buff, main_pass_desc, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, sky_shader.pipeline);
        if current_sky_draw_params.cpu != null {
            gpu_draw_instanced_direct(cmd_buff, current_sky_draw_params.gpu, 6, 1);
        }
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, pipeline(*ground_shader, graphics_shader_constants));
        gpu_draw_instanced_direct(cmd_buff, current_ground_draw_params.gpu, ground_index_count, 1);
        if render_grass && current_grass_draw_params.cpu != null && grass_instance_count > 0 {
            gpu_set_pipeline(cmd_buff, grass_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, current_grass_draw_params.gpu, 6, grass_instance_count);
        }
        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            total_task_slots := batch.max_meshlet_count;
            if total_task_slots == 0 continue;
            draw_first_instance := batch.first_instance;
            draw_instance_total := batch.instance_count;
            meshlet_chunk_count := max(cast(u32) 1, (total_task_slots + TASK_EMIT_MESHLET_COUNT - 1) / TASK_EMIT_MESHLET_COUNT);
            max_object_groups_per_draw := max(cast(u32) 1, mesh_grid_limit / TASK_EMIT_MESHLET_COUNT);
            total_object_groups := draw_instance_total * meshlet_chunk_count;

            animated_batch_index := find_animated_batch_index_for_batch(cast(s32) it_index);
            meshlet_flags := Model_Scene_Meshlet_Flags.HAS_LODS;
            if scene_shadows_enabled meshlet_flags |= .HAS_SHADOWS;
            if mesh.morph_target_count > 0 meshlet_flags |= .HAS_MORPHS;
            if animated_batch_index >= 0 meshlet_flags |= .HAS_SKINNING;
            mesh_constants := Model_Scene_Meshlet_Constants.{
                flags = meshlet_flags,
                debug_mode = mesh_shader_constants.debug_mode,
            };

            gpu_set_pipeline(cmd_buff, SHR.pipeline(*mesh_shader, main_pass_desc, mesh_constants));
            object_group_start: u32;
            while object_group_start < total_object_groups {
                draw_object_group_count := min(max_object_groups_per_draw, total_object_groups - object_group_start);
                draw_instance_start := object_group_start / meshlet_chunk_count;
                draw_group_end := object_group_start + draw_object_group_count;
                draw_instance_end := min(draw_instance_total, (draw_group_end + meshlet_chunk_count - 1) / meshlet_chunk_count);
                draw_instance_count := draw_instance_end - draw_instance_start;
                if draw_instance_count > 0 {
                    draw_params := sgpu_frame_param_alloc(*scene_meshlet_params);
                    batch_params := current_scene_draw_params.cpu[it_index];
                    material := scene_geo.materials.cpu[mesh.material_index];
                    draw_meshlet_instances := ifx scene_batch_uses_dynamic_instances[it_index] then current_dynamic_meshlet_instances.gpu else scene_static_meshlet_instances.gpu;
                    meshlet_draw_bindings := Gpu_Ptr.[
                        scene_meshes_gpu.gpu,
                        scene_geo.meshlet_meshes.gpu,
                        scene_geo.vertices.gpu,
                        scene_geo.meshlets.gpu,
                        scene_geo.meshlet_vertices.gpu,
                        scene_geo.meshlet_triangles.gpu,
                        scene_geo.meshlet_bounds.gpu,
                        draw_meshlet_instances,
                        batch_params.morph_weights,
                        batch_params.skin_matrices,
                        scene_geo.morph_vertex_deltas.gpu,
                    ];
                    draw_params.cpu.* = .{
                        camera_vp = view_proj,
                        frustum_planes = extract_frustum_planes(view_proj),
                        eye_position = scene_camera.position,
                        lod_projection_scale = cast(float) win_h / max(2.0 * max(tan(scene_camera.fov_y * 0.5), 0.0001), 0.0001),
                        lod_radius_threshold = lod_screen_radius,
                        lod_metric_power = lod_distance_power,
                        batch_mesh_index = batch.mesh_index,
                        light_dir = batch_params.light_dir,
                        sun_params = batch_params.sun_params,
                        camera_pos = batch_params.camera_pos,
                        shadow_view_proj = shadow_map.view_proj,
                        shadow_meta = shadow_binding,
                        base_color_factor = material.base_color_factor,
                        sampler_index = material.sampler_index,
                        base_color_texture_index = material.base_color_texture_index,
                        opacity_texture_index = material.opacity_texture_index,
                        normal_texture_index = material.normal_texture_index,
                        roughness_texture_index = material.roughness_texture_index,
                        ao_texture_index = material.ao_texture_index,
                        alpha_mode = material.alpha_mode,
                        alpha_cutoff = material.alpha_cutoff,
                        batch_first_instance = draw_first_instance + draw_instance_start,
                        batch_instance_count = draw_instance_count,
                        batch_max_meshlet_count = batch.max_meshlet_count,
                        batch_meshlet_chunk_count = meshlet_chunk_count,
                        batch_object_group_start = object_group_start - draw_instance_start * meshlet_chunk_count,
                        mesh_base_vertex = mesh.base_vertex,
                        skin_matrix_count = batch_params.skin_matrix_count,
                        morph_target_count = batch_params.morph_target_count,
                        morph_vertex_count = batch_params.morph_vertex_count,
                    };
                    draw_result := gpu_draw_meshlets(cmd_buff, draw_params.gpu, meshlet_draw_bindings, .[draw_object_group_count, 1, 1]);
                    assert(draw_result == .SUCCESS, "gpu_draw_meshlets failed: %", draw_result);
                }
                object_group_start += draw_object_group_count;
            }
        }
        graphics_pipeline := SHR.pipeline(*graphics_shader, graphics_shader_constants);
        gpu_set_pipeline(cmd_buff, graphics_pipeline);
        draw_main(*horde_runtime, cmd_buff, graphics_pipeline);

        should_draw_gizmos := physics_gizmos_enabled || control_mode == .Editor || horde_runtime.projectile_active_count > 0 || horde_runtime.spider_active_count > 0 || horde_runtime.powerup_active_count > 0 || horde_runtime.pillar_active_count > 0;
        if should_draw_gizmos {
            Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .TEST);
            Gizmo_Render.gizmo_render_draw(*gizmo_overlay_render_ctx, cmd_buff, *gizmo_overlay_ctx, viewport, depth_mode = .NONE);
        }

        if show_shadow_debug {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_shadow_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, current_scene_draw_params.gpu, 6, 1);
        }
        if show_pick_debug && current_debug_pick_params.cpu != null {
            gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
            gpu_set_pipeline(cmd_buff, debug_pick_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, current_debug_pick_params.gpu, 6, 1);
        }
    }

    linear_present_present(cmd_buff, *scene_present, swapchain_image);

    if horde_runtime.player_health <= 0.0 {
        using ImGui;
        draw := GetForegroundDrawList();
        viewport := GetMainViewport();
        PushPopFont(fonts.main, fonts.LARGE_SIZE * 2.0);
        msg := "YOU DIED";
        size := CalcTextSize(msg);
        pos := Vector2.{
            viewport.WorkPos.x + (viewport.WorkSize.x - size.x) * 0.5,
            viewport.WorkPos.y + max(56.0, (viewport.WorkSize.y - size.y) * 0.32),
        };
        ImDrawList.AddText(draw, pos + .{3.0, 3.0}, GetColorU32({0.0, 0.0, 0.0, 0.82}), msg);
        ImDrawList.AddText(draw, pos, GetColorU32({1.0, 0.15, 0.1, 0.98}), msg);
    }

    submit_and_present_with_ui(cmd_buff);
    scene_pick.render_this_frame = false;
    if scene_reload_pending {
        Scene_File.deinit(*compiled_scene);
        compiled_scene = Scene_File.recompile_scene_document(scene_doc);
        rebuild_scene_runtime();
        scene_manip_objects_dirty = true;
        scene_manip_apply_pending = false;
        scene_dirty = false;
        scene_reload_pending = false;
        scene_rebuild_pending = false;
    } else if scene_rebuild_pending {
        rebuild_scene_runtime();
        scene_manip_objects_dirty = true;
        scene_manip_apply_pending = false;
        scene_rebuild_pending = false;
    }
    if horde_reset_pending {
        reset_player_and_horde_game();
        horde_reset_pending = false;
    }
} @on_tick

scene_rebuild_manip_objects :: () {
    array_reset_keeping_memory(*scene_manip_objects);
    array_reset_keeping_memory(*scene_manip_node_indices);

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
    if scene_depth.views[0] != 0 && scene_depth_w == width && scene_depth_h == height {
        return; // no change needed.
    }
    ok := ensure_texture_ring(*scene_depth, .{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(ok, "Failed to create model_scene depth texture ring.");
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
    append_unique_model_path(*model_paths, "models/sample.glb");
    append_unique_model_path(*model_paths, "models/mediapipe-canonical-face.glb");
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
    running_lizard_idle_clip_index = -1;
    running_lizard_walk_clip_index = -1;
    running_lizard_jump_clip_index = -1;
    running_lizard_idle_player_index = -1;
    running_lizard_walk_player_index = -1;
    running_lizard_jump_player_index = -1;
    running_lizard_locomotion_node_index = -1;
    running_lizard_output_node_index = -1;
    running_lizard_move_alpha = 0.0;
    running_lizard_airborne_alpha = 0.0;
    running_lizard_scale = 1.0;
    running_lizard_ground_y = 0.0;
    mediapipe_body_model_index = -1;
    mediapipe_face_model_index = -1;
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
        using active_ground;
        size_x = max(size_x, 120.0);
        size_z = max(size_z, 120.0);
        render_grid_x = max(render_grid_x, 160);
        render_grid_z = max(render_grid_z, 160);
        physics_grid_x = max(physics_grid_x, 128);
        physics_grid_z = max(physics_grid_z, 128);
        init_ground_plane(active_ground);
    }
    while shadow_skip_batch.count < scene_batches.count array_add(*shadow_skip_batch, false);
    while batch_pick_object_ids.count < scene_batches.count array_add(*batch_pick_object_ids, 0);
    while batch_compiled_node_indices.count < scene_batches.count array_add(*batch_compiled_node_indices, -1);
    append_mediapipe_demo_instances(*instances_cpu, *total_skin_matrix_count);

    instance_uses_dynamic_storage: [..]bool;
    instance_uses_dynamic_storage.allocator = temp;
    array_resize(*instance_uses_dynamic_storage, instances_cpu.count);
    for it: running_lizard_instances           instance_uses_dynamic_storage[it.instance_index] = true;
    for it: running_lizard_attachment_instances instance_uses_dynamic_storage[it.instance_index] = true;
    for it: mediapipe_demo_instances           instance_uses_dynamic_storage[it.instance_index] = true;
    for it: mediapipe_face_instances           instance_uses_dynamic_storage[it.instance_index] = true;

    array_resize(*scene_batch_uses_dynamic_instances, scene_batches.count);
    static_instance_count: s64;
    dynamic_instance_count: s64;
    remapped_instance_indices: [..]u32;
    remapped_instance_indices.allocator = temp;
    array_resize(*remapped_instance_indices, instances_cpu.count);
    original_batch_first_instances: [..]u32;
    original_batch_first_instances.allocator = temp;
    array_resize(*original_batch_first_instances, scene_batches.count);

    for *scene_batches {
        batch_dynamic := false;
        old_first_instance := cast(s64) it.first_instance;
        original_batch_first_instances[it_index] = it.first_instance;
        for instance_offset: 0..it.instance_count-1 {
            old_index := old_first_instance + instance_offset;
            if old_index >= instance_uses_dynamic_storage.count continue;
            if instance_uses_dynamic_storage[old_index] {
                batch_dynamic = true;
                break;
            }
        }
        scene_batch_uses_dynamic_instances[it_index] = batch_dynamic;

        new_first_instance := ifx batch_dynamic then dynamic_instance_count else static_instance_count;
        it.first_instance = cast(u32) new_first_instance;
        for instance_offset: 0..it.instance_count-1 {
            old_index := old_first_instance + instance_offset;
            if old_index >= remapped_instance_indices.count continue;
            remapped_instance_indices[old_index] = cast(u32) (new_first_instance + instance_offset);
        }
        if batch_dynamic {
            dynamic_instance_count += it.instance_count;
        } else {
            static_instance_count += it.instance_count;
        }
    }

    static_instances_cpu: [..]Scene_Instance;
    static_instances_cpu.allocator = temp;
    array_resize(*static_instances_cpu, static_instance_count);
    dynamic_instances_cpu: [..]Scene_Instance;
    dynamic_instances_cpu.allocator = temp;
    array_resize(*dynamic_instances_cpu, dynamic_instance_count);
    for batch: scene_batches {
        old_first_instance := cast(s64) original_batch_first_instances[it_index];
        old_count := cast(s64) batch.instance_count;
        dst := ifx scene_batch_uses_dynamic_instances[it_index] then dynamic_instances_cpu else static_instances_cpu;
        for instance_offset: 0..old_count-1 {
            dst[batch.first_instance + cast(u32) instance_offset] = instances_cpu[old_first_instance + instance_offset];
        }
    }

    for *running_lizard_instances            it.instance_index = remapped_instance_indices[it.instance_index];
    for *running_lizard_attachment_instances it.instance_index = remapped_instance_indices[it.instance_index];
    for *mediapipe_demo_instances            it.instance_index = remapped_instance_indices[it.instance_index];
    for *mediapipe_face_instances            it.instance_index = remapped_instance_indices[it.instance_index];

    arena_bytes :=
        max(cast(s64) 1, static_instance_count) * size_of(Scene_Instance) +
        max(cast(s64) 1, dynamic_instance_count) * size_of(Scene_Instance) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, static_instance_count) * size_of(Model_Scene_Meshlet_Instance) +
        max(cast(s64) 1, dynamic_instance_count) * size_of(Model_Scene_Meshlet_Instance) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, static_instance_count) * (10 * size_of(Vector4)) +
        max(cast(s64) 1, dynamic_instance_count) * (10 * size_of(Vector4)) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, scene_batches.count) * size_of(Scene_Draw_Params_CPU) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, scene_batches.count * 16) * size_of(Model_Scene_Meshlet_Params_CPU) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, scene_geo.meshes.count) * size_of(Scene_Mesh) +
        max(cast(s64) 1, total_skin_matrix_count * 4) * size_of(Vector4) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, scene_geo.morph_targets.count) * size_of(float) * SGPU_FRAMES_IN_FLIGHT +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "model scene arena");
    assert(gpu_arena.cpu != null, "Model scene arena creation failed.");

    if static_instance_count > 0 {
        scene_static_instances = gpu_alloc_view(*gpu_arena, Scene_Instance, static_instance_count);
        memcpy(scene_static_instances.cpu.data, static_instances_cpu.data, static_instance_count * size_of(Scene_Instance));
        scene_static_meshlet_instances = gpu_alloc_view(*gpu_arena, Model_Scene_Meshlet_Instance, static_instance_count);
        write_meshlet_instances(static_instances_cpu, scene_static_meshlet_instances.cpu);
        scene_static_instance_world_rows = gpu_alloc_view(*gpu_arena, Vector4, static_instance_count * 4);
        scene_static_instance_tints = gpu_alloc_view(*gpu_arena, Vector4, static_instance_count);
        scene_static_instance_shadow_view_proj_rows = gpu_alloc_view(*gpu_arena, Vector4, static_instance_count * 4);
        scene_static_instance_shadow_metas = gpu_alloc_view(*gpu_arena, Vector4, static_instance_count);
        write_instance_meshlet_views(static_instances_cpu, scene_static_instance_world_rows.cpu, scene_static_instance_tints.cpu, scene_static_instance_shadow_view_proj_rows.cpu, scene_static_instance_shadow_metas.cpu);
    }
    if dynamic_instance_count > 0 {
        scene_dynamic_instances = sgpu_make_frame_view(*gpu_arena, Scene_Instance, dynamic_instance_count);
        scene_dynamic_meshlet_instances = sgpu_make_frame_view(*gpu_arena, Model_Scene_Meshlet_Instance, dynamic_instance_count);
        scene_dynamic_instance_world_rows = sgpu_make_frame_view(*gpu_arena, Vector4, dynamic_instance_count * 4);
        scene_dynamic_instance_tints = sgpu_make_frame_view(*gpu_arena, Vector4, dynamic_instance_count);
        scene_dynamic_instance_shadow_view_proj_rows = sgpu_make_frame_view(*gpu_arena, Vector4, dynamic_instance_count * 4);
        scene_dynamic_instance_shadow_metas = sgpu_make_frame_view(*gpu_arena, Vector4, dynamic_instance_count);
        for frame_i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
            frame_instances := sgpu_frame_view_slot(*scene_dynamic_instances, frame_i);
            memcpy(frame_instances.cpu.data, dynamic_instances_cpu.data, dynamic_instance_count * size_of(Scene_Instance));
            write_meshlet_instances(dynamic_instances_cpu, sgpu_frame_view_slot(*scene_dynamic_meshlet_instances, frame_i).cpu);
            write_instance_meshlet_views(dynamic_instances_cpu, sgpu_frame_view_slot(*scene_dynamic_instance_world_rows, frame_i).cpu, sgpu_frame_view_slot(*scene_dynamic_instance_tints, frame_i).cpu, sgpu_frame_view_slot(*scene_dynamic_instance_shadow_view_proj_rows, frame_i).cpu, sgpu_frame_view_slot(*scene_dynamic_instance_shadow_metas, frame_i).cpu);
        }
    }
    scene_meshlet_params = sgpu_make_frame_param_allocator(*gpu_arena, Model_Scene_Meshlet_Params_CPU, max(cast(s64) scene_batches.count * 16, 1));
    scene_meshes_gpu = gpu_alloc_view(*gpu_arena, Scene_Mesh, max(cast(s64) scene_geo.meshes.count, 1));
    if scene_geo.meshes.count > 0 memcpy(scene_meshes_gpu.cpu.data, scene_geo.meshes.data, scene_geo.meshes.count * size_of(Scene_Mesh));

    if total_skin_matrix_count > 0 scene_skin_matrices = sgpu_make_frame_view(*gpu_arena, Vector4, total_skin_matrix_count * 4);
    if scene_geo.morph_targets.count > 0 {
        scene_morph_weights = sgpu_make_frame_view(*gpu_arena, float, scene_geo.morph_targets.count);
        for frame_i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
            frame_morph_weights := sgpu_frame_view_slot(*scene_morph_weights, frame_i);
            for scene_geo.morph_targets {
                frame_morph_weights.cpu[it_index] = it.default_weight;
            }
        }
    }

    scene_draw_params = sgpu_make_frame_view(*gpu_arena, Scene_Draw_Params_CPU, max(cast(s64) scene_batches.count, 1));
    if scene_draw_params_template.data != null {
        free(scene_draw_params_template.data);
        scene_draw_params_template = .{};
    }
    scene_draw_params_template = .{
        count = scene_batches.count,
        data = cast(*Scene_Draw_Params_CPU) alloc(max(cast(s64) 1, scene_batches.count) * size_of(Scene_Draw_Params_CPU)),
    };
    for frame_i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
        frame_draw_params := sgpu_frame_view_slot(*scene_draw_params, frame_i);
        for batch: scene_batches {
            mesh := scene_geo.meshes[batch.mesh_index];
            frame_draw_params.cpu[it_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = ifx scene_batch_uses_dynamic_instances[it_index]
                then sgpu_frame_view_slot(*scene_dynamic_instances, frame_i).gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr)
                else scene_static_instances.gpu + (batch.first_instance * size_of(Scene_Instance)).(Gpu_Ptr),
            view_proj = Matrix4_Identity,
            light_dir = normalize({0.35, -1.0, 0.25}),
            sun_params = .{outdoor_rig.sun_strength, outdoor_rig.time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            material_index = mesh.material_index,
            object_id = batch_pick_object_ids[it_index],
            mesh_base_vertex = mesh.base_vertex,
            morph_target_count = mesh.morph_target_count,
            morph_vertex_count = mesh.vertex_count,
            };
            if mesh.morph_target_count > 0 {
                first_target := scene_geo.morph_targets[mesh.morph_target_start];
                frame_draw_params.cpu[it_index].morph_vertex_deltas = scene_geo.morph_vertex_deltas.gpu + (first_target.vertex_delta_start * size_of(Scene_Morph_Vertex_Delta)).(Gpu_Ptr);
                frame_draw_params.cpu[it_index].morph_weights = sgpu_frame_view_slot(*scene_morph_weights, frame_i).gpu + (mesh.morph_target_start * size_of(float)).(Gpu_Ptr);
            }
            if frame_i == 0 {
                scene_draw_params_template[it_index] = frame_draw_params.cpu[it_index];
            }
        }
    }
    for animated_batches {
        batch_index := cast(s64) it.batch_index;
        for frame_i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
            frame_draw_params := sgpu_frame_view_slot(*scene_draw_params, frame_i);
            frame_draw_params.cpu[batch_index].skin_matrices = sgpu_frame_view_slot(*scene_skin_matrices, frame_i).gpu + (it.skin_matrix_start * 4 * size_of(Vector4)).(Gpu_Ptr);
            frame_draw_params.cpu[batch_index].skin_matrix_count = it.skin_matrix_count;
        }
    }
    for *scene_batches {
        it.max_meshlet_count = mesh_max_meshlet_count(it.mesh_index);
    }

    reset(*horde_runtime, .{
        scene_geo = *scene_geo,
        shadow_map = *shadow_map,
        player_controller = *running_lizard_controller,
        ground = *active_ground,
        mask_import_basis = ifx compiled_scene_find_asset_index_by_name_for_runtime("mask") >= 0
            then compiled_asset_import_matrix(compiled_scene.assets[compiled_scene_find_asset_index_by_name_for_runtime("mask")])
            else Matrix4_Identity,
    }, scene_camera.position, outdoor_rig.sun_strength, outdoor_rig.time_of_day);
    gpu_commit_residency();
}

clear_scene_runtime_resources :: () {
    controller_deinit(*running_lizard_controller);
    deinit(*running_lizard_anim_tree);
    deinit(*mediapipe_body_anim);

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

    gpu_delete(*scene_depth);
    gpu_delete(*scene_present.color);
    scene_depth_w = 0;
    scene_depth_h = 0;
    scene_present.color_w = 0;
    scene_present.color_h = 0;
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
    grass_shadow_instance_count = 0;
    ground_index_count = 0;

    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
    gpu_arena = .{};
    if scene_draw_params_template.data != null {
        free(scene_draw_params_template.data);
    scene_draw_params_template = .{};
    }
    scene_static_instances = .{};
    scene_dynamic_instances = .{};
    scene_static_meshlet_instances = .{};
    scene_dynamic_meshlet_instances = .{};
    scene_static_instance_world_rows = .{};
    scene_dynamic_instance_world_rows = .{};
    scene_static_instance_tints = .{};
    scene_dynamic_instance_tints = .{};
    scene_static_instance_shadow_view_proj_rows = .{};
    scene_dynamic_instance_shadow_view_proj_rows = .{};
    scene_static_instance_shadow_metas = .{};
    scene_dynamic_instance_shadow_metas = .{};
    scene_draw_params = .{};
    scene_meshlet_params = .{};
    scene_meshes_gpu = .{};
    scene_skin_matrices = .{};
    scene_morph_weights = .{};
    clear(*horde_runtime);

    array_reset(*running_lizard_instances);
    array_reset(*mediapipe_demo_instances);
    array_reset(*animated_batches);
    array_reset(*scene_batches);
    array_reset(*scene_batch_uses_dynamic_instances);
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
    clip_name := ifx node.clip_name.count > 0 then node.clip_name else "walk";
    running_lizard_walk_clip_index = player_model_clip_index(model_index, .["walk", "Walk", clip_name, "Run", "run"]);
    running_lizard_idle_clip_index = player_model_clip_index(model_index, .["idle", "Idle", "static", "Static"]);
    running_lizard_jump_clip_index = player_model_clip_index(model_index, .["jump", "Jump"]);
    clip_index := running_lizard_idle_clip_index;
    if clip_index < 0 clip_index = running_lizard_walk_clip_index;
    if clip_index < 0 clip_index = running_lizard_jump_clip_index;
    if clip_index < 0 clip_index = cast(s32) scene_geo.models[model_index].anim_clip_start;
    if running_lizard_idle_clip_index < 0 running_lizard_idle_clip_index = clip_index;
    if running_lizard_walk_clip_index < 0 running_lizard_walk_clip_index = running_lizard_idle_clip_index;
    if running_lizard_jump_clip_index < 0 running_lizard_jump_clip_index = running_lizard_walk_clip_index;

    init(*running_lizard_anim_tree, *scene_geo, model_index);
    running_lizard_idle_player_index, idle_node_index := scene_anim_blend_tree_add_clip_node(*running_lizard_anim_tree, *scene_geo, running_lizard_idle_clip_index, rate = 0.8);
    running_lizard_walk_player_index, walk_node_index := scene_anim_blend_tree_add_clip_node(*running_lizard_anim_tree, *scene_geo, running_lizard_walk_clip_index, rate = 1.0);
    running_lizard_jump_player_index, jump_node_index := scene_anim_blend_tree_add_clip_node(*running_lizard_anim_tree, *scene_geo, running_lizard_jump_clip_index, rate = 1.5);
    running_lizard_locomotion_node_index = scene_anim_blend_tree_add_lerp_node(*running_lizard_anim_tree, *scene_geo, idle_node_index, walk_node_index, 0.0);
    running_lizard_output_node_index = scene_anim_blend_tree_add_lerp_node(*running_lizard_anim_tree, *scene_geo, running_lizard_locomotion_node_index, jump_node_index, 0.0);
    scene_anim_blend_tree_set_output(*running_lizard_anim_tree, running_lizard_output_node_index);
    running_lizard_move_alpha = 0.0;
    running_lizard_airborne_alpha = 0.0;
    scene_anim_blend_tree_sample(*running_lizard_anim_tree, *scene_geo);

    start_pos, start_rot_deg, start_scale := decompose_matrix_trs(node.world * compiled_asset_import_matrix(compiled_scene.assets[node.asset_index]));
    running_lizard_scale = max(max(start_scale.x, start_scale.y), start_scale.z);
    running_lizard_bounds := scene_geo_model_bounds(*scene_geo, model_index);
    running_lizard_ground_y = -running_lizard_bounds.min.y * running_lizard_scale - 0.2;
    running_lizard_spawn_position = .{start_pos.x, running_lizard_ground_y, start_pos.z};
    running_lizard_spawn_visual_yaw_offset = start_rot_deg.y * PI / 180.0;

    character_controller_init_in_system(
        *running_lizard_controller,
        Physics.physics.system,
        running_lizard_spawn_position,
        visual_yaw_offset = running_lizard_spawn_visual_yaw_offset);

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

reset_player_and_horde_game :: () {
    controller_deinit(*running_lizard_controller);
    character_controller_init_in_system(
        *running_lizard_controller,
        Physics.physics.system,
        running_lizard_spawn_position,
        visual_yaw_offset = running_lizard_spawn_visual_yaw_offset);
    running_lizard_root = character_controller_root_matrix(*running_lizard_controller, running_lizard_scale);
    idle_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_idle_player_index);
    if idle_player idle_player.time = 0.0;
    walk_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_walk_player_index);
    if walk_player walk_player.time = 0.0;
    jump_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_jump_player_index);
    if jump_player jump_player.time = 0.0;
    running_lizard_move_alpha = 0.0;
    running_lizard_airborne_alpha = 0.0;
    locomotion_node := scene_anim_blend_tree_node(*running_lizard_anim_tree, running_lizard_locomotion_node_index);
    if locomotion_node locomotion_node.alpha = running_lizard_move_alpha;
    output_node := scene_anim_blend_tree_node(*running_lizard_anim_tree, running_lizard_output_node_index);
    if output_node output_node.alpha = running_lizard_airborne_alpha;
    scene_anim_blend_tree_sample(*running_lizard_anim_tree, *scene_geo);
    reset(*horde_runtime, .{
        scene_geo = *scene_geo,
        shadow_map = *shadow_map,
        player_controller = *running_lizard_controller,
        ground = *active_ground,
        mask_import_basis = ifx compiled_scene_find_asset_index_by_name_for_runtime("mask") >= 0
            then compiled_asset_import_matrix(compiled_scene.assets[compiled_scene_find_asset_index_by_name_for_runtime("mask")])
            else Matrix4_Identity,
    }, scene_camera.position, outdoor_rig.sun_strength, outdoor_rig.time_of_day);
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

update_mediapipe_demo_pose :: (t: float, dynamic_instances: []Scene_Instance) {
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
        dynamic_instances[it.instance_index].world = instance_world;
    }
    for mediapipe_face_instances {
        node_local_index := it.node_index - cast(s32) body_model.node_start;
        instance_world := mediapipe_face_root;
        if node_local_index >= 0 && node_local_index < mediapipe_body_anim.worlds.count {
            instance_world = mediapipe_face_root * mediapipe_body_anim.worlds[node_local_index];
        }
        dynamic_instances[it.instance_index].world = instance_world;
    }
}

write_mediapipe_demo_morph_weights :: (t: float, morph_weights: []float) {
    if mediapipe_body_model_index >= 0 {
        for mesh_index: scene_geo.models[mediapipe_body_model_index].mesh_start .. scene_geo.models[mediapipe_body_model_index].mesh_start + scene_geo.models[mediapipe_body_model_index].mesh_count - 1 {
            mesh := scene_geo.meshes[mesh_index];
            if mesh.morph_target_count == 0 continue;
            dst := morph_weights;
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
        if it_index < scene_batch_uses_dynamic_instances.count && scene_batch_uses_dynamic_instances[it_index] continue;
        if it_index >= batch_compiled_node_indices.count continue;
        compiled_index := batch_compiled_node_indices[it_index];
        if compiled_index < 0 || compiled_index >= compiled_scene.nodes.count continue;
        compiled_node := compiled_scene.nodes[compiled_index];
        instance_world := compiled_node.world;
        if compiled_node.asset_index >= 0 {
            instance_world = instance_world * compiled_asset_import_matrix(compiled_scene.assets[compiled_node.asset_index]);
        }
        for instance_i: 0..batch.instance_count-1 {
            scene_static_instances.cpu[batch.first_instance + instance_i].world = instance_world;
        }
    }
    write_meshlet_instances(scene_static_instances.cpu, scene_static_meshlet_instances.cpu);
    write_instance_meshlet_views(scene_static_instances.cpu, scene_static_instance_world_rows.cpu, scene_static_instance_tints.cpu, scene_static_instance_shadow_view_proj_rows.cpu, scene_static_instance_shadow_metas.cpu);
}

write_meshlet_instances :: (src: []Scene_Instance, dst: []Model_Scene_Meshlet_Instance) {
    count := min(src.count, dst.count);
    for 0..count-1 {
        dst[it] = .{
            world = src[it].world,
            tint = src[it].tint,
        };
    }
}

write_instance_meshlet_views :: (
    src: []Scene_Instance,
    world_rows: []Vector4,
    tints: []Vector4,
    shadow_view_proj_rows: []Vector4,
    shadow_metas: []Vector4,
) {
    count := min(src.count, min(world_rows.count / 4, min(tints.count, min(shadow_view_proj_rows.count / 4, shadow_metas.count))));
    for 0..count-1 {
        world_row_start := it * 4;
        world_rows[world_row_start + 0] = src[it].world.v[0];
        world_rows[world_row_start + 1] = src[it].world.v[1];
        world_rows[world_row_start + 2] = src[it].world.v[2];
        world_rows[world_row_start + 3] = src[it].world.v[3];
        tints[it] = src[it].tint;
        shadow_view_proj_rows[world_row_start + 0] = src[it].shadow_view_proj.v[0];
        shadow_view_proj_rows[world_row_start + 1] = src[it].shadow_view_proj.v[1];
        shadow_view_proj_rows[world_row_start + 2] = src[it].shadow_view_proj.v[2];
        shadow_view_proj_rows[world_row_start + 3] = src[it].shadow_view_proj.v[3];
        shadow_metas[it] = src[it].shadow_meta;
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

clamp_player_camera_above_ground :: (camera: *Editor_Camera) {
    min_camera_y := ground_height_at(active_ground, camera.position.x, camera.position.z) + PLAYER_CAMERA_GROUND_CLEARANCE;
    if camera.position.y < min_camera_y {
        camera.position.y = min_camera_y;
    }
}

player_model_clip_index :: (model_index: s32, names: []string) -> s32 {
    for names {
        if !it continue;
        clip_index := scene_geo_model_clip_index_by_name(*scene_geo, model_index, it);
        if clip_index >= 0 return clip_index;
    }
    return -1;
}

player_anim_approach :: (current: float, target: float, dt: float, speed: float) -> float {
    t := clamp(dt * speed, 0.0, 1.0);
    return lerp(current, target, t);
}

update_player_animation_state :: (dt: float) {
    grounded := character_controller_is_grounded(*running_lizard_controller);
    locomotion_target := clamp(running_lizard_controller.animation_blend, 0.0, 1.0);
    airborne_target := ifx grounded then 0.0 else 1.0;

    running_lizard_move_alpha = player_anim_approach(running_lizard_move_alpha, locomotion_target, dt, speed = 18.0);
    running_lizard_airborne_alpha = player_anim_approach(running_lizard_airborne_alpha, airborne_target, dt, speed = 22.0);

    idle_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_idle_player_index);
    if idle_player idle_player.rate = 0.8;
    walk_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_walk_player_index);
    if walk_player walk_player.rate = max(0.35, running_lizard_controller.animation_blend) * 1.6;
    jump_player := scene_anim_blend_tree_player(*running_lizard_anim_tree, running_lizard_jump_player_index);
    if jump_player jump_player.rate = 1.5;
    locomotion_node := scene_anim_blend_tree_node(*running_lizard_anim_tree, running_lizard_locomotion_node_index);
    if locomotion_node locomotion_node.alpha = running_lizard_move_alpha;
    output_node := scene_anim_blend_tree_node(*running_lizard_anim_tree, running_lizard_output_node_index);
    if output_node output_node.alpha = running_lizard_airborne_alpha;
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


ground_plane_desc: Scene_File.Scene_Procedural_Ground_Desc;

init_ground_plane :: (ground: Scene_File.Scene_Procedural_Ground_Desc) {
    ground_plane_desc = ground;
    ground_texture, ground_texture_view = load_texture_rgba8_srgb(ground.base_color_path);
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

    ground_vertices = gpu_alloc_view(Scene_Vertex, ground_vertices_cpu.count, label = "ground vertices");
    ground_indices = gpu_alloc_view(u32, ground_indices_cpu.count, label = "ground indices");
    ground_instance = gpu_make_buffer_ring(Scene_Instance, label = "ground instance");
    ground_shadow_params = gpu_make_buffer_ring(Ground_Draw_Params_CPU, label = "ground shadow params");
    ground_draw_params   = gpu_make_buffer_ring(Ground_Draw_Params_CPU, label = "ground params");
    grass_shadow_params  = gpu_make_buffer_ring(Grass_Shadow_Params_CPU, label = "grass shadow params");
    grass_draw_params    = gpu_make_buffer_ring(Grass_Draw_Params, label = "grass params");

    memcpy(ground_vertices.cpu.data, ground_vertices_cpu.data, ground_vertices_cpu.count * size_of(Scene_Vertex));
    memcpy(ground_indices.cpu.data, ground_indices_cpu.data, ground_indices_cpu.count * size_of(u32));

    for frame_i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
        ground_instance_slot := gpu_buffer_ring_slot(*ground_instance, frame_i);
        ground_shadow_slot := gpu_buffer_ring_slot(*ground_shadow_params, frame_i);
        ground_draw_slot := gpu_buffer_ring_slot(*ground_draw_params, frame_i);
        grass_shadow_slot := gpu_buffer_ring_slot(*grass_shadow_params, frame_i);
        grass_draw_slot := gpu_buffer_ring_slot(*grass_draw_params, frame_i);

        ground_instance_slot.cpu.* = .{
            world = Matrix4_Identity,
            tint = .{1.0, 1.0, 1.0, 1.0},
            shadow_view_proj = Matrix4_Identity,
        };
        ground_shadow_slot.cpu.* = .{
            vertices = ground_vertices.gpu,
            indices = ground_indices.gpu,
            instances = ground_instance_slot.gpu,
            view_proj = Matrix4_Identity,
            light_dir = normalize(.{0.35, -1.0, 0.25}),
            sun_params = .{outdoor_rig.sun_strength, outdoor_rig.time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            sampler_index = 0,
            base_color_texture_index = 0,
            normal_texture_index = 0,
            roughness_texture_index = 0,
            ao_texture_index = 0,
        };
        ground_draw_slot.cpu.* = .{
            vertices = ground_vertices.gpu,
            indices = ground_indices.gpu,
            instances = ground_instance_slot.gpu,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            sun_params = .{outdoor_rig.sun_strength, outdoor_rig.time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            sampler_index = cast(u32) ground_sampler - 1,
            base_color_texture_index = gpu_texture_view_index(ground_texture_view),
            normal_texture_index = gpu_texture_view_index(ground_normal_texture_view),
            roughness_texture_index = gpu_texture_view_index(ground_roughness_texture_view),
            ao_texture_index = gpu_texture_view_index(ground_ao_texture_view),
        };
    grass_grid_x := max(1, cast(s32) ceil(cast(float) ground.render_grid_x * grass_density_scale));
    grass_grid_z := max(1, cast(s32) ceil(cast(float) ground.render_grid_z * grass_density_scale));
    grass_shadow_grid_x := max(1, cast(s32) ceil(cast(float) ground.render_grid_x * grass_shadow_density_scale));
    grass_shadow_grid_z := max(1, cast(s32) ceil(cast(float) ground.render_grid_z * grass_shadow_density_scale));
    grass_instance_count = cast(u32) grass_grid_x * cast(u32) grass_grid_z;
    grass_shadow_instance_count = cast(u32) grass_shadow_grid_x * cast(u32) grass_shadow_grid_z;
        grass_shadow_slot.cpu.* = .{
            shadow_view_proj = Matrix4_Identity,
            ground_size_center_z_time = .{ground.size_x, ground.size_z, ground.center_z, 0.0},
            ground_shape = .{ground.ridge, ground.swell, ground.warp, 0.0},
            grass_grid_height_width = .{cast(float) grass_shadow_grid_x, cast(float) grass_shadow_grid_z, grass_jitter, grass_blade_height},
            player_pos_radius = .{0.0, 0.0, 0.0, 1.7},
            camera_pos_fade_start = .{0.0, 0.0, 0.0, grass_shadow_fade_start},
            fade_end_far_shade_shadow_end = .{grass_fade_end, grass_far_shade_start, grass_shadow_fade_end, 0.0},
        };
        grass_draw_slot.cpu.* = .{
            view_proj = Matrix4_Identity,
            shadow_view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            sun_params = .{outdoor_rig.sun_strength, outdoor_rig.time_of_day, 0.0, 0.0},
            camera_pos = scene_camera.position,
            shadow_meta = .{0.0, 0.0, 0.0, 0.0},
            ground_size_center_z_time = grass_shadow_slot.cpu.ground_size_center_z_time,
            ground_shape = grass_shadow_slot.cpu.ground_shape,
            grass_grid_height_width = .{cast(float) grass_grid_x, cast(float) grass_grid_z, grass_jitter, grass_blade_height},
            player_pos_radius = grass_shadow_slot.cpu.player_pos_radius,
            camera_pos_fade_start = .{0.0, 0.0, 0.0, grass_fade_start},
            fade_end_far_shade_shadow_end = .{grass_fade_end, grass_far_shade_start, grass_shadow_fade_end, 0.0},
        };
    }
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

toggle_control_mode :: () {
    if #complete control_mode == {
    case .Player; control_mode = .Editor;
    case .Editor; control_mode = .Player;
    }
}

extract_frustum_planes :: (m: Matrix4) -> [6]Vector4 {
    row0 := Vector4.{m._11, m._12, m._13, m._14};
    row1 := Vector4.{m._21, m._22, m._23, m._24};
    row2 := Vector4.{m._31, m._32, m._33, m._34};
    row3 := Vector4.{m._41, m._42, m._43, m._44};

    planes: [6]Vector4;
    planes[0] = row3 + row0;
    planes[1] = row3 - row0;
    planes[2] = row3 + row1;
    planes[3] = row3 - row1;
    planes[4] = row3 + row2;
    planes[5] = row3 - row2;
    for *planes {
        len := length(it.xyz);
        if len > 1.0e-6 it.* /= len;
    }
    return planes;
}

mesh_max_meshlet_count :: (mesh_index: u32) -> u32 {
    result := scene_geo.meshlet_meshes.cpu[mesh_index].meshlet_count;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.lod_mesh_count > 0 {
        for lod_offset: 0..mesh.lod_mesh_count-1 {
            lod_mesh_index := mesh.lod_mesh_start + lod_offset;
            result = max(result, scene_geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count);
        }
    }
    return result;
}

#load "../character_controller.jai";
#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../ui/manip.jai";
#load "../ui/toggle_widget.jai";
#load "../shadowmap.jai";
#load "../scene_geo.jai";
#load "../scene_anim.jai";
#load "../horde_runtime.jai";
#load "../scene_pick.jai";
#load "../outdoor_rig.jai";
#load "shaders/model_scene_shader.jai";
#load "shaders/model_scene_meshlet_shader.jai";

Scene_File :: #import,file "../scene_file.jai";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
Physics :: #import "Physics";
using JPH :: #import "JoltC";
ai :: #import "assimp";
String :: #import "String";
Persist :: #import,file "../ui/persist_controls.jai";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Jai-Shader-Transpiler";
#import "Random";
#import "Math";
