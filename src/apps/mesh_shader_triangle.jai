graphics_pipeline: Gpu_Pipeline;
combined_task_mesh_source: string;

Triangle_Fragment_In :: struct {
    position: Vector4; @SV_Position
    color: Vector3; @TEXCOORD0
}

task_main :: () {
    task_payload_store_u32(task_group_id_x());
    task_set_mesh_groups(1, 1, 1);
} @task_shader

mesh_main :: () {
    group_index := cast(float) mesh_payload_load_u32();
    x_offset := (group_index - 1.0) * 0.6;
    mesh_set_output_counts(3, 1);
    mesh_set_vertex_position(0, .{ x_offset + 0.0, -0.5, 0.0, 1.0 });
    mesh_set_vertex_position(1, .{ x_offset + 0.5,  0.5, 0.0, 1.0 });
    mesh_set_vertex_position(2, .{ x_offset - 0.5,  0.5, 0.0, 1.0 });
    mesh_set_vertex_color(0, .{0.5 + group_index * 0.15, 0.2, 0.2});
    mesh_set_vertex_color(1, .{0.2, 0.6 + group_index * 0.15, 0.2});
    mesh_set_vertex_color(2, .{0.2, 0.4, 0.7 + group_index * 0.1});
    mesh_set_triangle(0, 0, 1, 2);
} @mesh_shader

fragment_main :: (using input: Triangle_Fragment_In) -> Vector4 @SV_Target0 {
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader

on_dll_init :: () {
    shader :: #run get_transpiled_task_mesh_pipeline(.METAL, task_main, mesh_main, fragment_main);
    combined_task_mesh_source = copy_string(tprint("%\n%", shader.task_source, shader.mesh_source));

    blend_state: Gpu_Blend_Desc;
    raster_desc := Gpu_Raster_Desc.{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };

    mesh_desc := Gpu_Mesh_Pipeline_Desc.{
        task_shader = cast([]u8) combined_task_mesh_source,
        mesh_shader = cast([]u8) combined_task_mesh_source,
        pixel_shader = cast([]u8) shader.pixel_source,
        raster_desc = raster_desc,
        task_threads = .[1, 1, 1],
        mesh_threads = .[1, 1, 1],
        // Keep Metal object/mesh payload allocation conservative.
        // The current transpiled payload is a single u32 field, but the stage ABI is struct-based.
        payload_memory_length = 16,
    };
    graphics_pipeline = gpu_create_mesh_pipeline(mesh_desc);
    assert(graphics_pipeline != 0, "Failed creating mesh shader pipeline.");
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.03, 0.05, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .NEVER, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);
    draw_result := gpu_draw_meshlets(cmd_buff, 0, .[3, 1, 1]);
    assert(draw_result == .SUCCESS, "Mesh shader triangle draw failed: %", draw_result);

    if app_ui_enabled {
        using ImGui;
        if Begin("Mesh Shader Triangle") {
            Text("Transpiled task+mesh+fragment path");
            Text("Task stage: enabled");
            Text("Task groups: 3");
            Text("Payload: u32 task_group_id_x -> mesh");
            Text("Mesh threads: 1");
            Text("SPIR-V -> SPIRV-Cross -> Metal");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Basic";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
ImGui :: #import "ImGui";
