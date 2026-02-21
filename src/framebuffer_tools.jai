
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

fb_try_parse_env_int :: (name: string) -> (s64, bool) {
    value_c := getenv(temp_c_string(name));
    if !value_c return 0, false;
    value_str := to_string(value_c, c_style_strlen(value_c));
    parsed, ok, _ := String.string_to_int(value_str);
    if !ok {
        log_error("Invalid %='%'. Expected integer.", name, value_str);
        return 0, false;
    }
    return cast(s64) parsed, true;
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

    Sample_Point :: struct { x, y: float; }
    sample_points: [5] Sample_Point;
    sample_points[0] = .{0.5, 0.5};
    sample_points[1] = .{0.25, 0.25};
    sample_points[2] = .{0.75, 0.25};
    sample_points[3] = .{0.25, 0.75};
    sample_points[4] = .{0.75, 0.75};

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

fb_dump_swapchain_thumbnail_ppm :: (view: Gpu_Texture_View, output_path: string, thumb_width: u32 = 96, thumb_height: u32 = 96) -> bool {
    width, height, ok := gpu_texture_view_size(view);
    if !ok || width <= 1 || height <= 1 return false;
    if thumb_width == 0 || thumb_height == 0 return false;

    bytes_per_row := cast(s64) width * 4;
    total_bytes := bytes_per_row * cast(s64) height;
    pixels := NewArray(total_bytes, u8);
    defer array_free(pixels);
    if !gpu_readback_texture_view_bgra8(view, pixels, bytes_per_row) return false;

    body_len := cast(s64) thumb_width * cast(s64) thumb_height * 3;
    body := NewArray(body_len, u8);
    defer array_free(body);

    dst := body.data;
    for y: 0..thumb_height-1 {
        src_y := clamp(cast(s64) floor((cast(float) y + 0.5) * cast(float) height / cast(float) thumb_height), 0, cast(s64) height - 1);
        for x: 0..thumb_width-1 {
            src_x := clamp(cast(s64) floor((cast(float) x + 0.5) * cast(float) width / cast(float) thumb_width), 0, cast(s64) width - 1);
            src := pixels.data + src_y * bytes_per_row + src_x * 4;
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst += 3;
        }
    }

    header := tprint("P6\n% %\n255\n", thumb_width, thumb_height);
    out := NewArray(header.count + body_len, u8);
    defer array_free(out);
    memcpy(out.data, header.data, header.count);
    memcpy(out.data + header.count, body.data, body_len);
    return File.write_entire_file(output_path, out.data, out.count);
}

#scope_file
#import "Math";
File :: #import "File";
String :: #import "String";
using,only(getenv) POSIX :: #import "POSIX";
#import "Basic";
#import "sgpu";
