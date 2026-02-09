//
// Metaprogram plugin for writing out a .srcdeps file with the source files your output depends on.
// The manifest file contains filenames, file modification times, and the Build_Options used during compilation.
// You can then ask on subsequent builds, with `can_skip_build`, if the build can be skipped.
//
NEVER_SKIP :: false;
DEFAULT_VERBOSE :: false;

get_plugin :: () -> *Build_Manifest_Metaprogram_Plugin {
    return New(Build_Manifest_Metaprogram_Plugin);
}

Build_Manifest_Metaprogram_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = on_compiler_message;

    on_event: (p: *Build_Manifest_Metaprogram_Plugin, evt: Build_Manifest_Event, userdata: *void);
    on_event_userdata: *void;

    plugin_magic: u32 = PLUGIN_MAGIC;
    build_files: [..]Manifest_Entry;
    verbose := DEFAULT_VERBOSE;
    did_write_output := false;

    PLUGIN_MAGIC: u32: 19437289;
}

deinit :: (p: *Build_Manifest_Metaprogram_Plugin) {
    array_free(p.build_files);
    initializer_of(Build_Manifest_Metaprogram_Plugin)(p);
}

Build_Manifest_Event :: enum {
    Executable_Was_Built;
}

Manifest_Entry :: struct {
    filename: string;
    modtime: Apollo_Time;
}

Commonly_Propogated_Build_Options :: type_of(Build_Options.Commonly_Propagated);

Manifest_Header :: struct {
    MAGIC: u32: 0xd3adb11d;
    CURRENT_VERSION: u32 : 2;

    magic:         u32 = MAGIC;
    version:       u32 = CURRENT_VERSION;
    cp_build_opts_size: u64 = size_of(Commonly_Propogated_Build_Options);
    cp_build_opts: Commonly_Propogated_Build_Options;
    entries_count: s64;
}

get_manifest_filename :: (output_executable: string) -> string {
    return String.join(output_executable, ".srcdeps");
}

can_skip_build :: (build_options: Build_Options, verbose: bool = DEFAULT_VERBOSE) -> bool {
    #if NEVER_SKIP return false;
    output_fn := get_output_executable_filename(build_options);
    return can_skip_build(output_fn, build_options, verbose);
}

can_skip_build :: (output_fn: string, build_options: Build_Options, verbose: bool = DEFAULT_VERBOSE) -> bool {
    output_modtime, size, exists := file_modtime_and_size(output_fn);

    check :: (condition: bool, reason: string, fmt_args: ..Any) #expand {
        if !condition {
            if verbose log("Build necessary: %", tprint(reason, ..fmt_args));
            `return false;
        }
    }

    check(exists, "Output file does not exist.");

    manifest_filename := get_manifest_filename(output_fn);
    manifest_modtime, manifest_size, manifest_exists := file_modtime_and_size(manifest_filename);
    check(manifest_exists, "Manifest file does not exist at path '%'", manifest_filename);
    check(manifest_modtime >= output_modtime, "Manifest file is older than output file.");

    ok, entries, manifest_build_opts := parse_manifest(manifest_filename);
    defer array_free(entries);
    check(ok, "Failed to parse manifest file.");

    // First, a memcmp for speed, and then a fieldwise comparison. TODO: figure out why memcmp shows a change but compare_fieldwise does not! Constant storage etc?
    if 0 != memcmp(*manifest_build_opts, *build_options.Commonly_Propagated, size_of(type_of(manifest_build_opts))) {
        check(compare_fieldwise(manifest_build_opts, build_options.Commonly_Propagated), "Build options have changed since the last build.");
    }

    // TODO:
    // - always write sorted lists to the manifest file.
    // - sort the input list before comparing it entry-wise to the manifest.
    // - we're missing a case where the user can add a new dependency to the main list in a manual build, and it will be missed.

    for entries {
        entry_modtime, entry_size, entry_exists := file_modtime_and_size(it.filename);

        check(entry_exists, "File in manifest does not exist.");
        check(entry_modtime <= it.modtime, "File is newer than manifest entry - '%'", it.filename);
        check(entry_modtime <= output_modtime, "Source file is newer than output file - '%'", it.filename);

        if verbose log("Checked file: '%' % %", it.filename, entry_modtime, it.modtime);
    }

    if verbose log("Build '%s' is unnecessary.", output_fn);
    return true;
}

mark_meta_dependency :: (filename: string) {
    if is_directory(filename) {
        log_error("mark_meta_dependency: expected a file, given a directory: '%'", filename);
    } else {
        _mark_file_dependency(*meta_dependencies, filename);
    }
}

mark_dependency :: (using p: *Build_Manifest_Metaprogram_Plugin, filename: string) {
    if is_directory(filename) {
        log_error("mark_dependency: expected a file, given a directory: '%'", filename);
    } else {
        _mark_file_dependency(*p.build_files, filename);
    }
}

// For when you want to build something out of a Jai compiler loop, but still use the Build_Manifest logic.
external_build :: (input_files: []string, output_filename: string, build_callback: () -> ()) {
    build_options: Build_Options;
    if can_skip_build(output_filename, build_options) {
        log("Skipping build for '%'", output_filename);
        return;
    }

    p: Build_Manifest_Metaprogram_Plugin;
    defer deinit(*p);
    for input_files {
        _mark_file_dependency(*p.build_files, it);
    }

    User_Data :: struct {
        was_called: bool = false;
        cb: () -> ();
        output_filename: string;
    }

    p.on_event = (p: *Build_Manifest_Metaprogram_Plugin, event: Build_Manifest_Event, userdata: *void) {
        using cast(*User_Data)userdata;
        if event == {
        case .Executable_Was_Built;
            was_called = true;
            build_options: Build_Options;
            cb(); // TODO: pass input_files, output_filename, build_options
        }
    }

    user_data: User_Data = .{
        cb = build_callback,
        output_filename = output_filename
    };

    p.on_event_userdata = *user_data;

    write_srcdeps_output(*p, build_options, output_filename);
    assert(user_data.was_called, "Expected the on_event callback to be called");
}

#scope_file

_mark_file_dependency :: (build_files: *[..]Manifest_Entry, filename: string) {
    modtime, size, file_exists := file_modtime_and_size(filename);
    if file_exists {
        array_add(build_files, .{ filename, modtime });
    } else {
        log_error("File '%' does not exist - but Build_Manifest expected it to", filename);
    }
}

on_compiler_message :: (_p: *Metaprogram_Plugin, compiler_message: *Message) {
    using p := cast(*Build_Manifest_Metaprogram_Plugin)_p;

    if compiler_message.kind == {
    case .COMPLETE;
        assert(plugin_magic == PLUGIN_MAGIC, "Plugin magic mismatch");

        if did_write_output {
            log_error("Build_Manifest: already wrote output, but got compiler_message .COMPLETE");
            return;
        }
        did_write_output = true;

        build_options := get_build_options(workspace);
        output_filename := get_output_executable_filename(build_options);
        write_srcdeps_output(p, build_options, output_filename);

    case .FILE;
        message_file := cast(*Message_File)compiler_message;
        if !message_file.enclosing_import || message_file.from_a_string {
            // Some special *Message_Files do not have *Message_Import, or are marked from_a_string,
            // like .added_strings_w1.jai. We don't care about those files.
            return;
        }
        _mark_file_dependency(*p.build_files, message_file.fully_pathed_filename);
    }
}

write_srcdeps_output :: (using p: *Build_Manifest_Metaprogram_Plugin, build_options: Build_Options, output_filename: string) {
    if build_files.count <= 0 {
        if verbose { log("Build_Manifest: no build files."); }
        return;
    }

    if on_event {
        on_event(p, .Executable_Was_Built, on_event_userdata);
    }

    modtime, size, exists := file_modtime_and_size(output_filename);
    assert(exists, "Expected the output file to exist already: '%'", output_filename);

    // TODO: should we check that the output file's modtime is newer than the input files?

    // Include global "meta_dependencies" and this-plugin-specific "build_files".
    manifest_entries_to_write: [..]Manifest_Entry;
    defer array_free(manifest_entries_to_write);

    if !did_include_this_file {
        // Also include this contents of this file.
        did_include_this_file = true;
        mark_meta_dependency(String.path_join(#filepath, "Build_Manifest.jai"));
    }
    array_add(*manifest_entries_to_write, ..meta_dependencies);
    array_add(*manifest_entries_to_write, ..build_files);

    manifest_filename := get_manifest_filename(output_filename);
    wrote_manifest := write_manifest(manifest_filename, manifest_entries_to_write, build_options.Commonly_Propagated, verbose);
    if !wrote_manifest {
        log_error("Error writing manifest file to '%'", manifest_filename);
    } else {
        log("Wrote manifest '%'", manifest_filename);
    }
}

write_manifest :: (manifest_filename: string, entries: [..]Manifest_Entry, cp_build_opts: Commonly_Propogated_Build_Options, verbose: bool) -> bool {
    assert(entries.count > 0);

    sb: String_Builder = .{ allocator = temp };

    write_T(*sb, Manifest_Header.{
            entries_count = entries.count,
            cp_build_opts = cp_build_opts,
    });

    if verbose log("Writing % entries to manfiest '%'.", entries.count, manifest_filename);
    for entries {
        write_dynamic_string(*sb, it.filename);
        write_T(*sb, it.modtime);
    }

    return File.write_entire_file(manifest_filename, builder_to_string(*sb,, temp));
}

parse_manifest :: (manifest_filename: string, verbose: bool = DEFAULT_VERBOSE) -> (parse_ok: bool, entries: [..]Manifest_Entry, manifest_build_options: Commonly_Propogated_Build_Options) {
    entries: [..]Manifest_Entry;

    check :: (condition: bool, message: string, fmt_args: ..Any, stderr := false) #expand {
        if !condition {
            if verbose log(message, ..fmt_args);
            `return false, entries, .{};
        }
    }

    contents, ok := File.read_entire_file(manifest_filename);
    check(ok, "Error: Failed to read manifest file '%s'.", manifest_filename);

    header := read_T(*contents, Manifest_Header);
    check(header.magic == Manifest_Header.MAGIC, "Invalid manifest magic number.");
    check(header.version == Manifest_Header.CURRENT_VERSION, "Manifest version (%d) does not match ours (%d).", header.version, Manifest_Header.CURRENT_VERSION);
    check(header.cp_build_opts_size == size_of(Commonly_Propogated_Build_Options), "Manifest cp_build_opts_size (%d) does not match ours (%d).", header.cp_build_opts_size, size_of(Commonly_Propogated_Build_Options));
    check(header.entries_count > 0, "Manifest entries count (%d) is invalid.", header.entries_count);

    for 0..header.entries_count - 1 {
        check(contents.count >= 4, "Error: ran out of manifest file data to parse, but expected more.");

        filename := read_dynamic_string(*contents);
        check(filename != "", "Error: Manifest entry filename is empty.");

        modtime := read_T(*contents, Apollo_Time);
        array_add(*entries, .{ filename, modtime });
    }

    return true, entries, header.cp_build_opts;
}

get_output_executable_filename :: (using build_options: Build_Options) -> string {
    ext := "";

    if append_executable_filename_extension { // TODO: is there a way to get this from the Compiler module?
        if output_type == {
        case .EXECUTABLE;
            #if OS == .WINDOWS ext = ".exe";
        case .DYNAMIC_LIBRARY;
            #if OS == .WINDOWS ext = ".dll";
            #if OS == .LINUX   ext = ".so";
            #if OS == .MACOS   ext = ".dylib";
        case .STATIC_LIBRARY;
            #if OS == .WINDOWS ext = ".lib";
            #if OS == .LINUX   ext = ".a";
            #if OS == .MACOS   ext = ".a";
        case;
            compiler_report(tprint("Unhandled output type: %", output_type));
        }
    }

    return String.path_join(output_path, String.join(output_executable_name, ext));
}

write_T :: (sb: *String_Builder, value: $Type) {
    append(sb, string.{ size_of(type_of(value)), cast(*void)*value });
}

read_T :: (s: *string, $type_to_read: Type) -> type_to_read {
    num_bytes := size_of(type_to_read);
    assert(s.count >= num_bytes);
    result := (cast(*type_to_read)s.data).*;
    advance(s, num_bytes);
    return result;
}

read_dynamic_string :: (s: *string) -> string {
    count := read_T(s, type_of(s.count));
    if count < 0 { return ""; }
    result_str := string.{ count,  s.data };
    advance(s, count);
    return result_str;
}

write_dynamic_string :: (sb: *String_Builder, value: string) {
    write_T(sb, value.count);
    append(sb, value);
}

compare_fieldwise :: (a: $T, b: T) -> bool {
    ti := type_info(T);
    if ti.type != .STRUCT {
        log_error("expected struct type");
        assert(false, "expected struct type");
    }

    ti_struct := cast(*Type_Info_Struct)ti;

    for member: ti_struct.members {
        if member.offset_into_constant_storage >= 0 {
            log("skipping field % because it's in constant storage", member.name);
            continue;
        }

        bytes_a := []u8.{ member.type.runtime_size, (cast(*void)*a) + member.offset_in_bytes };
        bytes_b := []u8.{ member.type.runtime_size, (cast(*void)*b) + member.offset_in_bytes };
        assert(bytes_a.count == bytes_b.count);
        assert(bytes_a.count > 0);

        if memcmp(bytes_a.data, bytes_b.data, bytes_a.count) != 0 {
            // log("field % differs", member.name);
            return false;
        } else {
            // log("field % is equal", member.name);
        }
    }

    return true;
}


#import "Compiler";
#import "Basic";
using,only(file_modtime_and_size, is_directory) File_Utilities :: #import "File_Utilities";
File :: #import "File";
String :: #import "String";
Sort :: #import "Sort";

did_include_this_file := false;
meta_dependencies: [..]Manifest_Entry;
