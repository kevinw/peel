Boids_Draw_Params_CPU :: CPU_Struct(Boids_Draw_Params);

palette :: Vector4.[
    .{0.949, 0.380, 0.384, 1.0}, // coral
    .{0.992, 0.682, 0.353, 1.0}, // apricot
    .{0.996, 0.902, 0.482, 1.0}, // butter
    .{0.490, 0.812, 0.620, 1.0}, // mint
    .{0.373, 0.663, 0.898, 1.0}, // azure
    .{0.576, 0.482, 0.914, 1.0}, // violet
];

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    num_vertices:      u32;
    num_instances:     u32;
}

using app: struct {
    shader: Shader(boids_vertex_main, boids_frag_main, {
        cull = .NONE,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    compute: Compute_Shader(boids_step_compute);
    gpu_arena: Gpu_Arena;
    draw_data: Draw_Data;

    boid_state_storage: Gpu_View(Boid_State);
    boid_state: AB_Buffer([BOIDS_COUNT] Boid_State);
    boid_tints: Gpu_View(Vector4);
    boids_draw_params: Gpu_Buffer(Boids_Draw_Params_CPU);
    boids_control_ring: Gpu_Frame_Ring(Boids_Control);

    using control: Boids_Control;
};

boids_ui_open: bool = true;
build_ui :: () {
    using,except(Viewport) _ :: #import "ImGui";
    window_flags: WindowFlags = .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing | .NoNav;
    if Begin("Boids", *boids_ui_open, window_flags) {
        using control;
        inspect_flat(*control, .{ flatten_struct = true });
    }
    End();
}

on_dll_init :: () {
    SHR.init(*shader);
    SHR.init(*compute);

    gpu_arena = gpu_make_arena(1024 * 1024, label = "boids arena");

    vertex_buffer := gpu_alloc_view(*gpu_arena, Vector2, 3);
    vertex_buffer.cpu[0] = .{ 0.020,  0.0 };
    vertex_buffer.cpu[1] = .{-0.014,  0.011};
    vertex_buffer.cpu[2] = .{-0.014, -0.011};

    boid_state_storage = gpu_alloc_view(*gpu_arena, Boid_State, BOIDS_COUNT * 2);
    boid_state_a_cpu := cast(*[BOIDS_COUNT] Boid_State) boid_state_storage.cpu.data;
    boid_state_b_cpu := cast(*[BOIDS_COUNT] Boid_State) (boid_state_storage.cpu.data + BOIDS_COUNT);
    boid_tints = gpu_alloc_view(*gpu_arena, Vector4, BOIDS_COUNT);

    for 0..BOIDS_COUNT-1 {
        pos := Vector2.{random_get_within_range(-0.62, 0.62), random_get_within_range(-0.62, 0.62)};
        dir := Vector2.{random_get_within_range(-1.0, 1.0), random_get_within_range(-1.0, 1.0)};
        normalize(*dir);
        speed := random_get_within_range(MIN_SPEED, MAX_SPEED);
        vel := dir * speed;
        palette_idx := cast(s64) floor(random_get_within_range(0.0, cast(float) palette.count));
        if palette_idx >= palette.count palette_idx = palette.count - 1;
        boid_state_a_cpu.*[it] = .{pos = pos, vel = vel};
        boid_tints.cpu[it] = palette[palette_idx];
    }
    boid_state_b_cpu.* = boid_state_a_cpu.*;
    bytes_per_state := BOIDS_COUNT * size_of(Boid_State);
    boid_state = .{
        a_cpu = boid_state_a_cpu,
        b_cpu = boid_state_b_cpu,
        a_gpu = boid_state_storage.gpu,
        b_gpu = boid_state_storage.gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    boids_draw_params = gpu_alloc_buffer(Boids_Draw_Params_CPU);
    boids_draw_params.cpu.* = .{
        positions = vertex_buffer.gpu,
        tints = boid_tints.gpu,
        instances = boid_state.a_gpu,
    };

    boids_control_ring = sgpu_make_frame_ring(*gpu_arena, Boids_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 boids_control_ring.view.cpu[it] = app.control;

    draw_data = .{
        vertex_params_gpu = boids_draw_params.gpu,
        num_vertices = 3,
        num_instances = BOIDS_COUNT,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;
    build_ui();

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    render_w, render_h := app_current_render_dimensions();


    if mouse_ok && render_w > 0 && render_h > 0 {
        nx := cast(float) mx / cast(float) render_w;
        ny := cast(float) my / cast(float) render_h;
        control.cursor = .{ (nx * 2.0 - 1.0), (ny * 2.0 - 1.0) } * control.view_extent;
    } else {
        control.cursor = .{ 9999.0, 9999.0 };
    }

    control.delta_time = dt;

    control_slot := sgpu_frame_ring_slot(*boids_control_ring);
    control_slot.cpu.* = app.control;

    _, cmd_buff := gpu_start_command_recording(gpu_get_queue(.MAIN, 0));
    gpu_set_pipeline(cmd_buff, compute.pipeline);
    control_slot.cpu.use_b_as_src = ifx boid_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    gpu_dispatch_buffers(cmd_buff, .[boid_state_storage.gpu, control_slot.gpu], .[(BOIDS_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*boid_state);
    boids_draw_params.cpu.instances = ifx boid_state.src_is_a then boid_state.a_gpu else boid_state.b_gpu;

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
    gpu_set_pipeline(cmd_buff, shader.pipeline);

    using draw_data;
    gpu_draw_instanced_direct(cmd_buff, vertex_params_gpu, num_vertices, num_instances);
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/boids_shader.jai";
#import "Random";
