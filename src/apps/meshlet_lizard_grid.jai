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
    eye_position: Vector3;
    debug_mode: u32;
    light_dir: Vector3;
    batch_mesh_index: u32;
    batch_first_instance: u32;
    batch_instance_count: u32;
    batch_max_meshlet_count: u32;
    lod_distance_scale: float;
    lod_distance_power: float;
    _pad0: Vector2;
}

MESHLET_LIZARD_MODEL_PATH :: "models/nerdy+lizard+3d+model.glb";
MESHLET_LIZARD_INSTANCE_COUNT :: 40;
MESHLET_LIZARD_GRID_COLS :: 10;
MESHLET_LIZARD_GRID_ROWS :: 10;

meshlet_lizard_pipeline: Gpu_Pipeline;
meshlet_lizard_depth_texture: Gpu_Texture;
meshlet_lizard_depth_view: Gpu_Texture_View;
meshlet_lizard_depth_w: u32;
meshlet_lizard_depth_h: u32;
meshlet_lizard_geo: Scene_Geo;
meshlet_lizard_arena: Gpu_Arena;
meshlet_lizard_params: Gpu_View(Meshlet_Grid_Params);
meshlet_lizard_vertices: Gpu_View(Scene_Vertex);
meshlet_lizard_materials: Gpu_View(Scene_Material);
meshlet_lizard_meshes: Gpu_View(Scene_Mesh);
meshlet_lizard_meshlet_meshes: Gpu_View(Scene_Meshlet_Mesh);
meshlet_lizard_meshlets: Gpu_View(Scene_Meshlet);
meshlet_lizard_meshlet_vertices: Gpu_View(u32);
meshlet_lizard_meshlet_triangles: Gpu_View(u32);
meshlet_lizard_meshlet_bounds: Gpu_View(Vector4);
meshlet_lizard_instances: Gpu_View(Meshlet_Grid_Instance);
meshlet_lizard_batches: [..]Meshlet_Grid_Draw_Batch;
meshlet_lizard_model_index: s32 = -1;
meshlet_lizard_debug_mode: Meshlet_Grid_Debug_Mode = .SHADED;
meshlet_lizard_camera: Editor_Camera = .{
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
meshlet_lizard_auto_orbit: bool;
meshlet_lizard_orbit_time: float;
meshlet_lizard_scene_center: Vector3;
meshlet_lizard_scene_radius: float = 24.0;
meshlet_lizard_lod_distance_scale: float = 8.0;
meshlet_lizard_lod_distance_power: float = 1.0;
meshlet_lizard_mesh_source: string;

on_dll_init :: () {
    assert(OS == .MACOS, "meshlet_lizard_grid is currently Metal mesh-shader only.");

    init_meshlet_lizard_pipeline();

    model_paths := string.[MESHLET_LIZARD_MODEL_PATH];
    scene_geo_init(*meshlet_lizard_geo, model_paths);
    meshlet_lizard_model_index = 0;
    assert(meshlet_lizard_geo.meshlet_meshes.cpu.count == meshlet_lizard_geo.meshes.count,
        "scene_geo meshlet metadata count mismatch.");
    assert(meshlet_lizard_geo.max_meshlet_count > 0, "scene_geo meshlet generation produced no meshlets.");

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

    ensure_meshlet_lizard_depth_target(cast(u32) win_w, cast(u32) win_h);

    allow_look := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    _ = editor_camera_update(*meshlet_lizard_camera, editor_dt, mx, my, mouse_ok, allow_move = true, allow_look = allow_look);

    if meshlet_lizard_auto_orbit {
        meshlet_lizard_orbit_time += editor_dt;
        orbit_radius := meshlet_lizard_scene_radius * 1.25;
        meshlet_lizard_camera.position = meshlet_lizard_scene_center + .{
            sin(meshlet_lizard_orbit_time * 0.23) * orbit_radius,
            meshlet_lizard_scene_radius * 0.55,
            cos(meshlet_lizard_orbit_time * 0.23) * orbit_radius,
        };
        editor_camera_set_look_at(*meshlet_lizard_camera, meshlet_lizard_scene_center);
    }

    aspect := cast(float) win_w / max(cast(float) win_h, 1.0);
    view := editor_camera_make_view(*meshlet_lizard_camera);
    proj := make_projection_matrix(PI / 3.2, aspect, 0.05, 300.0);
    meshlet_lizard_params.cpu[0].camera_vp = proj * view;
    meshlet_lizard_params.cpu[0].eye_position = meshlet_lizard_camera.position;
    meshlet_lizard_params.cpu[0].debug_mode = cast(u32) meshlet_lizard_debug_mode;
    light_dir := normalize(Vector3.{-0.45, -1.0, -0.25});
    meshlet_lizard_params.cpu[0].light_dir = light_dir;
    meshlet_lizard_params.cpu[0].lod_distance_scale = meshlet_lizard_lod_distance_scale;
    meshlet_lizard_params.cpu[0].lod_distance_power = meshlet_lizard_lod_distance_power;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = meshlet_lizard_depth_view,
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
    gpu_set_pipeline(cmd_buff, meshlet_lizard_pipeline);

    meshlet_draw_bindings := Gpu_Ptr.[
        meshlet_lizard_meshes.gpu,
        meshlet_lizard_meshlet_meshes.gpu,
        meshlet_lizard_vertices.gpu,
        meshlet_lizard_materials.gpu,
        meshlet_lizard_meshlets.gpu,
        meshlet_lizard_meshlet_vertices.gpu,
        meshlet_lizard_meshlet_triangles.gpu,
        meshlet_lizard_instances.gpu,
    ];
    for meshlet_lizard_batches {
        meshlet_lizard_params.cpu[0].batch_mesh_index = it.mesh_index;
        meshlet_lizard_params.cpu[0].batch_first_instance = it.first_instance;
        meshlet_lizard_params.cpu[0].batch_instance_count = it.instance_count;
        meshlet_lizard_params.cpu[0].batch_max_meshlet_count = it.max_meshlet_count;

        draw_result := gpu_draw_meshlets(cmd_buff, meshlet_lizard_params.gpu, meshlet_draw_bindings, .[it.max_meshlet_count, it.instance_count, 1]);
        assert(draw_result == .SUCCESS, "gpu_draw_meshlets failed: %", draw_result);
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick


show_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    defer End();
    if !Begin("Meshlet Lizard Grid") return;

    Text("Model: %", MESHLET_LIZARD_MODEL_PATH);
    Text("Batches: %  Instances: %", meshlet_lizard_batches.count, MESHLET_LIZARD_INSTANCE_COUNT);
    Text("Max Meshlets / Mesh: %", meshlet_lizard_geo.max_meshlet_count);
    Checkbox("Auto Orbit", *meshlet_lizard_auto_orbit);
    if RadioButton("Shaded", meshlet_lizard_debug_mode == .SHADED) meshlet_lizard_debug_mode = .SHADED;
    SameLine();
    if RadioButton("LODs", meshlet_lizard_debug_mode == .LODS) meshlet_lizard_debug_mode = .LODS;
    SameLine();
    if RadioButton("Meshlets", meshlet_lizard_debug_mode == .MESHLETS) meshlet_lizard_debug_mode = .MESHLETS;
    SliderFloat("LOD Distance", *meshlet_lizard_lod_distance_scale, 1.0, 20.0);
    SliderFloat("LOD Power", *meshlet_lizard_lod_distance_power, 0.5, 2.0);
    Text("Mesh+Fragment via Jai-Shader-Transpiler");
    Text("RMB look, WASD move, Shift boost");

    Separator();
    Text("LOD Triangle Counts");
    for *batch, batch_index: meshlet_lizard_batches {
        mesh := meshlet_lizard_geo.meshes[batch.mesh_index];
        Text("Batch %", batch_index);
        for lod_i: 0..cast(s64) mesh.lod_mesh_count {
            lod_mesh_index := ifx lod_i == 0 then batch.mesh_index else mesh.lod_mesh_start + cast(u32) (lod_i - 1);
            lod_mesh := meshlet_lizard_geo.meshes[lod_mesh_index];
            triangles := lod_mesh.index_count / 3;
            Text("  LOD%: % tris", lod_i, triangles);
        }
    }
} @on_ui

#scope_file
init_meshlet_lizard_pipeline :: () {
    shader :: #run get_transpiled_mesh_pipeline(.METAL, mesh_main, fragment_main);
    meshlet_lizard_mesh_source = copy_string(shader.mesh_source);
    mesh_desc := Gpu_Mesh_Pipeline_Desc.{
        task_shader = .{},
        mesh_shader = cast([]u8) meshlet_lizard_mesh_source,
        pixel_shader = cast([]u8) shader.pixel_source,
        raster_desc = .{
            cull = .NONE,
            depth_format = .D32_SFLOAT,
            color_targets = .[
                .{format = .B8G8R8A8_UNORM},
            ],
        },
        task_threads = .[0, 0, 0],
        mesh_threads = .[1, 1, 1],
        payload_memory_length = cast(u32) shader.payload_memory_length,
        max_total_threadgroups_per_mesh_grid = 0,
    };
    meshlet_lizard_pipeline = gpu_create_mesh_pipeline(mesh_desc);
    assert(meshlet_lizard_pipeline != 0, "Failed to create meshlet lizard mesh pipeline.");
}

rebuild_meshlet_lizard_scene :: () {
    array_reset(*meshlet_lizard_batches);
    if meshlet_lizard_arena.cpu != null {
        gpu_free_arena(meshlet_lizard_arena);
        meshlet_lizard_arena = .{};
    }

    meshlet_lizard_scene_center = .{0.0, 0.0, 0.0};

    model := meshlet_lizard_geo.models[meshlet_lizard_model_index];
    model_bounds := scene_geo_model_bounds(*meshlet_lizard_geo, meshlet_lizard_model_index);
    model_extent := model_bounds.max - model_bounds.min;
    model_center := (model_bounds.min + model_bounds.max) * 0.5;
    spacing := max(max(model_extent.x, model_extent.z), 1.0) * 1.5;
    used_cols := min(MESHLET_LIZARD_INSTANCE_COUNT, cast(u32) MESHLET_LIZARD_GRID_COLS);
    used_rows := (MESHLET_LIZARD_INSTANCE_COUNT + cast(u32) MESHLET_LIZARD_GRID_COLS - 1) / cast(u32) MESHLET_LIZARD_GRID_COLS;
    grid_width := cast(float) max(cast(s32) used_cols - 1, 0) * spacing;
    grid_depth := cast(float) max(cast(s32) used_rows - 1, 0) * spacing;
    meshlet_lizard_scene_center = .{0.0, 0.0, 0.0};
    meshlet_lizard_scene_radius = max(max(grid_width, grid_depth) * 0.55, spacing * 1.75);

    total_instance_count := cast(s64) model_mesh_ref_count(model);
    total_instance_count *= MESHLET_LIZARD_INSTANCE_COUNT;

    total_bytes :=
        1024 +
        size_of(Meshlet_Grid_Params) +
        meshlet_lizard_geo.vertices.cpu.count * size_of(Scene_Vertex) +
        meshlet_lizard_geo.materials.cpu.count * size_of(Scene_Material) +
        meshlet_lizard_geo.meshes.count * size_of(Scene_Mesh) +
        meshlet_lizard_geo.meshlet_meshes.cpu.count * size_of(Scene_Meshlet_Mesh) +
        meshlet_lizard_geo.meshlets.cpu.count * size_of(Scene_Meshlet) +
        meshlet_lizard_geo.meshlet_vertices.cpu.count * size_of(u32) +
        meshlet_lizard_geo.meshlet_triangles.cpu.count * size_of(u32) +
        meshlet_lizard_geo.meshlet_bounds.cpu.count * size_of(Vector4) +
        total_instance_count * size_of(Meshlet_Grid_Instance);

    meshlet_lizard_arena = gpu_make_arena(total_bytes, label = "meshlet lizard arena");
    assert(meshlet_lizard_arena.cpu != null, "Failed to allocate meshlet lizard arena.");

    meshlet_lizard_params = gpu_alloc_view(*meshlet_lizard_arena, Meshlet_Grid_Params, 1);
    meshlet_lizard_vertices = gpu_alloc_view(*meshlet_lizard_arena, Scene_Vertex, meshlet_lizard_geo.vertices.cpu.count);
    meshlet_lizard_materials = gpu_alloc_view(*meshlet_lizard_arena, Scene_Material, meshlet_lizard_geo.materials.cpu.count);
    meshlet_lizard_meshes = gpu_alloc_view(*meshlet_lizard_arena, Scene_Mesh, meshlet_lizard_geo.meshes.count);
    meshlet_lizard_meshlet_meshes = gpu_alloc_view(*meshlet_lizard_arena, Scene_Meshlet_Mesh, meshlet_lizard_geo.meshlet_meshes.cpu.count);
    meshlet_lizard_meshlets = gpu_alloc_view(*meshlet_lizard_arena, Scene_Meshlet, meshlet_lizard_geo.meshlets.cpu.count);
    meshlet_lizard_meshlet_vertices = gpu_alloc_view(*meshlet_lizard_arena, u32, meshlet_lizard_geo.meshlet_vertices.cpu.count);
    meshlet_lizard_meshlet_triangles = gpu_alloc_view(*meshlet_lizard_arena, u32, meshlet_lizard_geo.meshlet_triangles.cpu.count);
    meshlet_lizard_meshlet_bounds = gpu_alloc_view(*meshlet_lizard_arena, Vector4, meshlet_lizard_geo.meshlet_bounds.cpu.count);
    meshlet_lizard_instances = gpu_alloc_view(*meshlet_lizard_arena, Meshlet_Grid_Instance, total_instance_count);

    memcpy(meshlet_lizard_vertices.cpu.data, meshlet_lizard_geo.vertices.cpu.data, meshlet_lizard_geo.vertices.cpu.count * size_of(Scene_Vertex));
    memcpy(meshlet_lizard_materials.cpu.data, meshlet_lizard_geo.materials.cpu.data, meshlet_lizard_geo.materials.cpu.count * size_of(Scene_Material));
    memcpy(meshlet_lizard_meshes.cpu.data, meshlet_lizard_geo.meshes.data, meshlet_lizard_geo.meshes.count * size_of(Scene_Mesh));
    memcpy(meshlet_lizard_meshlet_meshes.cpu.data, meshlet_lizard_geo.meshlet_meshes.cpu.data, meshlet_lizard_geo.meshlet_meshes.cpu.count * size_of(Scene_Meshlet_Mesh));
    memcpy(meshlet_lizard_meshlets.cpu.data, meshlet_lizard_geo.meshlets.cpu.data, meshlet_lizard_geo.meshlets.cpu.count * size_of(Scene_Meshlet));
    memcpy(meshlet_lizard_meshlet_vertices.cpu.data, meshlet_lizard_geo.meshlet_vertices.cpu.data, meshlet_lizard_geo.meshlet_vertices.cpu.count * size_of(u32));
    memcpy(meshlet_lizard_meshlet_triangles.cpu.data, meshlet_lizard_geo.meshlet_triangles.cpu.data, meshlet_lizard_geo.meshlet_triangles.cpu.count * size_of(u32));
    memcpy(meshlet_lizard_meshlet_bounds.cpu.data, meshlet_lizard_geo.meshlet_bounds.cpu.data, meshlet_lizard_geo.meshlet_bounds.cpu.count * size_of(Vector4));

    meshlet_lizard_params.cpu[0] = .{
        light_dir = .{-0.45, -1.0, -0.25},
        lod_distance_scale = meshlet_lizard_lod_distance_scale,
        lod_distance_power = meshlet_lizard_lod_distance_power,
    };

    instance_cursor: u32;
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := meshlet_lizard_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := meshlet_lizard_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            batch := array_add(*meshlet_lizard_batches);
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
                meshlet_lizard_instances.cpu[instance_cursor] = .{
                    world = root * node.world,
                };
                instance_cursor += 1;
            }
        }
    }

    camera_height := max(model_extent.y, 1.0) * 4.0;
    meshlet_lizard_camera.position = meshlet_lizard_scene_center + .{0.0, camera_height, meshlet_lizard_scene_radius * 1.8};
    editor_camera_set_look_at(*meshlet_lizard_camera, meshlet_lizard_scene_center);
}

mesh_max_meshlet_count :: (mesh_index: u32) -> u32 {
    mesh := meshlet_lizard_geo.meshes[mesh_index];
    result := meshlet_lizard_geo.meshlet_meshes.cpu[mesh_index].meshlet_count;
    for lod_offset: 0..mesh.lod_mesh_count-1 {
        lod_mesh_index := mesh.lod_mesh_start + lod_offset;
        result = max(result, meshlet_lizard_geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count);
    }
    return max(result, 1);
}

model_mesh_ref_count :: (model: Scene_Model) -> s64 {
    total: s64;
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        total += meshlet_lizard_geo.nodes[node_index].mesh_ref_count;
    }
    return total;
}

ensure_meshlet_lizard_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if meshlet_lizard_depth_view != 0 && meshlet_lizard_depth_w == width && meshlet_lizard_depth_h == height return;

    if meshlet_lizard_depth_texture != 0 gpu_free(meshlet_lizard_depth_texture);
    meshlet_lizard_depth_texture = 0;
    meshlet_lizard_depth_view = 0;

    res, meshlet_lizard_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS, "Depth texture creation failed: %", res);
    meshlet_lizard_depth_view = gpu_texture_view(meshlet_lizard_depth_texture);
    assert(meshlet_lizard_depth_view != 0, "Depth view creation failed.");
    meshlet_lizard_depth_w = width;
    meshlet_lizard_depth_h = height;
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../scene_geo.jai";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "String";
#import "Math";
#load "shaders/meshlet_lizard_grid_shader.jai";
