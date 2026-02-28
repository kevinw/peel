Gizmo_Line :: struct {
    a: Vector3;
    b: Vector3;
    color: Vector4;
    thickness: float;
}

Gizmo_Context :: struct {
    lines: [..] Gizmo_Line;
    default_color: Vector4;
    default_thickness: float;
    point_size: float;
    arrow_head_size: float;
}

init :: (ctx: *Gizmo_Context) {
    ctx.* = .{};
    ctx.default_color = .{1.0, 1.0, 1.0, 1.0};
    ctx.default_thickness = 2.0;
    ctx.point_size = 8.0;
    ctx.arrow_head_size = 0.06;
    ctx.lines.allocator = context.allocator;
}

deinit :: (ctx: *Gizmo_Context) {
    array_free(ctx.lines);
    ctx.* = .{};
}

begin_frame :: (ctx: *Gizmo_Context) {
    array_reset(*ctx.lines);
}

gizmo_lines :: (ctx: *Gizmo_Context) -> []Gizmo_Line {
    return ctx.lines;
}

draw_line :: inline (ctx: *Gizmo_Context, a: Vector3, b: Vector3, color: Vector4 = .{}, thickness: float = 0.0) {
    line_color := color;
    if line_color.w == 0.0 {
        line_color = ctx.default_color;
    }

    line_thickness := thickness;
    if line_thickness <= 0.0 {
        line_thickness = ctx.default_thickness;
    }

    array_add(*ctx.lines, .{
        a = a,
        b = b,
        color = line_color,
        thickness = line_thickness,
    });
}

draw_lines :: (ctx: *Gizmo_Context, lines: []Gizmo_Line) {
    for lines {
        draw_line(ctx, it.a, it.b, it.color, it.thickness);
    }
}

draw_point :: (ctx: *Gizmo_Context, center: Vector3, color: Vector4 = .{}, size: float = 0.0, thickness: float = 0.0) {
    point_size := size;
    if point_size <= 0.0 point_size = ctx.point_size;
    half := point_size * 0.5;
    draw_line(ctx, .{center.x - half, center.y, center.z}, .{center.x + half, center.y, center.z}, color, thickness);
    draw_line(ctx, .{center.x, center.y - half, center.z}, .{center.x, center.y + half, center.z}, color, thickness);
    draw_line(ctx, .{center.x, center.y, center.z - half}, .{center.x, center.y, center.z + half}, color, thickness);
}

draw_handle :: (ctx: *Gizmo_Context, center: Vector3, size: float = 0.08, color: Vector4 = .{}, thickness: float = 0.0) {
    half := Vector3.{size * 0.5, size * 0.5, size * 0.5};
    draw_box(ctx, center, half, color, thickness);
    draw_point(ctx, center, color, size * 0.45, thickness);
}

draw_arrow :: (ctx: *Gizmo_Context, from: Vector3, to: Vector3, color: Vector4 = .{}, thickness: float = 0.0, head_size: float = 0.0) {
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

draw_grid_xz :: (
    ctx: *Gizmo_Context,
    center: Vector3 = .{0.0, 0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: Vector4 = .{0.24, 0.24, 0.26, 1.0},
    major_color: Vector4 = .{0.38, 0.38, 0.42, 1.0},
    x_axis_color: Vector4 = .{0.95, 0.34, 0.34, 1.0},
    y_axis_color: Vector4 = .{0.34, 0.85, 0.34, 1.0},
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

draw_box :: (ctx: *Gizmo_Context, center: Vector3, half_extents: Vector3, color: Vector4 = .{}, thickness: float = 0.0) {
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

draw_sphere :: (ctx: *Gizmo_Context, center: Vector3, radius: float, color: Vector4 = .{}, thickness: float = 0.0, segments: s64 = 24) {
    if radius <= 0.0 return;
    if segments < 6 segments = 6;

    emit_circle :: (ctx: *Gizmo_Context, center: Vector3, radius: float, axis_u: Vector3, axis_v: Vector3, color: Vector4, thickness: float, segments: s64) {
        prev := Vector3.{center.x + axis_u.x * radius, center.y + axis_u.y * radius, center.z + axis_u.z * radius};
        for i: 1..segments {
            t := cast(float) i / cast(float) segments;
            a := t * TAU;
            c := cos(a);
            s := sin(a);
            curr := Vector3.{
                center.x + (axis_u.x * c + axis_v.x * s) * radius,
                center.y + (axis_u.y * c + axis_v.y * s) * radius,
                center.z + (axis_u.z * c + axis_v.z * s) * radius,
            };
            draw_line(ctx, prev, curr, color, thickness);
            prev = curr;
        }
    }

    emit_circle(ctx, center, radius, .{1.0, 0.0, 0.0}, .{0.0, 1.0, 0.0}, color, thickness, segments); // XY
    emit_circle(ctx, center, radius, .{1.0, 0.0, 0.0}, .{0.0, 0.0, 1.0}, color, thickness, segments); // XZ
    emit_circle(ctx, center, radius, .{0.0, 1.0, 0.0}, .{0.0, 0.0, 1.0}, color, thickness, segments); // YZ
}

// Backward-compatible 2D helper: emits on the XY plane at z=0.
draw_grid_2d :: (
    ctx: *Gizmo_Context,
    center: Vector2 = .{0.0, 0.0},
    half_extent: float = 1.0,
    spacing: float = 0.1,
    major_every: s64 = 5,
    minor_color: Vector4 = .{0.24, 0.24, 0.26, 1.0},
    major_color: Vector4 = .{0.38, 0.38, 0.42, 1.0},
    x_axis_color: Vector4 = .{0.95, 0.34, 0.34, 1.0},
    y_axis_color: Vector4 = .{0.34, 0.85, 0.34, 1.0},
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

#scope_file

#import "Basic";
#import "Math";
