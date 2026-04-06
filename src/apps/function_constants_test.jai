Test_Params :: struct {
    viewport_width: float;
    test_color: Vector3;
    time: float;
}

Function_Constants_Test_VS_Out :: struct {
    position: Vector4; @SV_Position
}

Constant_Params :: struct {
    use_alternate_color: bool = false;
    alt_color: enum u8 { BLUE; MAGENTA; WHITE; } = .MAGENTA;
} @function_constants

gpu_arena: Gpu_Arena;

left_constants: Constant_Params;
right_constants: Constant_Params = { use_alternate_color = true };
params_ring: Gpu_Frame_Ring(Test_Params);
color: Vector4 = .{1, 0, 0, 1};

frag :: (using input: struct { position: Vector4; @SV_Position uv: Vector2; }, using params: *Test_Params, using constants: Constant_Params) -> Vector4 @SV_Target {
    split_x := viewport_width * 0.5;

    // make it wavey
    split_x += sin((time * 2.2 + position.y / 40.0)) * 40 * (sin(time * 5 + 4 * position.y * 0.003));

    if use_alternate_color {
        if input.position.x < split_x discard();

        if alt_color == {
        case .MAGENTA; return {1, 0, 1, 1};
        case .WHITE;   return {1, 1, 1, 1};
        case .BLUE;    return {0, 0, 1, 1};
        }

        return .{0.12, 0.82, 0.24, 1.0};
    } else {
        if input.position.x >= split_x discard();
        return .{test_color.x, test_color.y, test_color.z, 1.0};
    }
} @fragment_shader

do_ui :: () {
    using ImGui;
    base_flags: ColorEditFlags = .None;

    defer End();
    if !Begin("Function Constants Test") { return; }

    {
        PushPopFont(fonts.main, 15);
        TextWrapped("A simple fragment shader uses function constants to know which color to draw.");
    }

    Separator();

    Text("Uniform Color: "); SameLine();
    if ColorEdit4("Color##1", xx *color, .NoInputs | .NoLabel | base_flags) {
        // log("Color changed: %", color);
    }

    Text("Function Constant Enum:");
    if inspect("alt color", *right_constants.alt_color) {
        log("alt color changed: %", right_constants.alt_color);
    }
} @on_ui

shader: Shader(fullscreen_tri_vert, frag, {
    cull = .NONE,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
});

on_dll_init :: () {
    gpu_arena = gpu_make_arena(64 * 1024, label = "function constants test arena");
    params_ring = sgpu_make_frame_ring(*gpu_arena, Test_Params);
    SHR.init(*shader, left_constants);
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    _, _, win_w, _, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w == 0 return;

    params := sgpu_frame_ring_slot(*params_ring);
    params.cpu.* = .{
        viewport_width = cast(float) win_w,
        test_color = color.xyz,
        time = cast(float)time,
    };

    if !ImGui.GetIO().WantCaptureMouse && input_pressed(.MOUSE_BUTTON_LEFT) {
        cycle_alt_color();
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.03, 0.03, 0.05, 1.0],
            }
        ],
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});

    gpu_set_pipeline(cmd_buff, SHR.pipeline(*shader));
    gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);

    gpu_set_pipeline(cmd_buff, SHR.pipeline(*shader, right_constants));
    gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
Input :: #import "Input";

cycle_alt_color :: () {
    using right_constants;
    if alt_color == .WHITE {
        alt_color = .BLUE;
    } else {
        alt_color += 1;
    }
}
