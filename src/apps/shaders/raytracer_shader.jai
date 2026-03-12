Raytracer_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Raytracer_Vertex_Out :: struct {
    position: Vector4; @SV_Position
    uv: Vector2; @TEXCOORD0
}

Raytracer_Params :: struct {
    camera_pos: Vector3;
    time: float;

    cam_forward: Vector3;
    aspect: float;

    cam_right: Vector3;
    pad_1: float;

    cam_up: Vector3;
    pad_2: float;

    inv_viewport: Vector2;
    pad_3: Vector2;

    cube0_center_refl: Vector4;
    cube0_half_pad: Vector4;
    cube0_color_pad: Vector4;
    cube0_rotation: Vector4;
    cube1_center_refl: Vector4;
    cube1_half_pad: Vector4;
    cube1_color_pad: Vector4;
    cube1_rotation: Vector4;
}

raytracer_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    qv := q.xyz;
    t := cross(qv, v) * 2.0;
    return v + t * q.w + cross(qv, t);
}

raytracer_inverse_rotate_quat :: (v: Vector3, q: Vector4) -> Vector3 {
    return raytracer_rotate_quat(v, .{-q.x, -q.y, -q.z, q.w});
}

raytracer_make_camera_ray :: (p: Vector2, params: *Raytracer_Params) -> Vector3 {
    rd := params.cam_forward + params.cam_right * p.x * FOV_FACTOR + params.cam_up * p.y * FOV_FACTOR;
    rd /= max(sqrt(dot(rd, rd)), 0.00001);
    return rd;
}

raytracer_safe_normalize :: (v: Vector3) -> Vector3 {
    return v / max(sqrt(dot(v, v)), 0.00001);
}

raytracer_checker_at :: (x: float, z: float) -> Vector3 {
    cx := cast(int) floor(x);
    cz := cast(int) floor(z);
    checker := (cx + cz) & 1;
    if checker == 0 return .{0.88, 0.88, 0.90};
    return .{0.18, 0.18, 0.20};
}

raytracer_floor_hit :: (ro: Vector3, rd: Vector3, hit_pos: *Vector3) -> float {
    if abs(rd.y) <= 0.0001 return -1.0;
    t_floor := (-1.0 - ro.y) / rd.y;
    if t_floor <= 0.001 return -1.0;
    hit_pos.* = ro + rd * t_floor;
    return t_floor;
}

raytracer_checker_aniso :: (
    ro: Vector3,
    center_p: Vector2,
    center_hit: Vector3,
    params: *Raytracer_Params,
) -> Vector3 {
    mean_checker := Vector3.{0.53, 0.53, 0.55};
    dp_x := Vector2.{2.0 * params.aspect * params.inv_viewport.x, 0.0};
    dp_y := Vector2.{0.0, 2.0 * params.inv_viewport.y};

    hit_x, hit_y: Vector3;
    rd_x := raytracer_make_camera_ray(center_p + dp_x, params);
    rd_y := raytracer_make_camera_ray(center_p + dp_y, params);
    t_x := raytracer_floor_hit(ro, rd_x, *hit_x);
    t_y := raytracer_floor_hit(ro, rd_y, *hit_y);
    if t_x < 0.0 || t_y < 0.0 return raytracer_checker_at(center_hit.x, center_hit.z);

    dx_x := hit_x.x - center_hit.x;
    dx_z := hit_x.z - center_hit.z;
    dy_x := hit_y.x - center_hit.x;
    dy_z := hit_y.z - center_hit.z;
    dx_len_sq := dx_x * dx_x + dx_z * dx_z;
    dy_len_sq := dy_x * dy_x + dy_z * dy_z;

    major_x := dx_x;
    major_z := dx_z;
    minor_x := dy_x;
    minor_z := dy_z;
    if dy_len_sq > dx_len_sq {
        major_x = dy_x;
        major_z = dy_z;
        minor_x = dx_x;
        minor_z = dx_z;
    }

    major_len := sqrt(major_x * major_x + major_z * major_z);
    minor_len := sqrt(minor_x * minor_x + minor_z * minor_z);
    // Near the horizon the floor footprint explodes, so fade to the checker average.
    if major_len > 12.0 return mean_checker;
    ratio := major_len / max(minor_len, 0.0001);

    taps := 1;
    if ratio > 16.0 {
        taps = 8;
    } else if ratio > 8.0 {
        taps = 6;
    } else if ratio > 4.0 {
        taps = 4;
    } else if ratio > 2.0 {
        taps = 2;
    }

    accum := Vector3.{0.0, 0.0, 0.0};
    for i: 0..taps-1 {
        u := (cast(float) i + 0.5) / cast(float) taps - 0.5;
        sample_x := center_hit.x + major_x * u;
        sample_z := center_hit.z + major_z * u;
        accum += raytracer_checker_at(sample_x, sample_z);
    }

    filtered := accum / cast(float) taps;
    fade := clamp((major_len - 4.0) / 8.0, 0.0, 1.0);
    return filtered + (mean_checker - filtered) * fade;
}

raytracer_hit_obb :: (
    ro: Vector3,
    rd: Vector3,
    center: Vector3,
    half_extents: Vector3,
    rotation: Vector4,
    best_t: *float,
    hit_pos: *Vector3,
    hit_nrm: *Vector3,
) -> bool {
    local_ro := raytracer_inverse_rotate_quat(ro - center, rotation);
    local_rd := raytracer_inverse_rotate_quat(rd, rotation);

    inv_rd := Vector3.{1.0 / local_rd.x, 1.0 / local_rd.y, 1.0 / local_rd.z};
    bmin := -half_extents;
    bmax := half_extents;
    t0 := (bmin - local_ro) * inv_rd;
    t1 := (bmax - local_ro) * inv_rd;

    tmin_x := ifx t0.x < t1.x then t0.x else t1.x;
    tmin_y := ifx t0.y < t1.y then t0.y else t1.y;
    tmin_z := ifx t0.z < t1.z then t0.z else t1.z;
    tmax_x := ifx t0.x > t1.x then t0.x else t1.x;
    tmax_y := ifx t0.y > t1.y then t0.y else t1.y;
    tmax_z := ifx t0.z > t1.z then t0.z else t1.z;

    t_enter_xy := ifx tmin_x > tmin_y then tmin_x else tmin_y;
    t_enter := ifx t_enter_xy > tmin_z then t_enter_xy else tmin_z;
    t_exit_xy := ifx tmax_x < tmax_y then tmax_x else tmax_y;
    t_exit := ifx t_exit_xy < tmax_z then t_exit_xy else tmax_z;
    if t_exit < 0.0 || t_enter > t_exit return false;

    t_box := t_enter;
    if t_box < 0.001 t_box = t_exit;
    if t_box < 0.001 || t_box >= best_t.* return false;

    p_local := local_ro + local_rd * t_box;
    nrm_local := Vector3.{0.0, 0.0, 0.0};
    bias := 0.0015;
    sx := ifx p_local.x >= 0.0 then 1.0 else -1.0;
    sy := ifx p_local.y >= 0.0 then 1.0 else -1.0;
    sz := ifx p_local.z >= 0.0 then 1.0 else -1.0;
    if abs(abs(p_local.x) - half_extents.x) < bias {
        nrm_local = .{sx, 0.0, 0.0};
    } else if abs(abs(p_local.y) - half_extents.y) < bias {
        nrm_local = .{0.0, sy, 0.0};
    } else {
        nrm_local = .{0.0, 0.0, sz};
    }

    best_t.* = t_box;
    hit_pos.* = ro + rd * t_box;
    hit_nrm.* = raytracer_rotate_quat(nrm_local, rotation);
    hit_nrm.* /= max(sqrt(dot(hit_nrm.*, hit_nrm.*)), 0.00001);
    return true;
}

raytracer_hit_sphere :: (
    ro: Vector3,
    rd: Vector3,
    center: Vector3,
    radius: float,
    best_t: *float,
    hit_pos: *Vector3,
    hit_nrm: *Vector3,
) -> bool {
    oc := ro - center;
    b := dot(oc, rd);
    c := dot(oc, oc) - radius * radius;
    h := b * b - c;
    if h < 0.0 return false;

    q := sqrt(h);
    t0 := -b - q;
    t1 := -b + q;
    t := t0;
    if t < 0.001 t = t1;
    if t < 0.001 || t >= best_t.* return false;

    best_t.* = t;
    hit_pos.* = ro + rd * t;
    hit_nrm.* = raytracer_safe_normalize(hit_pos.* - center);
    return true;
}

raytracer_sky_color :: (rd: Vector3, sun_dir: Vector3) -> Vector3 {
    sky_t := clamp(0.5 * (rd.y + 1.0), 0.0, 1.0);
    horizon := clamp(1.0 - abs(rd.y), 0.0, 1.0);
    base_a := Vector3.{0.75, 0.86, 1.00};
    base_b := Vector3.{0.10, 0.12, 0.18};
    sky := base_a + (base_b - base_a) * sky_t;
    sun_dot := clamp(dot(rd, sun_dir), 0.0, 1.0);
    sun_glow := pow(sun_dot, 24.0) * 0.32 + pow(sun_dot, 320.0) * 5.5;
    warm_horizon := Vector3.{1.00, 0.70, 0.38} * horizon * 0.08;
    return sky + warm_horizon + Vector3.{1.00, 0.92, 0.78} * sun_glow;
}

raytracer_shadow_visibility :: (
    ro: Vector3,
    sun_dir: Vector3,
    params: *Raytracer_Params,
    avatar_center: Vector3,
    avatar_radius: float,
) -> float {
    shadow_t := cast(float) 100000.0;
    shadow_pos, shadow_nrm: Vector3;

    wobble := sin(params.time * 0.85) * 0.35;
    spheres := Vector4.[
        .{-1.90, -0.35, -4.9, 0.65},
        .{-0.55, -0.15 + wobble * 0.25, -3.9, 0.85},
        .{0.95, -0.20, -4.5, 0.80},
        .{2.35, -0.45, -5.6, 0.55},
    ];

    for s: spheres {
        center := Vector3.{s.x, s.y, s.z};
        if raytracer_hit_sphere(ro, sun_dir, center, s.w, *shadow_t, *shadow_pos, *shadow_nrm) return 0.0;
    }

    cube_center_refl := Vector4.[params.cube0_center_refl, params.cube1_center_refl];
    cube_half_pad := Vector4.[params.cube0_half_pad, params.cube1_half_pad];
    cube_rotation := Vector4.[params.cube0_rotation, params.cube1_rotation];
    for i: 0..1 {
        he := cube_half_pad[i].xyz;
        if he.x <= 0.0 || he.y <= 0.0 || he.z <= 0.0 continue;
        center := cube_center_refl[i].xyz;
        if raytracer_hit_obb(ro, sun_dir, center, he, cube_rotation[i], *shadow_t, *shadow_pos, *shadow_nrm) return 0.0;
    }

    if raytracer_hit_sphere(ro, sun_dir, avatar_center, avatar_radius, *shadow_t, *shadow_pos, *shadow_nrm) return 0.0;
    return 1.0;
}

raytracer_vertex_main :: (using in: Raytracer_Vertex_In) -> Raytracer_Vertex_Out {
    using out: Raytracer_Vertex_Out;
    if vertex_id == 0 {
        position = .{-1.0, -1.0, 0.0, 1.0};
        uv = .{0.0, 0.0};
    } else if vertex_id == 1 {
        position = .{3.0, -1.0, 0.0, 1.0};
        uv = .{2.0, 0.0};
    } else {
        position = .{-1.0, 3.0, 0.0, 1.0};
        uv = .{0.0, 2.0};
    }
    return out;
} @vertex_shader

raytracer_fragment_main :: (using in: Raytracer_Vertex_Out, using params: *Raytracer_Params) -> struct { out_color: Vector4; } {
    // Camera ray setup.
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    p.x *= params.aspect;

    ro := params.camera_pos;
    rd := raytracer_make_camera_ray(p, params);

    // Small camera-relative avatar sphere. Offset mostly behind camera so it appears in reflections.
    avatar_center := params.camera_pos + cam_right * 0.28 + cam_up * 0.16 - cam_forward * 0.22;
    avatar_radius := 0.31;
    avatar_color := Vector3.{0.92, 0.96, 1.00};
    sun_dir := raytracer_safe_normalize(Vector3.{0.42, 0.88, 0.20});
    sun_color := Vector3.{1.00, 0.94, 0.84};

    accum := Vector3.{0.0, 0.0, 0.0};
    throughput := Vector3.{1.0, 1.0, 1.0};

    for bounce: 0..3 {
        best_t := cast(float) 100000.0;
        hit_found := false;
        hit_pos := Vector3.{0.0, 0.0, 0.0};
        hit_nrm := Vector3.{0.0, 1.0, 0.0};
        hit_albedo := Vector3.{0.0, 0.0, 0.0};
        hit_refl := 0.0;

        // Checker floor (y = -1).
        if abs(rd.y) > 0.0001 {
            t_floor := (-1.0 - ro.y) / rd.y;
            if t_floor > 0.001 && t_floor < best_t {
                best_t = t_floor;
                hit_found = true;
                hit_pos = ro + rd * t_floor;
                hit_nrm = .{0.0, 1.0, 0.0};
                hit_albedo = raytracer_checker_aniso(ro, p, hit_pos, params);
                hit_refl = 0.06;
            }
        }

        wobble := sin(params.time * 0.85) * 0.35;
        spheres := Vector4.[
            .{-1.90, -0.35, -4.9, 0.65},
            .{-0.55, -0.15 + wobble * 0.25, -3.9, 0.85},
            .{0.95, -0.20, -4.5, 0.80},
            .{2.35, -0.45, -5.6, 0.55},
        ];
        sphere_colors := Vector3.[
            .{0.95, 0.25, 0.20},
            .{0.15, 0.60, 1.00},
            .{0.95, 0.88, 0.25},
            .{0.92, 0.92, 0.96},
        ];
        sphere_refl := float.[0.36, 0.52, 0.44, 0.76];

        for s, i: spheres {
            center := Vector3.{s.x, s.y, s.z};
            hit_sphere := raytracer_hit_sphere(ro, rd, center, s.w, *best_t, *hit_pos, *hit_nrm);
            if !hit_sphere continue;

            hit_found = true;
            hit_albedo = sphere_colors[i];
            hit_refl = sphere_refl[i];
        }

        cube_center_refl := Vector4.[params.cube0_center_refl, params.cube1_center_refl];
        cube_half_pad := Vector4.[params.cube0_half_pad, params.cube1_half_pad];
        cube_color_pad := Vector4.[params.cube0_color_pad, params.cube1_color_pad];
        cube_rotation := Vector4.[params.cube0_rotation, params.cube1_rotation];
        for i: 0..1 {
            center := cube_center_refl[i].xyz;
            he := cube_half_pad[i].xyz;
            if he.x <= 0.0 || he.y <= 0.0 || he.z <= 0.0 continue;

            hit_box := raytracer_hit_obb(ro, rd, center, he, cube_rotation[i], *best_t, *hit_pos, *hit_nrm);
            if !hit_box continue;

            hit_found = true;
            hit_albedo = cube_color_pad[i].xyz;
            hit_refl = cube_center_refl[i].w;
        }

        if raytracer_hit_sphere(ro, rd, avatar_center, avatar_radius, *best_t, *hit_pos, *hit_nrm) {
            hit_found = true;
            hit_albedo = avatar_color;
            hit_refl = 0.84;
        }

        if !hit_found {
            accum += throughput * raytracer_sky_color(rd, sun_dir);
            break;
        }

        shadow_origin := hit_pos + hit_nrm * 0.01;
        shadow_vis := raytracer_shadow_visibility(shadow_origin, sun_dir, params, avatar_center, avatar_radius);
        ndl := max(dot(hit_nrm, sun_dir), 0.0);
        ambient := hit_albedo * 0.12;
        bounce_fill := hit_albedo * (0.10 + 0.14 * max(hit_nrm.y, 0.0));
        sun_diffuse := hit_albedo * ndl * shadow_vis * 1.25;
        h := sun_dir - rd;
        h = raytracer_safe_normalize(h);
        spec := pow(max(dot(hit_nrm, h), 0.0), 70.0) * shadow_vis;
        spec_base := Vector3.{0.04, 0.04, 0.04};
        spec_tint := spec_base + (hit_albedo - spec_base) * hit_refl;
        lit := ambient + bounce_fill + sun_color * (sun_diffuse + spec_tint * spec * 1.1);

        accum += throughput * lit * (1.0 - hit_refl);
        throughput *= hit_albedo + (Vector3.{1.0, 1.0, 1.0} - hit_albedo) * hit_refl;

        ro = hit_pos + hit_nrm * 0.004;
        rd = rd - hit_nrm * (2.0 * dot(rd, hit_nrm));
        rd /= max(sqrt(dot(rd, rd)), 0.00001);

        if bounce == 3 {
            accum += throughput * raytracer_sky_color(rd, sun_dir);
        }
    }

    mapped := accum / (accum + Vector3.{1.0, 1.0, 1.0});
    gamma := Vector3.{sqrt(mapped.x), sqrt(mapped.y), sqrt(mapped.z)};
    return .{out_color = .{gamma.x, gamma.y, gamma.z, 1.0}};
} @fragment_shader
