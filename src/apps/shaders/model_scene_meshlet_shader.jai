#load "meshlet_common.jai";

Model_Scene_Meshlet_Flags :: enum_flags u32 {
    HAS_SHADOWS          :: 1 << 0;
    HAS_LODS             :: 1 << 1;
    HAS_MORPHS           :: 1 << 2;
    HAS_SKINNING         :: 1 << 3;
    DISABLE_FRUSTUM_CULL :: 1 << 4;
}

Model_Scene_Meshlet_Constants :: struct {
    flags: Model_Scene_Meshlet_Flags = .HAS_SHADOWS | .HAS_LODS | .HAS_MORPHS | .HAS_SKINNING;
    debug_mode: Meshlet_Grid_Debug_Mode = .SHADED;
} @function_constants

Model_Scene_Meshlet_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
}

Model_Scene_Meshlet_Params :: struct {
    camera_vp: Matrix4;
    frustum_planes: [6]Vector4;
    eye_position: Vector3;
    lod_projection_scale: float;
    lod_radius_threshold: float;
    lod_metric_power: float;
    batch_mesh_index: u32;

    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    shadow_view_proj: Matrix4;
    shadow_meta: Vector4;

    base_color_factor: Vector4;
    sampler_index: u32;
    base_color_texture_index: u32;
    opacity_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    alpha_mode: u32;
    alpha_cutoff: float;

    batch_first_instance: u32;
    batch_instance_count: u32;
    batch_max_meshlet_count: u32;
    batch_meshlet_chunk_count: u32;
    batch_object_group_start: u32;

    mesh_base_vertex: u32;
    skin_matrix_count: u32;
    morph_target_count: u32;
    morph_vertex_count: u32;
}

Model_Scene_Task_Params :: struct {
    camera_vp: Matrix4;
    frustum_planes: [6]Vector4;
    eye_position: Vector3;
    lod_projection_scale: float;
    lod_radius_threshold: float;
    lod_metric_power: float;
    batch_mesh_index: u32;

    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    shadow_view_proj: Matrix4;
    shadow_meta: Vector4;

    base_color_factor: Vector4;
    sampler_index: u32;
    base_color_texture_index: u32;
    opacity_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    alpha_mode: u32;
    alpha_cutoff: float;
    batch_first_instance: u32;
    batch_instance_count: u32;
    batch_max_meshlet_count: u32;
    batch_meshlet_chunk_count: u32;
    batch_object_group_start: u32;
}

Model_Scene_Meshlet_Fragment_In :: struct {
    position: Vector4; @SV_Position
    color: Vector3; @TEXCOORD0
    uv: Vector2; @TEXCOORD1
    world_pos: Vector3; @TEXCOORD2
    normal: Vector3; @TEXCOORD3
    tangent: Vector4; @TEXCOORD4
    tint: Vector4; @TEXCOORD5
    shadow_uvz: Vector3; @TEXCOORD6
    shadow_meta: Vector4; @TEXCOORD7
}

model_scene_meshlet_alpha :: (params: *Model_Scene_Meshlet_Params, uv: Vector2, tint_alpha: float) -> float {
    alpha := params.base_color_factor.w * tint_alpha;
    if params.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(params.base_color_texture_index, params.sampler_index, uv).w;
    }
    if params.opacity_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(params.opacity_texture_index, params.sampler_index, uv).x;
    }
    return alpha;
}

model_scene_meshlet_instance_world :: (instances: *Model_Scene_Meshlet_Instance, instance_index: u32) -> Matrix4 {
    return instances[instance_index].world;
}

model_scene_meshlet_instance_tint :: (instances: *Model_Scene_Meshlet_Instance, instance_index: u32) -> Vector4 {
    return instances[instance_index].tint;
}

model_scene_meshlet_load_skin_matrix :: (rows: *Vector4, bone_index: u32) -> Matrix4 {
    row_start := bone_index * 4;
    return .{
        rows[row_start + 0].x, rows[row_start + 0].y, rows[row_start + 0].z, rows[row_start + 0].w,
        rows[row_start + 1].x, rows[row_start + 1].y, rows[row_start + 1].z, rows[row_start + 1].w,
        rows[row_start + 2].x, rows[row_start + 2].y, rows[row_start + 2].z, rows[row_start + 2].w,
        rows[row_start + 3].x, rows[row_start + 3].y, rows[row_start + 3].z, rows[row_start + 3].w,
    };
}

model_scene_meshlet_shadow_visibility :: (shadow_meta: Vector4, shadow_uvz: Vector3) -> float {
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

    lit: float;
    if z <= t0.x + bias lit += 1.0;
    if z <= t1.x + bias lit += 1.0;
    if z <= t2.x + bias lit += 1.0;
    if z <= t3.x + bias lit += 1.0;
    return mix(0.28, 1.0, lit * 0.25);
}

model_scene_mesh_main :: (
    params: *Model_Scene_Meshlet_Params,
    meshes: *Scene_Mesh,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    vertices: *Scene_Vertex,
    meshlets: *Scene_Meshlet,
    meshlet_vertices: *u32,
    meshlet_triangles: *u32,
    meshlet_bounds: *Vector4,
    instances: *Model_Scene_Meshlet_Instance,
    morph_weights: *float,
    skin_matrices: *Vector4,
    morph_vertex_deltas: *Scene_Morph_Vertex_Delta,
    using constants: Model_Scene_Meshlet_Constants,
) {
    mesh_set_max_output_counts(MESHLET_MAX_VERTICES, MESHLET_MAX_TRIANGLES);

    payload_instance_index := mesh_payload_ptr(Task_Payload).instance_index;
    instance_world := model_scene_meshlet_instance_world(instances, payload_instance_index);
    instance_tint := model_scene_meshlet_instance_tint(instances, payload_instance_index);
    payload_mesh_index := mesh_payload_ptr(Task_Payload).mesh_index;
    payload_meshlet_count := mesh_payload_ptr(Task_Payload).meshlet_count;

    if mesh_group_id_x() >= payload_meshlet_count {
        mesh_set_output_counts(0, 0);
        return;
    }

    meshlet_index := mesh_payload_ptr(Task_Payload).meshlet_start + mesh_group_id_x();
    meshlet := meshlets[meshlet_index];
    meshlet_bound := meshlet_bounds[meshlet_index];
    meshlet_center4 := instance_world * Vector4.{meshlet_bound.x, meshlet_bound.y, meshlet_bound.z, 1.0};
    meshlet_center := meshlet_center4.xyz;
    meshlet_radius := max(meshlet_bound.w * meshlet_world_max_scale(instance_world), 0.001);
    clamped_vertex_count := min(meshlet.vertex_count, cast(u32) MESHLET_MAX_VERTICES);
    clamped_triangle_count := min(meshlet.triangle_count, cast(u32) MESHLET_MAX_TRIANGLES);
    if (flags & .DISABLE_FRUSTUM_CULL) == 0 && !meshlet_sphere_visible(params, meshlet_center, meshlet_radius) || clamped_vertex_count < 3 || clamped_triangle_count == 0 {
        mesh_set_output_counts(0, 0);
        return;
    }

    mesh_set_output_counts(clamped_vertex_count, clamped_triangle_count);

    meshlet_tint := meshlet_hue2rgb(meshlet_hash01(meshlet_index));
    chunk_tint := meshlet_hue2rgb(meshlet_hash01(mesh_payload_ptr(Task_Payload).chunk_index));

    for vertex_local: 0..cast(s64) clamped_vertex_count-1 {
        vertex_index := meshlet.vertex_offset + cast(u32) vertex_local;
        global_vertex_index := meshlet_vertices[vertex_index];
        v := vertices[global_vertex_index];

        local_pos := Vector4.{v.position.x, v.position.y, v.position.z, 1.0};
        local_normal := Vector4.{v.normal.x, v.normal.y, v.normal.z, 0.0};
        local_tangent := Vector4.{v.tangent.x, v.tangent.y, v.tangent.z, 0.0};
        local_vertex_index := global_vertex_index - params.mesh_base_vertex;
        if (flags & .HAS_MORPHS) != 0 && params.morph_target_count > 0 && local_vertex_index < params.morph_vertex_count {
            for target_index: 0..cast(s64) params.morph_target_count-1 {
                weight := morph_weights[target_index];
                if abs(weight) <= 0.00001 continue;
                delta_index := cast(u32) target_index * params.morph_vertex_count + local_vertex_index;
                delta := morph_vertex_deltas[delta_index];
                local_pos += delta.position * weight;
                local_normal += delta.normal * weight;
                local_tangent += delta.tangent * weight;
            }
            local_pos.w = 1.0;
            local_normal.w = 0.0;
            local_tangent.w = 0.0;
        }

        skinned_pos4 := local_pos;
        skinned_normal4 := local_normal;
        skinned_tangent4 := local_tangent;
        if (flags & .HAS_SKINNING) != 0 && params.skin_matrix_count > 0 {
            skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
            skinned_normal4 = .{0.0, 0.0, 0.0, 0.0};
            skinned_tangent4 = .{0.0, 0.0, 0.0, 0.0};
            total_weight: float = 0.0;
            if v.bone_weights.x > 0.0 {
                bone_index := cast(u32) v.bone_indices.x;
                if bone_index < params.skin_matrix_count {
                    skin := model_scene_meshlet_load_skin_matrix(skin_matrices, bone_index);
                    skinned_pos4 += (skin * local_pos) * v.bone_weights.x;
                    skinned_normal4 += (skin * local_normal) * v.bone_weights.x;
                    skinned_tangent4 += (skin * local_tangent) * v.bone_weights.x;
                    total_weight += v.bone_weights.x;
                }
            }
            if v.bone_weights.y > 0.0 {
                bone_index := cast(u32) v.bone_indices.y;
                if bone_index < params.skin_matrix_count {
                    skin := model_scene_meshlet_load_skin_matrix(skin_matrices, bone_index);
                    skinned_pos4 += (skin * local_pos) * v.bone_weights.y;
                    skinned_normal4 += (skin * local_normal) * v.bone_weights.y;
                    skinned_tangent4 += (skin * local_tangent) * v.bone_weights.y;
                    total_weight += v.bone_weights.y;
                }
            }
            if v.bone_weights.z > 0.0 {
                bone_index := cast(u32) v.bone_indices.z;
                if bone_index < params.skin_matrix_count {
                    skin := model_scene_meshlet_load_skin_matrix(skin_matrices, bone_index);
                    skinned_pos4 += (skin * local_pos) * v.bone_weights.z;
                    skinned_normal4 += (skin * local_normal) * v.bone_weights.z;
                    skinned_tangent4 += (skin * local_tangent) * v.bone_weights.z;
                    total_weight += v.bone_weights.z;
                }
            }
            if v.bone_weights.w > 0.0 {
                bone_index := cast(u32) v.bone_indices.w;
                if bone_index < params.skin_matrix_count {
                    skin := model_scene_meshlet_load_skin_matrix(skin_matrices, bone_index);
                    skinned_pos4 += (skin * local_pos) * v.bone_weights.w;
                    skinned_normal4 += (skin * local_normal) * v.bone_weights.w;
                    skinned_tangent4 += (skin * local_tangent) * v.bone_weights.w;
                    total_weight += v.bone_weights.w;
                }
            }
            if total_weight <= 0.0 {
                skinned_pos4 = local_pos;
                skinned_normal4 = local_normal;
                skinned_tangent4 = local_tangent;
            }
        }

        world_pos4 := instance_world * skinned_pos4;
        world_pos := world_pos4.xyz;
        world_normal4 := instance_world * skinned_normal4;
        world_normal := normalize(world_normal4.xyz);
        world_tangent4 := instance_world * skinned_tangent4;
        world_tangent := normalize(world_tangent4.xyz);
        out_color := Vector3.{1.0, 1.0, 1.0};
        if debug_mode == .LODS {
            out_color = meshlet_lod_debug_color(meshlet_lod_from_mesh_index(meshes, params.batch_mesh_index, payload_mesh_index));
        } else if debug_mode == .CHUNKS {
            out_color = chunk_tint;
        } else if debug_mode == .MESHLETS {
            out_color = meshlet_tint;
        }

        shadow_uvz := Vector3.{0.0, 0.0, 2.0};
        shadow_meta := Vector4.{0.0, 0.0, 2.0, 0.0};
        if (flags & .HAS_SHADOWS) != 0 {
            light_clip := params.shadow_view_proj * world_pos4;
            shadow_uvz = .{light_clip.x * 0.5 + 0.5, light_clip.y * 0.5 + 0.5, light_clip.z};
            shadow_meta = params.shadow_meta;
        }

        mesh_set_vertex(cast(u32) vertex_local, Model_Scene_Meshlet_Fragment_In.{
            position = params.camera_vp * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0},
            color = out_color,
            uv = v.uv,
            world_pos = world_pos,
            normal = world_normal,
            tangent = .{world_tangent.x, world_tangent.y, world_tangent.z, v.tangent.w},
            tint = instance_tint,
            shadow_uvz = shadow_uvz,
            shadow_meta = shadow_meta,
        });
    }

    for triangle_local: 0..cast(s64) clamped_triangle_count-1 {
        packed := meshlet_triangles[meshlet.triangle_offset + cast(u32) triangle_local];
        i0 := packed & 0xFF;
        i1 := (packed >> 8) & 0xFF;
        i2 := (packed >> 16) & 0xFF;
        mesh_set_triangle(cast(u32) triangle_local, i0, i1, i2);
    }
} @mesh_shader

model_scene_task_main :: (
    params: *Model_Scene_Task_Params,
    meshes: *Scene_Mesh,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    vertices: *Scene_Vertex,
    meshlets: *Scene_Meshlet,
    meshlet_vertices: *u32,
    meshlet_triangles: *u32,
    meshlet_bounds: *Vector4,
    instances: *Model_Scene_Meshlet_Instance,
    morph_weights: *float,
    skin_matrices: *Vector4,
    morph_vertex_deltas: *Scene_Morph_Vertex_Delta,
    using constants: Model_Scene_Meshlet_Constants
) {
    _ = vertices; _ = meshlets; _ = meshlet_vertices; _ = meshlet_triangles; _ = meshlet_bounds; _ = morph_weights; _ = skin_matrices; _ = morph_vertex_deltas;
    task_id := task_group_id_x();
    meshlet_chunk_count := params.batch_meshlet_chunk_count;
    emit_meshlet_count: u32;
    selected_instance_index: u32;
    selected_meshlet_start: u32;
    selected_mesh_index: u32 = params.batch_mesh_index;
    object_group_index: u32;

    if meshlet_chunk_count > 0 {
        object_group_index = params.batch_object_group_start + task_id;
        instance_local := object_group_index / meshlet_chunk_count;
        chunk_local := object_group_index % meshlet_chunk_count;
        if instance_local < params.batch_instance_count {
            selected_instance_index = params.batch_first_instance + instance_local;
            instance_world := model_scene_meshlet_instance_world(instances, selected_instance_index);
            base_mesh := meshes[params.batch_mesh_index];
            if (flags & .HAS_LODS) != 0 && base_mesh.lod_mesh_count > 0 {
                lod_metric := meshlet_lod_metric_for_instance(params, meshlet_meshes, params.batch_mesh_index, instance_world);
                lod_slot := min(meshlet_lod_slot_for_metric(lod_metric, base_mesh.lod_mesh_count), base_mesh.lod_mesh_count);
                if lod_slot > 0 {
                    selected_mesh_index = base_mesh.lod_mesh_start + lod_slot - 1;
                }
            }

            chunk_meshlet_start := chunk_local * TASK_EMIT_MESHLET_COUNT;
            lod_meshlet_mesh := meshlet_meshes[selected_mesh_index];
            lod_meshlet_count := lod_meshlet_mesh.meshlet_count;
            if chunk_meshlet_start < lod_meshlet_count {
                selected_meshlet_start = lod_meshlet_mesh.meshlet_start + chunk_meshlet_start;
                emit_meshlet_count = min(TASK_EMIT_MESHLET_COUNT, lod_meshlet_count - chunk_meshlet_start);

                if emit_meshlet_count > 0 && (flags & .DISABLE_FRUSTUM_CULL) == 0 {
                    lod_local_center := lod_meshlet_mesh.bounds_center_radius.xyz;
                    lod_local_radius := max(lod_meshlet_mesh.bounds_center_radius.w, 0.001);
                    lod_world_center4 := instance_world * Vector4.{lod_local_center.x, lod_local_center.y, lod_local_center.z, 1.0};
                    lod_world_center := lod_world_center4.xyz;
                    lod_world_radius := lod_local_radius * meshlet_world_max_scale(instance_world);
                    if !meshlet_sphere_visible(params, lod_world_center, lod_world_radius) {
                        emit_meshlet_count = 0;
                    }
                }
            }
        }
    }

    payload := task_payload_ptr(Task_Payload);
    payload.instance_index = selected_instance_index;
    payload.mesh_index = selected_mesh_index;
    payload.meshlet_start = selected_meshlet_start;
    payload.meshlet_count = emit_meshlet_count;
    payload.chunk_index = object_group_index;
    task_set_mesh_groups(emit_meshlet_count, 1, 1);
} @task_shader

model_scene_meshlet_fragment_main :: (
    using input: Model_Scene_Meshlet_Fragment_In,
    params: *Model_Scene_Meshlet_Params,
    using constants: Model_Scene_Meshlet_Constants,
) -> Vector4 @SV_Target0 {
    alpha := model_scene_meshlet_alpha(params, uv, tint.w);
    if params.alpha_mode == SCENE_ALPHA_MODE_MASK && alpha < params.alpha_cutoff discard();
    if debug_mode != .SHADED {
        return .{color.x, color.y, color.z, 1.0};
    }

    tex := sample_2d(params.base_color_texture_index, params.sampler_index, uv);
    base_rgb := Vector3.{
        tex.x * params.base_color_factor.x * tint.x,
        tex.y * params.base_color_factor.y * tint.y,
        tex.z * params.base_color_factor.z * tint.z,
    };
    N := normalize(normal);
    ao := 1.0;
    roughness := 0.82;
    if params.normal_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        T := normalize(tangent.xyz);
        B := normalize(cross(N, T)) * tangent.w;
        n_sample := sample_2d(params.normal_texture_index, params.sampler_index, uv);
        n_ts := decode_bc5_normal(n_sample);
        N = normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
    }
    if params.ao_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        ao = sample_2d(params.ao_texture_index, params.sampler_index, uv).x;
    }
    if params.roughness_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        roughness = sample_2d(params.roughness_texture_index, params.sampler_index, uv).y;
    }

    sun_dir := normalize(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);
    L := sun_dir;
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl_raw := dot(N, L);
    ndh := max(dot(N, H), 0.0);
    shadow := 1.0;
    if (flags & .HAS_SHADOWS) != 0 {
        shadow = model_scene_meshlet_shadow_visibility(shadow_meta, shadow_uvz);
    }
    indirect := model_scene_indirect_light(N, sun_dir, sun_strength, shadow) * mix(0.62, 1.0, ao);
    wrapped_ndl := clamp((ndl_raw + 0.28) / 1.28, 0.0, 1.0);
    diffuse := wrapped_ndl * 0.74 * shadow * sun_strength;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    specular := pow(ndh, spec_power) * spec_strength * shadow * sun_strength;
    lit_color := base_rgb * indirect + base_rgb * diffuse + sun_col * specular;
    lit_color = model_scene_apply_atmosphere(lit_color, world_pos, params.camera_pos, sun_dir);
    return .{lit_color.x, lit_color.y, lit_color.z, alpha};
} @fragment_shader
