WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";
#load "../readback_stats.jai";

#import "Jai-Shader-Transpiler";
#load "../textured_triangle_shader.jai";

USE_HANDCRAFTED_METAL :: false;

HANDCRAFTED_METAL_SOURCE :: #string END
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

struct VertexMain_out
{
    float2 uv [[user(locn0)]];
    float4 gl_Position [[position]];
};
struct Pixel_Params
{
    uint texture_index;
    uint sampler_index;
    uint debug_mode;
    uint _pad;
};
vertex VertexMain_out VertexMain(uint vertex_id [[vertex_id]])
{
    VertexMain_out out = {};
    float2 pos;
    float2 uv;
    if (vertex_id == 0u)
    {
        pos = float2(0.0, 0.82);
        uv = float2(0.5, 1.0);
    }
    else if (vertex_id == 1u)
    {
        pos = float2(-0.82, -0.66);
        uv = float2(0.0, 0.0);
    }
    else
    {
        pos = float2(0.82, -0.66);
        uv = float2(1.0, 0.0);
    }
    out.gl_Position = float4(pos, 0.0, 1.0);
    out.uv = uv;
    return out;
}
struct FragmentMain_out
{
    float4 out_color [[color(0)]];
};
fragment FragmentMain_out FragmentMain(VertexMain_out in [[stage_in]],
                                       const device Pixel_Params& params [[buffer(0)]],
                                       array<texture2d<float>, 16> sample_2d_textures [[texture(0)]],
                                       array<sampler, 16> sample_2d_samplers [[sampler(0)]])
{
    FragmentMain_out out = {};
    if ((params.debug_mode & 1u) != 0u) {
        out.out_color = float4(min(1.0, float(params.texture_index)), min(1.0, float(params.sampler_index)), 0.0, 1.0);
    } else {
        out.out_color = sample_2d_textures[params.texture_index].sample(sample_2d_samplers[params.sampler_index], in.uv);
    }
    return out;
}
END;

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
textured_triangle_readback: Readback_Stats;
window_snapshot_mode := false;
window_validate_mode := false;
window_probe_auto_quit := false;
tt_smoke_mode := false;
tt_debug_mode: u32 = 0;

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
    readback_stats_init(*textured_triangle_readback, "TEXTURED_TRIANGLE", snapshot_default_w = 128, snapshot_default_h = 128, enable_export_jpg = true);
    smoke_mode_env, _ := readback_stats_env_int("PEEL_SMOKE");
    window_snapshot_env, _ := readback_stats_env_int("PEEL_WINDOW_SNAPSHOT");
    window_validate_env, _ := readback_stats_env_int("PEEL_WINDOW_VALIDATE");
    tt_debug_mode_env, _ := readback_stats_env_int("PEEL_TT_DEBUG_MODE");
    if smoke_mode_env > 0 tt_smoke_mode = true;
    if window_snapshot_env > 0 window_snapshot_mode = true;
    if window_validate_env > 0 window_validate_mode = true;
    if tt_debug_mode_env > 0 tt_debug_mode = 1;
    if tt_smoke_mode {
        textured_triangle_readback.test_readback = true;
        window_probe_auto_quit = true;
    }
    if window_snapshot_mode || window_validate_mode window_probe_auto_quit = true;

    if readback_stats_needs_swapchain_readback(*textured_triangle_readback) || window_snapshot_mode || window_validate_mode {
        gpu_set_swapchain_framebuffer_only(false);
    }

    graphics_source: []u8;
    if USE_HANDCRAFTED_METAL {
        graphics_source = cast([]u8) HANDCRAFTED_METAL_SOURCE;
    } else {
        graphics_source = cast([]u8) get_transpiled(.METAL, textured_triangle_vertex_main, textured_triangle_fragment_main);
    }
    assert(graphics_source.count > 0, "Transpilation failed for textured triangle shaders.");

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });
    assert(graphics_pipeline != 0, "Textured triangle graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024, label = "textured triangle arena");

    #if OS == .MACOS {
        noise_texture = gpu_create_texture(.{
            dimensions = .[NOISE_W, NOISE_H, 1],
            format = .B8G8R8A8_UNORM,
            usage = .SAMPLED | .TRANSFER_DST,
        });
    } else {
        texture_result: Gpu_Result;
        texture_result, noise_texture = gpu_create_texture(.{
            dimensions = .[NOISE_W, NOISE_H, 1],
            format = .B8G8R8A8_UNORM,
            usage = .SAMPLED | .TRANSFER_DST,
        });
        assert(texture_result == .SUCCESS, tprint("Textured triangle texture creation failed: %", texture_result));
    }
    assert(noise_texture != 0, "Textured triangle texture creation returned null handle.");
    noise_texture_view = gpu_texture_view(noise_texture);
    assert(noise_texture_view != 0, "Textured triangle texture-view creation failed.");
    noise_sampler = gpu_create_sampler(.{
        compare_op = .NEVER,
    });
    assert(noise_sampler != 0, "Textured triangle sampler creation failed.");

    noise_pixels, _ := gpu_arena_alloc(*gpu_arena, [NOISE_BYTE_COUNT] u8);
    noise_fill_rgba8(noise_pixels);
    gpu_copy_to_texture(noise_texture, noise_pixels);

    pixel_params_cpu, pixel_gpu := gpu_malloc(Textured_Triangle_Pixel_Params);
    pixel_params_cpu.* = .{
        texture_index = cast(u32) noise_texture_view - 1,
        sampler_index = cast(u32) noise_sampler - 1,
        debug_mode = tt_debug_mode,
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
    result, swapchain_image := gpu_swapchain_acquire();
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

    gpu_submit_and_present(cmd_buff);

    frame_num := cast(s64) frame_count;
    if frame_num >= 2 && window_snapshot_mode {
        window_snapshot_path := tprint("./textured_triangle_window_frame_%.jpeg", frame_num);
        gpu_dump_to_bitmap(window_snapshot_path);
        log("TEXTURED_TRIANGLE_WINDOW_SNAPSHOT frame=% path=%", frame_num, window_snapshot_path);
        window_snapshot_mode = false;
    }
    if frame_num >= 2 && window_validate_mode {
        ok := gpu_validate_window_readback_non_black();
        assert(ok, "Textured triangle window capture validation failed: output appears black.");
        window_validate_mode = false;
    }
    if frame_num >= 2 && window_probe_auto_quit && !window_snapshot_mode && !window_validate_mode {
        log("TEXTURED_TRIANGLE_WINDOW_PROBE completed; quitting.");
        app_quit_requested = true;
    }
    if readback_stats_should_sample(*textured_triangle_readback, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(*textured_triangle_readback, "TEXTURED_TRIANGLE", frame_num, stats);
            readback_stats_maybe_dump_snapshot(*textured_triangle_readback, swapchain_image, frame_num, "textured_triangle_snapshot", "TEXTURED_TRIANGLE");
        }
        if readback_stats_advance_sample(*textured_triangle_readback) {
            log("TEXTURED_TRIANGLE_FRAMEBUFFER_STATS completed % samples; quitting.", textured_triangle_readback.stats_max_samples);
            app_quit_requested = true;
        }
    }
    assert(readback_stats_maybe_run_readback_check(*textured_triangle_readback, swapchain_image, "textured_triangle_metal"),
           "Textured triangle readback check failed: output appears uniform/black.");
} @on_tick

#scope_file
#import "Window_Creation";
