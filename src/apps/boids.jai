WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: BOIDS_COUNT;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../boids_shader.jai";
#load "framebuffer_tools.jai";

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

boid_state_storage_cpu: *[NUM_INSTANCES * 2 + 1] Boid_State;
boid_state_storage_gpu: Gpu_Ptr;
boid_state_a_cpu: *[NUM_INSTANCES] Boid_State;
boid_state_b_cpu: *[NUM_INSTANCES] Boid_State;
boid_state_a_gpu: Gpu_Ptr;
boid_state_b_gpu: Gpu_Ptr;
boid_tints_cpu: *[NUM_INSTANCES] Vector4;
boid_tints_gpu: Gpu_Ptr;
src_is_a := true;
vertex_params_a_gpu: Gpu_Ptr;
vertex_params_b_gpu: Gpu_Ptr;

boids_test_readback := false;
boids_did_readback := false;
boids_stats_mode := false;
boids_stats_every_frames: s64 = 0;
boids_stats_max_samples: s64 = 0;
boids_stats_samples_done: s64 = 0;
boids_snapshot_mode := false;
boids_snapshot_width: s64 = 96;
boids_snapshot_height: s64 = 96;

app_vec2_length :: (v: Vector2) -> float {
    return sqrt(v.x * v.x + v.y * v.y);
}

app_vec2_normalize_or_zero :: (v: Vector2) -> Vector2 {
    len := app_vec2_length(v);
    if len < 0.000001 return .{0, 0};
    inv := 1.0 / len;
    return .{v.x * inv, v.y * inv};
}

on_dll_init :: () {
    if fb_parse_env_int("PEEL_BOIDS_TEST_READBACK") > 0 boids_test_readback = true;
    boids_stats_every_frames = fb_parse_env_int("PEEL_BOIDS_STATS_EVERY");
    boids_stats_max_samples = fb_parse_env_int("PEEL_BOIDS_STATS_MAX");
    if boids_stats_every_frames > 0 && boids_stats_max_samples > 0 {
        boids_stats_mode = true;
    } else if boids_stats_every_frames > 0 || boids_stats_max_samples > 0 {
        log_error("Boids stats mode requires both PEEL_BOIDS_STATS_EVERY (>0) and PEEL_BOIDS_STATS_MAX (>0).");
    }
    if fb_parse_env_int("PEEL_BOIDS_SNAPSHOT") > 0 boids_snapshot_mode = true;
    boids_snapshot_width = max(1, fb_parse_env_int("PEEL_BOIDS_SNAPSHOT_W", boids_snapshot_width));
    boids_snapshot_height = max(1, fb_parse_env_int("PEEL_BOIDS_SNAPSHOT_H", boids_snapshot_height));

    if boids_test_readback || boids_stats_mode gpu_set_swapchain_framebuffer_only(false);

    graphics_source := cast([]u8) get_transpiled(.METAL, boids_vertex_main, boids_frag_main);
    assert(graphics_source.count > 0);
    compute_source := cast([]u8) get_transpiled(.METAL, boids_step_compute);
    assert(compute_source.count > 0);

    blend_state: Gpu_Blend_Desc;
    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    });
    assert(graphics_pipeline != 0, "Pipeline creation failed.");

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024, label = "boids arena");

    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [3] Vector2);
    vertex_buffer.* = .[
        .{ 0.020,  0.0 },
        .{-0.014,  0.011},
        .{-0.014, -0.011},
    ];

    state_storage, state_storage_gpu := gpu_arena_alloc(*gpu_arena, [NUM_INSTANCES * 2 + 1] Boid_State);
    boid_state_storage_cpu = state_storage;
    boid_state_storage_gpu = state_storage_gpu;
    boid_state_a_cpu = cast(*[NUM_INSTANCES] Boid_State) boid_state_storage_cpu;
    boid_state_b_cpu = cast(*[NUM_INSTANCES] Boid_State) (cast(*Boid_State) boid_state_storage_cpu + NUM_INSTANCES);
    tints, tints_gpu := gpu_arena_alloc(*gpu_arena, [NUM_INSTANCES] Vector4);
    boid_tints_cpu = tints;
    boid_tints_gpu = tints_gpu;

    palette := Vector4.[
        .{0.949, 0.380, 0.384, 1.0}, // coral
        .{0.992, 0.682, 0.353, 1.0}, // apricot
        .{0.996, 0.902, 0.482, 1.0}, // butter
        .{0.490, 0.812, 0.620, 1.0}, // mint
        .{0.373, 0.663, 0.898, 1.0}, // azure
        .{0.576, 0.482, 0.914, 1.0}, // violet
    ];

    for 0..NUM_INSTANCES-1 {
        pos := Vector2.{random_get_within_range(-0.62, 0.62), random_get_within_range(-0.62, 0.62)};
        dir := Vector2.{random_get_within_range(-1.0, 1.0), random_get_within_range(-1.0, 1.0)};
        dir = app_vec2_normalize_or_zero(dir);
        speed := random_get_within_range(BOIDS_MIN_SPEED, BOIDS_MAX_SPEED);
        vel := Vector2.{dir.x * speed, dir.y * speed};
        palette_idx := cast(s64) floor(random_get_within_range(0.0, cast(float) palette.count));
        if palette_idx >= palette.count palette_idx = palette.count - 1;
        boid_state_a_cpu.*[it] = .{pos = pos, vel = vel};
        boid_tints_cpu.*[it] = palette[palette_idx];
    }
    boid_state_b_cpu.* = boid_state_a_cpu.*;
    boid_state_storage_cpu.*[BOIDS_CTRL_INDEX].pos.x = 0.0;
    boid_state_storage_cpu.*[BOIDS_CTRL_INDEX].pos.y = 0.0;
    boid_state_storage_cpu.*[BOIDS_CTRL_INDEX].vel.x = 0.0;
    boid_state_storage_cpu.*[BOIDS_CTRL_INDEX].vel.y = 0.0;

    bytes_per_state := NUM_INSTANCES * size_of(Boid_State);
    boid_state_a_gpu = boid_state_storage_gpu;
    boid_state_b_gpu = boid_state_storage_gpu + bytes_per_state.(Gpu_Ptr);
    src_is_a = true;

    param_block_a, vertex_params_gpu_a := gpu_arena_alloc(*gpu_arena, [3] Gpu_Ptr);
    param_block_a.* = .[vertex_gpu, boid_tints_gpu, boid_state_a_gpu];
    vertex_params_a_gpu = vertex_params_gpu_a;

    param_block_b, vertex_params_gpu_b := gpu_arena_alloc(*gpu_arena, [3] Gpu_Ptr);
    param_block_b.* = .[vertex_gpu, boid_tints_gpu, boid_state_b_gpu];
    vertex_params_b_gpu = vertex_params_gpu_b;

    indices := u32.[0, 2, 1];
    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [3] u32);
    index_buffer.* = indices;

    pixel_data, pixel_gpu := gpu_arena_alloc(*gpu_arena, [3] float);
    pixel_data.* = .[1., 0., 1.];

    draw_data = .{
        vertex_params_gpu = vertex_params_a_gpu,
        pixel_gpu = pixel_gpu,
        index_gpu = index_gpu,
        num_vertices = indices.count,
        num_instances = NUM_INSTANCES,
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

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Boids compute set pipeline failed: %", result));
    gpu_dispatch(cmd_buff, boid_state_storage_gpu, .[(NUM_INSTANCES + 63) / 64, 1, 1]);

    src_is_a = !src_is_a;
    if src_is_a {
        draw_data.vertex_params_gpu = vertex_params_a_gpu;
    } else {
        draw_data.vertex_params_gpu = vertex_params_b_gpu;
    }

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.02, 0.02, 1],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, { depth_test = .ALWAYS, depth_mode = .NONE, });
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    using draw_data;
    gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, num_vertices, num_instances);

    gpu_submit_and_present(cmd_buff);
    gpu_wait_idle();

    if boids_stats_mode && boids_stats_samples_done < boids_stats_max_samples {
        frame_num := cast(s64) frame_count;
        if frame_num > 0 && (frame_num % boids_stats_every_frames) == 0 {
            stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
            if ok {
                log("BOIDS_FRAMEBUFFER_STATS frame=% sample=%/% size=%x% avg_rgb=(%, %, %) avg_luma=% min_luma=% max_luma=% std_luma=%",
                    frame_num,
                    boids_stats_samples_done + 1,
                    boids_stats_max_samples,
                    stats.width,
                    stats.height,
                    stats.avg_r,
                    stats.avg_g,
                    stats.avg_b,
                    stats.avg_luma,
                    stats.min_luma,
                    stats.max_luma,
                    stats.stddev_luma);

                if boids_snapshot_mode {
                    path := tprint("./boids_snapshot_frame_%.ppm", frame_num);
                    dumped := fb_dump_swapchain_thumbnail_ppm(
                        swapchain_image,
                        path,
                        cast(u32) boids_snapshot_width,
                        cast(u32) boids_snapshot_height);
                    if dumped log("BOIDS_FRAMEBUFFER_SNAPSHOT frame=% path=%", frame_num, path);
                }
            }
            boids_stats_samples_done += 1;
            if boids_stats_samples_done >= boids_stats_max_samples {
                log("BOIDS_FRAMEBUFFER_STATS completed % samples; quitting.", boids_stats_max_samples);
                app_quit_requested = true;
            }
        }
    }

    if boids_test_readback && !boids_did_readback && frame_count >= 1 {
        boids_did_readback = true;
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        assert(ok, "Boids readback check failed: framebuffer stats unavailable.");
        log("READBACK_SUMMARY backend=boids_metal avg_luma=% min_luma=% max_luma=% std_luma=%",
            stats.avg_luma,
            stats.min_luma,
            stats.max_luma,
            stats.stddev_luma);
        assert(stats.max_luma > 0.05 && stats.stddev_luma > 0.001,
               "Boids readback check failed: output appears uniform/black.");
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";
