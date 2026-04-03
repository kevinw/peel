MAX_DECAL_PAINTER_DECALS :: 48;
DECAL_PAINTER_SHAPE_CIRCLE :: 0;
DECAL_PAINTER_SHAPE_BOX    :: 1;
DECAL_PAINTER_SHAPE_STRIPE :: 2;

Decal_Painter_Draw_Params :: struct {
    vertices: *Procedural_Geometry_Vertex;
    indices: *u32;
    view_proj: Matrix4;
    model: Matrix4;
    camera_pos: Vector3;
    time: float;
    base_color: Vector4;
    light_dir: Vector3;
    decal_count: u32;
    decal_pos_radius: *Vector4;
    decal_color_opacity: *Vector4;
    decal_misc: *Vector4;
}

Decal_Painter_Draw_Params_CPU :: CPU_Struct(Decal_Painter_Draw_Params);

Decal_Painter_Object :: struct {
    mesh: Procedural_Geometry_Mesh_Range;
    position: Vector3;
    scale: float;
    rotation: Quaternion = .{0.0, 0.0, 0.0, 1.0};
    color: Vector4;
}

Decal_Painter_Decal :: struct {
    position: Vector3;
    radius: float;
    color: Vector4;
    rotation: float;
    thickness: float;
    normal_min_dot: float;
    shape: u32;
}

app: struct {
    graphics_pipeline: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;
    draw_params: Gpu_Frame_Param_Allocator(Decal_Painter_Draw_Params_CPU);

    geometry_vertices: Gpu_View(Procedural_Geometry_Vertex);
    geometry_indices: Gpu_View(u32);
    decal_pos_radius_gpu: Gpu_View(Vector4);
    decal_color_opacity_gpu: Gpu_View(Vector4);
    decal_misc_gpu: Gpu_View(Vector4);

    depth_texture: Gpu_Texture;
    depth_view: Gpu_Texture_View;
    depth_w: u32;
    depth_h: u32;

    camera: Editor_Camera = .{
        position = .{0.0, 5.0, 8.5},
        yaw = 0.0,
        pitch = -0.42,
        move_speed = 8.5,
        boost_multiplier = 2.2,
        move_planar = false,
    };

    draw_template: Decal_Painter_Draw_Params_CPU;

    floor_mesh: Procedural_Geometry_Mesh_Range;
    objects: [6]Decal_Painter_Object;

    decals: [MAX_DECAL_PAINTER_DECALS]Decal_Painter_Decal;
    decal_count: s32;

    paint_shape: u32 = DECAL_PAINTER_SHAPE_CIRCLE;
    paint_radius: float = 1.0;
    paint_opacity: float = 0.9;
    paint_rotation: float;
    paint_thickness: float = 0.65;
    paint_normal_min_dot: float = 0.65;
    paint_color: Vector4 = .{1.0, 0.27, 0.19, 0.9};
    erase_mode: bool;

    hovered_hit: Vector3;
    hovered_hit_valid: bool;
    left_was_down: bool;
    ui_open: bool = true;
};

on_dll_init :: () {
    using app;

    graphics_source := cast([]u8) get_transpiled(.METAL, decal_painter_vertex_main, decal_painter_fragment_main);
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };
    ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, decal_painter_vertex_main, decal_painter_fragment_main);
    assert(ok, "Decal painter pipeline creation failed.");

    draw_template.light_dir = normalize(Vector3.{-0.4, -1.0, -0.25});
    build_scene_geometry();
    init_scene_objects();
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

    viewport := Vector2.{cast(float) win_w, cast(float) win_h};
    ensure_depth_target(cast(u32) win_w, cast(u32) win_h);

    using ImGui;
    io := GetIO();
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    left_pressed := left_down && !left_was_down;
    left_was_down = left_down;

    _ = editor_camera_update(*camera, editor_dt, mx, my, mouse_ok,
        allow_move = !io.WantCaptureKeyboard,
        allow_look = right_down && !io.WantCaptureMouse,
        allow_zoom = !io.WantCaptureMouse);

    hovered_hit_valid = false;
    if mouse_ok {
        ray_origin, ray_dir, ray_ok := decal_painter_mouse_world_ray(cast(float) mx, cast(float) my, viewport, camera);
        if ray_ok {
            hovered_hit_valid, hovered_hit = decal_painter_ray_intersect_plane(ray_origin, ray_dir, .{0.0, 0.0, 0.0}, .{0.0, 1.0, 0.0});
        }
    }

    if left_pressed && !right_down && hovered_hit_valid && !io.WantCaptureMouse {
        place_or_erase_decal(hovered_hit);
    }

    view := editor_camera_make_view(*camera);
    aspect := viewport.x / max(viewport.y, 1.0);
    proj := editor_camera_make_projection(*camera, aspect, 0.05, 120.0);
    view_proj := proj * view;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = depth_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{depth = 1.0, stencil = 0},
        },
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.06, 0.075, 0.09, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_scene_mesh(cmd_buff, floor_mesh, make_translation_matrix4(.{0.0, 0.0, 0.0}), .{0.20, 0.22, 0.24, 1.0}, view_proj);
    for object: objects {
        model := make_trs_matrix(object.position, object.rotation, object.scale);
        draw_scene_mesh(cmd_buff, object.mesh, model, object.color, view_proj);
    }

    draw_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

build_scene_geometry :: () {
    using app;

    vertices_cpu: [..]Procedural_Geometry_Vertex;
    indices_cpu: [..]u32;
    vertices_cpu.allocator = context.allocator;
    indices_cpu.allocator = context.allocator;
    defer array_free(vertices_cpu);
    defer array_free(indices_cpu);

    floor_mesh = procedural_append_plane(*vertices_cpu, *indices_cpu, 8.5);
    pedestal := procedural_append_cylinder(*vertices_cpu, *indices_cpu, 0.9, 0.55, 20);
    block := procedural_append_prism(*vertices_cpu, *indices_cpu, 0.9, 0.8, 4);
    torus := procedural_append_torus(*vertices_cpu, *indices_cpu, 1.0, 0.28, 28, 12);
    cone := procedural_append_cone(*vertices_cpu, *indices_cpu, 0.85, 2.2, 20);
    orb := procedural_append_uv_sphere(*vertices_cpu, *indices_cpu, 0.95, 24, 12);

    gpu_bytes := vertices_cpu.count * size_of(Procedural_Geometry_Vertex) +
        indices_cpu.count * size_of(u32) +
        512 * 1024;
    gpu_arena = gpu_make_arena(cast(s64) gpu_bytes, label = "decal painter arena");
    draw_params = sgpu_make_frame_param_allocator(*gpu_arena, Decal_Painter_Draw_Params_CPU, 10);

    geometry_vertices = gpu_alloc_view(*gpu_arena, Procedural_Geometry_Vertex, vertices_cpu.count);
    geometry_indices = gpu_alloc_view(*gpu_arena, u32, indices_cpu.count);
    decal_pos_radius_gpu = gpu_alloc_view(*gpu_arena, Vector4, MAX_DECAL_PAINTER_DECALS);
    decal_color_opacity_gpu = gpu_alloc_view(*gpu_arena, Vector4, MAX_DECAL_PAINTER_DECALS);
    decal_misc_gpu = gpu_alloc_view(*gpu_arena, Vector4, MAX_DECAL_PAINTER_DECALS);
    memcpy(geometry_vertices.cpu.data, vertices_cpu.data, vertices_cpu.count * size_of(Procedural_Geometry_Vertex));
    memcpy(geometry_indices.cpu.data, indices_cpu.data, indices_cpu.count * size_of(u32));

    draw_template.vertices = geometry_vertices.gpu;
    draw_template.indices = geometry_indices.gpu;
    draw_template.decal_pos_radius = decal_pos_radius_gpu.gpu;
    draw_template.decal_color_opacity = decal_color_opacity_gpu.gpu;
    draw_template.decal_misc = decal_misc_gpu.gpu;

    objects[0] = .{
        mesh = pedestal,
        position = .{-2.2, 0.55, -0.9},
        scale = 1.0,
        color = .{0.68, 0.70, 0.75, 1.0},
    };
    objects[1] = .{
        mesh = pedestal,
        position = .{2.3, 0.55, 1.6},
        scale = 0.82,
        color = .{0.60, 0.64, 0.72, 1.0},
    };
    objects[2] = .{
        mesh = block,
        position = .{-0.1, 0.82, 2.8},
        scale = 1.0,
        rotation = quat_from_euler_deg(.{0.0, 45.0, 0.0}),
        color = .{0.85, 0.82, 0.77, 1.0},
    };
    objects[3] = .{
        mesh = torus,
        position = .{2.1, 1.35, -2.4},
        scale = 0.92,
        rotation = quat_from_euler_deg(.{78.0, 0.0, 0.0}),
        color = .{0.44, 0.58, 0.86, 1.0},
    };
    objects[4] = .{
        mesh = cone,
        position = .{-3.0, 1.1, 2.6},
        scale = 0.82,
        color = .{0.84, 0.64, 0.40, 1.0},
    };
    objects[5] = .{
        mesh = orb,
        position = .{0.0, 1.1, -1.9},
        scale = 0.72,
        color = .{0.75, 0.48, 0.58, 1.0},
    };
}

draw_scene_mesh :: (cmd: Gpu_Command_Buffer, mesh: Procedural_Geometry_Mesh_Range, model_matrix: Matrix4, color: Vector4, vp: Matrix4) {
    using app;

    params := draw_template;
    params.view_proj = vp;
    params.model = model_matrix;
    params.camera_pos = camera.position;
    params.time = cast(float) time;
    params.base_color = color;
    params.indices = draw_template.indices + (cast(Gpu_Ptr) mesh.first_index * size_of(u32));
    params.decal_count = cast(u32) decal_count;
    params.decal_pos_radius = decal_pos_radius_gpu.gpu;
    params.decal_color_opacity = decal_color_opacity_gpu.gpu;
    params.decal_misc = decal_misc_gpu.gpu;

    for 0..MAX_DECAL_PAINTER_DECALS-1 {
        decal_pos_radius_gpu.cpu[it] = .{};
        decal_color_opacity_gpu.cpu[it] = .{};
        decal_misc_gpu.cpu[it] = .{};
    }

    for decal_i: 0..decal_count-1 {
        decal := decals[decal_i];
        decal_pos_radius_gpu.cpu[decal_i] = .{decal.position.x, decal.position.y, decal.position.z, decal.radius};
        decal_color_opacity_gpu.cpu[decal_i] = decal.color;
        decal_misc_gpu.cpu[decal_i] = .{decal.rotation, cast(float) decal.shape, decal.thickness, decal.normal_min_dot};
    }

    draw_slot := sgpu_frame_param_alloc(*draw_params);
    draw_slot.cpu.* = params;
    draw_result := gpu_draw_instanced_direct(cmd, draw_slot.gpu, mesh.index_count, 1);
    assert(draw_result == .SUCCESS, tprint("decal painter draw failed: %", draw_result));
}

ensure_depth_target :: (width: u32, height: u32) {
    using app;
    if width == 0 || height == 0 return;
    if depth_view != 0 && depth_w == width && depth_h == height return;

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

init_scene_objects :: () {
    using app;
    editor_camera_set_look_at(*camera, .{0.0, 0.9, 0.0});
}

place_or_erase_decal :: (hit: Vector3) {
    using app;

    if erase_mode {
        best_i := -1;
        best_d := paint_radius;
        for 0..decal_count-1 {
            d := distance(decals[it].position, hit);
            if d < best_d {
                best_d = d;
                best_i = cast(s32) it;
            }
        }
        if best_i >= 0 {
            last_i := decal_count - 1;
            decals[best_i] = decals[last_i];
            decals[last_i] = .{};
            decal_count -= 1;
        }
        return;
    }

    slot := decal_count;
    if slot >= MAX_DECAL_PAINTER_DECALS {
        for 1..MAX_DECAL_PAINTER_DECALS-1 decals[it - 1] = decals[it];
        slot = MAX_DECAL_PAINTER_DECALS - 1;
        decal_count = MAX_DECAL_PAINTER_DECALS;
    } else {
        decal_count += 1;
    }

    decals[slot] = .{
        position = hit,
        radius = paint_radius,
        color = .{paint_color.x, paint_color.y, paint_color.z, paint_opacity},
        rotation = paint_rotation,
        thickness = paint_thickness,
        normal_min_dot = paint_normal_min_dot,
        shape = paint_shape,
    };
}

draw_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    using app;

    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{390.0, 320.0}, .FirstUseEver);

    if Begin("Decal Painter", *ui_open, flags = .NoCollapse) {
        Text("LMB stamp decals on the ground plane.");
        Text("RMB look, WASDQE fly, mouse wheel zoom.");
        Text("Decals: % / %", decal_count, MAX_DECAL_PAINTER_DECALS);
        if hovered_hit_valid Text("Hover: %.2f %.2f %.2f", hovered_hit.x, hovered_hit.y, hovered_hit.z);
        else Text("Hover: --");

        Checkbox("Erase Mode", *erase_mode);
        SliderFloat("Radius", *paint_radius, 0.25, 2.8);
        SliderFloat("Opacity", *paint_opacity, 0.1, 1.0);
        SliderFloat("Rotation", *paint_rotation, -PI, PI);
        SliderFloat("Thickness", *paint_thickness, 0.1, 1.6);
        SliderFloat("Normal Min", *paint_normal_min_dot, 0.0, 1.0);

        Text("Shape");
        if RadioButton("Circle", paint_shape == DECAL_PAINTER_SHAPE_CIRCLE) paint_shape = DECAL_PAINTER_SHAPE_CIRCLE;
        SameLine();
        if RadioButton("Box", paint_shape == DECAL_PAINTER_SHAPE_BOX) paint_shape = DECAL_PAINTER_SHAPE_BOX;
        SameLine();
        if RadioButton("Stripe", paint_shape == DECAL_PAINTER_SHAPE_STRIPE) paint_shape = DECAL_PAINTER_SHAPE_STRIPE;

        SliderFloat("Color R", *paint_color.x, 0.0, 1.0);
        SliderFloat("Color G", *paint_color.y, 0.0, 1.0);
        SliderFloat("Color B", *paint_color.z, 0.0, 1.0);

        if Button("Clear Decals") {
            for *decals it.* = .{};
            decal_count = 0;
        }
    }
    End();
}

decal_painter_mouse_world_ray :: (mouse_x: float, mouse_y: float, viewport: Vector2, camera: Editor_Camera) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if viewport.x <= 1.0 || viewport.y <= 1.0 return camera.position, .{0.0, 0.0, -1.0}, false;
    forward, right, up: Vector3;
    editor_camera_basis(*camera, *forward, *right, *up);
    nx := ((mouse_x + 0.5) / viewport.x) * 2.0 - 1.0;
    ny := ((mouse_y + 0.5) / viewport.y) * 2.0 - 1.0;
    aspect := viewport.x / max(viewport.y, 1.0);
    tan_half_fov := tan(camera.fov_y * 0.5);
    dir := forward + right * (nx * aspect * tan_half_fov) + up * (ny * tan_half_fov);
    normalize(*dir, fallback = forward);
    return camera.position, dir, true;
}

decal_painter_ray_intersect_plane :: (ray_origin: Vector3, ray_dir: Vector3, plane_origin: Vector3, plane_normal: Vector3) -> (hit: bool, p: Vector3) {
    denom := dot(ray_dir, plane_normal);
    if abs(denom) <= 0.00001 return false, .{};
    t := dot(plane_origin - ray_origin, plane_normal) / denom;
    if t <= 0.00001 return false, .{};
    return true, ray_origin + ray_dir * t;
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#load "procedural_geometry.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";
Input :: #import "Input";
ImGui :: #import "ImGui";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/decal_painter_shader.jai";
