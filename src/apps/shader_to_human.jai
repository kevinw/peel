#load "../SGPU_App_Common.jai";
#load "shaders/shader_to_human_shader.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
#import "ImGui";
Env_Vars :: #import "Env_Vars";

shader: Shader(fullscreen_tri_vert, shader_to_human_fragment_main, {
    cull = .NONE,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
});
gpu_arena: Gpu_Arena;
shader_to_human_params: Gpu_Buffer(Shader_To_Human_Params);

ui_open := true;
show_watch := true;
show_text := true;
show_shapes := true;
show_coords := true;
show_projected := true;
font_scale: float = 2.0;
line_width: float = 2.0;
auto_orbit := true;
orbit_speed: float = 0.45;

on_dll_init :: () {
    show_text_env, show_text_env_set := Env_Vars.try_parse_env_int("PEEL_SHADER_TO_HUMAN_TEXT");
    if show_text_env_set show_text = show_text_env != 0;

    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
    };
    SHR.init(*shader);

    gpu_arena = gpu_make_arena(64 * 1024, label = "shader_to_human arena");
    shader_to_human_params = gpu_alloc_buffer(*gpu_arena, Shader_To_Human_Params);
    shader_to_human_params.cpu.* = .{
        resolution = .{1280.0, 720.0},
        mouse_pos = .{0.0, 0.0},
        time = 0.0,
        scale = font_scale,
        line_width = line_width,
        flags = SHOW_WATCH | SHOW_SHAPES | SHOW_COORDS | SHOW_PROJECTED,
        view_proj = Matrix4_Identity,
    };

    gpu_commit_residency();
} @on_dll_init

shader_to_human_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{360.0, 220.0}, .FirstUseEver);
    if Begin("ShaderToHuman", *ui_open, flags = .NoCollapse) {
        Text("Ported shader-side debug drawing/watch overlay.");
        Checkbox("Show Watch", *show_watch);
        Checkbox("Show Text", *show_text);
        Checkbox("Show Shapes", *show_shapes);
        Checkbox("Show Coordinate System", *show_coords);
        Checkbox("Show Projected 3D", *show_projected);
        SliderFloat("Font Scale", *font_scale, 1.0, 4.0);
        SliderFloat("Line Width", *line_width, 1.0, 6.0);
        Checkbox("Auto Orbit", *auto_orbit);
        SliderFloat("Orbit Speed", *orbit_speed, 0.1, 1.6);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled shader_to_human_ui();

    render_w, render_h := app_current_render_dimensions();
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if render_w > 0 && render_h > 0 {
        shader_to_human_params.cpu.resolution = .{cast(float) render_w, cast(float) render_h};
    }
    if mouse_ok && render_h > 0 {
        shader_to_human_params.cpu.mouse_pos = .{cast(float) mx, cast(float) (render_h - my)};
    } else {
        shader_to_human_params.cpu.mouse_pos = .{-1000.0, -1000.0};
    }
    shader_to_human_params.cpu.time = cast(float) time;
    shader_to_human_params.cpu.scale = font_scale;
    shader_to_human_params.cpu.line_width = line_width;
    shader_to_human_params.cpu.flags = 0;
    if show_watch      shader_to_human_params.cpu.flags |= SHOW_WATCH;
    if show_text       shader_to_human_params.cpu.flags |= SHOW_TEXT;
    if show_shapes     shader_to_human_params.cpu.flags |= SHOW_SHAPES;
    if show_coords     shader_to_human_params.cpu.flags |= SHOW_COORDS;
    if show_projected  shader_to_human_params.cpu.flags |= SHOW_PROJECTED;

    orbit_t := ifx auto_orbit then cast(float) time * orbit_speed else 0.0;
    eye := Vector3.{cos(orbit_t) * 3.2, 1.55 + sin(orbit_t * 0.7) * 0.45, sin(orbit_t) * 3.2};
    view := make_look_at_matrix(
        viewpoint = eye,
        look_at = .{0, 0, 0},
        reference_up_vector = .{0, 1, 0},
        x_is_forward = false);
    aspect := ifx render_h > 0 then cast(float) render_w / cast(float) render_h else 1.0;
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
    gpu_set_pipeline(cmd_buff, shader.pipeline);

    gpu_draw_instanced_direct(cmd_buff, shader_to_human_params.gpu, 3, 1);

    submit_and_present_with_ui(cmd_buff);
} @on_tick
