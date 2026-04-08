
Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

using shaders: struct @init_group {
    graphics: Shader(fluid_vertex_main, fluid_fragment_main, {
        cull = .CW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    });
    compute: Compute_Shader(fluid_step_compute);
};
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

fluid_state_storage: Gpu_View(Vector4);
fluid_state: AB_Buffer([FLUID_CELL_COUNT] Vector4);
fluid_control_ring: Gpu_Frame_Ring(Fluid_Compute_Control);
fluid_last_mouse_uv: Vector2;
fluid_have_last_mouse := false;

fluid_init_state :: (state: *[FLUID_CELL_COUNT] Vector4) {
    cx := cast(float) FLUID_WIDTH * 0.5;
    cy := cast(float) FLUID_HEIGHT * 0.5;
    for y: 0..FLUID_HEIGHT-1 {
        for x: 0..FLUID_WIDTH-1 {
            idx := y * FLUID_WIDTH + x;
            fx := cast(float) x - cx;
            fy := cast(float) y - cy;
            dist2 := fx * fx + fy * fy;
            r := cast(float) FLUID_WIDTH * 0.11;
            v := Vector4.{0.0, 0.0, 0.0, 0.0};
            if dist2 < r * r {
                t := 1.0 - dist2 / (r * r);
                v.z = 0.55 + t * 0.45;
                v.x = -fy * 0.0012;
                v.y = fx * 0.0012;
            }
            state.*[idx] = v;
        }
    }
}

on_dll_init :: () {
    gpu_arena = gpu_make_arena(1024 * 1024 * 12, label = "fluid2d arena");

    fluid_state_storage = gpu_alloc_view(*gpu_arena, Vector4, FLUID_CELL_COUNT * 2);
    state_a_cpu := cast(*[FLUID_CELL_COUNT] Vector4) fluid_state_storage.cpu.data;
    state_b_cpu := cast(*[FLUID_CELL_COUNT] Vector4) (fluid_state_storage.cpu.data + FLUID_CELL_COUNT);
    fluid_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;

    bytes_per_state := FLUID_CELL_COUNT * size_of(Vector4);
    fluid_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = fluid_state_storage.gpu,
        b_gpu = fluid_state_storage.gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    fluid_control_ring = sgpu_make_frame_ring(*gpu_arena, Fluid_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        fluid_control_ring.view.cpu[it] = .{
            cursor_uv = .{-1.0, -1.0},
            cursor_delta_uv = .{0.0, 0.0},
            use_b_as_src = 0,
            cursor_active = 0,
        };
    }

    draw_data = .{
        vertex_params_gpu = fluid_state.a_gpu,
        pixel_gpu = 0,
        index_gpu = 0,
        num_vertices = 6,
        num_instances = 1,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    control := sgpu_frame_ring_slot(*fluid_control_ring);
    control.cpu.use_b_as_src = ifx fluid_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cpu.cursor_uv = .{-1.0, -1.0};
    control.cpu.cursor_delta_uv = .{0.0, 0.0};
    control.cpu.cursor_active = 0;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;

        if fluid_have_last_mouse {
            control.cpu.cursor_delta_uv = .{u - fluid_last_mouse_uv.x, v - fluid_last_mouse_uv.y};
        }
        fluid_last_mouse_uv = .{u, v};
        fluid_have_last_mouse = true;

        control.cpu.cursor_uv = .{u, v};
        control.cpu.cursor_active = 1;
    } else {
        fluid_have_last_mouse = false;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    gpu_set_pipeline(cmd_buff, compute.pipeline);
    gpu_dispatch_buffers(cmd_buff, .[fluid_state_storage.gpu, control.gpu], .[(FLUID_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*fluid_state);
    draw_data.vertex_params_gpu = ab_buffer_src_gpu(*fluid_state);

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.01, 0.01, 0.02, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, graphics.pipeline);

    using draw_data;
    gpu_draw_instanced_direct(cmd_buff, vertex_params_gpu, num_vertices, num_instances);
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#import "Math";
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/fluid2d_shader.jai";
