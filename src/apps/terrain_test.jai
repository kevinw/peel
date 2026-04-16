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
terrain_camera: Editor_Camera = .{
    position = .{0.0, 2.7, 5.6},
    yaw = 0.0,
    pitch = 0.0,
    move_speed = 8.0,
    boost_multiplier = 2.0,
    mouse_sensitivity = 0.0032,
    move_planar = true,
};
terrain_last_manual_time: float64 = -1000000.0;
terrain_auto_orbit_delay_sec: float64 = 7.6;
terrain_orbit_blend_speed: float = 3.5;
terrain_dig_radius: float = 0.94;
terrain_dig_strength: float = 2.4;
terrain_ray_max_dist: float = 80.0;
terrain_ray_step: float = 0.21;

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

terrain_mouse_world_ray :: (mouse_x: float, mouse_y: float, viewport: Vector2, camera: *Editor_Camera) -> (origin: Vector3, dir: Vector3, ok: bool) {
    if viewport.x <= 1.0 || viewport.y <= 1.0 return camera.position, .{0.0, 0.0, -1.0}, false;

    nx := (mouse_x / viewport.x) * 2.0 - 1.0;
    ny := (mouse_y / viewport.y) * 2.0 - 1.0;

    forward, right, cam_up: Vector3;
    editor_camera_basis(camera, *forward, *right, *cam_up);

    tan_half_fov := tan(camera.fov_y * 0.5);
    aspect := viewport.x / viewport.y;

    dir := forward + right * (nx * aspect * tan_half_fov) + cam_up * (ny * tan_half_fov);
    normalize(*dir, fallback = forward);
    return camera.position, dir, true;
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

    terrain_camera.position = .{0.0, 2.7, 5.6};
    editor_camera_set_look_at(*terrain_camera, terrain_orbit_center);
} @on_dll_init

on_unload :: () {
    Terrain_Mesh_Compute.deinit(*terrain_mesh_compute_ctx);
    Terrain_Render.deinit(*terrain_render_ctx);
    Terrain_Voxel.deinit(*terrain_voxel_ctx);
} @on_quit

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    render_w, render_h := app_current_render_dimensions();
    viewport := Vector2.{cast(float) max(render_w, 1), cast(float) max(render_h, 1)};
    ensure_depth_target(cast(u32) viewport.x, cast(u32) viewport.y);

    t := cast(float) time;
    mx, my, mouse_ok := get_mouse_pointer_position(true);
    game_mx, game_my, game_mouse_ok := app_game_view_mouse_pos_pixels();
    has_dims := render_w > 0 && render_h > 0;
    app_mx := ifx app_should_render_to_game_view() then game_mx else mx;
    app_my := ifx app_should_render_to_game_view() then game_my else my;
    app_mouse_ok := ifx app_should_render_to_game_view() then game_mouse_ok else mouse_ok;

    left_mouse_down := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN;
    right_mouse_down := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT] & .DOWN;
    io := ImGui.GetIO();
    camera_update := editor_camera_update(*terrain_camera, dt, app_mx, app_my, app_mouse_ok,
        allow_move = !io.WantCaptureKeyboard,
        allow_look = right_mouse_down && has_dims && (ifx app_should_render_to_game_view() then game_mouse_ok else !io.WantCaptureMouse),
        allow_zoom = ifx app_should_render_to_game_view() then game_mouse_ok else !io.WantCaptureMouse);
    keyboard_move := camera_update.moved;
    used_mouse_look := camera_update.looked;

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

    if keyboard_move || used_mouse_look || right_mouse_down || left_mouse_down {
        terrain_last_manual_time = time;
    }

    seconds_since_manual := time - terrain_last_manual_time;
    auto_orbit_active := seconds_since_manual >= terrain_auto_orbit_delay_sec;
    if auto_orbit_active {
        orbit_target := Vector3.{sin(t * 0.25) * 5.6, 2.7, cos(t * 0.25) * 5.6};
        blend_t := clamp(dt * terrain_orbit_blend_speed, 0.0, 1.0);
        terrain_camera.position += (orbit_target - terrain_camera.position) * blend_t;
        editor_camera_set_look_at(*terrain_camera, terrain_orbit_center);
    }

    Terrain_Voxel.update_streaming(*terrain_voxel_ctx, terrain_camera.position);

    if left_mouse_down && app_mouse_ok && has_dims {
        ray_origin, ray_dir, ray_ok := terrain_mouse_world_ray(cast(float) app_mx, cast(float) app_my, viewport, *terrain_camera);
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
    view := editor_camera_make_view(*terrain_camera);
    proj := editor_camera_make_projection(*terrain_camera, aspect, 0.05, 120.0);
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

#load "../editor_camera.jai";
Terrain_Voxel :: #import "Terrain_Voxel";
Terrain_Render :: #import "Terrain_Render";
Terrain_Mesh_Compute :: #import "Terrain_Mesh_Compute";
ImGui :: #import "ImGui";
#import "Math";
Input :: #import "Input";

#load "../../modules/Terrain_Mesh_Compute/shaders/terrain_mesh_compute_shader.jai";
