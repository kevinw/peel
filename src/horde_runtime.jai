Scene_File :: #import,file "scene_file.jai";
Gizmo :: #import "Gizmo";
Physics :: #import "Physics";
JPH :: #import "JoltC";
using JPH;
Persist :: #import,file "ui/persist_controls.jai";

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

Enemy_Kind :: enum u8 {
    MASK;
    SPIDER;
}

SPIDER_LEG_COUNT :: 8;
SPIDER_LEG_PAIR_COUNT :: SPIDER_LEG_COUNT / 2;

Enemy_Spawn_Params :: struct {
    enabled: bool = true;
    target_alive: s32 = 10;
    spawn_rate: float = 12.0;
    spawn_radius_min: float = 13.0;
    spawn_radius_max: float = 28.0;
    despawn_radius: float = 88.0;
    move_speed: float = 2.2;
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

Spider_Leg_Runtime :: struct {
    planted_pos: Vector3;
    target_pos: Vector3;
    step_from: Vector3;
    step_t: float;
    planted: bool;
    cooldown_t: float;
}

Enemy_Runtime :: struct {
    active: bool;
    body_id: u32;
    shape: *Shape;
    kind: Enemy_Kind;
    _pad0: [3]u8;
    hp: float;
    hit_flash_t: float;
    yaw: float;
    visual_scale: float;
    collider_scale: float;
    collider_kind: Enemy_Collider_Kind;
    _pad1: [3]u8;
    collider_radius: float;
    collider_half_height: float;
    spider_next_gait_slot: s32;
    tint: Vector4;
    spider_legs: [SPIDER_LEG_COUNT]Spider_Leg_Runtime;
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

Horde_Bindings :: struct {
    scene_geo: *Scene_Geo;
    shadow_map: *Shadow_Map;
    player_controller: *Character_Controller;
    ground: *Scene_File.Scene_Procedural_Ground_Desc;
}

Horde_Runtime :: struct {
    allocator: Allocator;
    bindings: Horde_Bindings;

    gpu_arena: Gpu_Arena;
    instances: Gpu_View(Scene_Instance);
    draw_params: Gpu_View(Scene_Draw_Params_CPU);
    indirect_args: Gpu_View(Indexed_Indirect_Draw_Args);

    mask_model_index: s32 = -1;

    spawn_params: Enemy_Spawn_Params = .{};
    auto_fire_params: Auto_Fire_Params = .{};
    player_health: float = 100.0;
    spawn_accumulator: float;
    shot_accumulator: float;

    collider_radius: float = 0.45;
    collider_half_height: float = 0.0;
    collider_kind: Enemy_Collider_Kind = .SPHERE;
    model_scale: float = 1.0;
    model_root_offset_y: float;
    mask_shape: *Shape;
    spider_shape: *Shape;
    spider_body_radius: float = 0.58;
    spider_move_height: float = 0.55;
    spider_leg_thickness: float = 8.5;
    spider_joint_radius: float = 0.05;
    spider_step_distance: float = 0.95;
    spider_step_height: float = 0.42;
    spider_step_speed: float = 3.2;
    spider_forward_bias: float = 0.34;
    spider_active_count: s32;

    max_count: s32 = 256;
    projectile_max_count: s32 = 256;
    alive_count: s32;
    visible_count_debug: s32;
    render_instance_count_debug: s32;
    projectile_active_count: s32;
    debug_next_log_time: float;

    render_enemy_masks: bool = true;
    direct_draw_debug: bool = true;

    enemies: [..]Enemy_Runtime;
    projectiles: [..]Projectile_Runtime;
    render_meshes: [..]Enemy_Render_Mesh;
    draw_groups: [..]Enemy_Draw_Group;
}

init :: (runtime: *Horde_Runtime, allocator: Allocator) {
    runtime.allocator = allocator;
    runtime.enemies.allocator = allocator;
    runtime.projectiles.allocator = allocator;
    runtime.render_meshes.allocator = allocator;
    runtime.draw_groups.allocator = allocator;
}

clear :: (runtime: *Horde_Runtime) {
    for runtime.enemies {
        if !it.active continue;
        Physics.destroy_body(it.body_id);
        if it.shape != null && it.shape != runtime.mask_shape && it.shape != runtime.spider_shape Shape_Destroy(it.shape);
    }
    if runtime.mask_shape != null {
        Shape_Destroy(runtime.mask_shape);
        runtime.mask_shape = null;
    }
    if runtime.spider_shape != null {
        Shape_Destroy(runtime.spider_shape);
        runtime.spider_shape = null;
    }
    if runtime.gpu_arena.cpu != null gpu_free_arena(runtime.gpu_arena);

    runtime.gpu_arena = .{};
    runtime.instances = .{};
    runtime.draw_params = .{};
    runtime.indirect_args = .{};
    runtime.mask_model_index = -1;
    runtime.player_health = 100.0;
    runtime.spawn_accumulator = 0.0;
    runtime.shot_accumulator = 0.0;
    runtime.collider_radius = 0.45;
    runtime.collider_half_height = 0.0;
    runtime.collider_kind = .SPHERE;
    runtime.model_scale = 1.0;
    runtime.model_root_offset_y = 0.0;
    runtime.spider_active_count = 0;
    runtime.alive_count = 0;
    runtime.visible_count_debug = 0;
    runtime.render_instance_count_debug = 0;
    runtime.projectile_active_count = 0;

    array_reset(*runtime.enemies);
    array_reset(*runtime.projectiles);
    array_reset(*runtime.render_meshes);
    array_reset(*runtime.draw_groups);
}

deinit :: (runtime: *Horde_Runtime) {
    clear(runtime);
    array_free(runtime.enemies);
    array_free(runtime.projectiles);
    array_free(runtime.render_meshes);
    array_free(runtime.draw_groups);
}

reset :: (runtime: *Horde_Runtime, bindings: Horde_Bindings, camera_pos: Vector3, sun_strength: float, time_of_day: float) {
    clear(runtime);
    runtime.bindings = bindings;

    scene_geo := bindings.scene_geo;
    runtime.mask_model_index = scene_geo_model_index_by_name(scene_geo, "mask");
    if runtime.mask_model_index < 0 return;

    bounds := scene_geo_model_bounds(scene_geo, runtime.mask_model_index);
    size := bounds.max - bounds.min;
    runtime.model_scale = scale_model_to_target_extent(scene_geo, runtime.mask_model_index, 3.1);
    scaled_size := size * runtime.model_scale;
    diameter_xz := max(scaled_size.x, scaled_size.z);
    runtime.collider_radius = max(0.24, diameter_xz * 0.32);
    runtime.collider_half_height = max(0.0, (scaled_size.y - runtime.collider_radius * 2.0) * 0.5);
    runtime.collider_kind = ifx runtime.collider_half_height > runtime.collider_radius * 0.4 then .CAPSULE else .SPHERE;
    runtime.model_root_offset_y = -bounds.min.y * runtime.model_scale - (runtime.collider_radius + runtime.collider_half_height) + 0.75;

    if #complete runtime.collider_kind == {
    case .SPHERE;
        runtime.mask_shape = cast(*Shape) SphereShape_Create(runtime.collider_radius);
    case .CAPSULE;
        runtime.mask_shape = cast(*Shape) CapsuleShape_Create(runtime.collider_half_height, runtime.collider_radius);
    }
    assert(runtime.mask_shape != null, "Failed to create horde mask collider shape.");
    runtime.spider_shape = cast(*Shape) SphereShape_Create(runtime.spider_body_radius);
    assert(runtime.spider_shape != null, "Failed to create horde spider collider shape.");

    array_resize(*runtime.enemies, runtime.max_count);
    for *runtime.enemies it.* = .{};
    array_resize(*runtime.projectiles, runtime.projectile_max_count);
    for *runtime.projectiles it.* = .{};

    model := scene_geo.models[runtime.mask_model_index];
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := scene_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            mesh := scene_geo.meshes[mesh_index];
            array_add(*runtime.render_meshes, .{
                node_index = cast(s32) node_index,
                base_mesh_index = mesh_index,
                lod_mesh_start = mesh.lod_mesh_start,
                lod_mesh_count = mesh.lod_mesh_count,
            });
        }
    }
    if runtime.render_meshes.count == 0 return;

    log("ENEMY_HORDE init model=% render_meshes=% collider=% radius=% half_height=% scale=%",
        scene_geo.models[runtime.mask_model_index].name,
        runtime.render_meshes.count,
        runtime.collider_kind,
        runtime.collider_radius,
        runtime.collider_half_height,
        runtime.model_scale);

    for render_mesh: runtime.render_meshes {
        lod_count := 1 + cast(s32) render_mesh.lod_mesh_count;
        for lod_level: 0..lod_count-1 {
            mesh_index := render_mesh.base_mesh_index;
            if lod_level > 0 mesh_index = render_mesh.lod_mesh_start + cast(u32) (lod_level - 1);
            array_add(*runtime.draw_groups, .{
                render_mesh_index = cast(u32) it_index,
                lod_level = cast(u32) lod_level,
                mesh_index = mesh_index,
            });
        }
    }

    max_instance_count := cast(s64) runtime.max_count * runtime.render_meshes.count;
    arena_bytes :=
        max(cast(s64) 1, max_instance_count) * size_of(Scene_Instance) +
        max(cast(s64) 1, runtime.draw_groups.count) * size_of(Scene_Draw_Params_CPU) +
        max(cast(s64) 1, runtime.draw_groups.count) * size_of(Indexed_Indirect_Draw_Args) +
        1024;
    runtime.gpu_arena = gpu_make_arena(arena_bytes, label = "horde runtime arena");
    assert(runtime.gpu_arena.cpu != null, "Failed to create horde runtime arena.");
    runtime.instances = gpu_alloc_view(*runtime.gpu_arena, Scene_Instance, max_instance_count);
    runtime.draw_params = gpu_alloc_view(*runtime.gpu_arena, Scene_Draw_Params_CPU, runtime.draw_groups.count);
    runtime.indirect_args = gpu_alloc_view(*runtime.gpu_arena, Indexed_Indirect_Draw_Args, runtime.draw_groups.count);

    for group, group_index: runtime.draw_groups {
        mesh := scene_geo.meshes[group.mesh_index];
        runtime.draw_params.cpu[group_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = 0,
            morph_vertex_deltas = 0,
            morph_weights = 0,
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            sun_params = .{sun_strength, time_of_day, 0.0, 0.0},
            camera_pos = camera_pos,
            material_index = mesh.material_index,
            object_id = 0,
            mesh_base_vertex = mesh.base_vertex,
            skin_matrix_count = 0,
            morph_target_count = 0,
            morph_vertex_count = 0,
        };
        runtime.indirect_args.cpu[group_index] = .{
            vertex_count = mesh.index_count,
            instance_count = 0,
            vertex_start = 0,
            base_instance = 0,
        };
    }

    PhysicsSystem_OptimizeBroadPhase(Physics.physics.system);
}

do_ui :: (runtime: *Horde_Runtime) {
    using Persist;
    ImGui.Checkbox("Enemy Horde", *runtime.spawn_params.enabled);
    ImGui.Checkbox("Render Enemy Masks", *runtime.render_enemy_masks);
    ImGui.Checkbox("Enemy Direct Draw", *runtime.direct_draw_debug);
    ImGui.Checkbox("Auto Fire", *runtime.auto_fire_params.enabled);
    Persist.SliderInt("Enemy Target", *runtime.spawn_params.target_alive, 0, runtime.max_count, "%d");
    Persist.SliderFloat("Enemy Spawn Rate", *runtime.spawn_params.spawn_rate, 0.0, 600.0, "%.0f/s");
    Persist.SliderFloat("Enemy Speed", *runtime.spawn_params.move_speed, 0.5, 6.0, "%.2f");
    Persist.SliderFloat("Climb Speed Ratio", *runtime.spawn_params.climb_speed_ratio, 0.0, 1.5, "%.2f");
    Persist.SliderFloat("Min Head Size", *runtime.spawn_params.min_head_size, 0.4, 1.5, "%.2f");
    Persist.SliderFloat("Max Head Size", *runtime.spawn_params.max_head_size, 0.5, 2.0, "%.2f");
    Persist.SliderFloat("Enemy Touch DPS", *runtime.spawn_params.touch_damage_per_second, 0.0, 40.0, "%.1f");
    Persist.SliderFloat("Shots / Sec", *runtime.auto_fire_params.shots_per_second, 0.0, 10.0, "%.1f");
    ImGui.Text("Player Health: %.1f", runtime.player_health);
    ImGui.Text("Enemies Alive: % / %", runtime.alive_count, runtime.spawn_params.target_alive);
    ImGui.Text("Spiders: %", runtime.spider_active_count);
    ImGui.Text("Projectiles: %", runtime.projectile_active_count);
}

update :: (runtime: *Horde_Runtime, dt: float) {
    update_enemies(runtime, dt);
    update_projectiles(runtime, dt);
}

prepare_render :: (runtime: *Horde_Runtime, view_proj: Matrix4, shadow_binding: Vector4, camera_pos: Vector3, sun_strength: float, time_of_day: float) {
    if runtime.enemies.count == 0 || runtime.draw_groups.count == 0 || runtime.instances.cpu.data == null return;
    runtime.visible_count_debug = 0;
    runtime.render_instance_count_debug = 0;

    for *runtime.draw_groups {
        it.first_instance = 0;
        it.instance_count = 0;
    }

    group_instance_counts: [..]u32;
    group_instance_counts.allocator = temp;
    array_resize(*group_instance_counts, runtime.draw_groups.count);
    for *group_instance_counts it.* = 0;

    scene_geo := runtime.bindings.scene_geo;
    model := scene_geo.models[runtime.mask_model_index];
    visible_enemy_count: s32;
    for *runtime.enemies {
        if !it.active continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        distance_to_camera := length(camera_pos - body_pos);
        if distance_to_camera > runtime.spawn_params.despawn_radius continue;
        visible_enemy_count += 1;
        if it.kind != .MASK continue;
        for render_mesh, render_mesh_index: runtime.render_meshes {
            lod_level := enemy_lod_level_for_distance(render_mesh, distance_to_camera);
            group_index := draw_group_index(runtime, render_mesh_index, lod_level);
            if group_index >= 0 group_instance_counts[group_index] += 1;
        }
    }

    running_first_instance: u32;
    for *runtime.draw_groups {
        it.first_instance = running_first_instance;
        it.instance_count = group_instance_counts[it_index];
        running_first_instance += it.instance_count;
    }

    group_write_offsets: [..]u32;
    group_write_offsets.allocator = temp;
    array_resize(*group_write_offsets, runtime.draw_groups.count);
    for *group_write_offsets it.* = runtime.draw_groups[it_index].first_instance;

    for *runtime.enemies {
        if !it.active continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        distance_to_camera := length(camera_pos - body_pos);
        if distance_to_camera > runtime.spawn_params.despawn_radius continue;
        if it.kind != .MASK continue;

        visual_root_pos := body_pos + .{0.0, runtime.model_root_offset_y * (it.visual_scale / max(runtime.model_scale, 0.001)), 0.0};
        visual_scale: Vector3 = .{it.visual_scale, it.visual_scale, it.visual_scale};
        world_root := make_trs_matrix(visual_root_pos, horde_quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI + 225.0, 0.0}), visual_scale);
        for render_mesh, render_mesh_index: runtime.render_meshes {
            lod_level := enemy_lod_level_for_distance(render_mesh, distance_to_camera);
            group_index := draw_group_index(runtime, render_mesh_index, lod_level);
            if group_index < 0 continue;
            write_index := group_write_offsets[group_index];
            group_write_offsets[group_index] += 1;
            node_local_index := render_mesh.node_index - cast(s32) model.node_start;
            world := world_root;
            if node_local_index >= 0 {
                world = world_root * scene_geo.nodes[render_mesh.node_index].world;
            }
            flash_mix := clamp(it.hit_flash_t * 9.0, 0.0, 1.0);
            tint := lerp(it.tint, Vector4.{3.2, 3.2, 3.2, 1.0}, flash_mix);
            runtime.instances.cpu[write_index] = .{
                world = world,
                tint = tint,
                shadow_view_proj = runtime.bindings.shadow_map.view_proj,
                shadow_meta = shadow_binding,
            };
            runtime.render_instance_count_debug += 1;
        }
    }
    runtime.visible_count_debug = visible_enemy_count;

    for group, group_index: runtime.draw_groups {
        mesh := scene_geo.meshes[group.mesh_index];
        runtime.draw_params.cpu[group_index].indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr);
        runtime.draw_params.cpu[group_index].instances = runtime.instances.gpu + (group.first_instance * size_of(Scene_Instance)).(Gpu_Ptr);
        runtime.draw_params.cpu[group_index].view_proj = view_proj;
        runtime.draw_params.cpu[group_index].camera_pos = camera_pos;
        runtime.draw_params.cpu[group_index].light_dir = runtime.bindings.shadow_map.light_dir;
        runtime.draw_params.cpu[group_index].sun_params = .{sun_strength, time_of_day, 0.0, 0.0};
        runtime.draw_params.cpu[group_index].material_index = mesh.material_index;
        runtime.draw_params.cpu[group_index].mesh_base_vertex = mesh.base_vertex;
        runtime.indirect_args.cpu[group_index] = .{
            vertex_count = mesh.index_count,
            instance_count = group.instance_count,
            vertex_start = 0,
            base_instance = 0,
        };
    }
}

draw_shadow :: (runtime: *Horde_Runtime, cmd_buff: Gpu_Command_Buffer, pipeline: Gpu_Pipeline) {
    if !runtime.render_enemy_masks || runtime.draw_groups.count == 0 || runtime.draw_params.cpu.data == null || runtime.indirect_args.cpu.data == null return;
    gpu_set_pipeline(cmd_buff, pipeline);
    for group: runtime.draw_groups {
        if group.instance_count == 0 continue;
        params_gpu := runtime.draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
        mesh := runtime.bindings.scene_geo.meshes[group.mesh_index];
        if runtime.direct_draw_debug {
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, group.instance_count);
        } else {
            args_gpu := runtime.indirect_args.gpu + (it_index * size_of(Indexed_Indirect_Draw_Args)).(Gpu_Ptr);
            gpu_draw_instanced_indirect(cmd_buff, params_gpu, params_gpu, args_gpu);
        }
    }
}

draw_main :: (runtime: *Horde_Runtime, cmd_buff: Gpu_Command_Buffer, pipeline: Gpu_Pipeline) {
    if !runtime.render_enemy_masks || runtime.draw_groups.count == 0 || runtime.draw_params.cpu.data == null || runtime.indirect_args.cpu.data == null return;
    gpu_set_pipeline(cmd_buff, pipeline);
    for group: runtime.draw_groups {
        if group.instance_count == 0 continue;
        params_gpu := runtime.draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
        mesh := runtime.bindings.scene_geo.meshes[group.mesh_index];
        if runtime.direct_draw_debug {
            gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, group.instance_count);
        } else {
            args_gpu := runtime.indirect_args.gpu + (it_index * size_of(Indexed_Indirect_Draw_Args)).(Gpu_Ptr);
            gpu_draw_instanced_indirect(cmd_buff, params_gpu, params_gpu, args_gpu);
        }
    }
}

draw_debug :: (runtime: *Horde_Runtime, gizmo_ctx: *Gizmo.Gizmo_Context) {
    spider_color := Vector4.{0.02, 0.02, 0.025, 0.96};
    spider_leg_color := Vector4.{0.01, 0.01, 0.01, 0.9};
    spider_joint_color := Vector4.{0.06, 0.06, 0.065, 0.85};
    drawn: s32;
    for runtime.enemies {
        if !it.active continue;
        pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        if it.kind != .SPIDER continue;
        body_radius := it.collider_radius;
        body_center := pos;
        Gizmo.draw_sphere(gizmo_ctx, body_center, body_radius, color = spider_color, thickness = 2.5, segments = 18);
        for leg_index: 0..SPIDER_LEG_COUNT-1 {
            leg := it.spider_legs[leg_index];
            hip, knee := spider_leg_joint_positions(runtime, it, cast(s32) leg_index, body_center, leg.planted_pos);
            Gizmo.draw_line(gizmo_ctx, hip, knee, color = spider_leg_color, thickness = runtime.spider_leg_thickness);
            Gizmo.draw_line(gizmo_ctx, knee, leg.planted_pos, color = spider_leg_color, thickness = runtime.spider_leg_thickness * 0.9);
            Gizmo.draw_sphere(gizmo_ctx, knee, runtime.spider_joint_radius * it.collider_scale, color = spider_joint_color, thickness = 1.0, segments = 10);
            Gizmo.draw_sphere(gizmo_ctx, leg.planted_pos, runtime.spider_joint_radius * 0.8 * it.collider_scale, color = .{0.03, 0.03, 0.03, 0.75}, thickness = 1.0, segments = 10);
        }
        drawn += 1;
        if drawn >= 96 break;
    }

    for runtime.projectiles {
        if !it.active continue;
        Gizmo.draw_sphere(gizmo_ctx, it.position, runtime.auto_fire_params.projectile_radius, color = .{0.98, 0.92, 0.38, 0.92}, thickness = 2.0);
        vel_len := length(it.velocity);
        if vel_len > 0.001 {
            tail := it.position - it.velocity / vel_len * 0.3;
            Gizmo.draw_line(gizmo_ctx, tail, it.position, color = .{1.0, 0.78, 0.22, 0.72}, thickness = 2.0);
        }
    }
}

draw_physics_debug :: (runtime: *Horde_Runtime, gizmo_ctx: *Gizmo.Gizmo_Context) {
    drawn: s32;
    for runtime.enemies {
        if !it.active continue;
        pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        scaled_collider_radius := it.collider_radius;
        scaled_collider_half_height := it.collider_half_height;
        Gizmo.draw_sphere(gizmo_ctx, pos, scaled_collider_radius, color = .{1.0, 0.18, 0.18, 0.55}, thickness = 1.25);
        if #complete it.collider_kind == {
        case .CAPSULE;
            top := pos + .{0.0, scaled_collider_half_height, 0.0};
            bottom := pos - .{0.0, scaled_collider_half_height, 0.0};
            Gizmo.draw_line(gizmo_ctx, top, bottom, color = .{1.0, 0.3, 0.3, 0.4}, thickness = 1.0);
        case .SPHERE;
            //
        }
        drawn += 1;
        if drawn >= 24 break;
    }
}

scale_model_to_target_extent :: (scene_geo: *Scene_Geo, model_index: s32, target_extent: float) -> float {
    bounds := scene_geo_model_bounds(scene_geo, model_index);
    size := bounds.max - bounds.min;
    max_extent := max(max(size.x, size.y), size.z);
    return ifx max_extent > 0.0 then target_extent / max_extent else 1.0;
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

draw_group_index :: (runtime: *Horde_Runtime, render_mesh_index: s64, lod_level: s32) -> s32 {
    running_index: s32;
    for runtime.render_meshes {
        lod_count := 1 + cast(s32) it.lod_mesh_count;
        if it_index == render_mesh_index {
            if lod_level < 0 || lod_level >= lod_count return -1;
            return running_index + lod_level;
        }
        running_index += lod_count;
    }
    return -1;
}

kill_enemy :: (runtime: *Horde_Runtime, enemy_index: s32) {
    if enemy_index < 0 || enemy_index >= runtime.enemies.count return;
    enemy := *runtime.enemies[enemy_index];
    if !enemy.active return;
    Physics.destroy_body(enemy.body_id);
    if enemy.shape != null && enemy.shape != runtime.mask_shape && enemy.shape != runtime.spider_shape Shape_Destroy(enemy.shape);
    if enemy.kind == .SPIDER {
        runtime.spider_active_count = max(cast(s32) 0, runtime.spider_active_count - 1);
    }
    runtime.enemies[enemy_index] = .{};
    runtime.alive_count = max(cast(s32) 0, runtime.alive_count - 1);
}

find_closest_enemy_to_player :: (runtime: *Horde_Runtime, player_pos: Vector3) -> s32 {
    best_index: s32 = -1;
    best_dist_sq := 1.0e30;
    for runtime.enemies {
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

spawn_projectile :: (runtime: *Horde_Runtime, origin: Vector3, dir: Vector3) -> bool {
    if dot(dir, dir) < 1.0e-8 return false;
    for *runtime.projectiles {
        if it.active continue;
        it.* = .{
            active = true,
            life_remaining = runtime.auto_fire_params.projectile_life,
            position = origin,
            velocity = normalize(dir) * runtime.auto_fire_params.projectile_speed,
        };
        runtime.projectile_active_count += 1;
        return true;
    }
    return false;
}

projectile_hits_enemy :: (runtime: *Horde_Runtime, projectile_pos: Vector3, projectile_radius: float, enemy_index: s32) -> bool {
    if enemy_index < 0 || enemy_index >= runtime.enemies.count return false;
    enemy := runtime.enemies[enemy_index];
    if !enemy.active return false;

    enemy_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, enemy.body_id);
    scaled_collider_radius := enemy.collider_radius;
    scaled_collider_half_height := enemy.collider_half_height;
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

spawn_enemy :: (runtime: *Horde_Runtime, spawn_index: s32) -> bool {
    if runtime.mask_shape == null || runtime.spider_shape == null || !runtime.spawn_params.enabled return false;
    if spawn_index < 0 || spawn_index >= runtime.enemies.count return false;
    if runtime.enemies[spawn_index].active return false;

    player_pos := character_controller_position(runtime.bindings.player_controller);
    spawn_seed := cast(u32) spawn_index * 2654435761 + cast(u32) floor(time * 11.0);
    spawn_angle := runtime.bindings.player_controller.facing_yaw + lerp(-1.9, 1.9, horde_hash01(cast(u32) floor(time * 37.0) + cast(u32) spawn_index * 17));
    spawn_radius := lerp(runtime.spawn_params.spawn_radius_min, runtime.spawn_params.spawn_radius_max, horde_hash01(spawn_seed));
    spawn_pos := player_pos + .{cos(spawn_angle) * spawn_radius, 0.0, sin(spawn_angle) * spawn_radius};
    min_head_size := min(runtime.spawn_params.min_head_size, runtime.spawn_params.max_head_size);
    max_head_size := max(runtime.spawn_params.min_head_size, runtime.spawn_params.max_head_size);
    size_variation := lerp(min_head_size, max_head_size, horde_hash01(spawn_seed ^ 0x9e3779b9));
    enemy_kind := ifx (spawn_seed & 3) == 0 then Enemy_Kind.SPIDER else .MASK;
    scaled_collider_radius := runtime.collider_radius * size_variation;
    scaled_collider_half_height := runtime.collider_half_height * size_variation;
    enemy_collider_kind := runtime.collider_kind;
    enemy_visual_scale := runtime.model_scale * size_variation;
    enemy_body_shape := runtime.mask_shape;
    if enemy_kind == .SPIDER {
        scaled_collider_radius = runtime.spider_body_radius * size_variation;
        scaled_collider_half_height = 0.0;
        enemy_collider_kind = .SPHERE;
        enemy_visual_scale = size_variation;
        enemy_body_shape = runtime.spider_shape;
    }
    spawn_pos.y = horde_ground_height_at(runtime.bindings.ground.*, spawn_pos.x, spawn_pos.z) + scaled_collider_radius + scaled_collider_half_height + 0.04;
    spawn_pos_jph := cast,force(RVec3) spawn_pos;

    hue_variation := horde_hash01(spawn_seed ^ 0x85ebca6b);
    brightness_variation := lerp(0.88, 1.18, horde_hash01(spawn_seed ^ 0xc2b2ae35));
    tint := lerp(Vector4.{0.92, 0.76, 0.72, 1.0}, Vector4.{1.58, 0.46, 0.36, 1.0}, hue_variation) * brightness_variation;
    tint.w = 1.0;

    if abs(size_variation - 1.0) > 0.001 {
        scale_vec := Vec3.{size_variation, size_variation, size_variation};
        base_shape := ifx enemy_kind == .SPIDER then runtime.spider_shape else runtime.mask_shape;
        enemy_body_shape = cast(*Shape) ScaledShape_Create(base_shape, *scale_vec);
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

    runtime.enemies[spawn_index] = .{
        active = true,
        body_id = body_id,
        shape = enemy_body_shape,
        kind = enemy_kind,
        hp = 3.0,
        hit_flash_t = 0.0,
        yaw = spawn_angle + PI,
        visual_scale = enemy_visual_scale,
        collider_scale = size_variation,
        collider_kind = enemy_collider_kind,
        collider_radius = scaled_collider_radius,
        collider_half_height = scaled_collider_half_height,
        spider_next_gait_slot = cast(s32) (spawn_seed & 3),
        tint = tint,
    };
    if enemy_kind == .SPIDER {
        init_spider_legs(runtime, *runtime.enemies[spawn_index]);
        runtime.spider_active_count += 1;
    }
    runtime.alive_count += 1;
    return true;
}

update_enemies :: (runtime: *Horde_Runtime, dt: float) {
    if runtime.enemies.count == 0 return;
    runtime.spawn_params.target_alive = clamp(runtime.spawn_params.target_alive, 0, runtime.max_count);
    runtime.spawn_params.climb_speed_ratio = max(0.0, runtime.spawn_params.climb_speed_ratio);
    if runtime.spawn_params.min_head_size > runtime.spawn_params.max_head_size {
        temp := runtime.spawn_params.min_head_size;
        runtime.spawn_params.min_head_size = runtime.spawn_params.max_head_size;
        runtime.spawn_params.max_head_size = temp;
    }

    player_pos := character_controller_position(runtime.bindings.player_controller);
    active_contacts: s32;
    active_spiders: s32;
    for *runtime.enemies {
        if !it.active continue;
        it.hit_flash_t = max(0.0, it.hit_flash_t - dt);

        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, it.body_id);
        scaled_collider_radius := it.collider_radius;
        scaled_collider_half_height := it.collider_half_height;
        to_player := player_pos - body_pos;
        planar_to_player := Vector3.{to_player.x, 0.0, to_player.z};
        planar_dist := length(planar_to_player);
        if planar_dist > runtime.spawn_params.despawn_radius {
            kill_enemy(runtime, cast(s32) it_index);
            continue;
        }

        if planar_dist > 0.001 {
            move_dir := planar_to_player / planar_dist;
            hover_height := ifx it.kind == .SPIDER then runtime.spider_move_height * it.collider_scale else 0.0;
            desired_ground_y := horde_ground_height_at(runtime.bindings.ground.*, body_pos.x, body_pos.z) + scaled_collider_radius + scaled_collider_half_height + hover_height + 0.04;
            target_vel := move_dir * runtime.spawn_params.move_speed;
            actual_velocity: Vec3;
            BodyInterface_GetLinearVelocity(Physics.physics.body_interface, it.body_id, *actual_velocity);
            planar_velocity := Vector3.{actual_velocity.x, 0.0, actual_velocity.z};
            planar_speed := length(planar_velocity);
            vertical_correction := (desired_ground_y - body_pos.y) * 10.0;
            climb_speed := runtime.spawn_params.move_speed * runtime.spawn_params.climb_speed_ratio;
            is_blocked := planar_speed < runtime.spawn_params.move_speed * 0.55 && planar_dist > scaled_collider_radius * 1.5;
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
            it.yaw = horde_smooth_yaw_towards(it.yaw, desired_yaw, dt, turn_speed = 12.0);
            rot := horde_quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI, 0.0});
            rot_jph := cast,force(Quat) rot;
            body_pos_jph := cast,force(RVec3) body_pos;
            BodyInterface_SetPositionAndRotationWhenChanged(Physics.physics.body_interface, it.body_id, *body_pos_jph, *rot_jph, .Activate);
        } else {
            zero_vel := Vec3.{0.0, 0.0, 0.0};
            BodyInterface_SetLinearVelocity(Physics.physics.body_interface, it.body_id, *zero_vel);
        }

        if it.kind == .SPIDER {
            update_spider_legs(runtime, it, dt);
            active_spiders += 1;
        }

        if runtime.bindings.player_controller.character != null && CharacterVirtual_HasCollidedWithBody(runtime.bindings.player_controller.character, it.body_id) {
            active_contacts += 1;
        }
    }
    runtime.spider_active_count = active_spiders;

    if active_contacts > 0 && runtime.player_health > 0.0 {
        runtime.player_health = max(0.0, runtime.player_health - cast(float) active_contacts * runtime.spawn_params.touch_damage_per_second * dt);
    }

    if !runtime.spawn_params.enabled return;

    runtime.spawn_accumulator += runtime.spawn_params.spawn_rate * dt;
    desired_spawns := cast(s32) floor(runtime.spawn_accumulator);
    runtime.spawn_accumulator -= cast(float) desired_spawns;
    if runtime.alive_count >= runtime.spawn_params.target_alive return;

    spawns_remaining := min(desired_spawns, runtime.spawn_params.target_alive - runtime.alive_count);
    for *runtime.enemies {
        if spawns_remaining <= 0 break;
        if it.active continue;
        if spawn_enemy(runtime, cast(s32) it_index) {
            spawns_remaining -= 1;
        }
    }
}

update_projectiles :: (runtime: *Horde_Runtime, dt: float) {
    runtime.projectile_active_count = 0;
    for *runtime.projectiles {
        if !it.active continue;
        it.life_remaining -= dt;
        if it.life_remaining <= 0.0 {
            it.* = .{};
            continue;
        }

        next_pos := it.position + it.velocity * dt;
        hit_enemy_index: s32 = -1;
        for runtime.enemies {
            if !it.active continue;
            if projectile_hits_enemy(runtime, next_pos, runtime.auto_fire_params.projectile_radius, cast(s32) it_index) {
                hit_enemy_index = cast(s32) it_index;
                break;
            }
        }

        if hit_enemy_index >= 0 {
            enemy := *runtime.enemies[hit_enemy_index];
            enemy.hp -= 1.0;
            enemy.hit_flash_t = 0.16;
            if enemy.hp <= 0.0 {
                kill_enemy(runtime, hit_enemy_index);
            }
            it.* = .{};
            continue;
        }

        it.position = next_pos;
        runtime.projectile_active_count += 1;
    }

    if !runtime.auto_fire_params.enabled || runtime.auto_fire_params.shots_per_second <= 0.0 return;
    if runtime.alive_count <= 0 return;

    runtime.shot_accumulator += runtime.auto_fire_params.shots_per_second * dt;
    shots_to_fire := cast(s32) floor(runtime.shot_accumulator);
    if shots_to_fire <= 0 return;
    runtime.shot_accumulator -= cast(float) shots_to_fire;

    player_pos := character_controller_position(runtime.bindings.player_controller);
    origin := player_pos + .{0.0, 0.95, 0.0};
    for 0..shots_to_fire-1 {
        target_enemy_index := find_closest_enemy_to_player(runtime, player_pos);
        if target_enemy_index < 0 break;
        target_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, runtime.enemies[target_enemy_index].body_id);
        target_pos.y += runtime.enemies[target_enemy_index].collider_half_height + runtime.enemies[target_enemy_index].collider_radius * 0.35;
        spawn_projectile(runtime, origin, target_pos - origin);
    }
}

init_spider_legs :: (runtime: *Horde_Runtime, enemy: *Enemy_Runtime) {
    body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, enemy.body_id);
    body_center := body_pos;
    for leg_index: 0..SPIDER_LEG_COUNT-1 {
        desired_anchor := spider_desired_foot_anchor(runtime, enemy.*, cast(s32) leg_index, body_center);
        hit, planted_pos := spider_raycast_foot(runtime, desired_anchor + .{0.0, 2.4 * enemy.collider_scale, 0.0}, enemy);
        if !hit {
            planted_pos = desired_anchor;
            planted_pos.y = horde_ground_height_at(runtime.bindings.ground.*, planted_pos.x, planted_pos.z);
        }
        enemy.spider_legs[leg_index] = .{
            planted_pos = planted_pos,
            target_pos = planted_pos,
            step_from = planted_pos,
            step_t = 1.0,
            planted = true,
        };
    }
}

update_spider_legs :: (runtime: *Horde_Runtime, enemy: *Enemy_Runtime, dt: float) {
    body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, enemy.body_id);
    body_center := body_pos;
    desired_plants: [SPIDER_LEG_COUNT]Vector3;
    needs_steps: [SPIDER_LEG_COUNT]bool;
    any_leg_stepping: bool;
    for leg_index: 0..SPIDER_LEG_COUNT-1 {
        leg := *enemy.spider_legs[leg_index];
        leg.cooldown_t = max(0.0, leg.cooldown_t - dt);
        desired_anchor := spider_desired_foot_anchor(runtime, enemy.*, cast(s32) leg_index, body_center);
        hit, desired_plant := spider_raycast_foot(runtime, desired_anchor + .{0.0, 2.8 * enemy.collider_scale, 0.0}, enemy);
        if !hit {
            desired_plant = desired_anchor;
            desired_plant.y = horde_ground_height_at(runtime.bindings.ground.*, desired_plant.x, desired_plant.z);
        }

        anchor_to_foot := desired_anchor - leg.planted_pos;
        anchor_to_foot.y = 0.0;
        anchor_dist := length(anchor_to_foot);
        hip, _ := spider_leg_joint_positions(runtime, enemy.*, cast(s32) leg_index, body_center, leg.planted_pos);
        full_leg := leg.planted_pos - hip;
        full_leg_len := length(full_leg);
        max_leg_reach := enemy.collider_scale * 1.9;
        needs_step := anchor_dist > runtime.spider_step_distance * enemy.collider_scale || full_leg_len > max_leg_reach;
        desired_plants[leg_index] = desired_plant;
        needs_steps[leg_index] = needs_step && leg.cooldown_t <= 0.0;
        if leg.step_t < 1.0 {
            any_leg_stepping = true;
            leg.step_t = min(1.0, leg.step_t + dt * runtime.spider_step_speed);
            t := smoothstep(0.0, 1.0, leg.step_t);
            lift := sin(t * PI) * runtime.spider_step_height * enemy.collider_scale;
            leg.planted_pos = lerp(leg.step_from, leg.target_pos, t) + .{0.0, lift, 0.0};
            if leg.step_t >= 1.0 {
                leg.planted_pos = leg.target_pos;
                leg.planted = true;
                leg.cooldown_t = 0.08;
            }
        }
    }

    if any_leg_stepping return;

    for slot_offset: 0..3 {
        gait_slot := (enemy.spider_next_gait_slot + cast(s32) slot_offset) & 3;
        slot_leg_a, slot_leg_b := spider_gait_slot_legs(gait_slot);
        should_step_a := needs_steps[slot_leg_a];
        should_step_b := needs_steps[slot_leg_b];
        if !should_step_a && !should_step_b continue;

        if should_step_a {
            leg_a := *enemy.spider_legs[slot_leg_a];
            leg_a.step_from = leg_a.planted_pos;
            leg_a.target_pos = desired_plants[slot_leg_a];
            leg_a.step_t = 0.0;
            leg_a.planted = false;
        }
        if should_step_b {
            leg_b := *enemy.spider_legs[slot_leg_b];
            leg_b.step_from = leg_b.planted_pos;
            leg_b.target_pos = desired_plants[slot_leg_b];
            leg_b.step_t = 0.0;
            leg_b.planted = false;
        }

        enemy.spider_next_gait_slot = (gait_slot + 1) & 3;
        break;
    }
}

spider_raycast_foot :: (runtime: *Horde_Runtime, origin: Vector3, enemy: *Enemy_Runtime) -> (bool, Vector3) {
    query := PhysicsSystem_GetNarrowPhaseQuery(Physics.physics.system);
    if query == null return false, .{};

    origin_jph := cast,force(RVec3) origin;
    direction := Vec3.{0.0, -6.5 * enemy.collider_scale, 0.0};
    hit: RayCastResult;
    hit_ok := NarrowPhaseQuery_CastRay(query, *origin_jph, *direction, *hit, null, null, null);
    if !hit_ok return false, .{};
    if hit.bodyID == enemy.body_id return false, .{};
    hit_p_jph: RVec3;
    RRayCast_GetPointOnRay(*origin_jph, *direction, hit.fraction, *hit_p_jph);
    return true, cast,force(Vector3) hit_p_jph;
}

spider_desired_foot_anchor :: (runtime: *Horde_Runtime, enemy: Enemy_Runtime, leg_index: s32, body_center: Vector3) -> Vector3 {
    side_sign := ifx (leg_index & 1) == 0 then -1.0 else 1.0;
    pair_index := leg_index / 2;
    pair_t := ifx SPIDER_LEG_PAIR_COUNT > 1 then cast(float) pair_index / cast(float) (SPIDER_LEG_PAIR_COUNT - 1) else 0.0;
    forward_offset := lerp(0.92, -0.92, pair_t);
    lateral_offset := 1.12 * side_sign;
    reach := 0.92 * enemy.collider_scale;
    yaw_forward := Vector3.{sin(enemy.yaw), 0.0, cos(enemy.yaw)};
    yaw_right := Vector3.{yaw_forward.z, 0.0, -yaw_forward.x};
    leg_center := body_center + yaw_forward * (runtime.spider_forward_bias * enemy.collider_scale);
    anchor := leg_center + yaw_forward * (forward_offset * reach) + yaw_right * (lateral_offset * reach);
    anchor.y = body_center.y - runtime.spider_move_height * enemy.collider_scale;
    return anchor;
}

spider_leg_joint_positions :: (runtime: *Horde_Runtime, enemy: Enemy_Runtime, leg_index: s32, body_center: Vector3, foot_pos: Vector3) -> (Vector3, Vector3) {
    side_sign := ifx (leg_index & 1) == 0 then -1.0 else 1.0;
    pair_index := leg_index / 2;
    pair_t := ifx SPIDER_LEG_PAIR_COUNT > 1 then cast(float) pair_index / cast(float) (SPIDER_LEG_PAIR_COUNT - 1) else 0.0;
    yaw_forward := Vector3.{sin(enemy.yaw), 0.0, cos(enemy.yaw)};
    yaw_right := Vector3.{yaw_forward.z, 0.0, -yaw_forward.x};
    hip := body_center + yaw_forward * lerp(0.42, -0.42, pair_t) * enemy.collider_scale + yaw_right * side_sign * enemy.collider_radius * 0.82;
    leg_vec := foot_pos - hip;
    leg_len := length(leg_vec);
    leg_dir := ifx leg_len > 1.0e-4 then leg_vec / leg_len else Vector3.{0.0, -1.0, 0.0};
    knee_dir := cross(yaw_forward, leg_dir);
    normalize(*knee_dir, fallback = yaw_right * side_sign);
    if side_sign < 0.0 {
        knee_dir *= -1.0;
    }
    knee := hip + leg_vec * 0.48 + knee_dir * (0.26 * enemy.collider_scale) + .{0.0, 0.22 * enemy.collider_scale, 0.0};
    return hip, knee;
}

spider_gait_slot_legs :: (slot: s32) -> (s64, s64) {
    if slot == {
    case 0; return 6, 1; // hind-left + front-right
    case 1; return 2, 5; // second-left + third-right
    case 2; return 4, 7; // third-left + hind-right
    case 3; return 0, 3; // front-left + second-right
    }
    return 0, 3;
}

horde_ground_height_at :: (ground: Scene_File.Scene_Procedural_Ground_Desc, x: float, z: float) -> float {
    ridge := sin(x * 0.23 + z * 0.09) * ground.ridge;
    swell := cos(z * 0.18 - x * 0.05) * ground.swell;
    warp := sin((x + z) * 0.11) * ground.warp + cos((x - z) * 0.07) * ground.warp;
    flatten := 1.0 - smoothstep(0.0, 6.0, abs(x) * 0.38);
    return ridge + swell + warp - flatten * 0.05;
}

horde_wrap_angle_pi :: (angle: float) -> float {
    wrapped := angle;
    while wrapped > PI  wrapped -= PI * 2.0;
    while wrapped < -PI wrapped += PI * 2.0;
    return wrapped;
}

horde_smooth_yaw_towards :: (current: float, target: float, dt: float, turn_speed: float) -> float {
    max_step := max(0.0, turn_speed) * dt;
    delta := horde_wrap_angle_pi(target - current);
    if abs(delta) <= max_step return current + delta;
    step_sign := ifx delta < 0.0 then -1.0 else 1.0;
    return current + step_sign * max_step;
}

horde_hash01 :: (x: u32) -> float {
    phase := cast(float) x * 12.9898 + 78.233;
    value := sin(phase) * cast(float) 43758.5453;
    return value - floor(value);
}

horde_quat_from_euler_deg :: (deg: Vector3) -> Quaternion {
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
