WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/brickmap_shader.jai";

AABB :: struct {
    min: Vector3;
    max: Vector3;
}

Brickmap_BVH :: struct {
    edit_bounds: [BRICKMAP_MAX_EDITS] AABB;
    edit_count: s32;
}

graphics_pipeline: Gpu_Pipeline;
compute_bake_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

brickmap_params_cpu: *Brickmap_Params;
brickmap_params_gpu: Gpu_Ptr;

brickmap_atlas_cpu: []u8;
brickmap_pointer_grid_cpu: []s32;
brickmap_lod_info_cpu: [BRICKMAP_LOD_COUNT] Brickmap_Lod_Info;
brickmap_edits_storage: [BRICKMAP_MAX_EDITS] SDF_Edit;
brickmap_edits_cpu: []SDF_Edit;
brickmap_dirty_storage: [BRICKMAP_MAX_DIRTY_BRICKS] Brick_Request;
brickmap_dirty_cpu: []Brick_Request;

brickmap_camera: Editor_Camera = .{
    position = .{4.0, 2.0, 7.0},
    yaw = -0.55,
    pitch = -0.12,
    move_speed = 7.0,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0058,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

brickmap_bvh: Brickmap_BVH;
brickmap_dirty_flags: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] bool;
brickmap_next_atlas_index: s32;
brickmap_pending_dirty_count: s32;
brickmap_last_camera_pos: Vector3;
brickmap_force_full_rebuild := true;

brickmap_ui_open := true;
brickmap_draw_debug_grid := false;
brickmap_auto_edit_after: s32 = 90;
brickmap_auto_edit_done := false;
brickmap_log_updates := false;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, brickmap_vertex_main, brickmap_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for brickmap graphics shaders.");
    compute_source := cast([]u8) get_transpiled(.METAL, brickmap_bake_compute);
    assert(compute_source.count > 0, "Transpilation failed for brickmap compute shaders.");

    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, brickmap_vertex_main, brickmap_fragment_main);
    assert(graphics_ok, "Brickmap graphics pipeline creation failed.");

    compute_bake_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_bake_pipeline != 0, "Brickmap bake compute pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_bake_pipeline, compute_source, .METAL, brickmap_bake_compute);
    assert(compute_ok, "Brickmap bake compute pipeline hot-reload registration failed.");

    arena_bytes := 256 * 1024 * 1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "brickmap arena");
    assert(gpu_arena.cpu != null, "Brickmap arena allocation failed.");

    brickmap_params_cpu, brickmap_params_gpu = gpu_arena_alloc(*gpu_arena, Brickmap_Params);

    assert(brickmap_params_cpu != null, "Brickmap params alloc failed.");

    brickmap_params_cpu.* = .{};
    brickmap_atlas_cpu = brickmap_params_cpu.atlas_values;
    brickmap_pointer_grid_cpu = brickmap_params_cpu.pointer_grid;
    brickmap_edits_cpu = brickmap_edits_storage;
    brickmap_dirty_cpu = brickmap_dirty_storage;
    brickmap_params_cpu.distance_range = 4.0;
    brickmap_params_cpu.camera_fov_y = PI / 3.0;
    brickmap_params_cpu.camera_tan_half_fov = tan(brickmap_params_cpu.camera_fov_y * 0.5);

    env_edit_after, env_edit_set := Env_Vars.try_parse_env_int("BRICKMAP_EDIT_AFTER");
    if env_edit_set && env_edit_after >= 0 brickmap_auto_edit_after = cast(s32) env_edit_after;

    env_log_updates, env_log_set := Env_Vars.try_parse_env_int("BRICKMAP_LOG");
    if env_log_set brickmap_log_updates = env_log_updates > 0;

    brickmap_seed_initial_scene();
    brickmap_rebuild_bvh();
    brickmap_update_lod_origins(true);
    brickmap_clear_cache();
    brickmap_mark_all_edits_dirty("init");
    brickmap_force_full_rebuild = false;
    if brickmap_log_updates {
        log("BRICKMAP init_dirty_complete pending=% atlas_used=%", brickmap_pending_dirty_count, brickmap_next_atlas_index);
    }

    brickmap_last_camera_pos = brickmap_camera.position;

    gpu_commit_residency();
} @on_dll_init

brickmap_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{430.0, 260.0}, .FirstUseEver);
    if Begin("Brickmap", *brickmap_ui_open, flags = .NoCollapse) {
        Text("Sparse brickmap SDF raymarch prototype");
        Text("RMB look, WASDQE fly, Shift boost");
        Checkbox("Draw Debug Grid", *brickmap_draw_debug_grid);
        Text("Edits: %", brickmap_params_cpu.edit_count);
        Text("Dirty bricks pending: %", brickmap_pending_dirty_count);
        Text("Atlas bricks used: % / %", brickmap_next_atlas_index, BRICKMAP_MAX_BRICKS);
        Text("Auto edit after frame: %", brickmap_auto_edit_after);
        Text("Auto edit done: %", ifx brickmap_auto_edit_done then "yes" else "no");
        Separator();
        Text("Clip LOD0 origin brick: % % %", brickmap_lod_info_cpu[0].origin_brick_x, brickmap_lod_info_cpu[0].origin_brick_y, brickmap_lod_info_cpu[0].origin_brick_z);
        Text("Clip LOD1 origin brick: % % %", brickmap_lod_info_cpu[1].origin_brick_x, brickmap_lod_info_cpu[1].origin_brick_y, brickmap_lod_info_cpu[1].origin_brick_z);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);

    brickmap_ui();
    io := ImGui.GetIO();
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

    _ = editor_camera_update(*brickmap_camera, dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = right_down && !io.WantCaptureMouse);

    if frame_count == brickmap_auto_edit_after && !brickmap_auto_edit_done {
        brickmap_apply_runtime_edit();
        brickmap_auto_edit_done = true;
    }

    camera_moved := distance(brickmap_camera.position, brickmap_last_camera_pos) > 0.35;
    if camera_moved {
        brickmap_last_camera_pos = brickmap_camera.position;
    }

    brickmap_update_lod_origins(camera_moved);

    if brickmap_force_full_rebuild {
        brickmap_clear_cache();
        brickmap_mark_all_edits_dirty("recenter/full");
        brickmap_force_full_rebuild = false;
    }

    if dims_ok && win_w > 0 && win_h > 0 {
        brickmap_params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    brickmap_params_cpu.time = cast(float) time;
    brickmap_params_cpu.camera_pos = brickmap_camera.position;
    brickmap_params_cpu.camera_fov_y = PI / 3.0;
    brickmap_params_cpu.camera_tan_half_fov = tan(brickmap_params_cpu.camera_fov_y * 0.5);
    editor_camera_basis(*brickmap_camera, *brickmap_params_cpu.camera_forward, *brickmap_params_cpu.camera_right, *brickmap_params_cpu.camera_up);
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := brickmap_lod_info_cpu[lod];
        brickmap_params_cpu.lod_origin_brick_x[lod] = info.origin_brick_x;
        brickmap_params_cpu.lod_origin_brick_y[lod] = info.origin_brick_y;
        brickmap_params_cpu.lod_origin_brick_z[lod] = info.origin_brick_z;
        brickmap_params_cpu.lod_voxel_size[lod] = info.voxel_size;
    }
    edit_count := cast(s32) brickmap_params_cpu.edit_count;
    for i: 0..edit_count-1 {
        e := brickmap_edits_cpu[i];
        brickmap_params_cpu.edit_shape[i] = e.shape;
        brickmap_params_cpu.edit_op[i] = e.op;
        brickmap_params_cpu.edit_pos_radius[i] = .{e.position.x, e.position.y, e.position.z, e.radius};
        brickmap_params_cpu.edit_half_extents_blend[i] = .{e.half_extents.x, e.half_extents.y, e.half_extents.z, e.blend};
        brickmap_params_cpu.edit_rotation[i] = .{e.rotation.x, e.rotation.y, e.rotation.z, e.rotation.w};
    }
    for i: 0..brickmap_pending_dirty_count-1 {
        req := brickmap_dirty_cpu[i];
        brickmap_params_cpu.dirty_lod_brick_xyz[i] = .{cast(float) req.lod, cast(float) req.brick_x, cast(float) req.brick_y, cast(float) req.brick_z};
        brickmap_params_cpu.dirty_atlas_index[i] = req.atlas_index;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if brickmap_pending_dirty_count > 0 {
        brickmap_params_cpu.dirty_count = cast(u32) brickmap_pending_dirty_count;
        bake_threads := brickmap_pending_dirty_count * BRICKMAP_BRICK_VOXELS;

        result = gpu_set_pipeline(cmd_buff, compute_bake_pipeline);
        assert(result == .SUCCESS, tprint("Brickmap bake set pipeline failed: %", result));
        dispatch_x := cast(u32) ((bake_threads + 63) / 64);
        gpu_dispatch_buffers(cmd_buff, .[brickmap_params_gpu], .[dispatch_x, 1, 1]);

        if brickmap_log_updates {
            log("BRICKMAP baked frame=% dirty_bricks=% threads=%", frame_count, brickmap_pending_dirty_count, bake_threads);
        }

        brickmap_pending_dirty_count = 0;
        for i: 0..brickmap_dirty_flags.count-1 brickmap_dirty_flags[i] = false;
    }

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.03, 0.035, 0.05, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced(cmd_buff, 0, brickmap_params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Brickmap draw failed: %", draw_result));

    if brickmap_draw_debug_grid {
        // Optional visual debug in future pass.
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../editor_camera.jai";

Env_Vars :: #import "Env_Vars";
Input :: #import "Input";
ImGui :: #import "ImGui";
#import "Math";

brickmap_seed_initial_scene :: () {
    count: s32 = 0;

    brickmap_add_sphere(*count, .{-2.1, 0.3, -3.8}, 1.1);
    brickmap_add_sphere(*count, .{1.8, -0.1, -4.9}, 1.4);
    brickmap_add_box(*count, .{0.0, 0.2, -6.7}, .{1.1, 0.9, 1.1}, .{0.18, 0.35, 0.05});
    brickmap_add_box(*count, .{-3.8, -0.2, -8.2}, .{0.9, 1.5, 0.9}, .{0.0, 0.42, 0.0});
    brickmap_add_sphere(*count, .{-0.1, 0.6, -6.7}, 0.85, op = SDF_OP_SUBTRACT);
    brickmap_add_box(*count, .{2.8, 0.7, -8.8}, .{1.7, 0.25, 0.7}, .{0.2, -0.3, 0.45});

    brickmap_params_cpu.edit_count = cast(u32) count;
}

brickmap_apply_runtime_edit :: () {
    if brickmap_params_cpu.edit_count <= 0 return;

    old_bounds := brickmap_edit_bounds(0);

    // Animated CSG punch to validate edit->BVH->brickmap update path.
    brickmap_edits_cpu[0].position += .{1.35, 0.75, -0.55};
    brickmap_edits_cpu[0].op = SDF_OP_UNION;

    new_bounds := brickmap_edit_bounds(0);

    brickmap_rebuild_bvh();
    brickmap_mark_dirty_aabb(old_bounds, "auto_edit_old");
    brickmap_mark_dirty_aabb(new_bounds, "auto_edit_new");

    if brickmap_log_updates {
        log("BRICKMAP runtime edit applied at frame=%", frame_count);
    }
}

brickmap_rebuild_bvh :: () {
    count := cast(s32) brickmap_params_cpu.edit_count;
    brickmap_bvh.edit_count = count;
    for i: 0..count-1 {
        brickmap_bvh.edit_bounds[i] = brickmap_edit_bounds(i);
    }
}

brickmap_edit_bounds :: (edit_index: s32) -> AABB {
    e := brickmap_edits_cpu[edit_index];
    extent := Vector3.{e.radius, e.radius, e.radius};
    if e.shape == SDF_SHAPE_BOX {
        // Conservative bound for rotated boxes.
        extent = .{length(e.half_extents), length(e.half_extents), length(e.half_extents)};
    }
    margin := 0.2;
    return .{
        min = e.position - extent - .{margin, margin, margin},
        max = e.position + extent + .{margin, margin, margin},
    };
}

brickmap_mark_all_edits_dirty :: (reason: string) {
    count := cast(s32) brickmap_params_cpu.edit_count;
    for i: 0..count-1 {
        brickmap_mark_dirty_aabb(brickmap_bvh.edit_bounds[i], reason);
    }
}

brickmap_update_lod_origins :: (camera_moved: bool) {
    _ = camera_moved;
    base_voxel := 0.14;

    changed := false;
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        voxel_size := base_voxel * cast(float) (1 << lod);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

        origin_x := cast(s32) floor(brickmap_camera.position.x / brick_world_size) - BRICKMAP_GRID_RES / 2;
        origin_y := cast(s32) floor(brickmap_camera.position.y / brick_world_size) - BRICKMAP_GRID_RES / 2;
        origin_z := cast(s32) floor(brickmap_camera.position.z / brick_world_size) - BRICKMAP_GRID_RES / 2;

        info := brickmap_lod_info_cpu[lod];
        if info.origin_brick_x != origin_x || info.origin_brick_y != origin_y || info.origin_brick_z != origin_z {
            changed = true;
            brickmap_lod_info_cpu[lod].origin_brick_x = origin_x;
            brickmap_lod_info_cpu[lod].origin_brick_y = origin_y;
            brickmap_lod_info_cpu[lod].origin_brick_z = origin_z;
        }
        brickmap_lod_info_cpu[lod].voxel_size = voxel_size;
    }

    if changed {
        brickmap_force_full_rebuild = true;
        if brickmap_log_updates {
            log("BRICKMAP clipmap recentered; forcing cache rebuild.");
        }
    }
}

brickmap_clear_cache :: () {
    for i: 0..brickmap_pointer_grid_cpu.count-1 {
        brickmap_pointer_grid_cpu[i] = -1;
    }
    for i: 0..brickmap_atlas_cpu.count-1 {
        brickmap_atlas_cpu[i] = cast(u8) 128;
    }
    for i: 0..brickmap_dirty_flags.count-1 {
        brickmap_dirty_flags[i] = false;
    }
    brickmap_next_atlas_index = 0;
    brickmap_pending_dirty_count = 0;
}

brickmap_mark_dirty_aabb :: (bounds: AABB, reason: string) {
    overlap_indices: [BRICKMAP_MAX_EDITS] s32;
    overlap_count := brickmap_bvh_query_overlap(bounds, *overlap_indices);
    pending_before := brickmap_pending_dirty_count;
    atlas_before := brickmap_next_atlas_index;

    if brickmap_log_updates {
        log("BRICKMAP mark_dirty reason=% overlap_edits=% bounds_min=[%,%,%] bounds_max=[%,%,%]",
            reason, overlap_count,
            bounds.min.x, bounds.min.y, bounds.min.z,
            bounds.max.x, bounds.max.y, bounds.max.z);
    }

    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := brickmap_lod_info_cpu[lod];
        voxel_size := max(info.voxel_size, 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

        bx0 := cast(s32) floor(bounds.min.x / brick_world_size);
        by0 := cast(s32) floor(bounds.min.y / brick_world_size);
        bz0 := cast(s32) floor(bounds.min.z / brick_world_size);
        bx1 := cast(s32) floor(bounds.max.x / brick_world_size);
        by1 := cast(s32) floor(bounds.max.y / brick_world_size);
        bz1 := cast(s32) floor(bounds.max.z / brick_world_size);
        lx0 := bx0 - info.origin_brick_x;
        ly0 := by0 - info.origin_brick_y;
        lz0 := bz0 - info.origin_brick_z;
        lx1 := bx1 - info.origin_brick_x;
        ly1 := by1 - info.origin_brick_y;
        lz1 := bz1 - info.origin_brick_z;
        if lx0 < 0 lx0 = 0;
        if ly0 < 0 ly0 = 0;
        if lz0 < 0 lz0 = 0;
        if lx1 > BRICKMAP_GRID_RES - 1 lx1 = BRICKMAP_GRID_RES - 1;
        if ly1 > BRICKMAP_GRID_RES - 1 ly1 = BRICKMAP_GRID_RES - 1;
        if lz1 > BRICKMAP_GRID_RES - 1 lz1 = BRICKMAP_GRID_RES - 1;
        if lx1 < lx0 || ly1 < ly0 || lz1 < lz0 continue;

        for lz: lz0..lz1 {
            for ly: ly0..ly1 {
                for lx: lx0..lx1 {
                    cell_local := brickmap_flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    cell := lod * BRICKMAP_GRID_CELLS + cell_local;
                    if brickmap_dirty_flags[cell] continue;

                    atlas_index := brickmap_pointer_grid_cpu[cell];
                    if atlas_index < 0 {
                        if brickmap_next_atlas_index >= BRICKMAP_MAX_BRICKS {
                            if brickmap_log_updates log_error("BRICKMAP atlas exhausted while allocating brick.");
                            continue;
                        }
                        atlas_index = brickmap_next_atlas_index;
                        brickmap_next_atlas_index += 1;
                        brickmap_pointer_grid_cpu[cell] = atlas_index;
                    }

                    if brickmap_pending_dirty_count >= BRICKMAP_MAX_DIRTY_BRICKS {
                        if brickmap_log_updates log_error("BRICKMAP dirty queue full; dropping brick updates.");
                        continue;
                    }

                    bx := lx + info.origin_brick_x;
                    by := ly + info.origin_brick_y;
                    bz := lz + info.origin_brick_z;
                    req := Brick_Request.{
                        lod = cast(u32) lod,
                        brick_x = bx,
                        brick_y = by,
                        brick_z = bz,
                        atlas_index = cast(u32) atlas_index,
                    };
                    brickmap_dirty_cpu[brickmap_pending_dirty_count] = req;
                    brickmap_pending_dirty_count += 1;
                    brickmap_dirty_flags[cell] = true;
                }
            }
        }
    }

    if brickmap_log_updates {
        queued := brickmap_pending_dirty_count - pending_before;
        atlas_new := brickmap_next_atlas_index - atlas_before;
        log("BRICKMAP mark_dirty_done reason=% queued_bricks=% atlas_new=% pending_total=% atlas_used=%",
            reason, queued, atlas_new, brickmap_pending_dirty_count, brickmap_next_atlas_index);
    }
}

brickmap_bvh_query_overlap :: (bounds: AABB, out_indices: *[BRICKMAP_MAX_EDITS] s32) -> s32 {
    count: s32 = 0;
    for i: 0..brickmap_bvh.edit_count-1 {
        b := brickmap_bvh.edit_bounds[i];
        if b.max.x < bounds.min.x || b.min.x > bounds.max.x continue;
        if b.max.y < bounds.min.y || b.min.y > bounds.max.y continue;
        if b.max.z < bounds.min.z || b.min.z > bounds.max.z continue;
        if count < BRICKMAP_MAX_EDITS {
            out_indices.*[count] = i;
            count += 1;
        }
    }
    return count;
}

brickmap_flatten_3d :: (x: s32, y: s32, z: s32, dim: s32) -> s32 {
    return x + y * dim + z * dim * dim;
}

quat_from_euler_xyz :: (euler: Vector3) -> Quaternion {
    hx := euler.x * 0.5;
    hy := euler.y * 0.5;
    hz := euler.z * 0.5;

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

brickmap_add_sphere :: (count: *s32, pos: Vector3, radius: float, op: u32 = SDF_OP_UNION) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    brickmap_edits_cpu[count.*] = .{
        shape = SDF_SHAPE_SPHERE,
        op = op,
        position = pos,
        radius = radius,
        half_extents = .{radius, radius, radius},
        rotation = .{0.0, 0.0, 0.0, 1.0},
    };
    count.* += 1;
}

brickmap_add_box :: (count: *s32, pos: Vector3, half_extents: Vector3, euler: Vector3 = .{0.0, 0.0, 0.0}, op: u32 = SDF_OP_UNION) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    q := quat_from_euler_xyz(euler);
    brickmap_edits_cpu[count.*] = .{
        shape = SDF_SHAPE_BOX,
        op = op,
        position = pos,
        radius = length(half_extents),
        half_extents = half_extents,
        rotation = .{q.x, q.y, q.z, q.w},
    };
    count.* += 1;
}
