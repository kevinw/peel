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

HDRI_Cache_Assets :: struct {
    cache_dir: string;
    skybox_path: string;
    ibl_path: string;
    dfg_path: string;
    sh_path: string;
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
    depth_textures: [MAX_FRAMES_IN_FLIGHT]Gpu_Texture;
    depth_views: [MAX_FRAMES_IN_FLIGHT]Gpu_Texture_View;
    depth_w: u32;
    depth_h: u32;
    geo: Scene_Geo;
    arena: Gpu_Arena;
    hdri_params: [MAX_FRAMES_IN_FLIGHT]Gpu_Buffer(HDRI_Background_Params);
    hdri_skybox: Sampled_Texture;
    hdri_ibl: Sampled_Texture;
    hdri_dfg: Sampled_Texture;
    hdri_sampler: Gpu_Sampler;
    hdri_enabled: bool = true;
    hdri_candidates: [..]string;
    hdri_index: s32 = -1;
    hdri_source_path: string;
    hdri_cache_dir: string;
    hdri_exposure: float = 1.0;
    hdri_ibl_mip_count: float;
    hdri_sh_coeffs: [9]Vector4;
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
    if hdri_cache_dir.count != 0 free(hdri_cache_dir);
    for hdri_candidates free(it);
    array_free(hdri_candidates);
    for *depth_textures if it.* != 0 gpu_free(it.*);
    for *hdri_params if it.gpu != 0 gpu_delete(it);
    gpu_delete(*hdri_sampler);
    gpu_delete(*hdri_dfg);
    gpu_delete(*hdri_ibl);
    gpu_delete(*hdri_skybox);
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
    depth_slot := cast(s64) (gpu_submission_frame_index() % MAX_FRAMES_IN_FLIGHT);
    depth_view := depth_views[depth_slot];
    assert(depth_view != 0, "Depth view missing for slot %", depth_slot);

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
    hdri_params_slot := hdri_params[depth_slot];
    if hdri_enabled && hdri_skybox.view != 0 && hdri_sampler != 0 && hdri_params_slot.cpu != null {
        cam_forward, cam_right, cam_up: Vector3;
        editor_camera_basis(camera, *cam_forward, *cam_right, *cam_up);
        hdri_params_slot.cpu.camera_right_proj_x = .{cam_right.x, cam_right.y, cam_right.z, proj._11};
        hdri_params_slot.cpu.camera_up_proj_y = .{cam_up.x, cam_up.y, cam_up.z, proj._22};
        hdri_params_slot.cpu.camera_forward_exposure = .{cam_forward.x, cam_forward.y, cam_forward.z, hdri_exposure};
        hdri_params_slot.cpu.skybox_texture_index = gpu_texture_view_index(hdri_skybox.view);
        hdri_params_slot.cpu.sampler_index = cast(u32) hdri_sampler - 1;

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, background_shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, hdri_params_slot.gpu, 3, 1);
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
                primary_params.cpu.ibl_texture_index = ifx hdri_enabled && hdri_ibl.view != 0 then gpu_texture_view_index(hdri_ibl.view) else SCENE_INVALID_TEXTURE_INDEX;
                primary_params.cpu.dfg_texture_index = ifx hdri_enabled && hdri_dfg.view != 0 then gpu_texture_view_index(hdri_dfg.view) else SCENE_INVALID_TEXTURE_INDEX;
                primary_params.cpu.ibl_max_lod = hdri_ibl_mip_count;
                primary_params.cpu.env_intensity = ifx hdri_enabled then hdri_exposure else 0.0;
                primary_params.cpu.env_sh0 = hdri_sh_coeffs[0];
                primary_params.cpu.env_sh1 = hdri_sh_coeffs[1];
                primary_params.cpu.env_sh2 = hdri_sh_coeffs[2];
                primary_params.cpu.env_sh3 = hdri_sh_coeffs[3];
                primary_params.cpu.env_sh4 = hdri_sh_coeffs[4];
                primary_params.cpu.env_sh5 = hdri_sh_coeffs[5];
                primary_params.cpu.env_sh6 = hdri_sh_coeffs[6];
                primary_params.cpu.env_sh7 = hdri_sh_coeffs[7];
                primary_params.cpu.env_sh8 = hdri_sh_coeffs[8];
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
    for i: 0..MAX_FRAMES_IN_FLIGHT-1 {
        hdri_params[i] = gpu_alloc_buffer(HDRI_Background_Params, label = tprint("blender scene hdri params %", i));
    }
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
    key_source := tprint("hdri|cmgen-v2|sky2048|ibl128|%|%|%:%", source_path, size, modtime.low, modtime.high);
    key_hash := Hash.fnv1a_hash(key_source.data, key_source.count);
    cache_dir := tprint("%/.build/texture_cache/hdri", find_workspace_root());
    return tprint("%/%", cache_dir, key_hash);
}

resolve_cmgen_executable :: () -> string {
    tool_name := "cmgen";
    result, stdout, stderr, timeout_reached := Process_Module.run_command(
        "which",
        tool_name,
        capture_and_return_output = true,
        working_directory = find_workspace_root(),
        timeout_ms = 2000);
    if !timeout_reached && result.type == .EXITED && result.exit_code == 0 {
        trimmed := String.trim(stdout);
        if trimmed.count != 0 && file_exists(trimmed) {
            if stdout.count != 0 free(stdout);
            if stderr.count != 0 free(stderr);
            return copy_string(trimmed);
        }
    }
    if stdout.count != 0 free(stdout);
    if stderr.count != 0 free(stderr);

    bundled := tprint("%/.build/tools/filament/v1.70.2/filament/bin/cmgen", find_workspace_root());
    if file_exists(bundled) return copy_string(bundled);
    return "";
}

ensure_hdri_cache :: (source_path: string) -> bool, HDRI_Cache_Assets {
    modtime, size, exists := file_modtime_and_size(source_path);
    if !exists {
        log_error("blender_scene: HDRI source does not exist: %", source_path);
        return false, .{};
    }

    cache_dir := hdri_cache_path_for_source(source_path, modtime, size);
    skybox_path := tprint("%/env/env_skybox.ktx", cache_dir);
    ibl_path := tprint("%/env/env_ibl.ktx", cache_dir);
    dfg_path := tprint("%/dfg.png", cache_dir);
    sh_path := tprint("%/env/sh.txt", cache_dir);
    assets := HDRI_Cache_Assets.{
        cache_dir = cache_dir,
        skybox_path = skybox_path,
        ibl_path = ibl_path,
        dfg_path = dfg_path,
        sh_path = sh_path,
    };

    _ = File.make_directory_if_it_does_not_exist(cache_dir, true);
    if file_exists(skybox_path) && file_exists(ibl_path) && file_exists(dfg_path) && file_exists(sh_path) {
        return true, assets;
    }

    cmgen := resolve_cmgen_executable();
    if cmgen.count == 0 {
        log_error("blender_scene: could not find cmgen. Install KTX/Filament tools or restore the bundled cmgen.");
        return false, assets;
    }

    result, stdout, stderr, timeout_reached := Process_Module.run_command(
        cmgen,
        "--quiet",
        tprint("--deploy=%/env", cache_dir),
        "--format=ktx",
        "--size=2048",
        source_path,
        capture_and_return_output = true,
        working_directory = find_workspace_root(),
        timeout_ms = 300000);

    if timeout_reached || result.type != .EXITED || result.exit_code != 0 {
        log_error("blender_scene: cmgen cubemap build failed for %", source_path);
        if stdout.count != 0 log_error("cmgen stdout:\n%", stdout);
        if stderr.count != 0 log_error("cmgen stderr:\n%", stderr);
        if stdout.count != 0 free(stdout);
        if stderr.count != 0 free(stderr);
        free(cmgen);
        return false, assets;
    }

    if stdout.count != 0 free(stdout);
    if stderr.count != 0 free(stderr);

    result, stdout, stderr, timeout_reached = Process_Module.run_command(
        cmgen,
        "--quiet",
        "--size=128",
        tprint("--ibl-dfg=%", dfg_path),
        source_path,
        capture_and_return_output = true,
        working_directory = find_workspace_root(),
        timeout_ms = 300000);
    free(cmgen);

    if timeout_reached || result.type != .EXITED || result.exit_code != 0 || !file_exists(skybox_path) || !file_exists(ibl_path) || !file_exists(dfg_path) || !file_exists(sh_path) {
        log_error("blender_scene: cmgen IBL/DFG build failed for %", source_path);
        if stdout.count != 0 log_error("cmgen stdout:\n%", stdout);
        if stderr.count != 0 log_error("cmgen stderr:\n%", stderr);
        if stdout.count != 0 free(stdout);
        if stderr.count != 0 free(stderr);
        return false, assets;
    }

    if stdout.count != 0 free(stdout);
    if stderr.count != 0 free(stderr);

    log("blender_scene: built HDRI cache % -> %", source_path, cache_dir);
    return true, assets;
}

gpu_format_from_ktx_pixel_format :: (pixel_format: MTLPixelFormat) -> Format {
    if pixel_format == {
    case .RG11B10Float; return .B10G11R11_UFLOAT_PACK32;
    case .RGBA8Unorm; return .R8G8B8A8_UNORM;
    case .RGBA8Unorm_sRGB; return .R8G8B8A8_SRGB;
    case; assert(false, "Unhandled KTX pixel format for HDRI cache: %", pixel_format); return .UNDEFINED;
    }
}

parse_hdri_sh_coeffs :: (path: string, coeffs: *[9]Vector4) -> bool {
    text, ok := File.read_entire_file(path, zero_terminated = false, log_errors = true);
    if !ok return false;
    defer free(text);

    lines := String.split(text, #char "\n");
    defer array_free(lines);
    coeff_index: s64 = 0;
    for line_raw: lines {
        line := String.trim(line_raw);
        if line.count == 0 continue;
        open_index := String.find_index_from_left(line, #char "(");
        close_index := String.find_index_from_left(line, #char ")");
        if open_index < 0 || close_index < 0 || close_index <= open_index continue;

        inside := String.slice(line, open_index + 1, close_index - (open_index + 1));
        parts := String.split(inside, #char ",");
        defer array_free(parts);
        if parts.count < 3 return false;

        x_cursor := String.trim(parts[0]);
        y_cursor := String.trim(parts[1]);
        z_cursor := String.trim(parts[2]);
        x, ok_x := String.parse_float(*x_cursor);
        y, ok_y := String.parse_float(*y_cursor);
        z, ok_z := String.parse_float(*z_cursor);
        if !ok_x || !ok_y || !ok_z return false;

        coeffs.*[coeff_index] = .{x, y, z, 0.0};
        coeff_index += 1;
        if coeff_index == coeffs.*.count break;
    }

    return coeff_index == coeffs.*.count;
}

load_texture_rgba8_file :: (path: string) -> Sampled_Texture {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer if pixels != null stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0, "Failed to load image: %", path);

    result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS, "Texture creation failed for %: %", path, result);
    gpu_copy_to_texture(texture, pixels);

    view := gpu_texture_view(texture);
    assert(view != 0, "Texture view creation failed for %", path);
    return .{
        texture = texture,
        view = view,
    };
}

load_cube_texture_from_ktx :: (path: string) -> Sampled_Texture, float {
    file_bytes, read_ok := File.read_entire_file(path, zero_terminated = false, log_errors = true);
    assert(read_ok, "blender_scene: failed reading KTX cache %", path);
    defer free(file_bytes);

    descriptor_ok, descriptor := ktx_load_descriptor(file_bytes, verbose = false);
    defer array_free(descriptor.levels);
    assert(descriptor_ok, "blender_scene: failed parsing KTX cache %", path);
    assert(descriptor.faceCount == 6, "Expected cubemap faceCount=6 for %; got %", path, descriptor.faceCount);
    assert(descriptor.levels.count > 0, "Cubemap cache has no mip levels: %", path);

    result, texture := gpu_create_texture(.{
        type = .CUBE,
        dimensions = .[cast(u32) descriptor.pixelWidth, cast(u32) descriptor.pixelHeight, 1],
        layer_count = 1,
        format = gpu_format_from_ktx_pixel_format(descriptor.pixelFormat),
        mip_count = cast(u8) descriptor.levels.count,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS, "Cubemap texture creation failed for %: %", path, result);

    for descriptor.levels {
        for face: 0..descriptor.faceCount-1 {
            face_offset := it.fileOffset + cast(s64) face * it.faceStrideInBytes;
            gpu_copy_to_texture_layout(
                texture,
                file_bytes.data + face_offset,
                cast(u32) it.size.width,
                cast(u32) max(it.size.height, 1),
                1,
                it.bytesPerRow,
                it.bytesPerImage,
                cast(u32) it_index,
                face);
        }
    }

    view := gpu_texture_view(texture);
    assert(view != 0, "Cubemap view creation failed for %", path);
    return .{
        texture = texture,
        view = view,
    }, cast(float) max(descriptor.levels.count - 1, 0);
}

load_hdri_background_texture :: (source_path: string) -> bool {
    ok, assets := ensure_hdri_cache(source_path);
    if !ok return false;

    sh_coeffs: [9]Vector4;
    coeff_ok := parse_hdri_sh_coeffs(assets.sh_path, *sh_coeffs);
    assert(coeff_ok, "Failed parsing SH coefficients from %", assets.sh_path);

    skybox, _ := load_cube_texture_from_ktx(assets.skybox_path);
    ibl, ibl_max_lod := load_cube_texture_from_ktx(assets.ibl_path);
    dfg := load_texture_rgba8_file(assets.dfg_path);

    gpu_delete(*hdri_dfg);
    gpu_delete(*hdri_ibl);
    gpu_delete(*hdri_skybox);

    hdri_dfg = dfg;
    hdri_ibl = ibl;
    hdri_skybox = skybox;
    hdri_ibl_mip_count = ibl_max_lod;
    hdri_sh_coeffs = sh_coeffs;

    if hdri_cache_dir.count != 0 free(hdri_cache_dir);
    hdri_cache_dir = copy_string(assets.cache_dir);
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
    if depth_views[0] != 0 && depth_w == width && depth_h == height return;

    for i: 0..MAX_FRAMES_IN_FLIGHT-1 {
        if depth_textures[i] != 0 gpu_free(depth_textures[i]);
        depth_textures[i] = 0;
        depth_views[i] = 0;

        res, depth_texture := gpu_create_texture(.{
            dimensions = .[width, height, 1],
            format = .D32_SFLOAT,
            usage = .DEPTH_STENCIL_ATTACHMENT,
        });
        assert(res == .SUCCESS, "Depth texture creation failed for slot %: %", i, res);
        depth_textures[i] = depth_texture;
        depth_views[i] = gpu_texture_view(depth_texture);
        assert(depth_views[i] != 0, "Depth view creation failed for slot %", i);
    }
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
