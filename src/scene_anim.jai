#import "Math";
ai :: #import "assimp";

Scene_Anim_State :: struct {
    // Model this sampled pose belongs to.
    model_index: s32 = -1;
    // Last clip sampled into this state, or -1 for mixed/bind poses.
    clip_index: s32 = -1;
    // Per-node local SQT transforms for the model.
    locals: [..]Scene_Node_Transform;
    // Per-node model-space/world-space transforms rebuilt from locals.
    worlds: [..]Matrix4;
    // Full morph target weight buffer for the scene.
    morph_weights: [..]float;
}

Scene_Anim_Clip_Player :: struct {
    // Clip index this player samples.
    clip_index: s32 = -1;
    // Accumulated playback time in seconds.
    time: float;
    // Playback speed multiplier applied during advance.
    rate: float = 1.0;
    // Blend from bind pose into the sampled clip.
    bind_blend: float = 1.0;
}

Scene_Anim_Blend_Node :: struct {
    // Blend node operation type.
    kind: enum u32 {
        CLIP;
        LERP;
    };
    // Source clip player for clip nodes.
    clip_player_index: s32 = -1;
    // First input node for lerp nodes.
    input_a: s32 = -1;
    // Second input node for lerp nodes.
    input_b: s32 = -1;
    // Interpolation factor for lerp nodes.
    alpha: float;
}

Scene_Anim_Blend_Tree :: struct {
    // Model this blend tree evaluates.
    model_index: s32 = -1;
    // Stateful clip players owned by the graph.
    clip_players: [..]Scene_Anim_Clip_Player;
    // Blend graph nodes in evaluation order.
    nodes: [..]Scene_Anim_Blend_Node;
    // Cached sampled state for each node.
    node_states: [..]Scene_Anim_State;
    // Final output node index for consumers.
    output_node_index: s32 = -1;
}

// Allocate pose buffers for one model's sampled animation state.
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

// Free all buffers owned by a sampled animation state.
deinit :: (state: *Scene_Anim_State) {
    array_free(state.locals);
    array_free(state.worlds);
    array_free(state.morph_weights);
    state.* = .{};
}

// Sample one clip into a state, optionally blending from bind pose.
scene_anim_sample :: (state: *Scene_Anim_State, geo: *Scene_Geo, clip_index: s32, seconds: float, blend_from_bind: float = 1.0) {
    assert(state.model_index >= 0 && state.model_index < geo.models.count);
    model := geo.models[state.model_index];
    assert(model.node_count == state.locals.count);
    assert(model.node_count == state.worlds.count);
    state.clip_index = clip_index;

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

// Initialize an empty blend tree for a specific model.
init :: (tree: *Scene_Anim_Blend_Tree, geo: *Scene_Geo, model_index: s32) {
    deinit(tree);
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    tree.model_index = model_index;
    tree.clip_players.allocator = context.allocator;
    tree.nodes.allocator = context.allocator;
    tree.node_states.allocator = context.allocator;
    tree.output_node_index = -1;
}

// Free all clip players, nodes, and cached states in a blend tree.
deinit :: (tree: *Scene_Anim_Blend_Tree) {
    for *tree.node_states deinit(it);
    array_free(tree.node_states);
    array_free(tree.nodes);
    array_free(tree.clip_players);
    tree.* = .{};
}

// Add a leaf node that samples a single clip player.
add_clip_node :: (tree: *Scene_Anim_Blend_Tree, geo: *Scene_Geo, clip_index: s32, rate: float = 1.0, bind_blend: float = 1.0) -> s32, s32 {
    assert(tree.model_index >= 0, "Scene_Anim_Blend_Tree must be initialized before adding nodes.");
    clip_player_index := cast(s32) tree.clip_players.count;
    array_add(*tree.clip_players, .{
        clip_index = clip_index,
        rate = rate,
        bind_blend = bind_blend,
    });

    node_index := cast(s32) tree.nodes.count;
    array_add(*tree.nodes, .{
        kind = .CLIP,
        clip_player_index = clip_player_index,
    });

    state := array_add(*tree.node_states);
    scene_anim_init(state, geo, tree.model_index, clip_index);
    return clip_player_index, node_index;
}

// Add a lerp node that blends two earlier node outputs.
add_lerp_node :: scene_anim_blend_tree_add_lerp_node;
scene_anim_blend_tree_add_lerp_node :: (using tree: *Scene_Anim_Blend_Tree, geo: *Scene_Geo, input_a: s32, input_b: s32, alpha: float = 0.0) -> s32 {
    assert(model_index >= 0, "Scene_Anim_Blend_Tree must be initialized before adding nodes.");
    assert(input_a >= 0 && input_a < nodes.count, "Invalid blend-tree input_a node index %", input_a);
    assert(input_b >= 0 && input_b < nodes.count, "Invalid blend-tree input_b node index %", input_b);

    node_index := cast(s32) nodes.count;
    array_add(*nodes, .{
        kind = .LERP,
        input_a = input_a,
        input_b = input_b,
        alpha = alpha,
    });

    state := array_add(*node_states);
    scene_anim_init(state, geo, model_index, -1);
    return node_index;
}

// Mark which node is the graph output consumed by runtime code.
set_output  :: (using tree: *Scene_Anim_Blend_Tree, node_index: s32) {
    assert(node_index >= 0 && node_index < nodes.count, "Invalid blend-tree output node index %", node_index);
    output_node_index = node_index;
}

// Return the sampled state for the current output node.
output_state :: (using tree: *Scene_Anim_Blend_Tree) -> *Scene_Anim_State {
    return *tree.node_states[output_node_index];
}

// Return a mutable clip player by index.
player :: (tree: *Scene_Anim_Blend_Tree, clip_player_index: s32) -> *Scene_Anim_Clip_Player {
    return *tree.clip_players[clip_player_index];
}

// Return a mutable blend node by index.
blend_tree_node :: (tree: *Scene_Anim_Blend_Tree, node_index: s32) -> *Scene_Anim_Blend_Node {
    return *tree.nodes[node_index];
}

// Advance all clip players by dt using their current playback rates.
advance :: (using tree: *Scene_Anim_Blend_Tree, dt: float) {
    for * clip_players {
        if it.clip_index < 0 continue;
        it.time += dt * it.rate;
    }
}

// Evaluate the blend tree into its per-node cached states.
sample :: scene_anim_blend_tree_sample;
scene_anim_blend_tree_sample :: (tree: *Scene_Anim_Blend_Tree, geo: *Scene_Geo) {
    assert(tree.model_index >= 0 && tree.model_index < geo.models.count);
    assert(tree.nodes.count == tree.node_states.count, "Blend tree node/state count mismatch.");

    for node_index: 0..tree.nodes.count-1 {
        node := tree.nodes[node_index];
        out_state := tree.node_states.data + node_index;
        if #complete node.kind == {
        case .CLIP;
            assert(node.clip_player_index >= 0 && node.clip_player_index < tree.clip_players.count);
            player := tree.clip_players[node.clip_player_index];
            scene_anim_sample(out_state, geo, player.clip_index, player.time, player.bind_blend);
        case .LERP;
            assert(node.input_a >= 0 && node.input_a < cast(s32) node_index, "Blend-tree lerp input_a must reference an earlier node.");
            assert(node.input_b >= 0 && node.input_b < cast(s32) node_index, "Blend-tree lerp input_b must reference an earlier node.");
            a := tree.node_states.data + node.input_a;
            b := tree.node_states.data + node.input_b;
            scene_anim_blend_states(out_state, geo, a, b, node.alpha);
        }
    }
}

// Rebuild world transforms after external local pose edits.
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

// Write skinned bone matrices for one mesh from a sampled pose.
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

// Write morph weights for one mesh from a sampled pose.
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

// Blend two fully sampled states into a destination state.
scene_anim_blend_states :: (dst: *Scene_Anim_State, geo: *Scene_Geo, a: *Scene_Anim_State, b: *Scene_Anim_State, alpha: float) {
    assert(dst != null && a != null && b != null);
    assert(a.model_index == b.model_index, "Can only blend animation states for the same model (% vs %).", a.model_index, b.model_index);
    assert(dst.model_index == a.model_index, "Blend destination model mismatch (% vs %).", dst.model_index, a.model_index);
    assert(a.locals.count == b.locals.count && dst.locals.count == a.locals.count, "Blend local-count mismatch.");
    assert(a.morph_weights.count == b.morph_weights.count && dst.morph_weights.count == a.morph_weights.count, "Blend morph-count mismatch.");

    t := clamp(alpha, 0.0, 1.0);
    dst.clip_index = -1;
    for local_index: 0..dst.locals.count-1 {
        dst.locals[local_index] = .{
            translation = lerp(a.locals[local_index].translation, b.locals[local_index].translation, t),
            rotation = quat_slerp(a.locals[local_index].rotation, b.locals[local_index].rotation, t),
            scale = lerp(a.locals[local_index].scale, b.locals[local_index].scale, t),
        };
    }
    for morph_index: 0..dst.morph_weights.count-1 {
        dst.morph_weights[morph_index] = lerp(a.morph_weights[morph_index], b.morph_weights[morph_index], t);
    }
    scene_anim_recompute_worlds(dst, geo);
}

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
