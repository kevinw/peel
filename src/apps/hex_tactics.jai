Hex_Tile_Flags :: enum_flags u32 {
    GRASS;
}

Hex_Tile :: struct {
    q: s32;
    r: s32;
    height: float;
    material_kind: u32;
    flags: Hex_Tile_Flags;
}

Hex_Tactics_Model :: struct {
    radius: s32;
    tile_radius: float;
    tiles: [..]Hex_Tile;
}

Hex_Tactics_Mesh_Params_CPU  :: CPU_Struct(Hex_Tactics_Mesh_Params);
Hex_Tactics_Grass_Params_CPU :: CPU_Struct(Hex_Tactics_Grass_Params);

Hex_Tactics_Render_Buffers :: struct {
    vertices: Gpu_View(Hex_Tactics_Vertex);
    indices: Gpu_View(u32);
    grass_instances: Gpu_View(Hex_Tactics_Grass_Instance);
    mesh_params: Gpu_Buffer(Hex_Tactics_Mesh_Params_CPU);
    grass_params: Gpu_Buffer(Hex_Tactics_Grass_Params_CPU);
    sky_params: Gpu_Buffer(Hex_Tactics_Sky_Params_CPU);
    index_count: u32;
    grass_count: u32;
}

Hex_Tactics_Sky_Params_CPU :: struct {
    camera_right_proj_x: Vector4;
    camera_up_proj_y: Vector4;
    camera_forward_time_of_day: Vector4;
    light_dir_sun_strength: Vector4;
}

terrain_shader: Shader(hex_tactics_mesh_vertex_main, hex_tactics_mesh_fragment_main, {
    cull = .CCW,
    depth_format = .D32_SFLOAT,
    color_targets = .[
        .{format = .B8G8R8A8_UNORM},
    ],
});

grass_shader: Shader(hex_tactics_grass_vertex_main, hex_tactics_grass_fragment_main, {
    cull = .NONE,
    depth_format = .D32_SFLOAT,
    color_targets = .[
        .{format = .B8G8R8A8_UNORM},
    ],
});

sky_shader: Shader(hex_tactics_sky_vertex_main, hex_tactics_sky_fragment_main, {
    cull = .NONE,
    depth_format = .D32_SFLOAT,
    color_targets = .[
        .{format = .B8G8R8A8_UNORM},
    ],
});

gpu_arena: Gpu_Arena;
hex_tactics_depth_texture: Gpu_Texture;
hex_tactics_depth_view: Gpu_Texture_View;
hex_tactics_depth_w: u32;
hex_tactics_depth_h: u32;

hex_tactics_model: Hex_Tactics_Model;
hex_tactics_render: Hex_Tactics_Render_Buffers;

hex_tactics_ui_open := true;
hex_tactics_camera: Editor_Camera = .{
    position = .{0.0, 10.0, 13.5},
    yaw = 0.0,
    pitch = -0.58,
    move_speed = 8.0,
    boost_multiplier = 2.4,
    mouse_sensitivity = 0.0056,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};
hex_tactics_orbit_target := Vector3.{0.0, 1.6, 0.0};
hex_tactics_orbit_drag_active := false;
hex_tactics_orbit_distance: float = 13.5;
hex_tactics_orbit_prev_mouse: Vector2;
hex_tactics_orbit_have_prev_mouse := false;
hex_tactics_time_of_day: float = 0.31;
hex_tactics_sun_strength: float = 1.0;

hex_tactics_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{320.0, 170.0}, .FirstUseEver);
    if Begin("Hex Tactics", *hex_tactics_ui_open, flags = .NoCollapse) {
        Text("3D hex tactics prototype");
        Text("RMB look, WASDQE fly, Alt+LMB orbit");
        SliderFloat("Time of Day", *hex_tactics_time_of_day, 0.0, 1.0, "%.2f");
        SliderFloat("Sun Strength", *hex_tactics_sun_strength, 0.0, 3.0, "%.2f");
        Text("Tiles: %", hex_tactics_model.tiles.count);
        Text("Grass Clumps: %", hex_tactics_render.grass_count);
    }
    End();
}

on_dll_init :: () {
    SHR.init(*terrain_shader);
    SHR.init(*grass_shader);
    SHR.init(*sky_shader);

    hex_tactics_model_init(*hex_tactics_model);
    hex_tactics_rebuild_render(*hex_tactics_model, *hex_tactics_render);

    render_w, render_h := app_current_render_dimensions();
    if render_w > 0 && render_h > 0 hex_tactics_ensure_depth_target(render_w, render_h);

    editor_camera_set_look_at(*hex_tactics_camera, hex_tactics_orbit_target);
    hex_tactics_camera.position = hex_tactics_orbit_target - editor_camera_forward(hex_tactics_camera) * hex_tactics_orbit_distance;

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    hex_tactics_model_deinit(*hex_tactics_model);
    hex_tactics_render_deinit(*hex_tactics_render);
    if hex_tactics_depth_view != 0 gpu_free_texture_view(hex_tactics_depth_view);
    if hex_tactics_depth_texture != 0 gpu_free(hex_tactics_depth_texture);
    gpu_delete(*sky_shader.pipeline);
    gpu_delete(*grass_shader.pipeline);
    gpu_delete(*terrain_shader.pipeline);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled hex_tactics_ui();

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    game_mx, game_my, game_mouse_ok := app_game_view_mouse_pos_pixels();
    render_w, render_h := app_current_render_dimensions();
    if render_w > 0 && render_h > 0 hex_tactics_ensure_depth_target(render_w, render_h);
    io := ImGui.GetIO();
    app_mx := ifx app_should_render_to_game_view() then game_mx else mx;
    app_my := ifx app_should_render_to_game_view() then game_my else my;
    app_mouse_ok := ifx app_should_render_to_game_view() then game_mouse_ok else mouse_ok;
    app_mouse_allowed := ifx app_should_render_to_game_view() then game_mouse_ok else !io.WantCaptureMouse;
    right_down := input_down(.MOUSE_BUTTON_RIGHT);
    alt_down := input_down(.ALT);

    orbit_start := alt_down && input_pressed(.MOUSE_BUTTON_LEFT) && app_mouse_allowed && !right_down && app_mouse_ok;
    if orbit_start {
        hex_tactics_orbit_prev_mouse = .{cast(float) app_mx, cast(float) app_my};
        hex_tactics_orbit_have_prev_mouse = true;
        hex_tactics_orbit_distance = max(distance(hex_tactics_camera.position, hex_tactics_orbit_target), 1.2);
        hex_tactics_orbit_drag_active = true;
    }

    if hex_tactics_orbit_drag_active {
        if !alt_down || !input_down(.MOUSE_BUTTON_LEFT) || !app_mouse_allowed || !app_mouse_ok {
            hex_tactics_orbit_drag_active = false;
            hex_tactics_orbit_have_prev_mouse = false;
        } else {
            hex_tactics_orbit_update_camera(.{cast(float) app_mx, cast(float) app_my});
        }
    }

    _ = editor_camera_update(*hex_tactics_camera, cast(float) dt, app_mx, app_my, app_mouse_ok,
        allow_move = !io.WantTextInput && !hex_tactics_orbit_drag_active,
        allow_look = right_down && app_mouse_allowed && !hex_tactics_orbit_drag_active,
        allow_zoom = app_mouse_allowed && !hex_tactics_orbit_drag_active);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(hex_tactics_camera, *cam_forward, *cam_right, *cam_up);
    view := editor_camera_make_view(*hex_tactics_camera);
    aspect := ifx render_h > 0 then cast(float) render_w / cast(float) render_h else 1.0;
    proj := editor_camera_make_projection(*hex_tactics_camera, aspect, 0.05, 120.0);
    view_proj := proj * view;

    hex_tactics_time_of_day = clamp(hex_tactics_time_of_day, 0.0, 1.0);
    hex_tactics_sun_strength = clamp(hex_tactics_sun_strength, 0.0, 3.0);
    sun_dir := hex_tactics_sun_direction(hex_tactics_time_of_day);
    light_dir := -sun_dir;

    hex_tactics_render.mesh_params.cpu.* = .{
        vertices = hex_tactics_render.vertices.gpu,
        indices = hex_tactics_render.indices.gpu,
        view_proj = view_proj,
        light_dir = light_dir,
        sun_params = .{hex_tactics_sun_strength, hex_tactics_time_of_day, 0.0, 0.0},
        camera_pos = hex_tactics_camera.position,
    };
    hex_tactics_render.grass_params.cpu.* = .{
        instances = hex_tactics_render.grass_instances.gpu,
        view_proj = view_proj,
        light_dir = light_dir,
        sun_params = .{hex_tactics_sun_strength, hex_tactics_time_of_day, 0.0, 0.0},
        camera_pos = hex_tactics_camera.position,
        time = cast(float) time,
    };
    hex_tactics_render.sky_params.cpu.* = .{
        camera_right_proj_x = .{cam_right.x, cam_right.y, cam_right.z, proj._11},
        camera_up_proj_y = .{cam_up.x, cam_up.y, cam_up.z, proj._22},
        camera_forward_time_of_day = .{cam_forward.x, cam_forward.y, cam_forward.z, hex_tactics_time_of_day},
        light_dir_sun_strength = .{light_dir.x, light_dir.y, light_dir.z, hex_tactics_sun_strength},
    };

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = hex_tactics_depth_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{depth = 1.0, stencil = 0},
        },
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.01, 0.01, 0.015, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, sky_shader.pipeline);
    gpu_draw_instanced_direct(cmd_buff, hex_tactics_render.sky_params.gpu, 6, 1);

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, terrain_shader.pipeline);
    gpu_draw_instanced_direct(cmd_buff, hex_tactics_render.mesh_params.gpu, hex_tactics_render.index_count, 1);

    if hex_tactics_render.grass_count > 0 {
        gpu_set_pipeline(cmd_buff, grass_shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, hex_tactics_render.grass_params.gpu, 6, hex_tactics_render.grass_count);
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

hex_tactics_model_init :: (model: *Hex_Tactics_Model) {
    model.tiles.allocator = context.allocator;
    model.radius = 4;
    model.tile_radius = 1.0;
    array_reset(*model.tiles);

    for r: -model.radius .. model.radius {
        q_min := max(-model.radius, -r - model.radius);
        q_max := min(model.radius, -r + model.radius);
        for q: q_min .. q_max {
            ridge := sin(cast(float) q * 0.9) * 0.42 + cos(cast(float) r * 0.73) * 0.36;
            swell := sin(cast(float) (q + r) * 0.48) * 0.28;
            bowl := cast(float) (abs(q) + abs(r)) * -0.05;
            height := 0.65 + ridge + swell + bowl;
            height = clamp(height, 0.18, 2.35);
            grass_noise := hash01_from_s32(q * 92821 + r * 68917 + 179);
            kind: u32 = ifx height > 1.55 then cast(u32) 1 else ifx height < 0.52 then cast(u32) 2 else cast(u32) 0;
            flags: Hex_Tile_Flags;
            if grass_noise > 0.38 && kind != 1 flags = .GRASS;
            array_add(*model.tiles, .{
                q = q,
                r = r,
                height = height,
                material_kind = kind,
                flags = flags,
            });
        }
    }
}

hex_tactics_model_deinit :: (model: *Hex_Tactics_Model) {
    array_free(model.tiles);
    model.* = .{};
}

hex_tactics_render_deinit :: (render: *Hex_Tactics_Render_Buffers) {
    if gpu_arena.cpu != null gpu_free_arena(gpu_arena);
    gpu_arena = .{};
    render.* = .{};
}

hex_tactics_rebuild_render :: (model: *Hex_Tactics_Model, render: *Hex_Tactics_Render_Buffers) {
    hex_tactics_render_deinit(render);

    vertices_cpu: [..]Hex_Tactics_Vertex;
    vertices_cpu.allocator = temp;
    indices_cpu: [..]u32;
    indices_cpu.allocator = temp;
    grass_cpu: [..]Hex_Tactics_Grass_Instance;
    grass_cpu.allocator = temp;

    for model.tiles {
        center := hex_tactics_tile_center(model.*, it.q, it.r);
        append_tile_mesh(*vertices_cpu, *indices_cpu, center, it.height, it.material_kind, model.tile_radius);
        if cast(u32) (it.flags & .GRASS) != 0 {
            hex_tactics_append_tile_grass(*grass_cpu, center, it.height, model.tile_radius, it.q, it.r);
        }
    }

    arena_bytes := max(cast(s64) 1, vertices_cpu.count) * size_of(Hex_Tactics_Vertex) +
        max(cast(s64) 1, indices_cpu.count) * size_of(u32) +
        max(cast(s64) 1, grass_cpu.count) * size_of(Hex_Tactics_Grass_Instance) +
        size_of(Hex_Tactics_Mesh_Params_CPU) + size_of(Hex_Tactics_Grass_Params_CPU) + size_of(Hex_Tactics_Sky_Params_CPU) + 1024;
    gpu_arena = gpu_make_arena(arena_bytes, label = "hex tactics arena");
    assert(gpu_arena.cpu != null, "Hex tactics arena creation failed.");

    render.vertices        = gpu_alloc_view(*gpu_arena, Hex_Tactics_Vertex, vertices_cpu.count);
    render.indices         = gpu_alloc_view(*gpu_arena, u32, indices_cpu.count);
    render.grass_instances = gpu_alloc_view(*gpu_arena, Hex_Tactics_Grass_Instance, grass_cpu.count);
    render.mesh_params     = gpu_alloc_buffer(*gpu_arena, Hex_Tactics_Mesh_Params_CPU);
    render.grass_params    = gpu_alloc_buffer(*gpu_arena, Hex_Tactics_Grass_Params_CPU);
    render.sky_params      = gpu_alloc_buffer(*gpu_arena, Hex_Tactics_Sky_Params_CPU);

    if vertices_cpu.count > 0 memcpy(render.vertices.cpu.data, vertices_cpu.data, vertices_cpu.count * size_of(Hex_Tactics_Vertex));
    if indices_cpu.count > 0  memcpy(render.indices.cpu.data, indices_cpu.data, indices_cpu.count * size_of(u32));
    if grass_cpu.count > 0    memcpy(render.grass_instances.cpu.data, grass_cpu.data, grass_cpu.count * size_of(Hex_Tactics_Grass_Instance));

    render.index_count = cast(u32) indices_cpu.count;
    render.grass_count = cast(u32) grass_cpu.count;
}

hex_tactics_ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if hex_tactics_depth_view != 0 && hex_tactics_depth_w == width && hex_tactics_depth_h == height return;

    if hex_tactics_depth_view != 0 gpu_free_texture_view(hex_tactics_depth_view);
    if hex_tactics_depth_texture != 0 gpu_free(hex_tactics_depth_texture);

    res, hex_tactics_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS, "Hex tactics depth texture creation failed.");
    hex_tactics_depth_view = gpu_texture_view(hex_tactics_depth_texture);
    assert(hex_tactics_depth_view != 0, "Hex tactics depth view creation failed.");
    hex_tactics_depth_w = width;
    hex_tactics_depth_h = height;
    gpu_commit_residency();
}

append_tile_mesh :: (vertices: *[..]Hex_Tactics_Vertex, indices: *[..]u32, center: Vector3, height: float, material_kind: u32, tile_radius: float) {
    side_base_y := -0.16;
    bevel_drop := 0.12;
    inner_scale := 0.84;
    top_inner_y := height;
    top_outer_y := height - bevel_drop;

    top_color, side_color, roughness, metallic, ao := hex_tactics_material_params(material_kind, height);

    center_top := hex_tactics_push_vertex(vertices, center + .{0.0, top_inner_y, 0.0}, .{0.0, 1.0, 0.0}, top_color, .{roughness, metallic, ao, 0.0});
    inner_ring: [6]u32;
    outer_ring: [6]u32;
    bottom_ring: [6]u32;

    for 0..5 {
        angle := (PI / 3.0) * cast(float) it + PI / 6.0;
        dir := Vector3.{cos(angle), 0.0, sin(angle)};
        inner_pos := center + dir * (tile_radius * inner_scale) + .{0.0, top_inner_y, 0.0};
        outer_pos := center + dir * tile_radius + .{0.0, top_outer_y, 0.0};
        bottom_pos := center + dir * tile_radius + .{0.0, side_base_y, 0.0};
        inner_ring[it] = hex_tactics_push_vertex(vertices, inner_pos, .{0.0, 1.0, 0.0}, top_color, .{roughness, metallic, ao, 0.0});

        bevel_normal := hex_tactics_safe_normalize(Vector3.{dir.x * 0.65, 1.0, dir.z * 0.65}, .{0.0, 1.0, 0.0});
        outer_ring[it] = hex_tactics_push_vertex(vertices, outer_pos, bevel_normal, mix(top_color, side_color, 0.22), .{roughness, metallic, ao, 0.0});

        side_normal := hex_tactics_safe_normalize(Vector3.{dir.x, 0.18, dir.z}, .{0.0, 1.0, 0.0});
        bottom_ring[it] = hex_tactics_push_vertex(vertices, bottom_pos, side_normal, side_color, .{roughness, metallic, ao, 0.0});
    }

    for 0..5 {
        next := (it + 1) % 6;
        push_tri(indices, center_top, inner_ring[it], inner_ring[next]);
        push_tri(indices, inner_ring[it], outer_ring[it], outer_ring[next]);
        push_tri(indices, inner_ring[it], outer_ring[next], inner_ring[next]);
        push_tri(indices, outer_ring[it], bottom_ring[it], bottom_ring[next]);
        push_tri(indices, outer_ring[it], bottom_ring[next], outer_ring[next]);
    }
}

hex_tactics_append_tile_grass :: (instances: *[..]Hex_Tactics_Grass_Instance, center: Vector3, height: float, tile_radius: float, q: s32, r: s32) {
    cluster_count := 3 + cast(s32) floor(hash01_from_s32(q * 37 + r * 53 + 13) * 145.0);
    for 0..cluster_count-1 {
        seed := cast(float) (q * 173 + r * 97 + cast(s32) it * 29);
        angle := hash01_f(seed * 0.71) * PI * 2.0;
        radius := hash01_f(seed * 1.17) * tile_radius * 0.65;
        pos := center + .{cos(angle) * radius, height - 0.01, sin(angle) * radius};
        tint_noise := hash01_f(seed * 0.41);
        tint := mix(Vector4.{0.78, 0.72, 0.46, 1.0}, Vector4.{0.58, 0.70, 0.26, 1.0}, tint_noise);
        array_add(instances, .{
            base = .{pos.x, pos.y, pos.z, 0.02 + hash01_f(seed * 0.93) * 0.24},
            tint = tint,
        });
    }
}

hex_tactics_tile_center :: (using model: Hex_Tactics_Model, q: s32, r: s32) -> Vector3 {
    x := tile_radius * 1.7320508 * (cast(float) q + cast(float) r * 0.5);
    z := tile_radius * 1.5 * cast(float) r;
    return .{x, 0.0, z};
}

hex_tactics_material_params :: (kind: u32, height: float) -> Vector4, Vector4, float, float, float {
    if kind == 1 {
        return .{0.44, 0.46, 0.50, 1.0}, .{0.28, 0.29, 0.31, 1.0}, 0.88, 0.02, 0.95;
    }
    if kind == 2 {
        sand_lift := clamp((0.6 - height) * 0.7, 0.0, 0.25);
        return .{0.76 + sand_lift, 0.63 + sand_lift * 0.4, 0.39, 1.0}, .{0.54, 0.42, 0.26, 1.0}, 0.72, 0.01, 0.92;
    }
    return .{0.54, 0.66, 0.34, 1.0}, .{0.34, 0.26, 0.18, 1.0}, 0.64, 0.01, 1.0;
}

hex_tactics_push_vertex :: (vertices: *[..]Hex_Tactics_Vertex, pos: Vector3, normal: Vector3, color: Vector4, material: Vector4) -> u32 {
    idx := cast(u32) vertices.count;
    array_add(vertices, .{
        pos      = vec4(pos, 1),
        normal   = vec4(normal, 0),
        color    = color,
        material = material,
    });
    return idx;
}

push_tri :: (indices: *[..]u32, a: u32, b: u32, c: u32) {
    array_add(indices, a);
    array_add(indices, b);
    array_add(indices, c);
}

hex_tactics_safe_normalize :: (v: Vector3, fallback: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 < 0.000001 return fallback;
    return v * (1.0 / sqrt(len2));
}


hex_tactics_orbit_update_camera :: (mouse_pos: Vector2) {
    if !hex_tactics_orbit_have_prev_mouse {
        hex_tactics_orbit_prev_mouse = mouse_pos;
        hex_tactics_orbit_have_prev_mouse = true;
        return;
    }

    delta := mouse_pos - hex_tactics_orbit_prev_mouse;
    hex_tactics_orbit_prev_mouse = mouse_pos;
    if abs(delta.x) < 0.0001 && abs(delta.y) < 0.0001 return;

    hex_tactics_camera.yaw += delta.x * hex_tactics_camera.mouse_sensitivity;
    hex_tactics_camera.pitch += delta.y * hex_tactics_camera.mouse_sensitivity;
    hex_tactics_camera.pitch = clamp(hex_tactics_camera.pitch, hex_tactics_camera.pitch_min, hex_tactics_camera.pitch_max);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(hex_tactics_camera, *cam_forward, *cam_right, *cam_up);
    hex_tactics_camera.position = hex_tactics_orbit_target - cam_forward * hex_tactics_orbit_distance;
}

hex_tactics_sun_direction :: (time_of_day: float) -> Vector3 {
    tau := cast(float) 6.28318530718;
    phase := (time_of_day - 0.25) * tau;
    elevation := sin(phase) * cast(float) 0.92;
    horizontal := sqrt(max(1.0 - elevation * elevation, 0.0001));
    return normalize(Vector3.{cos(phase) * horizontal, elevation, sin(phase) * horizontal * 0.55});
}

hash01_from_s32 :: (x: s32) -> float {
    phase := cast(float) x * 12.9898 + 78.233;
    value := sin(phase) * cast(float) 43758.5453;
    return value - floor(value);
}

hash01_f :: (x: float) -> float {
    value := sin(x * cast(float) 12.9898 + cast(float) 78.233) * cast(float) 43758.5453;
    return value - floor(value);
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "shaders/hex_tactics_shader.jai";
#import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
Input :: #import "Input";
#import "Math";
