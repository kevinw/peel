#load "../linear_present.jai";
#load "shaders/color_space_test_shader.jai";

color_space_test_shader: Shader(fullscreen_tri_vert, color_space_test_fragment_main, .{
});

Color_Space_Test_Params_CPU :: CPU_Struct(Color_Space_Test_Params);

gpu_arena: Gpu_Arena;
scene_present: Linear_Present_State;
params_alloc: Gpu_Frame_Param_Allocator(Color_Space_Test_Params_CPU);

ground_color_srgb: Sampled_Texture;
ground_color_linear: Sampled_Texture;
snow_color_srgb: Sampled_Texture;
snow_color_linear: Sampled_Texture;
ground_roughness: Sampled_Texture;
ground_ao: Sampled_Texture;
ground_displacement: Sampled_Texture;
ground_normal: Sampled_Texture;
scene_sampler: Gpu_Sampler;

ui_exposure: float = 1.0;

on_dll_init :: () {
    gpu_arena = gpu_make_arena(64 * 1024, label = "color space test arena");
    assert(SHR.init(*color_space_test_shader), "Failed to init color_space_test shader.");
    assert(linear_present_init(*scene_present, "color space test present"), "Failed to init linear present state.");
    params_alloc = sgpu_make_frame_param_allocator(*gpu_arena, Color_Space_Test_Params_CPU);

    ground_color_srgb = load_sampled_texture_rgba8_srgb("textures/Ground104_1K-JPG/Ground104_1K-JPG_Color.jpg");
    ground_color_linear = load_sampled_texture_rgba8("textures/Ground104_1K-JPG/Ground104_1K-JPG_Color.jpg");
    snow_color_srgb = load_sampled_texture_rgba8_srgb("textures/Snow/Snow015_2K-JPG_Color.jpg");
    snow_color_linear = load_sampled_texture_rgba8("textures/Snow/Snow015_2K-JPG_Color.jpg");
    ground_roughness = load_sampled_texture_rgba8("textures/Ground104_1K-JPG/Ground104_1K-JPG_Roughness.jpg");
    ground_ao = load_sampled_texture_rgba8("textures/Ground104_1K-JPG/Ground104_1K-JPG_AmbientOcclusion.jpg");
    ground_displacement = load_sampled_texture_rgba8("textures/Ground104_1K-JPG/Ground104_1K-JPG_Displacement.jpg");
    ground_normal = load_sampled_texture_rgba8("textures/Ground104_1K-JPG/Ground104_1K-JPG_NormalGL.jpg");

    scene_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .LINEAR,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });

    gpu_commit_residency();
} @on_dll_init

on_unload :: () {
    gpu_delete(*ground_color_srgb);
    gpu_delete(*ground_color_linear);
    gpu_delete(*snow_color_srgb);
    gpu_delete(*snow_color_linear);
    gpu_delete(*ground_roughness);
    gpu_delete(*ground_ao);
    gpu_delete(*ground_displacement);
    gpu_delete(*ground_normal);
    gpu_delete(*scene_sampler);
    linear_present_deinit(*scene_present);
    gpu_delete(*color_space_test_shader.pipeline);
    gpu_free_arena(gpu_arena);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if result != .SUCCESS || !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;

    width := cast(u32) win_w;
    height := cast(u32) win_h;
    if !linear_present_ensure_color_target(*scene_present, width, height) return;

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    scene_present.exposure = ui_exposure;

    params := sgpu_frame_param_alloc(*params_alloc);
    params.cpu.* = .{
        ground_color_srgb_index = gpu_texture_view_index(ground_color_srgb.view),
        ground_color_linear_index = gpu_texture_view_index(ground_color_linear.view),
        snow_color_srgb_index = gpu_texture_view_index(snow_color_srgb.view),
        snow_color_linear_index = gpu_texture_view_index(snow_color_linear.view),
        ground_roughness_index = gpu_texture_view_index(ground_roughness.view),
        ground_ao_index = gpu_texture_view_index(ground_ao.view),
        ground_displacement_index = gpu_texture_view_index(ground_displacement.view),
        ground_normal_index = gpu_texture_view_index(ground_normal.view),
        sampler_index = cast(u32) scene_sampler - 1,
    };

    scene_pass_desc := Gpu_Render_Pass_Desc.{
        color_targets = .[
            .{
                view = linear_present_current_color_view(*scene_present),
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.02, 0.02, 0.025, 1.0],
            }
        ],
    };

    {
        gpu_begin_scoped_render_pass(cmd_buff, scene_pass_desc, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, SHR.pipeline(*color_space_test_shader, scene_pass_desc));
        gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);
    }

    linear_present_present(cmd_buff, *scene_present, swapchain_image);

    if app_ui_enabled {
        using ImGui;
        if Begin("Color Space Test", flags = .AlwaysAutoResize) {
            Text("Top row:");
            BulletText("Ground color loaded as sRGB");
            BulletText("Ground color loaded as linear (wrong for albedo)");
            BulletText("Snow color loaded as sRGB");
            BulletText("Snow color loaded as linear (wrong for albedo)");
            Text("Bottom row:");
            BulletText("Ground roughness loaded as linear");
            BulletText("Ground ambient occlusion loaded as linear");
            BulletText("Ground displacement loaded as linear");
            BulletText("Ground normal GL loaded as linear and visualized as a decoded normal");
            SliderFloat("Exposure", *ui_exposure, 0.25, 2.5, "%.2f");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
ImGui :: #import "ImGui";
