/*
The idea here is for a metaprogram to collect all the globals in the app, with
type info and pointers to them.

A live-reloading host program can then use them to reload a DLL with these
globals, and the maintain the app's state by copying globals from one DLL to
another, by name.

Or it might also be useful for building a UI to show the global state of your
program, for example.

It emits a function which fills an array of Global_Entry structs, like

get_all_globals :: (result: *[..]Global_Entry) { ...

Declarations marked with @noreload are skipped.
*/

EXTRA_CHECKS :: false;

Globals_Reload_Metaprogram_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = on_compiler_message;
    flags: enum_flags {
        Reload_Globals_In_Main_Application;
        Collect_Reloadable_Procedures;
        Collect_Reloadable_Functions;
        Verbose;
    } = .Reload_Globals_In_Main_Application | .Collect_Reloadable_Procedures;

    // internal
    did_emit_code := false;

    files:   Table(*Message_File,   File_Entry);

    File_Entry :: struct {
        decls: [..]*Code_Declaration;
        procs: [..]Proc_Entry;
    }

    imports: Table(*Message_Import, [..]*Message_File);

    reload_common_module: *Message_Import;
    should_include_file_userdata: *void;
    allow_stdlib_module_names := string.[ "Basic", "Simp" ];
    never_reload_modules      := string.[ "Preload", "Runtime_Support" ];
    Include_Result :: enum { Unknown; Ignore; Include; };
    last_lookup: struct {
        file: *Message_File;
        result: Include_Result;
    }
}

get_plugin :: () -> *Globals_Reload_Metaprogram_Plugin {
    return New(Globals_Reload_Metaprogram_Plugin);
}

#scope_file

RELOAD_COMMON_MODULE_NAME :: "Reload_Common";

on_compiler_message :: (_p: *Metaprogram_Plugin, compiler_message: *Message) {
    using p := cast(*Globals_Reload_Metaprogram_Plugin) _p;

    if compiler_message.kind == {
        case .IMPORT;
            import_message := cast(*Message_Import) compiler_message;
            if reload_common_module == null && import_message.module_name == RELOAD_COMMON_MODULE_NAME {
                reload_common_module = import_message;
            }

        case .TYPECHECKED;
            tc := cast(*Message_Typechecked) compiler_message;
            for code_node: tc.all {
                if !code_node.expression continue;

                if code_node.expression.kind == {
                    case .DECLARATION;
                        handle_declaration(p, cast(*Code_Declaration) code_node.expression);
                    case .PROCEDURE_HEADER;
                        handle_procedure_header(p, cast(*Code_Procedure_Header) code_node.expression);
                }
            }

        case .PHASE;
            phase_message := cast(*Message_Phase) compiler_message;
            // Time to emit our code.
            if !p.did_emit_code && phase_message.phase == .TYPECHECKED_ALL_WE_CAN {
                p.did_emit_code = true;
                emit_code(p);
            }
    }
}

mark_file :: (using p: *Globals_Reload_Metaprogram_Plugin, file: *Message_File) -> bool {
    include, was_new := should_include_file_cached(p, file);
    if !include {
        return false;
    }

    // Each Message_Import gets a unique list of Message_Files it contains.
    if was_new {
        array_add_if_unique(find_or_add(*imports, file.enclosing_import), file);
    }

    return true;
}

handle_declaration :: (using p: *Globals_Reload_Metaprogram_Plugin, decl: *Code_Declaration) {
    if !should_include_declaration(p, decl) {
        return;
    }

    file := decl.enclosing_load;
    if mark_file(p, file) {
        // Each Message_File gets a list of Code_Declarations.
        entries_ptr := find_or_add(*files, file);
        array_add(*entries_ptr.decls, decl);
    }
}

handle_procedure_header :: (using p: *Globals_Reload_Metaprogram_Plugin, proc_header: *Code_Procedure_Header) {
    if proc_header.procedure_flags & (.ELSEWHERE | .COMPILE_TIME_ONLY | .POLYMORPHIC | .MACRO) != 0 {
        return;
    }

    track_proc := false;
    proc_flags: Proc_Flags = .None;
    keymap_name: string = "";
    cmd_name: string = "";

    for proc_header.notes {
        if it.text == "cb" {
            track_proc = true;
            if flags & .Verbose log("found reloadable callback %", proc_header.name);
            break;
        } else if String.starts_with(it.text, CMD_PROC_PREFIX) {
            proc_flags = is_valid_keymap_proc(proc_header);
            if proc_flags == .None {
                compiler_report("Cmd_ proc has invalid signature; it must be a Key_Press_Proc or Key_Hold_Proc.");
            }

            text := it.text;
            advance(*text, CMD_PROC_PREFIX.count);
            if !text {
                keymap_name = DEFAULT_KEYMAP_NAME;
                cmd_name = proc_header.name;
            } else {
                if text[0] != #char ":" {
                    compiler_report("Expected @cmd or @cmd:KeymapName:CmdName or @cmd:KeymapName");
                }
                advance(*text, 1);

                found, left, right := String.split_from_left(text, #char ":");
                if !found {
                    keymap_name = text;
                    if !keymap_name {
                        keymap_name = DEFAULT_KEYMAP_NAME;
                    }
                    cmd_name    = proc_header.name;
                } else {
                    keymap_name = left;
                    cmd_name    = right;
                }
            }

            track_proc = true;
            if flags & .Verbose log("found command procedure %", proc_header.name);
            break;
        }
    }

    if track_proc {
        file := proc_header.enclosing_load;
        if mark_file(p, file) {
            // Each Message_File also gets a list of Code_Procedure_Headers we care about.
            entries_ptr := find_or_add(*files, file);
            array_add(*entries_ptr.procs, .{ proc_header, keymap_name, cmd_name, proc_flags });
        }
    }
}


is_valid_keymap_proc :: (using proc: *Code_Procedure_Header) -> Proc_Flags {
    if returns.count != 0 {
        return .None;
    }

    if arguments.count == 1 {
        // TODO: check for a single boolean argument here.
        return .Key_Hold_Proc;
    } else if arguments.count == 0 {
        return .Key_Press_Proc;
    }

    return .None;
}

should_include_declaration :: (using p: *Globals_Reload_Metaprogram_Plugin, decl: *Code_Declaration) -> bool {
    // Ignore non-global variables.
    if decl.flags & .IS_GLOBAL == 0
        return false;

    // Ignore constant or elsewhere-defined globals. (It doesn't make sense to persist them across live reload changes for now.)
    if decl.flags & (.IS_CONSTANT | .ELSEWHERE) != 0
        return false;

    // Ignore globals marked as not reloadable with the @noreload note.
    for decl.notes if it.text == "noreload" {
        if flags & .Verbose log("Skipping Code_Declaration '%' because it's marked as @noreload\n", decl.name);
        return false;
    }

    return true;
}

should_include_file_cached :: (using p: *Globals_Reload_Metaprogram_Plugin, file: *Message_File) -> (include: bool, was_new: bool) {
    was_new := false;

    // Save some work for the common case where we get many declarations from the same file in a row.
    if last_lookup.file != file || last_lookup.result == .Unknown {
        was_new = true;
        should_include := should_include_file(p, file, should_include_file_userdata);
        last_lookup = .{ file, ifx should_include Include_Result.Include else Include_Result.Ignore };
    }

    return last_lookup.result == .Include, was_new;
}

should_include_file :: (using p: *Globals_Reload_Metaprogram_Plugin, file: *Message_File, userdata: *void) -> bool {
    if !file.enclosing_import {
        // Some special *Message_Files do not have *Message_Import, like .added_strings_w1.jai We don't want to recurse, so stop here.
        return false;
    }

    // Don't try to scrape values out of generated code. Maybe this could change?
    if file.from_a_string {
        return false;
    }

    module_name := file.enclosing_import.module_name;

    // Take note of the module pointer for our special "reload common" module, so we can add functions to it later.
    if module_name == RELOAD_COMMON_MODULE_NAME {
        reload_common_module = file.enclosing_import;
    }

    // Empty module name means "the main application" module.
    if module_name == "" {
        return (flags & .Reload_Globals_In_Main_Application) != 0;;
    }

    // Don't touch compiler internals.
    if array_find(never_reload_modules, module_name) {
        return false;
    }

    is_stdlib := String.find_index_from_left(module_name, "/jai/modules") != -1;

    if !is_stdlib {
        return true;
    }

    if array_find(allow_stdlib_module_names, module_name) {
        return true;
    }

    return false;
}

emit_code :: (using p: *Globals_Reload_Metaprogram_Plugin) {
    if flags & .Verbose log("Globals_Reload plugin adding code for workspace %\n", p.workspace);

    if files.count == 0 {
        add_build_string_to_module(p, #string END
// No globals found to reload.
get_all_globals :: (result: *[..]Global_Entry) {}
END, reload_common_module);
        return;
    }

    name_str_index   := 0;
    module_str_index := 0;

    name_str_indices: [..]int;
    name_hashes: [..]u32;

    // Get all entries out of the 'files' Hash_Table and precompute some data we need.
    file_entries: [..]struct {
        message_file: *Message_File;
        decls: [..]*Code_Declaration;
        procs: [..]Proc_Entry;
        module_offset: int = -1;
        global_offset: int = -1;
        module_name_hash: u32 = 0;
        import: *Message_Import = null;
        module_name_id: string = "";
    };

    for decls_and_procs, message_file: p.files {
        it := array_add(*file_entries);
        it.* = .{
            message_file=message_file,
            decls=decls_and_procs.decls,
            procs=decls_and_procs.procs
        };

        // Either we have decls, or procs, or both.
        assert(it.decls.count > 0 || it.procs.count > 0);
        if it.decls.count > 0 {
            it.import = it.decls[0].enclosing_load.enclosing_import;
        } else if it.procs.count > 0 {
            it.import = it.procs[0].proc.enclosing_load.enclosing_import;
        }

        it.module_name_id = String.replace(it.import.module_name, "/", "__",, temp);
    }

    // Now we have a global ordering of decls.

    // Sort them by filename.
    quick_sort(file_entries, (a, b) => String.compare(a.message_file.fully_pathed_filename, b.message_file.fully_pathed_filename));

    // Figure out how many files there are for each module.
    total_file_counts: Table(*Message_Import, int);
    total_decl_count := 0;
    for * file_entries {
        import := it.import;
        #if EXTRA_CHECKS for it.decls assert(it.enclosing_load.enclosing_import == import);

        ptr := find_or_add(*total_file_counts, import);
        previous_count := ptr.*;
        ptr.* += it.decls.count;
        it.module_offset = previous_count;

        it.global_offset = total_decl_count;
        total_decl_count += it.decls.count;

        for decl: it.decls {
            array_add(*name_str_indices, name_str_index);
            array_add(*name_hashes, get_hash(decl.name));
            name_str_index += decl.name.count + 1;
        }

        it.module_name_hash = get_hash(import.module_name); // TODO nocommit
    }

    // Each module's file gets a function which adds entries to the #no_reset array created above.
    // This way we can still have visibility into #scope_file globals.
    global_decl_index := 0;
    for file_entry: file_entries {
        import := file_entry.import;
        #if EXTRA_CHECKS {
            for decl: file_entry.decls {
                assert(decl.enclosing_load.enclosing_import == import);
            }
            assert(file_entry.offset >= 0);
            assert(file_entry.global_offset >= 0);
        }

        sb: String_Builder;
        func_name := tprint("file_%_%_globals", file_entry.module_name_id, it_index);
        append(*sb, tprint(#string END
// Exposing globals from file scope '%'
RC :: #import "Reload_Common";
#import "Basic"; // TODO: remove array_add from functions and just return slices
% :: (result: *[..]RC.Global_Entry) {
    array_add(result,
END, file_entry.message_file.fully_pathed_filename, func_name));
        for it, decl_index: file_entry.decls {
            name := it.name;
            loc := it.location;
            append(*sb, tprint(#string END
        .{ name_hash=% /* "%" */, module_name_hash=% /* "%" */, data=*%, size=size_of(type_of(%)), ti=type_info(type_of(%)) },
END,
                    name_hashes[global_decl_index], name, file_entry.module_name_hash, import.module_name, name, name, name));
            global_decl_index += 1;
        }
        append(*sb, tprint(#string END
    );
}
#poke_name RC %;
END, func_name));
        for file_entry.procs {
            append(*sb, tprint("#poke_name RC %;\n", it.proc.name));
        }
        add_build_string(builder_to_string(*sb), p.workspace, file_entry.message_file);
    }

    // Finally, make the function that collects all globals from all modules and all their files.
    {
        sb: String_Builder;
        append(*sb, "get_all_globals :: (result: *[..]Global_Entry) {\n");
        for file_entry: file_entries {
            import := file_entry.import;
            append(*sb, tprint(#string END
    file_%_%_globals(result);
END, file_entry.module_name_id, it_index));
        }
        append(*sb, "}\n");

        append(*sb, "get_procedure_by_name :: (name: string) -> *void {\n");
        for file_entry: file_entries {
            for proc_entry: file_entry.procs {
                append(*sb, tprint(#string END
    if name == "%1" return xx %1;
END, proc_entry.proc.name));
            }
        }
        append(*sb, "    return null;\n");
        append(*sb, "}\n");

        append(*sb, #string END
Keymap_Proc_Entry :: struct {
    union {
        press_proc: ();
        hold_proc: (hold: bool);
    }
    keymap_name: string;
    cmd_name: string;
    flags: Proc_Flags;
}
END);
        append(*sb, "get_keymap_procs :: (procs: *[..]Keymap_Proc_Entry) {\n");
        append(*sb, "    using,only(array_add) _ :: #import \"Basic\";");
        for file_entry: file_entries {
            for proc_entry: file_entry.procs {
                using proc_entry;
                if flags == {
                case .Key_Press_Proc; append(*sb, tprint("    array_add(procs, .{ press_proc = xx %, keymap_name = \"%\", cmd_name = \"%\", flags = .Key_Press_Proc });\n", proc.name, keymap_name, cmd_name));
                case .Key_Hold_Proc;  append(*sb, tprint("    array_add(procs, .{ hold_proc = xx %,  keymap_name = \"%\", cmd_name = \"%\", flags = .Key_Press_Proc });\n", proc.name, keymap_name, cmd_name));
                }
            }
        }
        append(*sb, "}");

        if reload_common_module != null {
            add_build_string_to_module(p, builder_to_string(*sb), reload_common_module);
        }
    }
}

add_build_string_to_module :: (using p: *Globals_Reload_Metaprogram_Plugin, str: string, message_import: *Message_Import) {
    // There's a single Message_Import which has an empty fully_pathed_filename.
    // This corresponds to the "module" which is your application/DLL.
    // Passing it to add_build_string causes a crash as of Oct 2025, but the workaround is to just use add_build_string without a message_import argument.

    if message_import.fully_pathed_filename {
        add_build_string(str, p.workspace, message_import);
    } else {
        add_build_string(str, p.workspace);
    }
}

Proc_Entry :: struct {
    proc:        *Code_Procedure_Header;
    keymap_name: string;
    cmd_name:    string;
    flags:       Proc_Flags;
}

CMD_PROC_PREFIX     :: "cmd";
DEFAULT_KEYMAP_NAME :: "Main";

#import "Reload_Common";
#import "Basic";
#import "Compiler";
String :: #import "String";
#import "Sort";
#import "Hash_Table";
#import "Hash";
