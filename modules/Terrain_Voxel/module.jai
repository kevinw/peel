#scope_export

Chunk_Res :: 24;
Sample_Res :: Chunk_Res + 1;
Sample_Count :: Sample_Res * Sample_Res * Sample_Res;
Voxel_Size :: 0.35;
Density_Scale :: 1024.0;
Iso_Level :: 0.0;

Chunk_World_Size :: cast(float) Chunk_Res * Voxel_Size;

Chunk_Coord :: struct {
    x, y, z: s64;
}

Chunk_Mesh :: struct {
    positions: [..]Vector3;
    normals: [..]Vector3;
    vertex_count: s64;
    dirty: bool;
}

Chunk :: struct {
    coord: Chunk_Coord;
    origin: Vector3;
    density: [Sample_Count]s16;
    mesh: Chunk_Mesh;
    dirty: bool;
}

Terrain_Voxel_Context :: struct {
    initialized: bool;
    chunks: [..]Chunk;
    stream_radius_xz: s64;
    stream_layers_y: s64;
    stream_layers_below_y: s64;
    demo_deform_time: float;
}

init :: (ctx: *Terrain_Voxel_Context, stream_radius_xz: s64 = 1, stream_layers_y: s64 = 1, stream_layers_below_y: s64 = 0) {
    ctx.* = .{};
    if stream_radius_xz < 0 stream_radius_xz = 0;
    if stream_layers_y < 1 stream_layers_y = 1;
    if stream_layers_below_y < 0 stream_layers_below_y = 0;

    ctx.stream_radius_xz = stream_radius_xz;
    ctx.stream_layers_y = stream_layers_y;
    ctx.stream_layers_below_y = stream_layers_below_y;
    ctx.chunks.allocator = context.allocator;
    ctx.initialized = true;
}

deinit :: (ctx: *Terrain_Voxel_Context) {
    for *ctx.chunks {
        array_free(it.mesh.positions);
        array_free(it.mesh.normals);
    }
    array_free(ctx.chunks);
    ctx.* = .{};
}

chunks :: (ctx: *Terrain_Voxel_Context) -> []Chunk {
    return ctx.chunks;
}

total_vertex_count :: (ctx: *Terrain_Voxel_Context) -> s64 {
    total: s64 = 0;
    for ctx.chunks total += it.mesh.vertex_count;
    return total;
}

carve_sphere :: (ctx: *Terrain_Voxel_Context, center: Vector3, radius: float, delta: float) {
    if radius <= 0.0 return;

    for *ctx.chunks {
        if !chunk_overlaps_sphere(it, center, radius) continue;
        apply_brush_sphere_density(it, center, radius, delta);
        it.dirty = true;
        it.mesh.dirty = true;
    }

    sync_dirty_chunk_boundaries(ctx);
}

carve_capsule :: (ctx: *Terrain_Voxel_Context, a: Vector3, b: Vector3, radius: float, delta: float) {
    if radius <= 0.0 return;

    for *ctx.chunks {
        if !chunk_overlaps_capsule(it, a, b, radius) continue;
        apply_brush_capsule_density(it, a, b, radius, delta);
        it.dirty = true;
        it.mesh.dirty = true;
    }

    sync_dirty_chunk_boundaries(ctx);
}

tick_demo_deform :: (ctx: *Terrain_Voxel_Context, dt: float, world_time: float) {
    ctx.demo_deform_time += dt;
    if ctx.demo_deform_time < 2.5 return;
    ctx.demo_deform_time = 0.0;

    c := Vector3.{sin(world_time * 0.7) * 2.4, -0.7 + sin(world_time * 1.9) * 0.25, cos(world_time * 0.6) * 2.4};
    carve_sphere(ctx, c, 0.34, +1.0);
}

update_streaming :: (ctx: *Terrain_Voxel_Context, center_world: Vector3) {
    if !ctx.initialized return;

    center_coord := world_to_chunk_coord(center_world);
    min_stream_y := -ctx.stream_layers_below_y;
    max_stream_y := ctx.stream_layers_y - 1;

    for dz: -ctx.stream_radius_xz..ctx.stream_radius_xz {
        for dx: -ctx.stream_radius_xz..ctx.stream_radius_xz {
            for y: min_stream_y..max_stream_y {
                coord := Chunk_Coord.{
                    x = center_coord.x + dx,
                    y = y,
                    z = center_coord.z + dz,
                };
                if find_chunk_index(ctx, coord) >= 0 continue;
                add_chunk(ctx, coord);
            }
        }
    }

    i: s64 = 0;
    while i < ctx.chunks.count {
        c := ctx.chunks[i].coord;
        keep_xz := abs(c.x - center_coord.x) <= ctx.stream_radius_xz && abs(c.z - center_coord.z) <= ctx.stream_radius_xz;
        keep_y := c.y >= min_stream_y && c.y <= max_stream_y;
        if keep_xz && keep_y {
            i += 1;
            continue;
        }

        array_free(ctx.chunks[i].mesh.positions);
        array_free(ctx.chunks[i].mesh.normals);
        array_ordered_remove_by_index(*ctx.chunks, i);
    }
}

rebuild_dirty_meshes :: (ctx: *Terrain_Voxel_Context, max_chunks: s64 = 0) {
    rebuilt: s64 = 0;
    for *ctx.chunks {
        if !it.dirty continue;
        rebuild_chunk_mesh(it);
        it.dirty = false;
        if max_chunks > 0 {
            rebuilt += 1;
            if rebuilt >= max_chunks break;
        }
    }
}

#scope_file

world_to_chunk_coord :: (p: Vector3) -> Chunk_Coord {
    return .{
        x = cast(s64) floor(p.x / Chunk_World_Size),
        y = cast(s64) floor(p.y / Chunk_World_Size),
        z = cast(s64) floor(p.z / Chunk_World_Size),
    };
}

chunk_origin :: (coord: Chunk_Coord) -> Vector3 {
    return .{
        cast(float) coord.x * Chunk_World_Size,
        cast(float) coord.y * Chunk_World_Size - 3.0,
        cast(float) coord.z * Chunk_World_Size,
    };
}

coords_equal :: inline (a: Chunk_Coord, b: Chunk_Coord) -> bool {
    return a.x == b.x && a.y == b.y && a.z == b.z;
}

find_chunk_index :: (ctx: *Terrain_Voxel_Context, coord: Chunk_Coord) -> s64 {
    for 0..ctx.chunks.count - 1 {
        if coords_equal(ctx.chunks[it].coord, coord) return it;
    }
    return -1;
}

sample_index :: inline (x: s64, y: s64, z: s64) -> s64 {
    return x + y * Sample_Res + z * Sample_Res * Sample_Res;
}

sample_pos_world :: inline (chunk: *Chunk, x: s64, y: s64, z: s64) -> Vector3 {
    return .{
        chunk.origin.x + cast(float) x * Voxel_Size,
        chunk.origin.y + cast(float) y * Voxel_Size,
        chunk.origin.z + cast(float) z * Voxel_Size,
    };
}

get_density_f32 :: inline (chunk: *Chunk, x: s64, y: s64, z: s64) -> float {
    return cast(float) chunk.density[sample_index(x, y, z)] / Density_Scale;
}

density_grad :: inline (chunk: *Chunk, x: s64, y: s64, z: s64) -> Vector3 {
    x0 := ifx x > 0 then x - 1 else x;
    x1 := ifx x + 1 < Sample_Res then x + 1 else x;
    y0 := ifx y > 0 then y - 1 else y;
    y1 := ifx y + 1 < Sample_Res then y + 1 else y;
    z0 := ifx z > 0 then z - 1 else z;
    z1 := ifx z + 1 < Sample_Res then z + 1 else z;

    gx := get_density_f32(chunk, x1, y,  z ) - get_density_f32(chunk, x0, y,  z );
    gy := get_density_f32(chunk, x,  y1, z ) - get_density_f32(chunk, x,  y0, z );
    gz := get_density_f32(chunk, x,  y,  z1) - get_density_f32(chunk, x,  y,  z0);
    if x == 0 || x == Sample_Res - 1 gx = 0.0;
    if y == 0 || y == Sample_Res - 1 gy = 0.0;
    if z == 0 || z == Sample_Res - 1 gz = 0.0;
    return safe_normalize(.{gx, gy, gz});
}

set_density_f32 :: inline (chunk: *Chunk, x: s64, y: s64, z: s64, d: float) {
    scaled := cast(s64) floor(d * Density_Scale + ifx d >= 0 then 0.5 else -0.5);
    if scaled > 32767 scaled = 32767;
    if scaled < -32768 scaled = -32768;
    chunk.density[sample_index(x, y, z)] = cast(s16) scaled;
}

smooth_falloff :: inline (t: float) -> float {
    x := saturate(t);
    return x * x * (3.0 - 2.0 * x);
}

hash_u32 :: (x: u32) -> u32 {
    v := x;
    v ^= v >> 16;
    v *= 0x7feb352d;
    v ^= v >> 15;
    v *= 0x846ca68b;
    v ^= v >> 16;
    return v;
}

hash_coord_01 :: (coord: Chunk_Coord, salt: u32) -> float {
    ux := cast,no_check(u32) (coord.x * 73856093 + 19349663);
    uy := cast,no_check(u32) (coord.y * 83492791 + 2971215073);
    uz := cast,no_check(u32) (coord.z * 2654435761 + 97531);
    h := hash_u32(ux ^ (uy << 1) ^ (uz << 2) ^ salt);
    return cast(float) (h & 0x00ffffff) / cast(float) 0x01000000;
}

apply_brush_sphere_density :: (chunk: *Chunk, center: Vector3, radius: float, delta: float) {
    if radius <= 0.0 return;

    min_x := cast(s64) floor((center.x - radius - chunk.origin.x) / Voxel_Size);
    min_y := cast(s64) floor((center.y - radius - chunk.origin.y) / Voxel_Size);
    min_z := cast(s64) floor((center.z - radius - chunk.origin.z) / Voxel_Size);
    max_x := cast(s64) ceil ((center.x + radius - chunk.origin.x) / Voxel_Size);
    max_y := cast(s64) ceil ((center.y + radius - chunk.origin.y) / Voxel_Size);
    max_z := cast(s64) ceil ((center.z + radius - chunk.origin.z) / Voxel_Size);

    if min_x < 0 min_x = 0;
    if min_y < 0 min_y = 0;
    if min_z < 0 min_z = 0;
    if max_x > Sample_Res - 1 max_x = Sample_Res - 1;
    if max_y > Sample_Res - 1 max_y = Sample_Res - 1;
    if max_z > Sample_Res - 1 max_z = Sample_Res - 1;

    r2 := radius * radius;
    for z: min_z..max_z {
        for y: min_y..max_y {
            for x: min_x..max_x {
                p := sample_pos_world(chunk, x, y, z);
                d := p - center;
                dist2 := dot(d, d);
                if dist2 > r2 continue;

                dist := sqrt(dist2);
                w := 1.0 - smooth_falloff(dist / radius);
                s := get_density_f32(chunk, x, y, z);
                set_density_f32(chunk, x, y, z, s + delta * w);
            }
        }
    }
}

apply_brush_capsule_density :: (chunk: *Chunk, a: Vector3, b: Vector3, radius: float, delta: float) {
    dir := b - a;
    len := length(dir);
    if len <= 0.0001 {
        apply_brush_sphere_density(chunk, a, radius, delta);
        return;
    }

    step := max(radius * 0.5, Voxel_Size * 0.75);
    steps := cast(s64) ceil(len / step);
    if steps < 1 steps = 1;

    for i: 0..steps {
        t := cast(float) i / cast(float) steps;
        p := a + dir * t;
        apply_brush_sphere_density(chunk, p, radius, delta);
    }
}

copy_shared_face_x :: (src: *Chunk, dst: *Chunk, src_x: s64, dst_x: s64) {
    for z: 0..Sample_Res - 1 {
        for y: 0..Sample_Res - 1 {
            src_i := sample_index(src_x, y, z);
            dst_i := sample_index(dst_x, y, z);
            dst.density[dst_i] = src.density[src_i];
        }
    }
}

copy_shared_face_y :: (src: *Chunk, dst: *Chunk, src_y: s64, dst_y: s64) {
    for z: 0..Sample_Res - 1 {
        for x: 0..Sample_Res - 1 {
            src_i := sample_index(x, src_y, z);
            dst_i := sample_index(x, dst_y, z);
            dst.density[dst_i] = src.density[src_i];
        }
    }
}

copy_shared_face_z :: (src: *Chunk, dst: *Chunk, src_z: s64, dst_z: s64) {
    for y: 0..Sample_Res - 1 {
        for x: 0..Sample_Res - 1 {
            src_i := sample_index(x, y, src_z);
            dst_i := sample_index(x, y, dst_z);
            dst.density[dst_i] = src.density[src_i];
        }
    }
}

sync_face_to_neighbor :: (ctx: *Terrain_Voxel_Context, chunk_i: s64, dx: s64, dy: s64, dz: s64) {
    coord := ctx.chunks[chunk_i].coord;
    neighbor_coord := Chunk_Coord.{coord.x + dx, coord.y + dy, coord.z + dz};
    neighbor_i := find_chunk_index(ctx, neighbor_coord);
    if neighbor_i < 0 return;

    src := *ctx.chunks[chunk_i];
    dst := *ctx.chunks[neighbor_i];

    if dx == -1 copy_shared_face_x(src, dst, 0, Sample_Res - 1);
    if dx == 1 copy_shared_face_x(src, dst, Sample_Res - 1, 0);
    if dy == -1 copy_shared_face_y(src, dst, 0, Sample_Res - 1);
    if dy == 1 copy_shared_face_y(src, dst, Sample_Res - 1, 0);
    if dz == -1 copy_shared_face_z(src, dst, 0, Sample_Res - 1);
    if dz == 1 copy_shared_face_z(src, dst, Sample_Res - 1, 0);

    dst.dirty = true;
    dst.mesh.dirty = true;
}

sync_dirty_chunk_boundaries :: (ctx: *Terrain_Voxel_Context) {
    for i: 0..ctx.chunks.count - 1 {
        if !ctx.chunks[i].dirty continue;
        sync_face_to_neighbor(ctx, i, -1,  0,  0);
        sync_face_to_neighbor(ctx, i, 1,  0,  0);
        sync_face_to_neighbor(ctx, i,  0, -1,  0);
        sync_face_to_neighbor(ctx, i,  0, 1,  0);
        sync_face_to_neighbor(ctx, i,  0,  0, -1);
        sync_face_to_neighbor(ctx, i,  0,  0, 1);
    }
}

stitch_face_from_neighbor :: (ctx: *Terrain_Voxel_Context, chunk: *Chunk, dx: s64, dy: s64, dz: s64) {
    coord := chunk.coord;
    neighbor_coord := Chunk_Coord.{coord.x + dx, coord.y + dy, coord.z + dz};
    neighbor_i := find_chunk_index(ctx, neighbor_coord);
    if neighbor_i < 0 return;

    neighbor := *ctx.chunks[neighbor_i];

    if dx == -1 copy_shared_face_x(neighbor, chunk, Sample_Res - 1, 0);
    if dx == 1 copy_shared_face_x(neighbor, chunk, 0, Sample_Res - 1);
    if dy == -1 copy_shared_face_y(neighbor, chunk, Sample_Res - 1, 0);
    if dy == 1 copy_shared_face_y(neighbor, chunk, 0, Sample_Res - 1);
    if dz == -1 copy_shared_face_z(neighbor, chunk, Sample_Res - 1, 0);
    if dz == 1 copy_shared_face_z(neighbor, chunk, 0, Sample_Res - 1);
}

stitch_chunk_from_neighbors :: (ctx: *Terrain_Voxel_Context, chunk: *Chunk) {
    stitch_face_from_neighbor(ctx, chunk, -1,  0,  0);
    stitch_face_from_neighbor(ctx, chunk, 1,  0,  0);
    stitch_face_from_neighbor(ctx, chunk,  0, -1,  0);
    stitch_face_from_neighbor(ctx, chunk,  0, 1,  0);
    stitch_face_from_neighbor(ctx, chunk,  0,  0, -1);
    stitch_face_from_neighbor(ctx, chunk,  0,  0, 1);
}

chunk_overlaps_sphere :: (chunk: *Chunk, center: Vector3, radius: float) -> bool {
    min_b := chunk.origin;
    max_b := chunk.origin + Vector3.{Chunk_World_Size, Chunk_World_Size, Chunk_World_Size};

    cx := clamp(center.x, min_b.x, max_b.x);
    cy := clamp(center.y, min_b.y, max_b.y);
    cz := clamp(center.z, min_b.z, max_b.z);

    d := center - Vector3.{cx, cy, cz};
    return dot(d, d) <= radius * radius;
}

chunk_overlaps_capsule :: (chunk: *Chunk, a: Vector3, b: Vector3, radius: float) -> bool {
    mid := (a + b) * 0.5;
    half_len := length(b - a) * 0.5;
    return chunk_overlaps_sphere(chunk, mid, radius + half_len + Chunk_World_Size * 0.6);
}

generate_chunk_density :: (chunk: *Chunk) {
    seed0 := hash_coord_01(chunk.coord, 0xabc001);
    seed1 := hash_coord_01(chunk.coord, 0xabc002);
    seed2 := hash_coord_01(chunk.coord, 0xabc003);
    seed3 := hash_coord_01(chunk.coord, 0xabc004);
    seed4 := hash_coord_01(chunk.coord, 0xabc005);
    seed5 := hash_coord_01(chunk.coord, 0xabc006);

    warp_phase_x := (seed0 * 2.0 - 1.0) * 7.0;
    warp_phase_z := (seed1 * 2.0 - 1.0) * 7.0;
    warp_freq_x := 0.42 + seed2 * 0.35;
    warp_freq_z := 0.39 + seed3 * 0.33;
    warp_amp := 0.22 + seed4 * 0.35;

    for z: 0..Sample_Res - 1 {
        for y: 0..Sample_Res - 1 {
            for x: 0..Sample_Res - 1 {
                p := sample_pos_world(chunk, x, y, z);

                // Larger vertical relief with ridges plus broad undulation.
                h0 := -0.92 + sin(p.x * 0.12) * 0.52 + cos(p.z * 0.10) * 0.46;
                h1 := sin((p.x + p.z) * 0.055) * 0.66 + cos((p.x - p.z) * 0.072) * 0.42;

                ridge0 := abs(sin(p.x * 0.24 + p.z * 0.19));
                ridge1 := abs(cos(p.x * 0.16 - p.z * 0.27));
                ridges := (ridge0 * ridge1) * 1.15 - 0.55;

                detail := sin(p.x * 0.54 + p.z * 0.41) * 0.17 + cos(p.x * 0.61 - p.z * 0.58) * 0.14;

                // Chunk-unique variation with edge fade to keep boundaries continuous.
                u := cast(float) x / cast(float) (Sample_Res - 1);
                v := cast(float) z / cast(float) (Sample_Res - 1);
                edge_x := min(u, 1.0 - u) * 2.0;
                edge_z := min(v, 1.0 - v) * 2.0;
                edge_fade := smooth_falloff(min(edge_x, edge_z));
                chunk_warp := (sin(p.x * warp_freq_x + warp_phase_x) + cos(p.z * warp_freq_z + warp_phase_z)) * 0.5;
                chunk_warp *= warp_amp * edge_fade;

                surface := h0 + h1 + ridges + detail + chunk_warp;
                d := p.y - surface;
                set_density_f32(chunk, x, y, z, d);
            }
        }
    }

    cave_center := chunk.origin + Vector3.{
        (0.16 + seed0 * 0.68) * Chunk_World_Size,
        0.18 * Chunk_World_Size + (seed1 - 0.5) * 0.42 * Chunk_World_Size,
        (0.15 + seed2 * 0.70) * Chunk_World_Size,
    };

    // Deeper cavities and longer crevices.
    apply_brush_sphere_density(chunk, cave_center, 0.30 * Chunk_World_Size, +2.1);
    side_cave := cave_center + Vector3.{(seed3 - 0.5) * 0.55 * Chunk_World_Size, (seed4 - 0.5) * 0.24 * Chunk_World_Size, (seed5 - 0.5) * 0.55 * Chunk_World_Size};
    apply_brush_sphere_density(chunk, side_cave, 0.18 * Chunk_World_Size, +1.6);

    tunnel_a := cave_center + Vector3.{-0.58 * Chunk_World_Size, 0.10 * Chunk_World_Size, -0.42 * Chunk_World_Size};
    tunnel_b := cave_center + Vector3.{ 0.70 * Chunk_World_Size, -0.18 * Chunk_World_Size, 0.56 * Chunk_World_Size};
    apply_brush_capsule_density(chunk, tunnel_a, tunnel_b, 0.11 * Chunk_World_Size, +1.9);

    crevice_a := cave_center + Vector3.{-0.10 * Chunk_World_Size, 0.34 * Chunk_World_Size, -0.62 * Chunk_World_Size};
    crevice_b := cave_center + Vector3.{ 0.18 * Chunk_World_Size, -0.44 * Chunk_World_Size, 0.64 * Chunk_World_Size};
    apply_brush_capsule_density(chunk, crevice_a, crevice_b, 0.09 * Chunk_World_Size, +2.2);
}

add_chunk :: (ctx: *Terrain_Voxel_Context, coord: Chunk_Coord) {
    chunk := Chunk.{};
    chunk.coord = coord;
    chunk.origin = chunk_origin(coord);
    chunk.dirty = true;
    chunk.mesh.dirty = true;
    chunk.mesh.positions.allocator = context.allocator;
    chunk.mesh.normals.allocator = context.allocator;

    generate_chunk_density(*chunk);
    stitch_chunk_from_neighbors(ctx, *chunk);
    array_add(*ctx.chunks, chunk);
}

interp_iso :: inline (pa: Vector3, pb: Vector3, da: float, db: float) -> Vector3 {
    denom := da - db;
    if abs(denom) < 0.000001 return pa;
    t := da / denom;
    if t < 0.0 t = 0.0;
    if t > 1.0 t = 1.0;
    return pa + (pb - pa) * t;
}

safe_normalize :: inline (v: Vector3) -> Vector3 {
    n := v;
    normalize(*n, fallback = .{0.0, 1.0, 0.0});
    return n;
}

interp_grad :: inline (ga: Vector3, gb: Vector3, da: float, db: float) -> Vector3 {
    denom := da - db;
    if abs(denom) < 0.000001 return safe_normalize(ga);
    t := da / denom;
    if t < 0.0 t = 0.0;
    if t > 1.0 t = 1.0;
    return safe_normalize(ga + (gb - ga) * t);
}

emit_triangle :: (mesh: *Chunk_Mesh,
                  p0: Vector3, n0: Vector3,
                  p1: Vector3, n1: Vector3,
                  p2: Vector3, n2: Vector3) {
    array_add(*mesh.positions, p0);
    array_add(*mesh.positions, p1);
    array_add(*mesh.positions, p2);
    array_add(*mesh.normals, safe_normalize(n0));
    array_add(*mesh.normals, safe_normalize(n1));
    array_add(*mesh.normals, safe_normalize(n2));
}

mesh_tetra :: (mesh: *Chunk_Mesh, tp: [4]Vector3, td: [4]float, tg: [4]Vector3) {
    inside: [4]s64;
    outside: [4]s64;
    inside_count: s64 = 0;
    outside_count: s64 = 0;

    for i: 0..3 {
        if td[i] < Iso_Level {
            inside[inside_count] = i;
            inside_count += 1;
        } else {
            outside[outside_count] = i;
            outside_count += 1;
        }
    }

    if inside_count == 0 || inside_count == 4 return;

    if inside_count == 1 {
        i0 := inside[0];
        o0 := outside[0];
        o1 := outside[1];
        o2 := outside[2];
        p0 := interp_iso(tp[i0], tp[o0], td[i0], td[o0]);
        p1 := interp_iso(tp[i0], tp[o1], td[i0], td[o1]);
        p2 := interp_iso(tp[i0], tp[o2], td[i0], td[o2]);
        n0 := interp_grad(tg[i0], tg[o0], td[i0], td[o0]);
        n1 := interp_grad(tg[i0], tg[o1], td[i0], td[o1]);
        n2 := interp_grad(tg[i0], tg[o2], td[i0], td[o2]);
        emit_triangle(mesh, p0, n0, p1, n1, p2, n2);
        return;
    }

    if inside_count == 3 {
        o0 := outside[0];
        i0 := inside[0];
        i1 := inside[1];
        i2 := inside[2];
        p0 := interp_iso(tp[o0], tp[i0], td[o0], td[i0]);
        p1 := interp_iso(tp[o0], tp[i1], td[o0], td[i1]);
        p2 := interp_iso(tp[o0], tp[i2], td[o0], td[i2]);
        n0 := interp_grad(tg[o0], tg[i0], td[o0], td[i0]);
        n1 := interp_grad(tg[o0], tg[i1], td[o0], td[i1]);
        n2 := interp_grad(tg[o0], tg[i2], td[o0], td[i2]);
        emit_triangle(mesh, p0, n0, p2, n2, p1, n1);
        return;
    }

    i0 := inside[0];
    i1 := inside[1];
    o0 := outside[0];
    o1 := outside[1];

    p0 := interp_iso(tp[i0], tp[o0], td[i0], td[o0]);
    p1 := interp_iso(tp[i1], tp[o0], td[i1], td[o0]);
    p2 := interp_iso(tp[i1], tp[o1], td[i1], td[o1]);
    p3 := interp_iso(tp[i0], tp[o1], td[i0], td[o1]);
    n0 := interp_grad(tg[i0], tg[o0], td[i0], td[o0]);
    n1 := interp_grad(tg[i1], tg[o0], td[i1], td[o0]);
    n2 := interp_grad(tg[i1], tg[o1], td[i1], td[o1]);
    n3 := interp_grad(tg[i0], tg[o1], td[i0], td[o1]);

    emit_triangle(mesh, p0, n0, p1, n1, p2, n2);
    emit_triangle(mesh, p0, n0, p2, n2, p3, n3);
}

rebuild_chunk_mesh :: (chunk: *Chunk) {
    array_reset(*chunk.mesh.positions);
    array_reset(*chunk.mesh.normals);

    cube_corner_offsets: [8]Vector3 = .[
        .{0, 0, 0}, .{1, 0, 0}, .{1, 1, 0}, .{0, 1, 0},
        .{0, 0, 1}, .{1, 0, 1}, .{1, 1, 1}, .{0, 1, 1},
    ];

    tetra_indices: [24]s64 = .[
        0, 5, 1, 6,
        0, 1, 2, 6,
        0, 2, 3, 6,
        0, 3, 7, 6,
        0, 7, 4, 6,
        0, 4, 5, 6,
    ];

    for z: 0..Chunk_Res - 1 {
        for y: 0..Chunk_Res - 1 {
            for x: 0..Chunk_Res - 1 {
                cp: [8]Vector3;
                cd: [8]float;
                cg: [8]Vector3;
                for i: 0..7 {
                    ox := cast(s64) cube_corner_offsets[i].x;
                    oy := cast(s64) cube_corner_offsets[i].y;
                    oz := cast(s64) cube_corner_offsets[i].z;
                    sx := x + ox;
                    sy := y + oy;
                    sz := z + oz;
                    cp[i] = sample_pos_world(chunk, sx, sy, sz);
                    cd[i] = get_density_f32(chunk, sx, sy, sz);
                }
                cg[0] = density_grad(chunk, sx0, sy0, sz0);
                cg[1] = density_grad(chunk, sx1, sy0, sz0);
                cg[2] = density_grad(chunk, sx1, sy1, sz0);
                cg[3] = density_grad(chunk, sx0, sy1, sz0);
                cg[4] = density_grad(chunk, sx0, sy0, sz1);
                cg[5] = density_grad(chunk, sx1, sy0, sz1);
                cg[6] = density_grad(chunk, sx1, sy1, sz1);
                cg[7] = density_grad(chunk, sx0, sy1, sz1);

                for t: 0..5 {
                    tp: [4]Vector3;
                    td: [4]float;
                    tg: [4]Vector3;
                    for v: 0..3 {
                        ci := tetra_indices[t * 4 + v];
                        tp[v] = cp[ci];
                        td[v] = cd[ci];
                        tg[v] = cg[ci];
                    }
                    mesh_tetra(*chunk.mesh, tp, td, tg);
                }
            }
        }
    }

    chunk.mesh.vertex_count = chunk.mesh.positions.count;
    chunk.mesh.dirty = false;
}

#import "Basic";
#import "Math";
