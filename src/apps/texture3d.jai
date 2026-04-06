#load "../SGPU_App_Common.jai";
#load "../editor_camera.jai";

#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
#import "ImGui";
Input :: #import "Input";

#load "shaders/texture3d_shader.jai";

TEXTURE3D_SIZE :: 128;
TEXTURE3D_VOXEL_COUNT :: TEXTURE3D_SIZE * TEXTURE3D_SIZE * TEXTURE3D_SIZE;

texture_render: Shader(fullscreen_tri_vert, texture3d_fragment_main, {
    cull = .NONE,
    color_targets = .[ { format = .B8G8R8A8_UNORM }],
});

texture_compute: Compute_Shader(texture3d_compute_main);

gpu_arena: Gpu_Arena;

texture3d_params: Gpu_Buffer(Texture3D_Params);
show_texture: bool = true;

volume_texture: Gpu_Texture;
volume_texture_view: Gpu_Texture_View;
volume_sampler: Gpu_Sampler;

volume_needs_init := true;
texture3d_ui_open := true;
texture3d_animate_volume := true;
texture3d_debug_slice := false;
texture3d_orbit_target := Vector3.{0.5, 0.48, 0.5};
texture3d_orbit_drag_active := false;
texture3d_orbit_distance: float = 1.95;
texture3d_orbit_prev_mouse: Vector2;
texture3d_orbit_have_prev_mouse := false;
texture3d_camera: Editor_Camera = .{
    position = .{1.8, 1.08, 1.95},
    yaw = 0.0,
    pitch = -0.18,
    move_speed = 1.45,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0056,
    move_planar = false,
    pitch_min = -1.45,
    pitch_max = 1.45,
};

on_dll_init :: () {
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };

    SHR.init(*texture_render);
    SHR.init(*texture_compute);

    texture_result, volume_texture= := gpu_create_texture(.{
        type = ._3D,
        dimensions = .[TEXTURE3D_SIZE, TEXTURE3D_SIZE, TEXTURE3D_SIZE],
        format = .R32_SFLOAT,
        usage = .SAMPLED | .STORAGE,
    });
    assert(texture_result == .SUCCESS, tprint("texture3d texture creation failed: %", texture_result));
    assert(volume_texture != 0, "texture3d texture creation returned null handle.");
    volume_texture_view = gpu_texture_view(volume_texture);
    assert(volume_texture_view != 0, "texture3d texture view creation failed.");

    volume_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(volume_sampler != 0, "texture3d sampler creation failed.");

    gpu_arena = gpu_make_arena(64 * 1024, label = "texture3d arena");
    texture3d_params = gpu_alloc_buffer(*gpu_arena, Texture3D_Params);
    texture3d_params.cpu.* = .{
        texture_index = gpu_texture_view_index(volume_texture_view),
        sampler_index = cast(u32) volume_sampler - 1,
        volume_size = TEXTURE3D_SIZE,
        flags = 1,
        time = 0.0,
        density_scale = 1.55,
        absorption = 2.2,
        march_steps = 112.0,
        camera_pos = texture3d_camera.position,
        camera_forward = .{0.0, 0.0, -1.0},
        camera_right = .{1.0, 0.0, 0.0},
        camera_up = .{0.0, 1.0, 0.0},
        resolution = .{1280.0, 720.0},
        _pad0 = .{0.0, 0.0},
    };
    editor_camera_set_look_at(*texture3d_camera, texture3d_orbit_target);
    texture3d_camera.position = texture3d_orbit_target - editor_camera_forward(texture3d_camera) * texture3d_orbit_distance;

    gpu_commit_residency();
} @on_dll_init

texture3d_ui :: () {
    using ImGui;
    SetNextWindowPos(.{24.0, 24.0}, .FirstUseEver);
    SetNextWindowSize(.{380.0, 220.0}, .FirstUseEver);
    if Begin("Texture3D", *texture3d_ui_open, flags = .NoCollapse) {
        Text("3D texture fog raymarch (Metal)");
        Checkbox("Show Texture", *show_texture);
        Text("Volume: %^3 R32_SFLOAT", TEXTURE3D_SIZE);
        Text("RMB look, WASDQE fly, Alt+LMB orbit");
        if Button("Rebuild Volume") volume_needs_init = true;
        Checkbox("Animate Volume", *texture3d_animate_volume);
        if Checkbox("Debug Slice", *texture3d_debug_slice) {
            volume_needs_init = true;
        }
        SliderFloat("Density Scale", *texture3d_params.cpu.density_scale, 0.2, 4.0);
        SliderFloat("Absorption", *texture3d_params.cpu.absorption, 0.5, 12.0);
        SliderFloat("March Steps", *texture3d_params.cpu.march_steps, 24.0, 144.0);
    }
    End();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    if app_ui_enabled texture3d_ui();

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    io := ImGui.GetIO();
    left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
    left_pressed := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .START) != 0;
    right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;
    alt_down := (Input.input_button_states[Input.Key_Code.ALT] & .DOWN) != 0;

    if dims_ok && win_w > 0 && win_h > 0 {
        texture3d_params.cpu.resolution = .{cast(float) win_w, cast(float) win_h};
    }

    orbit_start := alt_down && left_pressed && !io.WantCaptureMouse && !right_down && mouse_ok;
    if orbit_start {
        texture3d_orbit_prev_mouse = .{cast(float) mx, cast(float) my};
        texture3d_orbit_have_prev_mouse = true;
        texture3d_orbit_distance = max(distance(texture3d_camera.position, texture3d_orbit_target), 0.75);
        texture3d_orbit_drag_active = true;
    }

    if texture3d_orbit_drag_active {
        if !alt_down || !left_down || io.WantCaptureMouse || !mouse_ok {
            texture3d_orbit_drag_active = false;
            texture3d_orbit_have_prev_mouse = false;
        } else {
            texture3d_orbit_update_camera(.{cast(float) mx, cast(float) my});
        }
    }

    _ = editor_camera_update(*texture3d_camera, cast(float) dt, mx, my, mouse_ok,
        allow_move = !io.WantTextInput && !texture3d_orbit_drag_active,
        allow_look = right_down && !io.WantCaptureMouse && !texture3d_orbit_drag_active,
        allow_zoom = !io.WantCaptureMouse && !texture3d_orbit_drag_active);

    camera_forward, camera_right, camera_up: Vector3;
    editor_camera_basis(texture3d_camera, *camera_forward, *camera_right, *camera_up);
    texture3d_params.cpu.camera_pos = texture3d_camera.position;
    texture3d_params.cpu.camera_forward = camera_forward;
    texture3d_params.cpu.camera_right = camera_right;
    texture3d_params.cpu.camera_up = camera_up;

    if texture3d_animate_volume {
        texture3d_params.cpu.time = cast(float) time;
        texture3d_params.cpu.flags = 1;
        volume_needs_init = true;
    } else {
        texture3d_params.cpu.flags = 0;
    }
    if texture3d_debug_slice {
        texture3d_params.cpu.flags |= cast(u32) 2;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if volume_needs_init {
        gpu_set_pipeline(cmd_buff, texture_compute.pipeline);
        groups_x := cast(u32) (TEXTURE3D_VOXEL_COUNT + 63) / 64;
        gpu_dispatch_buffers(cmd_buff, .[texture3d_params.gpu], .[groups_x, 1, 1]);
        gpu_barrier(cmd_buff, .COMPUTE_SHADER, .PIXEL_SHADER);
        volume_needs_init = false;
    }

    if show_texture {
        gpu_begin_scoped_render_pass(cmd_buff, .{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.06, 0.08, 0.12, 1.0],
                }
            ]
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
        gpu_set_pipeline(cmd_buff, texture_render.pipeline);
        gpu_draw_instanced(cmd_buff, 0, texture3d_params.gpu, 3, 1);
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

texture3d_orbit_update_camera :: (mouse_pos: Vector2) {
    if !texture3d_orbit_have_prev_mouse {
        texture3d_orbit_prev_mouse = mouse_pos;
        texture3d_orbit_have_prev_mouse = true;
        return;
    }

    delta := mouse_pos - texture3d_orbit_prev_mouse;
    texture3d_orbit_prev_mouse = mouse_pos;
    if abs(delta.x) < 0.0001 && abs(delta.y) < 0.0001 return;

    texture3d_camera.yaw += delta.x * texture3d_camera.mouse_sensitivity;
    texture3d_camera.pitch += delta.y * texture3d_camera.mouse_sensitivity;
    texture3d_camera.pitch = clamp(texture3d_camera.pitch, texture3d_camera.pitch_min, texture3d_camera.pitch_max);

    cam_forward, cam_right, cam_up: Vector3;
    editor_camera_basis(texture3d_camera, *cam_forward, *cam_right, *cam_up);
    texture3d_camera.position = texture3d_orbit_target - cam_forward * texture3d_orbit_distance;
}
