#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

MESHLET_MAX_VERTICES :: 64;
MESHLET_MAX_TRIANGLES :: 124;
TASK_EMIT_MESHLET_COUNT : u32 : 64;
SCENE_ALPHA_MODE_OPAQUE :: 0;
SCENE_ALPHA_MODE_MASK   :: 1;
MESHLET_DEBUG_DISABLE_FRUSTUM_CULL : u32 : 1;
MESHLET_DEBUG_FORCE_FIRST_MESHLET  : u32 : 2;
MESHLET_DEBUG_SYNTHETIC_TRIANGLE   : u32 : 4;
MESHLET_DEBUG_FORCE_ALL_MESHLETS   : u32 : 8;
MESHLET_DEBUG_SIMPLE_SELECTION    : u32 : 16;
MESHLET_DEBUG_DISABLE_LODS        : u32 : 32;
MESHLET_DEBUG_TASK_MARKERS        : u32 : 64;

Fragment_In :: struct {
    position: Vector4; @SV_Position
    color: Vector3; @TEXCOORD0
    uv: Vector2; @TEXCOORD1
    world_pos: Vector3; @TEXCOORD2
    normal: Vector3; @TEXCOORD3
    tangent: Vector4; @TEXCOORD4
}

hash01 :: (x: u32) -> float {
    phase := cast(float) x * cast(float) 12.9898 + cast(float) 78.233;
    return fract(sin(phase) * cast(float) 43758.5453);
}

hue2rgb :: (hue: float) -> Vector3 {
    h := fract(hue);
    return clamp(Vector3.{
        abs(h * 6.0 - 3.0) - 1.0,
        2.0 - abs(h * 6.0 - 2.0),
        2.0 - abs(h * 6.0 - 4.0),
    }, 0.0, 1.0);
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

Task_Payload :: struct {
    instance_index: u32;
    mesh_index: u32;
    meshlet_start: u32;
    meshlet_count: u32;
    chunk_index: u32;
}

lod_from_mesh_index :: (meshes: *Scene_Mesh, base_mesh_index: u32, selected_mesh_index: u32) -> u32 {
    if selected_mesh_index == base_mesh_index return 0;
    return 1 + (selected_mesh_index - meshes[base_mesh_index].lod_mesh_start);
}

sphere_visible :: (params: *Meshlet_Grid_Params, center: Vector3, radius: float) -> bool {
    if (params.debug_flags & MESHLET_DEBUG_DISABLE_FRUSTUM_CULL) != 0 return true;
    for plane: params.frustum_planes {
        distance := dot(plane.xyz, center) + plane.w;
        if distance < -radius return false;
    }
    return true;
}

world_max_scale :: (world: Matrix4) -> float {
    axis_x4 := world * Vector4.{1.0, 0.0, 0.0, 0.0};
    axis_y4 := world * Vector4.{0.0, 1.0, 0.0, 0.0};
    axis_z4 := world * Vector4.{0.0, 0.0, 1.0, 0.0};
    return max(length(axis_x4.xyz), max(length(axis_y4.xyz), length(axis_z4.xyz)));
}

scene_material_alpha :: (params: *Meshlet_Grid_Params, uv: Vector2) -> float {
    alpha := params.base_color_factor.w;
    if params.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(params.base_color_texture_index, params.sampler_index, uv).w;
    }
    if params.opacity_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(params.opacity_texture_index, params.sampler_index, uv).x;
    }
    return alpha;
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
    meshlet_bounds: *Vector4,
    instances: *Meshlet_Grid_Instance,
    selected_lods: *u32,
    target_lods: *u32,
    transition_alphas: *float,
) {
    _ = selected_lods; _ = target_lods; _ = transition_alphas;
    mesh_set_max_output_counts(MESHLET_MAX_VERTICES, MESHLET_MAX_TRIANGLES);
    debug_synthetic_triangle := (params.debug_flags & MESHLET_DEBUG_SYNTHETIC_TRIANGLE) != 0;
    if debug_synthetic_triangle {
        mesh_set_output_counts(3, 1);
        mesh_set_vertex(0, Fragment_In.{
            position = .{-0.55, -0.45, 0.0, 1.0},
            color = .{1.0, 0.2, 0.1},
            uv = .{0.0, 0.0},
            world_pos = .{0.0, 0.0, 0.0},
            normal = .{0.0, 0.0, 1.0},
            tangent = .{1.0, 0.0, 0.0, 1.0},
        });
        mesh_set_vertex(1, Fragment_In.{
            position = .{0.0, 0.62, 0.0, 1.0},
            color = .{0.1, 1.0, 0.2},
            uv = .{1.0, 0.0},
            world_pos = .{0.0, 0.0, 0.0},
            normal = .{0.0, 0.0, 1.0},
            tangent = .{1.0, 0.0, 0.0, 1.0},
        });
        mesh_set_vertex(2, Fragment_In.{
            position = .{0.55, -0.45, 0.0, 1.0},
            color = .{0.1, 0.3, 1.0},
            uv = .{0.0, 1.0},
            world_pos = .{0.0, 0.0, 0.0},
            normal = .{0.0, 0.0, 1.0},
            tangent = .{1.0, 0.0, 0.0, 1.0},
        });
        mesh_set_triangle(0, 0, 1, 2);
    } else {
        payload_instance_index := mesh_payload_ptr(Task_Payload).instance_index;
        instance := instances[payload_instance_index];
        payload_mesh_index := mesh_payload_ptr(Task_Payload).mesh_index;
        payload_meshlet_count := mesh_payload_ptr(Task_Payload).meshlet_count;
        if (params.debug_flags & MESHLET_DEBUG_TASK_MARKERS) != 0 {
            marker_meshlet_index := mesh_payload_ptr(Task_Payload).meshlet_start + mesh_group_id_x();
            if mesh_group_id_x() >= payload_meshlet_count {
                mesh_set_output_counts(0, 0);
                return;
            }
            marker_bound := meshlet_bounds[marker_meshlet_index];
            marker_center4 := instance.world * Vector4.{marker_bound.x, marker_bound.y, marker_bound.z, 1.0};
            marker_world := marker_center4.xyz;
            marker_color := hue2rgb(hash01(mesh_group_id_x()));
            marker_size := max(marker_bound.w * 0.20, 0.08);
            mesh_set_output_counts(3, 1);
            mesh_set_vertex(0, Fragment_In.{
                position = params.camera_vp * Vector4.{marker_world.x - marker_size, marker_world.y - marker_size, marker_world.z, 1.0},
                color = marker_color,
                uv = .{0.0, 0.0},
                world_pos = marker_world,
                normal = .{0.0, 1.0, 0.0},
                tangent = .{1.0, 0.0, 0.0, 1.0},
            });
            mesh_set_vertex(1, Fragment_In.{
                position = params.camera_vp * Vector4.{marker_world.x, marker_world.y + marker_size, marker_world.z, 1.0},
                color = marker_color,
                uv = .{1.0, 0.0},
                world_pos = marker_world,
                normal = .{0.0, 1.0, 0.0},
                tangent = .{1.0, 0.0, 0.0, 1.0},
            });
            mesh_set_vertex(2, Fragment_In.{
                position = params.camera_vp * Vector4.{marker_world.x + marker_size, marker_world.y - marker_size, marker_world.z, 1.0},
                color = marker_color,
                uv = .{0.0, 1.0},
                world_pos = marker_world,
                normal = .{0.0, 1.0, 0.0},
                tangent = .{1.0, 0.0, 0.0, 1.0},
            });
            mesh_set_triangle(0, 0, 1, 2);
            return;
        }
        if mesh_group_id_x() >= payload_meshlet_count {
            mesh_set_output_counts(0, 0);
            return;
        }
        meshlet_index := mesh_payload_ptr(Task_Payload).meshlet_start + mesh_group_id_x();
        meshlet := meshlets[meshlet_index];
        meshlet_bound := meshlet_bounds[meshlet_index];
        meshlet_center4 := instance.world * Vector4.{meshlet_bound.x, meshlet_bound.y, meshlet_bound.z, 1.0};
        meshlet_center := Vector3.{meshlet_center4.x, meshlet_center4.y, meshlet_center4.z};
        meshlet_radius := max(meshlet_bound.w * world_max_scale(instance.world), 0.001);
        clamped_vertex_count := min(meshlet.vertex_count, cast(u32) MESHLET_MAX_VERTICES);
        clamped_triangle_count := min(meshlet.triangle_count, cast(u32) MESHLET_MAX_TRIANGLES);
        if !sphere_visible(params, meshlet_center, meshlet_radius) || clamped_vertex_count < 3 || clamped_triangle_count == 0 {
            mesh_set_output_counts(0, 0);
        } else {
            mesh_set_output_counts(clamped_vertex_count, clamped_triangle_count);

            meshlet_hue := hash01(meshlet_index);
            meshlet_tint := hue2rgb(meshlet_hue);
            for vertex_local: 0..cast(s64) clamped_vertex_count-1 {
                vertex_index := meshlet.vertex_offset + cast(u32) vertex_local;
                v := vertices[meshlet_vertices[vertex_index]];
                world_pos4 := instance.world * Vector4.{v.position.x, v.position.y, v.position.z, 1.0};
                world_pos := Vector3.{world_pos4.x, world_pos4.y, world_pos4.z};
                world_normal4 := instance.world * Vector4.{v.normal.x, v.normal.y, v.normal.z, 0.0};
                world_normal := normalize(Vector3.{world_normal4.x, world_normal4.y, world_normal4.z});
                world_tangent4 := instance.world * Vector4.{v.tangent.x, v.tangent.y, v.tangent.z, 0.0};
                world_tangent := normalize(Vector3.{world_tangent4.x, world_tangent4.y, world_tangent4.z});

                color := Vector3.{1.0, 1.0, 1.0};
                if params.debug_mode == cast(u32) Meshlet_Grid_Debug_Mode.LODS {
                    color = lod_debug_color(lod_from_mesh_index(meshes, params.batch_mesh_index, payload_mesh_index));
                } else if params.debug_mode == cast(u32) Meshlet_Grid_Debug_Mode.MESHLETS {
                    color = meshlet_tint;
                }
                vertex_out: Fragment_In = .{
                    position = params.camera_vp * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0},
                    color = color,
                    uv = v.uv,
                    world_pos = world_pos,
                    normal = world_normal,
                    tangent = .{world_tangent.x, world_tangent.y, world_tangent.z, v.tangent.w},
                };
                mesh_set_vertex(cast(u32) vertex_local, vertex_out);
            }

            for triangle_local: 0..cast(s64) clamped_triangle_count-1 {
                packed := meshlet_triangles[meshlet.triangle_offset + cast(u32) triangle_local];
                i0 := packed & 0xFF;
                i1 := (packed >> 8) & 0xFF;
                i2 := (packed >> 16) & 0xFF;
                mesh_set_triangle(cast(u32) triangle_local, i0, i1, i2);
            }
        }
    }
} @mesh_shader

task_main :: (
    params: *Meshlet_Grid_Params,
    meshes: *Scene_Mesh,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    vertices: *Scene_Vertex,
    materials: *Scene_Material,
    meshlets: *Scene_Meshlet,
    meshlet_vertices: *u32,
    meshlet_triangles: *u32,
    meshlet_bounds: *Vector4,
    instances: *Meshlet_Grid_Instance,
    selected_lods: *u32,
    target_lods: *u32,
    transition_alphas: *float,
) {
    _ = vertices; _ = materials; _ = meshlets; _ = meshlet_vertices; _ = meshlet_triangles; _ = meshlet_bounds;
    _ = target_lods; _ = transition_alphas;
    task_id := task_group_id_x();
    meshlet_chunk_count := params.batch_meshlet_chunk_count;

    emit_meshlet_count: u32;
    selected_instance_index: u32;
    selected_meshlet_start: u32;
    selected_mesh_index: u32 = params.batch_mesh_index;

    if (params.debug_flags & MESHLET_DEBUG_SYNTHETIC_TRIANGLE) != 0 {
        task_payload_ptr(Task_Payload).instance_index = 0;
        task_payload_ptr(Task_Payload).mesh_index = params.batch_mesh_index;
        task_payload_ptr(Task_Payload).meshlet_start = 0;
        task_payload_ptr(Task_Payload).meshlet_count = 1;
        task_payload_ptr(Task_Payload).chunk_index = 0;
        task_set_mesh_groups(1, 1, 1);
    } else if (params.debug_flags & MESHLET_DEBUG_FORCE_ALL_MESHLETS) != 0 {
        selected_instance_index = params.batch_first_instance;
        selected_mesh_index = params.batch_mesh_index;
        selected_meshlet_start = meshlet_meshes[selected_mesh_index].meshlet_start;
        emit_meshlet_count = meshlet_meshes[selected_mesh_index].meshlet_count;
        task_payload_ptr(Task_Payload).instance_index = selected_instance_index;
        task_payload_ptr(Task_Payload).mesh_index = selected_mesh_index;
        task_payload_ptr(Task_Payload).meshlet_start = selected_meshlet_start;
        task_payload_ptr(Task_Payload).meshlet_count = emit_meshlet_count;
        task_payload_ptr(Task_Payload).chunk_index = 0;
        task_set_mesh_groups(emit_meshlet_count, 1, 1);
    } else if (params.debug_flags & MESHLET_DEBUG_FORCE_FIRST_MESHLET) != 0 {
        selected_instance_index = params.batch_first_instance;
        selected_mesh_index = params.batch_mesh_index;
        selected_meshlet_start = meshlet_meshes[selected_mesh_index].meshlet_start;
        emit_meshlet_count = min(cast(u32) 1, meshlet_meshes[selected_mesh_index].meshlet_count);
        task_payload_ptr(Task_Payload).instance_index = selected_instance_index;
        task_payload_ptr(Task_Payload).mesh_index = selected_mesh_index;
        task_payload_ptr(Task_Payload).meshlet_start = selected_meshlet_start;
        task_payload_ptr(Task_Payload).meshlet_count = emit_meshlet_count;
        task_payload_ptr(Task_Payload).chunk_index = 0;
        task_set_mesh_groups(emit_meshlet_count, 1, 1);
    } else if (params.debug_flags & MESHLET_DEBUG_SIMPLE_SELECTION) != 0 {
        object_group_index: u32;
        if meshlet_chunk_count > 0 {
            object_group_index = params.batch_object_group_start + task_id;
            instance_local := object_group_index / meshlet_chunk_count;
            chunk_local := object_group_index % meshlet_chunk_count;
            if instance_local < params.batch_instance_count {
                selected_instance_index = params.batch_first_instance + instance_local;
                selected_mesh_index = params.batch_mesh_index;
                chunk_meshlet_start := chunk_local * TASK_EMIT_MESHLET_COUNT;
                total_meshlet_count := meshlet_meshes[selected_mesh_index].meshlet_count;
                if chunk_meshlet_start < total_meshlet_count {
                    selected_meshlet_start = meshlet_meshes[selected_mesh_index].meshlet_start + chunk_meshlet_start;
                    emit_meshlet_count = min(TASK_EMIT_MESHLET_COUNT, total_meshlet_count - chunk_meshlet_start);
                }
            }
        }

        task_payload_ptr(Task_Payload).instance_index = selected_instance_index;
        task_payload_ptr(Task_Payload).mesh_index = selected_mesh_index;
        task_payload_ptr(Task_Payload).meshlet_start = selected_meshlet_start;
        task_payload_ptr(Task_Payload).meshlet_count = emit_meshlet_count;
        task_payload_ptr(Task_Payload).chunk_index = object_group_index;
        if (params.debug_flags & MESHLET_DEBUG_TASK_MARKERS) != 0 && emit_meshlet_count > 0 {
            emit_meshlet_count = 1;
        }
        task_set_mesh_groups(emit_meshlet_count, 1, 1);
    } else {
        object_group_index: u32;
        if meshlet_chunk_count > 0 {
            object_group_index = params.batch_object_group_start + task_id;
            instance_local := object_group_index / meshlet_chunk_count;
            chunk_local := object_group_index % meshlet_chunk_count;
            if instance_local < params.batch_instance_count {
                selected_instance_index = params.batch_first_instance + instance_local;
                selected_lod_mesh_index := params.batch_mesh_index;
                if (params.debug_flags & MESHLET_DEBUG_DISABLE_LODS) == 0 &&
                    meshes[params.batch_mesh_index].lod_mesh_count > 0 {
                    lod_count := meshes[params.batch_mesh_index].lod_mesh_count;
                    lod_slot := min(selected_lods[selected_instance_index], lod_count);
                    if lod_slot > 0 {
                        selected_lod_mesh_index = meshes[params.batch_mesh_index].lod_mesh_start + (lod_slot - 1);
                    }
                }

                chunk_meshlet_start := chunk_local * TASK_EMIT_MESHLET_COUNT;
                lod_meshlet_mesh := meshlet_meshes[selected_lod_mesh_index];
                lod_meshlet_count := lod_meshlet_mesh.meshlet_count;
                if chunk_meshlet_start < lod_meshlet_count {
                    selected_mesh_index = selected_lod_mesh_index;
                    selected_meshlet_start = lod_meshlet_mesh.meshlet_start + chunk_meshlet_start;
                    emit_meshlet_count = min(TASK_EMIT_MESHLET_COUNT, lod_meshlet_count - chunk_meshlet_start);

                    if emit_meshlet_count > 0 && (params.debug_flags & MESHLET_DEBUG_DISABLE_FRUSTUM_CULL) == 0 {
                        instance := instances[selected_instance_index];
                        lod_local_center := lod_meshlet_mesh.bounds_center_radius.xyz;
                        lod_local_radius := max(lod_meshlet_mesh.bounds_center_radius.w, 0.001);
                        lod_world_center4 := instance.world * Vector4.{lod_local_center.x, lod_local_center.y, lod_local_center.z, 1.0};
                        lod_world_center := lod_world_center4.xyz;
                        if !sphere_visible(params, lod_world_center, lod_local_radius) {
                            emit_meshlet_count = 0;
                        }
                    }
                }
            }
        }

        task_payload_ptr(Task_Payload).instance_index = selected_instance_index;
        task_payload_ptr(Task_Payload).mesh_index = selected_mesh_index;
        task_payload_ptr(Task_Payload).meshlet_start = selected_meshlet_start;
        task_payload_ptr(Task_Payload).meshlet_count = emit_meshlet_count;
        task_payload_ptr(Task_Payload).chunk_index = object_group_index;
        if (params.debug_flags & MESHLET_DEBUG_TASK_MARKERS) != 0 && emit_meshlet_count > 0 {
            emit_meshlet_count = 1;
        }
        task_set_mesh_groups(emit_meshlet_count, 1, 1);
    }
} @task_shader

fragment_main :: (
    using input: Fragment_In,
    params: *Meshlet_Grid_Params,
) -> Vector4 @SV_Target0 {
    alpha := scene_material_alpha(params, uv);
    if params.alpha_mode == SCENE_ALPHA_MODE_MASK && alpha < params.alpha_cutoff discard();
    if params.debug_mode != cast(u32) Meshlet_Grid_Debug_Mode.SHADED {
        return .{color.x, color.y, color.z, 1.0};
    }

    albedo := params.base_color_factor;
    if params.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        tex := sample_2d(params.base_color_texture_index, params.sampler_index, uv);
        albedo = .{
            tex.x * params.base_color_factor.x,
            tex.y * params.base_color_factor.y,
            tex.z * params.base_color_factor.z,
            tex.w * params.base_color_factor.w,
        };
    }

    base_rgb := albedo.xyz;
    N := normalize(normal);
    if params.normal_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        T := normalize(tangent.xyz);
        B := normalize(cross(N, T)) * tangent.w;
        n_sample := sample_2d(params.normal_texture_index, params.sampler_index, uv);
        n_ts := n_sample * 2.0 - 1.0;
        N = normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
    }

    ao := 1.0;
    if params.ao_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        ao = sample_2d(params.ao_texture_index, params.sampler_index, uv).x;
    }
    roughness := 0.82;
    if params.roughness_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        roughness = sample_2d(params.roughness_texture_index, params.sampler_index, uv).y;
    }

    sun_dir := normalize(-params.light_dir);
    L := sun_dir;
    V := normalize(params.eye_position - world_pos);
    H := normalize(L + V);
    ndl_raw := dot(N, L);
    wrapped_ndl := clamp((ndl_raw + 0.24) / 1.24, 0.0, 1.0);
    ndh := max(dot(N, H), 0.0);

    ambient := base_rgb * mix(0.18, 0.32, ao);
    diffuse := base_rgb * wrapped_ndl * 0.74;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    specular := sun_col * (pow(ndh, spec_power) * spec_strength);
    shaded := ambient + diffuse + specular;

    return .{
        shaded.x,
        shaded.y,
        shaded.z,
        alpha,
    };
} @fragment_shader
