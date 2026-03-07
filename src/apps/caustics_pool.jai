Caustics_Pool_Params :: struct {
    resolution: Vector2;
    time: float;
    speed: float;

    scale: float;
    contrast: float;
    shimmer: float;
    tint_mix: float;

    glow: float;
    vignette: float;
    foam: float;
    _pad0: float;
}

Caustics_Pool_State :: struct {
    speed: float;
    scale: float;
    contrast: float;
    shimmer: float;
    tint_mix: float;
    glow: float;
    vignette: float;
    foam: float;
    ui_open: bool;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
params_cpu: *Caustics_Pool_Params;
params_gpu: Gpu_Ptr;
caustics_pool: Caustics_Pool_State = .{
    speed = 0.9,
    scale = 5.5,
    contrast = 1.55,
    shimmer = 0.45,
    tint_mix = 0.62,
    glow = 1.05,
    vignette = 0.28,
    foam = 0.22,
    ui_open = true,
};

on_dll_init :: () {
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_pipeline = gpu_create_graphics_pipeline(cast([]u8) CAUSTICS_POOL_GRAPHICS_SOURCE, raster_desc);
    assert(graphics_pipeline != 0, "Caustics pool pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "caustics pool arena");
    params_cpu, params_gpu = gpu_arena_alloc(*gpu_arena, Caustics_Pool_Params);
    params_cpu.* = .{
        resolution = .{1280.0, 720.0},
        time = 0.0,
        speed = caustics_pool.speed,
        scale = caustics_pool.scale,
        contrast = caustics_pool.contrast,
        shimmer = caustics_pool.shimmer,
        tint_mix = caustics_pool.tint_mix,
        glow = caustics_pool.glow,
        vignette = caustics_pool.vignette,
        foam = caustics_pool.foam,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }

    params_cpu.time = cast(float) time;
    params_cpu.speed = caustics_pool.speed;
    params_cpu.scale = caustics_pool.scale;
    params_cpu.contrast = caustics_pool.contrast;
    params_cpu.shimmer = caustics_pool.shimmer;
    params_cpu.tint_mix = caustics_pool.tint_mix;
    params_cpu.glow = caustics_pool.glow;
    params_cpu.vignette = caustics_pool.vignette;
    params_cpu.foam = caustics_pool.foam;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.06, 0.09, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    pipeline_result := gpu_set_pipeline(cmd_buff, graphics_pipeline);
    assert(pipeline_result == .SUCCESS, tprint("Caustics pool pipeline bind failed: %", pipeline_result));
    draw_result := gpu_draw_instanced(cmd_buff, 0, params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Caustics pool draw failed: %", draw_result));

    draw_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
ImGui :: #import "ImGui";

draw_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    SetNextWindowPos(.{28.0, 28.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 260.0}, .FirstUseEver);

    if Begin("Caustics Pool", *caustics_pool.ui_open, flags = .NoCollapse) {
        Text("Procedural water-light caustics study.");
        SliderFloat("Speed", *caustics_pool.speed, 0.1, 2.0);
        SliderFloat("Scale", *caustics_pool.scale, 1.5, 9.0);
        SliderFloat("Contrast", *caustics_pool.contrast, 0.4, 2.5);
        SliderFloat("Shimmer", *caustics_pool.shimmer, 0.0, 1.0);
        SliderFloat("Tint Mix", *caustics_pool.tint_mix, 0.0, 1.0);
        SliderFloat("Glow", *caustics_pool.glow, 0.0, 2.0);
        SliderFloat("Vignette", *caustics_pool.vignette, 0.0, 1.0);
        SliderFloat("Foam", *caustics_pool.foam, 0.0, 0.7);
    }
    End();
}

CAUSTICS_POOL_GRAPHICS_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Caustics_Pool_Params {
    float2 resolution;
    float time;
    float speed;
    float scale;
    float contrast;
    float shimmer;
    float tint_mix;
    float glow;
    float vignette;
    float foam;
    float _pad0;
};

struct Vertex_Out {
    float4 position [[position]];
    float2 uv;
};

vertex Vertex_Out VertexMain(uint vertex_id [[vertex_id]]) {
    Vertex_Out out;
    float2 pos;
    if (vertex_id == 0) {
        pos = float2(-1.0, -1.0);
    } else if (vertex_id == 1) {
        pos = float2(3.0, -1.0);
    } else {
        pos = float2(-1.0, 3.0);
    }

    out.position = float4(pos, 0.0, 1.0);
    out.uv = pos * 0.5 + 0.5;
    return out;
}

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(41.0, 289.0))) * 45758.5469);
}

static float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float field(float2 p, float t) {
    float total = 0.0;
    float weight = 0.6;
    float2 q = p;
    for (uint i = 0; i < 4; ++i) {
        float n = noise2(q + float2(t * 0.19, -t * 0.14));
        total += abs(sin((q.x + q.y + n * 1.4) * 3.14159)) * weight;
        q = float2(
            q.x * 1.73 - q.y * 0.64,
            q.x * 0.64 + q.y * 1.73
        ) + float2(3.1, -1.7);
        weight *= 0.55;
    }
    return total;
}

fragment float4 FragmentMain(Vertex_Out in [[stage_in]], constant Caustics_Pool_Params *params [[buffer(0)]]) {
    float2 uv = in.uv;
    float aspect = params->resolution.x / max(params->resolution.y, 1.0);
    float2 p = float2((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0);
    float t = params->time * params->speed;

    float2 drift = float2(sin(t * 0.7), cos(t * 0.53)) * 0.12;
    float2 ripple_uv = p * params->scale + drift;
    float caustic = field(ripple_uv, t);
    float caustic_b = field(ripple_uv * 1.17 + float2(2.4, -1.3), t * 1.13);

    float pattern = abs(caustic - caustic_b);
    pattern = pow(clamp(pattern, 0.0, 1.0), max(0.2, 2.4 - params->contrast));

    float shimmer = sin((p.x - p.y) * 14.0 + t * 6.5) * 0.5 + 0.5;
    pattern += shimmer * params->shimmer * 0.18;

    float foam = smoothstep(0.74 - params->foam * 0.35, 1.0, pattern);
    float glow = smoothstep(0.42, 1.0, pattern) * params->glow;

    float3 deep = float3(0.03, 0.17, 0.24);
    float3 aqua = float3(0.08, 0.48, 0.56);
    float3 sun  = float3(0.88, 0.98, 0.85);
    float3 tint = mix(aqua, float3(0.19, 0.62, 0.68), params->tint_mix);

    float3 color = mix(deep, tint, clamp(pattern * 0.7 + 0.15, 0.0, 1.0));
    color += sun * (glow * 0.45 + foam * 0.35);

    float vignette = pow(clamp(1.0 - dot(p, p) * 0.22, 0.0, 1.0), 1.0 + params->vignette * 2.2);
    color *= mix(1.0, vignette, params->vignette);
    color = clamp(color, 0.0, 1.0);

    return float4(color, 1.0);
}
END
