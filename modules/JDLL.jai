/*

A Metaprogram_Plugin which observes the Jai compilation of a dynamic library and emits
an "interface module" that can be used to call its functions.

## Example

If you compile a DLL with this plugin included, that has exported functions like this:

    #program_export
    my_func :: () -> int { return 42; }

You get a module that can be used to call those functions:

    my_func :: () -> int #elsewhere My_Lib;
    My_Lib :: #library "path/to/dynamic_lib.dll";

*/

#scope_file
DEFAULT_VERBOSE :: false;

#scope_module

get_plugin :: () -> *JDLL_Metaprogram_Plugin {
    return New(JDLL_Metaprogram_Plugin);
}

JDLL_Metaprogram_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;
    message = on_compiler_message;

    verbose := DEFAULT_VERBOSE;

    using compilation_state: struct {
        exported_decls: [..]*Code_Declaration;
    };
}

on_compiler_message :: (_p: *Metaprogram_Plugin, compiler_message: *Message) {
    using p := cast(*JDLL_Metaprogram_Plugin)_p;
    if compiler_message.kind == {
    case .TYPECHECKED;
        tc := cast(*Message_Typechecked) compiler_message;
        for tc.declarations {
            decl := it.expression;
            if !decl continue;

            if decl.flags & .PROGRAM_EXPORT != 0 {
                // Ignore compiler-generated exports __jai_runtime_fini and __jai_runtime_init
                if String.starts_with(decl.name, "__jai_") {
                    continue;
                }

                if verbose log("found #program_export %", decl.name);
                array_add(*exported_decls, decl);
            }
        }
    case .COMPLETE;
        generate_interface_module_output(p);
    }
}

generate_interface_module_output :: (using p: *JDLL_Metaprogram_Plugin) -> (ok: bool) {
    build_opts := get_build_options(p.workspace);
    interface_module_output := build_opts.output_executable_name;

    if !interface_module_output {
        compiler_report("workspace build options had no output_executable_name");
        return false;
    }

    sb: String_Builder;
    append(*sb, tprint("// Auto-generated interface module for JDLL '%'\n\n", interface_module_output));

    old_print_procedure_bodies := context.print_procedure_bodies;
    context.print_procedure_bodies = false;
    defer context.print_procedure_bodies = old_print_procedure_bodies;

    lib_name := tprint("%_lib", interface_module_output);

    for decl: exported_decls {
        decl_copy := decl.*;

        // Remove the #program_export flag since we're writing out code that does the importing.
        decl_copy.flags &= ~.PROGRAM_EXPORT;
        print_declaration(*sb, *decl_copy);

        // TODO: maybe just modify the flags so print_declaration does this part for us
        symbol_name := decl.name;
        append(*sb, tprint(" #elsewhere % \"%\";\n", lib_name, symbol_name));
    }

    append(*sb, tprint(#string END

#scope_file
#if OS == .MACOS {
%1 :: #library,no_static_library "lib/macos/%2";
} else #if OS == .WINDOWS {
%1 :: #library,no_static_library "lib/win/%2";
}
END, lib_name, interface_module_output));

    module_dirname := tprint("modules/%", interface_module_output);
    File.make_directory_if_it_does_not_exist(module_dirname, recursive=true);
    filename := tprint("%/module.jai", module_dirname);

    if !File.write_entire_file(filename, builder_to_string(*sb)) {
        compiler_report(tprint("Failed to generate interface module '%'", interface_module_output));
        return false;
    }

    if verbose log("Wrote JDLL interface for '%' to '%'", interface_module_output, filename);

    return true;
}

#scope_file
#import "Compiler";
#import "Basic";
#import "Program_Print";
String :: #import "String";
File :: #import "File";
