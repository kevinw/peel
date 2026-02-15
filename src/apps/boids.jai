WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: BOIDS_COUNT;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../boids_shader.jai";
#load "../readback_stats.jai";

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

boid_state_storage_cpu: *[NUM_INSTANCES * 2] Boid_State;
boid_state_storage_gpu: Gpu_Ptr;
boid_state: AB_Buffer([NUM_INSTANCES] Boid_State);
boid_tints_cpu: *[NUM_INSTANCES] Vector4;
boid_tints_gpu: Gpu_Ptr;
vertex_params_a_gpu: Gpu_Ptr;
vertex_params_b_gpu: Gpu_Ptr;
boids_control_ring_cpu: *[SGPU_FRAMES_IN_FLIGHT] Boids_Control;
boids_control_ring_gpu: Gpu_Ptr;

boids_readback: Readback_Stats;

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
    readback_stats_init(*boids_readback, "BOIDS", snapshot_default_w = 96, snapshot_default_h = 96);
    if readback_stats_needs_swapchain_readback(*boids_readback) gpu_set_swapchain_framebuffer_only(false);

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

    state_storage, state_storage_gpu := gpu_arena_alloc(*gpu_arena, [NUM_INSTANCES * 2] Boid_State);
    boid_state_storage_cpu = state_storage;
    boid_state_storage_gpu = state_storage_gpu;
    boid_state_a_cpu := cast(*[NUM_INSTANCES] Boid_State) boid_state_storage_cpu;
    boid_state_b_cpu := cast(*[NUM_INSTANCES] Boid_State) (cast(*Boid_State) boid_state_storage_cpu + NUM_INSTANCES);
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
    bytes_per_state := NUM_INSTANCES * size_of(Boid_State);
    boid_state = .{
        a_cpu = boid_state_a_cpu,
        b_cpu = boid_state_b_cpu,
        a_gpu = boid_state_storage_gpu,
        b_gpu = boid_state_storage_gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    param_block_a, vertex_params_gpu_a := gpu_arena_alloc(*gpu_arena, [3] Gpu_Ptr);
    param_block_a.* = .[vertex_gpu, boid_tints_gpu, boid_state.a_gpu];
    vertex_params_a_gpu = vertex_params_gpu_a;

    param_block_b, vertex_params_gpu_b := gpu_arena_alloc(*gpu_arena, [3] Gpu_Ptr);
    param_block_b.* = .[vertex_gpu, boid_tints_gpu, boid_state.b_gpu];
    vertex_params_b_gpu = vertex_params_gpu_b;

    boids_control_ring_cpu, boids_control_ring_gpu = sgpu_arena_alloc_frame_ring(*gpu_arena, Boids_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        boids_control_ring_cpu.*[it].cursor = .{9999.0, 9999.0};
        boids_control_ring_cpu.*[it].use_b_as_src = 0;
        boids_control_ring_cpu.*[it]._pad = 0;
    }

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

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    control := sgpu_frame_ring_cpu_slot(boids_control_ring_cpu);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        nx := cast(float) mx / cast(float) win_w;
        ny := cast(float) my / cast(float) win_h;
        control.cursor.x = (nx * 2.0 - 1.0) * BOIDS_VIEW_EXTENT;
        control.cursor.y = (ny * 2.0 - 1.0) * BOIDS_VIEW_EXTENT;
    } else {
        control.cursor.x = 9999.0;
        control.cursor.y = 9999.0;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Boids compute set pipeline failed: %", result));
    control.use_b_as_src = ifx boid_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control_gpu := sgpu_frame_ring_gpu_slot(boids_control_ring_gpu, Boids_Control);
    gpu_dispatch_buffers(cmd_buff, .[boid_state_storage_gpu, control_gpu], .[(NUM_INSTANCES + 63) / 64, 1, 1]);

    ab_buffer_advance(*boid_state);
    draw_data.vertex_params_gpu = ifx boid_state.src_is_a then vertex_params_a_gpu else vertex_params_b_gpu;

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

    frame_num := cast(s64) frame_count;
    if readback_stats_should_sample(*boids_readback, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(*boids_readback, "BOIDS", frame_num, stats);
            readback_stats_maybe_dump_snapshot(*boids_readback, swapchain_image, frame_num, "boids_snapshot", "BOIDS");
        }
        if readback_stats_advance_sample(*boids_readback) {
            log("BOIDS_FRAMEBUFFER_STATS completed % samples; quitting.", boids_readback.stats_max_samples);
            app_quit_requested = true;
        }
    }

    assert(readback_stats_maybe_run_readback_check(*boids_readback, swapchain_image, "boids_metal"),
           "Boids readback check failed: output appears uniform/black.");
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";
