Procedural_Geometry_Vertex :: struct {
    position: Vector4;
    normal: Vector4;
    outline_normal: Vector4;
}

Procedural_Geometry_Mesh_Range :: struct {
    first_index: u32;
    index_count: u32;
}

procedural_begin_mesh :: (indices: []u32) -> u32 {
    return cast(u32) indices.count;
}

procedural_finish_mesh :: (indices: []u32, first_index: u32) -> Procedural_Geometry_Mesh_Range {
    return .{
        first_index = first_index,
        index_count = cast(u32) indices.count - first_index,
    };
}

procedural_push_tri :: (indices: *[..]u32, a: u32, b: u32, c: u32) {
    array_add(indices, a, b, c);
}

pg_vertex :: (position: Vector3, normal: Vector3) -> Procedural_Geometry_Vertex {
    return pg_vertex(position, normal, normal);
}

pg_vertex :: (position: Vector3, normal: Vector3, outline_normal: Vector3) -> Procedural_Geometry_Vertex {
    return .{
        position = .{position.x, position.y, position.z, 1.0},
        normal = .{normal.x, normal.y, normal.z, 0.0},
        outline_normal = .{outline_normal.x, outline_normal.y, outline_normal.z, 0.0},
    };
}

procedural_append_uv_sphere :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, seg_x: s64, seg_y: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);
    base_vertex := cast(u32) vertices.count;

    for y: 0..seg_y {
        v := cast(float) y / cast(float) seg_y;
        theta := v * PI;
        sin_theta := sin(theta);
        cos_theta := cos(theta);

        for x: 0..seg_x {
            u := cast(float) x / cast(float) seg_x;
            phi := u * PI * 2.0;
            sin_phi := sin(phi);
            cos_phi := cos(phi);
            normal := Vector3.{
                cos_phi * sin_theta,
                cos_theta,
                sin_phi * sin_theta,
            };
            array_add(vertices, pg_vertex(normal * radius, normal));
        }
    }

    stride := seg_x + 1;
    for y: 0..seg_y - 1 {
        for x: 0..seg_x - 1 {
            i0 := base_vertex + cast(u32) (y * stride + x);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            procedural_push_tri(indices, i0, i2, i1);
            procedural_push_tri(indices, i1, i2, i3);
        }
    }

    return procedural_finish_mesh(indices.*, first_index);
}

procedural_append_torus :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, major_radius: float, minor_radius: float, major_segments: s64, minor_segments: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);
    base_vertex := cast(u32) vertices.count;

    for major: 0..major_segments {
        u := cast(float) major / cast(float) major_segments;
        phi := u * PI * 2.0;
        sin_phi := sin(phi);
        cos_phi := cos(phi);
        ring_center := Vector3.{cos_phi * major_radius, 0.0, sin_phi * major_radius};

        for minor: 0..minor_segments {
            v := cast(float) minor / cast(float) minor_segments;
            theta := v * PI * 2.0;
            sin_theta := sin(theta);
            cos_theta := cos(theta);
            outward := Vector3.{cos_phi * cos_theta, sin_theta, sin_phi * cos_theta};
            array_add(vertices, pg_vertex(ring_center + outward * minor_radius, outward));
        }
    }

    stride := minor_segments + 1;
    for major: 0..major_segments - 1 {
        for minor: 0..minor_segments - 1 {
            i0 := base_vertex + cast(u32) (major * stride + minor);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            procedural_push_tri(indices, i0, i2, i1);
            procedural_push_tri(indices, i1, i2, i3);
        }
    }

    return procedural_finish_mesh(indices.*, first_index);
}

procedural_append_prism :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, half_height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);

    top_center := cast(u32) vertices.count;
    array_add(vertices, pg_vertex(.{0.0, half_height, 0.0}, .{0.0, 1.0, 0.0}, .{0.0, 1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        array_add(vertices, .{
            position = .{cos(angle) * radius, half_height, sin(angle) * radius, 1.0},
            normal = .{0.0, 1.0, 0.0, 0.0},
            outline_normal = .{radial.x, radial.y, radial.z, 0.0},
        });
    }

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, pg_vertex(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        array_add(vertices, .{
            position = .{cos(angle) * radius, -half_height, sin(angle) * radius, 1.0},
            normal = .{0.0, -1.0, 0.0, 0.0},
            outline_normal = .{radial.x, radial.y, radial.z, 0.0},
        });
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        procedural_push_tri(indices, top_center, top_center + 1 + cast(u32) next, top_center + 1 + cast(u32) side);
        procedural_push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) side, bottom_center + 1 + cast(u32) next);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        p2 := Vector3.{cos(angle1) * radius, half_height, sin(angle1) * radius};
        p3 := Vector3.{cos(angle0) * radius, half_height, sin(angle0) * radius};
        edge := p1 - p0;
        up := p3 - p0;
        normal := cross_product(edge, up);
        normalize(*normal, fallback = .{0.0, 0.0, 1.0});
        o0 := normalize(Vector3.{p0.x, 0.0, p0.z});
        o1 := normalize(Vector3.{p1.x, 0.0, p1.z});
        o2 := normalize(Vector3.{p2.x, 0.0, p2.z});
        o3 := normalize(Vector3.{p3.x, 0.0, p3.z});

        base := cast(u32) vertices.count;
        array_add(vertices,
            pg_vertex(p0, normal, o0),
            pg_vertex(p1, normal, o1),
            pg_vertex(p2, normal, o2),
            pg_vertex(p3, normal, o3));
        procedural_push_tri(indices, base + 0, base + 1, base + 2);
        procedural_push_tri(indices, base + 0, base + 2, base + 3);
    }

    return procedural_finish_mesh(indices.*, first_index);
}

procedural_append_cone :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);
    half_height := height * 0.5;
    apex := Vector3.{0.0, half_height, 0.0};

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, pg_vertex(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        array_add(vertices, .{
            position = .{cos(angle) * radius, -half_height, sin(angle) * radius, 1.0},
            normal = .{0.0, -1.0, 0.0, 0.0},
            outline_normal = .{radial.x, radial.y, radial.z, 0.0},
        });
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        procedural_push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) side, bottom_center + 1 + cast(u32) next);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        normal := cross_product(p1 - p0, apex - p0);
        normalize(*normal, fallback = .{0.0, 0.0, 1.0});
        o0 := normalize(Vector3.{p0.x, height * 0.35, p0.z});
        o1 := normalize(Vector3.{p1.x, height * 0.35, p1.z});
        o2 := normalize(Vector3.{0.0, 1.0, 0.0});

        base := cast(u32) vertices.count;
        array_add(vertices,
            pg_vertex(p0, normal, o0),
            pg_vertex(p1, normal, o1),
            pg_vertex(apex, normal, o2));
        procedural_push_tri(indices, base + 0, base + 1, base + 2);
    }

    return procedural_finish_mesh(indices.*, first_index);
}

procedural_append_cylinder :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, half_height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);

    top_center := cast(u32) vertices.count;
    array_add(vertices, pg_vertex(.{0.0, half_height, 0.0}, .{0.0, 1.0, 0.0}, .{0.0, 1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        array_add(vertices, .{
            position = .{cos(angle) * radius, half_height, sin(angle) * radius, 1.0},
            normal = .{0.0, 1.0, 0.0, 0.0},
            outline_normal = .{radial.x, radial.y, radial.z, 0.0},
        });
    }

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, pg_vertex(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        array_add(vertices, .{
            position = .{cos(angle) * radius, -half_height, sin(angle) * radius, 1.0},
            normal = .{0.0, -1.0, 0.0, 0.0},
            outline_normal = .{radial.x, radial.y, radial.z, 0.0},
        });
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        procedural_push_tri(indices, top_center, top_center + 1 + cast(u32) next, top_center + 1 + cast(u32) side);
        procedural_push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) side, bottom_center + 1 + cast(u32) next);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        n0 := normalize(Vector3.{cos(angle0), 0.0, sin(angle0)});
        n1 := normalize(Vector3.{cos(angle1), 0.0, sin(angle1)});
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        p2 := Vector3.{cos(angle1) * radius, half_height, sin(angle1) * radius};
        p3 := Vector3.{cos(angle0) * radius, half_height, sin(angle0) * radius};

        base := cast(u32) vertices.count;
        array_add(vertices,
            pg_vertex(p0, n0, n0),
            pg_vertex(p1, n1, n1),
            pg_vertex(p2, n1, n1),
            pg_vertex(p3, n0, n0));
        procedural_push_tri(indices, base + 0, base + 1, base + 2);
        procedural_push_tri(indices, base + 0, base + 2, base + 3);
    }

    return procedural_finish_mesh(indices.*, first_index);
}

procedural_append_plane :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, half_extent: float) -> Procedural_Geometry_Mesh_Range {
    first_index := procedural_begin_mesh(indices.*);
    base := cast(u32) vertices.count;
    normal := Vector4.{0.0, 1.0, 0.0, 0.0};
    array_add(vertices,
        .{position = .{-half_extent, 0.0, -half_extent, 1.0}, normal = normal, outline_normal = normal},
        .{position = .{ half_extent, 0.0, -half_extent, 1.0}, normal = normal, outline_normal = normal},
        .{position = .{ half_extent, 0.0,  half_extent, 1.0}, normal = normal, outline_normal = normal},
        .{position = .{-half_extent, 0.0,  half_extent, 1.0}, normal = normal, outline_normal = normal});
    procedural_push_tri(indices, base + 0, base + 2, base + 1);
    procedural_push_tri(indices, base + 0, base + 3, base + 2);
    return procedural_finish_mesh(indices.*, first_index);
}

#scope_file

#import "Basic";
#import "Math";
