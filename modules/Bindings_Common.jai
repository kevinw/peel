PLATFORM_NAME :: #run to_lower_copy(sprint("%", OS)); // mac, linux, windows

get_absolute_path_assert :: (path: string, mkdirs := false, loc := #caller_location) -> string {
    if mkdirs make_directory_if_it_does_not_exist(path, recursive=true);
    result := get_absolute_path(path);
    if result == "" assert(false, tprint("Failed to get absolute path for %", path), loc=loc);
    return result;
}

get_platform_dir :: (platform_tag: Operating_System_Tag) -> string {
    return sprint("lib/%", get_shortened_platform_name_for_filesystem(platform_tag));
}

get_shortened_platform_name_for_filesystem :: (platform_tag: Operating_System_Tag) -> string {
    if platform_tag == .WINDOWS return "win";
    name := sprint("%", platform_tag);
    to_lower_in_place(name);
    return name;
}

get_platform_load_statements :: (prefix := "") -> string {
    PLATFORM_LOAD_STATEMENTS :: #string END
#if OS == {
case .MACOS;   #load "%macos.jai";
case .WINDOWS; #load "%windows.jai";
case .LINUX;   #load "%linux.jai";
case; #assert false "TODO: implement for this platform";
}
END;
    return sprint(PLATFORM_LOAD_STATEMENTS, prefix, prefix, prefix);
}

unzip :: (path: string) {
    #if OS == .WINDOWS {
        cmd("powershell", "Expand-Archive", "-Path", path, "-DestinationPath", ".");
    } else {
        cmd("unzip", "-oq", path);
    }
}

fail_and_exit :: (format_string: string = "", args: .. Any) {
    if format_string != ""
        log_error(format_string, ..args);
    compiler_set_workspace_status(.FAILED);
    exit(1);
}

cmd :: (args: ..string, print_captured_output := true) -> Process_Result {
    log("Running command: %", join(..args, separator=" "));
    result := run_command(..args, print_captured_output=print_captured_output);
    if result.type != .EXITED || result.exit_code != 0 {
        log_error("Command did not exit cleanly: % % %", result.type, result.exit_code, result.signal);
        fail_and_exit();
    }
    return result;
}

download_file :: (url: string, local_filepath: string) -> Process_Result {
    return cmd("curl", "-s", "-L", url, "--output", local_filepath);
}

copy_dll :: (source: string, destination: string) {
    copy(source, destination);

    #if OS == .WINDOWS {
        // on windows, the dll is not enough, we also need the pdb and lib files.
        pdb := join(path_strip_extension(source), ".pdb");
        if file_exists(pdb) copy(pdb, destination);

        lib := join(path_strip_extension(source), ".lib");
        if lib != source && file_exists(lib) copy(lib, destination);
    }

    // TODO: mac has dSYM for debugging info. (it's a directory...do we have copying directories recursively?)
}

files_have_same_size_and_modification_time :: (source: string, destination: string) -> bool {
    if !file_exists(source) || !file_exists(destination) return false;
    source_size, source_modtime := file_modtime_and_size(source);
    dest_size, dest_modtime := file_modtime_and_size(destination);
    return source_size == dest_size && source_modtime == dest_modtime;
}

copy :: (source: string, destination: string) {
    #if OS == .WINDOWS {
        if files_have_same_size_and_modification_time(source, destination) return;
        cmd("cmd", "/c", "copy", "/Y", replace(source, "/", "\\"), replace(destination, "/", "\\"));
    } else {
        cmd("cp", source, destination);
    }
}

delete :: (path: string) {
    // Some sanity checks. We should only be deleting files under this directory.
    assert(path != "");

    my_abs_path             := get_absolute_path(#filepath);
    file_to_delete_abs_path := get_absolute_path(path);

    if file_to_delete_abs_path == "" {
        // no file, nothing to delete.
        return;
    }

    assert(my_abs_path.count < file_to_delete_abs_path.count, tprint("delete called with a path that is not under the current working directory: '%' (my_abs_path: '%')", file_to_delete_abs_path, my_abs_path));

    #if OS == .WINDOWS {
        if file_exists(path) {
            if is_directory(path) {
                cmd("rmdir", "/s", "/q", path);
            } else {
                cmd("cmd", "/c", "del", path);
            }
        }
    } else {
        cmd("rm", "-rf", path);
    }
}

platform_dynamic_library_extension :: #run -> string {
    #if      OS == .WINDOWS return "dll";
    else #if OS == .LINUX   return "so";
    else #if OS == .MACOS   return "dylib";
    else #assert false "TODO: implement platform_dynamic_library_extension for this OS";
}

platform_static_library_extension :: #run -> string {
    #if      OS == .WINDOWS return "lib";
    else #if OS == .LINUX   return "a";
    else #if OS == .MACOS   return "a";
    else #assert false "TODO: implement platform_static_library_extension for this OS";
}

#scope_file
#import "String";
#import "Compiler";
#import "Basic";
#import "Process";
#import "File_Utilities";
using,only(get_absolute_path) #import "File";
