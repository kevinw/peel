#load "../SGPU_App_Common.jai";
#load "../readback_stats.jai";

DIRECT_SOURCE :: #string END
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

struct Pixel_Params {
    uint v;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};

struct VertexMain_out {
    float4 gl_Position [[position]];
};

vertex VertexMain_out VertexMain(uint vertex_id [[vertex_id]]) {
    VertexMain_out out = {};
    float2 pos;
    if (vertex_id == 0u) {
        pos = float2(0.0, 0.82);
    } else if (vertex_id == 1u) {
        pos = float2(-0.82, -0.66);
    } else {
        pos = float2(0.82, -0.66);
    }
    out.gl_Position = float4(pos, 0.0, 1.0);
    return out;
}

fragment float4 FragmentMain(VertexMain_out in [[stage_in]], const device Pixel_Params& params [[buffer(0)]]) {
    (void) in;
    float r = min(1.0, float(params.v));
    return float4(r, 0.0, 0.0, 1.0);
}
END;

BINDLESS_STRUCT_SOURCE :: #string END
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

struct Pixel_Params {
    uint v;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};

struct Bindless_Set0 {
    constant Pixel_Params* params [[id(0)]];
};

struct VertexMain_out {
    float4 gl_Position [[position]];
};

vertex VertexMain_out VertexMain(uint vertex_id [[vertex_id]]) {
    VertexMain_out out = {};
    float2 pos;
    if (vertex_id == 0u) {
        pos = float2(0.0, 0.82);
    } else if (vertex_id == 1u) {
        pos = float2(-0.82, -0.66);
    } else {
        pos = float2(0.82, -0.66);
    }
    out.gl_Position = float4(pos, 0.0, 1.0);
    return out;
}

fragment float4 FragmentMain(VertexMain_out in [[stage_in]], constant Bindless_Set0* bindless [[buffer(0)]]) {
    (void) in;
    float r = min(1.0, float((*(bindless->params)).v));
    return float4(r, 0.0, 0.0, 1.0);
}
END;

Draw_Data :: struct {
    pixel_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

Pixel_Params :: struct {
    v: u32;
    _pad0: u32;
    _pad1: u32;
    _pad2: u32;
}

graphics_pipeline: Gpu_Pipeline;
draw_data: Draw_Data;
readback_state: Readback_Stats;
use_bindless_struct := false;

on_dll_init :: () {
    readback_stats_init(*readback_state, "M4_BINDLESS_PROBE", snapshot_default_w = 128, snapshot_default_h = 128, enable_export_jpg = false);
    if readback_stats_needs_swapchain_readback(*readback_state) {
        gpu_set_swapchain_framebuffer_only(false);
    }

    probe_mode_env, _ := readback_stats_env_int("PEEL_BINDLESS_STRUCT_MODE");
    use_bindless_struct = probe_mode_env > 0;

    source: []u8;
    if use_bindless_struct {
        source = cast([]u8) BINDLESS_STRUCT_SOURCE;
    } else {
        source = cast([]u8) DIRECT_SOURCE;
    }

    graphics_pipeline = gpu_create_graphics_pipeline(source, .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });
    assert(graphics_pipeline != 0, "Probe graphics pipeline creation failed.");

    pixel_cpu, pixel_gpu := gpu_malloc(Pixel_Params);
    pixel_cpu.* = .{
        v = 1,
        _pad0 = 0,
        _pad1 = 0,
        _pad2 = 0,
    };

    draw_data = .{
        pixel_gpu = pixel_gpu,
        num_vertices = 3,
        num_instances = 1,
    };

    log("M4_BINDLESS_PROBE mode=% pixel_gpu=0x%", ifx use_bindless_struct then "bindless_struct" else "direct", formatInt(cast(u64) pixel_gpu, base=16));

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

    draw_result := gpu_draw_instanced(cmd_buff, draw_data.pixel_gpu, draw_data.pixel_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(draw_result == .SUCCESS, tprint("Probe draw failed: %", draw_result));

    gpu_submit_and_present(cmd_buff);

    frame_num := cast(s64) frame_count;
    if readback_stats_should_sample(*readback_state, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(*readback_state, "M4_BINDLESS_PROBE", frame_num, stats);
            readback_stats_maybe_dump_snapshot(*readback_state, swapchain_image, frame_num, "m4_bindless_probe_snapshot", "M4_BINDLESS_PROBE");
        }
        if readback_stats_advance_sample(*readback_state) {
            app_quit_requested = true;
        }
    }
} @on_tick

#scope_file
#import "Window_Creation";
