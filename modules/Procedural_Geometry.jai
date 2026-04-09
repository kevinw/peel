#module_parameters(
    winding_order: enum { Clockwise; Counterclockwise; } = .Clockwise
);

Procedural_Geometry_Vertex :: struct {
    position: Vector4;
    normal: Vector4;
    tangent: Vector4;
    uv: Vector2;
    _pad_uv: Vector2;
    outline_normal: Vector4;
}

Procedural_Geometry_Mesh_Range :: struct {
    first_index: u32;
    index_count: u32;
}

procedural_append_uv_sphere :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, seg_x: s64, seg_y: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);
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
            tangent := normalize(Vector3.{-sin_phi, 0.0, cos_phi}, fallback = .{1.0, 0.0, 0.0});
            array_add(vertices, vert(normal * radius, normal, tangent, .{u, v}));
        }
    }

    stride := seg_x + 1;
    for y: 0..seg_y - 1 {
        for x: 0..seg_x - 1 {
            i0 := base_vertex + cast(u32) (y * stride + x);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            push_tri(indices, i0, i2, i1);
            push_tri(indices, i1, i2, i3);
        }
    }

    return finish_mesh(indices.*, first_index);
}

procedural_append_torus :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, major_radius: float, minor_radius: float, major_segments: s64, minor_segments: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);
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
            tangent := normalize(Vector3.{-sin_phi, 0.0, cos_phi}, fallback = .{1.0, 0.0, 0.0});
            array_add(vertices, vert(ring_center + outward * minor_radius, outward, tangent, .{u, v}));
        }
    }

    stride := minor_segments + 1;
    for major: 0..major_segments - 1 {
        for minor: 0..minor_segments - 1 {
            i0 := base_vertex + cast(u32) (major * stride + minor);
            i1 := i0 + 1;
            i2 := i0 + cast(u32) stride;
            i3 := i2 + 1;
            push_tri(indices, i0, i2, i1);
            push_tri(indices, i1, i2, i3);
        }
    }

    return finish_mesh(indices.*, first_index);
}

procedural_append_prism :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, half_height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);

    top_center := cast(u32) vertices.count;
    array_add(vertices, vert(.{0.0, half_height, 0.0}, .{0.0, 1.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.5, 0.5}, .{0.0, 1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        tangent := cap_tangent(radial, .{0.0, 1.0, 0.0});
        uv: Vector2 = .{cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5};
        array_add(vertices, vert(.{cos(angle) * radius, half_height, sin(angle) * radius}, .{0.0, 1.0, 0.0}, tangent, uv, radial));
    }

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, vert(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.5, 0.5}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        tangent := cap_tangent(radial, .{0.0, -1.0, 0.0});
        uv: Vector2 = .{cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5};
        array_add(vertices, vert(.{cos(angle) * radius, -half_height, sin(angle) * radius}, .{0.0, -1.0, 0.0}, tangent, uv, radial));
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        push_tri(indices, top_center, top_center + 1 + cast(u32) side, top_center + 1 + cast(u32) next);
        push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) next, bottom_center + 1 + cast(u32) side);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        u0 := cast(float) side / cast(float) sides;
        u1 := cast(float) (side + 1) / cast(float) sides;
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        p2 := Vector3.{cos(angle1) * radius, half_height, sin(angle1) * radius};
        p3 := Vector3.{cos(angle0) * radius, half_height, sin(angle0) * radius};
        edge := p1 - p0;
        up := p3 - p0;
        normal := cross_product(up, edge);
        normalize(*normal, fallback = .{0.0, 0.0, 1.0});
        o0 := normalize(Vector3.{p0.x, 0.0, p0.z});
        o1 := normalize(Vector3.{p1.x, 0.0, p1.z});
        o2 := normalize(Vector3.{p2.x, 0.0, p2.z});
        o3 := normalize(Vector3.{p3.x, 0.0, p3.z});
        tangent := normalize(edge, fallback = .{1.0, 0.0, 0.0});

        base := cast(u32) vertices.count;
        array_add(vertices,
            vert(p0, normal, tangent, .{u0, 1.0}, o0),
            vert(p1, normal, tangent, .{u1, 1.0}, o1),
            vert(p2, normal, tangent, .{u1, 0.0}, o2),
            vert(p3, normal, tangent, .{u0, 0.0}, o3));
        push_tri(indices, base + 0, base + 1, base + 2);
        push_tri(indices, base + 0, base + 2, base + 3);
    }

    return finish_mesh(indices.*, first_index);
}

procedural_append_cone :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);
    half_height := height * 0.5;
    apex := Vector3.{0.0, half_height, 0.0};

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, vert(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.5, 0.5}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        tangent := cap_tangent(radial, .{0.0, -1.0, 0.0});
        uv: Vector2 = .{cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5};
        array_add(vertices, vert(.{cos(angle) * radius, -half_height, sin(angle) * radius}, .{0.0, -1.0, 0.0}, tangent, uv, radial));
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) next, bottom_center + 1 + cast(u32) side);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        u0 := cast(float) side / cast(float) sides;
        u1 := cast(float) (side + 1) / cast(float) sides;
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        normal := cross_product(apex - p0, p1 - p0);
        normalize(*normal, fallback = .{0.0, 0.0, 1.0});
        o0 := normalize(Vector3.{p0.x, height * 0.35, p0.z});
        o1 := normalize(Vector3.{p1.x, height * 0.35, p1.z});
        o2 := normalize(Vector3.{0.0, 1.0, 0.0});
        tangent := normalize(p1 - p0, fallback = .{1.0, 0.0, 0.0});

        base := cast(u32) vertices.count;
        array_add(vertices,
            vert(p0, normal, tangent, .{u0, 1.0}, o0),
            vert(p1, normal, tangent, .{u1, 1.0}, o1),
            vert(apex, normal, tangent, .{(u0 + u1) * 0.5, 0.0}, o2));
        push_tri(indices, base + 0, base + 1, base + 2);
    }

    return finish_mesh(indices.*, first_index);
}

procedural_append_cylinder :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, radius: float, half_height: float, sides: s64) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);

    top_center := cast(u32) vertices.count;
    array_add(vertices, vert(.{0.0, half_height, 0.0}, .{0.0, 1.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.5, 0.5}, .{0.0, 1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        tangent := cap_tangent(radial, .{0.0, 1.0, 0.0});
        uv: Vector2 = .{cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5};
        array_add(vertices, vert(.{cos(angle) * radius, half_height, sin(angle) * radius}, .{0.0, 1.0, 0.0}, tangent, uv, radial));
    }

    bottom_center := cast(u32) vertices.count;
    array_add(vertices, vert(.{0.0, -half_height, 0.0}, .{0.0, -1.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.5, 0.5}, .{0.0, -1.0, 0.0}));
    for side: 0..sides - 1 {
        angle := cast(float) side / cast(float) sides * PI * 2.0;
        radial := normalize(Vector3.{cos(angle), 0.0, sin(angle)});
        tangent := cap_tangent(radial, .{0.0, -1.0, 0.0});
        uv: Vector2 = .{cos(angle) * 0.5 + 0.5, sin(angle) * 0.5 + 0.5};
        array_add(vertices, vert(.{cos(angle) * radius, -half_height, sin(angle) * radius}, .{0.0, -1.0, 0.0}, tangent, uv, radial));
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        push_tri(indices, top_center, top_center + 1 + cast(u32) side, top_center + 1 + cast(u32) next);
        push_tri(indices, bottom_center, bottom_center + 1 + cast(u32) next, bottom_center + 1 + cast(u32) side);
    }

    for side: 0..sides - 1 {
        next := (side + 1) % sides;
        angle0 := cast(float) side / cast(float) sides * PI * 2.0;
        angle1 := cast(float) next / cast(float) sides * PI * 2.0;
        u0 := cast(float) side / cast(float) sides;
        u1 := cast(float) (side + 1) / cast(float) sides;
        n0 := normalize(Vector3.{cos(angle0), 0.0, sin(angle0)});
        n1 := normalize(Vector3.{cos(angle1), 0.0, sin(angle1)});
        p0 := Vector3.{cos(angle0) * radius, -half_height, sin(angle0) * radius};
        p1 := Vector3.{cos(angle1) * radius, -half_height, sin(angle1) * radius};
        p2 := Vector3.{cos(angle1) * radius, half_height, sin(angle1) * radius};
        p3 := Vector3.{cos(angle0) * radius, half_height, sin(angle0) * radius};

        base := cast(u32) vertices.count;
        tangent := normalize(p1 - p0, fallback = .{1.0, 0.0, 0.0});
        array_add(vertices,
            vert(p0, n0, tangent, .{u0, 1.0}, n0),
            vert(p1, n1, tangent, .{u1, 1.0}, n1),
            vert(p2, n1, tangent, .{u1, 0.0}, n1),
            vert(p3, n0, tangent, .{u0, 0.0}, n0));
        push_tri(indices, base + 0, base + 1, base + 2);
        push_tri(indices, base + 0, base + 2, base + 3);
    }

    return finish_mesh(indices.*, first_index);
}

procedural_append_plane :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, half_extent: float) -> Procedural_Geometry_Mesh_Range {
    return procedural_append_plane(vertices, indices, half_extent, .{0.0, 1.0, 0.0}, .{1.0, 0.0, 0.0});
}

procedural_append_plane :: (vertices: *[..]Procedural_Geometry_Vertex, indices: *[..]u32, half_extent: float, normal_in: Vector3, tangent_hint: Vector3) -> Procedural_Geometry_Mesh_Range {
    first_index := begin_mesh(indices.*);
    base := cast(u32) vertices.count;
    tangent, bitangent, normal := orthonormal_basis(normal_in, tangent_hint);
    array_add(vertices,
        vert((-tangent - bitangent) * half_extent, normal, tangent, .{0.0, 1.0}, normal),
        vert(( tangent - bitangent) * half_extent, normal, tangent, .{1.0, 1.0}, normal),
        vert(( tangent + bitangent) * half_extent, normal, tangent, .{1.0, 0.0}, normal),
        vert((-tangent + bitangent) * half_extent, normal, tangent, .{0.0, 0.0}, normal));
    push_tri(indices, base + 0, base + 2, base + 1);
    push_tri(indices, base + 0, base + 3, base + 2);
    return finish_mesh(indices.*, first_index);
}

#scope_file

push_tri :: inline (indices: *[..]u32, a: u32, b: u32, c: u32) {
    #if winding_order == .Counterclockwise {
        array_add(indices, a, c, b);
    } else {
        array_add(indices, a, b, c);
    }
}

vert :: inline (position: Vector3, normal: Vector3) -> Procedural_Geometry_Vertex {
    return vert(position, normal, tangent_from_normal(normal), .{0.0, 0.0}, normal);
}

vert :: inline (position: Vector3, normal: Vector3, tangent: Vector3) -> Procedural_Geometry_Vertex {
    return vert(position, normal, tangent, .{0.0, 0.0}, normal);
}

vert :: inline (position: Vector3, normal: Vector3, tangent: Vector3, uv: Vector2) -> Procedural_Geometry_Vertex {
    return vert(position, normal, tangent, uv, normal);
}

vert :: inline (position: Vector3, normal: Vector3, tangent: Vector3, uv: Vector2, outline_normal: Vector3) -> Procedural_Geometry_Vertex {
    return .{
        position = .{position.x, position.y, position.z, 1.0},
        normal = .{normal.x, normal.y, normal.z, 0.0},
        tangent = .{tangent.x, tangent.y, tangent.z, 1.0},
        uv = uv,
        _pad_uv = .{0.0, 0.0},
        outline_normal = .{outline_normal.x, outline_normal.y, outline_normal.z, 0.0},
    };
}

tangent_from_normal :: inline (normal: Vector3) -> Vector3 {
    tangent, _, _ := orthonormal_basis(normal, .{1.0, 0.0, 0.0});
    return tangent;
}

cap_tangent :: inline (radial: Vector3, normal: Vector3) -> Vector3 {
    tangent := cross_product(normal, radial);
    normalize(*tangent, fallback = tangent_from_normal(normal));
    return tangent;
}

orthonormal_basis :: inline (normal_in: Vector3, tangent_hint: Vector3) -> (Vector3, Vector3, Vector3) {
    normal := normalize(normal_in, fallback = .{0.0, 1.0, 0.0});
    tangent := tangent_hint - normal * dot(tangent_hint, normal);
    if dot(tangent, tangent) < 0.0001 {
        tangent = tangent_from_fallback_axes(normal);
    } else {
        normalize(*tangent, fallback = tangent_from_fallback_axes(normal));
    }
    bitangent := cross_product(normal, tangent);
    normalize(*bitangent, fallback = .{0.0, 0.0, 1.0});
    tangent = normalize(cross_product(bitangent, normal), fallback = tangent);
    return tangent, bitangent, normal;
}

tangent_from_fallback_axes :: inline (normal: Vector3) -> Vector3 {
    tangent := cross_product(Vector3.{0.0, 1.0, 0.0}, normal);
    if dot(tangent, tangent) < 0.0001 {
        tangent = cross_product(Vector3.{1.0, 0.0, 0.0}, normal);
    }
    normalize(*tangent, fallback = .{1.0, 0.0, 0.0});
    return tangent;
}


begin_mesh :: (indices: []u32) -> u32 {
    return cast(u32) indices.count;
}

finish_mesh :: (indices: []u32, first_index: u32) -> Procedural_Geometry_Mesh_Range {
    return .{
        first_index = first_index,
        index_count = cast(u32) indices.count - first_index,
    };
}

#import "Basic";
#import "Math";
