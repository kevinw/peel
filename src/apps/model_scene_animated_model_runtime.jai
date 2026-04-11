Animated_Model_Instance_Ref :: struct {
    instance_index: u32; // Dynamic scene instance driven by this animated node.
    node_index: s32; // Scene-geo node sampled for this instance.
    mesh_index: u32; // Mesh rendered by this instance.
}

Animated_Model_Attachment_Instance_Ref :: struct {
    instance_index: u32; // Dynamic scene instance driven by this attachment.
    geo_node_index: s32; // Attachment model node rendered by this instance.
    attachment_node_index: s32; // Player/body node used as the attachment anchor.
    _pad0: s32; // Padding for alignment.
    attachment_offset: Matrix4; // Local offset from the anchor node into attachment space.
}

Animated_Model_Runtime :: struct {
    model_index: s32 = -1; // Scene model driven by this runtime.
    root: Matrix4 = Matrix4_Identity; // World transform applied to the sampled pose.
    scale: float = 1.0; // Uniform render scale for the model.
    ground_y: float = 0.5; // Grounded visual Y offset for the model root.
    spawn_position: Vector3; // Reset/spawn position for the controller.
    spawn_visual_yaw_offset: float = PI; // Yaw offset between controller and model facing.
    anim_tree: Scene_Anim_Blend_Tree; // Imperative blend graph driving the pose.
    idle_clip_index: s32 = -1; // Resolved idle clip for the model.
    walk_clip_index: s32 = -1; // Resolved walk clip for the model.
    jump_clip_index: s32 = -1; // Resolved jump clip for the model.
    idle_player_index: s32 = -1; // Blend-tree leaf player sampling the idle clip.
    walk_player_index: s32 = -1; // Blend-tree leaf player sampling the walk clip.
    jump_player_index: s32 = -1; // Blend-tree leaf player sampling the jump clip.
    locomotion_node_index: s32 = -1; // Blend node mixing idle and walk.
    output_node_index: s32 = -1; // Final blend node mixing locomotion and jump.
    move_alpha: float; // Smoothed idle-to-walk blend factor.
    airborne_alpha: float; // Smoothed grounded-to-airborne blend factor.
    compiled_root_node_index: s32 = -1; // Root scene node that spawned this runtime.
    instances: [..]Animated_Model_Instance_Ref; // Scene instance refs driven by sampled node transforms.
    attachment_instances: [..]Animated_Model_Attachment_Instance_Ref; // Attachment instance refs driven from attachment nodes.
}

// Reset model-specific refs and scalar state while keeping owned storage alive.
animated_model_runtime_reset :: (using runtime: *Animated_Model_Runtime) {
    instances.allocator = context.allocator;
    attachment_instances.allocator = context.allocator;
    array_reset(*instances);
    array_reset(*attachment_instances);
    runtime.* = {};
}

// Free all owned arrays and animation graph state.
animated_model_runtime_deinit :: (using runtime: *Animated_Model_Runtime) {
    deinit(*anim_tree);
    array_free(instances);
    array_free(attachment_instances);
    runtime.* = .{};
}

// Build a simple idle/walk/jump locomotion graph for one animated model.
animated_model_runtime_init_locomotion_graph :: (runtime: *Animated_Model_Runtime, geo: *Scene_Geo, model_index: s32, idle_clip_index: s32, walk_clip_index: s32, jump_clip_index: s32) {
    runtime.model_index = model_index;
    runtime.idle_clip_index = idle_clip_index;
    runtime.walk_clip_index = walk_clip_index;
    runtime.jump_clip_index = jump_clip_index;
    init(*runtime.anim_tree, geo, model_index);
    idle_player_index, idle_node_index := add_clip_node(*runtime.anim_tree, geo, runtime.idle_clip_index, rate = 0.8);
    runtime.idle_player_index = idle_player_index;
    walk_player_index, walk_node_index := add_clip_node(*runtime.anim_tree, geo, runtime.walk_clip_index, rate = 1.0);
    runtime.walk_player_index = walk_player_index;
    jump_player_index, jump_node_index := add_clip_node(*runtime.anim_tree, geo, runtime.jump_clip_index, rate = 1.5);
    runtime.jump_player_index = jump_player_index;
    runtime.locomotion_node_index = add_lerp_node(*runtime.anim_tree, geo, idle_node_index, walk_node_index, 0.0);
    runtime.output_node_index = add_lerp_node(*runtime.anim_tree, geo, runtime.locomotion_node_index, jump_node_index, 0.0);
    set_output(*runtime.anim_tree, runtime.output_node_index);
    reset_blend(runtime, geo);
}

// Reset graph weights and playback times back to a grounded idle pose.
reset_blend :: (using runtime: *Animated_Model_Runtime, geo: *Scene_Geo) {
    idle_player := player(*anim_tree, idle_player_index);
    if idle_player idle_player.time = 0.0;
    walk_player := player(*anim_tree, walk_player_index);
    if walk_player walk_player.time = 0.0;
    jump_player := player(*anim_tree, jump_player_index);
    if jump_player jump_player.time = 0.0;
    move_alpha = 0.0;
    airborne_alpha = 0.0;
    locomotion_node := blend_tree_node(*anim_tree, locomotion_node_index);
    if locomotion_node locomotion_node.alpha = move_alpha;
    output_node := blend_tree_node(*anim_tree, output_node_index);
    if output_node output_node.alpha = airborne_alpha;
    sample(*anim_tree, geo);
}

// Update locomotion blend parameters and per-clip playback rates.
animated_model_runtime_update_locomotion :: (using runtime: *Animated_Model_Runtime, move_target: float, airborne_target: float, walk_rate: float, dt: float) {
    move_alpha = approach(move_alpha, clamp(move_target, 0.0, 1.0), dt, speed = 18.0);
    airborne_alpha = approach(airborne_alpha, clamp(airborne_target, 0.0, 1.0), dt, speed = 22.0);

    idle_player := player(*anim_tree, idle_player_index);
    if idle_player idle_player.rate = 0.8;
    walk_player := player(*anim_tree, walk_player_index);
    if walk_player walk_player.rate = walk_rate;
    jump_player := player(*anim_tree, jump_player_index);
    if jump_player jump_player.rate = 1.5;

    locomotion_node := blend_tree_node(*anim_tree, locomotion_node_index);
    if locomotion_node locomotion_node.alpha = move_alpha;
    output_node := blend_tree_node(*anim_tree, output_node_index);
    if output_node output_node.alpha = airborne_alpha;
}

// Advance clip-player clocks before sampling the graph.
animated_model_runtime_advance :: (using runtime: *Animated_Model_Runtime, dt: float) {
    advance(*anim_tree, dt);
}

// Evaluate the blend graph into its cached output state.
sample :: (using runtime: *Animated_Model_Runtime, geo: *Scene_Geo) {
    sample(*anim_tree, geo);
}

// Return the sampled pose produced by the current output node.
output_state :: (runtime: *Animated_Model_Runtime) -> *Scene_Anim_State {
    return output_state(*runtime.anim_tree);
}

#scope_file

// Smooth a runtime value toward a target using a simple exponential-ish step.
approach :: (current: float, target: float, dt: float, speed: float) -> float {
    t := clamp(dt * speed, 0.0, 1.0);
    return lerp(current, target, t);
}
