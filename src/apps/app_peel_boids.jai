WRITE_SHADER_OUTPUT :: true;
NUM_INSTANCES :: 200;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
#load "../boids_shader.jai";

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;


on_dll_init :: () {
    native_shader := cast([]u8)get_transpiled(.METAL, boids_vertex_main, boids_frag_main);

    log(cast(string)native_shader);

    //success, native_shader := compile_shader("shaders/boids.slang", entry_points=.["vertexMain", "fragmentMain"], write_output = WRITE_SHADER_OUTPUT); assert(success);
    //defer array_free(native_shader);

    blend_state: Gpu_Blend_Desc;

    graphics_pipeline = gpu_create_graphics_pipeline(native_shader, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    });
    assert(graphics_pipeline != 0, "Pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 5, label = "main arena");
    vertex_buffer, vertex_gpu := gpu_arena_alloc(*gpu_arena, [3] Vector2);
    vertex_buffer.* = .[
        .{ 0.5,   0.5 } * 0.1,
        .{ 0.5,  -0.5 } * 0.1,
        .{ -0.5, -0.5 } * 0.1,
    ];

    vertex_colors, colors_gpu := gpu_arena_alloc(*gpu_arena, [3] Vector4);
    vertex_colors.* = .[
        {1, 0, 0, 1},
        {0, 1, 0, 1},
        {0, 0, 1, 1},
    ];

    instance_data, instance_data_gpu := gpu_arena_alloc(*gpu_arena, [NUM_INSTANCES]Vector2);
    for 0..NUM_INSTANCES-1 {
        instance_data.*[it] = {random_get_within_range(-0.5, 0.5), random_get_within_range(-0.5, 0.5)};
    }

    param_block, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [3] Gpu_Ptr);
    param_block.* = .[vertex_gpu, colors_gpu, instance_data_gpu];

    indices := u32.[ 0, 2, 1 ];
    index_buffer, index_gpu := gpu_arena_alloc(*gpu_arena, [3] u32);
    index_buffer.* = indices;

    pixel_data, pixel_gpu := gpu_arena_alloc(*gpu_arena, [3] float);
    pixel_data.* = .[1., 0., 1.];

    draw_data = {
        vertex_params_gpu = vertex_params_gpu,
        pixel_gpu = pixel_gpu,
        index_gpu = index_gpu,
        num_vertices = indices.count,
        num_instances = NUM_INSTANCES,
    };
} @on_dll_init

tick :: () {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

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

    defer gpu_submit_and_present(cmd_buff);
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
#import "Random";
