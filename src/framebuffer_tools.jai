FB_Framebuffer_Stats :: struct {
    width: u32;
    height: u32;
    avg_r: float;
    avg_g: float;
    avg_b: float;
    avg_luma: float;
    min_luma: float;
    max_luma: float;
    stddev_luma: float;
}

fb_parse_env_int :: (name: string, default: s64 = 0) -> s64 {
    value_c := getenv(temp_c_string(name));
    if !value_c return default;
    value_str := to_string(value_c, c_style_strlen(value_c));
    parsed, ok, _ := String.string_to_int(value_str);
    if !ok {
        log_error("Invalid %='%'. Expected integer.", name, value_str);
        return default;
    }
    return cast(s64) parsed;
}

fb_collect_swapchain_framebuffer_stats :: (view: Gpu_Texture_View) -> (FB_Framebuffer_Stats, bool) {
    stats: FB_Framebuffer_Stats;
    width, height, size_ok := gpu_texture_view_size(view);
    if !size_ok || width <= 1 || height <= 1 return stats, false;

    bytes_per_row := cast(s64) width * 4;
    total_bytes := bytes_per_row * cast(s64) height;
    pixels := NewArray(total_bytes, u8);
    defer array_free(pixels);

    if !gpu_readback_texture_view_bgra8(view, pixels, bytes_per_row) return stats, false;

    count := cast(s64) width * cast(s64) height;
    if count <= 0 return stats, false;

    sum_r: float = 0.0;
    sum_g: float = 0.0;
    sum_b: float = 0.0;
    sum_luma: float = 0.0;
    sum_luma_sq: float = 0.0;
    min_luma: float = 9999.0;
    max_luma: float = -1.0;

    for y: 0..height-1 {
        for x: 0..width-1 {
            offset := cast(s64) y * bytes_per_row + cast(s64) x * 4;
            p := pixels.data + offset;
            b := cast(float) p[0] / 255.0;
            g := cast(float) p[1] / 255.0;
            r := cast(float) p[2] / 255.0;
            luma := 0.2126 * r + 0.7152 * g + 0.0722 * b;
            sum_r += r;
            sum_g += g;
            sum_b += b;
            sum_luma += luma;
            sum_luma_sq += luma * luma;
            min_luma = min(min_luma, luma);
            max_luma = max(max_luma, luma);
        }
    }

    inv_count := 1.0 / cast(float) count;
    avg_luma := sum_luma * inv_count;
    variance := max(0.0, sum_luma_sq * inv_count - avg_luma * avg_luma);
    stats = .{
        width = width,
        height = height,
        avg_r = sum_r * inv_count,
        avg_g = sum_g * inv_count,
        avg_b = sum_b * inv_count,
        avg_luma = avg_luma,
        min_luma = min_luma,
        max_luma = max_luma,
        stddev_luma = sqrt(variance),
    };
    return stats, true;
}

fb_validate_swapchain_readback_non_black :: (view: Gpu_Texture_View, backend_label: string = "framebuffer") -> bool {
    width, height, ok := gpu_texture_view_size(view);
    if !ok || width <= 1 || height <= 1 return false;

    bytes_per_row := cast(s64) width * 4;
    total_bytes := bytes_per_row * cast(s64) height;
    pixels := NewArray(total_bytes, u8);
    defer array_free(pixels);

    if !gpu_readback_texture_view_bgra8(view, pixels, bytes_per_row) {
        log_error("Readback failed (%): unable to read swapchain texture.", backend_label);
        return false;
    }

    sample_points :: Vector2.[
        {0.5, 0.5},
        {0.25, 0.25},
        {0.75, 0.25},
        {0.25, 0.75},
        {0.75, 0.75},
    ];

    non_black := 0;
    min_luma: float = 999.0;
    max_luma: float = -1.0;
    sum_luma: float = 0.0;
    for sample_points {
        px := clamp(cast(s64) floor(it.x * cast(float) width), 0, cast(s64) width - 1);
        py := clamp(cast(s64) floor(it.y * cast(float) height), 0, cast(s64) height - 1);
        offset := py * bytes_per_row + px * 4;
        p := pixels.data + offset;
        b := cast(float) p[0] / 255.0;
        g := cast(float) p[1] / 255.0;
        r := cast(float) p[2] / 255.0;
        luma := 0.2126 * r + 0.7152 * g + 0.0722 * b;
        if luma > 0.02 non_black += 1;
        min_luma = min(min_luma, luma);
        max_luma = max(max_luma, luma);
        sum_luma += luma;
    }
    avg_luma := sum_luma / cast(float) sample_points.count;
    log("READBACK_SUMMARY backend=% samples=% non_black=% avg_luma=% min_luma=% max_luma=%",
        backend_label, sample_points.count, non_black, avg_luma, min_luma, max_luma);

    ok = (non_black >= 1) && (max_luma > 0.05);
    if !ok log_error("READBACK_FAIL backend=%", backend_label);
    return ok;
}

fb_dump_swapchain_thumbnail_jpeg :: (
    view: Gpu_Texture_View,
    output_path: string,
    thumb_width: u32 = DEFAULT_SNAPSHOT_WIDTH,
    thumb_height: u32 = DEFAULT_SNAPSHOT_HEIGHT,
    frame_num: s64
) -> bool {
    width, height, ok := gpu_texture_view_size(view);
    assert(ok);
    if !ok return false;
    if width <= 1 || height <= 1 {
        log_error("fb_dump_swapchain_thumbnail_jpeg: invalid texture size <= 1 (% x %)", width, height);
        return false;
    }
    if thumb_width == 0 || thumb_height == 0 {
        log_error("fb_dump_swapchain_thumbnail_jpeg: invalid thumb size specified");
        return false;
    }

    bytes_per_row := cast(s64) width * 4;
    total_bytes := bytes_per_row * cast(s64) height;
    pixels := NewArray(total_bytes, u8);
    defer array_free(pixels);
    if !gpu_readback_texture_view_bgra8(view, pixels, bytes_per_row) {
        log_error("fb_dump_swapchain_thumbnail_jpeg: failed to readback texture");
        return false;
    }

    fit_scale_x := cast(float) thumb_width / cast(float) width;
    fit_scale_y := cast(float) thumb_height / cast(float) height;
    fit_scale := min(fit_scale_x, fit_scale_y);
    fit_w := max(1, cast(u32) floor(cast(float) width * fit_scale));
    fit_h := max(1, cast(u32) floor(cast(float) height * fit_scale));
    if fit_w > thumb_width fit_w = thumb_width;
    if fit_h > thumb_height fit_h = thumb_height;
    offset_x := cast(s64) (thumb_width - fit_w) / 2;
    offset_y := cast(s64) (thumb_height - fit_h) / 2;

    body_len := cast(s64) thumb_width * cast(s64) thumb_height * 3;
    body := NewArray(body_len, u8);
    defer array_free(body);

    for i: 0..body_len-1 {
        body[i] = ifx (i % 3) == 0 then cast(u8) 14 else ifx (i % 3) == 1 then cast(u8) 16 else cast(u8) 22;
    }

    for y: 0..fit_h-1 {
        src_y := clamp(cast(s64) floor((cast(float) y + 0.5) * cast(float) height / cast(float) fit_h), 0, cast(s64) height - 1);
        dst_y := offset_y + y;
        for x: 0..fit_w-1 {
            src_x := clamp(cast(s64) floor((cast(float) x + 0.5) * cast(float) width / cast(float) fit_w), 0, cast(s64) width - 1);
            dst_x := offset_x + x;
            src := pixels.data + src_y * bytes_per_row + src_x * 4;
            dst_i := (dst_y * cast(s64) thumb_width + dst_x) * 3;
            body[dst_i + 0] = src[2];
            body[dst_i + 1] = src[1];
            body[dst_i + 2] = src[0];
        }
    }

    write_ok := stbi_write_jpg(temp_c_string(output_path),
                               cast(s32) thumb_width,
                               cast(s32) thumb_height,
                               3,
                               body.data,
                               90);

    success := write_ok != 0;
    if !success {
        log_error("fb_dump_swapchain_thumbnail_jpeg: failed to write JPEG file to '%'", output_path);
    } else {
        abs_path := File.get_absolute_path(output_path);
        log("PEEL_SNAPSHOT wrote thumbnail (%x%) (frame=%) to %", thumb_width, thumb_height, frame_num, ifx abs_path else output_path);
    }
    return success;
}

#scope_file
#import "Math";
File :: #import "File";
String :: #import "String";
#import "stb_image_write";
using,only(getenv) POSIX :: #import "POSIX";
#import "Basic";
using,except(Viewport) _ :: #import "sgpu";
#import "Env_Vars";
