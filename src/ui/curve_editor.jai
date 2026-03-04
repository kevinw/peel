// Port of https://gist.github.com/SoapyMan/1d32b56dd267e7cd9a2408047fd5c90c
// adapted to Jai + peel ImGui bindings.

CURVE_TERMINATOR :: -10000.0;

Curve_Ease_Type :: enum s32 {
    LINEAR;
    QUADIN;
    QUADOUT;
    QUADINOUT;
    CUBICIN;
    CUBICOUT;
    CUBICINOUT;
    QUARTIN;
    QUARTOUT;
    QUARTINOUT;
    QUINTIN;
    QUINTOUT;
    QUINTINOUT;
    SINEIN;
    SINEOUT;
    SINEINOUT;
    EXPOIN;
    EXPOOUT;
    EXPOINOUT;
    CIRCIN;
    CIRCOUT;
    CIRCINOUT;
    ELASTICIN;
    ELASTICOUT;
    ELASTICINOUT;
    BACKIN;
    BACKOUT;
    BACKINOUT;
    BOUNCEIN;
    BOUNCEOUT;
    BOUNCEINOUT;
    SINESQUARE;
    EXPONENTIAL;
    SCHUBRING1;
    SCHUBRING2;
    SCHUBRING3;
    SINPI2;
    SWING;
}

curve_value :: (p: float, maxpoints: s32, points: *ImGui.ImVec2) -> float {
    if maxpoints < 2 || !points return 0.0;
    if p < 0.0 return points[0].y;

    count := curve_point_count(maxpoints, points);
    if count <= 0 return 0.0;
    if p <= points[0].x return points[0].y;
    if p >= points[count - 1].x return points[count - 1].y;

    left: s32 = 0;
    while left < count && points[left].x < p left += 1;
    left -= 1;
    if left < 0 left = 0;
    if left >= count - 1 return points[count - 1].y;

    denom := points[left + 1].x - points[left].x;
    if abs(denom) < 0.000001 return points[left].y;

    d := (p - points[left].x) / denom;
    return points[left].y + (points[left + 1].y - points[left].y) * d;
}

curve_value_smooth :: (p: float, maxpoints: s32, points: *ImGui.ImVec2) -> float {
    if maxpoints < 2 || !points return 0.0;

    count := curve_point_count(maxpoints, points);
    if count <= 0 return 0.0;
    if p <= points[0].x return points[0].y;
    if p >= points[count - 1].x return points[count - 1].y;

    k: s32 = 0;
    while k < count && points[k].x < p k += 1;
    if k <= 0 return points[0].y;
    if k >= count return points[count - 1].y;

    key0 := points[k - 1].x;
    key1 := points[k].x;
    denom := key1 - key0;
    if abs(denom) < 0.000001 return points[k].y;

    h := (p - key0) / denom;

    coefs := float.[
        -1.0, 2.0, -1.0, 0.0,
         3.0, -5.0, 0.0, 2.0,
        -3.0, 4.0, 1.0, 0.0,
         1.0, -1.0, 0.0, 0.0,
    ];

    out := 0.0;
    for i: 0..3 {
        co := i * 4;
        b := 0.5 * (((coefs[co + 0] * h + coefs[co + 1]) * h + coefs[co + 2]) * h + coefs[co + 3]);
        kn := clamp_s32(k + cast(s32) i - 2, 0, count - 1);
        out += b * points[kn].y;
    }

    return out;
}

curve :: (label: string, size: ImGui.ImVec2, maxpoints: s32, points: *ImGui.ImVec2, selection: *s32 = null,
          range_min := ImGui.ImVec2.{0.0, 0.0}, range_max := ImGui.ImVec2.{1.0, 1.0}) -> bool {
    using ImGui;

    if maxpoints < 2 || !points return false;

    if points[0].x <= CURVE_TERMINATOR {
        points[0] = range_min;
        points[1] = range_max;
        if maxpoints > 2 points[2].x = CURVE_TERMINATOR;
    }

    PushID(label);
    defer PopID();

    _ = InvisibleButton("##curve_canvas", size);
    bb_min := GetItemRectMin();
    bb_max := GetItemRectMax();
    hovered := IsItemHovered();

    count := curve_point_count(maxpoints, points);
    current_selection: s32 = ifx selection then selection.* else cast(s32) -1;
    changed := false;

    draw := GetWindowDrawList();

    frame_col := GetColorU32(.FrameBg, 1.0);
    frame_border_col := GetColorU32(.Border, 0.9);
    ImGui.ImDrawList.AddRectFilled(draw, bb_min, bb_max, frame_col, 4.0);
    ImGui.ImDrawList.AddRect(draw, bb_min, bb_max, frame_border_col, 4.0, .None, 1.0);

    ht := bb_max.y - bb_min.y;
    wd := bb_max.x - bb_min.x;

    // grid
    grid1 := GetColorU32(.TextDisabled, 0.50);
    grid2 := GetColorU32(.TextDisabled, 0.25);
    ImGui.ImDrawList.AddLine(draw, .{bb_min.x, bb_min.y + ht * 0.5}, .{bb_max.x, bb_min.y + ht * 0.5}, grid1, 2.0);
    ImGui.ImDrawList.AddLine(draw, .{bb_min.x, bb_min.y + ht * 0.25}, .{bb_max.x, bb_min.y + ht * 0.25}, grid1, 1.0);
    ImGui.ImDrawList.AddLine(draw, .{bb_min.x, bb_min.y + ht * 0.75}, .{bb_max.x, bb_min.y + ht * 0.75}, grid1, 1.0);
    for i: 1..9 {
        x := bb_min.x + (wd / 10.0) * cast(float) i;
        ImGui.ImDrawList.AddLine(draw, .{x, bb_min.y}, .{x, bb_max.y}, grid2, 1.0);
    }

    hovered_point: s32 = -1;
    point_radius_px := 5.0;

    if hovered {
        mouse := GetMousePos();
        uv := imv2_sub(mouse, bb_min);
        uv = imv2_div(uv, imv2_sub(bb_max, bb_min));
        uv.y = 1.0 - uv.y;
        pos := remap_v2(uv, .{0.0, 0.0}, .{1.0, 1.0}, range_min, range_max);

        left: s32 = 0;
        while left < count && points[left].x < pos.x left += 1;
        if left > 0 left -= 1;
        if left >= count - 1 left = count - 2;

        hover_screen := remap_v2(uv, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);
        p1s := remap_v2(points[left], range_min, range_max, bb_min, bb_max);
        p2s := remap_v2(points[left + 1], range_min, range_max, bb_min, bb_max);

        if imv2_length(imv2_sub(p1s, hover_screen)) < point_radius_px hovered_point = left;
        if imv2_length(imv2_sub(p2s, hover_screen)) < point_radius_px hovered_point = left + 1;

        io := GetIO();
        if io.MouseDown[0] {
            if current_selection == -1 current_selection = hovered_point;
        } else {
            current_selection = -1;
        }

        do_add := false;
        do_delete := false;

        if current_selection == -1 {
            if IsMouseDoubleClicked(.Left) || IsMouseDragging(.Left) do_add = true;
        } else if IsMouseDoubleClicked(.Left) {
            do_delete = true;
        }

        if do_add {
            if count < maxpoints {
                current_selection = left + 1;

                i := count;
                while i > left {
                    points[i] = points[i - 1];
                    i -= 1;
                }

                points[left + 1] = pos;
                count += 1;
                if count < maxpoints points[count].x = CURVE_TERMINATOR;
                changed = true;
            }
        } else if do_delete {
            if current_selection > 0 && current_selection < count - 1 {
                i := current_selection;
                while i < maxpoints - 1 {
                    points[i] = points[i + 1];
                    i += 1;
                }
                count -= 1;
                points[count].x = CURVE_TERMINATOR;
                current_selection = -1;
                changed = true;
            }
        }
    }

    if IsMouseDragging(.Left) && current_selection != -1 {
        mouse := GetMousePos();
        uv := imv2_sub(mouse, bb_min);
        uv = imv2_div(uv, imv2_sub(bb_max, bb_min));
        uv.y = 1.0 - uv.y;
        pos := remap_v2(uv, .{0.0, 0.0}, .{1.0, 1.0}, range_min, range_max);

        x_min := ifx current_selection > 0 then points[current_selection - 1].x else range_min.x;
        x_max := ifx current_selection + 1 < count then points[current_selection + 1].x else range_max.x;

        pos.x = clamp_float(pos.x, x_min, x_max);
        pos.y = clamp_float(pos.y, range_min.y, range_max.y);

        points[current_selection] = pos;
        changed = true;
    }

    // smooth curve
    ImGui.ImDrawList.PushClipRect(draw, bb_min, bb_max, true);
    defer ImGui.ImDrawList.PopClipRect(draw);

    smoothness :: 256;
    smooth_col := GetColorU32(.PlotHistogram, 1.0);
    for i: 0..smoothness - 1 {
        px := cast(float) (i + 0) / cast(float) smoothness;
        qx := cast(float) (i + 1) / cast(float) smoothness;

        px = remap_f(px, 0.0, 1.0, range_min.x, range_max.x);
        qx = remap_f(qx, 0.0, 1.0, range_min.x, range_max.x);

        py := curve_value_smooth(px, maxpoints, points);
        qy := curve_value_smooth(qx, maxpoints, points);

        p := remap_v2(.{px, py}, range_min, range_max, .{0.0, 0.0}, .{1.0, 1.0});
        q := remap_v2(.{qx, qy}, range_min, range_max, .{0.0, 0.0}, .{1.0, 1.0});
        p.y = 1.0 - p.y;
        q.y = 1.0 - q.y;

        p = remap_v2(p, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);
        q = remap_v2(q, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);

        ImGui.ImDrawList.AddLine(draw, p, q, smooth_col, 1.0);
    }

    // control polyline + points
    line_col := GetColorU32(.PlotLines, 0.5);
    for i: 1..count - 1 {
        a := remap_v2(points[i - 1], range_min, range_max, .{0.0, 0.0}, .{1.0, 1.0});
        b := remap_v2(points[i], range_min, range_max, .{0.0, 0.0}, .{1.0, 1.0});
        a.y = 1.0 - a.y;
        b.y = 1.0 - b.y;
        a = remap_v2(a, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);
        b = remap_v2(b, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);
        ImGui.ImDrawList.AddLine(draw, a, b, line_col, 1.0);
    }

    if hovered || IsMouseDragging(.Left) {
        point_col := GetColorU32(.PlotLinesHovered, 1.0);
        for i: 0..count - 1 {
            p := remap_v2(points[i], range_min, range_max, .{0.0, 0.0}, .{1.0, 1.0});
            p.y = 1.0 - p.y;
            p = remap_v2(p, .{0.0, 0.0}, .{1.0, 1.0}, bb_min, bb_max);

            if hovered_point == i {
                ImGui.ImDrawList.AddRect(draw, .{p.x - 4, p.y - 4}, .{p.x + 4, p.y + 4}, point_col, 1.0, .None, 1.0);
            } else {
                ImGui.ImDrawList.AddCircle(draw, p, point_radius_px, point_col, 12, 1.0);
            }
        }
    }

    // tooltip text inside frame
    label_text := label;
    if hovered || IsMouseDragging(.Left) {
        mouse := GetMousePos();
        uv := imv2_sub(mouse, bb_min);
        uv = imv2_div(uv, imv2_sub(bb_max, bb_min));
        uv.y = 1.0 - uv.y;
        pos := remap_v2(uv, .{0.0, 0.0}, .{1.0, 1.0}, range_min, range_max);
        label_text = tprint("% (%.2f, %.2f)", label, pos.x, pos.y);
    }
    ImGui.ImDrawList.AddText(draw, .{bb_min.x + 8, bb_min.y + 6}, GetColorU32(.Text, 1.0), label_text);

    if BeginPopupContextItem(null) {
        if Selectable("Reset") {
            points[0] = range_min;
            points[1] = range_max;
            if maxpoints > 2 points[2].x = CURVE_TERMINATOR;
            changed = true;
        }
        if Selectable("Flip") {
            for i: 0..count - 1 {
                yv := 1.0 - remap_f(points[i].y, range_min.y, range_max.y, 0.0, 1.0);
                points[i].y = remap_f(yv, 0.0, 1.0, range_min.y, range_max.y);
            }
            changed = true;
        }
        if Selectable("Mirror") {
            i := 0;
            j := count - 1;
            while i < j {
                tmp := points[i];
                points[i] = points[j];
                points[j] = tmp;
                i += 1;
                j -= 1;
            }
            for i: 0..count - 1 {
                xv := 1.0 - remap_f(points[i].x, range_min.x, range_max.x, 0.0, 1.0);
                points[i].x = remap_f(xv, 0.0, 1.0, range_min.x, range_max.x);
            }
            changed = true;
        }

        Separator();
        if BeginMenu("Presets") {
            if curve_preset_item("Linear", .LINEAR, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quad in", .QUADIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quad out", .QUADOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quad in out", .QUADINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Cubic in", .CUBICIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Cubic out", .CUBICOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Cubic in out", .CUBICINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quart in", .QUARTIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quart out", .QUARTOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quart in out", .QUARTINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quint in", .QUINTIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quint out", .QUINTOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Quint in out", .QUINTINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Sine in", .SINEIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Sine out", .SINEOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Sine in out", .SINEINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Expo in", .EXPOIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Expo out", .EXPOOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Expo in out", .EXPOINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Circ in", .CIRCIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Circ out", .CIRCOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Circ in out", .CIRCINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Elastic in", .ELASTICIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Elastic out", .ELASTICOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Elastic in out", .ELASTICINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Back in", .BACKIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Back out", .BACKOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Back in out", .BACKINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Bounce in", .BOUNCEIN, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Bounce out", .BOUNCEOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Bounce in out", .BOUNCEINOUT, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Sine square", .SINESQUARE, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Exponential", .EXPONENTIAL, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Schubring1", .SCHUBRING1, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Schubring2", .SCHUBRING2, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Schubring3", .SCHUBRING3, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("SinPi2", .SINPI2, maxpoints, points, range_min, range_max) changed = true;
            if curve_preset_item("Swing", .SWING, maxpoints, points, range_min, range_max) changed = true;
            EndMenu();
        }
        EndPopup();
    }

    if selection selection.* = current_selection;
    return changed;
}

#scope_file

curve_point_count :: (maxpoints: s32, points: *ImGui.ImVec2) -> s32 {
    count: s32 = 0;
    while count < maxpoints {
        if points[count].x <= CURVE_TERMINATOR break;
        count += 1;
    }
    return count;
}

curve_preset_item :: (label: *u8, ease_type: Curve_Ease_Type, maxpoints: s32, points: *ImGui.ImVec2,
                      range_min: ImGui.ImVec2, range_max: ImGui.ImVec2) -> bool {
    using ImGui;
    if !Selectable(label) return false;

    denom_i := maxpoints - 1;
    if denom_i < 1 denom_i = 1;
    denom := cast(float) denom_i;
    for i: 0..maxpoints - 1 {
        px := cast(float) i / denom;
        py := cast(float) curve_ease(ease_type, cast(float64) px);
        points[i] = remap_v2(.{px, py}, .{0.0, 0.0}, .{1.0, 1.0}, range_min, range_max);
    }

    return true;
}

curve_ease :: (ease_type: Curve_Ease_Type, t: float64) -> float64 {
    p := t;
    pi :: 3.1415926535897932384626433832795;
    pi2 :: pi * 0.5;
    if ease_type == .LINEAR return p;
    if ease_type == .QUADIN return p * p;
    if ease_type == .QUADOUT return -(p * (p - 2.0));
    if ease_type == .QUADINOUT {
        if p < 0.5 return 2.0 * p * p;
        return (-2.0 * p * p) + (4.0 * p) - 1.0;
    }
    if ease_type == .CUBICIN return p * p * p;
    if ease_type == .CUBICOUT {
        f := p - 1.0;
        return f * f * f + 1.0;
    }
    if ease_type == .CUBICINOUT {
        if p < 0.5 return 4.0 * p * p * p;
        f := (2.0 * p) - 2.0;
        return 0.5 * f * f * f + 1.0;
    }
    if ease_type == .QUARTIN return p * p * p * p;
    if ease_type == .QUARTOUT {
        f := p - 1.0;
        return f * f * f * (1.0 - p) + 1.0;
    }
    if ease_type == .QUARTINOUT {
        if p < 0.5 return 8.0 * p * p * p * p;
        f := p - 1.0;
        return -8.0 * f * f * f * f + 1.0;
    }
    if ease_type == .QUINTIN return p * p * p * p * p;
    if ease_type == .QUINTOUT {
        f := p - 1.0;
        return f * f * f * f * f + 1.0;
    }
    if ease_type == .QUINTINOUT {
        if p < 0.5 return 16.0 * p * p * p * p * p;
        f := (2.0 * p) - 2.0;
        return 0.5 * f * f * f * f * f + 1.0;
    }
    if ease_type == .SINEIN return sin((p - 1.0) * pi2) + 1.0;
    if ease_type == .SINEOUT return sin(p * pi2);
    if ease_type == .SINEINOUT return 0.5 * (1.0 - cos(p * pi));
    if ease_type == .EXPOIN {
        if p == 0.0 return p;
        return pow(2.0, 10.0 * (p - 1.0));
    }
    if ease_type == .EXPOOUT {
        if p == 1.0 return p;
        return 1.0 - pow(2.0, -10.0 * p);
    }
    if ease_type == .EXPOINOUT {
        if p == 0.0 || p == 1.0 return p;
        if p < 0.5 return 0.5 * pow(2.0, (20.0 * p) - 10.0);
        return -0.5 * pow(2.0, (-20.0 * p) + 10.0) + 1.0;
    }
    if ease_type == .CIRCIN return 1.0 - sqrt(1.0 - (p * p));
    if ease_type == .CIRCOUT return sqrt((2.0 - p) * p);
    if ease_type == .CIRCINOUT {
        if p < 0.5 return 0.5 * (1.0 - sqrt(1.0 - 4.0 * (p * p)));
        return 0.5 * (sqrt(-((2.0 * p) - 3.0) * ((2.0 * p) - 1.0)) + 1.0);
    }
    if ease_type == .ELASTICIN return sin(13.0 * pi2 * p) * pow(2.0, 10.0 * (p - 1.0));
    if ease_type == .ELASTICOUT return sin(-13.0 * pi2 * (p + 1.0)) * pow(2.0, -10.0 * p) + 1.0;
    if ease_type == .ELASTICINOUT {
        if p < 0.5 return 0.5 * sin(13.0 * pi2 * (2.0 * p)) * pow(2.0, 10.0 * ((2.0 * p) - 1.0));
        return 0.5 * (sin(-13.0 * pi2 * ((2.0 * p - 1.0) + 1.0)) * pow(2.0, -10.0 * (2.0 * p - 1.0)) + 2.0);
    }
    if ease_type == .BACKIN return p * p * p - p * sin(p * pi);
    if ease_type == .BACKOUT {
        f := 1.0 - p;
        return 1.0 - (f * f * f - f * sin(f * pi));
    }
    if ease_type == .BACKINOUT {
        if p < 0.5 {
            f := 2.0 * p;
            return 0.5 * (f * f * f - f * sin(f * pi));
        }
        f := 1.0 - (2.0 * p - 1.0);
        return 0.5 * (1.0 - (f * f * f - f * sin(f * pi))) + 0.5;
    }
    if ease_type == .BOUNCEOUT {
        if p < 4.0 / 11.0 return (121.0 * p * p) / 16.0;
        if p < 8.0 / 11.0 return (363.0 / 40.0 * p * p) - (99.0 / 10.0 * p) + 17.0 / 5.0;
        if p < 9.0 / 10.0 return (4356.0 / 361.0 * p * p) - (35442.0 / 1805.0 * p) + 16061.0 / 1805.0;
        return (54.0 / 5.0 * p * p) - (513.0 / 25.0 * p) + 268.0 / 25.0;
    }
    if ease_type == .BOUNCEIN return 1.0 - curve_ease(.BOUNCEOUT, 1.0 - p);
    if ease_type == .BOUNCEINOUT {
        if p < 0.5 return 0.5 * curve_ease(.BOUNCEIN, p * 2.0);
        return 0.5 * curve_ease(.BOUNCEOUT, p * 2.0 - 1.0) + 0.5;
    }
    if ease_type == .SINESQUARE {
        val := sin(p * pi2);
        return val * val;
    }
    if ease_type == .EXPONENTIAL return 1.0 / (1.0 + exp(6.0 - 12.0 * p));
    if ease_type == .SCHUBRING1 return 2.0 * (p + (0.5 - p) * abs(0.5 - p)) - 0.5;
    if ease_type == .SCHUBRING2 return 2.0 * (p + (0.5 - p) * abs(0.5 - p)) - 0.5;
    if ease_type == .SCHUBRING3 return (p * (cast(float64) 2.0 - p) * (cast(float64) 2.0 - p) + (cast(float64) 1.0 - p) * p * p) / 2.0;
    if ease_type == .SINPI2 return sin(p * pi2);
    if ease_type == .SWING return (-cos(pi * p) * 0.5) + 0.5;

    return p;
}

clamp_float :: (v: float, lo: float, hi: float) -> float {
    if v < lo return lo;
    if v > hi return hi;
    return v;
}

remap_f :: (v: float, a: float, b: float, c: float, d: float) -> float {
    if abs(b - a) < 0.000001 return c;
    return c + (d - c) * (v - a) / (b - a);
}

remap_v2 :: (v: ImGui.ImVec2, a: ImGui.ImVec2, b: ImGui.ImVec2, c: ImGui.ImVec2, d: ImGui.ImVec2) -> ImGui.ImVec2 {
    return .{
        remap_f(v.x, a.x, b.x, c.x, d.x),
        remap_f(v.y, a.y, b.y, c.y, d.y),
    };
}

imv2_sub :: (a: ImGui.ImVec2, b: ImGui.ImVec2) -> ImGui.ImVec2 {
    return .{a.x - b.x, a.y - b.y};
}

imv2_div :: (a: ImGui.ImVec2, b: ImGui.ImVec2) -> ImGui.ImVec2 {
    return .{a.x / b.x, a.y / b.y};
}

imv2_length :: (v: ImGui.ImVec2) -> float {
    return sqrt(v.x * v.x + v.y * v.y);
}

#scope_file
ImGui :: #import "ImGui";
#import "Basic";
#import "Math";

clamp_s32 :: (v: s32, lo: s32, hi: s32) -> s32 {
    if v < lo return lo;
    if v > hi return hi;
    return v;
}
