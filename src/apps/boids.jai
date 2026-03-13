WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: BOIDS_COUNT;

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu:         Gpu_Ptr;
    index_gpu:         Gpu_Ptr;
    num_vertices:      u32;
    num_instances:     u32;
}

graphics_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

boid_state_storage: Gpu_View(Boid_State);
boid_state: AB_Buffer([NUM_INSTANCES] Boid_State);
boid_tints: Gpu_View(Vector4);
vertex_params_a: Gpu_View(Gpu_Ptr);
vertex_params_b: Gpu_View(Gpu_Ptr);
boids_control_ring: Gpu_Frame_Ring(Boids_Control);

build_ui :: () {
    using,except(Viewport) _ :: #import "ImGui";
    open: bool = true;
    window_flags: WindowFlags = .NoDecoration | .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing | .NoNav;
    if Begin("Boids", *open, window_flags) {
        Text("Boids");
    }
    End();
}

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, boids_vertex_main, boids_frag_main); assert(graphics_source.count > 0);
    compute_source  := cast([]u8) get_transpiled(.METAL, boids_step_compute);                 assert(compute_source.count > 0);

    blend_state: Gpu_Blend_Desc;
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
        blend_state = *blend_state,
    };

    compute_pipeline = gpu_create_compute_pipeline(compute_source);
    SHR.gfx_pipeline    (*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, boids_vertex_main, boids_frag_main);
    SHR.compute_pipeline(*shader_reload_ctx, *compute_pipeline, compute_source, .METAL, boids_step_compute);

    gpu_arena = gpu_make_arena(1024 * 1024, label = "boids arena");

    vertex_buffer := gpu_alloc_view(*gpu_arena, Vector2, 3);
    vertex_buffer.cpu[0] = .{ 0.020,  0.0 };
    vertex_buffer.cpu[1] = .{-0.014,  0.011};
    vertex_buffer.cpu[2] = .{-0.014, -0.011};

    boid_state_storage = gpu_alloc_view(*gpu_arena, Boid_State, NUM_INSTANCES * 2);
    boid_state_a_cpu := cast(*[NUM_INSTANCES] Boid_State) boid_state_storage.cpu.data;
    boid_state_b_cpu := cast(*[NUM_INSTANCES] Boid_State) (boid_state_storage.cpu.data + NUM_INSTANCES);
    boid_tints = gpu_alloc_view(*gpu_arena, Vector4, NUM_INSTANCES);

    palette :: Vector4.[
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
        normalize(*dir);
        speed := random_get_within_range(BOIDS_MIN_SPEED, BOIDS_MAX_SPEED);
        vel := Vector2.{dir.x * speed, dir.y * speed};
        palette_idx := cast(s64) floor(random_get_within_range(0.0, cast(float) palette.count));
        if palette_idx >= palette.count palette_idx = palette.count - 1;
        boid_state_a_cpu.*[it] = .{pos = pos, vel = vel};
        boid_tints.cpu[it] = palette[palette_idx];
    }
    boid_state_b_cpu.* = boid_state_a_cpu.*;
    bytes_per_state := NUM_INSTANCES * size_of(Boid_State);
    boid_state = .{
        a_cpu = boid_state_a_cpu,
        b_cpu = boid_state_b_cpu,
        a_gpu = boid_state_storage.gpu,
        b_gpu = boid_state_storage.gpu + bytes_per_state.(Gpu_Ptr),
        src_is_a = true,
    };

    vertex_params_a = gpu_alloc_view(*gpu_arena, Gpu_Ptr, 3);
    vertex_params_a.cpu[0] = vertex_buffer.gpu;
    vertex_params_a.cpu[1] = boid_tints.gpu;
    vertex_params_a.cpu[2] = boid_state.a_gpu;

    vertex_params_b = gpu_alloc_view(*gpu_arena, Gpu_Ptr, 3);
    vertex_params_b.cpu[0] = vertex_buffer.gpu;
    vertex_params_b.cpu[1] = boid_tints.gpu;
    vertex_params_b.cpu[2] = boid_state.b_gpu;

    boids_control_ring = sgpu_make_frame_ring(*gpu_arena, Boids_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        boids_control_ring.view.cpu[it].cursor = .{9999.0, 9999.0};
        boids_control_ring.view.cpu[it].use_b_as_src = 0;
        boids_control_ring.view.cpu[it]._pad = 0;
    }

    indices := u32.[0, 2, 1];
    index_buffer := gpu_alloc_view(*gpu_arena, u32, 3);
    index_buffer.cpu[0] = indices[0];
    index_buffer.cpu[1] = indices[1];
    index_buffer.cpu[2] = indices[2];

    pixel_data := gpu_alloc_view(*gpu_arena, float, 3);
    pixel_data.cpu[0] = 1.0;
    pixel_data.cpu[1] = 0.0;
    pixel_data.cpu[2] = 1.0;

    draw_data = .{
        vertex_params_gpu = vertex_params_a.gpu,
        pixel_gpu = pixel_data.gpu,
        index_gpu = index_buffer.gpu,
        num_vertices = indices.count,
        num_instances = NUM_INSTANCES,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image {
        return;
    }
    build_ui();

    mx, my, mouse_ok := get_mouse_pointer_position(true);
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    control := sgpu_frame_ring_slot(*boids_control_ring);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        nx := cast(float) mx / cast(float) win_w;
        ny := cast(float) my / cast(float) win_h;
        control.cpu.cursor.x = (nx * 2.0 - 1.0) * BOIDS_VIEW_EXTENT;
        control.cpu.cursor.y = (ny * 2.0 - 1.0) * BOIDS_VIEW_EXTENT;
    } else {
        control.cpu.cursor.x = 9999.0;
        control.cpu.cursor.y = 9999.0;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Boids compute set pipeline failed: %", result));
    control.cpu.use_b_as_src = ifx boid_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    gpu_dispatch_buffers(cmd_buff, .[boid_state_storage.gpu, control.gpu], .[(NUM_INSTANCES + 63) / 64, 1, 1]);

    ab_buffer_advance(*boid_state);
    draw_data.vertex_params_gpu = ifx boid_state.src_is_a then vertex_params_a.gpu else vertex_params_b.gpu;

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
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/boids_shader.jai";
#import "Random";
SHR :: #import,file "../shader_hot_reload.jai";
