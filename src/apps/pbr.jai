TEX_TEMPL :: "./textures/Snow/Snow015_2K-JPG_%.jpg";
PBR_ALBEDO_PATH       :: #run sprint(TEX_TEMPL, "Color");
PBR_NORMAL_PATH       :: #run sprint(TEX_TEMPL, "NormalGL");
PBR_ROUGHNESS_PATH    :: #run sprint(TEX_TEMPL, "Roughness");
PBR_AO_PATH           :: #run sprint(TEX_TEMPL, "AmbientOcclusion");
PBR_DISPLACEMENT_PATH :: #run sprint(TEX_TEMPL, "Displacement");

using PBR_TEX: enum s64 {
    PBR_TEX_ALBEDO       :: 0;
    PBR_TEX_NORMAL       :: 1;
    PBR_TEX_ROUGHNESS    :: 2;
    PBR_TEX_AO           :: 3;
    PBR_TEX_DISPLACEMENT :: 4;
    PBR_TEXTURE_COUNT    :: 5;
}

Draw_Data :: struct {
    params_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

PBR_Params_CPU :: CPU_Struct(PBR_Params);

PBR_Geometry :: enum s64 {
    SPHERE   :: 0;
    TORUS    :: 1;
    PRISM    :: 2;
    CONE     :: 3;
    CYLINDER :: 4;
    PLANE    :: 5;
    COUNT    :: 6;
}

shader: Shader(pbr_vertex_main, pbr_fragment_main, {
    cull = .CW,
    depth_format = .D32_SFLOAT,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
}); @init
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;
pbr_params: Gpu_Buffer(PBR_Params_CPU);
pbr_geometry_vertices: Gpu_View(Procedural_Geometry_Vertex);
pbr_geometry_indices: Gpu_View(u32);
pbr_meshes: [PBR_Geometry.COUNT]Procedural_Geometry_Mesh_Range;
pbr_geometry: PBR_Geometry = .TORUS;
pbr_camera: Editor_Camera = .{
    position = .{1.35, 0.85, 3.25},
    yaw = 0.0,
    pitch = 0.0,
    move_speed = 2.4,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0056,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

pbr_textures: [PBR_TEXTURE_COUNT] Gpu_Texture;
pbr_views:    [PBR_TEXTURE_COUNT] Gpu_Texture_View;
pbr_sampler: Gpu_Sampler;
pbr_depth_texture: Gpu_Texture;
pbr_depth_view: Gpu_Texture_View;
pbr_depth_w: u32;
pbr_depth_h: u32;

on_dll_init :: () {
    stbi_set_flip_vertically_on_load(1);
    pbr_textures[PBR_TEX_ALBEDO], pbr_views[PBR_TEX_ALBEDO]             = load_texture_rgba8(PBR_ALBEDO_PATH);
    pbr_textures[PBR_TEX_NORMAL], pbr_views[PBR_TEX_NORMAL]             = load_texture_rgba8(PBR_NORMAL_PATH);
    pbr_textures[PBR_TEX_ROUGHNESS], pbr_views[PBR_TEX_ROUGHNESS]       = load_texture_rgba8(PBR_ROUGHNESS_PATH);
    pbr_textures[PBR_TEX_AO], pbr_views[PBR_TEX_AO]                     = load_texture_rgba8(PBR_AO_PATH);
    pbr_textures[PBR_TEX_DISPLACEMENT], pbr_views[PBR_TEX_DISPLACEMENT] = load_texture_rgba8(PBR_DISPLACEMENT_PATH);

    pbr_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .REPEAT,
        address_mode_v = .REPEAT,
        address_mode_w = .REPEAT,
    });
    assert(pbr_sampler != 0, "PBR sampler creation failed.");

    gpu_arena = gpu_make_arena(2 * 1024 * 1024, label = "pbr arena");
    build_geometry();

    pbr_params = gpu_alloc_buffer(PBR_Params_CPU);
    pbr_params.cpu.* = .{
        vertices = pbr_geometry_vertices.gpu,
        indices = pbr_geometry_indices.gpu + cast(Gpu_Ptr) pbr_meshes[pbr_geometry].first_index * size_of(u32),
        albedo_index = gpu_texture_view_index(pbr_views[PBR_TEX_ALBEDO]),
        normal_index = gpu_texture_view_index(pbr_views[PBR_TEX_NORMAL]),
        roughness_index = gpu_texture_view_index(pbr_views[PBR_TEX_ROUGHNESS]),
        ao_index = gpu_texture_view_index(pbr_views[PBR_TEX_AO]),
        displacement_index = gpu_texture_view_index(pbr_views[PBR_TEX_DISPLACEMENT]),

        sampler_index = cast(u32) pbr_sampler - 1,

        light_pos_x = 1.8,
        light_pos_y = 2.4,
        light_pos_z = 1.6,
        light_intensity = 26.0,

        light_color_r = 1.0,
        light_color_g = 0.98,
        light_color_b = 0.95,
        metallic = 0.02,

        camera_pos_x = pbr_camera.position.x,
        camera_pos_y = pbr_camera.position.y,
        camera_pos_z = pbr_camera.position.z,
        resolution_x = 1280.0,
        resolution_y = 720.0,
        time = 0.0,
        displacement_strength = 0.18,
        uv_scale = 5.0,
    };

    draw_data = .{
        params_gpu = pbr_params.gpu,
        num_vertices = pbr_meshes[pbr_geometry].index_count,
        num_instances = 1,
    };

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_depth_target(cast(u32) win_w, cast(u32) win_h);
        aspect := cast(float) win_w / cast(float) win_h;
        view := editor_camera_make_view(*pbr_camera);
        proj := editor_camera_make_projection(*pbr_camera, aspect, 0.05, 50.0);
        pbr_params.cpu.view_proj = proj * view;
    }
    editor_camera_set_look_at(*pbr_camera, .{0.0, 0.0, 0.0});

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled {
        if ImGui.Begin("PBR") {
            ImGui.Text("RMB look, WASDQE move");
            ImGui.SliderFloat("Texture Scale", *pbr_params.cpu.uv_scale, 0.25, 12.0);
            ImGui.Separator();
            ImGui.Text("Geometry");
            if ImGui.RadioButton("Sphere", pbr_geometry == .SPHERE) pbr_geometry = .SPHERE; ImGui.SameLine();
            if ImGui.RadioButton("Torus", pbr_geometry == .TORUS) pbr_geometry = .TORUS;
            if ImGui.RadioButton("Prism", pbr_geometry == .PRISM) pbr_geometry = .PRISM; ImGui.SameLine();
            if ImGui.RadioButton("Cone", pbr_geometry == .CONE) pbr_geometry = .CONE;
            if ImGui.RadioButton("Cylinder", pbr_geometry == .CYLINDER) pbr_geometry = .CYLINDER; ImGui.SameLine();
            if ImGui.RadioButton("Plane", pbr_geometry == .PLANE) pbr_geometry = .PLANE;
        }
        ImGui.End();
    }

    {
        mx, my, mouse_ok := get_mouse_pointer_position(true);
        _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
        io := ImGui.GetIO();
        right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
        _ = editor_camera_update(*pbr_camera, cast(float) dt, mx, my, mouse_ok,
            allow_move = !io.WantTextInput,
            allow_look = right_down && !io.WantCaptureMouse,
            allow_zoom = !io.WantCaptureMouse);
        if dims_ok && win_w > 0 && win_h > 0 {
            pbr_params.cpu.resolution_x = cast(float) win_w;
            pbr_params.cpu.resolution_y = cast(float) win_h;
            ensure_depth_target(cast(u32) win_w, cast(u32) win_h);
        }
        t := cast(float) frame_count * (1.0 / 60.0);
        pbr_params.cpu.time = t;
        if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
            u := cast(float) mx / cast(float) win_w;
            v := cast(float) my / cast(float) win_h;
            if u < 0.0 u = 0.0;
            if u > 1.0 u = 1.0;
            if v < 0.0 v = 0.0;
            if v > 1.0 v = 1.0;

            pbr_params.cpu.light_pos_x = ((1.0 - u) * 2.0 - 1.0) * 2.6;
            pbr_params.cpu.light_pos_y = ((1.0 - v) * 2.0 - 1.0) * 2.0;
            pbr_params.cpu.light_pos_z = 2.4 + sin(t * 0.35) * 0.4;
        } else {
            pbr_params.cpu.light_pos_x = sin(t * 0.35) * 2.2;
            pbr_params.cpu.light_pos_y = 1.8 + sin(t * 0.21) * 0.35;
            pbr_params.cpu.light_pos_z = 2.4 + cos(t * 0.35) * 0.4;
        }
        pbr_params.cpu.camera_pos_x = pbr_camera.position.x;
        pbr_params.cpu.camera_pos_y = pbr_camera.position.y;
        pbr_params.cpu.camera_pos_z = pbr_camera.position.z;
        pbr_params.cpu.indices = pbr_geometry_indices.gpu + cast(Gpu_Ptr) pbr_meshes[pbr_geometry].first_index * size_of(u32);
        draw_data.num_vertices = pbr_meshes[pbr_geometry].index_count;
        if dims_ok && win_w > 0 && win_h > 0 {
            aspect := cast(float) win_w / cast(float) win_h;
            view := editor_camera_make_view(*pbr_camera);
            proj := editor_camera_make_projection(*pbr_camera, aspect, 0.05, 50.0);
            pbr_params.cpu.view_proj = proj * view;
        }
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        depth_target = .{
            view = pbr_depth_view,
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
                clear_color._float = .[0.01, 0.02, 0.03, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .LESS, depth_mode = .READ | .WRITE});
    gpu_set_pipeline(cmd_buff, shader.pipeline);

    draw_result := gpu_draw_instanced_direct(cmd_buff, draw_data.params_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(draw_result == .SUCCESS, tprint("PBR draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

load_texture_rgba8 :: (path: string) -> Gpu_Texture, Gpu_Texture_View {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0, tprint("Failed to load texture: %", path));

    texture_result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(texture_result == .SUCCESS, tprint("Texture creation failed for %: %", path, texture_result));

    assert(texture != 0, tprint("Texture handle invalid for %", path));
    gpu_copy_to_texture(texture, pixels);

    view := gpu_texture_view(texture);
    assert(view != 0, tprint("Texture view creation failed for %", path));

    return texture, view;
}

ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if pbr_depth_view != 0 && pbr_depth_w == width && pbr_depth_h == height return;

    res, pbr_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS);
    assert(pbr_depth_texture != 0, "PBR depth texture creation failed.");

    pbr_depth_view = gpu_texture_view(pbr_depth_texture);
    assert(pbr_depth_view != 0, "PBR depth view creation failed.");

    pbr_depth_w = width;
    pbr_depth_h = height;
    gpu_commit_residency();
}

build_geometry :: () {
    vertices_cpu: [..]Procedural_Geometry_Vertex;
    indices_cpu: [..]u32;
    vertices_cpu.allocator = temp;
    indices_cpu.allocator = temp;

    pbr_meshes[PBR_Geometry.SPHERE]   = procedural_append_uv_sphere(*vertices_cpu, *indices_cpu, 0.9, 32, 18);
    pbr_meshes[PBR_Geometry.TORUS]    = procedural_append_torus(*vertices_cpu, *indices_cpu, 0.8, 0.26, 36, 18);
    pbr_meshes[PBR_Geometry.PRISM]    = procedural_append_prism(*vertices_cpu, *indices_cpu, 0.95, 0.95, 6);
    pbr_meshes[PBR_Geometry.CONE]     = procedural_append_cone(*vertices_cpu, *indices_cpu, 0.85, 2.1, 28);
    pbr_meshes[PBR_Geometry.CYLINDER] = procedural_append_cylinder(*vertices_cpu, *indices_cpu, 0.82, 1.0, 28);
    pbr_meshes[PBR_Geometry.PLANE]    = procedural_append_plane(*vertices_cpu, *indices_cpu, 1.2);

    pbr_geometry_vertices = gpu_alloc_view(*gpu_arena, Procedural_Geometry_Vertex, vertices_cpu.count);
    pbr_geometry_indices = gpu_alloc_view(*gpu_arena, u32, indices_cpu.count);
    memcpy(pbr_geometry_vertices.cpu.data, vertices_cpu.data, vertices_cpu.count * size_of(Procedural_Geometry_Vertex));
    memcpy(pbr_geometry_indices.cpu.data, indices_cpu.data, indices_cpu.count * size_of(u32));
}

#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";
#import "Jai-Shader-Transpiler";
#import "stb_image";
#import "ImGui";
Input :: #import "Input";
#import "Procedural_Geometry";
#load "shaders/pbr_shader.jai";
