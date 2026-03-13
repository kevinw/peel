#if OS == {
    case .MACOS;   DLL_EXTENSION :: "dylib";
    case .WINDOWS; DLL_EXTENSION :: "dll";
    case .LINUX;   DLL_EXTENSION :: "so";
    case; #assert false "please implement this for this platform";
}

host_app_build_start_worker_thread :: () {
    if host_app_build.worker_started return;

    Thread.init(*host_app_build.worker_wake, 0);
    Thread.init(*host_app_build.worker_mutex, "host_app_build");
    ok := Thread.thread_init(*host_app_build.worker_thread, host_app_build_worker_proc);
    if !ok {
        log_error("Host: failed to start app build worker thread.");
        return;
    }
    Thread.thread_start(*host_app_build.worker_thread);
    host_app_build.worker_started = true;
}

host_app_build_queue :: (app_source: string) {
    if app_source.count == 0 return;
    host_app_build_start_worker_thread();
    if !host_app_build.worker_started return;

    Thread.lock(*host_app_build.worker_mutex);
    defer Thread.unlock(*host_app_build.worker_mutex);

    if host_app_build.worker_pending_app_source.count != 0 {
        free(host_app_build.worker_pending_app_source);
        host_app_build.worker_pending_app_source = "";
    }
    host_app_build.worker_pending_app_source = copy_string(app_source);
    host_app_build.worker_has_pending = true;

    host_assign_string(*host_app_build.target, app_source);
    if host_app_build.error.count != 0 {
        free(host_app_build.error);
        host_app_build.error = "";
    }
    if host_app_build.worker_build_in_flight {
        host_app_build.status = .RUNNING;
    } else {
        host_app_build.status = .QUEUED;
    }

    Thread.signal(*host_app_build.worker_wake);
}

host_app_build_take_completion :: (completed_ok: *bool, completed_app_source: *string, completed_error: *string) -> bool {
    if !host_app_build.worker_started return false;

    Thread.lock(*host_app_build.worker_mutex);
    defer Thread.unlock(*host_app_build.worker_mutex);

    if !host_app_build.worker_has_completed return false;
    host_app_build.worker_has_completed = false;
    completed_ok.* = host_app_build.worker_completed_ok;
    completed_app_source.* = host_app_build.worker_completed_app_source;
    completed_error.* = host_app_build.worker_completed_error;
    host_app_build.worker_completed_app_source = "";
    host_app_build.worker_completed_error = "";
    return true;
}

host_app_build_handle_completion :: (ctx: *App_Update_Ctx, library_filename: *string) {
    completed_ok: bool;
    completed_app_source: string;
    completed_error: string;
    has_completed := host_app_build_take_completion(*completed_ok, *completed_app_source, *completed_error);
    if !has_completed return;

    if completed_ok {
        if host_app_build.error.count != 0 {
            free(host_app_build.error);
            host_app_build.error = "";
        }
        host_app_build.status = .NONE;
        if host_app_build.target.count != 0 {
            free(host_app_build.target);
            host_app_build.target = "";
        }
        app_dll := app_dll_basename_for_source_file(completed_app_source);
        ctx.app_return_flags |= .Load_App;
        ctx.app_return_data.load_app = copy_string(app_dll);
        if library_filename.count != 0 free(library_filename.*);
        library_filename.* = sprint("%.%", app_dll, DLL_EXTENSION);
    } else {
        host_app_build.status = .FAILED;
        host_assign_string(*host_app_build.target, completed_app_source);
        host_assign_string(*host_app_build.error, completed_error);
        if completed_error.count == 0 {
            host_app_build.error = copy_string("Build failed.");
        }
        log_error("Host: app DLL build failed for '%'.", completed_app_source);
    }

    if completed_app_source.count != 0 free(completed_app_source);
    if completed_error.count != 0 free(completed_error);
}

host_app_build_apply_status_to_update_ctx :: (ctx: *App_Update_Ctx) {
    ctx.host_build_state = host_app_build.status;
    ctx.host_build_target = host_app_build.target;
    ctx.host_build_error = host_app_build.error;
}

host_app_build_shutdown :: () {
    if host_app_build.worker_started {
        Thread.lock(*host_app_build.worker_mutex);
        host_app_build.worker_should_exit = true;
        Thread.unlock(*host_app_build.worker_mutex);
        Thread.signal(*host_app_build.worker_wake);
        Thread.thread_deinit(*host_app_build.worker_thread);
        host_app_build.worker_started = false;
    }

    if host_app_build.worker_pending_app_source.count != 0 free(host_app_build.worker_pending_app_source);
    if host_app_build.worker_completed_app_source.count != 0 free(host_app_build.worker_completed_app_source);
    if host_app_build.worker_completed_error.count != 0 free(host_app_build.worker_completed_error);
    if host_app_build.target.count != 0 free(host_app_build.target);
    if host_app_build.error.count != 0 free(host_app_build.error);
    host_app_build = .{};
}

host_app_build_worker_proc :: (thread: *Thread.Thread) -> s64 {
    while true {
        _ = Thread.wait_for(*host_app_build.worker_wake);

        app_source: string;
        Thread.lock(*host_app_build.worker_mutex);
        if host_app_build.worker_should_exit {
            Thread.unlock(*host_app_build.worker_mutex);
            break;
        }
        if !host_app_build.worker_has_pending {
            Thread.unlock(*host_app_build.worker_mutex);
            continue;
        }

        app_source = host_app_build.worker_pending_app_source;
        host_app_build.worker_pending_app_source = "";
        host_app_build.worker_has_pending = false;
        host_app_build.worker_build_in_flight = true;
        host_app_build.status = .RUNNING;
        Thread.unlock(*host_app_build.worker_mutex);

        build_error: string;
        build_ok := host_build_app_dll(app_source, *build_error);

        Thread.lock(*host_app_build.worker_mutex);
        host_app_build.worker_build_in_flight = false;
        host_app_build.worker_completed_ok = build_ok;
        host_assign_string(*host_app_build.worker_completed_app_source, app_source);
        host_assign_string(*host_app_build.worker_completed_error, build_error);
        host_app_build.worker_has_completed = true;
        Thread.unlock(*host_app_build.worker_mutex);

        if app_source.count != 0 free(app_source);
        if build_error.count != 0 free(build_error);
    }

    return 0;
}

host_build_app_dll :: (app_source: string, out_error: *string) -> bool {
    app_path := app_source_path_for_source_file(app_source,, temp);
    result, stdout, stderr, timeout_reached := Process.run_command(
        "jai", "build.jai", "-", app_path, "-dll",
        working_directory = "..",
        capture_and_return_output = true,
        timeout_ms = 120_000,
    );
    defer {
        if stdout.count != 0 free(stdout);
        if stderr.count != 0 free(stderr);
    }

    if timeout_reached {
        host_assign_string(out_error, tprint("Timed out building '%'.", app_path));
        return false;
    }

    if result.exit_code != 0 {
        details := stderr;
        if details.count == 0 details = stdout;
        if details.count == 0 details = "Build failed with no output.";
        host_assign_string(out_error, details);
        return false;
    }

    return true;
}

host_assign_string :: (dst: *string, src: string) {
    if dst.*.count != 0 {
        free(dst.*);
        dst.* = "";
    }
    if src.count != 0 dst.* = copy_string(src);
}


#scope_file

Host_App_Build_State :: struct {
    worker_started: bool;
    worker_thread: Thread.Thread;
    worker_wake: Thread.Semaphore;
    worker_mutex: Thread.Mutex;
    worker_should_exit: bool;
    worker_has_pending: bool;
    worker_pending_app_source: string;
    worker_build_in_flight: bool;
    worker_has_completed: bool;
    worker_completed_ok: bool;
    worker_completed_app_source: string;
    worker_completed_error: string;
    status: App_Update_Ctx.Host_Build_State;
    target: string;
    error: string;
}

host_app_build: Host_App_Build_State;

Process :: #import "Process";
Thread :: #import "Thread";
