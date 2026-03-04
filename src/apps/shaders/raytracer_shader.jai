Raytracer_Vertex_In :: struct {
    vertex_id: u32; @semantic_SV_VertexID
}

Raytracer_Vertex_Out :: struct {
    position: Vector4; @semantic_SV_Position
    uv: Vector2; @semantic_TEXCOORD0
}

Raytracer_Params :: struct {
    resolution: Vector2;
    mouse_uv: Vector2;
    camera_pos: Vector3;
    time: float;
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

raytracer_fragment_main :: (using in: Raytracer_Vertex_Out, params: *Raytracer_Params) -> struct { out_color: Vector4; } {
    // Camera ray setup.
    p := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
    aspect := params.resolution.x / max(params.resolution.y, 1.0);
    p.x *= aspect;

    yaw := (params.mouse_uv.x - 0.5) * 0.9;
    pitch := (-0.5 + params.mouse_uv.y) * 1.1;
    pitch = clamp(pitch, -1.2, 1.2);
    cos_pitch := cos(pitch);
    ro := params.camera_pos;
    forward := Vector3.{sin(yaw) * cos_pitch, sin(pitch), -cos(yaw) * cos_pitch};
    forward /= max(sqrt(dot(forward, forward)), 0.00001);
    right := cross(forward, Vector3.{0.0, 1.0, 0.0});
    right /= max(sqrt(dot(right, right)), 0.00001);
    up := cross(right, forward);
    up /= max(sqrt(dot(up, up)), 0.00001);
    rd := forward + right * p.x * 0.85 + up * p.y * 0.85;
    rd /= max(sqrt(dot(rd, rd)), 0.00001);
    // Small camera-relative avatar sphere. Offset mostly behind camera so it appears in reflections.
    avatar_center := params.camera_pos + right * 0.28 + up * 0.16 - forward * 0.22;
    avatar_radius := 0.31;
    avatar_color := Vector3.{0.92, 0.96, 1.00};

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
                cx := cast(int) floor(hit_pos.x);
                cz := cast(int) floor(hit_pos.z);
                checker := (cx + cz) & 1;
                if checker == 0 hit_albedo = .{0.88, 0.88, 0.90};
                else hit_albedo = .{0.18, 0.18, 0.20};
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
        sphere_refl := float.[0.45, 0.65, 0.55, 0.88];

        for s, i: spheres {
            center := Vector3.{s.x, s.y, s.z};
            oc := ro - center;
            b := dot(oc, rd);
            c := dot(oc, oc) - s.w * s.w;
            h := b * b - c;
            if h < 0.0 continue;
            q := sqrt(h);
            t0 := -b - q;
            t1 := -b + q;
            t := t0;
            if t < 0.001 t = t1;
            if t < 0.001 continue;
            if t >= best_t continue;

            best_t = t;
            hit_found = true;
            hit_pos = ro + rd * t;
            hit_nrm = hit_pos - center;
            hit_nrm /= max(sqrt(dot(hit_nrm, hit_nrm)), 0.00001);
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

        oc_avatar := ro - avatar_center;
        b_avatar := dot(oc_avatar, rd);
        c_avatar := dot(oc_avatar, oc_avatar) - avatar_radius * avatar_radius;
        h_avatar := b_avatar * b_avatar - c_avatar;
        if h_avatar >= 0.0 {
            q_avatar := sqrt(h_avatar);
            t0_avatar := -b_avatar - q_avatar;
            t1_avatar := -b_avatar + q_avatar;
            t_avatar := t0_avatar;
            if t_avatar < 0.001 t_avatar = t1_avatar;
            if t_avatar > 0.001 && t_avatar < best_t {
                best_t = t_avatar;
                hit_found = true;
                hit_pos = ro + rd * t_avatar;
                hit_nrm = hit_pos - avatar_center;
                hit_nrm /= max(sqrt(dot(hit_nrm, hit_nrm)), 0.00001);
                hit_albedo = avatar_color;
                hit_refl = 0.96;
            }
        }

        if !hit_found {
            sky_t := clamp(0.5 * (rd.y + 1.0), 0.0, 1.0);
            sky_a := Vector3.{0.72, 0.84, 1.00};
            sky_b := Vector3.{0.08, 0.11, 0.16};
            sky := sky_a + (sky_b - sky_a) * sky_t;
            accum += throughput * sky;
            break;
        }

        sun_dir := Vector3.{0.55, 0.92, 0.35};
        sun_dir /= max(sqrt(dot(sun_dir, sun_dir)), 0.00001);
        ndl := max(dot(hit_nrm, sun_dir), 0.0);
        diffuse := hit_albedo * (0.10 + 0.90 * ndl);
        h := sun_dir - rd;
        h /= max(sqrt(dot(h, h)), 0.00001);
        spec := pow(max(dot(hit_nrm, h), 0.0), 70.0);
        spec_base := Vector3.{0.04, 0.04, 0.04};
        spec_tint := spec_base + (hit_albedo - spec_base) * hit_refl;
        lit := diffuse + spec_tint * spec;

        accum += throughput * lit * (1.0 - hit_refl);
        throughput *= hit_albedo + (Vector3.{1.0, 1.0, 1.0} - hit_albedo) * hit_refl;

        ro = hit_pos + hit_nrm * 0.004;
        rd = rd - hit_nrm * (2.0 * dot(rd, hit_nrm));
        rd /= max(sqrt(dot(rd, rd)), 0.00001);

        if bounce == 3 {
            sky_t := clamp(0.5 * (rd.y + 1.0), 0.0, 1.0);
            sky_a := Vector3.{0.72, 0.84, 1.00};
            sky_b := Vector3.{0.08, 0.11, 0.16};
            sky := sky_a + (sky_b - sky_a) * sky_t;
            accum += throughput * sky;
        }
    }

    mapped := accum / (accum + Vector3.{1.0, 1.0, 1.0});
    gamma := Vector3.{sqrt(mapped.x), sqrt(mapped.y), sqrt(mapped.z)};
    return .{out_color = .{gamma.x, gamma.y, gamma.z, 1.0}};
} @fragment_shader
