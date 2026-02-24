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
rd_shader_reload: SHR.Shader_Hot_Reload;

state_storage_gpu: Gpu_Ptr;
state_storage_cpu: *[RD_CELL_COUNT * 2] Vector2;
rd_state: AB_Buffer([RD_CELL_COUNT] Vector2);
rd_control_cpu: *RD_Compute_Control;
rd_control_gpu: Gpu_Ptr;

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
    compute_source := cast([]u8) get_transpiled(.METAL, rd_step_compute);
    assert(compute_source.count > 0, "Compute transpilation failed (rd_step_compute).");
    graphics_source := cast([]u8) get_transpiled(.METAL, rd_vertex_main, rd_fragment_main);
    assert(graphics_source.count > 0, "Graphics transpilation failed (rd shaders).");
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };
    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    assert(compute_pipeline != 0, "Compute pipeline creation failed.");

    hot_reload_enabled_by_default := true;
    #if RELEASE hot_reload_enabled_by_default = false;
    _ = SHR.shader_hot_reload_init_auto(*rd_shader_reload, "src/apps/reaction_diffusion.jai", poll_every_frames = 15, log_prefix = "RD_SHADER_RELOAD", enabled_by_default = hot_reload_enabled_by_default);
    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*rd_shader_reload, *graphics_pipeline, graphics_source, raster_desc, .METAL, rd_vertex_main, rd_fragment_main);
    assert(graphics_ok, "Graphics pipeline creation failed.");
    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*rd_shader_reload, *compute_pipeline, compute_source, .METAL, rd_step_compute);
    assert(compute_ok, "Compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 8, label = "reaction diffusion arena");

    state_storage, state_storage_ptr := gpu_arena_alloc(*gpu_arena, [RD_CELL_COUNT * 2] Vector2);
    state_storage_cpu = state_storage;
    state_storage_gpu = state_storage_ptr;
    state_a_cpu := cast(*[RD_CELL_COUNT] Vector2) state_storage_cpu;
    state_b_cpu := cast(*[RD_CELL_COUNT] Vector2) (cast(*Vector2) state_storage_cpu + RD_CELL_COUNT);
    rd_init_state(state_a_cpu);
    state_b_cpu.* = state_a_cpu.*;
    bytes_per_state := RD_CELL_COUNT * size_of(Vector2);
    rd_state = .{
        a_cpu = state_a_cpu,
        b_cpu = state_b_cpu,
        a_gpu = state_storage_gpu,
        b_gpu = state_storage_gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };
    rd_control_cpu, rd_control_gpu = gpu_arena_alloc(*gpu_arena, RD_Compute_Control);
    rd_control_cpu.* = .{
        cursor_uv = .{-1.0, -1.0},
        use_b_as_src = 0,
        cursor_active = 0,
    };

    draw_data = .{
        vertex_params_gpu = rd_state.a_gpu,
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

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, compute_cmd := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    src_cpu := ab_buffer_src_cpu(*rd_state);
    rd_inject_perturbation(src_cpu, cast(s64) frame_count);
    result = gpu_set_pipeline(compute_cmd, compute_pipeline);
    assert(result == .SUCCESS, tprint("RD compute set pipeline failed: %", result));
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    rd_control_cpu.use_b_as_src = ifx rd_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;
        rd_control_cpu.cursor_uv = .{u, v};
        rd_control_cpu.cursor_active = 1;
    } else {
        rd_control_cpu.cursor_uv = .{-1.0, -1.0};
        rd_control_cpu.cursor_active = 0;
    }
    gpu_dispatch_buffers(compute_cmd, .[state_storage_gpu, rd_control_gpu], .[(RD_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*rd_state);
    render_state_gpu := ab_buffer_src_gpu(*rd_state);
    render_state_cpu := ab_buffer_src_cpu(*rd_state);
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

    frame_num := cast(s64) frame_count;
    did_rebuild, swapped_all, rebuild_ok := SHR.shader_hot_reload_tick(*rd_shader_reload, frame_num);
    sgpu_set_debug_status(SHR.shader_hot_reload_status_line(*rd_shader_reload));
    if did_rebuild && !rebuild_ok {
        log_error("RD_SHADER_RELOAD build failed; keeping current runtime shaders.");
    } else if did_rebuild && !swapped_all {
        log_error("RD_SHADER_RELOAD build succeeded but pipeline swap was partial.");
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "../reaction_diffusion_shader.jai";
