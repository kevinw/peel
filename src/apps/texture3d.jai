TEXTURE3D_SIZE :: 72;
TEXTURE3D_VOXEL_COUNT :: TEXTURE3D_SIZE * TEXTURE3D_SIZE * TEXTURE3D_SIZE;

Texture3D_Params :: struct {
    texture_index: u32;
    sampler_index: u32;
    volume_size: u32;
    flags: u32;

    time: float;
    density_scale: float;
    absorption: float;
    march_steps: float;

    resolution: Vector2;
    _pad0: Vector2;
}

graphics_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;

texture3d_params_cpu: *Texture3D_Params;
texture3d_params_gpu: Gpu_Ptr;

volume_texture: Gpu_Texture;
volume_texture_view: Gpu_Texture_View;
volume_sampler: Gpu_Sampler;

volume_needs_init := true;
texture3d_ui_open := true;
texture3d_animate_volume := true;

on_dll_init :: () {
    compute_pipeline = gpu_create_compute_pipeline(cast([]u8) TEXTURE3D_COMPUTE_SOURCE);
    assert(compute_pipeline != 0, "texture3d compute pipeline creation failed.");

    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };
    graphics_pipeline = gpu_create_graphics_pipeline(cast([]u8) TEXTURE3D_GRAPHICS_SOURCE, raster_desc);
    assert(graphics_pipeline != 0, "texture3d graphics pipeline creation failed.");

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

    texture3d_ui();

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

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.06, 0.08, 0.12, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);
    draw_result := gpu_draw_instanced(cmd_buff, 0, texture3d_params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("texture3d draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
ImGui :: #import "ImGui";
#import "Math";

TEXTURE3D_COMPUTE_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Texture3D_Params {
    uint texture_index;
    uint sampler_index;
    uint volume_size;
    uint flags;
    float time;
    float density_scale;
    float absorption;
    float march_steps;
    float2 resolution;
    float2 _pad0;
};

static float hash31(uint3 p) {
    uint n = p.x * 1597334677u ^ p.y * 3812015801u ^ p.z * 2798796415u;
    n ^= (n >> 16);
    n *= 2246822519u;
    n ^= (n >> 13);
    n *= 3266489917u;
    n ^= (n >> 16);
    return float(n & 0x00ffffffu) * (1.0 / 16777215.0);
}

static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    uint3 i0 = uint3(i);

    float n000 = hash31(i0 + uint3(0,0,0));
    float n100 = hash31(i0 + uint3(1,0,0));
    float n010 = hash31(i0 + uint3(0,1,0));
    float n110 = hash31(i0 + uint3(1,1,0));
    float n001 = hash31(i0 + uint3(0,0,1));
    float n101 = hash31(i0 + uint3(1,0,1));
    float n011 = hash31(i0 + uint3(0,1,1));
    float n111 = hash31(i0 + uint3(1,1,1));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

[[kernel]]
void ComputeMain(constant Texture3D_Params* params [[buffer(0)]],
                 array<texture3d<float, access::write>, 127> rw_textures [[texture(1)]],
                 uint gid [[thread_position_in_grid]]) {
    uint s = max(params->volume_size, 1u);
    uint ss = s * s;
    uint voxel_count = ss * s;
    if (gid >= voxel_count) return;

    uint z = gid / ss;
    uint rem = gid - z * ss;
    uint y = rem / s;
    uint x = rem - y * s;
    uint3 cell = uint3(x, y, z);

    float3 p = (float3(cell) + 0.5) / float(s);
    float t = params->time;

    float f = 2.8;
    float a = 0.6;
    float n = 0.0;
    for (uint octave = 0; octave < 4; octave++) {
        float3 wobble = float3(0.0, t * 0.22, 0.0) + float3(13.0, 29.0, 7.0) * float(octave);
        n += a * noise3(p * f + wobble);
        f *= 2.0;
        a *= 0.5;
    }

    float layers = 0.5 + 0.5 * sin((p.y * 11.0 + p.x * 4.0 + p.z * 3.0) + t * 0.7);
    float band = smoothstep(0.15, 0.8, p.y);
    float density = clamp((n * 0.85 + layers * 0.35) * band - 0.28, 0.0, 1.0);

    uint texture_index = min(params->texture_index, 126u);
    rw_textures[texture_index].write(density, cell);
}
END

TEXTURE3D_GRAPHICS_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Texture3D_Params {
    uint texture_index;
    uint sampler_index;
    uint volume_size;
    uint flags;
    float time;
    float density_scale;
    float absorption;
    float march_steps;
    float2 resolution;
    float2 _pad0;
};

struct VS_Out {
    float4 position [[position]];
    float2 uv;
};

vertex VS_Out VertexMain(uint vertex_id [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VS_Out out;
    out.position = float4(positions[vertex_id], 0.0, 1.0);
    out.uv = positions[vertex_id] * 0.5 + 0.5;
    return out;
}

static bool ray_box(float3 ro, float3 rd, float3 bmin, float3 bmax, thread float &t0, thread float &t1) {
    float3 inv_rd = 1.0 / max(abs(rd), float3(1e-6)) * sign(rd);
    float3 tmin = (bmin - ro) * inv_rd;
    float3 tmax = (bmax - ro) * inv_rd;
    float3 tn = min(tmin, tmax);
    float3 tf = max(tmin, tmax);
    t0 = max(max(tn.x, tn.y), tn.z);
    t1 = min(min(tf.x, tf.y), tf.z);
    return t1 > max(t0, 0.0);
}

fragment float4 FragmentMain(VS_Out in [[stage_in]],
                             constant Texture3D_Params* params [[buffer(0)]],
                             array<texture3d<float>, 127> volume_textures [[texture(1)]],
                             array<sampler, 16> volume_samplers [[sampler(0)]]) {
    float2 res = max(params->resolution, float2(1.0));
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= res.x / res.y;

    float t = params->time;
    float3 target = float3(0.5, 0.52, 0.5);
    float3 ro = target + float3(cos(t * 0.2) * 1.8, 0.45 + sin(t * 0.27) * 0.35, sin(t * 0.2) * 1.8);
    float3 forward = normalize(target - ro);
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), forward));
    float3 up = cross(forward, right);
    float3 rd = normalize(forward + uv.x * right * 0.9 + uv.y * up * 0.9);

    float bg_mix = clamp(in.uv.y * 0.8 + 0.2, 0.0, 1.0);
    float3 sky = mix(float3(0.07, 0.09, 0.12), float3(0.16, 0.2, 0.28), bg_mix);

    float near_t, far_t;
    if (!ray_box(ro, rd, float3(0.0), float3(1.0), near_t, far_t)) {
        return float4(sky, 1.0);
    }

    uint texture_index = min(params->texture_index, 126u);
    uint sampler_index = min(params->sampler_index, 15u);
    texture3d<float> volume_tex = volume_textures[texture_index];
    sampler samp = volume_samplers[sampler_index];

    float t_cursor = max(near_t, 0.0);
    float t_span = max(far_t - t_cursor, 1e-5);
    uint steps = max(uint(params->march_steps), 8u);
    float dt = t_span / float(steps);

    float optical_depth = 0.0;
    for (uint i = 0; i < steps; i++) {
        float3 p = ro + rd * (t_cursor + dt * (float(i) + 0.5));
        float d = volume_tex.sample(samp, p).x * params->density_scale;
        optical_depth += max(d, 0.0) * dt;
    }

    float transmittance = exp(-optical_depth * params->absorption);
    float fog = clamp(1.0 - transmittance, 0.0, 1.0);
    float3 fog_color = mix(float3(0.82, 0.88, 0.95), float3(0.12, 0.18, 0.26), fog);
    float3 out_color = mix(sky, fog_color, fog);
    return float4(out_color, 1.0);
}
END
