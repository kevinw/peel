#import "Jai-Shader-Transpiler";
#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";

#load "../../sth_common_shader.jai";

Shader_To_Human_Params :: struct {
    resolution: Vector2;
    mouse_pos: Vector2;
    time: float;
    scale: float;
    line_width: float;
    flags: u32;
    view_proj: Matrix4;
}

SHOW_WATCH      :: cast(u32) 0x1;
SHOW_TEXT       :: cast(u32) 0x2;
SHOW_SHAPES     :: cast(u32) 0x4;
SHOW_COORDS     :: cast(u32) 0x8;
SHOW_PROJECTED  :: cast(u32) 0x10;

draw_projected_line :: (ctx: *STH_Context, using params: *Shader_To_Human_Params, a: Vector3, b: Vector3, color: Vector4) {
    a_clip := view_proj * vec4(a, 1.0);
    b_clip := view_proj * vec4(b, 1.0);
    if abs(a_clip.w) < 0.00001 || abs(b_clip.w) < 0.00001 return;
    a_ndc := a_clip.xyz / a_clip.w;
    b_ndc := b_clip.xyz / b_clip.w;
    if a_ndc.z < 0.0 || a_ndc.z > 1.2 return;
    if b_ndc.z < 0.0 || b_ndc.z > 1.2 return;
    a_px := Vector2.{
        (a_ndc.x * 0.5 + 0.5) * resolution.x,
        (1.0 - (a_ndc.y * 0.5 + 0.5)) * resolution.y,
    };
    b_px := Vector2.{
        (b_ndc.x * 0.5 + 0.5) * resolution.x,
        (1.0 - (b_ndc.y * 0.5 + 0.5)) * resolution.y,
    };
    sth_draw_line(ctx, a_px, b_px, color);
}

draw_projected_axes :: (ctx: *STH_Context, params: *Shader_To_Human_Params) {
    draw_projected_line(ctx, params, .{0.0, 0.0, 0.0}, .{1.0, 0.0, 0.0}, .{0.96, 0.28, 0.26, 0.95});
    draw_projected_line(ctx, params, .{0.0, 0.0, 0.0}, .{0.0, 1.0, 0.0}, .{0.26, 0.92, 0.42, 0.95});
    draw_projected_line(ctx, params, .{0.0, 0.0, 0.0}, .{0.0, 0.0, 1.0}, .{0.34, 0.58, 0.98, 0.95});
}

rotate_y_vec3 :: (v: Vector3, c: float, s: float) -> Vector3 {
    return .{v.x * c - v.z * s, v.y, v.x * s + v.z * c};
}

draw_projected_box :: (ctx: *STH_Context, params: *Shader_To_Human_Params, center: Vector3, half_extents: Vector3, yaw: float, color: Vector4) {
    c := cos(yaw);
    s := sin(yaw);
    v0 := center + rotate_y_vec3(.{-half_extents.x, -half_extents.y, -half_extents.z}, c, s);
    v1 := center + rotate_y_vec3(.{ half_extents.x, -half_extents.y, -half_extents.z}, c, s);
    v2 := center + rotate_y_vec3(.{ half_extents.x,  half_extents.y, -half_extents.z}, c, s);
    v3 := center + rotate_y_vec3(.{-half_extents.x,  half_extents.y, -half_extents.z}, c, s);
    v4 := center + rotate_y_vec3(.{-half_extents.x, -half_extents.y,  half_extents.z}, c, s);
    v5 := center + rotate_y_vec3(.{ half_extents.x, -half_extents.y,  half_extents.z}, c, s);
    v6 := center + rotate_y_vec3(.{ half_extents.x,  half_extents.y,  half_extents.z}, c, s);
    v7 := center + rotate_y_vec3(.{-half_extents.x,  half_extents.y,  half_extents.z}, c, s);

    draw_projected_line(ctx, params, v0, v1, color);
    draw_projected_line(ctx, params, v1, v2, color);
    draw_projected_line(ctx, params, v2, v3, color);
    draw_projected_line(ctx, params, v3, v0, color);
    draw_projected_line(ctx, params, v4, v5, color);
    draw_projected_line(ctx, params, v5, v6, color);
    draw_projected_line(ctx, params, v6, v7, color);
    draw_projected_line(ctx, params, v7, v4, color);
    draw_projected_line(ctx, params, v0, v4, color);
    draw_projected_line(ctx, params, v1, v5, color);
    draw_projected_line(ctx, params, v2, v6, color);
    draw_projected_line(ctx, params, v3, v7, color);
}

shader_to_human_fragment_main :: (using in: struct { uv: Vector2; }, params: *Shader_To_Human_Params) -> struct { out_color: Vector4; } {
    px := Vector2.{uv.x * params.resolution.x, (1.0 - uv.y) * params.resolution.y};

    bg_a := Vector3.{0.06, 0.07, 0.10};
    bg_b := Vector3.{0.17, 0.20, 0.27};
    bg_t := clamp(0.15 + 0.85 * (1.0 - uv.y), 0.0, 1.0);
    color := mix(bg_a, bg_b, bg_t);
    vignette_uv := uv * (Vector2.{1.0, 1.0} - .{uv.y, uv.x});
    color = color * (0.65 + 2.8 * pow(vignette_uv.x * vignette_uv.y, 0.25));

    ctx: STH_Context;
    sth_init(*ctx, px);
    sth_set_scale(*ctx, params.scale);
    ctx.line_width = params.line_width;

    if (params.flags & SHOW_WATCH) != 0 {
        panel_min := Vector2.{524.0, 24.0};
        panel_max := Vector2.{716.0, 118.0};
        sth_draw_rectangle_aa(*ctx, panel_min, panel_max, .{0.92, 0.95, 1.0, 0.86}, .{0.10, 0.12, 0.16, 0.72}, 4.0);
        if (params.flags & SHOW_TEXT) != 0 {
            ctx.text_color = .{0.96, 0.98, 1.0, 0.95};
            sth_set_cursor(*ctx, panel_min + .{12.0, 12.0});
            sth_print_txt(*ctx, 85, 86, 58, 0, 0, 0); // "UV:"
            sth_print_space(*ctx, 1.0);
            sth_print_float(*ctx, uv.x);
            sth_print_space(*ctx, 1.0);
            sth_print_float(*ctx, uv.y);
            sth_print_lf(*ctx);
            sth_print_txt(*ctx, 84, 58, 0, 0, 0, 0); // "T:"
            sth_print_space(*ctx, 1.0);
            sth_print_float(*ctx, params.time);
        }

        bar_w := 124.0;
        bar_h := 12.0;
        uv_bar_min := Vector2.{76.0, 46.0};
        uv_fill_x := uv_bar_min.x + clamp(uv.x, 0.0, 1.0) * bar_w;
        uv_fill_y := uv_bar_min.y + clamp(uv.y, 0.0, 1.0) * bar_w;
        sth_draw_rectangle_aa(*ctx, uv_bar_min, uv_bar_min + .{bar_w, bar_h}, .{0.6, 0.7, 0.92, 0.75}, .{0.14, 0.16, 0.22, 0.55}, 2.0);
        sth_draw_rectangle(*ctx, uv_bar_min + .{2.0, 2.0}, .{uv_fill_x - 2.0, uv_bar_min.y + bar_h - 2.0}, .{0.95, 0.48, 0.42, 0.85});
        sth_draw_rectangle_aa(*ctx, uv_bar_min + .{0.0, 24.0}, uv_bar_min + .{bar_w, bar_h + 24.0}, .{0.6, 0.7, 0.92, 0.75}, .{0.14, 0.16, 0.22, 0.55}, 2.0);
        sth_draw_rectangle(*ctx, uv_bar_min + .{2.0, 26.0}, .{uv_fill_y - 2.0, uv_bar_min.y + bar_h + 22.0}, .{0.35, 0.92, 0.55, 0.85});

        pulse := 0.5 + 0.5 * sin(params.time * 2.4);
        sth_draw_circle(*ctx, .{48.0, 72.0}, 13.0, .{1.0, 1.0, 1.0, 0.45});
        sth_draw_disc(*ctx, .{48.0, 72.0}, 4.0 + pulse * 6.0, .{0.96, 0.78, 0.24, 0.55});
    }

    if (params.flags & SHOW_COORDS) != 0 {
        origin := Vector2.{120.0, 340.0};
        grid_min := Vector2.{24.0, 244.0};
        grid_max := Vector2.{248.0, 436.0};
        sth_draw_rectangle_aa(*ctx, grid_min, grid_max, .{0.82, 0.88, 0.98, 0.34}, .{0.05, 0.07, 0.10, 0.15}, 2.0);
        for 0..7 {
            x := grid_min.x + cast(float) it * 32.0;
            sth_draw_line(*ctx, .{x, grid_min.y}, .{x, grid_max.y}, .{0.85, 0.90, 1.0, 0.08});
        }
        for 0..6 {
            y := grid_min.y + cast(float) it * 32.0;
            sth_draw_line(*ctx, .{grid_min.x, y}, .{grid_max.x, y}, .{0.85, 0.90, 1.0, 0.08});
        }
        sth_draw_line(*ctx, .{grid_min.x, origin.y}, .{grid_max.x, origin.y}, .{0.96, 0.36, 0.30, 0.82});
        sth_draw_line(*ctx, .{origin.x, grid_min.y}, .{origin.x, grid_max.y}, .{0.32, 0.92, 0.48, 0.82});
        sth_draw_crosshair(*ctx, origin, 8.0, .{1.0, 1.0, 1.0, 0.42});
    }

    if (params.flags & SHOW_SHAPES) != 0 {
        sth_draw_rectangle_aa(*ctx, .{42.0, 74.0}, .{182.0, 148.0}, .{0.92, 0.95, 1.0, 0.9}, .{0.14, 0.19, 0.28, 0.52}, 4.0);
        sth_draw_circle(*ctx, .{268.0, 108.0}, 38.0, .{0.98, 0.72, 0.34, 0.96});
        sth_draw_disc(*ctx, .{268.0, 108.0}, 10.0, .{0.98, 0.72, 0.34, 0.45});
        sth_draw_line(*ctx, .{212.0, 196.0}, .{352.0, 246.0}, .{0.28, 0.92, 0.92, 0.92});
        sth_draw_crosshair(*ctx, params.mouse_pos, 11.0, .{1.0, 1.0, 1.0, 0.72});
    }

    if (params.flags & SHOW_PROJECTED) != 0 {
        draw_projected_axes(*ctx, params);
        draw_projected_box(*ctx, params, .{0.0, 0.55, 0.0}, .{0.55, 0.55, 0.55}, params.time * 0.6, .{0.92, 0.88, 0.55, 0.95});
    }

    final_rgb := mix(color, .{ctx.dst_color.x, ctx.dst_color.y, ctx.dst_color.z}, ctx.dst_color.w);
    return .{out_color = .{final_rgb.x, final_rgb.y, final_rgb.z, 1.0}};
} @fragment_shader
