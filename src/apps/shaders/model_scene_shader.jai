#import "Jai-Shader-Transpiler";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";
#import "Math";

Scene_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
    shadow_view_proj_0: Vector4;
    shadow_view_proj_1: Vector4;
    shadow_view_proj_2: Vector4;
    shadow_view_proj_3: Vector4;
    shadow_meta: Vector4;
}

Scene_Draw_Params :: struct {
    vertices: *Scene_Vertex;
    indices: *u32;
    materials: *Scene_Material;
    instances: *Scene_Instance;
    skin_matrices: *Vector4;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    camera_pos: Vector3;
    _pad1: float;
    material_index: u32;
    sampler_index: u32;
    skin_matrix_count: u32;
    _pad2: u32;
    _pad3: u32;
}

Ground_Draw_Params :: struct {
    vertices: *Scene_Vertex;
    indices: *u32;
    instances: *Scene_Instance;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    camera_pos: Vector3;
    _pad1: float;
    sampler_index: u32;
    base_color_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    _pad2: u32;
}

Model_Scene_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Model_Scene_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    tangent: Vector4;
    uv: Vector2;
    tint: Vector4;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Model_Scene_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    tangent: Vector4;
    uv: Vector2;
    tint: Vector4;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Model_Scene_Shadow_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    depth01: float;
}

Model_Scene_Shadow_Fragment_In :: struct {
    depth01: float;
}

Model_Scene_Debug_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Model_Scene_Debug_Fragment_In :: struct {
    uv: Vector2;
}

Ground_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Ground_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Ground_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

model_scene_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Vertex_Out {
    using out: Model_Scene_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    local_normal := Vector4.{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0.0};
    local_tangent := Vector4.{vertex.tangent.x, vertex.tangent.y, vertex.tangent.z, 0.0};
    skinned_pos4 := local_pos;
    skinned_normal4 := local_normal;
    skinned_tangent4 := local_tangent;

    if params.skin_matrix_count > 0 {
        skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
        skinned_normal4 = .{0.0, 0.0, 0.0, 0.0};
        skinned_tangent4 = .{0.0, 0.0, 0.0, 0.0};
        total_weight: float = 0.0;
        if vertex.bone_weights.x > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.x;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.x;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.x;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.x;
                total_weight += vertex.bone_weights.x;
            }
        }
        if vertex.bone_weights.y > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.y;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.y;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.y;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.y;
                total_weight += vertex.bone_weights.y;
            }
        }
        if vertex.bone_weights.z > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.z;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.z;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.z;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.z;
                total_weight += vertex.bone_weights.z;
            }
        }
        if vertex.bone_weights.w > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.w;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.w;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.w;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.w;
                total_weight += vertex.bone_weights.w;
            }
        }
        if total_weight <= 0.0 {
            skinned_pos4 = local_pos;
            skinned_normal4 = local_normal;
            skinned_tangent4 = local_tangent;
        }
    }

    world_pos4 := instance.world * skinned_pos4;
    gl_Position = params.view_proj * world_pos4;
    world_pos = .{world_pos4.x, world_pos4.y, world_pos4.z};
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    shadow_uvz = .{light_clip.x * 0.5 + 0.5, light_clip.y * 0.5 + 0.5, light_clip.z};
    shadow_meta = instance.shadow_meta;

    world_normal4 := instance.world * skinned_normal4;
    normal = normalize(Vector3.{world_normal4.x, world_normal4.y, world_normal4.z});
    world_tangent4 := instance.world * skinned_tangent4;
    tangent = .{world_tangent4.x, world_tangent4.y, world_tangent4.z, vertex.tangent.w};
    uv = vertex.uv;
    tint = instance.tint;
    return out;
} @vertex_shader

model_scene_shadow_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Shadow_Vertex_Out {
    using out: Model_Scene_Shadow_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    skinned_pos4 := local_pos;

    if params.skin_matrix_count > 0 {
        skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
        total_weight: float = 0.0;
        if vertex.bone_weights.x > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.x;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.x;
                total_weight += vertex.bone_weights.x;
            }
        }
        if vertex.bone_weights.y > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.y;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.y;
                total_weight += vertex.bone_weights.y;
            }
        }
        if vertex.bone_weights.z > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.z;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.z;
                total_weight += vertex.bone_weights.z;
            }
        }
        if vertex.bone_weights.w > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.w;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.w;
                total_weight += vertex.bone_weights.w;
            }
        }
        if total_weight <= 0.0 {
            skinned_pos4 = local_pos;
        }
    }

    world_pos4 := instance.world * skinned_pos4;
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    gl_Position = light_clip;
    depth01 = clamp(light_clip.z, 0.0, 1.0);
    return out;
} @vertex_shader

model_scene_shadow_fragment_main :: (using in: Model_Scene_Shadow_Fragment_In, params: *Scene_Draw_Params) -> struct { out_color: Vector4; } {
    _ = params;
    d := clamp(depth01, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_debug_shadow_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Debug_Vertex_Out {
    using out: Model_Scene_Debug_Vertex_Out;
    _ = params;

    x0 := 0.56;
    x1 := 0.98;
    y0 := -0.98;
    y1 := -0.56;

    if vertex_id == 0 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{x1, y0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{x0, y1, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

model_scene_debug_shadow_fragment_main :: (using in: Model_Scene_Debug_Fragment_In, params: *Scene_Draw_Params) -> struct { out_color: Vector4; } {
    meta := params.instances[0].shadow_meta;
    tex_idx := cast(u32) meta.x;
    samp_idx := cast(u32) meta.y;
    s := sample_2d(tex_idx, samp_idx, .{uv.x, 1.0 - uv.y});
    d := clamp(s.x, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_fragment_main :: (using in: Model_Scene_Fragment_In, params: *Scene_Draw_Params) -> Vector4 @SV_Target0 {
    material := params.materials[params.material_index];
    tex := sample_2d(material.base_color_texture_index, material.sampler_index, uv);
    base_rgb := Vector3.{
        tex.x * material.base_color_factor.x * tint.x,
        tex.y * material.base_color_factor.y * tint.y,
        tex.z * material.base_color_factor.z * tint.z,
    };
    N := normalize(normal);
    ao := 1.0;
    roughness := 0.82;
    if material.normal_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        T := normalize(Vector3.{tangent.x, tangent.y, tangent.z});
        B := normalize(cross(N, T)) * tangent.w;
        n_sample := sample_2d(material.normal_texture_index, material.sampler_index, uv);
        n_ts := Vector3.{
            n_sample.x * 2.0 - 1.0,
            n_sample.y * 2.0 - 1.0,
            n_sample.z * 2.0 - 1.0,
        };
        N = normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
    }
    if material.ao_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        ao = sample_2d(material.ao_texture_index, material.sampler_index, uv).x;
    }
    if material.roughness_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        roughness = sample_2d(material.roughness_texture_index, material.sampler_index, uv).y;
    }
    L := normalize(-params.light_dir);
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl := max(dot(N, L), 0.0);
    ndh := max(dot(N, H), 0.0);
    ambient := 0.18 * mix(0.62, 1.0, ao);
    local_shadow_meta := shadow_meta;
    local_shadow_uvz := shadow_uvz;
    shadow := model_scene_shadow_visibility(local_shadow_meta, local_shadow_uvz);
    diffuse := ambient + ndl * 0.78 * shadow;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    specular := pow(ndh, spec_power) * spec_strength * shadow;
    color := base_rgb * diffuse + Vector3.{1.0, 0.97, 0.92} * specular;
    return .{color.x, color.y, color.z, tex.w * tint.w};
} @fragment_shader

ground_vertex_main :: (using in: Ground_Vertex_In, params: *Ground_Draw_Params) -> Ground_Vertex_Out {
    using out: Ground_Vertex_Out;
    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    world_pos4 := instance.world * local_pos;
    gl_Position = params.view_proj * world_pos4;
    world_pos = .{world_pos4.x, world_pos4.y, world_pos4.z};
    normal = normalize(Vector3.{vertex.normal.x, vertex.normal.y, vertex.normal.z});
    uv = vertex.uv;
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    shadow_uvz = .{light_clip.x * 0.5 + 0.5, light_clip.y * 0.5 + 0.5, light_clip.z};
    shadow_meta = instance.shadow_meta;
    return out;
} @vertex_shader

ground_fragment_main :: (using in: Ground_Fragment_In, params: *Ground_Draw_Params) -> Vector4 @SV_Target0 {
    tex := sample_2d(params.base_color_texture_index, params.sampler_index, uv);
    base_rgb := Vector3.{tex.x, tex.y, tex.z};
    ao := sample_2d(params.ao_texture_index, params.sampler_index, uv).x;
    roughness := sample_2d(params.roughness_texture_index, params.sampler_index, uv).x;

    N := normalize(normal);
    up := Vector3.{0.0, 1.0, 0.0};
    tangent := cross(up, N);
    tangent_len2 := dot(tangent, tangent);
    if tangent_len2 < 1.0e-5 {
        tangent = .{1.0, 0.0, 0.0};
    } else {
        tangent = tangent / sqrt(tangent_len2);
    }
    bitangent := normalize(cross(N, tangent));
    n_sample := sample_2d(params.normal_texture_index, params.sampler_index, uv);
    n_ts := Vector3.{n_sample.x * 2.0 - 1.0, n_sample.y * 2.0 - 1.0, n_sample.z * 2.0 - 1.0};
    N = normalize(tangent * n_ts.x + bitangent * n_ts.y + N * max(n_ts.z, 0.0));

    L := normalize(-params.light_dir);
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl := max(dot(N, L), 0.0);
    ndh := max(dot(N, H), 0.0);
    ambient := 0.18 * mix(0.62, 1.0, ao);
    shadow := model_scene_shadow_visibility(shadow_meta, shadow_uvz);
    diffuse := ambient + ndl * 0.78 * shadow;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    specular := pow(ndh, spec_power) * spec_strength * shadow;
    color := base_rgb * diffuse + Vector3.{1.0, 0.97, 0.92} * specular;
    return .{color.x, color.y, color.z, tex.w};
} @fragment_shader

#scope_file

load_skin_matrix :: (rows: *Vector4, bone_index: u32) -> Matrix4 {
    row_start := bone_index * 4;
    return .{
        rows[row_start + 0].x, rows[row_start + 0].y, rows[row_start + 0].z, rows[row_start + 0].w,
        rows[row_start + 1].x, rows[row_start + 1].y, rows[row_start + 1].z, rows[row_start + 1].w,
        rows[row_start + 2].x, rows[row_start + 2].y, rows[row_start + 2].z, rows[row_start + 2].w,
        rows[row_start + 3].x, rows[row_start + 3].y, rows[row_start + 3].z, rows[row_start + 3].w,
    };
}

model_scene_shadow_visibility :: (shadow_meta: Vector4, shadow_uvz: Vector3) -> float {
    tex_idx := cast(u32) shadow_meta.x;
    samp_idx := cast(u32) shadow_meta.y;
    bias := shadow_meta.z;
    texel := shadow_meta.w;

    u := shadow_uvz.x;
    v := 1.0 - shadow_uvz.y;
    z := shadow_uvz.z;
    if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 return 1.0;

    t0 := sample_2d(tex_idx, samp_idx, .{u - texel, v - texel});
    t1 := sample_2d(tex_idx, samp_idx, .{u + texel, v - texel});
    t2 := sample_2d(tex_idx, samp_idx, .{u - texel, v + texel});
    t3 := sample_2d(tex_idx, samp_idx, .{u + texel, v + texel});

    lit: float = 0.0;
    if z <= t0.x + bias lit += 1.0;
    if z <= t1.x + bias lit += 1.0;
    if z <= t2.x + bias lit += 1.0;
    if z <= t3.x + bias lit += 1.0;
    return mix(0.28, 1.0, lit * 0.25);
}

load_shadow_view_proj :: (instance: Scene_Instance) -> Matrix4 {
    return .{
        instance.shadow_view_proj_0.x, instance.shadow_view_proj_0.y, instance.shadow_view_proj_0.z, instance.shadow_view_proj_0.w,
        instance.shadow_view_proj_1.x, instance.shadow_view_proj_1.y, instance.shadow_view_proj_1.z, instance.shadow_view_proj_1.w,
        instance.shadow_view_proj_2.x, instance.shadow_view_proj_2.y, instance.shadow_view_proj_2.z, instance.shadow_view_proj_2.w,
        instance.shadow_view_proj_3.x, instance.shadow_view_proj_3.y, instance.shadow_view_proj_3.z, instance.shadow_view_proj_3.w,
    };
}
