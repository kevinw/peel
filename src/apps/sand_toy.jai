WRITE_SHADER_OUTPUT :: true;

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

sand_state_storage_gpu: Gpu_Ptr;
sand_state_storage_cpu: *[SAND_CELL_COUNT * 2] Vector4;
sand_state: AB_Buffer([SAND_CELL_COUNT] Vector4);
sand_control_ring_cpu: *[SGPU_FRAMES_IN_FLIGHT] Sand_Compute_Control;
sand_control_ring_gpu: Gpu_Ptr;

sand_brush_element: u32 = SAND_MAT_SAND;
sand_brush_radius_px: float = 7.0;
sand_prev_left_down := false;
sand_prev_right_down := false;
sand_have_last_stamp_cell := false;
sand_last_stamp_cell_x: s64 = -1;
sand_last_stamp_cell_y: s64 = -1;

sand_set_cell :: (state: *[SAND_CELL_COUNT] Vector4, x: s64, y: s64, mat: u32, temp: float) {
    if x < 0 || y < 0 return;
    if x >= SAND_SIM_WIDTH || y >= SAND_SIM_HEIGHT return;
    idx := y * SAND_SIM_WIDTH + x;
    state.*[idx] = .{cast(float) mat, temp, 0.0, 0.0};
}

sand_init_state :: (state: *[SAND_CELL_COUNT] Vector4) {
    for y: 0..SAND_SIM_HEIGHT-1 {
        for x: 0..SAND_SIM_WIDTH-1 {
            idx := y * SAND_SIM_WIDTH + x;
            state.*[idx] = .{cast(float) SAND_MAT_EMPTY, 0.08, 0.0, 0.0};
        }
    }

    floor_y := cast(s64) (cast(float) SAND_SIM_HEIGHT * 0.86);
    for y: floor_y..SAND_SIM_HEIGHT-1 {
        for x: 0..SAND_SIM_WIDTH-1 {
            sand_set_cell(state, x, y, SAND_MAT_STONE, 0.20);
        }
    }

    // Sand dune on left.
    dune_cx := cast(s64) 82;
    dune_cy := cast(s64) 76;
    dune_r := cast(s64) 52;
    dune_r2 := dune_r * dune_r;
    for y: 18..122 {
        for x: 20..146 {
            dx := x - dune_cx;
            dy := y - dune_cy;
            if dx * dx + dy * dy > dune_r2 continue;
            if ((x + y * 3) & 1) == 0 {
                sand_set_cell(state, x, y, SAND_MAT_SAND, 0.32);
            }
        }
    }

    // Water pool in center.
    pool_cx := cast(s64) 198;
    pool_cy := cast(s64) 82;
    pool_rx := cast(s64) 46;
    pool_ry := cast(s64) 30;
    for y: 30..126 {
        for x: 142..254 {
            nx := cast(float) (x - pool_cx) / cast(float) pool_rx;
            ny := cast(float) (y - pool_cy) / cast(float) pool_ry;
            if nx * nx + ny * ny <= 1.0 {
                sand_set_cell(state, x, y, SAND_MAT_WATER, 0.15);
            }
        }
    }

    // Lava vent on right.
    vent_x0 := cast(s64) 276;
    vent_x1 := cast(s64) 336;
    for y: 40..112 {
        for x: vent_x0..vent_x1 {
            if y > 84 + ((x - vent_x0) / 3) continue;
            sand_set_cell(state, x, y, SAND_MAT_LAVA, 1.0);
        }
    }

    // Initial steam cloud above vent so first frame reads as "active".
    for y: 10..58 {
        for x: 260..344 {
            jitter := ((x * 19 + y * 7) & 15);
            if jitter < 6 {
                sand_set_cell(state, x, y, SAND_MAT_STEAM, 0.82);
            }
        }
    }

    // Glass strip near lava contact.
    for x: 246..290 {
        sand_set_cell(state, x, 118, SAND_MAT_GLASS, 0.56);
    }
}

sand_ui :: () -> bool {
    using,except(Viewport) _ :: #import "ImGui";

    window_flags: WindowFlags = .NoDecoration | .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing | .NoNav;
    open: bool = true;
    if Begin("Sand Toy", *open, window_flags) {
        Text("Left click paints selected element");
        Text("Right click erases");
        Separator();

        if Button("Sand") sand_brush_element = SAND_MAT_SAND;
        SameLine();
        if Button("Water") sand_brush_element = SAND_MAT_WATER;
        SameLine();
        if Button("Lava") sand_brush_element = SAND_MAT_LAVA;

        if Button("Stone") sand_brush_element = SAND_MAT_STONE;
        SameLine();
        if Button("Glass") sand_brush_element = SAND_MAT_GLASS;
        SameLine();
        if Button("Ice") sand_brush_element = SAND_MAT_ICE;
        SameLine();
        if Button("Erase") sand_brush_element = SAND_MAT_EMPTY;

        Separator();
        if RadioButton("Small Brush", sand_brush_radius_px == 5.0) sand_brush_radius_px = 5.0;
        SameLine();
        if RadioButton("Medium Brush", sand_brush_radius_px == 10.0) sand_brush_radius_px = 10.0;
        SameLine();
        if RadioButton("Large Brush", sand_brush_radius_px == 18.0) sand_brush_radius_px = 18.0;
    }
    End();

    io := GetIO();
    return io.WantCaptureMouse;
}

on_dll_init :: () {
    compute_source := cast([]u8) get_transpiled(.METAL, sand_step_compute);
    assert(compute_source.count > 0, "Compute transpilation failed (sand_step_compute).");
    graphics_source := cast([]u8) get_transpiled(.METAL, sand_vertex_main, sand_fragment_main);
    assert(graphics_source.count > 0, "Graphics transpilation failed (sand shaders).");

    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Sand compute pipeline creation failed.");

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, sand_vertex_main, sand_fragment_main);
    assert(graphics_ok, "Sand graphics pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_pipeline, compute_source, .METAL, sand_step_compute);
    assert(compute_ok, "Sand compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 18, label = "sand toy arena");

    state_storage, state_storage_gpu := gpu_arena_alloc(*gpu_arena, [SAND_CELL_COUNT * 2] Vector4);
    sand_state_storage_cpu = state_storage;
    sand_state_storage_gpu = state_storage_gpu;

    state_a_cpu := cast(*[SAND_CELL_COUNT] Vector4) sand_state_storage_cpu;
    state_b_cpu := cast(*[SAND_CELL_COUNT] Vector4) (cast(*Vector4) sand_state_storage_cpu + SAND_CELL_COUNT);
    sand_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;

    bytes_per_state := SAND_CELL_COUNT * size_of(Vector4);
    sand_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = sand_state_storage_gpu,
        b_gpu = sand_state_storage_gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    sand_control_ring_cpu, sand_control_ring_gpu = sgpu_arena_alloc_frame_ring(*gpu_arena, Sand_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        sand_control_ring_cpu.*[it] = .{
            cursor_uv = .{-1.0, -1.0},
            brush_radius_px = sand_brush_radius_px,
            use_b_as_src = 0,
            brush_active = 0,
            brush_element = SAND_MAT_SAND,
            frame_index = 0,
        };
    }

    draw_data = .{
        vertex_params_gpu = sand_state.a_gpu,
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

    imgui_wants_mouse := sand_ui();

    control := sgpu_frame_ring_cpu_slot(sand_control_ring_cpu);
    control.use_b_as_src = ifx sand_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cursor_uv = .{-1.0, -1.0};
    control.brush_radius_px = sand_brush_radius_px;
    control.brush_active = 0;
    control.brush_element = sand_brush_element;
    control.frame_index = cast(u32) frame_count;

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 && !imgui_wants_mouse {
        left_state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN;
        right_state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN;
        left_down := left_state != 0;
        right_down := right_state != 0;
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;
        v = 1.0 - v;

        control.cursor_uv = .{u, v};
        cell_x := cast(s64) floor(u * cast(float) SAND_SIM_WIDTH);
        cell_y := cast(s64) floor(v * cast(float) SAND_SIM_HEIGHT);
        if cell_x < 0 cell_x = 0;
        if cell_y < 0 cell_y = 0;
        if cell_x >= SAND_SIM_WIDTH cell_x = SAND_SIM_WIDTH - 1;
        if cell_y >= SAND_SIM_HEIGHT cell_y = SAND_SIM_HEIGHT - 1;

        control.brush_active = 0;
        control.brush_element = SAND_MAT_EMPTY;
        if left_down || right_down {
            cell_changed := !sand_have_last_stamp_cell || cell_x != sand_last_stamp_cell_x || cell_y != sand_last_stamp_cell_y;
            left_pressed := left_down && !sand_prev_left_down;
            right_pressed := right_down && !sand_prev_right_down;
            if cell_changed || left_pressed || right_pressed {
                if left_down {
                    control.brush_active = 1;
                    control.brush_element = sand_brush_element;
                }
                sand_have_last_stamp_cell = true;
                sand_last_stamp_cell_x = cell_x;
                sand_last_stamp_cell_y = cell_y;
            }
        } else {
            sand_have_last_stamp_cell = false;
        }

        sand_prev_left_down = left_down;
        sand_prev_right_down = right_down;
    } else {
        sand_prev_left_down = false;
        sand_prev_right_down = false;
        sand_have_last_stamp_cell = false;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Sand compute set pipeline failed: %", result));
    control_gpu := sgpu_frame_ring_gpu_slot(sand_control_ring_gpu, Sand_Compute_Control);
    gpu_dispatch_buffers(cmd_buff, .[sand_state_storage_gpu, control_gpu], .[(SAND_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*sand_state);
    draw_data.vertex_params_gpu = ab_buffer_src_gpu(*sand_state);

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.01, 0.01, 0.015, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    using draw_data;
    draw_result := gpu_draw_instanced_direct(cmd_buff, vertex_params_gpu, num_vertices, num_instances);
    assert(draw_result == .SUCCESS, tprint("Sand draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/sand_toy_shader.jai";
#import "Window_Creation";
Input :: #import "Input";
