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

Scene_Debug_Params :: struct {
    vertices: *Scene_Vertex;
    indices: *u32;
    materials: *Scene_Material;
    instances: *Scene_Instance;
}

Model_Scene_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Model_Scene_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    tint: Vector4;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Model_Scene_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
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

model_scene_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Vertex_Out {
    using out: Model_Scene_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    local_normal := Vector4.{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0.0};
    skinned_pos4 := local_pos;
    skinned_normal4 := local_normal;

    if params.skin_matrix_count > 0 {
        skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
        skinned_normal4 = .{0.0, 0.0, 0.0, 0.0};
        total_weight: float = 0.0;
        if vertex.bone_weights.x > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.x;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.x;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.x;
                total_weight += vertex.bone_weights.x;
            }
        }
        if vertex.bone_weights.y > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.y;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.y;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.y;
                total_weight += vertex.bone_weights.y;
            }
        }
        if vertex.bone_weights.z > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.z;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.z;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.z;
                total_weight += vertex.bone_weights.z;
            }
        }
        if vertex.bone_weights.w > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.w;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.w;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.w;
                total_weight += vertex.bone_weights.w;
            }
        }
        if total_weight <= 0.0 {
            skinned_pos4 = local_pos;
            skinned_normal4 = local_normal;
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

model_scene_debug_shadow_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Debug_Params) -> Model_Scene_Debug_Vertex_Out {
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

model_scene_debug_shadow_fragment_main :: (using in: Model_Scene_Debug_Fragment_In, params: *Scene_Debug_Params) -> struct { out_color: Vector4; } {
    meta := params.instances[0].shadow_meta;
    tex_idx := cast(u32) meta.x;
    samp_idx := cast(u32) meta.y;
    s := sample_2d(tex_idx, samp_idx, .{uv.x, 1.0 - uv.y});
    d := clamp(s.x, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_fragment_main :: (using in: Model_Scene_Fragment_In, params: *Scene_Draw_Params) -> Vector4 @SV_Target0 {
    material := params.materials[params.material_index];
    tex := sample_2d(material.base_color_texture_index, params.sampler_index, uv);
    base_rgb := Vector3.{
        tex.x * material.base_color_factor.x * tint.x,
        tex.y * material.base_color_factor.y * tint.y,
        tex.z * material.base_color_factor.z * tint.z,
    };

    N := normalize(normal);
    L := normalize(-params.light_dir);
    ndl := max(dot(N, L), 0.0);
    ambient := 0.22;
    local_shadow_meta := shadow_meta;
    local_shadow_uvz := shadow_uvz;
    shadow := model_scene_shadow_visibility(local_shadow_meta, local_shadow_uvz);
    diffuse := ambient + ndl * 0.78 * shadow;
    color := base_rgb * diffuse;
    return .{color.x, color.y, color.z, tex.w * tint.w};
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
