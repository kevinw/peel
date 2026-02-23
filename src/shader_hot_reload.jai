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

shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id :: (reload: *Shader_Hot_Reload, entry_id: string, pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc) -> bool {
    if entry_id.count == 0 || !pipeline || source.count == 0 return false;

    new_pipeline := gpu_create_graphics_pipeline(source, raster_desc);
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
    if entry_id.count == 0 || !pipeline || source.count == 0 return false;

    new_pipeline := gpu_create_compute_pipeline(source);
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
        has_completed := shader_hot_reload_take_background_completion(reload, *completed_ok, *completed_ids_csv);
        if !has_completed return false, true, true;

        reload.last_event_frame = frame_num;
        assign_string(*reload.watcher.last_changed_entry_ids_csv, completed_ids_csv);
        if completed_ids_csv.count != 0 free(completed_ids_csv);
        if !completed_ok {
            reload.last_result = .BUILD_FAILED;
            return true, false, false;
        }

        _ = SRM.shader_reload_manifest_load_with_context(*reload.watcher.manifest, *reload.watcher.paths);
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

#scope_file

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

    for graphics_targets {
        entry := SRM.shader_reload_manifest_find_entry(*watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing graphics entry id=%", log_prefix, it.entry_id);
            ok = false;
            continue;
        }

        source_path, found := SRM.shader_reload_manifest_find_entry_source_for_manifest(*watcher.manifest, entry, *reload.watcher.paths);
        if !found {
            log_error("% missing graphics source request=%", log_prefix, entry.request_name);
            ok = false;
            continue;
        }

        source, read_ok := File.read_entire_file(source_path);
        if !read_ok || source.count == 0 {
            log_error("% failed reading graphics source path=%", log_prefix, source_path);
            ok = false;
            continue;
        }

        new_pipeline := gpu_create_graphics_pipeline(cast([]u8) source, it.raster_desc);
        if new_pipeline == 0 {
            log_error("% graphics pipeline recreation failed path=%", log_prefix, source_path);
            ok = false;
            continue;
        }

        old_pipeline := it.pipeline.*;
        it.pipeline.* = new_pipeline;
        if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    }

    for compute_targets {
        entry := SRM.shader_reload_manifest_find_entry(*watcher.manifest, it.entry_id);
        if !entry {
            log_error("% missing compute entry id=%", log_prefix, it.entry_id);
            ok = false;
            continue;
        }

        source_path, found := SRM.shader_reload_manifest_find_entry_source_for_manifest(*watcher.manifest, entry, *watcher.paths);
        if !found {
            log_error("% missing compute source request=%", log_prefix, entry.request_name);
            ok = false;
            continue;
        }

        source, read_ok := File.read_entire_file(source_path);
        if !read_ok || source.count == 0 {
            log_error("% failed reading compute source path=%", log_prefix, source_path);
            ok = false;
            continue;
        }

        new_pipeline := gpu_create_compute_pipeline(cast([]u8) source);
        if new_pipeline == 0 {
            log_error("% compute pipeline recreation failed path=%", log_prefix, source_path);
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

shader_hot_reload_take_background_completion :: (using reload: *Shader_Hot_Reload, completed_ok: *bool, completed_ids_csv: *string) -> bool {
    if !worker_started return false;
    lock(*worker_mutex);
    defer unlock(*worker_mutex);

    if !worker_has_completed return false;
    worker_has_completed = false;
    completed_ok.* = worker_completed_ok;
    completed_ids_csv.* = worker_completed_ids_csv;
    worker_completed_ids_csv = "";
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

        build_ok := SRM.shader_reload_build_entry_ids_with_context(*watcher.paths, watcher.app_source_file, ids_csv);

        lock(*worker_mutex);
        worker_build_in_flight = false;
        worker_completed_ok = build_ok;
        assign_string(*worker_completed_ids_csv, ids_csv);
        worker_has_completed = true;
        unlock(*worker_mutex);
        if ids_csv.count != 0 free(ids_csv);
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

#import "Basic";
#import "Compiler";
#import "sgpu";
File :: #import "File";
#import "Thread";
JTS :: #import "Jai-Shader-Transpiler";
