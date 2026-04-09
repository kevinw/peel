Dynamic_Graphics_Test_Params :: struct {
    mode: u32;
    _pad0: u32;
    _pad1: u32;
    _pad2: u32;
}

fixed_shader: Shader(fullscreen_tri_vert, dynamic_graphics_test_fragment_main, .{
    cull = .NONE,
    color_targets = .[
        .{format = .B8G8R8A8_UNORM},
    ],
});

dynamic_shader: Shader(fullscreen_tri_vert, dynamic_graphics_test_fragment_main, .{
    cull = .NONE,
    derive_attachment_formats_from_render_pass = true,
});

dynamic_noparams_shader: Shader(fullscreen_tri_vert, dynamic_graphics_test_noparams_fragment_main, .{
    cull = .NONE,
    derive_attachment_formats_from_render_pass = true,
});

gpu_arena: Gpu_Arena;
params_alloc: Gpu_Frame_Param_Allocator(Dynamic_Graphics_Test_Params);

on_dll_init :: () {
    gpu_arena = gpu_make_arena(64 * 1024, label = "dynamic graphics test arena");
    params_alloc = sgpu_make_frame_param_allocator(*gpu_arena, Dynamic_Graphics_Test_Params, 2);

    assert(SHR.init(*fixed_shader), "Failed to init fixed graphics test shader.");
    assert(SHR.init(*dynamic_shader), "Failed to init dynamic graphics test shader.");
    assert(SHR.init(*dynamic_noparams_shader), "Failed to init dynamic no-params graphics test shader.");
} @on_dll_init

on_unload :: () {
    gpu_free_arena(gpu_arena);
    gpu_delete(*fixed_shader.pipeline);
    gpu_delete(*dynamic_shader.pipeline);
    gpu_delete(*dynamic_noparams_shader.pipeline);
} @on_unload

tick :: () {
    _, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    pass_desc := Gpu_Render_Pass_Desc.{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.03, 0.03, 0.05, 1.0],
            }
        ],
    };

    resolved_raster_desc, resolved_ok := SHR.shader_hot_reload_resolve_dynamic_raster_desc(dynamic_shader.raster_desc, pass_desc);
    assert(resolved_ok, "Failed to resolve dynamic raster desc.");
    assert(resolved_raster_desc.color_targets.count == fixed_shader.raster_desc.color_targets.count, "Resolved target count mismatch.");
    assert(resolved_raster_desc.depth_format == fixed_shader.raster_desc.depth_format, "Resolved depth format mismatch.");
    if resolved_raster_desc.color_targets.count > 0 {
        assert(resolved_raster_desc.color_targets[0].format == fixed_shader.raster_desc.color_targets[0].format,
            "Resolved color format mismatch: dynamic=% fixed=%",
            resolved_raster_desc.color_targets[0].format, fixed_shader.raster_desc.color_targets[0].format);
    }
    SHR.shader_hot_reload_release_dynamic_raster_desc(dynamic_shader.raster_desc, *resolved_raster_desc);

    dynamic_noparams_pipeline := SHR.pipeline(*dynamic_noparams_shader, pass_desc);

    gpu_begin_scoped_render_pass(cmd_buff, pass_desc);
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});

    left := sgpu_frame_param_alloc(*params_alloc, .{mode = 0});
    assert(gpu_set_pipeline(cmd_buff, fixed_shader.pipeline) == .SUCCESS, "fixed gpu_set_pipeline failed");
    assert(gpu_draw_instanced_direct(cmd_buff, left.gpu, 3, 1) == .SUCCESS, "fixed draw failed");

    right := sgpu_frame_param_alloc(*params_alloc, .{mode = 1});
    assert(gpu_set_pipeline(cmd_buff, dynamic_noparams_pipeline) == .SUCCESS, "dynamic gpu_set_pipeline failed");
    assert(gpu_draw_instanced_direct(cmd_buff, right.gpu, 3, 1) == .SUCCESS, "dynamic draw failed");

    if app_ui_enabled {
        using ImGui;
        if Begin("Dynamic Graphics Pipeline Test") {
            Text("Left: fixed Shader");
            Text("Right: dynamic Shader(pass_desc)");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

dynamic_graphics_test_fragment_main :: (using in: struct { uv: Vector2; }, params: *Dynamic_Graphics_Test_Params) -> Vector4 @SV_Target0 {
    if params.mode == 0 {
        if uv.x >= 0.5 discard();
        return .{1.0, 0.0, 0.0, 1.0};
    }

    if uv.x < 0.5 discard();
    return .{0.0, 1.0, 0.0, 1.0};
} @fragment_shader

dynamic_graphics_test_noparams_fragment_main :: (using in: struct { uv: Vector2; }) -> Vector4 @SV_Target0 {
    if uv.x < 0.5 discard();
    return .{0.0, 1.0, 0.0, 1.0};
} @fragment_shader

#scope_file

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
