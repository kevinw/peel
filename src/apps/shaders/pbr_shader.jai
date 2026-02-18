#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

PBR_PI :: cast(float) 3.1415926535;
PBR_SPHERE_SEG_X :: 64;
PBR_SPHERE_SEG_Y :: 48;

PBR_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

PBR_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
    world_pos: Vector3;
}

PBR_Fragment_In :: struct {
    uv: Vector2;
    world_pos: Vector3;
}

PBR_Params :: struct {
    albedo_index: u32;
    normal_index: u32;
    roughness_index: u32;
    ao_index: u32;
    displacement_index: u32;

    sampler_index: u32;
    debug_mode: u32;
    _pad0: u32;
    _pad1: u32;

    light_pos_x: float;
    light_pos_y: float;
    light_pos_z: float;
    light_intensity: float;

    light_color_r: float;
    light_color_g: float;
    light_color_b: float;
    metallic: float;

    camera_pos_x: float;
    camera_pos_y: float;
    camera_pos_z: float;

    resolution_x: float;
    resolution_y: float;
    time: float;
    displacement_strength: float;

    uv_scale: float;
}

fresnel_schlick :: (cos_theta: float, F0: Vector3) -> Vector3 {
    m := clamp(1.0 - cos_theta, 0.0, 1.0);
    m2 := m * m;
    m5 := m2 * m2 * m;
    return .{
        F0.x + (1.0 - F0.x) * m5,
        F0.y + (1.0 - F0.y) * m5,
        F0.z + (1.0 - F0.z) * m5,
    };
}

distribution_ggx :: (N: Vector3, H: Vector3, roughness: float) -> float {
    a := roughness * roughness;
    a2 := a * a;
    ndh := max(dot(N, H), 0.0);
    ndh2 := ndh * ndh;
    denom := ndh2 * (a2 - 1.0) + 1.0;
    return a2 / max(PBR_PI * denom * denom, 0.0001);
}

geometry_schlick_ggx :: (ndv: float, roughness: float) -> float {
    r := roughness + 1.0;
    k := (r * r) / 8.0;
    return ndv / max(ndv * (1.0 - k) + k, 0.0001);
}

geometry_smith :: (N: Vector3, V: Vector3, L: Vector3, roughness: float) -> float {
    ndv := max(dot(N, V), 0.0);
    ndl := max(dot(N, L), 0.0);
    g1 := geometry_schlick_ggx(ndv, roughness);
    g2 := geometry_schlick_ggx(ndl, roughness);
    return g1 * g2;
}

pbr_vertex_main :: (using in: PBR_Vertex_In, params: *PBR_Params) -> PBR_Vertex_Out {
    using out: PBR_Vertex_Out;

    tri := vertex_id / 3;
    corner := vertex_id % 3;
    cell := tri / 2;
    tri_in_cell := tri % 2;

    cell_x := cell % PBR_SPHERE_SEG_X;
    cell_y := cell / PBR_SPHERE_SEG_X;

    u0 := cast(float) cell_x / cast(float) PBR_SPHERE_SEG_X;
    v0 := cast(float) cell_y / cast(float) PBR_SPHERE_SEG_Y;
    u1 := cast(float) (cell_x + 1) / cast(float) PBR_SPHERE_SEG_X;
    v1 := cast(float) (cell_y + 1) / cast(float) PBR_SPHERE_SEG_Y;

    a := Vector2.{u0, v0};
    b := Vector2.{u1, v0};
    c := Vector2.{u1, v1};
    d := Vector2.{u0, v1};

    uv_out: Vector2;
    if tri_in_cell == 0 {
        if corner == 0 {
            uv_out = a;
        } else if corner == 1 {
            uv_out = b;
        } else {
            uv_out = c;
        }
    } else {
        if corner == 0 {
            uv_out = a;
        } else if corner == 1 {
            uv_out = c;
        } else {
            uv_out = d;
        }
    }

    phi := uv_out.x * (2.0 * PBR_PI);
    theta := uv_out.y * PBR_PI;
    sin_theta := sin(theta);
    cos_theta := cos(theta);
    sin_phi := sin(phi);
    cos_phi := cos(phi);

    n := Vector3.{
        cos_phi * sin_theta,
        cos_theta,
        sin_phi * sin_theta,
    };

    _ = instance_id;

    p := params[0];
    spin := p.time * 0.25;
    spin_sin := sin(spin);
    spin_cos := cos(spin);
    n_rot := Vector3.{
        n.x * spin_cos - n.z * spin_sin,
        n.y,
        n.x * spin_sin + n.z * spin_cos,
    };

    aspect := 1.0;
    if p.resolution_y > 0.0 {
        aspect = p.resolution_x / p.resolution_y;
    }
    radius_x := 0.85 / max(aspect, 0.0001);
    radius_y := 0.85;

    gl_Position = .{n_rot.x * radius_x, n_rot.y * radius_y, 0.0, 1.0};
    uv = uv_out;
    world_pos = n_rot;
    return out;
} @vertex_shader

pbr_fragment_main :: (using in: PBR_Fragment_In, params: *PBR_Params) -> Vector4 @SV_Target0 {
    p := params[0];
    if p.debug_mode == 99 {
        return .{uv.x, uv.y, 0.0, 1.0};
    }

    uv_tiled: Vector2 = .{uv.x * p.uv_scale, uv.y * p.uv_scale};
    albedo_srgb := sample_2d(p.albedo_index, p.sampler_index, uv_tiled);
    normal_tex := sample_2d(p.normal_index, p.sampler_index, uv_tiled);
    roughness_tex := sample_2d(p.roughness_index, p.sampler_index, uv_tiled);
    ao_tex := sample_2d(p.ao_index, p.sampler_index, uv_tiled);
    disp_tex := sample_2d(p.displacement_index, p.sampler_index, uv_tiled);

    base_n := normalize(world_pos);
    tangent := normalize(cross(Vector3.{0.0, 1.0, 0.0}, base_n));
    if dot(tangent, tangent) < 0.0001 {
        tangent = normalize(cross(Vector3.{1.0, 0.0, 0.0}, base_n));
    }
    bitangent := cross(base_n, tangent);

    normal_map := normalize(Vector3.{
        normal_tex.x * 2.0 - 1.0,
        normal_tex.y * 2.0 - 1.0,
        normal_tex.z * 2.0 - 1.0,
    });
    N := normalize(tangent * normal_map.x + bitangent * normal_map.y + base_n * normal_map.z);

    disp_height := disp_tex.x * 2.0 - 1.0;
    hit_pos := world_pos + N * (disp_height * p.displacement_strength);
    L := normalize(.{p.light_pos_x - hit_pos.x, p.light_pos_y - hit_pos.y, p.light_pos_z - hit_pos.z});
    ndl := max(dot(N, L), 0.0);

    roughness := clamp(roughness_tex.x, 0.05, 1.0);
    ao := clamp(ao_tex.x, 0.0, 1.0);

    albedo := Vector3.{
        pow(clamp(albedo_srgb.x, 0.0, 1.0), 2.2),
        pow(clamp(albedo_srgb.y, 0.0, 1.0), 2.2),
        pow(clamp(albedo_srgb.z, 0.0, 1.0), 2.2),
    };

    light_tint := Vector3.{p.light_color_r, p.light_color_g, p.light_color_b};
    diffuse := Vector3.{
        albedo.x * light_tint.x * (0.10 + ndl * p.light_intensity * 0.06),
        albedo.y * light_tint.y * (0.10 + ndl * p.light_intensity * 0.06),
        albedo.z * light_tint.z * (0.10 + ndl * p.light_intensity * 0.06),
    };
    shade := 1.0 - roughness * 0.35;
    color := Vector3.{
        diffuse.x * ao * shade,
        diffuse.y * ao * shade,
        diffuse.z * ao * shade,
    };

    mapped := Vector3.{
        color.x / (color.x + 1.0),
        color.y / (color.y + 1.0),
        color.z / (color.z + 1.0),
    };
    final_color := Vector3.{
        pow(clamp(mapped.x, 0.0, 1.0), 1.0 / 2.2),
        pow(clamp(mapped.y, 0.0, 1.0), 1.0 / 2.2),
        pow(clamp(mapped.z, 0.0, 1.0), 1.0 / 2.2),
    };

    out_rgb := final_color;
    if p.debug_mode == 1 {
        out_rgb = .{albedo_srgb.x, albedo_srgb.y, albedo_srgb.z};
    } else if p.debug_mode == 2 {
        out_rgb = .{normal_tex.x, normal_tex.y, normal_tex.z};
    } else if p.debug_mode == 3 {
        out_rgb = .{roughness_tex.x, roughness_tex.x, roughness_tex.x};
    } else if p.debug_mode == 4 {
        out_rgb = .{ao_tex.x, ao_tex.x, ao_tex.x};
    } else if p.debug_mode == 5 {
        out_rgb = .{disp_tex.x, disp_tex.x, disp_tex.x};
    }

    return .{out_rgb.x, out_rgb.y, out_rgb.z, 1.0};
} @fragment_shader
