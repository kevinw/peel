#import "Jai-Shader-Transpiler";
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";

BRICKMAP_BRICK_RES :: 8;
BRICKMAP_BRICK_TEX_RES :: BRICKMAP_BRICK_RES + 2;
BRICKMAP_BRICK_VOXELS :: BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES;
BRICKMAP_BRICK_TEXELS :: BRICKMAP_BRICK_TEX_RES * BRICKMAP_BRICK_TEX_RES * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_GRID_RES :: 24;
BRICKMAP_GRID_CELLS :: BRICKMAP_GRID_RES * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
BRICKMAP_LOD_COUNT :: 2;
BRICKMAP_MAX_EDITS :: 1000;
BRICKMAP_ATLAS_BRICKS_X :: 16;
BRICKMAP_ATLAS_BRICKS_Y :: 16;
BRICKMAP_ATLAS_BRICKS_Z :: 16;
BRICKMAP_MAX_BRICKS :: BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_ATLAS_BRICKS_Y * BRICKMAP_ATLAS_BRICKS_Z;
BRICKMAP_MAX_DIRTY_BRICKS :: 2048;
BRICKMAP_ATLAS_DIM_X :: BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_ATLAS_DIM_Y :: BRICKMAP_ATLAS_BRICKS_Y * BRICKMAP_BRICK_TEX_RES;
BRICKMAP_ATLAS_DIM_Z :: BRICKMAP_ATLAS_BRICKS_Z * BRICKMAP_BRICK_TEX_RES;

SDF_SHAPE_SPHERE :: 0;
SDF_SHAPE_BOX :: 1;
SDF_OP_UNION :: 0;
SDF_OP_SUBTRACT :: 1;
SDF_OP_INTERSECT :: 2;

Brickmap_Lod_Info :: struct {
    origin_brick_x: s32;
    origin_brick_y: s32;
    origin_brick_z: s32;
    _pad0: s32;
    voxel_size: float;
    _pad1: float;
    _pad2: float;
    _pad3: float;
}

SDF_Edit :: struct {
    shape: u32;
    op: u32;
    _pad0: u32;
    _pad1: u32;

    position: Vector3;
    radius: float;

    half_extents: Vector3;
    blend: float;

    rotation: Vector4;
}

Brick_Request :: struct {
    lod: u32;
    brick_x: s32;
    brick_y: s32;
    brick_z: s32;
    atlas_index: u32;
    _pad0: u32;
    _pad1: u32;
    _pad2: u32;
}

Brickmap_Params :: struct {
    resolution: Vector2;
    camera_fov_y: float;
    camera_tan_half_fov: float;
    time: float;

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
    cache_force_lod0: u32;
    atlas_debug_slice: float;
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
    _pad4: [2] u32;
    debug_bake_seen_atlas: [BRICKMAP_MAX_DIRTY_BRICKS] u32;
    pointer_grid: [BRICKMAP_LOD_COUNT * BRICKMAP_GRID_CELLS] s32;
    lod_origin_brick_x: [BRICKMAP_LOD_COUNT] s32;
    lod_origin_brick_y: [BRICKMAP_LOD_COUNT] s32;
    lod_origin_brick_z: [BRICKMAP_LOD_COUNT] s32;
    lod_voxel_size: [BRICKMAP_LOD_COUNT] float;
    edit_shape: [BRICKMAP_MAX_EDITS] u32;
    edit_op: [BRICKMAP_MAX_EDITS] u32;
    edit_pos_radius: [BRICKMAP_MAX_EDITS] Vector4;
    edit_half_extents_blend: [BRICKMAP_MAX_EDITS] Vector4;
    edit_rotation: [BRICKMAP_MAX_EDITS] Vector4;
    dirty_lod_brick_xyz: [BRICKMAP_MAX_DIRTY_BRICKS] Vector4;
    dirty_atlas_index: [BRICKMAP_MAX_DIRTY_BRICKS] u32;
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

brickmap_vertex_main :: (using in: Brickmap_Vertex_In) -> Brickmap_Vertex_Out {
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

brickmap_safe_normalize :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 <= 0.000001 return .{0.0, 1.0, 0.0};
    return v * (1.0 / sqrt(len2));
}

brickmap_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    t := cross(q.xyz, v) * 2.0;
    return v + t * q.w + cross(q.xyz, t);
}

brickmap_inv_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    qc := Vector4.{-q.x, -q.y, -q.z, q.w};
    return brickmap_rotate_quat(v, qc);
}

brickmap_sdf_sphere :: (p: Vector3, radius: float) -> float {
    return sqrt(dot(p, p)) - radius;
}

brickmap_sdf_box :: (p: Vector3, b: Vector3) -> float {
    q := Vector3.{abs(p.x) - b.x, abs(p.y) - b.y, abs(p.z) - b.z};
    outside := Vector3.{max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0)};
    outside_len := sqrt(dot(outside, outside));
    inside := min(max(q.x, max(q.y, q.z)), 0.0);
    return outside_len + inside;
}

brickmap_eval_edits_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    d := cast(float) 100000.0;
    count := cast(s32) params.edit_count;
    for i: 0..count-1 {
        shape := params.edit_shape[i];
        op := params.edit_op[i];
        pos_radius := params.edit_pos_radius[i];
        extents_blend := params.edit_half_extents_blend[i];
        rot := params.edit_rotation[i];
        q := brickmap_inv_rotate_quat(p - pos_radius.xyz, rot);

        sd: float;
        if shape == SDF_SHAPE_BOX {
            sd = brickmap_sdf_box(q, extents_blend.xyz);
        } else {
            sd = brickmap_sdf_sphere(q, pos_radius.w);
        }

        if op == SDF_OP_SUBTRACT {
            d = max(d, -sd);
        } else if op == SDF_OP_INTERSECT {
            d = max(d, sd);
        } else {
            d = min(d, sd);
        }
    }

    return d;
}

brickmap_eval_scene_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    d := brickmap_eval_edits_sdf(params, p);
    ground := p.y + 1.2;
    return min(d, ground);
}

brickmap_atlas_brick_coord :: (atlas_index: s32) -> Vector3 {
    x := atlas_index % BRICKMAP_ATLAS_BRICKS_X;
    y := (atlas_index / BRICKMAP_ATLAS_BRICKS_X) % BRICKMAP_ATLAS_BRICKS_Y;
    z := atlas_index / (BRICKMAP_ATLAS_BRICKS_X * BRICKMAP_ATLAS_BRICKS_Y);
    return .{cast(float) x, cast(float) y, cast(float) z};
}

brickmap_sample_brick_filtered :: (params: *Brickmap_Params, atlas_index: s32, uvw: Vector3) -> float {
    brick := brickmap_atlas_brick_coord(atlas_index);
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

brickmap_sample_cached_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    s := brickmap_sample_cached(params, p);
    lod := cast(s32) s.y;
    if lod < 0 return 100000.0;
    return s.x;
}

brickmap_sample_cached :: (params: *Brickmap_Params, p: Vector3) -> Vector4 {
    max_lod := BRICKMAP_LOD_COUNT;
    if params.cache_force_lod0 != 0 {
        max_lod = 1;
    }
    for lod: 0..max_lod-1 {
        voxel_size := max(params.lod_voxel_size[lod], 0.0001);

        gx := p.x / voxel_size;
        gy := p.y / voxel_size;
        gz := p.z / voxel_size;

        bx := cast(s32) floor(gx / cast(float) BRICKMAP_BRICK_RES);
        by := cast(s32) floor(gy / cast(float) BRICKMAP_BRICK_RES);
        bz := cast(s32) floor(gz / cast(float) BRICKMAP_BRICK_RES);

        lx := bx - params.lod_origin_brick_x[lod];
        ly := by - params.lod_origin_brick_y[lod];
        lz := bz - params.lod_origin_brick_z[lod];

        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;

        ptr_base := lod * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        atlas_index := params.pointer_grid[ptr_idx];
        if atlas_index < 0 continue;

        // Convert to voxel-center space (matching bake positions at +0.5 voxel).
        local_x := gx - cast(float) (bx * BRICKMAP_BRICK_RES) - 0.5;
        local_y := gy - cast(float) (by * BRICKMAP_BRICK_RES) - 0.5;
        local_z := gz - cast(float) (bz * BRICKMAP_BRICK_RES) - 0.5;
        d := brickmap_sample_brick_filtered(params, atlas_index, .{local_x, local_y, local_z});
        return .{d, cast(float) lod, voxel_size, 1.0};
    }

    return .{100000.0, -1.0, max(params.lod_voxel_size[0], 0.0001), 0.0};
}

brickmap_sample_cached_lod :: (params: *Brickmap_Params, p: Vector3) -> s32 {
    return cast(s32) brickmap_sample_cached(params, p).y;
}

brickmap_step_to_next_lod0_cell :: (params: *Brickmap_Params, p: Vector3, rd: Vector3) -> float {
    voxel_size := max(params.lod_voxel_size[0], 0.0001);
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

brickmap_brick_has_surface :: (params: *Brickmap_Params, lod: s32, bx: s32, by: s32, bz: s32) -> bool {
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return false;
    voxel_size := max(params.lod_voxel_size[lod], 0.0001);
    brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;

    min_p := Vector3.{
        cast(float) bx * brick_world_size,
        cast(float) by * brick_world_size,
        cast(float) bz * brick_world_size,
    };
    max_p := min_p + .{brick_world_size, brick_world_size, brick_world_size};
    center_p := (min_p + max_p) * 0.5;

    min_d:     float = 100000.0;
    max_d:     float = -100000.0;
    min_abs_d: float = 100000.0;

    d0 := brickmap_eval_edits_sdf(params, .{min_p.x, min_p.y, min_p.z});
    d1 := brickmap_eval_edits_sdf(params, .{max_p.x, min_p.y, min_p.z});
    d2 := brickmap_eval_edits_sdf(params, .{min_p.x, max_p.y, min_p.z});
    d3 := brickmap_eval_edits_sdf(params, .{max_p.x, max_p.y, min_p.z});
    d4 := brickmap_eval_edits_sdf(params, .{min_p.x, min_p.y, max_p.z});
    d5 := brickmap_eval_edits_sdf(params, .{max_p.x, min_p.y, max_p.z});
    d6 := brickmap_eval_edits_sdf(params, .{min_p.x, max_p.y, max_p.z});
    d7 := brickmap_eval_edits_sdf(params, .{max_p.x, max_p.y, max_p.z});
    d8 := brickmap_eval_edits_sdf(params, center_p);
    d9  := brickmap_eval_edits_sdf(params, .{center_p.x, min_p.y, center_p.z});
    d10 := brickmap_eval_edits_sdf(params, .{center_p.x, max_p.y, center_p.z});
    d11 := brickmap_eval_edits_sdf(params, .{min_p.x, center_p.y, center_p.z});
    d12 := brickmap_eval_edits_sdf(params, .{max_p.x, center_p.y, center_p.z});
    d13 := brickmap_eval_edits_sdf(params, .{center_p.x, center_p.y, min_p.z});
    d14 := brickmap_eval_edits_sdf(params, .{center_p.x, center_p.y, max_p.z});

    if d0 < min_d min_d = d0; if d0 > max_d max_d = d0; if abs(d0) < min_abs_d min_abs_d = abs(d0);
    if d1 < min_d min_d = d1; if d1 > max_d max_d = d1; if abs(d1) < min_abs_d min_abs_d = abs(d1);
    if d2 < min_d min_d = d2; if d2 > max_d max_d = d2; if abs(d2) < min_abs_d min_abs_d = abs(d2);
    if d3 < min_d min_d = d3; if d3 > max_d max_d = d3; if abs(d3) < min_abs_d min_abs_d = abs(d3);
    if d4 < min_d min_d = d4; if d4 > max_d max_d = d4; if abs(d4) < min_abs_d min_abs_d = abs(d4);
    if d5 < min_d min_d = d5; if d5 > max_d max_d = d5; if abs(d5) < min_abs_d min_abs_d = abs(d5);
    if d6 < min_d min_d = d6; if d6 > max_d max_d = d6; if abs(d6) < min_abs_d min_abs_d = abs(d6);
    if d7 < min_d min_d = d7; if d7 > max_d max_d = d7; if abs(d7) < min_abs_d min_abs_d = abs(d7);
    if d8 < min_d min_d = d8; if d8 > max_d max_d = d8; if abs(d8) < min_abs_d min_abs_d = abs(d8);
    if d9 < min_d min_d = d9; if d9 > max_d max_d = d9; if abs(d9) < min_abs_d min_abs_d = abs(d9);
    if d10 < min_d min_d = d10; if d10 > max_d max_d = d10; if abs(d10) < min_abs_d min_abs_d = abs(d10);
    if d11 < min_d min_d = d11; if d11 > max_d max_d = d11; if abs(d11) < min_abs_d min_abs_d = abs(d11);
    if d12 < min_d min_d = d12; if d12 > max_d max_d = d12; if abs(d12) < min_abs_d min_abs_d = abs(d12);
    if d13 < min_d min_d = d13; if d13 > max_d max_d = d13; if abs(d13) < min_abs_d min_abs_d = abs(d13);
    if d14 < min_d min_d = d14; if d14 > max_d max_d = d14; if abs(d14) < min_abs_d min_abs_d = abs(d14);

    if min_d <= 0.0 && max_d >= 0.0 return true;
    MARGIN :: 1.75;
    return min_abs_d <= voxel_size * MARGIN;
}

brickmap_scene_normal :: (params: *Brickmap_Params, p: Vector3) -> Vector3 {
    eps := 0.02;
    dpx := brickmap_eval_scene_sdf(params, p + .{eps, 0.0, 0.0});
    dnx := brickmap_eval_scene_sdf(params, p - .{eps, 0.0, 0.0});
    dpy := brickmap_eval_scene_sdf(params, p + .{0.0, eps, 0.0});
    dny := brickmap_eval_scene_sdf(params, p - .{0.0, eps, 0.0});
    dpz := brickmap_eval_scene_sdf(params, p + .{0.0, 0.0, eps});
    dnz := brickmap_eval_scene_sdf(params, p - .{0.0, 0.0, eps});
    return brickmap_safe_normalize(.{dpx - dnx, dpy - dny, dpz - dnz});
}

brickmap_cached_normal :: (params: *Brickmap_Params, p: Vector3, voxel: float) -> Vector3 {
    // TODO(brickmap-quality/perf):
    // Prefer seam-aware cached-field gradient as the default normal path:
    // 1) Sample across brick borders with guard/border texels + consistent atlas-space epsilon.
    // 2) Add confidence/fallback only when cached samples are invalid, to avoid noisy seams.
    // 3) If still too expensive, evaluate baking a compact gradient/normal into atlas (e.g. oct-encoded),
    //    but keep memory/bandwidth tradeoffs explicit versus deriving from SDF samples.
    eps := max(voxel * 0.45, 0.02);
    s_px := brickmap_sample_cached(params, p + .{eps, 0.0, 0.0});
    s_nx := brickmap_sample_cached(params, p - .{eps, 0.0, 0.0});
    s_py := brickmap_sample_cached(params, p + .{0.0, eps, 0.0});
    s_ny := brickmap_sample_cached(params, p - .{0.0, eps, 0.0});
    s_pz := brickmap_sample_cached(params, p + .{0.0, 0.0, eps});
    s_nz := brickmap_sample_cached(params, p - .{0.0, 0.0, eps});
    if cast(s32) s_px.y < 0 || cast(s32) s_nx.y < 0 || cast(s32) s_py.y < 0 || cast(s32) s_ny.y < 0 || cast(s32) s_pz.y < 0 || cast(s32) s_nz.y < 0 {
        return .{0.0, 1.0, 0.0};
    }
    return brickmap_safe_normalize(.{s_px.x - s_nx.x, s_py.x - s_ny.x, s_pz.x - s_nz.x});
}

brickmap_fragment_main :: (using in: Brickmap_Fragment_In, params: *Brickmap_Params) -> struct { out_color: Vector4; } {
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    denom := max(params.resolution.y, 1.0);
    aspect := params.resolution.x / denom;
    p.x *= aspect;

    tan_half := params.camera_tan_half_fov;
    ro := params.camera_pos;
    rd := brickmap_safe_normalize(params.camera_forward + params.camera_right * (p.x * tan_half) + params.camera_up * (p.y * tan_half));

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

        voxel_size := max(params.lod_voxel_size[0], 0.0001);
        brick_world_size := voxel_size * cast(float) BRICKMAP_BRICK_RES;
        bz := cast(s32) floor(params.camera_pos.z / brick_world_size);
        lz := bz - params.lod_origin_brick_z[0];

        if lz < 0 || lz >= BRICKMAP_GRID_RES {
            return .{out_color = .{0.12, 0.12, 0.12, 1.0}};
        }

        ptr_base := 0 * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + gx + gy * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        atlas_index := params.pointer_grid[ptr_idx];
        occupied := atlas_index >= 0;
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
    use_cache := params.use_cache_raymarch != 0;
    hit_lod: s32 = -1;
    hit_voxel := max(params.lod_voxel_size[0], 0.0001);
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
            cached := brickmap_sample_cached(params, pos);
            d_cached := cached.x;
            sample_lod = cast(s32) cached.y;
            sample_voxel := cached.z;
            if sample_lod >= 0 {
                hit_voxel = sample_voxel;
            }
            if sample_lod >= 0 {
                // Bias sampled distance slightly inward to counter
                // non-conservative interpolation on coarse voxels.
                d_cached -= sample_voxel * 0.35;
                non_ground_d = d_cached;
                d = min(non_ground_d, d_ground);
            } else {
                d_skip := brickmap_step_to_next_lod0_cell(params, pos, rd);
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
        } else {
            non_ground_d = brickmap_eval_edits_sdf(params, pos);
            d = min(non_ground_d, d_ground);
        }

        hit_eps := min_hit_eps;
        if use_cache && sample_lod >= 0 {
            lod_voxel := max(params.lod_voxel_size[sample_lod], 0.0001);
            // Cached SDF is sampled from voxel data; treat near-surface values
            // relative to voxel size to avoid missing thin silhouettes.
            hit_eps = max(hit_eps, lod_voxel * 0.24);
        }

        if d < hit_eps {
            hit_is_ground = d_ground <= non_ground_d;
            hit = true;
            break;
        }
        if use_cache && sample_lod >= 0 {
            lod_voxel := max(params.lod_voxel_size[sample_lod], 0.0001);
            // Trilinear sampled distance can stay slightly positive at the
            // surface; if we are already within a sub-voxel band and distance
            // turns upward, accept the local minimum as a hit.
            if d < lod_voxel * 0.45 && d > prev_d {
                hit = true;
                break;
            }
        }

        step_scale := ifx use_cache then 0.3 else 0.85;
        step_len := max(d * step_scale, 0.0035);
        if use_cache && sample_lod < 0 {
            // Cache miss means empty space; jump directly to next cell boundary.
            step_len = max(d, 0.0035);
        } else if use_cache && sample_lod >= 0 {
            lod_voxel := max(params.lod_voxel_size[sample_lod], 0.0001);
            // Cap step size in cached mode so non-conservative trilinear samples
            // do not skip through thin features.
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
        if hit_is_ground {
            // High-contrast floor debug color to separate floor-hits from sky misses.
            return .{out_color = .{0.10, 0.92, 0.18, 1.0}};
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
                n = brickmap_cached_normal(params, pos, hit_voxel);
            }
        } else {
            for 0..3 {
                refine_pos := ro + rd * t;
                t -= brickmap_eval_scene_sdf(params, refine_pos) * 0.7;
                if t < 0.0 {
                    t = 0.0;
                    break;
                }
            }
            pos = ro + rd * t;
            n = brickmap_scene_normal(params, pos);
        }
        sun := brickmap_safe_normalize(.{0.6, 0.7, 0.3});
        ndl := max(dot(n, sun), 0.0);
        base := Vector3.{0.48, 0.52, 0.58};
        color = base * (0.2 + 0.8 * ndl);

        // Grid-like accent from world position to make edits easier to read.
        grid_u := abs(fract(pos.x * 0.25) - 0.5) * 2.0;
        grid_v := abs(fract(pos.z * 0.25) - 0.5) * 2.0;
        line := 1.0 - clamp(min(grid_u, grid_v) * 22.0, 0.0, 1.0);
        color = mix(color, color * 1.35, line * 0.18);
    }

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

brickmap_classify_dirty_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params) {
    i := cast(s32) thread_id.x;
    candidates := min(cast(s32) params.debug_classify_candidates, BRICKMAP_MAX_DIRTY_BRICKS);
    if i >= candidates return;

    req := params.dirty_lod_brick_xyz[i];
    lod := cast(s32) req.x;
    bx := cast(s32) req.y;
    by := cast(s32) req.z;
    bz := cast(s32) req.w;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;

    lx := bx - params.lod_origin_brick_x[lod];
    ly := by - params.lod_origin_brick_y[lod];
    lz := bz - params.lod_origin_brick_z[lod];
    if lx < 0 || ly < 0 || lz < 0 return;
    if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES return;

    ptr_base := lod * BRICKMAP_GRID_CELLS;
    ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
    atlas_index := params.pointer_grid[ptr_idx];

    has_surface := brickmap_brick_has_surface(params, lod, bx, by, bz);
    if !has_surface {
        params.pointer_grid[ptr_idx] = -1;
        return;
    }
    atomic_add_u32(*params.debug_classify_surface, 1);

    if atlas_index < 0 {
        alloc_slot := cast(s32) atomic_add_u32(*params.atlas_alloc_next, 1);
        if alloc_slot >= BRICKMAP_MAX_BRICKS {
            atomic_add_u32(*params.debug_classify_rejected_capacity, 1);
            return;
        }
        atlas_index = alloc_slot;
        params.pointer_grid[ptr_idx] = atlas_index;
        atomic_add_u32(*params.debug_classify_new_alloc, 1);
    } else {
        atomic_add_u32(*params.debug_classify_existing, 1);
    }

    out_i := cast(s32) atomic_add_u32(*params.dirty_count, 1);
    if out_i >= BRICKMAP_MAX_DIRTY_BRICKS {
        atomic_add_u32(*params.debug_classify_rejected_capacity, 1);
        return;
    }
    params.dirty_lod_brick_xyz[out_i] = req;
    params.dirty_atlas_index[out_i] = cast(u32) atlas_index;
    atomic_min_u32(*params.debug_bake_min_atlas, cast(u32) max(atlas_index, 0));
    atomic_max_u32(*params.debug_bake_max_atlas, cast(u32) max(atlas_index, 0));
    atomic_add_u32(*params.debug_bake_total_voxels, cast(u32) BRICKMAP_BRICK_TEXELS);
    atomic_add_u32(*params.debug_bake_bricks_touched, 1);
} @compute_shader

brickmap_bake_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params) {
    total_voxels := params.dirty_count * BRICKMAP_BRICK_TEXELS;
    if thread_id.x >= total_voxels return;

    flat := cast(s32) thread_id.x;
    brick_i := flat / BRICKMAP_BRICK_TEXELS;
    voxel_i := flat - brick_i * BRICKMAP_BRICK_TEXELS;

    req := params.dirty_lod_brick_xyz[brick_i];
    lod := cast(s32) req.x;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;
    brick_x := cast(s32) req.y;
    brick_y := cast(s32) req.z;
    brick_z := cast(s32) req.w;

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
    d := brickmap_eval_edits_sdf(params, p);
    if params.bake_debug_gradient != 0 {
        fx := cast(float) vx / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        fy := cast(float) vy / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        fz := cast(float) vz / cast(float) (BRICKMAP_BRICK_TEX_RES - 1);
        d = (fx + fy + fz) / 3.0 * 2.0 - 1.0;
    }

    atlas_index: s32 = -1;
    lx := brick_x - params.lod_origin_brick_x[lod];
    ly := brick_y - params.lod_origin_brick_y[lod];
    lz := brick_z - params.lod_origin_brick_z[lod];
    if lx >= 0 && ly >= 0 && lz >= 0 && lx < BRICKMAP_GRID_RES && ly < BRICKMAP_GRID_RES && lz < BRICKMAP_GRID_RES {
        ptr_base := lod * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + lx + ly * BRICKMAP_GRID_RES + lz * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
        atlas_index = params.pointer_grid[ptr_idx];
    }
    if atlas_index < 0 {
        // Debug path when classify is skipped and atlas mapping is pre-seeded by CPU.
        atlas_index = cast(s32) params.dirty_atlas_index[brick_i];
    }
    if voxel_i == 0 {
        params.debug_bake_seen_atlas[brick_i] = cast(u32) max(atlas_index, 0);
    }
    if atlas_index < 0 return;
    atlas_brick := brickmap_atlas_brick_coord(atlas_index);
    tx := cast(s32) atlas_brick.x * BRICKMAP_BRICK_TEX_RES + vx;
    ty := cast(s32) atlas_brick.y * BRICKMAP_BRICK_TEX_RES + vy;
    tz := cast(s32) atlas_brick.z * BRICKMAP_BRICK_TEX_RES + vz;
    write_3d(params.atlas_texture_index, cast(u32) tx, cast(u32) ty, cast(u32) tz, .{d, 0.0, 0.0, 1.0});
} @compute_shader
