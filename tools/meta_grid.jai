// Build all apps, capture one snapshot per app, and compose a single grid image.

#load "../src/app_list.jai";

DELETE_INTERMEDIATE_FILES :: true;

Meta_Grid_Opts :: struct {
    skip_build: bool;      @"?Skip 'jai build.jai -'"
    skip_capture: bool;    @"?Skip launching apps and reuse existing captures in out_dir"
    columns: s64 = 3;      @"?Grid column count"
    cell_w: s64 = 640;     @"?Cell width in pixels"
    cell_h: s64 = 360;     @"?Cell height in pixels"
    padding: s64 = 16;     @"?Padding around and between cells"
    out_dir: string = APP_CAPTURE_DIR;                     @"?Capture output directory"
    out_grid: string = "screenshots/screenshot_grid.jpg"; @"?Composited grid image path"
}

run_command_checked :: (label: string, args: []string, working_directory := "", fail_on_error := true) -> bool {
    result, stdout, stderr, timeout := Process.run_command(..args, working_directory = working_directory, capture_and_return_output = false, timeout_ms = 1000 * 60 * 20);
    if timeout {
        log_error("% timed out after 20 minutes.\nCommand: %", label, String.join(..args, separator = " "));
        if fail_on_error exit(1);
        return false;
    }
    if result.type != .EXITED || result.exit_code != 0 {
        log_error("% failed (exit=% type=%).\nCommand: %", label, result.exit_code, result.type, String.join(..args, separator = " "));
        if stdout log("stdout:\n%", stdout);
        if stderr log_error("stderr:\n%", stderr);
        if fail_on_error exit(1);
        return false;
    }
    return true;
}

app_output_name :: (app_file: string) -> string {
    return String.path_strip_extension(String.path_filename(app_file));
}

app_executable_name :: (app_file: string) -> string {
    name := app_output_name(app_file);
    #if OS == .WINDOWS {
        return sprint("%.exe", name);
    } else {
        return name;
    }
}

delete_old_snapshots_for_app :: (app_name: string) {
    prefix := sprint("%_snapshot_frame_", app_name);
    suffix := ".ppm";
    for File_Utilities.file_list("dist", recursive = false, follow_directory_symlinks = false,, allocator = temp) {
        filename := String.path_filename(it);
        if !String.starts_with(filename, prefix) continue;
        if !String.ends_with(filename, suffix) continue;
        _ = File.file_delete(it);
    }
}

find_latest_snapshot_for_app :: (app_name: string) -> string {
    prefix := sprint("%_snapshot_frame_", app_name);
    suffix := ".jpeg";

    best_frame: s64 = -1;
    best_path := "";

    for File_Utilities.file_list("dist", recursive = false, follow_directory_symlinks = false,, allocator = temp) {
        filename := String.path_filename(it);
        if !String.starts_with(filename, prefix) continue;
        if !String.ends_with(filename, suffix) continue;
        frame_s := filename;
        frame_s = advance(frame_s, prefix.count);
        frame_s.count -= suffix.count;
        frame := cast(s64) String.string_to_int(frame_s);
        if frame > best_frame {
            best_frame = frame;
            best_path = copy_string(it);
        }
    }

    return best_path;
}

run_capture_for_app :: (exe_name: string, snapshot_w: s64, snapshot_h: s64) -> bool {
    sw := sprint("%", max(1, snapshot_w));
    sh := sprint("%", max(1, snapshot_h));
    #if OS == .WINDOWS {
        cmd := sprint("set PEEL_SNAPSHOT=1&& set PEEL_STATS_EVERY=1&& set PEEL_STATS_MAX=1&& set PEEL_SNAPSHOT_W=%&& set PEEL_SNAPSHOT_H=%&& \"%\" --max-frames 300", sw, sh, exe_name);
        return run_command_checked(sprint("Capture %", exe_name), .["cmd", "/C", cmd], working_directory = "dist", fail_on_error = false);
    } else {
        return run_command_checked(sprint("Capture %", exe_name), .["env", "PEEL_SNAPSHOT=1", "PEEL_STATS_EVERY=1", "PEEL_STATS_MAX=1", sprint("PEEL_SNAPSHOT_W=%", sw), sprint("PEEL_SNAPSHOT_H=%", sh), sprint("./%", exe_name), "--max-frames", "300"], working_directory = "dist", fail_on_error = false);
    }
}

write_placeholder_capture :: (dest_path: string, w: s64, h: s64) {
    ww := max(1, w);
    hh := max(1, h);
    pixels := NewArray(ww * hh * 4, u8);

    for y: 0..hh-1 {
        for x: 0..ww-1 {
            i := (y * ww + x) * 4;
            checker := ((x / 32) + (y / 32)) & 1;
            if checker == 0 {
                pixels[i + 0] = 26;
                pixels[i + 1] = 26;
                pixels[i + 2] = 26;
            } else {
                pixels[i + 0] = 110;
                pixels[i + 1] = 10;
                pixels[i + 2] = 10;
            }
            pixels[i + 3] = 255;
        }
    }

    _ = File.make_directory_if_it_does_not_exist(String.path_strip_filename(dest_path), recursive = true);
    ok := stbi_write_jpg(temp_c_string(dest_path), cast(s32) ww, cast(s32) hh, 4, pixels.data, cast(s32) (ww * 4));
    if ok == 0 {
        log_error("Failed to write placeholder capture '%'.", dest_path);
        exit(1);
    }
}

blit_scaled_rgba8_high_quality_fit :: (dst: []u8, dst_w: s64, dst_h: s64, dst_x: s64, dst_y: s64, dst_cell_w: s64, dst_cell_h: s64,
                                       src: *u8, src_w: s64, src_h: s64) {
    if dst_cell_w <= 0 || dst_cell_h <= 0 return;
    if src_w <= 0 || src_h <= 0 return;

    // Fit image into cell while preserving source aspect ratio.
    scale_x := cast(float) dst_cell_w / cast(float) src_w;
    scale_y := cast(float) dst_cell_h / cast(float) src_h;
    scale := min(scale_x, scale_y);

    fit_w := max(1, cast(s64) (cast(float) src_w * scale));
    fit_h := max(1, cast(s64) (cast(float) src_h * scale));
    if fit_w > dst_cell_w fit_w = dst_cell_w;
    if fit_h > dst_cell_h fit_h = dst_cell_h;

    ox := dst_x + (dst_cell_w - fit_w) / 2;
    oy := dst_y + (dst_cell_h - fit_h) / 2;

    resized := NewArray(fit_w * fit_h * 4, u8);
    // stb_image_resize defaults to Mitchell for downsampling in this module build.
    resized_ok := stbir_resize_uint8_srgb(
        input_pixels = src,
        input_w = cast(s32) src_w,
        input_h = cast(s32) src_h,
        input_stride_in_bytes = cast(s32) (src_w * 4),
        output_pixels = resized.data,
        output_w = cast(s32) fit_w,
        output_h = cast(s32) fit_h,
        output_stride_in_bytes = cast(s32) (fit_w * 4),
        num_channels = 4,
        alpha_channel = STBIR_ALPHA_CHANNEL_NONE,
        flags = cast(Resize_Flags) 0,
    );
    if resized_ok == 0 {
        log_error("stb_image_resize failed while resizing tile from %x% to %x%.", src_w, src_h, fit_w, fit_h);
        exit(1);
    }

    for y: 0..fit_h-1 {
        for x: 0..fit_w-1 {
            dst_px := ox + x;
            dst_py := oy + y;
            if dst_px < 0 || dst_px >= dst_w continue;
            if dst_py < 0 || dst_py >= dst_h continue;

            src_i := (y * fit_w + x) * 4;
            dst_i := (dst_py * dst_w + dst_px) * 4;

            dst[dst_i + 0] = resized[src_i + 0];
            dst[dst_i + 1] = resized[src_i + 1];
            dst[dst_i + 2] = resized[src_i + 2];
            dst[dst_i + 3] = resized[src_i + 3];
        }
    }
}

compose_grid :: (capture_paths: []string, opts: Meta_Grid_Opts) {
    count := capture_paths.count;
    if count == 0 {
        log_error("No capture images were found to compose.");
        exit(1);
    }

    cols := max(1, opts.columns);
    rows := (count + cols - 1) / cols;
    pad := max(0, opts.padding);
    cell_w := max(1, opts.cell_w);
    cell_h := max(1, opts.cell_h);

    canvas_w := cols * cell_w + (cols + 1) * pad;
    canvas_h := rows * cell_h + (rows + 1) * pad;
    pixel_count := canvas_w * canvas_h * 4;
    canvas := NewArray(pixel_count, u8);

    // Background color.
    i: s64 = 0;
    while i < pixel_count {
        canvas[i + 0] = 14;
        canvas[i + 1] = 16;
        canvas[i + 2] = 22;
        canvas[i + 3] = 255;
        i += 4;
    }

    for capture_paths {
        w: s32 = 0;
        h: s32 = 0;
        comp: s32 = 0;
        pixels := stbi_load(temp_c_string(it), *w, *h, *comp, 4);
        if pixels == null {
            reason := to_string(stbi_failure_reason());
            log_error("Failed to load capture image '%': %", it, reason);
            exit(1);
        }
        defer stbi_image_free(pixels);
        idx := cast(s64) it_index;
        col := idx % cols;
        row := idx / cols;
        x := pad + col * (cell_w + pad);
        y := pad + row * (cell_h + pad);

        blit_scaled_rgba8_high_quality_fit(canvas, canvas_w, canvas_h, x, y, cell_w, cell_h,
                                           pixels, cast(s64) w, cast(s64) h);
    }

    if !File.make_directory_if_it_does_not_exist(String.path_strip_filename(opts.out_grid), recursive = true) {
        log_error("Failed creating output directory for %", opts.out_grid);
        exit(1);
    }


    ok := stbi_write_jpg(temp_c_string(opts.out_grid), xx canvas_w, xx canvas_h, 4, canvas.data, quality=75);
    if ok == 0 {
        log_error("Failed to write grid image to '%'.", opts.out_grid);
        exit(1);
    }

    log("Wrote meta grid: % (%x%, cells=% columns=%)", opts.out_grid, canvas_w, canvas_h, count, cols);
}

capture_and_save_grid :: () {
    tool_dir := String.path_strip_filename(#filepath);
    repo_root := String.path_join(tool_dir, "..");
    set_working_directory(repo_root);

    opts: Meta_Grid_Opts;

    if !File.make_directory_if_it_does_not_exist(opts.out_dir, recursive = true) {
        log_error("Failed to create output dir '%'.", opts.out_dir);
        exit(1);
    }

    log("Capturing frames from % apps for a grid image...", APP_FILES.count);

    if !opts.skip_build {
        log("Building all apps...");
        _ = run_command_checked("Build all apps", .["jai", "build.jai", "-"]);
    }

    capture_paths: [..]string;
    failed_apps: [..]string;

    for APP_FILES {
        app_name := app_output_name(it);
        exe_name := app_executable_name(it);
        capture_dest := app_capture_path_for_source_file(it, opts.out_dir);

        if !opts.skip_capture {
            delete_old_snapshots_for_app(app_name);
            snapshot_w := max(256, opts.cell_w * 2);
            snapshot_h := max(256, opts.cell_h * 2);
            log("  capturing '%'...", exe_name);
            capture_ok := run_capture_for_app(exe_name, snapshot_w, snapshot_h);

            newest := find_latest_snapshot_for_app(app_name);
            if capture_ok && newest {
                if File_Utilities.file_exists(capture_dest) _ = File.file_delete(capture_dest);
                if !File_Utilities.copy_file(newest, capture_dest) {
                    log_error("Failed to copy snapshot from '%' to '%'.", newest, capture_dest);
                    exit(1);
                }
            } else {
                array_add(*failed_apps, copy_string(app_name));
                log_error("Capture failed for app '%'; (capture_ok=%, newest=%) writing placeholder tile.", app_name, capture_ok, newest);
                write_placeholder_capture(capture_dest, opts.cell_w, opts.cell_h);
            }
        }

        if !File_Utilities.file_exists(capture_dest) {
            log_error("Capture missing for app '%' at '%'. Run without -skip_capture first.", app_name, capture_dest);
            exit(1);
        }

        array_add(*capture_paths, copy_string(capture_dest));
    }

    compose_grid(capture_paths, opts);

    if failed_apps.count > 0 {
        log_error("Meta grid completed with capture failures: %", String.join(..failed_apps, separator = ", "));
        exit(1);
    }
}

#run,stallable {
    set_build_options_dc(.{ do_output = false });
    capture_and_save_grid();
}

#scope_file
#import "Basic";
#import "Compiler";
Process :: #import "Process";
String  :: #import "String";
File    :: #import "File";
File_Utilities :: #import "File_Utilities";
#import "stb_image";
#import "stb_image_resize";
#import "stb_image_write";
