Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
}

Animated_Batch :: struct {
    batch_index: s32;
    skin_matrix_start: u32;
    skin_matrix_count: u32;
}

Scene_Instance_CPU :: struct {
    world: Matrix4;
    tint: Vector4;
}

Scene_Draw_Params_CPU :: struct {
    vertices: Gpu_Ptr;
    indices: Gpu_Ptr;
    materials: Gpu_Ptr;
    instances: Gpu_Ptr;
    skin_matrices: Gpu_Ptr; // points to 4 Vector4 rows per bone
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    camera_pos: Vector3;
    _pad1: float;
    material_index: u32;
    sampler_index: u32;
    skin_matrix_count: u32;
    _pad2: u32;
    _pad3: u32;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
scene_geo: Scene_Geo;
running_lizard_anim: Scene_Anim_State;
running_lizard_clip_index: s32 = -1;
running_lizard_root: Matrix4 = Matrix4_Identity;
scene_instances: Gpu_View(Scene_Instance_CPU);
scene_draw_params: Gpu_View(Scene_Draw_Params_CPU);
scene_skin_matrices: Gpu_View(Vector4);
scene_depth_texture: Gpu_Texture;
scene_depth_view: Gpu_Texture_View;
scene_depth_w: u32;
scene_depth_h: u32;
scene_batches: [..]Draw_Batch;
animated_batches: [..]Animated_Batch;
scene_debug_logged: bool;

scene_camera: Editor_Camera = .{
    position = .{0.0, 7.0, 12.5},
    yaw = 0.0,
    pitch = -0.36,
    move_speed = 8.0,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0058,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, model_scene_vertex_main, model_scene_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for model scene shaders.");

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    });
    assert(graphics_pipeline != 0, "Model scene graphics pipeline creation failed.");

    model_paths := string.[
        "./models/triangle.obj",
        "./models/teapot.obj",
        "./models/nerdy+lizard+3d+model.glb",
        "./models/Lizard run.glb",
    ];
    scene_geo_init(*scene_geo, model_paths);

    triangle_model := scene_geo_model_index_by_name(*scene_geo, "triangle");
    teapot_model := scene_geo_model_index_by_name(*scene_geo, "teapot");
    lizard_model := scene_geo_model_index_by_name(*scene_geo, "nerdy+lizard+3d+model");
    running_lizard_model := scene_geo_model_index_by_name(*scene_geo, "Lizard run");
    assert(triangle_model >= 0 && teapot_model >= 0 && lizard_model >= 0 && running_lizard_model >= 0, "Failed to resolve Scene_Geo model indices.");
    hero_lizard_bounds := scene_geo_model_bounds(*scene_geo, lizard_model);
    hero_lizard_size := hero_lizard_bounds.max - hero_lizard_bounds.min;
    hero_lizard_max_extent := max(max(hero_lizard_size.x, hero_lizard_size.y), hero_lizard_size.z);
    running_lizard_bounds := scene_geo_model_bounds(*scene_geo, running_lizard_model);
    running_lizard_size := running_lizard_bounds.max - running_lizard_bounds.min;
    running_lizard_max_extent := max(max(running_lizard_size.x, running_lizard_size.y), running_lizard_size.z);
    hero_lizard_world_scale := 12.0;
    running_lizard_target_extent := hero_lizard_max_extent * hero_lizard_world_scale * 1.7;
    running_lizard_scale := ifx running_lizard_max_extent > 0.0 then running_lizard_target_extent / running_lizard_max_extent else 1.0;
    running_lizard_ground_y := -running_lizard_bounds.min.y * running_lizard_scale + 0.5;
    running_lizard_model_info := scene_geo.models[running_lizard_model];
    assert(running_lizard_model_info.anim_clip_count > 0, "Running lizard model has no imported animation clips.");
    running_lizard_clip_index = cast(s32) running_lizard_model_info.anim_clip_start;
    scene_anim_init(*running_lizard_anim, *scene_geo, running_lizard_model, running_lizard_clip_index);

    root_transforms: [..]Matrix4;
    instances_cpu: [..]Scene_Instance_CPU;
    total_skin_matrix_count: s64 = 0;
    root_transforms.allocator = context.allocator;
    instances_cpu.allocator = context.allocator;
    scene_batches.allocator = context.allocator;
    animated_batches.allocator = context.allocator;
    defer array_free(root_transforms);
    defer array_free(instances_cpu);

    array_add(*root_transforms, make_translation_matrix4(.{-4.8, 1.6, -15.5}) * make_scale_matrix4(.{1.35, 1.35, 1.35}));
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, triangle_model, root_transforms, tint = .{0.9, 0.45, 0.3, 1.0});
    array_reset(*root_transforms);

    array_add(*root_transforms, make_translation_matrix4(.{4.9, 1.1, -5.6}) * make_scale_matrix4(.{12.0, 12.0, 12.0}));
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, lizard_model, root_transforms);
    array_reset(*root_transforms);

    running_lizard_root = make_translation_matrix4(.{-6.8, running_lizard_ground_y, -9.5}) * make_scale_matrix4(.{running_lizard_scale, running_lizard_scale, running_lizard_scale});
    for node_index: running_lizard_model_info.node_start .. running_lizard_model_info.node_start + running_lizard_model_info.node_count - 1 {
        node := scene_geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := scene_geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            mesh := scene_geo.meshes[mesh_index];
            batch := array_add(*scene_batches);
            batch.mesh_index = mesh_index;
            batch.first_instance = cast(u32) instances_cpu.count;
            batch.instance_count = 1;

            instance_world := running_lizard_root;
            if mesh.skin_bone_count == 0 instance_world = running_lizard_root * node.world;
            array_add(*instances_cpu, .{
                world = instance_world,
                tint = .{1.0, 0.96, 0.96, 1.0},
            });

            if mesh.skin_bone_count > 0 {
                array_add(*animated_batches, .{
                    batch_index = cast(s32) scene_batches.count - 1,
                    skin_matrix_start = cast(u32) total_skin_matrix_count,
                    skin_matrix_count = mesh.skin_bone_count,
                });
                total_skin_matrix_count += mesh.skin_bone_count;
            }
        }
    }

    grid_w :: 20;
    grid_h :: 25;
    spacing := 1.15;
    for y: 0..grid_h-1 {
        for x: 0..grid_w-1 {
            tx := (cast(float) x - cast(float) (grid_w - 1) * 0.5) * spacing;
            tz := (cast(float) y - cast(float) (grid_h - 1) * 0.5) * spacing - 16.0;
            height := sin(cast(float) x * 0.45) * 0.18 + cos(cast(float) y * 0.32) * 0.12;
            scale := 0.09 + 0.018 * sin(cast(float) (x + y) * 0.37);
            array_add(*root_transforms, make_translation_matrix4(.{tx, height, tz}) * make_scale_matrix4(.{scale, scale, scale}));
        }
    }
    scene_geo_append_model_instances(*scene_batches, *instances_cpu, *scene_geo, teapot_model, root_transforms, tint = .{0.94, 0.78, 0.48, 1.0});

    arena_bytes :=
        instances_cpu.count * size_of(Scene_Instance_CPU) +
        scene_batches.count * size_of(Scene_Draw_Params_CPU) +
        total_skin_matrix_count * 4 * size_of(Vector4) +
        1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "model scene arena");
    assert(gpu_arena.cpu != null, "Model scene arena creation failed.");

    scene_instances = gpu_alloc_view(*gpu_arena, Scene_Instance_CPU, instances_cpu.count);
    if instances_cpu.count > 0 {
        memcpy(scene_instances.cpu.data, instances_cpu.data, instances_cpu.count * size_of(Scene_Instance_CPU));
    }

    if total_skin_matrix_count > 0 {
        scene_skin_matrices = gpu_alloc_view(*gpu_arena, Vector4, total_skin_matrix_count * 4);
    }

    scene_draw_params = gpu_alloc_view(*gpu_arena, Scene_Draw_Params_CPU, scene_batches.count);
    for batch: scene_batches {
        mesh := scene_geo.meshes[batch.mesh_index];
        scene_draw_params.cpu[it_index] = .{
            vertices = scene_geo.vertices.gpu,
            indices = scene_geo.indices.gpu + (mesh.first_index * size_of(u32)).(Gpu_Ptr),
            materials = scene_geo.materials.gpu,
            instances = scene_instances.gpu + (batch.first_instance * size_of(Scene_Instance_CPU)).(Gpu_Ptr),
            skin_matrices = 0,
            view_proj = Matrix4_Identity,
            light_dir = normalize(Vector3.{0.35, -1.0, 0.25}),
            camera_pos = scene_camera.position,
            material_index = mesh.material_index,
            sampler_index = cast(u32) scene_geo.sampler - 1,
            skin_matrix_count = 0,
        };
    }
    for animated_batches {
        batch_index := cast(s64) it.batch_index;
        scene_draw_params.cpu[batch_index].skin_matrices = scene_skin_matrices.gpu + (it.skin_matrix_start * 4 * size_of(Vector4)).(Gpu_Ptr);
        scene_draw_params.cpu[batch_index].skin_matrix_count = it.skin_matrix_count;
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    scene_anim_deinit(*running_lizard_anim);
    array_free(animated_batches);
    array_free(scene_batches);
    scene_geo_deinit(*scene_geo);
    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_scene_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    io := ImGui.GetIO();
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    _ = editor_camera_update(*scene_camera, dt, mx, my, mouse_ok,
        allow_move = !io.WantCaptureKeyboard,
        allow_look = right_down && !io.WantCaptureMouse);

    view := editor_camera_make_view(*scene_camera);
    aspect := ifx win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := make_projection_matrix(PI / 3.2, aspect, 0.05, 250.0);
    view_proj := proj * view;

    walk_blend := clamp(cast(float) time * 1.8, 0.0, 1.0);
    scene_anim_sample(*running_lizard_anim, *scene_geo, running_lizard_clip_index, cast(float) time, walk_blend);
    for animated_batches {
        batch := scene_batches[it.batch_index];
        mesh := scene_geo.meshes[batch.mesh_index];
        skin_start := cast(s64) it.skin_matrix_start * 4;
        skin_end := skin_start + cast(s64) it.skin_matrix_count * 4;
        dst := scene_skin_matrices.cpu;
        dst.data += skin_start;
        dst.count = skin_end - skin_start;
        written := scene_anim_write_skin_matrices(dst, *scene_geo, *running_lizard_anim, mesh);
        assert(written == it.skin_matrix_count);
    }

    for *scene_draw_params.cpu {
        it.view_proj = view_proj;
        it.camera_pos = scene_camera.position;
        it.light_dir = normalize(Vector3.{0.35, -1.0, 0.25});
    }

    if !scene_debug_logged scene_debug_logged = true;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = scene_depth_view,
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
                clear_color._float = .[0.06, 0.08, 0.11, 1.0],
            },
        ],
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    for batch: scene_batches {
        mesh := scene_geo.meshes[batch.mesh_index];
        params_gpu := scene_draw_params.gpu + (it_index * size_of(Scene_Draw_Params_CPU)).(Gpu_Ptr);
        draw_result := gpu_draw_instanced_direct(cmd_buff, params_gpu, mesh.index_count, batch.instance_count);
        assert(draw_result == .SUCCESS, "Model scene draw failed.");
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

ensure_scene_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if scene_depth_view != 0 && scene_depth_w == width && scene_depth_h == height return;

    res, scene_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS);
    assert(scene_depth_texture != 0, "Model scene depth texture creation failed.");

    scene_depth_view = gpu_texture_view(scene_depth_texture);
    assert(scene_depth_view != 0, "Model scene depth view creation failed.");
    scene_depth_w = width;
    scene_depth_h = height;
    gpu_commit_residency();
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "../scene_geo.jai";
#load "../scene_anim.jai";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Math";
#load "shaders/model_scene_shader.jai";
