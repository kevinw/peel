Meshlet_Grid_Instance :: struct {
    world: Matrix4;
}

Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Scene_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
}

Meshlet_Grid_Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
    max_meshlet_count: u32;
}

Meshlet_Grid_Debug_Mode :: enum u32 {
    SHADED;
    LODS;
    MESHLETS;
}


Meshlet_Grid_Params :: struct {
    camera_vp: Matrix4;
    frustum_planes: [6]Vector4;
    eye_position: Vector3;
    debug_mode: u32;
    light_dir: Vector3;
    base_color_factor: Vector4;
    batch_mesh_index: u32;
    base_color_texture_index: u32;
    opacity_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    alpha_mode: u32;
    alpha_cutoff: float;
    sampler_index: u32;
    batch_first_instance: u32;
    batch_instance_count: u32;
    batch_max_meshlet_count: u32;
    batch_meshlet_chunk_count: u32;
    batch_object_group_start: u32;
    debug_flags: u32;
}

MESHLET_LIZARD_MODEL_PATH :: "models/nerdy+lizard+3d+model.glb";
MESHLET_LIZARD_INSTANCE_COUNT :: 240;
MESHLET_LIZARD_GRID_COLS :: 15;
MESHLET_LIZARD_GRID_ROWS :: 15;
MESHLET_TASK_EMIT_MESHLET_COUNT : u32 : 64;
MESHLET_LIZARD_MAX_MESH_GROUPS_PER_DRAW : u32 : 1024;

using app: struct {
    pipeline: Gpu_Pipeline;
    depth_texture: Gpu_Texture;
    depth_view: Gpu_Texture_View;
    depth_w: u32;
    depth_h: u32;
    geo: Scene_Geo;
    arena: Gpu_Arena;
    params: Gpu_Frame_Param_Allocator(Meshlet_Grid_Params);
    vertices: Gpu_View(Scene_Vertex);
    materials: Gpu_View(Scene_Material);
    meshes: Gpu_View(Scene_Mesh);
    meshlet_meshes: Gpu_View(Scene_Meshlet_Mesh);
    meshlets: Gpu_View(Scene_Meshlet);
    meshlet_vertices: Gpu_View(u32);
    meshlet_triangles: Gpu_View(u32);
    meshlet_bounds: Gpu_View(Vector4);
    instances: Gpu_View(Meshlet_Grid_Instance);
    selected_lods: Gpu_View(u32);
    target_lods: Gpu_View(u32);
    lod_transition_alphas: Gpu_View(float);
    batches: [..]Meshlet_Grid_Draw_Batch;
    model_index: s32 = -1;
    camera: Editor_Camera = {
        position = .{0.0, 8.0, 24.0},
        yaw = 0.0,
        pitch = -0.32,
        move_speed = 18.0,
        boost_multiplier = 2.5,
        mouse_sensitivity = 0.0048,
        move_planar = false,
        pitch_min = -1.45,
        pitch_max = 1.45,
    };
    auto_orbit: bool;
    orbit_time: float;
    scene_center: Vector3;
    scene_radius: float = 24.0;
    lod_screen_radius: float = 420.0;
    lod_distance_power: float = 1.18;
    mesh_source: string;
    mesh_grid_limit: u32;
    param_slot_count: s64 = 1;
    using draw: Meshlet_Grid_Params = {
        debug_mode = cast(u32) Meshlet_Grid_Debug_Mode.SHADED,
        debug_flags = 0,
    };
}

on_dll_init :: () {
    assert(OS == .MACOS, "meshlet_lizard_grid is currently Metal mesh-shader only.");

    init_meshlet_lizard_pipeline();
    model_paths := string.[MESHLET_LIZARD_MODEL_PATH];
    scene_geo_init(*geo, model_paths);
    model_index = 0;
    assert(geo.meshlet_meshes.cpu.count == geo.meshes.count,
        "scene_geo meshlet metadata count mismatch.");
    assert(geo.max_meshlet_count > 0, "scene_geo meshlet generation produced no meshlets.");

    rebuild_meshlet_lizard_scene();
    gpu_commit_residency();
} @on_dll_init


tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;

    ensure_depth_target(cast(u32) win_w, cast(u32) win_h);

    allow_look := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    _ = editor_camera_update(*camera, editor_dt, mx, my, mouse_ok,
        allow_move = true,
        allow_look = allow_look,
        allow_zoom = true);

    if auto_orbit {
        orbit_time += editor_dt;
        orbit_radius := scene_radius * 1.25;
        camera.position = scene_center + .{
            sin(orbit_time * 0.23) * orbit_radius,
            scene_radius * 0.55,
            cos(orbit_time * 0.23) * orbit_radius,
        };
        editor_camera_set_look_at(*camera, scene_center);
    }

    aspect := cast(float) win_w / max(cast(float) win_h, 1.0);
    view := editor_camera_make_view(*camera);
    proj := editor_camera_make_projection(*camera, aspect, 0.05, 300.0);
    draw.camera_vp = proj * view;
    draw.frustum_planes = extract_frustum_planes(draw.camera_vp);
    draw.eye_position = camera.position;
    draw.light_dir = normalize(Vector3.{-0.45, -1.0, -0.25});
    base_params := draw;
    update_selected_lods(cast(float) win_h);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = depth_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{
                depth = 1.0,
                stencil = 0,
            },
        },
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.53, 0.67, 0.86, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, pipeline);

    meshlet_draw_bindings := Gpu_Ptr.[
        meshes.gpu,
        meshlet_meshes.gpu,
        vertices.gpu,
        materials.gpu,
        meshlets.gpu,
        meshlet_vertices.gpu,
        meshlet_triangles.gpu,
        meshlet_bounds.gpu,
        instances.gpu,
        selected_lods.gpu,
        target_lods.gpu,
        lod_transition_alphas.gpu,
    ];
    for batches {
        total_task_slots := it.max_meshlet_count;
        draw_first_instance := it.first_instance;
        draw_instance_total := it.instance_count;
        meshlet_chunk_count := max(cast(u32) 1, (total_task_slots + MESHLET_TASK_EMIT_MESHLET_COUNT - 1) / MESHLET_TASK_EMIT_MESHLET_COUNT);
        max_object_groups_per_draw := draw_instance_total * meshlet_chunk_count;
        if mesh_grid_limit != 0 {
            max_object_groups_per_draw = max(cast(u32) 1, mesh_grid_limit / MESHLET_TASK_EMIT_MESHLET_COUNT);
        }

        total_object_groups := draw_instance_total * meshlet_chunk_count;
        object_group_start: u32;
        while object_group_start < total_object_groups {
            draw_object_group_count := min(max_object_groups_per_draw, total_object_groups - object_group_start);

            draw_instance_start := object_group_start / meshlet_chunk_count;
            draw_group_end := object_group_start + draw_object_group_count;
            draw_instance_end := min(draw_instance_total, (draw_group_end + meshlet_chunk_count - 1) / meshlet_chunk_count);
            draw_instance_count := draw_instance_end - draw_instance_start;
            if draw_instance_count > 0 {
                batch_material := materials.cpu[meshes.cpu[it.mesh_index].material_index];
                primary_params := sgpu_frame_param_alloc(*params, base_params);
                primary_params.cpu.base_color_factor = batch_material.base_color_factor;
                primary_params.cpu.batch_mesh_index = it.mesh_index;
                primary_params.cpu.base_color_texture_index = batch_material.base_color_texture_index;
                primary_params.cpu.opacity_texture_index = batch_material.opacity_texture_index;
                primary_params.cpu.normal_texture_index = batch_material.normal_texture_index;
                primary_params.cpu.roughness_texture_index = batch_material.roughness_texture_index;
                primary_params.cpu.ao_texture_index = batch_material.ao_texture_index;
                primary_params.cpu.alpha_mode = batch_material.alpha_mode;
                primary_params.cpu.alpha_cutoff = batch_material.alpha_cutoff;
                primary_params.cpu.sampler_index = batch_material.sampler_index;
                primary_params.cpu.batch_first_instance = draw_first_instance + draw_instance_start;
                primary_params.cpu.batch_instance_count = draw_instance_count;
                primary_params.cpu.batch_max_meshlet_count = it.max_meshlet_count;
                primary_params.cpu.batch_meshlet_chunk_count = meshlet_chunk_count;
                primary_params.cpu.batch_object_group_start = object_group_start - draw_instance_start * meshlet_chunk_count;

                draw_result := gpu_draw_meshlets(cmd_buff, primary_params.gpu, meshlet_draw_bindings, .[draw_object_group_count, 1, 1]);
                assert(draw_result == .SUCCESS, "gpu_draw_meshlets failed: %", draw_result);
            }
            object_group_start += draw_object_group_count;
        }
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

show_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    defer End();
    if !Begin("Meshlet Lizard Grid") return;

    Text("Model: %", MESHLET_LIZARD_MODEL_PATH);
    Text("Batches: %  Instances: %", batches.count, MESHLET_LIZARD_INSTANCE_COUNT);
    Text("Max Meshlets / Mesh: %", geo.max_meshlet_count);
    Text("Mesh Grid Limit: %", mesh_grid_limit);
    Checkbox("Auto Orbit", *auto_orbit);
    debug_mode_value := draw.debug_mode;
    if RadioButton("Shaded", debug_mode_value == cast(u32) Meshlet_Grid_Debug_Mode.SHADED) draw.debug_mode = cast(u32) Meshlet_Grid_Debug_Mode.SHADED;
    SameLine();
    if RadioButton("LODs", debug_mode_value == cast(u32) Meshlet_Grid_Debug_Mode.LODS) draw.debug_mode = cast(u32) Meshlet_Grid_Debug_Mode.LODS;
    SameLine();
    if RadioButton("Meshlets", debug_mode_value == cast(u32) Meshlet_Grid_Debug_Mode.MESHLETS) draw.debug_mode = cast(u32) Meshlet_Grid_Debug_Mode.MESHLETS;
    SliderFloat("LOD Screen Radius", *lod_screen_radius, 8.0, 1024.0);
    SliderFloat("LOD Power", *lod_distance_power, 0.5, 2.0);
    Text("RMB look, WASD move, Shift boost");

    Separator();
    Text("LOD Triangle Counts");
    for *batch, batch_index: batches {
        mesh := geo.meshes[batch.mesh_index];
        Text("Batch %", batch_index);
        for lod_i: 0..cast(s64) mesh.lod_mesh_count {
            lod_mesh_index := ifx lod_i == 0 then batch.mesh_index else mesh.lod_mesh_start + cast(u32) (lod_i - 1);
            lod_mesh := geo.meshes[lod_mesh_index];
            triangles := lod_mesh.index_count / 3;
            Text("  LOD%: % tris", lod_i, triangles);
        }
    }
} @on_ui


#scope_file
init_meshlet_lizard_pipeline :: () {

    shader :: #run get_transpiled_task_mesh_pipeline(.METAL, task_main, mesh_main, fragment_main);
    mesh_source = copy_string(tprint("%\n%", shader.task_source, shader.mesh_source));
    mesh_desc := Gpu_Mesh_Pipeline_Desc.{
        task_shader = cast([]u8) mesh_source,
        mesh_shader = cast([]u8) mesh_source,
        pixel_shader = cast([]u8) shader.pixel_source,
        raster_desc = .{
            cull = .CW,
            depth_format = .D32_SFLOAT,
            color_targets = .[
                .{format = .B8G8R8A8_UNORM},
            ],
        },
        task_threads = .[1, 1, 1],
        mesh_threads = .[1, 1, 1],
        payload_memory_length = cast(u32) shader.payload_memory_length,
        max_total_threadgroups_per_mesh_grid = MESHLET_LIZARD_MAX_MESH_GROUPS_PER_DRAW,
    };
    pipeline = gpu_create_mesh_pipeline(mesh_desc);
    assert(pipeline != 0, "Failed to create meshlet lizard mesh pipeline.");
    mesh_grid_limit = gpu_get_mesh_pipeline_max_total_threadgroups_per_grid(pipeline);
    if mesh_grid_limit == 0 mesh_grid_limit = MESHLET_LIZARD_MAX_MESH_GROUPS_PER_DRAW;
    log("meshlet_lizard mesh grid limit=%", mesh_grid_limit);
}

rebuild_meshlet_lizard_scene :: () {
    array_reset(*batches);
    if arena.cpu != null {
        gpu_free_arena(arena);
        arena = .{};
    }

    scene_center = .{0.0, 0.0, 0.0};

    model := geo.models[model_index];
    model_bounds := scene_geo_model_bounds(*geo, model_index);
    model_extent := model_bounds.max - model_bounds.min;
    model_center := (model_bounds.min + model_bounds.max) * 0.5;
    spacing := max(max(model_extent.x, model_extent.z), 1.0) * 1.5;
    used_cols := min(MESHLET_LIZARD_INSTANCE_COUNT, cast(u32) MESHLET_LIZARD_GRID_COLS);
    used_rows := (MESHLET_LIZARD_INSTANCE_COUNT + cast(u32) MESHLET_LIZARD_GRID_COLS - 1) / cast(u32) MESHLET_LIZARD_GRID_COLS;
    grid_width := cast(float) max(cast(s32) used_cols - 1, 0) * spacing;
    grid_depth := cast(float) max(cast(s32) used_rows - 1, 0) * spacing;
    scene_min := Vector3.{1.0e30, 1.0e30, 1.0e30};
    scene_max := Vector3.{-1.0e30, -1.0e30, -1.0e30};

    total_instance_count := cast(s64) model_mesh_ref_count(model);
    total_instance_count *= MESHLET_LIZARD_INSTANCE_COUNT;

    limit := ifx mesh_grid_limit != 0 then mesh_grid_limit else MESHLET_LIZARD_MAX_MESH_GROUPS_PER_DRAW;
    param_slot_count = 0;
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            meshlet_chunk_count := cast(s64) ((mesh_max_meshlet_count(mesh_index) + MESHLET_TASK_EMIT_MESHLET_COUNT - 1) / MESHLET_TASK_EMIT_MESHLET_COUNT);
            total_object_groups := max(meshlet_chunk_count, cast(s64) 1) * cast(s64) MESHLET_LIZARD_INSTANCE_COUNT;
            max_object_groups_per_draw := max(cast(s64) 1, cast(s64) limit / cast(s64) MESHLET_TASK_EMIT_MESHLET_COUNT);
            draw_count := (total_object_groups + max_object_groups_per_draw - 1) / max_object_groups_per_draw;
            param_slot_count += max(draw_count, cast(s64) 1) * 2;
        }
    }
    param_slot_count = max(param_slot_count, cast(s64) 1);

    total_bytes :=
        1024 +
        gpu_arena_required_view_size(Meshlet_Grid_Params, param_slot_count * SGPU_FRAMES_IN_FLIGHT) +
        gpu_arena_required_view_size(Scene_Vertex, geo.vertices.cpu.count) +
        gpu_arena_required_view_size(Scene_Material, geo.materials.cpu.count) +
        gpu_arena_required_view_size(Scene_Mesh, geo.meshes.count) +
        gpu_arena_required_view_size(Scene_Meshlet_Mesh, geo.meshlet_meshes.cpu.count) +
        gpu_arena_required_view_size(Scene_Meshlet, geo.meshlets.cpu.count) +
        gpu_arena_required_view_size(u32, geo.meshlet_vertices.cpu.count) +
        gpu_arena_required_view_size(u32, geo.meshlet_triangles.cpu.count) +
        gpu_arena_required_view_size(Vector4, geo.meshlet_bounds.cpu.count) +
        gpu_arena_required_view_size(Meshlet_Grid_Instance, total_instance_count) +
        gpu_arena_required_view_size(u32, total_instance_count) +
        gpu_arena_required_view_size(u32, total_instance_count) +
        gpu_arena_required_view_size(float, total_instance_count);

    arena = gpu_make_arena(total_bytes, label = "meshlet lizard arena");
    assert(arena.cpu != null, "Failed to allocate meshlet lizard arena.");

    params = sgpu_make_frame_param_allocator(*arena, Meshlet_Grid_Params, param_slot_count);
    vertices = gpu_alloc_view(*arena, Scene_Vertex, geo.vertices.cpu.count);
    materials = gpu_alloc_view(*arena, Scene_Material, geo.materials.cpu.count);
    meshes = gpu_alloc_view(*arena, Scene_Mesh, geo.meshes.count);
    meshlet_meshes = gpu_alloc_view(*arena, Scene_Meshlet_Mesh, geo.meshlet_meshes.cpu.count);
    meshlets = gpu_alloc_view(*arena, Scene_Meshlet, geo.meshlets.cpu.count);
    meshlet_vertices = gpu_alloc_view(*arena, u32, geo.meshlet_vertices.cpu.count);
    meshlet_triangles = gpu_alloc_view(*arena, u32, geo.meshlet_triangles.cpu.count);
    meshlet_bounds = gpu_alloc_view(*arena, Vector4, geo.meshlet_bounds.cpu.count);
    instances = gpu_alloc_view(*arena, Meshlet_Grid_Instance, total_instance_count);
    selected_lods = gpu_alloc_view(*arena, u32, total_instance_count);
    target_lods = gpu_alloc_view(*arena, u32, total_instance_count);
    lod_transition_alphas = gpu_alloc_view(*arena, float, total_instance_count);

    memcpy(vertices.cpu.data, geo.vertices.cpu.data, geo.vertices.cpu.count * size_of(Scene_Vertex));
    memcpy(materials.cpu.data, geo.materials.cpu.data, geo.materials.cpu.count * size_of(Scene_Material));
    memcpy(meshes.cpu.data, geo.meshes.data, geo.meshes.count * size_of(Scene_Mesh));
    memcpy(meshlet_meshes.cpu.data, geo.meshlet_meshes.cpu.data, geo.meshlet_meshes.cpu.count * size_of(Scene_Meshlet_Mesh));
    memcpy(meshlets.cpu.data, geo.meshlets.cpu.data, geo.meshlets.cpu.count * size_of(Scene_Meshlet));
    memcpy(meshlet_vertices.cpu.data, geo.meshlet_vertices.cpu.data, geo.meshlet_vertices.cpu.count * size_of(u32));
    memcpy(meshlet_triangles.cpu.data, geo.meshlet_triangles.cpu.data, geo.meshlet_triangles.cpu.count * size_of(u32));
    memcpy(meshlet_bounds.cpu.data, geo.meshlet_bounds.cpu.data, geo.meshlet_bounds.cpu.count * size_of(Vector4));
    for i: 0..total_instance_count-1 {
        selected_lods.cpu[i] = 0;
        target_lods.cpu[i] = 0;
        lod_transition_alphas.cpu[i] = 0.0;
    }

    instance_cursor: u32;
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            meshlet_mesh := geo.meshlet_meshes.cpu[mesh_index];
            mesh_local_center := meshlet_mesh.bounds_center_radius.xyz;
            mesh_local_radius := max(meshlet_mesh.bounds_center_radius.w, 0.001);
            batch := array_add(*batches);
            batch.mesh_index = mesh_index;
            batch.first_instance = instance_cursor;
            batch.instance_count = MESHLET_LIZARD_INSTANCE_COUNT;
            batch.max_meshlet_count = mesh_max_meshlet_count(mesh_index);

            for grid_index: 0..MESHLET_LIZARD_INSTANCE_COUNT-1 {
                col := cast(float) (grid_index % MESHLET_LIZARD_GRID_COLS);
                row := cast(float) (grid_index / MESHLET_LIZARD_GRID_COLS);
                tx := col * spacing - grid_width * 0.5;
                tz := row * spacing - grid_depth * 0.5;
                root := make_translation_matrix4(.{tx, -model_center.y, tz});
                world := root * node.world;
                instances.cpu[instance_cursor] = .{ world = world };
                world_center4 := world * Vector4.{mesh_local_center.x, mesh_local_center.y, mesh_local_center.z, 1.0};
                world_center := Vector3.{world_center4.x, world_center4.y, world_center4.z};
                mesh_radius3 := Vector3.{mesh_local_radius, mesh_local_radius, mesh_local_radius};
                scene_min = min(scene_min, world_center - mesh_radius3);
                scene_max = max(scene_max, world_center + mesh_radius3);
                instance_cursor += 1;
            }
        }
    }

    scene_center = (scene_min + scene_max) * 0.5;
    scene_extent := scene_max - scene_min;
    scene_radius = max(max(scene_extent.x, scene_extent.z) * 0.6, spacing * 0.75);
    camera_height := max(scene_extent.y, 1.0) * 0.65;
    camera.position = scene_center + .{0.0, camera_height, scene_radius * 0.55};
    editor_camera_set_look_at(*camera, scene_center);

    if batches.count > 0 {
        mesh := geo.meshes[batches[0].mesh_index];
        log("meshlet_lizard batch0 base_mesh=% meshlets=% lod_meshes=%", batches[0].mesh_index, geo.meshlet_meshes.cpu[batches[0].mesh_index].meshlet_count, mesh.lod_mesh_count);
        for lod_offset: 0..mesh.lod_mesh_count-1 {
            lod_mesh_index := mesh.lod_mesh_start + lod_offset;
            log("meshlet_lizard batch0 lod% mesh=% meshlets=% tris=%", lod_offset + 1, lod_mesh_index, geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count, geo.meshes[lod_mesh_index].index_count / 3);
        }
    }
}

mesh_max_meshlet_count :: (mesh_index: u32) -> u32 {
    mesh := geo.meshes[mesh_index];
    result := geo.meshlet_meshes.cpu[mesh_index].meshlet_count;
    for lod_offset: 0..mesh.lod_mesh_count-1 {
        lod_mesh_index := mesh.lod_mesh_start + lod_offset;
        result = max(result, geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count);
    }
    return max(result, 1);
}

model_mesh_ref_count :: (model: Scene_Model) -> s64 {
    total: s64;
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        total += geo.nodes[node_index].mesh_ref_count;
    }
    return total;
}

mesh_world_max_scale :: (world: Matrix4) -> float {
    axis_x4 := world * Vector4.{1.0, 0.0, 0.0, 0.0};
    axis_y4 := world * Vector4.{0.0, 1.0, 0.0, 0.0};
    axis_z4 := world * Vector4.{0.0, 0.0, 1.0, 0.0};
    axis_x := Vector3.{axis_x4.x, axis_x4.y, axis_x4.z};
    axis_y := Vector3.{axis_y4.x, axis_y4.y, axis_y4.z};
    axis_z := Vector3.{axis_z4.x, axis_z4.y, axis_z4.z};
    return max(length(axis_x), max(length(axis_y), length(axis_z)));
}

lod_metric_for_instance :: (base_mesh_index: u32, world: Matrix4, viewport_height: float) -> float {
    meshlet_mesh := geo.meshlet_meshes.cpu[base_mesh_index];
    local_center := meshlet_mesh.bounds_center_radius.xyz;
    local_radius := max(meshlet_mesh.bounds_center_radius.w, 0.001);
    world_center4 := world * Vector4.{local_center.x, local_center.y, local_center.z, 1.0};
    world_center := Vector3.{world_center4.x, world_center4.y, world_center4.z};
    world_radius := max(local_radius * mesh_world_max_scale(world), 0.001);
    distance_to_eye := max(distance(camera.position, world_center), 0.001);
    tan_half_fov := max(tan(camera.fov_y * 0.5), 0.0001);
    projected_radius_px := world_radius * viewport_height / max(2.0 * distance_to_eye * tan_half_fov, 0.0001);
    return pow(lod_screen_radius / max(projected_radius_px, 0.0001), lod_distance_power);
}

lod_slot_for_metric :: (metric: float, max_lod: u32) -> u32 {
    lod_slot: u32;
    while lod_slot < max_lod {
        threshold := cast(float) (lod_slot + 1);
        if metric < threshold break;
        lod_slot += 1;
    }
    return lod_slot;
}

update_selected_lods :: (viewport_height: float) {
    for batches {
        max_lod := meshes.cpu[it.mesh_index].lod_mesh_count;
        for instance_offset: 0..it.instance_count-1 {
            instance_index := it.first_instance + instance_offset;
            metric := lod_metric_for_instance(it.mesh_index, instances.cpu[instance_index].world, viewport_height);
            selected_lod := lod_slot_for_metric(metric, max_lod);
            selected_lods.cpu[instance_index] = selected_lod;
            target_lods.cpu[instance_index] = selected_lod;
            lod_transition_alphas.cpu[instance_index] = 0.0;
        }
    }
}

normalize_plane4 :: (plane: Vector4) -> Vector4 {
    len := length(plane.xyz);
    if len <= 0.000001 return plane;
    inv_len := 1.0 / len;
    return plane * inv_len;
}

extract_frustum_planes :: (m: Matrix4) -> [6]Vector4 {
    row0 := m.v[0];
    row1 := m.v[1];
    row2 := m.v[2];
    row3 := m.v[3];
    return .[
        normalize_plane4(row3 + row0),
        normalize_plane4(row3 - row0),
        normalize_plane4(row3 + row1),
        normalize_plane4(row3 - row1),
        normalize_plane4(row3 + row2),
        normalize_plane4(row3 - row2),
    ];
}

ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if depth_view != 0 && depth_w == width && depth_h == height return;

    if depth_texture != 0 gpu_free(depth_texture);
    depth_texture = 0;
    depth_view = 0;

    res, depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS, "Depth texture creation failed: %", res);
    depth_view = gpu_texture_view(depth_texture);
    assert(depth_view != 0, "Depth view creation failed.");
    depth_w = width;
    depth_h = height;
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../scene_geo.jai";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "String";
#import "Math";
using,only(try_parse_env_int) _ :: #import "Env_Vars";
#load "shaders/meshlet_shader.jai";
