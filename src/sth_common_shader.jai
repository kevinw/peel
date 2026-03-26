#import "Math";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";

STH_Context :: struct {
    px_cursor: Vector2;
    px_pos: Vector2;
    px_left_x: float;
    scale: float;
    dst_color: Vector4;
    text_color: Vector4;
    frame_fill_color: Vector4;
    frame_border_color: Vector4;
    line_width: float;
}

STH_Triangle :: struct {
    a: Vector2;
    b: Vector2;
    c: Vector2;
}

STH_ASCII_SPACE   :: cast(u32) 32;
STH_ASCII_MINUS   :: cast(u32) 45;
STH_ASCII_PERIOD  :: cast(u32) 46;
STH_ASCII_COMMA   :: cast(u32) 44;
STH_ASCII_COLON   :: cast(u32) 58;
STH_ASCII_0       :: cast(u32) 48;
STH_ASCII_A       :: cast(u32) 65;

STH_FLAG_Y_IS_UP     :: cast(u32) 0x1;
STH_FLAG_GRID_LINES  :: cast(u32) 0x2;

g_sth_mini_font :: u32.[
    0x00306c6c, 0x30003860, 0x18600000, 0x00000006,
    0x00786c6c, 0x7cc66c60, 0x30306630, 0x0000000c,
    0x00786cfe, 0xc0cc38c0, 0x60183c30, 0x00000018,
    0x0030006c, 0x78187600, 0x6018fffc, 0x00fc0030,
    0x003000fe, 0x0c30dc00, 0x60183c30, 0x00000060,
    0x0000006c, 0xf866cc00, 0x30306630, 0x300030c0,
    0x0030006c, 0x30c67600, 0x18600000, 0x30003080,
    0x00000000, 0x00000000, 0x00000000, 0x60000000,
    0x7c307878, 0x1cfc38fc, 0x78780000, 0x18006078,
    0xc670cccc, 0x3cc060cc, 0xcccc3030, 0x300030cc,
    0xce300c0c, 0x6cf8c00c, 0xcccc3030, 0x60fc180c,
    0xde303838, 0xcc0cf818, 0x787c0000, 0xc0000c18,
    0xf630600c, 0xfe0ccc30, 0xcc0c0000, 0x60001830,
    0xe630cccc, 0x0ccccc30, 0xcc183030, 0x30fc3000,
    0x7cfcfc78, 0x1e787830, 0x78703030, 0x18006030,
    0x00000000, 0x00000000, 0x00000060, 0x00000000,
    0x7c30fc3c, 0xf8fefe3c, 0xcc781ee6, 0xf0c6c638,
    0xc6786666, 0x6c626266, 0xcc300c66, 0x60eee66c,
    0xdecc66c0, 0x666868c0, 0xcc300c6c, 0x60fef6c6,
    0xdecc7cc0, 0x667878c0, 0xfc300c78, 0x60fedec6,
    0xdefc66c0, 0x666868ce, 0xcc30cc6c, 0x62d6cec6,
    0xc0cc6666, 0x6c626066, 0xcc30cc66, 0x66c6c66c,
    0x78ccfc3c, 0xf8fef03e, 0xcc7878e6, 0xfec6c638,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0xfc78fc78, 0xfcccccc6, 0xc6ccfe78, 0xc0781000,
    0x66cc66cc, 0xb4ccccc6, 0xc6ccc660, 0x60183800,
    0x66cc66e0, 0x30ccccc6, 0x6ccc8c60, 0x30186c00,
    0x7ccc7c70, 0x30ccccd6, 0x38781860, 0x1818c600,
    0x60dc6c1c, 0x30ccccfe, 0x38303260, 0x0c180000,
    0x607866cc, 0x30cc78ee, 0x6c306660, 0x06180000,
    0xf01ce678, 0x78fc30c6, 0xc678fe78, 0x02780000,
    0x00000000, 0x00000000, 0x00000000, 0x000000ff,
    0x3000e000, 0x1c003800, 0xe0300ce0, 0x70000000,
    0x30006000, 0x0c006c00, 0x60000060, 0x30000000,
    0x18786078, 0x0c786076, 0x6c700c66, 0x30ccf878,
    0x000c7ccc, 0x7cccf0cc, 0x76300c6c, 0x30fecccc,
    0x007c66c0, 0xccfc60cc, 0x66300c78, 0x30fecccc,
    0x00cc66cc, 0xccc0607c, 0x6630cc6c, 0x30d6cccc,
    0x0076dc78, 0x7678f00c, 0xe678cce6, 0x78c6cc78,
    0x00000000, 0x000000f8, 0x00007800, 0x00000000,
    0x00000000, 0x10000000, 0x0000001c, 0x18e076ff,
    0x00000000, 0x30000000, 0x00000030, 0x1830dcff,
    0xdc76dc7c, 0x7cccccc6, 0xc6ccfc30, 0x183000ff,
    0x66cc76c0, 0x30ccccd6, 0x6ccc98e0, 0x001c00ff,
    0x66cc6678, 0x30ccccfe, 0x38cc3030, 0x183000ff,
    0x7c7c600c, 0x34cc78fe, 0x6c7c6430, 0x183000ff,
    0x600cf0f8, 0x1876306c, 0xc60cfc1c, 0x18e000ff,
    0xf01e0000, 0x00000000, 0x00f80000, 0x000000ff,
];

sth_font_size :: () -> float {
    return 8.0;
}

sth_saturate :: (x: float) -> float {
    return clamp(x, 0.0, 1.0);
}

sth_blend :: (dst: Vector4, src: Vector4, alpha: float) -> Vector4 {
    a := sth_saturate(alpha);
    if a <= 0.0 return dst;
    return mix(dst, .{src.x, src.y, src.z, 1.0}, a);
}

sth_init :: (ctx: *STH_Context, px_pos: Vector2) {
    ctx.px_cursor = .{0.0, 0.0};
    ctx.px_pos = px_pos;
    ctx.px_left_x = 0.0;
    ctx.scale = 1.0;
    ctx.dst_color = .{0.0, 0.0, 0.0, 0.0};
    ctx.text_color = .{1.0, 1.0, 1.0, 1.0};
    ctx.frame_fill_color = .{0.10, 0.11, 0.14, 0.88};
    ctx.frame_border_color = .{0.78, 0.83, 0.95, 0.92};
    ctx.line_width = 2.0;
}

sth_set_cursor :: (ctx: *STH_Context, left_top: Vector2) {
    ctx.px_cursor = left_top;
    ctx.px_left_x = left_top.x;
}

sth_set_scale :: (ctx: *STH_Context, scale: float) {
    ctx.scale = max(scale, 1.0);
}

sth_font_lookup :: (ascii: u32, px_x: s32, px_y: s32) -> bool {
    if cast(u32) px_x >= 8 || cast(u32) px_y >= 8 return false;
    if ascii <= 32 || ascii > 127 return false;

    chr := ascii - 32;
    chr_x := chr % 16;
    chr_y := chr / 16;
    pixel_x := chr_x * 8 + cast(u32) px_x;
    pixel_y := chr_y * 8 + cast(u32) px_y;
    dword_id := pixel_x / 32 + pixel_y * 4;
    bit_id := pixel_x & 0x1f;
    dword_value := g_sth_mini_font[dword_id];
    return ((dword_value >> (31 - bit_id)) & 1) != 0;
}

sth_print_character :: (ctx: *STH_Context, ascii: u32) {
    px_local_x := cast(s32) floor((ctx.px_pos.x - ctx.px_cursor.x) / ctx.scale);
    px_local_y := cast(s32) floor((ctx.px_pos.y - ctx.px_cursor.y) / ctx.scale);

    if sth_font_lookup(ascii, px_local_x, px_local_y) {
        ctx.dst_color = sth_blend(ctx.dst_color, ctx.text_color, ctx.text_color.w);
    }

    ctx.px_cursor.x = ctx.px_cursor.x + sth_font_size() * ctx.scale;
}

sth_print_txt :: (ctx: *STH_Context, a: u32, b: u32, c: u32, d: u32, e: u32, f: u32) {
    if a != 0 sth_print_character(ctx, a);
    if b != 0 sth_print_character(ctx, b);
    if c != 0 sth_print_character(ctx, c);
    if d != 0 sth_print_character(ctx, d);
    if e != 0 sth_print_character(ctx, e);
    if f != 0 sth_print_character(ctx, f);
}

sth_print_space :: (ctx: *STH_Context, number_of_chars: float) {
    ctx.px_cursor.x = ctx.px_cursor.x + sth_font_size() * number_of_chars * ctx.scale;
}

sth_print_lf :: (ctx: *STH_Context) {
    ctx.px_cursor.x = ctx.px_left_x;
    ctx.px_cursor.y = ctx.px_cursor.y + sth_font_size() * ctx.scale;
}

sth_print_int :: (ctx: *STH_Context, value: s32) {
    v := value;
    if v < 0 {
        sth_print_character(ctx, STH_ASCII_MINUS);
        v = -v;
    }
    if v == 0 {
        sth_print_character(ctx, STH_ASCII_0);
        return;
    }

    tmp := cast(u32) v;
    while tmp != 0 {
        ctx.px_cursor.x = ctx.px_cursor.x + sth_font_size() * ctx.scale;
        tmp = tmp / 10;
    }

    backup := ctx.px_cursor.x;
    tmp = cast(u32) v;
    while tmp != 0 {
        digit := tmp % 10;
        tmp = tmp / 10;
        ctx.px_cursor.x = ctx.px_cursor.x - sth_font_size() * ctx.scale;
        sth_print_character(ctx, STH_ASCII_0 + digit);
        ctx.px_cursor.x = ctx.px_cursor.x - sth_font_size() * ctx.scale;
    }
    ctx.px_cursor.x = backup;
}

sth_print_float :: (ctx: *STH_Context, value: float) {
    sth_print_int(ctx, cast(s32) value);
    fractional := fract(abs(value));
    sth_print_character(ctx, STH_ASCII_PERIOD);
    for 0..2 {
        fractional = fractional * 10.0;
        digit := cast(u32) fractional;
        fractional = fract(fractional);
        sth_print_character(ctx, STH_ASCII_0 + digit);
    }
}

sth_compute_box_dist :: (p: Vector2, aabb: Vector4) -> float {
    aabb_min := Vector2.{aabb.x, aabb.y};
    aabb_max := Vector2.{aabb.z, aabb.w};
    center := (aabb_min + aabb_max) * 0.5;
    half_size := (aabb_max - aabb_min) * 0.5;
    px_local := p - center;
    dist2 := Vector2.{max(0.0, abs(px_local.x) - half_size.x), max(0.0, abs(px_local.y) - half_size.y)};
    return max(dist2.x, dist2.y);
}

sth_frame :: (ctx: *STH_Context, width_in_characters: u32) {
    aabb := Vector4.{ctx.px_cursor.x - cast(float) width_in_characters * sth_font_size() * ctx.scale, ctx.px_cursor.y, ctx.px_cursor.x, ctx.px_cursor.y};
    aabb = aabb + Vector4.{4.0, 4.0, -4.0, 4.0} * ctx.scale;
    dist := sth_compute_box_dist(ctx.px_pos, aabb) / ctx.scale;
    rim_mask := sth_saturate(3.0 - dist);
    outer_mask := sth_saturate(4.0 - dist);

    local_color := Vector4.{0.0, 0.0, 0.0, 0.0};
    if outer_mask > 0.0 local_color = ctx.frame_border_color;
    if rim_mask > 0.0 local_color = ctx.frame_fill_color;
    ctx.dst_color = sth_blend(ctx.dst_color, local_color, local_color.w * (1.0 - ctx.dst_color.w));
}

sth_draw_rectangle :: (ctx: *STH_Context, left_top: Vector2, bottom_right: Vector2, color: Vector4) {
    if ctx.px_pos.x >= left_top.x && ctx.px_pos.y >= left_top.y && ctx.px_pos.x < bottom_right.x && ctx.px_pos.y < bottom_right.y {
        ctx.dst_color = sth_blend(ctx.dst_color, color, color.w);
    }
}

sth_draw_rectangle_aa :: (ctx: *STH_Context, a: Vector2, b: Vector2, border_color: Vector4, inner_color: Vector4, thickness: float) {
    r := thickness * 0.5;
    center := (a + b) * 0.5;
    half_size := abs(b - a) * 0.5;
    outer_local := Vector2.{max(0.0, abs(ctx.px_pos.x - center.x) - half_size.x), max(0.0, abs(ctx.px_pos.y - center.y) - half_size.y)};
    inner_local := Vector2.{max(0.0, abs(ctx.px_pos.x - center.x) - half_size.x + r), max(0.0, abs(ctx.px_pos.y - center.y) - half_size.y + r)};
    mask_outer := sth_saturate(1.0 + r - length(outer_local));
    mask_inner := sth_saturate(length(inner_local) - 0.5);
    color := mix(inner_color, .{border_color.x, border_color.y, border_color.z, 1.0}, border_color.w * mask_inner);
    ctx.dst_color = sth_blend(ctx.dst_color, color, color.w * mask_outer);
}

sth_draw_disc :: (ctx: *STH_Context, center: Vector2, radius: float, color: Vector4) {
    len := length(ctx.px_pos - center);
    mask := sth_saturate(radius - len);
    ctx.dst_color = sth_blend(ctx.dst_color, color, color.w * mask);
}

sth_draw_circle :: (ctx: *STH_Context, center: Vector2, radius: float, color: Vector4) {
    r := ctx.line_width * 0.5;
    len := length(ctx.px_pos - center);
    mask := sth_saturate(radius - len + r) * (1.0 - sth_saturate(radius - len - r));
    ctx.dst_color = sth_blend(ctx.dst_color, color, color.w * mask);
}

sth_draw_line :: (ctx: *STH_Context, begin: Vector2, end: Vector2, color: Vector4) {
    thickness := ctx.line_width + 1.0;
    r := thickness * 0.5;
    delta := end - begin;
    len := length(delta);
    if len <= 0.01 return;
    tangent := delta / len;
    normal := Vector2.{tangent.y, -tangent.x};
    local := ctx.px_pos - begin;
    uv := Vector2.{dot(local, tangent), dot(local, normal)};
    mask := sth_saturate(r - abs(uv.y)) * sth_saturate(r - uv.x + len) * sth_saturate(r + uv.x);
    ctx.dst_color = sth_blend(ctx.dst_color, color, color.w * mask);
}

sth_draw_crosshair :: (ctx: *STH_Context, center: Vector2, radius: float, color: Vector4) {
    h := Vector2.{radius, 0.0};
    v := Vector2.{0.0, radius};
    sth_draw_line(ctx, center - h, center + h, color);
    sth_draw_line(ctx, center - v, center + v, color);
}

sth_get_halfspace_plane :: (a: Vector2, b: Vector2) -> Vector3 {
    ab := normalize(a - b);
    plane := Vector3.{-ab.y, ab.x, 0.0};
    plane_xy := Vector2.{plane.x, plane.y};
    plane.z = dot(plane_xy, -a);
    return plane;
}

sth_draw_triangle :: (ctx: *STH_Context, tri: STH_Triangle, color: Vector4) {
    ab_mask := sth_saturate(dot(sth_get_halfspace_plane(tri.a, tri.b), .{ctx.px_pos.x, ctx.px_pos.y, 1.0}) - 0.5);
    bc_mask := sth_saturate(dot(sth_get_halfspace_plane(tri.b, tri.c), .{ctx.px_pos.x, ctx.px_pos.y, 1.0}) - 0.5);
    ca_mask := sth_saturate(dot(sth_get_halfspace_plane(tri.c, tri.a), .{ctx.px_pos.x, ctx.px_pos.y, 1.0}) - 0.5);
    ctx.dst_color = sth_blend(ctx.dst_color, color, color.w * ab_mask * bc_mask * ca_mask);
}

sth_draw_arrow :: (ctx: *STH_Context, start: Vector2, end: Vector2, color: Vector4, arrow_head_length: float, arrow_head_width: float) {
    direction := normalize(end - start);
    line_end := end - direction * arrow_head_length;
    perpendicular := normalize(Vector2.{direction.y, -direction.x});
    sth_draw_line(ctx, start, line_end, color);
    tri := STH_Triangle.{
        a = line_end - perpendicular * arrow_head_width,
        b = line_end + direction * arrow_head_length,
        c = line_end + perpendicular * arrow_head_width,
    };
    sth_draw_triangle(ctx, tri, color);
}

sth_coordinate_system :: (ctx: *STH_Context, px_origin: Vector2, domain: Vector4, px_scale: float, grid_size: float, grid_color: Vector4, flags: u32) {
    snapped_origin := floor(px_origin);
    y_is_up := (flags & STH_FLAG_Y_IS_UP) != 0;
    grid_lines := (flags & STH_FLAG_GRID_LINES) != 0;

    px_dot_size := ctx.line_width;
    px_d := fract(floor((ctx.px_pos - snapped_origin + .{px_dot_size * 0.5, px_dot_size * 0.5}) / grid_size)) * grid_size;
    local_grid_color := grid_color;
    if grid_lines {
        if px_d.x > floor(px_dot_size) && px_d.y > floor(px_dot_size) {
            local_grid_color = .{0.0, 0.0, 0.0, 0.0};
        }
    } else {
        if px_d.x > floor(px_dot_size) || px_d.y > floor(px_dot_size) {
            local_grid_color = .{0.0, 0.0, 0.0, 0.0};
        }
    }

    px_domain := domain * px_scale + .{snapped_origin.x, snapped_origin.y, snapped_origin.x, snapped_origin.y};
    sth_draw_rectangle(ctx, .{px_domain.x, px_domain.y}, .{px_domain.z, px_domain.w}, local_grid_color);

    backup_width := ctx.line_width;
    if px_d.x < backup_width ctx.line_width = ctx.line_width * 2.0;
    sth_draw_arrow(ctx, .{px_domain.x, snapped_origin.y}, .{px_domain.z, snapped_origin.y}, ctx.text_color, 16.0, 8.0);

    ctx.line_width = backup_width;
    if px_d.y < backup_width ctx.line_width = ctx.line_width * 2.0;
    if y_is_up {
        sth_draw_arrow(ctx, .{snapped_origin.x, px_domain.w}, .{snapped_origin.x, px_domain.y}, ctx.text_color, 16.0, 8.0);
    } else {
        sth_draw_arrow(ctx, .{snapped_origin.x, px_domain.y}, .{snapped_origin.x, px_domain.w}, ctx.text_color, 16.0, 8.0);
    }
    ctx.line_width = backup_width;
}
