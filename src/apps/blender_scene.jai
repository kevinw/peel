 #load "../SGPU_App_Common.jai";

BLENDER_SCENE_DEFAULT_BLEND_PATH :: "tools/blender_exporter/monkeys.blend";

Meshlet_Grid_Instance :: struct {
    world: Matrix4;
}

Draw_Batch :: struct {
    mesh_index: u32;
    first_instance: u32;
    instance_count: u32;
    max_meshlet_count: u32;
}

Scene_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
}

last_frustum_planes: [6]Vector4;

BLENDER_SCENE_POLL_SECONDS :: 0.20;
MESHLET_TASK_EMIT_MESHLET_COUNT : u32 : 64;
BLENDER_SCENE_MAX_MESH_GROUPS_PER_DRAW : u32 : 1024;

using app: struct {
    background_shader: Shader(fullscreen_tri_vert, hdri_background_fragment_main, {
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    });
    mesh_shader: Mesh_Shader(mesh_main, fragment_main, .{
        raster_desc = .{
            cull = .NONE,
            depth_format = .D32_SFLOAT,
            color_targets = .[
                .{format = .B8G8R8A8_UNORM},
            ],
        },
        task_threads = .[1, 1, 1],
        mesh_threads = .[1, 1, 1],
        max_total_threadgroups_per_mesh_grid = BLENDER_SCENE_MAX_MESH_GROUPS_PER_DRAW,
    }, task_main);
    depth_texture: Gpu_Texture;
    depth_view: Gpu_Texture_View;
    depth_w: u32;
    depth_h: u32;
    geo: Scene_Geo;
    arena: Gpu_Arena;
    hdri_params: Gpu_Buffer(HDRI_Background_Params);
    hdri_texture: Gpu_Texture;
    hdri_view: Gpu_Texture_View;
    hdri_sampler: Gpu_Sampler;
    hdri_enabled: bool = true;
    hdri_candidates: [..]string;
    hdri_index: s32 = -1;
    hdri_source_path: string;
    hdri_cache_path: string;
    hdri_exposure: float = 1.0;
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
    batches: [..]Draw_Batch;
    model_index: s32 = -1;
    camera: Editor_Camera = {
        position = .{0.0, 4.5, 9.0},
        yaw = 0.0,
        pitch = -0.32,
        move_speed = 14.0,
        boost_multiplier = 2.5,
        mouse_sensitivity = 0.0048,
        move_planar = false,
        pitch_min = -1.45,
        pitch_max = 1.45,
    };
    auto_orbit: bool;
    orbit_time: float;
    scene_center: Vector3;
    scene_radius: float = 6.0;
    lod_screen_radius: float = 420.0;
    lod_distance_power: float = 1.18;
    mesh_source: string;
    mesh_grid_limit: u32;
    param_slot_count: s64 = 1;
    source_path: string;
    export_path: string;
    debug_batch_filter: s32 = -1;
    watched_export_modtime: Apollo_Time;
    watched_export_size: s64;
    reload_count: u32;
    reload_poll_accum: float;

    freeze_culling := false;
    freeze_culling_set := false;
    frozen_culling_cam_matrix: Matrix4;

    using draw: Meshlet_Grid_Params;
}

on_dll_init :: () {
    assert(OS == .MACOS, "blender_scene is currently Metal mesh-shader only.");
    source_path = resolve_blend_source_path();
    export_path = sprint("%.peelscene", source_path);
    apply_debug_env_overrides();

    init_blender_scene_pipeline();
    init_hdri_background();
    load_blender_scene(first_load=true);
    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    if source_path.count != 0 free(source_path);
    free(export_path);
    if mesh_source.count != 0 free(mesh_source);
    if hdri_source_path.count != 0 free(hdri_source_path);
    if hdri_cache_path.count != 0 free(hdri_cache_path);
    for hdri_candidates free(it);
    array_free(hdri_candidates);
    if depth_texture != 0 gpu_free(depth_texture);
    gpu_delete(*hdri_params);
    gpu_delete(*hdri_sampler);
    gpu_delete(*hdri_view);
    gpu_delete(*hdri_texture);
    if background_shader.pipeline != 0 gpu_delete(*background_shader.pipeline);
    if mesh_shader.pipeline != 0 gpu_delete(*mesh_shader.pipeline);
    if arena.cpu != null gpu_free_arena(arena);
    array_free(batches);
    scene_geo_deinit(*geo);
} @on_unload

tick :: () {
    poll_for_blender_scene_changes();

    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;

    ensure_depth_target(cast(u32) win_w, cast(u32) win_h);

    allow_look := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    editor_camera_update(*camera, editor_dt, mx, my, mouse_ok,
        allow_move = true,
        allow_look = allow_look);

    if auto_orbit {
        orbit_time += editor_dt;
        orbit_radius := max(scene_radius * 1.35, 2.5);
        camera.position = scene_center + .{
            sin(orbit_time * 0.23) * orbit_radius,
            max(scene_radius * 0.42, 1.5),
            cos(orbit_time * 0.23) * orbit_radius,
        };
        editor_camera_set_look_at(*camera, scene_center);
    }

    aspect := cast(float) win_w / max(cast(float) win_h, 1.0);
    view := editor_camera_make_view(*camera);
    proj := editor_camera_make_projection(*camera, aspect, 0.05, 600.0);
    draw.camera_vp = proj * view;
    if freeze_culling {
        if freeze_culling_set {
            freeze_culling_set = false;
            frozen_culling_cam_matrix = draw.camera_vp;
        }
        draw.frustum_planes = extract_frustum_planes(frozen_culling_cam_matrix);
    } else {
        draw.frustum_planes = extract_frustum_planes(draw.camera_vp);
    }
    last_frustum_planes = draw.frustum_planes;
    draw.eye_position = camera.position;
    draw.lod_projection_scale = cast(float) win_h / max(2.0 * max(tan(camera.fov_y * 0.5), 0.0001), 0.0001);
    draw.lod_radius_threshold = lod_screen_radius;
    draw.lod_metric_power = lod_distance_power;
    draw.light_dir = normalize(Vector3.{-0.45, -1.0, -0.25});
    base_params := draw;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

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
    ];

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
    if hdri_enabled && hdri_view != 0 && hdri_sampler != 0 && hdri_params.cpu != null {
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(camera, *cam_forward, *cam_right, *cam_up);
        hdri_params.cpu.camera_right_proj_x = .{cam_right.x, cam_right.y, cam_right.z, proj._11};
        hdri_params.cpu.camera_up_proj_y = .{cam_up.x, cam_up.y, cam_up.z, proj._22};
        hdri_params.cpu.camera_forward_exposure = .{cam_forward.x, cam_forward.y, cam_forward.z, hdri_exposure};
        hdri_params.cpu.texture_index = gpu_texture_view_index(hdri_view);
        hdri_params.cpu.sampler_index = cast(u32) hdri_sampler - 1;

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, background_shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, hdri_params.gpu, 3, 1);
    }
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, SHR.pipeline(*mesh_shader, constants));

    for batches {
        if debug_batch_filter >= 0 && cast(s32) it_index != debug_batch_filter continue;
        total_task_slots := it.max_meshlet_count;
        draw_first_instance := it.first_instance;
        draw_instance_total := it.instance_count;
        meshlet_chunk_count := max(cast(u32) 1, (total_task_slots + MESHLET_TASK_EMIT_MESHLET_COUNT - 1) / MESHLET_TASK_EMIT_MESHLET_COUNT);
        max_object_groups_per_draw := max(cast(u32) 1, mesh_grid_limit / MESHLET_TASK_EMIT_MESHLET_COUNT);

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
                primary_params.cpu.metallic_factor = batch_material.metallic_factor;
                primary_params.cpu.roughness_factor = batch_material.roughness_factor;
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
    if !Begin("Blender Scene") return;

    if Button("Open In Blender (Live)") {
        spawn_live_blender();
    }
    SameLine();
    if Button("Reload Now") {
        load_blender_scene(first_load=false);
    }

    Text("Source: %", source_path);
    Text("Export: %", export_path);
    Text("Reloads: %", reload_count);
    Text("Batches: %  Instances: %", batches.count, instances.cpu.count);
    Text("Batch Filter: %", debug_batch_filter);
    Text("Max Meshlets / Mesh: %", geo.max_meshlet_count);
    Text("RMB look, WASD move, Shift boost");
    Checkbox("Render HDRI", *hdri_enabled);
    if hdri_candidates.count > 0 {
        if SmallButton("<") {
            cycle_hdri_selection(-1);
        }
        SameLine();
        current_hdri_name := ifx hdri_source_path.count != 0 then String.path_filename(hdri_source_path) else "(none)";
        Text("HDRI: %", current_hdri_name);
        SameLine();
        if SmallButton(">") {
            cycle_hdri_selection(1);
        }
    } else if hdri_source_path.count != 0 {
        Text("HDRI: %", String.path_filename(hdri_source_path));
    }
    SliderFloat("HDRI Exposure", *hdri_exposure, 0.1, 4.0);
    Checkbox("Auto Orbit", *auto_orbit);

    using constants;

    inspect("Debug Flags", *debug_flags);

    if Checkbox("Freeze Culling", *freeze_culling) {
        if freeze_culling freeze_culling_set = true;
    }

    //inspect("last_frustum_planes", *last_frustum_planes);
    inspect("Debug Mode", *debug_mode);
    SliderFloat("LOD Screen Radius", *lod_screen_radius, 8.0, 1024.0);
    SliderFloat("LOD Power", *lod_distance_power, 0.5, 2.0);
} @on_ui

#scope_file

resolve_blend_source_path :: () -> string {
    blend_path := getenv_string("PEEL_BLEND_PATH");
    if blend_path.count == 0 blend_path = BLENDER_SCENE_DEFAULT_BLEND_PATH;
    if !String.is_absolute_path(blend_path) {
        blend_path = tprint("%/%", find_workspace_root(), blend_path);
    }
    assert(file_exists(blend_path), "Set PEEL_BLEND_PATH to a .blend file. Missing path: %", blend_path);
    return copy_string(blend_path);
}

getenv_string :: (name: string) -> string {
    value_c := POSIX_Getenv.getenv(temp_c_string(name));
    if !value_c return "";
    return to_string(value_c, c_style_strlen(value_c));
}

constants: Meshlet_Shader_Constants;

apply_debug_env_overrides :: () {
    debug_flags_text := getenv_string("PEEL_MESHLET_DEBUG_FLAGS");
    if debug_flags_text.count != 0 {
        debug_flags_value, ok := string_to_int(debug_flags_text);
        assert(ok, "PEEL_MESHLET_DEBUG_FLAGS must be an integer, got '%'.", debug_flags_text);
        constants.debug_flags = cast(Meshlet_Debug_Flags) debug_flags_value;
    }

    debug_mode_text := getenv_string("PEEL_MESHLET_DEBUG_MODE");
    if debug_mode_text.count != 0 {
        debug_mode_value, ok := string_to_int(debug_mode_text);
        assert(ok, "PEEL_MESHLET_DEBUG_MODE must be an integer, got '%'.", debug_mode_text);
        constants.debug_mode = cast(Meshlet_Grid_Debug_Mode) debug_mode_value;
    }

    debug_batch_text := getenv_string("PEEL_MESHLET_BATCH");
    if debug_batch_text.count != 0 {
        debug_batch_value, ok := string_to_int(debug_batch_text);
        assert(ok, "PEEL_MESHLET_BATCH must be an integer, got '%'.", debug_batch_text);
        debug_batch_filter = cast(s32) debug_batch_value;
    }
}

find_workspace_root :: () -> string {
    cwd := get_working_directory();
    probe := cwd;

    while probe.count != 0 {
        if file_exists(tprint("%/build.jai", probe)) return probe;
        parent := String.path_strip_filename(probe);
        if parent.count != 0 && parent[parent.count-1] == "/" {
            parent.count -= 1;
        }
        if parent == probe break;
        probe = parent;
    }

    return cwd;
}

spawn_live_blender :: () {
    root := find_workspace_root();
    script_path := tprint("%/tools/blender_exporter/open_blend_live.sh", root);
    if !file_exists(script_path) {
        log_error("blender_scene: missing live Blender launcher: %", script_path);
        return;
    }

    launch_args := string.[script_path, source_path];

    // our build of blender was crashing with metal validation layers enabled, so I'm clearing them here - @kev Apr 2026
    cleared_env := "env -u MTL_SHADER_VALIDATION -u MTL_SHADER_VALIDATION_REPORT_TO_STDERR -u MTL_LOG_TO_STDERR -u MTL_DEBUG_LAYER -u MTL_LOG_LEVEL -u MTL_LOG_BUFFER_SIZE";

    launch_cmd := tprint(
        "nohup % % > >(tee -a /tmp/peel_blender_live.log) 2> >(tee -a /tmp/peel_blender_live.log >&2) &",
        cleared_env,
        Process_Module.get_quoted_command_string(launch_args));
    result, _, _, timeout_reached := Process_Module.run_command(
        "/bin/zsh", "-lc", launch_cmd,
        working_directory = root,
        capture_and_return_output = false,
        timeout_ms = 2000);
    if timeout_reached || result.type == .FAILED_TO_LAUNCH || (result.type == .EXITED && result.exit_code != 0) {
        log_error("blender_scene: failed to launch live Blender via %", script_path);
        return;
    }
}

init_blender_scene_pipeline :: () {
    ok_bg := SHR.init(*background_shader);
    assert(ok_bg, "Failed to create blender_scene HDRI background pipeline.");

    ok_mesh := SHR.init(*mesh_shader, Meshlet_Shader_Constants.{});
    assert(ok_mesh, "Failed to create blender_scene mesh pipeline.");

    mesh_grid_limit = gpu_get_mesh_pipeline_max_total_threadgroups_per_grid(mesh_shader.pipeline);
    if mesh_grid_limit == 0 mesh_grid_limit = BLENDER_SCENE_MAX_MESH_GROUPS_PER_DRAW;
}

init_hdri_background :: () {
    hdri_params = gpu_alloc_buffer(HDRI_Background_Params, label = "blender scene hdri params");
    hdri_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .LINEAR,
        address_mode_u = .REPEAT,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(hdri_sampler != 0, "HDRI sampler creation failed.");

    refresh_hdri_candidates();
    if hdri_candidates.count > 0 {
        select_hdri_index(0);
        return;
    }

    resolved_source := resolve_hdri_source_path();
    if resolved_source.count == 0 return;
    hdri_source_path = resolved_source;
    if load_hdri_background_texture(hdri_source_path) return;
    log_error("blender_scene: failed to load HDRI background from %", hdri_source_path);
}

resolve_hdri_source_path :: () -> string {
    env_path := getenv_string("PEEL_HDRI_PATH");
    if env_path.count != 0 {
        if !String.is_absolute_path(env_path) env_path = tprint("%/%", find_workspace_root(), env_path);
        if file_exists(env_path) return copy_string(env_path);
        log_error("PEEL_HDRI_PATH does not exist: %", env_path);
        return "";
    }

    root := find_workspace_root();
    candidates := string.[
        tprint("%/dist/textures/hdris/bell_tower_4k.exr", root),
        tprint("%/dist/textures/hdris/citrus_orchard_puresky_4k.exr", root),
    ];
    for candidates {
        if file_exists(it) return copy_string(it);
    }
    return "";
}

refresh_hdri_candidates :: () {
    for hdri_candidates free(it);
    array_reset(*hdri_candidates);

    hdri_dir := tprint("%/dist/textures/hdris", find_workspace_root());
    if !File_Utilities.is_directory(hdri_dir) return;

    candidates := File_Utilities.file_list(hdri_dir, recursive = false, follow_directory_symlinks = false);
    defer {
        for candidates free(it);
        if candidates.data != null array_free(candidates);
    }

    for candidates {
        lower := String.to_lower_copy(it,, temp);
        if !String.ends_with(lower, ".exr") && !String.ends_with(lower, ".hdr") continue;
        array_add(*hdri_candidates, copy_string(it));
    }

    if hdri_candidates.count > 1 {
        IntroSort.intro_sort(hdri_candidates, hdri_path_compare);
    }
}

select_hdri_index :: (index: s32) {
    if hdri_candidates.count == 0 return;
    next_index := index;
    if next_index < 0 next_index = 0;
    if next_index >= hdri_candidates.count next_index = cast(s32) (hdri_candidates.count - 1);
    if hdri_index == next_index && hdri_source_path.count != 0 return;

    if hdri_source_path.count != 0 free(hdri_source_path);
    hdri_source_path = copy_string(hdri_candidates[next_index]);
    hdri_index = next_index;
    if !load_hdri_background_texture(hdri_source_path) {
        log_error("blender_scene: failed to switch HDRI to %", hdri_source_path);
    }
}

cycle_hdri_selection :: (delta: s32) {
    if hdri_candidates.count == 0 return;
    next_index := hdri_index + delta;
    if next_index < 0 next_index = cast(s32) (hdri_candidates.count - 1);
    if next_index >= hdri_candidates.count next_index = 0;
    select_hdri_index(next_index);
}

hdri_cache_path_for_source :: (source_path: string, modtime: Apollo_Time, size: s64) -> string {
    key_source := tprint("hdri|astcenc-ch-6x6-fast|%|%|%:%", source_path, size, modtime.low, modtime.high);
    key_hash := Hash.fnv1a_hash(key_source.data, key_source.count);
    cache_dir := tprint("%/.build/texture_cache/hdri", find_workspace_root());
    return tprint("%/%.astc6x6hdr.ktx", cache_dir, key_hash);
}

ensure_hdri_cache :: (source_path: string) -> bool, string {
    modtime, size, exists := file_modtime_and_size(source_path);
    if !exists {
        log_error("blender_scene: HDRI source does not exist: %", source_path);
        return false, "";
    }

    cache_path := hdri_cache_path_for_source(source_path, modtime, size);
    _ = File.make_directory_if_it_does_not_exist(String.path_strip_filename(cache_path), true);
    if file_exists(cache_path) return true, cache_path;

    result, stdout, stderr, timeout_reached := Process_Module.run_command(
        "astcenc",
        "-ch",
        source_path,
        cache_path,
        "6x6",
        "-fast",
        capture_and_return_output = true,
        working_directory = find_workspace_root(),
        timeout_ms = 300000);

    if timeout_reached || result.type != .EXITED || result.exit_code != 0 || !file_exists(cache_path) {
        log_error("blender_scene: astcenc HDRI compression failed for %", source_path);
        if stdout.count != 0 log_error("astcenc stdout:\n%", stdout);
        if stderr.count != 0 log_error("astcenc stderr:\n%", stderr);
        if stdout.count != 0 free(stdout);
        if stderr.count != 0 free(stderr);
        return false, cache_path;
    }

    if stdout.count != 0 free(stdout);
    if stderr.count != 0 free(stderr);

    log("blender_scene: built HDRI cache % -> %", source_path, cache_path);
    return true, cache_path;
}

load_hdri_background_texture :: (source_path: string) -> bool {
    ok, cache_path := ensure_hdri_cache(source_path);
    if !ok return false;

    if hdri_cache_path.count != 0 free(hdri_cache_path);
    hdri_cache_path = copy_string(cache_path);

    file_bytes, read_ok := File.read_entire_file(cache_path, zero_terminated = false, log_errors = true);
    if !read_ok {
        log_error("blender_scene: failed reading HDRI cache %", cache_path);
        return false;
    }
    defer free(file_bytes);

    descriptor_ok, descriptor := ktx_load_descriptor(file_bytes, verbose = false);
    defer array_free(descriptor.levels);
    if !descriptor_ok {
        log_error("blender_scene: failed parsing KTX cache %", cache_path);
        return false;
    }
    assert(descriptor.levels.count > 0, "HDRI cache has no mip levels: %", cache_path);

    gpu_delete(*hdri_view);
    gpu_delete(*hdri_texture);

    result, hdri_texture= := gpu_create_texture(.{
        dimensions = .[cast(u32) descriptor.pixelWidth, cast(u32) descriptor.pixelHeight, 1],
        format = .ASTC_6x6_SFLOAT_BLOCK,
        mip_count = cast(u8) descriptor.levels.count,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS, "HDRI texture creation failed: %", result);
    hdri_view = gpu_texture_view(hdri_texture);
    assert(hdri_view != 0, "HDRI view creation failed.");

    for descriptor.levels {
        level_bytes := string.{
            count = it.sizeInBytes,
            data = file_bytes.data + it.fileOffset,
        };
        gpu_copy_to_texture_layout(
            hdri_texture,
            level_bytes.data,
            cast(u32) it.size.width,
            cast(u32) max(it.size.height, 1),
            1,
            it.bytesPerRow,
            it.bytesPerImage,
            cast(u32) it_index);
    }

    gpu_commit_residency();

    return true;
}

load_blender_scene :: (first_load := false) {
    if arena.cpu != null || geo.arena.cpu != null {
        gpu_wait_idle();
    }
    if arena.cpu != null {
        gpu_free_arena(arena);
        arena = .{};
    }
    array_reset(*batches);
    if geo.arena.cpu != null {
        scene_geo_deinit(*geo);
    }

    model_paths := string.[source_path];
    scene_geo_init(*geo, model_paths);
    assert(geo.models.count > 0, "No models imported from %", source_path);
    model_index = 0;
    rebuild_blender_scene_runtime(first_load=first_load);
    gpu_commit_residency();
    update_watched_export_state();
    reload_count += 1;
    log("blender_scene loaded source=% batches=% instances=% reloads=%", source_path, batches.count, instances.cpu.count, reload_count);
}

rebuild_blender_scene_runtime :: (first_load := false) {
    model := geo.models[model_index];
    model_bounds := scene_geo_model_bounds(*geo, model_index);
    log("blender_scene model '%': bounds min=% max=% meshes=% meshlets=% nodes=%",
        model.name, model_bounds.min, model_bounds.max, geo.meshes.count, geo.meshlets.cpu.count, geo.nodes.count);
    scene_center = (model_bounds.min + model_bounds.max) * 0.5;
    scene_extent := model_bounds.max - model_bounds.min;
    scene_radius = max(max(scene_extent.x, scene_extent.z), max(scene_extent.y, 1.0)) * 0.7;
    scene_radius = max(scene_radius, 1.5);

    if first_load {
        camera.position = scene_center + .{0.0, max(scene_extent.y, 1.0) * 0.65, max(scene_radius * 1.5, 3.0)};
        editor_camera_set_look_at(*camera, scene_center);
    }

    root_transforms := Matrix4.[Matrix4_Identity];
    temp_instances: [..]Scene_Instance;
    temp_instances.allocator = temp;
    temp_batches: [..]Draw_Batch;
    temp_batches.allocator = temp;
    scene_geo_append_model_instances(*temp_batches, *temp_instances, *geo, model_index, root_transforms);
    for *temp_batches {
        it.max_meshlet_count = mesh_max_meshlet_count(it.mesh_index);
    }

    param_slot_count = 0;
    for temp_batches {
        meshlet_chunk_count := cast(s64) ((mesh_max_meshlet_count(it.mesh_index) + MESHLET_TASK_EMIT_MESHLET_COUNT - 1) / MESHLET_TASK_EMIT_MESHLET_COUNT);
        total_object_groups := max(meshlet_chunk_count, cast(s64) 1) * cast(s64) it.instance_count;
        max_object_groups_per_draw := max(cast(s64) 1, cast(s64) mesh_grid_limit / cast(s64) MESHLET_TASK_EMIT_MESHLET_COUNT);
        draw_count := (total_object_groups + max_object_groups_per_draw - 1) / max_object_groups_per_draw;
        param_slot_count += max(draw_count, cast(s64) 1) * 2;
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
        gpu_arena_required_view_size(Meshlet_Grid_Instance, max(temp_instances.count, 1));

    arena = gpu_make_arena(total_bytes, label = "blender scene arena");
    assert(arena.cpu != null, "Failed to allocate blender scene arena.");

    params = sgpu_make_frame_param_allocator(*arena, Meshlet_Grid_Params, param_slot_count);
    vertices = gpu_alloc_view(*arena, Scene_Vertex, geo.vertices.cpu.count);
    materials = gpu_alloc_view(*arena, Scene_Material, geo.materials.cpu.count);
    meshes = gpu_alloc_view(*arena, Scene_Mesh, geo.meshes.count);
    meshlet_meshes = gpu_alloc_view(*arena, Scene_Meshlet_Mesh, geo.meshlet_meshes.cpu.count);
    meshlets = gpu_alloc_view(*arena, Scene_Meshlet, geo.meshlets.cpu.count);
    meshlet_vertices = gpu_alloc_view(*arena, u32, geo.meshlet_vertices.cpu.count);
    meshlet_triangles = gpu_alloc_view(*arena, u32, geo.meshlet_triangles.cpu.count);
    meshlet_bounds = gpu_alloc_view(*arena, Vector4, geo.meshlet_bounds.cpu.count);
    instances = gpu_alloc_view(*arena, Meshlet_Grid_Instance, max(temp_instances.count, 1));

    memcpy(vertices.cpu.data, geo.vertices.cpu.data, geo.vertices.cpu.count * size_of(Scene_Vertex));
    memcpy(materials.cpu.data, geo.materials.cpu.data, geo.materials.cpu.count * size_of(Scene_Material));
    memcpy(meshes.cpu.data, geo.meshes.data, geo.meshes.count * size_of(Scene_Mesh));
    memcpy(meshlet_meshes.cpu.data, geo.meshlet_meshes.cpu.data, geo.meshlet_meshes.cpu.count * size_of(Scene_Meshlet_Mesh));
    memcpy(meshlets.cpu.data, geo.meshlets.cpu.data, geo.meshlets.cpu.count * size_of(Scene_Meshlet));
    memcpy(meshlet_vertices.cpu.data, geo.meshlet_vertices.cpu.data, geo.meshlet_vertices.cpu.count * size_of(u32));
    memcpy(meshlet_triangles.cpu.data, geo.meshlet_triangles.cpu.data, geo.meshlet_triangles.cpu.count * size_of(u32));
    memcpy(meshlet_bounds.cpu.data, geo.meshlet_bounds.cpu.data, geo.meshlet_bounds.cpu.count * size_of(Vector4));

    array_copy(*batches, temp_batches);
    for temp_instances {
        instances.cpu[it_index] = .{world = it.world};
    }
    for batches {
        mesh := geo.meshes[it.mesh_index];
        meshlet_mesh := geo.meshlet_meshes.cpu[it.mesh_index];
        log("blender_scene batch mesh=% idx_count=% verts=% meshlets=% lods=% material=%",
            it.mesh_index, mesh.index_count, mesh.vertex_count, meshlet_mesh.meshlet_count, mesh.lod_mesh_count, mesh.material_index);
    }
}

update_watched_export_state :: () {
    watched_export_modtime, watched_export_size, _ = file_modtime_and_size(export_path);
}

poll_for_blender_scene_changes :: () {
    reload_poll_accum += editor_dt;
    if reload_poll_accum < BLENDER_SCENE_POLL_SECONDS return;
    reload_poll_accum = 0.0;

    modtime, size, exists := file_modtime_and_size(export_path);
    if !exists return;
    if modtime == watched_export_modtime && size == watched_export_size return;

    log("blender_scene detected updated export: %", export_path);
    load_blender_scene(first_load=false);
}

mesh_max_meshlet_count :: (mesh_index: u32) -> u32 {
    mesh := geo.meshes[mesh_index];
    result := geo.meshlet_meshes.cpu[mesh_index].meshlet_count;
    if mesh.lod_mesh_count > 0 {
        for lod_offset: 0..mesh.lod_mesh_count-1 {
            lod_mesh_index := mesh.lod_mesh_start + lod_offset;
            result = max(result, geo.meshlet_meshes.cpu[lod_mesh_index].meshlet_count);
        }
    }
    return max(result, 1);
}

normalize_plane4 :: (p: Vector4) -> Vector4 {
    n := Vector3.{p.x, p.y, p.z};
    len := max(length(n), 0.000001);
    return p / len;
}

extract_frustum_planes :: (m: Matrix4) -> [6]Vector4 {
    // TODO: use m.v[3] etc
    row0 := Vector4.{m._11, m._12, m._13, m._14};
    row1 := Vector4.{m._21, m._22, m._23, m._24};
    row2 := Vector4.{m._31, m._32, m._33, m._34};
    row3 := Vector4.{m._41, m._42, m._43, m._44};
    return .[
        normalize_plane4(row3 + row0),
        normalize_plane4(row3 - row0),
        normalize_plane4(row3 + row1),
        normalize_plane4(row3 - row1),
        normalize_plane4(row3 + row2),
        normalize_plane4(row3 - row2),
    ];
}

hdri_path_compare :: (a: string, b: string) -> int {
    return cast(int) Sort.compare_strings(a, b);
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

#load "../editor_camera.jai";
#load "../scene_geo.jai";
#import "KTX_Header";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
Process_Module :: #import "Process";
String :: #import "String";
File :: #import "File";
Hash :: #import "Hash";
File_Utilities :: #import "File_Utilities";
IntroSort :: #import "IntroSort";
Sort :: #import "Sort";
#import "Math";
using,only(getenv) POSIX_Getenv :: #import "POSIX";
#load "shaders/hdri_background_shader.jai";
#load "shaders/meshlet_shader.jai";
