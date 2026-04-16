Signal_Field_Params :: struct {
    resolution: Vector2;
    time: float;
    speed: float;

    band_scale: float;
    warp_strength: float;
    glow_strength: float;
    vignette_strength: float;

    palette_mix: float;
    grain_strength: float;
    _pad0: float;
    _pad1: float;
}

Signal_Field_State :: struct {
    speed: float;
    band_scale: float;
    warp_strength: float;
    glow_strength: float;
    vignette_strength: float;
    palette_mix: float;
    grain_strength: float;
    ui_open: bool;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
params: Gpu_Buffer(Signal_Field_Params);
signal_field: Signal_Field_State = .{
    speed = 0.85,
    band_scale = 4.2,
    warp_strength = 0.42,
    glow_strength = 1.15,
    vignette_strength = 0.58,
    palette_mix = 0.34,
    grain_strength = 0.035,
    ui_open = true,
};

on_dll_init :: () {
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_pipeline = gpu_create_graphics_pipeline(cast([]u8) SIGNAL_FIELD_GRAPHICS_SOURCE, raster_desc);
    assert(graphics_pipeline != 0, "Signal field pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "signal field arena");
    params = gpu_alloc_buffer(*gpu_arena, Signal_Field_Params);
    params.cpu.* = .{
        resolution = .{1280.0, 720.0},
        time = 0.0,
        speed = signal_field.speed,
        band_scale = signal_field.band_scale,
        warp_strength = signal_field.warp_strength,
        glow_strength = signal_field.glow_strength,
        vignette_strength = signal_field.vignette_strength,
        palette_mix = signal_field.palette_mix,
        grain_strength = signal_field.grain_strength,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    render_w, render_h := app_current_render_dimensions();
    if render_w > 0 && render_h > 0 {
        params.cpu.resolution = .{cast(float) render_w, cast(float) render_h};
    }

    params.cpu.time = cast(float) time;
    params.cpu.speed = signal_field.speed;
    params.cpu.band_scale = signal_field.band_scale;
    params.cpu.warp_strength = signal_field.warp_strength;
    params.cpu.glow_strength = signal_field.glow_strength;
    params.cpu.vignette_strength = signal_field.vignette_strength;
    params.cpu.palette_mix = signal_field.palette_mix;
    params.cpu.grain_strength = signal_field.grain_strength;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.03, 0.05, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    pipeline_result := gpu_set_pipeline(cmd_buff, graphics_pipeline);
    assert(pipeline_result == .SUCCESS, tprint("Signal field pipeline bind failed: %", pipeline_result));
    draw_result := gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Signal field draw failed: %", draw_result));

    draw_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
ImGui :: #import "ImGui";

draw_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 250.0}, .FirstUseEver);

    if Begin("Signal Field", *signal_field.ui_open, flags = .NoCollapse) {
        Text("Animated fullscreen fragment shader demo.");
        SliderFloat("Speed", *signal_field.speed, 0.1, 2.5);
        SliderFloat("Band Scale", *signal_field.band_scale, 1.0, 8.0);
        SliderFloat("Warp", *signal_field.warp_strength, 0.0, 1.2);
        SliderFloat("Glow", *signal_field.glow_strength, 0.0, 2.0);
        SliderFloat("Vignette", *signal_field.vignette_strength, 0.0, 1.0);
        SliderFloat("Palette Mix", *signal_field.palette_mix, 0.0, 1.0);
        SliderFloat("Grain", *signal_field.grain_strength, 0.0, 0.12);
    }
    End();
}

SIGNAL_FIELD_GRAPHICS_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Signal_Field_Params {
    float2 resolution;
    float time;
    float speed;
    float band_scale;
    float warp_strength;
    float glow_strength;
    float vignette_strength;
    float palette_mix;
    float grain_strength;
    float _pad0;
    float _pad1;
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
    float2 q = float2(
        dot(p, float2(127.1, 311.7)),
        dot(p, float2(269.5, 183.3))
    );
    return fract(sin(q.x + q.y) * 43758.547);
}

static float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (float2(3.0, 3.0) - f * 2.0);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    float ab = mix(a, b, u.x);
    float cd = mix(c, d, u.x);
    return mix(ab, cd, u.y);
}

static float fbm2(float2 p) {
    float sum = 0.0;
    float amp = 0.55;
    float freq = 1.0;
    for (uint i = 0; i < 4; ++i) {
        sum += noise2(p * freq) * amp;
        freq *= 2.07;
        amp *= 0.52;
    }
    return sum;
}

static float3 palette_a(float t) {
    return float3(
        0.33 + 0.28 * cos(6.28318 * (t + 0.00)),
        0.36 + 0.32 * cos(6.28318 * (t + 0.17)),
        0.42 + 0.34 * cos(6.28318 * (t + 0.31))
    );
}

static float3 palette_b(float t) {
    return float3(
        0.44 + 0.30 * cos(6.28318 * (t + 0.08)),
        0.30 + 0.28 * cos(6.28318 * (t + 0.25)),
        0.27 + 0.36 * cos(6.28318 * (t + 0.53))
    );
}

fragment float4 FragmentMain(Vertex_Out in [[stage_in]], constant Signal_Field_Params *params [[buffer(0)]]) {
    float aspect = params->resolution.x / max(params->resolution.y, 1.0);
    float2 p = float2(
        (in.uv.x * 2.0 - 1.0) * aspect,
        in.uv.y * 2.0 - 1.0
    );

    float t = params->time * params->speed;
    float2 flow_uv = p * 1.9 + float2(t * 0.18, -t * 0.14);

    float warp_x = fbm2(flow_uv + float2(1.7, 4.2));
    float warp_y = fbm2(flow_uv + float2(7.9, 0.6));
    float2 warp = (float2(warp_x, warp_y) - 0.5) * params->warp_strength;

    float2 q = p + warp;
    float radial = length(q);

    float ridge = fbm2(q * 2.6 + float2(0.0, t * 0.22));
    float stream = sin(q.x * 8.0 + ridge * 5.0 - t * 1.4);
    float ring_field = radial * params->band_scale - ridge * 1.7 + stream * 0.18;

    float bands = 0.5 + 0.5 * cos(ring_field * 6.28318);
    bands = pow(clamp(bands, 0.0, 1.0), 2.8);

    float accent = smoothstep(0.70, 0.99, bands);
    float core = smoothstep(0.24, 0.04, abs(fract(ring_field) - 0.5));
    float glow = accent * params->glow_strength + core * 0.7;

    float palette_t = ridge * 0.55 + radial * 0.22 - t * 0.06;
    float3 color_a = palette_a(palette_t);
    float3 color_b = palette_b(palette_t + 0.19);
    float3 band_color = mix(color_a, color_b, clamp(params->palette_mix, 0.0, 1.0));

    float3 bg = float3(0.03, 0.05, 0.08);
    float3 haze = float3(0.08, 0.12, 0.17) * (0.7 - radial * 0.25);
    float3 color = bg + haze + band_color * (bands * 0.72 + glow * 0.65);

    float vignette = pow(clamp(1.0 - radial * 0.78, 0.0, 1.0), 1.0 + params->vignette_strength * 1.8);
    color *= mix(1.0, vignette, clamp(params->vignette_strength, 0.0, 1.0));

    float grain = (hash21(in.uv * params->resolution + float2(t * 13.0, -t * 9.0)) - 0.5) * params->grain_strength;
    color += grain;
    color = clamp(color, 0.0, 1.0);

    return float4(color, 1.0);
}
END
