// Custom hand-written additions to the generated assimp bindings.  This file is loaded by module.jai, so don't load it yourself.

// Convert assimp String to a Jai string.
to_string :: inline (s: String) -> string {
    result: string;
    result.count = s.length;
    result.data = s.data.data;
    return result;
}

operator == :: inline (a: String, b: String) -> bool {
    return to_string(a) == to_string(b);
}

operator == :: inline (a: String, b: string) -> bool {
    return to_string(a) == b;
}

// Some helper procedures to make getting slices from assimp structs easier.

bones :: inline (using mesh: *Mesh)         -> []*Bone        { return .{ mNumBones, mBones }; }
meshes :: inline (using scene: *Scene)      -> []*Mesh        { return .{ mNumMeshes, mMeshes }; }
children :: inline (using node: *Node)      -> []*Node        { return .{ mNumChildren, mChildren }; }
channels :: inline (using anim: *Animation) -> []*NodeAnim    { return .{ mNumChannels, mChannels }; }
animations :: inline (using scene: *Scene)  -> []*Animation   { return .{ mNumAnimations, mAnimations }; }
faces :: inline (using mesh: *Mesh)         -> []Face         { return .{ mNumFaces, mFaces }; }
weights :: inline (using bone: *Bone)       -> []VertexWeight { return .{ mNumWeights, mWeights }; }
mesh_indices :: inline (using node: *Node)  -> []u32          { return .{ mNumMeshes, mMeshes }; }
properties :: inline (using material: *Material) -> []*MaterialProperty { return .{ mNumProperties, mProperties }; }