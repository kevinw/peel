Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

spark_state_cpu: *[PARTICLE_COUNT]Particle;
spark_state_gpu: Gpu_Ptr;

surprise_vec2_normalize_or_zero :: (v: Vector2) -> Vector2 {
    len := length(v);
    if len < 0.000001 return .{0, 0};
    inv := 1.0 / len;
    return .{v.x * inv, v.y * inv};
}

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, surprise_vertex_main, surprise_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for surprise graphics shaders.");
    compute_source  := cast([]u8) get_transpiled(.METAL, surprise_step_compute);
    assert(compute_source.count > 0, "Transpilation failed for surprise compute shader.");

    blend_state: Gpu_Blend_Desc = {
        src_color_factor = .SRC_ALPHA,
        dst_color_factor = .ONE,
        src_alpha_factor = .ONE,
        dst_alpha_factor = .ONE,
    };

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    });
    assert(graphics_pipeline != 0, "Pipeline creation failed (surprise graphics).");

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Pipeline creation failed (surprise compute).");

    gpu_arena = gpu_make_arena(1024 * 1024 * 4, label = "surprise arena");

    quad, quad_gpu := gpu_arena_alloc(*gpu_arena, [6] Vector2);
    quad.* = .[
        .{-1.0, -1.0},
        .{+1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, +1.0},
    ];

    sparks, sparks_gpu := gpu_arena_alloc(*gpu_arena, [PARTICLE_COUNT]Particle);
    spark_state_cpu = sparks;
    spark_state_gpu = sparks_gpu;

    for 0..PARTICLE_COUNT-1 {
        angle := random_get_within_range(0.0, 6.2831853);
        radius := random_get_within_range(0.08, 0.45);
        pos := Vector2.{cos(angle) * radius, sin(angle) * radius};
        tangent := surprise_vec2_normalize_or_zero(.{-pos.y, pos.x});
        speed := random_get_within_range(0.0015, 0.007);
        spark_state_cpu.*[it] = .{
            pos = pos,
            vel = tangent * speed,
            hue = random_get_within_range(0.0, 1.0),
            life = random_get_within_range(0.4, 1.0),
        };
    }

    param_block, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [2] Gpu_Ptr);
    param_block.* = .[quad_gpu, spark_state_gpu];

    draw_data = .{
        vertex_params_gpu = vertex_params_gpu,
        pixel_gpu = 0,
        num_vertices = 6,
        num_instances = PARTICLE_COUNT,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);

    result=, compute_cmd := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);
    result = gpu_set_pipeline(compute_cmd, compute_pipeline);
    assert(result == .SUCCESS, tprint("Surprise compute set pipeline failed: %", result));
    gpu_dispatch(compute_cmd, spark_state_gpu, .[(PARTICLE_COUNT + 63) / 64, 1, 1]);
    gpu_submit(compute_cmd);
    gpu_wait_idle();

    result=, render_cmd := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(render_cmd, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.015, 0.012, 0.035, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(render_cmd, { depth_test = .ALWAYS, depth_mode = .NONE, });
    gpu_set_pipeline(render_cmd, graphics_pipeline);

    using draw_data;
    draw_result := gpu_draw_instanced_direct(render_cmd, vertex_params_gpu, num_vertices, num_instances);
    assert(draw_result == .SUCCESS);

    submit_and_present_with_ui(render_cmd);
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/particles_shader.jai";
