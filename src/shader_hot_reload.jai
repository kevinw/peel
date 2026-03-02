SRM :: #import,file "../modules/Jai-Shader-Transpiler/modules/shader_reload_manifest.jai";

Shader_Hot_Reload :: struct {
    enabled: bool;
    use_background_thread: bool;
    log_prefix: string;
    watcher: SRM.Shader_Reload_Watcher;
    graphics_targets: [..] Shader_Hot_Reload_Graphics_Target;
    compute_targets: [..] Shader_Hot_Reload_Compute_Target;
    last_event_frame: s64;
    last_result: Shader_Hot_Reload_Last_Result;
    worker_started: bool;
    worker_thread: Thread;
    worker_wake: Semaphore;
    worker_mutex: Mutex;
    worker_should_exit: bool;
    worker_has_pending: bool;
    worker_pending_ids_csv: string;
    worker_build_in_flight: bool;
    worker_has_completed: bool;
    worker_completed_ok: bool;
    worker_completed_ids_csv: string;
    worker_completed_error_message: string;
    last_error_message: string;
    show_error_window: bool;
}

Shader_Hot_Reload_Last_Result :: enum {
    NONE;
    BUILD_QUEUED;
    BUILD_RUNNING;
    BUILD_FAILED;
    SWAP_PARTIAL;
    SWAP_OK;
}

Shader_Hot_Reload_Graphics_Target :: struct {
    entry_id: string;
    pipeline: *Gpu_Pipeline;
    raster_desc: Gpu_Raster_Desc;
}

Shader_Hot_Reload_Compute_Target :: struct {
    entry_id: string;
    pipeline: *Gpu_Pipeline;
}

shader_hot_reload_init_auto :: (reload: *Shader_Hot_Reload, app_source_file: string, poll_every_frames: s64 = 15, log_prefix: string = "SHADER_RELOAD", enabled_by_default: bool = false, use_background_thread: bool = true) -> bool {
    reload.* = .{};
    reload.log_prefix = copy_string(log_prefix);
    reload.use_background_thread = use_background_thread;
    reload.last_event_frame = -1;
    reload.last_result = .NONE;
    reload.last_error_message = "";
    reload.show_error_window = false;
    reload.enabled = SRM.shader_reload_watcher_init_auto(*reload.watcher, app_source_file, poll_every_frames, enabled_by_default);
    if reload.enabled && reload.use_background_thread {
        shader_hot_reload_start_worker_thread(reload);
    }
    return reload.enabled;
}

shader_hot_reload_register_graphics_pipeline :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline, raster_desc: Gpu_Raster_Desc) {
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.graphics_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
        raster_desc = raster_desc,
    });
}

shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc) -> bool {
    if entry_id.count == 0 || !pipeline return false;

    new_pipeline := shader_hot_reload_create_graphics_pipeline_for_entry(reload, entry_id, raster_desc);
    if new_pipeline == 0 && source.count > 0 {
        // Startup/build-cache fallback: manifest_latest can be stale (global/shared),
        // but direct source compilation is still valid for initial pipeline creation.
        log_error("% falling back to source graphics compile for id=%", reload.log_prefix, entry_id);
        new_pipeline = gpu_create_graphics_pipeline(source, raster_desc);
    }
    if new_pipeline == 0 return false;

    old_pipeline := pipeline.*;
    pipeline.* = new_pipeline;
    if old_pipeline != 0 gpu_free_pipeline(old_pipeline);

    shader_hot_reload_register_graphics_pipeline(reload, entry_id, pipeline, raster_desc);
    return true;
}

shader_hot_reload_create_and_register_graphics_pipeline :: (reload: *Shader_Hot_Reload, pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc, target: JTS.Transpiled_Target, $vertex_shader: $VERTEX_SHADER, $fragment_shader: $FRAGMENT_SHADER, call: Code = #caller_code) -> bool #expand {
    vertex_name := #run shader_hot_reload_proc_name_from_caller_arg_compile_time(call, 5);
    fragment_name := #run shader_hot_reload_proc_name_from_caller_arg_compile_time(call, 6);
    target_name := tprint("%", target);
    entry_id := tprint("pair|%|%|%", target_name, vertex_name, fragment_name);
    return shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id(reload, entry_id, pipeline, source, raster_desc);
}

shader_hot_reload_register_compute_pipeline :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline) {
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.compute_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
    });
}

shader_hot_reload_create_and_register_compute_pipeline_with_entry_id :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline, source: []u8) -> bool {
    if entry_id.count == 0 || !pipeline return false;

    new_pipeline := shader_hot_reload_create_compute_pipeline_for_entry(reload, entry_id);
    if new_pipeline == 0 && source.count > 0 {
        // Startup/build-cache fallback: manifest_latest can be stale (global/shared),
        // but direct source compilation is still valid for initial pipeline creation.
        log_error("% falling back to source compute compile for id=%", reload.log_prefix, entry_id);
        new_pipeline = gpu_create_compute_pipeline(source);
    }
    if new_pipeline == 0 return false;

    old_pipeline := pipeline.*;
    pipeline.* = new_pipeline;
    if old_pipeline != 0 gpu_free_pipeline(old_pipeline);

    shader_hot_reload_register_compute_pipeline(reload, entry_id, pipeline);
    return true;
}

shader_hot_reload_create_and_register_compute_pipeline :: (reload: *Shader_Hot_Reload, pipeline: *Gpu_Pipeline, source: []u8, target: JTS.Transpiled_Target, $compute_shader: $COMPUTE_SHADER, call: Code = #caller_code) -> bool #expand {
    compute_name := #run shader_hot_reload_proc_name_from_caller_arg_compile_time(call, 4);
    target_name := tprint("%", target);
    entry_id := tprint("single|%|compute|%", target_name, compute_name);
    return shader_hot_reload_create_and_register_compute_pipeline_with_entry_id(reload, entry_id, pipeline, source);
}

shader_hot_reload_tick :: (reload: *Shader_Hot_Reload, frame_num: s64) -> (did_rebuild: bool, swapped_all: bool, build_ok: bool) {
    if !reload.enabled return false, true, true;

    if reload.worker_started {
        changed_ids_csv, has_changes := SRM.shader_reload_watcher_poll_changed_entry_ids_csv(*reload.watcher, frame_num);
        if has_changes {
            shader_hot_reload_queue_background_build(reload, changed_ids_csv);
        }

        completed_ok: bool;
        completed_ids_csv: string;
        completed_error: string;
        has_completed := shader_hot_reload_take_background_completion(reload, *completed_ok, *completed_ids_csv, *completed_error);
        if !has_completed return false, true, true;

        reload.last_event_frame = frame_num;
        assign_string(*reload.watcher.last_changed_entry_ids_csv, completed_ids_csv);
        if !completed_ok {
            reload.last_result = .BUILD_FAILED;
            shader_hot_reload_set_error(reload, shader_hot_reload_build_failed_message(reload.log_prefix, reload.watcher.last_changed_entry_ids_csv, completed_error));
            if completed_error.count != 0 free(completed_error);
            if completed_ids_csv.count != 0 free(completed_ids_csv);
            return true, false, false;
        }
        if completed_error.count != 0 free(completed_error);

        manifest_reloaded := SRM.shader_reload_manifest_load_with_context(*reload.watcher.manifest, *reload.watcher.paths);
        if !manifest_reloaded {
            shader_hot_reload_log_manifest_state(reload, "manifest reload failed after build", reload.watcher.last_changed_entry_ids_csv);
        }
        SRM.shader_reload_watcher_refresh_baseline(*reload.watcher);

        apply_ok := shader_hot_reload_apply_registered_pipelines(reload);
        if apply_ok {
            reload.last_result = .SWAP_OK;
            shader_hot_reload_clear_error(reload);
        } else {
            reload.last_result = .SWAP_PARTIAL;
        }
        if completed_ids_csv.count != 0 free(completed_ids_csv);
        return true, apply_ok, true;
    }

    did_rebuild, build_ok := SRM.shader_reload_watcher_poll_and_rebuild(*reload.watcher, frame_num);
    if !did_rebuild return false, true, true;
    reload.last_event_frame = frame_num;
    if !build_ok {
        reload.last_result = .BUILD_FAILED;
        details := reload.watcher.last_build_error_message;
        shader_hot_reload_set_error(reload, shader_hot_reload_build_failed_message(reload.log_prefix, reload.watcher.last_changed_entry_ids_csv, details));
        return true, false, false;
    }
    apply_ok := shader_hot_reload_apply_registered_pipelines(reload);
    if apply_ok {
        reload.last_result = .SWAP_OK;
        shader_hot_reload_clear_error(reload);
    } else {
        reload.last_result = .SWAP_PARTIAL;
    }
    return true, apply_ok, true;
}

shader_hot_reload_status_line :: (using reload: *Shader_Hot_Reload, max_ids_chars: s64 = 72) -> string {
    if !enabled return "";

    if last_result == .NONE return "";
    ids := watcher.last_changed_entry_ids_csv;
    ids_short := ids;
    if max_ids_chars > 0 && ids_short.count > max_ids_chars {
        ids_short.count = max_ids_chars;
        ids_short = tprint("%...", ids_short);
    }


    result_text := tprint("%", last_result);
    if reload.last_event_frame < 0 return tprint("shader_reload=on status=%", result_text);
    if ids_short.count == 0 return tprint("shader_reload=on status=% frame=%", result_text, last_event_frame);
    return tprint("shader_reload=on status=% frame=% ids=%", result_text, last_event_frame, ids_short);
}

shader_hot_reload_proc_name_from_caller_arg_compile_time :: (call: Code, arg_index: s64) -> string {
    root, _ := compiler_get_nodes(call);
    if !root || root.kind != .PROCEDURE_CALL return "";
    pc := cast(*Code_Procedure_Call) root;
    if arg_index < 0 || arg_index >= pc.arguments_unsorted.count return "";
    arg := pc.arguments_unsorted[arg_index].expression;
    if !arg || arg.kind != .IDENT return "";
    return (cast(*Code_Ident) arg).name;
}

shader_hot_reload_apply_registered_pipelines :: (using reload: *Shader_Hot_Reload) -> bool {
    ok := true;
    changed_ids_csv := watcher.last_changed_entry_ids_csv;

    for graphics_targets {
        if changed_ids_csv.count != 0 && !shader_hot_reload_ids_csv_contains(changed_ids_csv, it.entry_id) continue;
        entry := SRM.shader_reload_manifest_find_entry(*watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing graphics entry id=%", log_prefix, it.entry_id);
            log_missing_entry_context(reload, it.entry_id, "graphics");
            shader_hot_reload_set_error(reload, tprint("% missing graphics entry id=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        new_pipeline := shader_hot_reload_create_graphics_pipeline_for_manifest_entry(reload, entry, it.raster_desc);
        if new_pipeline == 0 {
            shader_hot_reload_set_error(reload, tprint("% graphics pipeline recreation failed entry=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        old_pipeline := it.pipeline.*;
        it.pipeline.* = new_pipeline;
        if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    }

    for compute_targets {
        if changed_ids_csv.count != 0 && !shader_hot_reload_ids_csv_contains(changed_ids_csv, it.entry_id) continue;
        entry := SRM.shader_reload_manifest_find_entry(*watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing compute entry id=%", log_prefix, it.entry_id);
            log_missing_entry_context(reload, it.entry_id, "compute");
            shader_hot_reload_set_error(reload, tprint("% missing compute entry id=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        new_pipeline := shader_hot_reload_create_compute_pipeline_for_manifest_entry(reload, entry);
        if new_pipeline == 0 {
            shader_hot_reload_set_error(reload, tprint("% compute pipeline recreation failed entry=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        old_pipeline := it.pipeline.*;
        it.pipeline.* = new_pipeline;
        if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    }

    if ok log("% swapped pipelines for ids=%", log_prefix, watcher.last_changed_entry_ids_csv);
    return ok;
}

shader_hot_reload_imgui :: (reload: *Shader_Hot_Reload, monospace_font: *ImGui.ImFont = null) {
    if !reload || !reload.show_error_window || reload.last_error_message.count == 0 return;
    io := ImGui.GetIO();
    overlay_height := clamp(io.DisplaySize.y * 0.45, 220.0, io.DisplaySize.y - 24.0);
    ImGui.SetNextWindowPos(.{0.0, io.DisplaySize.y - overlay_height}, .Always);
    ImGui.SetNextWindowSize(.{io.DisplaySize.x, overlay_height}, .Always);
    open := true;
    window_flags: ImGui.WindowFlags = .NoMove | .NoResize | .NoCollapse | .NoSavedSettings | .NoNav | .NoBringToFrontOnFocus;
    if ImGui.Begin("Live shader reload failed.", *open, window_flags) {
        if monospace_font != null ImGui.PushFont(monospace_font, 0.0);
        defer if monospace_font != null ImGui.PopFont();
        avail := ImGui.GetContentRegionAvail();
        if ImGui.BeginChild("shader_reload_error_text", .{avail.x, avail.y}, .None) {
            shader_hot_reload_draw_error_message_with_links(reload.last_error_message);
        }
        ImGui.EndChild();
    }
    ImGui.End();
    if !open reload.show_error_window = false;
}

#scope_file

shader_hot_reload_start_worker_thread :: (using reload: *Shader_Hot_Reload) {
    init(*worker_wake, 0);
    init(*worker_mutex, "shader_hot_reload");
    ok := thread_init(*worker_thread, shader_hot_reload_worker_proc);
    if !ok {
        log_error("% failed to start worker thread; using synchronous reload path.", log_prefix);
        worker_started = false;
        use_background_thread = false;
        return;
    }
    worker_thread.data = reload;
    thread_start(*worker_thread);
    worker_started = true;
}

shader_hot_reload_queue_background_build :: (using reload: *Shader_Hot_Reload, changed_ids_csv: string) {
    if !worker_started return;
    lock(*worker_mutex);
    defer unlock(*worker_mutex);

    if worker_build_in_flight {
        last_result = .BUILD_RUNNING;
    } else {
        last_result = .BUILD_QUEUED;
    }
    assign_string(*worker_pending_ids_csv, changed_ids_csv);
    worker_has_pending = true;
    signal(*worker_wake);
}

shader_hot_reload_take_background_completion :: (using reload: *Shader_Hot_Reload, completed_ok: *bool, completed_ids_csv: *string, completed_error: *string) -> bool {
    if !worker_started return false;
    lock(*worker_mutex);
    defer unlock(*worker_mutex);

    if !worker_has_completed return false;
    worker_has_completed = false;
    completed_ok.* = worker_completed_ok;
    completed_ids_csv.* = worker_completed_ids_csv;
    completed_error.* = worker_completed_error_message;
    worker_completed_ids_csv = "";
    worker_completed_error_message = "";
    return true;
}

shader_hot_reload_worker_proc :: (thread: *Thread) -> s64 {
    using reload := cast(*Shader_Hot_Reload) thread.data;
    if !reload return 0;

    while true {
        _ = wait_for(*worker_wake);

        ids_csv: string;
        lock(*worker_mutex);
        if worker_should_exit {
            unlock(*worker_mutex);
            break;
        }
        if !worker_has_pending {
            unlock(*worker_mutex);
            continue;
        }
        ids_csv = worker_pending_ids_csv;
        worker_pending_ids_csv = "";
        worker_has_pending = false;
        worker_build_in_flight = true;
        unlock(*worker_mutex);

        build_error: string;
        build_ok := SRM.shader_reload_build_entry_ids_with_context(*watcher.paths, watcher.app_source_file, ids_csv, out_error = *build_error);

        lock(*worker_mutex);
        worker_build_in_flight = false;
        worker_completed_ok = build_ok;
        assign_string(*worker_completed_ids_csv, ids_csv);
        assign_string(*worker_completed_error_message, build_error);
        worker_has_completed = true;
        unlock(*worker_mutex);
        if ids_csv.count != 0 free(ids_csv);
        if build_error.count != 0 free(build_error);
    }

    return 0;
}

assign_string :: (dst: *string, src: string) {
    if dst.*.count != 0 {
        free(dst.*);
        dst.* = "";
    }
    if src.count != 0 dst.* = copy_string(src);
}

shader_hot_reload_ids_csv_contains :: (ids_csv: string, entry_id: string) -> bool {
    if ids_csv.count == 0 || entry_id.count == 0 return false;
    for String.split(ids_csv, #char ",") {
        if shader_hot_reload_trim_ascii_whitespace(it) == entry_id return true;
    }
    return false;
}

shader_hot_reload_trim_ascii_whitespace :: (in: string) -> string {
    if in.count == 0 return in;
    start: s64 = 0;
    last := in.count - 1;
    while start <= last && (in[start] == #char " " || in[start] == #char "\t" || in[start] == #char "\n" || in[start] == #char "\r")
        start += 1;
    while last >= start && (in[last] == #char " " || in[last] == #char "\t" || in[last] == #char "\n" || in[last] == #char "\r")
        last -= 1;
    out: string;
    out.data = in.data + start;
    out.count = last - start + 1;
    return out;
}

shader_hot_reload_set_error :: (reload: *Shader_Hot_Reload, message: string) {
    if !reload return;
    if message.count == 0 return;
    log_error("%", message);
    assign_string(*reload.last_error_message, message);
    reload.show_error_window = true;
}

shader_hot_reload_build_failed_message :: (log_prefix: string, ids_csv: string, details: string) -> string {
    base := tprint("% build failed for ids=%", log_prefix, ids_csv);
    if details.count == 0 return base;
    return tprint("%\n\n%", base, details);
}

shader_hot_reload_draw_error_message_with_links :: (message: string) {
    if message.count == 0 return;
    line_idx: s64 = 0;
    for String.split(message, #char "\n") {
        path: string;
        line_no: s64;
        col_no: s64;
        has_loc := shader_hot_reload_parse_source_location(it, *path, *line_no, *col_no);
        if has_loc {
            label := tprint("Open##shader_reload_open_%", line_idx);
            if ImGui.SmallButton(temp_c_string(label)) {
                arg := tprint("%:%", path, line_no);
                _ = Process.run_command("zed", arg, timeout_ms = 5000);
            }
            ImGui.SameLine();
        }
        ImGui.TextUnformatted(it);
        line_idx += 1;
    }
}

shader_hot_reload_parse_source_location :: (line: string, out_path: *string, out_line: *s64, out_col: *s64) -> bool {
    if line.count == 0 return false;
    jai_marker := ".jai:";
    marker_at: s64 = -1;
    if line.count >= jai_marker.count {
        max_start := line.count - jai_marker.count;
        for i: 0..max_start {
            match := true;
            for j: 0..jai_marker.count-1 {
                if line[i + j] != jai_marker[j] {
                    match = false;
                    break;
                }
            }
            if match {
                marker_at = i;
                break;
            }
        }
    }
    if marker_at <= 0 return false;
    if line[0] != #char "/" return false;

    path_len := marker_at + 4;
    path: string = .{count = path_len, data = line.data};
    i := marker_at + jai_marker.count;
    if i >= line.count return false;

    line_no: s64 = 0;
    has_line_digits := false;
    while i < line.count {
        c := line[i];
        if c < #char "0" || c > #char "9" break;
        has_line_digits = true;
        line_no = line_no * 10 + cast(s64) (c - #char "0");
        i += 1;
    }
    if !has_line_digits return false;

    col_no: s64 = 0;
    if i < line.count && line[i] == #char "," {
        i += 1;
        has_col_digits := false;
        while i < line.count {
            c := line[i];
            if c < #char "0" || c > #char "9" break;
            has_col_digits = true;
            col_no = col_no * 10 + cast(s64) (c - #char "0");
            i += 1;
        }
        if !has_col_digits col_no = 0;
    }

    if i >= line.count || line[i] != #char ":" return false;

    out_path.* = path;
    out_line.* = line_no;
    out_col.* = col_no;
    return true;
}

shader_hot_reload_clear_error :: (reload: *Shader_Hot_Reload) {
    if !reload return;
    assign_string(*reload.last_error_message, "");
    reload.show_error_window = false;
}

shader_hot_reload_create_graphics_pipeline_for_entry :: (reload: *Shader_Hot_Reload, entry_id: string, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    if !reload return 0;
    entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, entry_id);
    if !entry {
        log_missing_entry_context(reload, entry_id, "graphics");
        shader_hot_reload_set_error(reload, tprint("% missing graphics entry id=%", reload.log_prefix, entry_id));
        return 0;
    }
    return shader_hot_reload_create_graphics_pipeline_for_manifest_entry(reload, entry, raster_desc);
}

shader_hot_reload_create_graphics_pipeline_for_manifest_entry :: (reload: *Shader_Hot_Reload, entry: *SRM.Shader_Reload_Manifest_Entry, raster_desc: Gpu_Raster_Desc) -> Gpu_Pipeline {
    if !reload || !entry return 0;
    metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
    if !found {
        shader_hot_reload_set_error(reload, tprint("% missing metallib for graphics entry=% request=%", reload.log_prefix, entry.entry_id, entry.request_name));
        return 0;
    }
    if entry.metal_vertex_entry.count == 0 || entry.metal_fragment_entry.count == 0 {
        shader_hot_reload_set_error(reload, tprint("% missing metal vertex/fragment entry names for id=%", reload.log_prefix, entry.entry_id));
        return 0;
    }
    return gpu_create_graphics_pipeline_from_metallib(metallib_path, entry.metal_vertex_entry, entry.metal_fragment_entry, raster_desc);
}

shader_hot_reload_create_compute_pipeline_for_entry :: (reload: *Shader_Hot_Reload, entry_id: string) -> Gpu_Pipeline {
    if !reload return 0;
    entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, entry_id);
    if !entry {
        log_missing_entry_context(reload, entry_id, "compute");
        shader_hot_reload_set_error(reload, tprint("% missing compute entry id=%", reload.log_prefix, entry_id));
        return 0;
    }
    return shader_hot_reload_create_compute_pipeline_for_manifest_entry(reload, entry);
}

shader_hot_reload_create_compute_pipeline_for_manifest_entry :: (reload: *Shader_Hot_Reload, entry: *SRM.Shader_Reload_Manifest_Entry) -> Gpu_Pipeline {
    if !reload || !entry return 0;
    metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
    if !found {
        shader_hot_reload_set_error(reload, tprint("% missing metallib for compute entry=% request=%", reload.log_prefix, entry.entry_id, entry.request_name));
        return 0;
    }
    if entry.metal_compute_entry.count == 0 {
        shader_hot_reload_set_error(reload, tprint("% missing metal compute entry name for id=%", reload.log_prefix, entry.entry_id));
        return 0;
    }
    use_root_pointer_struct := entry.metal_compute_binding_mode == "ROOT_POINTER_STRUCT";
    return gpu_create_compute_pipeline_from_metallib(metallib_path, entry.metal_compute_entry, use_root_pointer_struct);
}

shader_hot_reload_log_manifest_state :: (reload: *Shader_Hot_Reload, reason: string, ids_csv: string = "") {
    if !reload return;
    using watcher := reload.watcher;
    log_error("% %: loaded=% manifest=% entries=% declared=% changed_ids=% app=% generated_dir=%",
        reload.log_prefix,
        reason,
        watcher.manifest.loaded,
        watcher.manifest.source_path,
        watcher.manifest.entries.count,
        watcher.manifest.declared_entry_count,
        ids_csv,
        watcher.app_source_file,
        watcher.paths.generated_dir);
}

log_missing_entry_context :: (reload: *Shader_Hot_Reload, requested_entry_id: string, kind: string) {
    if !reload return;
    shader_hot_reload_log_manifest_state(reload, tprint("missing % entry", kind), reload.watcher.last_changed_entry_ids_csv);

    MAX_DUMP_ENTRIES :: 12;
    if reload.watcher.manifest.entries.count == 0 {
        log_error("% manifest has zero entries while requesting % id=%", reload.log_prefix, kind, requested_entry_id);
        return;
    }

    tail := shader_hot_reload_entry_id_tail_after_target(requested_entry_id);
    if tail.count != 0 {
        log_error("% requested % id tail=%", reload.log_prefix, kind, tail);
    }

    dumped: s64 = 0;
    matched_tail: s64 = 0;
    for reload.watcher.manifest.entries {
        if tail.count != 0 {
            entry_tail := shader_hot_reload_entry_id_tail_after_target(it.entry_id);
            if entry_tail == tail {
                matched_tail += 1;
                log_error("% candidate same-tail id=% target=% request=%", reload.log_prefix, it.entry_id, it.target, it.request_name);
            }
        }

        if dumped < MAX_DUMP_ENTRIES {
            log_error("% manifest[%] id=% target=% kind=% stage=% request=%",
                reload.log_prefix, dumped, it.entry_id, it.target, it.shader_kind, it.stage, it.request_name);
            dumped += 1;
        }
    }

    if tail.count != 0 && matched_tail == 0 {
        log_error("% no manifest entries matched requested tail=%", reload.log_prefix, tail);
    }
    if reload.watcher.manifest.entries.count > MAX_DUMP_ENTRIES {
        log_error("% manifest dump truncated to %/% entries", reload.log_prefix, MAX_DUMP_ENTRIES, reload.watcher.manifest.entries.count);
    }
}

shader_hot_reload_entry_id_tail_after_target :: (entry_id: string) -> string {
    if entry_id.count == 0 return "";
    pipe_count: s64 = 0;
    for i: 0..entry_id.count-1 {
        if entry_id[i] != #char "|" continue;
        pipe_count += 1;
        if pipe_count == 2 {
            if i + 1 >= entry_id.count return "";
            return .{ count = entry_id.count - (i + 1), data = entry_id.data + i + 1 };
        }
    }
    return "";
}

#import "Basic";
#import "Compiler";
#import "sgpu";
#import "Thread";
String :: #import "String";
Process :: #import "Process";
JTS :: #import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
