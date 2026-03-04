// Adapted from https://github.com/Ka1serM/ImViewGuizmo (MIT)
// Simplified Jai port for peel: rotate + axis snap view gizmo.

View_Gizmo_Result :: struct {
    changed: bool;
    hovered: bool;
    in_use: bool;
}

View_Gizmo_Context :: struct {
    hovered_axis: s32;
    pressed_axis: s32;
    active: bool;
}

view_gizmo_ctx: View_Gizmo_Context;

view_gizmo :: (yaw: *float, pitch: *float, scale: float = 1.0) -> View_Gizmo_Result {
    using ImGui;

    result: View_Gizmo_Result;
    if !yaw || !pitch return result;

    vp := GetMainViewport();
    if !vp return result;

    center := ImVec2.{
        vp.Pos.x + vp.Size.x - (94.0 * scale),
        vp.Pos.y + (94.0 * scale),
    };
    radius := 70.0 * scale;
    line_len := 0.63 * radius;
    handle_r := 13.0 * scale;

    bounds_min := ImVec2.{center.x - radius - 18.0 * scale, center.y - radius - 18.0 * scale};
    bounds_max := ImVec2.{center.x + radius + 18.0 * scale, center.y + radius + 18.0 * scale};

    io := GetIO();
    draw := GetForegroundDrawList();

    cam_dir := Vector3.{
        cos(pitch.*) * cos(yaw.*),
        cos(pitch.*) * sin(yaw.*),
        sin(pitch.*),
    };
    cam_forward := -cam_dir;
    cam_forward = vg_norm3(cam_forward);

    world_up := Vector3.{0.0, 0.0, 1.0};
    cam_right := cross(cam_forward, world_up);
    if dot(cam_right, cam_right) < 0.00001 {
        world_up = .{0.0, 1.0, 0.0};
        cam_right = cross(cam_forward, world_up);
    }
    cam_right = vg_norm3(cam_right);
    cam_up := vg_norm3(cross(cam_right, cam_forward));

    axis_dirs := Vector3.[
        .{ 1.0,  0.0,  0.0},
        .{-1.0,  0.0,  0.0},
        .{ 0.0,  1.0,  0.0},
        .{ 0.0, -1.0,  0.0},
        .{ 0.0,  0.0,  1.0},
        .{ 0.0,  0.0, -1.0},
    ];
    axis_base := ImU32.[
        vg_col32(230,  51,  51, 255),
        vg_col32(230,  51,  51, 255),
        vg_col32( 51, 230,  51, 255),
        vg_col32( 51, 230,  51, 255),
        vg_col32( 51, 128, 255, 255),
        vg_col32( 51, 128, 255, 255),
    ];

    // Reset per-frame hover.
    view_gizmo_ctx.hovered_axis = -1;

    mouse_over := IsMouseHoveringRect(bounds_min, bounds_max, false);
    if mouse_over result.hovered = true;

    if mouse_over && !view_gizmo_ctx.active {
        mouse := io.MousePos;
        best_d2 := cast(float) 1000000000.0;
        for i: 0..5 {
            dir := axis_dirs[i];
            sx := dot(dir, cam_right);
            sy := dot(dir, cam_up);
            p := ImVec2.{center.x + sx * line_len, center.y - sy * line_len};
            dx := mouse.x - p.x;
            dy := mouse.y - p.y;
            d2 := dx * dx + dy * dy;
            if d2 < handle_r * handle_r && d2 < best_d2 {
                best_d2 = d2;
                view_gizmo_ctx.hovered_axis = cast(s32) i;
            }
        }
        if view_gizmo_ctx.hovered_axis >= 0 {
            SetMouseCursor(.Hand);
        } else {
            dx := mouse.x - center.x;
            dy := mouse.y - center.y;
            if dx * dx + dy * dy < radius * radius {
                SetMouseCursor(.ResizeAll);
            }
        }
    }

    // Start drag on orb center.
    if IsMouseClicked(.Left, false) {
        view_gizmo_ctx.pressed_axis = -1;
    }

    if mouse_over && !view_gizmo_ctx.active && IsMouseClicked(.Left, false) {
        mouse := io.MousePos;
        dx := mouse.x - center.x;
        dy := mouse.y - center.y;
        if dx * dx + dy * dy < radius * radius && view_gizmo_ctx.hovered_axis < 0 {
            view_gizmo_ctx.active = true;
            view_gizmo_ctx.pressed_axis = -1;
        } else {
            // Candidate snap axis is valid only if the click started on a gizmo handle.
            if view_gizmo_ctx.hovered_axis >= 0 {
                view_gizmo_ctx.pressed_axis = view_gizmo_ctx.hovered_axis;
            }
        }
    }

    if view_gizmo_ctx.active {
        yaw.* -= io.MouseDelta.x * 0.0085;
        pitch.* -= io.MouseDelta.y * 0.0065;
        pitch.* = clamp(pitch.*, -1.40, 1.40);
        result.changed = abs(io.MouseDelta.x) > 0.0 || abs(io.MouseDelta.y) > 0.0;
        result.in_use = true;
    }

    if IsMouseReleased(.Left) {
        if view_gizmo_ctx.active {
            view_gizmo_ctx.active = false;
            result.in_use = false;
        } else if mouse_over && view_gizmo_ctx.pressed_axis >= 0 && view_gizmo_ctx.hovered_axis == view_gizmo_ctx.pressed_axis {
            target := axis_dirs[view_gizmo_ctx.pressed_axis];
            yaw.* = atan2(target.y, target.x);
            pitch.* = asin(clamp(target.z, -1.0, 1.0));
            result.changed = true;
        }
        view_gizmo_ctx.pressed_axis = -1;
    }

    // Draw backing orb.
    bg_col := GetColorU32(.FrameBg, ifx (result.hovered || view_gizmo_ctx.active) then 0.82 else 0.55);
    ring_col := GetColorU32(.Border, 0.95);
    ImDrawList.AddCircleFilled(draw, center, radius, bg_col, 56);
    ImDrawList.AddCircle(draw, center, radius, ring_col, 56, 1.5);

    labels := string.["+X", "-X", "+Y", "-Y", "+Z", "-Z"];

    // Draw axis lines + handles.
    for i: 0..5 {
        dir := axis_dirs[i];
        sx := dot(dir, cam_right);
        sy := dot(dir, cam_up);
        sz := dot(dir, cam_forward);

        p := ImVec2.{center.x + sx * line_len, center.y - sy * line_len};

        fade := clamp(0.35 + 0.65 * ((sz + 1.0) * 0.5), 0.22, 1.0);
        col := GetColorU32(axis_base[i], fade);

        ImDrawList.AddLine(draw, center, p, col, 3.0 * scale);
        ImDrawList.AddCircleFilled(draw, p, handle_r, col, 20);

        if i == view_gizmo_ctx.hovered_axis {
            hi := vg_col32(255, 255, 80, 255);
            ImDrawList.AddCircle(draw, p, handle_r + 2.0 * scale, hi, 20, 2.0);
        }

        text := labels[i];
        ts := CalcTextSize(text);
        ImDrawList.AddText(draw, .{p.x - ts.x * 0.5, p.y - ts.y * 0.5}, vg_col32(255, 255, 255, 230), text);
    }

    if view_gizmo_ctx.active result.hovered = true;
    if view_gizmo_ctx.active result.in_use = true;

    return result;
}

#scope_file
vg_norm3 :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 < 0.000001 return .{0.0, 0.0, 1.0};
    return v * (1.0 / sqrt(len2));
}

vg_col32 :: (r: u32, g: u32, b: u32, a: u32) -> ImGui.ImU32 {
    return cast(ImGui.ImU32) (r | (g << 8) | (b << 16) | (a << 24));
}

ImGui :: #import "ImGui";
