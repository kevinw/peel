Draw_Data :: struct {
    vertex_params_gpu: Gpu_Ptr;
    pixel_gpu: Gpu_Ptr;
    num_vertices: u32;
    num_instances: u32;
}

TETRIS_MAX_PARTICLES :: 2048;
TETRIS_LAYOUT_LEFT_PANEL_PX :: 360.0;
TETRIS_LAYOUT_TOP_MARGIN_PX :: 36.0;
TETRIS_LAYOUT_BOTTOM_MARGIN_PX :: 36.0;
TETRIS_LAYOUT_RIGHT_MARGIN_PX :: 28.0;

Tetris_Particle :: struct {
    pos: Vector2;
    vel: Vector2;
    color: Vector4;
    life: float;
    ttl: float;
    size: float;
    spin: float;
    angle: float;
}

graphics_pipeline: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
draw_data: Draw_Data;

render_instances_cpu: *[TETRIS_MAX_RENDER_INSTANCES] Tetris_Block_Instance;
render_instances_gpu: Gpu_Ptr;

particles: [TETRIS_MAX_PARTICLES] Tetris_Particle;
particle_count: s32;

layout_board_min_ndc: Vector2;
layout_board_max_ndc: Vector2;
layout_board_x0_px: float;
layout_board_y0_px: float;
layout_cell_px: float = 24.0;
layout_win_w_px: float = 1.0;
layout_win_h_px: float = 1.0;

left_repeat_timer: float;
right_repeat_timer: float;
soft_drop_timer: float;

line_flash: [TETRIS_BOARD_H] float;
board_idle_phase: float;

game: Tetris_Game;

piece_palette : [8] Vector4 = .[
    Vector4.{0.0, 0.0, 0.0, 1.0},
    Vector4.{0.38, 0.93, 0.95, 1.0},
    Vector4.{0.96, 0.88, 0.36, 1.0},
    Vector4.{0.72, 0.42, 0.93, 1.0},
    Vector4.{0.45, 0.89, 0.45, 1.0},
    Vector4.{0.93, 0.41, 0.44, 1.0},
    Vector4.{0.35, 0.55, 0.93, 1.0},
    Vector4.{0.96, 0.62, 0.32, 1.0},
];

spawn_line_clear_particles :: (row: s32) {
    if row < 0 || row >= TETRIS_VISIBLE_H return;
    for x: 0..TETRIS_BOARD_W-1 {
        base := tetris_cell_center(x, row);
        for 0..5 {
            if particle_count >= TETRIS_MAX_PARTICLES break;
            speed := random_get_within_range(0.24, 0.88);
            angle := random_get_within_range(0.35, 2.8);
            idx := particle_count;
            particles[idx] = .{
                pos = .{base.x + random_get_within_range(-0.02, 0.02), base.y + random_get_within_range(-0.02, 0.02)},
                vel = .{cos(angle) * speed * ifx (it & 1) == 0 then -1.0 else 1.0, sin(angle) * speed * random_get_within_range(0.65, 1.2)},
                color = .{0.95, 0.83, 0.42, 1.0},
                life = random_get_within_range(0.5, 0.95),
                ttl = random_get_within_range(0.5, 0.95),
                size = random_get_within_range(0.011, 0.019),
                spin = random_get_within_range(-8.0, 8.0),
                angle = random_get_within_range(0.0, 6.283185),
            };
            particle_count += 1;
        }
    }
}

consume_line_clear_event :: () {
    if game.clear_event.count <= 0 return;

    for i: 0..game.clear_event.count-1 {
        row := game.clear_event.rows[i];
        if row >= 0 && row < TETRIS_BOARD_H {
            line_flash[row] = 0.36;
            spawn_line_clear_particles(row);
        }
    }

    game.clear_event.count = 0;
}

process_game_input :: () {
    if game.game_over {
        for Input.events_this_frame {
            using it;
            if type != .KEYBOARD || !key_pressed continue;
            if key_code == #char "R" {
                tetris_restart(*game, cast(u64) (seconds_since_init() * 1000.0));
                particle_count = 0;
                for y: 0..TETRIS_BOARD_H-1 line_flash[y] = 0.0;
                left_repeat_timer = 0;
                right_repeat_timer = 0;
                soft_drop_timer = 0;
            }
        }
        return;
    }

    for Input.events_this_frame {
        using it;
        if type != .KEYBOARD || !key_pressed continue;

        if key_code == #char "A" tetris_try_move(*game, -1, 0);
        if key_code == #char "D" tetris_try_move(*game, 1, 0);
        if key_code == #char "S" _ = tetris_soft_drop(*game);
        if key_code == #char "W" tetris_try_rotate(*game, 1);
        if key_code == #char "X" tetris_try_rotate(*game, 1);
        if key_code == #char "Q" tetris_try_rotate(*game, -1);
        if key_code == #char "Z" tetris_try_rotate(*game, -1);
        if key_code == #char " " _ = tetris_hard_drop(*game);
        if key_code == #char "P" tetris_toggle_pause(*game);
        if key_code == #char "R" tetris_restart(*game, cast(u64) (seconds_since_init() * 1000.0));
    }

    left_down := (Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN) != 0;
    right_down := (Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN) != 0;
    soft_down := (Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN) != 0;

    if left_down && !right_down {
        left_repeat_timer -= dt;
        if left_repeat_timer <= 0.0 {
            _ = tetris_try_move(*game, -1, 0);
            left_repeat_timer = 0.055;
        }
    } else {
        left_repeat_timer = 0.13;
    }

    if right_down && !left_down {
        right_repeat_timer -= dt;
        if right_repeat_timer <= 0.0 {
            _ = tetris_try_move(*game, 1, 0);
            right_repeat_timer = 0.055;
        }
    } else {
        right_repeat_timer = 0.13;
    }

    if soft_down {
        soft_drop_timer -= dt;
        if soft_drop_timer <= 0.0 {
            _ = tetris_soft_drop(*game);
            soft_drop_timer = 0.034;
        }
    } else {
        soft_drop_timer = 0.05;
    }
}

update_particles :: () {
    gravity := cast(float) -2.2;
    i: s32 = 0;
    while i < particle_count {
        p := particles[i];
        p.life -= dt;
        if p.life <= 0.0 {
            particles[i] = particles[particle_count - 1];
            particle_count -= 1;
            continue;
        }

        p.vel.y += gravity * dt;
        p.vel.x *= 1.0 - min(1.0, dt * 1.7);
        p.pos += p.vel * dt;
        p.angle += p.spin * dt;
        particles[i] = p;
        i += 1;
    }
}

add_render_instance :: (center: Vector2, half: Vector2, color: Vector4, flags: u32 = 0, anim: float = 0.0, angle: float = 0.0) {
    if draw_data.num_instances >= TETRIS_MAX_RENDER_INSTANCES return;
    i := draw_data.num_instances;
    render_instances_cpu.*[i] = Tetris_Block_Instance.{
        center = center,
        half_size = half,
        color = color,
        flags = flags,
        anim = anim,
        angle = angle,
        pad0 = 0.0,
    };
    draw_data.num_instances += 1;
}

tetris_cell_center :: (x: s32, y: s32) -> Vector2 {
    cx_px := layout_board_x0_px + (cast(float) x + 0.5) * layout_cell_px;
    board_bottom_px := layout_board_y0_px + cast(float) TETRIS_VISIBLE_H * layout_cell_px;
    cy_px := board_bottom_px - (cast(float) y + 0.5) * layout_cell_px;
    return tetris_pixels_to_ndc(cx_px, cy_px);
}

tetris_pixels_to_ndc :: (x_px: float, y_px: float) -> Vector2 {
    nx := (x_px / max(1.0, layout_win_w_px)) * 2.0 - 1.0;
    ny := 1.0 - (y_px / max(1.0, layout_win_h_px)) * 2.0;
    return .{nx, ny};
}

tetris_update_layout :: () {
    _, _, win_w, win_h, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w <= 0 || win_h <= 0 return;

    w := cast(float) win_w;
    h := cast(float) win_h;
    layout_win_w_px = w;
    layout_win_h_px = h;

    avail_x0 := TETRIS_LAYOUT_LEFT_PANEL_PX;
    avail_x1 := w - TETRIS_LAYOUT_RIGHT_MARGIN_PX;
    if avail_x1 - avail_x0 < 120.0 {
        avail_x0 = 24.0;
        avail_x1 = w - 24.0;
    }
    avail_y0 := TETRIS_LAYOUT_TOP_MARGIN_PX;
    avail_y1 := h - TETRIS_LAYOUT_BOTTOM_MARGIN_PX;

    avail_w := max(32.0, avail_x1 - avail_x0);
    avail_h := max(32.0, avail_y1 - avail_y0);

    fit_cell_w := avail_w / cast(float) TETRIS_BOARD_W;
    fit_cell_h := avail_h / cast(float) TETRIS_VISIBLE_H;
    layout_cell_px = max(4.0, min(fit_cell_w, fit_cell_h));

    board_w_px := cast(float) TETRIS_BOARD_W * layout_cell_px;
    board_h_px := cast(float) TETRIS_VISIBLE_H * layout_cell_px;

    layout_board_x0_px = avail_x0 + (avail_w - board_w_px) * 0.5;
    layout_board_y0_px = avail_y0 + (avail_h - board_h_px) * 0.5;

    x1_px := layout_board_x0_px + board_w_px;
    y1_px := layout_board_y0_px + board_h_px;
    layout_board_min_ndc = tetris_pixels_to_ndc(layout_board_x0_px, y1_px);
    layout_board_max_ndc = tetris_pixels_to_ndc(x1_px, layout_board_y0_px);
}

build_render_instances :: () {
    draw_data.num_instances = 0;
    board_idle_phase += dt;

    cell_w_ndc := (layout_cell_px * 2.0) / max(1.0, layout_win_w_px);
    cell_h_ndc := (layout_cell_px * 2.0) / max(1.0, layout_win_h_px);
    block_half := Vector2.{cell_w_ndc * 0.47, cell_h_ndc * 0.47};

    // board background blocks
    for y: 0..TETRIS_VISIBLE_H-1 {
        for x: 0..TETRIS_BOARD_W-1 {
            base := 0.07 + 0.03 * sin(cast(float) x * 0.9 + cast(float) y * 0.5 + board_idle_phase * 0.9);
            c := Vector4.{base * 0.72, base * 0.78, base, 1.0};
            add_render_instance(tetris_cell_center(x, y), block_half, c, TETRIS_BLOCK_FLAG_BACKGROUND);
        }
    }

    // locked blocks
    for y: 0..TETRIS_VISIBLE_H-1 {
        flash := line_flash[y];
        for x: 0..TETRIS_BOARD_W-1 {
            id := game.board[y][x];
            if id == 0 continue;
            color := piece_palette[id];
            if flash > 0.0 {
                color += Vector4.{flash * 0.9, flash * 0.75, flash * 0.45, 0.0};
            }
            add_render_instance(tetris_cell_center(x, y), block_half, color, 0, min(1.0, flash * 2.2));
        }
    }

    // ghost piece
    if game.active_valid && !game.game_over {
        ghost_y := tetris_ghost_y(*game);
        ghost_blocks := tetris_piece_blocks(game.active_piece, game.active_rot);
        ghost_color := piece_palette[cast(s32) game.active_piece + 1];
        for 0..3 {
            gx := game.active_x + ghost_blocks[it].x;
            gy := ghost_y + ghost_blocks[it].y;
            if gx < 0 || gx >= TETRIS_BOARD_W continue;
            if gy < 0 || gy >= TETRIS_VISIBLE_H continue;
            add_render_instance(tetris_cell_center(gx, gy), block_half, ghost_color, TETRIS_BLOCK_FLAG_GHOST, 0.0);
        }
    }

    // active piece
    if game.active_valid && !game.game_over {
        blocks := tetris_piece_blocks(game.active_piece, game.active_rot);
        color := piece_palette[cast(s32) game.active_piece + 1];
        active_anim := 0.08 + 0.06 * sin(cast(float) time * 8.0);
        for 0..3 {
            ax := game.active_x + blocks[it].x;
            ay := game.active_y + blocks[it].y;
            if ay < 0 || ay >= TETRIS_VISIBLE_H continue;
            if ax < 0 || ax >= TETRIS_BOARD_W continue;
            add_render_instance(tetris_cell_center(ax, ay), block_half, color, 0, active_anim);
        }
    }

    // particles
    for i: 0..particle_count-1 {
        p := particles[i];
        if p.life <= 0.0 continue;
        t := p.life / max(0.0001, p.ttl);
        c := p.color * (0.55 + 0.65 * t);
        add_render_instance(
            p.pos,
            .{p.size, p.size * 0.75},
            c,
            TETRIS_BLOCK_FLAG_PARTICLE,
            1.0 - t,
            p.angle,
        );
    }
}

ui_draw_overlay :: () {
    using ImGui;

    io := GetIO();
    if io.DisplaySize.x <= 0 || io.DisplaySize.y <= 0 return;

    draw := GetForegroundDrawList();
    title_col := ColorConvertFloat4ToU32(.{0.96, 0.91, 0.62, 1.0});
    text_col := ColorConvertFloat4ToU32(.{0.90, 0.92, 0.98, 1.0});
    sub_col := ColorConvertFloat4ToU32(.{0.64, 0.69, 0.82, 1.0});
    frame_col := ColorConvertFloat4ToU32(.{0.33, 0.36, 0.48, 0.85});

    ImGui.ImDrawList.AddText(draw, .{26, 22}, title_col, "TETRIS");
    ImGui.ImDrawList.AddText(draw, .{26, 52}, text_col, tprint("Score  %", game.score));
    ImGui.ImDrawList.AddText(draw, .{26, 74}, text_col, tprint("Lines  %", game.total_lines));
    ImGui.ImDrawList.AddText(draw, .{26, 96}, text_col, tprint("Level  %", game.level));

    if game.paused {
        ImGui.ImDrawList.AddText(draw, .{26, 128}, sub_col, "Paused (P)");
    } else {
        ImGui.ImDrawList.AddText(draw, .{26, 128}, sub_col, "A/D move  W/X rotate  S drop  Space hard-drop");
        ImGui.ImDrawList.AddText(draw, .{26, 148}, sub_col, "Q/Z rotate-ccw  P pause  R restart");
    }

    if game.game_over {
        go_col := ColorConvertFloat4ToU32(.{1.0, 0.48, 0.45, 1.0});
        ImGui.ImDrawList.AddText(draw, .{26, 182}, go_col, "Game Over - Press R to restart");
    }

    ndc_min := layout_board_min_ndc;
    ndc_max := layout_board_max_ndc;

    sx0 := (ndc_min.x * 0.5 + 0.5) * io.DisplaySize.x;
    sy0 := ((-ndc_max.y) * 0.5 + 0.5) * io.DisplaySize.y;
    sx1 := (ndc_max.x * 0.5 + 0.5) * io.DisplaySize.x;
    sy1 := ((-ndc_min.y) * 0.5 + 0.5) * io.DisplaySize.y;

    ImGui.ImDrawList.AddRect(draw, .{sx0 - 8, sy0 - 8}, .{sx1 + 8, sy1 + 8}, frame_col, 12.0, .None, 2.0);
}

on_dll_init :: () {
    graphics_source := cast([]u8) get_transpiled(.METAL, tetris_vertex_main, tetris_fragment_main);
    assert(graphics_source.count > 0, "Transpilation failed for Tetris shaders.");

    blend_state: Gpu_Blend_Desc = .{
        src_color_factor = .SRC_ALPHA,
        dst_color_factor = .ONE_MINUS_SRC_ALPHA,
        src_alpha_factor = .ONE,
        dst_alpha_factor = .ONE_MINUS_SRC_ALPHA,
    };

    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM}
        ],
        blend_state = *blend_state,
    };

    graphics_ok := SHR.shader_hot_reload_create_and_register_graphics_pipeline(*shader_reload_ctx, *graphics_pipeline, graphics_source, raster_desc, .METAL, tetris_vertex_main, tetris_fragment_main);
    assert(graphics_ok, "Tetris graphics pipeline creation failed.");

    gpu_arena = gpu_make_arena(1024 * 1024 * 8, label = "tetris arena");

    quad, quad_gpu := gpu_arena_alloc(*gpu_arena, [6] Vector2);
    quad.* = .[
        .{-1.0, -1.0},
        .{+1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, -1.0},
        .{+1.0, +1.0},
        .{-1.0, +1.0},
    ];

    render_instances_cpu, render_instances_gpu = gpu_arena_alloc(*gpu_arena, [TETRIS_MAX_RENDER_INSTANCES] Tetris_Block_Instance);

    vertex_params_data, vertex_params_gpu := gpu_arena_alloc(*gpu_arena, [2] Gpu_Ptr);
    vertex_params_data.* = .[quad_gpu, render_instances_gpu];

    draw_data = .{
        vertex_params_gpu = vertex_params_gpu,
        pixel_gpu = 0,
        num_vertices = 6,
        num_instances = 0,
    };

    tetris_init_game(*game, cast(u64) (seconds_since_init() * 1000000.0 + 1.0));

    left_repeat_timer = 0.13;
    right_repeat_timer = 0.13;
    soft_drop_timer = 0.05;
    tetris_update_layout();

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    tetris_update_layout();
    process_game_input();

    if !game.paused && !game.game_over {
        tetris_tick(*game, dt);
    }

    for y: 0..TETRIS_BOARD_H-1 {
        if line_flash[y] > 0.0 {
            line_flash[y] -= dt * 2.3;
            if line_flash[y] < 0.0 line_flash[y] = 0.0;
        }
    }

    consume_line_clear_event();
    update_particles();
    build_render_instances();

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.022, 0.028, 0.045, 1.0],
            }
        ]
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, graphics_pipeline);

    gpu_draw_instanced_direct(cmd_buff, draw_data.vertex_params_gpu, draw_data.num_vertices, draw_data.num_instances);

    ui_draw_overlay();
    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#load "tetris_core.jai";
#load "shaders/tetris_shader.jai";
#import "Random";
#import "Math";
Input :: #import "Input";
ImGui :: #import "ImGui";
SHR :: #import,file "../shader_hot_reload.jai";
