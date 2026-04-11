#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";

#import "Math";

BOIDS_COUNT :: 1920;
MIN_SPEED :: 0.05;
MAX_SPEED :: 0.9;
ALIGN_WEIGHT :: 0.9;
COHESION_WEIGHT :: 0.45;
SEPARATION_WEIGHT :: 1.4;
CURSOR_AVOID_RADIUS :: 0.25;
CURSOR_AVOID_WEIGHT :: 2.9;

// One boid's state.
Boid_State :: struct {
    pos: Vector2;
    vel: Vector2;
}

Boids_Control :: struct {
    cursor: Vector2; @no_ui
    use_b_as_src: u32; @no_ui
    delta_time: float; @no_ui

    view_extent: float = 1.05; @(0.25,1.1)
    min_speed: float = MIN_SPEED; @(0.001,0.2)
    max_speed: float = MAX_SPEED; @(0.5,2.0)
    perception_radius: float = 0.13; @(0,0.2)
    separation_radius: float = 0.049; @(0,0.1)
    _pad1: float;
    _pad2: float;
}

Boids_Compute_Params :: struct {
    state: *Boid_State;
    control: *Boids_Control;
}

boids_random_turn_impulse :: (i: u32, pos: Vector2, vel: Vector2, max_speed: float) -> Vector2 {
    h := hash01(i, pos);
    turn_strength := max_speed * 6.0;

    if h > 0.992 return Vector2.{-vel.y, vel.x} * turn_strength;
    if h < 0.008 return Vector2.{vel.y, -vel.x} * turn_strength;
    return .{0, 0};
}

Boids_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

boids_step_compute :: (using in: Boids_Compute_In, using data: *Boids_Compute_Params) {
    i := thread_id.x;
    if i >= BOIDS_COUNT return;

    using control;

    src_offset: u32 = 0;
    dst_offset: u32 = cast(u32) BOIDS_COUNT;
    if data.control.use_b_as_src != 0 {
        src_offset = cast(u32) BOIDS_COUNT;
        dst_offset = 0;
    }

    pos := state[src_offset + i].pos;
    vel := state[src_offset + i].vel;

    perception2 := perception_radius * perception_radius;
    separation2 := separation_radius * separation_radius;

    align_sum: Vector2;
    cohesion_sum: Vector2;
    separation_sum: Vector2;
    neighbors: u32;

    j: u32 = 0;
    while j < BOIDS_COUNT {
        if j == i {
            j += 1;
            continue;
        }

        other_pos := state[src_offset + j].pos;
        delta := other_pos - pos;
        dist2 := delta.x * delta.x + delta.y * delta.y;
        if dist2 > perception2 {
            j += 1;
            continue;
        }

        neighbors += 1;
        align_sum += state[src_offset + j].vel;
        cohesion_sum += other_pos;

        if dist2 < separation2 && dist2 > 0.000001 {
            inv_dist := 1.0 / sqrt(dist2);
            separation_sum -= delta * inv_dist;
        }
        j += 1;
    }

    fallback_hash := hash01(i, pos);
    fallback_angle := fallback_hash * 6.2831855;
    fallback_dir := Vector2.{cos(fallback_angle), sin(fallback_angle)};
    accel: Vector2;
    if neighbors > 0 {
        inv_neighbors := 1.0 / cast(float) neighbors;
        align_avg := align_sum * inv_neighbors;
        align_target := align_avg;
        align_len := length(align_target);
        if align_len < 0.000001 {
            align_target = fallback_dir * min_speed;
        } else if align_len > max_speed {
            align_target = align_target * (1.0 / align_len) * max_speed;
        } else if align_len < min_speed {
            align_target = align_target * (1.0 / align_len) * min_speed;
        }
        align_force := align_target - vel;

        cohesion_center := cohesion_sum * inv_neighbors;
        cohesion_dir := cohesion_center - pos;
        cohesion_target := cohesion_dir;
        cohesion_len := length(cohesion_target);
        if cohesion_len < 0.000001 {
            cohesion_target = fallback_dir * min_speed;
        } else if cohesion_len > max_speed {
            cohesion_target = cohesion_target * (1.0 / cohesion_len) * max_speed;
        } else if cohesion_len < min_speed {
            cohesion_target = cohesion_target * (1.0 / cohesion_len) * min_speed;
        }
        cohesion_force := cohesion_target - vel;

        separation_target := separation_sum;
        separation_len := length(separation_target);
        if separation_len < 0.000001 {
            separation_target = fallback_dir * min_speed;
        } else if separation_len > max_speed {
            separation_target = separation_target * (1.0 / separation_len) * max_speed;
        } else if separation_len < min_speed {
            separation_target = separation_target * (1.0 / separation_len) * min_speed;
        }

        separation_force := separation_target - vel;
        accel = align_force * ALIGN_WEIGHT + cohesion_force * COHESION_WEIGHT + separation_force * SEPARATION_WEIGHT;
    }

    turn_impulse := boids_random_turn_impulse(i, pos, vel, max_speed);
    accel += turn_impulse;

    cursor_delta := pos - data.control.cursor;
    cursor_dist2 := cursor_delta.x * cursor_delta.x + cursor_delta.y * cursor_delta.y;
    cursor_radius2 := CURSOR_AVOID_RADIUS * CURSOR_AVOID_RADIUS;
    if cursor_dist2 > 0.000001 && cursor_dist2 < cursor_radius2 {
        cursor_dist := sqrt(cursor_dist2);
        inv_cursor_dist := 1.0 / cursor_dist;
        falloff := 1.0 - (cursor_dist / CURSOR_AVOID_RADIUS);
        cursor_force := cursor_delta * inv_cursor_dist * max_speed * falloff;
        accel += cursor_force * CURSOR_AVOID_WEIGHT;
    }

    next_vel := vel + accel * delta_time;
    next_vel_len := length(next_vel);
    if next_vel_len < 0.000001 {
        next_vel = fallback_dir * MIN_SPEED;
    } else if next_vel_len > max_speed {
        inv := 1.0 / next_vel_len;
        next_vel = next_vel * inv * max_speed;
    } else if next_vel_len < MIN_SPEED {
        inv := 1.0 / next_vel_len;
        next_vel = next_vel * inv * MIN_SPEED;
    }

    next_pos := pos + next_vel * delta_time;
    if next_pos.x < -view_extent next_pos.x += view_extent * 2.0;
    if next_pos.x > view_extent next_pos.x -= view_extent * 2.0;
    if next_pos.y < -view_extent next_pos.y += view_extent * 2.0;
    if next_pos.y > view_extent next_pos.y -= view_extent * 2.0;

    state[dst_offset + i].pos = next_pos;
    state[dst_offset + i].vel = next_vel;
} @compute_shader

boids_vertex_main :: (using in: Vertex_In, data: *Boids_Draw_Params) -> Vertex_Out {
    instance_pos := data.instances[instance_id].pos;
    vel := data.instances[instance_id].vel;
    vel_len := length(vel);
    forward := Vector2.{1, 0};
    if vel_len > 0.000001 {
        inv_len := 1.0 / vel_len;
        forward = .{vel.x * inv_len, vel.y * inv_len};
    }
    right := Vector2.{-forward.y, forward.x};
    local := data.positions[vertex_id];
    rotated := Vector2.{
        local.x * forward.x + local.y * right.x,
        local.x * forward.y + local.y * right.y
    };
    pos := rotated + instance_pos;
    return {
        gl_Position = { pos.x, pos.y, 0, 1 },
        tint = data.tints[instance_id],
    };
} @vertex_shader

boids_frag_main :: (using in: struct { tint: Vector4; @color }, data: *Boids_Draw_Params) -> Vector4 @SV_Target0 {
    return tint;
} @fragment_shader

Boids_Draw_Params :: struct {
    positions: *Vector2;
    tints: *Vector4;
    instances: *Boid_State;
}

#scope_file

Vertex_Out :: struct {
    gl_Position: Vector4; @position
    tint: Vector4; @color
}

Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}
