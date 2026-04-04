
#load "../SGPU_App_Common.jai";
#load "../upscaler.jai";

#import "Jai-Shader-Transpiler";
#load "shaders/brickmap_shader.jai";
#load "brickmap_graph.jai";

// BRICK VISUAL FIDELITY TUNABLES
BASE_VOXEL :: 0.08;
INWARD_SAMPLED_BIAS :: 0.10;
HIT_EPSILON_VOXEL_SCALE :: 0.12;
BRICKMAP_PARAM_RING_SLOTS :: 32;
BRICKMAP_CLIPMAP_MARGIN_BRICKS :: BRICKMAP_GRID_RES / 4;


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
    scan_valid_cells: s32;
    scan_oob_atlas_refs: s32;
    scan_duplicate_atlas_refs: s32;
    scan_above_next_atlas_refs: s32;
    scan_negative_nonempty_refs: s32;
    scan_holes_below_next: s32;
    scan_referenced_slots: s32;
    scan_dirty_flag_cells: s32;
    scan_param_state_mismatches: s32;
    scan_owner_mismatches: s32;
    scan_owner_missing: s32;
    scan_valid_unpublished: s32;

    shift_preserved_cells: s32;
    shift_invalidated_cells: s32;
    shift_requeued_cells: s32;
    shift_dropped_cells: s32;
    enqueue_overflow: s32;
}

graphics_pipeline: Gpu_Pipeline;
temporal_graphics_pipeline: Gpu_Pipeline;
blit_pipeline: Gpu_Pipeline;
compute_recenter_pipeline: Gpu_Pipeline;
compute_clear_slot_owners_pipeline: Gpu_Pipeline;
compute_rebuild_slot_owners_pipeline: Gpu_Pipeline;
compute_reset_queues_pipeline: Gpu_Pipeline;
compute_full_rebuild_pipeline: Gpu_Pipeline;
compute_prepare_pipeline: Gpu_Pipeline;
compute_classify_pipeline: Gpu_Pipeline;
compute_prepare_dispatch_args_pipeline: Gpu_Pipeline;
compute_bake_pipeline: Gpu_Pipeline;
compute_publish_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
brickmap_compute_graph: Brickmap_Graph;

params_ring: Gpu_View(Brickmap_Params);
params: Gpu_Buffer(Brickmap_Params);
compute_params: Gpu_Buffer(Brickmap_Params);
render_params_ring: Gpu_View(Brickmap_Render_Params);
render_params: Gpu_Buffer(Brickmap_Render_Params);
brickmap_state_ring: Gpu_View(Brickmap_State);
brickmap_state: Gpu_Buffer(Brickmap_State);
brickmap_queues_ring: Gpu_View(Brickmap_Work_Queues);
brickmap_queues: Gpu_Buffer(Brickmap_Work_Queues);
brickmap_dispatch_args: Gpu_Buffer(Brickmap_Indirect_Dispatch_Pair);
blit_params_ring: Gpu_View(Brickmap_Blit_Params);
blit_params: Gpu_Buffer(Brickmap_Blit_Params);
params_guard_before: Gpu_View(u8);
params_guard_after: Gpu_View(u8);

pointer_grid_cpu: []s32;
pointer_grid_valid_cpu: []u32;
pointer_grid_publish_cpu: []u32;
pointer_grid_generation_cpu: []u32;
lod_info_cpu: [BRICKMAP_LOD_COUNT] Brickmap_Lod_Info;
edits_storage: [BRICKMAP_MAX_EDITS] SDF_Edit;
edits_cpu: []SDF_Edit;
atlas_texture: Gpu_Texture;
atlas_view: Gpu_Texture_View;
atlas_albedo_texture: Gpu_Texture;
atlas_albedo_view: Gpu_Texture_View;
atlas_linear_sampler: Gpu_Sampler;
atlas_point_sampler: Gpu_Sampler;
render_sampler: Gpu_Sampler;
render_point_sampler: Gpu_Sampler;
upscaler: MetalFX_Upscaler;
prev_view_proj: Matrix4 = Matrix4_Identity;

app: struct {
    camera: Editor_Camera = .{
        position = .{4.0, 2.0, 7.0},
        yaw = -0.55,
        pitch = -0.12,
        fov_y = PI / 3.0,
        move_speed = 7.0,
        boost_multiplier = 2.0,
        mouse_sensitivity = 0.0058,
        move_planar = false,
        pitch_min = -1.45,
        pitch_max = 1.45,
    };

    ui_open := true;
    use_cache_raymarch := true;
    use_hw_interp := true;
    show_atlas_overlay := false;
    show_atlas_fullscreen := false;
    show_pointer_grid_debug := false;
    bake_gradient_debug := false;
    cache_debug_show_selected_lod := false;
    cache_debug_show_distance := false;
    debug_force_flat_color := false;
    cache_force_lod0 := false;
    auto_fly_forward := false;
    auto_fly_speed: float = 8.0;
    atlas_debug_slice: float = 0.5;
    render_scale: float = 0.35;
    blit_nearest := false;
};

bvh: Brickmap_BVH;
next_atlas_index: s32;
pending_dirty_count: s32;
dirty_backlog_count: s32;
last_camera_pos: Vector3;
force_full_rebuild := true;
pending_full_rebuild := false;
gpu_full_rebuild_pending := false;
atlas_capacity_reached := false;
brickmap_active_cache_slot: s32;
control_mode: enum { Player; Editor; } = .Player;
physics_gizmos_enabled := false;
player_controller: Character_Controller;
player_edit_index: s32 = -1;
player_camera_eye_height: float = 1.25;
player_move_speed: float = 7.0;
player_push_radius: float = 1.45;
player_push_strength: float = 18.0;
player_pull_strength: float = 4.5;
physics_body_ids: [BRICKMAP_MAX_EDITS] BodyID;
physics_body_active: [BRICKMAP_MAX_EDITS] bool;
physics_body_gravitate: [BRICKMAP_MAX_EDITS] bool;
physics_body_shape_cache: [BRICKMAP_MAX_EDITS] SDF_Shape;
physics_body_radius_cache: [BRICKMAP_MAX_EDITS] float;
physics_body_half_extents_cache: [BRICKMAP_MAX_EDITS] Vector3;
physics_sync_suppress_edit: s32 = -1;
physics_step_dirty_accum_valid := false;
physics_step_dirty_bounds: AABB;

auto_edit_after: s32 = -1;
auto_edit_done := false;
auto_drag_near_camera := false;
auto_drag_started := false;
auto_drag_done := false;
auto_drag_start_frame: s32 = 4;
auto_drag_duration_frames: s32 = 12;
auto_drag_edit_index: s32 = -1;
auto_drag_from_pos: Vector3;
auto_drag_to_pos: Vector3;
log_updates := false;
draw_brick_debug := false;
debug_brick_limit: s32 = 420;
skip_classify_debug := false;
freeze_clipmap := false;
experimental_recenter_reuse := true;
log_validation_every_frame := false;
debug_wait_idle_every_frame := false;
debug_strict_compute_sync := false;
debug_render_direct_swapchain := false;
debug_autolog_once := false;
guard_corruption_count: s32;
guard_corruption_reported := false;
bindless_index_logged_once := false;
BRICKMAP_RANDOM_STARTUP_EDITS :: 520;
BRICKMAP_RANDOM_STARTUP_SEED  :: cast(u64) 0xB17C_A11A_5EED;

gizmo_ctx: Gizmo.Gizmo_Context;
gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;
manip_ctx: Manip_Context;
manip_objects: [..]Manip_Object;
edit_manip_enabled := true;
selected_edit: s32 = -1;
hovered_edit: s32 = -1;
left_was_down := false;
last_pick_edit: s32 = -1;
last_pick_time: float64 = -1000.0;
orbit_drag_active := false;
orbit_target: Vector3;
orbit_distance: float = 6.0;
orbit_prev_mouse: Vector2;
orbit_have_prev_mouse := false;
focus_active := false;
focus_from_pos: Vector3;
focus_to_pos: Vector3;
focus_from_yaw: float;
focus_to_yaw: float;
focus_from_pitch: float;
focus_to_pitch: float;
focus_t: float;
focus_duration: float = 0.25;
validation_frame: Brickmap_Validation_Counters;
validation_total: Brickmap_Validation_Counters;
validation_max_nonempty_cells: s32;
cpu_classify_wait_last_ms: float;
cpu_classify_wait_avg_ms: float;
cpu_bake_wait_last_ms: float;
cpu_bake_wait_avg_ms: float;
cpu_offscreen_wait_last_ms: float;
cpu_offscreen_wait_avg_ms: float;
cpu_classify_encode_last_ms: float;
cpu_classify_encode_avg_ms: float;
cpu_bake_encode_last_ms: float;
cpu_bake_encode_avg_ms: float;
cpu_offscreen_encode_last_ms: float;
cpu_offscreen_encode_avg_ms: float;
cpu_present_encode_last_ms: float;
cpu_present_encode_avg_ms: float;
last_classify_graph_stats: Brickmap_Graph_Stats;
last_bake_graph_stats: Brickmap_Graph_Stats;
validation_first_mismatch_cell: s32;
validation_first_mismatch_slot: s32;
validation_first_mismatch_expect_lod: s32;
validation_first_mismatch_expect_bx: s32;
validation_first_mismatch_expect_by: s32;
validation_first_mismatch_expect_bz: s32;
validation_first_mismatch_owner_lod: s32;
validation_first_mismatch_owner_bx: s32;
validation_first_mismatch_owner_by: s32;
validation_first_mismatch_owner_bz: s32;

on_dll_init :: () {
    using app;
    init(*brickmap_compute_graph);

    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    };

    SHR.gfx_pipeline(*graphics_pipeline, raster_desc, brickmap_vertex_main, brickmap_fragment_main);
    temporal_raster_desc := raster_desc;
    temporal_raster_desc.color_targets = .[
        .{format = .B8G8R8A8_UNORM},
        .{format = .R16G16_SFLOAT},
        .{format = .R16_SFLOAT},
    ];

    SHR.gfx_pipeline(*temporal_graphics_pipeline, temporal_raster_desc, brickmap_vertex_main, brickmap_temporal_fragment_main);
    SHR.gfx_pipeline(*blit_pipeline, raster_desc, brickmap_blit_vertex_main, brickmap_blit_fragment_main);

    SHR.compute_pipeline(*compute_recenter_pipeline, brickmap_recenter_compute);
    SHR.compute_pipeline(*compute_clear_slot_owners_pipeline, brickmap_clear_slot_owners_compute);
    SHR.compute_pipeline(*compute_rebuild_slot_owners_pipeline, brickmap_rebuild_slot_owners_compute);
    SHR.compute_pipeline(*compute_reset_queues_pipeline, brickmap_reset_queues_compute);
    SHR.compute_pipeline(*compute_full_rebuild_pipeline, brickmap_full_rebuild_cells_compute);
    SHR.compute_pipeline(*compute_prepare_pipeline, brickmap_prepare_dirty_compute);
    SHR.compute_pipeline(*compute_classify_pipeline, brickmap_classify_dirty_compute);
    SHR.compute_pipeline(*compute_prepare_dispatch_args_pipeline, brickmap_prepare_dispatch_args_compute);
    SHR.compute_pipeline(*compute_bake_pipeline, brickmap_bake_compute);
    SHR.compute_pipeline(*compute_publish_pipeline, brickmap_publish_compute);

    arena_bytes := 256 * 1024 * 1024; // TODO: calculate this based on our
    gpu_arena = gpu_make_arena(arena_bytes, label = "brickmap arena");
    assert(gpu_arena.cpu != null, "Brickmap arena allocation failed.");

    // Keep params in a deeper ring than SGPU_FRAMES_IN_FLIGHT; render + blit + UI can leave
    // transient parameter reads live long enough that a 3-slot ring is too aggressive on Metal.
    blit_params_ring = gpu_alloc_view(*gpu_arena, Brickmap_Blit_Params, BRICKMAP_PARAM_RING_SLOTS);
    params_guard_before = gpu_alloc_view(*gpu_arena, u8, 4096);
    params_ring = gpu_alloc_view(*gpu_arena, Brickmap_Params, BRICKMAP_PARAM_RING_SLOTS);
    render_params_ring = gpu_alloc_view(*gpu_arena, Brickmap_Render_Params, BRICKMAP_PARAM_RING_SLOTS);
    params_guard_after = gpu_alloc_view(*gpu_arena, u8, 4096);
    brickmap_state_ring = gpu_alloc_view(*gpu_arena, Brickmap_State, 2);
    brickmap_queues_ring = gpu_alloc_view(*gpu_arena, Brickmap_Work_Queues, 2);
    brickmap_dispatch_args = gpu_alloc_buffer(*gpu_arena, Brickmap_Indirect_Dispatch_Pair);
    compute_params = gpu_alloc_buffer(*gpu_arena, Brickmap_Params);

    assert(params_ring.cpu.data != null, "Brickmap params ring alloc failed.");
    assert(compute_params.cpu != null, "Brickmap compute params alloc failed.");
    assert(render_params_ring.cpu.data != null, "Brickmap render params ring alloc failed.");
    assert(blit_params_ring.cpu.data != null, "Brickmap blit params ring alloc failed.");
    assert(params_guard_before.cpu.data != null, "Brickmap params before-guard alloc failed.");
    assert(params_guard_after.cpu.data != null, "Brickmap params after-guard alloc failed.");
    assert(brickmap_dispatch_args.cpu != null, "Brickmap dispatch args alloc failed.");
    assert(brickmap_state_ring.cpu.data != null, "Brickmap state alloc failed.");
    assert(brickmap_queues_ring.cpu.data != null, "Brickmap work queues alloc failed.");

    params = brickmap_params_ring_slot(params_ring, 0);
    render_params = brickmap_params_ring_slot(render_params_ring, 0);
    blit_params = brickmap_params_ring_slot(blit_params_ring, 0);

    for i: 0..BRICKMAP_PARAM_RING_SLOTS-1 {
        params_ring.cpu[i] = .{};
        render_params_ring.cpu[i] = .{};
        blit_params_ring.cpu[i] = .{};
    }
    for i: 0..1 {
        brickmap_state_ring.cpu[i] = .{};
        brickmap_queues_ring.cpu[i] = .{};
    }
    params.cpu.* = .{};
    compute_params.cpu.* = .{};
    render_params.cpu.* = .{};
    init_params_guards();
    set_active_cache_slot(0);
    edits_cpu = edits_storage;
    params.cpu.camera_fov_y = camera.fov_y;
    params.cpu.camera_tan_half_fov = tan(params.cpu.camera_fov_y * 0.5);

    texture_result, atlas_texture= := gpu_create_texture(.{
        type = ._3D,
        dimensions = .[BRICKMAP_ATLAS_DIM_X, BRICKMAP_ATLAS_DIM_Y, BRICKMAP_ATLAS_DIM_Z],
        format = .R16_SFLOAT,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("Brickmap atlas texture creation failed: %", texture_result));
    assert(atlas_texture != 0, "Brickmap atlas texture handle invalid.");
    atlas_view = gpu_texture_view(atlas_texture);
    assert(atlas_view != 0, "Brickmap atlas texture view creation failed.");
    texture_result, atlas_albedo_texture = gpu_create_texture(.{
        type = ._3D,
        dimensions = .[BRICKMAP_ATLAS_DIM_X, BRICKMAP_ATLAS_DIM_Y, BRICKMAP_ATLAS_DIM_Z],
        format = .R8G8B8A8_UNORM,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("Brickmap atlas albedo texture creation failed: %", texture_result));
    assert(atlas_albedo_texture != 0, "Brickmap atlas albedo texture handle invalid.");
    atlas_albedo_view = gpu_texture_view(atlas_albedo_texture);
    assert(atlas_albedo_view != 0, "Brickmap atlas albedo texture view creation failed.");
    atlas_linear_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR, mag_filter = .LINEAR, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(atlas_linear_sampler != 0, "Brickmap atlas linear sampler creation failed.");
    atlas_point_sampler = gpu_create_sampler(.{
        min_filter = .NEAREST, mag_filter = .NEAREST, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(atlas_point_sampler != 0, "Brickmap atlas point sampler creation failed.");
    params.cpu.atlas_texture_index = gpu_texture_view_index(atlas_view);
    params.cpu.atlas_albedo_texture_index = gpu_texture_view_index(atlas_albedo_view);
    params.cpu.atlas_sampler_linear_index = cast(u32) atlas_linear_sampler - 1;
    params.cpu.atlas_sampler_point_index = cast(u32) atlas_point_sampler - 1;
    fill_render_params_from_compute_params();
    render_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR, mag_filter = .LINEAR, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(render_sampler != 0, "Brickmap render sampler creation failed.");
    render_point_sampler = gpu_create_sampler(.{
        min_filter = .NEAREST, mag_filter = .NEAREST, mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(render_point_sampler != 0, "Brickmap render point sampler creation failed.");
    prev_view_proj = Matrix4_Identity;
    init(*upscaler, "PEEL_BRICKMAP_UPSCALER", .SPATIAL);

    try_parse_env_int("BRICKMAP_EDIT_AFTER", *auto_edit_after);
    try_parse_env_int("BRICKMAP_LOG", *log_updates);
    try_parse_env_int("BRICKMAP_SKIP_CLASSIFY", *skip_classify_debug);
    try_parse_env_int("BRICKMAP_AUTO_FLY_FORWARD", *auto_fly_forward);
    try_parse_env_int("BRICKMAP_AUTO_FLY_SPEED", *auto_fly_speed);
    try_parse_env_int("BRICKMAP_AUTO_DRAG_NEAR_CAMERA", *auto_drag_near_camera);
    try_parse_env_int("BRICKMAP_AUTO_DRAG_START", *auto_drag_start_frame);
    try_parse_env_int("BRICKMAP_AUTO_DRAG_FRAMES", *auto_drag_duration_frames);
    try_parse_env_int("BRICKMAP_FREEZE_CLIPMAP", *freeze_clipmap);
    try_parse_env_int("BRICKMAP_EXPERIMENTAL_RECENTER_REUSE", *experimental_recenter_reuse);
    try_parse_env_int("BRICKMAP_LOG_VALIDATION", *log_validation_every_frame);
    try_parse_env_int("BRICKMAP_DEBUG_WAIT_IDLE", *debug_wait_idle_every_frame);
    try_parse_env_int("BRICKMAP_DEBUG_STRICT_COMPUTE_SYNC", *debug_strict_compute_sync);
    try_parse_env_int("BRICKMAP_DEBUG_DIRECT_SWAPCHAIN", *debug_render_direct_swapchain);
    try_parse_env_int("BRICKMAP_BLIT_NEAREST", *blit_nearest);

    seed_initial_scene();
    rebuild_bvh();
    params.cpu.atlas_alloc_next = 0;
    update_lod_origins(true);
    clear_cache();
    init_brickmap_physics();
    force_full_rebuild = true;
    if log_updates {
        log("BRICKMAP init_dirty_complete pending=% atlas_used=%", pending_dirty_count, next_atlas_index);
    }

    // Seed all frame-ring slots with initialized state so first use of any slot is valid.
    for i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
        params_ring.cpu[i] = params.cpu.*;
        blit_params_ring.cpu[i] = blit_params.cpu.*;
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
    deinit_brickmap_physics();
    deinit(*upscaler);
    gpu_free(render_sampler);
    gpu_free(render_point_sampler);
    gpu_free(atlas_point_sampler);
    gpu_free(atlas_linear_sampler);
    gpu_free_texture_view(atlas_albedo_view);
    gpu_free(atlas_albedo_texture);
    gpu_free_texture_view(atlas_view);
    gpu_free(atlas_texture);
    array_free(manip_objects);
    Gizmo_Render.deinit(*gizmo_render_ctx);
    Gizmo.deinit(*gizmo_ctx);
} @on_unload

ui :: () {
    using app;
    if !app_ui_enabled return;
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{560.0, 420.0}, .FirstUseEver);
    if Begin("Brickmap", *ui_open) {
        Text("Sparse brickmap SDF raymarch prototype");
        Text("P toggles Player/Editor. Player: RMB look, WASD move, Space jump.");
        Text("Editor: RMB look, Alt+LMB orbit, WASDQE fly, Shift boost");
        is_player := control_mode == .Player;
        if toggle("Player Mode (P)", *is_player) {
            control_mode = ifx is_player then .Player else .Editor;
        }
        _ = toggle("Use Cache Raymarch", *use_cache_raymarch, .{56.0, 0.0}, true, 0.09);
        _ = toggle("Use HW 3D Interp", *use_hw_interp, .{56.0, 0.0}, true, 0.09);
        SliderFloat("Render Scale", *render_scale, 0.25, 1.0);
        do_ui(*upscaler);
        Checkbox("Blit Nearest (No Filter)", *blit_nearest);
        Text("Render target: % x %", upscaler.render_width, upscaler.render_height);
        Checkbox("Atlas Overlay", *show_atlas_overlay);
        if show_atlas_overlay {
            SliderFloat("Atlas Slice", *atlas_debug_slice, 0.0, 1.0);
            Checkbox("Atlas Fullscreen Debug", *show_atlas_fullscreen);
        }
        Checkbox("Pointer Grid Debug", *show_pointer_grid_debug);
        Checkbox("Bake Gradient Debug", *bake_gradient_debug);
        Checkbox("Skip Classify (Debug)", *skip_classify_debug);
        Checkbox("Debug Wait Idle Every Frame", *debug_wait_idle_every_frame);
        Checkbox("Debug Strict Compute Sync", *debug_strict_compute_sync);
        Checkbox("Debug Direct Swapchain", *debug_render_direct_swapchain);
        Checkbox("Debug Force Flat Color", *debug_force_flat_color);
        Checkbox("Cache Debug: Selected LOD", *cache_debug_show_selected_lod);
        Checkbox("Cache Debug: Distance", *cache_debug_show_distance);
        Checkbox("Cache Debug: Force LOD0", *cache_force_lod0);
        Checkbox("Draw Brick Debug", *draw_brick_debug);
        Checkbox("Edit Manip", *edit_manip_enabled);
        Checkbox("Physics Gizmos", *physics_gizmos_enabled);
        Physics.debug_draw_enabled = physics_gizmos_enabled;
        Text("Selected edit: %", selected_edit);
        Text("Hovered edit: %", hovered_edit);
        Text("Control Mode: %", control_mode);
        if edit_manip_enabled {
            Text("Manip mode/space: % / %", manip_ctx.mode, manip_ctx.space);
        }
        if selected_edit >= 0 && cast(s64) selected_edit < edits_cpu.count {
            Separator();
            Text("Inspector");
            idx := cast(s64) selected_edit;
            old_bounds := edit_bounds(selected_edit);
            changed := false;

            sphere_selected := edits_cpu[idx].shape == .Sphere;
            box_selected := edits_cpu[idx].shape == .Box;
            if RadioButton("Sphere", sphere_selected) {
                edits_cpu[idx].shape = .Sphere;
                changed = true;
            }
            SameLine();
            if RadioButton("Box", box_selected) {
                edits_cpu[idx].shape = .Box;
                changed = true;
            }

            blend := edits_cpu[idx].blend;
            if SliderFloat("Blend", *blend, 0.0, 1.0) {
                edits_cpu[idx].blend = blend;
                changed = true;
            }

            if changed {
                sync_edit_body_from_edit(selected_edit);
                new_bounds := edit_bounds(selected_edit);
                rebuild_bvh();
                mark_edit_change_dirty(old_bounds, new_bounds, "inspector_edit");
            }
        }
        if TreeNode("Debug Info") {
            defer TreePop();
            Text("Edits: %", params.cpu.edit_count);
            avg_leaf_depth := ifx bvh.leaf_count > 0 then cast(float) bvh.leaf_depth_sum / cast(float) bvh.leaf_count else 0.0;
            Text("BVH nodes/leaves: % / %", bvh.node_count, bvh.leaf_count);
            Text("BVH depth max/avg_leaf: % / %", bvh.max_depth, avg_leaf_depth);
            Text("Dirty bricks pending: %", pending_dirty_count);
            Text("Dirty backlog (flags): %", dirty_backlog_count);
            Text("Dirty bricks after classify: %", params.cpu.dirty_count);
            Text("Atlas bricks used: % / %", next_atlas_index, BRICKMAP_MAX_BRICKS);
            Text("Pointer cells allocated: %", count_allocated_cells());
            Text("Params guard corruption count: %", guard_corruption_count);
            Separator();
            {
                using params.cpu;
                Text("GPU classify candidates: %", debug_classify_candidates);
                Text("GPU classify surface: %", debug_classify_surface);
                Text("GPU classify existing/new: % / %", debug_classify_existing, debug_classify_new_alloc);
                Text("GPU classify rejected(cap): %", debug_classify_rejected_capacity);
                Text("GPU classify out_count: %", debug_classify_out_count);
                Text("GPU bake bricks/voxels: % / %", debug_bake_bricks_touched, debug_bake_total_voxels);
                seen_count := cast(s32) min(params.cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
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
            Separator();
            Text("CPU wait ms classify/bake/offscreen: % / % / %",
                cpu_classify_wait_avg_ms,
                cpu_bake_wait_avg_ms,
                cpu_offscreen_wait_avg_ms);
            Text("CPU encode ms classify/bake/offscreen/present: % / % / % / %",
                cpu_classify_encode_avg_ms,
                cpu_bake_encode_avg_ms,
                cpu_offscreen_encode_avg_ms,
                cpu_present_encode_avg_ms);
            if TreeNode("Graph Pass Timings") {
                defer TreePop();
                Text("Classify graph total encode/wait: % / %", last_classify_graph_stats.encode_ms, last_classify_graph_stats.wait_ms);
                for i: 0..last_classify_graph_stats.pass_count-1 {
                    if i >= BRICKMAP_GRAPH_MAX_STATS_PASSES break;
                    Text("%  % / %", last_classify_graph_stats.pass_names[i], last_classify_graph_stats.pass_encode_ms[i], last_classify_graph_stats.pass_wait_ms[i]);
                }
                Separator();
                Text("Bake graph total encode/wait: % / %", last_bake_graph_stats.encode_ms, last_bake_graph_stats.wait_ms);
                for i: 0..last_bake_graph_stats.pass_count-1 {
                    if i >= BRICKMAP_GRAPH_MAX_STATS_PASSES break;
                    Text("%  % / %", last_bake_graph_stats.pass_names[i], last_bake_graph_stats.pass_encode_ms[i], last_bake_graph_stats.pass_wait_ms[i]);
                }
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
            edit_count := cast(s32) params.cpu.edit_count;
            if BeginChild("brickmap_edit_list", .{0.0, 180.0}, .None) {
                if edit_count <= 0 {
                    Text("  (no edits)");
                } else {
                    for i: 0..edit_count-1 {
                        using edit := edits_cpu[i];
                        Text("#%  %  %  pos(%)  r=%  he(%)",
                            i,
                            shape,
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
    using app;
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    // Known-good baseline: the brickmap cache/state buffers are shared and mutated on CPU
    // every frame. Until we have a stricter resource lifetime model, force the GPU idle
    // before touching them so render/compute cannot observe partially updated state.
    main_queue := gpu_get_queue(.MAIN, 0);
    gpu_queue_wait_idle(main_queue);

    // Known-good baseline: use a single params slot. The brickmap cache/state still
    // needs to follow the active cache slot after a recenter preserve step.
    params = brickmap_params_ring_slot(params_ring, 0);
    render_params = brickmap_params_ring_slot(render_params_ring, 0);
    blit_params = brickmap_params_ring_slot(blit_params_ring, 0);
    set_active_cache_slot(brickmap_active_cache_slot);
    sync_params_pointer_grid_from_state();
    if debug_wait_idle_every_frame {
        gpu_queue_wait_idle(main_queue);
    }

    gpu_next_atlas := cast(s32) params.cpu.atlas_alloc_next;
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
    alt_down := (Input.input_button_states[Input.Key_Code.ALT] & .DOWN) != 0;
    left_pressed := left_down && !left_was_down;
    left_released := !left_down && left_was_down;
    left_was_down = left_down;

    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;
        if key_code == {
        case #char "P";
            if control_mode == .Player {
                control_mode = .Editor;
            } else {
                control_mode = .Player;
            }
        case #char "1";
            if !edit_manip_enabled || control_mode != .Editor continue;
            manip_ctx.mode = .TRANSLATE;
        case #char "2";
            if !edit_manip_enabled || control_mode != .Editor continue;
            manip_ctx.mode = .ROTATE;
        case #char "3";
            if !edit_manip_enabled || control_mode != .Editor continue;
            manip_ctx.mode = .SCALE;
        case #char "4";
            if !edit_manip_enabled || control_mode != .Editor continue;
            manip_ctx.space = .WORLD;
        case #char "5";
            if !edit_manip_enabled || control_mode != .Editor continue;
            manip_ctx.space = .LOCAL;
        }
    }

    orbit_start := alt_down && left_pressed && !io.WantCaptureMouse && !right_down && mouse_ok && dims_ok && win_w > 0 && win_h > 0;
    if orbit_start {
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
        ray_origin, ray_dir, ray_ok := mouse_world_ray(
            .{cast(float) win_w, cast(float) win_h}, tan((PI / 3.0) * 0.5),
            camera.position, cam_forward, cam_right, cam_up,
            .{cast(float) mx, cast(float) my}, mouse_ok);
        pick_i: s32 = -1;
        if ray_ok {
            pick_i = pick_edit_from_bvh(ray_origin, ray_dir);
        }
        if pick_i >= 0 {
            focus_center, _ := edit_focus_center_radius(pick_i);
            orbit_target = focus_center;
        } else if selected_edit >= 0 && cast(s64) selected_edit < edits_cpu.count {
            focus_center, _ := edit_focus_center_radius(selected_edit);
            orbit_target = focus_center;
        } else {
            orbit_target = camera.position + cam_forward * 8.0;
        }
        orbit_distance = max(distance(camera.position, orbit_target), 0.6);
        orbit_prev_mouse = .{cast(float) mx, cast(float) my};
        orbit_have_prev_mouse = true;
        orbit_drag_active = true;
        focus_active = false;
    }

    if orbit_drag_active {
        if !alt_down || !left_down || io.WantCaptureMouse || !mouse_ok {
            orbit_drag_active = false;
            orbit_have_prev_mouse = false;
        } else {
            orbit_update_camera(.{cast(float) mx, cast(float) my});
        }
    }

    camera_input: Editor_Camera_Update_Result;
    if control_mode == .Editor {
        camera_input = editor_camera_update(*camera, dt, mx, my, mouse_ok,
            allow_move = !io.WantTextInput && !orbit_drag_active,
            allow_look = right_down && !io.WantCaptureMouse && !orbit_drag_active,
            allow_zoom = !io.WantCaptureMouse && !orbit_drag_active);
    } else {
        camera_input = .{};
    }
    if focus_active {
        if orbit_drag_active || right_down || camera_input.moved || camera_input.looked {
            focus_active = false;
        } else {
            focus_update_camera(dt);
        }
    }
    if auto_fly_forward && control_mode == .Editor {
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
        camera.position += cam_forward * (auto_fly_speed * cast(float) dt);
    }

    if !debug_autolog_once && frame_count >= 2 {
        seen_count := cast(s32) min(params.cpu.debug_classify_out_count, cast(u32) BRICKMAP_MAX_DIRTY_BRICKS);
        seen_min: s32 = 1 << 30;
        seen_max: s32 = -1;
        seen_nonzero: s32 = 0;
        for i: 0..seen_count-1 {
            v := cast(s32) params.cpu.debug_bake_seen_atlas[i];
            if v < seen_min seen_min = v;
            if v > seen_max seen_max = v;
            if v > 0 seen_nonzero += 1;
        }
        if seen_count <= 0 {
            seen_min = 0;
            seen_max = 0;
        }

        using params.cpu;
        log("BRICKMAP_GPU_DEBUG edits=% dirty_pending=% dirty_after=% atlas_used=%/% ptr_cells=% classify(cand=% surf=% exist=% new=% reject=% out=%) bake(bricks=% voxels=% seen=%..% nonzero=%/%)",
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
            seen_min, seen_max, seen_nonzero, seen_count);
        debug_autolog_once = true;
    }

    if frame_count == auto_edit_after && !auto_edit_done {
        apply_runtime_edit();
        auto_edit_done = true;
    }
    if auto_drag_near_camera && !auto_drag_done {
        update_auto_drag_repro();
    }

    camera_moved := distance(camera.position, last_camera_pos) > 0.35;
    if camera_moved {
        last_camera_pos = camera.position;
    }

    can_recenter := camera_moved;
    if atlas_capacity_reached && dirty_backlog_count > BRICKMAP_MAX_DIRTY_BRICKS / 2 {
        can_recenter = false;
    }
    recenter_pending := update_lod_origins(can_recenter);

    if force_full_rebuild || pending_full_rebuild {
        perform_pending_full_rebuild();
        recenter_pending = false;
    }

    render_scale = clamp(render_scale, 0.25, 1.0);
    if dims_ok && win_w > 0 && win_h > 0 {
        if debug_render_direct_swapchain {
            params.cpu.resolution = .{cast(float) win_w, cast(float) win_h};
        } else {
            if !ensure_render_target(*upscaler, win_w, win_h, render_scale) {
                return;
            }
            params.cpu.resolution = .{cast(float) upscaler.render_width, cast(float) upscaler.render_height};
            if upscaler.mode == .NONE {
                blit_params.cpu.source_texture_index = gpu_texture_view_index(upscaler.render_view);
                blit_params.cpu.source_sampler_index = cast(u32) blit_sampler_handle() - 1;
                log_bindless_indices_once();
            }
        }
    }
    params.cpu.time = cast(float) time;
    to_u32 :: (val: bool) -> u32 #expand { if val { return 1; } else { return 0; } }  // TODO
    params.cpu.use_cache_raymarch = to_u32(use_cache_raymarch);
    params.cpu.use_hw_interp = to_u32(use_hw_interp);
    params.cpu.atlas_debug_overlay = to_u32(show_atlas_overlay);
    params.cpu.atlas_debug_fullscreen = to_u32(show_atlas_fullscreen);
    params.cpu.pointer_grid_debug = to_u32(show_pointer_grid_debug);
    params.cpu.bake_debug_gradient = to_u32(bake_gradient_debug);
    params.cpu.cache_debug_show_selected_lod = to_u32(cache_debug_show_selected_lod);
    params.cpu.cache_debug_show_distance = to_u32(cache_debug_show_distance);
    params.cpu.debug_force_flat_color = to_u32(debug_force_flat_color);
    params.cpu.cache_force_lod0 = to_u32(cache_force_lod0);
    params.cpu.frame_index = cast(u32) frame_count;
    params.cpu.atlas_debug_slice = clamp(atlas_debug_slice, 0.0, 1.0);
    params.cpu.camera_pos = camera.position;
    params.cpu.camera_fov_y = camera.fov_y;
    params.cpu.camera_tan_half_fov = tan(params.cpu.camera_fov_y * 0.5);
    editor_camera_basis(*camera, *params.cpu.camera_forward, *params.cpu.camera_right, *params.cpu.camera_up);
    aspect := ifx dims_ok && win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    current_view := editor_camera_make_view(*camera);
    current_proj := make_projection_matrix(params.cpu.camera_fov_y, aspect, 0.05, 160.0);
    current_view_proj := current_proj * current_view;
    if !upscaler.temporal_history_valid {
        prev_view_proj = current_view_proj;
    }
    params.cpu.view_proj = current_view_proj;
    params.cpu.prev_view_proj = prev_view_proj;
    if !debug_render_direct_swapchain && upscaler.render_view == 0 {
        return;
    }
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        info := lod_info_cpu[lod];
        params.cpu.lod_origin_brick_x[lod] = info.origin_brick.x;
        params.cpu.lod_origin_brick_y[lod] = info.origin_brick.y;
        params.cpu.lod_origin_brick_z[lod] = info.origin_brick.z;
        params.cpu.lod_voxel_size[lod] = info.voxel_size;
    }
    fill_render_params_from_compute_params();
    hovered_edit = -1;
    draw_any_gizmo := (draw_brick_debug || (edit_manip_enabled && control_mode == .Editor) || physics_gizmos_enabled) && dims_ok && win_w > 0 && win_h > 0;
    if draw_any_gizmo {
        viewport := Vector2.{cast(float) win_w, cast(float) win_h};
        view := editor_camera_make_view(*camera);
        proj := make_projection_matrix(params.cpu.camera_fov_y, viewport.x / max(viewport.y, 1.0), 0.05, 160.0);
        Gizmo_Render.gizmo_render_set_view_projection(*gizmo_render_ctx, proj * view);
        Gizmo.begin_frame(*gizmo_ctx);

        if draw_brick_debug {
            build_debug_gizmos();
        }

        if edit_manip_enabled && control_mode == .Editor {
            ray_origin, ray_dir, ray_ok := mouse_world_ray(
                .{cast(float) win_w, cast(float) win_h}, params.cpu.camera_tan_half_fov,
                camera.position, params.cpu.camera_forward, params.cpu.camera_right, params.cpu.camera_up,
                .{cast(float) mx, cast(float) my}, mouse_ok);
            hovered_edit = -1;
            if ray_ok && !io.WantCaptureMouse && !right_down {
                hovered_edit = pick_edit_from_bvh(ray_origin, ray_dir);
            }

            frame := Manip_Frame_Input.{
                viewport = viewport,
                camera_pos = camera.position,
                camera_forward = params.cpu.camera_forward,
                camera_right = params.cpu.camera_right,
                camera_up = params.cpu.camera_up,
                fov_y = params.cpu.camera_fov_y,
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
                    sync_edit_body_from_edit(selected_edit);
                    new_bounds := edit_bounds(selected_edit);
                    rebuild_bvh();
                    mark_edit_change_dirty(old_bounds, new_bounds, "manip_edit");
                }
            }

            // Scene picking should only be blocked by actual gizmo-handle interaction.
            // `manip_result.captured_mouse` is broader (includes selected-object hover), which prevents re-selection.
            handle_hovered := manip_ctx.hovered_axis >= 0 || manip_ctx.hovered_plane >= 0 || manip_ctx.hovered_orbit;
            can_pick_scene := left_pressed && !alt_down && !io.WantCaptureMouse && !right_down && !manip_ctx.active && !handle_hovered;
            if can_pick_scene {
                if ray_ok {
                    picked_edit := pick_edit_from_bvh(ray_origin, ray_dir);
                    selected_edit = picked_edit;
                    if picked_edit >= 0 {
                        double_click := (picked_edit == last_pick_edit) && ((time - last_pick_time) <= 0.30);
                        last_pick_edit = picked_edit;
                        last_pick_time = time;
                        if double_click {
                            start_focus_on_edit(picked_edit);
                        }
                    } else {
                        last_pick_edit = -1;
                        last_pick_time = -1000.0;
                    }
                } else {
                    selected_edit = -1;
                }
            }
        } else {
            hovered_edit = -1;
        }
    }
    if pending_full_rebuild {
        perform_pending_full_rebuild();
        recenter_pending = false;
    }
    ensure_edit_physics_bodies();
    physics_sync_suppress_edit = ifx manip_ctx.active && selected_edit >= 0 then selected_edit else -1;
    if control_mode == .Player {
        update_player_mode(dt, mouse_ok, right_down, cast(s32) mx, cast(s32) my);
    } else {
        Physics.tick(cast(float32) dt);
        sync_edits_from_physics();
        sync_player_edit_from_controller();
    }
    physics_sync_suppress_edit = -1;
    pending_dirty_count = count_dirty_flags();
    dirty_backlog_count = 0;

    // Upload edits after manip/picking so compute sees latest changes this frame.
    edit_count := cast(s32) params.cpu.edit_count;
    for i: 0..edit_count-1 {
        sanitize_edit_for_gpu(*edits_cpu[i], i);
        e := edits_cpu[i];
        using params.cpu;
        edit_shape[i] = e.shape;
        edit_op[i] = e.op;
        edit_pos_radius[i] = .{e.position.x, e.position.y, e.position.z, e.radius};
        edit_half_extents_blend[i] = .{e.half_extents.x, e.half_extents.y, e.half_extents.z, e.blend};
        edit_rotation[i] = e.rotation;
        edit_albedo[i] = e.albedo;
    }
    fill_render_params_from_compute_params();
    params.cpu.dirty_count = 0;
    bake_threads: s32 = 0;
    if recenter_pending || pending_dirty_count > 0 || gpu_full_rebuild_pending {
        active_state_gpu := brickmap_state.gpu;
        active_queue_gpu := brickmap_queues.gpu;
        next_cache_slot := brickmap_active_cache_slot;

        using params.cpu;
        debug_classify_candidates = cast(u32) pending_dirty_count;
        debug_classify_surface = 0;
        debug_classify_existing = 0;
        debug_classify_new_alloc = 0;
        debug_classify_rejected_capacity = 0;
        debug_classify_out_count = 0;
        dirty_count = 0;
        debug_bake_total_voxels = 0;
        debug_bake_bricks_touched = 0;

        inter_pass_sync: Brickmap_Graph_Sync = .WAIT_IDLE;
        recenter_sync: Brickmap_Graph_Sync = .WAIT_IDLE;
        owner_rebuild_sync: Brickmap_Graph_Sync = .WAIT_IDLE;
        setup_sync: Brickmap_Graph_Sync = .NONE;
        prepare_sync: Brickmap_Graph_Sync = .WAIT_IDLE;

        compute_params.cpu.* = params.cpu.*;

        reset(*brickmap_compute_graph);
        if recenter_pending {
            next_cache_slot = 1 - brickmap_active_cache_slot;
            next_state := brickmap_cache_slot(brickmap_state_ring, next_cache_slot);
            next_queue := brickmap_cache_slot(brickmap_queues_ring, next_cache_slot);
            active_state_gpu = next_state.gpu;
            active_queue_gpu = next_queue.gpu;
            add_compute_pass(*brickmap_compute_graph, "Recenter", compute_recenter_pipeline,
                .[compute_params.gpu, brickmap_state.gpu, brickmap_queues.gpu, next_state.gpu, next_queue.gpu],
                .[(BRICKMAP_TOTAL_GRID_CELLS + 63) / 64, 1, 1],
                .PARAMS | .STATE | .QUEUES, .STATE | .QUEUES, recenter_sync);
            add_compute_pass(*brickmap_compute_graph, "ClearSlotOwners", compute_clear_slot_owners_pipeline,
                .[compute_params.gpu, active_state_gpu],
                .[(cast(u32) (BRICKMAP_MAX_BRICKS + 63)) / 64, 1, 1],
                .PARAMS | .STATE, .PARAMS | .STATE, inter_pass_sync);
            add_compute_pass(*brickmap_compute_graph, "RebuildSlotOwners", compute_rebuild_slot_owners_pipeline,
                .[compute_params.gpu, active_state_gpu],
                .[(cast(u32) (max(BRICKMAP_TOTAL_GRID_CELLS, BRICKMAP_MAX_BRICKS) + 63)) / 64, 1, 1],
                .PARAMS | .STATE, .PARAMS | .STATE, owner_rebuild_sync);
        }

        add_compute_pass(*brickmap_compute_graph, "ResetQueues", compute_reset_queues_pipeline,
            .[active_queue_gpu], .[1, 1, 1], .QUEUES, .QUEUES, setup_sync);
        add_buffer_barrier_pass(*brickmap_compute_graph, "QueuesAfterReset", active_queue_gpu,
            .COMPUTE_SHADER, .SHADER_WRITE,
            .COMPUTE_SHADER, .SHADER_READ | .SHADER_WRITE);

        if gpu_full_rebuild_pending {
            add_compute_pass(*brickmap_compute_graph, "FullRebuildInvalidate", compute_full_rebuild_pipeline,
                .[compute_params.gpu, active_state_gpu, active_queue_gpu], .[(BRICKMAP_TOTAL_GRID_CELLS + 63) / 64, 1, 1],
                .PARAMS | .STATE | .QUEUES, .PARAMS | .STATE | .QUEUES, setup_sync);
            add_buffer_barrier_pass(*brickmap_compute_graph, "ParamsAfterFullRebuild", compute_params.gpu,
                .COMPUTE_SHADER, .SHADER_WRITE,
                .COMPUTE_SHADER, .SHADER_READ | .SHADER_WRITE);
            add_buffer_barrier_pass(*brickmap_compute_graph, "StateAfterFullRebuild", active_state_gpu,
                .COMPUTE_SHADER, .SHADER_WRITE,
                .COMPUTE_SHADER, .SHADER_READ | .SHADER_WRITE);
            add_buffer_barrier_pass(*brickmap_compute_graph, "QueuesAfterFullRebuild", active_queue_gpu,
                .COMPUTE_SHADER, .SHADER_WRITE,
                .COMPUTE_SHADER, .SHADER_READ | .SHADER_WRITE);
        }

        add_compute_pass(*brickmap_compute_graph, "PrepareDirty", compute_prepare_pipeline,
            .[compute_params.gpu, active_state_gpu, active_queue_gpu], .[(BRICKMAP_TOTAL_GRID_CELLS + 63) / 64, 1, 1],
            .PARAMS | .QUEUES, .QUEUES, prepare_sync);
        add_compute_pass(*brickmap_compute_graph, "ClassifyDirty", compute_classify_pipeline,
            .[compute_params.gpu, active_state_gpu, active_queue_gpu], .[(BRICKMAP_TOTAL_GRID_CELLS + 63) / 64, 1, 1],
            .PARAMS | .STATE | .QUEUES, .PARAMS | .STATE | .QUEUES, .NONE);
        add_buffer_barrier_pass(*brickmap_compute_graph, "QueuesForIndirectArgs", active_queue_gpu,
            .COMPUTE_SHADER, .SHADER_WRITE,
            .DRAW_INDIRECT, .INDIRECT_READ);
        add_compute_pass(*brickmap_compute_graph, "PrepareDispatchArgs", compute_prepare_dispatch_args_pipeline,
            .[active_queue_gpu, brickmap_dispatch_args.gpu], .[1, 1, 1],
            .QUEUES, .QUEUES, .NONE);
        add_buffer_barrier_pass(*brickmap_compute_graph, "DispatchArgsForBake", brickmap_dispatch_args.gpu,
            .COMPUTE_SHADER, .SHADER_WRITE,
            .DRAW_INDIRECT, .INDIRECT_READ);

        classify_stats := execute(*brickmap_compute_graph, main_queue);
        last_classify_graph_stats = classify_stats;
        note_perf_sample(*cpu_classify_encode_last_ms, *cpu_classify_encode_avg_ms, classify_stats.encode_ms);
        note_perf_sample(*cpu_classify_wait_last_ms, *cpu_classify_wait_avg_ms, classify_stats.wait_ms);

        if recenter_pending {
            set_active_cache_slot(next_cache_slot);
        }
        gpu_full_rebuild_pending = false;
        if log_updates {
            log("BRICKMAP indirect args bake=%x%x% publish=%x%x%",
                brickmap_dispatch_args.cpu.bake_x, brickmap_dispatch_args.cpu.bake_y, brickmap_dispatch_args.cpu.bake_z,
                brickmap_dispatch_args.cpu.publish_x, brickmap_dispatch_args.cpu.publish_y, brickmap_dispatch_args.cpu.publish_z);
        }
        bake_threads = 1;
    }

    if bake_threads > 0 {
        publish_args_gpu := brickmap_dispatch_args.gpu + cast(Gpu_Ptr) (size_of(u32) * 3);
        reset(*brickmap_compute_graph);
        add_compute_pass_indirect(*brickmap_compute_graph, "Bake", compute_bake_pipeline,
            .[compute_params.gpu, brickmap_queues.gpu], brickmap_dispatch_args.gpu,
            .PARAMS | .QUEUES, .ATLAS_SDF | .ATLAS_ALBEDO, .NONE);
        add_compute_pass_indirect(*brickmap_compute_graph, "Publish", compute_publish_pipeline,
            .[compute_params.gpu, brickmap_state.gpu, brickmap_queues.gpu], publish_args_gpu,
            .PARAMS | .STATE | .QUEUES | .ATLAS_SDF | .ATLAS_ALBEDO, .PARAMS | .STATE, .WAIT_IDLE);

        bake_stats := execute(*brickmap_compute_graph, main_queue);
        last_bake_graph_stats = bake_stats;
        note_perf_sample(*cpu_bake_encode_last_ms, *cpu_bake_encode_avg_ms, bake_stats.encode_ms);
        note_perf_sample(*cpu_bake_wait_last_ms, *cpu_bake_wait_avg_ms, bake_stats.wait_ms);

        sync_params_pointer_grid_from_state();
        params.cpu.atlas_alloc_next = compute_params.cpu.atlas_alloc_next;
        params.cpu.debug_classify_surface = compute_params.cpu.debug_classify_surface;
        params.cpu.debug_classify_existing = compute_params.cpu.debug_classify_existing;
        params.cpu.debug_classify_new_alloc = compute_params.cpu.debug_classify_new_alloc;
        params.cpu.debug_classify_rejected_capacity = compute_params.cpu.debug_classify_rejected_capacity;
        params.cpu.debug_bake_total_voxels = compute_params.cpu.debug_bake_total_voxels;
        params.cpu.debug_bake_bricks_touched = compute_params.cpu.debug_bake_bricks_touched;
        params.cpu.debug_bake_seen_atlas = compute_params.cpu.debug_bake_seen_atlas;
        params.cpu.debug_gpu_seen_edit_count = compute_params.cpu.debug_gpu_seen_edit_count;
        params.cpu.debug_gpu_seen_watch_shape = compute_params.cpu.debug_gpu_seen_watch_shape;
        params.cpu.debug_gpu_seen_watch_op = compute_params.cpu.debug_gpu_seen_watch_op;
        params.cpu.debug_gpu_seen_watch_pos_radius = compute_params.cpu.debug_gpu_seen_watch_pos_radius;
        params.cpu.debug_gpu_scene_at_camera = compute_params.cpu.debug_gpu_scene_at_camera;
        params.cpu.debug_gpu_scene_at_watch_center = compute_params.cpu.debug_gpu_scene_at_watch_center;
        params.cpu.debug_classify_out_count = brickmap_queues.cpu.bake_count;
        params.cpu.dirty_count = brickmap_queues.cpu.bake_count;
        next_atlas_index = cast(s32) min(compute_params.cpu.atlas_alloc_next, cast(u32) BRICKMAP_MAX_BRICKS);
        if log_updates {
            log("BRICKMAP classify_done pending_before=% classify_out=% atlas_next=% ptr_cells_now=% gpu(edit_count=% watch=% shape=% op=% posr=% sdf_cam=% sdf_watch=%)",
                pending_dirty_count,
                params.cpu.debug_classify_out_count,
                next_atlas_index,
                count_allocated_cells(),
                params.cpu.debug_gpu_seen_edit_count,
                params.cpu.debug_watch_edit_index,
                params.cpu.debug_gpu_seen_watch_shape,
                params.cpu.debug_gpu_seen_watch_op,
                params.cpu.debug_gpu_seen_watch_pos_radius,
                params.cpu.debug_gpu_scene_at_camera,
                params.cpu.debug_gpu_scene_at_watch_center);
        }
        if params.cpu.debug_classify_rejected_capacity > 0 {
            atlas_capacity_reached = true;
        } else if next_atlas_index < BRICKMAP_MAX_BRICKS {
            atlas_capacity_reached = false;
        }
        if log_updates {
            log("BRICKMAP bake_done bricks=% ptr_cells_now=% atlas_used=%",
                brickmap_queues.cpu.bake_count, count_allocated_cells(), next_atlas_index);
        }

        if log_updates {
            log("BRICKMAP baked frame=% dirty_bricks=%", frame_count, brickmap_queues.cpu.bake_count);
        }
        pending_dirty_count = 0;
    }

    encode_start := seconds_since_init();
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if !debug_render_direct_swapchain {
        offscreen_encode_start := seconds_since_init();
        if upscaler.mode == .TEMPORAL {
            {
                gpu_begin_scoped_render_pass(cmd_buff, .{
                    color_targets = .[
                        .{
                            view = upscaler.render_view,
                            load_op = .CLEAR,
                            store_op = .STORE,
                            clear_color._float = .[0.03, 0.035, 0.05, 1.0],
                        },
                        .{
                            view = upscaler.temporal_motion_view,
                            load_op = .CLEAR,
                            store_op = .STORE,
                            clear_color._float = .[0.0, 0.0, 0.0, 0.0],
                        },
                        .{
                            view = upscaler.temporal_depth_view,
                            load_op = .CLEAR,
                            store_op = .STORE,
                            clear_color._float = .[1.0, 0.0, 0.0, 0.0],
                        },
                    ]
                }, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);

                gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
                gpu_set_pipeline(cmd_buff, temporal_graphics_pipeline);
                draw_result := gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);
                assert(draw_result == .SUCCESS, tprint("Brickmap temporal offscreen draw failed: %", draw_result));
            }
        } else {
            {
                gpu_begin_scoped_render_pass(cmd_buff, .{
                    color_targets = .[
                        .{
                            view = upscaler.render_view,
                            load_op = .CLEAR,
                            store_op = .STORE,
                            clear_color._float = .[0.03, 0.035, 0.05, 1.0],
                        }
                    ]
                }, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);

                gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
                gpu_set_pipeline(cmd_buff, graphics_pipeline);
                draw_result := gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);
                assert(draw_result == .SUCCESS, tprint("Brickmap offscreen draw failed: %", draw_result));
            }
        }
        note_perf_sample(*cpu_offscreen_encode_last_ms, *cpu_offscreen_encode_avg_ms, cast(float) ((seconds_since_init() - offscreen_encode_start) * 1000.0));
    }

    if debug_render_direct_swapchain {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.03, 0.035, 0.05, 1.0],
                }
            ]
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, graphics_pipeline);
        draw_result := gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);
        assert(draw_result == .SUCCESS, tprint("Brickmap draw failed: %", draw_result));
        if draw_any_gizmo {
            viewport := Vector2.{cast(float) win_w, cast(float) win_h};
            gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .NONE);
            assert(gizmo_draw_result == .SUCCESS, tprint("Brickmap gizmo draw failed: %", gizmo_draw_result));
        }
    } else {
        if upscaler.mode == .SPATIAL {
            encode(*upscaler, cmd_buff, win_w, win_h, upscaler.render_view);
        } else if upscaler.mode == .TEMPORAL {
            encode(*upscaler, cmd_buff, win_w, win_h, upscaler.render_view, upscaler.temporal_motion_view, upscaler.temporal_depth_view);
        }

        if upscaler.mode != .NONE {
            blit_params.cpu.source_texture_index = gpu_texture_view_index(blit_source_view(*upscaler));
            blit_params.cpu.source_sampler_index = cast(u32) blit_sampler_handle() - 1;
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
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, blit_pipeline);
        blit_draw_result := gpu_draw_instanced(cmd_buff, 0, blit_params.gpu, 3, 1);
        if upscaler.mode == .NONE {
            assert(blit_draw_result == .SUCCESS, tprint("Brickmap blit draw failed: %", blit_draw_result));
        } else {
            assert(blit_draw_result == .SUCCESS, tprint("Brickmap MetalFX blit draw failed: %", blit_draw_result));
        }
        if draw_any_gizmo {
            viewport := Vector2.{cast(float) win_w, cast(float) win_h};
            gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*gizmo_render_ctx, cmd_buff, *gizmo_ctx, viewport, depth_mode = .NONE);
            assert(gizmo_draw_result == .SUCCESS, tprint("Brickmap gizmo draw failed: %", gizmo_draw_result));
        }
    }

    validation_scan_state();
    validation_assert_known_good();
    if log_validation_every_frame {
        log_validation_frame();
    }

    prev_view_proj = current_view_proj;
    note_perf_sample(*cpu_present_encode_last_ms, *cpu_present_encode_avg_ms, cast(float) ((seconds_since_init() - encode_start) * 1000.0));
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../editor_camera.jai";
#load "../ui/toggle_widget.jai";
#load "../ui/manip.jai";
#load "../character_controller.jai";

using,only(try_parse_env_int) _ :: #import "Env_Vars";
Input :: #import "Input";
ImGui :: #import "ImGui";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
Physics :: #import "Physics";
#import "JoltC";
#import "Math";
#import "Random";

blit_sampler_handle :: () -> Gpu_Sampler {
    using app;
    if blit_nearest return render_point_sampler;
    return render_sampler;
}

fill_render_params_from_compute_params :: () {
    render_params.cpu.resolution = params.cpu.resolution;
    render_params.cpu.camera_fov_y = params.cpu.camera_fov_y;
    render_params.cpu.camera_tan_half_fov = params.cpu.camera_tan_half_fov;
    render_params.cpu.time = params.cpu.time;

    render_params.cpu.view_proj = params.cpu.view_proj;
    render_params.cpu.prev_view_proj = params.cpu.prev_view_proj;
    render_params.cpu.cache_state = cast(*Brickmap_State) brickmap_state.gpu;

    render_params.cpu.camera_pos = params.cpu.camera_pos;
    render_params.cpu.camera_forward = params.cpu.camera_forward;
    render_params.cpu.camera_right = params.cpu.camera_right;
    render_params.cpu.camera_up = params.cpu.camera_up;

    render_params.cpu.atlas_texture_index = params.cpu.atlas_texture_index;
    render_params.cpu.atlas_albedo_texture_index = params.cpu.atlas_albedo_texture_index;
    render_params.cpu.atlas_sampler_linear_index = params.cpu.atlas_sampler_linear_index;
    render_params.cpu.atlas_sampler_point_index = params.cpu.atlas_sampler_point_index;
    render_params.cpu.use_cache_raymarch = params.cpu.use_cache_raymarch;
    render_params.cpu.use_hw_interp = params.cpu.use_hw_interp;
    render_params.cpu.atlas_debug_overlay = params.cpu.atlas_debug_overlay;
    render_params.cpu.atlas_debug_fullscreen = params.cpu.atlas_debug_fullscreen;
    render_params.cpu.pointer_grid_debug = params.cpu.pointer_grid_debug;
    render_params.cpu.bake_debug_gradient = params.cpu.bake_debug_gradient;
    render_params.cpu.cache_debug_show_selected_lod = params.cpu.cache_debug_show_selected_lod;
    render_params.cpu.cache_debug_show_distance = params.cpu.cache_debug_show_distance;
    render_params.cpu.cache_debug_show_cell_state = params.cpu.cache_debug_show_cell_state;
    render_params.cpu.debug_force_flat_color = params.cpu.debug_force_flat_color;
    render_params.cpu.cache_force_lod0 = params.cpu.cache_force_lod0;
    render_params.cpu.atlas_debug_slice = params.cpu.atlas_debug_slice;
    render_params.cpu.frame_index = params.cpu.frame_index;
    render_params.cpu.lod0_origin_brick_x = params.cpu.lod_origin_brick_x[0];
    render_params.cpu.lod0_origin_brick_y = params.cpu.lod_origin_brick_y[0];
    render_params.cpu.lod0_origin_brick_z = params.cpu.lod_origin_brick_z[0];
    render_params.cpu.lod1_origin_brick_x = params.cpu.lod_origin_brick_x[1];
    render_params.cpu.lod1_origin_brick_y = params.cpu.lod_origin_brick_y[1];
    render_params.cpu.lod1_origin_brick_z = params.cpu.lod_origin_brick_z[1];
    render_params.cpu.lod2_origin_brick_x = params.cpu.lod_origin_brick_x[2];
    render_params.cpu.lod2_origin_brick_y = params.cpu.lod_origin_brick_y[2];
    render_params.cpu.lod2_origin_brick_z = params.cpu.lod_origin_brick_z[2];
    render_params.cpu.lod3_origin_brick_x = params.cpu.lod_origin_brick_x[3];
    render_params.cpu.lod3_origin_brick_y = params.cpu.lod_origin_brick_y[3];
    render_params.cpu.lod3_origin_brick_z = params.cpu.lod_origin_brick_z[3];
    render_params.cpu.lod0_voxel_size = params.cpu.lod_voxel_size[0];
    render_params.cpu.lod1_voxel_size = params.cpu.lod_voxel_size[1];
    render_params.cpu.lod2_voxel_size = params.cpu.lod_voxel_size[2];
    render_params.cpu.lod3_voxel_size = params.cpu.lod_voxel_size[3];
}

log_bindless_indices_once :: () {
    if bindless_index_logged_once return;
    bindless_index_logged_once = true;
    log("BRICKMAP_BINDLESS atlas_tex=% atlas_albedo=% atlas_lin=% atlas_point=% blit_tex=% blit_sampler=%",
        params.cpu.atlas_texture_index,
        params.cpu.atlas_albedo_texture_index,
        params.cpu.atlas_sampler_linear_index,
        params.cpu.atlas_sampler_point_index,
        blit_params.cpu.source_texture_index,
        blit_params.cpu.source_sampler_index);
    if params.cpu.atlas_texture_index > 15 || params.cpu.atlas_albedo_texture_index > 15 ||
       params.cpu.atlas_sampler_linear_index > 15 || params.cpu.atlas_sampler_point_index > 15 ||
       blit_params.cpu.source_texture_index > 15 || blit_params.cpu.source_sampler_index > 15 {
        log_error("BRICKMAP_BINDLESS exceeds transpiler bindless clamp (15). This can cause wrong resource sampling.");
    }
}

BRICKMAP_PARAMS_GUARD_BYTES :: 4096;
BRICKMAP_PARAMS_GUARD_BEFORE :: cast(u8) 0xA5;
BRICKMAP_PARAMS_GUARD_AFTER  :: cast(u8) 0x5A;

init_params_guards :: () {
    for i: 0..BRICKMAP_PARAMS_GUARD_BYTES-1 {
        params_guard_before.cpu[i] = BRICKMAP_PARAMS_GUARD_BEFORE;
        params_guard_after.cpu[i] = BRICKMAP_PARAMS_GUARD_AFTER;
    }
}

seed_initial_scene :: () {
    using app;
    count: s32 = 0;

    add_sphere(*count, .{-2.1, 0.3, -3.8}, 1.1, albedo = .{0.68, 0.30, 0.28});
    add_sphere(*count, .{1.8, -0.1, -4.9}, 1.4, albedo = .{0.30, 0.57, 0.72});
    add_box(*count, .{0.0, 0.2, -6.7}, .{1.1, 0.9, 1.1}, .{0.18, 0.35, 0.05}, albedo = .{0.63, 0.58, 0.29});
    add_box(*count, .{-3.8, -0.2, -8.2}, .{0.9, 1.5, 0.9}, .{0.0, 0.42, 0.0}, albedo = .{0.36, 0.68, 0.39});
    add_sphere(*count, .{-0.1, 0.6, -6.7}, 0.85, op = .Subtract, albedo = .{0.86, 0.18, 0.76});
    add_box(*count, .{2.8, 0.7, -8.8}, .{1.7, 0.25, 0.7}, .{0.2, -0.3, 0.45}, albedo = .{0.78, 0.44, 0.21});

    random_seed(BRICKMAP_RANDOM_STARTUP_SEED);
    for 0..BRICKMAP_RANDOM_STARTUP_EDITS-1 {
        shape: SDF_Shape = ifx random_get_zero_to_one() < 0.5 then SDF_Shape.Sphere else SDF_Shape.Box;
        op: SDF_Op = ifx random_get_zero_to_one() < 0.82 then SDF_Op.Union else SDF_Op.Subtract;
        pos := Vector3.{
            random_get_within_range(-22.0, 22.0),
            random_get_within_range(-0.8, 2.8),
            random_get_within_range(-28.0, 18.0),
        };
        albedo := random_edit_albedo();

        blend: float = 0;
        if random_get_zero_to_one() < 0.4 {
            blend = random_get_within_range(0.2, 1.0);
        }
        gravitate := op == .Union && random_get_zero_to_one() < 0.3;

        if #complete shape == {
        case .Box;
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
            add_box(*count, pos, half_extents, euler, op = op, albedo = albedo, blend = blend, gravitate = gravitate);
        case .Sphere;
            radius := random_get_within_range(0.35, 1.65);
            add_sphere(*count, pos, radius, op = op, albedo = albedo, blend = blend, gravitate = gravitate);
        }

        if count >= BRICKMAP_MAX_EDITS break;
    }

    player_edit_index = count;
    add_sphere(*count, camera.position + .{0.0, 0.62, 0.0}, 0.56, albedo = .{0.96, 0.96, 0.98}, blend = 0.18);

    params.cpu.edit_count = cast(u32) count;
}

apply_runtime_edit :: () {
    if params.cpu.edit_count <= 0 return;

    old_bounds := edit_bounds(0);

    // Animated CSG punch to validate edit->BVH->brickmap update path.
    edits_cpu[0].position += .{1.35, 0.75, -0.55};
    edits_cpu[0].op = .Union;
    sync_edit_body_from_edit(0);

    new_bounds := edit_bounds(0);

    rebuild_bvh();
    mark_edit_change_dirty(old_bounds, new_bounds, "auto_edit");

    if log_updates {
        log("BRICKMAP runtime edit applied at frame=%", frame_count);
    }
}

update_auto_drag_repro :: () {
    if auto_drag_done return;
    if frame_count < auto_drag_start_frame return;

    if !auto_drag_started {
        auto_drag_edit_index = find_nearest_edit_to_camera();
        assert(auto_drag_edit_index >= 0, "BRICKMAP auto drag found no edit near camera.");
        auto_drag_started = true;
        dragged_edit := edits_cpu[auto_drag_edit_index];
        params.cpu.debug_watch_edit_index = cast(u32) auto_drag_edit_index;
        auto_drag_from_pos = dragged_edit.position;
        auto_drag_to_pos = auto_drag_from_pos + .{0.0, 1.0, 0.0};
        selected_edit = auto_drag_edit_index;
        if log_updates {
            log("BRICKMAP auto drag start edit=% shape=% op=% pos=% radius=% half=% blend=% rot=% from=% to=% start=% duration=%",
                auto_drag_edit_index,
                dragged_edit.shape,
                dragged_edit.op,
                dragged_edit.position,
                dragged_edit.radius,
                dragged_edit.half_extents,
                dragged_edit.blend,
                dragged_edit.rotation,
                auto_drag_from_pos,
                auto_drag_to_pos,
                auto_drag_start_frame,
                auto_drag_duration_frames);
        }
    }

    duration := max(auto_drag_duration_frames, 1);
    drag_frame := frame_count - auto_drag_start_frame;
    t := clamp(cast(float) drag_frame / cast(float) duration, 0.0, 1.0);
    old_bounds := edit_bounds(auto_drag_edit_index);
    edits_cpu[auto_drag_edit_index].position = lerp(auto_drag_from_pos, auto_drag_to_pos, t);
    sync_edit_body_from_edit(auto_drag_edit_index);
    new_bounds := edit_bounds(auto_drag_edit_index);
    rebuild_bvh();
    mark_edit_change_dirty(old_bounds, new_bounds, "manip_edit");

    if t >= 1.0 {
        auto_drag_done = true;
        if log_updates {
            log("BRICKMAP auto drag done edit=% frame=%", auto_drag_edit_index, frame_count);
        }
    }
}

find_nearest_edit_to_camera :: () -> s32 {
    using app;
    edit_count := cast(s32) params.cpu.edit_count;
    best_index: s32 = -1;
    best_dist2 := 1.0e30;
    for i: 0..edit_count-1 {
        d2 := length_squared(edits_cpu[i].position - camera.position);
        if d2 < best_dist2 {
            best_dist2 = d2;
            best_index = i;
        }
    }
    return best_index;
}

rebuild_bvh :: () {
    count := cast(s32) params.cpu.edit_count;
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
    if e.shape == .Box {
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
    count := cast(s32) params.cpu.edit_count;
    for i: 0..count-1 {
        mark_dirty_aabb(bvh.edit_bounds[i], reason);
    }
}

mark_edit_change_dirty :: (old_bounds: AABB, new_bounds: AABB, reason: string) {
    mark_dirty_aabb(old_bounds, reason);
    mark_dirty_aabb(new_bounds, reason);

    swept_bounds := AABB.{
        min = .{
            min(old_bounds.min.x, new_bounds.min.x),
            min(old_bounds.min.y, new_bounds.min.y),
            min(old_bounds.min.z, new_bounds.min.z),
        },
        max = .{
            max(old_bounds.max.x, new_bounds.max.x),
            max(old_bounds.max.y, new_bounds.max.y),
            max(old_bounds.max.z, new_bounds.max.z),
        },
    };
    mark_dirty_aabb(swept_bounds, reason);
}

request_full_rebuild :: (reason: string) {
    pending_full_rebuild = true;
    if log_updates && frame_count > 0 {
        log("BRICKMAP full rebuild requested reason=%", reason);
    }
}

mark_all_cells_dirty :: (reason: string) {
    for cell: 0..BRICKMAP_TOTAL_GRID_CELLS-1 {
        pointer_grid_generation_cpu[cell] += 1;
        brickmap_queues.cpu.dirty_flags[cell] = 1;
    }
    pending_dirty_count = BRICKMAP_TOTAL_GRID_CELLS;
    if log_updates && frame_count > 0 {
        log("BRICKMAP full clipmap dirty reason=% cells=%", reason, pending_dirty_count);
    }
    sync_params_pointer_grid_from_state();
}

perform_pending_full_rebuild :: () {
    if !force_full_rebuild && !pending_full_rebuild return;
    gpu_full_rebuild_pending = true;
    pending_dirty_count = BRICKMAP_TOTAL_GRID_CELLS;
    if log_updates && frame_count > 0 {
        log("BRICKMAP full rebuild prepared dirty=% edits=%", pending_dirty_count, params.cpu.edit_count);
    }
    pending_full_rebuild = false;
    force_full_rebuild = false;
}

update_lod_origins :: (camera_moved: bool) -> bool {
    using app;
    if !camera_moved return false;

    changed := false;
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
        voxel_size := BASE_VOXEL * cast(float) (1 << lod);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

        info := lod_info_cpu[lod];
        camera_brick_x := cast(s32) floor(camera.position.x / brick_world_size);
        camera_brick_y := cast(s32) floor(camera.position.y / brick_world_size);
        camera_brick_z := cast(s32) floor(camera.position.z / brick_world_size);
        origin_x := info.origin_brick.x;
        origin_y := info.origin_brick.y;
        origin_z := info.origin_brick.z;
        margin := BRICKMAP_CLIPMAP_MARGIN_BRICKS;
        max_local := BRICKMAP_GRID_RES - margin - 1;

        local_x := camera_brick_x - origin_x;
        local_z := camera_brick_z - origin_z;

        if freeze_clipmap {
            if info.voxel_size <= 0.0 {
                origin_x = camera_brick_x - BRICKMAP_GRID_RES / 2;
                origin_z = camera_brick_z - BRICKMAP_GRID_RES / 2;
            }
        } else {
            if local_x < margin origin_x = camera_brick_x - BRICKMAP_GRID_RES / 2;
            if local_x > max_local origin_x = camera_brick_x - BRICKMAP_GRID_RES / 2;
            if local_z < margin origin_z = camera_brick_z - BRICKMAP_GRID_RES / 2;
            if local_z > max_local origin_z = camera_brick_z - BRICKMAP_GRID_RES / 2;
        }

        params.cpu.prev_lod_origin_brick_x[lod] = info.origin_brick.x;
        params.cpu.prev_lod_origin_brick_y[lod] = info.origin_brick.y;
        params.cpu.prev_lod_origin_brick_z[lod] = info.origin_brick.z;
        if info.origin_brick.x != origin_x || info.origin_brick.y != origin_y || info.origin_brick.z != origin_z {
            changed = true;
            lod_info_cpu[lod].origin_brick.x = origin_x;
            lod_info_cpu[lod].origin_brick.y = origin_y;
            lod_info_cpu[lod].origin_brick.z = origin_z;
        }
        lod_info_cpu[lod].voxel_size = voxel_size;
    }

    if !changed return false;

    if experimental_recenter_reuse {
        if log_updates {
            log("BRICKMAP clipmap origin changed; scheduling conservative recenter");
        }
        return true;
    }

    pending_full_rebuild = true;
    if log_updates {
        log("BRICKMAP clipmap origin changed; scheduling CPU-side full rebuild");
    }
    return false;
}

clear_cache :: () {
    for i: 0..pointer_grid_cpu.count-1 {
        pointer_grid_cpu[i] = -1;
        pointer_grid_valid_cpu[i] = 0;
        pointer_grid_publish_cpu[i] = 0;
        pointer_grid_generation_cpu[i] = 0;
    }
    for i: 0..BRICKMAP_MAX_BRICKS-1 {
        brickmap_state.cpu.slot_owner_lod[i] = -1;
        brickmap_state.cpu.slot_owner_bx[i] = 0;
        brickmap_state.cpu.slot_owner_by[i] = 0;
        brickmap_state.cpu.slot_owner_bz[i] = 0;
        brickmap_state.cpu.slot_generation[i] = 0;
    }
    for i: 0..BRICKMAP_TOTAL_GRID_CELLS-1 {
        brickmap_queues.cpu.dirty_flags[i] = 0;
    }
    next_atlas_index = 0;
    params.cpu.atlas_alloc_next = 0;
    params.cpu.full_rebuild_requested = 0;
    gpu_full_rebuild_pending = false;
    pending_dirty_count = 0;
    dirty_backlog_count = 0;
    sync_params_pointer_grid_from_state();
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
                    pointer_grid_valid_cpu[base + idx] = 0;
                    pointer_grid_publish_cpu[base + idx] = 0;
                    pointer_grid_generation_cpu[base + idx] += 1;
                    brickmap_queues.cpu.dirty_flags[base + idx] = 0;

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
    shifted_valid: [BRICKMAP_GRID_CELLS] u32;
    shifted_publish: [BRICKMAP_GRID_CELLS] u32;
    shifted_generation: [BRICKMAP_GRID_CELLS] u32;
    shifted_dirty: [BRICKMAP_GRID_CELLS] bool;
    for i: 0..BRICKMAP_GRID_CELLS-1 {
        shifted[i] = -1;
        shifted_valid[i] = 0;
        shifted_publish[i] = 0;
        shifted_generation[i] = 0;
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
                shifted_valid[new_idx] = pointer_grid_valid_cpu[base + old_idx];
                shifted_publish[new_idx] = pointer_grid_publish_cpu[base + old_idx];
                shifted_generation[new_idx] = pointer_grid_generation_cpu[base + old_idx];
                shifted_dirty[new_idx] = brickmap_queues.cpu.dirty_flags[base + old_idx] != 0;
                if shifted[new_idx] >= 0 {
                    validation_frame.shift_preserved_cells += 1;
                }
            }
        }
    }

    for i: 0..BRICKMAP_GRID_CELLS-1 {
        pointer_grid_cpu[base + i] = shifted[i];
        pointer_grid_valid_cpu[base + i] = shifted_valid[i];
        pointer_grid_publish_cpu[base + i] = shifted_publish[i];
        pointer_grid_generation_cpu[base + i] = shifted_generation[i];
        if shifted_dirty[i] {
            brickmap_queues.cpu.dirty_flags[base + i] = 1;
        } else {
            brickmap_queues.cpu.dirty_flags[base + i] = 0;
        }
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
                pointer_grid_valid_cpu[base + idx] = 0;
                pointer_grid_publish_cpu[base + idx] = 0;
                pointer_grid_generation_cpu[base + idx] += 1;
                brickmap_queues.cpu.dirty_flags[base + idx] = 0;

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
    pointer_grid_generation_cpu[cell] += 1;
    if brickmap_queues.cpu.dirty_flags[cell] != 0 return true;
    brickmap_queues.cpu.dirty_flags[cell] = 1;
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
        expanded_bounds := bounds;
        expanded_bounds.min -= .{voxel_size, voxel_size, voxel_size};
        expanded_bounds.max += .{voxel_size, voxel_size, voxel_size};

        bx0 := cast(s32) floor(expanded_bounds.min.x / brick_world_size);
        by0 := cast(s32) floor(expanded_bounds.min.y / brick_world_size);
        bz0 := cast(s32) floor(expanded_bounds.min.z / brick_world_size);
        bx1 := cast(s32) floor(expanded_bounds.max.x / brick_world_size);
        by1 := cast(s32) floor(expanded_bounds.max.y / brick_world_size);
        bz1 := cast(s32) floor(expanded_bounds.max.z / brick_world_size);
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
                    pointer_grid_generation_cpu[cell] += 1;
                    if brickmap_queues.cpu.dirty_flags[cell] != 0 continue;
                    brickmap_queues.cpu.dirty_flags[cell] = 1;
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
    sync_params_pointer_grid_from_state();
}

count_dirty_flags :: () -> s32 {
    count: s32 = 0;
    for i: 0..BRICKMAP_TOTAL_GRID_CELLS-1 {
        if brickmap_queues.cpu.dirty_flags[i] != 0 count += 1;
    }
    return count;
}

rebuild_free_slots_from_pointer_grid :: () {
    return;
}

pop_free_atlas_slot :: () -> s32 {
    return -1;
}

build_dirty_batch_from_flags :: (max_batch: s32) -> s32 {
    _ = max_batch;
    return count_dirty_flags();
}

clear_processed_dirty_flags_from_batch :: (processed_count: s32) {
    _ = processed_count;
}

clear_processed_dirty_flags_from_gpu :: (processed_count: s32) {
    _ = processed_count;
}

apply_classify_results_to_dirty_flags :: (candidate_count: s32) {
    _ = candidate_count;
}

sync_params_pointer_grid_from_state :: () {
    params.cpu.pointer_grid = brickmap_state.cpu.pointer_grid;
    params.cpu.pointer_grid_valid = brickmap_state.cpu.pointer_grid_valid;
    params.cpu.pointer_grid_publish_frame = brickmap_state.cpu.pointer_grid_publish_frame;
    params.cpu.pointer_grid_generation = brickmap_state.cpu.pointer_grid_generation;
    params.cpu.slot_owner_lod = brickmap_state.cpu.slot_owner_lod;
    params.cpu.slot_owner_bx = brickmap_state.cpu.slot_owner_bx;
    params.cpu.slot_owner_by = brickmap_state.cpu.slot_owner_by;
    params.cpu.slot_owner_bz = brickmap_state.cpu.slot_owner_bz;
    params.cpu.slot_generation = brickmap_state.cpu.slot_generation;
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

random_edit_albedo :: () -> Vector3 {
    palette: [12]Vector3 = .[
        .{0.87, 0.41, 0.33},
        .{0.93, 0.66, 0.33},
        .{0.82, 0.74, 0.38},
        .{0.58, 0.76, 0.39},
        .{0.32, 0.74, 0.56},
        .{0.30, 0.65, 0.79},
        .{0.39, 0.52, 0.86},
        .{0.66, 0.49, 0.85},
        .{0.83, 0.42, 0.76},
        .{0.79, 0.46, 0.56},
        .{0.66, 0.62, 0.55},
        .{0.74, 0.69, 0.61},
    ];

    palette_f := cast(float) palette.count;
    idx := clamp(cast(s32) floor(random_get_zero_to_one() * palette_f), 0, palette.count - 1);
    base := palette[idx];
    jitter := 0.06;
    return .{
        clamp(base.x + random_get_within_range(-jitter, jitter), 0.0, 1.0),
        clamp(base.y + random_get_within_range(-jitter, jitter), 0.0, 1.0),
        clamp(base.z + random_get_within_range(-jitter, jitter), 0.0, 1.0),
    };
}

add_sphere :: (count: *s32, pos: Vector3, radius: float, op: SDF_Op = .Union, albedo: Vector3 = .{0.48, 0.52, 0.58}, blend: float = 0, gravitate: bool = false) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    edits_cpu[count.*] = .{
        shape = .Sphere,
        op = op,
        position = pos,
        radius = radius,
        half_extents = .{radius, radius, radius},
        rotation = .{0.0, 0.0, 0.0, 1.0},
        albedo = .{albedo.x, albedo.y, albedo.z, 1.0},
        blend = blend,
    };
    physics_body_gravitate[count.*] = gravitate;
    count.* += 1;
}

add_box :: (count: *s32, pos: Vector3, half_extents: Vector3, euler: Vector3 = .{0.0, 0.0, 0.0}, op: SDF_Op = .Union, albedo: Vector3 = .{0.48, 0.52, 0.58}, blend: float = 0.0, gravitate: bool = false) {
    if count.* >= BRICKMAP_MAX_EDITS return;
    q := quat_from_euler_xyz(euler);
    edits_cpu[count.*] = .{
        shape = .Box,
        op = op,
        position = pos,
        radius = length(half_extents),
        half_extents = half_extents,
        rotation = .{q.x, q.y, q.z, q.w},
        albedo = .{albedo.x, albedo.y, albedo.z, 1.0},
        blend = blend,
    };
    physics_body_gravitate[count.*] = gravitate;
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

edit_has_physics_body :: (edit_index: s32) -> bool {
    if edit_index < 0 || cast(s64) edit_index >= edits_cpu.count return false;
    if edit_index == player_edit_index return false;
    return edits_cpu[edit_index].op == .Union;
}

destroy_edit_physics_body :: (edit_index: s32) {
    if edit_index < 0 || cast(s64) edit_index >= physics_body_active.count return;
    if !physics_body_active[edit_index] return;
    Physics.destroy_body(physics_body_ids[edit_index]);
    physics_body_ids[edit_index] = 0;
    physics_body_active[edit_index] = false;
}

create_dynamic_body_for_edit :: (edit_index: s32) {
    if edit_index < 0 || cast(s64) edit_index >= edits_cpu.count return;
    if !edit_has_physics_body(edit_index) {
        destroy_edit_physics_body(edit_index);
        return;
    }

    destroy_edit_physics_body(edit_index);

    e := edits_cpu[edit_index];
    shape: *Shape;
    if e.shape == {
    case .Sphere;
        shape = cast(*Shape) SphereShape_Create(e.radius);
    case .Box;
        half_jph := cast,force(Vec3) e.half_extents;
        shape = cast(*Shape) BoxShape_Create(*half_jph, JPH_DEFAULT_CONVEX_RADIUS);
    }
    assert(shape != null, "Brickmap edit physics shape creation failed for edit %.", edit_index);
    defer Shape_Destroy(shape);

    pos_jph := cast,force(Vec3) e.position;
    rot_jph := cast,force(Quat) Quaternion.{e.rotation.x, e.rotation.y, e.rotation.z, e.rotation.w};
    body_settings := BodyCreationSettings_Create3(shape, *pos_jph, *rot_jph, .Dynamic, Physics.Layers.MOVING);
    assert(body_settings != null, "Brickmap edit physics settings creation failed for edit %.", edit_index);
    defer BodyCreationSettings_Destroy(body_settings);
    BodyCreationSettings_SetFriction(body_settings, 0.85);
    BodyCreationSettings_SetRestitution(body_settings, 0.02);
    BodyCreationSettings_SetLinearDamping(body_settings, 0.55);
    BodyCreationSettings_SetAngularDamping(body_settings, 0.72);
    BodyCreationSettings_SetMotionQuality(body_settings, .LinearCast);

    body_id := BodyInterface_CreateAndAddBody(Physics.physics.body_interface, body_settings, .Activate);
    physics_body_ids[edit_index] = body_id;
    physics_body_active[edit_index] = true;
    physics_body_shape_cache[edit_index] = e.shape;
    physics_body_radius_cache[edit_index] = e.radius;
    physics_body_half_extents_cache[edit_index] = e.half_extents;
}

physics_shape_changed :: (edit_index: s32) -> bool {
    if !physics_body_active[edit_index] return true;
    e := edits_cpu[edit_index];
    if physics_body_shape_cache[edit_index] != e.shape return true;
    if abs(physics_body_radius_cache[edit_index] - e.radius) > 0.0001 return true;
    cached_half := physics_body_half_extents_cache[edit_index];
    if length_squared(cached_half - e.half_extents) > 0.0001 return true;
    return false;
}

sync_edit_body_from_edit :: (edit_index: s32) {
    if !edit_has_physics_body(edit_index) {
        destroy_edit_physics_body(edit_index);
        return;
    }
    if !physics_body_active[edit_index] || physics_shape_changed(edit_index) {
        create_dynamic_body_for_edit(edit_index);
        return;
    }

    e := edits_cpu[edit_index];
    pos_jph := cast,force(RVec3) e.position;
    rot_jph := cast,force(Quat) Quaternion.{e.rotation.x, e.rotation.y, e.rotation.z, e.rotation.w};
    BodyInterface_SetPositionAndRotationWhenChanged(Physics.physics.body_interface, physics_body_ids[edit_index], *pos_jph, *rot_jph, .Activate);
    BodyInterface_ActivateBody(Physics.physics.body_interface, physics_body_ids[edit_index]);
}

ensure_edit_physics_bodies :: () {
    edit_count := cast(s32) params.cpu.edit_count;
    for i: 0..edit_count-1 {
        if edit_has_physics_body(i) {
            if !physics_body_active[i] || physics_shape_changed(i) {
                create_dynamic_body_for_edit(i);
            }
        } else {
            destroy_edit_physics_body(i);
        }
    }
    for i: edit_count..BRICKMAP_MAX_EDITS-1 {
        destroy_edit_physics_body(cast(s32) i);
    }
}

physics_dirty_accum_add :: (bounds: AABB) {
    if !physics_step_dirty_accum_valid {
        physics_step_dirty_bounds = bounds;
        physics_step_dirty_accum_valid = true;
        return;
    }
    physics_step_dirty_bounds = aabb_union(physics_step_dirty_bounds, bounds);
}

sync_edits_from_physics :: () {
    edit_count := cast(s32) params.cpu.edit_count;
    physics_step_dirty_accum_valid = false;
    any_changed := false;
    for i: 0..edit_count-1 {
        if !physics_body_active[i] continue;
        if i == physics_sync_suppress_edit continue;

        old_bounds := edit_bounds(i);
        pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, physics_body_ids[i]);
        rot := cast,force(Quaternion) BodyInterface_GetRotation(Physics.physics.body_interface, physics_body_ids[i]);
        e := edits_cpu[i];
        moved := length_squared(e.position - pos) > 0.000025;
        rotated := 1.0 - abs(dot(Vector4.{e.rotation.x, e.rotation.y, e.rotation.z, e.rotation.w}, Vector4.{rot.x, rot.y, rot.z, rot.w})) > 0.00005;
        if !moved && !rotated continue;

        e.position = pos;
        e.rotation = .{rot.x, rot.y, rot.z, rot.w};
        edits_cpu[i] = e;
        new_bounds := edit_bounds(i);
        physics_dirty_accum_add(old_bounds);
        physics_dirty_accum_add(new_bounds);
        physics_dirty_accum_add(aabb_union(old_bounds, new_bounds));
        any_changed = true;
    }

    if any_changed {
        rebuild_bvh();
        mark_dirty_aabb(physics_step_dirty_bounds, "physics_step");
    }
}

sync_player_edit_from_controller :: () {
    if player_edit_index < 0 || cast(s64) player_edit_index >= edits_cpu.count return;
    old_bounds := edit_bounds(player_edit_index);
    player_pos := character_controller_position(*player_controller);
    edits_cpu[player_edit_index].position = player_pos + .{0.0, 0.42, 0.0};
    edits_cpu[player_edit_index].rotation = .{0.0, 0.0, 0.0, 1.0};
    new_bounds := edit_bounds(player_edit_index);
    rebuild_bvh();
    mark_edit_change_dirty(old_bounds, new_bounds, "player_step");
}

apply_player_push_impulses :: (dt: float) {
    player_center := character_controller_position(*player_controller) + .{0.0, 0.42, 0.0};
    player_vel := cast,force(Vector3) CharacterVirtual_GetLinearVelocity(player_controller.character);
    player_speed2 := length_squared(Vector3.{player_vel.x, 0.0, player_vel.z});
    if player_speed2 < 0.01 return;

    edit_count := cast(s32) params.cpu.edit_count;
    for i: 0..edit_count-1 {
        if !physics_body_active[i] continue;
        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, physics_body_ids[i]);
        to_body := body_pos - player_center;
        horizontal := Vector3.{to_body.x, 0.0, to_body.z};
        dist2 := length_squared(horizontal);
        push_range := player_push_radius + max(edits_cpu[i].radius, 0.45);
        if dist2 > push_range * push_range continue;

        dir := normalize_or_zero(horizontal);
        if length_squared(dir) < 0.0001 {
            dir = normalize_or_zero(Vector3.{player_vel.x, 0.0, player_vel.z});
        }
        impulse := dir * (player_push_strength * dt * 60.0);
        impulse.y = 0.18;
        impulse_jph := cast,force(Vec3) impulse;
        BodyInterface_AddImpulse(Physics.physics.body_interface, physics_body_ids[i], *impulse_jph);
        BodyInterface_ActivateBody(Physics.physics.body_interface, physics_body_ids[i]);
    }
}

apply_player_pull_forces :: (dt: float) {
    player_center := character_controller_position(*player_controller) + .{0.0, 0.62, 0.0};
    edit_count := cast(s32) params.cpu.edit_count;
    for i: 0..edit_count-1 {
        if !physics_body_active[i] continue;
        if !physics_body_gravitate[i] continue;

        body_pos := cast,force(Vector3) BodyInterface_GetPosition(Physics.physics.body_interface, physics_body_ids[i]);
        to_player := player_center - body_pos;
        dist2 := length_squared(to_player);
        if dist2 <= 0.05 || dist2 > 64.0 continue;

        dir := normalize_or_zero(to_player);
        falloff := clamp(1.0 - sqrt(dist2) / 8.0, 0.0, 1.0);
        force := dir * (player_pull_strength * falloff);
        force.y += 0.35 * falloff;
        force_jph := cast,force(Vec3) force;
        BodyInterface_AddForce(Physics.physics.body_interface, physics_body_ids[i], *force_jph);
        BodyInterface_ActivateBody(Physics.physics.body_interface, physics_body_ids[i]);
    }
}

update_player_mode :: (dt: float, mouse_ok: bool, right_down: bool, mx: s32, my: s32) {
    using app;
    if control_mode != .Player return;

    _ = editor_camera_update(*camera, dt, mx, my, mouse_ok,
        allow_move = false,
        allow_look = right_down && !ImGui.GetIO().WantCaptureMouse && !orbit_drag_active,
        allow_zoom = !ImGui.GetIO().WantCaptureMouse && !orbit_drag_active);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
    forward := normalize_or_zero(Vector3.{cam_forward.x, 0.0, cam_forward.z});
    right := normalize_or_zero(Vector3.{cam_right.x, 0.0, cam_right.z});

    desired_move := Vector3.{};
    if (Input.input_button_states[#char "W"] & .DOWN) != 0 desired_move += forward;
    if (Input.input_button_states[#char "S"] & .DOWN) != 0 desired_move -= forward;
    if (Input.input_button_states[#char "D"] & .DOWN) != 0 desired_move += right;
    if (Input.input_button_states[#char "A"] & .DOWN) != 0 desired_move -= right;
    desired_move = normalize_or_zero(desired_move) * player_move_speed;
    jump_pressed := (Input.input_button_states[Input.Key_Code.SPACEBAR] & .START) != 0;

    character_controller_update_in_system(*player_controller, Physics.physics.system, desired_move, dt, jump_pressed);
    apply_player_push_impulses(dt);
    apply_player_pull_forces(dt);
    Physics.tick(cast(float32) dt);
    sync_edits_from_physics();
    sync_player_edit_from_controller();

    player_eye := character_controller_position(*player_controller) + .{0.0, player_camera_eye_height, 0.0};
    camera.position = player_eye;
}

init_brickmap_physics :: () {
    using app;
    Physics.configure_test_environment(
        spawn_spheres = false,
        include_static_box = false,
        create_floor = true,
        floor_half_extent = .{140.0, 1.0, 140.0},
        floor_center = .{0.0, -1.0, 0.0});
    Physics.init();
    Physics.debug_draw_enabled = physics_gizmos_enabled;
    ensure_edit_physics_bodies();
    start_pos := camera.position;
    start_pos.y = max(start_pos.y, 1.2);
    player_controller.radius = 0.52;
    player_controller.height = 1.25;
    player_controller.jump_speed = 5.8;
    player_controller.accel = 11.0;
    character_controller_init_in_system(*player_controller, Physics.physics.system, start_pos, walk_speed = player_move_speed, visual_yaw_offset = 0.0);
}

deinit_brickmap_physics :: () {
    for i: 0..BRICKMAP_MAX_EDITS-1 destroy_edit_physics_body(cast(s32) i);
    controller_deinit(*player_controller);
    Physics.deinit();
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
                    if pointer_grid_valid_cpu[cell] == 0 continue;

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
    validation_first_mismatch_cell = -1;
    validation_first_mismatch_slot = -1;
}

validation_scan_state :: () {
    seen: [BRICKMAP_MAX_BRICKS] bool;
    next := clamp(next_atlas_index, 0, BRICKMAP_MAX_BRICKS);

    for i: 0..pointer_grid_cpu.count-1 {
        v := pointer_grid_cpu[i];
        if params.cpu.pointer_grid[i] != pointer_grid_cpu[i] ||
           params.cpu.pointer_grid_valid[i] != pointer_grid_valid_cpu[i] ||
           params.cpu.pointer_grid_publish_frame[i] != pointer_grid_publish_cpu[i] ||
           params.cpu.pointer_grid_generation[i] != pointer_grid_generation_cpu[i] {
            validation_frame.scan_param_state_mismatches += 1;
        }
        if brickmap_queues.cpu.dirty_flags[i] != 0 {
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
        if pointer_grid_valid_cpu[i] != 0 {
            validation_frame.scan_valid_cells += 1;
            if pointer_grid_publish_cpu[i] == 0 {
                validation_frame.scan_valid_unpublished += 1;
            }

            lod := i / BRICKMAP_GRID_CELLS;
            local_idx := i - lod * BRICKMAP_GRID_CELLS;
            lz := local_idx / (BRICKMAP_GRID_RES * BRICKMAP_GRID_RES);
            remain := local_idx - lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
            ly := remain / BRICKMAP_GRID_RES;
            lx := remain - ly * BRICKMAP_GRID_RES;
            expect_bx := lod_info_cpu[lod].origin_brick.x + lx;
            expect_by := lod_info_cpu[lod].origin_brick.y + ly;
            expect_bz := lod_info_cpu[lod].origin_brick.z + lz;

            owner_lod := brickmap_state.cpu.slot_owner_lod[v];
            owner_bx := brickmap_state.cpu.slot_owner_bx[v];
            owner_by := brickmap_state.cpu.slot_owner_by[v];
            owner_bz := brickmap_state.cpu.slot_owner_bz[v];
            if owner_lod < 0 {
                validation_frame.scan_owner_missing += 1;
            } else if owner_lod != lod || owner_bx != expect_bx || owner_by != expect_by || owner_bz != expect_bz {
                validation_frame.scan_owner_mismatches += 1;
                if validation_first_mismatch_cell < 0 {
                    validation_first_mismatch_cell = cast(s32) i;
                    validation_first_mismatch_slot = cast(s32) v;
                    validation_first_mismatch_expect_lod = cast(s32) lod;
                    validation_first_mismatch_expect_bx = cast(s32) expect_bx;
                    validation_first_mismatch_expect_by = cast(s32) expect_by;
                    validation_first_mismatch_expect_bz = cast(s32) expect_bz;
                    validation_first_mismatch_owner_lod = cast(s32) owner_lod;
                    validation_first_mismatch_owner_bx = cast(s32) owner_bx;
                    validation_first_mismatch_owner_by = cast(s32) owner_by;
                    validation_first_mismatch_owner_bz = cast(s32) owner_bz;
                }
            }
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

    if validation_frame.scan_nonempty_cells > validation_max_nonempty_cells {
        validation_max_nonempty_cells = validation_frame.scan_nonempty_cells;
    }
}

log_validation_frame :: () {
    using app;
    v := validation_frame;
    log("BRICKMAP_VAL frame=% cam=[%,%,%] pending=% dirty=% atlas=%/% ptr=% val(nonempty=% valid=% oob=% dup=% above=% neg=% holes=% refs=% dirty_flags=% owner_mismatch=% owner_missing=% valid_unpublished=% max_seen=%) shift(keep=% inval=% requeue=% drop=% overflow=%)",
        frame_count,
        camera.position.x, camera.position.y, camera.position.z,
        pending_dirty_count,
        params.cpu.dirty_count,
        next_atlas_index, BRICKMAP_MAX_BRICKS,
        count_allocated_cells(),
        v.scan_nonempty_cells, v.scan_valid_cells, v.scan_oob_atlas_refs, v.scan_duplicate_atlas_refs, v.scan_above_next_atlas_refs,
        v.scan_negative_nonempty_refs, v.scan_holes_below_next, v.scan_referenced_slots, v.scan_dirty_flag_cells,
        v.scan_owner_mismatches, v.scan_owner_missing, v.scan_valid_unpublished, validation_max_nonempty_cells,
        v.shift_preserved_cells, v.shift_invalidated_cells, v.shift_requeued_cells, v.shift_dropped_cells, v.enqueue_overflow);
    if v.scan_param_state_mismatches > 0 {
        log_error("BRICKMAP_VAL param/state mismatches=%", v.scan_param_state_mismatches);
    }
    if v.scan_owner_mismatches > 0 && validation_first_mismatch_cell >= 0 {
        log_error("BRICKMAP_VAL first_owner_mismatch cell=% slot=% expect=(lod=% bx=% by=% bz=%) owner=(lod=% bx=% by=% bz=%)",
            validation_first_mismatch_cell,
            validation_first_mismatch_slot,
            validation_first_mismatch_expect_lod,
            validation_first_mismatch_expect_bx,
            validation_first_mismatch_expect_by,
            validation_first_mismatch_expect_bz,
            validation_first_mismatch_owner_lod,
            validation_first_mismatch_owner_bx,
            validation_first_mismatch_owner_by,
            validation_first_mismatch_owner_bz);
    }
}

validation_assert_known_good :: () {
    v := validation_frame;
    assert(v.scan_param_state_mismatches == 0, "Brickmap param/state mismatches=%", v.scan_param_state_mismatches);
    assert(v.scan_oob_atlas_refs == 0, "Brickmap OOB atlas refs=%", v.scan_oob_atlas_refs);
    assert(v.scan_negative_nonempty_refs == 0, "Brickmap negative nonempty refs=%", v.scan_negative_nonempty_refs);
    assert(v.scan_duplicate_atlas_refs == 0, "Brickmap duplicate atlas refs=%", v.scan_duplicate_atlas_refs);
    if v.scan_owner_mismatches > 0 && validation_first_mismatch_cell >= 0 {
        log_error("BRICKMAP_VAL first_owner_mismatch cell=% slot=% expect=(lod=% bx=% by=% bz=%) owner=(lod=% bx=% by=% bz=%)",
            validation_first_mismatch_cell,
            validation_first_mismatch_slot,
            validation_first_mismatch_expect_lod,
            validation_first_mismatch_expect_bx,
            validation_first_mismatch_expect_by,
            validation_first_mismatch_expect_bz,
            validation_first_mismatch_owner_lod,
            validation_first_mismatch_owner_bx,
            validation_first_mismatch_owner_by,
            validation_first_mismatch_owner_bz);
    }
    assert(v.scan_owner_mismatches == 0, "Brickmap slot owner mismatches=%", v.scan_owner_mismatches);
    assert(v.scan_owner_missing == 0, "Brickmap slot owner missing=%", v.scan_owner_missing);
    assert(v.scan_valid_unpublished == 0, "Brickmap valid but unpublished cells=%", v.scan_valid_unpublished);

    // If the scene has already built up a substantial cache, a sudden collapse to nearly-empty
    // after a synchronous rebuild is a correctness bug, not a transient we want to hide.
    if validation_max_nonempty_cells > 256 && params.cpu.edit_count > 100 {
        min_expected := max(validation_max_nonempty_cells / 4, 128);
        assert(v.scan_nonempty_cells >= min_expected,
            "Brickmap populated cells collapsed unexpectedly. current=% max_seen=% min_expected=%",
            v.scan_nonempty_cells, validation_max_nonempty_cells, min_expected);
    }
}

mouse_world_ray :: (resolution: Vector2, tan_half_fov: float,
    camera_pos: Vector3, camera_forward: Vector3, camera_right: Vector3, camera_up: Vector3,
    mouse_pos: Vector2, mouse_valid: bool) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if !mouse_valid return .{}, .{}, false;
    if resolution.x <= 1.0 || resolution.y <= 1.0 return .{}, .{}, false;

    // Input mouse coords are integer pixel locations; offset to pixel center to
    // match fragment shader sampling convention ((pixel + 0.5) / resolution).
    uv := Vector2.{(mouse_pos.x + 0.5) / resolution.x, (mouse_pos.y + 0.5) / resolution.y};
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
            hit_t := ray_edit_hit_t(ray_origin, ray_dir, node.edit_index);
            if hit_t >= 0.0 && hit_t < best_t {
                best_t = hit_t;
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

ray_sphere_hit_t :: (ray_origin: Vector3, ray_dir: Vector3, center: Vector3, radius: float) -> float {
    oc := ray_origin - center;
    b := dot(oc, ray_dir);
    c := dot(oc, oc) - radius * radius;
    h := b * b - c;
    if h < 0.0 return -1.0;
    s := sqrt(h);
    t0 := -b - s;
    t1 := -b + s;
    if t0 >= 0.0 return t0;
    if t1 >= 0.0 return t1;
    return -1.0;
}

ray_obb_hit_t :: (ray_origin: Vector3, ray_dir: Vector3, center: Vector3, rotation: Vector4, half_extents: Vector3) -> float {
    local_origin := inv_rotate_quat(ray_origin - center, rotation);
    local_dir := inv_rotate_quat(ray_dir, rotation);
    bounds := AABB.{min = -half_extents, max = half_extents};
    return ray_aabb_hit_t(local_origin, local_dir, bounds);
}

ray_edit_hit_t :: (ray_origin: Vector3, ray_dir: Vector3, edit_index: s32) -> float {
    if edit_index < 0 || cast(s64) edit_index >= edits_cpu.count return -1.0;
    e := edits_cpu[edit_index];

    if e.shape == {
    case .Sphere;
        return ray_sphere_hit_t(ray_origin, ray_dir, e.position, e.radius);
    case .Box;
        return ray_obb_hit_t(ray_origin, ray_dir, e.position, e.rotation, e.half_extents);
    }
    return -1.0;
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
    color := ifx e.op == .Subtract then Vector4.{0.98, 0.42, 0.30, 1.0} else Vector4.{0.30, 0.88, 0.98, 1.0};
    if e.shape == .Sphere {
        half_extents = .{e.radius, e.radius, e.radius};
    }
    return .{
        name = tprint("edit_%", edit_index),
        shape = ifx e.shape == .Sphere then Manip_Object_Shape.SPHERE else Manip_Object_Shape.BOX,
        position = e.position,
        rotation = .{x = e.rotation.x, y = e.rotation.y, z = e.rotation.z, w = e.rotation.w},
        scale = .{1.0, 1.0, 1.0},
        half_extents = half_extents,
        color = color,
    };
}

apply_manip_to_edit :: (edit_index: s32, obj: Manip_Object) {
    e := *edits_cpu[edit_index];

    new_position := obj.position;
    new_rotation := Quaternion.{obj.rotation.x, obj.rotation.y, obj.rotation.z, obj.rotation.w};
    if !vector3_is_finite(new_position) || !quat_is_finite(new_rotation) || !vector3_is_finite(obj.scale) || !vector3_is_finite(obj.half_extents) {
        log("BRICKMAP manip rejected invalid transform edit=% pos=% rot=% scale=% half=%",
            edit_index, new_position, new_rotation, obj.scale, obj.half_extents);
        return;
    }
    _ = normalize_or_identity(*new_rotation);

    if manip_ctx.mode == .TRANSLATE {
        e.position = new_position;
    } else if manip_ctx.mode == .ROTATE {
        e.rotation = .{new_rotation.x, new_rotation.y, new_rotation.z, new_rotation.w};
    } else {
        e.position = new_position;
        e.rotation = .{new_rotation.x, new_rotation.y, new_rotation.z, new_rotation.w};
    }

    effective_half := Vector3.{
        obj.half_extents.x * abs(obj.scale.x),
        obj.half_extents.y * abs(obj.scale.y),
        obj.half_extents.z * abs(obj.scale.z),
    };
    effective_half.x = max(effective_half.x, 0.02);
    effective_half.y = max(effective_half.y, 0.02);
    effective_half.z = max(effective_half.z, 0.02);
    if manip_ctx.mode == .SCALE {
        if #complete e.shape == {
        case .Sphere;
            r := max(max(effective_half.x, effective_half.y), effective_half.z);
            e.radius = max(r, 0.02);
            e.half_extents = .{e.radius, e.radius, e.radius};
        case .Box;
            e.half_extents = effective_half;
            e.radius = length(effective_half);
        }
    }
    edits_cpu[edit_index] = e;
}

sanitize_edit_for_gpu :: (e: *SDF_Edit, edit_index: s32) {
    if !vector3_is_finite(e.position) {
        log("BRICKMAP sanitize invalid edit position idx=% pos=%", edit_index, e.position);
        e.position = .{};
    }
    q := Quaternion.{e.rotation.x, e.rotation.y, e.rotation.z, e.rotation.w};
    if !quat_is_finite(q) {
        log("BRICKMAP sanitize invalid edit rotation idx=% rot=%", edit_index, q);
        q = .{w = 1.0};
    }
    _ = normalize_or_identity(*q);
    e.rotation = .{q.x, q.y, q.z, q.w};

    if !is_finite(e.radius) || e.radius < 0.02 {
        e.radius = 0.02;
    }

    if !vector3_is_finite(e.half_extents) {
        log("BRICKMAP sanitize invalid edit extents idx=% half=%", edit_index, e.half_extents);
        e.half_extents = .{e.radius, e.radius, e.radius};
    }
    e.half_extents.x = max(abs(e.half_extents.x), 0.02);
    e.half_extents.y = max(abs(e.half_extents.y), 0.02);
    e.half_extents.z = max(abs(e.half_extents.z), 0.02);
    if !is_finite(e.blend) || e.blend < 0.0 {
        e.blend = 0.0;
    }
}

vector3_is_finite :: (v: Vector3) -> bool {
    return is_finite(v.x) && is_finite(v.y) && is_finite(v.z);
}

quat_is_finite :: (q: Quaternion) -> bool {
    return is_finite(q.x) && is_finite(q.y) && is_finite(q.z) && is_finite(q.w);
}

normalize_or_zero :: (v: Vector3) -> Vector3 {
    len2 := length_squared(v);
    if len2 <= 1.0e-8 return .{};
    return v / sqrt(len2);
}

edit_focus_center_radius :: (edit_index: s32) -> (center: Vector3, radius: float) {
    if edit_index < 0 || cast(s64) edit_index >= edits_cpu.count return .{}, 1.0;
    e := edits_cpu[edit_index];
    if #complete e.shape == {
    case .Sphere;
        return e.position, max(e.radius, 0.08);
    case .Box;
        return e.position, max(length(e.half_extents), 0.08);
    }
    return e.position, max(e.radius, 0.08);
}

start_focus_on_edit :: (edit_index: s32) {
    using app;
    center, radius := edit_focus_center_radius(edit_index);
    fov_y := PI / 3.0;
    framed_distance := max(radius / max(tan(fov_y * 0.5), 0.0001) * 1.30, radius * 2.0);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
    desired_pos := center - cam_forward * framed_distance;
    look_dir := center - desired_pos;
    look_len := length(look_dir);
    look_n := ifx look_len > 0.000001 then look_dir / look_len else cam_forward;
    desired_yaw, desired_pitch := brickmap_camera_angles_from_forward(look_n);

    focus_from_pos = camera.position;
    focus_to_pos = desired_pos;
    focus_from_yaw = camera.yaw;
    focus_to_yaw = desired_yaw;
    focus_from_pitch = camera.pitch;
    focus_to_pitch = desired_pitch;
    focus_t = 0.0;
    focus_active = true;
}

focus_update_camera :: (dt: float) {
    using app;
    if !focus_active return;
    step := dt / max(focus_duration, 0.01);
    focus_t = clamp(focus_t + step, 0.0, 1.0);
    t := focus_t * focus_t * (3.0 - 2.0 * focus_t);
    camera.position = focus_from_pos + (focus_to_pos - focus_from_pos) * t;
    camera.yaw = lerp_angle_shortest(focus_from_yaw, focus_to_yaw, t);
    camera.pitch = clamp(focus_from_pitch + (focus_to_pitch - focus_from_pitch) * t, camera.pitch_min, camera.pitch_max);
    if focus_t >= 1.0 {
        focus_active = false;
    }
}

orbit_update_camera :: (mouse_pos: Vector2) {
    using app;
    if !orbit_have_prev_mouse {
        orbit_prev_mouse = mouse_pos;
        orbit_have_prev_mouse = true;
        return;
    }

    delta := mouse_pos - orbit_prev_mouse;
    orbit_prev_mouse = mouse_pos;
    if abs(delta.x) < 0.0001 && abs(delta.y) < 0.0001 return;

    camera.yaw += delta.x * camera.mouse_sensitivity;
    camera.pitch += delta.y * camera.mouse_sensitivity;
    camera.pitch = clamp(camera.pitch, camera.pitch_min, camera.pitch_max);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(*camera, *cam_forward, *cam_right, *cam_up);
    camera.position = orbit_target - cam_forward * orbit_distance;
}

lerp_angle_shortest :: (a: float, b: float, t: float) -> float {
    delta := b - a;
    while delta > PI delta -= PI * 2.0;
    while delta < -PI delta += PI * 2.0;
    return a + delta * t;
}

brickmap_camera_angles_from_forward :: (forward: Vector3) -> (yaw: float, pitch: float) {
    n := forward;
    normalize(*n, fallback = .{0.0, 0.0, -1.0});
    return atan2(n.x, -n.z), asin(clamp(n.y, -1.0, 1.0));
}

note_perf_sample :: (last_ms: *float, avg_ms: *float, sample_ms: float) {
    last_ms.* = sample_ms;
    if avg_ms.* <= 0.0 {
        avg_ms.* = sample_ms;
    } else {
        avg_ms.* = lerp(avg_ms.*, sample_ms, 0.08);
    }
}

brickmap_params_ring_index :: (frame_number: s64 = -1) -> s64 {
    if frame_number < 0 frame_number = cast(s64) gpu_submission_frame_index();
    idx := frame_number % BRICKMAP_PARAM_RING_SLOTS;
    if idx < 0 idx += BRICKMAP_PARAM_RING_SLOTS;
    return idx;
}

brickmap_params_ring_slot :: (ring: Gpu_View($T), frame_number: s64 = -1) -> Gpu_Buffer(T) #expand {
    idx := brickmap_params_ring_index(frame_number);
    return .{
        cpu = ring.cpu.data + idx,
        gpu = ring.gpu + (idx * size_of(T)).(Gpu_Ptr),
    };
}

brickmap_cache_slot :: (ring: Gpu_View($T), slot: s32) -> Gpu_Buffer(T) #expand {
    assert(slot >= 0 && slot < 2);
    return .{
        cpu = ring.cpu.data + slot,
        gpu = ring.gpu + (slot * size_of(T)).(Gpu_Ptr),
    };
}

set_active_cache_slot :: (slot: s32) {
    brickmap_active_cache_slot = slot;
    brickmap_state = brickmap_cache_slot(brickmap_state_ring, slot);
    brickmap_queues = brickmap_cache_slot(brickmap_queues_ring, slot);
    pointer_grid_cpu = brickmap_state.cpu.pointer_grid;
    pointer_grid_valid_cpu = brickmap_state.cpu.pointer_grid_valid;
    pointer_grid_publish_cpu = brickmap_state.cpu.pointer_grid_publish_frame;
    pointer_grid_generation_cpu = brickmap_state.cpu.pointer_grid_generation;
}
