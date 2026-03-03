#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

FLUX_WIDTH  :: 2048;
FLUX_HEIGHT :: 2048;
FLUX_CELL_COUNT :: FLUX_WIDTH * FLUX_HEIGHT;
FLUX_MESH_WIDTH  :: 512;
FLUX_MESH_HEIGHT :: 512;
FLUX_MESH_VERTS :: (FLUX_MESH_WIDTH - 1) * (FLUX_MESH_HEIGHT - 1) * 6;
FLUX_GRASS_INSTANCE_COUNT :: 44000;
FLUX_GRASS_VERTS_PER_INSTANCE :: 6;

FLUX_PARAM_V4_COUNT :: 14;
FLUX_STATE_OFFSET :: FLUX_PARAM_V4_COUNT;
FLUX_GRASS_DATA_OFFSET :: FLUX_STATE_OFFSET + FLUX_CELL_COUNT * 2;
FLUX_PAYLOAD_TOTAL_V4_COUNT :: FLUX_GRASS_DATA_OFFSET + FLUX_GRASS_INSTANCE_COUNT;

FLUX_PARAM_CAMERA_POS_PROJ_X              :: 0;
FLUX_PARAM_CAMERA_RIGHT_PROJ_Y            :: 1;
FLUX_PARAM_CAMERA_UP_NEAR                 :: 2;
FLUX_PARAM_CAMERA_FORWARD_FAR             :: 3;
FLUX_PARAM_LIGHT_RIGHT_EXTENT             :: 4;
FLUX_PARAM_LIGHT_UP_NEAR                  :: 5;
FLUX_PARAM_LIGHT_FORWARD_FAR              :: 6;
FLUX_PARAM_LIGHT_CENTER_USE_B_AS_SRC      :: 7;
FLUX_PARAM_SHADOW_TEX_SAMPLER_BIAS_TEXEL  :: 8;
FLUX_PARAM_SUN_DIR_XZ_SCALE               :: 9;
FLUX_PARAM_FOG_TIME_WIND_GAIN             :: 10;
FLUX_PARAM_GRASS_COUNT_SPACING_SCALE      :: 11;
FLUX_PARAM_GRASS_SPAWN_LOD                :: 12;
FLUX_PARAM_GRASS_FADE_NEAR_FAR            :: 13;

Flux_Render_Params :: struct {
    camera_pos_proj_x: Vector4;
    camera_right_proj_y: Vector4;
    camera_up_near: Vector4;
    camera_forward_far: Vector4;
    light_right_extent: Vector4;
    light_up_near: Vector4;
    light_forward_far: Vector4;
    light_center_use_b_as_src: Vector4;
    shadow_tex_sampler_bias_texel: Vector4;
    sun_dir_xz_scale: Vector4;
    fog_time_wind_gain: Vector4;
    grass_count_spacing_scale: Vector4;
    grass_spawn_lod: Vector4;
    grass_fade_near_far: Vector4;
}

#assert(size_of(Flux_Render_Params) == FLUX_PARAM_V4_COUNT * size_of(Vector4));

FLUX_DT :: 1.0;
FLUX_FLOW_ACCEL :: 0.030;
FLUX_VEL_DAMPING :: 0.986;
FLUX_HEIGHT_DIFFUSION :: 0.042;
FLUX_TEMP_DIFFUSION :: 0.075;
FLUX_TEMP_COOLING :: 0.995;
FLUX_FORCING :: 0.012;
FLUX_MAX_HEIGHT :: 6.0;
FLUX_MAX_VEL :: 1.9;
FLUX_MAX_TEMP :: 2.0;

Brush_Type :: enum u32 {
    NONE :: 0;
    RAISE :: 1;
    CARVE :: 2;
    HEAT :: 3;
}
FLUX_BRUSH_NONE  :: Brush_Type.NONE;
FLUX_BRUSH_RAISE :: Brush_Type.RAISE;
FLUX_BRUSH_CARVE :: Brush_Type.CARVE;
FLUX_BRUSH_HEAT  :: Brush_Type.HEAT;

Flux_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Flux_Compute_Control :: struct {
    cursor_uv: Vector2;
    cursor_delta_uv: Vector2;
    brush_radius_px: float;
    brush_strength: float;
    time_scale: float;
    use_b_as_src: u32;
    brush_active: u32;
    brush_mode: Brush_Type;
    frame_index: u32;
}

Flux_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Flux_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
    world_pos: Vector3;
    shadow_uvz: Vector3;
}

Flux_Fragment_In :: struct {
    uv: Vector2;
    world_pos: Vector3;
    shadow_uvz: Vector3;
}

Flux_Debug_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Flux_Debug_Fragment_In :: struct {
    uv: Vector2;
}

Flux_Sky_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Flux_Sky_Fragment_In :: struct {
    uv: Vector2;
}

Flux_Shadow_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    depth01: float;
}

Flux_Shadow_Fragment_In :: struct {
    depth01: float;
}

Flux_Grass_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Flux_Grass_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    shadow_uvz: Vector3;
    blade_t: float;
}

Flux_Grass_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    shadow_uvz: Vector3;
    blade_t: float;
}

flux_cell_index :: (x: u32, y: u32) -> u32 {
    return y * FLUX_WIDTH + x;
}

flux_clamp_index :: (coord: s64, limit: u32) -> u32 {
    if coord < 0 return 0;
    upper := cast(s64) limit - 1;
    if coord > upper return cast(u32) upper;
    return cast(u32) coord;
}

flux_sample_clamped :: (state: *Vector4, src_offset: u32, x: s64, y: s64) -> Vector4 {
    sx := flux_clamp_index(x, FLUX_WIDTH);
    sy := flux_clamp_index(y, FLUX_HEIGHT);
    return state[src_offset + flux_cell_index(sx, sy)];
}

flux_fract :: (x: float) -> float {
    return x - floor(x);
}

flux_hash01 :: (x: u32, y: u32, frame_index: u32) -> float {
    s := sin(cast(float) x * cast(float) 12.9898 + cast(float) y * cast(float) 78.233 + cast(float) frame_index * cast(float) 0.173);
    return flux_fract(s * cast(float) 43758.5453);
}

flux_rand01_from_id :: (id: u32, mul: float, add: float) -> float {
    return flux_fract((cast(float) id + 0.5) * mul + add);
}

flux_safe_normalize3 :: (v: Vector3) -> Vector3 {
    len2 := v.x * v.x + v.y * v.y + v.z * v.z;
    if len2 < 0.000001 return .{0.0, 0.0, 1.0};
    inv := 1.0 / sqrt(len2);
    return .{v.x * inv, v.y * inv, v.z * inv};
}

flux_sky_base_color :: (view_dir: Vector3, sun_dir: Vector3) -> Vector3 {
    upness := clamp(view_dir.z * 0.5 + 0.5, 0.0, 1.0);
    sun_dot := dot(view_dir, sun_dir);
    toward_sun := clamp((sun_dot + 0.15) / 1.15, 0.0, 1.0);
    away_from_sun := 1.0 - toward_sun;
    horizon := pow(1.0 - clamp(view_dir.z, 0.0, 1.0), 2.0);
    sun_elevation := clamp(sun_dir.z, -1.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);

    night_zenith := Vector3.{0.004, 0.006, 0.012};
    night_horizon := Vector3.{0.008, 0.006, 0.005};
    day_zenith := Vector3.{0.18, 0.34, 0.72};
    day_horizon := Vector3.{0.62, 0.70, 0.86};
    zenith_col := mix(night_zenith, day_zenith, day_t);
    horizon_col := mix(night_horizon, day_horizon, day_t);
    base := mix(horizon_col, zenith_col, upness);
    base = base * mix(0.82, 1.0 - horizon * 0.22, day_t);

    sunset_orange := Vector3.{1.18, 0.42, 0.09};
    twilight_blue := Vector3.{0.08, 0.18, 0.42};
    base += sunset_orange * (horizon * twilight_t * toward_sun * 0.55);
    base += twilight_blue * (twilight_t * away_from_sun * (0.18 + upness * 0.42));
    return base;
}

flux_sky_color :: (view_dir: Vector3, sun_dir: Vector3) -> Vector3 {
    sun_dot := dot(view_dir, sun_dir);
    sun_amount := clamp(sun_dot, 0.0, 1.0);
    sun_elevation := clamp(sun_dir.z, -1.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    base := flux_sky_base_color(view_dir, sun_dir);

    sun_glow := pow(sun_amount, 18.0) * 0.42;
    sun_core := pow(sun_amount, 140.0);
    warm_day := Vector3.{1.0, 0.74, 0.44};
    warm_twilight := Vector3.{1.25, 0.48, 0.12};
    warm := mix(warm_day, warm_twilight, twilight_t);

    night_glow_scale := mix(0.35, 1.0, day_t + twilight_t * 0.45);
    return base + warm * (sun_glow + sun_core * 1.2) * night_glow_scale;
}

flux_param_camera_pos_proj_x :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_CAMERA_POS_PROJ_X]; }
flux_param_camera_right_proj_y :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_CAMERA_RIGHT_PROJ_Y]; }
flux_param_camera_up_near :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_CAMERA_UP_NEAR]; }
flux_param_camera_forward_far :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_CAMERA_FORWARD_FAR]; }
flux_param_light_right_extent :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_LIGHT_RIGHT_EXTENT]; }
flux_param_light_up_near :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_LIGHT_UP_NEAR]; }
flux_param_light_forward_far :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_LIGHT_FORWARD_FAR]; }
flux_param_light_center_use_b_as_src :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_LIGHT_CENTER_USE_B_AS_SRC]; }
flux_param_shadow_tex_sampler_bias_texel :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_SHADOW_TEX_SAMPLER_BIAS_TEXEL]; }
flux_param_sun_dir_xz_scale :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_SUN_DIR_XZ_SCALE]; }
flux_param_fog_time_wind_gain :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_FOG_TIME_WIND_GAIN]; }
flux_param_grass_count_spacing_scale :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_GRASS_COUNT_SPACING_SCALE]; }
flux_param_grass_spawn_lod :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_GRASS_SPAWN_LOD]; }
flux_param_grass_fade_near_far :: (payload: *Vector4) -> Vector4 { return payload[FLUX_PARAM_GRASS_FADE_NEAR_FAR]; }

flux_sim_src_offset :: (payload: *Vector4) -> u32 {
    use_b_f := flux_param_light_center_use_b_as_src(payload).w;
    if use_b_f >= 0.5 return FLUX_STATE_OFFSET + FLUX_CELL_COUNT;
    return FLUX_STATE_OFFSET;
}

flux_read_state_uv :: (payload: *Vector4, uv: Vector2) -> Vector4 {
    u := clamp(uv.x, 0.0, 1.0);
    v := clamp(uv.y, 0.0, 1.0);
    px := cast(u32) floor(u * cast(float) (FLUX_WIDTH - 1));
    py := cast(u32) floor(v * cast(float) (FLUX_HEIGHT - 1));
    return payload[flux_sim_src_offset(payload) + flux_cell_index(px, py)];
}

flux_grass_data_at :: (payload: *Vector4, instance_id: u32) -> Vector4 {
    return payload[FLUX_GRASS_DATA_OFFSET + instance_id];
}

flux_decode_world_pos :: (vertex_id: u32, payload: *Vector4, uv_out: *Vector2) -> Vector3 {
    tri_id := vertex_id / 3;
    tri_corner := vertex_id % 3;
    cell_id := tri_id / 2;
    tri_in_cell := tri_id % 2;
    cells_x := FLUX_MESH_WIDTH - 1;

    cx := cell_id % cells_x;
    cy := cell_id / cells_x;

    ox: u32;
    oy: u32;
    if tri_in_cell == 0 {
        if tri_corner == 0 { ox = 0; oy = 0; }
        else if tri_corner == 1 { ox = 1; oy = 0; }
        else { ox = 1; oy = 1; }
    } else {
        if tri_corner == 0 { ox = 0; oy = 0; }
        else if tri_corner == 1 { ox = 1; oy = 1; }
        else { ox = 0; oy = 1; }
    }

    gx := cx + ox;
    gy := cy + oy;
    fx := cast(float) gx / cast(float) (FLUX_MESH_WIDTH - 1);
    fy := cast(float) gy / cast(float) (FLUX_MESH_HEIGHT - 1);
    uv_out.* = .{fx, fy};

    sample := flux_read_state_uv(payload, uv_out.*);
    h := sample.x;

    xz_scale := max(flux_param_sun_dir_xz_scale(payload).w, 0.0001);
    wx := (fx * 2.0 - 1.0) * xz_scale;
    wy := (fy * 2.0 - 1.0) * xz_scale;
    wz := h * 0.34;
    return .{wx, wy, wz};
}

flux_project_camera :: (world_pos: Vector3, payload: *Vector4) -> Vector4 {
    p0 := flux_param_camera_pos_proj_x(payload);
    p1 := flux_param_camera_right_proj_y(payload);
    p2 := flux_param_camera_up_near(payload);
    p3 := flux_param_camera_forward_far(payload);
    cam_pos := Vector3.{p0.x, p0.y, p0.z};
    cam_right := Vector3.{p1.x, p1.y, p1.z};
    cam_up := Vector3.{p2.x, p2.y, p2.z};
    cam_forward := Vector3.{p3.x, p3.y, p3.z};
    proj_x := p0.w;
    proj_y := p1.w;
    z_near := p2.w;
    z_far := p3.w;

    rel := world_pos - cam_pos;
    vx := dot(rel, cam_right);
    vy := dot(rel, cam_up);
    vz := dot(rel, cam_forward);

    clip_x := vx * proj_x;
    clip_y := vy * proj_y;
    a := z_far / max(z_far - z_near, 0.0001);
    b := (-z_near * z_far) / max(z_far - z_near, 0.0001);
    clip_z := a * vz + b;

    return .{clip_x, clip_y, clip_z, vz};
}

flux_project_light :: (world_pos: Vector3, payload: *Vector4) -> Vector3 {
    p4 := flux_param_light_right_extent(payload);
    p5 := flux_param_light_up_near(payload);
    p6 := flux_param_light_forward_far(payload);
    p7 := flux_param_light_center_use_b_as_src(payload);
    light_right := Vector3.{p4.x, p4.y, p4.z};
    light_up := Vector3.{p5.x, p5.y, p5.z};
    light_forward := Vector3.{p6.x, p6.y, p6.z};
    light_extent := p4.w;
    light_near := p5.w;
    light_far := p6.w;
    light_center := Vector3.{p7.x, p7.y, p7.z};

    rel := world_pos - light_center;
    lx := dot(rel, light_right);
    ly := dot(rel, light_up);
    lz := dot(rel, light_forward);

    ndc_x := lx / max(light_extent, 0.0001);
    ndc_y := ly / max(light_extent, 0.0001);
    ndc_z := (lz - light_near) / max(light_far - light_near, 0.0001);
    return .{ndc_x, ndc_y, ndc_z};
}

flux_init_compute :: (using in: Flux_Compute_In, state: *Vector4) {
    if thread_id.x >= FLUX_CELL_COUNT return;

    i := thread_id.x;
    x := i % FLUX_WIDTH;
    y := i / FLUX_WIDTH;
    fx := cast(float) x / cast(float) FLUX_WIDTH;
    fy := cast(float) y / cast(float) FLUX_HEIGHT;

    h1 := sin(fx * 9.2) * 0.34;
    h2 := cos(fy * 11.4) * 0.30;
    h3 := sin((fx + fy * 0.7) * 18.8) * 0.14;
    ridge := sin((fx * 2.0 - fy * 1.7) * 27.0) * 0.08;
    crater_x := fx - 0.72;
    crater_y := fy - 0.43;
    crater := exp(-(crater_x * crater_x + crater_y * crater_y) * 84.0) * 0.85;
    hot_x := fx - 0.22;
    hot_y := fy - 0.72;
    hot_spot := exp(-(hot_x * hot_x + hot_y * hot_y) * 120.0);

    height := h1 + h2 + h3 + ridge - crater;
    temp := 0.08 + hot_spot * 1.4;
    vx := (fy - 0.5) * 0.06;
    vy := -(fx - 0.5) * 0.06;
    state[i] = .{height*1.2, vx, vy, temp};
} @compute_shader

flux_step_compute :: (using in: Flux_Compute_In, state: *Vector4, control: *Flux_Compute_Control) {
    if thread_id.x >= FLUX_CELL_COUNT return;
    dt := FLUX_DT * clamp(control[0].time_scale, 0.0, 4.0);

    src_offset: u32 = 0;
    dst_offset: u32 = FLUX_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = FLUX_CELL_COUNT;
        dst_offset = 0;
    }

    i := thread_id.x;
    x := i % FLUX_WIDTH;
    y := i / FLUX_WIDTH;
    sx := cast(s64) x;
    sy := cast(s64) y;

    center := state[src_offset + i];
    left := flux_sample_clamped(state, src_offset, sx - 1, sy);
    right := flux_sample_clamped(state, src_offset, sx + 1, sy);
    up := flux_sample_clamped(state, src_offset, sx, sy - 1);
    down := flux_sample_clamped(state, src_offset, sx, sy + 1);

    h := center.x;
    vx := center.y;
    vy := center.z;
    temp := center.w;

    grad_x := (right.x - left.x) * 0.5;
    grad_y := (down.x - up.x) * 0.5;
    lap_h := left.x + right.x + up.x + down.x - h * 4.0;

    vx += (-grad_x * FLUX_FLOW_ACCEL + lap_h * 0.004) * dt;
    vy += (-grad_y * FLUX_FLOW_ACCEL + lap_h * 0.004) * dt;

    rnd := flux_hash01(x, y, control[0].frame_index);
    angle := rnd * 6.2831853;
    thermal_push := temp * temp;
    vx += cos(angle) * FLUX_FORCING * thermal_push;
    vy += sin(angle) * FLUX_FORCING * thermal_push;

    div_v := ((right.y - left.y) + (down.z - up.z)) * 0.5;
    next_h := h - div_v * dt + lap_h * FLUX_HEIGHT_DIFFUSION * dt;

    temp_lap := left.w + right.w + up.w + down.w - temp * 4.0;
    next_temp := (temp + temp_lap * FLUX_TEMP_DIFFUSION * dt) * FLUX_TEMP_COOLING;

    if control[0].brush_active != 0 {
        cursor_x := control[0].cursor_uv.x * cast(float) FLUX_WIDTH;
        cursor_y := control[0].cursor_uv.y * cast(float) FLUX_HEIGHT;
        cell_x := cast(float) x + 0.5;
        cell_y := cast(float) y + 0.5;
        dx := cell_x - cursor_x;
        dy := cell_y - cursor_y;
        dist2 := dx * dx + dy * dy;
        brush_r2 := control[0].brush_radius_px * control[0].brush_radius_px;
        if dist2 < brush_r2 {
            falloff := 1.0 - dist2 / brush_r2;
            impulse_x := control[0].cursor_delta_uv.x * cast(float) FLUX_WIDTH;
            impulse_y := control[0].cursor_delta_uv.y * cast(float) FLUX_HEIGHT;
            vx += impulse_x * 0.08 * falloff;
            vy += impulse_y * 0.08 * falloff;

            brush_amount := control[0].brush_strength * falloff;
            if control[0].brush_mode == FLUX_BRUSH_RAISE {
                next_h += brush_amount;
            } else if control[0].brush_mode == FLUX_BRUSH_CARVE {
                next_h -= brush_amount;
            } else if control[0].brush_mode == FLUX_BRUSH_HEAT {
                next_temp += brush_amount * 0.9;
                next_h += brush_amount * 0.12;
            }
        }
    }

    vx *= FLUX_VEL_DAMPING;
    vy *= FLUX_VEL_DAMPING;
    next_h = clamp(next_h, -FLUX_MAX_HEIGHT, FLUX_MAX_HEIGHT);
    vx = clamp(vx, -FLUX_MAX_VEL, FLUX_MAX_VEL);
    vy = clamp(vy, -FLUX_MAX_VEL, FLUX_MAX_VEL);
    next_temp = clamp(next_temp, 0.0, FLUX_MAX_TEMP);

    state[dst_offset + i] = .{next_h, vx, vy, next_temp};
} @compute_shader

flux_grass_spawn_compute :: (using in: Flux_Grass_Compute_In, payload: *Vector4) {
    if thread_id.x >= FLUX_GRASS_INSTANCE_COUNT return;

    id := thread_id.x;
    p11 := flux_param_grass_count_spacing_scale(payload);
    blade_count := cast(u32) max(p11.x, 0.0);
    spacing := max(p11.y, 0.05);
    if id >= blade_count {
        payload[FLUX_GRASS_DATA_OFFSET + id] = .{0.0, 0.0, 0.0, 0.0};
        return;
    }

    u := flux_rand01_from_id(id, 0.7548777, 0.1213);
    v := flux_rand01_from_id(id, 0.5698403, 0.9175);
    uv := Vector2.{u, v};

    center := flux_read_state_uv(payload, uv);
    du := 1.0 / cast(float) FLUX_WIDTH;
    dv := 1.0 / cast(float) FLUX_HEIGHT;
    left := flux_read_state_uv(payload, .{uv.x - du, uv.y});
    right := flux_read_state_uv(payload, .{uv.x + du, uv.y});
    up := flux_read_state_uv(payload, .{uv.x, uv.y - dv});
    down := flux_read_state_uv(payload, .{uv.x, uv.y + dv});

    grad_x := (right.x - left.x) * 0.5;
    grad_y := (down.x - up.x) * 0.5;
    slope := sqrt(grad_x * grad_x + grad_y * grad_y);

    xz_scale := max(flux_param_sun_dir_xz_scale(payload).w, 0.0001);
    wx := (u * 2.0 - 1.0) * xz_scale;
    wy := (v * 2.0 - 1.0) * xz_scale;
    wz := center.x * 0.34;

    keep_prob := 1.0 / (spacing * spacing);
    p0 := flux_param_camera_pos_proj_x(payload);
    cam_xy := Vector2.{p0.x, p0.y};
    to_cam_x := wx - cam_xy.x;
    to_cam_y := wy - cam_xy.y;
    cam_dist := sqrt(to_cam_x * to_cam_x + to_cam_y * to_cam_y);
    p12 := flux_param_grass_spawn_lod(payload);
    spawn_near := max(p12.x, 0.0);
    spawn_far := max(p12.y, spawn_near + 0.001);
    spawn_near_boost := max(p12.z, 0.0);
    spawn_far_density := max(p12.w, 0.0);
    lod_t := clamp((cam_dist - spawn_near) / (spawn_far - spawn_near), 0.0, 1.0);
    density_mul := mix(spawn_near_boost, spawn_far_density, lod_t);
    keep_prob = clamp(keep_prob * density_mul, 0.0, 1.0);
    keep_roll := flux_rand01_from_id(id, 0.4385780, 0.3317);
    spawn_mask := 0.0;
    if slope < 0.20 && center.w < 1.35 && center.x > -3.0 {
        if keep_roll <= keep_prob {
            spawn_mask = 1.0;
        }
    }

    payload[FLUX_GRASS_DATA_OFFSET + id] = .{wx, wy, wz, spawn_mask};
} @compute_shader

flux_shadow_vertex_main :: (using in: Flux_Vertex_In, payload: *Vector4) -> Flux_Shadow_Vertex_Out {
    using out: Flux_Shadow_Vertex_Out;
    local_uv: Vector2;
    world := flux_decode_world_pos(vertex_id, payload, *local_uv);
    lndc := flux_project_light(world, payload);
    gl_Position = .{lndc.x, lndc.y, clamp(lndc.z, 0.0, 1.0), 1.0};
    depth01 = clamp(lndc.z, 0.0, 1.0);
    return out;
} @vertex_shader

flux_shadow_fragment_main :: (using in: Flux_Shadow_Fragment_In, payload: *Vector4) -> struct { out_color: Vector4; } {
    _ = payload;
    d := clamp(depth01, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

flux_vertex_main :: (using in: Flux_Vertex_In, payload: *Vector4) -> Flux_Vertex_Out {
    using out: Flux_Vertex_Out;
    world_pos = flux_decode_world_pos(vertex_id, payload, *uv);
    gl_Position = flux_project_camera(world_pos, payload);

    lndc := flux_project_light(world_pos, payload);
    shadow_uvz = .{lndc.x * 0.5 + 0.5, lndc.y * 0.5 + 0.5, lndc.z};
    return out;
} @vertex_shader

flux_shadow_visibility :: (payload: *Vector4, shadow_uvz: Vector3) -> float {
    p8 := flux_param_shadow_tex_sampler_bias_texel(payload);
    tex_idx := cast(u32) p8.x;
    samp_idx := cast(u32) p8.y;
    bias := p8.z;
    texel := p8.w;

    u := shadow_uvz.x;
    // Render-target UV convention differs from clip-space Y; flip for shadow lookup.
    v := 1.0 - shadow_uvz.y;
    z := shadow_uvz.z;

    if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 return 1.0;

    // 2x2 PCF
    t0 := sample_2d(tex_idx, samp_idx, .{u - texel, v - texel});
    t1 := sample_2d(tex_idx, samp_idx, .{u + texel, v - texel});
    t2 := sample_2d(tex_idx, samp_idx, .{u - texel, v + texel});
    t3 := sample_2d(tex_idx, samp_idx, .{u + texel, v + texel});
    s0 := t0.x;
    s1 := t1.x;
    s2 := t2.x;
    s3 := t3.x;

    lit: float = 0.0;
    if z <= s0 + bias lit += 1.0;
    if z <= s1 + bias lit += 1.0;
    if z <= s2 + bias lit += 1.0;
    if z <= s3 + bias lit += 1.0;

    return mix(0.28, 1.0, lit * 0.25);
}

flux_fragment_main :: (using in: Flux_Fragment_In, payload: *Vector4) -> struct { out_color: Vector4; } {
    c := flux_read_state_uv(payload, uv);
    h := c.x;
    vx := c.y;
    vy := c.z;
    temp := c.w;

    du := 1.0 / cast(float) FLUX_WIDTH;
    dv := 1.0 / cast(float) FLUX_HEIGHT;
    c_left := flux_read_state_uv(payload, .{uv.x - du, uv.y});
    c_right := flux_read_state_uv(payload, .{uv.x + du, uv.y});
    c_up := flux_read_state_uv(payload, .{uv.x, uv.y - dv});
    c_down := flux_read_state_uv(payload, .{uv.x, uv.y + dv});
    h_left := c_left.x;
    h_right := c_right.x;
    h_up := c_up.x;
    h_down := c_down.x;

    grad_x := (h_right - h_left) * 0.5;
    grad_y := (h_down - h_up) * 0.5;

    n := flux_safe_normalize3(.{-grad_x * 12.0, -grad_y * 12.0, 1.0});
    p9 := flux_param_sun_dir_xz_scale(payload);
    light_dir := flux_safe_normalize3(.{p9.x, p9.y, p9.z});
    ndotl := clamp(dot(n, light_dir), 0.0, 1.0);

    speed := clamp(sqrt(vx * vx + vy * vy), 0.0, 1.0);
    ht := clamp(h * 0.5 + 0.5, 0.0, 1.0);
    tt := clamp(temp / FLUX_MAX_TEMP, 0.0, 1.0);

    low := Vector3.{0.030, 0.055, 0.120};
    mid := Vector3.{0.085, 0.240, 0.440};
    ridge := Vector3.{0.680, 0.790, 0.860};
    heat := Vector3.{1.000, 0.520, 0.140};

    base := Vector3.{
        mix(low.x, mid.x, ht),
        mix(low.y, mid.y, ht),
        mix(low.z, ridge.z, ht),
    };
    base = mix(base, ridge, clamp(ht * ht, 0.0, 1.0));
    base = mix(base, heat, tt * 0.65);

    shadow := flux_shadow_visibility(payload, shadow_uvz);

    ambient := 0.22 + 0.18 * clamp(n.z, 0.0, 1.0);
    diffuse := 0.82 * ndotl * shadow;
    rim := pow(1.0 - clamp(n.z, 0.0, 1.0), 2.4) * 0.16;
    flow_sheen := speed * 0.16;

    color := base * (ambient + diffuse + rim) + Vector3.{flow_sheen, flow_sheen * 0.8, flow_sheen * 0.6};
    p0 := flux_param_camera_pos_proj_x(payload);
    p10 := flux_param_fog_time_wind_gain(payload);
    cam_pos := Vector3.{p0.x, p0.y, p0.z};
    fog_density := max(p10.x, 0.0);
    fog_exponent := max(p10.y, 0.0001);
    view_vec := world_pos - cam_pos;
    dist := sqrt(max(dot(view_vec, view_vec), 0.0));
    view_dir := flux_safe_normalize3(view_vec);
    sky_col := flux_sky_base_color(view_dir, light_dir);
    fog_term := pow(max(dist * fog_density, 0.0), fog_exponent);
    fog := 1.0 - exp(-fog_term);
    fog = clamp(fog, 0.0, 1.0);
    color = mix(color, sky_col, fog);
    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

flux_debug_shadow_vertex_main :: (using in: Flux_Vertex_In, payload: *Vector4) -> Flux_Debug_Vertex_Out {
    using out: Flux_Debug_Vertex_Out;
    _ = payload;

    x0 := 0.56;
    x1 := 0.98;
    y0 := 0.56;
    y1 := 0.98;

    if vertex_id == 0 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{x1, y0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{x0, y1, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

flux_debug_shadow_fragment_main :: (using in: Flux_Debug_Fragment_In, payload: *Vector4) -> struct { out_color: Vector4; } {
    p8 := flux_param_shadow_tex_sampler_bias_texel(payload);
    tex_idx := cast(u32) p8.x;
    samp_idx := cast(u32) p8.y;
    s := sample_2d(tex_idx, samp_idx, .{uv.x, 1.0 - uv.y});
    d := clamp(s.x, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

flux_sky_vertex_main :: (using in: Flux_Vertex_In, payload: *Vector4) -> Flux_Sky_Vertex_Out {
    using out: Flux_Sky_Vertex_Out;
    _ = payload;
    if vertex_id == 0 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{1.0, -1.0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{-1.0, 1.0, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

flux_sky_fragment_main :: (using in: Flux_Sky_Fragment_In, payload: *Vector4) -> struct { out_color: Vector4; } {
    p0 := flux_param_camera_pos_proj_x(payload);
    p1 := flux_param_camera_right_proj_y(payload);
    p2 := flux_param_camera_up_near(payload);
    p3 := flux_param_camera_forward_far(payload);
    p9 := flux_param_sun_dir_xz_scale(payload);

    cam_right := Vector3.{p1.x, p1.y, p1.z};
    cam_up := Vector3.{p2.x, p2.y, p2.z};
    cam_forward := Vector3.{p3.x, p3.y, p3.z};
    proj_x := p0.w;
    proj_y := p1.w;
    sun_dir := flux_safe_normalize3(.{p9.x, p9.y, p9.z});

    ndc_x := uv.x * 2.0 - 1.0;
    ndc_y := uv.y * 2.0 - 1.0;
    view_dir := flux_safe_normalize3(cam_forward + cam_right * (ndc_x / max(proj_x, 0.0001)) + cam_up * (ndc_y / max(proj_y, 0.0001)));

    color := flux_sky_color(view_dir, sun_dir);

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

flux_grass_vertex_main :: (using in: Flux_Vertex_In, payload: *Vector4) -> Flux_Grass_Vertex_Out {
    using out: Flux_Grass_Vertex_Out;

    entry := flux_grass_data_at(payload, instance_id);
    active := entry.w;
    if active < 0.5 {
        gl_Position = .{0.0, 0.0, 2.0, 1.0};
        world_pos = .{0.0, 0.0, 0.0};
        normal = .{0.0, 0.0, 1.0};
        shadow_uvz = .{0.0, 0.0, 2.0};
        blade_t = 0.0;
        return out;
    }

    base := Vector3.{entry.x, entry.y, entry.z};
    id := instance_id;
    tau := cast(float) 6.28318530718;
    r0 := flux_rand01_from_id(id, 0.8191725, 0.2179);
    r1 := flux_rand01_from_id(id, 0.6710436, 0.4891);
    r2 := flux_rand01_from_id(id, 0.5129028, 0.7334);

    yaw := r0 * tau;
    right := Vector3.{cos(yaw), sin(yaw), 0.0};
    tangent := Vector3.{-right.y, right.x, 0.0};

    blade_scale := max(flux_param_grass_count_spacing_scale(payload).z, 0.05);
    h := mix(0.07, 0.17, r1) * blade_scale;
    w := h * mix(0.12, 0.20, r2);

    vx: float;
    vt: float;
    if vertex_id == 0 { vx = -1.0; vt = 0.0; }
    else if vertex_id == 1 { vx =  1.0; vt = 0.0; }
    else if vertex_id == 2 { vx = -0.32; vt = 1.0; }
    else if vertex_id == 3 { vx =  1.0; vt = 0.0; }
    else if vertex_id == 4 { vx =  0.32; vt = 1.0; }
    else { vx = -0.32; vt = 1.0; }

    p10 := flux_param_fog_time_wind_gain(payload);
    wind_time := p10.z;
    wind_gain := max(p10.w, 0.0);
    wind_dir := flux_safe_normalize3(.{sin(wind_time * 0.19), cos(wind_time * 0.23), 0.0});
    sway := sin(wind_time * 1.8 + r2 * 12.0 + base.x * 0.9 + base.y * 1.1) * (0.06 + wind_gain * 0.26) * blade_scale;
    bend := sway * vt * vt;

    world_pos = base + right * (vx * w) + Vector3.{0.0, 0.0, vt * h} + wind_dir * bend;
    gl_Position = flux_project_camera(world_pos, payload);

    tip_dir := flux_safe_normalize3(.{wind_dir.x * bend, wind_dir.y * bend, 1.0});
    n := flux_safe_normalize3(cross(tangent, tip_dir));
    normal = n;
    blade_t = vt;

    lndc := flux_project_light(world_pos, payload);
    shadow_uvz = .{lndc.x * 0.5 + 0.5, lndc.y * 0.5 + 0.5, lndc.z};
    return out;
} @vertex_shader

flux_grass_fragment_main :: (using in: Flux_Grass_Fragment_In, payload: *Vector4) -> struct { out_color: Vector4; } {
    p0 := flux_param_camera_pos_proj_x(payload);
    p9 := flux_param_sun_dir_xz_scale(payload);
    p10 := flux_param_fog_time_wind_gain(payload);
    p13 := flux_param_grass_fade_near_far(payload);
    light_dir := flux_safe_normalize3(.{p9.x, p9.y, p9.z});
    n := flux_safe_normalize3(normal);
    ndotl := clamp(dot(n, light_dir), 0.0, 1.0);
    shadow := flux_shadow_visibility(payload, shadow_uvz);

    low := Vector3.{0.065, 0.20, 0.07};
    high := Vector3.{0.26, 0.56, 0.17};
    base := mix(low, high, blade_t);
    ambient := 0.24;
    diffuse := 0.85 * ndotl * shadow;
    col := base * (ambient + diffuse);

    cam_pos := Vector3.{p0.x, p0.y, p0.z};
    view_vec := world_pos - cam_pos;
    dist := sqrt(max(dot(view_vec, view_vec), 0.0));
    fade_start := max(p13.x, 0.0);
    fade_end := max(p13.y, fade_start + 0.001);
    fade_t := clamp((fade_end - dist) / (fade_end - fade_start), 0.0, 1.0);
    if fade_t <= 0.0 {
        discard();
    }
    dither_seed := world_pos.x * cast(float) 12.9898 + world_pos.y * cast(float) 78.233 + world_pos.z * cast(float) 37.719 + blade_t * cast(float) 5.173;
    dither := flux_fract(sin(dither_seed) * cast(float) 43758.5453);
    if dither > fade_t {
        discard();
    }
    fog_density := max(p10.x, 0.0);
    fog_exponent := max(p10.y, 0.0001);
    view_dir := flux_safe_normalize3(view_vec);
    sky_col := flux_sky_base_color(view_dir, light_dir);
    fog_term := pow(max(dist * fog_density, 0.0), fog_exponent);
    fog := clamp(1.0 - exp(-fog_term), 0.0, 1.0);
    col = mix(col, sky_col, fog);

    return .{out_color = .{col.x, col.y, col.z, 1.0}};
} @fragment_shader
