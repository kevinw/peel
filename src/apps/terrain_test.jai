#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";

terrain_voxel_ctx: Terrain_Voxel.Terrain_Voxel_Context;
terrain_render_ctx: Terrain_Render.Terrain_Render_Context;
terrain_mesh_compute_ctx: Terrain_Mesh_Compute.Terrain_Mesh_Compute_Context;

terrain_depth_texture: Gpu_Texture;
terrain_depth_view: Gpu_Texture_View;
terrain_depth_w: u32;
terrain_depth_h: u32;

terrain_orbit_center := Vector3.{0.0, -0.8, 0.0};
terrain_camera_pos := Vector3.{0.0, 2.7, 5.6};
terrain_camera_yaw: float = 0.0;
terrain_camera_pitch: float = 0.0;
terrain_last_manual_time: float64 = -1000000.0;
terrain_prev_mouse_pos: Vector2;
terrain_have_prev_mouse := false;

terrain_fly_speed: float = 8.0;
terrain_mouse_sensitivity: float = 0.0032;
terrain_auto_orbit_delay_sec: float64 = 7.6;
terrain_orbit_blend_speed: float = 3.5;
terrain_dig_radius: float = 0.94;
terrain_dig_strength: float = 2.4;
terrain_ray_max_dist: float = 80.0;
terrain_ray_step: float = 0.21;

terrain_forward_from_angles :: (yaw: float, pitch: float) -> Vector3 {
    cp := cos(pitch);
    return .{
        sin(yaw) * cp,
        sin(pitch),
        -cos(yaw) * cp,
    };
}

terrain_angles_from_forward :: (forward: Vector3) -> (yaw: float, pitch: float) {
    n := forward;
    normalize(*n, fallback = .{0.0, 0.0, -1.0});
    return atan2(n.x, -n.z), asin(clamp(n.y, -1.0, 1.0));
}

terrain_sample_index :: inline (x: s64, y: s64, z: s64) -> s64 {
    return x + y * Terrain_Voxel.Sample_Res + z * Terrain_Voxel.Sample_Res * Terrain_Voxel.Sample_Res;
}

terrain_sample_density_trilinear :: (chunk: *Terrain_Voxel.Chunk, p: Vector3, out_density: *float) -> bool {
    min_b := chunk.origin;
    max_b := chunk.origin + Vector3.{Terrain_Voxel.Chunk_World_Size, Terrain_Voxel.Chunk_World_Size, Terrain_Voxel.Chunk_World_Size};
    if p.x < min_b.x || p.y < min_b.y || p.z < min_b.z return false;
    if p.x > max_b.x || p.y > max_b.y || p.z > max_b.z return false;

    local := p - chunk.origin;
    gx := clamp(local.x / Terrain_Voxel.Voxel_Size, 0.0, cast(float) (Terrain_Voxel.Sample_Res - 1));
    gy := clamp(local.y / Terrain_Voxel.Voxel_Size, 0.0, cast(float) (Terrain_Voxel.Sample_Res - 1));
    gz := clamp(local.z / Terrain_Voxel.Voxel_Size, 0.0, cast(float) (Terrain_Voxel.Sample_Res - 1));

    x0 := cast(s64) floor(gx);
    y0 := cast(s64) floor(gy);
    z0 := cast(s64) floor(gz);
    x1 := min(x0 + 1, Terrain_Voxel.Sample_Res - 1);
    y1 := min(y0 + 1, Terrain_Voxel.Sample_Res - 1);
    z1 := min(z0 + 1, Terrain_Voxel.Sample_Res - 1);

    tx := gx - cast(float) x0;
    ty := gy - cast(float) y0;
    tz := gz - cast(float) z0;

    d000 := cast(float) chunk.density[terrain_sample_index(x0, y0, z0)] / Terrain_Voxel.Density_Scale;
    d100 := cast(float) chunk.density[terrain_sample_index(x1, y0, z0)] / Terrain_Voxel.Density_Scale;
    d010 := cast(float) chunk.density[terrain_sample_index(x0, y1, z0)] / Terrain_Voxel.Density_Scale;
    d110 := cast(float) chunk.density[terrain_sample_index(x1, y1, z0)] / Terrain_Voxel.Density_Scale;
    d001 := cast(float) chunk.density[terrain_sample_index(x0, y0, z1)] / Terrain_Voxel.Density_Scale;
    d101 := cast(float) chunk.density[terrain_sample_index(x1, y0, z1)] / Terrain_Voxel.Density_Scale;
    d011 := cast(float) chunk.density[terrain_sample_index(x0, y1, z1)] / Terrain_Voxel.Density_Scale;
    d111 := cast(float) chunk.density[terrain_sample_index(x1, y1, z1)] / Terrain_Voxel.Density_Scale;

    c00 := d000 + (d100 - d000) * tx;
    c10 := d010 + (d110 - d010) * tx;
    c01 := d001 + (d101 - d001) * tx;
    c11 := d011 + (d111 - d011) * tx;
    c0 := c00 + (c10 - c00) * ty;
    c1 := c01 + (c11 - c01) * ty;
    out_density.* = c0 + (c1 - c0) * tz;
    return true;
}

terrain_density_at_world :: (ctx: *Terrain_Voxel.Terrain_Voxel_Context, p: Vector3, out_density: *float) -> bool {
    for *ctx.chunks {
        if terrain_sample_density_trilinear(it, p, out_density) return true;
    }
    return false;
}

terrain_mouse_world_ray :: (mouse_x: float, mouse_y: float, viewport: Vector2, camera_pos: Vector3, yaw: float, pitch: float) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if viewport.x <= 1.0 || viewport.y <= 1.0 return camera_pos, .{0.0, 0.0, -1.0}, false;

    nx := (mouse_x / viewport.x) * 2.0 - 1.0;
    ny := (mouse_y / viewport.y) * 2.0 - 1.0;

    forward := terrain_forward_from_angles(yaw, pitch);
    up_axis := Vector3.{0.0, 1.0, 0.0};
    right := cross(forward, up_axis);
    normalize(*right, fallback = .{1.0, 0.0, 0.0});
    cam_up := cross(right, forward);
    normalize(*cam_up, fallback = .{0.0, 1.0, 0.0});

    fov_y := PI / 3.2;
    tan_half_fov := tan(fov_y * 0.5);
    aspect := viewport.x / viewport.y;

    dir := forward + right * (nx * aspect * tan_half_fov) + cam_up * (ny * tan_half_fov);
    normalize(*dir, fallback = forward);
    return camera_pos, dir, true;
}

terrain_raycast_surface :: (ctx: *Terrain_Voxel.Terrain_Voxel_Context, origin: Vector3, dir: Vector3, max_dist: float, step: float) -> (hit: bool, p: Vector3) {
    t0: float = 0.0;
    prev_p := origin;
    prev_d: float = 0.0;
    prev_ok := terrain_density_at_world(ctx, prev_p, *prev_d);
    if prev_ok && prev_d <= Terrain_Voxel.Iso_Level return true, prev_p;

    while t0 < max_dist {
        t0 += step;
        p := origin + dir * t0;
        d: float = 0.0;
        ok := terrain_density_at_world(ctx, p, *d);
        if !ok {
            prev_ok = false;
            continue;
        }

        if prev_ok && prev_d > Terrain_Voxel.Iso_Level && d <= Terrain_Voxel.Iso_Level {
            lo := prev_p;
            hi := p;
            dlo := prev_d;
            dhi := d;
            for 0..5 {
                mid := (lo + hi) * 0.5;
                dm: float = 0.0;
                if !terrain_density_at_world(ctx, mid, *dm) break;
                if dlo > Terrain_Voxel.Iso_Level && dm <= Terrain_Voxel.Iso_Level {
                    hi = mid;
                    dhi = dm;
                } else {
                    lo = mid;
                    dlo = dm;
                }
            }
            return true, (lo + hi) * 0.5;
        }

        prev_ok = true;
        prev_p = p;
        prev_d = d;
    }

    return false, origin;
}

ensure_depth_target :: (width: u32, height: u32) {
    if width == 0 || height == 0 return;
    if terrain_depth_view != 0 && terrain_depth_w == width && terrain_depth_h == height return;

    res, terrain_depth_texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });
    assert(res == .SUCCESS);
    assert(terrain_depth_texture != 0, "Terrain depth texture creation failed.");

    terrain_depth_view = gpu_texture_view(terrain_depth_texture);
    assert(terrain_depth_view != 0, "Terrain depth view creation failed.");

    terrain_depth_w = width;
    terrain_depth_h = height;
    gpu_commit_residency();
}

on_dll_init :: () {
    Terrain_Voxel.init(*terrain_voxel_ctx, stream_radius_xz = 1, stream_layers_y = 2, stream_layers_below_y = 3);

    compute_source := cast([]u8) get_transpiled(.METAL, terrain_mesh_build_chunk_compute);
    assert(compute_source.count > 0, "Transpilation failed for terrain mesh compute shader.");
    mesh_ok := Terrain_Mesh_Compute.init(*terrain_mesh_compute_ctx, compute_source);
    assert(mesh_ok, "Terrain_Mesh_Compute initialization failed.");

    ok := Terrain_Render.init(*terrain_render_ctx, max_vertices = 1200000);
    assert(ok, "Terrain_Render initialization failed.");
    Terrain_Render.set_material(*terrain_render_ctx, tex_scale = 0.22, tri_sharpness = 3.0);

    terrain_camera_pos = .{0.0, 2.7, 5.6};
    terrain_camera_yaw, terrain_camera_pitch = terrain_angles_from_forward(terrain_orbit_center - terrain_camera_pos);
} @on_dll_init

on_unload :: () {
    Terrain_Mesh_Compute.deinit(*terrain_mesh_compute_ctx);
    Terrain_Render.deinit(*terrain_render_ctx);
    Terrain_Voxel.deinit(*terrain_voxel_ctx);
} @on_unload

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    viewport := Vector2.{1280.0, 720.0};
    if dims_ok && win_w > 0 && win_h > 0 {
        viewport = .{cast(float) win_w, cast(float) win_h};
    }
    ensure_depth_target(cast(u32) viewport.x, cast(u32) viewport.y);

    t := cast(float) time;
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    has_dims := dims_ok && win_w > 0 && win_h > 0;

    left_mouse_down := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN;
    right_mouse_down := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN;
    keyboard_move := false;
    move := Vector3.{0.0, 0.0, 0.0};
    forward := terrain_forward_from_angles(terrain_camera_yaw, terrain_camera_pitch);
    up_axis := Vector3.{0.0, 1.0, 0.0};
    right := cross(forward, up_axis);
    normalize(*right, fallback = .{1.0, 0.0, 0.0});
    forward_xz := Vector3.{forward.x, 0.0, forward.z};
    normalize(*forward_xz, fallback = .{0.0, 0.0, -1.0});

    if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN {
        move += forward_xz;
        keyboard_move = true;
    }
    if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN {
        move -= forward_xz;
        keyboard_move = true;
    }
    if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN {
        move -= right;
        keyboard_move = true;
    }
    if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN {
        move += right;
        keyboard_move = true;
    }
    if Input.input_button_states[cast(Input.Key_Code) #char "Q"] & .DOWN {
        move -= up_axis;
        keyboard_move = true;
    }
    if Input.input_button_states[cast(Input.Key_Code) #char "E"] & .DOWN {
        move += up_axis;
        keyboard_move = true;
    }

    used_mouse_look := false;
    if right_mouse_down && mouse_ok && has_dims {
        mouse_pos := Vector2.{cast(float) mx, cast(float) my};
        if terrain_have_prev_mouse {
            delta := mouse_pos - terrain_prev_mouse_pos;
            if delta.x != 0.0 || delta.y != 0.0 {
                terrain_camera_yaw += delta.x * terrain_mouse_sensitivity;
                terrain_camera_pitch += delta.y * terrain_mouse_sensitivity;
                terrain_camera_pitch = clamp(terrain_camera_pitch, -1.5, 1.5);
                used_mouse_look = true;
            }
        }
        terrain_prev_mouse_pos = mouse_pos;
        terrain_have_prev_mouse = true;
    } else {
        terrain_have_prev_mouse = false;
    }

    {
        // example imgui overlay
        #import "ImGui";
        open: bool = true;
        window_flags: WindowFlags = .NoDecoration | .AlwaysAutoResize | .NoSavedSettings | .NoFocusOnAppearing | .NoNav;
        if Begin("debug overlay", *open, window_flags) {
            Text("Simple overlay");
            Separator();
        }
        End();
    }

    move_len_sq := dot(move, move);
    if move_len_sq > 0.000001 {
        move /= sqrt(move_len_sq);
        terrain_camera_pos += move * (terrain_fly_speed * dt);
    }

    if keyboard_move || used_mouse_look || right_mouse_down || left_mouse_down {
        terrain_last_manual_time = time;
    }

    seconds_since_manual := time - terrain_last_manual_time;
    auto_orbit_active := seconds_since_manual >= terrain_auto_orbit_delay_sec;
    if auto_orbit_active {
        orbit_target := Vector3.{sin(t * 0.25) * 5.6, 2.7, cos(t * 0.25) * 5.6};
        blend_t := clamp(dt * terrain_orbit_blend_speed, 0.0, 1.0);
        terrain_camera_pos += (orbit_target - terrain_camera_pos) * blend_t;
        terrain_camera_yaw, terrain_camera_pitch = terrain_angles_from_forward(terrain_orbit_center - terrain_camera_pos);
    }

    Terrain_Voxel.update_streaming(*terrain_voxel_ctx, terrain_camera_pos);

    if left_mouse_down && mouse_ok && has_dims {
        ray_origin, ray_dir, ray_ok := terrain_mouse_world_ray(cast(float) mx, cast(float) my, viewport, terrain_camera_pos, terrain_camera_yaw, terrain_camera_pitch);
        if ray_ok {
            hit, hit_p := terrain_raycast_surface(*terrain_voxel_ctx, ray_origin, ray_dir, terrain_ray_max_dist, terrain_ray_step);
            if hit {
                Terrain_Voxel.carve_sphere(*terrain_voxel_ctx, hit_p, terrain_dig_radius, terrain_dig_strength);
            }
        }
    }

    Terrain_Voxel.tick_demo_deform(*terrain_voxel_ctx, dt, t);
    rebuilt_chunks := Terrain_Mesh_Compute.rebuild_dirty_meshes(*terrain_mesh_compute_ctx, *terrain_voxel_ctx);

    aspect := viewport.x / max(viewport.y, 1.0);
    view_forward := terrain_forward_from_angles(terrain_camera_yaw, terrain_camera_pitch);
    view_target := terrain_camera_pos + view_forward;
    view := make_look_at_matrix(
        viewpoint = terrain_camera_pos,
        look_at = view_target,
        reference_up_vector = .{0.0, 1.0, 0.0},
        x_is_forward = false);
    proj := make_projection_matrix(PI / 3.2, aspect, 0.05, 120.0);
    Terrain_Render.set_view_projection(*terrain_render_ctx, proj * view);

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.065, 0.075, 0.085, 1.0],
            }
        ],
        depth_target = .{
            view = terrain_depth_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_value = .{
                depth = 1.0,
                stencil = 0,
            },
        }
    });

    draw_result := Terrain_Render.draw(*terrain_render_ctx, cmd_buff, *terrain_voxel_ctx, depth_mode = .TEST, force_upload = rebuilt_chunks > 0);
    assert(draw_result == .SUCCESS, tprint("Terrain draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

Terrain_Voxel :: #import "Terrain_Voxel";
Terrain_Render :: #import "Terrain_Render";
Terrain_Mesh_Compute :: #import "Terrain_Mesh_Compute";
#import "Math";
Input :: #import "Input";

#load "../../modules/Terrain_Mesh_Compute/shaders/terrain_mesh_compute_shader.jai";
