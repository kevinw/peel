
Raymarch_Params :: struct {
    resolution: Vector2;
    mouse_uv: Vector2;
    current_time: float;
    _pad: float;
}

sphere_dist :: (p: Vector3, c: Vector3, r: float) -> float {
    q := Vector3.{p.x - c.x, p.y - c.y, p.z - c.z};
    return sqrt(q.x * q.x + q.y * q.y + q.z * q.z) - r;
}

box_dist :: (p: Vector3, b: Vector3) -> float {
    q := Vector3.{rm_abs(p.x) - b.x, rm_abs(p.y) - b.y, rm_abs(p.z) - b.z};
    outside := Vector3.{max(q.x, 0.0), max(q.y, 0.0), max(q.z, 0.0)};
    outside_len := sqrt(outside.x * outside.x + outside.y * outside.y + outside.z * outside.z);
    inside := min(max(q.x, max(q.y, q.z)), 0.0);
    return outside_len + inside;
}

torus_dist :: (p: Vector3, major_radius: float, minor_radius: float) -> float {
    ring := sqrt(p.x * p.x + p.z * p.z) - major_radius;
    return sqrt(ring * ring + p.y * p.y) - minor_radius;
}

hash2 :: (x: float, y: float) -> float {
    return fract(sin(x * cast(float) 127.1 + y * cast(float) 311.7) * cast(float) 43758.5453);
}

value_noise_2d :: (x: float, y: float) -> float {
    ix := floor(x);
    iy := floor(y);
    fx := fract(x);
    fy := fract(y);

    ux := fx * fx * (3.0 - 2.0 * fx);
    uy := fy * fy * (3.0 - 2.0 * fy);

    a := hash2(ix + 0.0, iy + 0.0);
    b := hash2(ix + 1.0, iy + 0.0);
    c := hash2(ix + 0.0, iy + 1.0);
    d := hash2(ix + 1.0, iy + 1.0);

    x0 := lerp(a, b, ux);
    x1 := lerp(c, d, ux);
    return lerp(x0, x1, uy);
}

rm_abs :: (x: float) -> float {
    if x < 0.0 return -x;
    return x;
}

capped_cylinder_dist :: (p: Vector3, center_y: float, half_h: float, radius: float) -> float {
    radial := sqrt(p.x * p.x + p.z * p.z) - radius;
    vertical := rm_abs(p.y - center_y) - half_h;
    if radial > vertical return radial;
    return vertical;
}

repeat_symmetric :: (x: float, spacing: float) -> float {
    return x - spacing * floor(x / spacing + 0.5);
}

repeat_positive :: (x: float, spacing: float) -> float {
    return x - spacing * floor(x / spacing);
}

tree_cell_index_x :: (world_x: float) -> float {
    return floor(world_x / 2.2 + 0.5);
}

tree_cell_index_z :: (world_z: float) -> float {
    return floor((world_z + 10.0) / 3.8);
}

tree_variation :: (p: Vector3) -> float {
    ix := tree_cell_index_x(p.x);
    iz := tree_cell_index_z(p.z);
    seed := ix * cast(float) 127.1 + iz * cast(float) 311.7;
    return fract(sin(seed) * cast(float) 43758.5453);
}

tree_cell_center :: (p: Vector3) -> Vector3 {
    x_spacing := 2.2;
    z_spacing := 3.8;

    ix := tree_cell_index_x(p.x);
    iz := tree_cell_index_z(p.z);

    base_center_x := ix * x_spacing;
    base_center_z := iz * z_spacing - 10.0;

    offset_x := (hash2(ix + 13.7, iz + 5.3) - 0.5) * x_spacing * 0.55;
    offset_z := (hash2(ix + 23.1, iz + 19.9) - 0.5) * z_spacing * 0.55;

    return .{base_center_x + offset_x, 0.0, base_center_z + offset_z};
}

tree_local_pos_from_world :: (p: Vector3) -> Vector3 {
    center := tree_cell_center(p);
    return .{p.x - center.x, p.y, p.z - center.z};
}

tree_trunk_dist :: (p: Vector3) -> float {
    tree_h := tree_variation(p);
    trunk_half_h := lerp(0.34, 0.56, tree_h);
    trunk_radius := lerp(0.070, 0.112, tree_h);
    trunk_center_y := -0.65 + trunk_half_h;
    q := tree_local_pos_from_world(p);
    return capped_cylinder_dist(q, trunk_center_y, trunk_half_h, trunk_radius);
}

tree_leaves_dist :: (p: Vector3) -> float {
    tree_h := tree_variation(p);
    scale := lerp(0.82, 1.26, tree_h);
    shift := (tree_h - 0.5) * 0.10;
    q := tree_local_pos_from_world(p);
    crown_a := sphere_dist(q, .{0.0 + shift * 0.5, 0.34 + tree_h * 0.14, 0.0}, 0.34 * scale);
    crown_b := sphere_dist(q, .{0.20 + shift, 0.30 + tree_h * 0.08, -0.08}, 0.26 * scale);
    crown_c := sphere_dist(q, .{-0.18 + shift * 0.6, 0.28 + tree_h * 0.10, 0.10}, 0.24 * scale);
    leaves := crown_a;
    if crown_b < leaves leaves = crown_b;
    if crown_c < leaves leaves = crown_c;
    return leaves;
}

tree_dist :: (p: Vector3) -> float {
  trunk := tree_trunk_dist(p);
  leaves := tree_leaves_dist(p);
  if leaves < trunk return leaves;
  return trunk;
}

plane_dist :: (p: Vector3) -> float {
    return p.y + 0.65;
}

terrain_height :: (x: float, z: float, time: float) -> float {
    wave_a := sin(x * 0.34 + z * 0.26 + time * 0.18) * 0.09;
    wave_b := sin(x * 0.92 - z * 0.41) * 0.04;
    radial := sqrt(x * x + z * z);
    bowl := -0.03 * radial;
    return -0.65 + wave_a + wave_b + bowl;
}

terrain_dist :: (p: Vector3, time: float) -> float {
    return p.y - terrain_height(p.x, p.z, time);
}

rock_dist :: (p: Vector3) -> float {
    spacing := 2.6;
    q := p;
    q.x = repeat_symmetric(p.x, spacing);
    q.z = repeat_symmetric(p.z, spacing);

    ix := floor(p.x / spacing + 0.5);
    iz := floor(p.z / spacing + 0.5);
    v := hash2(ix, iz);

    rock_y := -0.63 + (v - 0.5) * 0.10;
    local := Vector3.{q.x, p.y - rock_y, q.z};
    rock_box := box_dist(local, .{0.22 + 0.25 * v, 0.10 + 0.16 * v, 0.18 + 0.20 * (1.0 - v)});
    rock_cap := sphere_dist(local, .{0.0, 0.10, 0.0}, 0.25 + 0.14 * v);
    rock := ifx rock_box < rock_cap then rock_box else rock_cap;

    // Keep an open clearing around the origin.
    clearing := sqrt(p.x * p.x + p.z * p.z) - 1.35;
    if clearing < rock return clearing;
    return rock;
}

ruin_dist :: (p: Vector3, time: float) -> float {
    wobble := sin(time * 0.6) * 0.03;
    // Primary ruin: smaller and off-center.
    ring_p := Vector3.{p.x - 1.35, p.y + 0.02 + wobble, p.z - 1.9};
    ring := torus_dist(ring_p, 0.62, 0.08);

    pillar_a := capped_cylinder_dist(.{p.x - 1.88, p.y, p.z - 1.9}, -0.30, 0.32, 0.08);
    pillar_b := capped_cylinder_dist(.{p.x - 0.82, p.y, p.z - 1.9}, -0.30, 0.32, 0.08);
    pillars := ifx pillar_a < pillar_b then pillar_a else pillar_b;

    primary := ifx pillars < ring then pillars else ring;

    // Secondary fragment cluster for denser scenery.
    ring2_p := Vector3.{p.x + 1.05, p.y - 0.06 - wobble * 0.7, p.z - 0.35};
    ring2 := torus_dist(ring2_p, 0.34, 0.06);
    stub := capped_cylinder_dist(.{p.x + 1.28, p.y, p.z - 0.52}, -0.43, 0.18, 0.07);
    secondary := ifx stub < ring2 then stub else ring2;

    if secondary < primary return secondary;
    return primary;
}

cloud_density :: (p: Vector3, time: float) -> float {
    low := 1.25;
    high := 3.10;
    if p.y < low || p.y > high return 0.0;

    qx := p.x * 0.24 + time * 0.035;
    qz := p.z * 0.24 + time * 0.018;
    base := value_noise_2d(qx, qz);
    detail := value_noise_2d(qx * 2.3 + 7.2, qz * 2.3 - 3.7);
    shape := base * 0.72 + detail * 0.28;

    h0 := clamp((p.y - low) / (high - low), 0.0, 1.0);
    height_falloff := h0 * (1.0 - h0) * 4.0;
    density := (shape - 0.56) * 2.4 * height_falloff;
    return clamp(density, 0.0, 1.0);
}

scene_dist :: (p: Vector3, time: float) -> float {
    tree := tree_dist(p);
    terrain := terrain_dist(p, time);
    rocks := rock_dist(p);
    ruin := ruin_dist(p, time);

    d := tree;
    if terrain < d d = terrain;
    if rocks < d d = rocks;
    if ruin < d d = ruin;
    return d;
}

scene_normal :: (p: Vector3, time: float) -> Vector3 {
    eps := 0.001;
    ex := Vector3.{eps, 0, 0};
    ey := Vector3.{0, eps, 0};
    ez := Vector3.{0, 0, eps};
    nx := scene_dist(.{p.x + ex.x, p.y + ex.y, p.z + ex.z}, time) - scene_dist(.{p.x - ex.x, p.y - ex.y, p.z - ex.z}, time);
    ny := scene_dist(.{p.x + ey.x, p.y + ey.y, p.z + ey.z}, time) - scene_dist(.{p.x - ey.x, p.y - ey.y, p.z - ey.z}, time);
    nz := scene_dist(.{p.x + ez.x, p.y + ez.y, p.z + ez.z}, time) - scene_dist(.{p.x - ez.x, p.y - ez.y, p.z - ez.z}, time);
    return normalize(Vector3.{nx, ny, nz});
}

raymarch_fragment_main :: (using in: struct { uv: Vector2; }, params: *Raymarch_Params) -> struct { out_color: Vector4; } {
    time := params[0].current_time;

    uv_ndc := uv * 2.0 - 1.0;
    denom := params[0].resolution.y;
    if denom < 1.0 denom = 1.0;
    aspect := params[0].resolution.x / denom;
    uv_ndc.x *= aspect;

    camera_tilt := (params[0].mouse_uv.y - 0.5) * 0.7;
    camera_pan := (params[0].mouse_uv.x - 0.5) * 1.4;
    ro := Vector3.{sin(time * 0.23 + camera_pan) * 2.4, 1.0 + camera_tilt, -3.2};
    target := Vector3.{0.0, 0.05, 0.0};
    forward := normalize(Vector3.{target.x - ro.x, target.y - ro.y, target.z - ro.z});
    right := normalize(cross(Vector3.{0, 1, 0}, forward));
    up := cross(forward, right);
    rd := normalize(Vector3.{
        forward.x + right.x * uv_ndc.x + up.x * uv_ndc.y,
        forward.y + right.y * uv_ndc.x + up.y * uv_ndc.y,
        forward.z + right.z * uv_ndc.x + up.z * uv_ndc.y,
    });

    t := 0.0;
    hit := false;
    for 0..125 {
        p := Vector3.{ro.x + rd.x * t, ro.y + rd.y * t, ro.z + rd.z * t};
        d := scene_dist(p, time);
        if d < 0.0005 {
            hit = true;
            break;
        }
        t += d;
        if t > 24.0 break;
    }

    sky_top := Vector3.{0.06, 0.09, 0.16};
    sky_bottom := Vector3.{0.92, 0.63, 0.34};
    sky_mix := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := lerp(sky_bottom, sky_top, sky_mix);

    // Soft volumetric cloud integration in sky.
    cloud_alpha := 0.0;
    if rd.y > -0.08 {
        cloud_t := 2.0;
        transmittance := 1.0;
        sun_dir := normalize(Vector3.{0.55, 0.52, -0.64});
        silver := clamp(dot(rd, sun_dir), 0.0, 1.0);
        silver = silver * silver;

        for 0..20 {
            sample_pos := Vector3.{ro.x + rd.x * cloud_t, ro.y + rd.y * cloud_t, ro.z + rd.z * cloud_t};
            dens := cloud_density(sample_pos, time);
            if dens > 0.0001 {
                step_size := 0.55;
                a := clamp(dens * step_size * 0.9, 0.0, 0.32);
                cloud_alpha += transmittance * a;
                transmittance *= (1.0 - a);
                if transmittance < 0.04 break;
            }
            cloud_t += 0.55;
            if cloud_t > 24.0 break;
        }

        cloud_alpha = clamp(cloud_alpha, 0.0, 1.0);
        cloud_tint := Vector3.{0.94 + 0.06 * silver, 0.95 + 0.05 * silver, 0.98 + 0.02 * silver};
        color = .{
            lerp(color.x, cloud_tint.x, cloud_alpha),
            lerp(color.y, cloud_tint.y, cloud_alpha),
            lerp(color.z, cloud_tint.z, cloud_alpha),
        };
    }

    if hit {
        p := Vector3.{ro.x + rd.x * t, ro.y + rd.y * t, ro.z + rd.z * t};
        n := scene_normal(p, time);
        light := Vector3.{2.2 * sin(time * 0.8), 2.7, -2.0 + 1.2 * cos(time * 0.6)};
        l := normalize(.{light.x - p.x, light.y - p.y, light.z - p.z});
        v := normalize(.{ro.x - p.x, ro.y - p.y, ro.z - p.z});
        h := normalize(.{l.x + v.x, l.y + v.y, l.z + v.z});

        diff := clamp(dot(n, l), 0.0, 1.0);
        ndh := clamp(dot(n, h), 0.0, 1.0);
        spec := ndh * ndh;
        spec = spec * spec * spec * 0.8;

        q := tree_local_pos_from_world(p);
        tree_h := tree_variation(p);
        trunk_d, leaves_d := tree_trunk_dist(p), tree_leaves_dist(p);
        tree_d := ifx trunk_d < leaves_d then trunk_d else leaves_d;
        terrain_d := terrain_dist(p, time);
        rocks_d := rock_dist(p);
        ruin_d := ruin_dist(p, time);

        is_terrain := terrain_d <= tree_d && terrain_d <= rocks_d && terrain_d <= ruin_d;
        is_rock := !is_terrain && rocks_d <= tree_d && rocks_d <= ruin_d;
        is_ruin := !is_terrain && !is_rock && ruin_d <= tree_d;
        is_trunk := !is_terrain && !is_rock && !is_ruin && trunk_d <= leaves_d;

        base := Vector3.{0.16, 0.46 + 0.16 * tree_h, 0.18 + 0.12 * tree_h};
        if is_terrain {
            soil := Vector3.{0.14, 0.10, 0.08};
            moss := Vector3.{0.10, 0.22, 0.12};
            strata := clamp(0.5 + 0.5 * sin(p.x * 1.8 + p.z * 1.3), 0.0, 1.0);
            base = .{
                lerp(soil.x, moss.x, strata),
                lerp(soil.y, moss.y, strata),
                lerp(soil.z, moss.z, strata),
            };
        } else if is_rock {
            grain := clamp(0.5 + 0.5 * sin(p.x * 7.0 + p.z * 6.0 + p.y * 10.0), 0.0, 1.0);
            rock_a := Vector3.{0.24, 0.25, 0.28};
            rock_b := Vector3.{0.36, 0.34, 0.30};
            base = lerp(rock_a, rock_b, grain);
        } else if is_ruin {
            wear := clamp((p.y + 0.8) * 0.8, 0.0, 1.0);
            ruin_a := Vector3.{0.30, 0.30, 0.33};
            ruin_b := Vector3.{0.44, 0.41, 0.36};
            base = lerp(ruin_a, ruin_b, wear);
        } else if is_trunk {
            bark_mix := clamp((q.y + 0.65) * 0.9, 0.0, 1.0);
            bark_a := Vector3.{0.24 + 0.07 * tree_h, 0.15 + 0.04 * tree_h, 0.08};
            bark_b := Vector3.{0.34 + 0.08 * tree_h, 0.22 + 0.05 * tree_h, 0.11};
            base = lerp(bark_a, bark_b, bark_mix);
        }

        shadow := 1.0;
        shadow_t := 0.04;
        for 0..20 {
            sp := Vector3.{p.x + n.x * 0.015 + l.x * shadow_t, p.y + n.y * 0.015 + l.y * shadow_t, p.z + n.z * 0.015 + l.z * shadow_t};
            sd := scene_dist(sp, time);
            if sd < 0.001 {
                shadow = 0.30;
                break;
            }
            softness := 16.0 * sd / max(shadow_t, 0.001);
            if softness < shadow shadow = softness;
            shadow_t += clamp(sd, 0.02, 0.35);
            if shadow_t > 7.0 break;
        }
        shadow = clamp(shadow, 0.30, 1.0);

        ao := 1.0;
        ao = ao - clamp(0.55 - scene_dist(.{p.x + n.x * 0.10, p.y + n.y * 0.10, p.z + n.z * 0.10}, time) * 2.0, 0.0, 0.55);
        ao = ao - clamp(0.35 - scene_dist(.{p.x + n.x * 0.22, p.y + n.y * 0.22, p.z + n.z * 0.22}, time) * 1.2, 0.0, 0.35);
        ao = clamp(ao, 0.30, 1.0);

        ambient := 0.22;
        direct := diff * shadow * 0.95;
        lit := Vector3.{
            base.x * (ambient * ao + direct) + spec * shadow,
            base.y * (ambient * ao + direct) + spec * shadow,
            base.z * (ambient * ao + direct) + spec * shadow,
        };

        fog := clamp(1.0 / (1.0 + t * 0.12 + t * t * 0.02), 0.0, 1.0);
        color = Vector3.{
            lerp(color.x, lit.x, fog),
            lerp(color.y, lit.y, fog),
            lerp(color.z, lit.z, fog),
        };
    }

    vignette := clamp(1.0 - (uv_ndc.x * uv_ndc.x + uv_ndc.y * uv_ndc.y) * 0.18, 0.0, 1.0);
    color = .{color.x * vignette, color.y * vignette, color.z * vignette};
    color = .{
        clamp(color.x, 0.0, 1.0),
        clamp(color.y, 0.0, 1.0),
        clamp(color.z, 0.0, 1.0),
    };

    return .{
        out_color = .{
            color.x,
            color.y,
            color.z,
            1.0,
        },
    };
} @fragment_shader

#scope_file
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
