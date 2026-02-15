WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../reaction_diffusion_shader.jai";
#load "rd_readback_tools.jai";

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
compute_pipeline_ab: Gpu_Pipeline;
compute_pipeline_ba: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;
test_readback := false;
did_readback := false;
stats_mode := false;
stats_every_frames: s64 = 0;
stats_max_samples: s64 = 0;
stats_samples_done: s64 = 0;
stats_prev_valid := false;
stats_prev_avg_luma: float = 0.0;
snapshot_mode := false;
snapshot_width: s64 = 96;
snapshot_height: s64 = 96;
window_snapshot_mode := false;

state_storage_gpu: Gpu_Ptr;
state_storage_cpu: *[RD_CELL_COUNT * 2] Vector2;
state_a_gpu: Gpu_Ptr;
state_b_gpu: Gpu_Ptr;
state_a_cpu: *[RD_CELL_COUNT] Vector2;
state_b_cpu: *[RD_CELL_COUNT] Vector2;
src_is_a := true;

rd_init_state :: (state: *[RD_CELL_COUNT] Vector2) {
    center_x := cast(s64) RD_WIDTH / 2;
    center_y := cast(s64) RD_HEIGHT / 2;
    seed_half_w := cast(s64) RD_WIDTH / 9;
    seed_half_h := cast(s64) RD_HEIGHT / 9;

    for y: 0..RD_HEIGHT-1 {
        for x: 0..RD_WIDTH-1 {
            idx := cast(s64) y * cast(s64) RD_WIDTH + cast(s64) x;
            dx := cast(s64) x - center_x;
            dy := cast(s64) y - center_y;
            inside_center := rd_abs(cast(float) dx) <= cast(float) seed_half_w &&
                             rd_abs(cast(float) dy) <= cast(float) seed_half_h;
            noise_code := (x * 131 + y * 197 + x * y * 17) % 1024;
            noise := cast(float) noise_code / 1024.0;
            a: float = 1.0;
            b: float = noise * 0.02;
            if inside_center {
                a = 0.0;
                b = 1.0;
            } else if noise > 0.992 {
                a = 0.1;
                b = 0.85;
            }
            state.*[idx] = .{a, b};
        }
    }
}

rd_inject_perturbation :: (state: *[RD_CELL_COUNT] Vector2, frame: s64) {
    if frame <= 0 return;
    if (frame % 24) != 0 return;

    inject_radius: s64 = 2;
    inject_r2 := inject_radius * inject_radius;
    seed := cast(u32) frame * 1664525 + 1013904223;
    for 0..0 {
        seed = seed * 1664525 + 1013904223;
        cx := cast(s64) (seed % RD_WIDTH);
        seed = seed * 1664525 + 1013904223;
        cy := cast(s64) (seed % RD_HEIGHT);
        for oy: -inject_radius..inject_radius {
            for ox: -inject_radius..inject_radius {
                if ox * ox + oy * oy > inject_r2 continue;
                x := cx + ox;
                y := cy + oy;
                if x < 0 x += RD_WIDTH;
                if x >= RD_WIDTH x -= RD_WIDTH;
                if y < 0 y += RD_HEIGHT;
                if y >= RD_HEIGHT y -= RD_HEIGHT;
                idx := cast(s64) y * cast(s64) RD_WIDTH + cast(s64) x;
                v := state.*[idx];
                v.x = min(v.x, 0.20);
                v.y = max(v.y, 0.80);
                state.*[idx] = v;
            }
        }
    }
}

on_dll_init :: () {
    cmdline_args := get_command_line_arguments();
    defer array_free(cmdline_args);
    for cmdline_args {
        if it == "-test_readback" || it == "--test_readback" || it == "--test-readback" {
            test_readback = true;
            break;
        }
    }
    if rd_parse_env_int("PEEL_RD_TEST_READBACK") > 0 test_readback = true;
    stats_every_frames = rd_parse_env_int("PEEL_RD_STATS_EVERY");
    stats_max_samples = rd_parse_env_int("PEEL_RD_STATS_MAX");
    if stats_every_frames > 0 && stats_max_samples > 0 {
        stats_mode = true;
    } else if stats_every_frames > 0 || stats_max_samples > 0 {
        log_error("RD stats mode requires both PEEL_RD_STATS_EVERY (>0) and PEEL_RD_STATS_MAX (>0).");
    }
    if rd_parse_env_int("PEEL_RD_SNAPSHOT") > 0 snapshot_mode = true;
    if rd_parse_env_int("PEEL_RD_WINDOW_SNAPSHOT") > 0 window_snapshot_mode = true;
    snapshot_width = max(1, rd_parse_env_int("PEEL_RD_SNAPSHOT_W", snapshot_width));
    snapshot_height = max(1, rd_parse_env_int("PEEL_RD_SNAPSHOT_H", snapshot_height));

    if test_readback || stats_mode gpu_set_swapchain_framebuffer_only(false);

    compute_source_ab := cast([]u8) get_transpiled(.METAL, rd_step_compute_ab);
    compute_source_ba := cast([]u8) get_transpiled(.METAL, rd_step_compute_ba);
    assert(compute_source_ab.count > 0, "Compute transpilation failed (rd_step_compute_ab).");
    assert(compute_source_ba.count > 0, "Compute transpilation failed (rd_step_compute_ba).");
    graphics_source := cast([]u8) get_transpiled(.METAL, rd_vertex_main, rd_fragment_main);
    compute_pipeline_ab = gpu_create_compute_pipeline(compute_source_ab);
    compute_pipeline_ba = gpu_create_compute_pipeline(compute_source_ba);
    assert(compute_pipeline_ab != 0, "Compute pipeline creation failed (ab).");
    assert(compute_pipeline_ba != 0, "Compute pipeline creation failed (ba).");

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });
    assert(graphics_pipeline != 0, "Graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 8, label = "reaction diffusion arena");

    state_storage, state_storage_ptr := gpu_arena_alloc(*gpu_arena, [RD_CELL_COUNT * 2] Vector2);
    state_storage_cpu = state_storage;
    state_storage_gpu = state_storage_ptr;
    state_a_cpu = cast(*[RD_CELL_COUNT] Vector2) state_storage_cpu;
    state_b_cpu = cast(*[RD_CELL_COUNT] Vector2) (cast(*Vector2) state_storage_cpu + RD_CELL_COUNT);
    rd_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;
    bytes_per_state := RD_CELL_COUNT * size_of(Vector2);
    state_a_gpu = state_storage_gpu;
    state_b_gpu = state_storage_gpu + bytes_per_state.(Gpu_Ptr);
    src_is_a = true;

    draw_data = .{
        vertex_params_gpu = state_a_gpu,
        pixel_gpu = 0,
        index_gpu = 0,
        num_vertices = 6,
        num_instances = 1,
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

    src_cpu := state_a_cpu;
    pipeline := compute_pipeline_ab;
    if !src_is_a {
        src_cpu = state_b_cpu;
        pipeline = compute_pipeline_ba;
    }
    rd_inject_perturbation(src_cpu, cast(s64) frame_count);
    result = gpu_set_pipeline(compute_cmd, pipeline);
    assert(result == .SUCCESS, tprint("RD compute set pipeline failed: %", result));
    gpu_dispatch(compute_cmd, state_storage_gpu, .[(RD_CELL_COUNT + 63) / 64, 1, 1]);

    src_is_a = !src_is_a;
    render_state_gpu := state_b_gpu;
    render_state_cpu := state_b_cpu;
    if src_is_a {
        render_state_gpu = state_a_gpu;
        render_state_cpu = state_a_cpu;
    }
    draw_data.vertex_params_gpu = render_state_gpu;

    gpu_submit(compute_cmd);
    gpu_wait_idle();

    result=, render_cmd := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    clear_color: [4]float;
    clear_color = .[0, 0, 0, 1];

    gpu_begin_scoped_render_pass(render_cmd, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = clear_color,
            }
        ]
    });

    gpu_set_depth_stencil_state(render_cmd, { depth_test = .ALWAYS, depth_mode = .NONE, });
    gpu_set_pipeline(render_cmd, graphics_pipeline);

    using draw_data;
    draw_result := gpu_draw_instanced_direct(render_cmd, vertex_params_gpu, num_vertices, num_instances);
    assert(draw_result == .SUCCESS, tprint("RD draw failed: %", draw_result));

    gpu_submit_and_present(render_cmd);
    gpu_wait_idle();

    if stats_mode && stats_samples_done < stats_max_samples {
        frame_num := cast(s64) frame_count;
        if frame_num > 0 && (frame_num % stats_every_frames) == 0 {
            stats, stats_ok := rd_collect_swapchain_framebuffer_stats(swapchain_image);
            if stats_ok {
                sim_min_b: float = 999.0;
                sim_max_b: float = -1.0;
                sim_sum_b: float = 0.0;
                for render_state_cpu.* {
                    b := it.y;
                    sim_min_b = min(sim_min_b, b);
                    sim_max_b = max(sim_max_b, b);
                    sim_sum_b += b;
                }
                sim_avg_b := sim_sum_b / cast(float) RD_CELL_COUNT;
                delta_luma := 0.0;
                if stats_prev_valid delta_luma = stats.avg_luma - stats_prev_avg_luma;
                log("RD_FRAMEBUFFER_STATS frame=% sample=%/% size=%x% avg_rgb=(%, %, %) avg_luma=% min_luma=% max_luma=% std_luma=% delta_avg_luma=% sim_b(avg=% min=% max=%)",
                    frame_num,
                    stats_samples_done + 1,
                    stats_max_samples,
                    stats.width,
                    stats.height,
                    stats.avg_r,
                    stats.avg_g,
                    stats.avg_b,
                    stats.avg_luma,
                    stats.min_luma,
                    stats.max_luma,
                    stats.stddev_luma,
                    delta_luma,
                    sim_avg_b,
                    sim_min_b,
                    sim_max_b);
                stats_prev_avg_luma = stats.avg_luma;
                stats_prev_valid = true;
                if snapshot_mode {
                    snapshot_path := tprint("./rd_snapshot_frame_%.ppm", frame_num);
                    dump_ok := rd_dump_swapchain_thumbnail_ppm(
                        swapchain_image,
                        snapshot_path,
                        cast(u32) snapshot_width,
                        cast(u32) snapshot_height);
                    if dump_ok {
                        log("RD_FRAMEBUFFER_SNAPSHOT frame=% path=% size=%x%", frame_num, snapshot_path, snapshot_width, snapshot_height);
                    } else {
                        log_error("RD_FRAMEBUFFER_SNAPSHOT frame=% failed path=%", frame_num, snapshot_path);
                    }
                }
                if window_snapshot_mode {
                    window_snapshot_path := tprint("./rd_window_frame_%.jpeg", frame_num);
                    gpu_dump_to_bitmap(window_snapshot_path);
                    log("RD_WINDOW_SNAPSHOT frame=% path=%", frame_num, window_snapshot_path);
                }
            } else {
                log_error("RD_FRAMEBUFFER_STATS frame=% sample=%/% failed to collect stats.",
                          frame_num, stats_samples_done + 1, stats_max_samples);
            }
            stats_samples_done += 1;
            if stats_samples_done >= stats_max_samples {
                log("RD_FRAMEBUFFER_STATS completed % samples; quitting.", stats_max_samples);
                app_quit_requested = true;
            }
        }
    }

    if test_readback && !did_readback && frame_count >= 1 {
        did_readback = true;
        log("RD readback check begin");
        assert(rd_validate_swapchain_readback_non_black(swapchain_image),
               "Reaction diffusion readback check failed: rendered output appears black.");
        log("RD readback check done");
    }

} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
