#import "Jai-Shader-Transpiler";
#import "Math";

BOIDS_COUNT :: 920;
BOIDS_VIEW_EXTENT :: 1.05;
BOIDS_MAX_SPEED :: 0.9;
BOIDS_MIN_SPEED :: 0.05;
BOIDS_PERCEPTION_RADIUS :: 0.14;
BOIDS_SEPARATION_RADIUS :: 0.059;
BOIDS_ALIGN_WEIGHT :: 0.9;
BOIDS_COHESION_WEIGHT :: 0.45;
BOIDS_SEPARATION_WEIGHT :: 1.4;
BOIDS_CURSOR_AVOID_RADIUS :: 0.25;
BOIDS_CURSOR_AVOID_WEIGHT :: 1.9;
BOIDS_DT :: 1.0 / 60.0;

boids_hash01 :: (i: u32, pos: Vector2) -> float {
    k0: float = 12.9898;
    k1: float = 78.233;
    k2: float = 37.719;
    k3: float = 43758.547;
    n := sin(pos.x * k0 + pos.y * k1 + cast(float) i * k2);
    x := n * k3;
    return x - floor(x);
}

boids_random_turn_impulse :: (i: u32, pos: Vector2, vel: Vector2) -> Vector2 {
    h := boids_hash01(i, pos);
    turn_strength := BOIDS_MAX_SPEED * 6.0;

    if h > 0.992 {
        return .{-vel.y * turn_strength, vel.x * turn_strength};
    }
    if h < 0.008 {
        return .{vel.y * turn_strength, -vel.x * turn_strength};
    }
    return .{0, 0};
}

Boid_State :: struct {
    pos: Vector2;
    vel: Vector2;
}

Boids_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

UVector3 :: struct {
    x, y, z: u32;
}

BOIDS_CTRL_INDEX :: BOIDS_COUNT * 2;

boids_step_compute :: (using in: Boids_Compute_In, state: *Boid_State) {
    i := thread_id.x;
    if i >= BOIDS_COUNT return;

    use_b_as_src := state[BOIDS_CTRL_INDEX].pos.x > 0.5;
    src_offset: u32 = 0;
    dst_offset: u32 = cast(u32) BOIDS_COUNT;
    if use_b_as_src {
        src_offset = cast(u32) BOIDS_COUNT;
        dst_offset = 0;
    }

    pos := state[src_offset + i].pos;
    vel := state[src_offset + i].vel;

    perception2 := BOIDS_PERCEPTION_RADIUS * BOIDS_PERCEPTION_RADIUS;
    separation2 := BOIDS_SEPARATION_RADIUS * BOIDS_SEPARATION_RADIUS;

    align_sum := Vector2.{0, 0};
    cohesion_sum := Vector2.{0, 0};
    separation_sum := Vector2.{0, 0};
    neighbors: u32 = 0;

    j: u32 = 0;
    while j < BOIDS_COUNT {
        if j == i {
            j += 1;
            continue;
        }

        other_pos_x := state[src_offset + j].pos.x;
        other_pos_y := state[src_offset + j].pos.y;
        delta := Vector2.{other_pos_x - pos.x, other_pos_y - pos.y};
        dist2 := delta.x * delta.x + delta.y * delta.y;
        if dist2 > perception2 {
            j += 1;
            continue;
        }

        neighbors += 1;
        align_sum.x += state[src_offset + j].vel.x;
        align_sum.y += state[src_offset + j].vel.y;
        cohesion_sum.x += other_pos_x;
        cohesion_sum.y += other_pos_y;

        if dist2 < separation2 && dist2 > 0.000001 {
            inv_dist := 1.0 / sqrt(dist2);
            separation_sum.x -= delta.x * inv_dist;
            separation_sum.y -= delta.y * inv_dist;
        }
        j += 1;
    }

    fallback_hash := boids_hash01(i, pos);
    fallback_angle := fallback_hash * 6.2831855;
    fallback_dir := Vector2.{cos(fallback_angle), sin(fallback_angle)};
    accel := Vector2.{0, 0};
    if neighbors > 0 {
        inv_neighbors := 1.0 / cast(float) neighbors;

        align_avg := Vector2.{align_sum.x * inv_neighbors, align_sum.y * inv_neighbors};
        align_target := align_avg;
        align_len := sqrt(align_target.x * align_target.x + align_target.y * align_target.y);
        if align_len < 0.000001 {
            align_target = .{fallback_dir.x * BOIDS_MIN_SPEED, fallback_dir.y * BOIDS_MIN_SPEED};
        } else if align_len > BOIDS_MAX_SPEED {
            inv := 1.0 / align_len;
            align_target = .{align_target.x * inv * BOIDS_MAX_SPEED, align_target.y * inv * BOIDS_MAX_SPEED};
        } else if align_len < BOIDS_MIN_SPEED {
            inv := 1.0 / align_len;
            align_target = .{align_target.x * inv * BOIDS_MIN_SPEED, align_target.y * inv * BOIDS_MIN_SPEED};
        }
        align_force := Vector2.{align_target.x - vel.x, align_target.y - vel.y};

        cohesion_center := Vector2.{cohesion_sum.x * inv_neighbors, cohesion_sum.y * inv_neighbors};
        cohesion_dir := Vector2.{cohesion_center.x - pos.x, cohesion_center.y - pos.y};
        cohesion_target := cohesion_dir;
        cohesion_len := sqrt(cohesion_target.x * cohesion_target.x + cohesion_target.y * cohesion_target.y);
        if cohesion_len < 0.000001 {
            cohesion_target = .{fallback_dir.x * BOIDS_MIN_SPEED, fallback_dir.y * BOIDS_MIN_SPEED};
        } else if cohesion_len > BOIDS_MAX_SPEED {
            inv := 1.0 / cohesion_len;
            cohesion_target = .{cohesion_target.x * inv * BOIDS_MAX_SPEED, cohesion_target.y * inv * BOIDS_MAX_SPEED};
        } else if cohesion_len < BOIDS_MIN_SPEED {
            inv := 1.0 / cohesion_len;
            cohesion_target = .{cohesion_target.x * inv * BOIDS_MIN_SPEED, cohesion_target.y * inv * BOIDS_MIN_SPEED};
        }
        cohesion_force := Vector2.{cohesion_target.x - vel.x, cohesion_target.y - vel.y};

        separation_target := separation_sum;
        separation_len := sqrt(separation_target.x * separation_target.x + separation_target.y * separation_target.y);
        if separation_len < 0.000001 {
            separation_target = .{fallback_dir.x * BOIDS_MIN_SPEED, fallback_dir.y * BOIDS_MIN_SPEED};
        } else if separation_len > BOIDS_MAX_SPEED {
            inv := 1.0 / separation_len;
            separation_target = .{separation_target.x * inv * BOIDS_MAX_SPEED, separation_target.y * inv * BOIDS_MAX_SPEED};
        } else if separation_len < BOIDS_MIN_SPEED {
            inv := 1.0 / separation_len;
            separation_target = .{separation_target.x * inv * BOIDS_MIN_SPEED, separation_target.y * inv * BOIDS_MIN_SPEED};
        }
        separation_force := Vector2.{separation_target.x - vel.x, separation_target.y - vel.y};

        accel.x = align_force.x * BOIDS_ALIGN_WEIGHT +
                  cohesion_force.x * BOIDS_COHESION_WEIGHT +
                  separation_force.x * BOIDS_SEPARATION_WEIGHT;
        accel.y = align_force.y * BOIDS_ALIGN_WEIGHT +
                  cohesion_force.y * BOIDS_COHESION_WEIGHT +
                  separation_force.y * BOIDS_SEPARATION_WEIGHT;
    }
    turn_impulse := boids_random_turn_impulse(i, pos, vel);
    accel.x += turn_impulse.x;
    accel.y += turn_impulse.y;

    cursor_pos := state[BOIDS_CTRL_INDEX].vel;
    cursor_delta := Vector2.{pos.x - cursor_pos.x, pos.y - cursor_pos.y};
    cursor_dist2 := cursor_delta.x * cursor_delta.x + cursor_delta.y * cursor_delta.y;
    cursor_radius2 := BOIDS_CURSOR_AVOID_RADIUS * BOIDS_CURSOR_AVOID_RADIUS;
    if cursor_dist2 > 0.000001 && cursor_dist2 < cursor_radius2 {
        cursor_dist := sqrt(cursor_dist2);
        inv_cursor_dist := 1.0 / cursor_dist;
        falloff := 1.0 - (cursor_dist / BOIDS_CURSOR_AVOID_RADIUS);
        cursor_force := Vector2.{
            cursor_delta.x * inv_cursor_dist * BOIDS_MAX_SPEED * falloff,
            cursor_delta.y * inv_cursor_dist * BOIDS_MAX_SPEED * falloff,
        };
        accel.x += cursor_force.x * BOIDS_CURSOR_AVOID_WEIGHT;
        accel.y += cursor_force.y * BOIDS_CURSOR_AVOID_WEIGHT;
    }

    next_vel := Vector2.{vel.x + accel.x * BOIDS_DT, vel.y + accel.y * BOIDS_DT};
    next_vel_len := sqrt(next_vel.x * next_vel.x + next_vel.y * next_vel.y);
    if next_vel_len < 0.000001 {
        next_vel = .{fallback_dir.x * BOIDS_MIN_SPEED, fallback_dir.y * BOIDS_MIN_SPEED};
    } else if next_vel_len > BOIDS_MAX_SPEED {
        inv := 1.0 / next_vel_len;
        next_vel = .{next_vel.x * inv * BOIDS_MAX_SPEED, next_vel.y * inv * BOIDS_MAX_SPEED};
    } else if next_vel_len < BOIDS_MIN_SPEED {
        inv := 1.0 / next_vel_len;
        next_vel = .{next_vel.x * inv * BOIDS_MIN_SPEED, next_vel.y * inv * BOIDS_MIN_SPEED};
    }

    next_pos := Vector2.{pos.x + next_vel.x * BOIDS_DT, pos.y + next_vel.y * BOIDS_DT};
    if next_pos.x < -BOIDS_VIEW_EXTENT next_pos.x += BOIDS_VIEW_EXTENT * 2.0;
    if next_pos.x > BOIDS_VIEW_EXTENT next_pos.x -= BOIDS_VIEW_EXTENT * 2.0;
    if next_pos.y < -BOIDS_VIEW_EXTENT next_pos.y += BOIDS_VIEW_EXTENT * 2.0;
    if next_pos.y > BOIDS_VIEW_EXTENT next_pos.y -= BOIDS_VIEW_EXTENT * 2.0;

    state[dst_offset + i].pos = next_pos;
    state[dst_offset + i].vel = next_vel;

    if i == 0 {
        if use_b_as_src {
            state[BOIDS_CTRL_INDEX].pos.x = 0.0;
        } else {
            state[BOIDS_CTRL_INDEX].pos.x = 1.0;
        }
    }
} @compute_shader

boids_vertex_main :: (using in: Vertex_In, data: *All_Params) -> Vertex_Out {
    using out: Vertex_Out;
    instance_pos := data.v.instances[instance_id].pos;
    vel := data.v.instances[instance_id].vel;
    vel_len := sqrt(vel.x * vel.x + vel.y * vel.y);
    forward := Vector2.{1, 0};
    if vel_len > 0.000001 {
        inv_len := 1.0 / vel_len;
        forward = .{vel.x * inv_len, vel.y * inv_len};
    }
    right := Vector2.{-forward.y, forward.x};
    local := data.v.positions[vertex_id];
    rotated := Vector2.{
        local.x * forward.x + local.y * right.x,
        local.x * forward.y + local.y * right.y
    };
    pos := rotated + instance_pos;
    gl_Position = { pos.x, pos.y, 0, 1 };
    tint = data.v.tints[instance_id];
    return out;
} @vertex_shader

boids_frag_main :: (using in: Fragment_In, data: *All_Params) -> Vector4 @SV_Target0 {
    return tint;
} @fragment_shader

Vertex_Params :: struct {
    positions: *Vector2;
    tints: *Vector4;
    instances: *Boid_State;
}

Pixel_Params :: struct {
    color: *float;
}

All_Params :: struct {
    v: *Vertex_Params;
    p: *Pixel_Params;
}

#scope_file

Vertex_Out :: struct {
    gl_Position: Vector4; @position
    tint: Vector4; @color
}

Fragment_In :: struct {
    tint: Vector4; @color
}

Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Vertex_Uniforms :: struct {}
