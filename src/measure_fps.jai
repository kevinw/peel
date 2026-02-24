PERF_AVG_WINDOW_FRAMES :: 120;
PERF_TITLE_UPDATE_EVERY_FRAMES :: 10;

perf_cpu_frame_ms_sum: float = 0;
perf_cpu_frame_ms_ring_index: s64 = 0;
perf_cpu_frame_ms_ring_count: s64 = 0;
perf_last_gpu_frame_ms: float = -1;
perf_cpu_frame_ms_ring: [PERF_AVG_WINDOW_FRAMES] float;

perf_push_cpu_frame_ms :: (cpu_ms: float) {
    clamped_ms := max(cpu_ms, 0.0001);

    if perf_cpu_frame_ms_ring_count < PERF_AVG_WINDOW_FRAMES {
        perf_cpu_frame_ms_ring_count += 1;
    } else {
        perf_cpu_frame_ms_sum -= perf_cpu_frame_ms_ring[perf_cpu_frame_ms_ring_index];
    }

    perf_cpu_frame_ms_ring[perf_cpu_frame_ms_ring_index] = clamped_ms;
    perf_cpu_frame_ms_sum += clamped_ms;
    perf_cpu_frame_ms_ring_index = (perf_cpu_frame_ms_ring_index + 1) % PERF_AVG_WINDOW_FRAMES;
}

perf_avg_cpu_frame_ms :: () -> float {
    if perf_cpu_frame_ms_ring_count <= 0 return 0;
    return perf_cpu_frame_ms_sum / cast(float) perf_cpu_frame_ms_ring_count;
}

perf_title_text :: () -> string {
    avg_cpu_ms := perf_avg_cpu_frame_ms();
    if avg_cpu_ms <= 0 return "fps=? cpu=?ms";

    f :: (value: float) -> FormatFloat #expand {
        return FormatFloat.{ value = value, trailing_width = 2, zero_removal = .NO };
    }

    avg_fps := 1000.0 / avg_cpu_ms;
    if perf_last_gpu_frame_ms >= 0 {
        return tprint("fps=% cpu=%ms gpu=%ms", f(avg_fps), f(avg_cpu_ms), f(perf_last_gpu_frame_ms));
    } else {
        return tprint("fps=% cpu=%ms", f(avg_fps), f(avg_cpu_ms));
    }
}
