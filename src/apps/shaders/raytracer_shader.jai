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
    camera_pos_xy: Vector2;
    camera_pos_z: float;
    time: float;
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
    ro := Vector3.{params.camera_pos_xy.x, params.camera_pos_xy.y, params.camera_pos_z};
    forward := Vector3.{sin(yaw), -0.18, -cos(yaw)};
    forward /= max(sqrt(dot(forward, forward)), 0.00001);
    right := cross(forward, Vector3.{0.0, 1.0, 0.0});
    right /= max(sqrt(dot(right, right)), 0.00001);
    up := cross(right, forward);
    up /= max(sqrt(dot(up, up)), 0.00001);
    rd := forward + right * p.x * 0.85 + up * p.y * 0.85;
    rd /= max(sqrt(dot(rd, rd)), 0.00001);
    // Small camera-relative avatar sphere. Offset mostly behind camera so it appears in reflections.
    avatar_center := Vector3.{params.camera_pos_xy.x, params.camera_pos_xy.y, params.camera_pos_z} + right * 0.28 + up * 0.16 - forward * 0.22;
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

        for i: 0..3 {
            s := spheres[i];
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
