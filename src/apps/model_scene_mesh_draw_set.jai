Mesh_Draw_Set_Mesh :: struct {
    node_index: s32;
    base_mesh_index: u32;
}

Mesh_Draw_Set_Group :: struct {
    render_mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Mesh_Draw_Set :: struct {
    allocator: Allocator;
    render_meshes: [..]Mesh_Draw_Set_Mesh;
    groups: [..]Mesh_Draw_Set_Group;
    meshlet_instances: Gpu_Frame_View(Model_Scene_Meshlet_Instance);
}

Mesh_Draw_Set_Params :: struct {
    camera_vp: Matrix4;
    frustum_planes: [6]Vector4;
    eye_position: Vector3;
    lod_projection_scale: float;
    lod_radius_threshold: float;
    lod_metric_power: float;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    shadow_view_proj: Matrix4;
    shadow_meta: Vector4;
}

clear :: (using set: *Mesh_Draw_Set) {
    gpu_delete(*meshlet_instances);
    array_reset(*render_meshes);
    array_reset(*groups);
}

deinit :: (using set: *Mesh_Draw_Set) {
    gpu_delete(*meshlet_instances);
    array_free(render_meshes);
    array_free(groups);
    set.* = {};
}

append_model_meshes :: (set: *Mesh_Draw_Set, scene_geo: *Scene_Geo, model_index: s32) {
    if model_index < 0 return;
    model := scene_geo.models[model_index];
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := scene_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            array_add(*set.render_meshes, .{
                node_index = cast(s32) node_index,
                base_mesh_index = mesh_index,
            });
        }
    }
}

init_groups :: (using set: *Mesh_Draw_Set) {
    array_reset(*groups);
    for render_meshes {
        array_add(*groups, .{
            render_mesh_index = cast(u32) it_index,
        });
    }
}

allocate_dynamic_instances :: (using set: *Mesh_Draw_Set, arena: *Gpu_Arena, max_instance_count: s64) {
    meshlet_instances = sgpu_make_frame_view(arena, Model_Scene_Meshlet_Instance, max(cast(s64) 1, max_instance_count));
}

begin_frame :: (using set: *Mesh_Draw_Set) {
    for *groups {
        it.first_instance = 0;
        it.instance_count = 0;
    }
}

group_index :: (set: *Mesh_Draw_Set, render_mesh_index: s64) -> s32 {
    for group, idx: set.groups {
        if cast(s64) group.render_mesh_index == render_mesh_index return cast(s32) idx;
    }
    return -1;
}

assign_counts :: (using set: *Mesh_Draw_Set, counts: []u32) {
    assert(counts.count == groups.count, "Mesh_Draw_Set counts mismatch: % vs %.", counts.count, groups.count);
    running_first_instance: u32;
    for *groups {
        it.first_instance = running_first_instance;
        it.instance_count = counts[it_index];
        running_first_instance += it.instance_count;
    }
}

current_instances :: (set: *Mesh_Draw_Set) -> Gpu_View(Model_Scene_Meshlet_Instance) {
    return sgpu_frame_view_slot(*set.meshlet_instances);
}

max_meshlet_count :: (scene_geo: *Scene_Geo, mesh_index: u32) -> u32 {
    result := scene_geo.meshlet_meshes.cpu[mesh_index].meshlet_count;
    mesh := scene_geo.meshes[mesh_index];
    if mesh.lod_mesh_count > 0 {
        for lod_offset: 0..mesh.lod_mesh_count-1 {
            lod_mesh_index := mesh.lod_mesh_start + lod_offset;
            result = max(result, scene_geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count);
        }
    }
    return result;
}

draw_meshlets :: (
    set: *Mesh_Draw_Set,
    cmd_buff: Gpu_Command_Buffer,
    pass_desc: Gpu_Render_Pass_Desc,
    scene_geo: *Scene_Geo,
    params: Mesh_Draw_Set_Params,
    shadow_pass := false,
) {
    current_meshlet_instances := current_instances(set);
    if current_meshlet_instances.gpu == 0 return;

    meshlet_flags := Model_Scene_Meshlet_Flags.HAS_LODS;
    if !shadow_pass && params.shadow_meta.z < 1.5 meshlet_flags |= .HAS_SHADOWS;

    mesh_constants := Model_Scene_Meshlet_Constants.{
        flags = meshlet_flags,
        debug_mode = ifx shadow_pass then .SHADED else mesh_shader_constants.debug_mode,
    };
    if shadow_pass {
        gpu_set_pipeline(cmd_buff, SHR.pipeline(*mesh_shadow_shader, pass_desc, mesh_constants));
    } else {
        gpu_set_pipeline(cmd_buff, SHR.pipeline(*mesh_shader, pass_desc, mesh_constants));
    }

    for group: set.groups {
        if group.instance_count == 0 continue;
        render_mesh := set.render_meshes[group.render_mesh_index];
        base_mesh := scene_geo.meshes[render_mesh.base_mesh_index];
        total_task_slots := max_meshlet_count(scene_geo, render_mesh.base_mesh_index);
        if total_task_slots == 0 continue;
        meshlet_chunk_count := max(cast(u32) 1, (total_task_slots + TASK_EMIT_MESHLET_COUNT - 1) / TASK_EMIT_MESHLET_COUNT);
        max_object_groups_per_draw := max(cast(u32) 1, mesh_grid_limit / TASK_EMIT_MESHLET_COUNT);
        total_object_groups := group.instance_count * meshlet_chunk_count;
        material := scene_geo.materials.cpu[base_mesh.material_index];
        object_group_start: u32;
        while object_group_start < total_object_groups {
            draw_object_group_count := min(max_object_groups_per_draw, total_object_groups - object_group_start);
            draw_instance_start := object_group_start / meshlet_chunk_count;
            draw_group_end := object_group_start + draw_object_group_count;
            draw_instance_end := min(group.instance_count, (draw_group_end + meshlet_chunk_count - 1) / meshlet_chunk_count);
            draw_instance_count := draw_instance_end - draw_instance_start;
            if draw_instance_count > 0 {
                draw_params := sgpu_frame_param_alloc(*scene_meshlet_params);
                meshlet_draw_bindings := Gpu_Ptr.[
                    scene_meshes_gpu.gpu,
                    scene_geo.meshlet_meshes.gpu,
                    scene_geo.vertices.gpu,
                    scene_geo.meshlets.gpu,
                    scene_geo.meshlet_vertices.gpu,
                    scene_geo.meshlet_triangles.gpu,
                    scene_geo.meshlet_bounds.gpu,
                    current_meshlet_instances.gpu,
                    0,
                    0,
                    scene_geo.morph_vertex_deltas.gpu,
                    scene_geo.materials.gpu,
                ];
                draw_params.cpu.* = .{
                    camera_vp = params.camera_vp,
                    frustum_planes = params.frustum_planes,
                    eye_position = params.eye_position,
                    lod_projection_scale = params.lod_projection_scale,
                    lod_radius_threshold = params.lod_radius_threshold,
                    lod_metric_power = params.lod_metric_power,
                    batch_mesh_index = render_mesh.base_mesh_index,
                    light_dir = params.light_dir,
                    sun_params = params.sun_params,
                    camera_pos = params.camera_pos,
                    material_index = base_mesh.material_index,
                    shadow_view_proj = params.shadow_view_proj,
                    shadow_meta = params.shadow_meta,
                    batch_first_instance = group.first_instance + draw_instance_start,
                    batch_instance_count = draw_instance_count,
                    batch_max_meshlet_count = total_task_slots,
                    batch_meshlet_chunk_count = meshlet_chunk_count,
                    batch_object_group_start = object_group_start - draw_instance_start * meshlet_chunk_count,
                    mesh_base_vertex = base_mesh.base_vertex,
                    skin_matrix_count = 0,
                    morph_target_count = 0,
                    morph_vertex_count = 0,
                };
                draw_result := gpu_draw_meshlets(cmd_buff, draw_params.gpu, meshlet_draw_bindings, .[draw_object_group_count, 1, 1]);
                assert(draw_result == .SUCCESS, "gpu_draw_meshlets failed: %", draw_result);
            }
            object_group_start += draw_object_group_count;
        }
    }
}
