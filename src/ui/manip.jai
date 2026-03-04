#scope_export

Manip_Mode :: enum {
    TRANSLATE;
    ROTATE;
    SCALE;
}

Manip_Space :: enum {
    WORLD;
    LOCAL;
}

Manip_Object :: struct {
    name: string;
    position: Vector3;
    rotation: Quaternion = .{w = 1.0};
    scale: Vector3 = .{1.0, 1.0, 1.0};
    half_extents: Vector3 = .{0.2, 0.2, 0.2};
    color: Vector4 = .{0.7, 0.7, 0.7, 1.0};
}

Manip_Context :: struct {
    selected_index: s32 = -1;
    hovered_index: s32 = -1;
    mode: Manip_Mode = .TRANSLATE;
    space: Manip_Space = .WORLD;

    hovered_axis: s32 = -1;
    active_axis: s32 = -1;
    active := false;

    drag_start_mouse: Vector2;
    drag_start_position: Vector3;
    drag_start_rotation: Quaternion;
    drag_start_scale: Vector3;
    drag_axis_world: Vector3;
    drag_axis_screen: Vector2;
}

Manip_Frame_Input :: struct {
    viewport: Vector2;
    camera_pos: Vector3;
    camera_forward: Vector3;
    camera_right: Vector3;
    camera_up: Vector3;
    fov_y: float = PI / 3.0;
    mouse_pos: Vector2;
    mouse_valid: bool;
    mouse_down: bool;
    mouse_pressed: bool;
    mouse_released: bool;
    block_mouse: bool;
}

Manip_Result :: struct {
    changed: bool;
    captured_mouse: bool;
}

quat_from_euler_xyz :: (euler: Vector3) -> Quaternion {
    hx := euler.x * 0.5;
    hy := euler.y * 0.5;
    hz := euler.z * 0.5;

    cx := cos(hx); sx := sin(hx);
    cy := cos(hy); sy := sin(hy);
    cz := cos(hz); sz := sin(hz);

    // Intrinsic XYZ (local axes): q = qz * qy * qx
    qx := Quaternion.{x = sx, y = 0.0, z = 0.0, w = cx};
    qy := Quaternion.{x = 0.0, y = sy, z = 0.0, w = cy};
    qz := Quaternion.{x = 0.0, y = 0.0, z = sz, w = cz};
    q := qz * qy * qx;
    normalize_or_identity(*q);
    return q;
}

quat_to_euler_xyz :: (q: Quaternion) -> Vector3 {
    n := q;
    normalize_or_identity(*n);

    sinr_cosp := 2.0 * (n.w * n.x + n.y * n.z);
    cosr_cosp := 1.0 - 2.0 * (n.x * n.x + n.y * n.y);
    x := atan2(sinr_cosp, cosr_cosp);

    sinp := 2.0 * (n.w * n.y - n.z * n.x);
    y := asin(clamp(sinp, -1.0, 1.0));

    siny_cosp := 2.0 * (n.w * n.z + n.x * n.y);
    cosy_cosp := 1.0 - 2.0 * (n.y * n.y + n.z * n.z);
    z := atan2(siny_cosp, cosy_cosp);

    return .{x, y, z};
}

manip_update :: (ctx: *Manip_Context, gizmo_ctx: *Gizmo.Gizmo_Context, objects: []Manip_Object, frame: Manip_Frame_Input) -> Manip_Result {
    result: Manip_Result;
    if !ctx || !gizmo_ctx return result;
    if objects.count <= 0 {
        ctx.selected_index = -1;
        ctx.hovered_index = -1;
        ctx.hovered_axis = -1;
        ctx.active_axis = -1;
        ctx.active = false;
        return result;
    }

    for *objects {
        draw_obb(gizmo_ctx, it.position, hadamard(it.half_extents, it.scale), it.rotation, it.color, 2.0);
    }

    if frame.block_mouse || !frame.mouse_valid || frame.viewport.x <= 1.0 || frame.viewport.y <= 1.0 {
        draw_handles(ctx, gizmo_ctx, objects, frame);
        return result;
    }

    ray_origin, ray_dir, ray_ok := mouse_world_ray(frame);
    if !ray_ok {
        draw_handles(ctx, gizmo_ctx, objects, frame);
        return result;
    }

    hovered := pick_object(objects, ray_origin, ray_dir);
    ctx.hovered_index = hovered;
    if hovered >= 0 result.captured_mouse = true;

    if frame.mouse_pressed && !ctx.active {
        if ctx.selected_index >= 0 {
            selected := cast(s64) ctx.selected_index;
            axis := pick_axis(ctx, objects[selected], frame);
            if axis >= 0 {
                begin_axis_drag(ctx, objects[selected], axis, frame);
                result.captured_mouse = true;
            } else {
                ctx.selected_index = hovered;
            }
        } else {
            ctx.selected_index = hovered;
        }
    }

    if ctx.active && ctx.selected_index >= 0 {
        selected := cast(s64) ctx.selected_index;
        apply_drag(ctx, *objects[selected], frame, *result);
        result.captured_mouse = true;
    }

    if frame.mouse_released {
        ctx.active = false;
        ctx.active_axis = -1;
    }

    draw_handles(ctx, gizmo_ctx, objects, frame);
    return result;
}

#scope_file

draw_handles :: (ctx: *Manip_Context, gizmo_ctx: *Gizmo.Gizmo_Context, objects: []Manip_Object, frame: Manip_Frame_Input) {
    if ctx.selected_index < 0 || cast(s64) ctx.selected_index >= objects.count return;

    obj := objects[cast(s64) ctx.selected_index];
    half := hadamard(obj.half_extents, obj.scale);
    draw_obb(gizmo_ctx, obj.position, half * 1.08, obj.rotation, .{1.0, 0.95, 0.55, 1.0}, 3.0);

    axis_len := manip_axis_length(obj.position, frame.camera_pos);
    center := obj.position;

    axis_colors := Vector4.[
        .{0.95, 0.32, 0.32, 1.0},
        .{0.32, 0.92, 0.40, 1.0},
        .{0.35, 0.58, 0.98, 1.0},
    ];

    for axis_i: 0..2 {
        axis_i32 := cast(s32) axis_i;
        dir := object_axis_dir(ctx, obj, axis_i32);
        tip := center + dir * axis_len;
        color := axis_colors[axis_i];
        if ctx.hovered_axis == axis_i32 || ctx.active_axis == axis_i32 {
            color = color * .{1.25, 1.25, 1.25, 1.0};
        }

        if ctx.mode == .ROTATE {
            draw_axis_ring(gizmo_ctx, center, dir, axis_len * 0.82, color, 1.8, 40);
        } else {
            Gizmo.draw_arrow(gizmo_ctx, center, tip, color, 2.8, axis_len * 0.16);
            if ctx.mode == .SCALE {
                draw_obb(gizmo_ctx, tip, .{axis_len * 0.08, axis_len * 0.08, axis_len * 0.08}, .{w = 1.0}, color, 2.0);
            } else {
                Gizmo.draw_handle(gizmo_ctx, tip, axis_len * 0.09, color, 2.0);
            }
        }
    }
}

pick_axis :: (ctx: *Manip_Context, obj: Manip_Object, frame: Manip_Frame_Input) -> s32 {
    ctx.hovered_axis = -1;
    axis_len := manip_axis_length(obj.position, frame.camera_pos);
    center := obj.position;
    center_screen, center_ok := world_to_screen(center, frame);
    if !center_ok return -1;

    best_dist: float = 1000000.0;
    best_axis: s32 = -1;
    for axis_i: 0..2 {
        axis_i32 := cast(s32) axis_i;
        axis_world := object_axis_dir(ctx, obj, axis_i32);
        tip := center + axis_world * axis_len;
        tip_screen, tip_ok := world_to_screen(tip, frame);
        if !tip_ok continue;

        dist := distance_point_segment(frame.mouse_pos, center_screen, tip_screen);
        if ctx.mode == .ROTATE {
            basis_u, _ := orthonormal_basis(axis_world);
            ring_ref := center + basis_u * axis_len * 0.82;
            ring_ref_screen, ref_ok := world_to_screen(ring_ref, frame);
            if ref_ok {
                radius := max(length(ring_ref_screen - center_screen), 10.0);
                ring_dist := abs(length(frame.mouse_pos - center_screen) - radius);
                if ring_dist < dist dist = ring_dist;
            }
        }
        if dist < 18.0 && dist < best_dist {
            best_dist = dist;
            best_axis = axis_i32;
        }
    }
    ctx.hovered_axis = best_axis;
    return best_axis;
}

begin_axis_drag :: (ctx: *Manip_Context, obj: Manip_Object, axis: s32, frame: Manip_Frame_Input) {
    ctx.active = true;
    ctx.active_axis = axis;
    ctx.drag_start_mouse = frame.mouse_pos;
    ctx.drag_start_position = obj.position;
    ctx.drag_start_rotation = obj.rotation;
    ctx.drag_start_scale = obj.scale;
    ctx.drag_axis_world = object_axis_dir(ctx, obj, axis);

    axis_len := manip_axis_length(obj.position, frame.camera_pos);
    center_screen, center_ok := world_to_screen(obj.position, frame);
    tip_screen, tip_ok := world_to_screen(obj.position + ctx.drag_axis_world * axis_len, frame);
    if center_ok && tip_ok {
        axis_screen := tip_screen - center_screen;
        len := length(axis_screen);
        if len > 0.001 {
            ctx.drag_axis_screen = axis_screen * (1.0 / len);
            if ctx.mode == .ROTATE {
                radial := frame.mouse_pos - center_screen;
                radial_len := length(radial);
                if radial_len > 0.001 {
                    r := radial * (1.0 / radial_len);
                    ctx.drag_axis_screen = .{-r.y, r.x};
                }
            }
        } else {
            ctx.drag_axis_screen = .{1.0, 0.0};
        }
    } else {
        ctx.drag_axis_screen = .{1.0, 0.0};
    }
}

apply_drag :: (ctx: *Manip_Context, obj: *Manip_Object, frame: Manip_Frame_Input, result: *Manip_Result) {
    mouse_delta := frame.mouse_pos - ctx.drag_start_mouse;
    pixel_delta := dot(mouse_delta, ctx.drag_axis_screen);
    world_per_pixel := max(0.0001, distance(frame.camera_pos, ctx.drag_start_position)) * tan(frame.fov_y * 0.5) * 2.0 / max(frame.viewport.y, 1.0);
    world_delta := pixel_delta * world_per_pixel;

    axis := ctx.active_axis;
    if axis < 0 || axis > 2 return;

    if ctx.mode == .TRANSLATE {
        obj.position = ctx.drag_start_position + ctx.drag_axis_world * world_delta;
        result.changed = true;
    } else if ctx.mode == .ROTATE {
        angle := world_delta * 1.6;
        start := ctx.drag_start_rotation;
        delta_local_axis := axis_dir(axis);
        delta_world_axis := ctx.drag_axis_world;
        dq := quat_from_axis_angle(delta_world_axis, angle);
        if ctx.space == .LOCAL {
            dq = quat_from_axis_angle(delta_local_axis, angle);
            obj.rotation = start * dq;
        } else {
            obj.rotation = dq * start;
        }
        normalize_or_identity(*obj.rotation);
        result.changed = true;
    } else if ctx.mode == .SCALE {
        s := ctx.drag_start_scale;
        next := max(0.05, get_axis_component(s, axis) + world_delta);
        set_axis_component(*s, axis, next);
        obj.scale = s;
        result.changed = true;
    }
}

pick_object :: (objects: []Manip_Object, ray_origin: Vector3, ray_dir: Vector3) -> s32 {
    best_t: float = 1000000.0;
    best: s32 = -1;
    for objects {
        half := hadamard(it.half_extents, it.scale);
        radius := max(0.05, length(half));
        hit, t := ray_intersects_sphere(ray_origin, ray_dir, it.position, radius);
        if hit && t > 0.0 && t < best_t {
            best_t = t;
            best = cast(s32) it_index;
        }
    }
    return best;
}

mouse_world_ray :: (frame: Manip_Frame_Input) -> (origin: Vector3, dir: Vector3, ok: bool) {
    nx := (frame.mouse_pos.x / frame.viewport.x) * 2.0 - 1.0;
    ny := (frame.mouse_pos.y / frame.viewport.y) * 2.0 - 1.0;
    aspect := frame.viewport.x / max(frame.viewport.y, 1.0);
    tan_half_fov := tan(frame.fov_y * 0.5);
    dir := frame.camera_forward + frame.camera_right * (nx * aspect * tan_half_fov) + frame.camera_up * (ny * tan_half_fov);
    normalize(*dir, fallback = frame.camera_forward);
    return frame.camera_pos, dir, true;
}

ray_intersects_sphere :: (origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> (hit: bool, t: float) {
    oc := origin - center;
    b := dot(oc, dir);
    c := dot(oc, oc) - radius * radius;
    h := b * b - c;
    if h < 0.0 return false, 0.0;
    h = sqrt(h);
    t0 := -b - h;
    t1 := -b + h;
    if t0 > 0.0 return true, t0;
    if t1 > 0.0 return true, t1;
    return false, 0.0;
}

world_to_screen :: (world: Vector3, frame: Manip_Frame_Input) -> (p: Vector2, ok: bool) {
    rel := world - frame.camera_pos;
    x := dot(rel, frame.camera_right);
    y := dot(rel, frame.camera_up);
    z := dot(rel, frame.camera_forward);
    if z <= 0.01 return .{}, false;

    tan_half_fov := tan(frame.fov_y * 0.5);
    aspect := frame.viewport.x / max(frame.viewport.y, 1.0);
    ndc_x := x / (z * tan_half_fov * aspect);
    ndc_y := y / (z * tan_half_fov);
    sx := (ndc_x * 0.5 + 0.5) * frame.viewport.x;
    sy := (ndc_y * 0.5 + 0.5) * frame.viewport.y;
    return .{sx, sy}, true;
}

manip_axis_length :: (object_pos: Vector3, camera_pos: Vector3) -> float {
    d := distance(object_pos, camera_pos);
    return clamp(d * 0.16, 0.25, 1.6);
}

object_axis_dir :: (ctx: *Manip_Context, obj: Manip_Object, axis: s32) -> Vector3 {
    base := axis_dir(axis);
    if ctx.space == .WORLD return base;
    result := rotate(base, obj.rotation);
    normalize(*result, fallback = base);
    return result;
}

axis_dir :: (axis: s32) -> Vector3 {
    if axis == 0 return .{1.0, 0.0, 0.0};
    if axis == 1 return .{0.0, 1.0, 0.0};
    return .{0.0, 0.0, 1.0};
}

orthonormal_basis :: (n: Vector3) -> (u: Vector3, v: Vector3) {
    up := Vector3.{0.0, 1.0, 0.0};
    if abs(dot(n, up)) > 0.95 up = .{1.0, 0.0, 0.0};
    u: Vector3;
    v: Vector3;
    u = cross(n, up);
    normalize(*u, fallback = .{1.0, 0.0, 0.0});
    v = cross(n, u);
    normalize(*v, fallback = .{0.0, 1.0, 0.0});
    return u, v;
}

draw_axis_ring :: (ctx: *Gizmo.Gizmo_Context, center: Vector3, normal: Vector3, radius: float, color: Vector4, thickness: float, segments: s64) {
    if radius <= 0.0 return;
    if segments < 8 segments = 8;
    n := normal;
    normalize(*n, fallback = .{0.0, 0.0, 1.0});
    u, v := orthonormal_basis(n);

    prev := center + u * radius;
    for i: 1..segments {
        t := cast(float) i / cast(float) segments;
        a := t * TAU;
        c := cos(a);
        s := sin(a);
        curr := center + (u * c + v * s) * radius;
        Gizmo.draw_line(ctx, prev, curr, color, thickness);
        prev = curr;
    }
}

draw_obb :: (ctx: *Gizmo.Gizmo_Context, center: Vector3, half_extents: Vector3, rotation: Quaternion, color: Vector4, thickness: float) {
    h := half_extents;

    corners_local := Vector3.[
        .{-h.x, -h.y, -h.z},
        .{ h.x, -h.y, -h.z},
        .{ h.x,  h.y, -h.z},
        .{-h.x,  h.y, -h.z},
        .{-h.x, -h.y,  h.z},
        .{ h.x, -h.y,  h.z},
        .{ h.x,  h.y,  h.z},
        .{-h.x,  h.y,  h.z},
    ];

    corners_world: [8]Vector3;
    for i: 0..7 {
        corners_world[i] = center + rotate(corners_local[i], rotation);
    }

    edge :: (i0: s64, i1: s64) #expand {
        Gizmo.draw_line(ctx, corners_world[i0], corners_world[i1], color, thickness);
    }

    edge(0, 1); edge(1, 2); edge(2, 3); edge(3, 0);
    edge(4, 5); edge(5, 6); edge(6, 7); edge(7, 4);
    edge(0, 4); edge(1, 5); edge(2, 6); edge(3, 7);
}

distance_point_segment :: (p: Vector2, a: Vector2, b: Vector2) -> float {
    ab := b - a;
    ap := p - a;
    denom := dot(ab, ab);
    if denom <= 0.000001 return length(p - a);
    t := clamp(dot(ap, ab) / denom, 0.0, 1.0);
    q := a + ab * t;
    return length(p - q);
}

hadamard :: (a: Vector3, b: Vector3) -> Vector3 {
    return .{a.x * b.x, a.y * b.y, a.z * b.z};
}

quat_from_axis_angle :: (axis: Vector3, angle: float) -> Quaternion {
    q := Quaternion.{};
    set_from_axis_and_angle(*q, axis, angle);
    normalize_or_identity(*q);
    return q;
}

get_axis_component :: (v: Vector3, axis: s32) -> float {
    if axis == 0 return v.x;
    if axis == 1 return v.y;
    return v.z;
}

set_axis_component :: (v: *Vector3, axis: s32, value: float) {
    if axis == 0 v.x = value;
    else if axis == 1 v.y = value;
    else v.z = value;
}

Gizmo :: #import "Gizmo";
#import "Math";
