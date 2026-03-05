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

Manip_Object_Shape :: enum {
    BOX;
    SPHERE;
}

Manip_Object :: struct {
    name: string;
    shape: Manip_Object_Shape = .BOX;
    position: Vector3;
    rotation: Quaternion = .{w = 1.0};
    scale: Vector3 = .{1.0, 1.0, 1.0};
    half_extents: Vector3 = .{0.2, 0.2, 0.2};
    color: Vector4 = .{0.7, 0.7, 0.7, 1.0};
}

Manip_Drag_Kind :: enum {
    NONE;
    AXIS;
    PLANE;
    ORBIT;
}

Manip_Context :: struct {
    selected_index: s32 = -1;
    hovered_index: s32 = -1;
    mode: Manip_Mode = .TRANSLATE;
    space: Manip_Space = .WORLD;

    hovered_axis: s32 = -1;
    hovered_plane: s32 = -1;
    hovered_orbit := false;

    active_axis: s32 = -1;
    active_plane: s32 = -1;
    active_kind: Manip_Drag_Kind = .NONE;
    active := false;

    drag_start_mouse: Vector2;
    drag_start_position: Vector3;
    drag_start_rotation: Quaternion;
    drag_start_scale: Vector3;

    drag_axis_world: Vector3;
    drag_axis_screen: Vector2;

    drag_plane_normal: Vector3;
    drag_plane_origin: Vector3;
    drag_plane_start_hit: Vector3;

    drag_orbit_center_screen: Vector2;
    drag_orbit_radius_px: float;
    drag_orbit_prev_vec: Vector3;
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

    reset_hover(ctx);

    if objects.count <= 0 {
        ctx.selected_index = -1;
        ctx.active = false;
        ctx.active_kind = .NONE;
        return result;
    }

    for objects {
        draw_object_wire(gizmo_ctx, it, 1.0, it.color, 2.0);
    }

    if frame.viewport.x <= 1.0 || frame.viewport.y <= 1.0 {
        draw_handles(ctx, gizmo_ctx, objects, frame);
        return result;
    }

    ray_origin, ray_dir, ray_ok := mouse_world_ray(frame);
    if !ray_ok {
        draw_handles(ctx, gizmo_ctx, objects, frame);
        return result;
    }

    hovered_object := pick_object(objects, ray_origin, ray_dir);
    ctx.hovered_index = hovered_object;

    if !frame.block_mouse {
        if frame.mouse_pressed && !ctx.active {
            if ctx.selected_index >= 0 {
                selected := cast(s64) ctx.selected_index;
                kind, axis, plane := pick_handle(ctx, objects[selected], frame);
                if kind != .NONE {
                    begin_drag(ctx, objects[selected], kind, axis, plane, frame, ray_origin, ray_dir);
                    result.captured_mouse = true;
                } else {
                    ctx.selected_index = hovered_object;
                }
            } else {
                ctx.selected_index = hovered_object;
            }
        }

        if ctx.active && ctx.selected_index >= 0 {
            selected := cast(s64) ctx.selected_index;
            apply_drag(ctx, *objects[selected], frame, ray_origin, ray_dir, *result);
            result.captured_mouse = true;
        }

        if frame.mouse_released {
            ctx.active = false;
            ctx.active_kind = .NONE;
            ctx.active_axis = -1;
            ctx.active_plane = -1;
        }

        if ctx.selected_index >= 0 && !ctx.active {
            selected := cast(s64) ctx.selected_index;
            kind, _, _ := pick_handle(ctx, objects[selected], frame);
            if kind != .NONE result.captured_mouse = true;
        }
    }

    if hovered_object >= 0 result.captured_mouse = true;
    draw_handles(ctx, gizmo_ctx, objects, frame);
    return result;
}

#scope_file

reset_hover :: (ctx: *Manip_Context) {
    ctx.hovered_axis = -1;
    ctx.hovered_plane = -1;
    ctx.hovered_orbit = false;
}

draw_handles :: (ctx: *Manip_Context, gizmo_ctx: *Gizmo.Gizmo_Context, objects: []Manip_Object, frame: Manip_Frame_Input) {
    if ctx.selected_index < 0 || cast(s64) ctx.selected_index >= objects.count return;

    obj := objects[cast(s64) ctx.selected_index];
    draw_object_wire(gizmo_ctx, obj, 1.08, .{1.0, 0.95, 0.55, 1.0}, 3.0);

    axis_len := manip_axis_length(obj.position, frame.camera_pos);
    center := obj.position;
    axis_colors := Vector4.[
        .{0.95, 0.32, 0.32, 1.0},
        .{0.32, 0.92, 0.40, 1.0},
        .{0.35, 0.58, 0.98, 1.0},
    ];

    if ctx.mode == .ROTATE {
        orbit_r := axis_len * 0.92;
        orbit_col := Vector4.{0.92, 0.92, 0.96, 0.92};
        if ctx.hovered_orbit || (ctx.active && ctx.active_kind == .ORBIT) {
            orbit_col = .{1.0, 0.95, 0.55, 1.0};
        }
        draw_axis_ring(gizmo_ctx, center, .{1.0, 0.0, 0.0}, orbit_r, orbit_col, 2.1, 44);
        draw_axis_ring(gizmo_ctx, center, .{0.0, 1.0, 0.0}, orbit_r, orbit_col, 2.1, 44);
        draw_axis_ring(gizmo_ctx, center, .{0.0, 0.0, 1.0}, orbit_r, orbit_col, 2.1, 44);
        return;
    }

    for axis_i: 0..2 {
        axis_i32 := cast(s32) axis_i;
        dir := object_axis_dir(ctx, obj, axis_i32);
        tip := center + dir * axis_len;
        color := axis_colors[axis_i];
        view_depth := clamp(dot(normalize_or_fallback(tip - frame.camera_pos, frame.camera_forward), frame.camera_forward), 0.0, 1.0);
        depth_fade := 0.35 + 0.65 * view_depth;
        color *= .{depth_fade, depth_fade, depth_fade, 1.0};
        if ctx.hovered_axis == axis_i32 || (ctx.active && ctx.active_kind == .AXIS && ctx.active_axis == axis_i32) {
            color = color * .{1.25, 1.25, 1.25, 1.0};
        }

        Gizmo.draw_arrow(gizmo_ctx, center, tip, color, 2.8, axis_len * 0.16);
        if ctx.mode == .SCALE {
            draw_obb(gizmo_ctx, tip, .{axis_len * 0.08, axis_len * 0.08, axis_len * 0.08}, .{w = 1.0}, color, 2.0);
        } else {
            Gizmo.draw_handle(gizmo_ctx, tip, axis_len * 0.09, color, 2.0);
        }
    }

    if ctx.mode == .TRANSLATE {
        for plane_i: 0..2 {
            plane_i32 := cast(s32) plane_i;
            u_axis, v_axis, _ := plane_axes(plane_i32);
            u := object_axis_dir(ctx, obj, u_axis);
            v := object_axis_dir(ctx, obj, v_axis);
            plane_offset := axis_len * 0.20;
            plane_size := axis_len * 0.18;
            plane_center := center + (u + v) * plane_offset;

            col := plane_color(plane_i32);
            view_depth := clamp(dot(normalize_or_fallback(plane_center - frame.camera_pos, frame.camera_forward), frame.camera_forward), 0.0, 1.0);
            depth_fade := 0.30 + 0.70 * view_depth;
            col *= .{depth_fade, depth_fade, depth_fade, 1.0};
            col.w = 0.22 + 0.40 * depth_fade;
            if ctx.hovered_plane == plane_i32 || (ctx.active && ctx.active_kind == .PLANE && ctx.active_plane == plane_i32) {
                col = .{1.0, 0.95, 0.55, 0.9};
            }
            draw_plane_quad(gizmo_ctx, plane_center, u, v, plane_size, col, 2.2, fill = true);
        }
    }
}

pick_handle :: (ctx: *Manip_Context, obj: Manip_Object, frame: Manip_Frame_Input) -> (kind: Manip_Drag_Kind, axis: s32, plane: s32) {
    reset_hover(ctx);

    center_screen, center_ok := world_to_screen(obj.position, frame);
    if !center_ok return .NONE, -1, -1;

    axis_len := manip_axis_length(obj.position, frame.camera_pos);

    if ctx.mode == .ROTATE {
        orbit_world := obj.position + frame.camera_right * (axis_len * 0.92);
        orbit_screen, orbit_ok := world_to_screen(orbit_world, frame);
        if orbit_ok {
            radius_px := length(orbit_screen - center_screen);
            d := length(frame.mouse_pos - center_screen);
            if d <= radius_px + 14.0 {
                ctx.hovered_orbit = true;
                return .ORBIT, -1, -1;
            }
        }
        return .NONE, -1, -1;
    }

    // Plane picking first (Unity-like).
    if ctx.mode == .TRANSLATE {
        for plane_i: 0..2 {
            plane_i32 := cast(s32) plane_i;
            u_axis, v_axis, _ := plane_axes(plane_i32);
            u := object_axis_dir(ctx, obj, u_axis);
            v := object_axis_dir(ctx, obj, v_axis);
            plane_offset := axis_len * 0.20;
            plane_size := axis_len * 0.18;
            plane_center := obj.position + (u + v) * plane_offset;
            if mouse_in_plane_quad(frame.mouse_pos, frame, plane_center, u, v, plane_size) {
                ctx.hovered_plane = plane_i32;
                return .PLANE, -1, plane_i32;
            }
        }
    }

    best_dist: float = 1000000.0;
    best_axis: s32 = -1;
    for axis_i: 0..2 {
        axis_i32 := cast(s32) axis_i;
        axis_world := object_axis_dir(ctx, obj, axis_i32);
        tip := obj.position + axis_world * axis_len;
        tip_screen, tip_ok := world_to_screen(tip, frame);
        if !tip_ok continue;

        dist := distance_point_segment(frame.mouse_pos, center_screen, tip_screen);
        if dist < 18.0 && dist < best_dist {
            best_dist = dist;
            best_axis = axis_i32;
        }
    }

    if best_axis >= 0 {
        ctx.hovered_axis = best_axis;
        return .AXIS, best_axis, -1;
    }

    return .NONE, -1, -1;
}

begin_drag :: (
    ctx: *Manip_Context,
    obj: Manip_Object,
    kind: Manip_Drag_Kind,
    axis: s32,
    plane: s32,
    frame: Manip_Frame_Input,
    ray_origin: Vector3,
    ray_dir: Vector3,
) {
    ctx.active = true;
    ctx.active_kind = kind;
    ctx.active_axis = axis;
    ctx.active_plane = plane;
    ctx.drag_start_mouse = frame.mouse_pos;
    ctx.drag_start_position = obj.position;
    ctx.drag_start_rotation = obj.rotation;
    ctx.drag_start_scale = obj.scale;

    if kind == .AXIS {
        ctx.drag_axis_world = object_axis_dir(ctx, obj, axis);
        axis_len := manip_axis_length(obj.position, frame.camera_pos);
        center_screen, center_ok := world_to_screen(obj.position, frame);
        tip_screen, tip_ok := world_to_screen(obj.position + ctx.drag_axis_world * axis_len, frame);
        if center_ok && tip_ok {
            axis_screen := tip_screen - center_screen;
            len := length(axis_screen);
            if len > 0.001 ctx.drag_axis_screen = axis_screen * (1.0 / len);
            else ctx.drag_axis_screen = .{1.0, 0.0};
        } else {
            ctx.drag_axis_screen = .{1.0, 0.0};
        }
        return;
    }

    if kind == .PLANE {
        _, _, n_axis := plane_axes(plane);
        n := object_axis_dir(ctx, obj, n_axis);
        normalize(*n, fallback = axis_dir(n_axis));
        ctx.drag_plane_normal = n;
        ctx.drag_plane_origin = obj.position;

        hit, p := ray_intersect_plane(ray_origin, ray_dir, ctx.drag_plane_origin, ctx.drag_plane_normal);
        if hit ctx.drag_plane_start_hit = p;
        else ctx.drag_plane_start_hit = ctx.drag_plane_origin;
        return;
    }

    if kind == .ORBIT {
        axis_len := manip_axis_length(obj.position, frame.camera_pos);
        orbit_world := obj.position + frame.camera_right * (axis_len * 0.92);
        orbit_screen, orbit_ok := world_to_screen(orbit_world, frame);
        center_screen, center_ok := world_to_screen(obj.position, frame);

        radius_px := ifx (orbit_ok && center_ok) then length(orbit_screen - center_screen) else 80.0;
        ctx.drag_orbit_center_screen = ifx center_ok then center_screen else frame.mouse_pos;
        ctx.drag_orbit_radius_px = max(20.0, radius_px);
        ctx.drag_orbit_prev_vec = trackball_vec(frame.mouse_pos, ctx.drag_orbit_center_screen, ctx.drag_orbit_radius_px);
        return;
    }
}

apply_drag :: (
    ctx: *Manip_Context,
    obj: *Manip_Object,
    frame: Manip_Frame_Input,
    ray_origin: Vector3,
    ray_dir: Vector3,
    result: *Manip_Result,
) {
    if ctx.active_kind == .AXIS {
        mouse_delta := frame.mouse_pos - ctx.drag_start_mouse;
        pixel_delta := dot(mouse_delta, ctx.drag_axis_screen);
        world_per_pixel := max(0.0001, distance(frame.camera_pos, ctx.drag_start_position)) * tan(frame.fov_y * 0.5) * 2.0 / max(frame.viewport.y, 1.0);
        world_delta := pixel_delta * world_per_pixel;

        axis := ctx.active_axis;
        if axis < 0 || axis > 2 return;

        if ctx.mode == .TRANSLATE {
            obj.position = ctx.drag_start_position + ctx.drag_axis_world * world_delta;
            result.changed = true;
        } else if ctx.mode == .SCALE {
            s := ctx.drag_start_scale;
            next := max(0.05, get_axis_component(s, axis) + world_delta);
            set_axis_component(*s, axis, next);
            obj.scale = s;
            result.changed = true;
        }
        return;
    }

    if ctx.active_kind == .PLANE {
        hit, p := ray_intersect_plane(ray_origin, ray_dir, ctx.drag_plane_origin, ctx.drag_plane_normal);
        if hit {
            delta := p - ctx.drag_plane_start_hit;
            obj.position = ctx.drag_start_position + delta;
            result.changed = true;
        }
        return;
    }

    if ctx.active_kind == .ORBIT {
        v0 := ctx.drag_orbit_prev_vec;
        v1 := trackball_vec(frame.mouse_pos, ctx.drag_orbit_center_screen, ctx.drag_orbit_radius_px);

        axis_cam := cross(v1, v0);
        axis_len := length(axis_cam);
        if axis_len <= 0.00001 return;
        axis_cam /= axis_len;
        dot_v := clamp(dot(v0, v1), -1.0, 1.0);
        angle := acos(dot_v);

        axis_world :=
            frame.camera_right * axis_cam.x +
            frame.camera_up * axis_cam.y +
            frame.camera_forward * axis_cam.z;
        normalize(*axis_world, fallback = frame.camera_up);

        dq := quat_from_axis_angle(axis_world, angle * 1.45);
        if ctx.space == .LOCAL {
            obj.rotation = obj.rotation * dq;
        } else {
            obj.rotation = dq * obj.rotation;
        }
        normalize_or_identity(*obj.rotation);
        ctx.drag_orbit_prev_vec = v1;
        result.changed = true;
        return;
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
    // Mouse positions are integer pixel coordinates; ray should pass through
    // pixel centers for consistent hit-testing against rasterized output.
    nx := ((frame.mouse_pos.x + 0.5) / frame.viewport.x) * 2.0 - 1.0;
    ny := ((frame.mouse_pos.y + 0.5) / frame.viewport.y) * 2.0 - 1.0;
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

ray_intersect_plane :: (ray_origin: Vector3, ray_dir: Vector3, plane_origin: Vector3, plane_normal: Vector3) -> (hit: bool, p: Vector3) {
    denom := dot(ray_dir, plane_normal);
    if abs(denom) <= 0.00001 return false, .{};
    t := dot(plane_origin - ray_origin, plane_normal) / denom;
    if t <= 0.00001 return false, .{};
    return true, ray_origin + ray_dir * t;
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

plane_axes :: (plane_index: s32) -> (u_axis: s32, v_axis: s32, n_axis: s32) {
    if plane_index == 0 return 0, 1, 2; // XY
    if plane_index == 1 return 1, 2, 0; // YZ
    return 0, 2, 1; // XZ
}

plane_color :: (plane_index: s32) -> Vector4 {
    if plane_index == 0 return .{0.92, 0.82, 0.32, 1.0};
    if plane_index == 1 return .{0.34, 0.82, 0.92, 1.0};
    return .{0.92, 0.48, 0.92, 1.0};
}

orthonormal_basis :: (n: Vector3) -> (u: Vector3, v: Vector3) {
    up := Vector3.{0.0, 1.0, 0.0};
    if abs(dot(n, up)) > 0.95 up = .{1.0, 0.0, 0.0};
    u := cross(n, up);
    normalize(*u, fallback = .{1.0, 0.0, 0.0});
    v := cross(n, u);
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

draw_plane_quad :: (ctx: *Gizmo.Gizmo_Context, center: Vector3, u: Vector3, v: Vector3, size: float, color: Vector4, thickness: float, fill: bool = false) {
    h := size * 0.5;
    p0 := center + (-u - v) * h;
    p1 := center + ( u - v) * h;
    p2 := center + ( u + v) * h;
    p3 := center + (-u + v) * h;
    if fill {
        fill_col := color;
        fill_col.w *= 0.75;
        Gizmo.draw_triangle(ctx, p0, p1, p2, fill_col, filled = true);
        Gizmo.draw_triangle(ctx, p0, p2, p3, fill_col, filled = true);
    }
    Gizmo.draw_line(ctx, p0, p1, color, thickness);
    Gizmo.draw_line(ctx, p1, p2, color, thickness);
    Gizmo.draw_line(ctx, p2, p3, color, thickness);
    Gizmo.draw_line(ctx, p3, p0, color, thickness);
}

mouse_in_plane_quad :: (mouse: Vector2, frame: Manip_Frame_Input, center: Vector3, u: Vector3, v: Vector3, size: float) -> bool {
    h := size * 0.5;
    p0w := center + (-u - v) * h;
    p1w := center + ( u - v) * h;
    p2w := center + ( u + v) * h;
    p3w := center + (-u + v) * h;

    p0, ok0 := world_to_screen(p0w, frame);
    p1, ok1 := world_to_screen(p1w, frame);
    p2, ok2 := world_to_screen(p2w, frame);
    p3, ok3 := world_to_screen(p3w, frame);
    if !ok0 || !ok1 || !ok2 || !ok3 return false;

    return point_in_triangle(mouse, p0, p1, p2) || point_in_triangle(mouse, p0, p2, p3);
}

point_in_triangle :: (p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool {
    s1 := sign2(p, a, b);
    s2 := sign2(p, b, c);
    s3 := sign2(p, c, a);
    has_neg := s1 < 0.0 || s2 < 0.0 || s3 < 0.0;
    has_pos := s1 > 0.0 || s2 > 0.0 || s3 > 0.0;
    return !(has_neg && has_pos);
}

sign2 :: (p1: Vector2, p2: Vector2, p3: Vector2) -> float {
    return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}

trackball_vec :: (mouse: Vector2, center: Vector2, radius_px: float) -> Vector3 {
    r := max(radius_px, 1.0);
    x := (mouse.x - center.x) / r;
    y := (mouse.y - center.y) / r;
    len2 := x * x + y * y;
    if len2 > 1.0 {
        inv := 1.0 / sqrt(len2);
        return .{x * inv, y * inv, 0.0};
    }
    z := sqrt(max(0.0, 1.0 - len2));
    return .{x, y, z};
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

draw_object_wire :: (ctx: *Gizmo.Gizmo_Context, obj: Manip_Object, scale_factor: float, color: Vector4, thickness: float) {
    if #complete obj.shape == {
    case .SPHERE;
        effective_half := hadamard(obj.half_extents, obj.scale);
        radius := max(max(effective_half.x, effective_half.y), effective_half.z) * scale_factor;
        Gizmo.draw_sphere(ctx, obj.position, radius, color, thickness, segments = 24, rotation = obj.rotation);
    case .BOX;
        half := hadamard(obj.half_extents, obj.scale) * scale_factor;
        draw_obb(ctx, obj.position, half, obj.rotation, color, thickness);
    }
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

normalize_or_fallback :: (v: Vector3, fallback: Vector3) -> Vector3 {
    n := v;
    normalize(*n, fallback = fallback);
    return n;
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
