WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/raytracer_shader.jai";

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
raytracer_params_cpu: *Raytracer_Params;
raytracer_params_gpu: Gpu_Ptr;
raytracer_shader_reload: SHR.Shader_Hot_Reload;
RAYTRACER_ENTRY_ID :: "pair|METAL|raytracer_vertex_main|raytracer_fragment_main";

dump_png_mode := false;
dump_png_done := false;
dump_png_auto_quit := false;
dump_png_after_frame: s64 = 2;
camera_pos := Vector3.{0.0, 0.75, 1.95};
camera_speed: float = 3.0;

on_dll_init :: () {
    hot_reload_enabled_by_default := true;
    #if RELEASE hot_reload_enabled_by_default = false;
    _ = SHR.shader_hot_reload_init_auto(*raytracer_shader_reload, "src/apps/raytracer.jai", poll_every_frames = 15, log_prefix = "RAYTRACER_SHADER_RELOAD", enabled_by_default = hot_reload_enabled_by_default);
    SHR.shader_hot_reload_register_graphics_pipeline(*raytracer_shader_reload, RAYTRACER_ENTRY_ID, *graphics_pipeline, {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });

    graphics_source := cast([]u8) get_transpiled(.METAL, raytracer_vertex_main, raytracer_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for raytracer graphics shaders.");

    graphics_pipeline = gpu_create_graphics_pipeline(graphics_source, .{
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    });
    assert(graphics_pipeline != 0, "Raytracer graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "raytracer arena");
    raytracer_params_cpu, raytracer_params_gpu = gpu_arena_alloc(*gpu_arena, Raytracer_Params);
    raytracer_params_cpu.* = .{
        resolution = .{1280.0, 720.0},
        mouse_uv = .{0.5, 0.5},
        camera_pos = camera_pos,
        time = 0.0,
    };

    dump_png, _ := readback_stats_env_int("PEEL_RT_DUMP_PNG");
    dump_png_mode = dump_png > 0;
    dump_auto_quit, _ := readback_stats_env_int("PEEL_RT_DUMP_PNG_AUTO_QUIT");
    dump_png_auto_quit = dump_auto_quit > 0;
    dump_frame, dump_frame_set := readback_stats_env_int("PEEL_RT_DUMP_PNG_FRAME");
    if dump_frame_set && dump_frame >= 0 dump_png_after_frame = dump_frame;

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        raytracer_params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;
        raytracer_params_cpu.mouse_uv = .{u, v};
    }
    yaw := (raytracer_params_cpu.mouse_uv.x - 0.5) * 0.9;
    move_forward := Vector3.{sin(yaw), 0.0, -cos(yaw)};
    move_right := Vector3.{move_forward.z, 0.0, -move_forward.x};

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

    gpu_submit_and_present(cmd_buff);

    frame_num := cast(s64) frame_count;
    did_rebuild, swapped_all, rebuild_ok := SHR.shader_hot_reload_tick(*raytracer_shader_reload, frame_num);
    sgpu_set_debug_status(SHR.shader_hot_reload_status_line(*raytracer_shader_reload));
    if did_rebuild && !rebuild_ok {
        log_error("RAYTRACER_SHADER_RELOAD build failed; keeping current runtime shaders.");
    } else if did_rebuild && !swapped_all {
        log_error("RAYTRACER_SHADER_RELOAD build succeeded but pipeline swap was partial; keeping remaining old pipelines.");
    }

    if dump_png_mode && !dump_png_done && frame_num >= dump_png_after_frame {
        out_path := tprint("./%_frame_%.png", APP_NAME, frame_num);
        gpu_dump_to_bitmap(out_path);
        log("RAYTRACER_PNG path=%", out_path);
        dump_png_done = true;
        if dump_png_auto_quit app_quit_requested = true;
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
Input :: #import "Input";
