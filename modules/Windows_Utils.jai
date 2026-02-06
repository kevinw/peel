/*

OutputDebugString on windows goes to the visual studio output window. but not to stderr. tools like the D3D12 debug layer write to OutputDebugString,
so here we map it to stderr to see it in the main console.

todo: we could filter on our process id to avoid logging other processes' debug output

*/
ODS_Buffer :: struct {
    process_id: DWORD;
    data: [4096 - size_of(DWORD)]u8;
};

ods_buffer: *ODS_Buffer;

// for receiving "debug output" on windows, which is separate from stderr
ods_proc :: (arg: *void) -> s32 #c_call {
    stderr := GetStdHandle(STD_ERROR_HANDLE);
    if stderr == null {
        push_context,defer_pop;
        log_error("GetStdHandle(STD_ERROR_HANDLE) returned null");
        return 1;
    }

    while true {
        SetEvent(ods_buffer_ready);

        wait := WaitForSingleObject(ods_data_ready, INFINITE);
        if wait != WAIT_OBJECT_0 {
            push_context,defer_pop;
            log_error("WaitForSingleObject(ods_data_ready, INFINITE) returned %", wait);
            return 1;
        }

        length: DWORD = 0;
        while length < size_of(type_of(ods_buffer.data)) && ods_buffer.data[length] != 0 {
            length += 1;
        }

        if length != 0 {
            written: DWORD;
            WriteFile(stderr, cast(*void)*ods_buffer.data[0], length, *written, null);
        }
    }

    return 0;
}

map_debug_output_to_stderr :: () {
    if IsDebuggerPresent() {
        log("IsDebuggerPresent() is true, not mapping debug output to stderr");
        return;
    }

    file := CreateFileMappingA(INVALID_HANDLE_VALUE, null, PAGE_READWRITE, 0, size_of(ODS_Buffer), "DBWIN_BUFFER");
    assert(file != INVALID_HANDLE_VALUE);

    ods_buffer = MapViewOfFile(file, SECTION_MAP_READ, 0, 0, 0);
    assert(ods_buffer != null);

    ods_buffer_ready = CreateEventA(null, FALSE, FALSE, "DBWIN_BUFFER_READY");
    assert(ods_buffer_ready != null);

    ods_data_ready = CreateEventA(null, FALSE, FALSE, "DBWIN_DATA_READY");
    assert(ods_data_ready != null);

    thread := CreateThread(null, 0, cast(*void)ods_proc, null, 0, null);
    assert(thread != null);
    if thread != null CloseHandle(thread);
}

get_current_process_path :: () -> string /*temp*/ {
    // Get the length we need.
    actual_len := GetEnvironmentVariableA("PATH", null, 0);
    if actual_len == 0 {
        log_error("Failed to get PATH environment variable: %", GetLastError());
        return "";
    }

    // The length returned above includes the null terminator.
    path_buffer: string = .{actual_len - 1, talloc(actual_len)};
    actual_len_2 := GetEnvironmentVariableA("PATH", path_buffer.data, actual_len);
    assert(actual_len_2 == actual_len - 1); // But oddly, the length returned when you have enough space does NOT include the null terminator.

    return path_buffer;
}

add_to_current_process_path :: (paths: []string,
    replace_forward_slashes_with_backslashes: bool,
    make_paths_absolute: bool = false
) -> bool {
    path_str := get_current_process_path();
    if !path_str {
        return false;
    }

    sb: String_Builder = .{ allocator = temp };
    for paths {
        path_windows := it;
        if replace_forward_slashes_with_backslashes {
            path_windows = String.replace(it, "/", "\\",, temp);
        }
        if make_paths_absolute {
            path_windows = File.get_absolute_path(path_windows);
            if path_windows == "" {
                log_error("Could not get absolute path for %", it);
                return false;
            }
        }
        append(*sb, path_windows);
        append(*sb, ";");
    }
    append(*sb, path_str);
    append(*sb, "\0");

    new_path_str := builder_to_string(*sb,, temp);
    // log(new_path_str);
    res := SetEnvironmentVariableA("PATH", new_path_str.data);
    if 0 == res {
        last_error := GetLastError();
        log_error("Failed to set PATH environment variable: %", last_error);
        return false;
    }

    return true;
}

current_memory_usage_bytes :: () -> u64 {
    PROCESS_MEMORY_COUNTERS_EX :: struct {
      cb: DWORD;
      PageFaultCount: DWORD;
      PeakWorkingSetSize: SIZE_T;
      WorkingSetSize: SIZE_T;
      QuotaPeakPagedPoolUsage: SIZE_T;
      QuotaPagedPoolUsage: SIZE_T;
      QuotaPeakNonPagedPoolUsage: SIZE_T;
      QuotaNonPagedPoolUsage: SIZE_T;
      PagefileUsage: SIZE_T;
      PeakPagefileUsage: SIZE_T;
      PrivateUsage: SIZE_T;
    }

    Psapi :: #system_library "Psapi";
    GetProcessMemoryInfo :: (process: HANDLE, ppsmemCounters: *PROCESS_MEMORY_COUNTERS_EX, cb: DWORD) -> BOOL #foreign Psapi;

    info: PROCESS_MEMORY_COUNTERS_EX;
    info.cb = size_of(PROCESS_MEMORY_COUNTERS_EX);

    result := GetProcessMemoryInfo(GetCurrentProcess(), cast(*PROCESS_MEMORY_COUNTERS_EX)*info, info.cb);
    if result == 0 {
        log_error("GetProcessMemoryInfo failed: %", GetLastError());
        return 0;
    }

    return info.PrivateUsage;
}

set_window_title :: (window: *void, title: string) {
    SetWindowTextA(window, temp_c_string(title));
}

#scope_file

#import "Windows";
#import "Basic";
String :: #import "String";
File :: #import "File";
ods_data_ready: HANDLE;
ods_buffer_ready: HANDLE;
FALSE :: 0;

SECTION_MAP_READ :: 4;
kernel32 :: #system_library "kernel32";
GetLastError :: () -> u32 #foreign kernel32;
SetEvent :: (event: HANDLE) -> s32 #foreign kernel32;
GetEnvironmentVariableA :: (lpName: *u8, lpBuffer: *u8, nSize: u32) -> u32 #foreign kernel32;
SetEnvironmentVariableA :: (lpName: *u8, lpValue: *u8) -> s32 #foreign kernel32;
