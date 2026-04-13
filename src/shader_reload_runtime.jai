shader_hot_reload_init_auto :: (app_source_file: string, poll_every_frames: s64 = 15, log_prefix: string = "SHADER_RELOAD", enabled_by_default: bool = false, use_background_thread: bool = true) -> bool {
    reload := shader_hot_reload_current_ctx();
    reload.* = .{};
    reload.log_prefix = copy_string(log_prefix);
    reload.use_background_thread = use_background_thread;
    reload.last_event_frame = -1;
    reload.last_result = .NONE;
    reload.last_error_message = "";
    reload.show_error_window = false;
    reload.reload_generation = 1;
    reload.enabled = SRM.shader_reload_watcher_init_auto(*reload.watcher, app_source_file, poll_every_frames, enabled_by_default);
    if reload.enabled && reload.use_background_thread {
        shader_hot_reload_start_worker_thread(reload);
    }
    return reload.enabled;
}

shader_hot_reload_register_graphics_pipeline :: (entry_id: string, pipeline: *Gpu_Pipeline, raster_desc: Gpu_Raster_Desc) {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.graphics_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
        raster_desc = raster_desc,
    });
}

shader_hot_reload_register_graphics_pipeline_with_function_constants :: (entry_id: string, pipeline: *Gpu_Pipeline, raster_desc: Gpu_Raster_Desc, constants: *$T) {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return;

    constants_bytes, info_storage := shader_hot_reload_capture_function_constant_state(constants);
    array_add(*reload.graphics_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
        raster_desc = raster_desc,
        default_function_constants_bytes = constants_bytes,
        function_constant_info = info_storage,
    });
}

shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id :: (entry_id: string, pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc) -> bool {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return false;

    new_pipeline := shader_hot_reload_create_graphics_pipeline_for_entry(reload, entry_id, raster_desc);
    if new_pipeline == 0 && source.count > 0 {
        log_error("% falling back to source graphics compile for id=%", reload.log_prefix, entry_id);
        new_pipeline = gpu_create_graphics_pipeline(source, raster_desc);
    }

    assert(new_pipeline != 0, "Graphics pipeline creation failed.");
    if new_pipeline == 0 return false;

    shader_hot_reload_swap_pipeline_handle(pipeline, new_pipeline);
    shader_hot_reload_register_graphics_pipeline(entry_id, pipeline, raster_desc);
    return true;
}

shader_hot_reload_create_and_register_graphics_pipeline :: (pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc, target: JTS.Transpiled_Target, $vertex_shader: $VERTEX_SHADER, $fragment_shader: $FRAGMENT_SHADER, call: Code = #caller_code) -> bool #expand {
    vertex_name   := #run proc_name_from_caller_arg(call, 4);
    fragment_name := #run proc_name_from_caller_arg(call, 5);
    target_name   := tprint("%", target);
    entry_id      := tprint("pair|%|%|%", target_name, vertex_name, fragment_name);
    return shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id(entry_id, pipeline, source, raster_desc);
}

shader_hot_reload_register_compute_pipeline :: (entry_id: string, pipeline: *Gpu_Pipeline) {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.compute_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
    });
}

shader_hot_reload_register_mesh_pipeline :: (entry_id: string, pipeline: *Gpu_Pipeline, desc: Shader_Hot_Reload_Mesh_Desc) {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return;
    array_add(*reload.mesh_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
        desc = desc,
    });
}

shader_hot_reload_register_mesh_pipeline_with_function_constants :: (entry_id: string, pipeline: *Gpu_Pipeline, desc: Shader_Hot_Reload_Mesh_Desc, constants: *$T) {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return;

    constants_bytes, info_storage := shader_hot_reload_capture_function_constant_state(constants);
    array_add(*reload.mesh_targets, .{
        entry_id = copy_string(entry_id),
        pipeline = pipeline,
        desc = desc,
        default_function_constants_bytes = constants_bytes,
        function_constant_info = info_storage,
    });
}

shader_hot_reload_create_and_register_compute_pipeline_with_entry_id :: (entry_id: string, pipeline: *Gpu_Pipeline, source: []u8) -> bool {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return false;

    new_pipeline := shader_hot_reload_create_compute_pipeline_for_entry(reload, entry_id);
    if new_pipeline == 0 && source.count > 0 {
        log_error("% falling back to source compute compile for id=%", reload.log_prefix, entry_id);
        new_pipeline = gpu_create_compute_pipeline(source);
    }
    assert(new_pipeline != 0, "Compute pipeline creation failed.");
    if new_pipeline == 0 return false;

    shader_hot_reload_swap_pipeline_handle(pipeline, new_pipeline);
    shader_hot_reload_register_compute_pipeline(entry_id, pipeline);
    return true;
}

shader_hot_reload_create_and_register_compute_pipeline :: (pipeline: *Gpu_Pipeline, source: []u8, target: JTS.Transpiled_Target, $compute_shader: $COMPUTE_SHADER, call: Code = #caller_code) -> bool #expand {
    compute_name := #run proc_name_from_caller_arg(call, 3);
    target_name := tprint("%", target);
    entry_id := tprint("single|%|compute|%", target_name, compute_name);
    return shader_hot_reload_create_and_register_compute_pipeline_with_entry_id(entry_id, pipeline, source);
}

shader_hot_reload_mesh_desc_from_gpu_desc :: (desc: Gpu_Mesh_Pipeline_Desc) -> Shader_Hot_Reload_Mesh_Desc {
    return .{
        raster_desc = desc.raster_desc,
        task_threads = desc.task_threads,
        mesh_threads = desc.mesh_threads,
        payload_memory_length = desc.payload_memory_length,
        max_total_threadgroups_per_mesh_grid = desc.max_total_threadgroups_per_mesh_grid,
    };
}

shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id :: (entry_id: string, pipeline: *Gpu_Pipeline, shader: JTS.Transpiled_Mesh_Pipeline, desc: Gpu_Mesh_Pipeline_Desc) -> bool {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return false;

    final_desc := desc;
    final_desc.task_shader = cast([]u8) shader.task_source;
    final_desc.mesh_shader = cast([]u8) shader.mesh_source;
    final_desc.pixel_shader = cast([]u8) shader.pixel_source;
    final_desc.payload_memory_length = cast(u32) shader.payload_memory_length;

    new_pipeline := shader_hot_reload_create_mesh_pipeline_for_entry(reload, entry_id, shader_hot_reload_mesh_desc_from_gpu_desc(final_desc));
    if new_pipeline == 0 && (final_desc.mesh_shader.count > 0 && final_desc.pixel_shader.count > 0) {
        log_error("% falling back to source mesh compile for id=%", reload.log_prefix, entry_id);
        new_pipeline = gpu_create_mesh_pipeline(final_desc);
    }

    assert(new_pipeline != 0, "Mesh pipeline creation failed.");
    if new_pipeline == 0 return false;

    shader_hot_reload_swap_pipeline_handle(pipeline, new_pipeline);
    shader_hot_reload_register_mesh_pipeline(entry_id, pipeline, shader_hot_reload_mesh_desc_from_gpu_desc(final_desc));
    return true;
}

shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id :: (entry_id: string, pipeline: *Gpu_Pipeline, shader: JTS.Transpiled_Mesh_Pipeline, desc: Gpu_Mesh_Pipeline_Desc, constants: *$T) -> bool {
    reload := shader_hot_reload_current_ctx();
    if entry_id.count == 0 || !pipeline return false;

    final_desc := desc;
    final_desc.task_shader = cast([]u8) shader.task_source;
    final_desc.mesh_shader = cast([]u8) shader.mesh_source;
    final_desc.pixel_shader = cast([]u8) shader.pixel_source;
    final_desc.payload_memory_length = cast(u32) shader.payload_memory_length;

    new_pipeline: Gpu_Pipeline;
    entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, entry_id);
    if entry {
        metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
        if found {
            constants_bytes, info_storage := shader_hot_reload_capture_function_constant_state(constants);
            defer free(constants_bytes.data);
            defer {
                for info_storage {
                    if it.name.count != 0 free(it.name.data);
                }
                if info_storage.count != 0 free(info_storage.data);
            }

            task_constants: *MTLFunctionConstantValues;
            if entry.metal_task_entry.count != 0 {
                task_constants = shader_hot_reload_build_function_constant_values_for_metallib_function(
                    metallib_path, entry.metal_task_entry, constants_bytes, info_storage);
            }
            mesh_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
                metallib_path, entry.metal_mesh_entry, constants_bytes, info_storage);
            fragment_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
                metallib_path, entry.metal_fragment_entry, constants_bytes, info_storage);
            defer if task_constants != null release(task_constants);
            defer if mesh_constants != null release(mesh_constants);
            defer if fragment_constants != null release(fragment_constants);

            new_pipeline = gpu_create_mesh_pipeline_from_metallib_with_function_constants(
                metallib_path, entry.metal_task_entry, entry.metal_mesh_entry, entry.metal_fragment_entry,
                final_desc, task_constants, mesh_constants, fragment_constants);
        }
    }

    if new_pipeline == 0 {
        log_error("% falling back to source mesh compile with function constants for id=%", reload.log_prefix, entry_id);
        new_pipeline = shader_hot_reload_mesh_pipeline_from_source_with_function_constants(shader, desc, constants);
    }

    if new_pipeline == 0 {
        shader_hot_reload_set_error(reload, tprint("% mesh pipeline creation with function constants failed for id=%", reload.log_prefix, entry_id));
    }

    assert(new_pipeline != 0, "Mesh pipeline creation with function constants failed.");
    if new_pipeline == 0 return false;

    shader_hot_reload_swap_pipeline_handle(pipeline, new_pipeline);
    shader_hot_reload_register_mesh_pipeline_with_function_constants(entry_id, pipeline, shader_hot_reload_mesh_desc_from_gpu_desc(final_desc), constants);
    return true;
}

shader_hot_reload_tick :: (frame_num: s64) -> (did_rebuild: bool, swapped_all: bool, build_ok: bool) {
    reload := shader_hot_reload_current_ctx();
    if !reload.enabled return false, true, true;

    if reload.worker_started {
        changed_ids_csv, has_changes := SRM.shader_reload_watcher_poll_changed_entry_ids_csv(*reload.watcher, frame_num);
        if has_changes {
            shader_hot_reload_queue_background_build(reload, changed_ids_csv);
        }

        completed_ok: bool;
        completed_ids_csv: string;
        completed_error: string;
        has_completed := take_background_completion(reload, *completed_ok, *completed_ids_csv, *completed_error);
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
        reload.reload_generation += 1;
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
    reload.reload_generation += 1;
    if apply_ok {
        reload.last_result = .SWAP_OK;
        shader_hot_reload_clear_error(reload);
    } else {
        reload.last_result = .SWAP_PARTIAL;
    }
    return true, apply_ok, true;
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

        new_pipeline := shader_hot_reload_create_graphics_pipeline_for_manifest_entry(reload, entry, it.raster_desc, *it);
        if new_pipeline == 0 {
            shader_hot_reload_set_error(reload, tprint("% graphics pipeline recreation failed entry=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        shader_hot_reload_swap_pipeline_handle(it.pipeline, new_pipeline);
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

        shader_hot_reload_swap_pipeline_handle(it.pipeline, new_pipeline);
    }

    for mesh_targets {
        if changed_ids_csv.count != 0 && !shader_hot_reload_ids_csv_contains(changed_ids_csv, it.entry_id) continue;
        new_pipeline := shader_hot_reload_create_mesh_pipeline_for_entry(reload, it.entry_id, it.desc);
        if new_pipeline == 0 {
            shader_hot_reload_set_error(reload, tprint("% mesh pipeline recreation failed entry=%", log_prefix, it.entry_id));
            ok = false;
            continue;
        }

        shader_hot_reload_swap_pipeline_handle(it.pipeline, new_pipeline);
    }

    if ok log("% swapped pipelines for ids=%", log_prefix, watcher.last_changed_entry_ids_csv);
    return ok;
}

shader_hot_reload_reset_function_constant_variants :: (base: *Shader_Base) {
    if !base return;
    for base.function_constant_variants {
        if it.pipeline != 0 gpu_free_pipeline(it.pipeline);
        if it.constants_bytes.count != 0 free(it.constants_bytes.data);
    }
    base.function_constant_variants.count = 0;
    reload := shader_hot_reload_current_ctx();
    base.function_constant_variant_generation = reload.reload_generation;
}

shader_hot_reload_ensure_function_constant_variant_generation :: (base: *Shader_Base) {
    if !base return;
    reload := shader_hot_reload_current_ctx();
    if base.function_constant_variant_generation == reload.reload_generation return;
    shader_hot_reload_reset_function_constant_variants(base);
}

is_dynamic :: (using raster_desc: Gpu_Raster_Desc) -> bool {
    return color_targets.count == 0;
}

shader_hot_reload_attachment_layout_from_raster_desc :: (raster_desc: Gpu_Raster_Desc) -> Shader_Attachment_Layout_Key {
    using key: Shader_Attachment_Layout_Key;
    sample_count = raster_desc.sample_count;
    color_target_count = cast(u8) min(raster_desc.color_targets.count, 8);
    depth_format = raster_desc.depth_format;
    stencil_format = raster_desc.stencil_format;
    for i: 0..cast(s64) key.color_target_count-1 {
        color_formats[i] = raster_desc.color_targets[i].format;
    }
    return key;
}

shader_hot_reload_attachment_layout_equals :: (a: Shader_Attachment_Layout_Key, b: Shader_Attachment_Layout_Key) -> bool {
    if a.sample_count != b.sample_count return false;
    if a.color_target_count != b.color_target_count return false;
    if a.depth_format != b.depth_format return false;
    if a.stencil_format != b.stencil_format return false;
    for i: 0..7 {
        if a.color_formats[i] != b.color_formats[i] return false;
    }
    return true;
}

shader_hot_reload_hash_attachment_layout :: (key: Shader_Attachment_Layout_Key) -> u64 {
    FNV_OFFSET :: cast(u64) 14695981039346656037;
    FNV_PRIME  :: cast(u64) 1099511628211;

    mix_byte :: (hash: u64, value: u8) -> u64 {
        return (hash ^ cast(u64) value) * FNV_PRIME;
    }

    mix_u32 :: (hash: u64, value: u32) -> u64 {
        hash = mix_byte(hash, cast(u8) ( value        & 0xFF));
        hash = mix_byte(hash, cast(u8) ((value >>  8) & 0xFF));
        hash = mix_byte(hash, cast(u8) ((value >> 16) & 0xFF));
        hash = mix_byte(hash, cast(u8) ((value >> 24) & 0xFF));
        return hash;
    }

    hash := FNV_OFFSET;
    hash = mix_byte(hash, key.sample_count);
    hash = mix_byte(hash, key.color_target_count);
    hash = mix_u32(hash, cast(u32) key.depth_format);
    hash = mix_u32(hash, cast(u32) key.stencil_format);
    for key.color_formats {
        hash = mix_u32(hash, cast(u32) it);
    }
    return hash;
}

shader_hot_reload_hash_graphics_variant_key :: (layout: Shader_Attachment_Layout_Key, constants_bytes: []u8) -> u64 {
    hash := shader_hot_reload_hash_attachment_layout(layout);
    if constants_bytes.count != 0 {
        constants_hash := Hash.fnv1a_hash(constants_bytes.data, constants_bytes.count);
        hash = hash ~ constants_hash;
    }
    return hash;
}

resolve_dynamic_raster_desc :: (logical_raster_desc: Gpu_Raster_Desc, pass_desc: Gpu_Render_Pass_Desc, debug_label := "") -> (Gpu_Raster_Desc, bool) {
    resolved := logical_raster_desc;
    if !is_dynamic(logical_raster_desc) {
        return resolved, true;
    }

    push_allocator(cpu_allocator);
    assert(pass_desc.color_targets.count > 0, "resolve_dynamic_raster_desc: no color targets in pass_desc");
    color_targets := NewArray(pass_desc.color_targets.count, Color_Target);
    for pass_desc.color_targets {
        if it.view == 0 return .{}, false;
        format, ok := gpu_texture_view_format(it.view);
        if !ok || format == .UNDEFINED return .{}, false;
        color_targets[it_index] = .{format = format};
    }

    resolved.color_targets = color_targets;

    if resolved.depth_format == .UNDEFINED && pass_desc.depth_target.view != 0 {
        depth_format, ok := gpu_texture_view_format(pass_desc.depth_target.view);
        if !ok || depth_format == .UNDEFINED return .{}, false;
        resolved.depth_format = depth_format;
    }
    if resolved.stencil_format == .UNDEFINED && pass_desc.stencil_target.view != 0 {
        stencil_format, ok := gpu_texture_view_format(pass_desc.stencil_target.view);
        if !ok || stencil_format == .UNDEFINED return .{}, false;
        resolved.stencil_format = stencil_format;
    }

    return resolved, true;
}

shader_hot_reload_release_dynamic_raster_desc :: (logical_raster_desc: Gpu_Raster_Desc, resolved_raster_desc: *Gpu_Raster_Desc) {
    if resolved_raster_desc == null return;
    if !is_dynamic(logical_raster_desc) return;
    if resolved_raster_desc.color_targets.count != 0 && resolved_raster_desc.color_targets.data != null {
        free(resolved_raster_desc.color_targets.data,, allocator = cpu_allocator);
    }
    resolved_raster_desc.color_targets = .{};
}

shader_hot_reload_swap_pipeline_handle :: (pipeline: *Gpu_Pipeline, new_pipeline: Gpu_Pipeline) -> bool {
    if !pipeline || new_pipeline == 0 return false;
    old_pipeline := pipeline.*;
    pipeline.* = new_pipeline;
    if old_pipeline != 0 gpu_free_pipeline(old_pipeline);
    return true;
}

shader_hot_reload_log_error_if_not_null :: (error: *NSError, description: string = "") -> bool {
    if error == null return false;

    err_str := to_string(NSError.localizedDescription(error));
    if description.count != 0 {
        log_error("%: %", description, err_str);
    } else {
        log_error("%", err_str);
    }

    return true;
}

shader_hot_reload_new_library_from_source_or_return_0 :: (source: []u8, debug_name: string) -> *MTLLibrary {
    compile_options := objc_new_defer_release(MTLCompileOptions);
    MTLCompileOptions.setLanguageVersion(compile_options, ._3_2);
    MTLCompileOptions.setEnableLogging(compile_options, ifx SGPU_ENABLE_SHADER_LOGGING then YES else NO);

    error: *NSError;
    library := MTLDevice.newLibraryWithSource(mtl_device, to_temp_nsstring(cast(string)source), compile_options, *error);
    if shader_hot_reload_log_error_if_not_null(error) {
        log_error("Failed to compile %.", debug_name);
        return null;
    }
    if library == null {
        log_error("Failed to create % library.", debug_name);
        return null;
    }
    return library;
}

shader_hot_reload_new_library_from_file_or_return_0 :: (path: string, debug_name: string) -> *MTLLibrary {
    error: *NSError;
    library := MTLDevice.newLibraryWithFile(mtl_device, to_temp_nsstring(path), *error);
    if shader_hot_reload_log_error_if_not_null(error) {
        log_error("Failed to load % from file '%'.", debug_name, path);
        return null;
    }
    if library == null {
        log_error("Failed to create % from file '%'.", debug_name, path);
        return null;
    }
    return library;
}

shader_hot_reload_get_function_from_library :: (library: *MTLLibrary, names: ..string) -> *MTLFunction {
    for name: names {
        fn := MTLLibrary.newFunctionWithName(library, to_temp_nsstring(name));
        if fn != null return fn;
    }
    return null;
}

shader_hot_reload_graphics_pipeline_from_source_with_function_constants :: (
    metal: []u8,
    raster_desc: Gpu_Raster_Desc,
    shader_meta: JTS.Shader_Meta,
    constants: *$T
) -> Gpu_Pipeline {
    auto_release_temp();
    library := shader_hot_reload_new_library_from_source_or_return_0(metal, "vertex+fragment shader");
    if library == null return 0;
    defer release(library);
    vertex_function_name := tprint("%_VertexMain", shader_meta.request_name);
    fragment_function_name := tprint("%_FragmentMain", shader_meta.request_name);
    vertex_function := shader_hot_reload_get_function_from_library(library, vertex_function_name);
    assert(vertex_function != null, "Failed to find vertex function '%' in graphics library.", vertex_function_name);
    defer release(vertex_function);

    fragment_function := shader_hot_reload_get_function_from_library(library, fragment_function_name);
    assert(fragment_function != null, "Failed to find fragment function '%' in graphics library.", fragment_function_name);
    defer release(fragment_function);

    vertex_constants   := shader_hot_reload_build_function_constant_values_for_function(vertex_function, constants);
    fragment_constants := shader_hot_reload_build_function_constant_values_for_function(fragment_function, constants);
    defer if vertex_constants != null release(vertex_constants);
    defer if fragment_constants != null release(fragment_constants);
    return _internal_gpu_create_graphics_pipeline_with_names_and_constants(
        library, library, raster_desc, vertex_function_name, fragment_function_name, vertex_constants, fragment_constants);
}

shader_hot_reload_mesh_pipeline_from_source_with_function_constants :: (
    shader: JTS.Transpiled_Mesh_Pipeline,
    desc: Gpu_Mesh_Pipeline_Desc,
    constants: *$T
) -> Gpu_Pipeline {
    auto_release_temp();
    mesh_library := shader_hot_reload_new_library_from_source_or_return_0(cast([]u8) shader.mesh_source, "mesh shader");
    if mesh_library == null return 0;
    defer release(mesh_library);

    pixel_library := shader_hot_reload_new_library_from_source_or_return_0(cast([]u8) shader.pixel_source, "fragment shader");
    if pixel_library == null return 0;
    defer release(pixel_library);

    task_library: *MTLLibrary = mesh_library;
    if shader.task_source.count != 0 && (shader.task_source.count != shader.mesh_source.count || shader.task_source.data != shader.mesh_source.data) {
        task_library = shader_hot_reload_new_library_from_source_or_return_0(cast([]u8) shader.task_source, "task shader");
        if task_library == null return 0;
    }
    defer if task_library != mesh_library {
        release(task_library);
    }

    mesh_function_name := tprint("%_MeshMain", shader.meta.request_name);
    fragment_function_name := tprint("%_FragmentMain", shader.meta.request_name);
    task_function_name := tprint("%_ObjectMain", shader.meta.request_name);

    mesh_function := shader_hot_reload_get_function_from_library(mesh_library, mesh_function_name, "MeshMain");
    assert(mesh_function != null, "Failed to find mesh function '%' in source mesh shader.", mesh_function_name);
    defer release(mesh_function);

    fragment_function := shader_hot_reload_get_function_from_library(pixel_library, fragment_function_name, "FragmentMain");
    assert(fragment_function != null, "Failed to find fragment function '%' in source fragment shader.", fragment_function_name);
    defer release(fragment_function);

    task_constants: *MTLFunctionConstantValues;
    if shader.task_source.count != 0 {
        object_function := shader_hot_reload_get_function_from_library(task_library, task_function_name, "ObjectMain");
        assert(object_function != null, "Failed to find task function '%' in source task shader.", task_function_name);
        defer release(object_function);
        task_constants = shader_hot_reload_build_function_constant_values_for_function(object_function, constants);
    }

    mesh_constants := shader_hot_reload_build_function_constant_values_for_function(mesh_function, constants);
    fragment_constants := shader_hot_reload_build_function_constant_values_for_function(fragment_function, constants);
    defer if task_constants != null release(task_constants);
    defer if mesh_constants != null release(mesh_constants);
    defer if fragment_constants != null release(fragment_constants);

    final_desc := desc;
    final_desc.task_shader = cast([]u8) shader.task_source;
    final_desc.mesh_shader = cast([]u8) shader.mesh_source;
    final_desc.pixel_shader = cast([]u8) shader.pixel_source;
    final_desc.payload_memory_length = cast(u32) shader.payload_memory_length;
    return gpu_create_mesh_pipeline_with_function_constants(final_desc, task_constants, mesh_constants, fragment_constants);
}

create_graphics_pipeline_with_function_constants :: (
    source: []u8,
    shader_meta: JTS.Shader_Meta,
    raster_desc: Gpu_Raster_Desc,
    constants: *$T
) -> Gpu_Pipeline {
    reload := shader_hot_reload_current_ctx();
    if reload != null && reload.enabled && shader_meta.entry_id.count != 0 {
        entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, shader_meta.entry_id);
        if entry != null {
            metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
            if found && entry.metal_vertex_entry.count != 0 && entry.metal_fragment_entry.count != 0 {
                library := shader_hot_reload_new_library_from_file_or_return_0(metallib_path, "graphics metallib");
                if library != null {
                    defer release(library);
                    vertex_function := shader_hot_reload_get_function_from_library(library, entry.metal_vertex_entry);
                    fragment_function := shader_hot_reload_get_function_from_library(library, entry.metal_fragment_entry);
                    if vertex_function != null && fragment_function != null {
                        defer release(vertex_function);
                        defer release(fragment_function);
                        vertex_constants := shader_hot_reload_build_function_constant_values_for_function(vertex_function, constants);
                        fragment_constants := shader_hot_reload_build_function_constant_values_for_function(fragment_function, constants);
                        defer if vertex_constants != null release(vertex_constants);
                        defer if fragment_constants != null release(fragment_constants);
                        return gpu_create_graphics_pipeline_from_metallib_with_function_constants(
                            metallib_path, entry.metal_vertex_entry, entry.metal_fragment_entry, raster_desc, vertex_constants, fragment_constants);
                    }
                    if vertex_function != null release(vertex_function);
                    if fragment_function != null release(fragment_function);
                }
            }
        }
    }

    if source.count == 0 return 0;
    return shader_hot_reload_graphics_pipeline_from_source_with_function_constants(source, raster_desc, shader_meta, constants);
}

create_mesh_pipeline_with_function_constants :: (
    shader: JTS.Transpiled_Mesh_Pipeline,
    desc: Gpu_Mesh_Pipeline_Desc,
    constants: *$T
) -> Gpu_Pipeline {
    reload := shader_hot_reload_current_ctx();
    if reload != null && reload.enabled && shader.meta.entry_id.count != 0 {
        entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, shader.meta.entry_id);
        if entry != null {
            metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
            if found && entry.metal_mesh_entry.count != 0 && entry.metal_fragment_entry.count != 0 {
                constants_bytes, info_storage := shader_hot_reload_capture_function_constant_state(constants);
                defer free(constants_bytes.data);
                defer {
                    for info_storage {
                        if it.name.count != 0 free(it.name.data);
                    }
                    if info_storage.count != 0 free(info_storage.data);
                }

                task_constants: *MTLFunctionConstantValues;
                if entry.metal_task_entry.count != 0 {
                    task_constants = shader_hot_reload_build_function_constant_values_for_metallib_function(
                        metallib_path, entry.metal_task_entry, constants_bytes, info_storage);
                }
                mesh_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
                    metallib_path, entry.metal_mesh_entry, constants_bytes, info_storage);
                fragment_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
                    metallib_path, entry.metal_fragment_entry, constants_bytes, info_storage);
                defer if task_constants != null release(task_constants);
                defer if mesh_constants != null release(mesh_constants);
                defer if fragment_constants != null release(fragment_constants);

                return gpu_create_mesh_pipeline_from_metallib_with_function_constants(
                    metallib_path, entry.metal_task_entry, entry.metal_mesh_entry, entry.metal_fragment_entry, desc,
                    task_constants, mesh_constants, fragment_constants);
            }
        }
    }

    return shader_hot_reload_mesh_pipeline_from_source_with_function_constants(shader, desc, constants);
}

shader_hot_reload_get_or_create_graphics_pipeline_variant :: (
    base: *Shader_Base,
    source: []u8,
    shader_meta: JTS.Shader_Meta,
    raster_desc: Gpu_Raster_Desc,
    constants: *$T
) -> Gpu_Pipeline {
    assert(base != null);
    shader_hot_reload_ensure_function_constant_variant_generation(base);

    constants_bytes: []u8 = .{count = size_of(T), data = cast(*u8) constants};
    attachment_layout := shader_hot_reload_attachment_layout_from_raster_desc(raster_desc);
    key_hash := shader_hot_reload_hash_graphics_variant_key(attachment_layout, constants_bytes);

    for base.function_constant_variants {
        if it.key_hash != key_hash continue;
        if !shader_hot_reload_attachment_layout_equals(it.attachment_layout, attachment_layout) continue;
        if shader_hot_reload_constants_equal(it.constants_bytes, constants_bytes) return it.pipeline;
    }

    new_pipeline := create_graphics_pipeline_with_function_constants(source, shader_meta, raster_desc, constants);

    assert(new_pipeline != 0, "Graphics pipeline creation with function constants failed for entry '%'.", shader_meta.entry_id);
    if new_pipeline == 0 return 0;

    stored_bytes := NewArray(size_of(T), u8);
    memcpy(stored_bytes.data, constants, stored_bytes.count);
    array_add(*base.function_constant_variants, .{
        key_hash = key_hash,
        constants_bytes = stored_bytes,
        attachment_layout = attachment_layout,
        pipeline = new_pipeline,
    });
    gpu_commit_residency();
    return new_pipeline;
}

shader_hot_reload_get_or_create_graphics_pipeline_variant_no_constants :: (
    base: *Shader_Base,
    source: []u8,
    shader_meta: JTS.Shader_Meta,
    raster_desc: Gpu_Raster_Desc
) -> Gpu_Pipeline {
    assert(base != null);
    shader_hot_reload_ensure_function_constant_variant_generation(base);

    attachment_layout := shader_hot_reload_attachment_layout_from_raster_desc(raster_desc);
    empty_constants: []u8;
    key_hash := shader_hot_reload_hash_graphics_variant_key(attachment_layout, empty_constants);

    for base.function_constant_variants {
        if it.key_hash != key_hash continue;
        if !shader_hot_reload_attachment_layout_equals(it.attachment_layout, attachment_layout) continue;
        if it.constants_bytes.count == 0 return it.pipeline;
    }

    reload := shader_hot_reload_current_ctx();
    new_pipeline: Gpu_Pipeline;
    if reload != null && reload.enabled && shader_meta.entry_id.count != 0 {
        entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, shader_meta.entry_id);
        if entry != null {
            new_pipeline = shader_hot_reload_create_graphics_pipeline_for_entry(reload, shader_meta.entry_id, raster_desc);
        }
    }
    if new_pipeline == 0 && source.count > 0 {
        new_pipeline = gpu_create_graphics_pipeline(source, raster_desc);
    }

    assert(new_pipeline != 0, "Graphics pipeline creation failed for entry '%'.", shader_meta.entry_id);
    if new_pipeline == 0 return 0;

    array_add(*base.function_constant_variants, .{
        key_hash = key_hash,
        attachment_layout = attachment_layout,
        pipeline = new_pipeline,
    });
    gpu_commit_residency();
    return new_pipeline;
}

shader_hot_reload_get_or_create_mesh_pipeline_variant :: (
    base: *Shader_Base,
    shader: JTS.Transpiled_Mesh_Pipeline,
    desc: Gpu_Mesh_Pipeline_Desc,
    constants: *$T
) -> Gpu_Pipeline {
    assert(base != null);
    shader_hot_reload_ensure_function_constant_variant_generation(base);

    constants_bytes: []u8 = .{count = size_of(T), data = cast(*u8) constants};
    attachment_layout := shader_hot_reload_attachment_layout_from_raster_desc(desc.raster_desc);
    key_hash := shader_hot_reload_hash_graphics_variant_key(attachment_layout, constants_bytes);

    for base.function_constant_variants {
        if it.key_hash != key_hash continue;
        if !shader_hot_reload_attachment_layout_equals(it.attachment_layout, attachment_layout) continue;
        if shader_hot_reload_constants_equal(it.constants_bytes, constants_bytes) return it.pipeline;
    }

    new_pipeline := create_mesh_pipeline_with_function_constants(shader, desc, constants);
    assert(new_pipeline != 0, "Mesh pipeline creation with function constants failed for entry '%'.", shader.meta.entry_id);
    if new_pipeline == 0 return 0;

    stored_bytes := NewArray(size_of(T), u8);
    memcpy(stored_bytes.data, constants, stored_bytes.count);
    array_add(*base.function_constant_variants, .{
        key_hash = key_hash,
        constants_bytes = stored_bytes,
        attachment_layout = attachment_layout,
        pipeline = new_pipeline,
    });
    gpu_commit_residency();
    return new_pipeline;
}

shader_hot_reload_get_or_create_mesh_pipeline_variant_no_constants :: (
    base: *Shader_Base,
    shader: JTS.Transpiled_Mesh_Pipeline,
    desc: Gpu_Mesh_Pipeline_Desc
) -> Gpu_Pipeline {
    assert(base != null);
    shader_hot_reload_ensure_function_constant_variant_generation(base);

    attachment_layout := shader_hot_reload_attachment_layout_from_raster_desc(desc.raster_desc);
    empty_constants: []u8;
    key_hash := shader_hot_reload_hash_graphics_variant_key(attachment_layout, empty_constants);

    for base.function_constant_variants {
        if it.key_hash != key_hash continue;
        if !shader_hot_reload_attachment_layout_equals(it.attachment_layout, attachment_layout) continue;
        if it.constants_bytes.count == 0 return it.pipeline;
    }

    reload := shader_hot_reload_current_ctx();
    new_pipeline := shader_hot_reload_create_mesh_pipeline_for_entry(reload, shader.meta.entry_id, shader_hot_reload_mesh_desc_from_gpu_desc(desc));
    if new_pipeline == 0 && (desc.mesh_shader.count > 0 && desc.pixel_shader.count > 0) {
        new_pipeline = gpu_create_mesh_pipeline(desc);
    }

    assert(new_pipeline != 0, "Mesh pipeline creation failed for entry '%'.", shader.meta.entry_id);
    if new_pipeline == 0 return 0;

    array_add(*base.function_constant_variants, .{
        key_hash = key_hash,
        attachment_layout = attachment_layout,
        pipeline = new_pipeline,
    });
    gpu_commit_residency();
    return new_pipeline;
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
    return shader_hot_reload_create_graphics_pipeline_for_manifest_entry(reload, entry, raster_desc, null);
}

shader_hot_reload_create_graphics_pipeline_for_manifest_entry :: (
    reload: *Shader_Hot_Reload,
    entry: *SRM.Shader_Reload_Manifest_Entry,
    raster_desc: Gpu_Raster_Desc,
    target: *Shader_Hot_Reload_Graphics_Target
) -> Gpu_Pipeline {
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
    if target != null && target.default_function_constants_bytes.count != 0 {
        vertex_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
            metallib_path, entry.metal_vertex_entry, target.default_function_constants_bytes, target.function_constant_info);
        fragment_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
            metallib_path, entry.metal_fragment_entry, target.default_function_constants_bytes, target.function_constant_info);
        defer if vertex_constants != null release(vertex_constants);
        defer if fragment_constants != null release(fragment_constants);
        return gpu_create_graphics_pipeline_from_metallib_with_function_constants(
            metallib_path, entry.metal_vertex_entry, entry.metal_fragment_entry, raster_desc, vertex_constants, fragment_constants);
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

shader_hot_reload_create_mesh_pipeline_for_entry :: (reload: *Shader_Hot_Reload, entry_id: string, desc: Shader_Hot_Reload_Mesh_Desc) -> Gpu_Pipeline {
    if !reload return 0;
    entry := SRM.shader_reload_manifest_find_entry(*reload.watcher.manifest, entry_id);
    if !entry {
        log_missing_entry_context(reload, entry_id, "mesh");
        shader_hot_reload_set_error(reload, tprint("% missing mesh entry id=%", reload.log_prefix, entry_id));
        return 0;
    }
    return shader_hot_reload_create_mesh_pipeline_for_manifest_entry(reload, entry, desc);
}

shader_hot_reload_create_mesh_pipeline_for_manifest_entry :: (reload: *Shader_Hot_Reload, entry: *SRM.Shader_Reload_Manifest_Entry, desc: Shader_Hot_Reload_Mesh_Desc) -> Gpu_Pipeline {
    if !reload || !entry return 0;
    metallib_path, found := SRM.shader_reload_manifest_find_entry_metallib_for_manifest(*reload.watcher.manifest, entry, *reload.watcher.paths);
    if !found {
        shader_hot_reload_set_error(reload, tprint("% missing metallib for mesh entry=% request=%", reload.log_prefix, entry.entry_id, entry.request_name));
        return 0;
    }
    if entry.metal_mesh_entry.count == 0 || entry.metal_fragment_entry.count == 0 {
        shader_hot_reload_set_error(reload, tprint("% missing metal mesh/fragment entry names for id=%", reload.log_prefix, entry.entry_id));
        return 0;
    }
    mesh_desc := Gpu_Mesh_Pipeline_Desc.{
        raster_desc = desc.raster_desc,
        task_threads = desc.task_threads,
        mesh_threads = desc.mesh_threads,
        payload_memory_length = desc.payload_memory_length,
        max_total_threadgroups_per_mesh_grid = desc.max_total_threadgroups_per_mesh_grid,
    };
    target: *Shader_Hot_Reload_Mesh_Target;
    for *reload.mesh_targets {
        if it.entry_id == entry.entry_id {
            target = it;
            break;
        }
    }

    if target != null && target.default_function_constants_bytes.count != 0 {
        task_constants: *MTLFunctionConstantValues;
        if entry.metal_task_entry.count != 0 {
            task_constants = shader_hot_reload_build_function_constant_values_for_metallib_function(
                metallib_path, entry.metal_task_entry, target.default_function_constants_bytes, target.function_constant_info);
        }
        mesh_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
            metallib_path, entry.metal_mesh_entry, target.default_function_constants_bytes, target.function_constant_info);
        fragment_constants := shader_hot_reload_build_function_constant_values_for_metallib_function(
            metallib_path, entry.metal_fragment_entry, target.default_function_constants_bytes, target.function_constant_info);
        defer if task_constants != null release(task_constants);
        defer if mesh_constants != null release(mesh_constants);
        defer if fragment_constants != null release(fragment_constants);
        return gpu_create_mesh_pipeline_from_metallib_with_function_constants(
            metallib_path, entry.metal_task_entry, entry.metal_mesh_entry, entry.metal_fragment_entry, mesh_desc,
            task_constants, mesh_constants, fragment_constants);
    }

    return gpu_create_mesh_pipeline_from_metallib(metallib_path, entry.metal_task_entry, entry.metal_mesh_entry, entry.metal_fragment_entry, mesh_desc);
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
