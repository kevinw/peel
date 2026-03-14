#load "framebuffer_tools.jai";

smoke_mode := false;
debug_mode: u32 = 0;
window_snapshot_mode := false;
window_validate_mode := false;
window_probe_auto_quit := false;

Readback_Stats :: struct {
    test_readback: bool;
    did_readback: bool;
    stats_mode: bool;
    stats_every_frames: s64;
    stats_max_samples: s64;
    stats_samples_done: s64;
    snapshot_mode: bool;
    snapshot_target_frame: s64;
    snapshot_frames: [..]s64;
    snapshot_next_index: s64;
    snapshot_width: s64;
    snapshot_height: s64;
    export_jpg_mode: bool;
    exported_jpg: bool;
    prev_valid: bool;
    prev_avg_luma: float;
}

DEFAULT_SNAPSHOT_WIDTH  :u32 : 500;
DEFAULT_SNAPSHOT_HEIGHT :u32 : 500;

readback_stats_reset :: (state: *Readback_Stats, snapshot_default_w: s64 = DEFAULT_SNAPSHOT_WIDTH, snapshot_default_h: s64 = DEFAULT_SNAPSHOT_HEIGHT) {
    array_free(state.snapshot_frames);
    state.* = .{
        snapshot_width  = max(1, snapshot_default_w),
        snapshot_height = max(1, snapshot_default_h),
    };
    state.snapshot_frames.allocator = context.allocator;
}

readback_stats_init :: (state: *Readback_Stats, log_prefix: string, snapshot_default_w: s64 = DEFAULT_SNAPSHOT_WIDTH, snapshot_default_h: s64 = DEFAULT_SNAPSHOT_HEIGHT) {
    readback_stats_reset(state, snapshot_default_w, snapshot_default_h);

    test_readback, _ := try_parse_env_int("PEEL_TEST_READBACK");
    state.test_readback = test_readback > 0;

    stats_every_frames, stats_every_set := try_parse_env_int("PEEL_STATS_EVERY");
    stats_max_samples, stats_max_set := try_parse_env_int("PEEL_STATS_MAX");
    state.stats_every_frames = stats_every_frames;
    state.stats_max_samples = stats_max_samples;
    if stats_every_frames > 0 && stats_max_samples > 0 {
        state.stats_mode = true;
    } else if stats_every_set || stats_max_set {
        log_error("% stats mode requires both PEEL_STATS_EVERY (>0) and PEEL_STATS_MAX (>0).", log_prefix);
    }

    snapshot_value_c := getenv(temp_c_string("PEEL_SNAPSHOT"));
    if snapshot_value_c {
        snapshot_value := to_string(snapshot_value_c, c_style_strlen(snapshot_value_c));
        parse_snapshot_frames(state, snapshot_value);
        state.snapshot_mode = state.snapshot_frames.count > 0;
        if state.snapshot_frames.count > 0 {
            state.snapshot_target_frame = state.snapshot_frames[0];
        }
    }

    snapshot_w, snapshot_w_set := try_parse_env_int("PEEL_SNAPSHOT_W");
    if snapshot_w_set state.snapshot_width = max(1, snapshot_w);
    snapshot_h, snapshot_h_set := try_parse_env_int("PEEL_SNAPSHOT_H");
    if snapshot_h_set state.snapshot_height = max(1, snapshot_h);

}

readback_stats_needs_swapchain_readback :: (state: *Readback_Stats) -> bool {
    return state.test_readback || state.stats_mode || state.snapshot_mode || state.export_jpg_mode;
}

readback_stats_should_sample :: (using state: *Readback_Stats, frame_num: s64) -> bool {
    if !stats_mode return false;
    if stats_samples_done >= stats_max_samples return false;
    if frame_num <= 0 return false;
    return (frame_num % stats_every_frames) == 0;
}

readback_stats_log_sample :: (state: *Readback_Stats, log_prefix: string, frame_num: s64, using stats: FB_Framebuffer_Stats) {
    log("%_FRAMEBUFFER_STATS frame=% sample=%/% size=%x% avg_rgb=(%, %, %) avg_luma=% min_luma=% max_luma=% std_luma=%",

        log_prefix,
        frame_num,
        state.stats_samples_done + 1,
        state.stats_max_samples,

        width,
        height,
        avg_r,
        avg_g,
        avg_b,
        avg_luma,
        min_luma,
        max_luma,
        stddev_luma);
}

readback_stats_advance_sample :: (using state: *Readback_Stats) -> bool {
    stats_samples_done += 1;
    return stats_samples_done >= stats_max_samples;
}

readback_stats_dump_snapshot :: (using state: *Readback_Stats, view: Gpu_Texture_View, frame_num: s64, path_prefix: string, log_prefix: string) {
    path := tprint("./%_frame_%.jpeg", path_prefix, frame_num);
    dumped := fb_dump_swapchain_thumbnail_jpeg(view, path, cast(u32) snapshot_width, cast(u32) snapshot_height);
    if dumped {
        log("%_FRAMEBUFFER_SNAPSHOT frame=% path=%", log_prefix, frame_num, path);
    }
}


readback_stats_should_export_jpg :: (using state: *Readback_Stats, frame_num: s64, min_frame: s64 = 2) -> bool {
    if !export_jpg_mode return false;
    if exported_jpg return false;
    return frame_num >= min_frame;
}

readback_stats_mark_jpg_exported :: (using state: *Readback_Stats) {
    exported_jpg = true;
}

parse_snapshot_frames :: (state: *Readback_Stats, value: string) {
    start: s64 = 0;
    while start < value.count {
        end := start;
        while end < value.count && value[end] != #char "," end += 1;
        part := string.{count = end - start, data = value.data + start};
        part = trim(part);
        if part.count > 0 {
            frame, ok, _ := String.string_to_int(part);
            if ok && frame > 0 {
                array_add(*state.snapshot_frames, cast(s64) frame);
            } else {
                log_error("Invalid PEEL_SNAPSHOT entry '%'. Expected positive integer.", part);
            }
        }
        start = end + 1;
    }
}

doing_peel_diagnostic :: () -> bool {
    return smoke_mode ||
        max_frames > 0 ||
        window_snapshot_mode ||
        readback_stats.export_jpg_mode;
}


frame_debug_init :: (readback_stats: *Readback_Stats) {
    readback_stats_init(readback_stats, APP_NAME, snapshot_default_w = DEFAULT_SNAPSHOT_WIDTH, snapshot_default_h = DEFAULT_SNAPSHOT_HEIGHT);

    if try_parse_env_int("PEEL_SMOKE") > 0           smoke_mode = true;
    if try_parse_env_int("PEEL_WINDOW_SNAPSHOT") > 0 window_snapshot_mode = true;
    if try_parse_env_int("PEEL_WINDOW_VALIDATE") > 0 window_validate_mode = true;
    debug_mode_env,      _ := try_parse_env_int("PEEL_DEBUG_MODE");
    if debug_mode_env > 0      debug_mode = cast(u32) debug_mode_env;

    if smoke_mode {
        readback_stats.test_readback = true;
        window_probe_auto_quit = true;
    }

    if window_snapshot_mode || window_validate_mode window_probe_auto_quit = true;

    if readback_stats_needs_swapchain_readback(readback_stats) || window_snapshot_mode || window_validate_mode {
        gpu_set_swapchain_framebuffer_only(false);
    }
}

per_frame_debug :: (using readback_stats: *Readback_Stats, frame_num: s64, swapchain_image: Gpu_Texture_View) {
    check_frame_buffer :: () #expand {
        if swapchain_image == 0 {
            log_error("Swapchain image is null; cannot perform readback/stats/snapshot.");
            `return;
        }
    }

    if max_frames == 1 && (window_snapshot_mode || window_validate_mode) {
        log("Warning: PEEL_WINDOW_SNAPSHOT and PEEL_WINDOW_VALIDATE require at least 2 frames to run. Current max_frames=%.", max_frames);
    }

    if frame_num >= 2 && window_snapshot_mode {
        check_frame_buffer();
        window_snapshot_path := tprint("./%_window_frame_%.jpeg", APP_NAME, frame_num);
        gpu_dump_to_bitmap(window_snapshot_path);
        log("WINDOW_SNAPSHOT frame=% path=%", frame_num, window_snapshot_path);
        window_snapshot_mode = false;
    }

    if frame_num >= 2 && window_validate_mode {
        check_frame_buffer();
        ok := gpu_validate_window_readback_non_black();
        assert(ok, "Error: Window capture validation failed: output appears black.");
        window_validate_mode = false;
    }

    if frame_num >= 2 && window_probe_auto_quit && !window_snapshot_mode && !window_validate_mode {
        check_frame_buffer();
        log("WINDOW_PROBE completed; quitting.");
        app_quit_requested = true;
    }

    if snapshot_mode && snapshot_next_index < snapshot_frames.count &&
       frame_num >= snapshot_frames[snapshot_next_index] {
        check_frame_buffer();
        readback_stats_dump_snapshot(readback_stats, swapchain_image, frame_num, tprint("%_snapshot", APP_STEM), APP_STEM);
        snapshot_next_index += 1;
        if snapshot_next_index >= readback_stats.snapshot_frames.count {
            snapshot_mode = false;
        } else {
            snapshot_target_frame = snapshot_frames[snapshot_next_index];
        }
    }

    if readback_stats_should_sample(readback_stats, frame_num) {
        check_frame_buffer();
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(readback_stats, APP_NAME, frame_num, stats);
        } else {
            log("error: failed to collect framebuffer stats");
        }
        if readback_stats_advance_sample(readback_stats) {
            log("Framebuffer stats completed % samples; quitting.", stats_max_samples);
            app_quit_requested = true;
        }
    }

    {
        using readback_stats;
        if test_readback && !did_readback && frame_count >= 1 {
            check_frame_buffer();
            did_readback = true;
            os_lower := tprint("%", OS);
            to_lower_in_place(os_lower);
            ok := fb_validate_swapchain_readback_non_black(swapchain_image, tprint("%_%", APP_NAME, os_lower));
            assert(ok, "Readback check failed: output appears uniform/black.");
        }
    }
}

#scope_file
#import "Env_Vars";
using,only(getenv) POSIX :: #import "POSIX";
String :: #import "String";
using,only(to_lower_in_place, trim) _ :: #import "String";
