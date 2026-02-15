SRM :: #import,file "shader_reload_manifest.jai";

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
    worker_thread: TH.Thread;
    worker_wake: TH.Semaphore;
    worker_mutex: TH.Mutex;
    worker_should_exit: bool;
    worker_has_pending: bool;
    worker_pending_ids_csv: string;
    worker_build_in_flight: bool;
    worker_has_completed: bool;
    worker_completed_ok: bool;
    worker_completed_ids_csv: string;
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

shader_hot_reload_register_compute_pipeline :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline) {
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.compute_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
    });
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
        has_completed := shader_hot_reload_take_background_completion(reload, *completed_ok, *completed_ids_csv);
        if !has_completed return false, true, true;

        reload.last_event_frame = frame_num;
        shader_hot_reload_assign_string(*reload.watcher.last_changed_entry_ids_csv, completed_ids_csv);
        if completed_ids_csv.count != 0 free(completed_ids_csv);
        if !completed_ok {
            reload.last_result = .BUILD_FAILED;
            return true, false, false;
        }

        _ = SRM.shader_reload_manifest_load_auto(*reload.watcher.manifest);
        SRM.shader_reload_watcher_refresh_baseline(*reload.watcher);

        apply_ok := shader_hot_reload_apply_registered_pipelines(reload);
        if apply_ok reload.last_result = .SWAP_OK;
        else reload.last_result = .SWAP_PARTIAL;
        return true, apply_ok, true;
    }

    did_rebuild, build_ok := SRM.shader_reload_watcher_poll_and_rebuild(*reload.watcher, frame_num);
    if !did_rebuild return false, true, true;
    reload.last_event_frame = frame_num;
    if !build_ok {
        reload.last_result = .BUILD_FAILED;
        return true, false, false;
    }
    apply_ok := shader_hot_reload_apply_registered_pipelines(reload);
    if apply_ok reload.last_result = .SWAP_OK;
    else reload.last_result = .SWAP_PARTIAL;
    return true, apply_ok, true;
}

shader_hot_reload_status_line :: (reload: *Shader_Hot_Reload, max_ids_chars: s64 = 72) -> string {
    if !reload.enabled return "shader_reload=off";

    ids := reload.watcher.last_changed_entry_ids_csv;
    ids_short := ids;
    if max_ids_chars > 0 && ids_short.count > max_ids_chars {
        ids_short.count = max_ids_chars;
        ids_short = tprint("%...", ids_short);
    }

    result_text := "idle";
    if reload.last_result == .BUILD_QUEUED result_text = "queued";
    else if reload.last_result == .BUILD_RUNNING result_text = "building";
    else if reload.last_result == .BUILD_FAILED result_text = "build_failed";
    else if reload.last_result == .SWAP_PARTIAL result_text = "swap_partial";
    else if reload.last_result == .SWAP_OK result_text = "ok";

    if reload.last_event_frame < 0 return tprint("shader_reload=on status=%", result_text);
    if ids_short.count == 0 return tprint("shader_reload=on status=% frame=%", result_text, reload.last_event_frame);
    return tprint("shader_reload=on status=% frame=% ids=%", result_text, reload.last_event_frame, ids_short);
}

#scope_file

shader_hot_reload_apply_registered_pipelines :: (reload: *Shader_Hot_Reload) -> bool {
    ok := true;

    for reload.graphics_targets {
        entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing graphics entry id=%", reload.log_prefix, it.entry_id);
            ok = false;
            continue;
        }

        source_path, found := SRM.shader_reload_manifest_find_entry_source_auto(entry);
        if !found {
            log_error("% missing graphics source request=%", reload.log_prefix, entry.request_name);
            ok = false;
            continue;
        }

        source, read_ok := File.read_entire_file(source_path);
        if !read_ok || source.count == 0 {
            log_error("% failed reading graphics source path=%", reload.log_prefix, source_path);
            ok = false;
            continue;
        }

        new_pipeline := gpu_create_graphics_pipeline(cast([]u8) source, it.raster_desc);
        if new_pipeline == 0 {
            log_error("% graphics pipeline recreation failed path=%", reload.log_prefix, source_path);
            ok = false;
            continue;
        }

        old_pipeline := it.pipeline.*;
        it.pipeline.* = new_pipeline;
        if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    }

    for reload.compute_targets {
        entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing compute entry id=%", reload.log_prefix, it.entry_id);
            ok = false;
            continue;
        }

        source_path, found := SRM.shader_reload_manifest_find_entry_source_auto(entry);
        if !found {
            log_error("% missing compute source request=%", reload.log_prefix, entry.request_name);
            ok = false;
            continue;
        }

        source, read_ok := File.read_entire_file(source_path);
        if !read_ok || source.count == 0 {
            log_error("% failed reading compute source path=%", reload.log_prefix, source_path);
            ok = false;
            continue;
        }

        new_pipeline := gpu_create_compute_pipeline(cast([]u8) source);
        if new_pipeline == 0 {
            log_error("% compute pipeline recreation failed path=%", reload.log_prefix, source_path);
            ok = false;
            continue;
        }

        old_pipeline := it.pipeline.*;
        it.pipeline.* = new_pipeline;
        if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    }

    if ok log("% swapped pipelines for ids=%", reload.log_prefix, reload.watcher.last_changed_entry_ids_csv);
    return ok;
}

shader_hot_reload_start_worker_thread :: (reload: *Shader_Hot_Reload) {
    TH.init(*reload.worker_wake, 0);
    TH.init(*reload.worker_mutex, "shader_hot_reload");
    ok := TH.thread_init(*reload.worker_thread, shader_hot_reload_worker_proc);
    if !ok {
        log_error("% failed to start worker thread; using synchronous reload path.", reload.log_prefix);
        reload.worker_started = false;
        reload.use_background_thread = false;
        return;
    }
    reload.worker_thread.data = reload;
    TH.thread_start(*reload.worker_thread);
    reload.worker_started = true;
}

shader_hot_reload_queue_background_build :: (reload: *Shader_Hot_Reload, changed_ids_csv: string) {
    if !reload.worker_started return;
    TH.lock(*reload.worker_mutex);
    defer TH.unlock(*reload.worker_mutex);

    if reload.worker_build_in_flight {
        reload.last_result = .BUILD_RUNNING;
    } else {
        reload.last_result = .BUILD_QUEUED;
    }
    shader_hot_reload_assign_string(*reload.worker_pending_ids_csv, changed_ids_csv);
    reload.worker_has_pending = true;
    TH.signal(*reload.worker_wake);
}

shader_hot_reload_take_background_completion :: (reload: *Shader_Hot_Reload, completed_ok: *bool, completed_ids_csv: *string) -> bool {
    if !reload.worker_started return false;
    TH.lock(*reload.worker_mutex);
    defer TH.unlock(*reload.worker_mutex);

    if !reload.worker_has_completed return false;
    reload.worker_has_completed = false;
    completed_ok.* = reload.worker_completed_ok;
    completed_ids_csv.* = reload.worker_completed_ids_csv;
    reload.worker_completed_ids_csv = "";
    return true;
}

shader_hot_reload_worker_proc :: (thread: *TH.Thread) -> s64 {
    reload := cast(*Shader_Hot_Reload) thread.data;
    if !reload return 0;

    while true {
        _ = TH.wait_for(*reload.worker_wake);

        ids_csv: string;
        TH.lock(*reload.worker_mutex);
        if reload.worker_should_exit {
            TH.unlock(*reload.worker_mutex);
            break;
        }
        if !reload.worker_has_pending {
            TH.unlock(*reload.worker_mutex);
            continue;
        }
        ids_csv = reload.worker_pending_ids_csv;
        reload.worker_pending_ids_csv = "";
        reload.worker_has_pending = false;
        reload.worker_build_in_flight = true;
        TH.unlock(*reload.worker_mutex);

        build_ok := SRM.shader_reload_build_entry_ids(reload.watcher.app_source_file, ids_csv);

        TH.lock(*reload.worker_mutex);
        reload.worker_build_in_flight = false;
        reload.worker_completed_ok = build_ok;
        shader_hot_reload_assign_string(*reload.worker_completed_ids_csv, ids_csv);
        reload.worker_has_completed = true;
        TH.unlock(*reload.worker_mutex);
        if ids_csv.count != 0 free(ids_csv);
    }

    return 0;
}

shader_hot_reload_assign_string :: (dst: *string, src: string) {
    if dst.*.count != 0 {
        free(dst.*);
        dst.* = "";
    }
    if src.count != 0 dst.* = copy_string(src);
}

#import "Basic";
#import "sgpu";
File :: #import "File";
TH :: #import "Thread";
