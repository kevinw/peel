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
    target_alive: s32 = 30;
    spawn_rate: float = 12.0;
    spawn_radius_min: float = 13.0;
    spawn_radius_max: float = 28.0;
    despawn_radius: float = 88.0;
    move_speed: float = 80.2;
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
    burst_spacing: float = 0.11;
}

Powerup_Params :: struct {
    enabled: bool = true;
    spawn_rate: float = 0.09;
    pickup_radius: float = 0.48;
    world_margin: float = 5.0;
}

Pillar_Params :: struct {
    enabled: bool = true;
    count: s32 = 5;
    interact_radius: float = 1.8;
    fill_duration: float = 7.0;
    world_margin: float = 8.0;
    base_radius: float = 0.7;
    min_height: float = 5.2;
    max_height: float = 8.2;
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

Powerup_Runtime :: struct {
    active: bool;
    _pad0: [3]u8;
    radius: float;
    position: Vector3;
}

Pillar_Runtime :: struct {
    active: bool;
    _pad0: [3]u8;
    radius: float;
    height: float;
    progress_t: float;
    position: Vector3;
}

Horde_Bindings :: struct {
    scene_geo: *Scene_Geo;
    shadow_map: *Shadow_Map;
    player_controller: *Character_Controller;
    ground: *Scene_File.Scene_Procedural_Ground_Desc;
    mask_import_basis: Matrix4 = Matrix4_Identity;
    pillar_import_basis: Matrix4 = Matrix4_Identity;
}

Horde_Runtime :: struct {
    allocator: Allocator;
    bindings: Horde_Bindings;

    gpu_arena: Gpu_Arena;
    meshlet_params: Gpu_Frame_Param_Allocator(Model_Scene_Meshlet_Params_CPU);
    mask_draw_set: Mesh_Draw_Set;
    pillar_draw_set: Mesh_Draw_Set;

    mask_model_index: s32 = -1;
    pillar_model_index: s32 = -1;

    spawn_params: Enemy_Spawn_Params = .{};
    auto_fire_params: Auto_Fire_Params = .{};
    powerup_params: Powerup_Params = .{};
    pillar_params: Pillar_Params = .{};
    player_health: float = 100.0;
    bonus_bullets: s32;
    spawn_accumulator: float;
    shot_accumulator: float;
    powerup_spawn_accumulator: float;
    burst_delay_remaining: float;
    burst_remaining: s32;
    game_time: float;
    death_reset_delay: float = 1.8;
    death_reset_t: float = 1.8;
    restart_requested: bool;

    collider_radius: float = 0.45;
    collider_half_height: float = 0.0;
    collider_kind: Enemy_Collider_Kind = .SPHERE;
    model_scale: float = 1.0;
    model_root_offset_y: float;
    pillar_model_height: float = 1.0;
    pillar_model_root_offset_y: float;
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
    powerup_max_count: s32 = 64;
    alive_count: s32;
    visible_count_debug: s32;
    render_instance_count_debug: s32;
    projectile_active_count: s32;
    powerup_active_count: s32;
    pillar_active_count: s32;
    debug_next_log_time: float;

    direct_draw_debug: bool = true;

    enemies: [..]Enemy_Runtime;
    projectiles: [..]Projectile_Runtime;
    powerups: [..]Powerup_Runtime;
    pillars: [..]Pillar_Runtime;

    render_view_proj: Matrix4 = Matrix4_Identity;
    render_camera_pos: Vector3;
    render_shadow_binding: Vector4;
    render_sun_strength: float;
    render_time_of_day: float;
    render_view_height: float = 1.0;
    render_lod_projection_scale: float = 1.0;
    spawn_camera_pos: Vector3;
}

maybe_log :: (using horde_runtime: *Horde_Runtime) {
#if LOG_HORDE_STATS {
    if cast(float)time < debug_next_log_time return;

    log("ENEMY_HORDE alive=% visible=% render_instances=% groups=% health=% target=% enabled=%",
        alive_count,
        visible_count_debug,
        render_instance_count_debug,
        mask_draw_set.groups.count + pillar_draw_set.groups.count,
        player_health,
        spawn_params.target_alive,
        spawn_params.enabled);
    debug_next_log_time = cast(float) time + 1.0;
}
}


enemy_body_user_data_make :: (enemy_index: s32) -> u64 {
    assert(enemy_index >= 0);
    return cast(u64) (enemy_index + 1);
}

enemy_body_user_data_index :: (user_data: u64) -> s32, bool {
    if user_data == 0 return -1, false;
    return cast(s32) user_data - 1, true;
}

matrix_max_scale :: (m: Matrix4) -> float {
    axis_x := Vector3.{m._11, m._12, m._13};
    axis_y := Vector3.{m._21, m._22, m._23};
    axis_z := Vector3.{m._31, m._32, m._33};
    return max(length(axis_x), max(length(axis_y), length(axis_z)));
}


clear :: (using runtime: *Horde_Runtime) {
    for * enemies {
        using it;
        if !active continue;
        destroy_body(body_id);
        if shape != null && shape != mask_shape && shape != spider_shape {
            destroy(*shape);
        }
    }

    destroy(*mask_shape);
    destroy(*spider_shape);

    if runtime.gpu_arena.cpu != null gpu_free_arena(runtime.gpu_arena);
    clear(*mask_draw_set);
    clear(*pillar_draw_set);
    array_reset(*enemies);
    array_reset(*projectiles);
    array_reset(*powerups);
    array_reset(*pillars);
    runtime.* = {};
}

deinit :: (using runtime: *Horde_Runtime) {
    array_free(enemies);
    array_free(projectiles);
    array_free(powerups);
    array_free(pillars);
    deinit(*mask_draw_set);
    deinit(*pillar_draw_set);
    clear(runtime);
}

reset :: (using runtime: *Horde_Runtime, horde_bindings: Horde_Bindings, camera_pos: Vector3, sun_strength: float, time_of_day: float) {
    preserved_allocator := allocator;
    preserved_max_count := max_count;
    preserved_projectile_max_count := projectile_max_count;
    preserved_powerup_max_count := powerup_max_count;
    preserved_spawn_params := spawn_params;
    preserved_auto_fire_params := auto_fire_params;
    preserved_powerup_params := powerup_params;
    preserved_pillar_params := pillar_params;
    preserved_direct_draw_debug := direct_draw_debug;
    preserved_spider_move_height := spider_move_height;
    preserved_spider_leg_thickness := spider_leg_thickness;
    preserved_spider_joint_radius := spider_joint_radius;
    preserved_spider_step_distance := spider_step_distance;
    preserved_spider_step_height := spider_step_height;
    preserved_spider_step_speed := spider_step_speed;
    preserved_spider_forward_bias := spider_forward_bias;
    preserved_spider_body_radius := spider_body_radius;
    preserved_death_reset_delay := death_reset_delay;
    clear(runtime);
    if preserved_allocator.proc != null allocator = preserved_allocator;
    if allocator.proc == null allocator = context.allocator;
    max_count = cast(s32) max(1, preserved_max_count);
    projectile_max_count = cast(s32) max(1, preserved_projectile_max_count);
    powerup_max_count = cast(s32) max(1, preserved_powerup_max_count);
    spawn_params = preserved_spawn_params;
    auto_fire_params = preserved_auto_fire_params;
    powerup_params = preserved_powerup_params;
    pillar_params = preserved_pillar_params;
    direct_draw_debug = preserved_direct_draw_debug;
    spider_move_height = preserved_spider_move_height;
    spider_leg_thickness = preserved_spider_leg_thickness;
    spider_joint_radius = preserved_spider_joint_radius;
    spider_step_distance = preserved_spider_step_distance;
    spider_step_height = preserved_spider_step_height;
    spider_step_speed = preserved_spider_step_speed;
    spider_forward_bias = preserved_spider_forward_bias;
    spider_body_radius = preserved_spider_body_radius;
    death_reset_delay = max(0.25, preserved_death_reset_delay);
    death_reset_t = death_reset_delay;
    bindings = horde_bindings;
    spawn_camera_pos = camera_pos;

    scene_geo := horde_bindings.scene_geo;
    mask_model_index = scene_geo_model_index_by_name(scene_geo, "mask");
    if mask_model_index < 0 {
        log_error("no model named 'mask' found in scene geo");
        return;
    }

    bounds := scene_geo_model_bounds(scene_geo, mask_model_index);
    size := bounds.max - bounds.min;
    model_scale = scale_model_to_target_extent(scene_geo, mask_model_index, 3.1);
    scaled_size := size * model_scale;
    diameter_xz := max(scaled_size.x, scaled_size.z);
    collider_radius = max(0.24, diameter_xz * 0.32);
    collider_half_height = max(0.0, (scaled_size.y - collider_radius * 2.0) * 0.5);
    collider_kind = ifx collider_half_height > collider_radius * 0.4 then .CAPSULE else .SPHERE;
    model_root_offset_y = -bounds.min.y * model_scale - (collider_radius + collider_half_height) + 0.75;

    if #complete collider_kind == {
    case .SPHERE;  mask_shape = cast(*Shape) SphereShape_Create(collider_radius);
    case .CAPSULE; mask_shape = cast(*Shape) CapsuleShape_Create(collider_half_height, collider_radius);
    }
    assert(mask_shape != null, "Failed to create horde mask collider shape.");

    spider_shape = cast(*Shape) SphereShape_Create(spider_body_radius);
    assert(spider_shape != null, "Failed to create horde spider collider shape.");

    array_resize(*enemies, max_count);
    for *enemies it.* = .{};
    array_resize(*projectiles, projectile_max_count);
    for *projectiles it.* = .{};
    array_resize(*powerups, powerup_max_count);
    for *powerups it.* = .{};
    array_resize(*pillars, max(cast(s64) 0, pillar_params.count));
    for *pillars it.* = .{};

    append_model_meshes(*mask_draw_set, scene_geo, mask_model_index);

    pillar_model_index = scene_geo_model_index_by_name(scene_geo, "ancient_egyptian_column");
    if pillar_model_index < 0 {
        log_error("no model named 'ancient_egyptian_column' found in scene geo");
    } else {
        pillar_bounds := scene_geo_model_bounds(scene_geo, pillar_model_index);
        pillar_import_scale := max(matrix_max_scale(bindings.pillar_import_basis), 0.0001);
        pillar_model_height = max((pillar_bounds.max.y - pillar_bounds.min.y) * pillar_import_scale, 0.001);
        pillar_model_root_offset_y = -pillar_bounds.min.y * pillar_import_scale;
        append_model_meshes(*pillar_draw_set, scene_geo, pillar_model_index);
    }

    if mask_draw_set.render_meshes.count == 0 return;

    #if LOG_HORDE_STATS {
        log("ENEMY_HORDE init model=% render_meshes=% collider=% radius=% half_height=% scale=%",
            scene_geo.models[mask_model_index].name, mask_draw_set.render_meshes.count, collider_kind, collider_radius, collider_half_height, model_scale);
    }

    init_groups(*mask_draw_set);
    init_groups(*pillar_draw_set);
    max_instance_count := cast(s64) max_count * mask_draw_set.render_meshes.count;
    max_pillar_instance_count := cast(s64) pillars.count * pillar_draw_set.render_meshes.count;
    max_meshlet_param_count: s64 = 1;
    for mask_draw_set.render_meshes {
        meshlet_chunk_count := max(cast(s64) 1, (cast(s64) horde_mesh_max_meshlet_count(scene_geo, it.base_mesh_index) + TASK_EMIT_MESHLET_COUNT - 1) / TASK_EMIT_MESHLET_COUNT);
        max_meshlet_param_count += cast(s64) max_count * meshlet_chunk_count;
    }
    for pillar_draw_set.render_meshes {
        meshlet_chunk_count := max(cast(s64) 1, (cast(s64) horde_mesh_max_meshlet_count(scene_geo, it.base_mesh_index) + TASK_EMIT_MESHLET_COUNT - 1) / TASK_EMIT_MESHLET_COUNT);
        max_meshlet_param_count += cast(s64) pillars.count * meshlet_chunk_count;
    }
    arena_bytes :=
        max(cast(s64) 1, max_instance_count) * size_of(Model_Scene_Meshlet_Instance) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, max_pillar_instance_count) * size_of(Model_Scene_Meshlet_Instance) * SGPU_FRAMES_IN_FLIGHT +
        max(cast(s64) 1, max_meshlet_param_count) * size_of(Model_Scene_Meshlet_Params_CPU) * SGPU_FRAMES_IN_FLIGHT +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "horde runtime arena");
    assert(gpu_arena.cpu != null, "Failed to create horde runtime arena.");
    allocate_dynamic_instances(*mask_draw_set, *gpu_arena, max_instance_count);
    allocate_dynamic_instances(*pillar_draw_set, *gpu_arena, max_pillar_instance_count);
    meshlet_params = sgpu_make_frame_param_allocator(*gpu_arena, Model_Scene_Meshlet_Params_CPU, max(cast(s64) 1, max_meshlet_param_count));
    gpu_commit_residency();

    PhysicsSystem_OptimizeBroadPhase(physics.system);

    init_pillars(runtime);
}

do_ui :: (using runtime: *Horde_Runtime) {
    #import "ImGui";
    Persist :: #import,file "ui/persist_controls.jai";


    if !CollapsingHeader("Horde", .None) return;

    ImGui.Checkbox("Enemy Direct Draw", *direct_draw_debug);
    ImGui.Checkbox("Auto Fire", *auto_fire_params.enabled);
    ImGui.Checkbox("Powerups", *powerup_params.enabled);
    ImGui.Checkbox("Pillars", *pillar_params.enabled);
    {
        using spawn_params;
        ImGui.Checkbox("Enemy Horde", *enabled);
        Persist.SliderInt("Enemy Target",       *target_alive, 0, max_count, "%d");
        Persist.SliderFloat("Enemy Spawn Rate", *spawn_rate, 0.0, 600.0, "%.0f/s");
        Persist.SliderFloat("Enemy Speed",      *move_speed, 10.5, 100.0, "%.2f");
        Persist.SliderFloat("Min Head Size",    *min_head_size, 0.4, 1.5, "%.2f");
        Persist.SliderFloat("Max Head Size",    *max_head_size, 0.5, 2.0, "%.2f");
        Persist.SliderFloat("Enemy Touch DPS",  *touch_damage_per_second, 0.0, 40.0, "%.1f");
    }
    Persist.SliderFloat("Shots / Sec", *auto_fire_params.shots_per_second, 0.0, 10.0, "%.1f");
    Persist.SliderFloat("Burst Spacing", *auto_fire_params.burst_spacing, 0.02, 0.4, "%.2f");

    Persist.SliderFloat("Powerup Spawn Rate", *powerup_params.spawn_rate, 0.0, 1.0, "%.2f/s");
    Persist.SliderInt("Pillar Count", *pillar_params.count, 0, 16, "%d");
    Persist.SliderFloat("Pillar Radius", *pillar_params.interact_radius, 0.8, 3.5, "%.2f");
    Persist.SliderFloat("Pillar Fill Time", *pillar_params.fill_duration, 1.0, 15.0, "%.1fs");
    Separator();
    ImGui.Text("Player Health: %.1f", player_health);
    ImGui.Text("Bonus Bullets: %", bonus_bullets);
    ImGui.Text("Enemies Alive: % / %", alive_count, spawn_params.target_alive);
    ImGui.Text("Spiders: %", spider_active_count);
    ImGui.Text("Projectiles: %", projectile_active_count);
    ImGui.Text("Powerups: %", powerup_active_count);
    ImGui.Text("Pillars: %", pillar_active_count);
    ImGui.Text("Survival Time: %.1fs", game_time);
}

update :: (using runtime: *Horde_Runtime, dt: float) {
    restart_requested = false;
    if player_health <= 0.0 {
        death_reset_t -= dt;
        if death_reset_t <= 0.0 {
            restart_requested = true;
        }
        return;
    }
    game_time += dt;
    update_enemies(runtime, dt);
    update_powerups(runtime, dt);
    update_pillars(runtime, dt);
    update_projectiles_pre_physics(runtime, dt);
}

prepare_render :: (using runtime: *Horde_Runtime, view_proj: Matrix4, shadow_binding: Vector4, camera_pos: Vector3, sun_strength: float, time_of_day: float, view_height: float, lod_projection_scale: float = 1.0) {
    render_view_proj = view_proj;
    render_camera_pos = camera_pos;
    render_shadow_binding = shadow_binding;
    render_sun_strength = sun_strength;
    render_time_of_day = time_of_day;
    render_view_height = view_height;
    render_lod_projection_scale = lod_projection_scale;
    visible_count_debug = 0;
    render_instance_count_debug = 0;

    begin_frame(*mask_draw_set);
    begin_frame(*pillar_draw_set);
    current_mask_instances := current_instances(*mask_draw_set);
    current_pillar_instances := current_instances(*pillar_draw_set);
    if current_mask_instances.cpu.data == null return;

    mask_group_instance_counts: [..]u32;
    mask_group_instance_counts.allocator = temp;
    array_resize(*mask_group_instance_counts, mask_draw_set.groups.count);
    for *mask_group_instance_counts it.* = 0;

    pillar_group_instance_counts: [..]u32;
    pillar_group_instance_counts.allocator = temp;
    array_resize(*pillar_group_instance_counts, pillar_draw_set.groups.count);
    for *pillar_group_instance_counts it.* = 0;

    USE_BATCH_PHYSICS_READ :: true;

    #if USE_BATCH_PHYSICS_READ {
        body_ids: [..]BodyID;
        body_ids.allocator = temp;
        array_resize(*body_ids, enemies.count);
        positions: [..]Vector3;
        positions.allocator = temp;
        array_resize(*positions, enemies.count);
        for * enemies body_ids[it_index] = it.body_id;
        lock_interface := PhysicsSystem_GetBodyLockInterface(physics.system);
        body_interface_no_lock := PhysicsSystem_GetBodyInterfaceNoLock(physics.system);
        {
            body_lock_multi_read := BodyLockInterface_LockMultiRead(lock_interface, body_ids.data, cast(u32)body_ids.count);
            defer BodyLockMultiRead_Destroy(body_lock_multi_read);
            for body_id: body_ids {
                body_pos := cast,force(Vector3) BodyInterface_GetPosition(body_interface_no_lock, body_id);
                positions[it_index] = body_pos;
            }
        }
    }


    scene_geo := bindings.scene_geo;
    mask_model := scene_geo.models[mask_model_index];
    visible_enemy_count: s32;
    for *enemies {
        if !it.active continue;
        #if USE_BATCH_PHYSICS_READ {
            body_pos := positions[it_index];
        } else {
            body_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
        }
        distance_to_camera := length(camera_pos - body_pos);
        if distance_to_camera > spawn_params.despawn_radius continue;
        visible_enemy_count += 1;
        if it.kind != .MASK continue;
        for _, render_mesh_index: mask_draw_set.render_meshes {
            group_idx := group_index(*mask_draw_set, render_mesh_index);
            assert(group_idx >= 0, "Missing horde mask group for render mesh %.", render_mesh_index);
            mask_group_instance_counts[group_idx] += 1;
        }
    }
    for pillars {
        if !it.active continue;
        for render_mesh_index: 0..pillar_draw_set.render_meshes.count-1 {
            group_idx := group_index(*pillar_draw_set, render_mesh_index);
            assert(group_idx >= 0, "Missing pillar draw group for render mesh %.", render_mesh_index);
            pillar_group_instance_counts[group_idx] += 1;
        }
    }

    assign_counts(*mask_draw_set, mask_group_instance_counts);
    assign_counts(*pillar_draw_set, pillar_group_instance_counts);

    mask_group_write_offsets: [..]u32;
    mask_group_write_offsets.allocator = temp;
    array_resize(*mask_group_write_offsets, mask_draw_set.groups.count);
    for *mask_group_write_offsets it.* = mask_draw_set.groups[it_index].first_instance;

    pillar_group_write_offsets: [..]u32;
    pillar_group_write_offsets.allocator = temp;
    array_resize(*pillar_group_write_offsets, pillar_draw_set.groups.count);
    for *pillar_group_write_offsets it.* = pillar_draw_set.groups[it_index].first_instance;

    for *enemies {
        if !it.active continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
        distance_to_camera := length(camera_pos - body_pos);
        if distance_to_camera > spawn_params.despawn_radius continue;
        if it.kind != .MASK continue;

        visual_root_pos := body_pos + .{0.0, model_root_offset_y * (it.visual_scale / max(model_scale, 0.001)), 0.0};
        visual_scale: Vector3 = .{it.visual_scale, it.visual_scale, it.visual_scale};
        world_root := make_trs_matrix(visual_root_pos, horde_quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI, 0.0}), visual_scale) * bindings.mask_import_basis;
        for render_mesh, render_mesh_index: mask_draw_set.render_meshes {
            group_idx := group_index(*mask_draw_set, render_mesh_index);
            assert(group_idx >= 0, "Missing horde mask group for render mesh %.", render_mesh_index);
            write_index := mask_group_write_offsets[group_idx];
            mask_group_write_offsets[group_idx] += 1;
            node_local_index := render_mesh.node_index - cast(s32) mask_model.node_start;
            world := world_root;
            if node_local_index >= 0 {
                world = world_root * scene_geo.nodes[render_mesh.node_index].world;
            }
            flash_mix := clamp(it.hit_flash_t * 9.0, 0.0, 1.0);
            tint := lerp(it.tint, Vector4.{3.2, 3.2, 3.2, 1.0}, flash_mix);
            current_mask_instances.cpu[write_index] = .{
                world = world,
                tint = tint,
            };
            render_instance_count_debug += 1;
        }
    }
    for pillars {
        if !it.active continue;
        pillar_scale := it.height / pillar_model_height;
        base_y := it.position.y - it.height * 0.5;
        pillar_pos: Vector3 = .{it.position.x, base_y + pillar_model_root_offset_y * pillar_scale, it.position.z};
        progress_brightness := lerp(0.86, 1.1, it.progress_t);
        pillar_tint := Vector4.{0.48, 0.56, 0.72, 1.0} * progress_brightness;
        world_root := make_trs_matrix(pillar_pos, horde_quat_from_euler_deg(.{0.0, 0.0, 0.0}), .{pillar_scale, pillar_scale, pillar_scale}) * bindings.pillar_import_basis;
        for render_mesh, render_mesh_index: pillar_draw_set.render_meshes {
            group_idx := group_index(*pillar_draw_set, render_mesh_index);
            assert(group_idx >= 0, "Missing pillar draw group for render mesh %.", render_mesh_index);
            write_index := pillar_group_write_offsets[group_idx];
            pillar_group_write_offsets[group_idx] += 1;
            world := world_root * scene_geo.nodes[render_mesh.node_index].world;
            current_pillar_instances.cpu[write_index] = .{
                world = world,
                tint = pillar_tint,
            };
            render_instance_count_debug += 1;
        }
    }
    visible_count_debug = visible_enemy_count;
}

draw_shadow :: (using runtime: *Horde_Runtime, cmd_buff: Gpu_Command_Buffer, pass_desc: Gpu_Render_Pass_Desc) {
    shadow_params := Mesh_Draw_Set_Params.{
        camera_vp = bindings.shadow_map.view_proj,
        frustum_planes = horde_extract_frustum_planes(bindings.shadow_map.view_proj),
        eye_position = render_camera_pos,
        lod_projection_scale = render_lod_projection_scale,
        lod_radius_threshold = lod_screen_radius,
        lod_metric_power = lod_distance_power,
        light_dir = bindings.shadow_map.light_dir,
        sun_params = .{render_sun_strength, render_time_of_day, 0.0, 0.0},
        camera_pos = render_camera_pos,
        shadow_view_proj = bindings.shadow_map.view_proj,
        shadow_meta = .{},
    };
    draw_meshlets(*mask_draw_set, cmd_buff, pass_desc, bindings.scene_geo, shadow_params, shadow_pass = true);
    draw_meshlets(*pillar_draw_set, cmd_buff, pass_desc, bindings.scene_geo, shadow_params, shadow_pass = true);
}

draw_main :: (using runtime: *Horde_Runtime, cmd_buff: Gpu_Command_Buffer, pass_desc: Gpu_Render_Pass_Desc) {
    main_params := Mesh_Draw_Set_Params.{
        camera_vp = render_view_proj,
        frustum_planes = horde_extract_frustum_planes(render_view_proj),
        eye_position = render_camera_pos,
        lod_projection_scale = render_lod_projection_scale,
        lod_radius_threshold = lod_screen_radius,
        lod_metric_power = lod_distance_power,
        light_dir = bindings.shadow_map.light_dir,
        sun_params = .{render_sun_strength, render_time_of_day, 0.0, 0.0},
        camera_pos = render_camera_pos,
        shadow_view_proj = bindings.shadow_map.view_proj,
        shadow_meta = render_shadow_binding,
    };
    draw_meshlets(*mask_draw_set, cmd_buff, pass_desc, bindings.scene_geo, main_params);
    draw_meshlets(*pillar_draw_set, cmd_buff, pass_desc, bindings.scene_geo, main_params);
}

draw_debug :: (using runtime: *Horde_Runtime, gizmo_ctx: *Gizmo.Gizmo_Context) {
    for powerups {
        if !it.active continue;
        pulse := 0.84 + 0.16 * sin(game_time * 4.2 + cast(float) it_index * 0.6);
        color := Vector4.{0.32, 0.92, 1.25, 0.95} * pulse;
        color.w = 0.95;
        Gizmo.draw_sphere(gizmo_ctx, it.position, it.radius, color = color, thickness = 2.0, segments = 16);
    }

    spider_color := Vector4.{0.02, 0.02, 0.025, 0.96};
    spider_leg_color := Vector4.{0.01, 0.01, 0.01, 0.9};
    spider_joint_color := Vector4.{0.06, 0.06, 0.065, 0.85};
    drawn: s32;
    for enemies {
        if !it.active continue;
        pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
        if it.kind != .SPIDER continue;
        body_radius := it.collider_radius;
        body_center := pos;
        Gizmo.draw_sphere(gizmo_ctx, body_center, body_radius, color = spider_color, thickness = 2.5, segments = 18);
        for leg_index: 0..SPIDER_LEG_COUNT-1 {
            leg := it.spider_legs[leg_index];
            hip, knee := spider_leg_joint_positions(runtime, it, cast(s32) leg_index, body_center, leg.planted_pos);
            Gizmo.draw_line(gizmo_ctx, hip, knee, color = spider_leg_color, thickness = spider_leg_thickness);
            Gizmo.draw_line(gizmo_ctx, knee, leg.planted_pos, color = spider_leg_color, thickness = spider_leg_thickness * 0.9);
            Gizmo.draw_sphere(gizmo_ctx, knee, spider_joint_radius * it.collider_scale, color = spider_joint_color, thickness = 1.0, segments = 10);
            Gizmo.draw_sphere(gizmo_ctx, leg.planted_pos, spider_joint_radius * 0.8 * it.collider_scale, color = .{0.03, 0.03, 0.03, 0.75}, thickness = 1.0, segments = 10);
        }
        drawn += 1;
        if drawn >= 96 break;
    }

    for projectiles {
        if !it.active continue;
        Gizmo.draw_sphere(gizmo_ctx, it.position, auto_fire_params.projectile_radius, color = .{0.98, 0.92, 0.38, 0.92}, thickness = 2.0);
        vel_len := length(it.velocity);
        if vel_len > 0.001 {
            tail := it.position - it.velocity / vel_len * 0.3;
            Gizmo.draw_line(gizmo_ctx, tail, it.position, color = .{1.0, 0.78, 0.22, 0.72}, thickness = 2.0);
        }
    }
}

draw_physics_debug :: (using runtime: *Horde_Runtime, gizmo_ctx: *Gizmo.Gizmo_Context) {
    drawn: s32;
    for enemies {
        if !it.active continue;
        pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
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

horde_mesh_max_meshlet_count :: (scene_geo: *Scene_Geo, mesh_index: u32) -> u32 {
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

horde_extract_frustum_planes :: (m: Matrix4) -> [6]Vector4 {
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

kill_enemy :: (using runtime: *Horde_Runtime, enemy_index: s32) {
    if enemy_index < 0 || enemy_index >= enemies.count return;
    enemy := *enemies[enemy_index];
    if !enemy.active return;
    destroy_body(enemy.body_id);
    if enemy.shape != null && enemy.shape != runtime.mask_shape && enemy.shape != runtime.spider_shape Shape_Destroy(enemy.shape);
    if enemy.kind == .SPIDER {
        spider_active_count = max(cast(s32) 0, spider_active_count - 1);
    }
    enemies[enemy_index] = .{};
    alive_count = max(cast(s32) 0, alive_count - 1);
}

find_closest_enemy_to_player :: (runtime: *Horde_Runtime, player_pos: Vector3) -> s32 {
    best_index: s32 = -1;
    best_dist_sq := 1.0e30;
    for runtime.enemies {
        if !it.active continue;
        enemy_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
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
        projectile_velocity := normalize(dir) * runtime.auto_fire_params.projectile_speed;
        it.* = .{
            active = true,
            life_remaining = runtime.auto_fire_params.projectile_life,
            position = origin,
            velocity = projectile_velocity,
        };
        return true;
    }
    return false;
}

deactivate_projectile :: (runtime: *Horde_Runtime, projectile_index: s32) {
    if projectile_index < 0 || projectile_index >= runtime.projectiles.count return;
    runtime.projectiles[projectile_index] = .{};
}

Projectile_Collide_Result :: struct {
    body_ids: [16]BodyID;
    count: s32;
}

horde_projectile_collide_result: Projectile_Collide_Result;

projectile_collide_shape_body_callback :: (_context: *void, result: BodyID) -> float #c_call {
    if horde_projectile_collide_result.count < horde_projectile_collide_result.body_ids.count {
        horde_projectile_collide_result.body_ids[horde_projectile_collide_result.count] = result;
        horde_projectile_collide_result.count += 1;
    }
    return 1.0;
}

projectile_hits_enemy :: (runtime: *Horde_Runtime, projectile_pos: Vector3, projectile_radius: float, enemy_index: s32) -> bool {
    if enemy_index < 0 || enemy_index >= runtime.enemies.count return false;
    enemy := runtime.enemies[enemy_index];
    if !enemy.active return false;

    enemy_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, enemy.body_id);
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

projectile_query_enemy_hit :: (runtime: *Horde_Runtime, projectile_pos: Vector3) -> s32 {
    query := PhysicsSystem_GetBroadPhaseQuery(physics.system);
    if query == null return -1;

    horde_projectile_collide_result = .{};
    query_center := cast,force(Vec3) projectile_pos;

    _ = BroadPhaseQuery_CollideSphere(
        query,
        *query_center,
        runtime.auto_fire_params.projectile_radius + max(runtime.collider_radius, runtime.spider_body_radius) * max(runtime.spawn_params.max_head_size, 1.0),
        projectile_collide_shape_body_callback,
        null,
        null,
        null);

    if horde_projectile_collide_result.count == 0 return -1;
    for body_i: 0..horde_projectile_collide_result.count-1 {
        body_id := horde_projectile_collide_result.body_ids[body_i];
        enemy_index, ok := enemy_body_user_data_index(BodyInterface_GetUserData(physics.body_interface, body_id));
        if !ok continue;
        if projectile_hits_enemy(runtime, projectile_pos, runtime.auto_fire_params.projectile_radius, enemy_index) {
            return enemy_index;
        }
    }
    return -1;
}

spawn_enemy :: (using runtime: *Horde_Runtime, spawn_index: s32) -> bool {
    if mask_shape == null || spider_shape == null || !spawn_params.enabled return false;
    if spawn_index < 0 || spawn_index >= enemies.count return false;
    if enemies[spawn_index].active return false;

    player_pos := character_controller_position(bindings.player_controller);
    spawn_seed := cast(u32) spawn_index * 2654435761 + cast(u32) floor(time * 11.0);
    spawn_angle := bindings.player_controller.facing_yaw + lerp(-1.9, 1.9, horde_hash01(cast(u32) floor(time * 37.0) + cast(u32) spawn_index * 17));
    spawn_radius := lerp(spawn_params.spawn_radius_min, spawn_params.spawn_radius_max, horde_hash01(spawn_seed));
    spawn_pos := player_pos + .{cos(spawn_angle) * spawn_radius, 0.0, sin(spawn_angle) * spawn_radius};
    min_head_size := min(spawn_params.min_head_size, spawn_params.max_head_size);
    max_head_size := max(spawn_params.min_head_size, spawn_params.max_head_size);
    progression_t := clamp(game_time / 180.0, 0.0, 1.0);
    size_growth := lerp(1.0, 1.35, progression_t);
    size_variation := lerp(min_head_size, max_head_size, horde_hash01(spawn_seed ^ 0x9e3779b9)) * size_growth;
    enemy_kind := ifx (spawn_seed & 3) == 0 then Enemy_Kind.SPIDER else .MASK;
    scaled_collider_radius := collider_radius * size_variation;
    scaled_collider_half_height := collider_half_height * size_variation;
    enemy_collider_kind := collider_kind;
    enemy_visual_scale := model_scale * size_variation;
    enemy_body_shape := mask_shape;
    if enemy_kind == .SPIDER {
        scaled_collider_radius = spider_body_radius * size_variation;
        scaled_collider_half_height = 0.0;
        enemy_collider_kind = .SPHERE;
        enemy_visual_scale = size_variation;
        enemy_body_shape = spider_shape;
    }
    spawn_pos.y = horde_ground_height_at(bindings.ground.*, spawn_pos.x, spawn_pos.z) + scaled_collider_radius + scaled_collider_half_height + 0.04;
    spawn_pos_jph := cast,force(RVec3) spawn_pos;

    hue_variation := horde_hash01(spawn_seed ^ 0x85ebca6b);
    brightness_variation := lerp(0.88, 1.18, horde_hash01(spawn_seed ^ 0xc2b2ae35));
    tint := lerp(Vector4.{0.92, 0.76, 0.72, 1.0}, Vector4.{1.58, 0.46, 0.36, 1.0}, hue_variation) * brightness_variation;
    tint.w = 1.0;

    if abs(size_variation - 1.0) > 0.001 {
        scale_vec := Vec3.{size_variation, size_variation, size_variation};
        base_shape := ifx enemy_kind == .SPIDER then spider_shape else mask_shape;
        enemy_body_shape = cast(*Shape) ScaledShape_Create(base_shape, *scale_vec);
        assert(enemy_body_shape != null, "Enemy scaled shape creation failed.");
    }

    body_settings := BodyCreationSettings_Create3(enemy_body_shape, *spawn_pos_jph, null, .Dynamic, Layers.MOVING);
    assert(body_settings != null, "Enemy body settings creation failed.");
    defer BodyCreationSettings_Destroy(body_settings);
    BodyCreationSettings_SetGravityFactor(body_settings, 0.0);
    BodyCreationSettings_SetFriction(body_settings, 0.0);
    BodyCreationSettings_SetLinearDamping(body_settings, 8.0);
    BodyCreationSettings_SetAngularDamping(body_settings, 8.0);
    BodyCreationSettings_SetAllowedDOFs(body_settings,
        cast(AllowedDOFs) (AllowedDOFs.TranslationX | AllowedDOFs.TranslationY | AllowedDOFs.TranslationZ | AllowedDOFs.RotationY));
    BodyCreationSettings_SetMotionQuality(body_settings, .LinearCast);

    body_id := BodyInterface_CreateAndAddBody(physics.body_interface, body_settings, .Activate);
    BodyInterface_SetUserData(physics.body_interface, body_id, enemy_body_user_data_make(spawn_index));

    hp_scale := 1.0 + floor(game_time / 24.0);
    enemies[spawn_index] = .{
        active = true,
        body_id = body_id,
        shape = enemy_body_shape,
        kind = enemy_kind,
        hp = 2.0 + hp_scale,
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
        init_spider_legs(runtime, *enemies[spawn_index]);
        spider_active_count += 1;
    }
    alive_count += 1;
    return true;
}

update_enemies :: (using runtime: *Horde_Runtime, dt: float) {
    if enemies.count == 0 return;

    spawn_params.target_alive = clamp(spawn_params.target_alive, 0, max_count);
    if spawn_params.min_head_size > spawn_params.max_head_size {
        temp := spawn_params.min_head_size;
        spawn_params.min_head_size = spawn_params.max_head_size;
        spawn_params.max_head_size = temp;
    }

    player_pos := character_controller_position(bindings.player_controller);
    active_contacts: s32;
    active_spiders: s32;
    for *enemies {
        if !it.active continue;
        it.hit_flash_t = max(0.0, it.hit_flash_t - dt);

        body_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, it.body_id);
        scaled_collider_radius := it.collider_radius;
        scaled_collider_half_height := it.collider_half_height;
        to_player := player_pos - body_pos;
        planar_to_player := Vector3.{to_player.x, 0.0, to_player.z};
        planar_dist := length(planar_to_player);
        if planar_dist > spawn_params.despawn_radius {
            kill_enemy(runtime, cast(s32) it_index);
            continue;
        }

        if planar_dist > 0.001 {
            move_dir := planar_to_player / planar_dist;
            hover_height := ifx it.kind == .SPIDER then spider_move_height * it.collider_scale else 0.0;
            desired_ground_y := horde_ground_height_at(bindings.ground.*, body_pos.x, body_pos.z) + scaled_collider_radius + scaled_collider_half_height + hover_height + 0.04;
            target_vel := move_dir * spawn_params.move_speed;
            actual_velocity := linear_velocity(it);
            vertical_correction := (desired_ground_y - body_pos.y) * 10.0;
            target_vel.y = vertical_correction;
            speed_factor: float;
            if #complete it.kind == {
            case .SPIDER; speed_factor = 4500.0;
            case .MASK;   speed_factor = 10000.0;
            }

            add_force(it, target_vel * speed_factor * dt);

            desired_yaw := it.yaw;

            planar_velocity := Vector3.{actual_velocity.x, 0.0, actual_velocity.z};
            planar_speed := length(planar_velocity);
            if planar_speed > 0.05 {
                facing_dir := planar_velocity / planar_speed;
                desired_yaw = atan2(facing_dir.x, facing_dir.z);
            } else {
                desired_yaw = atan2(move_dir.x, move_dir.z);
            }

            it.yaw = horde_smooth_yaw_towards(it.yaw, desired_yaw, dt, turn_speed = 10.0);
            rot := horde_quat_from_euler_deg(.{0.0, it.yaw * 180.0 / PI, 0.0});
            set_rotation(it, rot);
        } else {
            set_linear_velocity(it, {0, 0, 0});
        }

        if it.kind == .SPIDER {
            update_spider_legs(runtime, it, dt);
            active_spiders += 1;
        }

        if bindings.player_controller.character != null && CharacterVirtual_HasCollidedWithBody(bindings.player_controller.character, it.body_id) {
            active_contacts += 1;
        }
    }
    spider_active_count = active_spiders;

    if active_contacts > 0 && player_health > 0.0 {
        player_health = max(0.0, player_health - cast(float) active_contacts * spawn_params.touch_damage_per_second * dt);
    }

    if !spawn_params.enabled return;

    spawn_accumulator += spawn_params.spawn_rate * dt;
    desired_spawns := cast(s32) floor(spawn_accumulator);
    spawn_accumulator -= cast(float) desired_spawns;
    if alive_count >= spawn_params.target_alive return;

    spawns_remaining := min(desired_spawns, spawn_params.target_alive - alive_count);
    for *enemies {
        if spawns_remaining <= 0 break;
        if it.active continue;
        if spawn_enemy(runtime, cast(s32) it_index) {
            spawns_remaining -= 1;
        }
    }
}

#scope_file
update_pillars :: (using runtime: *Horde_Runtime, dt: float) {
    pillar_active_count = 0;
    if pillars.count == 0 return;

    fill_duration := max(0.1, pillar_params.fill_duration);
    player_pos := character_controller_position(bindings.player_controller);
    player_charge_pos := player_pos + .{0.0, 0.95, 0.0};
    for *pillars {
        if !it.active continue;
        charge_center := it.position + .{0.0, it.height * 0.5, 0.0};
        interact_distance := pillar_params.interact_radius + it.radius;
        if length(player_charge_pos - charge_center) <= interact_distance {
            it.progress_t = min(1.0, it.progress_t + dt / fill_duration);
            if it.progress_t >= 1.0 {
                it.active = false;
                bonus_bullets += 1;
                continue;
            }
        } else {
            it.progress_t = max(0.0, it.progress_t - dt / (fill_duration * 1.5));
        }
        pillar_active_count += 1;
    }
}

update_powerups :: (using runtime: *Horde_Runtime, dt: float) {
    powerup_active_count = 0;
    player_pos := character_controller_position(bindings.player_controller);
    player_pickup_pos := player_pos + .{0.0, 0.85, 0.0};

    for *powerups {
        if !it.active continue;
        if length(player_pickup_pos - it.position) <= it.radius + powerup_params.pickup_radius {
            it.active = false;
            bonus_bullets += 1;
            continue;
        }
        powerup_active_count += 1;
    }

    if !powerup_params.enabled || powerup_params.spawn_rate <= 0.0 return;

    powerup_spawn_accumulator += powerup_params.spawn_rate * dt;
    powerups_to_spawn := cast(s32) floor(powerup_spawn_accumulator);
    if powerups_to_spawn <= 0 return;
    powerup_spawn_accumulator -= cast(float) powerups_to_spawn;

    ground_half_x := max(4.0, bindings.ground.size_x * 0.5 - powerup_params.world_margin);
    ground_half_z := max(4.0, bindings.ground.size_z * 0.5 - powerup_params.world_margin);
    for *powerups {
        if powerups_to_spawn <= 0 break;
        if it.active continue;
        item_t := cast(float) cast(s32) it_index;
        seed_base := cast(u32) floor((game_time + item_t * 13.0) * 31.0);
        seed := seed_base ^ (cast(u32) it_index * cast(u32) 0x9e3779b9);
        spawn_x := lerp(-ground_half_x, ground_half_x, horde_hash01(seed ^ 0x85ebca6b));
        spawn_z := lerp(-ground_half_z, ground_half_z, horde_hash01(seed ^ 0xc2b2ae35));
        radius := 0.38;
        spawn_y := horde_ground_height_at(bindings.ground.*, spawn_x, spawn_z) + radius + 0.14;
        it.* = .{
            active = true,
            radius = radius,
            position = .{spawn_x, spawn_y, spawn_z},
        };
        powerups_to_spawn -= 1;
        powerup_active_count += 1;
    }
}

init_pillars :: (runtime: *Horde_Runtime) {
    if runtime.pillars.count == 0 return;
    for *runtime.pillars it.* = .{};
    runtime.pillar_active_count = 0;
    if !runtime.pillar_params.enabled return;

    ground_half_x := max(6.0, runtime.bindings.ground.size_x * 0.5 - runtime.pillar_params.world_margin);
    ground_half_z := max(6.0, runtime.bindings.ground.size_z * 0.5 - runtime.pillar_params.world_margin);
    player_pos := character_controller_position(runtime.bindings.player_controller);
    camera_forward := player_pos - runtime.spawn_camera_pos;
    camera_forward.y = 0.0;
    if length(camera_forward) <= 0.001 {
        camera_forward = .{0.0, 0.0, -1.0};
    } else {
        camera_forward = normalize(camera_forward);
    }
    camera_forward_yaw := atan2(camera_forward.z, camera_forward.x);
    placement_radius_min := 12.0;
    placement_radius_max := min(min(ground_half_x, ground_half_z) - 2.0, 28.0);
    placement_radius_max = max(placement_radius_max, placement_radius_min + 0.5);
    desired_count := min(runtime.pillars.count, max(cast(s64) 0, runtime.pillar_params.count));
    placed_count: s32;
    for pillar_index: 0..desired_count-1 {
        placed := false;
        for attempt: 0..31 {
            seed := cast(u32) pillar_index * cast(u32) 0x9e3779b9 + cast(u32) attempt * cast(u32) 0x85ebca6b + 17;
            spawn_angle := camera_forward_yaw + lerp(-1.15, 1.15, horde_hash01(seed ^ 0x243f6a88));
            spawn_radius := lerp(placement_radius_min, placement_radius_max, horde_hash01(seed ^ 0xb7e15162));
            if pillar_index == 0 && attempt == 0 {
                spawn_angle = camera_forward_yaw;
                spawn_radius = min(11.0, placement_radius_max);
            }
            spawn_x := clamp(player_pos.x + cos(spawn_angle) * spawn_radius, -ground_half_x, ground_half_x);
            spawn_z := clamp(player_pos.z + sin(spawn_angle) * spawn_radius, -ground_half_z, ground_half_z);
            position := Vector3.{spawn_x, 0.0, spawn_z};
            to_player := position - player_pos;
            to_player.y = 0.0;
            if length(to_player) < 7.5 continue;

            too_close := false;
            for runtime.pillars {
                if !it.active continue;
                delta := position - it.position;
                delta.y = 0.0;
                if length(delta) < 6.0 {
                    too_close = true;
                    break;
                }
            }
            if too_close continue;

            radius := runtime.pillar_params.base_radius * lerp(0.85, 1.2, horde_hash01(seed ^ 0x52dce729));
            height := lerp(runtime.pillar_params.min_height, runtime.pillar_params.max_height, horde_hash01(seed ^ 0x7f4a7c15));
            if pillar_index == 0 && attempt == 0 {
                radius = runtime.pillar_params.base_radius;
                height = runtime.pillar_params.max_height;
            }
            base_y := horde_ground_height_at(runtime.bindings.ground.*, spawn_x, spawn_z);
            runtime.pillars[pillar_index] = .{
                active = true,
                radius = radius,
                height = height,
                progress_t = 0.0,
                position = .{spawn_x, base_y + height * 0.5, spawn_z},
            };
            placed_count += 1;
            placed = true;
            break;
        }
        if !placed {
            runtime.pillars[pillar_index] = .{};
        }
    }
    runtime.pillar_active_count = placed_count;
}

draw_pillar_debug :: (runtime: *Horde_Runtime, gizmo_ctx: *Gizmo.Gizmo_Context) {
    if runtime.pillar_active_count <= 0 return;
    ring_segments :: 14;
    for runtime.pillars {
        if !it.active continue;
        base_center := it.position - .{0.0, it.height * 0.5, 0.0};
        top_center := it.position + .{0.0, it.height * 0.5, 0.0};
        interact_radius := runtime.pillar_params.interact_radius;
        if interact_radius > 0.0 {
            interact_color := Vector4.{0.18, 0.95, 0.72, 0.26};
            ring_center := base_center + .{0.0, 0.08, 0.0};
            for seg: 0..ring_segments-1 {
                seg_t0 := cast(float) seg / cast(float) ring_segments;
                seg_t1 := cast(float) (seg + 1) / cast(float) ring_segments;
                angle0 := seg_t0 * PI * 2.0;
                angle1 := seg_t1 * PI * 2.0;
                ring0 := Vector3.{cos(angle0) * interact_radius, 0.0, sin(angle0) * interact_radius};
                ring1 := Vector3.{cos(angle1) * interact_radius, 0.0, sin(angle1) * interact_radius};
                Gizmo.draw_line(gizmo_ctx, ring_center + ring0, ring_center + ring1, color = interact_color, thickness = 1.0);
            }
        }

        if it.progress_t > 0.0 {
            orb_center := top_center + .{0.0, 0.35, 0.0};
            orb_radius := lerp(0.16, max(0.24, it.radius * 1.65), it.progress_t);
            orb_color := Vector4.{0.18, 0.98, 0.86, 0.72};
            orb_color *= lerp(0.65, 1.35, it.progress_t);
            orb_color.w = 0.72;
            Gizmo.draw_sphere(gizmo_ctx, orb_center, orb_radius, color = orb_color, thickness = 2.0, segments = 16);
        }
    }
}

update_projectiles_pre_physics :: (using runtime: *Horde_Runtime, dt: float) {
    projectile_active_count = 0;
    for * projectiles {
        if !it.active continue;
        it.life_remaining -= dt;
        if it.life_remaining <= 0.0 {
            deactivate_projectile(runtime, cast(s32) it_index);
            continue;
        }

        next_pos := it.position + it.velocity * dt;
        hit_enemy_index := projectile_query_enemy_hit(runtime, next_pos);
        if hit_enemy_index >= 0 {
            enemy := *enemies[hit_enemy_index];
            enemy.hp -= 1.0;
            enemy.hit_flash_t = 0.16;
            if enemy.hp <= 0.0 {
                kill_enemy(runtime, hit_enemy_index);
            }
            add_impulse(enemy, it.velocity * 100);
            deactivate_projectile(runtime, cast(s32) it_index);
            continue;
        }

        it.position = next_pos;
        projectile_active_count += 1;
    }

    auto_fire_params.burst_spacing = max(0.02, auto_fire_params.burst_spacing);
    if burst_remaining > 0 {
        burst_delay_remaining -= dt;
        while burst_remaining > 0 && burst_delay_remaining <= 0.0 {
            player_pos := character_controller_position(bindings.player_controller);
            origin := player_pos + .{0.0, 0.95, 0.0};
            target_enemy_index := find_closest_enemy_to_player(runtime, player_pos);
            if target_enemy_index >= 0 {
                target_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, enemies[target_enemy_index].body_id);
                target_pos.y += enemies[target_enemy_index].collider_half_height + enemies[target_enemy_index].collider_radius * 0.35;
                _ = spawn_projectile(runtime, origin, target_pos - origin);
            }
            burst_remaining -= 1;
            burst_delay_remaining += auto_fire_params.burst_spacing;
        }
    }

    if !auto_fire_params.enabled || auto_fire_params.shots_per_second <= 0.0 return;
    if alive_count <= 0 return;

    shot_accumulator += auto_fire_params.shots_per_second * dt;
    shots_to_fire := cast(s32) floor(shot_accumulator);
    if shots_to_fire <= 0 return;
    shot_accumulator -= cast(float) shots_to_fire;

    for 0..shots_to_fire-1 {
        burst_remaining += 1 + bonus_bullets;
    }
    if burst_remaining > 0 {
        burst_delay_remaining = min(burst_delay_remaining, 0.0);
    }
}

init_spider_legs :: (runtime: *Horde_Runtime, enemy: *Enemy_Runtime) {
    body_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, enemy.body_id);
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
    body_pos := cast,force(Vector3) BodyInterface_GetPosition(physics.body_interface, enemy.body_id);
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
    query := PhysicsSystem_GetNarrowPhaseQuery(physics.system);
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

Scene_File :: #import,file "scene_file.jai";
Gizmo :: #import "Gizmo";
#import "Physics";
using JPH :: #import "JoltC";
LOG_HORDE_STATS :: false;
