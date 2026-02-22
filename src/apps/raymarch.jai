WRITE_SHADER_OUTPUT :: true;

#load "../SGPU_App_Common.jai";

#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/raymarch_shader.jai";

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
raymarch_params_cpu: *Raymarch_Params;
raymarch_params_gpu: Gpu_Ptr;
raymarch_shader_reload: SHR.Shader_Hot_Reload;

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, raymarch_vertex_main, raymarch_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for raymarch graphics shaders.");
    raster_desc: Gpu_Raster_Desc = {
        cull = .CW,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    hot_reload_enabled_by_default := true;
    #if RELEASE hot_reload_enabled_by_default = false;
    _ = SHR.shader_hot_reload_init_auto(*raymarch_shader_reload, "src/apps/raymarch.jai", poll_every_frames = 15, log_prefix = "RAYMARCH_SHADER_RELOAD", enabled_by_default = hot_reload_enabled_by_default);
    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*raymarch_shader_reload, *graphics_pipeline, graphics_source, raster_desc, .METAL, raymarch_vertex_main, raymarch_fragment_main);
    assert(graphics_ok, "Raymarch graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "raymarch arena");
    raymarch_params_cpu, raymarch_params_gpu = gpu_arena_alloc(*gpu_arena, Raymarch_Params);
    raymarch_params_cpu.* = .{
        time = 0.0,
        resolution = .{1280.0, 720.0},
        mouse_uv = .{0.5, 0.5},
        _pad = 0.0,
    };

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := gpu_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    if dims_ok && win_w > 0 && win_h > 0 {
        raymarch_params_cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 {
        u := cast(float) mx / cast(float) win_w;
        v := cast(float) my / cast(float) win_h;
        if u < 0.0 u = 0.0;
        if u > 1.0 u = 1.0;
        if v < 0.0 v = 0.0;
        if v > 1.0 v = 1.0;
        raymarch_params_cpu.mouse_uv = .{u, v};
    }
    raymarch_params_cpu.time = cast(float) frame_count * (1.0 / 60.0);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, {
        color_targets = .[
            {
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.02, 0.03, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced(cmd_buff, 0, raymarch_params_gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Raymarch draw failed: %", draw_result));

    gpu_submit_and_present(cmd_buff);

    frame_num := cast(s64) frame_count;
    did_rebuild, swapped_all, rebuild_ok := SHR.shader_hot_reload_tick(*raymarch_shader_reload, frame_num);
    sgpu_set_debug_status(SHR.shader_hot_reload_status_line(*raymarch_shader_reload));
    if did_rebuild && !rebuild_ok {
        log_error("RAYMARCH_SHADER_RELOAD build failed; keeping current runtime shaders.");
    } else if did_rebuild && !swapped_all {
        log_error("RAYMARCH_SHADER_RELOAD build succeeded but pipeline swap was partial; keeping remaining old pipelines.");
    }
} @on_tick

#scope_file
#import "Window_Creation";
#import "Math";
