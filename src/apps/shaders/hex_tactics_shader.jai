#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

Hex_Tactics_Vertex :: struct {
    pos: Vector4;
    normal: Vector4;
    color: Vector4;
    material: Vector4;
}

Hex_Tactics_Mesh_Params :: struct {
    vertices: *Hex_Tactics_Vertex;
    indices: *u32;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
}

Hex_Tactics_Grass_Instance :: struct {
    base: Vector4;
    tint: Vector4;
}

Hex_Tactics_Grass_Params :: struct {
    instances: *Hex_Tactics_Grass_Instance;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    time: float;
    _pad2: Vector3;
}

Hex_Tactics_Sky_Params :: struct {
    camera_right_proj_x: Vector4;
    camera_up_proj_y: Vector4;
    camera_forward_time_of_day: Vector4;
    light_dir_sun_strength: Vector4;
}

Hex_Tactics_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Hex_Tactics_Mesh_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4; @color
    material: Vector4;
}

Hex_Tactics_Mesh_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4; @color
    material: Vector4;
}

Hex_Tactics_Grass_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    blade_t: float;
    tint: Vector4; @color
}

Hex_Tactics_Grass_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    blade_t: float;
    tint: Vector4; @color
}

Hex_Tactics_Sky_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Hex_Tactics_Sky_Fragment_In :: struct {
    uv: Vector2;
}

hex_tactics_hash01 :: (x: float) -> float {
    v := sin(x * cast(float) 12.9898 + cast(float) 78.233) * cast(float) 43758.5453;
    return v - floor(v);
}

hex_tactics_sky_base_color :: (view_dir: Vector3, sun_dir: Vector3) -> Vector3 {
    upness := clamp(view_dir.y * 0.5 + 0.5, 0.0, 1.0);
    sun_dot := dot(view_dir, sun_dir);
    toward_sun := clamp((sun_dot + 0.15) / 1.15, 0.0, 1.0);
    away_from_sun := 1.0 - toward_sun;
    horizon := pow(1.0 - clamp(view_dir.y, 0.0, 1.0), 2.0);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);

    night_zenith := Vector3.{0.006, 0.008, 0.018};
    night_horizon := Vector3.{0.016, 0.013, 0.013};
    day_zenith := Vector3.{0.18, 0.34, 0.75};
    day_horizon := Vector3.{0.70, 0.78, 0.92};
    zenith_col := mix(night_zenith, day_zenith, day_t);
    horizon_col := mix(night_horizon, day_horizon, day_t);
    base := mix(horizon_col, zenith_col, upness);
    base = base * mix(0.84, 1.0 - horizon * 0.2, day_t);

    sunset_orange := Vector3.{1.12, 0.46, 0.14};
    twilight_blue := Vector3.{0.09, 0.17, 0.36};
    base += sunset_orange * (horizon * twilight_t * toward_sun * 0.56);
    base += twilight_blue * (twilight_t * away_from_sun * (0.15 + upness * 0.34));
    return base;
}

hex_tactics_apply_atmosphere :: (color: Vector3, world_pos: Vector3, camera_pos: Vector3, sun_dir: Vector3) -> Vector3 {
    view_vec := world_pos - camera_pos;
    dist := sqrt(max(dot(view_vec, view_vec), 0.0));
    fog := 1.0 - exp(-dist * 0.026);
    fog = clamp(fog, 0.0, 0.66);
    sky_col := hex_tactics_sky_base_color(safe_normalize3(view_vec, .{0.0, 0.2, 1.0}), sun_dir);
    return mix(color, sky_col, fog);
}

hex_tactics_mesh_vertex_main :: (using in: Hex_Tactics_Vertex_In, using params: *Hex_Tactics_Mesh_Params) -> Hex_Tactics_Mesh_Vertex_Out {
    idx := indices[vertex_id];
    v := vertices[idx];

    using out: Hex_Tactics_Mesh_Vertex_Out;
    world_pos = .{v.pos.x, v.pos.y, v.pos.z};
    gl_Position = view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    normal = safe_normalize3(v.normal.xyz);
    base_color = v.color;
    material = v.material;
    return out;
} @vertex_shader

hex_tactics_mesh_fragment_main :: (using in: Hex_Tactics_Mesh_Fragment_In, params: *Hex_Tactics_Mesh_Params) -> Vector4 @SV_Target0 {
    base_rgb := Vector3.{base_color.x, base_color.y, base_color.z};
    roughness := clamp(material.x, 0.04, 1.0);
    metallic := clamp(material.y, 0.0, 1.0);
    ao := clamp(material.z, 0.0, 1.0);
    sun_dir := safe_normalize3(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);

    N := safe_normalize3(normal);
    V := safe_normalize3(params.camera_pos - world_pos, .{0.0, 0.0, 1.0});
    L := sun_dir;
    H := safe_normalize3(L + V, sun_dir);
    ndl_raw := dot(N, L);
    wrapped_ndl := clamp((ndl_raw + 0.26) / 1.26, 0.0, 1.0);
    ndh := max(dot(N, H), 0.0);

    indirect := indirect_light(N, sun_dir, sun_strength, ao);
    spec_power := mix(48.0, 6.0, roughness);
    spec_strength := mix(0.16, 0.03, roughness) * mix(1.0, 1.65, metallic);
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    direct := base_rgb * wrapped_ndl * 0.76 * sun_strength;
    specular := sun_col * pow(ndh, spec_power) * spec_strength * sun_strength;
    rim := pow(1.0 - max(dot(N, V), 0.0), 2.2) * 0.045;
    color := base_rgb * indirect + direct + specular + base_rgb * rim * 0.08;
    color = hex_tactics_apply_atmosphere(color, world_pos, params.camera_pos, sun_dir);
    return .{color.x, color.y, color.z, base_color.w};
} @fragment_shader

hex_tactics_grass_vertex_main :: (using in: Hex_Tactics_Vertex_In, params: *Hex_Tactics_Grass_Params) -> Hex_Tactics_Grass_Vertex_Out {
    using out: Hex_Tactics_Grass_Vertex_Out;
    inst := params.instances[instance_id];
    base := Vector3.{inst.base.x, inst.base.y, inst.base.z};
    blade_height := inst.base.w;
    blade_t = ifx vertex_id == 0 || vertex_id == 1 || vertex_id == 3 then 0.0 else 1.0;
    blade_x := ifx vertex_id == 0 then -1.0 else ifx vertex_id == 1 then 1.0 else ifx vertex_id == 2 then -0.28 else ifx vertex_id == 3 then 1.0 else ifx vertex_id == 4 then 0.28 else -0.28;

    phase := hex_tactics_hash01(base.x * 0.21 + base.z * 0.13 + cast(float) instance_id * 0.17) * 6.2831855;
    yaw := hex_tactics_hash01(base.x * 0.07 + base.z * 0.31 + cast(float) instance_id * 0.11) * 6.2831855;
    right := Vector3.{cos(yaw), 0.0, sin(yaw)};
    wind := sin(params.time * 1.25 + phase) * 0.15 + cos(params.time * 0.73 + phase * 1.7) * 0.08;
    tip_dir := safe_normalize3(Vector3.{sin(yaw) * 0.25 + wind * 0.65, 1.0, cos(yaw) * 0.25 + wind * 0.22});

    blade_width := max(blade_height * 0.11, 0.012);
    pos := base + right * (blade_x * blade_width) + .{0.0, blade_t * blade_height, 0.0};
    pos += tip_dir * (blade_t * blade_t * 0.08);

    side := safe_normalize3(cross(Vector3.{0.0, 1.0, 0.0}, tip_dir), .{1.0, 0.0, 0.0});
    normal = safe_normalize3(cross(side, tip_dir));
    world_pos = pos;
    gl_Position = params.view_proj * Vector4.{pos.x, pos.y, pos.z, 1.0};
    tint = inst.tint;
    return out;
} @vertex_shader

hex_tactics_grass_fragment_main :: (using in: Hex_Tactics_Grass_Fragment_In, params: *Hex_Tactics_Grass_Params) -> Vector4 @SV_Target0 {
    base := Vector3.{tint.x, tint.y, tint.z} * mix(Vector3.{0.32, 0.26, 0.12}, Vector3.{0.78, 0.72, 0.32}, blade_t);
    N := safe_normalize3(normal);
    sun_dir := safe_normalize3(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);
    V := safe_normalize3(params.camera_pos - world_pos, .{0.0, 0.0, 1.0});
    H := safe_normalize3(sun_dir + V, sun_dir);
    ndl_raw := dot(N, sun_dir);
    wrapped_ndl := clamp((ndl_raw + 0.34) / 1.34, 0.0, 1.0);
    indirect := indirect_light(N, sun_dir, sun_strength, 1.0);
    specular := pow(max(dot(N, H), 0.0), 14.0) * 0.028 * sun_strength;
    rim := pow(1.0 - max(dot(N, V), 0.0), 2.3) * 0.09;
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    color := base * indirect + base * wrapped_ndl * 0.7 * sun_strength + sun_col * specular + base * rim;
    color = hex_tactics_apply_atmosphere(color, world_pos, params.camera_pos, sun_dir);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader

hex_tactics_sky_vertex_main :: (using in: Hex_Tactics_Vertex_In, params: *Hex_Tactics_Sky_Params) -> Hex_Tactics_Sky_Vertex_Out {
    using out: Hex_Tactics_Sky_Vertex_Out;
    _ = params;
    if vertex_id == 0 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{1.0, -1.0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{-1.0, 1.0, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

hex_tactics_sky_fragment_main :: (using in: Hex_Tactics_Sky_Fragment_In, using params: *Hex_Tactics_Sky_Params) -> struct { out_color: Vector4; } {
    proj_x := camera_right_proj_x.w;
    proj_y := camera_up_proj_y.w;
    sun_dir := safe_normalize3(-light_dir_sun_strength.xyz);
    sun_strength := max(light_dir_sun_strength.w, 0.0);

    ndc := uv * 2.0 - 1.0;
    view_dir := safe_normalize3(
        camera_forward_time_of_day.xyz +
        camera_right_proj_x.xyz * (ndc.x / max(proj_x, 0.0001)) +
        camera_up_proj_y.xyz * (ndc.y / max(proj_y, 0.0001)), .{0.0, 0.0, 1.0});
    color := sky_color(view_dir, sun_dir, sun_strength);
    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

#scope_file

sky_color :: (view_dir: Vector3, sun_dir: Vector3, sun_strength: float) -> Vector3 {
    sun_dot := dot(view_dir, sun_dir);
    sun_amount := clamp(sun_dot, 0.0, 1.0);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    base := hex_tactics_sky_base_color(view_dir, sun_dir);

    sun_glow := pow(sun_amount, 18.0) * 0.38;
    sun_core := pow(sun_amount, 140.0);
    warm_day := Vector3.{1.0, 0.77, 0.47};
    warm_twilight := Vector3.{1.24, 0.52, 0.18};
    warm := mix(warm_day, warm_twilight, twilight_t);
    glow_scale := max(sun_strength, 0.0) * mix(0.35, 1.0, day_t + twilight_t * 0.45);
    return base + warm * (sun_glow + sun_core * 1.25) * glow_scale;
}

indirect_light :: (N: Vector3, sun_dir: Vector3, sun_strength: float, ao: float) -> Vector3 {
    upness := clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    horizonness := 1.0 - abs(N.y);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);

    sky_zenith := hex_tactics_sky_base_color(Vector3.{0.0, 1.0, 0.0}, sun_dir);
    sky_horizon := hex_tactics_sky_base_color(safe_normalize3(Vector3.{0.0, 0.08, 1.0}), sun_dir);
    sky_fill := mix(sky_horizon, sky_zenith, upness) * (0.34 + horizonness * 0.08);

    ground_day := Vector3.{0.22, 0.19, 0.12};
    ground_twilight := Vector3.{0.29, 0.17, 0.09};
    ground_fill := mix(ground_day, ground_twilight, twilight_t) * (1.0 - upness) * (0.18 + sun_strength * 0.12);
    return (sky_fill + ground_fill) * ao;
}

safe_normalize3 :: (v: Vector3, fallback: Vector3 = .{0.0, 1.0, 0.0}) -> Vector3 {
    len2 := dot(v, v);
    if len2 < 0.000001 return fallback;
    return v * (1.0 / sqrt(len2));
}
