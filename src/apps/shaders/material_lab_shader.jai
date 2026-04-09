#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

Material_Lab_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Material_Lab_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
    world_pos: Vector3;
    world_normal: Vector3;
    world_tangent: Vector4;
}

Material_Lab_Fragment_In :: struct {
    uv: Vector2;
    world_pos: Vector3;
    world_normal: Vector3;
    world_tangent: Vector4;
}

Material_Lab_Params :: struct {
    vertices: *Procedural_Geometry_Vertex;
    indices: *u32;
    view_proj: Matrix4;
    model: Matrix4;

    albedo_index: u32;
    normal_index: u32;
    roughness_index: u32;
    ao_index: u32;

    sampler_index: u32;
    use_normal_map: u32;
    _pad0: u32;
    _pad1: u32;

    camera_pos: Vector3;
    metallic: float;

    base_color_tint: Vector3;
    emissive_strength: float;

    light_dir: Vector3;
    light_intensity: float;

    light_color: Vector3;
    roughness_bias: float;

    ao_strength: float;
    normal_strength: float;
    uv_scale: float;
    _pad2: float;
}

Material_Lab_Constants :: struct {
    debug_mode: ML_Debug_Mode = .LIT;
} @function_constants

ML_Debug_Mode :: enum u32 {
    LIT :: 0;
    ALBEDO :: 1;
    WORLD_NORMAL :: 2;
    NORMAL :: 3;
    ROUGHNESS :: 4;
    AO :: 5;
    NDOTL :: 6;
}

Material_Lab_Params_CPU :: CPU_Struct(Material_Lab_Params);


material_lab_vertex_main :: (using in: Material_Lab_Vertex_In, params: *Material_Lab_Params, constants: Material_Lab_Constants) -> Material_Lab_Vertex_Out {
    using out: Material_Lab_Vertex_Out;
    idx := params.indices[vertex_id];
    vertex := params.vertices[idx];
    local_pos := vertex.position.xyz;
    local_normal := normalize(vertex.normal.xyz);
    local_tangent := normalize(vertex.tangent.xyz);
    uv_out := vertex.uv;

    world4 := params.model * Vector4.{local_pos.x, local_pos.y, local_pos.z, 1.0};
    world_normal4 := params.model * Vector4.{local_normal.x, local_normal.y, local_normal.z, 0.0};
    world_tangent4 := params.model * Vector4.{local_tangent.x, local_tangent.y, local_tangent.z, 0.0};
    world_tangent3 := normalize(world_tangent4.xyz);

    gl_Position = params.view_proj * world4;
    uv = uv_out;
    world_pos = world4.xyz;
    world_normal = normalize(world_normal4.xyz);
    world_tangent = .{world_tangent3.x, world_tangent3.y, world_tangent3.z, vertex.tangent.w};
    _ = instance_id;
    return out;
} @vertex_shader

material_lab_fragment_main :: (using in: Material_Lab_Fragment_In, params: *Material_Lab_Params, using constants: Material_Lab_Constants) -> Vector4 @SV_Target0 {
    uv_tiled := uv * params.uv_scale;

    albedo_tex := sample_2d(params.albedo_index, params.sampler_index, uv_tiled).xyz;
    normal_tex := sample_2d(params.normal_index, params.sampler_index, uv_tiled).xyz;
    roughness_tex := sample_2d(params.roughness_index, params.sampler_index, uv_tiled).x;
    ao_tex := sample_2d(params.ao_index, params.sampler_index, uv_tiled).x;

    base_n := normalize(world_normal);
    tangent := normalize(world_tangent.xyz);
    bitangent := normalize(cross_product(base_n, tangent)) * world_tangent.w;

    N := base_n;
    if params.use_normal_map != 0 {
        normal_map := decode_bc5_normal(normal_tex);
        normal_map = normalize(lerp(Vector3.{0.0, 0.0, 1.0}, normal_map, clamp(params.normal_strength, 0.0, 2.0)));
        N = normalize(tangent * normal_map.x + bitangent * normal_map.y + base_n * normal_map.z);
    }

    V := normalize(params.camera_pos - world_pos);
    L := normalize(-params.light_dir);
    H := normalize(V + L);

    ndl := max(dot(N, L), 0.0);
    ndv := max(dot(N, V), 0.0);
    ndh := max(dot(N, H), 0.0);

    roughness := clamp(roughness_tex + params.roughness_bias, 0.05, 1.0);
    ao := lerp(1.0, clamp(ao_tex, 0.0, 1.0), clamp(params.ao_strength, 0.0, 1.0));
    albedo := albedo_tex * params.base_color_tint;

    F0 := lerp(Vector3.{0.04, 0.04, 0.04}, albedo, clamp(params.metallic, 0.0, 1.0));
    fresnel := F0 + (Vector3.{1.0, 1.0, 1.0} - F0) * pow(1.0 - ndv, 5.0);
    diffuse_k := (Vector3.{1.0, 1.0, 1.0} - fresnel) * (1.0 - clamp(params.metallic, 0.0, 1.0));

    alpha := roughness * roughness;
    alpha2 := alpha * alpha;
    denom := ndh * ndh * (alpha2 - 1.0) + 1.0;
    D := alpha2 / max(PI * denom * denom, 0.0001);
    k := pow(roughness + 1.0, 2.0) / 8.0;
    Gv := ndv / max(ndv * (1.0 - k) + k, 0.0001);
    Gl := ndl / max(ndl * (1.0 - k) + k, 0.0001);
    G := Gv * Gl;
    specular := (D * G) / max(4.0 * ndv * ndl, 0.0001);

    radiance := params.light_color * (params.light_intensity * ndl);
    diffuse := diffuse_k * albedo / PI;
    color := (diffuse + fresnel * specular) * radiance;
    color += albedo * 0.08 * ao;
    color += params.base_color_tint * params.emissive_strength;

    if debug_mode == {
    case .ALBEDO; return .{albedo.x, albedo.y, albedo.z, 1.0};
    case .WORLD_NORMAL; return .{base_n.x * 0.5 + 0.5, base_n.y * 0.5 + 0.5, base_n.z * 0.5 + 0.5, 1.0};
    case .NORMAL; return .{N.x * 0.5 + 0.5, N.y * 0.5 + 0.5, N.z * 0.5 + 0.5, 1.0};
    case .ROUGHNESS; return .{roughness, roughness, roughness, 1.0};
    case .AO; return .{ao, ao, ao, 1.0};
    case .NDOTL; return .{ndl, ndl, ndl, 1.0};
    }

    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
