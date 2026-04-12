Mediapipe_Instance_Ref :: struct {
    instance_index: u32; // Dynamic scene instance driven by the mediapipe demo pose.
    node_index: s32; // Scene-geo node sampled for this instance.
    mesh_index: u32; // Mesh rendered by this instance.
}

Mediapipe_Demo_Runtime :: struct {
    body_anim: Scene_Anim_State; // Sampled body pose used for skinning and morph output.
    body_root: Matrix4 = Matrix4_Identity; // World transform applied to the body model.
    body_scale: float = 1.0; // Uniform scale applied to the body model.
    focus: Vector3 = .{0.0, 2.3, -6.2}; // Editor camera focus point for the demo.
    body_casts_shadows: bool = true; // Whether body batches should render into the shadow map.
    face_casts_shadows: bool = true; // Whether face batches should render into the shadow map.
    body_instances: [..]Mediapipe_Instance_Ref; // Dynamic scene instances driven by the body pose.
    face_instances: [..]Mediapipe_Instance_Ref; // Dynamic scene instances driven by the face pose.
    body_model_index: s32 = -1; // Scene model index for the animated body.
    face_model_index: s32 = -1; // Scene model index for the separate face asset.
    body_mesh_index: s32 = -1; // Mesh index used to resolve important body bones.
    face_mesh_index: s32 = -1; // Mesh index for the separate face demo mesh.
    face_node_index: s32 = -1; // Body node used as the face attachment source.
    face_root: Matrix4 = Matrix4_Identity; // World transform applied to the separate face mesh.
    body_hips_node_index: s32 = -1; // Hips bone used for additive demo motion.
    body_torso_node_index: s32 = -1; // Torso bone used for additive demo motion.
    body_neck_node_index: s32 = -1; // Neck bone used for additive demo motion.
    body_head_node_index: s32 = -1; // Head bone used for additive demo motion.
    body_upper_arm_l_node_index: s32 = -1; // Left upper arm bone used for additive demo motion.
    body_upper_arm_r_node_index: s32 = -1; // Right upper arm bone used for additive demo motion.
    body_forearm_l_node_index: s32 = -1; // Left forearm bone used for additive demo motion.
    body_forearm_r_node_index: s32 = -1; // Right forearm bone used for additive demo motion.
    body_thigh_l_node_index: s32 = -1; // Left thigh bone used for additive demo motion.
    body_thigh_r_node_index: s32 = -1; // Right thigh bone used for additive demo motion.
    body_shin_l_node_index: s32 = -1; // Left shin bone used for additive demo motion.
    body_shin_r_node_index: s32 = -1; // Right shin bone used for additive demo motion.
}

// Reset mediapipe runtime refs while keeping owned arrays alive.
reset :: (using runtime: *Mediapipe_Demo_Runtime) {
    body_instances.allocator = context.allocator;
    face_instances.allocator = context.allocator;
    array_reset(*body_instances);
    array_reset(*face_instances);
    runtime.* = .{
        focus = .{0.0, 2.3, -6.2},
        body_casts_shadows = true,
        face_casts_shadows = true,
    };
}

// Free all mediapipe runtime arrays and sampled animation state.
deinit :: (using runtime: *Mediapipe_Demo_Runtime) {
    deinit(*body_anim);
    array_free(body_instances);
    array_free(face_instances);
    runtime.* = .{};
}

// Append body and face demo instances plus animated-batch refs.
append_instances :: (using runtime: *Mediapipe_Demo_Runtime, instances_cpu: *[..]Scene_Instance, total_skin_matrix_count: *s64) {
    body_model_index = scene_geo_model_index_by_name(*scene_geo, "sample");
    face_model_index = scene_geo_model_index_by_name(*scene_geo, "mediapipe-canonical-face");

    if body_model_index >= 0 {
        scene_anim_init(*body_anim, *scene_geo, body_model_index, -1);
        body_scale = scale_model_to_target_extent(body_model_index, 8.0);
        body_bounds := scene_geo_model_bounds(*scene_geo, body_model_index);
        body_ground_y := -body_bounds.min.y * body_scale;
        body_pos := Vector3.{0.0, body_ground_y, -5.8};
        body_root = make_trs_matrix(body_pos, quat_from_euler_deg(.{0.0, 180.0, 0.0}), .{body_scale, body_scale, body_scale});

        body_model := scene_geo.models[body_model_index];
        body_mesh_index = find_model_mesh_index_by_node_name(body_model_index, "body");
        body_hips_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "hips");
        body_torso_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "torso");
        body_neck_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "neck");
        body_head_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "head");
        body_upper_arm_l_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "upper_arm.L");
        body_upper_arm_r_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "upper_arm.R");
        body_forearm_l_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "forearm.L");
        body_forearm_r_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "forearm.R");
        body_thigh_l_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "thigh.L");
        body_thigh_r_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "thigh.R");
        body_shin_l_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "shin.L");
        body_shin_r_node_index = find_mesh_skin_bone_node_index(body_mesh_index, "shin.R");

        for geo_node_index: body_model.node_start .. body_model.node_start + body_model.node_count - 1 {
            geo_node := scene_geo.nodes[geo_node_index];
            if geo_node.mesh_ref_count == 0 continue;
            for mesh_ref_offset: 0..geo_node.mesh_ref_count-1 {
                mesh_index := scene_geo.node_mesh_refs[geo_node.first_mesh_ref + mesh_ref_offset];
                mesh := scene_geo.meshes[mesh_index];
                batch := array_add(*scene_batches);
                batch.mesh_index = mesh_index;
                batch.first_instance = cast(u32) instances_cpu.count;
                batch.instance_count = 1;
                array_add(*batch_pick_object_ids, 0);
                array_add(*shadow_skip_batch, !body_casts_shadows);
                array_add(*batch_compiled_node_indices, -1);

                instance_index := cast(u32) instances_cpu.count;
                array_add(instances_cpu, .{
                    world = body_root,
                    tint = .{1.0, 1.0, 1.0, 1.0},
                    shadow_view_proj = Matrix4_Identity,
                });
                array_add(*body_instances, .{
                    instance_index = instance_index,
                    node_index = cast(s32) geo_node_index,
                    mesh_index = mesh_index,
                });

                if mesh.skin_bone_count > 0 {
                    array_add(*animated_batches, .{
                        batch_index = cast(s32) scene_batches.count - 1,
                        node_index = cast(s32) geo_node_index,
                        skin_matrix_start = cast(u32) total_skin_matrix_count.*,
                        skin_matrix_count = mesh.skin_bone_count,
                        source = .MEDIAPIPE_DEMO,
                    });
                    total_skin_matrix_count.* += mesh.skin_bone_count;
                }
            }
        }
    }

    if body_model_index >= 0 {
        face_node_index = scene_geo_model_node_index_by_name(*scene_geo, body_model_index, "face.001");
        if face_node_index >= 0 {
            face_node := scene_geo.nodes[face_node_index];
            if face_node.mesh_ref_count > 0 {
                face_mesh_index = cast(s32) scene_geo.node_mesh_refs[face_node.first_mesh_ref];
                face_scale := scale_model_to_target_extent(body_model_index, 3.0);
                face_root = make_trs_matrix(.{5.4, 2.6, -6.4}, quat_from_euler_deg(.{0.0, 200.0, 0.0}), .{face_scale, face_scale, face_scale});

                mesh := scene_geo.meshes[face_mesh_index];
                batch := array_add(*scene_batches);
                batch.mesh_index = cast(u32) face_mesh_index;
                batch.first_instance = cast(u32) instances_cpu.count;
                batch.instance_count = 1;
                array_add(*batch_pick_object_ids, 0);
                array_add(*shadow_skip_batch, !face_casts_shadows);
                array_add(*batch_compiled_node_indices, -1);

                instance_index := cast(u32) instances_cpu.count;
                array_add(instances_cpu, .{
                    world = face_root,
                    tint = .{1.0, 1.0, 1.0, 1.0},
                    shadow_view_proj = Matrix4_Identity,
                });
                array_add(*face_instances, .{
                    instance_index = instance_index,
                    node_index = face_node_index,
                    mesh_index = cast(u32) face_mesh_index,
                });

                if mesh.skin_bone_count > 0 {
                    array_add(*animated_batches, .{
                        batch_index = cast(s32) scene_batches.count - 1,
                        node_index = face_node_index,
                        skin_matrix_start = cast(u32) total_skin_matrix_count.*,
                        skin_matrix_count = mesh.skin_bone_count,
                        source = .MEDIAPIPE_DEMO,
                    });
                    total_skin_matrix_count.* += mesh.skin_bone_count;
                }
            }
        }
    }
}

// Sample and write the current demo pose into the dynamic instance buffer.
update_pose :: (using runtime: *Mediapipe_Demo_Runtime, t: float, dynamic_instances: []Scene_Instance) {
    if body_model_index < 0 return;

    scene_anim_sample(*body_anim, *scene_geo, -1, t, 1.0);

    pose_t := t;
    apply_bone_offset(runtime, body_hips_node_index, quat_from_euler_deg(.{0.0, sin(pose_t * 0.55) * 10.0, 0.0}));
    apply_bone_offset(runtime, body_torso_node_index, quat_from_euler_deg(.{sin(pose_t * 0.8) * 10.0, 0.0, sin(pose_t * 0.5) * 9.0}));
    apply_bone_offset(runtime, body_neck_node_index, quat_from_euler_deg(.{sin(pose_t * 0.9) * 9.0, sin(pose_t * 0.7) * 18.0, 0.0}));
    apply_bone_offset(runtime, body_head_node_index, quat_from_euler_deg(.{sin(pose_t * 1.0) * 14.0, sin(pose_t * 0.6 + 0.6) * 28.0, sin(pose_t * 0.8) * 7.0}));
    apply_bone_offset(runtime, body_upper_arm_l_node_index, quat_from_euler_deg(.{-40.0 + sin(pose_t * 1.7) * 28.0, 0.0, -52.0 + sin(pose_t * 1.3) * 22.0}));
    apply_bone_offset(runtime, body_upper_arm_r_node_index, quat_from_euler_deg(.{-24.0 + sin(pose_t * 1.9 + 1.4) * 38.0, 0.0, 52.0 + sin(pose_t * 1.2 + 0.4) * 26.0}));
    apply_bone_offset(runtime, body_forearm_l_node_index, quat_from_euler_deg(.{-36.0 + sin(pose_t * 2.1 + 0.4) * 26.0, 0.0, -18.0}));
    apply_bone_offset(runtime, body_forearm_r_node_index, quat_from_euler_deg(.{-54.0 + sin(pose_t * 2.2 + 1.0) * 34.0, 0.0, 18.0}));
    apply_bone_offset(runtime, body_thigh_l_node_index, quat_from_euler_deg(.{sin(pose_t * 1.4) * 14.0, 0.0, 0.0}));
    apply_bone_offset(runtime, body_thigh_r_node_index, quat_from_euler_deg(.{sin(pose_t * 1.4 + PI) * 14.0, 0.0, 0.0}));
    apply_bone_offset(runtime, body_shin_l_node_index, quat_from_euler_deg(.{max(0.0, sin(pose_t * 1.4 + 0.25)) * 18.0, 0.0, 0.0}));
    apply_bone_offset(runtime, body_shin_r_node_index, quat_from_euler_deg(.{max(0.0, sin(pose_t * 1.4 + PI + 0.25)) * 18.0, 0.0, 0.0}));

    set_model_morph_wave_weights(runtime, *body_anim, body_model_index, t, 0.0);
    scene_anim_recompute_worlds(*body_anim, *scene_geo);

    body_model := scene_geo.models[body_model_index];
    for body_instances {
        node_local_index := it.node_index - cast(s32) body_model.node_start;
        instance_world := body_root;
        if node_local_index >= 0 && node_local_index < body_anim.worlds.count {
            instance_world = body_root * body_anim.worlds[node_local_index];
        }
        dynamic_instances[it.instance_index].world = instance_world;
    }
    for face_instances {
        node_local_index := it.node_index - cast(s32) body_model.node_start;
        instance_world := face_root;
        if node_local_index >= 0 && node_local_index < body_anim.worlds.count {
            instance_world = face_root * body_anim.worlds[node_local_index];
        }
        dynamic_instances[it.instance_index].world = instance_world;
    }
}

// Write the sampled body morph weights into the scene morph buffer.
write_morph_weights :: (using runtime: *Mediapipe_Demo_Runtime, morph_weights: []float, t: float) {
    if body_model_index >= 0 {
        for mesh_index: scene_geo.models[body_model_index].mesh_start .. scene_geo.models[body_model_index].mesh_start + scene_geo.models[body_model_index].mesh_count - 1 {
            mesh := scene_geo.meshes[mesh_index];
            if mesh.morph_target_count == 0 continue;
            dst := morph_weights;
            dst.data += mesh.morph_target_start;
            dst.count = mesh.morph_target_count;
            written := scene_anim_write_morph_weights(dst, *scene_geo, *body_anim, mesh);
            assert(written == mesh.morph_target_count);
        }
    }

    _ = t;
}

#scope_file

// Resolve the first mesh referenced by a named node inside one model.
find_model_mesh_index_by_node_name :: (model_index: s32, node_name: string) -> s32 {
    if model_index < 0 return -1;
    model := scene_geo.models[model_index];
    target_node_index := scene_geo_model_node_index_by_name(*scene_geo, model_index, node_name);
    if target_node_index < 0 return -1;
    node := scene_geo.nodes[target_node_index];
    if node.mesh_ref_count <= 0 return -1;
    return cast(s32) scene_geo.node_mesh_refs[node.first_mesh_ref];
}

// Resolve a skinned bone node by name from one mesh.
find_mesh_skin_bone_node_index :: (mesh_index: s32, node_name: string) -> s32 {
    if mesh_index < 0 return -1;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.skin_bone_count <= 0 return -1;
    for i: 0..mesh.skin_bone_count-1 {
        skin_bone := scene_geo.mesh_skin_bones[mesh.skin_bone_start + i];
        if scene_geo.node_names[skin_bone.node_index] == node_name return skin_bone.node_index;
    }
    return -1;
}

// Resolve a morph target by name from one mesh.
find_mesh_morph_target_index_by_name :: (mesh_index: s32, target_name: string) -> s32 {
    if mesh_index < 0 return -1;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.morph_target_count <= 0 return -1;
    for local_index: 0..mesh.morph_target_count-1 {
        global_index := mesh.morph_target_start + cast(u32) local_index;
        if global_index >= scene_geo.morph_target_names.count continue;
        if scene_geo.morph_target_names[global_index] == target_name return cast(s32) global_index;
    }
    return -1;
}

// Clamp and assign one named morph target weight.
set_named_morph_weight :: (state: *Scene_Anim_State, mesh_index: s32, target_name: string, weight: float) {
    target_index := find_mesh_morph_target_index_by_name(mesh_index, target_name);
    if target_index < 0 return;
    state.morph_weights[target_index] = clamp(weight, 0.0, 1.0);
}

// Compute a uniform scale that fits one model into a target extent.
scale_model_to_target_extent :: (model_index: s32, target_extent: float) -> float {
    bounds := scene_geo_model_bounds(*scene_geo, model_index);
    size := bounds.max - bounds.min;
    max_extent := max(max(size.x, size.y), size.z);
    return ifx max_extent > 0.0 then target_extent / max_extent else 1.0;
}

// Apply one additive local-space rotation offset to a body bone.
apply_bone_offset :: (runtime: *Mediapipe_Demo_Runtime, node_index: s32, rotation_offset: Quaternion) {
    if node_index < 0 return;
    local_index := node_index - cast(s32) scene_geo.models[runtime.body_model_index].node_start;
    if local_index < 0 || local_index >= runtime.body_anim.locals.count return;
    local := *runtime.body_anim.locals[local_index];
    local.rotation = rotation_offset * local.rotation;
    normalize_or_identity(*local.rotation);
}

// Drive the mediapipe demo morph targets with a simple procedural wave pattern.
set_model_morph_wave_weights :: (runtime: *Mediapipe_Demo_Runtime, state: *Scene_Anim_State, model_index: s32, t: float, phase: float) {
    _ = runtime;
    if model_index < 0 return;
    model := scene_geo.models[model_index];
    for mesh_index: model.mesh_start .. model.mesh_start + model.mesh_count - 1 {
        mesh := scene_geo.meshes[mesh_index];
        if mesh.morph_target_count == 0 continue;
        for local_index: 0..mesh.morph_target_count-1 {
            state.morph_weights[mesh.morph_target_start + local_index] = 0.0;
        }
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeBlinkLeft",  clamp(0.5 + 0.5 * sin(t * 1.7 + phase), 0.0, 1.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeBlinkRight", clamp(0.5 + 0.5 * sin(t * 1.7 + phase + 1.7), 0.0, 1.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeSquintLeft", 0.12 + 0.10 * sin(t * 1.1 + phase + 0.2));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeSquintRight", 0.12 + 0.10 * sin(t * 1.1 + phase + 1.1));
        set_named_morph_weight(state, cast(s32) mesh_index, "browInnerUp", 0.2 + 0.18 * sin(t * 0.7 + phase));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthSmileLeft", 0.2 + 0.18 * sin(t * 0.9 + phase + 2.0));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthSmileRight", 0.2 + 0.18 * sin(t * 0.9 + phase + 3.3));
        set_named_morph_weight(state, cast(s32) mesh_index, "jawOpen", 0.18 + 0.16 * sin(t * 1.2 + phase + 0.8));
        set_named_morph_weight(state, cast(s32) mesh_index, "mouthFunnel", 0.12 + 0.12 * sin(t * 0.6 + phase + 1.3));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeWideLeft", 0.05 + 0.08 * sin(t * 1.0 + phase + 0.5));
        set_named_morph_weight(state, cast(s32) mesh_index, "eyeWideRight", 0.05 + 0.08 * sin(t * 1.0 + phase + 1.0));
    }
}
