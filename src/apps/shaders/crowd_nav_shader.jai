#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

CROWD_AGENT_COUNT: u32: 540;
CROWD_OBSTACLE_COUNT: u32: 4;
CROWD_INSTANCE_COUNT: u32: CROWD_AGENT_COUNT + CROWD_OBSTACLE_COUNT;

Crowd_Nav_Vertex :: struct {
    pos: Vector4;
    normal: Vector4;
}

Crowd_Nav_Obstacle :: struct {
    center: Vector2;
    radius: float;
    _pad0: float;
}

Crowd_Nav_State :: struct {
    motion: Vector4;
    sim0: Vector4;
    sim1: Vector4;
    sim2: Vector4;
}

Crowd_Nav_Draw_Params :: struct {
    vertices: *Crowd_Nav_Vertex;
    states: *Crowd_Nav_State;
    view_proj: Matrix4;
    light_dir: Vector3;
    time: float;
}

Crowd_Nav_Floor_Params :: struct {
    view_proj: Matrix4;
}

Crowd_Nav_Compute_Control :: struct {
    dt: float;
    time: float;
    use_b_as_src: u32;
    _pad0: u32;
    obstacle0: Vector4;
    obstacle1: Vector4;
    obstacle2: Vector4;
    obstacle3: Vector4;
}

Crowd_Nav_Compute_Params :: struct {
    state: *Crowd_Nav_State;
    control: *Crowd_Nav_Compute_Control;
}

Crowd_Nav_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Crowd_Nav_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    normal_ws: Vector3;
    world_pos: Vector3;
    tint: Vector4; @color
}

Crowd_Nav_Floor_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
}

Crowd_Nav_Fragment_In :: struct {
    normal_ws: Vector3;
    world_pos: Vector3;
    tint: Vector4; @color
}

Crowd_Nav_Floor_Fragment_In :: struct {
    world_pos: Vector3;
}

Crowd_Nav_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

crowd_nav_safe_normalize2 :: (v: Vector2, fallback: Vector2 = .{1.0, 0.0}) -> Vector2 {
    len2 := dot(v, v);
    if len2 < 0.000001 return fallback;
    return v * (1.0 / sqrt(len2));
}

crowd_nav_safe_normalize3 :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 < 0.000001 return .{0.0, 1.0, 0.0};
    return v * (1.0 / sqrt(len2));
}

crowd_nav_hash01 :: (seed: float) -> float {
    x := sin(seed * 12.9898 + 78.233) * 43758.547;
    return x - floor(x);
}

crowd_nav_target_at :: (idx: float) -> Vector2 {
    if idx < 0.5 return .{-6.5, -5.3};
    if idx < 1.5 return .{ 6.0, -4.2};
    if idx < 2.5 return .{ 5.7,  5.1};
    if idx < 3.5 return .{-5.9,  4.7};
    return .{-6.5, -5.3};
}

crowd_nav_obstacle_push :: (pos: Vector2, center: Vector2, radius: float) -> Vector2 {
    delta := pos - center;
    dist2 := dot(delta, delta);
    safe_radius := radius + 0.78;
    safe_radius2 := safe_radius * safe_radius;
    if dist2 >= safe_radius2 return .{0.0, 0.0};

    dist := sqrt(max(dist2, 0.000001));
    push := delta * (1.0 / dist);
    return push * (1.0 - dist / safe_radius);
}

crowd_nav_step_compute :: (using in: Crowd_Nav_Compute_In, data: *Crowd_Nav_Compute_Params) {
    i := thread_id.x;
    if i >= CROWD_AGENT_COUNT return;

    use_b_as_src := data.control[0].use_b_as_src != 0;
    src_offset: u32 = 0;
    dst_offset: u32 = CROWD_INSTANCE_COUNT;
    if use_b_as_src {
        src_offset = CROWD_INSTANCE_COUNT;
        dst_offset = 0;
    }

    dt := max(data.control[0].dt, 0.0001);
    src_motion := data.state[src_offset + i].motion;
    src_sim0 := data.state[src_offset + i].sim0;
    src_sim1 := data.state[src_offset + i].sim1;
    src_sim2 := data.state[src_offset + i].sim2;

    target_index := src_sim0.x;
    target := crowd_nav_target_at(target_index);
    pos := Vector2.{src_motion.x, src_motion.y};
    vel := Vector2.{src_motion.z, src_motion.w};
    to_target := target - pos;
    if dot(to_target, to_target) < 0.64 {
        target_index += 1.0;
        if target_index > 3.5 target_index = 0.0;
        target = crowd_nav_target_at(target_index);
        to_target = target - pos;
    }

    desired_dir := crowd_nav_safe_normalize2(to_target);
    desired_vel := desired_dir * src_sim0.z;

    separation_radius :: 0.82;
    neighbor_radius :: 1.6;
    arena_radius :: 8.4;
    min_speed :: 0.65;
    max_speed :: 2.4;

    separation_radius2 := separation_radius * separation_radius;
    neighbor_radius2 := neighbor_radius * neighbor_radius;

    separation := Vector2.{0.0, 0.0};
    alignment := Vector2.{0.0, 0.0};
    neighbors: float = 0.0;

    j: u32 = 0;
    while j < CROWD_AGENT_COUNT {
        if j != i {
            other := data.state[src_offset + j];
            other_pos := Vector2.{other.motion.x, other.motion.y};
            delta := pos - other_pos;
            dist2 := dot(delta, delta);
            if dist2 > 0.000001 {
                if dist2 < separation_radius2 {
                    inv_dist := 1.0 / sqrt(dist2);
                    separation += delta * inv_dist;
                }
                if dist2 < neighbor_radius2 {
                    alignment += Vector2.{other.motion.z, other.motion.w};
                    neighbors += 1.0;
                }
            }
        }
        j += 1;
    }

    if neighbors > 0.0 {
        alignment *= 1.0 / neighbors;
        alignment = crowd_nav_safe_normalize2(alignment, .{0.0, 0.0}) * src_sim0.z;
    }

    obstacle_push := Vector2.{0.0, 0.0};
    obstacle_push += crowd_nav_obstacle_push(pos, .{data.control[0].obstacle0.x, data.control[0].obstacle0.y}, data.control[0].obstacle0.z);
    obstacle_push += crowd_nav_obstacle_push(pos, .{data.control[0].obstacle1.x, data.control[0].obstacle1.y}, data.control[0].obstacle1.z);
    obstacle_push += crowd_nav_obstacle_push(pos, .{data.control[0].obstacle2.x, data.control[0].obstacle2.y}, data.control[0].obstacle2.z);
    obstacle_push += crowd_nav_obstacle_push(pos, .{data.control[0].obstacle3.x, data.control[0].obstacle3.y}, data.control[0].obstacle3.z);

    boundary_push := Vector2.{0.0, 0.0};
    center_dist2 := dot(pos, pos);
    if center_dist2 > arena_radius * arena_radius {
        center_dist := sqrt(center_dist2);
        inward := crowd_nav_safe_normalize2(-pos, .{0.0, 1.0});
        boundary_push = inward * ((center_dist - arena_radius) * 1.25);
    }

    lane_angle := crowd_nav_hash01(src_sim1.x * 0.71 + pos.x * 0.13 + pos.y * 0.19) * 6.2831855;
    lane_bias := Vector2.{cos(lane_angle), sin(lane_angle)} * 0.16;

    steer := (desired_vel - vel) * 1.2;
    steer += separation * 1.45;
    steer += (alignment - vel) * 0.25;
    steer += obstacle_push * 3.0;
    steer += boundary_push * 2.4;
    steer += lane_bias;

    next_vel := vel + steer * dt;
    speed := sqrt(dot(next_vel, next_vel));
    if speed > max_speed {
        next_vel *= max_speed / speed;
    } else if speed < min_speed {
        next_vel = crowd_nav_safe_normalize2(next_vel, desired_dir) * min_speed;
    }

    pos += next_vel * dt;
    speed_t := clamp((sqrt(dot(next_vel, next_vel)) - min_speed) / (max_speed - min_speed), 0.0, 1.0);
    data.state[dst_offset + i].motion = .{pos.x, pos.y, next_vel.x, next_vel.y};
    data.state[dst_offset + i].sim0 = .{target_index, src_sim0.y, src_sim0.z, src_sim0.w};
    data.state[dst_offset + i].sim1 = .{src_sim1.x, 0.34, 0.44 + speed_t * 0.07, 0.5};
    data.state[dst_offset + i].sim2 = src_sim2;

    if i < CROWD_OBSTACLE_COUNT {
        data.state[dst_offset + CROWD_AGENT_COUNT + i].motion = data.state[src_offset + CROWD_AGENT_COUNT + i].motion;
        data.state[dst_offset + CROWD_AGENT_COUNT + i].sim0 = data.state[src_offset + CROWD_AGENT_COUNT + i].sim0;
        data.state[dst_offset + CROWD_AGENT_COUNT + i].sim1 = data.state[src_offset + CROWD_AGENT_COUNT + i].sim1;
        data.state[dst_offset + CROWD_AGENT_COUNT + i].sim2 = data.state[src_offset + CROWD_AGENT_COUNT + i].sim2;
    }
} @compute_shader

crowd_nav_vertex_main :: (using in: Crowd_Nav_Vertex_In, params: *Crowd_Nav_Draw_Params) -> Crowd_Nav_Vertex_Out {
    using out: Crowd_Nav_Vertex_Out;
    v := params[0].vertices[vertex_id];
    state := params[0].states[instance_id];

    local := Vector3.{v.pos.x * state.sim1.y, v.pos.y * state.sim1.z, v.pos.z * state.sim1.w};
    normal_local := crowd_nav_safe_normalize3(Vector3.{v.normal.x, v.normal.y, v.normal.z});

    wobble_phase := params[0].time * 7.0 + state.sim1.x * 0.37;
    bob := sin(wobble_phase) * 0.028 * (1.0 - state.sim0.y);
    lean := sin(wobble_phase + local.z * 8.0) * 0.022 * (1.0 - state.sim0.y);
    local.y += bob;
    local.x += lean;

    rotated := local;
    normal_ws = normal_local;
    base_height := mix(0.34, 0.58, state.sim0.y);
    world_pos = rotated + Vector3.{state.motion.x, base_height, state.motion.y};
    gl_Position = params[0].view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    tint = .{state.sim2.y, state.sim2.z, state.sim2.w, 1.0};
    return out;
} @vertex_shader

crowd_nav_fragment_main :: (using in: Crowd_Nav_Fragment_In, params: *Crowd_Nav_Draw_Params) -> Vector4 @SV_Target0 {
    n := crowd_nav_safe_normalize3(normal_ws);
    light_dir := crowd_nav_safe_normalize3(-params[0].light_dir);
    ndl := clamp(dot(n, light_dir), 0.0, 1.0);
    hemi := clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
    base := Vector3.{tint.x, tint.y, tint.z};
    lit := base * (0.22 + ndl * 0.9) + Vector3.{0.04, 0.05, 0.06} * hemi;
    rim := pow(1.0 - clamp(dot(n, crowd_nav_safe_normalize3(Vector3.{0.2, 0.8, 0.5})), 0.0, 1.0), 2.0) * 0.08;
    lit += Vector3.{rim, rim, rim};
    return .{lit.x, lit.y, lit.z, tint.w};
} @fragment_shader

crowd_nav_floor_vertex_main :: (using in: Crowd_Nav_Vertex_In, params: *Crowd_Nav_Floor_Params) -> Crowd_Nav_Floor_Vertex_Out {
    using out: Crowd_Nav_Floor_Vertex_Out;
    positions := Vector3.[
        .{-12.0, 0.0, -12.0},
        .{ 12.0, 0.0, -12.0},
        .{-12.0, 0.0,  12.0},
        .{-12.0, 0.0,  12.0},
        .{ 12.0, 0.0, -12.0},
        .{ 12.0, 0.0,  12.0},
    ];
    world_pos = positions[vertex_id];
    gl_Position = params[0].view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    return out;
} @vertex_shader

crowd_nav_floor_fragment_main :: (using in: Crowd_Nav_Floor_Fragment_In, params: *Crowd_Nav_Floor_Params) -> Vector4 @SV_Target0 {
    _ = params;
    coarse_x := abs(fract(world_pos.x * 0.25) - 0.5) * 2.0;
    coarse_z := abs(fract(world_pos.z * 0.25) - 0.5) * 2.0;
    fine_x := abs(fract(world_pos.x) - 0.5) * 2.0;
    fine_z := abs(fract(world_pos.z) - 0.5) * 2.0;
    coarse_line := 1.0 - smoothstep(0.90, 1.0, min(coarse_x, coarse_z));
    fine_line := 1.0 - smoothstep(0.965, 1.0, min(fine_x, fine_z));
    base := Vector3.{0.085, 0.095, 0.105};
    accent := Vector3.{0.20, 0.24, 0.28};
    line_mix := clamp(coarse_line * 0.9 + fine_line * 0.28, 0.0, 1.0);
    fog := clamp(length(Vector2.{world_pos.x, world_pos.z}) / 14.0, 0.0, 1.0);
    color := mix(base, accent, line_mix);
    color = mix(color, Vector3.{0.03, 0.035, 0.045}, fog * 0.45);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
