#load "../linear_present.jai";
#load "shaders/material_lab_shader.jai";

Tex :: enum s64 {
    GROUND_ALBEDO_SRGB   :: 0;
    GROUND_ALBEDO_LINEAR :: 1;
    SNOW_ALBEDO_SRGB     :: 2;
    SNOW_ALBEDO_LINEAR   :: 3;
    GROUND_NORMAL        :: 4;
    GROUND_ROUGHNESS     :: 5;
    GROUND_AO            :: 6;
    SNOW_NORMAL          :: 7;
    SNOW_ROUGHNESS       :: 8;
    SNOW_AO              :: 9;
    COUNT                :: 10;
}

MATERIAL_LAB_OBJ_COUNT :: 7;

Material_Lab_Geometry :: enum s64 {
    SPHERE;
    TORUS;
    PRISM;
    CONE;
    CYLINDER;
    FLOOR;
    COUNT;
}

Material_Lab_Object :: struct {
    name: string;
    geometry: Material_Lab_Geometry;
    position: Vector3;
    scale: Vector3;
    albedo_index: u32;
    normal_index: u32;
    roughness_index: u32;
    ao_index: u32;
    tint: Vector3;
    metallic: float;
    roughness_bias: float;
    ao_strength: float;
    normal_strength: float;
    emissive_strength: float;
    uv_scale: float;
}

material_lab_shader: Shader(material_lab_vertex_main, material_lab_fragment_main, .{ cull = .CCW }); @init

gpu_arena: Gpu_Arena;
material_lab_camera: Editor_Camera = .{
    position = .{0.0, 3.3, 10.2},
    yaw = 0.0,
    pitch = -0.22,
    move_speed = 4.0,
    boost_multiplier = 2.5,
    mouse_sensitivity = 0.0056,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

material_lab_vertices: Gpu_View(Procedural_Geometry_Vertex);
material_lab_indices: Gpu_View(u32);
material_lab_meshes: [Material_Lab_Geometry.COUNT]Procedural_Geometry_Mesh_Range;
material_lab_draw_params: Gpu_Frame_Param_Allocator(Material_Lab_Params_CPU);
material_lab_textures: [Tex.COUNT]Sampled_Texture;
material_lab_sampler: Gpu_Sampler;
material_lab_depth: Texture_Ring;
material_lab_present: Linear_Present_State;
material_lab_objects: [MATERIAL_LAB_OBJ_COUNT]Material_Lab_Object;
material_lab_gizmo_ctx: Gizmo.Gizmo_Context;
material_lab_gizmo_render_ctx: Gizmo_Render.Gizmo_Render_Context;

constants: Material_Lab_Constants;
material_lab_use_normal_map := true;
material_lab_draw_vertex_normals := false;
material_lab_vertex_normal_length: float = 0.18;
material_lab_auto_orbit := false;
material_lab_orbit_time: float;
material_lab_exposure: float = 1.02;
material_lab_light_yaw: float = 2.38;
material_lab_light_pitch: float = -0.72;
material_lab_light_intensity: float = 7.21;

on_dll_init :: () {
    gpu_arena = gpu_make_arena(2 * 1024 * 1024, label = "material lab arena");
    material_lab_draw_params = sgpu_make_frame_param_allocator(*gpu_arena, Material_Lab_Params_CPU, MATERIAL_LAB_OBJ_COUNT);

    assert(linear_present_init(*material_lab_present, "material lab present"), "Failed to init material_lab present.");
    Gizmo.init(*material_lab_gizmo_ctx);
    gizmo_ok := Gizmo_Render.init(*material_lab_gizmo_render_ctx, max_lines = 65536);
    assert(gizmo_ok, "Failed to init material_lab gizmo renderer.");
    Gizmo_Render.bind_gizmo(*material_lab_gizmo_render_ctx, *material_lab_gizmo_ctx);

    build_geometry();
    init_textures();
    init_objects();

    material_lab_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .LINEAR,
        address_mode_u = .REPEAT,
        address_mode_v = .REPEAT,
        address_mode_w = .REPEAT,
    });
    assert(material_lab_sampler != 0, "Failed to create material_lab sampler.");

    editor_camera_set_look_at(*material_lab_camera, .{0.0, 0.8, 0.0});

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    gpu_delete(*material_lab_depth);
    gpu_delete(*material_lab_sampler);
    for *material_lab_textures gpu_delete(it);
    linear_present_deinit(*material_lab_present);
    gpu_delete(*material_lab_shader.pipeline);
    Gizmo_Render.deinit(*material_lab_gizmo_render_ctx);
    Gizmo.deinit(*material_lab_gizmo_ctx);
    gpu_free_arena(gpu_arena);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    game_mx, game_my, game_mouse_ok := app_game_view_mouse_pos_pixels();
    width, height := app_current_render_dimensions();
    if width == 0 || height == 0 return;
    if !linear_present_ensure_color_target(*material_lab_present, width, height) return;
    assert(ensure_texture_ring(*material_lab_depth, .{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    }), "Failed to ensure material_lab depth ring.");
    gpu_commit_residency();

    io := ImGui.GetIO();
    app_mx := ifx app_should_render_to_game_view() then game_mx else mx;
    app_my := ifx app_should_render_to_game_view() then game_my else my;
    app_mouse_ok := ifx app_should_render_to_game_view() then game_mouse_ok else mouse_ok;
    app_mouse_allowed := ifx app_should_render_to_game_view() then game_mouse_ok else !io.WantCaptureMouse;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    _ = editor_camera_update(*material_lab_camera, cast(float) dt, app_mx, app_my, app_mouse_ok,
        allow_move = !io.WantTextInput,
        allow_look = right_down && app_mouse_allowed,
        allow_zoom = app_mouse_allowed);

    if material_lab_auto_orbit {
        material_lab_orbit_time += cast(float) editor_dt;
        radius := 10.0;
        material_lab_camera.position = .{
            sin(material_lab_orbit_time * 0.33) * radius, 3.8, cos(material_lab_orbit_time * 0.33) * radius,
        };
        editor_camera_set_look_at(*material_lab_camera, .{0.0, 0.6, 0.0});
    }

    aspect := cast(float) width / cast(float) height;
    view := editor_camera_make_view(*material_lab_camera);
    proj := editor_camera_make_projection(*material_lab_camera, aspect, 0.05, 80.0);
    view_proj := proj * view;

    light_dir := Vector3.{
        cos(material_lab_light_pitch) * sin(material_lab_light_yaw),
        sin(material_lab_light_pitch),
        cos(material_lab_light_pitch) * cos(material_lab_light_yaw),
    };
    normalize(*light_dir, fallback = .{0.25, -0.75, 0.55});
    light_pos := -light_dir * 6.0 + .{0.0, 3.0, 0.0};
    Gizmo.begin_frame(*material_lab_gizmo_ctx);
    Gizmo.draw_sphere(*material_lab_gizmo_ctx, light_pos, 0.22, color = .{1.0, 0.92, 0.36, 0.95}, thickness = 2.0, segments = 28);
    if material_lab_draw_vertex_normals {
        normal_color := Vector4.{0.20, 0.95, 0.45, 0.90};
        for object: material_lab_objects {
            mesh := material_lab_meshes[object.geometry];
            model := make_translation_matrix4(object.position);
            model = scale(model, object.scale);

            for index_offset: 0..cast(s64) mesh.index_count - 1 {
                vertex_index := material_lab_indices.cpu[mesh.first_index + cast(u32) index_offset];
                vertex := material_lab_vertices.cpu[vertex_index];
                world_pos4 := model * vertex.position;
                world_normal4 := model * Vector4.{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0.0};
                world_normal := normalize(world_normal4.xyz, fallback = .{0.0, 1.0, 0.0});
                line_start := world_pos4.xyz;
                line_end := line_start + world_normal * material_lab_vertex_normal_length;
                Gizmo.draw_line(*material_lab_gizmo_ctx, line_start, line_end, color = normal_color, thickness = 1.0);
            }
        }
    }
    Gizmo_Render.gizmo_render_set_view_projection(*material_lab_gizmo_render_ctx, view_proj);

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    scene_pass_desc := Gpu_Render_Pass_Desc.{
        depth_target = .{
            view = texture_ring_current_view(*material_lab_depth),
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{depth = 1.0, stencil = 0},
        },
        color_targets = .[
            .{
                view = linear_present_current_color_view(*material_lab_present),
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.025, 0.03, 1.0],
            }
        ],
    };

    {
        gpu_begin_scoped_render_pass(cmd_buff, scene_pass_desc, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, pipeline(*material_lab_shader, scene_pass_desc, constants));

        for object, object_index: material_lab_objects {
            mesh := material_lab_meshes[object.geometry];
            model := make_translation_matrix4(object.position);
            model = scale(model, object.scale);
            use_normal_map_flag: u32;
            if material_lab_use_normal_map {
                use_normal_map_flag = 1;
            }

            params := sgpu_frame_param_alloc(*material_lab_draw_params, {
                vertices = material_lab_vertices.gpu,
                indices = material_lab_indices.gpu + cast(Gpu_Ptr) mesh.first_index * size_of(u32),
                view_proj = view_proj,
                model = model,
                albedo_index = object.albedo_index,
                normal_index = object.normal_index,
                roughness_index = object.roughness_index,
                ao_index = object.ao_index,
                sampler_index = cast(u32) material_lab_sampler - 1,
                use_normal_map = use_normal_map_flag,
                camera_pos = material_lab_camera.position,
                metallic = object.metallic,
                base_color_tint = object.tint,
                emissive_strength = object.emissive_strength,
                light_dir = light_dir,
                light_intensity = material_lab_light_intensity,
                light_color = .{1.0, 0.97, 0.92},
                roughness_bias = object.roughness_bias,
                ao_strength = object.ao_strength,
                normal_strength = object.normal_strength,
                uv_scale = object.uv_scale,
            });

            draw_result := gpu_draw_instanced_direct(cmd_buff, params.gpu, mesh.index_count, 1);
            assert(draw_result == .SUCCESS, "material_lab draw failed for object % (%): %", object_index, object.name, draw_result);
        }

        viewport := Vector2.{cast(float) width, cast(float) height};
        gizmo_draw_result := Gizmo_Render.gizmo_render_draw(*material_lab_gizmo_render_ctx, cmd_buff, *material_lab_gizmo_ctx, viewport, depth_mode = .TEST);
        assert(gizmo_draw_result == .SUCCESS, "material_lab gizmo draw failed: %", gizmo_draw_result);
    }

    material_lab_present.exposure = material_lab_exposure;
    linear_present_present(cmd_buff, *material_lab_present, swapchain_image);

    show_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

build_geometry :: () {
    vertices_cpu: [..]Procedural_Geometry_Vertex;
    indices_cpu: [..]u32;
    vertices_cpu.allocator = temp;
    indices_cpu.allocator = temp;

    material_lab_meshes[Material_Lab_Geometry.SPHERE] = procedural_append_uv_sphere(*vertices_cpu, *indices_cpu, 0.92, 32, 18);
    material_lab_meshes[Material_Lab_Geometry.TORUS] = procedural_append_torus(*vertices_cpu, *indices_cpu, 0.84, 0.26, 36, 18);
    material_lab_meshes[Material_Lab_Geometry.PRISM] = procedural_append_prism(*vertices_cpu, *indices_cpu, 0.95, 0.95, 6);
    material_lab_meshes[Material_Lab_Geometry.CONE] = procedural_append_cone(*vertices_cpu, *indices_cpu, 0.82, 2.1, 28);
    material_lab_meshes[Material_Lab_Geometry.CYLINDER] = procedural_append_cylinder(*vertices_cpu, *indices_cpu, 0.8, 1.0, 28);
    material_lab_meshes[Material_Lab_Geometry.FLOOR] = procedural_append_plane(*vertices_cpu, *indices_cpu, 8.0);

    material_lab_vertices = gpu_alloc_view(*gpu_arena, Procedural_Geometry_Vertex, vertices_cpu.count);
    material_lab_indices = gpu_alloc_view(*gpu_arena, u32, indices_cpu.count);
    memcpy(material_lab_vertices.cpu.data, vertices_cpu.data, vertices_cpu.count * size_of(Procedural_Geometry_Vertex));
    memcpy(material_lab_indices.cpu.data, indices_cpu.data, indices_cpu.count * size_of(u32));
}

init_textures :: () {
    material_lab_textures[Tex.GROUND_ALBEDO_SRGB] = load_cached_sampled_texture_2d(
        "textures/Ground104_1K-JPG/Ground104_1K-JPG_Color.jpg",
        .{format = .BC7_SRGB, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.GROUND_ALBEDO_LINEAR] = load_cached_sampled_texture_2d(
        "textures/Ground104_1K-JPG/Ground104_1K-JPG_Color.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.SNOW_ALBEDO_SRGB] = load_cached_sampled_texture_2d(
        "textures/Snow/Snow015_2K-JPG_Color.jpg",
        .{format = .BC7_SRGB, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.SNOW_ALBEDO_LINEAR] = load_cached_sampled_texture_2d(
        "textures/Snow/Snow015_2K-JPG_Color.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.GROUND_NORMAL] = load_cached_sampled_texture_2d(
        "textures/Ground104_1K-JPG/Ground104_1K-JPG_NormalGL.jpg",
        .{format = .BC5_UNORM, generate_mips = true, normal_mode = true, uastc_quality = "medium"});
    material_lab_textures[Tex.GROUND_ROUGHNESS] = load_cached_sampled_texture_2d(
        "textures/Ground104_1K-JPG/Ground104_1K-JPG_Roughness.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.GROUND_AO] = load_cached_sampled_texture_2d(
        "textures/Ground104_1K-JPG/Ground104_1K-JPG_AmbientOcclusion.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.SNOW_NORMAL] = load_cached_sampled_texture_2d(
        "textures/Snow/Snow015_2K-JPG_NormalGL.jpg",
        .{format = .BC5_UNORM, generate_mips = true, normal_mode = true, uastc_quality = "medium"});
    material_lab_textures[Tex.SNOW_ROUGHNESS] = load_cached_sampled_texture_2d(
        "textures/Snow/Snow015_2K-JPG_Roughness.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
    material_lab_textures[Tex.SNOW_AO] = load_cached_sampled_texture_2d(
        "textures/Snow/Snow015_2K-JPG_AmbientOcclusion.jpg",
        .{format = .BC7_UNORM, generate_mips = true, uastc_quality = "medium"});
}

init_objects :: () {
    view_idx :: (tex: Tex) -> u32 {
        return gpu_texture_view_index(material_lab_textures[tex].view);
    }

    material_lab_objects[0] = .{
        name = "Ground SRGB Sphere",
        geometry = .SPHERE,
        position = .{-5.4, 1.05, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.GROUND_ALBEDO_SRGB),
        normal_index = view_idx(.GROUND_NORMAL),
        roughness_index = view_idx(.GROUND_ROUGHNESS),
        ao_index = view_idx(.GROUND_AO),
        tint = .{1.0, 1.0, 1.0},
        metallic = 0.04,
        roughness_bias = 0.0,
        ao_strength = 1.0,
        normal_strength = 1.0,
        emissive_strength = 0.0,
        uv_scale = 3.0,
    };
    material_lab_objects[1] = .{
        name = "Ground Linear Torus",
        geometry = .TORUS,
        position = .{-3.2, 1.15, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.GROUND_ALBEDO_LINEAR),
        normal_index = view_idx(.GROUND_NORMAL),
        roughness_index = view_idx(.GROUND_ROUGHNESS),
        ao_index = view_idx(.GROUND_AO),
        tint = .{1.0, 1.0, 1.0},
        metallic = 0.04,
        roughness_bias = 0.0,
        ao_strength = 1.0,
        normal_strength = 1.0,
        emissive_strength = 0.0,
        uv_scale = 3.0,
    };
    material_lab_objects[2] = .{
        name = "Snow SRGB Prism",
        geometry = .PRISM,
        position = .{-1.05, 1.0, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.SNOW_ALBEDO_SRGB),
        normal_index = view_idx(.SNOW_NORMAL),
        roughness_index = view_idx(.SNOW_ROUGHNESS),
        ao_index = view_idx(.SNOW_AO),
        tint = .{1.0, 1.0, 1.0},
        metallic = 0.0,
        roughness_bias = 0.0,
        ao_strength = 1.0,
        normal_strength = 1.0,
        emissive_strength = 0.0,
        uv_scale = 2.4,
    };
    material_lab_objects[3] = .{
        name = "Snow Linear Cone",
        geometry = .CONE,
        position = .{1.1, 1.05, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.SNOW_ALBEDO_LINEAR),
        normal_index = view_idx(.SNOW_NORMAL),
        roughness_index = view_idx(.SNOW_ROUGHNESS),
        ao_index = view_idx(.SNOW_AO),
        tint = .{1.0, 1.0, 1.0},
        metallic = 0.0,
        roughness_bias = 0.0,
        ao_strength = 1.0,
        normal_strength = 1.0,
        emissive_strength = 0.0,
        uv_scale = 2.4,
    };
    material_lab_objects[4] = .{
        name = "Copper Cylinder",
        geometry = .CYLINDER,
        position = .{3.3, 1.05, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.GROUND_ALBEDO_SRGB),
        normal_index = view_idx(.GROUND_NORMAL),
        roughness_index = view_idx(.GROUND_ROUGHNESS),
        ao_index = view_idx(.GROUND_AO),
        tint = .{1.0, 0.62, 0.34},
        metallic = 0.92,
        roughness_bias = -0.15,
        ao_strength = 1.0,
        normal_strength = 0.75,
        emissive_strength = 0.0,
        uv_scale = 2.8,
    };
    material_lab_objects[5] = .{
        name = "Emissive Orb",
        geometry = .SPHERE,
        position = .{5.5, 1.0, 0.0},
        scale = .{0.95, 0.95, 0.95},
        albedo_index = view_idx(.SNOW_ALBEDO_SRGB),
        normal_index = view_idx(.SNOW_NORMAL),
        roughness_index = view_idx(.SNOW_ROUGHNESS),
        ao_index = view_idx(.SNOW_AO),
        metallic = 0.0,
        roughness_bias = 0.35,
        ao_strength = 0.6,
        normal_strength = 0.4,
        emissive_strength = 1.8,
        uv_scale = 2.0,
    };
    material_lab_objects[6] = .{
        name = "Floor",
        geometry = .FLOOR,
        position = .{0.0, -0.1, 0.0},
        scale = .{1.0, 1.0, 1.0},
        albedo_index = view_idx(.GROUND_ALBEDO_SRGB),
        normal_index = view_idx(.GROUND_NORMAL),
        roughness_index = view_idx(.GROUND_ROUGHNESS),
        ao_index = view_idx(.GROUND_AO),
        tint = .{0.9, 0.92, 0.96},
        metallic = 0.0,
        roughness_bias = 0.05,
        ao_strength = 1.0,
        normal_strength = 1.0,
        emissive_strength = 0.0,
        uv_scale = 6.5,
    };
}

show_ui :: () {
    if !app_ui_enabled return;
    Persist :: #import,file "../ui/persist_controls.jai";

    using ImGui;
    if Begin("Material Lab", flags = .AlwaysAutoResize) {
        Text("RMB look, WASDQE move");
        Checkbox("Auto Orbit", *material_lab_auto_orbit);
        Checkbox("Use Normal Maps", *material_lab_use_normal_map);
        Checkbox("Draw Vertex Normals", *material_lab_draw_vertex_normals);
        if material_lab_draw_vertex_normals {
            Persist.SliderFloat("Normal Gizmo Length", *material_lab_vertex_normal_length, 0.02, 0.5, "%.2f");
        }
        Persist.SliderFloat("Exposure", *material_lab_exposure, 0.2, 3.0, "%.2f");
        Persist.SliderFloat("Light Yaw", *material_lab_light_yaw, -PI, PI, "%.2f");
        Persist.SliderFloat("Light Pitch", *material_lab_light_pitch, -2.45, 2.05, "%.2f");
        Persist.SliderFloat("Light Intensity", *material_lab_light_intensity, 0.5, 20.0, "%.2f");
        Separator();
        Text("Debug View");
        inspect("Debug Mode", *constants.debug_mode);
        Separator();
        Text("Left to right:");
        BulletText("Ground albedo loaded as sRGB");
        BulletText("Same ground albedo loaded as linear");
        BulletText("Snow albedo loaded as sRGB");
        BulletText("Same snow albedo loaded as linear");
        BulletText("Metallic copper-tinted cylinder");
        BulletText("Emissive orb");
    }
    End();
}

material_lab_texture_cache_path :: (source_path: string, options: Texture_Cache_Options) -> string {
    modtime, size, exists := file_modtime_and_size(source_path);
    assert(exists, "material_lab texture source missing: %", source_path);
    key := tprint("material_lab_texture|v1|%|%:%|%|fmt=%|mips=%|normal=%|quality=%",
        source_path, modtime.low, modtime.high, size, options.format, options.generate_mips, options.normal_mode, options.uastc_quality);
    cache_hash := Hash.fnv1a_hash(key.data, key.count);
    cache_dir := cache_subdir_path(".build/texture_cache/material_lab");
    return tprint("%/%.ktx2", cache_dir, cache_hash);
}

material_lab_format_from_ktx_pixel_format :: (pixel_format: MTLPixelFormat) -> Format {
    if pixel_format == {
    case .RGBA8Unorm; return .R8G8B8A8_UNORM;
    case .RGBA8Unorm_sRGB; return .R8G8B8A8_SRGB;
    case .BC5_RGUnorm; return .BC5_UNORM_BLOCK;
    case .BC7_RGBAUnorm; return .BC7_UNORM_BLOCK;
    case .BC7_RGBAUnorm_sRGB; return .BC7_SRGB_BLOCK;
    }
    assert(false, "material_lab: unsupported KTX pixel format %", pixel_format);
    return .UNDEFINED;
}

create_sampled_texture_from_ktx_2d :: (path: string) -> Sampled_Texture {
    file_bytes, read_ok := File.read_entire_file(path, zero_terminated = false, log_errors = true);
    assert(read_ok, "material_lab: failed reading KTX cache %", path);
    defer free(file_bytes);

    descriptor_ok, descriptor := ktx_load_descriptor(file_bytes, verbose = false);
    defer array_free(descriptor.levels);
    assert(descriptor_ok, "material_lab: failed parsing KTX cache %", path);
    assert(descriptor.faceCount == 1, "material_lab: expected 2D KTX cache, got faceCount=% for %", descriptor.faceCount, path);
    assert(descriptor.levels.count > 0, "material_lab: KTX cache has no mip levels: %", path);

    result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) descriptor.pixelWidth, cast(u32) descriptor.pixelHeight, 1],
        format = material_lab_format_from_ktx_pixel_format(descriptor.pixelFormat),
        mip_count = cast(u8) descriptor.levels.count,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS && texture != 0, "material_lab: texture creation failed for %: %", path, result);

    for descriptor.levels {
        gpu_copy_to_texture_layout(
            texture,
            file_bytes.data + it.fileOffset,
            cast(u32) it.size.width,
            cast(u32) max(it.size.height, 1),
            1,
            it.bytesPerRow,
            it.bytesPerImage,
            cast(u32) it_index,
            0);
    }

    view := gpu_texture_view(texture);
    assert(view != 0, "material_lab: texture view creation failed for %", path);
    return .{texture = texture, view = view};
}

load_cached_sampled_texture_2d :: (source_path: string, options: Texture_Cache_Options) -> Sampled_Texture {
    cache_path := material_lab_texture_cache_path(source_path, options);
    cache_ok := ensure_ktx_texture_cache_from_file(source_path, cache_path, options, "material_lab");
    assert(cache_ok, "material_lab: failed to build KTX texture cache for %", source_path);
    return create_sampled_texture_from_ktx_2d(cache_path);
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#import "Procedural_Geometry";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
Hash :: #import "Hash";
File_Utilities :: #import "File_Utilities";
using File_Utilities;
KTX_Header :: #import "KTX_Header";
using KTX_Header;
ImGui :: #import "ImGui";
Input :: #import "Input";
Gizmo :: #import "Gizmo";
Gizmo_Render :: #import "Gizmo_Render";
