WRITE_SHADER_OUTPUT :: true;

PBR_ALBEDO_PATH :: "./textures/Snow/Snow015_2K-JPG_Color.jpg";
PBR_NORMAL_PATH :: "./textures/Snow/Snow015_2K-JPG_NormalGL.jpg";
PBR_ROUGHNESS_PATH :: "./textures/Snow/Snow015_2K-JPG_Roughness.jpg";
PBR_AO_PATH :: "./textures/Snow/Snow015_2K-JPG_AmbientOcclusion.jpg";
PBR_DISPLACEMENT_PATH :: "./textures/Snow/Snow015_2K-JPG_Displacement.jpg";

PBR_TEXTURE_COUNT :: 5;
PBR_TEX_ALBEDO :: 0;
PBR_TEX_NORMAL :: 1;
PBR_TEX_ROUGHNESS :: 2;
PBR_TEX_AO :: 3;
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

pbr_readback: Readback_Stats;
window_snapshot_mode := false;
window_validate_mode := false;
window_probe_auto_quit := false;
pbr_smoke_mode := false;
pbr_debug_mode: u32 = 0;


on_dll_init :: () {
    frame_debug_init();
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
    log("Loading textures...");
    pbr_textures[PBR_TEX_ALBEDO], pbr_views[PBR_TEX_ALBEDO] = load_texture_rgba8(PBR_ALBEDO_PATH);
    pbr_textures[PBR_TEX_NORMAL], pbr_views[PBR_TEX_NORMAL] = load_texture_rgba8(PBR_NORMAL_PATH);
    pbr_textures[PBR_TEX_ROUGHNESS], pbr_views[PBR_TEX_ROUGHNESS] = load_texture_rgba8(PBR_ROUGHNESS_PATH);
    pbr_textures[PBR_TEX_AO], pbr_views[PBR_TEX_AO] = load_texture_rgba8(PBR_AO_PATH);
    pbr_textures[PBR_TEX_DISPLACEMENT], pbr_views[PBR_TEX_DISPLACEMENT] = load_texture_rgba8(PBR_DISPLACEMENT_PATH);
    log("Loaded textures.");

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
        debug_mode = pbr_debug_mode,
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
    result, swapchain_image := gpu_swapchain_acquire();
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

    per_frame_debug(cast(s64)frame_count, swapchain_image);
} @on_tick

#scope_file


frame_debug_init :: () {
    readback_stats_init(*pbr_readback, "PBR", snapshot_default_w = 128, snapshot_default_h = 128, enable_export_jpg = true);

    smoke_mode_env,      _ := readback_stats_env_int("PEEL_SMOKE");
    window_snapshot_env, _ := readback_stats_env_int("PEEL_WINDOW_SNAPSHOT");
    window_validate_env, _ := readback_stats_env_int("PEEL_WINDOW_VALIDATE");
    pbr_debug_mode_env,  _ := readback_stats_env_int("PEEL_PBR_DEBUG_MODE");

    if smoke_mode_env > 0      pbr_smoke_mode = true;
    if window_snapshot_env > 0 window_snapshot_mode = true;
    if window_validate_env > 0 window_validate_mode = true;
    if pbr_debug_mode_env > 0  pbr_debug_mode = cast(u32) pbr_debug_mode_env;

    if pbr_smoke_mode {
        pbr_readback.test_readback = true;
        window_probe_auto_quit = true;
    }
    if window_snapshot_mode || window_validate_mode window_probe_auto_quit = true;

    if readback_stats_needs_swapchain_readback(*pbr_readback) || window_snapshot_mode || window_validate_mode {
        gpu_set_swapchain_framebuffer_only(false);
    }

}

per_frame_debug :: (frame_num: s64, swapchain_image: Gpu_Texture_View) {
    if frame_num >= 2 && window_snapshot_mode {
        window_snapshot_path := tprint("./pbr_window_frame_%.jpeg", frame_num);
        gpu_dump_to_bitmap(window_snapshot_path);
        log("PBR_WINDOW_SNAPSHOT frame=% path=%", frame_num, window_snapshot_path);
        window_snapshot_mode = false;
    }
    if frame_num >= 2 && window_validate_mode {
        ok := gpu_validate_window_readback_non_black();
        assert(ok, "PBR window capture validation failed: output appears black.");
        window_validate_mode = false;
    }
    if frame_num >= 2 && window_probe_auto_quit && !window_snapshot_mode && !window_validate_mode {
        log("PBR_WINDOW_PROBE completed; quitting.");
        app_quit_requested = true;
    }

    if readback_stats_should_sample(*pbr_readback, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(*pbr_readback, "PBR", frame_num, stats);
            readback_stats_maybe_dump_snapshot(*pbr_readback, swapchain_image, frame_num, "pbr_snapshot", "PBR");
        }
        if readback_stats_advance_sample(*pbr_readback) {
            log("PBR_FRAMEBUFFER_STATS completed % samples; quitting.", pbr_readback.stats_max_samples);
            app_quit_requested = true;
        }
    }

    assert(readback_stats_maybe_run_readback_check(*pbr_readback, swapchain_image, "pbr_metal"),
           "PBR readback check failed: output appears uniform/black.");
}

load_texture_rgba8 :: (path: string) -> Gpu_Texture, Gpu_Texture_View {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0, tprint("Failed to load texture: %", path));

    texture: Gpu_Texture;
    #if OS == .MACOS {
        texture = gpu_create_texture(.{
            dimensions = .[cast(u32) width, cast(u32) height, 1],
            format = .B8G8R8A8_UNORM,
            usage = .SAMPLED | .TRANSFER_DST,
        });
    } else {
        texture_result: Gpu_Result;
        texture_result, texture = gpu_create_texture(.{
            dimensions = .[cast(u32) width, cast(u32) height, 1],
            format = .B8G8R8A8_UNORM,
            usage = .SAMPLED | .TRANSFER_DST,
        });
        assert(texture_result == .SUCCESS, tprint("Texture creation failed for %: %", path, texture_result));
    }

    assert(texture != 0, tprint("Texture handle invalid for %", path));
    gpu_copy_to_texture(texture, pixels);

    view := gpu_texture_view(texture);
    assert(view != 0, tprint("Texture view creation failed for %", path));

    return texture, view;
}

ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if pbr_depth_view != 0 && pbr_depth_w == width && pbr_depth_h == height return;

    pbr_depth_texture = gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(pbr_depth_texture != 0, "PBR depth texture creation failed.");

    pbr_depth_view = gpu_texture_view(pbr_depth_texture);
    assert(pbr_depth_view != 0, "PBR depth view creation failed.");

    pbr_depth_w = width;
    pbr_depth_h = height;
    gpu_commit_residency();
}

#import "Window_Creation";
#load "../SGPU_App_Common.jai";
#load "../readback_stats.jai";

#import "Jai-Shader-Transpiler";
#import "stb_image";
#load "shaders/pbr_shader.jai";
