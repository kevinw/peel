WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

SHR :: #import,file "../shader_hot_reload.jai";
#import "Math";
#import "ImGui";

#load "shaders/texture3d_shader.jai";

TEXTURE3D_SIZE :: 128;
TEXTURE3D_VOXEL_COUNT :: TEXTURE3D_SIZE * TEXTURE3D_SIZE * TEXTURE3D_SIZE;

graphics_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

texture3d_params_cpu: *Texture3D_Params;
texture3d_params_gpu: Gpu_Ptr;
show_texture: bool = true;

volume_texture: Gpu_Texture;
volume_texture_view: Gpu_Texture_View;
volume_sampler: Gpu_Sampler;

volume_needs_init := true;
texture3d_ui_open := true;
texture3d_animate_volume := true;

on_dll_init :: () {
    compute_source := cast([]u8) get_transpiled(.METAL, texture3d_compute_main);
    assert(compute_source.count > 0, "Transpilation failed for texture3d compute shader.");
    graphics_source := cast([]u8) get_transpiled(.METAL, texture3d_vertex_main, texture3d_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for texture3d graphics shaders.");

    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, texture3d_vertex_main, texture3d_fragment_main);
    assert(graphics_ok, "texture3d graphics pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_pipeline, compute_source, .METAL, texture3d_compute_main);
    assert(compute_ok, "texture3d compute pipeline creation failed.");

    texture_result, volume_texture= := gpu_create_texture(.{
        type = ._3D,
        dimensions = .[TEXTURE3D_SIZE, TEXTURE3D_SIZE, TEXTURE3D_SIZE],
        format = .R32_SFLOAT,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("texture3d texture creation failed: %", texture_result));
    assert(volume_texture != 0, "texture3d texture creation returned null handle.");
    volume_texture_view = gpu_texture_view(volume_texture);
    assert(volume_texture_view != 0, "texture3d texture view creation failed.");

    volume_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(volume_sampler != 0, "texture3d sampler creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "texture3d arena");
    texture3d_params_cpu, texture3d_params_gpu = gpu_arena_alloc(*gpu_arena, Texture3D_Params);
    texture3d_params_cpu.* = .{
        texture_index = cast(u32) volume_texture_view - 1,
        sampler_index = cast(u32) volume_sampler - 1,
        volume_size = TEXTURE3D_SIZE,
        flags = 1,
        time = 0.0,
        density_scale = 1.6,
        absorption = 6.0,
        march_steps = 72.0,
        resolution = .{1280.0, 720.0},
        _pad0 = .{0.0, 0.0},
    };

    gpu_commit_residency();
} @on_dll_init

texture3d_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{380.0, 220.0}, .FirstUseEver);
    if Begin("Texture3D", *texture3d_ui_open, flags = .NoCollapse) {
        Text("3D texture fog raymarch (Metal)");
        Checkbox("Show Texture", *show_texture);
        Text("Volume: %^3 R32_SFLOAT", TEXTURE3D_SIZE);
        if Button("Rebuild Volume") volume_needs_init = true;
        Checkbox("Animate Volume", *texture3d_animate_volume);
        SliderFloat("Density Scale", *texture3d_params_cpu.density_scale, 0.2, 4.0);
        SliderFloat("Absorption", *texture3d_params_cpu.absorption, 0.5, 12.0);
        SliderFloat("March Steps", *texture3d_params_cpu.march_steps, 24.0, 144.0);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled texture3d_ui();

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        texture3d_params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    if texture3d_animate_volume {
        texture3d_params_cpu.time = cast(float) time;
        texture3d_params_cpu.flags = 1;
        volume_needs_init = true;
    } else {
        texture3d_params_cpu.flags = 0;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if volume_needs_init {
        compute_result := gpu_set_pipeline(cmd_buff, compute_pipeline);
        assert(compute_result == .SUCCESS, tprint("texture3d compute set pipeline failed: %", compute_result));
        groups_x := cast(u32) (TEXTURE3D_VOXEL_COUNT + 63) / 64;
        gpu_dispatch_buffers(cmd_buff, .[texture3d_params_gpu], .[groups_x, 1, 1]);
        gpu_barrier(cmd_buff, .COMPUTE_SHADER, .PIXEL_SHADER);
        volume_needs_init = false;
    }

    if show_texture {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.06, 0.08, 0.12, 1.0],
                }
            ]
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, graphics_pipeline);
        draw_result := gpu_draw_instanced(cmd_buff, 0, texture3d_params_gpu, 3, 1);
        assert(draw_result == .SUCCESS, tprint("texture3d draw failed: %", draw_result));
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick
