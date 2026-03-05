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
    edit_bounds:   [BRICKMAP_MAX_EDITS] AABB;
    build_indices: [BRICKMAP_MAX_EDITS] s32;
    nodes:         [BRICKMAP_MAX_EDITS * 2] Brickmap_BVH_Node;
    edit_count: s32;
    node_count: s32;
    root_node: s32;
    max_depth: s32;
    leaf_count: s32;
    leaf_depth_sum: s32;
}

Brickmap_BVH_Node :: struct {
    bounds: AABB;
    left: s32;
    right: s32;
    edit_index: s32;
}

Brickmap_Validation_Counters :: struct {
    scan_nonempty_cells: s32;
    scan_oob_atlas_refs: s32;
    scan_duplicate_atlas_refs: s32;
    scan_above_next_atlas_refs: s32;
    scan_negative_nonempty_refs: s32;
    scan_holes_below_next: s32;
    scan_referenced_slots: s32;
    scan_dirty_flag_cells: s32;

    shift_preserved_cells: s32;
    shift_invalidated_cells: s32;
    shift_requeued_cells: s32;
    shift_dropped_cells: s32;
    enqueue_overflow: s32;
}

graphics_pipeline: Gpu_Pipeline;
compute_classify_pipeline: Gpu_Pipeline;
compute_bake_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

params_cpu: *Brickmap_Params;
params_gpu: Gpu_Ptr;

pointer_grid_cpu: []s32;
lod_info_cpu: [BRICKMAP_LOD_COUNT] Brickmap_Lod_Info;
edits_storage: [BRICKMAP_MAX_EDITS] SDF_Edit;
edits_cpu: []SDF_Edit;
dirty_storage: [BRICKMAP_MAX_DIRTY_BRICKS] Brick_Request;
dirty_cpu: []Brick_Request;
atlas_texture: Gpu_Texture;
atlas_view: Gpu_Texture_View;
atlas_linear_sampler: Gpu_Sampler;
atlas_point_sampler: Gpu_Sampler;

camera: Editor_Camera = .{
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

bvh: Brickmap_BVH;
dirty_flags: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] bool;
next_atlas_index: s32;
pending_dirty_count: s32;
dirty_backlog_count: s32;
last_camera_pos: Vector3;
force_full_rebuild := true;
atlas_capacity_reached := false;
free_atlas_slots: [BRICKMAP_MAX_BRICKS] s32;
free_atlas_count: s32;

ui_open := true;
auto_edit_after: s32 = -1;
auto_edit_done := false;
log_updates := false;
use_cache_raymarch := true;
use_hw_interp := true;
draw_brick_debug := false;
debug_brick_limit: s32 = 420;
show_atlas_overlay := false;
show_atlas_fullscreen := false;
show_pointer_grid_debug := false;
bake_gradient_debug := false;
skip_classify_debug := false;
cache_debug_show_selected_lod := false;
cache_debug_show_distance := false;
cache_force_lod0 := false;
auto_fly_forward := false;
auto_fly_speed: float = 8.0;
log_validation_every_frame := false;
atlas_debug_slice: float = 0.5;
debug_autolog_once := false;
BRICKMAP_RANDOM_STARTUP_EDITS :: 900;
BRICKMAP_RANDOM_STARTUP_SEED  :: cast(u64) 0xB17C_A11A_5EED;

gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
manip_ctx: Manip_Context;
manip_objects: [..]Manip_Object;
edit_manip_enabled := true;
selected_edit: s32 = -1;
left_was_down := false;
validation_frame: Brickmap_Validation_Counters;
validation_total: Brickmap_Validation_Counters;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, brickmap_vertex_main, brickmap_fragment_main);
    classify_source := cast([]u8) get_transpiled(.METAL, brickmap_classify_dirty_compute);
    compute_source  := cast([]u8) get_transpiled(.METAL, brickmap_bake_compute);

    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, brickmap_vertex_main, brickmap_fragment_main);
    assert(graphics_ok, "Brickmap graphics pipeline creation failed.");

    compute_classify_pipeline = gpu_create_compute_pipeline(classify_source);
    assert(compute_classify_pipeline != 0, "Brickmap classify compute pipeline creation failed.");
    classify_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_classify_pipeline, classify_source, .METAL, brickmap_classify_dirty_compute);
    assert(classify_ok, "Brickmap classify compute pipeline hot-reload registration failed.");

    compute_bake_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_bake_pipeline != 0, "Brickmap bake compute pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_bake_pipeline, compute_source, .METAL, brickmap_bake_compute);
    assert(compute_ok, "Brickmap bake compute pipeline hot-reload registration failed.");

    arena_bytes := 256 * 1024 * 1024; // TODO: calculate this based on our
    gpu_arena = gpu_make_arena(arena_bytes, label = "brickmap arena");
    assert(gpu_arena.cpu != null, "Brickmap arena allocation failed.");

    params_cpu, params_gpu = gpu_arena_alloc(*gpu_arena, Brickmap_Params);

    assert(params_cpu != null, "Brickmap params alloc failed.");

    params_cpu.* = .{};
    pointer_grid_cpu = params_cpu.pointer_grid;
    edits_cpu = edits_storage;
    dirty_cpu = dirty_storage;
    params_cpu.camera_fov_y = PI / 3.0;
    params_cpu.camera_tan_half_fov = tan(params_cpu.camera_fov_y * 0.5);

    texture_result, atlas_texture= := gpu_create_texture(.{
        type = ._3D,
        dimensions = .[BRICKMAP_ATLAS_DIM_X, BRICKMAP_ATLAS_DIM_Y, BRICKMAP_ATLAS_DIM_Z],
        format = .R32_SFLOAT,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("Brickmap atlas texture creation failed: %", texture_result));
    assert(atlas_texture != 0, "Brickmap atlas texture handle invalid.");
    atlas_view = gpu_texture_view(atlas_texture);
    assert(atlas_view != 0, "Brickmap atlas texture view creation failed.");
    atlas_linear_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(atlas_linear_sampler != 0, "Brickmap atlas linear sampler creation failed.");
    atlas_point_sampler = gpu_create_sampler(.{
        min_filter = .NEAREST,
        mag_filter = .NEAREST,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(atlas_point_sampler != 0, "Brickmap atlas point sampler creation failed.");
    params_cpu.atlas_texture_index = cast(u32) atlas_view - 1;
    params_cpu.atlas_sampler_linear_index = cast(u32) atlas_linear_sampler - 1;
    params_cpu.atlas_sampler_point_index = cast(u32) atlas_point_sampler - 1;
    log("BRICKMAP bindless indices tex=% linear_sampler=% point_sampler=%",
        params_cpu.atlas_texture_index,
        params_cpu.atlas_sampler_linear_index,
        params_cpu.atlas_sampler_point_index);

    try_parse_env_int("BRICKMAP_EDIT_AFTER", *auto_edit_after);
    try_parse_env_int("BRICKMAP_LOG", *log_updates);
    try_parse_env_int("BRICKMAP_SKIP_CLASSIFY", *skip_classify_debug);
    try_parse_env_int("BRICKMAP_AUTO_FLY_FORWARD", *auto_fly_forward);
    try_parse_env_int("BRICKMAP_AUTO_FLY_SPEED", *auto_fly_speed);
    try_parse_env_int("BRICKMAP_LOG_VALIDATION", *log_validation_every_frame);

    seed_initial_scene();
    rebuild_bvh();
    params_cpu.atlas_alloc_next = 0;
    update_lod_origins(true);
    clear_cache();
    mark_all_edits_dirty("init");
    force_full_rebuild = false;
    if log_updates {
        log("BRICKMAP init_dirty_complete pending=% atlas_used=%", pending_dirty_count, next_atlas_index);
    }

    last_camera_pos = camera.position;

    Gizmo.init(*gizmo_ctx);
    gizmo_ok := Gizmo_Render.init(*gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Brickmap gizmo renderer init failed.");
    Gizmo_Render.bind_gizmo(*gizmo_render_ctx, *gizmo_ctx);
    manip_objects.allocator = context.allocator;

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    gpu_free(atlas_point_sampler);
    gpu_free(atlas_linear_sampler);
    gpu_free_texture_view(atlas_view);
    gpu_free(atlas_texture);
    array_free(manip_objects);
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{560.0, 420.0}, .FirstUseEver);
    if Begin("Brickmap", *ui_open) {
        Text("Sparse brickmap SDF raymarch prototype");
        Text("RMB look, WASDQE fly, Shift boost");
        _ = toggle("Use Cache Raymarch", *use_cache_raymarch, .{56.0, 0.0}, true, 0.09);
        _ = toggle("Use HW 3D Interp", *use_hw_interp, .{56.0, 0.0}, true, 0.09);
        Checkbox("Atlas Overlay", *show_atlas_overlay);
        if show_atlas_overlay {
            SliderFloat("Atlas Slice", *atlas_debug_slice, 0.0, 1.0);
            Checkbox("Atlas Fullscreen Debug", *show_atlas_fullscreen);
        }
        Checkbox("Pointer Grid Debug", *show_pointer_grid_debug);
        Checkbox("Bake Gradient Debug", *bake_gradient_debug);
        Checkbox("Skip Classify (Debug)", *skip_classify_debug);
        Checkbox("Cache Debug: Selected LOD", *cache_debug_show_selected_lod);
        Checkbox("Cache Debug: Distance", *cache_debug_show_distance);
        Checkbox("Cache Debug: Force LOD0", *cache_force_lod0);
        Checkbox("Draw Brick Debug", *draw_brick_debug);
        Checkbox("Edit Manip", *edit_manip_enabled);
        Text("Selected edit: %", selected_edit);
        if edit_manip_enabled {
            Text("Manip mode/space: % / %", manip_ctx.mode, manip_ctx.space);
        }
        if TreeNode("Debug Info") {
            defer TreePop();
            Text("Edits: %", params_cpu.edit_count);
            avg_leaf_depth := ifx bvh.leaf_count > 0 then cast(float) bvh.leaf_depth_sum / cast(float) bvh.leaf_count else 0.0;
            Text("BVH nodes/leaves: % / %", bvh.node_count, bvh.leaf_count);
            Text("BVH depth max/avg_leaf: % / %", bvh.max_depth, avg_leaf_depth);
            Text("Dirty bricks pending: %", pending_dirty_count);
            Text("Dirty backlog (flags): %", dirty_backlog_count);
            Text("Dirty bricks after classify: %", params_cpu.dirty_count);
            Text("Atlas bricks used: % / %", next_atlas_index, BRICKMAP_MAX_BRICKS);
            Text("Pointer cells allocated: %", count_allocated_cells());
            Separator();
            {
                using params_cpu;
                Text("GPU classify candidates: %", debug_classify_candidates);
                Text("GPU classify surface: %", debug_classify_surface);
                Text("GPU classify existing/new: % / %", debug_classify_existing, debug_classify_new_alloc);
                Text("GPU classify rejected(cap): %", debug_classify_rejected_capacity);
                Text("GPU classify out_count: %", debug_classify_out_count);
                Text("GPU bake bricks/voxels: % / %", debug_bake_bricks_touched, debug_bake_total_voxels);
                Text("GPU bake atlas min..max: % .. %", debug_bake_min_atlas, debug_bake_max_atlas);
                seen_count := cast(s32) min(params_cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
                seen_min: s32 = 1 << 30;
                seen_max: s32 = -1;
                seen_nonzero: s32 = 0;
                for i: 0..seen_count-1 {
                    v := cast(s32) debug_bake_seen_atlas[i];
                    if v < seen_min seen_min = v;
                    if v > seen_max seen_max = v;
                    if v > 0 seen_nonzero += 1;
                }
                if seen_count <= 0 {
                    seen_min = 0;
                    seen_max = 0;
                }
                Text("GPU bake seen atlas min..max: % .. %", seen_min, seen_max);
                Text("GPU bake seen atlas nonzero: % / %", seen_nonzero, seen_count);
            }
            Separator();
            {
                using validation_frame;
                Text("VAL scan nonempty/oob/dup: % / % / %", scan_nonempty_cells, scan_oob_atlas_refs, scan_duplicate_atlas_refs);
                Text("VAL scan above_next/neg_nonempty/holes: % / % / %", scan_above_next_atlas_refs, scan_negative_nonempty_refs, scan_holes_below_next);
                Text("VAL scan refs/dirty_flags: % / %", scan_referenced_slots, scan_dirty_flag_cells);
                Text("VAL shift preserve/invalidate/requeue/drop: % / % / % / %", shift_preserved_cells, shift_invalidated_cells, shift_requeued_cells, shift_dropped_cells);
                Text("VAL queue overflow frame/total: % / %", enqueue_overflow, enqueue_overflow);
            }
            Text("Auto edit after frame: %", auto_edit_after);
            Text("Auto edit done: %", ifx auto_edit_done then "yes" else "no");
            Separator();
            Text("Clip LOD0 origin brick: %", lod_info_cpu[0].origin_brick);
            Text("Clip LOD1 origin brick: %", lod_info_cpu[1].origin_brick);
            if Button("apply runtime edit") {
                apply_runtime_edit();
            }
            Separator();
            Text("Edit List");
            edit_count := cast(s32) params_cpu.edit_count;
            if BeginChild("brickmap_edit_list", .{0.0, 180.0}, .None) {
                if edit_count <= 0 {
                    Text("  (no edits)");
                } else {
                    for i: 0..edit_count-1 {
                        using edit := edits_cpu[i];
                        Text("#%  %  %  pos(%)  r=%  he(%)",
                            i,
                            shape_label(shape),
                            op,
                            position,
                            edit.radius,
                            edit.half_extents);
                    }
                }
            }
            EndChild();
        }
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    gpu_next_atlas := cast(s32) params_cpu.atlas_alloc_next;
    if gpu_next_atlas > BRICKMAP_MAX_BRICKS {
        gpu_next_atlas = BRICKMAP_MAX_BRICKS;
    }
    if gpu_next_atlas > next_atlas_index {
        next_atlas_index = gpu_next_atlas;
    }
    grid_max_atlas := pointer_grid_max_atlas_index();
    compact_next := clamp(grid_max_atlas + 1, 0, BRICKMAP_MAX_BRICKS);
    if compact_next < next_atlas_index {
        next_atlas_index = compact_next;
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);

    ui();
    validation_begin_frame();
    io := ImGui.GetIO();
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_pressed := left_down && !left_was_down;
    left_released := !left_down && left_was_down;
    left_was_down = left_down;

    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;
        if !edit_manip_enabled continue;
        using manip_ctx;
        if key_code == {
            case #char "1"; mode = .TRANSLATE;
            case #char "2"; manip_ctx.mode = .ROTATE;
            case #char "3"; manip_ctx.mode = .SCALE;
            case #char "4"; manip_ctx.space = .WORLD;
            case #char "5"; manip_ctx.space = .LOCAL;
        }
    }

    _ = editor_camera_update(*camera, dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = right_down && !io.WantCaptureMouse);
    if auto_fly_forward {
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
        camera.position += cam_forward * (auto_fly_speed * cast(float) dt);
    }

    if !debug_autolog_once && frame_count >= 2 {
        seen_count := cast(s32) min(params_cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
        seen_min: s32 = 1 << 30;
        seen_max: s32 = -1;
        seen_nonzero: s32 = 0;
        for i: 0..seen_count-1 {
            v := cast(s32) params_cpu.debug_bake_seen_atlas[i];
            if v < seen_min seen_min = v;
            if v > seen_max seen_max = v;
            if v > 0 seen_nonzero += 1;
        }
        if seen_count <= 0 {
            seen_min = 0;
            seen_max = 0;
        }

        using params_cpu;
        log("BRICKMAP_GPU_DEBUG edits=% dirty_pending=% dirty_after=% atlas_used=%/% ptr_cells=% classify(cand=% surf=% exist=% new=% reject=% out=%) bake(bricks=% voxels=% atlas=%..% seen=%..% nonzero=%/%)",
            edit_count,
            pending_dirty_count,
            dirty_count,
            next_atlas_index, BRICKMAP_MAX_BRICKS,
            count_allocated_cells(),
            debug_classify_candidates,
            debug_classify_surface,
            debug_classify_existing,
            debug_classify_new_alloc,
            debug_classify_rejected_capacity,
            debug_classify_out_count,
            debug_bake_bricks_touched,
            debug_bake_total_voxels,
            debug_bake_min_atlas, debug_bake_max_atlas,
            seen_min, seen_max, seen_nonzero, seen_count);
        debug_autolog_once = true;
    }

    if frame_count == auto_edit_after && !auto_edit_done {
        apply_runtime_edit();
        auto_edit_done = true;
    }

    camera_moved := distance(camera.position, last_camera_pos) > 0.35;
    if camera_moved {
        last_camera_pos = camera.position;
    }

    can_recenter := camera_moved;
    if atlas_capacity_reached && dirty_backlog_count > BRICKMAP_MAX_DIRTY_BRICKS / 2 {
        can_recenter = false;
    }
    update_lod_origins(can_recenter);

    if force_full_rebuild {
        clear_cache();
        mark_all_edits_dirty("recenter/full");
        force_full_rebuild = false;
    }

    if dims_ok && win_w > 0 && win_h > 0 {
        params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    params_cpu.time = cast(float) time;
    params_cpu.use_cache_raymarch = ifx use_cache_raymarch then cast(u32) 1 else cast(u32) 0;
    params_cpu.use_hw_interp = ifx use_hw_interp then cast(u32) 1 else cast(u32) 0;
    params_cpu.atlas_debug_overlay = ifx show_atlas_overlay then cast(u32) 1 else cast(u32) 0;
    params_cpu.atlas_debug_fullscreen = ifx show_atlas_fullscreen then cast(u32) 1 else cast(u32) 0;
    params_cpu.pointer_grid_debug = ifx show_pointer_grid_debug then cast(u32) 1 else cast(u32) 0;
    params_cpu.bake_debug_gradient = ifx bake_gradient_debug then cast(u32) 1 else cast(u32) 0;
    params_cpu.cache_debug_show_selected_lod = ifx cache_debug_show_selected_lod then cast(u32) 1 else cast(u32) 0;
    params_cpu.cache_debug_show_distance = ifx cache_debug_show_distance then cast(u32) 1 else cast(u32) 0;
    params_cpu.cache_force_lod0 = ifx cache_force_lod0 then cast(u32) 1 else cast(u32) 0;
    params_cpu.atlas_debug_slice = clamp(atlas_debug_slice, 0.0, 1.0);
    params_cpu.camera_pos = camera.position;
    params_cpu.camera_fov_y = PI / 3.0;
    params_cpu.camera_tan_half_fov = tan(params_cpu.camera_fov_y * 0.5);
    editor_camera_basis(*camera, *params_cpu.camera_forward, *params_cpu.camera_right, *params_cpu.camera_up);
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := lod_info_cpu[lod];
        params_cpu.lod_origin_brick_x[lod] = info.origin_brick.x;
        params_cpu.lod_origin_brick_y[lod] = info.origin_brick.y;
        params_cpu.lod_origin_brick_z[lod] = info.origin_brick.z;
        params_cpu.lod_voxel_size[lod] = info.voxel_size;
    }
    draw_any_gizmo := (draw_brick_debug || edit_manip_enabled) && dims_ok && win_w > 0 && win_h > 0;
    if draw_any_gizmo {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        view := editor_camera_make_view(*camera);
        proj := make_projection_matrix(params_cpu.camera_fov_y, viewport.x / max(viewport.y, 1.0), 0.05, 160.0);
        Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, proj * view);
        Gizmo.begin_frame(*gizmo_ctx);

        if draw_brick_debug {
            build_debug_gizmos();
        }

        if edit_manip_enabled {
            ray_origin, ray_dir, ray_ok := mouse_world_ray(
                params_cpu.resolution, params_cpu.camera_tan_half_fov,
                camera.position, params_cpu.camera_forward, params_cpu.camera_right, params_cpu.camera_up,
                .{cast(float) mx, cast(float) my}, mouse_ok);

            frame := Manip_Frame_Input.{
                viewport = viewport,
                camera_pos = camera.position,
                camera_forward = params_cpu.camera_forward,
                camera_right = params_cpu.camera_right,
                camera_up = params_cpu.camera_up,
                fov_y = params_cpu.camera_fov_y,
                mouse_pos = .{cast(float) mx, cast(float) my},
                mouse_valid = mouse_ok,
                mouse_down = left_down,
                mouse_pressed = left_pressed,
                mouse_released = left_released,
                block_mouse = io.WantCaptureMouse || right_down,
            };

            manip_result: Manip_Result;
            old_bounds: AABB;
            had_selected := false;
            if selected_edit >= 0 && cast(s64) selected_edit < edits_cpu.count {
                had_selected = true;
                old_bounds = edit_bounds(selected_edit);

                manip_obj := edit_to_manip_object(selected_edit);
                array_reset(*manip_objects);
                array_add(*manip_objects, manip_obj);
                manip_ctx.selected_index = 0;
                manip_result = manip_update(*manip_ctx, *gizmo_ctx, manip_objects, frame);
            } else {
                manip_ctx.selected_index = -1;
                array_reset(*manip_objects);
            }

            if had_selected && manip_result.changed {
                obj_i := cast(s64) manip_ctx.selected_index;
                if obj_i >= 0 && obj_i < manip_objects.count {
                    apply_manip_to_edit(selected_edit, manip_objects[obj_i]);
                    rebuild_bvh();
                    new_bounds := edit_bounds(selected_edit);
                    mark_dirty_aabb(old_bounds, "manip_old");
                    mark_dirty_aabb(new_bounds, "manip_new");
                }
            }

            // Scene picking should only be blocked by actual gizmo-handle interaction.
            // `manip_result.captured_mouse` is broader (includes selected-object hover), which prevents re-selection.
            handle_hovered := manip_ctx.hovered_axis >= 0 || manip_ctx.hovered_plane >= 0 || manip_ctx.hovered_orbit;
            can_pick_scene := left_pressed && !io.WantCaptureMouse && !right_down && !manip_ctx.active && !handle_hovered;
            if can_pick_scene {
                if ray_ok {
                    selected_edit = pick_edit_from_bvh(ray_origin, ray_dir);
                } else {
                    selected_edit = -1;
                }
            }
        }
    }

    // Build a bounded dirty batch from persistent dirty flags.
    pending_dirty_count = build_dirty_batch_from_flags(BRICKMAP_MAX_DIRTY_BRICKS);

    // Upload edits and dirty queue after manip/picking so compute sees latest changes this frame.
    edit_count := cast(s32) params_cpu.edit_count;
    for i: 0..edit_count-1 {
        e := edits_cpu[i];
        using params_cpu;
        edit_shape[i] = e.shape;
        edit_op[i] = e.op;
        edit_pos_radius[i] = .{e.position.x, e.position.y, e.position.z, e.radius};
        edit_half_extents_blend[i] = .{e.half_extents.x, e.half_extents.y, e.half_extents.z, e.blend};
        edit_rotation[i] = e.rotation;
    }
    for i: 0..pending_dirty_count-1 {
        req := dirty_cpu[i];
        params_cpu.dirty_lod_brick_xyz_in[i] = .{cast(float) req.lod, cast(float) req.brick_x, cast(float) req.brick_y, cast(float) req.brick_z};
        // Keep output queue seeded for debug/skip-classify paths.
        params_cpu.dirty_lod_brick_xyz[i] = params_cpu.dirty_lod_brick_xyz_in[i];
        params_cpu.dirty_atlas_index[i] = 0;
        params_cpu.dirty_classify_result[i] = 0;
    }

    params_cpu.dirty_count = 0;
    bake_threads: s32 = 0;
    main_queue := gpu_get_queue(.MAIN, 0);
    if pending_dirty_count > 0 {
        params_cpu.atlas_alloc_next = cast(u32) next_atlas_index;

        if skip_classify_debug {
            using params_cpu;
            debug_classify_candidates = cast(u32) pending_dirty_count;
            dirty_count = cast(u32) pending_dirty_count;
            for i: 0..pending_dirty_count-1 {
                dirty_atlas_index[i] = cast(u32) i;
                dirty_classify_result[i] = 1;
            }
            debug_classify_out_count = cast(u32) pending_dirty_count;
            debug_bake_min_atlas = 0;
            debug_bake_max_atlas = cast(u32) max(0, pending_dirty_count - 1);
            if next_atlas_index < pending_dirty_count {
                next_atlas_index = pending_dirty_count;
                atlas_alloc_next = cast(u32) next_atlas_index;
            }
            bake_threads = pending_dirty_count * BRICKMAP_BRICK_TEXELS;
        } else {
            {
                using params_cpu;
                debug_classify_candidates = cast(u32) pending_dirty_count;
                debug_classify_surface = 0;
                debug_classify_existing = 0;
                debug_classify_new_alloc = 0;
                debug_classify_rejected_capacity = 0;
                debug_classify_out_count = 0;
                dirty_count = 0;
                debug_bake_total_voxels = 0;
                debug_bake_bricks_touched = 0;
                debug_bake_min_atlas = cast(u32) 0xFFFFFFFF;
                debug_bake_max_atlas = 0;
            }

            result=, classify_cmd := gpu_start_command_recording(main_queue);
            assert(result == .SUCCESS);
            result = gpu_set_pipeline(classify_cmd, compute_classify_pipeline);
            assert(result == .SUCCESS, tprint("Brickmap classify set pipeline failed: %", result));
            classify_threads := cast(u32) pending_dirty_count;
            classify_dispatch_x := (classify_threads + 63) / 64;
            if classify_dispatch_x > 0 {
                gpu_dispatch_buffers(classify_cmd, .[params_gpu], .[classify_dispatch_x, 1, 1]);
            }
            gpu_submit(classify_cmd);
            gpu_queue_wait_idle(main_queue);

            gpu_next_atlas_after := cast(s32) params_cpu.atlas_alloc_next;
            if gpu_next_atlas_after > BRICKMAP_MAX_BRICKS {
                gpu_next_atlas_after = BRICKMAP_MAX_BRICKS;
            }
            if gpu_next_atlas_after > next_atlas_index {
                next_atlas_index = gpu_next_atlas_after;
            }
            if params_cpu.debug_classify_rejected_capacity > 0 {
                if !atlas_capacity_reached && log_updates {
                    log_error("BRICKMAP classify rejected % bricks due to atlas capacity; preserving dirty flags for retry.",
                        params_cpu.debug_classify_rejected_capacity);
                }
                atlas_capacity_reached = true;
            } else if next_atlas_index < BRICKMAP_MAX_BRICKS {
                atlas_capacity_reached = false;
            }
            params_cpu.debug_classify_out_count = params_cpu.dirty_count;
            if params_cpu.dirty_count == 0 {
                params_cpu.debug_bake_min_atlas = 0;
                params_cpu.debug_bake_max_atlas = 0;
            }
            bake_threads = cast(s32) params_cpu.dirty_count * BRICKMAP_BRICK_TEXELS;
        }
    }

    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if pending_dirty_count > 0 {
        result = gpu_set_pipeline(cmd_buff, compute_bake_pipeline);
        assert(result == .SUCCESS, tprint("Brickmap bake set pipeline failed: %", result));
        dispatch_x := cast(u32) ((bake_threads + 63) / 64);
        if dispatch_x > 0 {
            gpu_dispatch_buffers(cmd_buff, .[params_gpu], .[dispatch_x, 1, 1]);
            gpu_barrier(cmd_buff, .COMPUTE_SHADER, .PIXEL_SHADER);
        }

        if log_updates {
            log("BRICKMAP baked frame=% dirty_bricks=% threads=%", frame_count, pending_dirty_count, bake_threads);
        }
        if skip_classify_debug {
            clear_processed_dirty_flags_from_batch(pending_dirty_count);
        } else {
            apply_classify_results_to_dirty_flags(pending_dirty_count);
        }
        pending_dirty_count = 0;
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

    draw_result := gpu_draw_instanced(cmd_buff, 0, params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Brickmap draw failed: %", draw_result));

    if draw_any_gizmo {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .NONE);
        assert(gizmo_draw_result == .SUCCESS, tprint("Brickmap gizmo draw failed: %", gizmo_draw_result));
    }

    validation_scan_state();
    if log_validation_every_frame {
        log_validation_frame();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../editor_camera.jai";
#load "../ui/toggle_widget.jai";
#load "../ui/manip.jai";

using,only(try_parse_env_int) _ :: #import "Env_Vars";
Input :: #import "Input";
ImGui :: #import "ImGui";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
#import "Math";
#import "Random";

seed_initial_scene :: () {
    count: s32 = 0;

    add_sphere(*count, .{-2.1, 0.3, -3.8}, 1.1);
    add_sphere(*count, .{1.8, -0.1, -4.9}, 1.4);
    add_box(*count, .{0.0, 0.2, -6.7}, .{1.1, 0.9, 1.1}, .{0.18, 0.35, 0.05});
    add_box(*count, .{-3.8, -0.2, -8.2}, .{0.9, 1.5, 0.9}, .{0.0, 0.42, 0.0});
    add_sphere(*count, .{-0.1, 0.6, -6.7}, 0.85, op = SDF_OP_SUBTRACT);
    add_box(*count, .{2.8, 0.7, -8.8}, .{1.7, 0.25, 0.7}, .{0.2, -0.3, 0.45});

    random_seed(BRICKMAP_RANDOM_STARTUP_SEED);
    for 0..BRICKMAP_RANDOM_STARTUP_EDITS-1 {
        shape: u32 = cast(u32) (ifx random_get_zero_to_one() < 0.5 then SDF_SHAPE_SPHERE else SDF_SHAPE_BOX);
        op: u32 = cast(u32) (ifx random_get_zero_to_one() < 0.82 then SDF_OP_UNION else SDF_OP_SUBTRACT);
        pos := Vector3.{
            random_get_within_range(-40.0, 40.0),
            random_get_within_range(-1.2, 3.0),
            random_get_within_range(-26.0, -2.0),
        };

        if shape == SDF_SHAPE_BOX {
            half_extents := Vector3.{
                random_get_within_range(0.35, 1.8),
                random_get_within_range(0.35, 1.8),
                random_get_within_range(0.35, 1.8),
            };
            euler := Vector3.{
                random_get_within_range(-PI, PI),
                random_get_within_range(-PI, PI),
                random_get_within_range(-PI, PI),
            };
            add_box(*count, pos, half_extents, euler, op = op);
        } else {
            radius := random_get_within_range(0.35, 1.65);
            add_sphere(*count, pos, radius, op = op);
        }

        if count >= BRICKMAP_MAX_EDITS break;
    }

    params_cpu.edit_count = cast(u32) count;
}

apply_runtime_edit :: () {
    if params_cpu.edit_count <= 0 return;

    old_bounds := edit_bounds(0);

    // Animated CSG punch to validate edit->BVH->brickmap update path.
    edits_cpu[0].position += .{1.35, 0.75, -0.55};
    edits_cpu[0].op = SDF_OP_UNION;

    new_bounds := edit_bounds(0);

    rebuild_bvh();
    mark_dirty_aabb(old_bounds, "auto_edit_old");
    mark_dirty_aabb(new_bounds, "auto_edit_new");

    if log_updates {
        log("BRICKMAP runtime edit applied at frame=%", frame_count);
    }
}

rebuild_bvh :: () {
    count := cast(s32) params_cpu.edit_count;
    bvh.edit_count = count;
    bvh.node_count = 0;
    bvh.root_node = -1;
    bvh.max_depth = 0;
    bvh.leaf_count = 0;
    bvh.leaf_depth_sum = 0;
    for i: 0..count-1 {
        bvh.edit_bounds[i] = edit_bounds(i);
        bvh.build_indices[i] = i;
    }

    if count > 0 {
        bvh.root_node = bvh_build_range(0, count, 0);
    }
}

edit_bounds :: (edit_index: s32) -> AABB {
    e := edits_cpu[edit_index];
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

mark_all_edits_dirty :: (reason: string) {
    count := cast(s32) params_cpu.edit_count;
    for i: 0..count-1 {
        mark_dirty_aabb(bvh.edit_bounds[i], reason);
    }
}

update_lod_origins :: (camera_moved: bool) {
    if !camera_moved return;
    base_voxel := 0.14;

    changed := false;
    queued_total: s32 = 0;
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        voxel_size := base_voxel * cast(float) (1 << lod);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

        origin_x := cast(s32) floor(camera.position.x / brick_world_size) - BRICKMAP_GRID_RES / 2;
        origin_y := cast(s32) floor(camera.position.y / brick_world_size) - BRICKMAP_GRID_RES / 2;
        origin_z := cast(s32) floor(camera.position.z / brick_world_size) - BRICKMAP_GRID_RES / 2;

        info := lod_info_cpu[lod];
        if info.origin_brick.x != origin_x || info.origin_brick.y != origin_y || info.origin_brick.z != origin_z {
            changed = true;
            if !force_full_rebuild {
                queued_total += shift_lod_cache_for_origin_delta(
                    cast(s32) lod,
                    info.origin_brick.x, info.origin_brick.y, info.origin_brick.z,
                    origin_x, origin_y, origin_z);
            }
            lod_info_cpu[lod].origin_brick.x = origin_x;
            lod_info_cpu[lod].origin_brick.y = origin_y;
            lod_info_cpu[lod].origin_brick.z = origin_z;
        }
        lod_info_cpu[lod].voxel_size = voxel_size;
    }

    if changed {
        if log_updates {
            log("BRICKMAP clipmap recentered; queued_exposed=% pending=%", queued_total, pending_dirty_count);
        }
    }
}

clear_cache :: () {
    for i: 0..pointer_grid_cpu.count-1 {
        pointer_grid_cpu[i] = -1;
    }
    for i: 0..dirty_flags.count-1 {
        dirty_flags[i] = false;
    }
    next_atlas_index = 0;
    params_cpu.atlas_alloc_next = 0;
    pending_dirty_count = 0;
    dirty_backlog_count = 0;
}

shift_lod_cache_for_origin_delta :: (lod: s32,
    old_origin_x: s32, old_origin_y: s32, old_origin_z: s32,
    new_origin_x: s32, new_origin_y: s32, new_origin_z: s32) -> s32 {

    dx := new_origin_x - old_origin_x;
    dy := new_origin_y - old_origin_y;
    dz := new_origin_z - old_origin_z;
    base := lod * BRICKMAP_GRID_CELLS;
    queued: s32 = 0;

    if abs_s32(dx) >= BRICKMAP_GRID_RES || abs_s32(dy) >= BRICKMAP_GRID_RES || abs_s32(dz) >= BRICKMAP_GRID_RES {
        for lz_i: 0..BRICKMAP_GRID_RES-1 {
            lz := cast(s32) lz_i;
            for ly_i: 0..BRICKMAP_GRID_RES-1 {
                ly := cast(s32) ly_i;
                for lx_i: 0..BRICKMAP_GRID_RES-1 {
                    lx := cast(s32) lx_i;
                    idx := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    if pointer_grid_cpu[base + idx] >= 0 {
                        validation_frame.shift_invalidated_cells += 1;
                    }
                    pointer_grid_cpu[base + idx] = -1;
                    dirty_flags[base + idx] = false;

                    bx := new_origin_x + lx;
                    by := new_origin_y + ly;
                    bz := new_origin_z + lz;
                    if try_enqueue_dirty_cell(lod, lx, ly, lz, bx, by, bz) {
                        queued += 1;
                        validation_frame.shift_requeued_cells += 1;
                    } else {
                        validation_frame.shift_dropped_cells += 1;
                        return queued;
                    }
                }
            }
        }
        return queued;
    }

    shifted: [BRICKMAP_GRID_CELLS] s32;
    shifted_dirty: [BRICKMAP_GRID_CELLS] bool;
    for i: 0..BRICKMAP_GRID_CELLS-1 {
        shifted[i] = -1;
        shifted_dirty[i] = false;
    }

    for old_lz_i: 0..BRICKMAP_GRID_RES-1 {
        old_lz := cast(s32) old_lz_i;
        for old_ly_i: 0..BRICKMAP_GRID_RES-1 {
            old_ly := cast(s32) old_ly_i;
            for old_lx_i: 0..BRICKMAP_GRID_RES-1 {
                old_lx := cast(s32) old_lx_i;
                new_lx := old_lx - dx;
                new_ly := old_ly - dy;
                new_lz := old_lz - dz;
                if new_lx < 0 || new_ly < 0 || new_lz < 0 continue;
                if new_lx >= BRICKMAP_GRID_RES || new_ly >= BRICKMAP_GRID_RES || new_lz >= BRICKMAP_GRID_RES continue;

                old_idx := flatten_3d(old_lx, old_ly, old_lz, BRICKMAP_GRID_RES);
                new_idx := flatten_3d(new_lx, new_ly, new_lz, BRICKMAP_GRID_RES);
                shifted[new_idx] = pointer_grid_cpu[base + old_idx];
                shifted_dirty[new_idx] = dirty_flags[base + old_idx];
                if shifted[new_idx] >= 0 {
                    validation_frame.shift_preserved_cells += 1;
                }
            }
        }
    }

    for i: 0..BRICKMAP_GRID_CELLS-1 {
        pointer_grid_cpu[base + i] = shifted[i];
        dirty_flags[base + i] = shifted_dirty[i];
    }

    for lz_i: 0..BRICKMAP_GRID_RES-1 {
        lz := cast(s32) lz_i;
        for ly_i: 0..BRICKMAP_GRID_RES-1 {
            ly := cast(s32) ly_i;
            for lx_i: 0..BRICKMAP_GRID_RES-1 {
                lx := cast(s32) lx_i;
                old_lx := lx + dx;
                old_ly := ly + dy;
                old_lz := lz + dz;
                if old_lx >= 0 && old_ly >= 0 && old_lz >= 0 &&
                   old_lx < BRICKMAP_GRID_RES && old_ly < BRICKMAP_GRID_RES && old_lz < BRICKMAP_GRID_RES {
                    continue;
                }

                idx := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                if pointer_grid_cpu[base + idx] >= 0 {
                    validation_frame.shift_invalidated_cells += 1;
                }
                pointer_grid_cpu[base + idx] = -1;
                dirty_flags[base + idx] = false;

                bx := new_origin_x + lx;
                by := new_origin_y + ly;
                bz := new_origin_z + lz;
                if try_enqueue_dirty_cell(lod, lx, ly, lz, bx, by, bz) {
                    queued += 1;
                    validation_frame.shift_requeued_cells += 1;
                } else {
                    validation_frame.shift_dropped_cells += 1;
                    return queued;
                }
            }
        }
    }

    return queued;
}

try_enqueue_dirty_cell :: (lod: s32, lx: s32, ly: s32, lz: s32, bx: s32, by: s32, bz: s32) -> bool {
    cell_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
    cell := lod * BRICKMAP_GRID_CELLS + cell_local;
    if dirty_flags[cell] return true;
    dirty_flags[cell] = true;
    return true;
}

mark_dirty_aabb :: (bounds: AABB, reason: string) {
    overlap_indices: [BRICKMAP_MAX_EDITS] s32;
    overlap_count := bvh_query_overlap(bounds, *overlap_indices);
    flagged_before := count_dirty_flags();
    atlas_before := next_atlas_index;

    if log_updates {
        log("BRICKMAP mark_dirty reason=% overlap_edits=% bounds_min=[%,%,%] bounds_max=[%,%,%]",
            reason, overlap_count,
            bounds.min.x, bounds.min.y, bounds.min.z,
            bounds.max.x, bounds.max.y, bounds.max.z);
    }

    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := lod_info_cpu[lod];
        voxel_size := max(info.voxel_size, 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

        bx0 := cast(s32) floor(bounds.min.x / brick_world_size);
        by0 := cast(s32) floor(bounds.min.y / brick_world_size);
        bz0 := cast(s32) floor(bounds.min.z / brick_world_size);
        bx1 := cast(s32) floor(bounds.max.x / brick_world_size);
        by1 := cast(s32) floor(bounds.max.y / brick_world_size);
        bz1 := cast(s32) floor(bounds.max.z / brick_world_size);
        lx0 := bx0 - info.origin_brick.x;
        ly0 := by0 - info.origin_brick.y;
        lz0 := bz0 - info.origin_brick.z;
        lx1 := bx1 - info.origin_brick.x;
        ly1 := by1 - info.origin_brick.y;
        lz1 := bz1 - info.origin_brick.z;
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
                    cell_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    cell := lod * BRICKMAP_GRID_CELLS + cell_local;
                    if dirty_flags[cell] continue;
                    dirty_flags[cell] = true;
                }
            }
        }
    }

    if log_updates {
        queued := count_dirty_flags() - flagged_before;
        atlas_new := next_atlas_index - atlas_before;
        log("BRICKMAP mark_dirty_done reason=% queued_bricks=% atlas_new=% pending_total=% atlas_used=%",
            reason, queued, atlas_new, pending_dirty_count, next_atlas_index);
    }
}

count_dirty_flags :: () -> s32 {
    count: s32 = 0;
    for i: 0..dirty_flags.count-1 {
        if dirty_flags[i] count += 1;
    }
    return count;
}

rebuild_free_slots_from_pointer_grid :: () {
    used: [BRICKMAP_MAX_BRICKS] bool;
    max_i := clamp(next_atlas_index, 0, BRICKMAP_MAX_BRICKS);
    for i: 0..pointer_grid_cpu.count-1 {
        v := pointer_grid_cpu[i];
        if v >= 0 && v < max_i {
            used[v] = true;
        }
    }

    free_atlas_count = 0;
    for i: 0..max_i-1 {
        if used[i] continue;
        free_atlas_slots[free_atlas_count] = i;
        free_atlas_count += 1;
    }
}

pop_free_atlas_slot :: () -> s32 {
    if free_atlas_count <= 0 return -1;
    free_atlas_count -= 1;
    return free_atlas_slots[free_atlas_count];
}

build_dirty_batch_from_flags :: (max_batch: s32) -> s32 {
    out_count: s32 = 0;
    total_dirty: s32 = 0;

    rebuild_free_slots_from_pointer_grid();

    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := lod_info_cpu[lod];
        base := lod * BRICKMAP_GRID_CELLS;
        for lz_i: 0..BRICKMAP_GRID_RES-1 {
            lz := cast(s32) lz_i;
            for ly_i: 0..BRICKMAP_GRID_RES-1 {
                ly := cast(s32) ly_i;
                for lx_i: 0..BRICKMAP_GRID_RES-1 {
                    lx := cast(s32) lx_i;
                    idx_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    cell := base + idx_local;
                    if !dirty_flags[cell] continue;
                    total_dirty += 1;
                    if out_count >= max_batch continue;

                    if pointer_grid_cpu[cell] < 0 {
                        slot := pop_free_atlas_slot();
                        if slot >= 0 {
                            pointer_grid_cpu[cell] = slot;
                        }
                    }

                    dirty_cpu[out_count] = .{
                        lod = cast(u32) lod,
                        brick_x = info.origin_brick.x + lx,
                        brick_y = info.origin_brick.y + ly,
                        brick_z = info.origin_brick.z + lz,
                        atlas_index = 0,
                    };
                    out_count += 1;
                }
            }
        }
    }

    dirty_backlog_count = ifx total_dirty > out_count then total_dirty - out_count else 0;
    if dirty_backlog_count > 0 {
        validation_frame.enqueue_overflow += dirty_backlog_count;
        validation_total.enqueue_overflow += dirty_backlog_count;
    }
    return out_count;
}

clear_processed_dirty_flags_from_batch :: (processed_count: s32) {
    count := clamp(processed_count, 0, pending_dirty_count);
    for i: 0..count-1 {
        req := dirty_cpu[i];
        lod := cast(s32) req.lod;
        if lod < 0 || lod >= BRICKMAP_LOD_COUNT continue;
        info := lod_info_cpu[lod];
        lx := req.brick_x - info.origin_brick.x;
        ly := req.brick_y - info.origin_brick.y;
        lz := req.brick_z - info.origin_brick.z;
        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;
        idx_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
        cell := lod * BRICKMAP_GRID_CELLS + idx_local;
        dirty_flags[cell] = false;
    }
}

clear_processed_dirty_flags_from_gpu :: (processed_count: s32) {
    count := clamp(processed_count, 0, BRICKMAP_MAX_DIRTY_BRICKS);
    for i: 0..count-1 {
        req := params_cpu.dirty_lod_brick_xyz[i];
        lod := cast(s32) req.x;
        if lod < 0 || lod >= BRICKMAP_LOD_COUNT continue;
        bx := cast(s32) req.y;
        by := cast(s32) req.z;
        bz := cast(s32) req.w;

        info := lod_info_cpu[lod];
        lx := bx - info.origin_brick.x;
        ly := by - info.origin_brick.y;
        lz := bz - info.origin_brick.z;
        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;
        idx_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
        cell := lod * BRICKMAP_GRID_CELLS + idx_local;
        dirty_flags[cell] = false;
    }
}

apply_classify_results_to_dirty_flags :: (candidate_count: s32) {
    count := clamp(candidate_count, 0, BRICKMAP_MAX_DIRTY_BRICKS);
    for i: 0..count-1 {
        req := dirty_cpu[i];
        lod := cast(s32) req.lod;
        if lod < 0 || lod >= BRICKMAP_LOD_COUNT continue;

        info := lod_info_cpu[lod];
        lx := req.brick_x - info.origin_brick.x;
        ly := req.brick_y - info.origin_brick.y;
        lz := req.brick_z - info.origin_brick.z;
        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;

        idx_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
        cell := lod * BRICKMAP_GRID_CELLS + idx_local;
        result := params_cpu.dirty_classify_result[i];
        if result == 2 {
            dirty_flags[cell] = true;
        } else {
            dirty_flags[cell] = false;
        }
    }
}

bvh_query_overlap :: (bounds: AABB, out_indices: *[BRICKMAP_MAX_EDITS] s32) -> s32 {
    count: s32 = 0;
    if bvh.root_node < 0 return count;

    stack: [BRICKMAP_MAX_EDITS * 2] s32;
    sp: s32 = 0;
    stack[sp] = bvh.root_node;
    sp += 1;

    while sp > 0 {
        sp -= 1;
        node_index := stack[sp];
        if node_index < 0 continue;
        node := bvh.nodes[node_index];
        if !aabb_overlaps(node.bounds, bounds) continue;

        if node.edit_index >= 0 {
            if count < BRICKMAP_MAX_EDITS {
                out_indices.*[count] = node.edit_index;
                count += 1;
            }
            continue;
        }

        if node.left >= 0 {
            stack[sp] = node.left;
            sp += 1;
        }
        if node.right >= 0 {
            stack[sp] = node.right;
            sp += 1;
        }
    }

    return count;
}

flatten_3d :: (x: s32, y: s32, z: s32, dim: s32) -> s32 {
    return x + y * dim + z * dim * dim;
}

abs_s32 :: (v: s32) -> s32 {
    if v < 0 return -v;
    return v;
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

add_sphere :: (count: *s32, pos: Vector3, radius: float, op: u32 = SDF_OP_UNION) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    edits_cpu[count.*] = .{
        shape = SDF_SHAPE_SPHERE,
        op = op,
        position = pos,
        radius = radius,
        half_extents = .{radius, radius, radius},
        rotation = .{0.0, 0.0, 0.0, 1.0},
    };
    count.* += 1;
}

add_box :: (count: *s32, pos: Vector3, half_extents: Vector3, euler: Vector3 = .{0.0, 0.0, 0.0}, op: u32 = SDF_OP_UNION) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    q := quat_from_euler_xyz(euler);
    edits_cpu[count.*] = .{
        shape = SDF_SHAPE_BOX,
        op = op,
        position = pos,
        radius = length(half_extents),
        half_extents = half_extents,
        rotation = .{q.x, q.y, q.z, q.w},
    };
    count.* += 1;
}

count_allocated_cells :: () -> s32 {
    count: s32 = 0;
    for i: 0..pointer_grid_cpu.count-1 {
        if pointer_grid_cpu[i] >= 0 count += 1;
    }
    return count;
}

pointer_grid_max_atlas_index :: () -> s32 {
    max_i: s32 = -1;
    for i: 0..pointer_grid_cpu.count-1 {
        v := pointer_grid_cpu[i];
        if v > max_i max_i = v;
    }
    return max_i;
}

build_debug_gizmos :: () {
    if !draw_brick_debug return;

    drawn: s32 = 0;
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := lod_info_cpu[lod];
        voxel_size := max(info.voxel_size, 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;
        half := Vector3.{brick_world_size * 0.5, brick_world_size * 0.5, brick_world_size * 0.5};
        color := ifx lod == 0 then Vector4.{0.20, 0.88, 1.0, 0.60} else Vector4.{1.0, 0.58, 0.15, 0.60};

        for lz_i: 0..BRICKMAP_GRID_RES-1 {
            lz := cast(s32) lz_i;
            for ly_i: 0..BRICKMAP_GRID_RES-1 {
                ly := cast(s32) ly_i;
                for lx_i: 0..BRICKMAP_GRID_RES-1 {
                    lx := cast(s32) lx_i;
                    if drawn >= debug_brick_limit return;
                    cell_local := flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    cell := lod * BRICKMAP_GRID_CELLS + cell_local;
                    if pointer_grid_cpu[cell] < 0 continue;

                    bx := lx + info.origin_brick.x;
                    by := ly + info.origin_brick.y;
                    bz := lz + info.origin_brick.z;
                    center := Vector3.{
                        (cast(float) bx + 0.5) * brick_world_size,
                        (cast(float) by + 0.5) * brick_world_size,
                        (cast(float) bz + 0.5) * brick_world_size,
                    };
                    Gizmo.draw_box(*gizmo_ctx, center, half, color, 1.2);
                    drawn += 1;
                }
            }
        }
    }
}

validation_begin_frame :: () {
    validation_frame = .{};
}

validation_scan_state :: () {
    seen: [BRICKMAP_MAX_BRICKS] bool;
    next := clamp(next_atlas_index, 0, BRICKMAP_MAX_BRICKS);

    for i: 0..pointer_grid_cpu.count-1 {
        v := pointer_grid_cpu[i];
        if dirty_flags[i] {
            validation_frame.scan_dirty_flag_cells += 1;
        }
        if v == -1 continue;
        if v < -1 {
            validation_frame.scan_negative_nonempty_refs += 1;
            continue;
        }
        validation_frame.scan_nonempty_cells += 1;
        if v >= BRICKMAP_MAX_BRICKS {
            validation_frame.scan_oob_atlas_refs += 1;
            continue;
        }
        if v >= next_atlas_index {
            validation_frame.scan_above_next_atlas_refs += 1;
        }
        if seen[v] {
            validation_frame.scan_duplicate_atlas_refs += 1;
        } else {
            seen[v] = true;
            validation_frame.scan_referenced_slots += 1;
        }
    }

    for i: 0..next-1 {
        if !seen[i] {
            validation_frame.scan_holes_below_next += 1;
        }
    }
}

log_validation_frame :: () {
    v := validation_frame;
    log("BRICKMAP_VAL frame=% cam=[%,%,%] pending=% dirty=% atlas=%/% ptr=% val(nonempty=% oob=% dup=% above=% neg=% holes=% refs=% dirty_flags=%) shift(keep=% inval=% requeue=% drop=% overflow=%)",
        frame_count,
        camera.position.x, camera.position.y, camera.position.z,
        pending_dirty_count,
        params_cpu.dirty_count,
        next_atlas_index, BRICKMAP_MAX_BRICKS,
        count_allocated_cells(),
        v.scan_nonempty_cells, v.scan_oob_atlas_refs, v.scan_duplicate_atlas_refs, v.scan_above_next_atlas_refs,
        v.scan_negative_nonempty_refs, v.scan_holes_below_next, v.scan_referenced_slots, v.scan_dirty_flag_cells,
        v.shift_preserved_cells, v.shift_invalidated_cells, v.shift_requeued_cells, v.shift_dropped_cells, v.enqueue_overflow);
}

mouse_world_ray :: (resolution: Vector2, tan_half_fov: float,
    camera_pos: Vector3, camera_forward: Vector3, camera_right: Vector3, camera_up: Vector3,
    mouse_pos: Vector2, mouse_valid: bool) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if !mouse_valid return .{}, .{}, false;
    if resolution.x <= 1.0 || resolution.y <= 1.0 return .{}, .{}, false;

    uv := Vector2.{mouse_pos.x / resolution.x, mouse_pos.y / resolution.y};
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    p.x *= resolution.x / max(resolution.y, 1.0);
    rd_un := camera_forward + camera_right * (p.x * tan_half_fov) + camera_up * (p.y * tan_half_fov);
    rd_len := length(rd_un);
    rd := ifx rd_len > 0.000001 then rd_un / rd_len else camera_forward;
    return camera_pos, rd, true;
}

ray_aabb_hit_t :: (ray_origin: Vector3, ray_dir: Vector3, bounds: AABB) -> float {
    inv_x: float = cast(float) 1000000000.0;
    inv_y: float = cast(float) 1000000000.0;
    inv_z: float = cast(float) 1000000000.0;
    if abs(ray_dir.x) > 0.000001 inv_x = cast(float) 1.0 / ray_dir.x;
    if abs(ray_dir.y) > 0.000001 inv_y = cast(float) 1.0 / ray_dir.y;
    if abs(ray_dir.z) > 0.000001 inv_z = cast(float) 1.0 / ray_dir.z;
    inv_dir := Vector3.{inv_x, inv_y, inv_z};

    tx0 := (bounds.min.x - ray_origin.x) * inv_dir.x;
    tx1 := (bounds.max.x - ray_origin.x) * inv_dir.x;
    tmin := min(tx0, tx1);
    tmax := max(tx0, tx1);

    ty0 := (bounds.min.y - ray_origin.y) * inv_dir.y;
    ty1 := (bounds.max.y - ray_origin.y) * inv_dir.y;
    tmin = max(tmin, min(ty0, ty1));
    tmax = min(tmax, max(ty0, ty1));

    tz0 := (bounds.min.z - ray_origin.z) * inv_dir.z;
    tz1 := (bounds.max.z - ray_origin.z) * inv_dir.z;
    tmin = max(tmin, min(tz0, tz1));
    tmax = min(tmax, max(tz0, tz1));

    if tmax < 0.0 || tmin > tmax return -1.0;
    out_t := ifx tmin > 0.0 then tmin else tmax;
    return ifx out_t >= 0.0 then out_t else -1.0;
}

pick_edit_from_bvh :: (ray_origin: Vector3, ray_dir: Vector3) -> s32 {
    best_i: s32 = -1;
    best_t: float = cast(float) 1000000000.0;
    if bvh.root_node < 0 return best_i;

    stack: [BRICKMAP_MAX_EDITS * 2] s32;
    sp: s32 = 0;
    stack[sp] = bvh.root_node;
    sp += 1;

    while sp > 0 {
        sp -= 1;
        node_index := stack[sp];
        if node_index < 0 continue;
        node := bvh.nodes[node_index];

        node_t := ray_aabb_hit_t(ray_origin, ray_dir, node.bounds);
        if node_t < 0.0 continue;
        if node_t > best_t continue;

        if node.edit_index >= 0 {
            if node_t < best_t {
                best_t = node_t;
                best_i = node.edit_index;
            }
            continue;
        }

        if node.left >= 0 {
            stack[sp] = node.left;
            sp += 1;
        }
        if node.right >= 0 {
            stack[sp] = node.right;
            sp += 1;
        }
    }

    return best_i;
}

bvh_alloc_node :: () -> s32 {
    assert(bvh.node_count < bvh.nodes.count, "BVH node overflow.");
    out := bvh.node_count;
    bvh.node_count += 1;
    return out;
}

bvh_axis_value :: (v: Vector3, axis: s32) -> float {
    if axis == {
    case 0; return v.x;
    case 1; return v.y;
    case 2; return v.z;
    }
    return v.x;
}

aabb_center :: (b: AABB) -> Vector3 {
    return (b.min + b.max) * 0.5;
}

aabb_union :: (a: AABB, b: AABB) -> AABB {
    return .{
        min = .{
            min(a.min.x, b.min.x),
            min(a.min.y, b.min.y),
            min(a.min.z, b.min.z),
        },
        max = .{
            max(a.max.x, b.max.x),
            max(a.max.y, b.max.y),
            max(a.max.z, b.max.z),
        },
    };
}

aabb_overlaps :: (a: AABB, b: AABB) -> bool {
    if a.max.x < b.min.x || a.min.x > b.max.x return false;
    if a.max.y < b.min.y || a.min.y > b.max.y return false;
    if a.max.z < b.min.z || a.min.z > b.max.z return false;
    return true;
}

bvh_build_range :: (start: s32, end: s32, depth: s32) -> s32 {
    node_index := bvh_alloc_node();
    count := end - start;
    assert(count > 0, "Invalid BVH build range.");
    if depth > bvh.max_depth bvh.max_depth = depth;

    bounds := bvh.edit_bounds[bvh.build_indices[start]];
    centroid_min := aabb_center(bounds);
    centroid_max := centroid_min;
    for i: start+1..end-1 {
        b := bvh.edit_bounds[bvh.build_indices[i]];
        bounds = aabb_union(bounds, b);
        c := aabb_center(b);
        centroid_min.x = min(centroid_min.x, c.x);
        centroid_min.y = min(centroid_min.y, c.y);
        centroid_min.z = min(centroid_min.z, c.z);
        centroid_max.x = max(centroid_max.x, c.x);
        centroid_max.y = max(centroid_max.y, c.y);
        centroid_max.z = max(centroid_max.z, c.z);
    }

    if count == 1 {
        bvh.leaf_count += 1;
        bvh.leaf_depth_sum += depth;
        bvh.nodes[node_index] = .{
            bounds = bounds,
            left = -1,
            right = -1,
            edit_index = bvh.build_indices[start],
        };
        return node_index;
    }

    extent := centroid_max - centroid_min;
    axis: s32 = 0;
    if extent.y > extent.x {
        axis = 1;
    }
    if extent.z > bvh_axis_value(extent, axis) {
        axis = 2;
    }
    split_value := (bvh_axis_value(centroid_min, axis) + bvh_axis_value(centroid_max, axis)) * 0.5;

    left_i := start;
    right_i := end - 1;
    while left_i <= right_i {
        idx := bvh.build_indices[left_i];
        c := aabb_center(bvh.edit_bounds[idx]);
        if bvh_axis_value(c, axis) < split_value {
            left_i += 1;
            continue;
        }

        tmp := bvh.build_indices[left_i];
        bvh.build_indices[left_i] = bvh.build_indices[right_i];
        bvh.build_indices[right_i] = tmp;
        right_i -= 1;
    }

    split := left_i;
    if split <= start || split >= end {
        split = start + count / 2;
    }

    left := bvh_build_range(start, split, depth + 1);
    right := bvh_build_range(split, end, depth + 1);

    bvh.nodes[node_index] = .{
        bounds = bounds,
        left = left,
        right = right,
        edit_index = -1,
    };
    return node_index;
}

edit_to_manip_object :: (edit_index: s32) -> Manip_Object {
    e := edits_cpu[edit_index];
    half_extents := e.half_extents;
    color := ifx e.op == SDF_OP_SUBTRACT then Vector4.{0.98, 0.42, 0.30, 1.0} else Vector4.{0.30, 0.88, 0.98, 1.0};
    if e.shape == SDF_SHAPE_SPHERE {
        half_extents = .{e.radius, e.radius, e.radius};
    }
    return .{
        name = tprint("edit_%", edit_index),
        position = e.position,
        rotation = .{x = e.rotation.x, y = e.rotation.y, z = e.rotation.z, w = e.rotation.w},
        scale = .{1.0, 1.0, 1.0},
        half_extents = half_extents,
        color = color,
    };
}

apply_manip_to_edit :: (edit_index: s32, obj: Manip_Object) {
    e := *edits_cpu[edit_index];
    e.position = obj.position;
    e.rotation = .{obj.rotation.x, obj.rotation.y, obj.rotation.z, obj.rotation.w};

    effective_half := Vector3.{
        obj.half_extents.x * obj.scale.x,
        obj.half_extents.y * obj.scale.y,
        obj.half_extents.z * obj.scale.z,
    };
    effective_half.x = max(effective_half.x, 0.02);
    effective_half.y = max(effective_half.y, 0.02);
    effective_half.z = max(effective_half.z, 0.02);
    if e.shape == SDF_SHAPE_SPHERE {
        r := max(max(effective_half.x, effective_half.y), effective_half.z);
        e.radius = max(r, 0.02);
        e.half_extents = .{e.radius, e.radius, e.radius};
    } else {
        e.half_extents = effective_half;
        e.radius = length(effective_half);
    }
    edits_cpu[edit_index] = e;
}

shape_label :: (shape: u32) -> string {
    if shape == SDF_SHAPE_BOX return "box";
    if shape == SDF_SHAPE_SPHERE return "sphere";
    return "unknown-shape";
}
