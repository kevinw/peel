#import "Jai-Shader-Transpiler";
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";

BRICKMAP_BRICK_RES :: 8;
BRICKMAP_BRICK_VOXELS :: BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES;
BRICKMAP_GRID_RES :: 24;
BRICKMAP_GRID_CELLS :: BRICKMAP_GRID_RES * BRICKMAP_GRID_RES * BRICKMAP_GRID_RES;
BRICKMAP_LOD_COUNT :: 2;
BRICKMAP_MAX_EDITS :: 64;
BRICKMAP_MAX_BRICKS :: 4096;
BRICKMAP_MAX_DIRTY_BRICKS :: 2048;
BRICKMAP_ATLAS_VOXELS :: BRICKMAP_MAX_BRICKS * BRICKMAP_BRICK_VOXELS;

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
    distance_range: float;
    use_cache_raymarch: u32;
    _pad4: u32;
    atlas_values: [BRICKMAP_ATLAS_VOXELS] u32;
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

brickmap_flatten_3d :: (x: s32, y: s32, z: s32, dim: s32) -> s32 {
    return x + y * dim + z * dim * dim;
}

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

brickmap_eval_scene_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
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

    ground := p.y + 1.2;
    d = min(d, ground);
    return d;
}

brickmap_encode_distance :: (d: float, range: float) -> u32 {
    r := max(range, 0.0001);
    n := clamp(d / r * 0.5 + 0.5, 0.0, 1.0);
    return cast(u32) floor(n * 255.0 + 0.5);
}

brickmap_decode_distance :: (v: u32, range: float) -> float {
    n := cast(float) min(v, cast(u32) 255) / 255.0;
    return (n * 2.0 - 1.0) * range;
}

brickmap_atlas_index :: (brick_index: s32, vx: s32, vy: s32, vz: s32) -> s32 {
    local := brickmap_flatten_3d(vx, vy, vz, BRICKMAP_BRICK_RES);
    return brick_index * BRICKMAP_BRICK_VOXELS + local;
}

brickmap_read_distance :: (params: *Brickmap_Params, atlas_index: s32, vx: s32, vy: s32, vz: s32) -> float {
    idx := brickmap_atlas_index(atlas_index, vx, vy, vz);
    return brickmap_decode_distance(params.atlas_values[idx], params.distance_range);
}

brickmap_sample_brick_trilinear :: (params: *Brickmap_Params, atlas_index: s32, uvw: Vector3) -> float {
    px := clamp(uvw.x, 0.0, cast(float) (BRICKMAP_BRICK_RES - 1));
    py := clamp(uvw.y, 0.0, cast(float) (BRICKMAP_BRICK_RES - 1));
    pz := clamp(uvw.z, 0.0, cast(float) (BRICKMAP_BRICK_RES - 1));

    x0 := cast(s32) floor(px);
    y0 := cast(s32) floor(py);
    z0 := cast(s32) floor(pz);
    x1 := min(x0 + 1, BRICKMAP_BRICK_RES - 1);
    y1 := min(y0 + 1, BRICKMAP_BRICK_RES - 1);
    z1 := min(z0 + 1, BRICKMAP_BRICK_RES - 1);

    tx := px - cast(float) x0;
    ty := py - cast(float) y0;
    tz := pz - cast(float) z0;

    d000 := brickmap_read_distance(params, atlas_index, x0, y0, z0);
    d100 := brickmap_read_distance(params, atlas_index, x1, y0, z0);
    d010 := brickmap_read_distance(params, atlas_index, x0, y1, z0);
    d110 := brickmap_read_distance(params, atlas_index, x1, y1, z0);
    d001 := brickmap_read_distance(params, atlas_index, x0, y0, z1);
    d101 := brickmap_read_distance(params, atlas_index, x1, y0, z1);
    d011 := brickmap_read_distance(params, atlas_index, x0, y1, z1);
    d111 := brickmap_read_distance(params, atlas_index, x1, y1, z1);

    c00 := mix(d000, d100, tx);
    c10 := mix(d010, d110, tx);
    c01 := mix(d001, d101, tx);
    c11 := mix(d011, d111, tx);
    c0 := mix(c00, c10, ty);
    c1 := mix(c01, c11, ty);
    return mix(c0, c1, tz);
}

brickmap_sample_cached_sdf :: (params: *Brickmap_Params, p: Vector3) -> float {
    for lod: 0..BRICKMAP_LOD_COUNT-1 {
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
        ptr_idx := ptr_base + brickmap_flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
        atlas_index := params.pointer_grid[ptr_idx];
        if atlas_index < 0 continue;

        local_x := gx - cast(float) (bx * BRICKMAP_BRICK_RES);
        local_y := gy - cast(float) (by * BRICKMAP_BRICK_RES);
        local_z := gz - cast(float) (bz * BRICKMAP_BRICK_RES);
        return brickmap_sample_brick_trilinear(params, atlas_index, .{local_x, local_y, local_z});
    }

    return brickmap_eval_scene_sdf(params, p);
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

    min_d := cast(float) 100000.0;
    max_d := cast(float) -100000.0;
    min_abs_d := cast(float) 100000.0;

    d0 := brickmap_eval_scene_sdf(params, .{min_p.x, min_p.y, min_p.z});
    d1 := brickmap_eval_scene_sdf(params, .{max_p.x, min_p.y, min_p.z});
    d2 := brickmap_eval_scene_sdf(params, .{min_p.x, max_p.y, min_p.z});
    d3 := brickmap_eval_scene_sdf(params, .{max_p.x, max_p.y, min_p.z});
    d4 := brickmap_eval_scene_sdf(params, .{min_p.x, min_p.y, max_p.z});
    d5 := brickmap_eval_scene_sdf(params, .{max_p.x, min_p.y, max_p.z});
    d6 := brickmap_eval_scene_sdf(params, .{min_p.x, max_p.y, max_p.z});
    d7 := brickmap_eval_scene_sdf(params, .{max_p.x, max_p.y, max_p.z});
    d8 := brickmap_eval_scene_sdf(params, center_p);

    if d0 < min_d min_d = d0; if d0 > max_d max_d = d0; if abs(d0) < min_abs_d min_abs_d = abs(d0);
    if d1 < min_d min_d = d1; if d1 > max_d max_d = d1; if abs(d1) < min_abs_d min_abs_d = abs(d1);
    if d2 < min_d min_d = d2; if d2 > max_d max_d = d2; if abs(d2) < min_abs_d min_abs_d = abs(d2);
    if d3 < min_d min_d = d3; if d3 > max_d max_d = d3; if abs(d3) < min_abs_d min_abs_d = abs(d3);
    if d4 < min_d min_d = d4; if d4 > max_d max_d = d4; if abs(d4) < min_abs_d min_abs_d = abs(d4);
    if d5 < min_d min_d = d5; if d5 > max_d max_d = d5; if abs(d5) < min_abs_d min_abs_d = abs(d5);
    if d6 < min_d min_d = d6; if d6 > max_d max_d = d6; if abs(d6) < min_abs_d min_abs_d = abs(d6);
    if d7 < min_d min_d = d7; if d7 > max_d max_d = d7; if abs(d7) < min_abs_d min_abs_d = abs(d7);
    if d8 < min_d min_d = d8; if d8 > max_d max_d = d8; if abs(d8) < min_abs_d min_abs_d = abs(d8);

    if min_d <= 0.0 && max_d >= 0.0 return true;
    return min_abs_d <= voxel_size * 1.75;
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

brickmap_fragment_main :: (using in: Brickmap_Fragment_In, params: *Brickmap_Params) -> struct { out_color: Vector4; } {
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    denom := max(params.resolution.y, 1.0);
    aspect := params.resolution.x / denom;
    p.x *= aspect;

    tan_half := params.camera_tan_half_fov;
    ro := params.camera_pos;
    rd := brickmap_safe_normalize(params.camera_forward + params.camera_right * (p.x * tan_half) + params.camera_up * (p.y * tan_half));

    t := 0.0;
    hit := false;
    min_hit_eps := 0.003;
    use_cache := params.use_cache_raymarch != 0;
    for 0..170 {
        pos := ro + rd * t;
        d: float;
        if use_cache {
            d = brickmap_sample_cached_sdf(params, pos);
        } else {
            d = brickmap_eval_scene_sdf(params, pos);
        }

        if d < min_hit_eps {
            hit = true;
            break;
        }

        step_scale := ifx use_cache then 0.3 else 0.85;
        t += max(d * step_scale, 0.0035);
        if t > 80.0 break;
    }

    sky_a := Vector3.{0.12, 0.14, 0.18};
    sky_b := Vector3.{0.55, 0.68, 0.88};
    sky_t := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := mix(sky_a, sky_b, sky_t);

    if hit {
        for 0..3 {
            pos := ro + rd * t;
            t -= brickmap_eval_scene_sdf(params, pos) * 0.7;
            if t < 0.0 {
                t = 0.0;
                break;
            }
        }
        pos := ro + rd * t;
        n := brickmap_scene_normal(params, pos);
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
    if thread_id.x != 0 return;

    candidates := min(cast(s32) params.dirty_count, BRICKMAP_MAX_DIRTY_BRICKS);
    out_count: s32 = 0;
    next_atlas := cast(s32) params.atlas_alloc_next;

    for i: 0..candidates-1 {
        req := params.dirty_lod_brick_xyz[i];
        lod := cast(s32) req.x;
        bx := cast(s32) req.y;
        by := cast(s32) req.z;
        bz := cast(s32) req.w;
        if lod < 0 || lod >= BRICKMAP_LOD_COUNT continue;

        lx := bx - params.lod_origin_brick_x[lod];
        ly := by - params.lod_origin_brick_y[lod];
        lz := bz - params.lod_origin_brick_z[lod];
        if lx < 0 || ly < 0 || lz < 0 continue;
        if lx >= BRICKMAP_GRID_RES || ly >= BRICKMAP_GRID_RES || lz >= BRICKMAP_GRID_RES continue;

        ptr_base := lod * BRICKMAP_GRID_CELLS;
        ptr_idx := ptr_base + brickmap_flatten_3d(lx, ly, lz, BRICKMAP_GRID_RES);
        atlas_index := params.pointer_grid[ptr_idx];

        has_surface := brickmap_brick_has_surface(params, lod, bx, by, bz);
        if !has_surface {
            params.pointer_grid[ptr_idx] = -1;
            continue;
        }

        if atlas_index < 0 {
            if next_atlas >= BRICKMAP_MAX_BRICKS continue;
            atlas_index = next_atlas;
            next_atlas += 1;
            params.pointer_grid[ptr_idx] = atlas_index;
        }

        if out_count >= BRICKMAP_MAX_DIRTY_BRICKS continue;
        params.dirty_lod_brick_xyz[out_count] = req;
        params.dirty_atlas_index[out_count] = cast(u32) atlas_index;
        out_count += 1;
    }

    params.dirty_count = cast(u32) out_count;
    params.atlas_alloc_next = cast(u32) next_atlas;
} @compute_shader

brickmap_bake_compute :: (using in: Brickmap_Compute_In, params: *Brickmap_Params) {
    total_voxels := params.dirty_count * BRICKMAP_BRICK_VOXELS;
    if thread_id.x >= total_voxels return;

    flat := cast(s32) thread_id.x;
    brick_i := flat / BRICKMAP_BRICK_VOXELS;
    voxel_i := flat - brick_i * BRICKMAP_BRICK_VOXELS;

    req := params.dirty_lod_brick_xyz[brick_i];
    lod := cast(s32) req.x;
    if lod < 0 || lod >= BRICKMAP_LOD_COUNT return;

    voxel_size := max(params.lod_voxel_size[lod], 0.0001);

    vx := voxel_i % BRICKMAP_BRICK_RES;
    vy := (voxel_i / BRICKMAP_BRICK_RES) % BRICKMAP_BRICK_RES;
    vz := voxel_i / (BRICKMAP_BRICK_RES * BRICKMAP_BRICK_RES);

    brick_x := cast(s32) req.y;
    brick_y := cast(s32) req.z;
    brick_z := cast(s32) req.w;
    world_vox_x := cast(float) (brick_x * BRICKMAP_BRICK_RES + vx) + 0.5;
    world_vox_y := cast(float) (brick_y * BRICKMAP_BRICK_RES + vy) + 0.5;
    world_vox_z := cast(float) (brick_z * BRICKMAP_BRICK_RES + vz) + 0.5;

    p := Vector3.{world_vox_x * voxel_size, world_vox_y * voxel_size, world_vox_z * voxel_size};
    d := brickmap_eval_scene_sdf(params, p);

    atlas_index := cast(s32) params.dirty_atlas_index[brick_i];
    out_idx := brickmap_atlas_index(atlas_index, vx, vy, vz);
    params.atlas_values[out_idx] = brickmap_encode_distance(d, params.distance_range);
} @compute_shader
