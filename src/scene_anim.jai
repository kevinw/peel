#import "Math";
ai :: #import "assimp";

Scene_Anim_State :: struct {
    model_index: s32 = -1;
    clip_index: s32 = -1;
    locals: [..]Scene_Node_Transform;
    worlds: [..]Matrix4;
    morph_weights: [..]float;
}

scene_anim_init :: (state: *Scene_Anim_State, geo: *Scene_Geo, model_index: s32, clip_index: s32 = -1) {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    model := geo.models[model_index];

    state.model_index = model_index;
    state.clip_index = clip_index;
    state.locals.allocator = context.allocator;
    state.worlds.allocator = context.allocator;
    state.morph_weights.allocator = context.allocator;
    array_resize(*state.locals, model.node_count);
    array_resize(*state.worlds, model.node_count);
    array_resize(*state.morph_weights, geo.morph_targets.count);

    for local_index: 0..model.node_count-1 {
        state.locals[local_index] = geo.node_bind_transforms[model.node_start + local_index];
        state.worlds[local_index] = Matrix4_Identity;
    }
    reset_morph_weights_to_bind(state, geo);
}

scene_anim_deinit :: (state: *Scene_Anim_State) {
    array_free(state.locals);
    array_free(state.worlds);
    array_free(state.morph_weights);
    state.* = .{};
}

scene_anim_sample :: (state: *Scene_Anim_State, geo: *Scene_Geo, clip_index: s32, seconds: float, blend_from_bind: float = 1.0) {
    assert(state.model_index >= 0 && state.model_index < geo.models.count);
    model := geo.models[state.model_index];
    assert(model.node_count == state.locals.count);
    assert(model.node_count == state.worlds.count);

    blend := clamp(blend_from_bind, 0.0, 1.0);
    for local_index: 0..model.node_count-1 {
        state.locals[local_index] = geo.node_bind_transforms[model.node_start + local_index];
    }
    reset_morph_weights_to_bind(state, geo);

    if clip_index >= 0 {
        clip := geo.anim_clips[clip_index];
        ticks_per_second := ifx clip.ticks_per_second > 0.0 then clip.ticks_per_second else 25.0;
        time_in_ticks := seconds * ticks_per_second;
        sample_time := time_in_ticks;
        if clip.duration > 0.0 {
            sample_time -= floor(sample_time / clip.duration) * clip.duration;
        }

        if clip.channel_count > 0 {
            for channel_index: clip.channel_start .. clip.channel_start + clip.channel_count - 1 {
                channel := geo.anim_channels[channel_index];
                local_index := channel.node_index - cast(s32) model.node_start;
                if local_index < 0 || local_index >= state.locals.count continue;

                bind := geo.node_bind_transforms[channel.node_index];
                sampled := bind;

                if channel.position_key_count > 0 {
                    sampled.translation = sample_vec3_keys(anim_position_key_span(geo, channel), sample_time, clip.duration);
                }
                if channel.rotation_key_count > 0 {
                    sampled.rotation = sample_quat_keys(anim_rotation_key_span(geo, channel), sample_time, clip.duration);
                }
                if channel.scale_key_count > 0 {
                    sampled.scale = sample_vec3_keys(anim_scale_key_span(geo, channel), sample_time, clip.duration);
                }

                state.locals[local_index] = .{
                    translation = lerp(bind.translation, sampled.translation, blend),
                    rotation = quat_slerp(bind.rotation, sampled.rotation, blend),
                    scale = lerp(bind.scale, sampled.scale, blend),
                };
            }
        }

        if clip.morph_channel_count > 0 {
            for channel_index: clip.morph_channel_start .. clip.morph_channel_start + clip.morph_channel_count - 1 {
                channel := geo.anim_morph_channels[channel_index];
                if channel.morph_target_index >= state.morph_weights.count continue;
                bind_weight := geo.morph_targets[channel.morph_target_index].default_weight;
                sampled_weight := sample_float_keys(anim_morph_key_span(geo, channel), sample_time, clip.duration);
                state.morph_weights[channel.morph_target_index] = lerp(bind_weight, sampled_weight, blend);
            }
        }
    }

    for local_index: 0..model.node_count-1 {
        node_index := model.node_start + local_index;
        parent_world := Matrix4_Identity;
        parent_index := geo.nodes[node_index].parent_index;
        if parent_index >= cast(s32) model.node_start {
            parent_world = state.worlds[parent_index - cast(s32) model.node_start];
        }
        local_matrix := make_sqt_matrix4(state.locals[local_index].scale, state.locals[local_index].rotation, state.locals[local_index].translation);
        state.worlds[local_index] = parent_world * local_matrix;
    }
}

scene_anim_recompute_worlds :: (state: *Scene_Anim_State, geo: *Scene_Geo) {
    assert(state.model_index >= 0 && state.model_index < geo.models.count);
    model := geo.models[state.model_index];
    assert(model.node_count == state.locals.count);
    assert(model.node_count == state.worlds.count);

    for local_index: 0..model.node_count-1 {
        node_index := model.node_start + local_index;
        parent_world := Matrix4_Identity;
        parent_index := geo.nodes[node_index].parent_index;
        if parent_index >= cast(s32) model.node_start {
            parent_world = state.worlds[parent_index - cast(s32) model.node_start];
        }
        local_matrix := make_sqt_matrix4(state.locals[local_index].scale, state.locals[local_index].rotation, state.locals[local_index].translation);
        state.worlds[local_index] = parent_world * local_matrix;
    }
}

scene_anim_write_skin_matrices :: (dst: []Vector4, geo: *Scene_Geo, state: *Scene_Anim_State, mesh: Scene_Mesh, mesh_node_index: s32) -> s64 {
    assert(state.model_index >= 0 && state.model_index < geo.models.count);
    model := geo.models[state.model_index];
    if mesh.skin_bone_count == 0 return 0;
    assert(dst.count >= mesh.skin_bone_count * 4);

    mesh_local_index := mesh_node_index - cast(s32) model.node_start;
    assert(mesh_local_index >= 0 && mesh_local_index < state.worlds.count);
    inverse_ok, inv_mesh_transform := inverse(state.worlds[mesh_local_index]);
    assert(inverse_ok, "Failed to invert current mesh transform for animated model '%'.", model.name);

    for i: 0..mesh.skin_bone_count-1 {
        skin_bone := geo.mesh_skin_bones[mesh.skin_bone_start + i];
        local_index := skin_bone.node_index - cast(s32) model.node_start;
        assert(local_index >= 0 && local_index < state.worlds.count);
        skin_matrix := inv_mesh_transform * state.worlds[local_index] * skin_bone.inverse_bind;
        row_start := cast(s64) i * 4;
        dst[row_start + 0] = skin_matrix.v[0];
        dst[row_start + 1] = skin_matrix.v[1];
        dst[row_start + 2] = skin_matrix.v[2];
        dst[row_start + 3] = skin_matrix.v[3];
    }
    return mesh.skin_bone_count;
}

scene_anim_write_morph_weights :: (dst: []float, geo: *Scene_Geo, state: *Scene_Anim_State, mesh: Scene_Mesh) -> s64 {
    assert(state.model_index >= 0 && state.model_index < geo.models.count);
    if mesh.morph_target_count == 0 return 0;
    assert(dst.count >= mesh.morph_target_count);

    for i: 0..mesh.morph_target_count-1 {
        dst[i] = state.morph_weights[mesh.morph_target_start + i];
    }
    return mesh.morph_target_count;
}

#scope_file

reset_morph_weights_to_bind :: (state: *Scene_Anim_State, geo: *Scene_Geo) {
    for it: 0..state.morph_weights.count-1 {
        state.morph_weights[it] = geo.morph_targets[it].default_weight;
    }
}

make_sqt_matrix4 :: (scale: Vector3, rotation: Quaternion, translation: Vector3) -> Matrix4 {
    ai_scale := ai.Vector3D.{scale.x, scale.y, scale.z};
    ai_rotation := ai.Quaternion.{w = rotation.w, x = rotation.x, y = rotation.y, z = rotation.z};
    ai_translation := ai.Vector3D.{translation.x, translation.y, translation.z};
    out: Matrix4;
    ai.Matrix4FromScalingQuaternionPosition(cast(*ai.Matrix4x4) *out, *ai_scale, *ai_rotation, *ai_translation);
    return out;
}

sample_vec3_keys :: (keys: []$T, sample_time: float, clip_duration: float) -> Vector3 {
    if keys.count == 0 return .{0.0, 0.0, 0.0};
    if keys.count == 1 return keys[0].value;

    frame := find_keyframe_index(keys, sample_time);
    next_frame := (frame + 1) % keys.count;
    key := keys[frame];
    next_key := keys[next_frame];
    diff_time := next_key.time - key.time;
    if diff_time < 0.0 diff_time += clip_duration;
    if diff_time <= 0.0 return key.value;
    factor := clamp((sample_time - key.time) / diff_time, 0.0, 1.0);
    return lerp(key.value, next_key.value, factor);
}

sample_quat_keys :: (keys: []Scene_Anim_Rotation_Key, sample_time: float, clip_duration: float) -> Quaternion {
    if keys.count == 0 return .{w = 1.0};
    if keys.count == 1 return keys[0].value;

    frame := find_keyframe_index(keys, sample_time);
    next_frame := (frame + 1) % keys.count;
    key := keys[frame];
    next_key := keys[next_frame];
    diff_time := next_key.time - key.time;
    if diff_time < 0.0 diff_time += clip_duration;
    if diff_time <= 0.0 return key.value;
    factor := clamp((sample_time - key.time) / diff_time, 0.0, 1.0);
    return quat_slerp(key.value, next_key.value, factor);
}

sample_float_keys :: (keys: []Scene_Anim_Morph_Key, sample_time: float, clip_duration: float) -> float {
    if keys.count == 0 return 0.0;
    if keys.count == 1 return keys[0].value;

    frame := find_keyframe_index(keys, sample_time);
    next_frame := (frame + 1) % keys.count;
    key := keys[frame];
    next_key := keys[next_frame];
    diff_time := next_key.time - key.time;
    if diff_time < 0.0 diff_time += clip_duration;
    if diff_time <= 0.0 return key.value;
    factor := clamp((sample_time - key.time) / diff_time, 0.0, 1.0);
    return lerp(key.value, next_key.value, factor);
}

find_keyframe_index :: (keys: []$T, sample_time: float) -> s64 {
    frame: s64 = 0;
    while frame < keys.count - 1 {
        if sample_time < keys[frame + 1].time break;
        frame += 1;
    }
    return frame;
}

quat_slerp :: (a: Quaternion, b: Quaternion, t: float) -> Quaternion {
    ai_a := ai.Quaternion.{w = a.w, x = a.x, y = a.y, z = a.z};
    ai_b := ai.Quaternion.{w = b.w, x = b.x, y = b.y, z = b.z};
    ai_out: ai.Quaternion;
    ai.QuaternionInterpolate(*ai_out, *ai_a, *ai_b, t);
    return .{ai_out.x, ai_out.y, ai_out.z, ai_out.w};
}

anim_position_key_span :: (geo: *Scene_Geo, channel: Scene_Anim_Channel) -> []Scene_Anim_Position_Key {
    result := geo.anim_position_keys;
    result.data += channel.position_key_start;
    result.count = channel.position_key_count;
    return result;
}

anim_rotation_key_span :: (geo: *Scene_Geo, channel: Scene_Anim_Channel) -> []Scene_Anim_Rotation_Key {
    result := geo.anim_rotation_keys;
    result.data += channel.rotation_key_start;
    result.count = channel.rotation_key_count;
    return result;
}

anim_scale_key_span :: (geo: *Scene_Geo, channel: Scene_Anim_Channel) -> []Scene_Anim_Scale_Key {
    result := geo.anim_scale_keys;
    result.data += channel.scale_key_start;
    result.count = channel.scale_key_count;
    return result;
}

anim_morph_key_span :: (geo: *Scene_Geo, channel: Scene_Anim_Morph_Channel) -> []Scene_Anim_Morph_Key {
    result := geo.anim_morph_keys;
    result.data += channel.key_start;
    result.count = channel.key_count;
    return result;
}
