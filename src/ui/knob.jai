// Port of https://github.com/altschuler/imgui-knobs adapted for Jai + peel ImGui bindings.
// Upstream license is copied to peel root LICENSE.

KNOB_PI :: 3.14159265358979323846;

Knob_Flags :: enum_flags u32 {
    NONE :: 0;
    NoTitle        :: 1 << 0;
    NoInput        :: 1 << 1;
    ValueTooltip   :: 1 << 2;
    DragHorizontal :: 1 << 3;
    DragVertical   :: 1 << 4;
    Logarithmic    :: 1 << 5;
    AlwaysClamp    :: 1 << 6;
}

Knob_Variant :: enum s32 {
    TICK;
    DOT;
    WIPER;
    WIPER_ONLY;
    WIPER_DOT;
    STEPPED;
    SPACE;
}

Knob_Color_Set :: struct {
    base: ImGui.ImU32;
    hovered: ImGui.ImU32;
    active: ImGui.ImU32;
}

Knob_State :: struct {
    radius: float;
    center: ImGui.ImVec2;
    is_active: bool;
    is_hovered: bool;
    angle_min: float;
    angle_max: float;
    t: float;
    angle: float;
    value_changed: bool;
}

knob :: (label: string, p_value: *float, v_min: float, v_max: float, speed: float = 0.0, format := "%.3f",
         variant: Knob_Variant = .TICK, size: float = 0.0, flags: Knob_Flags = .NONE, steps: s32 = 10,
         angle_min: float = -1.0, angle_max: float = -1.0) -> bool {
    if !p_value return false;
    state := knob_begin_float(label, p_value, v_min, v_max, speed, format, size, flags, angle_min, angle_max);
    knob_draw_variant(state, variant, steps);
    knob_end();
    return state.value_changed;
}

knob_int :: (label: string, p_value: *s32, v_min: s32, v_max: s32, speed: float = 0.0, format := "%d",
             variant: Knob_Variant = .TICK, size: float = 0.0, flags: Knob_Flags = .NONE, steps: s32 = 10,
             angle_min: float = -1.0, angle_max: float = -1.0) -> bool {
    if !p_value return false;
    state := knob_begin_int(label, p_value, v_min, v_max, speed, format, size, flags, angle_min, angle_max);
    knob_draw_variant(state, variant, steps);
    knob_end();
    return state.value_changed;
}

#scope_file
knob_begin_float :: (label: string, p_value: *float, v_min: float, v_max: float, speed: float, format: string, size: float,
                     flags: Knob_Flags, angle_min: float, angle_max: float) -> Knob_State {
    using ImGui;

    PushID(label);

    width := ifx size > 0.0 then size else GetTextLineHeight() * 4.0;
    PushItemWidth(width);
    BeginGroup();

    if !flags.NoTitle {
        title_size := CalcTextSize(label);
        SetCursorPosX(GetCursorPosX() + max((width - title_size.x) * 0.5, 0.0));
        Text("%", label);
    }

    screen_pos := GetCursorScreenPos();
    _ = InvisibleButton("##knob_btn", .{width, width});

    is_active := IsItemActive();
    is_hovered := IsItemHovered();

    eff_speed := speed;
    if eff_speed == 0.0 eff_speed = max((v_max - v_min) / 250.0, 0.000001);

    value_changed := false;
    if is_active {
        io := GetIO();
        delta := knob_pick_drag_delta(io, flags);
        if abs(delta) > 0.0 {
            p_value.* += delta * eff_speed;
            value_changed = true;
        }
    }

    if flags.AlwaysClamp || flags.Logarithmic {
        p_value.* = clamp(p_value.*, v_min, v_max);
    }

    slider_flags: SliderFlags = .None;
    if flags.AlwaysClamp slider_flags |= .AlwaysClamp;
    if flags.Logarithmic slider_flags |= .Logarithmic;

    if !flags.NoInput {
        if DragFloat("##knob_drag", p_value, eff_speed, v_min, v_max, temp_c_string(format), slider_flags) {
            value_changed = true;
        }
    }

    clamped_value := clamp(p_value.*, v_min, v_max);
    t := knob_value_to_t_float(clamped_value, v_min, v_max, flags);

    real_angle_min := ifx angle_min < 0.0 then cast(float) (KNOB_PI * 0.75) else angle_min;
    real_angle_max := ifx angle_max < 0.0 then cast(float) (KNOB_PI * 2.25) else angle_max;
    angle := real_angle_min + (real_angle_max - real_angle_min) * t;

    if flags.ValueTooltip && (is_hovered || is_active) {
        if BeginTooltip() {
            Text("%", tprint(format, p_value.*));
            EndTooltip();
        }
    }

    return .{
        radius = width * 0.5,
        center = .{screen_pos.x + width * 0.5, screen_pos.y + width * 0.5},
        is_active = is_active,
        is_hovered = is_hovered,
        angle_min = real_angle_min,
        angle_max = real_angle_max,
        t = t,
        angle = angle,
        value_changed = value_changed,
    };
}

knob_begin_int :: (label: string, p_value: *s32, v_min: s32, v_max: s32, speed: float, format: string, size: float,
                   flags: Knob_Flags, angle_min: float, angle_max: float) -> Knob_State {
    using ImGui;

    PushID(label);

    width := ifx size > 0.0 then size else GetTextLineHeight() * 4.0;
    PushItemWidth(width);
    BeginGroup();

    if !flags.NoTitle {
        title_size := CalcTextSize(label);
        SetCursorPosX(GetCursorPosX() + max((width - title_size.x) * 0.5, 0.0));
        Text("%", label);
    }

    screen_pos := GetCursorScreenPos();
    _ = InvisibleButton("##knob_btn", .{width, width});

    is_active := IsItemActive();
    is_hovered := IsItemHovered();

    eff_speed := speed;
    if eff_speed == 0.0 eff_speed = max(cast(float) (v_max - v_min) / 250.0, 0.01);

    value_changed := false;
    if is_active {
        io := GetIO();
        delta := knob_pick_drag_delta(io, flags);
        if abs(delta) > 0.0 {
            next := cast(float) p_value.* + delta * eff_speed;
            p_value.* = cast(s32) round(next);
            value_changed = true;
        }
    }

    if flags.AlwaysClamp || flags.Logarithmic {
        p_value.* = clamp(p_value.*, v_min, v_max);
    }

    slider_flags: SliderFlags = .None;
    if flags.AlwaysClamp slider_flags |= .AlwaysClamp;
    if flags.Logarithmic slider_flags |= .Logarithmic;

    if !flags.NoInput {
        if DragInt("##knob_drag", p_value, eff_speed, v_min, v_max, temp_c_string(format), slider_flags) {
            value_changed = true;
        }
    }

    clamped_value := clamp(p_value.*, v_min, v_max);
    t := knob_value_to_t_int(clamped_value, v_min, v_max, flags);

    real_angle_min := ifx angle_min < 0.0 then cast(float) (KNOB_PI * 0.75) else angle_min;
    real_angle_max := ifx angle_max < 0.0 then cast(float) (KNOB_PI * 2.25) else angle_max;
    angle := real_angle_min + (real_angle_max - real_angle_min) * t;

    if flags.ValueTooltip && (is_hovered || is_active) {
        if BeginTooltip() {
            Text("%", tprint(format, p_value.*));
            EndTooltip();
        }
    }

    return .{
        radius = width * 0.5,
        center = .{screen_pos.x + width * 0.5, screen_pos.y + width * 0.5},
        is_active = is_active,
        is_hovered = is_hovered,
        angle_min = real_angle_min,
        angle_max = real_angle_max,
        t = t,
        angle = angle,
        value_changed = value_changed,
    };
}

knob_end :: () {
    using ImGui;
    EndGroup();
    PopItemWidth();
    PopID();
}

knob_pick_drag_delta :: (io: *ImGui.IO, flags: Knob_Flags) -> float {
    if flags.DragHorizontal return io.MouseDelta.x;
    if flags.DragVertical return -io.MouseDelta.y;

    dx := io.MouseDelta.x;
    dy := io.MouseDelta.y;
    if abs(dy) > abs(dx) return -dy;
    return dx;
}

knob_value_to_t_float :: (v: float, v_min: float, v_max: float, flags: Knob_Flags) -> float {
    range := max(v_max - v_min, 0.000001);
    if flags.Logarithmic && v_min > 0.0 && v_max > v_min {
        ln_min := log(v_min);
        ln_max := log(v_max);
        ln_v := log(max(v, v_min));
        return clamp((ln_v - ln_min) / max(ln_max - ln_min, 0.000001), 0.0, 1.0);
    }
    return clamp((v - v_min) / range, 0.0, 1.0);
}

knob_value_to_t_int :: (v: s32, v_min: s32, v_max: s32, flags: Knob_Flags) -> float {
    if flags.Logarithmic && v_min > 0 && v_max > v_min {
        fv := cast(float) v;
        fmin := cast(float) v_min;
        fmax := cast(float) v_max;
        ln_min := log(fmin);
        ln_max := log(fmax);
        ln_v := log(max(fv, fmin));
        return clamp((ln_v - ln_min) / max(ln_max - ln_min, 0.000001), 0.0, 1.0);
    }

    denom := max(cast(float) (v_max - v_min), 1.0);
    return clamp((cast(float) (v - v_min)) / denom, 0.0, 1.0);
}

knob_draw_variant :: (state: Knob_State, variant: Knob_Variant, steps: s32) {
    primary := knob_primary_colors();
    secondary := knob_secondary_colors();
    track := knob_track_colors();

    if variant == {
        case .TICK;
            knob_draw_circle(state, 0.85, secondary, true, 32);
            knob_draw_tick(state, 0.5, 0.85, 0.08, state.angle, primary);
        case .DOT;
            knob_draw_circle(state, 0.85, secondary, true, 32);
            knob_draw_dot(state, 0.12, 0.6, state.angle, primary, 12);
        case .WIPER;
            knob_draw_circle(state, 0.7, secondary, true, 32);
            knob_draw_arc(state, 0.8, 0.41, state.angle_min, state.angle_max, track);
            if state.t > 0.01 knob_draw_arc(state, 0.8, 0.43, state.angle_min, state.angle, primary);
        case .WIPER_ONLY;
            knob_draw_arc(state, 0.8, 0.41, state.angle_min, state.angle_max, track);
            if state.t > 0.01 knob_draw_arc(state, 0.8, 0.43, state.angle_min, state.angle, primary);
        case .WIPER_DOT;
            knob_draw_circle(state, 0.6, secondary, true, 32);
            knob_draw_arc(state, 0.85, 0.41, state.angle_min, state.angle_max, track);
            knob_draw_dot(state, 0.1, 0.85, state.angle, primary, 12);
        case .STEPPED;
            step_count := max(steps, 2);
            for n: 0..step_count - 1 {
                a := cast(float) n / cast(float) (step_count - 1);
                angle := state.angle_min + (state.angle_max - state.angle_min) * a;
                knob_draw_tick(state, 0.7, 0.9, 0.04, angle, primary);
            }
            knob_draw_circle(state, 0.6, secondary, true, 32);
            knob_draw_dot(state, 0.12, 0.4, state.angle, primary, 12);
        case .SPACE;
            knob_draw_circle(state, 0.3 - state.t * 0.1, secondary, true, 16);
            if state.t > 0.01 {
                knob_draw_arc(state, 0.4, 0.15, state.angle_min - 1.0, state.angle - 1.0, primary);
                knob_draw_arc(state, 0.6, 0.15, state.angle_min + 1.0, state.angle + 1.0, primary);
                knob_draw_arc(state, 0.8, 0.15, state.angle_min + 3.0, state.angle + 3.0, primary);
            }
    };
}

knob_draw_dot :: (state: Knob_State, size: float, radius: float, angle: float, colors: Knob_Color_Set, segments: s32) {
    draw := ImGui.GetWindowDrawList();
    dot_size := size * state.radius;
    dot_radius := radius * state.radius;
    p := ImGui.ImVec2.{
        state.center.x + cos(angle) * dot_radius,
        state.center.y + sin(angle) * dot_radius,
    };
    ImGui.ImDrawList.AddCircleFilled(draw, p, dot_size, knob_state_color(state, colors), segments);
}

knob_draw_tick :: (state: Knob_State, start: float, end: float, width: float, angle: float, colors: Knob_Color_Set) {
    draw := ImGui.GetWindowDrawList();
    tick_start := start * state.radius;
    tick_end := end * state.radius;
    c := cos(angle);
    s := sin(angle);

    a := ImGui.ImVec2.{state.center.x + c * tick_end, state.center.y + s * tick_end};
    b := ImGui.ImVec2.{state.center.x + c * tick_start, state.center.y + s * tick_start};
    ImGui.ImDrawList.AddLine(draw, a, b, knob_state_color(state, colors), width * state.radius);
}

knob_draw_circle :: (state: Knob_State, size: float, colors: Knob_Color_Set, _filled: bool, segments: s32) {
    draw := ImGui.GetWindowDrawList();
    circle_radius := size * state.radius;
    ImGui.ImDrawList.AddCircleFilled(draw, state.center, circle_radius, knob_state_color(state, colors), segments);
}

knob_draw_arc :: (state: Knob_State, radius: float, size: float, start_angle: float, end_angle: float, colors: Knob_Color_Set) {
    draw := ImGui.GetWindowDrawList();
    arc_radius := radius * state.radius;
    thickness := max(size * state.radius * 0.5, 1.0);
    col := knob_state_color(state, colors);

    angle_span := end_angle - start_angle;
    seg_count := clamp(cast(s32) (abs(angle_span) * 20.0), 8, 128);
    prev := ImGui.ImVec2.{
        state.center.x + cos(start_angle) * arc_radius,
        state.center.y + sin(start_angle) * arc_radius,
    };

    for i: 1..seg_count {
        t := cast(float) i / cast(float) seg_count;
        a := start_angle + angle_span * t;
        next := ImGui.ImVec2.{
            state.center.x + cos(a) * arc_radius,
            state.center.y + sin(a) * arc_radius,
        };
        ImGui.ImDrawList.AddLine(draw, prev, next, col, thickness);
        prev = next;
    }
}

knob_state_color :: (state: Knob_State, colors: Knob_Color_Set) -> ImGui.ImU32 {
    if state.is_active return colors.active;
    if state.is_hovered return colors.hovered;
    return colors.base;
}

knob_primary_colors :: () -> Knob_Color_Set {
    return .{
        base = ImGui.GetColorU32(.ButtonActive, 1.0),
        hovered = ImGui.GetColorU32(.ButtonHovered, 1.0),
        active = ImGui.GetColorU32(.ButtonHovered, 1.0),
    };
}

knob_secondary_colors :: () -> Knob_Color_Set {
    style := ImGui.GetStyle();
    active_v := style.Colors[ImGui.Col.ButtonActive];
    hovered_v := style.Colors[ImGui.Col.ButtonHovered];

    active_v.x *= 0.5; active_v.y *= 0.5; active_v.z *= 0.5;
    hovered_v.x *= 0.5; hovered_v.y *= 0.5; hovered_v.z *= 0.5;

    return .{
        base = ImGui.ColorConvertFloat4ToU32(active_v),
        hovered = ImGui.ColorConvertFloat4ToU32(hovered_v),
        active = ImGui.ColorConvertFloat4ToU32(hovered_v),
    };
}

knob_track_colors :: () -> Knob_Color_Set {
    c := ImGui.GetColorU32(.Button, 1.0);
    return .{base = c, hovered = c, active = c};
}

ImGui :: #import "ImGui";
