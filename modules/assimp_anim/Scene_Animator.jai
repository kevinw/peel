RHS :: true;

Scene_Anim_Node :: struct {
    name: string;
    parent: *Scene_Anim_Node;
    children: [..]*Scene_Anim_Node;

    local_transform: Matrix4; // most recently calculated local transform
    global_transform: Matrix4; // same, but in world space

    channel_index: s32; // index in the current animation's channel array. -1 if not animated.
}

Scene_Animator :: struct {
    scene: *ai.Scene;
    current_anim_index: s32 = -1;
    anim_evaluator: Anim_Evaluator;
    root_node: *Scene_Anim_Node;

    nodes_by_name: Table(*ai.Node, *Scene_Anim_Node);
    bone_nodes_by_name: Table(string, *ai.Node);

    transforms: [..]Matrix4;
}

// Find a node by name in a graph of scene nodes.
find_node :: (node: *Node, name: string) -> *Node {
    if node.mName == name
        return node;

    for children(node) {
        n := find_node(it, name);
        if n != null return n;
    }

    return null;
}

init :: (s: *Scene_Animator, scene: *Scene, anim_index: s32) {
    s.scene = scene;
    s.current_anim_index = -1;

    // build the nodes-for-bones table
    for mesh: meshes(scene) {
        for bone: bones(mesh) {
            node_name := to_string(bone.mName);
            node := find_node(scene.mRootNode, node_name);
            if node
                table_set(*s.bone_nodes_by_name, node_name, node);
        }
    }

    set_anim_index(s, anim_index);
}

deinit :: (using s: *Scene_Animator) {
    deinit(*bone_nodes_by_name);
    array_reset(*transforms);
    deinit(*anim_evaluator);
    deinit(*nodes_by_name);
    if root_node {
        free_node_tree(*root_node);
        root_node = null;
    }
}

set_anim_index :: (using s: *Scene_Animator, anim_index: s32) {
    assert(s != null);

    if anim_index == s.current_anim_index
        return;

    // TODO: free memory from old parallel node tree
    deinit(*anim_evaluator);
    table_reset(*nodes_by_name);

    current_anim_index = anim_index;

    // create the internal node tree. Do this even in case of invalid animation index
    // so that the transformation matrices are properly set up to mimic the current scene
    if s.root_node free_node_tree(*s.root_node);

    s.root_node = create_node_tree(s, s.scene.mRootNode, null);

    // invalid anim index
    if current_anim_index >= scene.mNumAnimations.(s32)
        return;

    // create an evaluator for this animation
    init(*anim_evaluator, scene.mAnimations[current_anim_index]);
}

calculate :: (using s: *Scene_Animator, time: float64) {
    evaluate(*anim_evaluator, time);
    update_transforms(s, root_node, anim_evaluator.transforms);
}

get_local_transform :: (using s: *Scene_Animator, node: *Scene_Anim_Node) -> Matrix4 {
    found, internal_node := table_find(*nodes_by_name, node);
    if !found return Matrix4_identity;
    return internal_node.local_transform;
}

get_global_transform :: (using s: *Scene_Animator, node: *Node) -> Matrix4 {
    found, internal_node := table_find(*nodes_by_name, node);
    if !found {
        log_error("Failed to find node %", to_string(node.mName));
        return Matrix4_Identity;
    }

    return internal_node.global_transform;
}

get_bone_matrices :: (using s: *Scene_Animator, node: *Node, p_mesh_index: int = 0) -> []Matrix4 {
    assert(p_mesh_index < node.mNumMeshes);
    mesh_index := node.mMeshes[p_mesh_index];

    assert(mesh_index < scene.mNumMeshes);
    mesh := scene.mMeshes[mesh_index];

    array_resize(*transforms, mesh.mNumBones);

    // calculate the mesh's inverse global transform
    inverse_ok, global_inverse_mesh_transform := inverse(get_global_transform(s, node));
    if !inverse_ok log_error("Failed to invert global transform for node %", to_string(node.mName));

    // Bone matrices transform from mesh coordinates in bind pose to mesh coordinates in skinned pose
    // Therefore the formula is offsetMatrix * currentGlobalTransform * inverseCurrentMeshTransform
    for bone: bones(mesh) {
        found, bone_node := table_find(*bone_nodes_by_name, to_string(bone.mName));
        if !found {
            log_error("Failed to find bone node %", to_string(bone.mName));
            continue;
        }

        current_global_transform := get_global_transform(s, bone_node);
        #if RHS
            transforms[it_index] = global_inverse_mesh_transform * current_global_transform * cast,force(Matrix4)bone.mOffsetMatrix;
        else
            transforms[it_index] = cast,force(Matrix4)bone.mOffsetMatrix * current_global_transform * global_inverse_mesh_transform;
    }

    return transforms;
}

calculate_global_transform :: (internal_node: *Scene_Anim_Node) {
    // concatenate all parent transforms to get the global transform for this node
    internal_node.global_transform = internal_node.local_transform;
    node := internal_node.parent;
    while node {
        #if RHS {
            internal_node.global_transform = node.local_transform * internal_node.global_transform;
        } else {
            internal_node.global_transform = internal_node.global_transform * node.local_transform;
        }
        node = node.parent;
    }
}

// Recursively updates the internal
update_transforms :: (s: *Scene_Animator, node: *Scene_Anim_Node, transforms: []Matrix4) {
    // update node local transforms
    if node.channel_index != -1
        node.local_transform = transforms[node.channel_index];

    // update global transform as well
    calculate_global_transform(node);

    // continue for all children
    for child: node.children
        update_transforms(s, child, transforms);
}

#scope_file


create_node_tree :: (using s: *Scene_Animator, node: *ai.Node, parent: *Scene_Anim_Node) -> *Scene_Anim_Node {
    internal_node := New(Scene_Anim_Node);
    internal_node.name = to_string(node.mName);
    internal_node.parent = parent;
    table_set(*nodes_by_name, node, internal_node);

    // copy its transformation
    internal_node.local_transform = cast,force(Matrix4)node.mTransformation;
    calculate_global_transform(internal_node);

    // find the index of the animation track affecting this node, if any
    if current_anim_index < scene.mNumAnimations.(s32) {
        internal_node.channel_index = -1;
        current_anim := scene.mAnimations[current_anim_index];
        for channel: channels(current_anim) {
            if channel.mNodeName == internal_node.name {
                internal_node.channel_index = it_index.(s32);
                break;
            }
        }
    }

    // continue for all child nodes and assign the created internal nodes as our children
    for child: children(node) {
        child_node := create_node_tree(s, child, internal_node);
        array_add(*internal_node.children, child_node);
    }

    return internal_node;
}

free_node_tree :: (node: **Scene_Anim_Node) {
    n := node.*;
    for * child: n.children
        free_node_tree(child);
    array_reset(*n.children);
    free(n);
    node.* = null;
}

#import "Hash_Table";
#import "Pool";
