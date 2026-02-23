WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/fluid2d_shader.jai";

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
fluid_shader_reload: SHR.Shader_Hot_Reload;

fluid_state_storage_gpu: Gpu_Ptr;
fluid_state_storage_cpu: *[FLUID_CELL_COUNT * 2] Vector4;
fluid_state: AB_Buffer([FLUID_CELL_COUNT] Vector4);
fluid_control_ring_cpu: *[SGPU_FRAMES_IN_FLIGHT] Fluid_Compute_Control;
fluid_control_ring_gpu: Gpu_Ptr;
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
    compute_source := cast([]u8) get_transpiled(.METAL, fluid_step_compute);
    assert(compute_source.count > 0, "Compute transpilation failed (fluid_step_compute).");
    graphics_source := cast([]u8) get_transpiled(.METAL, fluid_vertex_main, fluid_fragment_main);
    assert(graphics_source.count > 0, "Graphics transpilation failed (fluid shaders).");
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Fluid2D compute pipeline creation failed.");

    hot_reload_enabled_by_default := true;
    #if RELEASE hot_reload_enabled_by_default = false;
    _ = SHR.shader_hot_reload_init_auto(*fluid_shader_reload, "src/apps/fluid2d.jai", poll_every_frames = 15, log_prefix = "FLUID2D_SHADER_RELOAD", enabled_by_default = hot_reload_enabled_by_default);
    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*fluid_shader_reload, *graphics_pipeline, graphics_source, raster_desc, .METAL, fluid_vertex_main, fluid_fragment_main);
    assert(graphics_ok, "Fluid2D graphics pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*fluid_shader_reload, *compute_pipeline, compute_source, .METAL, fluid_step_compute);
    assert(compute_ok, "Fluid2D compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 12, label = "fluid2d arena");

    state_storage, state_storage_gpu := gpu_arena_alloc(*gpu_arena, [FLUID_CELL_COUNT * 2] Vector4);
    fluid_state_storage_cpu = state_storage;
    fluid_state_storage_gpu = state_storage_gpu;

    state_a_cpu := cast(*[FLUID_CELL_COUNT] Vector4) fluid_state_storage_cpu;
    state_b_cpu := cast(*[FLUID_CELL_COUNT] Vector4) (cast(*Vector4) fluid_state_storage_cpu + FLUID_CELL_COUNT);
    fluid_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;

    bytes_per_state := FLUID_CELL_COUNT * size_of(Vector4);
    fluid_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = fluid_state_storage_gpu,
        b_gpu = fluid_state_storage_gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    fluid_control_ring_cpu, fluid_control_ring_gpu = sgpu_arena_alloc_frame_ring(*gpu_arena, Fluid_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        fluid_control_ring_cpu.*[it] = .{
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
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    control := sgpu_frame_ring_cpu_slot(fluid_control_ring_cpu);
    control.use_b_as_src = ifx fluid_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cursor_uv = .{-1.0, -1.0};
    control.cursor_delta_uv = .{0.0, 0.0};
    control.cursor_active = 0;

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
            control.cursor_delta_uv = .{u - fluid_last_mouse_uv.x, v - fluid_last_mouse_uv.y};
        }
        fluid_last_mouse_uv = .{u, v};
        fluid_have_last_mouse = true;

        control.cursor_uv = .{u, v};
        control.cursor_active = 1;
    } else {
        fluid_have_last_mouse = false;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Fluid2D compute set pipeline failed: %", result));
    control_gpu := sgpu_frame_ring_gpu_slot(fluid_control_ring_gpu, Fluid_Compute_Control);
    gpu_dispatch_buffers(cmd_buff, .[fluid_state_storage_gpu, control_gpu], .[(FLUID_CELL_COUNT + 63) / 64, 1, 1]);

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
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    using draw_data;
    draw_result := gpu_draw_instanced_direct(cmd_buff, vertex_params_gpu, num_vertices, num_instances);
    assert(draw_result == .SUCCESS, tprint("Fluid2D draw failed: %", draw_result));

    gpu_submit_and_present(cmd_buff);

    frame_num := cast(s64) frame_count;
    did_rebuild, swapped_all, rebuild_ok := SHR.shader_hot_reload_tick(*fluid_shader_reload, frame_num);
    sgpu_set_debug_status(SHR.shader_hot_reload_status_line(*fluid_shader_reload));
    if did_rebuild && !rebuild_ok {
        log_error("FLUID2D_SHADER_RELOAD build failed; keeping current runtime shaders.");
    } else if did_rebuild && !swapped_all {
        log_error("FLUID2D_SHADER_RELOAD build succeeded but pipeline swap was partial.");
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
