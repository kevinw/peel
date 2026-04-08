
FLUX_SHADOW_MAP_SIZE :: 2048;

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

using shaders: struct @init_group {
    shader: Shader(flux_vertex_main, flux_fragment_main, main_raster);
    sky_shader: Shader(flux_sky_vertex_main, flux_sky_fragment_main, main_raster);
    debug_shadow_shader: Shader(flux_debug_shadow_vertex_main, flux_debug_shadow_fragment_main, main_raster);
    shadow_shader: Shader(flux_shadow_vertex_main, flux_shadow_fragment_main, shadow_raster);
    grass_shadow_shader: Shader(flux_grass_shadow_vertex_main, flux_shadow_fragment_main, shadow_raster);
    step_compute: Compute_Shader(flux_step_compute);
    init_compute: Compute_Shader(flux_init_compute);
    grass_spawn_compute: Compute_Shader(flux_grass_spawn_compute);
    grass_shader: Shader(flux_grass_vertex_main, flux_grass_fragment_main, main_raster);
};

gpu_arena: Gpu_Arena;
draw_data: Draw_Data;
FLUX_GRASS_INSTANCE_COUNT :: 130000;

depth_texture: Gpu_Texture;
depth_view: Gpu_Texture_View;
depth_w: u32;
depth_h: u32;

shadow_map_texture: Gpu_Texture;
shadow_map_view: Gpu_Texture_View;
shadow_depth_texture: Gpu_Texture;
shadow_depth_view: Gpu_Texture_View;
shadow_sampler: Gpu_Sampler;

payload: Gpu_Buffer(Flux_Payload);
render_params_ring: Gpu_Frame_Ring(Flux_Render_Params);
state: AB_Buffer([FLUX_CELL_COUNT] Vector4);
state_initialized := false;
control_ring: Gpu_Frame_Ring(Flux_Compute_Control);

last_mouse_uv: Vector2;
have_last_mouse_uv := false;
last_mouse_x: s64;
last_mouse_y: s64;
have_last_mouse_px := false;

brush_mode := Brush_Type.RAISE;
brush_radius_px: float = 82.0;
brush_strength: float = 0.018;
flux_time_scale: float = 0.35;
show_shadow_debug := true;
render_grass := true;
xz_scale: float = 2.6;
fog_density: float = 0.18;
fog_exponent: float = 1.0;
time_of_day: float = 0.61;
grass_spacing: float = 0.6;
grass_blade_scale: float = 0.54; @0.05..3.0
grass_spawn_near: float = 1.8;
grass_spawn_far: float = 2.36;
grass_spawn_near_boost: float = 3.0;
grass_spawn_far_density: float = 1.0;
grass_fade_start: float = 8.46;
grass_fade_end: float = 22.58;
wind: float = 0.07;
grass_wind_macro: float = 0.95;
grass_wind_turbulence: float = 0.62;
grass_wind_turbulence_freq: float = 0.75;

cam_target := Vector3.{0.0, 0.0, 0.0};
cam_yaw: float = 0.78;
cam_pitch: float = 0.58;
cam_radius: float = 2.9;
FLUX_CAMERA_RADIUS_MIN :: 2.4;
FLUX_CAMERA_RADIUS_MAX :: 6.0;

flux_dummy_curve_points: [16] ImGui.ImVec2;
flux_dummy_curve_selection: s32 = -1;
flux_dummy_curve_initialized := false;
dummy_knob_gain: float = 0.35;
dummy_knob_steps: s32 = 7;

flux_safe_normalize3_cpu :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 < 0.000001 return .{0.0, 0.0, 1.0};
    inv := 1.0 / sqrt(len2);
    return v * inv;
}

flux_compute_camera_basis :: (win_w: u32, win_h: u32, cam_pos: *Vector3, cam_right: *Vector3, cam_up: *Vector3, cam_forward: *Vector3, proj_x: *float, proj_y: *float) {
    aspect: float = 1.0;
    if win_h > 0 aspect = cast(float) win_w / cast(float) win_h;

    fov_rad := cast(float) 52.0 * cast(float) (3.1415926535 / 180.0);
    tan_half := tan(fov_rad * 0.5);
    proj_y.* = 1.0 / max(tan_half, 0.0001);
    proj_x.* = proj_y.* / max(aspect, 0.0001);

    // Z-up spherical orbit: yaw spins around world up (Z), pitch tilts up/down.
    cam_dir := Vector3.{
        cos(cam_pitch) * cos(cam_yaw),
        cos(cam_pitch) * sin(cam_yaw),
        sin(cam_pitch),
    };
    cam_pos.* = cam_target + cam_dir * cam_radius;
    cam_forward.* = flux_safe_normalize3_cpu(cam_target - cam_pos.*);

    world_up := Vector3.{0.0, 0.0, 1.0};
    cam_right.* = cross(cam_forward.*, world_up);
    if dot(cam_right.*, cam_right.*) < 0.00001 {
        world_up = .{0.0, 1.0, 0.0};
        cam_right.* = cross(cam_forward.*, world_up);
    }
    cam_right.* = flux_safe_normalize3_cpu(cam_right.*);
    cam_up.* = flux_safe_normalize3_cpu(cross(cam_right.*, cam_forward.*));
}

flux_mouse_ray_to_terrain_uv :: (mouse_x: s64, mouse_y: s64, win_w: u32, win_h: u32, uv: *Vector2) -> bool {
    if win_w == 0 || win_h == 0 return false;

    cam_pos, cam_right, cam_up, cam_forward: Vector3;
    proj_x, proj_y: float;
    flux_compute_camera_basis(win_w, win_h, *cam_pos, *cam_right, *cam_up, *cam_forward, *proj_x, *proj_y);

    u := cast(float) mouse_x / cast(float) win_w;
    v := cast(float) mouse_y / cast(float) win_h;
    if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 return false;
    v = 1.0 - v;

    ndc_x := u * 2.0 - 1.0;
    ndc_y := 1.0 - v * 2.0;
    ray_dir := flux_safe_normalize3_cpu(cam_forward + cam_right * (ndc_x / proj_x) + cam_up * (ndc_y / proj_y));

    // Intersect with terrain mid-plane z = 0.0 in world space.
    denom := ray_dir.z;
    if abs(denom) < 0.00001 return false;
    t := (0.0 - cam_pos.z) / denom;
    if t <= 0.0 return false;

    hit := cam_pos + ray_dir * t;
    terrain_xz_scale := max(xz_scale, 0.0001);
    hit_u := hit.x / (2.0 * terrain_xz_scale) + 0.5;
    hit_v := hit.y / (2.0 * terrain_xz_scale) + 0.5;
    if hit_u < 0.0 || hit_u > 1.0 || hit_v < 0.0 || hit_v > 1.0 return false;

    uv.* = .{hit_u, hit_v};
    return true;
}

flux_ui_open: bool = true;

flux_ui :: () {
    if !app_ui_enabled return;
    using,except(Viewport) ImGui;
    Persist :: #import,file "../ui/persist_controls.jai";


    window_flags: WindowFlags = .AlwaysAutoResize | .NoFocusOnAppearing;
    if Begin("Flux", *flux_ui_open, window_flags) {
        Text("Controls - LMB: paint");
        SameLine();
        Text("RMB: orbit camera");
        Separator();

        Text("Brush Mode:");
        if RadioButton("Raise", brush_mode == FLUX_BRUSH_RAISE) brush_mode = .RAISE; SameLine();
        if RadioButton("Carve", brush_mode == FLUX_BRUSH_CARVE) brush_mode = .CARVE; SameLine();
        if RadioButton("Heat", brush_mode == FLUX_BRUSH_HEAT)   brush_mode = .HEAT;
        if brush_mode == {
            case .RAISE; Text("Raise: builds terrain upward.");
            case .CARVE; Text("Carve: cuts terrain downward.");
            case .HEAT;  Text("Heat: adds thermal energy and slight uplift.");
        }
        Separator();

        using Persist;
        SliderFloat("Brush Radius", *brush_radius_px, 10.0, 150.0, "%.1f px");
        SliderFloat("Brush Strength", *brush_strength, 0.001, 0.025, "%.3f");
        SliderFloat("Time Scale", *flux_time_scale, 0.01, 2.0, "%.2f");
        SliderFloat("Time of Day", *time_of_day, 0.0, 1.0, "%.2f");
        SliderFloat("XZ Scale", *xz_scale, 1.0, 16.0, "%.2f");
        SliderFloat("Fog", *fog_density, 0.0, 1.0, "%.3f");
        SliderFloat("Fog Exponent", *fog_exponent, 0.25, 8.0, "%.2f");
        SliderFloat("Grass Spacing", *grass_spacing, 0.6, 3.0, "%.2f");
        SliderFloat("Grass Blade Scale", *grass_blade_scale, 0.05, 2.0, "%.2f");
        SliderFloat("Grass Spawn Near", *grass_spawn_near, 0.2, 8.0, "%.2f");
        SliderFloat("Grass Spawn Far", *grass_spawn_far, 0.5, 16.0, "%.2f");
        SliderFloat("Grass Near Boost", *grass_spawn_near_boost, 0.0, 4.0, "%.2f");
        SliderFloat("Grass Far Density", *grass_spawn_far_density, 0.0, 1.0, "%.2f");
        SliderFloat("Grass Fade Start", *grass_fade_start, 0.5, 12.0, "%.2f");
        SliderFloat("Grass Fade End", *grass_fade_end, 1.0, 24.0, "%.2f");
        SliderFloat("Grass Wind Macro", *grass_wind_macro, 0.0, 2.0, "%.2f");
        SliderFloat("Grass Turbulence", *grass_wind_turbulence, 0.0, 2.0, "%.2f");
        SliderFloat("Grass Turb Freq", *grass_wind_turbulence_freq, 0.1, 3.0, "%.2f");
        SliderFloat("Camera Radius", *cam_radius, FLUX_CAMERA_RADIUS_MIN, FLUX_CAMERA_RADIUS_MAX, "%.2f");
        SliderFloat("Wind", *wind, 0, 0.5, "%.2f");
        Checkbox("Show Shadow Debug", *show_shadow_debug);
        _ = toggle("Render Grass", *render_grass, .{56.0, 0.0}, true, 0.09);

        Separator();
        Text("Dummy Knobs");
        _ = knob("Gain##dummy", *dummy_knob_gain, 0.0, 1.0, 0.005, "%.3f", .WIPER_DOT, 64.0, .ValueTooltip | .AlwaysClamp);
        SameLine();
        _ = knob_int("Steps##dummy", *dummy_knob_steps, 1, 24, 0.15, "%d", .STEPPED, 64.0, .ValueTooltip | .AlwaysClamp, 12);
        SameLine();
        _ = knob("Macro##dummy", *grass_wind_macro, 0.0, 2.0, 0.01, "%.2f", .SPACE, 64.0, .ValueTooltip | .AlwaysClamp);

        Separator();
        Text("Dummy Curve");
        if !flux_dummy_curve_initialized {
            flux_dummy_curve_points[0] = .{0.0, 0.0};
            flux_dummy_curve_points[1] = .{1.0, 1.0};
            flux_dummy_curve_points[2].x = CURVE_TERMINATOR;
            flux_dummy_curve_initialized = true;
        }
        _ = curve("Flux Dummy Curve", .{420.0, 160.0}, flux_dummy_curve_points.count, flux_dummy_curve_points.data, *flux_dummy_curve_selection);
        curve_sample := curve_value(time_of_day, flux_dummy_curve_points.count, flux_dummy_curve_points.data);
        Text("Curve sample @ Time of Day: %.3f", curve_sample);
    }
    End();
}

flux_write_render_payload :: (win_w: u32, win_h: u32) {
    params := sgpu_frame_ring_slot(*render_params_ring);
    using params_cpu := params.cpu;
    cam_radius = clamp(cam_radius, FLUX_CAMERA_RADIUS_MIN, FLUX_CAMERA_RADIUS_MAX);
    xz_scale = clamp(xz_scale, 1.0, 16.0);
    fog_density = clamp(fog_density, 0.0, 2.0);
    fog_exponent = clamp(fog_exponent, 0.25, 8.0);
    grass_spacing = clamp(grass_spacing, 0.6, 3.0);
    grass_blade_scale = clamp(grass_blade_scale, 0.05, 2.0);
    grass_spawn_near = clamp(grass_spawn_near, 0.0, 64.0);
    grass_spawn_far = clamp(grass_spawn_far, grass_spawn_near + 0.001, 128.0);
    grass_spawn_near_boost = clamp(grass_spawn_near_boost, 0.0, 8.0);
    grass_spawn_far_density = clamp(grass_spawn_far_density, 0.0, 8.0);
    grass_fade_start = clamp(grass_fade_start, 0.0, 128.0);
    grass_fade_end = clamp(grass_fade_end, grass_fade_start + 0.001, 256.0);
    grass_wind_macro = clamp(grass_wind_macro, 0.0, 2.0);
    grass_wind_turbulence = clamp(grass_wind_turbulence, 0.0, 2.0);
    grass_wind_turbulence_freq = clamp(grass_wind_turbulence_freq, 0.1, 3.0);

    cam_pos, cam_right, cam_up, cam_forward: Vector3;
    proj_x, proj_y: float;
    flux_compute_camera_basis(win_w, win_h, *cam_pos, *cam_right, *cam_up, *cam_forward, *proj_x, *proj_y);
    cam_near := cast(float) 0.08;
    cam_far := cast(float) 12.0;

    time_of_day = clamp(time_of_day, 0.0, 1.0);
    // `light_dir` is used in shading as the vector from surface toward the light.
    // Shadow-map view forward must point from light toward the scene, so use -light_dir.
    tau := cast(float) 6.28318530718;
    sun_phase := (time_of_day - 0.25) * tau;
    sun_elev := sin(sun_phase) * cast(float) 0.55;
    sun_xy := cos(sun_elev);
    light_dir := flux_safe_normalize3_cpu(Vector3.{cos(sun_phase) * sun_xy, sin(sun_phase) * sun_xy, sin(sun_elev)});
    light_forward := -light_dir;
    light_ref_up := Vector3.{0.0, 0.0, 1.0};
    light_right := cross(light_ref_up, light_forward);
    if dot(light_right, light_right) < 0.00001 {
        light_ref_up = .{0.0, 1.0, 0.0};
        light_right = cross(light_ref_up, light_forward);
    }
    light_right = flux_safe_normalize3_cpu(light_right);
    light_up := flux_safe_normalize3_cpu(cross(light_forward, light_right));

    light_extent := max(cast(float) 2.0, xz_scale * 1.15);
    light_near := cast(float) -3.0;
    light_far := cast(float) 3.0;
    light_center := Vector3.{0.0, 0.0, 0.0};

    use_b_as_src_f := ifx state.src_is_a then cast(float) 0.0 else cast(float) 1.0;
    shadow_tex_idx := cast(float) gpu_texture_view_index(shadow_map_view);
    shadow_sampler_idx := cast(float) (cast(u32) shadow_sampler - 1);
    shadow_bias := cast(float) 0.0035;
    shadow_texel := 1.0 / cast(float) FLUX_SHADOW_MAP_SIZE;

    params_cpu.camera_pos_proj_x = .{cam_pos.x, cam_pos.y, cam_pos.z, proj_x};
    params_cpu.camera_right_proj_y = .{cam_right.x, cam_right.y, cam_right.z, proj_y};
    params_cpu.camera_up_near = .{cam_up.x, cam_up.y, cam_up.z, cam_near};
    params_cpu.camera_forward_far = .{cam_forward.x, cam_forward.y, cam_forward.z, cam_far};

    params_cpu.light_right_extent = .{light_right.x, light_right.y, light_right.z, light_extent};
    params_cpu.light_up_near = .{light_up.x, light_up.y, light_up.z, light_near};
    params_cpu.light_forward_far = .{light_forward.x, light_forward.y, light_forward.z, light_far};
    params_cpu.light_center_use_b_as_src = .{light_center.x, light_center.y, light_center.z, use_b_as_src_f};

    params_cpu.shadow_tex_sampler_bias_texel = .{shadow_tex_idx, shadow_sampler_idx, shadow_bias, shadow_texel};
    params_cpu.sun_dir_xz_scale = .{light_dir.x, light_dir.y, light_dir.z, xz_scale};
    params_cpu.fog_time_wind_gain = .{fog_density, fog_exponent, cast(float) time, wind};
    params_cpu.grass_count_spacing_scale = .{cast(float) FLUX_GRASS_INSTANCE_COUNT, grass_spacing, grass_blade_scale, grass_wind_macro};
    params_cpu.grass_spawn_lod = .{grass_spawn_near, grass_spawn_far, grass_spawn_near_boost, grass_spawn_far_density};
    params_cpu.grass_fade_near_far = .{grass_fade_start, grass_fade_end, grass_wind_turbulence, grass_wind_turbulence_freq};
}

on_dll_init :: () {
    gpu_arena = gpu_make_arena(1024 * 1024 * 196, label = "flux arena");

    payload = gpu_alloc_buffer(*gpu_arena, Flux_Payload);
    render_params_ring = sgpu_make_frame_ring(*gpu_arena, Flux_Render_Params);

    sim_a_cpu := cast(*[FLUX_CELL_COUNT] Vector4) (cast(*Vector4) payload.cpu + FLUX_STATE_OFFSET);
    sim_b_cpu := cast(*[FLUX_CELL_COUNT] Vector4) (cast(*Vector4) payload.cpu + FLUX_STATE_OFFSET + FLUX_CELL_COUNT);

    sim_a_gpu := payload.gpu + (FLUX_STATE_OFFSET * size_of(Vector4)).(Gpu_Ptr);
    sim_b_gpu := sim_a_gpu + (FLUX_CELL_COUNT * size_of(Vector4)).(Gpu_Ptr);
    state = .{
        a_cpu = sim_a_cpu,
        b_cpu = sim_b_cpu,
        a_gpu = sim_a_gpu,
        b_gpu = sim_b_gpu,
        src_is_a = true,
    };
    state_initialized = false;

    for i: 0..FLUX_GRASS_INSTANCE_COUNT-1 {
        payload.cpu.grass_data[i] = .{0.0, 0.0, 0.0, 0.0};
    }

    control_ring = sgpu_make_frame_ring(*gpu_arena, Flux_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        control_ring.view.cpu[it] = .{
            cursor_uv = .{-1.0, -1.0},
            cursor_delta_uv = .{0.0, 0.0},
            brush_radius_px = brush_radius_px,
            brush_strength = brush_strength,
            time_scale = flux_time_scale,
            use_b_as_src = 0,
            brush_active = 0,
            brush_mode = .RAISE,
            frame_index = 0,
        };
    }

    shadow_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(shadow_sampler != 0, "Flux shadow sampler creation failed.");

    draw_data = .{
        vertex_params_gpu = payload.gpu,
        pixel_gpu = 0,
        index_gpu = 0,
        num_vertices = FLUX_MESH_VERTS,
        num_instances = 1,
    };

    ensure_shadow_targets();

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 && win_h > 0 {
        ensure_depth_target(cast(u32) win_w, cast(u32) win_h);
        flux_write_render_payload(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    render_w, render_h, render_ok := gpu_texture_view_size(swapchain_image);
    if render_ok && render_w > 0 && render_h > 0 {
        ensure_depth_target(render_w, render_h);
    }

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if render_ok && render_w > 0 && render_h > 0 {
        win_w = cast(s32) render_w;
        win_h = cast(s32) render_h;
        dims_ok = true;
    }

    flux_ui();
    using,only(GetIO) _ :: #import "ImGui";
    gizmo_result := view_gizmo(*cam_yaw, *cam_pitch, 1.0);
    imgui_wants_mouse := GetIO().WantCaptureMouse || gizmo_result.hovered || gizmo_result.in_use;

    control := sgpu_frame_ring_slot(*control_ring);
    control.cpu.use_b_as_src = ifx state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cpu.cursor_uv = .{-1.0, -1.0};
    control.cpu.cursor_delta_uv = .{0.0, 0.0};
    control.cpu.brush_radius_px = brush_radius_px;
    control.cpu.brush_strength = brush_strength;
    control.cpu.time_scale = flux_time_scale;
    control.cpu.brush_mode = brush_mode;
    control.cpu.brush_active = 0;
    control.cpu.frame_index = cast(u32) frame_count;

    if dims_ok && win_w > 0 && win_h > 0 {
        cam_pos, cam_right, cam_up, cam_forward: Vector3;
        proj_x_unused, proj_y_unused: float;
        flux_compute_camera_basis(cast(u32) win_w, cast(u32) win_h, *cam_pos, *cam_right, *cam_up, *cam_forward, *proj_x_unused, *proj_y_unused);
        _ = cam_pos;
        _ = cam_up;

        move := Vector3.{0.0, 0.0, 0.0};

        if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN move += cam_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN move -= cam_forward;
        if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN move -= cam_right;
        if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN move += cam_right;

        move_len2 := dot(move, move);
        if move_len2 > 0.00001 {
            move = flux_safe_normalize3_cpu(move);
            move_speed := 2.6 * dt;
            cam_target += move * move_speed;
        }
    }

    mx, my, mouse_ok := get_mouse_pointer_position(cast(Window_Type) window, true);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 && !imgui_wants_mouse {
        left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
        right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

        if right_down {
            if have_last_mouse_px {
                dx := cast(float) (mx - last_mouse_x);
                dy := cast(float) (my - last_mouse_y);
                cam_yaw -= dx * 0.0085;
                cam_pitch -= dy * 0.0065;
                cam_pitch = clamp(cam_pitch, -1.40, 1.40);
            }
            have_last_mouse_uv = false;
        } else if left_down {
            hit_uv: Vector2;
            if flux_mouse_ray_to_terrain_uv(mx, my, cast(u32) win_w, cast(u32) win_h, *hit_uv) {
                control.cpu.cursor_uv = hit_uv;
                control.cpu.brush_active = 1;
                if have_last_mouse_uv {
                    control.cpu.cursor_delta_uv = .{hit_uv.x - last_mouse_uv.x, hit_uv.y - last_mouse_uv.y};
                }
                last_mouse_uv = hit_uv;
                have_last_mouse_uv = true;
            } else {
                have_last_mouse_uv = false;
            }
        } else {
            have_last_mouse_uv = false;
        }

        last_mouse_x = mx;
        last_mouse_y = my;
        have_last_mouse_px = true;
    } else {
        have_last_mouse_uv = false;
        have_last_mouse_px = false;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    if !state_initialized {
        init_state_start := current_time_monotonic();
        result = gpu_set_pipeline(cmd_buff, init_compute.pipeline);
        assert(result == .SUCCESS, tprint("Flux init compute set pipeline failed: %", result));
        gpu_dispatch_buffers(cmd_buff, .[state.a_gpu], .[(FLUX_CELL_COUNT + 63) / 64, 1, 1]);
        gpu_dispatch_buffers(cmd_buff, .[state.b_gpu], .[(FLUX_CELL_COUNT + 63) / 64, 1, 1]);
        init_state_ms := to_float64_seconds(current_time_monotonic() - init_state_start) * 1000.0;
        log("FLUX init_state_gpu_encode ms=%", init_state_ms);
        state_initialized = true;
    }

    render_params := sgpu_frame_ring_slot(*render_params_ring);
    copy_result := gpu_memcpy(cmd_buff, payload.gpu, render_params.gpu, size_of(Flux_Render_Params));
    assert(copy_result == .SUCCESS, tprint("Flux params memcpy failed: %", copy_result));

    result = gpu_set_pipeline(cmd_buff, step_compute.pipeline);
    assert(result == .SUCCESS, tprint("Flux compute set pipeline failed: %", result));
    gpu_dispatch_buffers(cmd_buff, .[state.a_gpu, control.gpu], .[(FLUX_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*state);

    if dims_ok && win_w > 0 && win_h > 0 {
        flux_write_render_payload(cast(u32) win_w, cast(u32) win_h);
    }

    if render_grass {
        result = gpu_set_pipeline(cmd_buff, grass_spawn_compute.pipeline);
        assert(result == .SUCCESS, tprint("Flux grass compute set pipeline failed: %", result));
        gpu_dispatch_buffers(cmd_buff, .[payload.gpu], .[(FLUX_GRASS_INSTANCE_COUNT + 63) / 64, 1, 1]);
    }

    {
        // Render the shadow map that the main scene pass samples for lighting.
        gpu_begin_scoped_render_pass(cmd_buff, {
            depth_target = .{
                view = shadow_depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{
                    depth = 1.0,
                    stencil = 0,
                },
            },
            color_targets = .[
                {
                    view = shadow_map_view,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[1.0, 1.0, 1.0, 1.0],
                }
            ]
        }, .COLOR_ATTACHMENT_WRITE, .SHADER_READ);

        gpu_set_depth_stencil_state(cmd_buff, {depth_test = .LESS, depth_mode = .READ | .WRITE,});
        gpu_set_pipeline(cmd_buff, shadow_shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, payload.gpu, draw_data.num_vertices, draw_data.num_instances);
        if render_grass {
            gpu_set_pipeline(cmd_buff, grass_shadow_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, payload.gpu, FLUX_GRASS_VERTS_PER_INSTANCE, cast(u32) FLUX_GRASS_INSTANCE_COUNT);
        }
    }

    {
        // Render the visible scene into the swapchain before the ImGui overlay pass loads it.
        gpu_begin_scoped_render_pass(cmd_buff, {
            depth_target = .{
                view = depth_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_value = .{
                    depth = 1.0,
                    stencil = 0,
                },
            },
            color_targets = .[
                {
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0.008, 0.010, 0.016, 1.0],
                }
            ]
        }, .COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_WRITE);
        gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
        gpu_set_pipeline(cmd_buff, sky_shader.pipeline);
        sky_draw_result := gpu_draw_instanced_direct(cmd_buff, payload.gpu, 6, 1);

        gpu_set_depth_stencil_state(cmd_buff, {depth_test = .LESS, depth_mode = .READ | .WRITE,});
        gpu_set_pipeline(cmd_buff, shader.pipeline);
        gpu_draw_instanced_direct(cmd_buff, payload.gpu, draw_data.num_vertices, draw_data.num_instances);

        if render_grass {
            gpu_set_depth_stencil_state(cmd_buff, {depth_test = .LESS, depth_mode = .READ | .WRITE,});
            gpu_set_pipeline(cmd_buff, grass_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, payload.gpu, FLUX_GRASS_VERTS_PER_INSTANCE, cast(u32) FLUX_GRASS_INSTANCE_COUNT);
        }

        if show_shadow_debug {
            gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
            gpu_set_pipeline(cmd_buff, debug_shadow_shader.pipeline);
            gpu_draw_instanced_direct(cmd_buff, payload.gpu, 6, 1);
        }
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if depth_view != 0 && depth_w == width && depth_h == height return;

    res, depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS, tprint("Flux depth texture creation failed: %", res));
    assert(depth_texture != 0, "Flux depth texture handle invalid.");

    depth_view = gpu_texture_view(depth_texture);
    assert(depth_view != 0, "Flux depth view creation failed.");

    depth_w = width;
    depth_h = height;
}

ensure_shadow_targets :: () {
    if shadow_map_view != 0 && shadow_depth_view != 0 return;

    res_map, shadow_map_texture= := gpu_create_texture(.{
        dimensions = .[FLUX_SHADOW_MAP_SIZE, FLUX_SHADOW_MAP_SIZE, 1],
        format = .R32_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    assert(res_map == .SUCCESS, tprint("Flux shadow map texture creation failed: %", res_map));
    assert(shadow_map_texture != 0, "Flux shadow map texture handle invalid.");

    shadow_map_view = gpu_texture_view(shadow_map_texture);
    assert(shadow_map_view != 0, "Flux shadow map view creation failed.");

    res_depth, shadow_depth_texture= := gpu_create_texture(.{
        dimensions = .[FLUX_SHADOW_MAP_SIZE, FLUX_SHADOW_MAP_SIZE, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res_depth == .SUCCESS, tprint("Flux shadow depth texture creation failed: %", res_depth));
    assert(shadow_depth_texture != 0, "Flux shadow depth texture handle invalid.");

    shadow_depth_view = gpu_texture_view(shadow_depth_texture);
    assert(shadow_depth_view != 0, "Flux shadow depth view creation failed.");
}

#import "Math";
#load "../SGPU_App_Common.jai";
#load "../ui/curve_editor.jai";
#load "../ui/knob.jai";
#load "../ui/toggle_widget.jai";
#load "../ui/view_gizmo.jai";
#import "Jai-Shader-Transpiler";
#load "shaders/flux_shader.jai";
Input :: #import "Input";
ImGui :: #import "ImGui";

main_raster: Gpu_Raster_Desc : {
    cull = .NONE,
    depth_format = .D32_SFLOAT,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
};

shadow_raster: Gpu_Raster_Desc : {
    cull = .NONE,
    depth_format = .D32_SFLOAT,
    color_targets = .[ .{format = .R32_SFLOAT} ],
};
