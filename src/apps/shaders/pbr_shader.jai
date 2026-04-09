#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

PBR_PI :: cast(float) 3.1415926535;

PBR_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

PBR_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
    world_pos: Vector3;
    world_normal: Vector3;
}

PBR_Fragment_In :: struct {
    uv: Vector2;
    world_pos: Vector3;
    world_normal: Vector3;
}

PBR_Params :: struct {
    vertices: *Procedural_Geometry_Vertex;
    indices: *u32;
    view_proj: Matrix4;

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
    idx := params[0].indices[vertex_id];
    vertex := params[0].vertices[idx];
    local_pos := vertex.position.xyz;
    local_normal := normalize(vertex.normal.xyz);

    abs_normal := abs(local_normal);
    uv_out: Vector2;
    if abs_normal.x > abs_normal.y && abs_normal.x > abs_normal.z {
        uv_out = .{local_pos.z, local_pos.y};
    } else if abs_normal.y > abs_normal.z {
        uv_out = .{local_pos.x, local_pos.z};
    } else {
        uv_out = .{local_pos.x, local_pos.y};
    }

    _ = instance_id;
    rot_x := params[0].time * 0.13;
    rot_y := params[0].time * 0.19;
    rot_z := params[0].time * 0.11;

    sx := sin(rot_x); cx := cos(rot_x);
    sy := sin(rot_y); cy := cos(rot_y);
    sz := sin(rot_z); cz := cos(rot_z);

    pos_scaled := local_pos * 0.72;
    pos_rot_x := Vector3.{pos_scaled.x, pos_scaled.y * cx - pos_scaled.z * sx, pos_scaled.y * sx + pos_scaled.z * cx};
    pos_rot_y := Vector3.{pos_rot_x.x * cy + pos_rot_x.z * sy, pos_rot_x.y, -pos_rot_x.x * sy + pos_rot_x.z * cy};
    pos_rot := Vector3.{pos_rot_y.x * cz - pos_rot_y.y * sz, pos_rot_y.x * sz + pos_rot_y.y * cz, pos_rot_y.z};

    normal_rot_x := Vector3.{local_normal.x, local_normal.y * cx - local_normal.z * sx, local_normal.y * sx + local_normal.z * cx};
    normal_rot_y := Vector3.{normal_rot_x.x * cy + normal_rot_x.z * sy, normal_rot_x.y, -normal_rot_x.x * sy + normal_rot_x.z * cy};
    normal_rot := normalize(Vector3.{normal_rot_y.x * cz - normal_rot_y.y * sz, normal_rot_y.x * sz + normal_rot_y.y * cz, normal_rot_y.z});

    world4 := Vector4.{pos_rot.x, pos_rot.y, pos_rot.z, 1.0};
    gl_Position = params[0].view_proj * world4;
    uv = uv_out;
    world_pos = pos_rot;
    world_normal = normal_rot;
    return out;
} @vertex_shader

pbr_fragment_main :: (using in: PBR_Fragment_In, params: *PBR_Params) -> Vector4 @SV_Target0 {
    if params[0].debug_mode == 99 {
        return .{uv.x, uv.y, 0.0, 1.0};
    }

    uv_tiled: Vector2 = .{uv.x * params[0].uv_scale, uv.y * params[0].uv_scale};
    albedo_srgb   := sample_2d(params[0].albedo_index, params[0].sampler_index, uv_tiled);
    normal_tex    := sample_2d(params[0].normal_index, params[0].sampler_index, uv_tiled);
    roughness_tex := sample_2d(params[0].roughness_index, params[0].sampler_index, uv_tiled);
    ao_tex        := sample_2d(params[0].ao_index, params[0].sampler_index, uv_tiled);
    disp_tex      := sample_2d(params[0].displacement_index, params[0].sampler_index, uv_tiled);

    base_n := normalize(world_normal);
    tangent := normalize(cross(Vector3.{0.0, 1.0, 0.0}, base_n));
    if dot(tangent, tangent) < 0.0001 {
        tangent = normalize(cross(Vector3.{1.0, 0.0, 0.0}, base_n));
    }
    bitangent := cross(base_n, tangent);

    normal_map := decode_bc5_normal(normal_tex);
    N := normalize(tangent * normal_map.x + bitangent * normal_map.y + base_n * normal_map.z);

    disp_height := disp_tex.x * 2.0 - 1.0;
    hit_pos := world_pos + N * (disp_height * params[0].displacement_strength);
    L := normalize(.{params[0].light_pos_x - hit_pos.x, params[0].light_pos_y - hit_pos.y, params[0].light_pos_z - hit_pos.z});
    ndl := max(dot(N, L), 0.0);

    roughness := clamp(roughness_tex.x, 0.05, 1.0);
    ao := clamp(ao_tex.x, 0.0, 1.0);

    albedo := Vector3.{
        pow(clamp(albedo_srgb.x, 0.0, 1.0), 2.2),
        pow(clamp(albedo_srgb.y, 0.0, 1.0), 2.2),
        pow(clamp(albedo_srgb.z, 0.0, 1.0), 2.2),
    };

    light_tint := Vector3.{params[0].light_color_r, params[0].light_color_g, params[0].light_color_b};
    diffuse := Vector3.{
        albedo.x * light_tint.x * (0.10 + ndl * params[0].light_intensity * 0.06),
        albedo.y * light_tint.y * (0.10 + ndl * params[0].light_intensity * 0.06),
        albedo.z * light_tint.z * (0.10 + ndl * params[0].light_intensity * 0.06),
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
    if params[0].debug_mode == 1 {
        out_rgb = .{albedo_srgb.x, albedo_srgb.y, albedo_srgb.z};
    } else if params[0].debug_mode == 2 {
        out_rgb = .{normal_tex.x, normal_tex.y, normal_tex.z};
    } else if params[0].debug_mode == 3 {
        out_rgb = .{roughness_tex.x, roughness_tex.x, roughness_tex.x};
    } else if params[0].debug_mode == 4 {
        out_rgb = .{ao_tex.x, ao_tex.x, ao_tex.x};
    } else if params[0].debug_mode == 5 {
        out_rgb = .{disp_tex.x, disp_tex.x, disp_tex.x};
    }

    return .{out_rgb.x, out_rgb.y, out_rgb.z, 1.0};
} @fragment_shader
