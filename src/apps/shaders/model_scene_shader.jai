#import "Jai-Shader-Transpiler";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";
#import "Math";

Scene_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
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
}

Model_Scene_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    tint: Vector4;
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

    world_normal4 := instance.world * skinned_normal4;
    normal = normalize(Vector3.{world_normal4.x, world_normal4.y, world_normal4.z});
    uv = vertex.uv;
    tint = instance.tint;
    return out;
} @vertex_shader

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
    diffuse := ambient + ndl * 0.78;
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
