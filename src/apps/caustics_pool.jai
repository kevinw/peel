Caustics_Pool_Params :: struct {
    resolution: Vector2;
    current_time: float;
    speed: float;

    scl: float;
    contrast: float;
    shimmer: float;
    tint_mix: float;

    glow: float;
    vignette: float;
    foam: float;
    _pad0: float;
}

Caustics_Pool_App :: struct {
    graphics_pipeline: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;
    params: Gpu_Frame_Param_Allocator(Caustics_Pool_Params);
    using draw: Caustics_Pool_Params;
    ui_open: bool;
}

using app: Caustics_Pool_App = .{
    resolution = .{1280.0, 720.0},
    speed = 0.9,
    scl = 5.5,
    contrast = 1.55,
    shimmer = 0.45,
    tint_mix = 0.62,
    glow = 1.05,
    vignette = 0.28,
    foam = 0.22,
    ui_open = true,
};

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, fullscreen_tri_vert, caustics_pool_fragment_main);
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, fullscreen_tri_vert, caustics_pool_fragment_main);
    gpu_arena = gpu_make_arena(64 * 1024, label = "caustics pool arena");
    params = sgpu_make_frame_param_allocator(*gpu_arena, Caustics_Pool_Params);

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        resolution = .{cast(float) win_w, cast(float) win_h};
    }
    current_time = cast(float) time;

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
    gpu_set_pipeline(cmd_buff, graphics_pipeline);
    gpu_draw_instanced(cmd_buff, 0, sgpu_frame_param_alloc(*params, draw).gpu, 3, 1);

    draw_ui();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

CAUSTICS_HASH_DOT :: Vector2.{41.0, 289.0};
CAUSTICS_HASH_SCALE: float : 45758.547;
CAUSTICS_PI: float : 3.1415927;

hash21 :: (p: Vector2) -> float {
    return fract(sin(dot(p, CAUSTICS_HASH_DOT)) * CAUSTICS_HASH_SCALE);
}

noise2 :: (p: Vector2) -> float {
    i := floor(p);
    f := fract(p);
    u := f * f * (Vector2.{3.0, 3.0} - f * 2.0);

    a := hash21(i + .{0.0, 0.0});
    b := hash21(i + .{1.0, 0.0});
    c := hash21(i + .{0.0, 1.0});
    d := hash21(i + .{1.0, 1.0});

    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

caustics_field :: (p: Vector2, t: float) -> float {
    total := 0.0;
    weight := 0.6;
    q := p;
    for 0..3 {
        n := noise2(q + Vector2.{t * 0.19, -t * 0.14});
        total += abs(sin((q.x + q.y + n * 1.4) * CAUSTICS_PI)) * weight;
        q = Vector2.{
            q.x * 1.73 - q.y * 0.64,
            q.x * 0.64 + q.y * 1.73,
        } + Vector2.{3.1, -1.7};
        weight *= 0.55;
    }
    return total;
}

caustics_pool_fragment_main :: (using in: struct { uv: Vector2; }, using params: Caustics_Pool_Params) -> Vector4 @SV_Target0 {
    denom := resolution.y;
    if denom < 1.0 denom = 1.0;

    aspect := resolution.x / denom;
    p := uv * 2 - 1;
    t := current_time * speed;

    drift := Vector2.{sin(t * 0.7), cos(t * 0.53)} * 0.12;
    ripple_uv := p * scl + drift;
    caustic_a := caustics_field(ripple_uv, t);
    caustic_b := caustics_field(ripple_uv * 1.17 + Vector2.{2.4, -1.3}, t * 1.13);

    pattern := abs(caustic_a - caustic_b);
    pattern = pow(clamp(pattern, 0.0, 1.0), max(0.2, 2.4 - contrast));

    shimmer_term := sin((p.x - p.y) * 14.0 + t * 6.5) * 0.5 + 0.5;
    pattern += shimmer_term * shimmer * 0.18;

    foam_term := smoothstep(0.74 - foam * 0.35, 1.0, pattern);
    glow_term := smoothstep(0.42, 1.0, pattern) * glow;

    deep := Vector3.{0.03, 0.17, 0.24};
    aqua := Vector3.{0.08, 0.48, 0.56};
    sun := Vector3.{0.88, 0.98, 0.85};
    tint := lerp(aqua, Vector3.{0.19, 0.62, 0.68}, tint_mix);

    color := lerp(deep, tint, clamp(pattern * 0.7 + 0.15, 0.0, 1.0));
    color += sun * (glow_term * 0.45 + foam_term * 0.35);

    vignette_term := pow(clamp(1.0 - dot(p, p) * 0.22, 0.0, 1.0), 1.0 + vignette * 2.2);
    color *= lerp(1.0, vignette_term, vignette);
    color = clamp(color, 0.0, 1.0);

    return vec4(color, 1);
} @fragment_shader

#scope_file
#load "../SGPU_App_Common.jai";
ImGui :: #import "ImGui";
#import "Math";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
SHR :: #import,file "../shader_hot_reload.jai";

draw_ui :: () {
    if !app_ui_enabled return;

    using ImGui;
    SetNextWindowPos(.{28.0, 28.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 260.0}, .FirstUseEver);

    using app;
    if Begin("Caustics Pool", *ui_open, flags = .NoCollapse) {
        Text("Procedural water-light caustics study.");
        SliderFloat("Speed", *speed, 0.1, 2.0);
        SliderFloat("Scale", *scl, 1.5, 9.0);
        SliderFloat("Contrast", *contrast, 0.4, 2.5);
        SliderFloat("Shimmer", *shimmer, 0.0, 1.0);
        SliderFloat("Tint Mix", *tint_mix, 0.0, 1.0);
        SliderFloat("Glow", *glow, 0.0, 2.0);
        SliderFloat("Vignette", *vignette, 0.0, 1.0);
        SliderFloat("Foam", *foam, 0.0, 0.7);
    }
    End();
}
