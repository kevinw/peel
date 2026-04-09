Cache_Command_Result :: struct {
    success: bool;
    stdout: string;
    stderr: string;
    timeout_reached: bool;
    exit_code: s32;
}

cache_workspace_root :: () -> string {
    cwd := get_working_directory();
    probe := cwd;

    while probe.count != 0 {
        if file_exists(tprint("%/build.jai", probe)) return probe;
        parent := String.path_strip_filename(probe);
        if parent.count != 0 && parent[parent.count-1] == "/" {
            parent.count -= 1;
        }
        if parent == probe break;
        probe = parent;
    }

    return cwd;
}

cache_subdir_path :: (subdir: string) -> string {
    path := tprint("%/%", cache_workspace_root(), subdir);
    File.make_directory_if_it_does_not_exist(path, true);
    return path;
}

cache_file_path_for_hash :: (subdir: string, hash: u64, suffix: string) -> string {
    cache_dir := cache_subdir_path(subdir);
    return tprint("%/%_%", cache_dir, hash, suffix);
}

cache_directory_for_hash :: (subdir: string, hash: u64) -> string {
    cache_dir := cache_subdir_path(subdir);
    return tprint("%/%", cache_dir, hash);
}

cache_resolve_executable :: (tool_name: string, bundled_relative_path := "") -> string {
    result, stdout, stderr, timeout_reached := Process_Module.run_command(
        "which",
        tool_name,
        capture_and_return_output = true,
        working_directory = cache_workspace_root(),
        timeout_ms = 2000);
    if !timeout_reached && result.type == .EXITED && result.exit_code == 0 {
        trimmed := String.trim(stdout);
        if trimmed.count != 0 && file_exists(trimmed) {
            path_copy := copy_string(trimmed);
            if stdout.count != 0 free(stdout);
            if stderr.count != 0 free(stderr);
            return path_copy;
        }
    }
    if stdout.count != 0 free(stdout);
    if stderr.count != 0 free(stderr);

    if bundled_relative_path.count != 0 {
        bundled := tprint("%/%", cache_workspace_root(), bundled_relative_path);
        if file_exists(bundled) return copy_string(bundled);
    }

    return "";
}

cache_shell_quote :: (value: string) -> string {
    escaped := String.replace(value, "\\", "\\\\",, temp);
    escaped = String.replace(escaped, "\"", "\\\"",, temp);
    escaped = String.replace(escaped, "$", "\\$",, temp);
    escaped = String.replace(escaped, "`", "\\`",, temp);
    return tprint("\"%\"", escaped);
}

cache_run_command_line :: (command_line: string, timeout_ms := 300000, working_directory := "") -> Cache_Command_Result {
    cwd := working_directory;
    if cwd.count == 0 cwd = cache_workspace_root();

    result, stdout, stderr, timeout_reached := Process_Module.run_command(
        "/bin/zsh",
        "-lc",
        command_line,
        capture_and_return_output = true,
        working_directory = cwd,
        timeout_ms = timeout_ms);

    return .{
        success = !timeout_reached && result.type == .EXITED && result.exit_code == 0,
        stdout = stdout,
        stderr = stderr,
        timeout_reached = timeout_reached,
        exit_code = ifx result.type == .EXITED then cast(s32) result.exit_code else -1,
    };
}

cache_free_command_result :: (result: *Cache_Command_Result) {
    if result.stdout.count != 0 free(result.stdout);
    if result.stderr.count != 0 free(result.stderr);
    result.* = .{};
}

Process_Module :: #import "Process";
#import "File_Utilities";
File :: #import "File";
String :: #import "String";
