WRITE_SHADER_OUTPUT :: true;

FLUX_SHADOW_MAP_SIZE :: 2048;

Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    index_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

graphics_pipeline: Gpu_Pipeline;
sky_pipeline: Gpu_Pipeline;
debug_shadow_pipeline: Gpu_Pipeline;
shadow_pipeline: Gpu_Pipeline;
compute_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

flux_depth_texture: Gpu_Texture;
flux_depth_view: Gpu_Texture_View;
flux_depth_w: u32;
flux_depth_h: u32;

flux_shadow_map_texture: Gpu_Texture;
flux_shadow_map_view: Gpu_Texture_View;
flux_shadow_depth_texture: Gpu_Texture;
flux_shadow_depth_view: Gpu_Texture_View;
flux_shadow_sampler: Gpu_Sampler;

flux_payload_cpu: *[FLUX_PARAM_V4_COUNT + FLUX_CELL_COUNT * 2] Vector4;
flux_payload_gpu: Gpu_Ptr;
flux_state: AB_Buffer([FLUX_CELL_COUNT] Vector4);
flux_control_ring_cpu: *[SGPU_FRAMES_IN_FLIGHT] Flux_Compute_Control;
flux_control_ring_gpu: Gpu_Ptr;

flux_last_mouse_uv: Vector2;
flux_have_last_mouse_uv := false;
flux_last_mouse_x: s64;
flux_last_mouse_y: s64;
flux_have_last_mouse_px := false;

flux_brush_mode: u32 = FLUX_BRUSH_RAISE;
flux_brush_radius_px: float = 82.0;
flux_brush_strength: float = 0.018;
flux_time_scale: float = 0.35;
flux_show_shadow_debug := true;
flux_xz_scale: float = 2.6;
flux_fog_density: float = 0.18;
flux_fog_exponent: float = 1.0;
flux_time_of_day: float = 0.36;

flux_cam_target := Vector3.{0.0, 0.0, 0.0};
flux_cam_yaw: float = 0.78;
flux_cam_pitch: float = 0.58;
flux_cam_radius: float = 2.9;
FLUX_CAMERA_RADIUS_MIN :: 2.4;
FLUX_CAMERA_RADIUS_MAX :: 6.0;

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
        cos(flux_cam_pitch) * cos(flux_cam_yaw),
        cos(flux_cam_pitch) * sin(flux_cam_yaw),
        sin(flux_cam_pitch),
    };
    cam_pos.* = flux_cam_target + cam_dir * flux_cam_radius;
    cam_forward.* = flux_safe_normalize3_cpu(flux_cam_target - cam_pos.*);

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
    xz_scale := max(flux_xz_scale, 0.0001);
    hit_u := hit.x / (2.0 * xz_scale) + 0.5;
    hit_v := hit.y / (2.0 * xz_scale) + 0.5;
    if hit_u < 0.0 || hit_u > 1.0 || hit_v < 0.0 || hit_v > 1.0 return false;

    uv.* = .{hit_u, hit_v};
    return true;
}

flux_init_state :: (state: *[FLUX_CELL_COUNT] Vector4) {
    inv_w := 1.0 / cast(float) FLUX_WIDTH;
    inv_h := 1.0 / cast(float) FLUX_HEIGHT;
    for y: 0..FLUX_HEIGHT-1 {
        for x: 0..FLUX_WIDTH-1 {
            idx := y * FLUX_WIDTH + x;
            fx := cast(float) x * inv_w;
            fy := cast(float) y * inv_h;

            h1 := sin(fx * 9.2) * 0.34;
            h2 := cos(fy * 11.4) * 0.30;
            h3 := sin((fx + fy * 0.7) * 18.8) * 0.14;
            ridge := sin((fx * 2.0 - fy * 1.7) * 27.0) * 0.08;
            crater_x := fx - 0.72;
            crater_y := fy - 0.43;
            crater := exp(-(crater_x * crater_x + crater_y * crater_y) * 84.0) * 0.85;
            hot_x := fx - 0.22;
            hot_y := fy - 0.72;
            hot_spot := exp(-(hot_x * hot_x + hot_y * hot_y) * 120.0);

            height := h1 + h2 + h3 + ridge - crater;
            temp := 0.08 + hot_spot * 1.4;
            vx := (fy - 0.5) * 0.06;
            vy := -(fx - 0.5) * 0.06;
            state.*[idx] = .{height, vx, vy, temp};
        }
    }
}

flux_ui :: () -> bool {
    using,except(Viewport) _ :: #import "ImGui";

    window_flags: WindowFlags = .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing;
    open: bool = true;
    if Begin("Flux", *open, window_flags) {
        Text("Controls - LMB: paint");
        SameLine();
        Text("RMB: orbit camera");
        Separator();

        Text("Brush Mode:");
        if RadioButton("Raise", flux_brush_mode == FLUX_BRUSH_RAISE) flux_brush_mode = FLUX_BRUSH_RAISE;
        SameLine();
        if RadioButton("Carve", flux_brush_mode == FLUX_BRUSH_CARVE) flux_brush_mode = FLUX_BRUSH_CARVE;
        SameLine();
        if RadioButton("Heat", flux_brush_mode == FLUX_BRUSH_HEAT) flux_brush_mode = FLUX_BRUSH_HEAT;
        if flux_brush_mode == FLUX_BRUSH_RAISE {
            Text("Raise: builds terrain upward.");
        } else if flux_brush_mode == FLUX_BRUSH_CARVE {
            Text("Carve: cuts terrain downward.");
        } else if flux_brush_mode == FLUX_BRUSH_HEAT {
            Text("Heat: adds thermal energy and slight uplift.");
        }

        Separator();
        SliderFloat("Brush Radius", *flux_brush_radius_px, 10.0, 150.0, "%.1f px");
        SliderFloat("Brush Strength", *flux_brush_strength, 0.001, 0.025, "%.3f");
        SliderFloat("Time Scale", *flux_time_scale, 0.01, 2.0, "%.2f");
        SliderFloat("Time of Day", *flux_time_of_day, 0.0, 1.0, "%.2f");
        SliderFloat("XZ Scale", *flux_xz_scale, 1.0, 16.0, "%.2f");
        SliderFloat("Fog", *flux_fog_density, 0.0, 1.0, "%.3f");
        SliderFloat("Fog Exponent", *flux_fog_exponent, 0.25, 8.0, "%.2f");
        SliderFloat("Camera Radius", *flux_cam_radius, FLUX_CAMERA_RADIUS_MIN, FLUX_CAMERA_RADIUS_MAX, "%.2f");
        Checkbox("Show Shadow Debug", *flux_show_shadow_debug);
    }
    End();

    io := GetIO();
    return io.WantCaptureMouse;
}

flux_write_render_payload :: (win_w: u32, win_h: u32) {
    payload := cast(*[FLUX_PARAM_V4_COUNT] Vector4) flux_payload_cpu;
    flux_cam_radius = clamp(flux_cam_radius, FLUX_CAMERA_RADIUS_MIN, FLUX_CAMERA_RADIUS_MAX);
    flux_xz_scale = clamp(flux_xz_scale, 1.0, 16.0);
    flux_fog_density = clamp(flux_fog_density, 0.0, 2.0);
    flux_fog_exponent = clamp(flux_fog_exponent, 0.25, 8.0);

    cam_pos, cam_right, cam_up, cam_forward: Vector3;
    proj_x, proj_y: float;
    flux_compute_camera_basis(win_w, win_h, *cam_pos, *cam_right, *cam_up, *cam_forward, *proj_x, *proj_y);
    cam_near := cast(float) 0.08;
    cam_far := cast(float) 12.0;

    flux_time_of_day = clamp(flux_time_of_day, 0.0, 1.0);
    // `light_dir` is used in shading as the vector from surface toward the light.
    // Shadow-map view forward must point from light toward the scene, so use -light_dir.
    tau := cast(float) 6.28318530718;
    sun_phase := (flux_time_of_day - 0.25) * tau;
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

    light_extent := max(cast(float) 2.0, flux_xz_scale * 1.15);
    light_near := cast(float) -3.0;
    light_far := cast(float) 3.0;
    light_center := Vector3.{0.0, 0.0, 0.0};

    use_b_as_src_f := ifx flux_state.src_is_a then cast(float) 0.0 else cast(float) 1.0;
    shadow_tex_idx := cast(float) (cast(u32) flux_shadow_map_view - 1);
    shadow_sampler_idx := cast(float) (cast(u32) flux_shadow_sampler - 1);
    shadow_bias := cast(float) 0.0035;
    shadow_texel := 1.0 / cast(float) FLUX_SHADOW_MAP_SIZE;

    payload.*[0] = .{cam_pos.x, cam_pos.y, cam_pos.z, proj_x};
    payload.*[1] = .{cam_right.x, cam_right.y, cam_right.z, proj_y};
    payload.*[2] = .{cam_up.x, cam_up.y, cam_up.z, cam_near};
    payload.*[3] = .{cam_forward.x, cam_forward.y, cam_forward.z, cam_far};

    payload.*[4] = .{light_right.x, light_right.y, light_right.z, light_extent};
    payload.*[5] = .{light_up.x, light_up.y, light_up.z, light_near};
    payload.*[6] = .{light_forward.x, light_forward.y, light_forward.z, light_far};
    payload.*[7] = .{light_center.x, light_center.y, light_center.z, use_b_as_src_f};

    payload.*[8] = .{shadow_tex_idx, shadow_sampler_idx, shadow_bias, shadow_texel};
    payload.*[9] = .{light_dir.x, light_dir.y, light_dir.z, flux_xz_scale};
    payload.*[10] = .{flux_fog_density, flux_fog_exponent, 0.0, 0.0};
}

on_dll_init :: () {
    compute_source := cast([]u8) get_transpiled(.METAL, flux_step_compute);
    assert(compute_source.count > 0, "Compute transpilation failed (flux_step_compute).");

    graphics_source := cast([]u8) get_transpiled(.METAL, flux_vertex_main, flux_fragment_main);
    assert(graphics_source.count > 0, "Graphics transpilation failed (flux shaders).");
    sky_source := cast([]u8) get_transpiled(.METAL, flux_sky_vertex_main, flux_sky_fragment_main);
    assert(sky_source.count > 0, "Graphics transpilation failed (flux sky shaders).");
    debug_shadow_source := cast([]u8) get_transpiled(.METAL, flux_debug_shadow_vertex_main, flux_debug_shadow_fragment_main);
    assert(debug_shadow_source.count > 0, "Graphics transpilation failed (flux debug shadow shaders).");

    shadow_source := cast([]u8) get_transpiled(.METAL, flux_shadow_vertex_main, flux_shadow_fragment_main);
    assert(shadow_source.count > 0, "Graphics transpilation failed (flux shadow shaders).");

    main_raster: Gpu_Raster_Desc = {
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
    };
    shadow_raster: Gpu_Raster_Desc = {
        cull = .NONE,
        depth_format = .D32_SFLOAT,
        color_targets = .[
            .{format = .R32_SFLOAT}
        ],
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, main_raster, .METAL, flux_vertex_main, flux_fragment_main);
    assert(graphics_ok, "Flux graphics pipeline creation failed.");
    sky_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *sky_pipeline, sky_source, main_raster, .METAL, flux_sky_vertex_main, flux_sky_fragment_main);
    assert(sky_ok, "Flux sky pipeline creation failed.");
    debug_shadow_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *debug_shadow_pipeline, debug_shadow_source, main_raster, .METAL, flux_debug_shadow_vertex_main, flux_debug_shadow_fragment_main);
    assert(debug_shadow_ok, "Flux debug shadow pipeline creation failed.");

    shadow_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *shadow_pipeline, shadow_source, shadow_raster, .METAL, flux_shadow_vertex_main, flux_shadow_fragment_main);
    assert(shadow_ok, "Flux shadow pipeline creation failed.");

    compute_ok := SHR.shader_hot_reload_create_and_register_compute_pipeline(*shader_reload_ctx, *compute_pipeline, compute_source, .METAL, flux_step_compute);
    assert(compute_ok, "Flux compute pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 196, label = "flux arena");

    payload_storage, payload_storage_gpu := gpu_arena_alloc(*gpu_arena, [FLUX_PARAM_V4_COUNT + FLUX_CELL_COUNT * 2] Vector4);
    flux_payload_cpu = payload_storage;
    flux_payload_gpu = payload_storage_gpu;

    sim_a_cpu := cast(*[FLUX_CELL_COUNT] Vector4) (cast(*Vector4) flux_payload_cpu + FLUX_STATE_OFFSET);
    sim_b_cpu := cast(*[FLUX_CELL_COUNT] Vector4) (cast(*Vector4) flux_payload_cpu + FLUX_STATE_OFFSET + FLUX_CELL_COUNT);
    flux_init_state(sim_a_cpu);
    sim_b_cpu.* = sim_a_cpu.*;

    sim_a_gpu := flux_payload_gpu + (FLUX_STATE_OFFSET * size_of(Vector4)).(Gpu_Ptr);
    sim_b_gpu := sim_a_gpu + (FLUX_CELL_COUNT * size_of(Vector4)).(Gpu_Ptr);
    flux_state = .{
        a_cpu = sim_a_cpu,
        b_cpu = sim_b_cpu,
        a_gpu = sim_a_gpu,
        b_gpu = sim_b_gpu,
        src_is_a = true,
    };

    flux_control_ring_cpu, flux_control_ring_gpu = sgpu_arena_alloc_frame_ring(*gpu_arena, Flux_Compute_Control);
    for 0..SGPU_FRAMES_IN_FLIGHT-1 {
        flux_control_ring_cpu.*[it] = .{
            cursor_uv = .{-1.0, -1.0},
            cursor_delta_uv = .{0.0, 0.0},
            brush_radius_px = flux_brush_radius_px,
            brush_strength = flux_brush_strength,
            time_scale = flux_time_scale,
            use_b_as_src = 0,
            brush_active = 0,
            brush_mode = FLUX_BRUSH_RAISE,
            frame_index = 0,
        };
    }

    flux_shadow_sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(flux_shadow_sampler != 0, "Flux shadow sampler creation failed.");

    draw_data = .{
        vertex_params_gpu = flux_payload_gpu,
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

    imgui_wants_mouse := flux_ui();

    control := sgpu_frame_ring_cpu_slot(flux_control_ring_cpu);
    control.use_b_as_src = ifx flux_state.src_is_a then cast(u32) 0 else cast(u32) 1;
    control.cursor_uv = .{-1.0, -1.0};
    control.cursor_delta_uv = .{0.0, 0.0};
    control.brush_radius_px = flux_brush_radius_px;
    control.brush_strength = flux_brush_strength;
    control.time_scale = flux_time_scale;
    control.brush_mode = flux_brush_mode;
    control.brush_active = 0;
    control.frame_index = cast(u32) frame_count;

    if dims_ok && win_w > 0 && win_h > 0 {
        cam_pos, cam_right, cam_up, cam_forward: Vector3;
        proj_x_unused, proj_y_unused: float;
        flux_compute_camera_basis(cast(u32) win_w, cast(u32) win_h, *cam_pos, *cam_right, *cam_up, *cam_forward, *proj_x_unused, *proj_y_unused);
        _ = cam_pos;
        _ = cam_up;

        move := Vector3.{0.0, 0.0, 0.0};
        if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN {
            move += cam_forward;
        }
        if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN {
            move -= cam_forward;
        }
        if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN {
            move -= cam_right;
        }
        if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN {
            move += cam_right;
        }
        move_len2 := dot(move, move);
        if move_len2 > 0.00001 {
            move = flux_safe_normalize3_cpu(move);
            move_speed := 2.6 * dt;
            flux_cam_target += move * move_speed;
        }
    }

    mx, my, mouse_ok := get_mouse_pointer_position(cast(Window_Type) window, true);
    if mouse_ok && dims_ok && win_w > 0 && win_h > 0 && !imgui_wants_mouse {
        left_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0;
        right_down := (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN) != 0;

        if right_down {
            if flux_have_last_mouse_px {
                dx := cast(float) (mx - flux_last_mouse_x);
                dy := cast(float) (my - flux_last_mouse_y);
                flux_cam_yaw -= dx * 0.0085;
                flux_cam_pitch -= dy * 0.0065;
                flux_cam_pitch = clamp(flux_cam_pitch, -1.40, 1.40);
            }
            flux_have_last_mouse_uv = false;
        } else if left_down {
            hit_uv: Vector2;
            if flux_mouse_ray_to_terrain_uv(mx, my, cast(u32) win_w, cast(u32) win_h, *hit_uv) {
                control.cursor_uv = hit_uv;
                control.brush_active = 1;
                if flux_have_last_mouse_uv {
                    control.cursor_delta_uv = .{hit_uv.x - flux_last_mouse_uv.x, hit_uv.y - flux_last_mouse_uv.y};
                }
                flux_last_mouse_uv = hit_uv;
                flux_have_last_mouse_uv = true;
            } else {
                flux_have_last_mouse_uv = false;
            }
        } else {
            flux_have_last_mouse_uv = false;
        }

        flux_last_mouse_x = mx;
        flux_last_mouse_y = my;
        flux_have_last_mouse_px = true;
    } else {
        flux_have_last_mouse_uv = false;
        flux_have_last_mouse_px = false;
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    result = gpu_set_pipeline(cmd_buff, compute_pipeline);
    assert(result == .SUCCESS, tprint("Flux compute set pipeline failed: %", result));
    control_gpu := sgpu_frame_ring_gpu_slot(flux_control_ring_gpu, Flux_Compute_Control);
    gpu_dispatch_buffers(cmd_buff, .[flux_state.a_gpu, control_gpu], .[(FLUX_CELL_COUNT + 63) / 64, 1, 1]);

    ab_buffer_advance(*flux_state);

    if dims_ok && win_w > 0 && win_h > 0 {
        flux_write_render_payload(cast(u32) win_w, cast(u32) win_h);
    }

    gpu_begin_render_pass(cmd_buff, {
        depth_target = .{
            view = flux_shadow_depth_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{
                depth = 1.0,
                stencil = 0,
            },
        },
        color_targets = .[
            {
                view = flux_shadow_map_view,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[1.0, 1.0, 1.0, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .LESS, depth_mode = .READ | .WRITE,});
    gpu_set_pipeline(cmd_buff, shadow_pipeline);
    shadow_draw_result := gpu_draw_instanced_direct(cmd_buff, flux_payload_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(shadow_draw_result == .SUCCESS, tprint("Flux shadow draw failed: %", shadow_draw_result));
    gpu_end_render_pass(cmd_buff);

    gpu_begin_render_pass(cmd_buff, {
        depth_target = .{
            view = flux_depth_view,
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
    });

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
    gpu_set_pipeline(cmd_buff, sky_pipeline);
    sky_draw_result := gpu_draw_instanced_direct(cmd_buff, flux_payload_gpu, 6, 1);
    assert(sky_draw_result == .SUCCESS, tprint("Flux sky draw failed: %", sky_draw_result));

    gpu_set_depth_stencil_state(cmd_buff, {depth_test = .LESS, depth_mode = .READ | .WRITE,});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    draw_result := gpu_draw_instanced_direct(cmd_buff, flux_payload_gpu, draw_data.num_vertices, draw_data.num_instances);
    assert(draw_result == .SUCCESS, tprint("Flux draw failed: %", draw_result));

    if flux_show_shadow_debug {
        gpu_set_depth_stencil_state(cmd_buff, {depth_test = .ALWAYS, depth_mode = .NONE,});
        gpu_set_pipeline(cmd_buff, debug_shadow_pipeline);
        debug_draw_result := gpu_draw_instanced_direct(cmd_buff, flux_payload_gpu, 6, 1);
        assert(debug_draw_result == .SUCCESS, tprint("Flux debug shadow draw failed: %", debug_draw_result));
    }
    gpu_end_render_pass(cmd_buff);

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if flux_depth_view != 0 && flux_depth_w == width && flux_depth_h == height return;

    res, flux_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS, tprint("Flux depth texture creation failed: %", res));
    assert(flux_depth_texture != 0, "Flux depth texture handle invalid.");

    flux_depth_view = gpu_texture_view(flux_depth_texture);
    assert(flux_depth_view != 0, "Flux depth view creation failed.");

    flux_depth_w = width;
    flux_depth_h = height;
}

ensure_shadow_targets :: () {
    if flux_shadow_map_view != 0 && flux_shadow_depth_view != 0 return;

    res_map, flux_shadow_map_texture= := gpu_create_texture(.{
        dimensions = .[FLUX_SHADOW_MAP_SIZE, FLUX_SHADOW_MAP_SIZE, 1],
        format = .R32_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    assert(res_map == .SUCCESS, tprint("Flux shadow map texture creation failed: %", res_map));
    assert(flux_shadow_map_texture != 0, "Flux shadow map texture handle invalid.");

    flux_shadow_map_view = gpu_texture_view(flux_shadow_map_texture);
    assert(flux_shadow_map_view != 0, "Flux shadow map view creation failed.");

    res_depth, flux_shadow_depth_texture= := gpu_create_texture(.{
        dimensions = .[FLUX_SHADOW_MAP_SIZE, FLUX_SHADOW_MAP_SIZE, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res_depth == .SUCCESS, tprint("Flux shadow depth texture creation failed: %", res_depth));
    assert(flux_shadow_depth_texture != 0, "Flux shadow depth texture handle invalid.");

    flux_shadow_depth_view = gpu_texture_view(flux_shadow_depth_texture);
    assert(flux_shadow_depth_view != 0, "Flux shadow depth view creation failed.");
}

#import "Math";
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
SHR :: #import,file "../shader_hot_reload.jai";
#load "shaders/flux_shader.jai";
Input :: #import "Input";
