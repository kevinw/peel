#import "Math";

MESHLET_MAX_VERTICES :: 64;
MESHLET_MAX_TRIANGLES :: 124;
TASK_EMIT_MESHLET_COUNT : u32 : 64;

Meshlet_Grid_Debug_Mode :: enum u32 {
    SHADED;
    ALBEDO;
    LODS;
    CHUNKS;
    MESHLETS;
}

Task_Payload :: struct {
    instance_index: u32;
    mesh_index: u32;
    meshlet_start: u32;
    meshlet_count: u32;
    chunk_index: u32;
}

meshlet_hash01 :: (x: u32) -> float {
    phase := cast(float) x * cast(float) 12.9898 + cast(float) 78.233;
    return fract(sin(phase) * cast(float) 43758.5453);
}

meshlet_hue2rgb :: (hue: float) -> Vector3 {
    h := fract(hue);
    return clamp(Vector3.{
        abs(h * 6.0 - 3.0) - 1.0,
        2.0 - abs(h * 6.0 - 2.0),
        2.0 - abs(h * 6.0 - 4.0),
    }, 0.0, 1.0);
}

meshlet_lod_debug_color :: (lod: u32) -> Vector3 {
    if lod == {
    case 0; return .{0.13, 0.47, 0.71};
    case 1; return .{0.90, 0.62, 0.00};
    case 2; return .{0.80, 0.47, 0.65};
    case 3; return .{0.84, 0.15, 0.16};
    }
    return .{0.55, 0.55, 0.55};
}

meshlet_lod_from_mesh_index :: (meshes: *Scene_Mesh, base_mesh_index: u32, selected_mesh_index: u32) -> u32 {
    if selected_mesh_index == base_mesh_index return 0;
    return 1 + (selected_mesh_index - meshes[base_mesh_index].lod_mesh_start);
}

meshlet_sphere_visible :: (params: *$T, center: Vector3, radius: float) -> bool {
    for plane: params.frustum_planes {
        distance := dot(plane.xyz, center) + plane.w;
        if distance < -radius return false;
    }
    return true;
}

meshlet_world_max_scale :: (world: Matrix4) -> float {
    axis_x4 := world * Vector4.{1.0, 0.0, 0.0, 0.0};
    axis_y4 := world * Vector4.{0.0, 1.0, 0.0, 0.0};
    axis_z4 := world * Vector4.{0.0, 0.0, 1.0, 0.0};
    return max(length(axis_x4.xyz), max(length(axis_y4.xyz), length(axis_z4.xyz)));
}

meshlet_lod_metric_for_instance :: (
    params: *$T,
    meshlet_meshes: *Scene_Meshlet_Mesh,
    base_mesh_index: u32,
    world: Matrix4,
) -> float {
    meshlet_mesh := meshlet_meshes[base_mesh_index];
    local_center := meshlet_mesh.bounds_center_radius.xyz;
    local_radius := max(meshlet_mesh.bounds_center_radius.w, 0.001);
    world_center4 := world * Vector4.{local_center.x, local_center.y, local_center.z, 1.0};
    world_center := world_center4.xyz;
    world_radius := max(local_radius * meshlet_world_max_scale(world), 0.001);
    distance_to_eye := max(distance(params.eye_position, world_center), 0.001);
    projected_radius_px := world_radius * params.lod_projection_scale / distance_to_eye;
    return pow(params.lod_radius_threshold / max(projected_radius_px, 0.0001), params.lod_metric_power);
}

meshlet_lod_slot_for_metric :: (metric: float, max_lod: u32) -> u32 {
    lod_slot: u32;
    while lod_slot < max_lod {
        threshold := cast(float) (lod_slot + 1);
        if metric < threshold break;
        lod_slot += 1;
    }
    return lod_slot;
}
