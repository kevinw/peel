//
// This file was auto-generated using the following command:
//
// jai /Users/kev/src/peel/tools/blender_exporter/generate.jai
//



PeelObjectInfo :: struct {
    name:         *u8;
    type:         s32;
    parent_index: s32;
    world:        [16] float;
}

PeelSceneObjectCountFn :: #type (context_ptr: *void) -> s32 #c_call;
PeelSceneObjectsFillFn :: #type (context_ptr: *void, out_objects: *PeelObjectInfo, max_objects: s32) -> s32 #c_call;

PeelBridgeAPI :: struct {
    scene_object_count: PeelSceneObjectCountFn;
    scene_objects_fill: PeelSceneObjectsFillFn;
}

#scope_file

