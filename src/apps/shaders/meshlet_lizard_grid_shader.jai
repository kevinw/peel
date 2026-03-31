#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

MESHLET_MAX_VERTICES :: 64;
MESHLET_MAX_TRIANGLES :: 124;

Fragment_In :: struct {
    position: Vector4; @SV_Position
    color: Vector3; @TEXCOORD0
}

hash01 :: (x: u32) -> float {
    phase := cast(float) x * cast(float) 12.9898 + cast(float) 78.233;
    return fract(sin(phase) * cast(float) 43758.5453);
}

hue2rgb :: (hue: float) -> Vector3 {
    h := fract(hue);
    r := abs(h * 6.0 - 3.0) - 1.0;
    g := 2.0 - abs(h * 6.0 - 2.0);
    b := 2.0 - abs(h * 6.0 - 4.0);
    return .{
        clamp(r, 0.0, 1.0),
        clamp(g, 0.0, 1.0),
        clamp(b, 0.0, 1.0),
    };
}

lod_debug_color :: (lod: u32) -> Vector3 {
    if lod == {
    case 0; return .{0.13, 0.47, 0.71}; // blue
    case 1; return .{0.90, 0.62, 0.00}; // orange
    case 2; return .{0.80, 0.47, 0.65}; // magenta
    case 3; return .{0.84, 0.15, 0.16}; // red
    }
    return .{0.55, 0.55, 0.55};
}

Lod_Result :: struct {
    mesh_index: u32;
    lod: u32;
}

select_lod :: (
    params: *Meshlet_Grid_Params,
    meshes: *Scene_Mesh,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    base_mesh_index: u32,
    world: Matrix4,
) -> Lod_Result {
    base_meshlet_mesh := meshlet_meshes[base_mesh_index];
    local_center := base_meshlet_mesh.bounds_center_radius.xyz;
    local_radius := max(base_meshlet_mesh.bounds_center_radius.w, 0.001);
    world_center4 := world * Vector4.{local_center.x, local_center.y, local_center.z, 1.0};
    world_center := Vector3.{world_center4.x, world_center4.y, world_center4.z};
    view_delta := params.eye_position - world_center;
    distance_to_eye := length(view_delta);
    normalized_distance := distance_to_eye / max(local_radius * params.lod_distance_scale, 0.0001);
    lod_metric := pow(normalized_distance, params.lod_distance_power);

    result := Lod_Result.{base_mesh_index, 0};
    if meshes[base_mesh_index].lod_mesh_count > 0 {
        lod_count := meshes[base_mesh_index].lod_mesh_count;
        lod_slot := min(cast(u32) floor(lod_metric), lod_count);
        if lod_slot > 0 {
            result.mesh_index = meshes[base_mesh_index].lod_mesh_start + (lod_slot - 1);
            result.lod = lod_slot;
        }
    }
    return result;
}

mesh_main :: (
    params: *Meshlet_Grid_Params,
    meshes: *Scene_Mesh,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    vertices: *Scene_Vertex,
    materials: *Scene_Material,
    meshlets: *Scene_Meshlet,
    meshlet_vertices: *u32,
    meshlet_triangles: *u32,
    instances: *Meshlet_Grid_Instance,
) {
    mesh_set_max_output_counts(MESHLET_MAX_VERTICES, MESHLET_MAX_TRIANGLES);
    meshlet_local := mesh_group_id_x();
    instance_local := mesh_group_id_y();
    if meshlet_local >= params.batch_max_meshlet_count || instance_local >= params.batch_instance_count {
        mesh_set_output_counts(0, 0);
    } else {
        instance_index := params.batch_first_instance + instance_local;
        instance := instances[instance_index];
        lod_result := select_lod(params, meshes, meshlet_meshes, params.batch_mesh_index, instance.world);
        meshlet_mesh := meshlet_meshes[lod_result.mesh_index];
        if meshlet_local >= meshlet_mesh.meshlet_count {
            mesh_set_output_counts(0, 0);
        } else {
            meshlet_index := meshlet_mesh.meshlet_start + meshlet_local;
            meshlet := meshlets[meshlet_index];
            if meshlet.vertex_count < 3 {
                mesh_set_output_counts(0, 0);
            } else {
                mesh_set_output_counts(meshlet.vertex_count, meshlet.triangle_count);

                material := materials[meshes[lod_result.mesh_index].material_index];
                meshlet_hue := hash01(meshlet_index);
                meshlet_tint := hue2rgb(meshlet_hue);
                light_direction := normalize(-params.light_dir);

                for vertex_local: 0..cast(s64) meshlet.vertex_count-1 {
                    vertex_index := meshlet.vertex_offset + cast(u32) vertex_local;
                    v := vertices[meshlet_vertices[vertex_index]];
                    world_pos4 := instance.world * Vector4.{v.position.x, v.position.y, v.position.z, 1.0};
                    world_pos := Vector3.{world_pos4.x, world_pos4.y, world_pos4.z};
                    normal := normalize(v.normal.xyz);
                    ndotl := max(dot(normal, light_direction), 0.0);
                    lit := 0.18 + ndotl * 0.82;

                    color := material.base_color_factor.xyz * lit;
                    if params.debug_mode == cast(u32) Meshlet_Grid_Debug_Mode.LODS {
                        color = lod_debug_color(lod_result.lod);
                    } else if params.debug_mode == cast(u32) Meshlet_Grid_Debug_Mode.MESHLETS {
                        color = meshlet_tint;
                    }

                    mesh_set_vertex_position(cast(u32) vertex_local, params.camera_vp * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0});
                    mesh_set_vertex_color(cast(u32) vertex_local, color);
                }

                for triangle_local: 0..cast(s64) meshlet.triangle_count-1 {
                    packed := meshlet_triangles[meshlet.triangle_offset + cast(u32) triangle_local];
                    i0 := packed & 0xFF;
                    i1 := (packed >> 8) & 0xFF;
                    i2 := (packed >> 16) & 0xFF;
                    mesh_set_triangle(cast(u32) triangle_local, i0, i1, i2);
                }
            }
        }
    }
} @mesh_shader

fragment_main :: (using input: Fragment_In) -> Vector4 @SV_Target0 {
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
