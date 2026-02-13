WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../reaction_diffusion_shader.jai";

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

compute_pipeline: Gpu_Pipeline;
graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

compute_params_cpu: *RD_Compute_Params;
compute_params_gpu: Gpu_Ptr;
vertex_params_cpu: *RD_Vertex_Params;
vertex_params_gpu: Gpu_Ptr;

rd_init_state :: (state: *[RD_CELL_COUNT] Vector2) {
    cx := cast(s64) RD_WIDTH / 2;
    cy := cast(s64) RD_HEIGHT / 2;
    radius_sq := cast(s64) (RD_WIDTH / 10) * cast(s64) (RD_WIDTH / 10);

    for y: 0..RD_HEIGHT-1 {
        for x: 0..RD_WIDTH-1 {
            idx := cast(s64) y * cast(s64) RD_WIDTH + cast(s64) x;
            dx := cast(s64) x - cx;
            dy := cast(s64) y - cy;
            inside := dx * dx + dy * dy <= radius_sq;

            a: float = 1.0;
            b: float = 0.0;
            if inside b = 1.0;
            state.*[idx] = .{a, b};
        }
    }
}

on_dll_init :: () {
    compute_source := cast([]u8) get_transpiled(.METAL, rd_step_compute);
    graphics_source := cast([]u8) get_transpiled(.METAL, rd_vertex_main, rd_fragment_main);

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Compute pipeline creation failed.");

    blend_state: Gpu_Blend_Desc;
    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    });
    assert(graphics_pipeline != 0, "Graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 8, label = "reaction diffusion arena");

    state_a_cpu, state_a_gpu := gpu_arena_alloc(*gpu_arena, [RD_CELL_COUNT] Vector2);
    state_b_cpu, state_b_gpu := gpu_arena_alloc(*gpu_arena, [RD_CELL_COUNT] Vector2);
    rd_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;

    params_cpu, params_gpu := gpu_arena_alloc(*gpu_arena, RD_Compute_Params);
    params_cpu.* = .{
        src = cast(*Vector2) state_a_gpu,
        dst = cast(*Vector2) state_b_gpu,
    };
    compute_params_cpu = params_cpu;
    compute_params_gpu = params_gpu;

    quad_positions_cpu, quad_positions_gpu := gpu_arena_alloc(*gpu_arena, [6] Vector2);
    quad_positions_cpu.* = .[
        .{-1.0, -1.0},
        .{+1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, +1.0},
    ];

    vert_params_cpu, vert_params_gpu := gpu_arena_alloc(*gpu_arena, RD_Vertex_Params);
    vert_params_cpu.* = .{
        positions = cast(*Vector2) quad_positions_gpu,
        state = cast(*Vector2) state_a_gpu,
    };
    vertex_params_cpu = vert_params_cpu;
    vertex_params_gpu = vert_params_gpu;

    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [6] u32);
    index_buffer.* = .[0, 1, 2, 3, 4, 5];

    draw_data = .{
        vertex_params_gpu = vertex_params_gpu,
        pixel_gpu = vertex_params_gpu,
        index_gpu = index_gpu,
        num_vertices = 6,
        num_instances = 1,
    };
} @on_dll_init

tick :: () {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_set_pipeline(cmd_buff, compute_pipeline);
    groups_x := cast(u32) ((RD_CELL_COUNT + 63) / 64);
    gpu_dispatch(cmd_buff, compute_params_gpu, .[groups_x, 1, 1]);
    vertex_params_cpu.state = compute_params_cpu.dst;

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0, 0, 0, 1],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, { depth_test = .ALWAYS, depth_mode = .NONE, });
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    using draw_data;
    gpu_draw_indexed_instanced(cmd_buff, vertex_params_gpu, pixel_gpu, index_gpu, num_vertices, num_instances);

    gpu_submit_and_present(cmd_buff);
    gpu_wait_idle();
    tmp := compute_params_cpu.src;
    compute_params_cpu.src = compute_params_cpu.dst;
    compute_params_cpu.dst = tmp;
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
