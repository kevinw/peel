
#load "../SGPU_App_Common.jai";

SHR :: #import,file "../shader_hot_reload.jai";
#import "Jai-Shader-Transpiler";
#import "Math";
#import "ImGui";
Env_Vars :: #import "Env_Vars";

#load "shaders/shader_to_human_shader.jai";

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
shader_to_human_params: Gpu_Buffer(Shader_To_Human_Params);

shader_to_human_ui_open := true;
shader_to_human_show_watch := true;
shader_to_human_show_text := true;
shader_to_human_show_shapes := true;
shader_to_human_show_coords := true;
shader_to_human_show_projected := true;
shader_to_human_font_scale: float = 2.0;
shader_to_human_line_width: float = 2.0;
shader_to_human_auto_orbit := true;
shader_to_human_orbit_speed: float = 0.45;

on_dll_init :: () {
    show_text_env, show_text_env_set := Env_Vars.try_parse_env_int("PEEL_SHADER_TO_HUMAN_TEXT");
    if show_text_env_set shader_to_human_show_text = show_text_env != 0;

    graphics_source := cast([]u8) get_transpiled(.METAL, shader_to_human_vertex_main, shader_to_human_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for shader_to_human shaders.");

    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, shader_to_human_vertex_main, shader_to_human_fragment_main);
    assert(graphics_ok, "shader_to_human graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "shader_to_human arena");
    shader_to_human_params = gpu_alloc_buffer(*gpu_arena, Shader_To_Human_Params);
    shader_to_human_params.cpu.* = .{
        resolution = .{1280.0, 720.0},
        mouse_pos = .{0.0, 0.0},
        time = 0.0,
        scale = shader_to_human_font_scale,
        line_width = shader_to_human_line_width,
        flags = SHOW_WATCH | SHOW_SHAPES | SHOW_COORDS | SHOW_PROJECTED,
        view_proj = Matrix4_Identity,
    };

    gpu_commit_residency();
} @on_dll_init

shader_to_human_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 220.0}, .FirstUseEver);
    if Begin("ShaderToHuman", *shader_to_human_ui_open, flags = .NoCollapse) {
        Text("Ported shader-side debug drawing/watch overlay.");
        Checkbox("Show Watch", *shader_to_human_show_watch);
        Checkbox("Show Text", *shader_to_human_show_text);
        Checkbox("Show Shapes", *shader_to_human_show_shapes);
        Checkbox("Show Coordinate System", *shader_to_human_show_coords);
        Checkbox("Show Projected 3D", *shader_to_human_show_projected);
        SliderFloat("Font Scale", *shader_to_human_font_scale, 1.0, 4.0);
        SliderFloat("Line Width", *shader_to_human_line_width, 1.0, 6.0);
        Checkbox("Auto Orbit", *shader_to_human_auto_orbit);
        SliderFloat("Orbit Speed", *shader_to_human_orbit_speed, 0.1, 1.6);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled shader_to_human_ui();

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        shader_to_human_params.cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    if mouse_ok && dims_ok && win_h > 0 {
        shader_to_human_params.cpu.mouse_pos = .{cast(float) mx, cast(float) (win_h - my)};
    } else {
        shader_to_human_params.cpu.mouse_pos = .{-1000.0, -1000.0};
    }
    shader_to_human_params.cpu.time = cast(float) time;
    shader_to_human_params.cpu.scale = shader_to_human_font_scale;
    shader_to_human_params.cpu.line_width = shader_to_human_line_width;
    shader_to_human_params.cpu.flags = 0;
    if shader_to_human_show_watch      shader_to_human_params.cpu.flags |= SHOW_WATCH;
    if shader_to_human_show_text       shader_to_human_params.cpu.flags |= SHOW_TEXT;
    if shader_to_human_show_shapes     shader_to_human_params.cpu.flags |= SHOW_SHAPES;
    if shader_to_human_show_coords     shader_to_human_params.cpu.flags |= SHOW_COORDS;
    if shader_to_human_show_projected  shader_to_human_params.cpu.flags |= SHOW_PROJECTED;

    orbit_t := ifx shader_to_human_auto_orbit then cast(float) time * shader_to_human_orbit_speed else 0.0;
    eye := Vector3.{cos(orbit_t) * 3.2, 1.55 + sin(orbit_t * 0.7) * 0.45, sin(orbit_t) * 3.2};
    view := make_look_at_matrix(
        viewpoint = eye,
        look_at = .{0.0, 0.0, 0.0},
        reference_up_vector = .{0.0, 1.0, 0.0},
        x_is_forward = false);
    aspect := ifx dims_ok && win_h > 0 then cast(float) win_w / cast(float) win_h else 1.0;
    proj := make_projection_matrix(PI / 3.1, aspect, 0.05, 40.0);
    shader_to_human_params.cpu.view_proj = proj * view;

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.03, 0.04, 0.06, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced_direct(cmd_buff, shader_to_human_params.gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("shader_to_human draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick
