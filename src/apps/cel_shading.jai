Cel_Scene_Params :: struct {
    vertices: *Procedural_Geometry_Vertex;
    indices: *u32;
    view_proj: Matrix4;
    model: Matrix4;
    camera_pos: Vector3;
    outline_thickness: float;
    light_dir: Vector3;
    posterize_steps: float;
    base_color: Vector4;
    time: float;
    scene_ambient: Vector4;
    ink_color: Vector4;
}

Cel_Sky_Params :: struct {
    camera_right: Vector4;
    camera_up: Vector4;
    camera_forward: Vector4;
    light_dir: Vector4;
    horizon_color: Vector4;
    zenith_color: Vector4;
    sun_color: Vector4;
    resolution_time: Vector4;
    sky_params: Vector4;
}

Cel_Post_Params :: struct {
    scene_texture_index: u32;
    edge_texture_index: u32;
    sampler_index: u32;
    _pad0: u32;
    resolution: Vector2;
    outline_thickness: float;
    _pad1: float;
    ink_color: Vector4;
}

Cel_Scene_Params_CPU :: CPU_Struct(Cel_Scene_Params);

Cel_Draw_Data :: struct {
    params_gpu: Gpu_Ptr;
    vertex_count: u32;
}

Cel_Object :: struct {
    mesh: Procedural_Geometry_Mesh_Range;
    position: Vector3;
    scale: float;
    rotation_axis: Vector3;
    spin_deg_per_sec: float;
    phase: float;
    color: Vector4;
}

Cel_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Cel_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4;
    clip_depth: float;
}

Cel_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4;
    clip_depth: float;
}


Cel_Sky_Fragment_In :: struct {
    uv: Vector2;
}

app: struct {
    sky_shader: Shader(fullscreen_tri_vert, cel_sky_fragment_main, {
        cull = .NONE,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    scene_shader: Shader(cel_vertex_main, cel_fragment_main, {
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    edge_shader: Shader(cel_vertex_main, cel_edge_fragment_main, {
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    composite_shader: Shader(fullscreen_tri_vert, cel_composite_fragment_main, {
        cull = .NONE,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    gpu_arena: Gpu_Arena;
    draw_params: Gpu_Frame_Param_Allocator(Cel_Scene_Params_CPU);
    sky_params: Gpu_Frame_Param_Allocator(Cel_Sky_Params);
    post_params: Gpu_Frame_Param_Allocator(Cel_Post_Params);

    geometry_vertices: Gpu_View(Procedural_Geometry_Vertex);
    geometry_indices: Gpu_View(u32);

    scene_texture: Gpu_Texture;
    scene_view: Gpu_Texture_View;
    edge_texture: Gpu_Texture;
    edge_view: Gpu_Texture_View;
    composite_sampler: Gpu_Sampler;

    depth_texture: Gpu_Texture;
    depth_view: Gpu_Texture_View;
    depth_w: u32;
    depth_h: u32;

    camera: Editor_Camera = .{
        position = .{0.0, 3.8, 11.0},
        yaw = 0.0,
        pitch = -0.22,
        move_speed = 9.0,
        boost_multiplier = 2.4,
        move_planar = true,
    };

    using draw: Cel_Scene_Params_CPU = .{
        outline_thickness = 3.0,
        posterize_steps = 3.0,
        light_dir = .{-0.347, -0.913, -0.219},
        scene_ambient = .{0.20, 0.20, 0.26, 0.0},
        ink_color = .{0.05, 0.05, 0.08, 1.0},
    };

    ui_open: bool = true;
    auto_orbit: bool = true;
    orbit_time: float;
    orbit_radius: float = 10.8;
    scene_center: Vector3 = .{0.0, 1.8, 0.0};

    floor_mesh: Procedural_Geometry_Mesh_Range;
    objects: [8]Cel_Object;
};

on_dll_init :: () {
    using app;
    SHR.init(*sky_shader);
    SHR.init(*scene_shader);
    SHR.init(*edge_shader);
    SHR.init(*composite_shader);

    build_scene_geometry();
    init_scene_objects();
    composite_sampler = gpu_create_sampler({ compare_op = .NEVER });

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    using app;
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;

    ensure_render_targets(cast(u32) win_w, cast(u32) win_h);

    allow_look := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    _ = editor_camera_update(*camera, editor_dt, mx, my, mouse_ok,
        allow_move = true,
        allow_look = allow_look,
        allow_zoom = true);

    if auto_orbit {
        orbit_time += editor_dt;
        camera.position = scene_center + .{
            sin(orbit_time * 0.42) * orbit_radius,
            4.6 + sin(orbit_time * 0.31) * 0.9,
            cos(orbit_time * 0.42) * orbit_radius,
        };
        editor_camera_set_look_at(*camera, scene_center + .{0.0, 1.1, 0.0});
    }

    aspect := cast(float) win_w / max(cast(float) win_h, 1.0);
    view := editor_camera_make_view(*camera);
    proj := editor_camera_make_projection(*camera, aspect, 0.05, 120.0);
    view_proj = proj * view;
    camera_forward := normalize(scene_center - camera.position);
    view_right := normalize(cross(camera_forward, camera.world_up));
    view_up := normalize(cross(view_right, camera_forward));
    current_time := cast(float) time;
    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    floor_model := make_translation_matrix4(.{0.0, -0.55, 0.0});

    {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            depth_target = .{
                view = depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{depth = 1.0, stencil = 0},
            },
            color_targets = .[
                .{
                    view = scene_view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.62, 0.76, 0.92, 1.0],
                }
            ]
        });

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, sky_shader.pipeline);
        sky := sgpu_frame_param_alloc(*sky_params);
        sky.cpu.* = .{
            camera_right = .{view_right.x, view_right.y, view_right.z, 0.0},
            camera_up = .{view_up.x, view_up.y, view_up.z, 0.0},
            camera_forward = .{camera_forward.x, camera_forward.y, camera_forward.z, 0.0},
            light_dir = .{draw.light_dir.x, draw.light_dir.y, draw.light_dir.z, 0.0},
            horizon_color = .{0.98, 0.76, 0.60, 1.0},
            zenith_color = .{0.24, 0.45, 0.84, 1.0},
            sun_color = .{1.0, 0.92, 0.76, 1.0},
            resolution_time = .{cast(float) win_w, cast(float) win_h, current_time, 0.0},
            sky_params = .{tan(camera.fov_y * 0.5), aspect, 0.18, 0.06},
        };
        gpu_draw_instanced_direct(cmd_buff, sky.gpu, 3, 1);

        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, scene_shader.pipeline);
        draw_scene_mesh(cmd_buff, floor_mesh, floor_model, .{0.24, 0.22, 0.28, 1.0}, view_proj, current_time);

        for object: objects {
            spin := quat_from_euler_deg(object.rotation_axis * (current_time * object.spin_deg_per_sec + object.phase));
            bob := sin(current_time * 0.9 + object.phase) * 0.16;
            model := make_trs_matrix(object.position + .{0.0, bob, 0.0}, spin, object.scale);
            draw_scene_mesh(cmd_buff, object.mesh, model, object.color, view_proj, current_time);
        }
    }

    {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            depth_target = .{
                view = depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{depth = 1.0, stencil = 0},
            },
            color_targets = .[
                .{
                    view = edge_view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.50, 0.50, 1.0, 1.0],
                }
            ]
        });
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
        gpu_set_pipeline(cmd_buff, edge_shader.pipeline);
        draw_scene_mesh(cmd_buff, floor_mesh, floor_model, .{0.24, 0.22, 0.28, 1.0}, view_proj, current_time);

        for object: objects {
            spin := quat_from_euler_deg(object.rotation_axis * (current_time * object.spin_deg_per_sec + object.phase));
            bob := sin(current_time * 0.9 + object.phase) * 0.16;
            model := make_trs_matrix(object.position + .{0.0, bob, 0.0}, spin, object.scale);
            draw_scene_mesh(cmd_buff, object.mesh, model, object.color, view_proj, current_time);
        }
    }

    gpu_begin_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.0, 0.0, 0.0, 1.0],
            }
            ]
        });
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, composite_shader.pipeline);
        post := sgpu_frame_param_alloc(*post_params);
    post.cpu.* = .{
        scene_texture_index = gpu_texture_view_index(scene_view),
        edge_texture_index = gpu_texture_view_index(edge_view),
        sampler_index = cast(u32) composite_sampler - 1,
        resolution = .{cast(float) win_w, cast(float) win_h},
        outline_thickness = draw.outline_thickness,
        ink_color = draw.ink_color,
    };
    gpu_draw_instanced_direct(cmd_buff, post.gpu, 3, 1);

    draw_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

cel_vertex_main :: (using in: Cel_Vertex_In, params: *Cel_Scene_Params) -> Cel_Vertex_Out {
    using out: Cel_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];

    local_pos := vertex.position;
    local_normal := vertex.normal;

    world_pos4 := params.model * local_pos;
    world_normal4 := params.model * local_normal;
    world_pos = world_pos4.xyz;
    normal = normalize(Vector3.{world_normal4.x, world_normal4.y, world_normal4.z});
    clip := params.view_proj * world_pos4;
    gl_Position = clip;
    base_color = params.base_color;
    clip_depth = clip.z / max(clip.w, 0.0001);
    return out;
} @vertex_shader

cel_fragment_main :: (using in: Cel_Fragment_In, params: *Cel_Scene_Params) -> Vector4 @SV_Target0 {
    N := normalize(normal);
    L := normalize(-params.light_dir);
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);

    ndl := max(dot(N, L), 0.0);
    ndh := max(dot(N, H), 0.0);
    steps := max(2.0, params.posterize_steps);
    lit_band := floor(ndl * steps) / max(1.0, steps - 1.0);
    spec_band := floor(pow(ndh, 20.0) * steps) / steps;
    rim := pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 2.5);

    ambient := params.scene_ambient.xyz;
    lit_color := base_color.xyz * (ambient + Vector3.{lit_band, lit_band, lit_band} * 0.86);
    lit_color += Vector3.{1, 1, 1} * 0.12 * spec_band;
    lit_color += base_color.xyz * (rim * 0.12);

    color := clamp(lit_color, 0.0, 1.0);
    return vec4(color, 1.0);
} @fragment_shader

cel_edge_fragment_main :: (using in: Cel_Fragment_In, params: *Cel_Scene_Params) -> Vector4 @SV_Target0 {
    n := normalize(normal) * 0.5 + .{0.5, 0.5, 0.5};
    depth01 := clamp(clip_depth * 0.5 + 0.5, 0.0, 1.0);
    return vec4(n, depth01);
} @fragment_shader

Cel_Composite_Fragment_In :: struct {
    uv: Vector2;
}

cel_composite_fragment_main :: (using in: Cel_Composite_Fragment_In, using params: *Cel_Post_Params) -> Vector4 @SV_Target0 {
    uv.y = 1.0 - uv.y;
    base := sample_2d(scene_texture_index, sampler_index, uv);
    texel := Vector2.{1.0 / max(resolution.x, 1.0), 1.0 / max(resolution.y, 1.0)};
    radius := max(1.0, outline_thickness);
    dx := Vector2.{texel.x * radius, 0.0};
    dy := Vector2.{0.0, texel.y * radius};

    base_r := sample_2d(scene_texture_index, sampler_index, uv + dx);
    base_l := sample_2d(scene_texture_index, sampler_index, uv - dx);
    base_u := sample_2d(scene_texture_index, sampler_index, uv + dy);
    base_d := sample_2d(scene_texture_index, sampler_index, uv - dy);

    center :=   sample_2d(edge_texture_index, sampler_index, uv);
    sample_r := sample_2d(edge_texture_index, sampler_index, uv + dx);
    sample_l := sample_2d(edge_texture_index, sampler_index, uv - dx);
    sample_u := sample_2d(edge_texture_index, sampler_index, uv + dy);
    sample_d := sample_2d(edge_texture_index, sampler_index, uv - dy);

    center_n := center.xyz;
    edge_n := max(max(length(center_n - sample_r.xyz),
                       length(center_n - sample_l.xyz)),
                  max(length(center_n - sample_u.xyz),
                       length(center_n - sample_d.xyz)));
    edge_d := max(max(abs(center.w - sample_r.w), abs(center.w - sample_l.w)),
                  max(abs(center.w - sample_u.w), abs(center.w - sample_d.w)));
    base_rgb := Vector3.{base.x, base.y, base.z};
    edge_c := max(max(length(base_rgb - base_r.xyz),
                       length(base_rgb - base_l.xyz)),
                  max(length(base_rgb - base_u.xyz),
                       length(base_rgb - base_d.xyz)));

    depth_edge := smoothstep(0.0015, 0.012, edge_d);
    normal_edge := smoothstep(0.18, 0.34, edge_n);
    edge := max(depth_edge, normal_edge * depth_edge);
    ink := params.ink_color;
    return lerp(base, ink, edge);
} @fragment_shader


CEL_SKY_HASH :: Vector2.{37.0, 157.0};

cel_sky_fragment_main :: (using in: Cel_Sky_Fragment_In, using params: *Cel_Sky_Params) -> Vector4 @SV_Target0 {
    resolution := resolution_time.xy;
    aspect := resolution.x / max(resolution.y, 1.0);
    tan_half_fov := params.sky_params.x;
    ndc := uv * 2 - 1;

    ray_dir := normalize(camera_forward.xyz + camera_right.xyz * (ndc.x * aspect * tan_half_fov) + camera_up.xyz * (ndc.y * tan_half_fov));
    up_mix := smoothstep(-0.15, 0.75, ray_dir.y);
    color := horizon_color + (zenith_color - horizon_color) * up_mix;

    cloud_wave := sin(ray_dir.x * 5.4 + params.resolution_time.z * 0.12) + cos(ray_dir.z * 6.9 - params.resolution_time.z * 0.08);
    cloud_band := smoothstep(0.52, 0.95, cloud_wave * 0.25 + 0.5 - ray_dir.y * 0.18);
    color.xyz += (Vector3.{0.97, 0.92, 0.88} - color.xyz) * cloud_band * 0.22;

    sun_dir := normalize(Vector3.{-params.light_dir.x, -params.light_dir.y, -params.light_dir.z});
    sun_amount := max(dot(ray_dir, sun_dir), 0.0);
    sun_disk := smoothstep(0.992, 0.9985, sun_amount);
    sun_glow := pow(sun_amount, 24.0) * 0.55;
    sun_mix := sun_disk * 1.45 + sun_glow;
    color.xyz += sun_color.xyz * sun_mix;

    haze := smoothstep(-0.25, 0.12, ray_dir.y);
    haze_mix := (1.0 - haze) * 0.12;
    color.xyz += (horizon_color.xyz * 0.95 + {0.10, 0.08, 0.06} - color.xyz) * haze_mix;
    return vec4(clamp(color.xyz, 0, 1), 1.0);
} @fragment_shader

#scope_file

build_scene_geometry :: () {
    using app;
    vertices_cpu: [..]Procedural_Geometry_Vertex;
    indices_cpu: [..]u32;
    vertices_cpu.allocator = temp;
    indices_cpu.allocator = temp;

    floor_mesh = procedural_append_plane(*vertices_cpu, *indices_cpu, 18.0);
    objects[0].mesh = procedural_append_torus(*vertices_cpu, *indices_cpu, 1.25, 0.38, 52, 26);
    objects[1].mesh = procedural_append_uv_sphere(*vertices_cpu, *indices_cpu, 1.2, 40, 26);
    objects[2].mesh = procedural_append_prism(*vertices_cpu, *indices_cpu, 1.18, 1.2, 6);
    objects[3].mesh = procedural_append_cone(*vertices_cpu, *indices_cpu, 1.0, 2.4, 28);
    objects[4].mesh = procedural_append_cylinder(*vertices_cpu, *indices_cpu, 0.92, 1.15, 26);
    objects[5].mesh = procedural_append_prism(*vertices_cpu, *indices_cpu, 1.0, 1.0, 3);
    objects[6].mesh = procedural_append_torus(*vertices_cpu, *indices_cpu, 0.92, 0.24, 40, 18);
    objects[7].mesh = procedural_append_cylinder(*vertices_cpu, *indices_cpu, 0.62, 1.55, 20);

    arena_bytes := max(cast(s64) 256 * 1024,
        vertices_cpu.count * size_of(Procedural_Geometry_Vertex) +
        indices_cpu.count * size_of(u32) +
        128 * 1024);
    gpu_arena = gpu_make_arena(arena_bytes, label = "cel shading arena");
    geometry_vertices = gpu_alloc_view(*gpu_arena, Procedural_Geometry_Vertex, vertices_cpu.count);
    geometry_indices = gpu_alloc_view(*gpu_arena, u32, indices_cpu.count);
    memcpy(geometry_vertices.cpu.data, vertices_cpu.data, vertices_cpu.count * size_of(Procedural_Geometry_Vertex));
    memcpy(geometry_indices.cpu.data, indices_cpu.data, indices_cpu.count * size_of(u32));

    draw.vertices = geometry_vertices.gpu;
    draw.indices = geometry_indices.gpu;
    init_frame_param_alloc(*draw_params, *gpu_arena, 20);
    init_frame_param_alloc(*sky_params, *gpu_arena);
    init_frame_param_alloc(*post_params, *gpu_arena);
}

init_scene_objects :: () {
    using app;
    objects[0].position = .{-5.6, 1.30, 0.3};
    objects[0].scale = 0.96;
    objects[0].rotation_axis = .{0.0, 1.0, 0.0};
    objects[0].spin_deg_per_sec = 36.0;
    objects[0].phase = 0.0;
    objects[0].color = .{0.95, 0.48, 0.36, 1.0};

    objects[1].position = .{-2.6, 1.15, 1.9};
    objects[1].scale = 1.12;
    objects[1].rotation_axis = .{0.0, 1.0, 0.15};
    objects[1].spin_deg_per_sec = -28.0;
    objects[1].phase = 0.8;
    objects[1].color = .{0.98, 0.82, 0.42, 1.0};

    objects[2].position = .{0.4, 1.32, 1.5};
    objects[2].scale = 0.96;
    objects[2].rotation_axis = normalize(Vector3.{0.35, 1.0, 0.1});
    objects[2].spin_deg_per_sec = 30.0;
    objects[2].phase = 1.7;
    objects[2].color = .{0.40, 0.77, 0.56, 1.0};

    objects[3].position = .{3.3, 1.28, 0.7};
    objects[3].scale = 0.92;
    objects[3].rotation_axis = normalize(Vector3.{0.1, 1.0, 0.25});
    objects[3].spin_deg_per_sec = -40.0;
    objects[3].phase = 2.5;
    objects[3].color = .{0.36, 0.60, 0.94, 1.0};

    objects[4].position = .{6.0, 1.22, 1.8};
    objects[4].scale = 0.88;
    objects[4].rotation_axis = normalize(Vector3.{0.0, 1.0, -0.2});
    objects[4].spin_deg_per_sec = 34.0;
    objects[4].phase = 1.2;
    objects[4].color = .{0.77, 0.53, 0.96, 1.0};

    objects[5].position = .{-8.0, 1.02, 3.4};
    objects[5].scale = 0.92;
    objects[5].rotation_axis = normalize(Vector3.{0.2, 1.0, 0.25});
    objects[5].spin_deg_per_sec = 48.0;
    objects[5].phase = 3.2;
    objects[5].color = .{0.98, 0.62, 0.80, 1.0};

    objects[6].position = .{-0.9, 2.55, -1.7};
    objects[6].scale = 0.74;
    objects[6].rotation_axis = normalize(Vector3.{0.4, 1.0, 0.0});
    objects[6].spin_deg_per_sec = 58.0;
    objects[6].phase = 0.45;
    objects[6].color = .{0.58, 0.95, 0.86, 1.0};

    objects[7].position = .{7.8, 1.75, -0.9};
    objects[7].scale = 0.78;
    objects[7].rotation_axis = normalize(Vector3.{0.15, 1.0, 0.32});
    objects[7].spin_deg_per_sec = -32.0;
    objects[7].phase = 2.1;
    objects[7].color = .{0.93, 0.73, 0.42, 1.0};
}

draw_scene_mesh :: (cmd: Gpu_Command_Buffer, mesh: Procedural_Geometry_Mesh_Range, model: Matrix4, color: Vector4, view_proj: Matrix4, current_time: float) {
    params := app.draw;
    params.view_proj = view_proj;
    params.model = model;
    params.camera_pos = app.camera.position;
    params.base_color = color;
    params.time = current_time;
    params.indices = app.draw.indices + (cast(Gpu_Ptr) mesh.first_index * size_of(u32));

    draw_slot := sgpu_frame_param_alloc(*app.draw_params);
    draw_slot.cpu.* = params;
    draw_result := gpu_draw_instanced_direct(cmd, draw_slot.gpu, mesh.index_count, 1);
    assert(draw_result == .SUCCESS, tprint("cel shading draw failed: %", draw_result));
}

ensure_render_targets :: (width: u32, height: u32) {
    using app;
    if width == 0 || height == 0 return;
    if depth_view != 0 && scene_view != 0 && edge_view != 0 && depth_w == width && depth_h == height return;

    res_scene, scene_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    assert(res_scene == .SUCCESS);
    scene_view = gpu_texture_view(scene_texture);
    assert(scene_view != 0);

    res_edge, edge_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    assert(res_edge == .SUCCESS);
    edge_view = gpu_texture_view(edge_texture);
    assert(edge_view != 0);

    res, depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS);
    depth_view = gpu_texture_view(depth_texture);
    assert(depth_view != 0);
    depth_w = width;
    depth_h = height;
    gpu_commit_residency();
}

draw_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    SetNextWindowPos(.{28.0, 28.0}, .FirstUseEver);
    SetNextWindowSize(.{340.0, 230.0}, .FirstUseEver);

    using app;
    if Begin("Cel Shading", *ui_open, flags = .NoCollapse) {
        Text("Forward-pass procedural cel scene.");
        SliderFloat("Outline Thickness", *outline_thickness, 0.5, 8.0);
        SliderFloat("Posterize", *posterize_steps, 2.0, 8.0);
        Checkbox("Auto Orbit", *auto_orbit);
        SliderFloat("Orbit Radius", *orbit_radius, 7.0, 16.0);
        SliderFloat("FOV", *camera.fov_y, PI / 12.0, PI * 0.75);
    }
    End();
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "procedural_geometry.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
Input :: #import "Input";
ImGui :: #import "ImGui";
