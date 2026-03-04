WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/raytracer_shader.jai";

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
raytracer_params_cpu: *Raytracer_Params;
raytracer_params_gpu: Gpu_Ptr;

camera_pos := Vector3.{0.0, 0.75, 1.95};
camera_speed: float = 5.0;
raytracer_prev_mouse_x: s64 = 0;
raytracer_prev_mouse_y: s64 = 0;
raytracer_have_prev_mouse := false;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, raytracer_vertex_main, raytracer_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for raytracer graphics shaders.");
    raster_desc: Gpu_Raster_Desc = .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, raytracer_vertex_main, raytracer_fragment_main);
    assert(graphics_ok, "Raytracer graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "raytracer arena");
    raytracer_params_cpu, raytracer_params_gpu = gpu_arena_alloc(*gpu_arena, Raytracer_Params);
    raytracer_params_cpu.* = .{
        resolution = .{1280.0, 720.0},
        mouse_uv = .{0.5, 0.5},
        camera_pos = camera_pos,
        time = 0.0,
    };

    gpu_commit_residency();
} @on_dll_init

app_ui_open := true;

app_ui :: () {
    using,except(Viewport) _ :: #import "ImGui";
    Persist :: #import,file "../ui/persist_controls.jai";
    inspect_globals();

    window_flags: WindowFlags = .AlwaysAutoResize | .NoFocusOnAppearing;
    if Begin("Raytracing", *app_ui_open, window_flags) {
        Text("Controls - LMB: mouse look");
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        raytracer_params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    look_down :=
        (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0 ||
        (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0 ||
        (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_MIDDLE] & .DOWN) != 0;
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 && look_down {
        if raytracer_have_prev_mouse {
            dx := mx - raytracer_prev_mouse_x;
            dy := my - raytracer_prev_mouse_y;
            uv := raytracer_params_cpu.mouse_uv;
            mouse_look_speed := 2.0;
            uv.x += cast(float) dx / cast(float) win_w * mouse_look_speed;
            uv.y += cast(float) dy / cast(float) win_h * mouse_look_speed;
            if uv.x < 0.0 uv.x = 0.0;
            if uv.x > 1.0 uv.x = 1.0;
            if uv.y < 0.0 uv.y = 0.0;
            if uv.y > 1.0 uv.y = 1.0;
            raytracer_params_cpu.mouse_uv = uv;
        }
        raytracer_prev_mouse_x = mx;
        raytracer_prev_mouse_y = my;
        raytracer_have_prev_mouse = true;
    } else {
        raytracer_have_prev_mouse = false;
    }

    app_ui();

    yaw := (raytracer_params_cpu.mouse_uv.x - 0.5) * 0.9;
    move_forward := Vector3.{sin(yaw), 0.0, -cos(yaw)};
    move_right := Vector3.{-move_forward.z, 0.0, move_forward.x};

    move := Vector3.{0.0, 0.0, 0.0};
    if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN move += move_forward;
    if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN move -= move_forward;
    if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN move -= move_right;
    if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN move += move_right;

    move_len_sq := dot(move, move);
    if move_len_sq > 0.000001 {
        move /= sqrt(move_len_sq);
        camera_pos += move * (camera_speed * dt);
    }
    raytracer_params_cpu.camera_pos = camera_pos;
    raytracer_params_cpu.time = cast(float) frame_count * (1.0 / 60.0);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.0, 0.0, 0.0, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced(cmd_buff, 0, raytracer_params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Raytracer draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#import "Math";
Input :: #import "Input";
