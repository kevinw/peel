// Lightweight port inspired by https://github.com/cmdwtf/imgui_toggle
// Simplified for peel: single toggle style with optional animation.

Toggle_Anim_Slot :: struct {
    id: ImGui.ID;
    used: bool;
    value: float;
}

TOGGLE_ANIM_SLOT_COUNT :: 256;
toggle_anim_slots: [TOGGLE_ANIM_SLOT_COUNT] Toggle_Anim_Slot;

// Toggle widget similar to a checkbox, but rendered as a switch.
// Returns true when the boolean value changes.
toggle :: (label: string, value: *bool, size: ImGui.ImVec2 = .{0.0, 0.0}, animated := true,
           animation_duration: float = 0.10) -> bool {
    using ImGui;

    if !value return false;

    PushID(label);
    defer PopID();

    h := ifx size.y > 0.0 then size.y else GetFrameHeight();
    w := ifx size.x > 0.0 then size.x else h * 1.6180339;

    _ = InvisibleButton("##toggle", .{w, h});

    changed := false;
    if IsItemClicked(.Left) {
        value.* = !value.*;
        changed = true;
    }

    bb_min := GetItemRectMin();
    bb_max := GetItemRectMax();

    id := GetID("##toggle");
    anim := get_toggle_anim_slot(id);
    target := ifx value.* then 1.0 else 0.0;

    if !animated || animation_duration <= 0.0 {
        anim.value = target;
    } else {
        io := GetIO();
        step := io.DeltaTime / max(animation_duration, 0.0001);
        if target > anim.value {
            anim.value = min(anim.value + step, target);
        } else {
            anim.value = max(anim.value - step, target);
        }
    }

    hovered := IsItemHovered();

    frame_off := GetColorU32(.FrameBg, ifx hovered then 1.12 else 1.0);
    frame_on  := GetColorU32(.ButtonActive, ifx hovered then 1.08 else 1.0);
    knob_col  := GetColorU32(.Text, 1.0);

    draw := GetWindowDrawList();

    t := clamp(anim.value, 0.0, 1.0);
    frame_col := blend_color(frame_off, frame_on, t);

    rounding := h * 0.5;
    ImGui.ImDrawList.AddRectFilled(draw, bb_min, bb_max, frame_col, rounding);

    pad := max(h * 0.10, 1.0);
    r := (h - 2.0 * pad) * 0.5;
    cx0 := bb_min.x + pad + r;
    cx1 := bb_max.x - pad - r;
    cx := cx0 + (cx1 - cx0) * t;
    cy := bb_min.y + h * 0.5;

    ImGui.ImDrawList.AddCircleFilled(draw, .{cx, cy}, r, knob_col, 20);

    if label.count > 0 {
        SameLine(0.0, GetStyle().ItemInnerSpacing.x);
        Text("%", label);
    }

    return changed;
}

#scope_file
get_toggle_anim_slot :: (id: ImGui.ID) -> *Toggle_Anim_Slot {
    // First try exact match.
    for i: 0..TOGGLE_ANIM_SLOT_COUNT-1 {
        slot := *toggle_anim_slots[i];
        if slot.used && slot.id == id return slot;
    }

    // Then claim an unused slot.
    for i: 0..TOGGLE_ANIM_SLOT_COUNT-1 {
        slot := *toggle_anim_slots[i];
        if !slot.used {
            slot.used = true;
            slot.id = id;
            slot.value = 0.0;
            return slot;
        }
    }

    // Fallback: simple deterministic replacement.
    idx := cast(s32) (id % TOGGLE_ANIM_SLOT_COUNT);
    slot := *toggle_anim_slots[idx];
    slot.used = true;
    slot.id = id;
    return slot;
}

blend_color :: (a: ImGui.ImU32, b: ImGui.ImU32, t: float) -> ImGui.ImU32 {
    av := ImGui.ColorConvertU32ToFloat4(a);
    bv := ImGui.ColorConvertU32ToFloat4(b);

    tt := clamp(t, 0.0, 1.0);

    out := ImGui.ImVec4.{
        av.x + (bv.x - av.x) * tt,
        av.y + (bv.y - av.y) * tt,
        av.z + (bv.z - av.z) * tt,
        av.w + (bv.w - av.w) * tt,
    };

    return ImGui.ColorConvertFloat4ToU32(out);
}

ImGui :: #import "ImGui";
