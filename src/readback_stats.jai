#load "framebuffer_tools.jai";

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
        snapshot_width = max(1, snapshot_default_w),
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

readback_stats_log_sample :: (state: *Readback_Stats, log_prefix: string, frame_num: s64, stats: FB_Framebuffer_Stats) {
    log("%_FRAMEBUFFER_STATS frame=% sample=%/% size=%x% avg_rgb=(%, %, %) avg_luma=% min_luma=% max_luma=% std_luma=%",
        log_prefix,
        frame_num,
        state.stats_samples_done + 1,
        state.stats_max_samples,
        stats.width,
        stats.height,
        stats.avg_r,
        stats.avg_g,
        stats.avg_b,
        stats.avg_luma,
        stats.min_luma,
        stats.max_luma,
        stats.stddev_luma);
}

readback_stats_advance_sample :: (state: *Readback_Stats) -> bool {
    state.stats_samples_done += 1;
    return state.stats_samples_done >= state.stats_max_samples;
}

readback_stats_maybe_dump_snapshot :: (state: *Readback_Stats, view: Gpu_Texture_View, frame_num: s64, path_prefix: string, log_prefix: string) {
    if !state.snapshot_mode return;
    path := tprint("./%_frame_%.ppm", path_prefix, frame_num);
    dumped := fb_dump_swapchain_thumbnail_ppm(
        view,
        path,
        cast(u32) state.snapshot_width,
        cast(u32) state.snapshot_height);
    if dumped log("%_FRAMEBUFFER_SNAPSHOT frame=% path=%", log_prefix, frame_num, path);
}

readback_stats_maybe_run_readback_check :: (state: *Readback_Stats, view: Gpu_Texture_View, backend_label: string) -> bool {
    if !state.test_readback || state.did_readback || frame_count < 1 return true;
    state.did_readback = true;
    return fb_validate_swapchain_readback_non_black(view, backend_label);
}

readback_stats_should_export_jpg :: (state: *Readback_Stats, frame_num: s64, min_frame: s64 = 2) -> bool {
    if !state.export_jpg_mode return false;
    if state.exported_jpg return false;
    return frame_num >= min_frame;
}

readback_stats_mark_jpg_exported :: (state: *Readback_Stats) {
    state.exported_jpg = true;
}

readback_stats_env_int :: (name: string) -> (s64, bool) {
    value, set := fb_try_parse_env_int(name);
    return value, set;
}
