/*

A Metaprogram_Plugin which observes the Jai compilation of a dynamic library and emits
an "interface module" that can be used to call its functions.

## Example

If you compile a DLL with this plugin included, that has exported functions like this:

    #program_export
    my_func :: () -> int #c_call { return 42; }

You get a generated module that can be used to call those functions:

    my_func :: () -> int #elsewhere #c_call My_Lib;
    My_Lib :: #library "path/to/dynamic_lib.dll";

*/

// TODO:
//
// support @jdll_export on proc header, as well as on proc body (more readable)
//
// add an option to mark the files as readonly since they bring some duplication into the tree
//
// install_name_tool to @loader_path/name.dylib on mac?

// @DLLBoundaryBug - we wrap exported functions in #c_call to work around compiler bugs
// with jai ABI functions (reported, not fixed as of Feb 21 2026)

#scope_file

DEFAULT_VERBOSE :: false;
LOG_ALL_GENERATED_CODE :: false;

// Files written by this module will start with this string.
GENERATED_MODULE_START_TAG :: "// Auto-generated";

#scope_module

get_plugin :: () -> *JDLL_Metaprogram_Plugin {
    return New(JDLL_Metaprogram_Plugin);
}

deinit :: (using plugin: *JDLL_Metaprogram_Plugin) {
    array_free(*exported);
    free(output.generated_module_filename);
    plugin.* = {};
}

JDLL_Metaprogram_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = on_compiler_message;

    // Options for users of the plugin.
    using options: struct {
        verbose := DEFAULT_VERBOSE;
        include_files: [..]string;
        export_note := "jdll_export";
    };

    // Filled by the plugin, you can inspect after the build.
    output: struct {
        // The Jai interface module to the dynamic library.
        generated_module_filename: string;
    }

    // Internal state
    using compilation_state: struct {
        did_generate: bool;
        exported: [..]struct {
            decl: *Code_Declaration;
            flags: enum_flags {
                NEEDS_WRAPPER;
            };
        };
    };
}

on_compiler_message :: (_p: *Metaprogram_Plugin, compiler_message: *Message) {
    using p := cast(*JDLL_Metaprogram_Plugin)_p;
    if compiler_message.kind == {
    case .TYPECHECKED;
        for compiler_message.(*Message_Typechecked).declarations {
            using decl := it.expression;
            if !decl continue;

            if flags & .PROGRAM_EXPORT != 0 {
                // Ignore compiler-generated exports __jai_runtime_fini and __jai_runtime_init
                if name.count > 5 && name[0] == #char "_" {
                    if String.starts_with(name, "__jai_") || String.starts_with(name, "_jdll_") {
                        continue;
                    }
                }

                if verbose log("JDLL will bind to #program_export function '%'", decl.name);
                array_add(*exported, .{ decl=decl });
            } else if decl.notes && options.export_note {
                for decl.notes {
                    if it.text == options.export_note {
                        if verbose log("JDLL will bind to % function %", options.export_note, decl.name);
                        array_add(*exported, { decl, .NEEDS_WRAPPER });
                        emit_wrapper(p, decl);
                    }
                }
            }

        }
    case .COMPLETE;
        if compiler_message.(*Message_Complete).error_code == .NONE {
            if p.did_generate {
                log_error("WARNING: JDLL has already generated code, so we are ignoring this .COMPLETE compiler message");
            } else {
                generate_interface_module_output(p);
            }
        }
    }
}

emit_wrapper :: (p: *JDLL_Metaprogram_Plugin, decl: *Code_Declaration)  {
    scoped_program_print_procedure_bodies(false);

    assert(decl.expression.kind == .PROCEDURE_HEADER);
    proc_header := decl.expression.(*Code_Procedure_Header);

    proc_header_copy := proc_header.*;
    proc_header_copy.procedure_flags |= .C_CALL; // @DLLBoundaryBug - make sure the exported function is #c_call

    c: String_Builder;

    // Generate the function wrapper: a #program_export #c_call version of the original Jai function.
    pr(*c, "#program_export _jdll_% :: ", decl.name, newline=false);
    print_expression(*c, *proc_header_copy);
    pr(*c, " {");
    pr(*c, "    push_context,defer_pop;"); // @DLLBoundaryBug

    // Generate the inner function call
    if proc_header.returns.count == 0 {
        pr(*c, "    ", newline=false);
    } else {
        pr(*c, "    return ", newline=false);
    }
    pr(*c, "%(", proc_header.name, newline=false);
    for proc_header.arguments {
        append(*c, it.name);
        if it_index != proc_header.arguments.count - 1 {
            pr(*c, ", ");
        }
    }
    pr(*c, ");");
    pr(*c, "}");

    // Finally, add the generated wrapper code to the same scope as the original function.
    build_string := builder_to_string(*c,, temp);
    #if LOG_ALL_GENERATED_CODE log("%", build_string);
    add_build_string(build_string, p.workspace, decl.enclosing_load);
}

generate_interface_module_output :: (using p: *JDLL_Metaprogram_Plugin) -> (ok: bool) {
    assert(!did_generate);
    did_generate = true;

    assert(p.workspace != 0, "workspace is 0");
    build_opts := get_build_options(p.workspace);

    if !build_opts.output_executable_name {
        compiler_report("JDLL: workspace build options had no output_executable_name; cannot generate interface module.");
        return false;
    }

    interface_module_output := build_opts.output_executable_name;
    lib_name                := tprint("%_lib", interface_module_output);
    module_dirname          := tprint("modules/%", interface_module_output);
    File.make_directory_if_it_does_not_exist(module_dirname, recursive=true);

    sb: String_Builder;
    print_to_builder(*sb, "% JDLL interface module '%'\n\n", GENERATED_MODULE_START_TAG, interface_module_output);

    scoped_program_print_procedure_bodies(false);

    for entry: exported {
        decl := entry.decl;
        exported_name := decl.name;

        // TODO: we could also support #program_export structs or variables.
        assert(decl.expression.kind == .PROCEDURE_HEADER);

        if entry.flags & .NEEDS_WRAPPER {
            exported_name = tprint("_jdll_%", exported_name);
        } else {
            if decl.expression.(*Code_Procedure_Header).procedure_flags & .C_CALL == 0 {
                MSG := tprint(#string END
JDLL - missing #c_call
JDLL currently requires #program_exported procedure '%' to be #c_call and
use push_context or push_context,defer pop inside. Once the compiler bug
involving #elsewhere Jai ABI'd procs is fixed, this error can go away.
You can use @jdll_export to automatically generate a #program_export
wrapper instead.
        END, decl.name);
                compiler_report(MSG, loc=make_location(decl.expression));
                assert(false);
            }
        }

        // Remove the #program_export flag since we're writing out code that does the importing.
        decl_copy := decl.*;
        decl_copy.flags &= ~.PROGRAM_EXPORT;
        print_declaration(*sb, *decl_copy);

        // TODO: maybe just modify the flags so print_declaration does this part for us
        if entry.flags & .NEEDS_WRAPPER {
            pr(*sb, " #foreign % \"%\";", lib_name, exported_name);
        } else {
            pr(*sb, " #foreign %;", lib_name);
        }

    }

    // make sure include_files get automatically #loaded
    for p.options.include_files {
        print_to_builder(*sb, "#load \"%\";\n", String.path_filename(it));
    }

    append(*sb, tprint(#string END

#scope_file
#if OS == .MACOS   %1 :: #library,no_static_library "macos/%2";
#if OS == .WINDOWS %1 :: #library,no_static_library "win/%2";
END, lib_name, interface_module_output));

    filename := sprint("%/module.jai", module_dirname);
    p.output.generated_module_filename = filename;

    // copy include_files into the module directory.
    for p.options.include_files {
        copy_file(it, tprint("%/%", module_dirname, String.path_filename(it)));
    }

    if !check_if_file_is_ok_to_overwrite(filename) {
        return false;
    }

    if !File.write_entire_file(filename, builder_to_string(*sb)) {
        compiler_report(tprint("Failed to generate interface module '%'", interface_module_output));
        return false;
    }

    if verbose {
        log("Wrote JDLL interface for '%' to '%'", interface_module_output, filename);
    }

    return true;
}

#scope_file
#import "Compiler";
#import "Basic";
#import "Program_Print";
String :: #import "String";
using,only(file_open, file_read) File :: #import "File";
using,only(file_exists, copy_file) File_Utilities :: #import "File_Utilities";
pr :: (sb: *String_Builder, str: string, args: ..Any, newline := true) {
    final_str: string;
    if newline final_str = String.join(str, "\n",, temp);
    else final_str = str;
    print_to_builder(sb, final_str, ..args,, temp);
};

scoped_program_print_procedure_bodies :: (enabled: bool) #expand {
    old_print_procedure_bodies := context.print_procedure_bodies;
    context.print_procedure_bodies = enabled;
    `defer context.print_procedure_bodies = old_print_procedure_bodies;
}

check_if_file_is_ok_to_overwrite :: (filename: string) -> bool {
    if !file_exists(filename) {
        return true;
    }

    file, ok := file_open(filename);
    assert(ok);

    // Make sure the file begins with our expected "// Auto-generated" comment.
    buf: [GENERATED_MODULE_START_TAG.count + 1]u8;
    success, total_read := file_read(file, buf.data, GENERATED_MODULE_START_TAG.count);
    if total_read != GENERATED_MODULE_START_TAG.count {
        compiler_report(tprint("Refusing to overwrite file named '%'. We could not read enough bytes to check if it was auto-generated.",
            filename));
        return false;
    }

    str := string.{ buf.count - 1, buf.data }; // Remove null byte
    if str != GENERATED_MODULE_START_TAG {
        compiler_report(tprint("Refusing to overwrite file named '%'. It does not start with our expected tag '%'.\nThe bytes we did read: \"%\"",
            filename, GENERATED_MODULE_START_TAG, str));
        return false;
    }

    return true;
}
