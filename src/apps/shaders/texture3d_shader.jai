#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

Texture3D_Params :: struct {
    texture_index: u32;
    sampler_index: u32;
    volume_size: u32;
    flags: u32;

    time: float;
    density_scale: float;
    absorption: float;
    march_steps: float;

    resolution: Vector2;
    _pad0: Vector2;
}

Texture3D_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Texture3D_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Texture3D_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Texture3D_Fragment_In :: struct {
    uv: Vector2;
}

texture3d_hash31 :: (x: u32, y: u32, z: u32) -> float {
    n := x * cast(u32) 1597334677 + y * cast(u32) 3812015801 + z * cast(u32) 2798796415;
    n = n ~ (n >> 16);
    n *= cast(u32) 2246822519;
    n = n ~ (n >> 13);
    n *= cast(u32) 3266489917;
    n = n ~ (n >> 16);
    scale := 1.0 / cast(float) 16777215;
    return cast(float) (n & cast(u32) 0x00ff_ffff) * scale;
}

texture3d_noise3 :: (p: Vector3) -> float {
    ix_f := floor(p.x);
    iy_f := floor(p.y);
    iz_f := floor(p.z);
    fx := fract(p.x);
    fy := fract(p.y);
    fz := fract(p.z);
    ux := fx * fx * (3.0 - 2.0 * fx);
    uy := fy * fy * (3.0 - 2.0 * fy);
    uz := fz * fz * (3.0 - 2.0 * fz);

    ix := cast(u32) ix_f;
    iy := cast(u32) iy_f;
    iz := cast(u32) iz_f;

    n000 := texture3d_hash31(ix + 0, iy + 0, iz + 0);
    n100 := texture3d_hash31(ix + 1, iy + 0, iz + 0);
    n010 := texture3d_hash31(ix + 0, iy + 1, iz + 0);
    n110 := texture3d_hash31(ix + 1, iy + 1, iz + 0);
    n001 := texture3d_hash31(ix + 0, iy + 0, iz + 1);
    n101 := texture3d_hash31(ix + 1, iy + 0, iz + 1);
    n011 := texture3d_hash31(ix + 0, iy + 1, iz + 1);
    n111 := texture3d_hash31(ix + 1, iy + 1, iz + 1);

    nx00 := mix(n000, n100, ux);
    nx10 := mix(n010, n110, ux);
    nx01 := mix(n001, n101, ux);
    nx11 := mix(n011, n111, ux);
    nxy0 := mix(nx00, nx10, uy);
    nxy1 := mix(nx01, nx11, uy);
    return mix(nxy0, nxy1, uz);
}

texture3d_sign :: (x: float) -> float {
    if x < 0.0 return -1.0;
    return 1.0;
}

texture3d_compute_main :: (using in: Texture3D_Compute_In, params: *Texture3D_Params) {
    s := max(params[0].volume_size, cast(u32) 1);
    ss := s * s;
    voxel_count := ss * s;
    if thread_id.x >= voxel_count return;

    z := thread_id.x / ss;
    rem := thread_id.x - z * ss;
    y := rem / s;
    x := rem - y * s;

    p := (Vector3.{cast(float) x, cast(float) y, cast(float) z} + Vector3.{0.5, 0.5, 0.5}) / cast(float) s;
    t := params[0].time;

    f := 2.8;
    a := 0.6;
    n := 0.0;
    for octave: 0..3 {
        wobble := Vector3.{0.0, t * 0.22, 0.0} + Vector3.{13.0, 29.0, 7.0} * cast(float) octave;
        n += a * texture3d_noise3(p * f + wobble);
        f *= 2.0;
        a *= 0.5;
    }

    layers := 0.5 + 0.5 * sin((p.y * 11.0 + p.x * 4.0 + p.z * 3.0) + t * 0.7);
    band := smoothstep(0.15, 0.8, p.y);
    density := clamp((n * 0.85 + layers * 0.35) * band - 0.28, 0.0, 1.0);

    texture_index := min(params[0].texture_index, 126);
    write_3d(texture_index, x, y, z, .{density, 0.0, 0.0, 0.0});
} @compute_shader

texture3d_vertex_main :: (using in: Texture3D_Vertex_In) -> Texture3D_Vertex_Out {
    using out: Texture3D_Vertex_Out;
    positions := Vector2.[
        .{-1.0, -1.0},
        .{ 3.0, -1.0},
        .{-1.0,  3.0},
    ];
    pos := positions[vertex_id];
    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = pos * 0.5 + Vector2.{0.5, 0.5};
    return out;
} @vertex_shader

texture3d_fragment_main :: (using in: Texture3D_Fragment_In, params: *Texture3D_Params) -> struct { out_color: Vector4; } {
    res := Vector2.{
        max(params[0].resolution.x, 1.0),
        max(params[0].resolution.y, 1.0),
    };
    uv_clip := uv * 2.0 - Vector2.{1.0, 1.0};
    uv_clip.x *= res.x / res.y;

    t := params[0].time;
    target := Vector3.{0.5, 0.52, 0.5};
    ro := target + Vector3.{cos(t * 0.2) * 1.8, 0.45 + sin(t * 0.27) * 0.35, sin(t * 0.2) * 1.8};
    forward := normalize(target - ro);
    right := normalize(cross(Vector3.{0.0, 1.0, 0.0}, forward));
    up := cross(forward, right);
    rd := normalize(forward + uv_clip.x * right * 0.9 + uv_clip.y * up * 0.9);

    bg_mix := clamp(uv.y * 0.8 + 0.2, 0.0, 1.0);
    sky := mix(Vector3.{0.07, 0.09, 0.12}, Vector3.{0.16, 0.2, 0.28}, bg_mix);

    eps :: 0.000001;
    inv_rd_x := texture3d_sign(rd.x) / max(abs(rd.x), eps);
    inv_rd_y := texture3d_sign(rd.y) / max(abs(rd.y), eps);
    inv_rd_z := texture3d_sign(rd.z) / max(abs(rd.z), eps);
    tmin_x := (0.0 - ro.x) * inv_rd_x;
    tmin_y := (0.0 - ro.y) * inv_rd_y;
    tmin_z := (0.0 - ro.z) * inv_rd_z;
    tmax_x := (1.0 - ro.x) * inv_rd_x;
    tmax_y := (1.0 - ro.y) * inv_rd_y;
    tmax_z := (1.0 - ro.z) * inv_rd_z;
    tn_x := min(tmin_x, tmax_x);
    tn_y := min(tmin_y, tmax_y);
    tn_z := min(tmin_z, tmax_z);
    tf_x := max(tmin_x, tmax_x);
    tf_y := max(tmin_y, tmax_y);
    tf_z := max(tmin_z, tmax_z);
    near_t := max(max(tn_x, tn_y), tn_z);
    far_t := min(min(tf_x, tf_y), tf_z);
    if far_t <= max(near_t, 0.0) {
        return .{out_color = .{sky.x, sky.y, sky.z, 1.0}};
    }

    t_cursor := max(near_t, 0.0);
    t_span := max(far_t - t_cursor, 0.00001);
    steps := max(cast(u32) params[0].march_steps, cast(u32) 8);
    dt := t_span / cast(float) steps;

    optical_depth := 0.0;
    for i: 0..cast(s64) steps-1 {
        p := ro + rd * (t_cursor + dt * (cast(float) i + 0.5));
        d := sample_3d(params[0].texture_index, params[0].sampler_index, p).x * params[0].density_scale;
        optical_depth += max(d, 0.0) * dt;
    }

    transmittance := exp(-optical_depth * params[0].absorption);
    fog := clamp(1.0 - transmittance, 0.0, 1.0);
    fog_color := mix(Vector3.{0.82, 0.88, 0.95}, Vector3.{0.12, 0.18, 0.26}, fog);
    out_color := mix(sky, fog_color, fog);
    return .{out_color = .{out_color.x, out_color.y, out_color.z, 1.0}};
} @fragment_shader
