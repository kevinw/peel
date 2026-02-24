WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/ripple_heightfield_shader.jai";

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

ripple_state_storage_gpu: Gpu_Ptr;
ripple_state_storage_cpu: *[RIPPLE_CELL_COUNT * 2] Vector2;
ripple_state: AB_Buffer([RIPPLE_CELL_COUNT] Vector2);
ripple_control_ring_cpu: *[SGPU_FRAMES_IN_FLIGHT] Ripple_Compute_Control;
ripple_control_ring_gpu: Gpu_Ptr;

on_dll_init :: () {
    compute_source := cast([]u8) get_transpiled(.METAL, ripple_step_compute);
    assert(compute_source.count > 0, "Compute transpilation failed (ripple_step_compute).");
    graphics_source := cast([]u8) get_transpiled(.METAL, ripple_vertex_main, ripple_fragment_main);
    assert(graphics_source.count > 0, "Graphics transpilation failed (ripple shaders).");
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Ripple compute pipeline creation failed.");

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, ripple_vertex_main, ripple_fragment_main);
    assert(graphics_ok, "Ripple graphics pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_pipeline, compute_source, .METAL, ripple_step_compute);
    assert(compute_ok, "Ripple compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 8, label = "ripple arena");

    state_storage, state_storage_gpu := gpu_arena_alloc(*gpu_arena, [RIPPLE_CELL_COUNT * 2] Vector2);
    ripple_state_storage_cpu = state_storage;
    ripple_state_storage_gpu = state_storage_gpu;

    state_a_cpu := cast(*[RIPPLE_CELL_COUNT] Vector2) ripple_state_storage_cpu;
    state_b_cpu := cast(*[RIPPLE_CELL_COUNT] Vector2) (cast(*Vector2) ripple_state_storage_cpu + RIPPLE_CELL_COUNT);
    for 0..RIPPLE_CELL_COUNT-1 {
        state_a_cpu.*[it] = .{0.0, 0.0};
    }
    state_b_cpu.* = state_a_cpu.*;

    bytes_per_state := RIPPLE_CELL_COUNT * size_of(Vector2);
    ripple_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = ripple_state_storage_gpu,
        b_gpu = ripple_state_storage_gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    ripple_control_ring_cpu, ripple_control_ring_gpu = sgpu_arena_alloc_frame_ring(*gpu_arena, Ripple_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        ripple_control_ring_cpu.*[it] = .{
            cursor_uv = .{-1.0, -1.0},
            use_b_as_src = 0,
            cursor_mode = 0,
        };
    }

    draw_data = .{
        vertex_params_gpu = ripple_state.a_gpu,
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

    control := sgpu_frame_ring_cpu_slot(ripple_control_ring_cpu);
    control.use_b_as_src = ifx ripple_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cursor_uv = .{-1.0, -1.0};
    control.cursor_mode = 0;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;

        control.cursor_uv = .{u, v};
        if Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN {
            control.cursor_mode = 1;
        } else if Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN {
            control.cursor_mode = 2;
        }
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Ripple compute set pipeline failed: %", result));
    control_gpu := sgpu_frame_ring_gpu_slot(ripple_control_ring_gpu, Ripple_Compute_Control);
    gpu_dispatch_buffers(cmd_buff, .[ripple_state_storage_gpu, control_gpu], .[(RIPPLE_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*ripple_state);
    draw_data.vertex_params_gpu = ab_buffer_src_gpu(*ripple_state);

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.01, 0.015, 0.025, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    using draw_data;
    draw_result := gpu_draw_instanced_direct(cmd_buff, vertex_params_gpu, num_vertices, num_instances);
    assert(draw_result == .SUCCESS, tprint("Ripple draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
Input :: #import "Input";
