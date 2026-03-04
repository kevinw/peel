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
compute_classify_pipeline: Gpu_Pipeline;
compute_bake_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

brickmap_params_cpu: *Brickmap_Params;
brickmap_params_gpu: Gpu_Ptr;

brickmap_pointer_grid_cpu: []s32;
brickmap_lod_info_cpu: [BRICKMAP_LOD_COUNT] Brickmap_Lod_Info;
brickmap_edits_storage: [BRICKMAP_MAX_EDITS] SDF_Edit;
brickmap_edits_cpu: []SDF_Edit;
brickmap_dirty_storage: [BRICKMAP_MAX_DIRTY_BRICKS] Brick_Request;
brickmap_dirty_cpu: []Brick_Request;
brickmap_atlas_texture: Gpu_Texture;
brickmap_atlas_view: Gpu_Texture_View;
brickmap_atlas_linear_sampler: Gpu_Sampler;
brickmap_atlas_point_sampler: Gpu_Sampler;

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
brickmap_auto_edit_after: s32 = -1;
brickmap_auto_edit_done := false;
brickmap_log_updates := false;
brickmap_use_cache_raymarch := true;
brickmap_use_hw_interp := true;
brickmap_draw_brick_debug := false;
brickmap_debug_brick_limit: s32 = 420;
brickmap_show_lod0 := true;
brickmap_show_lod1 := false;
brickmap_show_atlas_overlay := false;
brickmap_show_atlas_fullscreen := false;
brickmap_show_pointer_grid_debug := false;
brickmap_bake_gradient_debug := false;
brickmap_skip_classify_debug := false;
brickmap_cache_debug_show_selected_lod := false;
brickmap_cache_debug_show_distance := false;
brickmap_cache_force_lod0 := false;
brickmap_atlas_debug_slice: float = 0.5;
brickmap_debug_autolog_once := false;
BRICKMAP_RANDOM_STARTUP_EDITS :: 20;
BRICKMAP_RANDOM_STARTUP_SEED  :: cast(u64) 0xB17C_A11A_5EED;

brickmap_gizmo_ctx: Gizmo.Gizmo_Context;
brickmap_gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, brickmap_vertex_main, brickmap_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for brickmap graphics shaders.");
    classify_source := cast([]u8) get_transpiled(.METAL, brickmap_classify_dirty_compute);
    assert(classify_source.count > 0, "Transpilation failed for brickmap classify compute shader.");
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

    compute_classify_pipeline = gpu_create_compute_pipeline(classify_source);
    assert(compute_classify_pipeline != 0, "Brickmap classify compute pipeline creation failed.");
    classify_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_classify_pipeline, classify_source, .METAL, brickmap_classify_dirty_compute);
    assert(classify_ok, "Brickmap classify compute pipeline hot-reload registration failed.");

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
    brickmap_pointer_grid_cpu = brickmap_params_cpu.pointer_grid;
    brickmap_edits_cpu = brickmap_edits_storage;
    brickmap_dirty_cpu = brickmap_dirty_storage;
    brickmap_params_cpu.camera_fov_y = PI / 3.0;
    brickmap_params_cpu.camera_tan_half_fov = tan(brickmap_params_cpu.camera_fov_y * 0.5);

    texture_result, brickmap_atlas_texture= := gpu_create_texture(.{
        type = ._3D,
        dimensions = .[BRICKMAP_ATLAS_DIM_X, BRICKMAP_ATLAS_DIM_Y, BRICKMAP_ATLAS_DIM_Z],
        format = .R32_SFLOAT,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("Brickmap atlas texture creation failed: %", texture_result));
    assert(brickmap_atlas_texture != 0, "Brickmap atlas texture handle invalid.");
    brickmap_atlas_view = gpu_texture_view(brickmap_atlas_texture);
    assert(brickmap_atlas_view != 0, "Brickmap atlas texture view creation failed.");
    brickmap_atlas_linear_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(brickmap_atlas_linear_sampler != 0, "Brickmap atlas linear sampler creation failed.");
    brickmap_atlas_point_sampler = gpu_create_sampler(.{
        min_filter = .NEAREST,
        mag_filter = .NEAREST,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(brickmap_atlas_point_sampler != 0, "Brickmap atlas point sampler creation failed.");
    brickmap_params_cpu.atlas_texture_index = cast(u32) brickmap_atlas_view - 1;
    brickmap_params_cpu.atlas_sampler_linear_index = cast(u32) brickmap_atlas_linear_sampler - 1;
    brickmap_params_cpu.atlas_sampler_point_index = cast(u32) brickmap_atlas_point_sampler - 1;
    log("BRICKMAP bindless indices tex=% linear_sampler=% point_sampler=%",
        brickmap_params_cpu.atlas_texture_index,
        brickmap_params_cpu.atlas_sampler_linear_index,
        brickmap_params_cpu.atlas_sampler_point_index);

    env_edit_after, env_edit_set := Env_Vars.try_parse_env_int("BRICKMAP_EDIT_AFTER");
    if env_edit_set && env_edit_after >= 0 brickmap_auto_edit_after = cast(s32) env_edit_after;

    env_log_updates, env_log_set := Env_Vars.try_parse_env_int("BRICKMAP_LOG");
    if env_log_set brickmap_log_updates = env_log_updates > 0;
    env_skip_classify, env_skip_set := Env_Vars.try_parse_env_int("BRICKMAP_SKIP_CLASSIFY");
    if env_skip_set brickmap_skip_classify_debug = env_skip_classify > 0;

    seed_initial_scene();
    rebuild_bvh();
    brickmap_params_cpu.atlas_alloc_next = 0;
    brickmap_update_lod_origins(true);
    brickmap_clear_cache();
    brickmap_mark_all_edits_dirty("init");
    brickmap_force_full_rebuild = false;
    if brickmap_log_updates {
        log("BRICKMAP init_dirty_complete pending=% atlas_used=%", brickmap_pending_dirty_count, brickmap_next_atlas_index);
    }

    brickmap_last_camera_pos = brickmap_camera.position;

    Gizmo.init(*brickmap_gizmo_ctx);
    gizmo_ok := Gizmo_Render.init(*brickmap_gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Brickmap gizmo renderer init failed.");
    Gizmo_Render.bind_gizmo(*brickmap_gizmo_render_ctx, *brickmap_gizmo_ctx);

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    gpu_free(brickmap_atlas_point_sampler);
    gpu_free(brickmap_atlas_linear_sampler);
    gpu_free_texture_view(brickmap_atlas_view);
    gpu_free(brickmap_atlas_texture);
    Gizmo_Render.deinit(*brickmap_gizmo_render_ctx);
    Gizmo.deinit(*brickmap_gizmo_ctx);
} @on_unload

brickmap_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{560.0, 420.0}, .FirstUseEver);
    if Begin("Brickmap", *brickmap_ui_open, flags = .NoCollapse) {
        Text("Sparse brickmap SDF raymarch prototype");
        Text("RMB look, WASDQE fly, Shift boost");
        Checkbox("Draw Debug Grid", *brickmap_draw_debug_grid);
        _ = toggle("Use Cache Raymarch", *brickmap_use_cache_raymarch, .{56.0, 0.0}, true, 0.09);
        _ = toggle("Use HW 3D Interp", *brickmap_use_hw_interp, .{56.0, 0.0}, true, 0.09);
        Checkbox("Atlas Overlay", *brickmap_show_atlas_overlay);
        Checkbox("Atlas Fullscreen Debug", *brickmap_show_atlas_fullscreen);
        Checkbox("Pointer Grid Debug", *brickmap_show_pointer_grid_debug);
        Checkbox("Bake Gradient Debug", *brickmap_bake_gradient_debug);
        Checkbox("Skip Classify (Debug)", *brickmap_skip_classify_debug);
        Checkbox("Cache Debug: Selected LOD", *brickmap_cache_debug_show_selected_lod);
        Checkbox("Cache Debug: Distance", *brickmap_cache_debug_show_distance);
        Checkbox("Cache Debug: Force LOD0", *brickmap_cache_force_lod0);
        SliderFloat("Atlas Slice", *brickmap_atlas_debug_slice, 0.0, 1.0);
        Checkbox("Draw Brick Debug", *brickmap_draw_brick_debug);
        Checkbox("Debug LOD0", *brickmap_show_lod0);
        Checkbox("Debug LOD1", *brickmap_show_lod1);
        Text("Edits: %", brickmap_params_cpu.edit_count);
        Text("Dirty bricks pending: %", brickmap_pending_dirty_count);
        Text("Dirty bricks after classify: %", brickmap_params_cpu.dirty_count);
        Text("Atlas bricks used: % / %", brickmap_next_atlas_index, BRICKMAP_MAX_BRICKS);
        Text("Pointer cells allocated: %", brickmap_count_allocated_cells());
        Separator();
        Text("GPU classify candidates: %", brickmap_params_cpu.debug_classify_candidates);
        Text("GPU classify surface: %", brickmap_params_cpu.debug_classify_surface);
        Text("GPU classify existing/new: % / %", brickmap_params_cpu.debug_classify_existing, brickmap_params_cpu.debug_classify_new_alloc);
        Text("GPU classify rejected(cap): %", brickmap_params_cpu.debug_classify_rejected_capacity);
        Text("GPU classify out_count: %", brickmap_params_cpu.debug_classify_out_count);
        Text("GPU bake bricks/voxels: % / %", brickmap_params_cpu.debug_bake_bricks_touched, brickmap_params_cpu.debug_bake_total_voxels);
        Text("GPU bake atlas min..max: % .. %", brickmap_params_cpu.debug_bake_min_atlas, brickmap_params_cpu.debug_bake_max_atlas);
        seen_count := cast(s32) min(brickmap_params_cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
        seen_min: s32 = 1 << 30;
        seen_max: s32 = -1;
        seen_nonzero: s32 = 0;
        for i: 0..seen_count-1 {
            v := cast(s32) brickmap_params_cpu.debug_bake_seen_atlas[i];
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
        Text("Auto edit after frame: %", brickmap_auto_edit_after);
        Text("Auto edit done: %", ifx brickmap_auto_edit_done then "yes" else "no");
        Separator();
        Text("Clip LOD0 origin brick: % % %", brickmap_lod_info_cpu[0].origin_brick_x, brickmap_lod_info_cpu[0].origin_brick_y, brickmap_lod_info_cpu[0].origin_brick_z);
        Text("Clip LOD1 origin brick: % % %", brickmap_lod_info_cpu[1].origin_brick_x, brickmap_lod_info_cpu[1].origin_brick_y, brickmap_lod_info_cpu[1].origin_brick_z);
        if Button("apply runtime edit") {
            brickmap_apply_runtime_edit();
        }
        Separator();
        Text("Edit List");
        edit_count := cast(s32) brickmap_params_cpu.edit_count;
        if BeginChild("brickmap_edit_list", .{0.0, 180.0}, .None) {
            if edit_count <= 0 {
                Text("  (no edits)");
            } else {
                for i: 0..edit_count-1 {
                    edit := brickmap_edits_cpu[i];
                    Text("#%  %  %  pos(%, %, %)  r=%  he(%, %, %)",
                        i,
                        brickmap_shape_label(edit.shape),
                        brickmap_op_label(edit.op),
                        edit.position.x, edit.position.y, edit.position.z,
                        edit.radius,
                        edit.half_extents.x, edit.half_extents.y, edit.half_extents.z);
                }
            }
        }
        EndChild();
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    gpu_next_atlas := cast(s32) brickmap_params_cpu.atlas_alloc_next;
    if gpu_next_atlas > brickmap_next_atlas_index {
        brickmap_next_atlas_index = gpu_next_atlas;
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);

    brickmap_ui();
    io := ImGui.GetIO();
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

    _ = editor_camera_update(*brickmap_camera, dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = right_down && !io.WantCaptureMouse);

    if !brickmap_debug_autolog_once && frame_count >= 2 {
        seen_count := cast(s32) min(brickmap_params_cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
        seen_min: s32 = 1 << 30;
        seen_max: s32 = -1;
        seen_nonzero: s32 = 0;
        for i: 0..seen_count-1 {
            v := cast(s32) brickmap_params_cpu.debug_bake_seen_atlas[i];
            if v < seen_min seen_min = v;
            if v > seen_max seen_max = v;
            if v > 0 seen_nonzero += 1;
        }
        if seen_count <= 0 {
            seen_min = 0;
            seen_max = 0;
        }

        log("BRICKMAP_GPU_DEBUG edits=% dirty_pending=% dirty_after=% atlas_used=%/% ptr_cells=% classify(cand=% surf=% exist=% new=% reject=% out=%) bake(bricks=% voxels=% atlas=%..% seen=%..% nonzero=%/%)",
            brickmap_params_cpu.edit_count,
            brickmap_pending_dirty_count,
            brickmap_params_cpu.dirty_count,
            brickmap_next_atlas_index, BRICKMAP_MAX_BRICKS,
            brickmap_count_allocated_cells(),
            brickmap_params_cpu.debug_classify_candidates,
            brickmap_params_cpu.debug_classify_surface,
            brickmap_params_cpu.debug_classify_existing,
            brickmap_params_cpu.debug_classify_new_alloc,
            brickmap_params_cpu.debug_classify_rejected_capacity,
            brickmap_params_cpu.debug_classify_out_count,
            brickmap_params_cpu.debug_bake_bricks_touched,
            brickmap_params_cpu.debug_bake_total_voxels,
            brickmap_params_cpu.debug_bake_min_atlas, brickmap_params_cpu.debug_bake_max_atlas,
            seen_min, seen_max, seen_nonzero, seen_count);
        brickmap_debug_autolog_once = true;
    }

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
    brickmap_params_cpu.use_cache_raymarch = ifx brickmap_use_cache_raymarch then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.use_hw_interp = ifx brickmap_use_hw_interp then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.atlas_debug_overlay = ifx brickmap_show_atlas_overlay then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.atlas_debug_fullscreen = ifx brickmap_show_atlas_fullscreen then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.pointer_grid_debug = ifx brickmap_show_pointer_grid_debug then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.bake_debug_gradient = ifx brickmap_bake_gradient_debug then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.cache_debug_show_selected_lod = ifx brickmap_cache_debug_show_selected_lod then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.cache_debug_show_distance = ifx brickmap_cache_debug_show_distance then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.cache_force_lod0 = ifx brickmap_cache_force_lod0 then cast(u32) 1 else cast(u32) 0;
    brickmap_params_cpu.atlas_debug_slice = clamp(brickmap_atlas_debug_slice, 0.0, 1.0);
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
        brickmap_params_cpu.dirty_atlas_index[i] = 0;
    }

    if brickmap_draw_brick_debug && dims_ok && win_w > 0 && win_h > 0 {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        view := editor_camera_make_view(*brickmap_camera);
        proj := make_projection_matrix(brickmap_params_cpu.camera_fov_y, viewport.x / max(viewport.y, 1.0), 0.05, 160.0);
        Gizmo_Render.gizmo_render_set_view_projection(*brickmap_gizmo_render_ctx, proj * view);
        brickmap_build_debug_gizmos();
    }

    brickmap_params_cpu.dirty_count = 0;
    bake_threads: s32 = 0;
    main_queue := gpu_get_queue(.MAIN, 0);
    if brickmap_pending_dirty_count > 0 {
        brickmap_params_cpu.dirty_count = cast(u32) brickmap_pending_dirty_count;
        brickmap_params_cpu.atlas_alloc_next = cast(u32) brickmap_next_atlas_index;

        if brickmap_skip_classify_debug {
            for i: 0..brickmap_pending_dirty_count-1 {
                brickmap_params_cpu.dirty_atlas_index[i] = cast(u32) i;
            }
            brickmap_params_cpu.debug_classify_out_count = cast(u32) brickmap_pending_dirty_count;
            brickmap_params_cpu.debug_bake_min_atlas = 0;
            brickmap_params_cpu.debug_bake_max_atlas = cast(u32) max(0, brickmap_pending_dirty_count - 1);
            if brickmap_next_atlas_index < brickmap_pending_dirty_count {
                brickmap_next_atlas_index = brickmap_pending_dirty_count;
                brickmap_params_cpu.atlas_alloc_next = cast(u32) brickmap_next_atlas_index;
            }
            bake_threads = brickmap_pending_dirty_count * BRICKMAP_BRICK_TEXELS;
        } else {
            result=, classify_cmd := gpu_start_command_recording(main_queue);
            assert(result == .SUCCESS);
            result = gpu_set_pipeline(classify_cmd, compute_classify_pipeline);
            assert(result == .SUCCESS, tprint("Brickmap classify set pipeline failed: %", result));
            gpu_dispatch_buffers(classify_cmd, .[brickmap_params_gpu], .[1, 1, 1]);
            gpu_submit(classify_cmd);
            gpu_queue_wait_idle(main_queue);

            gpu_next_atlas_after := cast(s32) brickmap_params_cpu.atlas_alloc_next;
            if gpu_next_atlas_after > brickmap_next_atlas_index {
                brickmap_next_atlas_index = gpu_next_atlas_after;
            }
            bake_threads = cast(s32) brickmap_params_cpu.dirty_count * BRICKMAP_BRICK_TEXELS;
        }
    }

    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if brickmap_pending_dirty_count > 0 {
        result = gpu_set_pipeline(cmd_buff, compute_bake_pipeline);
        assert(result == .SUCCESS, tprint("Brickmap bake set pipeline failed: %", result));
        dispatch_x := cast(u32) ((bake_threads + 63) / 64);
        if dispatch_x > 0 {
            gpu_dispatch_buffers(cmd_buff, .[brickmap_params_gpu], .[dispatch_x, 1, 1]);
            gpu_barrier(cmd_buff, .COMPUTE_SHADER, .PIXEL_SHADER);
        }

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

    if brickmap_draw_brick_debug && dims_ok && win_w > 0 && win_h > 0 {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*brickmap_gizmo_render_ctx, cmd_buff, *brickmap_gizmo_ctx, viewport, depth_mode = .NONE);
        assert(gizmo_draw_result == .SUCCESS, tprint("Brickmap gizmo draw failed: %", gizmo_draw_result));
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../editor_camera.jai";
#load "../ui/toggle_widget.jai";

Env_Vars :: #import "Env_Vars";
Input :: #import "Input";
ImGui :: #import "ImGui";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
#import "Math";
#import "Random";

seed_initial_scene :: () {
    count: s32 = 0;

    brickmap_add_sphere(*count, .{-2.1, 0.3, -3.8}, 1.1);
    brickmap_add_sphere(*count, .{1.8, -0.1, -4.9}, 1.4);
    brickmap_add_box(*count, .{0.0, 0.2, -6.7}, .{1.1, 0.9, 1.1}, .{0.18, 0.35, 0.05});
    brickmap_add_box(*count, .{-3.8, -0.2, -8.2}, .{0.9, 1.5, 0.9}, .{0.0, 0.42, 0.0});
    brickmap_add_sphere(*count, .{-0.1, 0.6, -6.7}, 0.85, op = SDF_OP_SUBTRACT);
    brickmap_add_box(*count, .{2.8, 0.7, -8.8}, .{1.7, 0.25, 0.7}, .{0.2, -0.3, 0.45});

    random_seed(BRICKMAP_RANDOM_STARTUP_SEED);
    for 0..BRICKMAP_RANDOM_STARTUP_EDITS-1 {
        shape: u32 = cast(u32) (ifx random_get_zero_to_one() < 0.5 then SDF_SHAPE_SPHERE else SDF_SHAPE_BOX);
        op: u32 = cast(u32) (ifx random_get_zero_to_one() < 0.82 then SDF_OP_UNION else SDF_OP_SUBTRACT);
        pos := Vector3.{
            random_get_within_range(-10.0, 10.0),
            random_get_within_range(-1.2, 3.0),
            random_get_within_range(-16.0, -2.0),
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
            brickmap_add_box(*count, pos, half_extents, euler, op = op);
        } else {
            radius := random_get_within_range(0.35, 1.65);
            brickmap_add_sphere(*count, pos, radius, op = op);
        }

        if count >= BRICKMAP_MAX_EDITS break;
    }

    brickmap_params_cpu.edit_count = cast(u32) count;
}

brickmap_apply_runtime_edit :: () {
    if brickmap_params_cpu.edit_count <= 0 return;

    old_bounds := brickmap_edit_bounds(0);

    // Animated CSG punch to validate edit->BVH->brickmap update path.
    brickmap_edits_cpu[0].position += .{1.35, 0.75, -0.55};
    brickmap_edits_cpu[0].op = SDF_OP_UNION;

    new_bounds := brickmap_edit_bounds(0);

    rebuild_bvh();
    brickmap_mark_dirty_aabb(old_bounds, "auto_edit_old");
    brickmap_mark_dirty_aabb(new_bounds, "auto_edit_new");

    if brickmap_log_updates {
        log("BRICKMAP runtime edit applied at frame=%", frame_count);
    }
}

rebuild_bvh :: () {
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
    for i: 0..brickmap_dirty_flags.count-1 {
        brickmap_dirty_flags[i] = false;
    }
    brickmap_next_atlas_index = 0;
    brickmap_params_cpu.atlas_alloc_next = 0;
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

                    bx := lx + info.origin_brick_x;
                    by := ly + info.origin_brick_y;
                    bz := lz + info.origin_brick_z;

                    if brickmap_pending_dirty_count >= BRICKMAP_MAX_DIRTY_BRICKS {
                        if brickmap_log_updates log_error("BRICKMAP dirty queue full; dropping brick updates.");
                        continue;
                    }

                    req := Brick_Request.{
                        lod = cast(u32) lod,
                        brick_x = bx,
                        brick_y = by,
                        brick_z = bz,
                        atlas_index = 0,
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

brickmap_count_allocated_cells :: () -> s32 {
    count: s32 = 0;
    for i: 0..brickmap_pointer_grid_cpu.count-1 {
        if brickmap_pointer_grid_cpu[i] >= 0 count += 1;
    }
    return count;
}

brickmap_build_debug_gizmos :: () {
    Gizmo.begin_frame(*brickmap_gizmo_ctx);
    if !brickmap_draw_brick_debug return;

    drawn: s32 = 0;
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        if lod == 0 && !brickmap_show_lod0 continue;
        if lod == 1 && !brickmap_show_lod1 continue;

        info := brickmap_lod_info_cpu[lod];
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
                    if drawn >= brickmap_debug_brick_limit return;
                    cell_local := brickmap_flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
                    cell := lod * BRICKMAP_GRID_CELLS + cell_local;
                    if brickmap_pointer_grid_cpu[cell] < 0 continue;

                    bx := lx + info.origin_brick_x;
                    by := ly + info.origin_brick_y;
                    bz := lz + info.origin_brick_z;
                    center := Vector3.{
                        (cast(float) bx + 0.5) * brick_world_size,
                        (cast(float) by + 0.5) * brick_world_size,
                        (cast(float) bz + 0.5) * brick_world_size,
                    };
                    Gizmo.draw_box(*brickmap_gizmo_ctx, center, half, color, 1.2);
                    drawn += 1;
                }
            }
        }
    }
}

brickmap_shape_label :: (shape: u32) -> string {
    if shape == SDF_SHAPE_BOX return "box";
    if shape == SDF_SHAPE_SPHERE return "sphere";
    return "unknown-shape";
}

brickmap_op_label :: (op: u32) -> string {
    if op == SDF_OP_UNION return "union";
    if op == SDF_OP_SUBTRACT return "subtract";
    if op == SDF_OP_INTERSECT return "intersect";
    return "unknown-op";
}
