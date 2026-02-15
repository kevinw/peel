#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

Raymarch_Params :: struct {
    resolution: Vector2;
    mouse_uv: Vector2;
    time: float;
    _pad: float;
}

Raymarch_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Raymarch_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Raymarch_Fragment_In :: struct {
    uv: Vector2;
}

rm_sphere_dist :: (p: Vector3, c: Vector3, r: float) -> float {
    q := Vector3.{p.x - c.x, p.y - c.y, p.z - c.z};
    return sqrt(q.x * q.x + q.y * q.y + q.z * q.z) - r;
}

rm_plane_dist :: (p: Vector3) -> float {
    return p.y + 0.65;
}

rm_scene_dist :: (p: Vector3, time: float) -> float {
    center := Vector3.{sin(time * 0.8) * 0.65, 0.22 + sin(time * 1.3) * 0.07, cos(time * 0.7) * 0.22};
    sphere := rm_sphere_dist(p, center, 0.92);
    plane := rm_plane_dist(p);
    if sphere < plane return sphere;
    return plane;
}

rm_scene_normal :: (p: Vector3, time: float) -> Vector3 {
    eps := 0.001;
    ex := Vector3.{eps, 0, 0};
    ey := Vector3.{0, eps, 0};
    ez := Vector3.{0, 0, eps};
    nx := rm_scene_dist(.{p.x + ex.x, p.y + ex.y, p.z + ex.z}, time) - rm_scene_dist(.{p.x - ex.x, p.y - ex.y, p.z - ex.z}, time);
    ny := rm_scene_dist(.{p.x + ey.x, p.y + ey.y, p.z + ey.z}, time) - rm_scene_dist(.{p.x - ey.x, p.y - ey.y, p.z - ey.z}, time);
    nz := rm_scene_dist(.{p.x + ez.x, p.y + ez.y, p.z + ez.z}, time) - rm_scene_dist(.{p.x - ez.x, p.y - ez.y, p.z - ez.z}, time);
    return normalize(Vector3.{nx, ny, nz});
}

raymarch_vertex_main :: (using in: Raymarch_Vertex_In) -> Raymarch_Vertex_Out {
    using out: Raymarch_Vertex_Out;

    pos: Vector2;
    if vertex_id == 0 {
        pos = .{-1.0, -1.0};
    } else if vertex_id == 1 {
        pos = .{3.0, -1.0};
    } else {
        pos = .{-1.0, 3.0};
    }

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{
        pos.x * 0.5 + 0.5,
        pos.y * 0.5 + 0.5,
    };
    return out;
} @vertex_shader

raymarch_fragment_main :: (using in: Raymarch_Fragment_In, params: *Raymarch_Params) -> struct { out_color: Vector4; } {
    time := params[0].time;

    uv_ndc := Vector2.{uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0};
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
    for 0..95 {
        p := Vector3.{ro.x + rd.x * t, ro.y + rd.y * t, ro.z + rd.z * t};
        d := rm_scene_dist(p, time);
        if d < 0.0015 {
            hit = true;
            break;
        }
        t += d;
        if t > 24.0 break;
    }

    sky_top := Vector3.{0.06, 0.09, 0.16};
    sky_bottom := Vector3.{0.92, 0.63, 0.34};
    sky_mix := clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    color := Vector3.{
        lerp(sky_bottom.x, sky_top.x, sky_mix),
        lerp(sky_bottom.y, sky_top.y, sky_mix),
        lerp(sky_bottom.z, sky_top.z, sky_mix),
    };

    if hit {
        p := Vector3.{ro.x + rd.x * t, ro.y + rd.y * t, ro.z + rd.z * t};
        n := rm_scene_normal(p, time);
        light := Vector3.{2.2 * sin(time * 0.8), 2.7, -2.0 + 1.2 * cos(time * 0.6)};
        l := normalize(Vector3.{light.x - p.x, light.y - p.y, light.z - p.z});
        v := normalize(Vector3.{ro.x - p.x, ro.y - p.y, ro.z - p.z});
        h := normalize(Vector3.{l.x + v.x, l.y + v.y, l.z + v.z});

        diff := clamp(dot(n, l), 0.0, 1.0);
        ndh := clamp(dot(n, h), 0.0, 1.0);
        spec := ndh * ndh;
        spec = spec * spec * spec * 0.8;

        sphere_center := Vector3.{sin(time * 0.8) * 0.65, 0.22 + sin(time * 1.3) * 0.07, cos(time * 0.7) * 0.22};
        ds := rm_sphere_dist(p, sphere_center, 0.62);
        dp := rm_plane_dist(p);
        is_floor := dp < ds;

        base := Vector3.{0.42, 0.80, 1.00};
        if is_floor {
            checker := floor(p.x * 3.0) + floor(p.z * 3.0);
            check := checker - floor(checker * 0.5) * 2.0;
            floor_a := Vector3.{0.14, 0.13, 0.16};
            floor_b := Vector3.{0.20, 0.18, 0.24};
            base = ifx check < 1.0 then floor_a else floor_b;
        }

        ambient := 0.22;
        lit := Vector3.{
            base.x * (ambient + diff * 0.95) + spec,
            base.y * (ambient + diff * 0.95) + spec,
            base.z * (ambient + diff * 0.95) + spec,
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
