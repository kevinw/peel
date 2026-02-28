#import "Jai-Shader-Transpiler";
#import "Math";

TM_Chunk_Res :: 24;
TM_Sample_Res :: TM_Chunk_Res + 1;
TM_Cell_Count :: TM_Chunk_Res * TM_Chunk_Res * TM_Chunk_Res;
TM_Max_Verts_Per_Cell :: 36;
TM_Voxel_Size :: 0.35;
TM_Iso_Level :: 0.0;

TM_UVector3 :: struct {
    x, y, z: u32;
}

TM_Compute_In :: struct {
    thread_id: TM_UVector3; @thread_position_in_grid
}

TM_Float4 :: struct {
    x, y, z, w: float;
}

tm_sample_index :: (x: u32, y: u32, z: u32) -> u32 {
    return x + y * TM_Sample_Res + z * TM_Sample_Res * TM_Sample_Res;
}

tm_interp_iso :: (pa: Vector3, pb: Vector3, da: float, db: float) -> Vector3 {
    denom := da - db;
    if abs(denom) < 0.000001 return pa;
    t := da / denom;
    if t < 0.0 t = 0.0;
    if t > 1.0 t = 1.0;
    return pa + (pb - pa) * t;
}

tm_getp :: (i: u32, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Vector3 {
    if i == 0 return p0;
    if i == 1 return p1;
    if i == 2 return p2;
    return p3;
}

tm_getd :: (i: u32, d0: float, d1: float, d2: float, d3: float) -> float {
    if i == 0 return d0;
    if i == 1 return d1;
    if i == 2 return d2;
    return d3;
}

tm_getg :: (i: u32, g0: Vector3, g1: Vector3, g2: Vector3, g3: Vector3) -> Vector3 {
    if i == 0 return g0;
    if i == 1 return g1;
    if i == 2 return g2;
    return g3;
}

tm_safe_normalize :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 > 0.0000001 return v / sqrt(len2);
    return .{0.0, 1.0, 0.0};
}

tm_interp_grad :: (ga: Vector3, gb: Vector3, da: float, db: float) -> Vector3 {
    denom := da - db;
    if abs(denom) < 0.000001 return tm_safe_normalize(ga);
    t := da / denom;
    if t < 0.0 t = 0.0;
    if t > 1.0 t = 1.0;
    return tm_safe_normalize(ga + (gb - ga) * t);
}

tm_emit_vertex :: (positions: *TM_Float4, normals: *TM_Float4, base: u32, out_count: u32, p: Vector3, n: Vector3) -> u32 {
    if out_count >= TM_Max_Verts_Per_Cell return out_count;
    i := base + out_count;
    positions[i].x = p.x;
    positions[i].y = p.y;
    positions[i].z = p.z;
    positions[i].w = 0.0;
    normals[i].x = n.x;
    normals[i].y = n.y;
    normals[i].z = n.z;
    normals[i].w = 0.0;
    return out_count + 1;
}

tm_emit_triangle :: (positions: *TM_Float4, normals: *TM_Float4, base: u32, out_count: u32,
                     p0: Vector3, n0: Vector3, p1: Vector3, n1: Vector3, p2: Vector3, n2: Vector3) -> u32 {
    out_count = tm_emit_vertex(positions, normals, base, out_count, p0, n0);
    out_count = tm_emit_vertex(positions, normals, base, out_count, p1, n1);
    out_count = tm_emit_vertex(positions, normals, base, out_count, p2, n2);
    return out_count;
}

tm_mesh_tetra :: (positions: *TM_Float4, normals: *TM_Float4, base: u32, out_count: u32,
                  p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
                  d0: float, d1: float, d2: float, d3: float,
                  g0: Vector3, g1: Vector3, g2: Vector3, g3: Vector3) -> u32 {
    inside: [4]u32;
    outside: [4]u32;
    inside_count: u32 = 0;
    outside_count: u32 = 0;

    if d0 < TM_Iso_Level { inside[inside_count] = 0; inside_count += 1; } else { outside[outside_count] = 0; outside_count += 1; }
    if d1 < TM_Iso_Level { inside[inside_count] = 1; inside_count += 1; } else { outside[outside_count] = 1; outside_count += 1; }
    if d2 < TM_Iso_Level { inside[inside_count] = 2; inside_count += 1; } else { outside[outside_count] = 2; outside_count += 1; }
    if d3 < TM_Iso_Level { inside[inside_count] = 3; inside_count += 1; } else { outside[outside_count] = 3; outside_count += 1; }

    if inside_count == 0 || inside_count == 4 return out_count;

    if inside_count == 1 {
        i0 := inside[0];
        o0 := outside[0];
        o1 := outside[1];
        o2 := outside[2];

        pi0 := tm_getp(i0, p0, p1, p2, p3);
        po0 := tm_getp(o0, p0, p1, p2, p3);
        po1 := tm_getp(o1, p0, p1, p2, p3);
        po2 := tm_getp(o2, p0, p1, p2, p3);
        di0 := tm_getd(i0, d0, d1, d2, d3);
        do0 := tm_getd(o0, d0, d1, d2, d3);
        do1 := tm_getd(o1, d0, d1, d2, d3);
        do2 := tm_getd(o2, d0, d1, d2, d3);
        gi0 := tm_getg(i0, g0, g1, g2, g3);
        go0 := tm_getg(o0, g0, g1, g2, g3);
        go1 := tm_getg(o1, g0, g1, g2, g3);
        go2 := tm_getg(o2, g0, g1, g2, g3);

        q0 := tm_interp_iso(pi0, po0, di0, do0);
        q1 := tm_interp_iso(pi0, po1, di0, do1);
        q2 := tm_interp_iso(pi0, po2, di0, do2);
        n0 := tm_interp_grad(gi0, go0, di0, do0);
        n1 := tm_interp_grad(gi0, go1, di0, do1);
        n2 := tm_interp_grad(gi0, go2, di0, do2);
        out_count = tm_emit_triangle(positions, normals, base, out_count, q0, n0, q1, n1, q2, n2);
        return out_count;
    }

    if inside_count == 3 {
        o0 := outside[0];
        i0 := inside[0];
        i1 := inside[1];
        i2 := inside[2];

        po0 := tm_getp(o0, p0, p1, p2, p3);
        pi0 := tm_getp(i0, p0, p1, p2, p3);
        pi1 := tm_getp(i1, p0, p1, p2, p3);
        pi2 := tm_getp(i2, p0, p1, p2, p3);
        do0 := tm_getd(o0, d0, d1, d2, d3);
        di0 := tm_getd(i0, d0, d1, d2, d3);
        di1 := tm_getd(i1, d0, d1, d2, d3);
        di2 := tm_getd(i2, d0, d1, d2, d3);
        go0 := tm_getg(o0, g0, g1, g2, g3);
        gi0 := tm_getg(i0, g0, g1, g2, g3);
        gi1 := tm_getg(i1, g0, g1, g2, g3);
        gi2 := tm_getg(i2, g0, g1, g2, g3);

        q0 := tm_interp_iso(po0, pi0, do0, di0);
        q1 := tm_interp_iso(po0, pi1, do0, di1);
        q2 := tm_interp_iso(po0, pi2, do0, di2);
        n0 := tm_interp_grad(go0, gi0, do0, di0);
        n1 := tm_interp_grad(go0, gi1, do0, di1);
        n2 := tm_interp_grad(go0, gi2, do0, di2);
        out_count = tm_emit_triangle(positions, normals, base, out_count, q0, n0, q2, n2, q1, n1);
        return out_count;
    }

    i0 := inside[0];
    i1 := inside[1];
    o0 := outside[0];
    o1 := outside[1];

    pi0 := tm_getp(i0, p0, p1, p2, p3);
    pi1 := tm_getp(i1, p0, p1, p2, p3);
    po0 := tm_getp(o0, p0, p1, p2, p3);
    po1 := tm_getp(o1, p0, p1, p2, p3);
    di0 := tm_getd(i0, d0, d1, d2, d3);
    di1 := tm_getd(i1, d0, d1, d2, d3);
    do0 := tm_getd(o0, d0, d1, d2, d3);
    do1 := tm_getd(o1, d0, d1, d2, d3);
    gi0 := tm_getg(i0, g0, g1, g2, g3);
    gi1 := tm_getg(i1, g0, g1, g2, g3);
    go0 := tm_getg(o0, g0, g1, g2, g3);
    go1 := tm_getg(o1, g0, g1, g2, g3);

    q0 := tm_interp_iso(pi0, po0, di0, do0);
    q1 := tm_interp_iso(pi1, po0, di1, do0);
    q2 := tm_interp_iso(pi1, po1, di1, do1);
    q3 := tm_interp_iso(pi0, po1, di0, do1);
    n0 := tm_interp_grad(gi0, go0, di0, do0);
    n1 := tm_interp_grad(gi1, go0, di1, do0);
    n2 := tm_interp_grad(gi1, go1, di1, do1);
    n3 := tm_interp_grad(gi0, go1, di0, do1);

    out_count = tm_emit_triangle(positions, normals, base, out_count, q0, n0, q1, n1, q2, n2);
    out_count = tm_emit_triangle(positions, normals, base, out_count, q0, n0, q2, n2, q3, n3);
    return out_count;
}

terrain_mesh_build_chunk_compute :: (using in: TM_Compute_In, density: *float, positions: *TM_Float4, normals: *TM_Float4) {
    cell_idx := thread_id.x;
    if cell_idx >= TM_Cell_Count return;

    x := cell_idx % TM_Chunk_Res;
    yz := cell_idx / TM_Chunk_Res;
    y := yz % TM_Chunk_Res;
    z := yz / TM_Chunk_Res;

    sx0 := x;
    sy0 := y;
    sz0 := z;
    sx1 := x + 1;
    sy1 := y + 1;
    sz1 := z + 1;

    c0 := Vector3.{cast(float) sx0 * TM_Voxel_Size, cast(float) sy0 * TM_Voxel_Size, cast(float) sz0 * TM_Voxel_Size};
    c1 := Vector3.{cast(float) sx1 * TM_Voxel_Size, cast(float) sy0 * TM_Voxel_Size, cast(float) sz0 * TM_Voxel_Size};
    c2 := Vector3.{cast(float) sx1 * TM_Voxel_Size, cast(float) sy1 * TM_Voxel_Size, cast(float) sz0 * TM_Voxel_Size};
    c3 := Vector3.{cast(float) sx0 * TM_Voxel_Size, cast(float) sy1 * TM_Voxel_Size, cast(float) sz0 * TM_Voxel_Size};
    c4 := Vector3.{cast(float) sx0 * TM_Voxel_Size, cast(float) sy0 * TM_Voxel_Size, cast(float) sz1 * TM_Voxel_Size};
    c5 := Vector3.{cast(float) sx1 * TM_Voxel_Size, cast(float) sy0 * TM_Voxel_Size, cast(float) sz1 * TM_Voxel_Size};
    c6 := Vector3.{cast(float) sx1 * TM_Voxel_Size, cast(float) sy1 * TM_Voxel_Size, cast(float) sz1 * TM_Voxel_Size};
    c7 := Vector3.{cast(float) sx0 * TM_Voxel_Size, cast(float) sy1 * TM_Voxel_Size, cast(float) sz1 * TM_Voxel_Size};

    d0 := density[tm_sample_index(sx0, sy0, sz0)];
    d1 := density[tm_sample_index(sx1, sy0, sz0)];
    d2 := density[tm_sample_index(sx1, sy1, sz0)];
    d3 := density[tm_sample_index(sx0, sy1, sz0)];
    d4 := density[tm_sample_index(sx0, sy0, sz1)];
    d5 := density[tm_sample_index(sx1, sy0, sz1)];
    d6 := density[tm_sample_index(sx1, sy1, sz1)];
    d7 := density[tm_sample_index(sx0, sy1, sz1)];

    g0 := Vector3.{d1 - d0, d3 - d0, d4 - d0};
    g1 := Vector3.{d1 - d0, d2 - d1, d5 - d1};
    g2 := Vector3.{d2 - d3, d2 - d1, d6 - d2};
    g3 := Vector3.{d2 - d3, d3 - d0, d7 - d3};
    g4 := Vector3.{d5 - d4, d7 - d4, d4 - d0};
    g5 := Vector3.{d5 - d4, d6 - d5, d5 - d1};
    g6 := Vector3.{d6 - d7, d6 - d5, d6 - d2};
    g7 := Vector3.{d6 - d7, d7 - d4, d7 - d3};

    base := cell_idx * TM_Max_Verts_Per_Cell;
    emitted: u32 = 0;

    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c5, c1, c6, d0, d5, d1, d6, g0, g5, g1, g6);
    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c1, c2, c6, d0, d1, d2, d6, g0, g1, g2, g6);
    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c2, c3, c6, d0, d2, d3, d6, g0, g2, g3, g6);
    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c3, c7, c6, d0, d3, d7, d6, g0, g3, g7, g6);
    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c7, c4, c6, d0, d7, d4, d6, g0, g7, g4, g6);
    emitted = tm_mesh_tetra(positions, normals, base, emitted, c0, c4, c5, c6, d0, d4, d5, d6, g0, g4, g5, g6);

    positions[base].w = cast(float) emitted;
} @compute_shader
