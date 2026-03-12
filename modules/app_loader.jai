#import "Basic";
#import "System";
#import "String";
#import "Reload_Common";
#import "File_Utilities";
library :: #import "library";

#import "Host_App_Common";

App :: struct {
    handle:             *void;
    filepath:           string; // Original filepath of the app.
    temp_loaded_filepath: string; // If we copied the app to a temp file to load, this is its path.

    on_host_message:    (message: Host_Message) -> App_Return_Message;
    get_globals:        () -> []Global_Entry;

    last_modification:  Apollo_Time;
    is_valid:           bool;
}

app_library_load :: (library_filename: string, verbose := true) -> (app: App) {
    assert(library_filename != "", "library_filename is empty");

    cwd := get_path_of_running_executable_directory(,, allocator = temp);
    logger := ifx(verbose) then context.logger else noop_logger;

    source_path_full := tprint("%/%", cwd, library_filename);
    temp_path_full := tprint("%.temp.%", source_path_full, _counter);
    copy_ok := copy_file(source_path_full, temp_path_full,, logger = logger);
    if copy_ok == false && verbose {
        log_error("Couldn't copy to temp file.");
        exit(1);
    }

    using app: App;
    temp_loaded_filepath = copy_string(temp_path_full);
    if verbose log("loading DLL: %", temp_path_full);
    handle = library.load(temp_path_full, verbose);

    on_host_message = library.symbol_address(handle, "on_host_message", verbose);
    get_globals     = library.symbol_address(handle, "get_globals", verbose);

    is_valid = handle != null && on_host_message != null && get_globals != null;
    if is_valid {
        _counter += 1;
        last_modification = file_modtime_and_size(source_path_full);
    }
    filepath = copy_string(source_path_full);
    return app;
}

// This is where we bitwise copy globals from a DLL to another when reloading.
app_library_copy :: (src: *App, dst: *App, only_names: ..string) -> (ok: bool) {
    for src_global: src.get_globals() {
        if only_names.count > 0 && !array_find(only_names, src_global.name) {
            continue;
        }
        for dst_global: dst.get_globals() {
            // If the names and module names match, copy the data.
            if src_global.name_hash == dst_global.name_hash && src_global.module_name_hash == dst_global.module_name_hash {
                memcpy(dst_global.data, src_global.data, src_global.size);
            }
        }
    }

    return true;
}

app_library_unload :: (using app: *App, verbose := false) -> (ok: bool) {
    result := library.unload(handle, verbose);
    if !result {
        log_error("Failed to unload app.");
    } else {
        if temp_loaded_filepath != "" {
            File.file_delete(temp_loaded_filepath);
            free(temp_loaded_filepath);
            temp_loaded_filepath = "";
        }
    }
    handle = null;
    on_host_message = null;
    get_globals = null;
    is_valid = false;

    free(app.filepath);
    app.filepath = "";

    return result;
}

app_library_changed :: (app: *App) -> bool {
    modtime, size := file_modtime_and_size(app.filepath);
    diff := compare_apollo_times(modtime, app.last_modification);
    return diff == 1;
}

app_library_get_global_pointer :: (app: *App, global_name: string) -> *void, bool {
    for it: app.get_globals() {
        if it.name != global_name continue;
        assert(it.size == size_of(*void), "Global '%' is size %, expected pointer-sized %.", global_name, it.size, size_of(*void));
        return (cast(**void) it.data).*, true;
    }

    return null, false;
}

#scope_file

_counter := 0; // We use this to generate incrementing filenames

get_path_of_running_executable_directory :: () -> string {
    path := get_path_of_running_executable();
    words := split(path, "/");
    return join(..array_view(words, 0, words.count - 1), "/");
}

noop_logger :: (message: string, data: *void, info: Log_Info) {}

File :: #import "File";
