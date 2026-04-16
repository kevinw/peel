//
// This file was auto-generated using the following command:
//
// jai tools/blender_exporter/generate.jai
//



PEEL_SCENE_FILE_MAGIC :: "PEBLEND2";
PEEL_SCENE_FILE_VERSION :: 3;

PeelSceneFileHeader :: struct {
    magic:               [8] u8;
    version:             u32;
    material_count:      u32;
    mesh_count:          u32;
    node_count:          u32;
    node_mesh_ref_count: u32;
    vertex_count:        u32;
    index_count:         u32;
}

PeelSceneFileMaterial :: struct {
    base_color: [4] float;
    metallic:   float;
    roughness:  float;
}

PeelSceneFileMesh :: struct {
    base_vertex:    u32;
    vertex_count:   u32;
    first_index:    u32;
    index_count:    u32;
    material_index: u32;
}

PeelSceneFileNode :: struct {
    parent_index:       s32;
    first_child_index:  s32;
    next_sibling_index: s32;
    pad_i:              s32;
    first_mesh_ref:     u32;
    mesh_ref_count:     u32;
    pad_u0:             u32;
    pad_u1:             u32;
    translation:        [3] float;
    rotation:           [4] float;
    scale:              [3] float;
}

PeelSceneFileVertex :: struct {
    position: [4] float;
    normal:   [4] float;
    tangent:  [4] float;
    uv:       [2] float;
}

#scope_file

