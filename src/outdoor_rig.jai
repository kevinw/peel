
Outdoor_Rig :: struct {
    sun_strength: float = 1.0;
    time_of_day: float = 0.4;
}

do_ui :: (rig: *Outdoor_Rig) {
    ImGui.SliderFloat("Sun Strength", *rig.sun_strength, 0.0, 3.0, "%.2f");
    Persist.SliderFloat("Time of Day", *rig.time_of_day, 0.0, 1.0, "%.2f px");
}

update :: (rig: *Outdoor_Rig, shadow_map: *Shadow_Map) {
    rig.time_of_day = clamp(rig.time_of_day, 0.0, 1.0);
    rig.sun_strength = clamp(rig.sun_strength, 0.0, 3.0);
    sun_dir := sun_direction(rig.*);
    shadow_map.light_dir = -sun_dir;
    shadow_map.center = .{0.0, 2.0, -12.0};
    shadow_map.extent = 18.0;
    shadow_map.distance = 20.0;
    shadow_map.near_plane = 0.1;
    shadow_map.far_plane = 48.0;
    shadow_map.bias = 0.0035;
    shadow_map_update_view_proj(shadow_map);
}

sun_direction :: (rig: Outdoor_Rig) -> Vector3 {
    tau := cast(float) 6.28318530718;
    phase := (rig.time_of_day - 0.25) * tau;
    elevation := sin(phase) * cast(float) 0.92;
    horizontal := sqrt(max(1.0 - elevation * elevation, 0.0001));
    return normalize(Vector3.{cos(phase) * horizontal, elevation, sin(phase) * horizontal * 0.55});
}

fill_sky_params :: (rig: Outdoor_Rig, params: *Model_Scene_Sky_Params_CPU, cam_forward: Vector3, cam_right: Vector3, cam_up: Vector3, proj: Matrix4, light_dir: Vector3) {
    if params == null return;
    params.* = .{
        camera_right_proj_x = .{cam_right.x, cam_right.y, cam_right.z, proj._11},
        camera_up_proj_y = .{cam_up.x, cam_up.y, cam_up.z, proj._22},
        camera_forward_time_of_day = vec4(cam_forward, rig.time_of_day),
        light_dir_sun_strength = .{light_dir.x, light_dir.y, light_dir.z, rig.sun_strength},
    };
}

apply_scene_lighting :: (rig: Outdoor_Rig, params: []Scene_Draw_Params_CPU, view_proj: Matrix4, camera_pos: Vector3, light_dir: Vector3) {
    for *params {
        it.view_proj = view_proj;
        it.camera_pos = camera_pos;
        it.light_dir = light_dir;
        it.sun_params = .{rig.sun_strength, rig.time_of_day, 0.0, 0.0};
    }
}

apply_ground_lighting :: (rig: Outdoor_Rig, shadow_params: *Scene_Draw_Params_CPU, draw_params: *Ground_Draw_Params_CPU, view_proj: Matrix4, camera_pos: Vector3, light_dir: Vector3) {
    shadow_params.view_proj = view_proj;
    shadow_params.camera_pos = camera_pos;
    shadow_params.light_dir = light_dir;
    shadow_params.sun_params = .{rig.sun_strength, rig.time_of_day, 0.0, 0.0};

    draw_params.view_proj = view_proj;
    draw_params.camera_pos = camera_pos;
    draw_params.light_dir = light_dir;
    draw_params.sun_params = .{rig.sun_strength, rig.time_of_day, 0.0, 0.0};
}

apply_grass_lighting :: (rig: Outdoor_Rig, shadow_params: *Grass_Shadow_Params_CPU, draw_params: *Gpu_Buffer(Grass_Draw_Params), active_ground: Scene_File.Scene_Procedural_Ground_Desc, lizard_pos: Vector3, lizard_facing_yaw: float, now: float, view_proj: Matrix4, camera_pos: Vector3, light_dir: Vector3, shadow_view_proj: Matrix4, shadow_binding: Vector4) {
    if draw_params.cpu == null return;
    shadow_params.shadow_view_proj = shadow_view_proj;
    shadow_params.ground_size_center_z_time = .{active_ground.size_x, active_ground.size_z, active_ground.center_z, now};
    shadow_params.ground_shape = .{active_ground.ridge, active_ground.swell, active_ground.warp, 0.0};
    shadow_params.player_pos_radius = .{lizard_pos.x, lizard_facing_yaw, lizard_pos.z, 1.9};

    draw_params.shadow_view_proj = shadow_params.shadow_view_proj;
    draw_params.ground_size_center_z_time = shadow_params.ground_size_center_z_time;
    draw_params.ground_shape = shadow_params.ground_shape;
    draw_params.grass_grid_height_width = shadow_params.grass_grid_height_width;
    draw_params.player_pos_radius = shadow_params.player_pos_radius;
    draw_params.view_proj = view_proj;
    draw_params.camera_pos = camera_pos;
    draw_params.light_dir = light_dir;
    draw_params.sun_params = .{rig.sun_strength, rig.time_of_day, 0.0, 0.0};
    draw_params.shadow_meta = shadow_binding;
}
