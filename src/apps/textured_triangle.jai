NOISE_W :: 128;
NOISE_H :: 128;
NOISE_BYTE_COUNT :: NOISE_W * NOISE_H * 4;

Draw_Data :: struct {
    pixel_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;
pixel_params_cpu: *Textured_Triangle_Pixel_Params;

noise_texture: Gpu_Texture;
noise_texture_view: Gpu_Texture_View;
noise_sampler: Gpu_Sampler;

noise_fill_rgba8 :: (pixels: *[NOISE_BYTE_COUNT] u8) {
    for y: 0..NOISE_H - 1 {
        for x: 0..NOISE_W - 1 {
            i := y * NOISE_W + x;
            idx := i * 4;
            // Deterministic checker + gradients so texture sampling is visibly non-uniform.
            r := cast(u8) ((x * 255) / (NOISE_W - 1));
            g := cast(u8) ((y * 255) / (NOISE_H - 1));
            checker := cast(u8) 32;
            if (((x / 8) + (y / 8)) & 1) == 0 checker = 220;
            b := checker;
            pixels.*[idx + 0] = b;
            pixels.*[idx + 1] = g;
            pixels.*[idx + 2] = r;
            pixels.*[idx + 3] = 255;
        }
    }
}

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, textured_triangle_vertex_main, textured_triangle_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for textured triangle shaders.");
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, textured_triangle_vertex_main, textured_triangle_fragment_main);
    assert(graphics_ok, "Textured triangle graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024, label = "textured triangle arena");

    texture_result, noise_texture= := gpu_create_texture({
        dimensions = .[NOISE_W, NOISE_H, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(texture_result == .SUCCESS, tprint("Textured triangle texture creation failed: %", texture_result));
    assert(noise_texture != 0, "Textured triangle texture creation returned null handle.");
    noise_texture_view = gpu_texture_view(noise_texture);
    assert(noise_texture_view != 0, "Textured triangle texture-view creation failed.");
    noise_sampler = gpu_create_sampler({ compare_op = .NEVER });
    assert(noise_sampler != 0, "Textured triangle sampler creation failed.");

    noise_pixels, _ := gpu_arena_alloc(*gpu_arena, [NOISE_BYTE_COUNT] u8);
    noise_fill_rgba8(noise_pixels);
    gpu_copy_to_texture(noise_texture, noise_pixels);

    pixel_params_cpu, pixel_gpu := gpu_malloc(Textured_Triangle_Pixel_Params);
    pixel_params_cpu.* = .{
        texture_index = cast(u32) noise_texture_view - 1,
        sampler_index = cast(u32) noise_sampler - 1,
        debug_mode = debug_mode,
        _pad = 0,
    };
    draw_data = .{
        pixel_gpu = pixel_gpu,
        num_vertices = 3,
        num_instances = 1,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0, 0, 0, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced_direct(cmd_buff, draw_data.pixel_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(draw_result == .SUCCESS, tprint("Textured triangle draw failed: %", draw_result));

    if app_ui_enabled {
        using ImGui;
        if Begin("Textured Triangle") {
            Text("Hello, triangle!");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/textured_triangle_shader.jai";
#import "Random";
ImGui :: #import "ImGui";
