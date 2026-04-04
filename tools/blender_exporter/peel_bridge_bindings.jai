//
// This file was auto-generated using the following command:
//
// jai /Users/kev/src/peel/tools/blender_exporter/generate.jai
//



PeelExportMaterial :: struct {
    name:       *u8;
    base_color: [4] float;
}

PeelExportMesh :: struct {
    base_vertex:    u32;
    vertex_count:   u32;
    first_index:    u32;
    index_count:    u32;
    material_index: u32;
}

PeelExportNode :: struct {
    name:               *u8;
    parent_index:       s32;
    first_child_index:  s32;
    next_sibling_index: s32;
    first_mesh_ref:     u32;
    mesh_ref_count:     u32;
    translation:        [3] float;
    rotation:           [4] float;
    scale:              [3] float;
}

PeelExportVertex :: struct {
    position: [3] float;
    normal:   [3] float;
    uv:       [2] float;
}

PeelExportSnapshot :: struct {
    model_name:          *u8;
    materials:           *PeelExportMaterial;
    meshes:              *PeelExportMesh;
    nodes:               *PeelExportNode;
    node_mesh_refs:      *u32;
    vertices:            *PeelExportVertex;
    indices:             *u32;
    material_count:      u32;
    mesh_count:          u32;
    node_count:          u32;
    node_mesh_ref_count: u32;
    vertex_count:        u32;
    index_count:         u32;
}

#scope_file

