WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: SURPRISE_PARTICLE_COUNT;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../surprise_shader.jai";
#load "../framebuffer_tools.jai";

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

surprise_stats_mode := false;
surprise_stats_every_frames: s64 = 0;
surprise_stats_max_samples: s64 = 0;
surprise_stats_samples_done: s64 = 0;
surprise_snapshot_mode := false;
surprise_snapshot_width: s64 = 160;
surprise_snapshot_height: s64 = 160;
surprise_export_jpg_mode := false;
surprise_exported_jpg := false;

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
    surprise_stats_every_frames = fb_parse_env_int("PEEL_SURPRISE_STATS_EVERY", 0);
    surprise_stats_max_samples = fb_parse_env_int("PEEL_SURPRISE_STATS_MAX", 0);
    if surprise_stats_every_frames > 0 && surprise_stats_max_samples > 0 {
        surprise_stats_mode = true;
    } else if surprise_stats_every_frames > 0 || surprise_stats_max_samples > 0 {
        log_error("Surprise stats mode requires both PEEL_SURPRISE_STATS_EVERY (>0) and PEEL_SURPRISE_STATS_MAX (>0).");
    }

    if fb_parse_env_int("PEEL_SURPRISE_SNAPSHOT", 0) > 0 surprise_snapshot_mode = true;
    surprise_snapshot_width = max(1, fb_parse_env_int("PEEL_SURPRISE_SNAPSHOT_W", surprise_snapshot_width));
    surprise_snapshot_height = max(1, fb_parse_env_int("PEEL_SURPRISE_SNAPSHOT_H", surprise_snapshot_height));
    if fb_parse_env_int("PEEL_SURPRISE_EXPORT_JPG", 0) > 0 surprise_export_jpg_mode = true;

    if surprise_stats_mode || surprise_snapshot_mode || surprise_export_jpg_mode {
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
    if surprise_stats_mode && surprise_stats_samples_done < surprise_stats_max_samples {
        if frame_num > 0 && (frame_num % surprise_stats_every_frames) == 0 {
            stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
            if ok {
                log("SURPRISE_FRAMEBUFFER_STATS frame=% sample=%/% size=%x% avg_rgb=(%, %, %) avg_luma=% min_luma=% max_luma=% std_luma=%",
                    frame_num,
                    surprise_stats_samples_done + 1,
                    surprise_stats_max_samples,
                    stats.width,
                    stats.height,
                    stats.avg_r,
                    stats.avg_g,
                    stats.avg_b,
                    stats.avg_luma,
                    stats.min_luma,
                    stats.max_luma,
                    stats.stddev_luma);

                if surprise_snapshot_mode {
                    thumb_path := tprint("./surprise_thumb_frame_%.ppm", frame_num);
                    dumped := fb_dump_swapchain_thumbnail_ppm(
                        swapchain_image,
                        thumb_path,
                        cast(u32) surprise_snapshot_width,
                        cast(u32) surprise_snapshot_height);
                    if dumped log("SURPRISE_FRAMEBUFFER_SNAPSHOT frame=% path=%", frame_num, thumb_path);
                }

                if surprise_export_jpg_mode && !surprise_exported_jpg {
                    surprise_exported_jpg = true;
                    gpu_dump_to_bitmap("../surprise.jpg");
                    log("SURPRISE_JPG_EXPORTED path=../surprise.jpg");
                }
            } else {
                log_error("SURPRISE_FRAMEBUFFER_STATS failed for frame=%", frame_num);
            }

            surprise_stats_samples_done += 1;
            if surprise_stats_samples_done >= surprise_stats_max_samples {
                app_quit_requested = true;
            }
        }
    } else if surprise_export_jpg_mode && !surprise_exported_jpg && frame_num >= 2 {
        surprise_exported_jpg = true;
        gpu_dump_to_bitmap("../surprise.jpg");
        log("SURPRISE_JPG_EXPORTED path=../surprise.jpg");
        app_quit_requested = true;
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";
