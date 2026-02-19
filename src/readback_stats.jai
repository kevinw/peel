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
    snapshot_width: s64;
    snapshot_height: s64;
    export_jpg_mode: bool;
    exported_jpg: bool;
    prev_valid: bool;
    prev_avg_luma: float;
}

readback_stats_reset :: (state: *Readback_Stats, snapshot_default_w: s64 = 96, snapshot_default_h: s64 = 96) {
    state.* = .{
        snapshot_width  = max(1, snapshot_default_w),
        snapshot_height = max(1, snapshot_default_h),
    };
}

readback_stats_init :: (state: *Readback_Stats, log_prefix: string, snapshot_default_w: s64 = 96, snapshot_default_h: s64 = 96, enable_export_jpg := false) {
    readback_stats_reset(state, snapshot_default_w, snapshot_default_h);

    test_readback, _ := readback_stats_env_int("PEEL_TEST_READBACK");
    state.test_readback = test_readback > 0;

    stats_every_frames, stats_every_set := readback_stats_env_int("PEEL_STATS_EVERY");
    stats_max_samples, stats_max_set := readback_stats_env_int("PEEL_STATS_MAX");
    state.stats_every_frames = stats_every_frames;
    state.stats_max_samples = stats_max_samples;
    if stats_every_frames > 0 && stats_max_samples > 0 {
        state.stats_mode = true;
    } else if stats_every_set || stats_max_set {
        log_error("% stats mode requires both PEEL_STATS_EVERY (>0) and PEEL_STATS_MAX (>0).", log_prefix);
    }

    snapshot_mode, _ := readback_stats_env_int("PEEL_SNAPSHOT");
    state.snapshot_mode = snapshot_mode > 0;

    snapshot_w, snapshot_w_set := readback_stats_env_int("PEEL_SNAPSHOT_W");
    if snapshot_w_set state.snapshot_width = max(1, snapshot_w);
    snapshot_h, snapshot_h_set := readback_stats_env_int("PEEL_SNAPSHOT_H");
    if snapshot_h_set state.snapshot_height = max(1, snapshot_h);

    if enable_export_jpg {
        export_jpg_mode, _ := readback_stats_env_int("PEEL_EXPORT_JPG");
        state.export_jpg_mode = export_jpg_mode > 0;
    }
}

readback_stats_needs_swapchain_readback :: (state: *Readback_Stats) -> bool {
    return state.test_readback || state.stats_mode || state.snapshot_mode || state.export_jpg_mode;
}

readback_stats_should_sample :: (state: *Readback_Stats, frame_num: s64) -> bool {
    if !state.stats_mode return false;
    if state.stats_samples_done >= state.stats_max_samples return false;
    if frame_num <= 0 return false;
    return (frame_num % state.stats_every_frames) == 0;
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

readback_stats_maybe_dump_snapshot :: (using state: *Readback_Stats, view: Gpu_Texture_View, frame_num: s64, path_prefix: string, log_prefix: string) {
    if !snapshot_mode return;
    path := tprint("./%_frame_%.ppm", path_prefix, frame_num);
    dumped := fb_dump_swapchain_thumbnail_ppm(view, path, cast(u32) snapshot_width, cast(u32) snapshot_height);
    if dumped {
        log("%_FRAMEBUFFER_SNAPSHOT frame=% path=%", log_prefix, frame_num, path);
    }
}

readback_stats_maybe_run_readback_check :: (using state: *Readback_Stats, view: Gpu_Texture_View, backend_label: string) -> bool {
    if !test_readback || did_readback || frame_count < 1 return true;
    did_readback = true;
    return fb_validate_swapchain_readback_non_black(view, backend_label);
}

readback_stats_should_export_jpg :: (using state: *Readback_Stats, frame_num: s64, min_frame: s64 = 2) -> bool {
    if !export_jpg_mode return false;
    if exported_jpg return false;
    return frame_num >= min_frame;
}

readback_stats_mark_jpg_exported :: (using state: *Readback_Stats) {
    exported_jpg = true;
}

readback_stats_env_int :: (name: string) -> (s64, bool) {
    value, set := fb_try_parse_env_int(name);
    return value, set;
}

frame_debug_init :: (readback_stats: *Readback_Stats) {
    readback_stats_init(readback_stats, APP_NAME, snapshot_default_w = 128, snapshot_default_h = 128, enable_export_jpg = true);

    if readback_stats_env_int("PEEL_SMOKE") > 0      smoke_mode = true;
    if readback_stats_env_int("PEEL_WINDOW_SNAPSHOT") > 0 window_snapshot_mode = true;
    if readback_stats_env_int("PEEL_WINDOW_VALIDATE") > 0 window_validate_mode = true;
    debug_mode_env,      _ := readback_stats_env_int("PEEL_DEBUG_MODE");
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

per_frame_debug :: (readback_stats: *Readback_Stats, frame_num: s64, swapchain_image: Gpu_Texture_View) {
    if frame_num >= 2 && window_snapshot_mode {
        window_snapshot_path := tprint("./%_window_frame_%.jpeg", APP_NAME, frame_num);
        gpu_dump_to_bitmap(window_snapshot_path);
        log("WINDOW_SNAPSHOT frame=% path=%", frame_num, window_snapshot_path);
        window_snapshot_mode = false;
    }
    if frame_num >= 2 && window_validate_mode {
        ok := gpu_validate_window_readback_non_black();
        assert(ok, "Error: Window capture validation failed: output appears black.");
        window_validate_mode = false;
    }
    if frame_num >= 2 && window_probe_auto_quit && !window_snapshot_mode && !window_validate_mode {
        log("WINDOW_PROBE completed; quitting.");
        app_quit_requested = true;
    }

    if readback_stats_should_sample(readback_stats, frame_num) {
        stats, ok := fb_collect_swapchain_framebuffer_stats(swapchain_image);
        if ok {
            readback_stats_log_sample(readback_stats, APP_NAME, frame_num, stats);
            readback_stats_maybe_dump_snapshot(readback_stats, swapchain_image, frame_num, tprint("%_snapshot", APP_NAME), APP_NAME);
        }
        if readback_stats_advance_sample(readback_stats) {
            log("Framebuffer stats completed % samples; quitting.", readback_stats.stats_max_samples);
            app_quit_requested = true;
        }
    }

    ok := readback_stats_maybe_run_readback_check(readback_stats, swapchain_image, tprint("%_metal", APP_NAME));
    assert(ok, "Readback check failed: output appears uniform/black.");
}
