#import "Jai-Shader-Transpiler";
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";

// Logical SDF voxels per brick edge (without border texels).
BRICKMAP_BRICK_RES :: 8;
// Brick edge size in atlas texels, including a 1-voxel border on each side.
BRICKMAP_BRICK_TEX_RES :: BRICKMAP_BRICK_RES + 2;
// Number of logical voxels evaluated per brick.
BRICKMAP_BRICK_VOXELS :: BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES;
// Number of atlas texels written per brick (including borders).
BRICKMAP_BRICK_TEXELS :: BRICKMAP_BRICK_TEX_RES * BRICKMAP_BRICK_TEX_RES * BRICKMAP_BRICK_TEX_RES;
// Brick cells per clipmap edge for each LOD grid.
BRICKMAP_GRID_RES :: 24;
// Total brick cells per LOD grid.
BRICKMAP_GRID_CELLS :: BRICKMAP_GRID_RES * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
// Number of clipmap LOD levels sampled/baked.
BRICKMAP_LOD_COUNT :: 4;
BRICKMAP_TOTAL_GRID_CELLS :: BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS;
// Max editable SDF primitives packed into params.
BRICKMAP_MAX_EDITS :: 5000;
// Atlas brick count along XYZ.
BRICKMAP_ATLAS_BRICKS_X :: 64;
BRICKMAP_ATLAS_BRICKS_Y :: 32;
BRICKMAP_ATLAS_BRICKS_Z :: 64;
// Total number of addressable atlas brick slots.
BRICKMAP_MAX_BRICKS :: BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_ATLAS_BRICKS_Y * BRICKMAP_ATLAS_BRICKS_Z;
// Max dirty-brick work items processed in one dispatch batch.
BRICKMAP_MAX_DIRTY_BRICKS :: 1024;
// Atlas texture width/height/depth in texels.
BRICKMAP_ATLAS_DIM_X :: BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_ATLAS_DIM_Y :: BRICKMAP_ATLAS_BRICKS_Y * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_ATLAS_DIM_Z :: BRICKMAP_ATLAS_BRICKS_Z * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_MAX_QUEUE_ITEMS :: BRICKMAP_TOTAL_GRID_CELLS;

SDF_Shape :: enum u32 {
    Sphere :: 0;
    Box :: 1;
}

SDF_Op :: enum u32 {
    Union :: 0;
    Subtract :: 1;
    Intersect :: 2;
}

Brickmap_Lod_Info :: struct {
    origin_brick: IVector3;
    _pad0: s32;
    voxel_size: float;
    _pad1: float;
    _pad2: float;
    _pad3: float;
}

SDF_Edit :: struct {
    shape: SDF_Shape;
    op: SDF_Op;
    _pad0: u32;
    _pad1: u32;

    position: Vector3;
    radius: float;

    half_extents: Vector3;
    blend: float;

    rotation: Vector4;
    albedo: Vector4;
}

Brick_Request :: struct {
    lod: u32;
    brick_x: s32;
    brick_y: s32;
    brick_z: s32;
    atlas_index: u32;
    generation: u32;
    _pad0: u32;
    _pad1: u32;
}

Brickmap_Indirect_Dispatch_Pair :: struct {
    bake_x: u32;
    bake_y: u32;
    bake_z: u32;
    publish_x: u32;
    publish_y: u32;
    publish_z: u32;
}

Brickmap_State :: struct {
    pointer_grid: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] s32;
    pointer_grid_valid: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    pointer_grid_publish_frame: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    pointer_grid_generation: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    slot_owner_lod: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_bx: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_by: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_bz: [BRICKMAP_MAX_BRICKS] s32;
    slot_generation: [BRICKMAP_MAX_BRICKS] u32;
}

Brickmap_Work_Queues :: struct {
    dirty_flags: [BRICKMAP_TOTAL_GRID_CELLS] u32;
    candidate_count: u32;
    bake_count: u32;
    _pad0: [2] u32;
    candidates: [BRICKMAP_MAX_QUEUE_ITEMS] Brick_Request;
    bake: [BRICKMAP_MAX_QUEUE_ITEMS] Brick_Request;
}

Brickmap_Params :: struct {
    resolution: Vector2;
    camera_fov_y: float;
    camera_tan_half_fov: float;
    time: float;

    view_proj: Matrix4;
    prev_view_proj: Matrix4;

    camera_pos: Vector3;
    _cam_pad0: float;
    camera_forward: Vector3;
    _cam_pad1: float;
    camera_right: Vector3;
    _cam_pad2: float;
    camera_up: Vector3;
    _cam_pad3: float;

    edit_count: u32;
    dirty_count: u32;
    atlas_alloc_next: u32;
    atlas_texture_index: u32;
    atlas_albedo_texture_index: u32;
    atlas_sampler_linear_index: u32;
    atlas_sampler_point_index: u32;
    use_cache_raymarch: u32;
    use_hw_interp: u32;
    atlas_debug_overlay: u32;
    atlas_debug_fullscreen: u32;
    pointer_grid_debug: u32;
    bake_debug_gradient: u32;
    cache_debug_show_selected_lod: u32;
    cache_debug_show_distance: u32;
    cache_debug_show_cell_state: u32;
    debug_force_flat_color: u32;
    cache_force_lod0: u32;
    atlas_debug_slice: float;
    frame_index: u32;
    _pad_frame_index0: u32;
    _pad_frame_index1: u32;
    _pad_frame_index2: u32;
    debug_classify_candidates: u32;
    debug_classify_surface: u32;
    debug_classify_existing: u32;
    debug_classify_new_alloc: u32;
    debug_classify_rejected_capacity: u32;
    debug_classify_out_count: u32;
    debug_bake_total_voxels: u32;
    debug_bake_bricks_touched: u32;
    debug_bake_min_atlas: u32;
    debug_bake_max_atlas: u32;
    debug_watch_edit_index: u32;
    debug_gpu_seen_edit_count: u32;
    debug_gpu_seen_watch_shape: u32;
    debug_gpu_seen_watch_op: u32;
    full_rebuild_requested: u32;
    _pad4: [2] u32;
    debug_gpu_seen_watch_pos_radius: Vector4;
    debug_gpu_scene_at_camera: float;
    debug_gpu_scene_at_watch_center: float;
    _pad_debug_probe0: u32;
    _pad_debug_probe1: u32;
    debug_bake_seen_atlas: [BRICKMAP_MAX_DIRTY_BRICKS] u32;
    pointer_grid: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] s32;
    pointer_grid_valid: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    pointer_grid_publish_frame: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    pointer_grid_generation: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] u32;
    slot_owner_lod: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_bx: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_by: [BRICKMAP_MAX_BRICKS] s32;
    slot_owner_bz: [BRICKMAP_MAX_BRICKS] s32;
    slot_generation: [BRICKMAP_MAX_BRICKS] u32;
    prev_lod_origin_brick_x: [BRICKMAP_LOD_COUNT] s32;
    prev_lod_origin_brick_y: [BRICKMAP_LOD_COUNT] s32;
    prev_lod_origin_brick_z: [BRICKMAP_LOD_COUNT] s32;
    lod_origin_brick_x: [BRICKMAP_LOD_COUNT] s32;
    lod_origin_brick_y: [BRICKMAP_LOD_COUNT] s32;
    lod_origin_brick_z: [BRICKMAP_LOD_COUNT] s32;
    lod_voxel_size: [BRICKMAP_LOD_COUNT] float;
    edit_shape: [BRICKMAP_MAX_EDITS] SDF_Shape;
    edit_op: [BRICKMAP_MAX_EDITS] SDF_Op;
    edit_pos_radius: [BRICKMAP_MAX_EDITS] Vector4;
    edit_half_extents_blend: [BRICKMAP_MAX_EDITS] Vector4;
    edit_rotation: [BRICKMAP_MAX_EDITS] Vector4;
    edit_albedo: [BRICKMAP_MAX_EDITS] Vector4;
}

Brickmap_Render_Params :: struct {
    resolution: Vector2;
    camera_fov_y: float;
    camera_tan_half_fov: float;
    time: float;

    view_proj: Matrix4;
    prev_view_proj: Matrix4;
    cache_state: *Brickmap_State;
    _cache_state_pad0: u64;

    camera_pos: Vector3;
    _cam_pad0: float;
    camera_forward: Vector3;
    _cam_pad1: float;
    camera_right: Vector3;
    _cam_pad2: float;
    camera_up: Vector3;
    _cam_pad3: float;

    atlas_texture_index: u32;
    atlas_albedo_texture_index: u32;
    atlas_sampler_linear_index: u32;
    atlas_sampler_point_index: u32;
    use_cache_raymarch: u32;
    use_hw_interp: u32;
    atlas_debug_overlay: u32;
    atlas_debug_fullscreen: u32;
    pointer_grid_debug: u32;
    bake_debug_gradient: u32;
    cache_debug_show_selected_lod: u32;
    cache_debug_show_distance: u32;
    cache_debug_show_cell_state: u32;
    debug_force_flat_color: u32;
    cache_force_lod0: u32;
    atlas_debug_slice: float;
    frame_index: u32;
    _pad_frame_index0: u32;
    _pad_frame_index1: u32;
    lod0_origin_brick_x: s32;
    lod0_origin_brick_y: s32;
    lod0_origin_brick_z: s32;
    _lod0_pad0: u32;
    lod1_origin_brick_x: s32;
    lod1_origin_brick_y: s32;
    lod1_origin_brick_z: s32;
    _lod1_pad0: u32;
    lod2_origin_brick_x: s32;
    lod2_origin_brick_y: s32;
    lod2_origin_brick_z: s32;
    _lod2_pad0: u32;
    lod3_origin_brick_x: s32;
    lod3_origin_brick_y: s32;
    lod3_origin_brick_z: s32;
    _lod3_pad0: u32;
    lod0_voxel_size: float;
    lod1_voxel_size: float;
    lod2_voxel_size: float;
    lod3_voxel_size: float;
}

Brickmap_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Brickmap_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Brickmap_Fragment_In :: struct {
    uv: Vector2;
}

Brickmap_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Brickmap_Blit_Params :: struct {
    source_texture_index: u32;
    source_sampler_index: u32;
}

brickmap_vertex_main :: (using in: Brickmap_Vertex_In, params: *Brickmap_Params) -> Brickmap_Vertex_Out {
    using out: Brickmap_Vertex_Out;
    _ = params.frame_index;

    pos: Vector2;
    if vertex_id == 0 {
        pos = .{-1.0, -1.0};
    } else if vertex_id == 1 {
        pos = .{3.0, -1.0};
    } else {
        pos = .{-1.0, 3.0};
    }

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

brickmap_blit_vertex_main :: (using in: Brickmap_Vertex_In) -> Brickmap_Vertex_Out {
    using out: Brickmap_Vertex_Out;

    pos: Vector2;
    if vertex_id == 0 {
        pos = .{-1.0, -1.0};
    } else if vertex_id == 1 {
        pos = .{3.0, -1.0};
    } else {
        pos = .{-1.0, 3.0};
    }

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

brickmap_blit_fragment_main :: (using in: Brickmap_Fragment_In, params: *Brickmap_Blit_Params) -> struct { out_color: Vector4; } {
    c := sample_2d(params.source_texture_index, params.source_sampler_index, .{uv.x, 1.0 - uv.y});
    return .{out_color = c};
} @fragment_shader

safe_normalize :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 <= 0.000001 return .{0.0, 1.0, 0.0};
    return v * (1.0 / sqrt(len2));
}

rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    t := cross(q.xyz, v) * 2.0;
    return v + t * q.w + cross(q.xyz, t);
}

inv_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    qc := Vector4.{-q.x, -q.y, -q.z, q.w};
    return rotate_quat(v, qc);
}

sdf_sphere :: (p: Vector3, radius: float) -> float {
    return sqrt(dot(p, p)) - radius;
}

sdf_box :: (p: Vector3, b: Vector3) -> float {
    q := Vector3.{abs(p.x) - b.x, abs(p.y) - b.y, abs(p.z) - b.z};
    outside := Vector3.{max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0)};
    outside_len := sqrt(dot(outside, outside));
    inside := min(max(q.x, max(q.y, q.z)), 0.0);
    return outside_len + inside;
}

smooth_min :: (a: float, b: float, k: float) -> float {
    if k <= 0.00001 return min(a, b);
    h := clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

smooth_max :: (a: float, b: float, k: float) -> float {
    if k <= 0.00001 return max(a, b);
    h := clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

eval_edits_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    d := cast(float) 100000.0;
    count := cast(s32) params.edit_count;
    for i: 0..count-1 {
        op := params.edit_op[i];
        pos_radius := params.edit_pos_radius[i];
        extents_blend := params.edit_half_extents_blend[i];
        blend := max(extents_blend.w, 0.0);
        rot := params.edit_rotation[i];
        q := inv_rotate_quat(p - pos_radius.xyz, rot);

        sd: float;
        if #complete params.edit_shape[i] == {
        case .Box;
            sd = sdf_box(q, extents_blend.xyz);
        case .Sphere;
            sd = sdf_sphere(q, pos_radius.w);
        }

        if #complete op == {
        case .Union;     d = smooth_min(d, sd, blend);
        case .Subtract;  d = smooth_max(d, -sd, blend);
        case .Intersect; d = smooth_max(d, sd, blend);
        }
    }

    return d;
}


eval_edits_sdf_albedo :: (params: *Brickmap_Params, p: Vector3) -> Vector4 {
    d := cast(float) 100000.0;
    albedo := Vector3.{0.48, 0.52, 0.58};
    count := cast(s32) params.edit_count;
    for i: 0..count-1 {
        op := params.edit_op[i];
        pos_radius := params.edit_pos_radius[i];
        extents_blend := params.edit_half_extents_blend[i];
        blend := max(extents_blend.w, 0.0);
        rot := params.edit_rotation[i];
        q := inv_rotate_quat(p - pos_radius.xyz, rot);

        sd: float;
        if #complete params.edit_shape[i] == {
        case .Box;
            sd = sdf_box(q, extents_blend.xyz);
        case .Sphere;
            sd = sdf_sphere(q, pos_radius.w);
        }

        edit_color := params.edit_albedo[i].xyz;
        if #complete op == {
        case .Union;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (sd - d) / blend, 0.0, 1.0);
                d = smooth_min(d, sd, blend);
                albedo = mix(edit_color, albedo, h);
            } else {
                if sd < d {
                    d = sd;
                    albedo = edit_color;
                }
            }
        case .Subtract;
            sub_d := -sd;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (d - sub_d) / blend, 0.0, 1.0);
                d = smooth_max(d, sub_d, blend);
                albedo = mix(edit_color, albedo, h);
            } else {
                if sub_d > d {
                    d = sub_d;
                    albedo = edit_color;
                }
            }
        case .Intersect;
            if blend > 0.00001 {
                h := clamp(0.5 + 0.5 * (d - sd) / blend, 0.0, 1.0);
                d = smooth_max(d, sd, blend);
                albedo = mix(edit_color, albedo, h);
            } else {
                if sd > d {
                    d = sd;
                    albedo = edit_color;
                }
            }
        }
    }

    return .{d, albedo.x, albedo.y, albedo.z};
}


eval_scene_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    d := eval_edits_sdf(params, p);
    ground := p.y + 1.2;
    return min(d, ground);
}


atlas_brick_coord :: (atlas_index: s32) -> Vector3 {
    x := atlas_index % BRICKMAP_ATLAS_BRICKS_X;
    y := (atlas_index / BRICKMAP_ATLAS_BRICKS_X) % BRICKMAP_ATLAS_BRICKS_Y;
    z := atlas_index / (BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_ATLAS_BRICKS_Y);
    return .{cast(float) x, cast(float) y, cast(float) z};
}

sample_brick_filtered :: (params: *Brickmap_Params, atlas_index: s32, uvw: Vector3) -> float {
    brick := atlas_brick_coord(atlas_index);
    local := Vector3.{
        // uvw is in voxel-center space (0 = first center, 7 = last center).
        // Allow half-voxel overreach so the duplicated 1-voxel border participates in filtering.
        clamp(uvw.x, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
        clamp(uvw.y, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
        clamp(uvw.z, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
    };

    base_texel := brick * cast(float) BRICKMAP_BRICK_TEX_RES;
    texel := base_texel + .{
        1.0 + local.x,
        1.0 + local.y,
        1.0 + local.z,
    };

    uvw_norm := Vector3.{
        (texel.x + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_X,
        (texel.y + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_Y,
        (texel.z + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_Z,
    };
    sampler_index := ifx params.use_hw_interp != 0 then params.atlas_sampler_linear_index else params.atlas_sampler_point_index;
    return sample_3d(params.atlas_texture_index, sampler_index, uvw_norm).x;
}

sample_brick_albedo_filtered :: (params: *Brickmap_Params, atlas_index: s32, uvw: Vector3) -> Vector3 {
    brick := atlas_brick_coord(atlas_index);
    local := Vector3.{
        clamp(uvw.x, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
        clamp(uvw.y, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
        clamp(uvw.z, -0.5, cast(float) (BRICKMAP_BRICK_RES - 1) + 0.5),
    };

    base_texel := brick * cast(float) BRICKMAP_BRICK_TEX_RES;
    texel := base_texel + .{
        1.0 + local.x,
        1.0 + local.y,
        1.0 + local.z,
    };

    uvw_norm := Vector3.{
        (texel.x + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_X,
        (texel.y + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_Y,
        (texel.z + 0.5) / cast(float) BRICKMAP_ATLAS_DIM_Z,
    };
    sampler_index := ifx params.use_hw_interp != 0 then params.atlas_sampler_linear_index else params.atlas_sampler_point_index;
    return sample_3d(params.atlas_albedo_texture_index, sampler_index, uvw_norm).xyz;
}

sample_cached_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    s := sample_cached(params, p);
    lod := cast(s32) s.y;
    if lod < 0 return 100000.0;
    return s.x;
}

sample_cached :: (params: *Brickmap_Params, p: Vector3) -> Vector4 {
    max_lod := BRICKMAP_LOD_COUNT;
    if params.cache_force_lod0 != 0 {
        max_lod = 1;
    }
    fallback_lod: s32 = -1;
    fallback_voxel := max(render_lod_voxel_size(params, 0), 0.0001);
    for lod_i: 0..max_lod-1 {
        lod := cast(s32) lod_i;
        voxel_size := max(render_lod_voxel_size(params, lod), 0.0001);

        gx := p.x / voxel_size;
        gy := p.y / voxel_size;
        gz := p.z / voxel_size;

        bx := cast(s32) floor(gx / cast(float) BRICKMAP_BRICK_RES);
        by := cast(s32) floor(gy / cast(float) BRICKMAP_BRICK_RES);
        bz := cast(s32) floor(gz / cast(float) BRICKMAP_BRICK_RES);

        lx := bx - render_lod_origin_brick_x(params, lod);
        ly := by - render_lod_origin_brick_y(params, lod);
        lz := bz - render_lod_origin_brick_z(params, lod);

        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;

        ptr_base := lod * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        if params.pointer_grid_valid[ptr_idx] == 0 {
            if fallback_lod < 0 {
                fallback_lod = lod;
                fallback_voxel = voxel_size;
            }
            continue;
        }
        atlas_index := params.pointer_grid[ptr_idx];
        if atlas_index < 0 {
            if fallback_lod < 0 {
                fallback_lod = lod;
                fallback_voxel = voxel_size;
            }
            continue;
        }
        // Convert to voxel-center space (matching bake positions at +0.5 voxel).
        local_x := gx - cast(float) (bx * BRICKMAP_BRICK_RES) - 0.5;
        local_y := gy - cast(float) (by * BRICKMAP_BRICK_RES) - 0.5;
        local_z := gz - cast(float) (bz * BRICKMAP_BRICK_RES) - 0.5;
        d := sample_brick_filtered(params, atlas_index, .{local_x, local_y, local_z});
        return .{d, cast(float) lod, voxel_size, 1.0};
    }

    if fallback_lod >= 0 {
        return .{100000.0, cast(float) fallback_lod, fallback_voxel, 0.0};
    }
    return .{100000.0, -1.0, max(render_lod_voxel_size(params, 0), 0.0001), 0.0};
}

sample_cached_lod :: (params: *Brickmap_Params, p: Vector3) -> s32 {
    return cast(s32) sample_cached(params, p).y;
}

sample_cached_albedo :: (params: *Brickmap_Params, p: Vector3) -> Vector3 {
    max_lod := BRICKMAP_LOD_COUNT;
    if params.cache_force_lod0 != 0 {
        max_lod = 1;
    }
    for lod_i: 0..max_lod-1 {
        lod := cast(s32) lod_i;
        voxel_size := max(render_lod_voxel_size(params, lod), 0.0001);

        gx := p.x / voxel_size;
        gy := p.y / voxel_size;
        gz := p.z / voxel_size;

        bx := cast(s32) floor(gx / cast(float) BRICKMAP_BRICK_RES);
        by := cast(s32) floor(gy / cast(float) BRICKMAP_BRICK_RES);
        bz := cast(s32) floor(gz / cast(float) BRICKMAP_BRICK_RES);

        lx := bx - render_lod_origin_brick_x(params, lod);
        ly := by - render_lod_origin_brick_y(params, lod);
        lz := bz - render_lod_origin_brick_z(params, lod);

        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;

        ptr_base := lod * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        if params.pointer_grid_valid[ptr_idx] == 0 continue;
        atlas_index := params.pointer_grid[ptr_idx];
        if atlas_index < 0 continue;
        local_x := gx - cast(float) (bx * BRICKMAP_BRICK_RES) - 0.5;
        local_y := gy - cast(float) (by * BRICKMAP_BRICK_RES) - 0.5;
        local_z := gz - cast(float) (bz * BRICKMAP_BRICK_RES) - 0.5;
        return sample_brick_albedo_filtered(params, atlas_index, .{local_x, local_y, local_z});
    }

    return .{0.48, 0.52, 0.58};
}

step_to_next_lod_cell :: (params: *Brickmap_Params, p: Vector3, rd: Vector3, lod: s32) -> float {
    sample_lod := clamp(lod, 0, BRICKMAP_LOD_COUNT - 1);
    voxel_size := max(render_lod_voxel_size(params, sample_lod), 0.0001);
    cell_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;
    gx := p.x / cell_size;
    gy := p.y / cell_size;
    gz := p.z / cell_size;
    fx := gx - floor(gx);
    fy := gy - floor(gy);
    fz := gz - floor(gz);

    t_x := 100000.0;
    if rd.x > 0.000001 {
        t_x = ((1.0 - fx) * cell_size) / rd.x;
    } else if rd.x < -0.000001 {
        t_x = (fx * cell_size) / -rd.x;
    }

    t_y := 100000.0;
    if rd.y > 0.000001 {
        t_y = ((1.0 - fy) * cell_size) / rd.y;
    } else if rd.y < -0.000001 {
        t_y = (fy * cell_size) / -rd.y;
    }

    t_z := 100000.0;
    if rd.z > 0.000001 {
        t_z = ((1.0 - fz) * cell_size) / rd.z;
    } else if rd.z < -0.000001 {
        t_z = (fz * cell_size) / -rd.z;
    }

    t_min := min(t_x, min(t_y, t_z));
    return max(t_min + 0.0005, 0.0025);
}

step_to_next_lod0_cell :: (params: *Brickmap_Params, p: Vector3, rd: Vector3) -> float {
    return step_to_next_lod_cell(params, p, rd, 0);
}

brick_has_surface :: (params: *Brickmap_Params, lod: s32, bx: s32, by: s32, bz: s32) -> bool {
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return false;
    voxel_size := max(params.lod_voxel_size[lod], 0.0001);
    brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

    min_p := Vector3.{
        cast(float) bx * brick_world_size,
        cast(float) by * brick_world_size,
        cast(float) bz * brick_world_size,
    };
    max_p := min_p + .{brick_world_size, brick_world_size, brick_world_size};
    min_d:     float = 100000.0;
    max_d:     float = -100000.0;
    min_abs_d: float = 100000.0;

    // Be conservative here. False negatives create visible holes/chopped geometry when
    // dirty cells are reclassified after edits or clipmap churn. A denser 3x3x3 test is
    // cheap compared to a missed brick.
    for sz_i: 0..2 {
        sz := cast(float) sz_i * 0.5;
        pz := lerp(min_p.z, max_p.z, sz);
        for sy_i: 0..2 {
            sy := cast(float) sy_i * 0.5;
            py := lerp(min_p.y, max_p.y, sy);
            for sx_i: 0..2 {
                sx := cast(float) sx_i * 0.5;
                px := lerp(min_p.x, max_p.x, sx);
                d := eval_edits_sdf(params, .{px, py, pz});
                if d < min_d min_d = d;
                if d > max_d max_d = d;
                if abs(d) < min_abs_d min_abs_d = abs(d);
            }
        }
    }

    if min_d <= 0.0 && max_d >= 0.0 return true;
    MARGIN :: 1.75;
    return min_abs_d <= voxel_size * MARGIN;
}

scene_normal :: (params: *Brickmap_Params, p: Vector3) -> Vector3 {
    eps := 0.02;
    dpx := eval_scene_sdf(params, p + .{eps, 0.0, 0.0});
    dnx := eval_scene_sdf(params, p - .{eps, 0.0, 0.0});
    dpy := eval_scene_sdf(params, p + .{0.0, eps, 0.0});
    dny := eval_scene_sdf(params, p - .{0.0, eps, 0.0});
    dpz := eval_scene_sdf(params, p + .{0.0, 0.0, eps});
    dnz := eval_scene_sdf(params, p - .{0.0, 0.0, eps});
    return safe_normalize(.{dpx - dnx, dpy - dny, dpz - dnz});
}


cached_normal :: (params: *Brickmap_Params, p: Vector3, voxel: float) -> Vector3 {
    // TODO(brickmap-quality/perf):
    // Prefer seam-aware cached-field gradient as the default normal path:
    // 1) Sample across brick borders with guard/border texels + consistent atlas-space epsilon.
    // 2) Add confidence/fallback only when cached samples are invalid, to avoid noisy seams.
    // 3) If still too expensive, evaluate baking a compact gradient/normal into atlas (e.g. oct-encoded),
    //    but keep memory/bandwidth tradeoffs explicit versus deriving from SDF samples.
    eps := max(voxel * 0.45, 0.02);
    s_px := sample_cached(params, p + .{eps, 0.0, 0.0});
    s_nx := sample_cached(params, p - .{eps, 0.0, 0.0});
    s_py := sample_cached(params, p + .{0.0, eps, 0.0});
    s_ny := sample_cached(params, p - .{0.0, eps, 0.0});
    s_pz := sample_cached(params, p + .{0.0, 0.0, eps});
    s_nz := sample_cached(params, p - .{0.0, 0.0, eps});
    if cast(s32) s_px.y < 0 || cast(s32) s_nx.y < 0 || cast(s32) s_py.y < 0 || cast(s32) s_ny.y < 0 || cast(s32) s_pz.y < 0 || cast(s32) s_nz.y < 0 {
        return .{0.0, 1.0, 0.0};
    }
    return safe_normalize(.{s_px.x - s_nx.x, s_py.x - s_ny.x, s_pz.x - s_nz.x});
}

brickmap_project_screen_px :: (view_proj: Matrix4, world_pos: Vector3, resolution: Vector2) -> Vector2 {
    clip := view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    if abs(clip.w) <= 0.00001 return .{-100000.0, -100000.0};
    ndc_xy := clip.xy * (1.0 / clip.w);
    return .{
        (ndc_xy.x * 0.5 + 0.5) * resolution.x,
        (1.0 - (ndc_xy.y * 0.5 + 0.5)) * resolution.y,
    };
}

brickmap_project_depth01 :: (view_proj: Matrix4, world_pos: Vector3) -> float {
    clip := view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    if abs(clip.w) <= 0.00001 return 1.0;
    ndc_z := clip.z / clip.w;
    return clamp(ndc_z * 0.5 + 0.5, 0.0, 1.0);
}

render_lod_origin_brick_x :: inline (params: *Brickmap_Render_Params, lod: s32) -> s32 {
    if lod == {
    case 0; return params.lod0_origin_brick_x;
    case 1; return params.lod1_origin_brick_x;
    case 2; return params.lod2_origin_brick_x;
    case 3; return params.lod3_origin_brick_x;
    }
    return params.lod3_origin_brick_x;
}

render_lod_origin_brick_y :: inline (params: *Brickmap_Render_Params, lod: s32) -> s32 {
    if lod == {
    case 0; return params.lod0_origin_brick_y;
    case 1; return params.lod1_origin_brick_y;
    case 2; return params.lod2_origin_brick_y;
    case 3; return params.lod3_origin_brick_y;
    }
    return params.lod3_origin_brick_y;
}

render_lod_origin_brick_z :: inline (params: *Brickmap_Render_Params, lod: s32) -> s32 {
    if lod == {
    case 0; return params.lod0_origin_brick_z;
    case 1; return params.lod1_origin_brick_z;
    case 2; return params.lod2_origin_brick_z;
    case 3; return params.lod3_origin_brick_z;
    }
    return params.lod3_origin_brick_z;
}

render_lod_voxel_size :: inline (params: *Brickmap_Render_Params, lod: s32) -> float {
    if lod == {
    case 0; return params.lod0_voxel_size;
    case 1; return params.lod1_voxel_size;
    case 2; return params.lod2_voxel_size;
    case 3; return params.lod3_voxel_size;
    }
    return params.lod3_voxel_size;
}

render_lod_origin_brick_x :: inline (params: *Brickmap_Params, lod: s32) -> s32 {
    return params.lod_origin_brick_x[lod];
}

render_lod_origin_brick_y :: inline (params: *Brickmap_Params, lod: s32) -> s32 {
    return params.lod_origin_brick_y[lod];
}

render_lod_origin_brick_z :: inline (params: *Brickmap_Params, lod: s32) -> s32 {
    return params.lod_origin_brick_z[lod];
}

render_lod_voxel_size :: inline (params: *Brickmap_Params, lod: s32) -> float {
    return params.lod_voxel_size[lod];
}

brickmap_fragment_main :: (using in: Brickmap_Fragment_In, params: *Brickmap_Params) -> struct { out_color: Vector4; } {
    if params.debug_force_flat_color != 0 {
        return .{out_color = .{0.22, 0.35, 0.58, 1.0}};
    }

    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    denom := max(params.resolution.y, 1.0);
    aspect := params.resolution.x / denom;
    p.x *= aspect;

    tan_half := params.camera_tan_half_fov;
    ro := params.camera_pos;
    rd := safe_normalize(params.camera_forward + params.camera_right * (p.x * tan_half) + params.camera_up * (p.y * tan_half));

    if params.atlas_debug_fullscreen != 0 {
        debug_uvw := Vector3.{uv.x, uv.y, clamp(params.atlas_debug_slice, 0.0, 1.0)};
        d := sample_3d(params.atlas_texture_index, params.atlas_sampler_point_index, debug_uvw).x;
        g := clamp(0.5 + d * 0.35, 0.0, 1.0);
        return .{out_color = .{g, g, g, 1.0}};
    }

    if params.pointer_grid_debug != 0 && uv.x > 0.72 && uv.y < 0.28 {
        map_uv := Vector2.{(uv.x - 0.72) / 0.28, uv.y / 0.28};
        gx := clamp(cast(s32) floor(map_uv.x * cast(float) BRICKMAP_GRID_RES), 0, BRICKMAP_GRID_RES - 1);
        gy := clamp(cast(s32) floor(map_uv.y * cast(float) BRICKMAP_GRID_RES), 0, BRICKMAP_GRID_RES - 1);

        voxel_size := max(render_lod_voxel_size(params, 0), 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;
        bz := cast(s32) floor(params.camera_pos.z / brick_world_size);
        lz := bz - render_lod_origin_brick_z(params, 0);

        if lz < 0 || lz >= BRICKMAP_GRID_RES {
            return .{out_color = .{0.12, 0.12, 0.12, 1.0}};
        }

        ptr_base := 0 * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + gx + gy * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        atlas_index := params.pointer_grid[ptr_idx];
        occupied := atlas_index >= 0 && params.pointer_grid_valid[ptr_idx] != 0;
        occ := ifx occupied then 1.0 else 0.0;
        idx_t := clamp(cast(float) max(atlas_index, 0) / cast(float) BRICKMAP_MAX_BRICKS, 0.0, 1.0);
        c := mix(Vector3.{0.08, 0.08, 0.08}, Vector3.{0.15, 0.95, 0.35}, occ);
        c = mix(c, Vector3.{1.0, 0.45, 0.15}, idx_t * 0.5);

        grid_x := abs(fract(map_uv.x * cast(float) BRICKMAP_GRID_RES) - 0.5) * 2.0;
        grid_y := abs(fract(map_uv.y * cast(float) BRICKMAP_GRID_RES) - 0.5) * 2.0;
        line := 1.0 - clamp(min(grid_x, grid_y) * 40.0, 0.0, 1.0);
        c = mix(c, Vector3.{1.0, 1.0, 1.0}, line * 0.2);
        return .{out_color = .{c.x, c.y, c.z, 1.0}};
    }

    if params.atlas_debug_overlay != 0 && uv.x < 0.28 && uv.y < 0.28 {
        debug_uvw := Vector3.{uv.x / 0.28, uv.y / 0.28, clamp(params.atlas_debug_slice, 0.0, 1.0)};
        d := sample_3d(params.atlas_texture_index, params.atlas_sampler_point_index, debug_uvw).x;
        g := clamp(0.5 + d * 0.35, 0.0, 1.0);
        grid_x := abs(fract(debug_uvw.x * 8.0) - 0.5) * 2.0;
        grid_y := abs(fract(debug_uvw.y * 8.0) - 0.5) * 2.0;
        line := 1.0 - clamp(min(grid_x, grid_y) * 20.0, 0.0, 1.0);
        c := mix(Vector3.{g, g, g}, Vector3.{1.0, 0.35, 0.15}, line * 0.35);
        return .{out_color = .{c.x, c.y, c.z, 1.0}};
    }

    t := 0.0;
    hit := false;
    min_hit_eps := 0.003;
    use_cache := true;
    hit_lod: s32 = -1;
    hit_voxel := max(render_lod_voxel_size(params, 0), 0.0001);
    hit_cached_d := 0.0;
    hit_is_ground := false;
    prev_d := cast(float) 100000.0;
    for 0..219 {
        pos := ro + rd * t;
        sample_lod: s32 = -1;
        d: float;
        d_ground := pos.y + 1.2;
        non_ground_d := cast(float) 100000.0;
        if use_cache {
            cached := sample_cached(params, pos);
            d_cached := cached.x;
            sample_lod = cast(s32) cached.y;
            sample_voxel := cached.z;
            cache_valid := cached.w != 0.0;
            if sample_lod >= 0 {
                hit_voxel = sample_voxel;
            }
            if sample_lod >= 0 && cache_valid {
                // Bias sampled distance slightly inward to counter
                // non-conservative interpolation on coarse voxels.
                d_cached -= sample_voxel * INWARD_SAMPLED_BIAS;
                non_ground_d = d_cached;
                d = min(non_ground_d, d_ground);
            } else if sample_lod >= 0 {
                d_skip := step_to_next_lod_cell(params, pos, rd, sample_lod);
                non_ground_d = 100000.0;
                d = min(d_skip, d_ground);
                if d_ground < min_hit_eps {
                    hit_is_ground = true;
                    hit = true;
                    break;
                }
                t += max(d_skip, 0.0035);
                prev_d = d_skip;
                if t > 80.0 break;
                continue;
            } else {
                d_skip := step_to_next_lod0_cell(params, pos, rd);
                non_ground_d = 100000.0;
                d = min(d_skip, d_ground);
                // On cache miss, never treat cell-boundary skip distance as a surface hit.
                if d_ground < min_hit_eps {
                    hit_is_ground = true;
                    hit = true;
                    break;
                }
                t += max(d_skip, 0.0035);
                prev_d = d_skip;
                if t > 80.0 break;
                continue;
            }
            hit_lod = sample_lod;
            hit_cached_d = d_cached;
        }

        hit_eps := min_hit_eps;
        if use_cache && sample_lod >= 0 {
            lod_voxel := max(render_lod_voxel_size(params, sample_lod), 0.0001);
            // Cached SDF is sampled from voxel data; treat near-surface values
            // relative to voxel size to avoid missing thin silhouettes.
            hit_eps = max(hit_eps, lod_voxel * HIT_EPSILON_VOXEL_SCALE);
        }

        if d < hit_eps {
            hit_is_ground = d_ground <= non_ground_d;
            hit = true;
            break;
        }
        step_scale := 0.3;
        step_len := max(d * step_scale, 0.0035);
        if use_cache && sample_lod < 0 {
            // Cache miss means empty space; jump directly to next cell boundary.
            step_len = max(d, 0.0035);
        } else if use_cache && sample_lod >= 0 {
            lod_voxel := max(render_lod_voxel_size(params, sample_lod), 0.0001);
            // Cap step size in cached mode so non-conservative trilinear samples
            // do not skip through thin features.
            step_len = min(step_len, lod_voxel * 0.60);
            if d < lod_voxel * 0.80 {
                step_len = min(step_len, lod_voxel * 0.25);
            }
        }
        t += step_len;
        prev_d = d;
        if t > 80.0 break; // TODO: make this a named constant and tune based on expected scene scale.
    }

    sky_a := Vector3.{0.12, 0.14, 0.18};
    sky_b := Vector3.{0.55, 0.68, 0.88};
    sky_t := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := mix(sky_a, sky_b, sky_t);

    if hit {
        if hit_is_ground {
            // High-contrast floor debug color to separate floor-hits from sky misses.
            return .{out_color = .{0.5, 0.72, 0.38, 1.0}};
        }
        if use_cache && params.cache_debug_show_selected_lod != 0 {
            if hit_lod == 0 return .{out_color = .{0.15, 0.85, 1.0, 1.0}};
            if hit_lod == 1 return .{out_color = .{1.0, 0.65, 0.2, 1.0}};
            return .{out_color = .{1.0, 0.0, 1.0, 1.0}};
        }
        if use_cache && params.cache_debug_show_distance != 0 {
            g := clamp(0.5 + hit_cached_d * 0.35, 0.0, 1.0);
            return .{out_color = .{g, g, g, 1.0}};
        }
        pos := ro + rd * t;
        n: Vector3;
        if use_cache {
            is_ground := abs(pos.y + 1.2) <= max(min_hit_eps * 2.0, hit_voxel * 0.25);
            if is_ground {
                n = .{0.0, 1.0, 0.0};
            } else {
                n = cached_normal(params, pos, hit_voxel);
            }
        }
        sun := safe_normalize(.{0.6, 0.7, 0.3});
        ndl := max(dot(n, sun), 0.0);
        base: Vector3;
        if use_cache {
            base = sample_cached_albedo(params, pos);
        }
        color = base * (0.2 + 0.8 * ndl);

        // Optional grid-like accent from world position to make edits easier to read.
        if false {
            grid_u := abs(fract(pos.x * 0.25) - 0.5) * 2.0;
            grid_v := abs(fract(pos.z * 0.25) - 0.5) * 2.0;
            line := 1.0 - clamp(min(grid_u, grid_v) * 22.0, 0.0, 1.0);
            color = mix(color, color * 1.35, line * 0.18);
        }

    }

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

brickmap_temporal_fragment_main :: (using in: Brickmap_Fragment_In, params: *Brickmap_Params) -> struct { out_color: Vector4; out_motion: Vector2; out_depth: float; } {
    hit_world := Vector3.{0.0, 0.0, 0.0};
    hit_valid := false;

    if params.debug_force_flat_color != 0 {
        return .{out_color = .{0.22, 0.35, 0.58, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
    }

    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    denom := max(params.resolution.y, 1.0);
    aspect := params.resolution.x / denom;
    p.x *= aspect;

    tan_half := params.camera_tan_half_fov;
    ro := params.camera_pos;
    rd := safe_normalize(params.camera_forward + params.camera_right * (p.x * tan_half) + params.camera_up * (p.y * tan_half));

    if params.atlas_debug_fullscreen != 0 {
        debug_uvw := Vector3.{uv.x, uv.y, clamp(params.atlas_debug_slice, 0.0, 1.0)};
        d := sample_3d(params.atlas_texture_index, params.atlas_sampler_point_index, debug_uvw).x;
        g := clamp(0.5 + d * 0.35, 0.0, 1.0);
        return .{out_color = .{g, g, g, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
    }

    if params.pointer_grid_debug != 0 && uv.x > 0.72 && uv.y < 0.28 {
        map_uv := Vector2.{(uv.x - 0.72) / 0.28, uv.y / 0.28};
        gx := clamp(cast(s32) floor(map_uv.x * cast(float) BRICKMAP_GRID_RES), 0, BRICKMAP_GRID_RES - 1);
        gy := clamp(cast(s32) floor(map_uv.y * cast(float) BRICKMAP_GRID_RES), 0, BRICKMAP_GRID_RES - 1);

        voxel_size := max(render_lod_voxel_size(params, 0), 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;
        bz := cast(s32) floor(params.camera_pos.z / brick_world_size);
        lz := bz - render_lod_origin_brick_z(params, 0);

        if lz < 0 || lz >= BRICKMAP_GRID_RES {
            return .{out_color = .{0.12, 0.12, 0.12, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
        }

        ptr_base := 0 * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + gx + gy * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        atlas_index := params.pointer_grid[ptr_idx];
        occupied := atlas_index >= 0 && params.pointer_grid_valid[ptr_idx] != 0;
        occ := ifx occupied then 1.0 else 0.0;
        idx_t := clamp(cast(float) max(atlas_index, 0) / cast(float) BRICKMAP_MAX_BRICKS, 0.0, 1.0);
        c := mix(Vector3.{0.08, 0.08, 0.08}, Vector3.{0.15, 0.95, 0.35}, occ);
        c = mix(c, Vector3.{1.0, 0.45, 0.15}, idx_t * 0.5);

        grid_x := abs(fract(map_uv.x * cast(float) BRICKMAP_GRID_RES) - 0.5) * 2.0;
        grid_y := abs(fract(map_uv.y * cast(float) BRICKMAP_GRID_RES) - 0.5) * 2.0;
        line := 1.0 - clamp(min(grid_x, grid_y) * 40.0, 0.0, 1.0);
        c = mix(c, Vector3.{1.0, 1.0, 1.0}, line * 0.2);
        return .{out_color = .{c.x, c.y, c.z, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
    }

    if params.atlas_debug_overlay != 0 && uv.x < 0.28 && uv.y < 0.28 {
        debug_uvw := Vector3.{uv.x / 0.28, uv.y / 0.28, clamp(params.atlas_debug_slice, 0.0, 1.0)};
        d := sample_3d(params.atlas_texture_index, params.atlas_sampler_point_index, debug_uvw).x;
        g := clamp(0.5 + d * 0.35, 0.0, 1.0);
        grid_x := abs(fract(debug_uvw.x * 8.0) - 0.5) * 2.0;
        grid_y := abs(fract(debug_uvw.y * 8.0) - 0.5) * 2.0;
        line := 1.0 - clamp(min(grid_x, grid_y) * 20.0, 0.0, 1.0);
        c := mix(Vector3.{g, g, g}, Vector3.{1.0, 0.35, 0.15}, line * 0.35);
        return .{out_color = .{c.x, c.y, c.z, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
    }

    t := 0.0;
    hit := false;
    min_hit_eps := 0.003;
    use_cache := true;
    hit_lod: s32 = -1;
    hit_voxel := max(render_lod_voxel_size(params, 0), 0.0001);
    hit_cached_d := 0.0;
    hit_is_ground := false;
    prev_d := cast(float) 100000.0;
    for 0..219 {
        pos := ro + rd * t;
        sample_lod: s32 = -1;
        d: float;
        d_ground := pos.y + 1.2;
        non_ground_d := cast(float) 100000.0;
        if use_cache {
            cached := sample_cached(params, pos);
            d_cached := cached.x;
            sample_lod = cast(s32) cached.y;
            sample_voxel := cached.z;
            cache_valid := cached.w != 0.0;
            if sample_lod >= 0 {
                hit_voxel = sample_voxel;
            }
            if sample_lod >= 0 && cache_valid {
                d_cached -= sample_voxel * INWARD_SAMPLED_BIAS;
                non_ground_d = d_cached;
                d = min(non_ground_d, d_ground);
            } else if sample_lod >= 0 {
                d_skip := step_to_next_lod_cell(params, pos, rd, sample_lod);
                non_ground_d = 100000.0;
                d = min(d_skip, d_ground);
                if d_ground < min_hit_eps {
                    hit_is_ground = true;
                    hit = true;
                    break;
                }
                t += max(d_skip, 0.0035);
                prev_d = d_skip;
                if t > 80.0 break;
                continue;
            } else {
                d_skip := step_to_next_lod0_cell(params, pos, rd);
                non_ground_d = 100000.0;
                d = min(d_skip, d_ground);
                if d_ground < min_hit_eps {
                    hit_is_ground = true;
                    hit = true;
                    break;
                }
                t += max(d_skip, 0.0035);
                prev_d = d_skip;
                if t > 80.0 break;
                continue;
            }
            hit_lod = sample_lod;
            hit_cached_d = d_cached;
        }

        hit_eps := min_hit_eps;
        if use_cache && sample_lod >= 0 {
            lod_voxel := max(render_lod_voxel_size(params, sample_lod), 0.0001);
            hit_eps = max(hit_eps, lod_voxel * HIT_EPSILON_VOXEL_SCALE);
        }

        if d < hit_eps {
            hit_is_ground = d_ground <= non_ground_d;
            hit = true;
            break;
        }
        step_scale := 0.3;
        step_len := max(d * step_scale, 0.0035);
        if use_cache && sample_lod < 0 {
            step_len = max(d, 0.0035);
        } else if use_cache && sample_lod >= 0 {
            lod_voxel := max(render_lod_voxel_size(params, sample_lod), 0.0001);
            step_len = min(step_len, lod_voxel * 0.60);
            if d < lod_voxel * 0.80 {
                step_len = min(step_len, lod_voxel * 0.25);
            }
        }
        t += step_len;
        prev_d = d;
        if t > 80.0 break;
    }

    sky_a := Vector3.{0.12, 0.14, 0.18};
    sky_b := Vector3.{0.55, 0.68, 0.88};
    sky_t := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := mix(sky_a, sky_b, sky_t);

    if hit {
        hit_world = ro + rd * t;
        hit_valid = true;
        if hit_is_ground {
            depth := brickmap_project_depth01(params.view_proj, hit_world);
            return .{out_color = .{0.5, 0.72, 0.38, 1.0}, out_motion = .{0.0, 0.0}, out_depth = depth};
        }
        out_color: Vector4;
        if use_cache && params.cache_debug_show_selected_lod != 0 {
            if hit_lod == 0 out_color = .{0.15, 0.85, 1.0, 1.0};
            else if hit_lod == 1 out_color = .{1.0, 0.65, 0.2, 1.0};
            else out_color = .{1.0, 0.0, 1.0, 1.0};
        } else if use_cache && params.cache_debug_show_distance != 0 {
            g := clamp(0.5 + hit_cached_d * 0.35, 0.0, 1.0);
            out_color = .{g, g, g, 1.0};
        } else {
            pos := hit_world;
            n: Vector3;
            if use_cache {
                is_ground := abs(pos.y + 1.2) <= max(min_hit_eps * 2.0, hit_voxel * 0.25);
                if is_ground {
                    n = .{0.0, 1.0, 0.0};
                } else {
                    n = cached_normal(params, pos, hit_voxel);
                }
            }
            sun := safe_normalize(.{0.6, 0.7, 0.3});
            ndl := max(dot(n, sun), 0.0);
            base: Vector3;
            if use_cache {
                base = sample_cached_albedo(params, pos);
            }
            color = base * (0.2 + 0.8 * ndl);
            if false {
                grid_u := abs(fract(pos.x * 0.25) - 0.5) * 2.0;
                grid_v := abs(fract(pos.z * 0.25) - 0.5) * 2.0;
                line := 1.0 - clamp(min(grid_u, grid_v) * 22.0, 0.0, 1.0);
                color = mix(color, color * 1.35, line * 0.18);
            }
            out_color = .{color.x, color.y, color.z, 1.0};
        }

        current_px := brickmap_project_screen_px(params.view_proj, hit_world, params.resolution);
        prev_px := brickmap_project_screen_px(params.prev_view_proj, hit_world, params.resolution);
        return .{
            out_color = out_color,
            out_motion = prev_px - current_px,
            out_depth = brickmap_project_depth01(params.view_proj, hit_world),
        };
    }

    return .{out_color = .{color.x, color.y, color.z, 1.0}, out_motion = .{0.0, 0.0}, out_depth = 1.0};
} @fragment_shader

brickmap_recenter_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params,
    src_state: *Brickmap_State, src_queues: *Brickmap_Work_Queues,
    dst_state: *Brickmap_State, dst_queues: *Brickmap_Work_Queues) {

    cell := cast(s32) thread_id.x;
    if cell == 0 {
        dst_queues.candidate_count = 0;
        dst_queues.bake_count = 0;
    }
    if cell >= BRICKMAP_TOTAL_GRID_CELLS return;

    lod := cell / BRICKMAP_GRID_CELLS;
    local_idx := cell - lod * BRICKMAP_GRID_CELLS;
    lz := local_idx / (BRICKMAP_GRID_RES * BRICKMAP_GRID_RES);
    remain := local_idx - lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
    ly := remain / BRICKMAP_GRID_RES;
    lx := remain - ly * BRICKMAP_GRID_RES;

    dx := params.lod_origin_brick_x[lod] - params.prev_lod_origin_brick_x[lod];
    dy := params.lod_origin_brick_y[lod] - params.prev_lod_origin_brick_y[lod];
    dz := params.lod_origin_brick_z[lod] - params.prev_lod_origin_brick_z[lod];

    // Be conservative for the near clipmaps. Preserve only coarse levels; invalidate the
    // near levels so they rebuild cleanly after the origin shift.
    if lod <= 1 {
        dst_state.pointer_grid[cell] = -1;
        dst_state.pointer_grid_valid[cell] = 0;
        dst_state.pointer_grid_publish_frame[cell] = 0;
        dst_state.pointer_grid_generation[cell] = src_state.pointer_grid_generation[cell] + 1;
        params.pointer_grid[cell] = -1;
        params.pointer_grid_valid[cell] = 0;
        params.pointer_grid_publish_frame[cell] = 0;
        params.pointer_grid_generation[cell] = dst_state.pointer_grid_generation[cell];
        dst_queues.dirty_flags[cell] = 1;
        return;
    }

    old_lx := lx + dx;
    old_ly := ly + dy;
    old_lz := lz + dz;
    if old_lx >= 0 && old_ly >= 0 && old_lz >= 0 &&
       old_lx < BRICKMAP_GRID_RES && old_ly < BRICKMAP_GRID_RES && old_lz < BRICKMAP_GRID_RES {

        old_cell := lod * BRICKMAP_GRID_CELLS + old_lx + old_ly * BRICKMAP_GRID_RES + old_lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        dst_state.pointer_grid[cell] = src_state.pointer_grid[old_cell];
        dst_state.pointer_grid_valid[cell] = src_state.pointer_grid_valid[old_cell];
        dst_state.pointer_grid_publish_frame[cell] = src_state.pointer_grid_publish_frame[old_cell];
        dst_state.pointer_grid_generation[cell] = src_state.pointer_grid_generation[old_cell];
        params.pointer_grid[cell] = src_state.pointer_grid[old_cell];
        params.pointer_grid_valid[cell] = src_state.pointer_grid_valid[old_cell];
        params.pointer_grid_publish_frame[cell] = src_state.pointer_grid_publish_frame[old_cell];
        params.pointer_grid_generation[cell] = src_state.pointer_grid_generation[old_cell];
        dst_queues.dirty_flags[cell] = src_queues.dirty_flags[old_cell];
        return;
    }

    dst_state.pointer_grid[cell] = -1;
    dst_state.pointer_grid_valid[cell] = 0;
    dst_state.pointer_grid_publish_frame[cell] = 0;
    dst_state.pointer_grid_generation[cell] = src_state.pointer_grid_generation[cell] + 1;
    params.pointer_grid[cell] = -1;
    params.pointer_grid_valid[cell] = 0;
    params.pointer_grid_publish_frame[cell] = 0;
    params.pointer_grid_generation[cell] = dst_state.pointer_grid_generation[cell];
    dst_queues.dirty_flags[cell] = 1;
} @compute_shader

brickmap_reset_queues_compute :: (using in: Brickmap_Compute_In, queues: *Brickmap_Work_Queues) {
    if thread_id.x != 0 return;
    queues.candidate_count = 0;
    queues.bake_count = 0;
} @compute_shader

brickmap_full_rebuild_cells_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State, queues: *Brickmap_Work_Queues) {
    cell := cast(s32) thread_id.x;
    if cell == 0 {
        params.atlas_alloc_next = 0;
    }
    if cell >= BRICKMAP_TOTAL_GRID_CELLS return;
    state.pointer_grid[cell] = -1;
    state.pointer_grid_valid[cell] = 0;
    state.pointer_grid_publish_frame[cell] = 0;
    state.pointer_grid_generation[cell] += 1;
    params.pointer_grid[cell] = -1;
    params.pointer_grid_valid[cell] = 0;
    params.pointer_grid_publish_frame[cell] = 0;
    params.pointer_grid_generation[cell] = state.pointer_grid_generation[cell];
    queues.dirty_flags[cell] = 1;
} @compute_shader

brickmap_clear_slot_owners_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State) {
    i := cast(s32) thread_id.x;
    if i >= BRICKMAP_MAX_BRICKS return;
    state.slot_owner_lod[i] = -1;
    state.slot_owner_bx[i] = 0;
    state.slot_owner_by[i] = 0;
    state.slot_owner_bz[i] = 0;
    state.slot_generation[i] = 0;
    params.slot_owner_lod[i] = -1;
    params.slot_owner_bx[i] = 0;
    params.slot_owner_by[i] = 0;
    params.slot_owner_bz[i] = 0;
    params.slot_generation[i] = 0;
} @compute_shader

brickmap_rebuild_slot_owners_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State) {
    i := cast(s32) thread_id.x;
    if i >= BRICKMAP_TOTAL_GRID_CELLS return;
    if state.pointer_grid_valid[i] == 0 return;

    atlas_index := state.pointer_grid[i];
    if atlas_index < 0 || atlas_index >= BRICKMAP_MAX_BRICKS return;

    lod := i / BRICKMAP_GRID_CELLS;
    local_idx := i - lod * BRICKMAP_GRID_CELLS;
    lz := local_idx / (BRICKMAP_GRID_RES * BRICKMAP_GRID_RES);
    remain := local_idx - lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
    ly := remain / BRICKMAP_GRID_RES;
    lx := remain - ly * BRICKMAP_GRID_RES;
    bx := params.lod_origin_brick_x[lod] + lx;
    by := params.lod_origin_brick_y[lod] + ly;
    bz := params.lod_origin_brick_z[lod] + lz;
    generation := state.pointer_grid_generation[i];

    state.slot_owner_lod[atlas_index] = lod;
    state.slot_owner_bx[atlas_index] = bx;
    state.slot_owner_by[atlas_index] = by;
    state.slot_owner_bz[atlas_index] = bz;
    state.slot_generation[atlas_index] = generation;
    params.slot_owner_lod[atlas_index] = lod;
    params.slot_owner_bx[atlas_index] = bx;
    params.slot_owner_by[atlas_index] = by;
    params.slot_owner_bz[atlas_index] = bz;
    params.slot_generation[atlas_index] = generation;
} @compute_shader

brickmap_prepare_dirty_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State, queues: *Brickmap_Work_Queues) {
    cell := cast(s32) thread_id.x;
    if cell >= BRICKMAP_TOTAL_GRID_CELLS return;

    if queues.dirty_flags[cell] == 0 return;

    lod := cell / BRICKMAP_GRID_CELLS;
    local_idx := cell - lod * BRICKMAP_GRID_CELLS;
    lz := local_idx / (BRICKMAP_GRID_RES * BRICKMAP_GRID_RES);
    remain := local_idx - lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
    ly := remain / BRICKMAP_GRID_RES;
    lx := remain - ly * BRICKMAP_GRID_RES;

    out_i := cast(s32) atomic_add_u32(*queues.candidate_count, 1);
    if out_i >= BRICKMAP_MAX_QUEUE_ITEMS return;

    queues.candidates[out_i].lod = cast(u32) lod;
    queues.candidates[out_i].brick_x = params.lod_origin_brick_x[lod] + lx;
    queues.candidates[out_i].brick_y = params.lod_origin_brick_y[lod] + ly;
    queues.candidates[out_i].brick_z = params.lod_origin_brick_z[lod] + lz;
    queues.candidates[out_i].atlas_index = 0;
} @compute_shader

brickmap_classify_dirty_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State, queues: *Brickmap_Work_Queues) {
    i := cast(s32) thread_id.x;
    if i == 0 {
        params.debug_gpu_seen_edit_count = params.edit_count;
        if params.edit_count > 0 {
            watch_idx := clamp(cast(s32) params.debug_watch_edit_index, 0, cast(s32) params.edit_count - 1);
            params.debug_gpu_seen_watch_shape = cast(u32) params.edit_shape[watch_idx];
            params.debug_gpu_seen_watch_op = cast(u32) params.edit_op[watch_idx];
            params.debug_gpu_seen_watch_pos_radius = params.edit_pos_radius[watch_idx];
            params.debug_gpu_scene_at_camera = eval_edits_sdf(params, params.camera_pos);
            params.debug_gpu_scene_at_watch_center = eval_edits_sdf(params, params.edit_pos_radius[watch_idx].xyz);
        } else {
            params.debug_gpu_seen_watch_shape = 0;
            params.debug_gpu_seen_watch_op = 0;
            params.debug_gpu_seen_watch_pos_radius = .{0.0, 0.0, 0.0, 0.0};
            params.debug_gpu_scene_at_camera = 0;
            params.debug_gpu_scene_at_watch_center = 0;
        }
    }
    candidates := min(cast(s32) queues.candidate_count, BRICKMAP_MAX_QUEUE_ITEMS);
    if i >= candidates return;

    lod := cast(s32) queues.candidates[i].lod;
    bx := queues.candidates[i].brick_x;
    by := queues.candidates[i].brick_y;
    bz := queues.candidates[i].brick_z;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;

    lx := bx - params.lod_origin_brick_x[lod];
    ly := by - params.lod_origin_brick_y[lod];
    lz := bz - params.lod_origin_brick_z[lod];
    if lx < 0 || ly < 0 || lz < 0 return;
    if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES return;

    ptr_base := lod * BRICKMAP_GRID_CELLS;
    ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
    atlas_index := state.pointer_grid[ptr_idx];

    has_surface := brick_has_surface(params, lod, bx, by, bz);
    if !has_surface {
        state.pointer_grid[ptr_idx] = -1;
        state.pointer_grid_valid[ptr_idx] = 0;
        state.pointer_grid_publish_frame[ptr_idx] = 0;
        params.pointer_grid[ptr_idx] = -1;
        params.pointer_grid_valid[ptr_idx] = 0;
        params.pointer_grid_publish_frame[ptr_idx] = 0;
        queues.dirty_flags[ptr_idx] = 0;
        return;
    }
    atomic_add_u32(*params.debug_classify_surface, 1);

    if atlas_index < 0 {
        alloc_slot := cast(s32) atomic_add_u32(*params.atlas_alloc_next, 1);
        if alloc_slot >= BRICKMAP_MAX_BRICKS {
            atomic_add_u32(*params.debug_classify_rejected_capacity, 1);
            queues.dirty_flags[ptr_idx] = 1;
            return;
        }
        atlas_index = alloc_slot;
        state.pointer_grid[ptr_idx] = atlas_index;
        params.pointer_grid[ptr_idx] = atlas_index;
        atomic_add_u32(*params.debug_classify_new_alloc, 1);
    } else {
        atomic_add_u32(*params.debug_classify_existing, 1);
    }

    out_i := cast(s32) atomic_add_u32(*queues.bake_count, 1);
    if out_i >= BRICKMAP_MAX_QUEUE_ITEMS {
        atomic_add_u32(*params.debug_classify_rejected_capacity, 1);
        queues.dirty_flags[ptr_idx] = 1;
        return;
    }

    queues.bake[out_i].lod = cast(u32) lod;
    queues.bake[out_i].brick_x = bx;
    queues.bake[out_i].brick_y = by;
    queues.bake[out_i].brick_z = bz;
    queues.bake[out_i].atlas_index = cast(u32) atlas_index;
    queues.bake[out_i].generation = state.pointer_grid_generation[ptr_idx];
    queues.dirty_flags[ptr_idx] = 0;
    atomic_add_u32(*params.debug_bake_bricks_touched, 1);
} @compute_shader

brickmap_prepare_dispatch_args_compute :: (using in: Brickmap_Compute_In, queues: *Brickmap_Work_Queues, args: *Brickmap_Indirect_Dispatch_Pair) {
    if thread_id.x != 0 return;

    bake_count := min(queues.bake_count, cast(u32) BRICKMAP_MAX_QUEUE_ITEMS);
    bake_groups := max((bake_count * cast(u32) BRICKMAP_BRICK_TEXELS + 63) / 64, 1);
    publish_groups := max((bake_count + 63) / 64, 1);

    args.bake_x = bake_groups;
    args.bake_y = 1;
    args.bake_z = 1;
    args.publish_x = publish_groups;
    args.publish_y = 1;
    args.publish_z = 1;
} @compute_shader

brickmap_bake_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, queues: *Brickmap_Work_Queues) {
    total_voxels := queues.bake_count * BRICKMAP_BRICK_TEXELS;
    if thread_id.x >= total_voxels return;

    flat := cast(s32) thread_id.x;
    brick_i := flat / BRICKMAP_BRICK_TEXELS;
    voxel_i := flat - brick_i * BRICKMAP_BRICK_TEXELS;

    lod := cast(s32) queues.bake[brick_i].lod;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;
    brick_x := queues.bake[brick_i].brick_x;
    brick_y := queues.bake[brick_i].brick_y;
    brick_z := queues.bake[brick_i].brick_z;

    voxel_size := max(params.lod_voxel_size[lod], 0.0001);

    vx := voxel_i % BRICKMAP_BRICK_TEX_RES;
    vy := (voxel_i / BRICKMAP_BRICK_TEX_RES) % BRICKMAP_BRICK_TEX_RES;
    vz := voxel_i / (BRICKMAP_BRICK_TEX_RES * BRICKMAP_BRICK_TEX_RES);

    // Include a true 1-voxel halo around each brick so filtering remains continuous
    // across neighboring bricks (instead of duplicating edge voxels).
    sample_vx := vx - 1;
    sample_vy := vy - 1;
    sample_vz := vz - 1;

    world_vox_x := cast(float) (brick_x * BRICKMAP_BRICK_RES + sample_vx) + 0.5;
    world_vox_y := cast(float) (brick_y * BRICKMAP_BRICK_RES + sample_vy) + 0.5;
    world_vox_z := cast(float) (brick_z * BRICKMAP_BRICK_RES + sample_vz) + 0.5;

    p := Vector3.{world_vox_x * voxel_size, world_vox_y * voxel_size, world_vox_z * voxel_size};
    d_albedo := eval_edits_sdf_albedo(params, p);
    d := d_albedo.x;
    albedo := Vector3.{d_albedo.y, d_albedo.z, d_albedo.w};
    if params.bake_debug_gradient != 0 {
        fx := cast(float) vx / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        fy := cast(float) vy / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        fz := cast(float) vz / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        d = (fx + fy + fz) / 3.0 * 2.0 - 1.0;
        albedo = .{fx, fy, fz};
    }

    atlas_index := cast(s32) queues.bake[brick_i].atlas_index;
    if voxel_i == 0 {
        params.debug_bake_seen_atlas[brick_i] = cast(u32) max(atlas_index, 0);
    }
    if atlas_index < 0 return;
    atlas_brick := atlas_brick_coord(atlas_index);
    tx := cast(s32) atlas_brick.x * BRICKMAP_BRICK_TEX_RES + vx;
    ty := cast(s32) atlas_brick.y * BRICKMAP_BRICK_TEX_RES + vy;
    tz := cast(s32) atlas_brick.z * BRICKMAP_BRICK_TEX_RES + vz;
    write_3d(params.atlas_texture_index, cast(u32) tx, cast(u32) ty, cast(u32) tz, .{d, 0.0, 0.0, 1.0});
    write_3d(params.atlas_albedo_texture_index, cast(u32) tx, cast(u32) ty, cast(u32) tz, .{albedo.x, albedo.y, albedo.z, 1.0});
} @compute_shader

brickmap_publish_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params, state: *Brickmap_State, queues: *Brickmap_Work_Queues) {
    i := cast(s32) thread_id.x;
    count := min(cast(s32) queues.bake_count, BRICKMAP_MAX_QUEUE_ITEMS);
    if i >= count return;

    lod := cast(s32) queues.bake[i].lod;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;

    bx := queues.bake[i].brick_x;
    by := queues.bake[i].brick_y;
    bz := queues.bake[i].brick_z;

    lx := bx - params.lod_origin_brick_x[lod];
    ly := by - params.lod_origin_brick_y[lod];
    lz := bz - params.lod_origin_brick_z[lod];
    if lx < 0 || ly < 0 || lz < 0 return;
    if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES return;

    ptr_base := lod * BRICKMAP_GRID_CELLS;
    ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;

    atlas_index := cast(s32) queues.bake[i].atlas_index;
    generation := queues.bake[i].generation;
    if atlas_index < 0 {
        state.pointer_grid[ptr_idx] = -1;
        state.pointer_grid_valid[ptr_idx] = 0;
        state.pointer_grid_publish_frame[ptr_idx] = 0;
        params.pointer_grid[ptr_idx] = -1;
        params.pointer_grid_valid[ptr_idx] = 0;
        params.pointer_grid_publish_frame[ptr_idx] = 0;
        return;
    }
    if state.pointer_grid_generation[ptr_idx] != generation {
        return;
    }
    state.pointer_grid[ptr_idx] = atlas_index;
    state.pointer_grid_valid[ptr_idx] = 1;
    state.pointer_grid_publish_frame[ptr_idx] = params.frame_index;
    state.slot_owner_lod[atlas_index] = lod;
    state.slot_owner_bx[atlas_index] = bx;
    state.slot_owner_by[atlas_index] = by;
    state.slot_owner_bz[atlas_index] = bz;
    state.slot_generation[atlas_index] = generation;
    params.pointer_grid[ptr_idx] = atlas_index;
    params.pointer_grid_valid[ptr_idx] = 1;
    params.pointer_grid_publish_frame[ptr_idx] = params.frame_index;
    params.slot_owner_lod[atlas_index] = lod;
    params.slot_owner_bx[atlas_index] = bx;
    params.slot_owner_by[atlas_index] = by;
    params.slot_owner_bz[atlas_index] = bz;
    params.slot_generation[atlas_index] = generation;
} @compute_shader
