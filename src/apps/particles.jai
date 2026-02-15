WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: SURPRISE_PARTICLE_COUNT;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../surprise_shader.jai";
#load "../readback_stats.jai";

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

spark_state_cpu: *[NUM_INSTANCES] Surprise_State;
spark_state_gpu: Gpu_Ptr;

surprise_readback: Readback_Stats;

surprise_vec2_length :: (v: Vector2) -> float {
    return sqrt(v.x * v.x + v.y * v.y);
}

surprise_vec2_normalize_or_zero :: (v: Vector2) -> Vector2 {
    len := surprise_vec2_length(v);
    if len < 0.000001 return .{0, 0};
    inv := 1.0 / len;
    return .{v.x * inv, v.y * inv};
}

on_dll_init :: () {
    readback_stats_init(*surprise_readback, "SURPRISE", snapshot_default_w = 160, snapshot_default_h = 160, enable_export_jpg = true);
    if readback_stats_needs_swapchain_readback(*surprise_readback) {
        gpu_set_swapchain_framebuffer_only(false);
    }

    graphics_source := cast([]u8) get_transpiled(.METAL, surprise_vertex_main, surprise_fragment_main);
    compute_source := cast([]u8) get_transpiled(.METAL, surprise_step_compute);
    assert(graphics_source.count > 0, "Transpilation failed for surprise graphics shaders.");
    assert(compute_source.count > 0, "Transpilation failed for surprise compute shader.");

    blend_state: Gpu_Blend_Desc;
    blend_state.src_color_factor = .SRC_ALPHA;
    blend_state.dst_color_factor = .ONE;
    blend_state.src_alpha_factor = .ONE;
    blend_state.dst_alpha_factor = .ONE;

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

    sparks, sparks_gpu := gpu_arena_alloc(*gpu_arena, [NUM_INSTANCES] Surprise_State);
    spark_state_cpu = sparks;
    spark_state_gpu = sparks_gpu;

    for 0..NUM_INSTANCES-1 {
        angle := random_get_within_range(0.0, 6.2831853);
        radius := random_get_within_range(0.08, 0.45);
        pos := Vector2.{cos(angle) * radius, sin(angle) * radius};
        tangent := surprise_vec2_normalize_or_zero(.{-pos.y, pos.x});
        speed := random_get_within_range(0.0015, 0.007);
        spark_state_cpu.*[it] = .{
            pos = pos,
            vel = .{tangent.x * speed, tangent.y * speed},
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
        num_instances = NUM_INSTANCES,
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
    gpu_dispatch(compute_cmd, spark_state_gpu, .[(NUM_INSTANCES + 63) / 64, 1, 1]);
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
    assert(draw_result == .SUCCESS, tprint("Surprise draw failed: %", draw_result));

    gpu_submit_and_present(render_cmd);
    gpu_wait_idle();

    frame_num := cast(s64) frame_count;
    if readback_stats_should_sample(*surprise_readback, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(*surprise_readback, "SURPRISE", frame_num, stats);
            readback_stats_maybe_dump_snapshot(*surprise_readback, swapchain_image, frame_num, "surprise_thumb", "SURPRISE");
            if readback_stats_should_export_jpg(*surprise_readback, frame_num, 0) {
                readback_stats_mark_jpg_exported(*surprise_readback);
                gpu_dump_to_bitmap("../surprise.jpg");
                log("SURPRISE_JPG_EXPORTED path=../surprise.jpg");
            }
        } else {
            log_error("SURPRISE_FRAMEBUFFER_STATS failed for frame=%", frame_num);
        }

        if readback_stats_advance_sample(*surprise_readback) {
            app_quit_requested = true;
        }
    } else if readback_stats_should_export_jpg(*surprise_readback, frame_num) {
        readback_stats_mark_jpg_exported(*surprise_readback);
        gpu_dump_to_bitmap("../surprise.jpg");
        log("SURPRISE_JPG_EXPORTED path=../surprise.jpg");
        app_quit_requested = true;
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";
