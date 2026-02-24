TEX_TEMPL :: "./textures/Snow/Snow015_2K-JPG_%.jpg";
PBR_ALBEDO_PATH       :: #run sprint(TEX_TEMPL, "Color");
PBR_NORMAL_PATH       :: #run sprint(TEX_TEMPL, "NormalGL");
PBR_ROUGHNESS_PATH    :: #run sprint(TEX_TEMPL, "Roughness");
PBR_AO_PATH           :: #run sprint(TEX_TEMPL, "AmbientOcclusion");
PBR_DISPLACEMENT_PATH :: #run sprint(TEX_TEMPL, "Displacement");

PBR_TEXTURE_COUNT    :: 5;
PBR_TEX_ALBEDO       :: 0;
PBR_TEX_NORMAL       :: 1;
PBR_TEX_ROUGHNESS    :: 2;
PBR_TEX_AO           :: 3;
PBR_TEX_DISPLACEMENT :: 4;

Draw_Data :: struct {
    params_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;
pbr_params_cpu: *PBR_Params;

pbr_textures: [PBR_TEXTURE_COUNT] Gpu_Texture;
pbr_views:    [PBR_TEXTURE_COUNT] Gpu_Texture_View;
pbr_sampler: Gpu_Sampler;
pbr_depth_texture: Gpu_Texture;
pbr_depth_view: Gpu_Texture_View;
pbr_depth_w: u32;
pbr_depth_h: u32;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, pbr_vertex_main, pbr_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for PBR shaders.");

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, .{
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });
    assert(graphics_pipeline != 0, "PBR graphics pipeline creation failed.");

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

    gpu_arena = gpu_make_arena(128 * 1024, label = "pbr arena");

    params_gpu: Gpu_Ptr;
    pbr_params_cpu, params_gpu = gpu_malloc(PBR_Params);
    pbr_params_cpu.* = .{
        albedo_index = cast(u32) pbr_views[PBR_TEX_ALBEDO] - 1,
        normal_index = cast(u32) pbr_views[PBR_TEX_NORMAL] - 1,
        roughness_index = cast(u32) pbr_views[PBR_TEX_ROUGHNESS] - 1,
        ao_index = cast(u32) pbr_views[PBR_TEX_AO] - 1,
        displacement_index = cast(u32) pbr_views[PBR_TEX_DISPLACEMENT] - 1,

        sampler_index = cast(u32) pbr_sampler - 1,
        debug_mode = debug_mode,
        _pad0 = 0,
        _pad1 = 0,

        light_pos_x = 1.8,
        light_pos_y = 2.4,
        light_pos_z = 1.6,
        light_intensity = 26.0,

        light_color_r = 1.0,
        light_color_g = 0.98,
        light_color_b = 0.95,
        metallic = 0.02,

        camera_pos_x = 0.0,
        camera_pos_y = 0.2,
        camera_pos_z = 3.2,
        resolution_x = 1280.0,
        resolution_y = 720.0,
        time = 0.0,
        displacement_strength = 0.18,
        uv_scale = 5.0,
    };

    draw_data = .{
        params_gpu = params_gpu,
        num_vertices = PBR_SPHERE_SEG_X * PBR_SPHERE_SEG_Y * 6,
        num_instances = 1,
    };

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_depth_target(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    {
        using pbr_params_cpu;
        mx, my, mouse_ok := get_mouse_pointer_position(true);
        _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
        if dims_ok && win_w > 0 && win_h > 0 {
            resolution_x = cast(float) win_w;
            resolution_y = cast(float) win_h;
            ensure_depth_target(cast(u32) win_w, cast(u32) win_h);
        }
        t := cast(float) frame_count * (1.0 / 60.0);
        time = t;
        if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
            u := cast(float) mx / cast(float) win_w;
            v := cast(float) my / cast(float) win_h;
            if u < 0.0 u = 0.0;
            if u > 1.0 u = 1.0;
            if v < 0.0 v = 0.0;
            if v > 1.0 v = 1.0;

            light_pos_x = ((1.0 - u) * 2.0 - 1.0) * 2.6;
            light_pos_y = ((1.0 - v) * 2.0 - 1.0) * 2.0;
            light_pos_z = 2.4 + sin(t * 0.35) * 0.4;
        } else {
            light_pos_x = sin(t * 0.35) * 2.2;
            light_pos_y = 1.8 + sin(t * 0.21) * 0.35;
            light_pos_z = 2.4 + cos(t * 0.35) * 0.4;
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
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced_direct(cmd_buff, draw_data.params_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(draw_result == .SUCCESS, tprint("PBR draw failed: %", draw_result));

    gpu_submit_and_present(cmd_buff);
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

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "stb_image";
#load "shaders/pbr_shader.jai";
