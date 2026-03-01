#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

SAND_SIM_WIDTH  :: 360;
SAND_SIM_HEIGHT :: 220;
SAND_CELL_COUNT :: SAND_SIM_WIDTH * SAND_SIM_HEIGHT;

SAND_MAT_EMPTY :: cast(u32) 0;
SAND_MAT_SAND  :: cast(u32) 1;
SAND_MAT_WATER :: cast(u32) 2;
SAND_MAT_LAVA  :: cast(u32) 3;
SAND_MAT_STEAM :: cast(u32) 4;
SAND_MAT_STONE :: cast(u32) 5;
SAND_MAT_GLASS :: cast(u32) 6;
SAND_MAT_ICE   :: cast(u32) 7;

Sand_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Sand_Compute_Control :: struct {
    cursor_uv: Vector2;
    brush_radius_px: float;
    use_b_as_src: u32;
    brush_active: u32;
    brush_element: u32;
    frame_index: u32;
}

Sand_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Sand_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Sand_Fragment_In :: struct {
    uv: Vector2;
}

sand_cell_index :: (x: u32, y: u32) -> u32 {
    return y * SAND_SIM_WIDTH + x;
}

sand_wrap_index :: (coord: s64, limit: u32) -> u32 {
    l := cast(s64) limit;
    c := coord % l;
    if c < 0 c += l;
    return cast(u32) c;
}

sand_sample_wrapped :: (state: *Vector4, src_offset: u32, x: s64, y: s64) -> Vector4 {
    sx := sand_wrap_index(x, SAND_SIM_WIDTH);
    sy := sand_wrap_index(y, SAND_SIM_HEIGHT);
    return state[src_offset + sand_cell_index(sx, sy)];
}

sand_material_of :: (cell: Vector4) -> u32 {
    m := cast(u32) cell.x;
    if m > SAND_MAT_ICE return SAND_MAT_EMPTY;
    return m;
}

sand_default_temp_for_material :: (mat: u32) -> float {
    if mat == SAND_MAT_LAVA return 1.0;
    if mat == SAND_MAT_STEAM return 0.82;
    if mat == SAND_MAT_WATER return 0.18;
    if mat == SAND_MAT_SAND return 0.34;
    if mat == SAND_MAT_GLASS return 0.55;
    if mat == SAND_MAT_STONE return 0.22;
    if mat == SAND_MAT_ICE return 0.05;
    return 0.08;
}

sand_material_priority :: (mat: u32) -> u32 {
    if mat == SAND_MAT_LAVA return 6;
    if mat == SAND_MAT_SAND return 5;
    if mat == SAND_MAT_WATER return 4;
    if mat == SAND_MAT_STONE return 3;
    if mat == SAND_MAT_GLASS return 2;
    if mat == SAND_MAT_ICE return 2;
    if mat == SAND_MAT_STEAM return 1;
    return 0;
}

sand_is_passable_for :: (mover: u32, target: u32) -> bool {
    if mover == SAND_MAT_SAND || mover == SAND_MAT_LAVA {
        return target == SAND_MAT_EMPTY || target == SAND_MAT_WATER || target == SAND_MAT_STEAM;
    }
    if mover == SAND_MAT_WATER {
        return target == SAND_MAT_EMPTY || target == SAND_MAT_STEAM;
    }
    if mover == SAND_MAT_STEAM {
        return target == SAND_MAT_EMPTY || target == SAND_MAT_WATER;
    }
    return false;
}

sand_heat_diffusion :: (center: float, up: float, down: float, left: float, right: float) -> float {
    avg := (up + down + left + right) * 0.25;
    return mix(center, avg, 0.18);
}

sand_step_compute :: (using in: Sand_Compute_In, state: *Vector4, control: *Sand_Compute_Control) {
    if thread_id.x >= SAND_CELL_COUNT return;

    src_offset: u32 = 0;
    dst_offset: u32 = SAND_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = SAND_CELL_COUNT;
        dst_offset = 0;
    }

    i := thread_id.x;
    x := i % SAND_SIM_WIDTH;
    y := i / SAND_SIM_WIDTH;
    sx := cast(s64) x;
    sy := cast(s64) y;

    center := state[src_offset + i];
    up_v := sand_sample_wrapped(state, src_offset, sx, sy - 1);
    down_v := sand_sample_wrapped(state, src_offset, sx, sy + 1);
    left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy);
    right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy);
    up_left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy - 1);
    up_right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy - 1);
    down_left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy + 1);
    down_right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy + 1);

    center_m := sand_material_of(center);
    up_m := sand_material_of(up_v);
    down_m := sand_material_of(down_v);
    left_m := sand_material_of(left_v);
    right_m := sand_material_of(right_v);
    up_left_m := sand_material_of(up_left_v);
    up_right_m := sand_material_of(up_right_v);
    down_left_m := sand_material_of(down_left_v);
    down_right_m := sand_material_of(down_right_v);

    frame_hash := (x * 92837111 + y * 689287499 + control[0].frame_index * 283923481);
    rand_bit := frame_hash & 1;

    // Determine if this cell material moves out this step.
    self_moves_out := false;
    if center_m == SAND_MAT_SAND || center_m == SAND_MAT_LAVA {
        if sand_is_passable_for(center_m, down_m) self_moves_out = true;
    } else if center_m == SAND_MAT_WATER {
        if sand_is_passable_for(center_m, down_m) self_moves_out = true;
        else if rand_bit == 0 && sand_is_passable_for(center_m, left_m) self_moves_out = true;
        else if rand_bit == 1 && sand_is_passable_for(center_m, right_m) self_moves_out = true;
    } else if center_m == SAND_MAT_STEAM {
        if sand_is_passable_for(center_m, up_m) self_moves_out = true;
        else if rand_bit == 0 && sand_is_passable_for(center_m, left_m) self_moves_out = true;
        else if rand_bit == 1 && sand_is_passable_for(center_m, right_m) self_moves_out = true;
    }

    next_mat := center_m;
    next_temp := center.y;
    if self_moves_out {
        next_mat = SAND_MAT_EMPTY;
        next_temp = sand_default_temp_for_material(SAND_MAT_EMPTY);
    }

    // Incoming from above (sand/water/lava fall).
    if up_m == SAND_MAT_SAND || up_m == SAND_MAT_WATER || up_m == SAND_MAT_LAVA {
        candidate_mat := sand_material_of(up_v);
        // Conservation guard: don't let sand/lava overwrite water unless that
        // water cell already moved out this step.
        if center_m == SAND_MAT_WATER && !self_moves_out {
            if candidate_mat == SAND_MAT_SAND || candidate_mat == SAND_MAT_LAVA {
                candidate_mat = SAND_MAT_EMPTY;
            }
        }
        // Donor eligibility is evaluated against OLD center material to avoid
        // duplication when this cell moves out in the same step.
        if candidate_mat != SAND_MAT_EMPTY && sand_is_passable_for(candidate_mat, center_m) {
            if sand_material_priority(candidate_mat) > sand_material_priority(next_mat) {
                next_mat = candidate_mat;
                next_temp = up_v.y;
            }
        }
    }

    // Incoming from below (steam rises).
    if down_m == SAND_MAT_STEAM && sand_is_passable_for(SAND_MAT_STEAM, center_m) {
        if sand_material_priority(SAND_MAT_STEAM) > sand_material_priority(next_mat) {
            next_mat = SAND_MAT_STEAM;
            next_temp = down_v.y;
        }
    }

    // Incoming from left/right for lateral water/steam flow.
    left_rand := ((frame_hash >> 1) & 1) == 1;
    right_rand := ((frame_hash >> 2) & 1) == 0;
    if left_m == SAND_MAT_WATER {
        left_down_open := sand_is_passable_for(SAND_MAT_WATER, down_left_m);
        if !left_down_open && left_rand && sand_is_passable_for(SAND_MAT_WATER, center_m) {
            candidate_mat := sand_material_of(left_v);
            if candidate_mat != SAND_MAT_EMPTY {
                if sand_material_priority(candidate_mat) > sand_material_priority(next_mat) {
                    next_mat = candidate_mat;
                    next_temp = left_v.y;
                }
            }
        }
    } else if left_m == SAND_MAT_STEAM {
        left_up_open := sand_is_passable_for(SAND_MAT_STEAM, up_left_m);
        if !left_up_open && left_rand && sand_is_passable_for(SAND_MAT_STEAM, center_m) {
            candidate_mat := sand_material_of(left_v);
            if candidate_mat != SAND_MAT_EMPTY {
                if sand_material_priority(candidate_mat) > sand_material_priority(next_mat) {
                    next_mat = candidate_mat;
                    next_temp = left_v.y;
                }
            }
        }
    }

    if right_m == SAND_MAT_WATER {
        right_down_open := sand_is_passable_for(SAND_MAT_WATER, down_right_m);
        if !right_down_open && right_rand && sand_is_passable_for(SAND_MAT_WATER, center_m) {
            candidate_mat := sand_material_of(right_v);
            if candidate_mat != SAND_MAT_EMPTY {
                if sand_material_priority(candidate_mat) > sand_material_priority(next_mat) {
                    next_mat = candidate_mat;
                    next_temp = right_v.y;
                }
            }
        }
    } else if right_m == SAND_MAT_STEAM {
        right_up_open := sand_is_passable_for(SAND_MAT_STEAM, up_right_m);
        if !right_up_open && right_rand && sand_is_passable_for(SAND_MAT_STEAM, center_m) {
            candidate_mat := sand_material_of(right_v);
            if candidate_mat != SAND_MAT_EMPTY {
                if sand_material_priority(candidate_mat) > sand_material_priority(next_mat) {
                    next_mat = candidate_mat;
                    next_temp = right_v.y;
                }
            }
        }
    }

    next_temp = sand_heat_diffusion(next_temp, up_v.y, down_v.y, left_v.y, right_v.y);
    adjacent_lava := (up_m == SAND_MAT_LAVA) || (down_m == SAND_MAT_LAVA) || (left_m == SAND_MAT_LAVA) || (right_m == SAND_MAT_LAVA);
    adjacent_water_count: u32 = 0;
    adjacent_ice := (up_m == SAND_MAT_ICE) || (down_m == SAND_MAT_ICE) || (left_m == SAND_MAT_ICE) || (right_m == SAND_MAT_ICE);
    if up_m == SAND_MAT_WATER adjacent_water_count += 1;
    if down_m == SAND_MAT_WATER adjacent_water_count += 1;
    if left_m == SAND_MAT_WATER adjacent_water_count += 1;
    if right_m == SAND_MAT_WATER adjacent_water_count += 1;

    if next_mat == SAND_MAT_SAND && adjacent_lava {
        next_mat = SAND_MAT_GLASS;
        next_temp = max(next_temp, 0.62);
    } else if next_mat == SAND_MAT_WATER && adjacent_lava {
        next_mat = SAND_MAT_STEAM;
        next_temp = max(next_temp, 0.86);
    } else if next_mat == SAND_MAT_LAVA && adjacent_water_count >= 2 {
        next_mat = SAND_MAT_STONE;
        next_temp = 0.30;
    } else if next_mat == SAND_MAT_STEAM && next_temp < 0.28 {
        next_mat = SAND_MAT_WATER;
        next_temp = 0.22;
    } else if next_mat == SAND_MAT_ICE && adjacent_lava {
        next_mat = SAND_MAT_WATER;
        next_temp = 0.20;
    } else if next_mat == SAND_MAT_WATER && adjacent_ice && next_temp < 0.14 {
        next_mat = SAND_MAT_ICE;
        next_temp = 0.06;
    }

    target_temp := sand_default_temp_for_material(next_mat);
    next_temp = mix(next_temp, target_temp, 0.035);
    next_temp = clamp(next_temp, 0.0, 1.0);

    // Brush paint.
    if control[0].brush_active != 0 {
        cursor_x := control[0].cursor_uv.x * cast(float) SAND_SIM_WIDTH;
        cursor_y := control[0].cursor_uv.y * cast(float) SAND_SIM_HEIGHT;
        cell_x := cast(float) x + 0.5;
        cell_y := cast(float) y + 0.5;
        dx := cell_x - cursor_x;
        dy := cell_y - cursor_y;
        dist2 := dx * dx + dy * dy;
        radius := control[0].brush_radius_px;
        if dist2 < radius * radius {
            painted := control[0].brush_element;
            next_mat = painted;
            next_temp = sand_default_temp_for_material(next_mat);
        }
    }

    state[dst_offset + i] = .{cast(float) next_mat, next_temp, 0.0, 0.0};
} @compute_shader

sand_vertex_corner :: (vid: u32) -> Vector2 {
    if vid == 0 return .{-1, -1};
    if vid == 1 return .{+1, -1};
    if vid == 2 return .{+1, +1};
    if vid == 3 return .{-1, -1};
    if vid == 4 return .{+1, +1};
    return .{-1, +1};
}

sand_vertex_main :: (using in: Sand_Vertex_In, state: *[SAND_CELL_COUNT] Vector4) -> Sand_Vertex_Out {
    using out: Sand_Vertex_Out;
    _ = state;
    pos := sand_vertex_corner(vertex_id);
    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

sand_color_from_cell :: (mat: u32, temp: float) -> Vector3 {
    if mat == SAND_MAT_SAND {
        cool := Vector3.{0.68, 0.60, 0.34};
        hot := Vector3.{0.88, 0.72, 0.38};
        t := clamp((temp - 0.20) / 0.60, 0.0, 1.0);
        return .{mix(cool.x, hot.x, t), mix(cool.y, hot.y, t), mix(cool.z, hot.z, t)};
    }
    if mat == SAND_MAT_WATER {
        cold := Vector3.{0.08, 0.32, 0.68};
        warm := Vector3.{0.22, 0.56, 0.88};
        t := clamp(temp * 1.2, 0.0, 1.0);
        return .{mix(cold.x, warm.x, t), mix(cold.y, warm.y, t), mix(cold.z, warm.z, t)};
    }
    if mat == SAND_MAT_LAVA {
        low := Vector3.{0.42, 0.05, 0.01};
        high := Vector3.{1.00, 0.50, 0.02};
        t := clamp((temp - 0.20) / 0.80, 0.0, 1.0);
        return .{mix(low.x, high.x, t), mix(low.y, high.y, t), mix(low.z, high.z, t)};
    }
    if mat == SAND_MAT_STEAM {
        return Vector3.{0.74, 0.78, 0.82} * (0.5 + temp * 0.4);
    }
    if mat == SAND_MAT_STONE {
        return Vector3.{0.34, 0.34, 0.36};
    }
    if mat == SAND_MAT_GLASS {
        return Vector3.{0.70, 0.88, 0.90};
    }
    if mat == SAND_MAT_ICE {
        return Vector3.{0.78, 0.92, 1.00};
    }
    return Vector3.{0.03, 0.03, 0.05};
}

sand_fragment_main :: (using in: Sand_Fragment_In, state: *[SAND_CELL_COUNT] Vector4) -> struct { out_color: Vector4; } {
    sample_v := 1.0 - uv.y;
    px := cast(u32) floor(uv.x * cast(float) SAND_SIM_WIDTH);
    py := cast(u32) floor(sample_v * cast(float) SAND_SIM_HEIGHT);
    if px >= SAND_SIM_WIDTH px = SAND_SIM_WIDTH - 1;
    if py >= SAND_SIM_HEIGHT py = SAND_SIM_HEIGHT - 1;

    idx := sand_cell_index(px, py);
    cell := (cast(*Vector4) state)[idx];
    mat := sand_material_of(cell);
    temp := clamp(cell.y, 0.0, 1.0);
    color := sand_color_from_cell(mat, temp);

    // Subtle grid shading so cell motion reads clearly.
    gx := fract(uv.x * cast(float) SAND_SIM_WIDTH);
    gy := fract(sample_v * cast(float) SAND_SIM_HEIGHT);
    edge := min(min(gx, 1.0 - gx), min(gy, 1.0 - gy));
    shade := smoothstep(0.0, 0.12, edge) * 0.92 + 0.08;
    color *= shade;

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader
