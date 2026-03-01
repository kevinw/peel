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

SAND_LAVA_LATERAL_CHANCE_MASK_SURFACE :: cast(u32) 31;     // 1 in (mask+1): 3.125%
SAND_LAVA_LATERAL_CHANCE_MASK_STACKED :: cast(u32) 15;     // 1 in (mask+1): 6.25%
SAND_STEAM_SIDE_CHANCE_MASK_WHEN_UP_OPEN :: cast(u32) 1;   // 1 in (mask+1): 50%

sand_frame_hash :: (x: u32, y: u32, frame_index: u32) -> u32 {
    return x * 92837111 + y * 689287499 + frame_index * 283923481;
}

sand_hash_mix :: (v: u32) -> u32 {
    x := v;
    x ^= x >> 16;
    x *= cast(u32) 0x7feb352d;
    x ^= x >> 15;
    x *= cast(u32) 0x846ca68b;
    x ^= x >> 16;
    return x;
}

sand_lava_lateral_chance_mask :: (up_material: u32) -> u32 {
    if up_material == SAND_MAT_LAVA return SAND_LAVA_LATERAL_CHANCE_MASK_STACKED;
    return SAND_LAVA_LATERAL_CHANCE_MASK_SURFACE;
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
    if mover == SAND_MAT_SAND {
        return target == SAND_MAT_EMPTY || target == SAND_MAT_STEAM || target == SAND_MAT_WATER;
    }
    if mover == SAND_MAT_LAVA {
        // Note: allowing sand/lava into water requires explicit swap/eviction
        // handling; without that, water can be dropped. Keep it conservative.
        return target == SAND_MAT_EMPTY || target == SAND_MAT_STEAM;
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

sand_pick_candidate :: (candidate: Vector4, old_center_mat: u32, io_mat: *u32, io_temp: *float, io_aux: *float) {
    candidate_mat := sand_material_of(candidate);
    if candidate_mat == SAND_MAT_EMPTY return;
    if !sand_is_passable_for(candidate_mat, old_center_mat) return;
    if sand_material_priority(candidate_mat) > sand_material_priority(io_mat.*) {
        io_mat.* = candidate_mat;
        io_temp.* = candidate.y;
        io_aux.* = candidate.z;
    }
}

sand_apply_reactions :: (up_m: u32, down_m: u32, left_m: u32, right_m: u32, io_mat: *u32, io_temp: *float) {
    adjacent_lava := (up_m == SAND_MAT_LAVA) || (down_m == SAND_MAT_LAVA) || (left_m == SAND_MAT_LAVA) || (right_m == SAND_MAT_LAVA);
    adjacent_water_count: u32 = 0;
    adjacent_ice := (up_m == SAND_MAT_ICE) || (down_m == SAND_MAT_ICE) || (left_m == SAND_MAT_ICE) || (right_m == SAND_MAT_ICE);
    if up_m == SAND_MAT_WATER adjacent_water_count += 1;
    if down_m == SAND_MAT_WATER adjacent_water_count += 1;
    if left_m == SAND_MAT_WATER adjacent_water_count += 1;
    if right_m == SAND_MAT_WATER adjacent_water_count += 1;

    if io_mat.* == SAND_MAT_SAND && adjacent_lava {
        io_mat.* = SAND_MAT_GLASS;
        io_temp.* = max(io_temp.*, 0.62);
    } else if io_mat.* == SAND_MAT_WATER && adjacent_lava {
        io_mat.* = SAND_MAT_STEAM;
        io_temp.* = max(io_temp.*, 0.86);
    } else if io_mat.* == SAND_MAT_LAVA && adjacent_water_count >= 2 {
        io_mat.* = SAND_MAT_STONE;
        io_temp.* = 0.30;
    } else if io_mat.* == SAND_MAT_STEAM && io_temp.* < 0.12 && !adjacent_lava && adjacent_water_count >= 2 {
        io_mat.* = SAND_MAT_WATER;
        io_temp.* = 0.22;
    } else if io_mat.* == SAND_MAT_ICE && adjacent_lava {
        io_mat.* = SAND_MAT_WATER;
        io_temp.* = 0.20;
    } else if io_mat.* == SAND_MAT_WATER && adjacent_ice && io_temp.* < 0.14 {
        io_mat.* = SAND_MAT_ICE;
        io_temp.* = 0.06;
    }
}

sand_plan_moves_compute :: (using in: Sand_Compute_In, state: *Vector4, move_targets: *u32, control: *Sand_Compute_Control) {
    if thread_id.x >= SAND_CELL_COUNT return;

    src_offset: u32 = 0;
    dst_offset: u32 = SAND_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = SAND_CELL_COUNT;
        dst_offset = 0;
    }
    _ = dst_offset;

    i := thread_id.x;
    x := i % SAND_SIM_WIDTH;
    y := i / SAND_SIM_WIDTH;
    sx := cast(s64) x;
    sy := cast(s64) y;

    center := state[src_offset + i];
    up_v := sand_sample_wrapped(state, src_offset, sx, sy - 1);
    down_v := sand_sample_wrapped(state, src_offset, sx, sy + 1);
    down_down_v := sand_sample_wrapped(state, src_offset, sx, sy + 2);
    left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy);
    right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy);
    up_left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy - 1);
    up_right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy - 1);
    down_left_v := sand_sample_wrapped(state, src_offset, sx - 1, sy + 1);
    down_right_v := sand_sample_wrapped(state, src_offset, sx + 1, sy + 1);

    center_m := sand_material_of(center);
    up_m := sand_material_of(up_v);
    down_m := sand_material_of(down_v);
    down_down_m := sand_material_of(down_down_v);
    left_m := sand_material_of(left_v);
    right_m := sand_material_of(right_v);
    up_left_m := sand_material_of(up_left_v);
    up_right_m := sand_material_of(up_right_v);
    down_left_m := sand_material_of(down_left_v);
    down_right_m := sand_material_of(down_right_v);

    frame_hash := sand_hash_mix(sand_frame_hash(x, y, control[0].frame_index));
    rand_bit := frame_hash & 1;
    target_x := x;
    target_y := y;

    if center_m == SAND_MAT_SAND || center_m == SAND_MAT_LAVA {
        if sand_is_passable_for(center_m, down_m) {
            target_y = sand_wrap_index(sy + 1, SAND_SIM_HEIGHT);
        } else if center_m == SAND_MAT_LAVA {
            lava_mask := sand_lava_lateral_chance_mask(up_m);
            lava_can_spread := (frame_hash & lava_mask) == 0;
            if lava_can_spread {
                if rand_bit == 0 && sand_is_passable_for(center_m, left_m) {
                    target_x = sand_wrap_index(sx - 1, SAND_SIM_WIDTH);
                } else if rand_bit == 1 && sand_is_passable_for(center_m, right_m) {
                    target_x = sand_wrap_index(sx + 1, SAND_SIM_WIDTH);
                }
            }
        }
    } else if center_m == SAND_MAT_WATER {
        down_open := sand_is_passable_for(center_m, down_m);

        if down_open {
            target_y = sand_wrap_index(sy + 1, SAND_SIM_HEIGHT);
        } else {
            // Try both sides in randomized order for faster leveling.
            if rand_bit == 0 {
                if sand_is_passable_for(center_m, left_m) {
                    target_x = sand_wrap_index(sx - 1, SAND_SIM_WIDTH);
                } else if sand_is_passable_for(center_m, right_m) {
                    target_x = sand_wrap_index(sx + 1, SAND_SIM_WIDTH);
                }
            } else {
                if sand_is_passable_for(center_m, right_m) {
                    target_x = sand_wrap_index(sx + 1, SAND_SIM_WIDTH);
                } else if sand_is_passable_for(center_m, left_m) {
                    target_x = sand_wrap_index(sx - 1, SAND_SIM_WIDTH);
                }
            }
        }
    } else if center_m == SAND_MAT_STEAM {
        up_passable := (up_m == SAND_MAT_EMPTY) || (up_m == SAND_MAT_WATER) || (up_m == SAND_MAT_LAVA);
        // Always allow vertical swap through lava.
        if up_m == SAND_MAT_LAVA {
            target_y = sand_wrap_index(sy - 1, SAND_SIM_HEIGHT);
        } else
        if up_passable {
            prefer_side := ((frame_hash >> 4) & SAND_STEAM_SIDE_CHANCE_MASK_WHEN_UP_OPEN) == 0;
            if prefer_side {
                if rand_bit == 0 && sand_is_passable_for(center_m, left_m) {
                    target_x = sand_wrap_index(sx - 1, SAND_SIM_WIDTH);
                } else if rand_bit == 1 && sand_is_passable_for(center_m, right_m) {
                    target_x = sand_wrap_index(sx + 1, SAND_SIM_WIDTH);
                } else {
                    target_y = sand_wrap_index(sy - 1, SAND_SIM_HEIGHT);
                }
            } else {
                target_y = sand_wrap_index(sy - 1, SAND_SIM_HEIGHT);
            }
        } else if rand_bit == 0 && sand_is_passable_for(center_m, left_m) {
            target_x = sand_wrap_index(sx - 1, SAND_SIM_WIDTH);
        } else if rand_bit == 1 && sand_is_passable_for(center_m, right_m) {
            target_x = sand_wrap_index(sx + 1, SAND_SIM_WIDTH);
        }
    }

    move_targets[i] = sand_cell_index(target_x, target_y);
} @compute_shader

sand_resolve_compute :: (using in: Sand_Compute_In, state: *Vector4, move_targets: *u32, control: *Sand_Compute_Control) {
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
    up_i := sand_cell_index(x, sand_wrap_index(sy - 1, SAND_SIM_HEIGHT));
    down_i := sand_cell_index(x, sand_wrap_index(sy + 1, SAND_SIM_HEIGHT));
    left_i := sand_cell_index(sand_wrap_index(sx - 1, SAND_SIM_WIDTH), y);
    right_i := sand_cell_index(sand_wrap_index(sx + 1, SAND_SIM_WIDTH), y);

    up_v := state[src_offset + up_i];
    down_v := state[src_offset + down_i];
    left_v := state[src_offset + left_i];
    right_v := state[src_offset + right_i];

    up_m := sand_material_of(up_v);
    down_m := sand_material_of(down_v);
    left_m := sand_material_of(left_v);
    right_m := sand_material_of(right_v);

    frame_hash := sand_hash_mix(sand_frame_hash(x, y, control[0].frame_index));

    source_stays := false;
    source_won_target := false;
    source_target: u32 = i;
    source_target_center: Vector4 = center;
    center_m := sand_material_of(center);
    if center_m != SAND_MAT_EMPTY {
        source_target = move_targets[i];
        if source_target == i {
            source_stays = true;
            source_won_target = true;
        } else {
            tx := source_target % SAND_SIM_WIDTH;
            ty := source_target / SAND_SIM_WIDTH;
            tsx := cast(s64) tx;
            tsy := cast(s64) ty;

            t_up_i := sand_cell_index(tx, sand_wrap_index(tsy - 1, SAND_SIM_HEIGHT));
            t_down_i := sand_cell_index(tx, sand_wrap_index(tsy + 1, SAND_SIM_HEIGHT));
            t_left_i := sand_cell_index(sand_wrap_index(tsx - 1, SAND_SIM_WIDTH), ty);
            t_right_i := sand_cell_index(sand_wrap_index(tsx + 1, SAND_SIM_WIDTH), ty);
            target_hash := sand_hash_mix(sand_frame_hash(tx, ty, control[0].frame_index));
            source_target_center = state[src_offset + source_target];

            has_target_winner := false;
            target_best_priority: u32 = 0;
            target_best_tie: u32 = 0;
            target_best_src: u32 = source_target;

            if move_targets[source_target] == source_target {
                src_cell := state[src_offset + source_target];
                src_mat := sand_material_of(src_cell);
                if src_mat != SAND_MAT_EMPTY {
                    priority := sand_material_priority(src_mat);
                    tie := sand_hash_mix(target_hash ^ source_target ^ cast(u32) 0xa511e9b3);
                    has_target_winner = true;
                    target_best_priority = priority;
                    target_best_tie = tie;
                    target_best_src = source_target;
                }
            }
            if move_targets[t_up_i] == source_target {
                src_cell := state[src_offset + t_up_i];
                src_mat := sand_material_of(src_cell);
                if src_mat != SAND_MAT_EMPTY {
                    priority := sand_material_priority(src_mat);
                    tie := sand_hash_mix(target_hash ^ t_up_i ^ cast(u32) 0xa511e9b3);
                    if !has_target_winner || priority > target_best_priority || (priority == target_best_priority && tie > target_best_tie) {
                        has_target_winner = true;
                        target_best_priority = priority;
                        target_best_tie = tie;
                        target_best_src = t_up_i;
                    }
                }
            }
            if move_targets[t_down_i] == source_target {
                src_cell := state[src_offset + t_down_i];
                src_mat := sand_material_of(src_cell);
                if src_mat != SAND_MAT_EMPTY {
                    priority := sand_material_priority(src_mat);
                    tie := sand_hash_mix(target_hash ^ t_down_i ^ cast(u32) 0xa511e9b3);
                    if !has_target_winner || priority > target_best_priority || (priority == target_best_priority && tie > target_best_tie) {
                        has_target_winner = true;
                        target_best_priority = priority;
                        target_best_tie = tie;
                        target_best_src = t_down_i;
                    }
                }
            }
            if move_targets[t_left_i] == source_target {
                src_cell := state[src_offset + t_left_i];
                src_mat := sand_material_of(src_cell);
                if src_mat != SAND_MAT_EMPTY {
                    priority := sand_material_priority(src_mat);
                    tie := sand_hash_mix(target_hash ^ t_left_i ^ cast(u32) 0xa511e9b3);
                    if !has_target_winner || priority > target_best_priority || (priority == target_best_priority && tie > target_best_tie) {
                        has_target_winner = true;
                        target_best_priority = priority;
                        target_best_tie = tie;
                        target_best_src = t_left_i;
                    }
                }
            }
            if move_targets[t_right_i] == source_target {
                src_cell := state[src_offset + t_right_i];
                src_mat := sand_material_of(src_cell);
                if src_mat != SAND_MAT_EMPTY {
                    priority := sand_material_priority(src_mat);
                    tie := sand_hash_mix(target_hash ^ t_right_i ^ cast(u32) 0xa511e9b3);
                    if !has_target_winner || priority > target_best_priority || (priority == target_best_priority && tie > target_best_tie) {
                        has_target_winner = true;
                        target_best_priority = priority;
                        target_best_tie = tie;
                        target_best_src = t_right_i;
                    }
                }
            }

            source_won_target = has_target_winner && target_best_src == i;
            if !source_won_target {
                source_stays = true;
            }
        }
    }

    has_candidate := false;
    best_priority: u32 = 0;
    best_tie: u32 = 0;
    best_src: u32 = i;

    if move_targets[i] == i {
        src_cell := state[src_offset + i];
        src_mat := sand_material_of(src_cell);
        if src_mat != SAND_MAT_EMPTY {
            priority := sand_material_priority(src_mat);
            tie := sand_hash_mix(frame_hash ^ i ^ cast(u32) 0xa511e9b3);
            has_candidate = true;
            best_priority = priority;
            best_tie = tie;
            best_src = i;
        }
    }
    if move_targets[up_i] == i {
        src_cell := state[src_offset + up_i];
        src_mat := sand_material_of(src_cell);
        if src_mat != SAND_MAT_EMPTY {
            priority := sand_material_priority(src_mat);
            tie := sand_hash_mix(frame_hash ^ up_i ^ cast(u32) 0xa511e9b3);
            if !has_candidate || priority > best_priority || (priority == best_priority && tie > best_tie) {
                has_candidate = true;
                best_priority = priority;
                best_tie = tie;
                best_src = up_i;
            }
        }
    }
    if move_targets[down_i] == i {
        src_cell := state[src_offset + down_i];
        src_mat := sand_material_of(src_cell);
        if src_mat != SAND_MAT_EMPTY {
            priority := sand_material_priority(src_mat);
            tie := sand_hash_mix(frame_hash ^ down_i ^ cast(u32) 0xa511e9b3);
            if !has_candidate || priority > best_priority || (priority == best_priority && tie > best_tie) {
                has_candidate = true;
                best_priority = priority;
                best_tie = tie;
                best_src = down_i;
            }
        }
    }
    if move_targets[left_i] == i {
        src_cell := state[src_offset + left_i];
        src_mat := sand_material_of(src_cell);
        if src_mat != SAND_MAT_EMPTY {
            priority := sand_material_priority(src_mat);
            tie := sand_hash_mix(frame_hash ^ left_i ^ cast(u32) 0xa511e9b3);
            if !has_candidate || priority > best_priority || (priority == best_priority && tie > best_tie) {
                has_candidate = true;
                best_priority = priority;
                best_tie = tie;
                best_src = left_i;
            }
        }
    }
    if move_targets[right_i] == i {
        src_cell := state[src_offset + right_i];
        src_mat := sand_material_of(src_cell);
        if src_mat != SAND_MAT_EMPTY {
            priority := sand_material_priority(src_mat);
            tie := sand_hash_mix(frame_hash ^ right_i ^ cast(u32) 0xa511e9b3);
            if !has_candidate || priority > best_priority || (priority == best_priority && tie > best_tie) {
                has_candidate = true;
                best_priority = priority;
                best_tie = tie;
                best_src = right_i;
            }
        }
    }

    next_mat := SAND_MAT_EMPTY;
    next_temp := sand_default_temp_for_material(SAND_MAT_EMPTY);
    next_aux: float = 0.0;
    has_incoming_winner := has_candidate && best_src != i;
    if source_won_target && center_m == SAND_MAT_SAND {
        // Explicit vertical swap: sand falling into water pulls that water up.
        source_target_m := sand_material_of(source_target_center);
        if source_target == down_i && source_target_m == SAND_MAT_WATER {
            next_mat = SAND_MAT_WATER;
            next_temp = source_target_center.y;
            next_aux = source_target_center.z;
        } else if has_incoming_winner {
            src_cell := state[src_offset + best_src];
            next_mat = sand_material_of(src_cell);
            next_temp = src_cell.y;
            next_aux = src_cell.z;
        } else if source_stays {
            next_mat = sand_material_of(center);
            next_temp = center.y;
            next_aux = center.z;
        } else if has_candidate {
            src_cell := state[src_offset + best_src];
            next_mat = sand_material_of(src_cell);
            next_temp = src_cell.y;
            next_aux = src_cell.z;
        }
    } else if has_incoming_winner {
        src_cell := state[src_offset + best_src];
        next_mat = sand_material_of(src_cell);
        next_temp = src_cell.y;
        next_aux = src_cell.z;
    } else if source_stays {
        next_mat = sand_material_of(center);
        next_temp = center.y;
        next_aux = center.z;
    } else if has_candidate {
        src_cell := state[src_offset + best_src];
        next_mat = sand_material_of(src_cell);
        next_temp = src_cell.y;
        next_aux = src_cell.z;
    }

    next_temp = sand_heat_diffusion(next_temp, up_v.y, down_v.y, left_v.y, right_v.y);
    sand_apply_reactions(up_m, down_m, left_m, right_m, *next_mat, *next_temp);

    target_temp := sand_default_temp_for_material(next_mat);
    next_temp = mix(next_temp, target_temp, 0.035);
    next_temp = clamp(next_temp, 0.0, 1.0);

    if next_mat == SAND_MAT_STEAM {
        steam_adjacent_lava := (up_m == SAND_MAT_LAVA) || (down_m == SAND_MAT_LAVA) || (left_m == SAND_MAT_LAVA) || (right_m == SAND_MAT_LAVA);
        // Steam age (cell.z) increases while steam remains steam.
        next_aux = min(next_aux + 1.0, 4096.0);

        age_factor := clamp(next_aux / 420.0, 0.0, 1.0);
        cool_factor := clamp((0.50 - next_temp) / 0.50, 0.0, 1.0);
        dissipation_chance := 0.0015 + age_factor * 0.03 + cool_factor * 0.02;
        if steam_adjacent_lava dissipation_chance *= 0.35;

        dissipate_hash := sand_hash_mix(sand_frame_hash(x ^ (i * 17), y ^ (i * 31), control[0].frame_index ^ (i * 131)));
        rnd := cast(float) (dissipate_hash & 1023) / 1023.0;
        if rnd < dissipation_chance {
            next_mat = SAND_MAT_EMPTY;
            next_temp = sand_default_temp_for_material(SAND_MAT_EMPTY);
            next_aux = 0.0;
        }
    } else {
        next_aux = 0.0;
    }

    // Brush paint in resolve pass so edits are deterministic.
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
            next_aux = 0.0;
        }
    }

    state[dst_offset + i] = .{cast(float) next_mat, next_temp, next_aux, 0.0};
} @compute_shader

sand_step_compute :: (using in: Sand_Compute_In, state: *Vector4, control: *Sand_Compute_Control) {
    // Legacy single-pass entry (kept for compatibility); no-op.
    if thread_id.x >= SAND_CELL_COUNT return;
    src_offset: u32 = 0;
    dst_offset: u32 = SAND_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = SAND_CELL_COUNT;
        dst_offset = 0;
    }
    i := thread_id.x;
    state[dst_offset + i] = state[src_offset + i];
} @compute_shader

/* old single-pass implementation removed in favor of two-phase plan/resolve */
/* keep symbol sand_step_compute for backward compatibility with existing tools */
/*
*/

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
