
line :: (a: Vector3, b: Vector3, color: u32 = 0, thickness: float = 0) {
    draw_line(g_ctx, a, b, color, thickness);
}

line :: (a: Vector3, b: Vector3, color: Vector4, thickness: float = 0) {
    draw_line(g_ctx, a, b, pack_color_rgba8(color), thickness);
}

triangle :: inline (a: Vector3, b: Vector3, c: Vector3, color: u32 = 0, filled := false) {
    draw_triangle(g_ctx, a, b, c, color, filled=filled);
}

triangle :: inline (a: Vector3, b: Vector3, c: Vector3, color: Vector4, filled := false) {
    draw_triangle(g_ctx, a, b, c, pack_color_rgba8(color), filled=false);
}

Gizmo_Line :: struct {
    a: Vector3;
    b: Vector3;
    color: u32;
    thickness: float;
}

Gizmo_Unit_Circle_Cache_Entry :: struct {
    segments: s64;
    points: [..]Vector2; // points[0] == points[segments], so ring emission can iterate linearly
}

pack_color_rgba8 :: inline (color: Vector4) -> u32 {
    r := cast(u32) floor(saturate(color.x) * 255.0 + 0.5);
    g := cast(u32) floor(saturate(color.y) * 255.0 + 0.5);
    b := cast(u32) floor(saturate(color.z) * 255.0 + 0.5);
    a := cast(u32) floor(saturate(color.w) * 255.0 + 0.5);
    return (r << 0) | (g << 8) | (b << 16) | (a << 24);
}

unpack_color_rgba8 :: inline (color: u32) -> Vector4 {
    return .{
        cast(float)((color >> 0) & 0xff) / 255.0,
        cast(float)((color >> 8) & 0xff) / 255.0,
        cast(float)((color >> 16) & 0xff) / 255.0,
        cast(float)((color >> 24) & 0xff) / 255.0,
    };
}

Gizmo_Context :: struct {
    line_count: s64;
    max_lines: s64;
    line_a_sink: []Vector3;
    line_b_sink: []Vector3;
    line_color_sink: []u32;
    line_thickness_sink: []u16;
    triangle_count: s64;
    max_triangles: s64;
    triangle_a_sink: []Vector3;
    triangle_b_sink: []Vector3;
    triangle_c_sink: []Vector3;
    triangle_color_sink: []Vector4;
    default_color: u32;
    default_thickness: float;
    point_size: float;
    arrow_head_size: float;
    unit_circle_cache: [..]Gizmo_Unit_Circle_Cache_Entry;
}

init :: (ctx: *Gizmo_Context) {
    ctx.* = .{};
    ctx.default_color = 0xffffffff;
    ctx.default_thickness = 2.0;
    ctx.point_size = 8.0;
    ctx.arrow_head_size = 0.06;
    ctx.unit_circle_cache.allocator = context.allocator;

    g_ctx = ctx;
}

deinit :: (ctx: *Gizmo_Context) {
    for *ctx.unit_circle_cache {
        array_free(it.points);
    }
    array_free(ctx.unit_circle_cache);
    ctx.* = .{};
}

begin_frame :: (ctx: *Gizmo_Context) {
    ensure_line_sink_bound(ctx);
    ensure_triangle_sink_bound(ctx);
    ctx.line_count = 0;
    ctx.triangle_count = 0;
}

line_count :: (ctx: *Gizmo_Context) -> s64 {
    return ctx.line_count;
}

triangle_count :: (ctx: *Gizmo_Context) -> s64 {
    return ctx.triangle_count;
}

get_cached_unit_circle_points :: (ctx: *Gizmo_Context, segments: s64) -> []Vector2 {
    for *ctx.unit_circle_cache {
        if it.segments == segments {
            return it.points;
        }
    }

    entry := Gizmo_Unit_Circle_Cache_Entry.{segments = segments};
    entry.points.allocator = context.allocator;
    array_reserve(*entry.points, segments + 1);
    for i: 0..segments {
        t := cast(float) i / cast(float) segments;
        a := t * TAU;
        array_add(*entry.points, .{cos(a), sin(a)});
    }
    array_add(*ctx.unit_circle_cache, entry);
    return ctx.unit_circle_cache[ctx.unit_circle_cache.count - 1].points;
}

set_external_line_sink :: (
    ctx: *Gizmo_Context,
    line_a: []Vector3,
    line_b: []Vector3,
    line_color: []u32,
    line_thickness: []u16,
) {
    count := line_a.count;
    if line_b.count < count count = line_b.count;
    if line_color.count < count count = line_color.count;
    if line_thickness.count < count count = line_thickness.count;

    if count <= 0 {
        clear_external_line_sink(ctx);
        return;
    }

    ctx.max_lines = count;
    ctx.line_count = 0;
    ctx.line_a_sink = line_a;
    ctx.line_b_sink = line_b;
    ctx.line_color_sink = line_color;
    ctx.line_thickness_sink = line_thickness;
}

clear_external_line_sink :: (using ctx: *Gizmo_Context) {
    max_lines = 0;
    line_count = 0;
    line_a_sink = .{};
    line_b_sink = .{};
    line_color_sink = .{};
    line_thickness_sink = .{};
}

set_external_triangle_sink :: (
    using ctx: *Gizmo_Context,
    triangle_a: []Vector3,
    triangle_b: []Vector3,
    triangle_c: []Vector3,
    triangle_color: []Vector4,
) {
    count := triangle_a.count;
    if triangle_b.count < count count = triangle_b.count;
    if triangle_c.count < count count = triangle_c.count;
    if triangle_color.count < count count = triangle_color.count;

    if count <= 0 {
        clear_external_triangle_sink(ctx);
        return;
    }

    max_triangles = count;
    triangle_count = 0;
    triangle_a_sink = triangle_a;
    triangle_b_sink = triangle_b;
    triangle_c_sink = triangle_c;
    triangle_color_sink = triangle_color;
}

clear_external_triangle_sink :: (using ctx: *Gizmo_Context) {
    max_triangles = 0;
    triangle_count = 0;
    triangle_a_sink = .{};
    triangle_b_sink = .{};
    triangle_c_sink = .{};
    triangle_color_sink = .{};
}


draw_line :: inline (ctx: *Gizmo_Context, a: Vector3, b: Vector3, color: u32 = 0, thickness: float = 0.0) #no_abc {
    line_color := color;
    if line_color == 0 line_color = ctx.default_color;

    line_thickness := thickness;
    if line_thickness <= 0.0 {
        line_thickness = ctx.default_thickness;
    }

    ensure_line_sink_bound(ctx);

    if ctx.line_count >= ctx.max_lines {
        return;
    }
    i := ctx.line_count;
    ctx.line_a_sink[i] = a;
    ctx.line_b_sink[i] = b;
    ctx.line_color_sink[i] = line_color;
    ctx.line_thickness_sink[i] = float32_to_float16(line_thickness);
    ctx.line_count += 1;
}

draw_line :: inline (ctx: *Gizmo_Context, a: Vector3, b: Vector3, color: Vector4, thickness: float = 0.0) {
    draw_line(ctx, a, b, pack_color_rgba8(color), thickness);
}

is_line_sink_bound :: (ctx: *Gizmo_Context) -> bool {
    return ctx.max_lines > 0
        && ctx.line_a_sink.count >= ctx.max_lines
        && ctx.line_b_sink.count >= ctx.max_lines
        && ctx.line_color_sink.count >= ctx.max_lines
        && ctx.line_thickness_sink.count >= ctx.max_lines;
}

assert_line_sink_bound :: (ctx: *Gizmo_Context) {
    assert(is_line_sink_bound(ctx), "Gizmo requires a bound external line sink. Call Gizmo_Render.bind_gizmo.");
}

ensure_line_sink_bound :: (ctx: *Gizmo_Context) {
    if !is_line_sink_bound(ctx) {
        assert_line_sink_bound(ctx);
    }
}

is_triangle_sink_bound :: (ctx: *Gizmo_Context) -> bool {
    return ctx.max_triangles > 0
        && ctx.triangle_a_sink.count >= ctx.max_triangles
        && ctx.triangle_b_sink.count >= ctx.max_triangles
        && ctx.triangle_c_sink.count >= ctx.max_triangles
        && ctx.triangle_color_sink.count >= ctx.max_triangles;
}

assert_triangle_sink_bound :: (ctx: *Gizmo_Context) {
    assert(is_triangle_sink_bound(ctx), "Gizmo requires a bound external triangle sink. Call Gizmo_Render.bind_gizmo.");
}

ensure_triangle_sink_bound :: (ctx: *Gizmo_Context) {
    if !is_triangle_sink_bound(ctx) {
        assert_triangle_sink_bound(ctx);
    }
}

draw_lines :: (ctx: *Gizmo_Context, lines: []Gizmo_Line) {
    for lines {
        draw_line(ctx, it.a, it.b, it.color, it.thickness);
    }
}

draw_triangle :: (
    ctx: *Gizmo_Context,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    color: u32 = 0,
    filled: bool = true,
    thickness: float = 0.0,
) #no_abc {
    assert(ctx != null);
    tri_color := color;
    if tri_color == 0 tri_color = ctx.default_color;

    if !filled {
        draw_line(ctx, a, b, tri_color, thickness);
        draw_line(ctx, b, c, tri_color, thickness);
        draw_line(ctx, c, a, tri_color, thickness);
        return;
    }

    ensure_triangle_sink_bound(ctx);
    if ctx.triangle_count >= ctx.max_triangles {
        log_error("max_triangles hit: %", ctx.max_triangles);
        return;
    }

    i := ctx.triangle_count;
    ctx.triangle_a_sink[i] = a;
    ctx.triangle_b_sink[i] = b;
    ctx.triangle_c_sink[i] = c;
    ctx.triangle_color_sink[i] = unpack_color_rgba8(tri_color);
    ctx.triangle_count += 1;
}

draw_triangle :: (
    ctx: *Gizmo_Context,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    color: Vector4,
    filled: bool = true,
    thickness: float = 0.0,
) {
    inline draw_triangle(ctx, a, b, c, pack_color_rgba8(color), filled, thickness);
}

draw_point :: (ctx: *Gizmo_Context, center: Vector3, color: u32 = 0, size: float = 0.0, thickness: float = 0.0) {
    point_size := size;
    if point_size <= 0.0 point_size = ctx.point_size;
    half := point_size * 0.5;
    draw_line(ctx, .{center.x - half, center.y, center.z}, .{center.x + half, center.y, center.z}, color, thickness);
    draw_line(ctx, .{center.x, center.y - half, center.z}, .{center.x, center.y + half, center.z}, color, thickness);
    draw_line(ctx, .{center.x, center.y, center.z - half}, .{center.x, center.y, center.z + half}, color, thickness);
}

draw_point :: (ctx: *Gizmo_Context, center: Vector3, color: Vector4, size: float = 0.0, thickness: float = 0.0) {
    draw_point(ctx, center, pack_color_rgba8(color), size, thickness);
}

draw_handle :: (ctx: *Gizmo_Context, center: Vector3, size: float = 0.08, color: u32 = 0, thickness: float = 0.0) {
    half := Vector3.{size * 0.5, size * 0.5, size * 0.5};
    draw_box(ctx, center, half, color, thickness);
    draw_point(ctx, center, color, size * 0.45, thickness);
}

draw_handle :: (ctx: *Gizmo_Context, center: Vector3, size: float = 0.08, color: Vector4, thickness: float = 0.0) {
    draw_handle(ctx, center, size, pack_color_rgba8(color), thickness);
}

draw_arrow :: (ctx: *Gizmo_Context, from: Vector3, to: Vector3, color: u32 = 0, thickness: float = 0.0, head_size: float = 0.0) {
    draw_line(ctx, from, to, color, thickness);

    dir := Vector3.{to.x - from.x, to.y - from.y, to.z - from.z};
    len2 := dir.x * dir.x + dir.y * dir.y + dir.z * dir.z;
    if len2 <= 0.000001 return;

    inv_len := 1.0 / sqrt(len2);
    dir = .{dir.x * inv_len, dir.y * inv_len, dir.z * inv_len};

    head_len := head_size;
    if head_len <= 0.0 head_len = ctx.arrow_head_size;
    head_w := head_len * 0.65;
    back := Vector3.{to.x - dir.x * head_len, to.y - dir.y * head_len, to.z - dir.z * head_len};

    ref_up := Vector3.{0.0, 1.0, 0.0};
    if abs(dot(ref_up, dir)) > 0.98 ref_up = .{1.0, 0.0, 0.0};
    right_dir := cross_product(ref_up, dir);
    normalize(*right_dir, fallback = .{1.0, 0.0, 0.0});
    up_dir := cross_product(dir, right_dir);
    normalize(*up_dir, fallback = .{0.0, 1.0, 0.0});

    left := Vector3.{back.x + right_dir.x * head_w + up_dir.x * head_w * 0.25, back.y + right_dir.y * head_w + up_dir.y * head_w * 0.25, back.z + right_dir.z * head_w + up_dir.z * head_w * 0.25};
    right := Vector3.{back.x - right_dir.x * head_w + up_dir.x * head_w * 0.25, back.y - right_dir.y * head_w + up_dir.y * head_w * 0.25, back.z - right_dir.z * head_w + up_dir.z * head_w * 0.25};

    draw_line(ctx, to, left, color, thickness);
    draw_line(ctx, to, right, color, thickness);
}

draw_arrow :: (ctx: *Gizmo_Context, from: Vector3, to: Vector3, color: Vector4, thickness: float = 0.0, head_size: float = 0.0) {
    draw_arrow(ctx, from, to, pack_color_rgba8(color), thickness, head_size);
}

draw_grid_xz :: (
    ctx: *Gizmo_Context,
    center: Vector3 = .{0.0, 0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: u32 = 0xff423d3d,
    major_color: u32 = 0xff6b6161,
    x_axis_color: u32 = 0xff5757f2,
    y_axis_color: u32 = 0xff57d957,
    line_thickness: float = 1.0,
) {
    if spacing <= 0.0 return;
    if half_extent <= 0.0 return;

    half_lines := cast(s64) floor(half_extent / spacing);
    for i: -half_lines..half_lines {
        offset := cast(float) i * spacing;
        x := center.x + offset;
        z := center.z + offset;

        vertical_color := minor_color;
        horizontal_color := minor_color;

        if i == 0 {
            vertical_color = y_axis_color;
            horizontal_color = x_axis_color;
        } else if major_every > 0 && i % major_every == 0 {
            vertical_color = major_color;
            horizontal_color = major_color;
        }

        draw_line(ctx,
            .{x, center.y, center.z - half_extent},
            .{x, center.y, center.z + half_extent},
            vertical_color,
            line_thickness);

        draw_line(ctx,
            .{center.x - half_extent, center.y, z},
            .{center.x + half_extent, center.y, z},
            horizontal_color,
            line_thickness);
    }
}

draw_grid_xz :: (
    ctx: *Gizmo_Context,
    center: Vector3 = .{0.0, 0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: Vector4,
    major_color: Vector4,
    x_axis_color: Vector4,
    y_axis_color: Vector4,
    line_thickness: float = 1.0,
) {
    draw_grid_xz(ctx, center, half_extent, spacing, major_every,
        pack_color_rgba8(minor_color), pack_color_rgba8(major_color),
        pack_color_rgba8(x_axis_color), pack_color_rgba8(y_axis_color),
        line_thickness);
}

draw_box :: (ctx: *Gizmo_Context, center: Vector3, half_extents: Vector3, color: u32 = 0, thickness: float = 0.0) {
    c := center;
    h := half_extents;
    corners := Vector3.[
        .{c.x - h.x, c.y - h.y, c.z - h.z},
        .{c.x + h.x, c.y - h.y, c.z - h.z},
        .{c.x + h.x, c.y + h.y, c.z - h.z},
        .{c.x - h.x, c.y + h.y, c.z - h.z},
        .{c.x - h.x, c.y - h.y, c.z + h.z},
        .{c.x + h.x, c.y - h.y, c.z + h.z},
        .{c.x + h.x, c.y + h.y, c.z + h.z},
        .{c.x - h.x, c.y + h.y, c.z + h.z},
    ];

    edge :: (i0: s64, i1: s64) #expand {
        draw_line(ctx, corners[i0], corners[i1], color, thickness);
    }
    edge(0, 1); edge(1, 2); edge(2, 3); edge(3, 0);
    edge(4, 5); edge(5, 6); edge(6, 7); edge(7, 4);
    edge(0, 4); edge(1, 5); edge(2, 6); edge(3, 7);
}

draw_box :: (ctx: *Gizmo_Context, center: Vector3, half_extents: Vector3, color: Vector4, thickness: float = 0.0) {
    draw_box(ctx, center, half_extents, pack_color_rgba8(color), thickness);
}

draw_sphere :: (
    ctx: *Gizmo_Context,
    center: Vector3,
    radius: float,
    color: u32 = 0,
    thickness: float = 0.0,
    segments: s64 = 24,
    rotation: Quaternion = .{w = 1.0},
) {
    if radius <= 0.0 return;
    if segments < 6 segments = 6;
    q := rotation;
    normalize_or_identity(*q);
    unit_circle := get_cached_unit_circle_points(ctx, segments);

    emit_circle :: (ctx: *Gizmo_Context, center: Vector3, radius: float, axis_u: Vector3, axis_v: Vector3, color: u32, thickness: float, unit_circle: []Vector2, segments: s64) {
        prev_uv := unit_circle[0];
        prev := Vector3.{
            center.x + (axis_u.x * prev_uv.x + axis_v.x * prev_uv.y) * radius,
            center.y + (axis_u.y * prev_uv.x + axis_v.y * prev_uv.y) * radius,
            center.z + (axis_u.z * prev_uv.x + axis_v.z * prev_uv.y) * radius,
        };
        for i: 1..segments {
            uv := unit_circle[i];
            curr := Vector3.{
                center.x + (axis_u.x * uv.x + axis_v.x * uv.y) * radius,
                center.y + (axis_u.y * uv.x + axis_v.y * uv.y) * radius,
                center.z + (axis_u.z * uv.x + axis_v.z * uv.y) * radius,
            };
            draw_line(ctx, prev, curr, color, thickness);
            prev = curr;
        }
    }

    axis_x := rotate(Vector3.{1.0, 0.0, 0.0}, q);
    axis_y := rotate(Vector3.{0.0, 1.0, 0.0}, q);
    axis_z := rotate(Vector3.{0.0, 0.0, 1.0}, q);

    emit_circle(ctx, center, radius, axis_x, axis_y, color, thickness, unit_circle, segments); // XY
    emit_circle(ctx, center, radius, axis_x, axis_z, color, thickness, unit_circle, segments); // XZ
    emit_circle(ctx, center, radius, axis_y, axis_z, color, thickness, unit_circle, segments); // YZ
}

draw_sphere :: (
    ctx: *Gizmo_Context,
    center: Vector3,
    radius: float,
    color: Vector4,
    thickness: float = 0.0,
    segments: s64 = 24,
    rotation: Quaternion = .{w = 1.0},
) {
    draw_sphere(ctx, center, radius, pack_color_rgba8(color), thickness, segments, rotation);
}

// Backward-compatible 2D helper: emits on the XY plane at z=0.
draw_grid_2d :: (
    ctx: *Gizmo_Context,
    center: Vector2 = .{0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: u32 = 0xff423d3d,
    major_color: u32 = 0xff6b6161,
    x_axis_color: u32 = 0xff5757f2,
    y_axis_color: u32 = 0xff57d957,
    line_thickness: float = 1.0,
) {
    if spacing <= 0.0 return;
    if half_extent <= 0.0 return;

    half_lines := cast(s64) floor(half_extent / spacing);
    for i: -half_lines..half_lines {
        offset := cast(float) i * spacing;
        x := center.x + offset;
        y := center.y + offset;

        vertical_color := minor_color;
        horizontal_color := minor_color;

        if i == 0 {
            vertical_color = y_axis_color;
            horizontal_color = x_axis_color;
        } else if major_every > 0 && i % major_every == 0 {
            vertical_color = major_color;
            horizontal_color = major_color;
        }

        draw_line(ctx, .{x, center.y - half_extent, 0.0}, .{x, center.y + half_extent, 0.0}, vertical_color, line_thickness);
        draw_line(ctx, .{center.x - half_extent, y, 0.0}, .{center.x + half_extent, y, 0.0}, horizontal_color, line_thickness);
    }
}

draw_grid_2d :: (
    ctx: *Gizmo_Context,
    center: Vector2 = .{0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: Vector4,
    major_color: Vector4,
    x_axis_color: Vector4,
    y_axis_color: Vector4,
    line_thickness: float = 1.0,
) {
    draw_grid_2d(ctx, center, half_extent, spacing, major_every,
        pack_color_rgba8(minor_color), pack_color_rgba8(major_color),
        pack_color_rgba8(x_axis_color), pack_color_rgba8(y_axis_color),
        line_thickness);
}

#scope_file

#import "Basic";
#import "Float16";
#import "Math";
g_ctx: *Gizmo_Context;
