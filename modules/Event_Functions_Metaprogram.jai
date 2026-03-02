/*

Records function declartions marked with notes like @on_reload.

Then you can call all the noted functions like this:

    call_event_functions(.reload);
*/

Event_Functions_Metaprogram :: struct {
    using #as plugin: Metaprogram_Plugin;

    event_names: [..]string;
    did_generate_code := false;
    verbose := false;

    decls: [..]struct { event_name: string; decl: *Code_Declaration; };
}

get_plugin :: () -> *Metaprogram_Plugin {
    p := New(Event_Functions_Metaprogram);
    p.message = on_compiler_message;
    return p;
}

on_compiler_message :: (_p: *Metaprogram_Plugin, msg: *Message) {
    using p := cast(*Event_Functions_Metaprogram) _p;

    if msg.kind == {
        case .TYPECHECKED;
            for (cast(*Message_Typechecked) msg).declarations {
                for note: it.expression.notes {
                    if note.text.count < 4 || !begins_with(note.text, "on_")
                        continue;


                    if it.expression.expression == null {
                        log_error("Found on_ note on declaration with no expression: %\n", it.expression.name);
                        continue;
                    }

                    if it.expression.expression.kind != .PROCEDURE_HEADER {
                        log_error("Found on_ note on something that wasn't a PROCEDURE_HEADER: %\n", it.expression.expression.kind);
                        continue;
                    }


                    if verbose log("Event_Functions_Metaprogram: found on_XXX note on procedure header: %", it.expression.name);

                    // Get the XXX part from the on_XXX note.
                    event_name := note.text;
                    advance(*event_name, 3);

                    // Note the event name if we haven't seen it already.
                    if !array_find(event_names, event_name)
                        array_add(*event_names, event_name);

                    // Store the declaration for later when we need to generate the function calling code.
                    array_add(*decls, .{ event_name, it.expression });
                }
            }

        case .PHASE;
            phase := cast(*Message_Phase)msg;
            if phase.phase == .TYPECHECKED_ALL_WE_CAN && !did_generate_code {
                did_generate_code = true;

                if verbose log("Event_Functions_Metaprogram: generating code for event names: %", event_names);

                sb: String_Builder;
                defer reset(*sb);
                append(*sb, "// Any function declarations marked with @on_XXX will get make an XXX entry added here.\n");
                append(*sb, "Event_Function_Type :: enum {\n");
                for event_name: event_names {
                    append(*sb, tprint("    %;\n", event_name));
                }
                append(*sb, "};\n\n");

                append(*sb, #string END
call_event_functions :: ($event_function_type: Event_Function_Type) {
    #if event_function_type == {
END);
                for event_name: event_names {
                    append(*sb, tprint(#string END
        case .%;
END, event_name));
                    for it: decls {
                        if it.event_name == event_name {
                            decl := it.decl;

                            // If the declaration is in a module, we need to import the module to call the function on it.
                            if decl.enclosing_load && decl.enclosing_load.enclosing_import && decl.enclosing_load.enclosing_import.module_name {
                                import := decl.enclosing_load.enclosing_import;
                                module_name := import.module_name;
                                module_name_id := sanitize_identifier(module_name);
                                import_suffix := "";
                                if ends_with(module_name, ".jai") {
                                    import_suffix = ",file";
                                    module_name = import.fully_pathed_filename;
                                }
                                append(*sb, tprint(#string END
            %1 :: #import%4 "%2";
            %1.%3();
END, module_name_id, module_name, decl.name, import_suffix));
                            } else {
                                // Otherwise, just call the function directly.
                                append(*sb, tprint(#string END
            %();
END, decl.name));
                            }
                        }
                    }
                }

                append(*sb, #string END
    }
}
END);
                add_build_string(builder_to_string(*sb), p.workspace);
            }
    }
}

#scope_file
sanitize_identifier :: (s: string) -> string {
    result := alloc_string(s.count);

    for c: s {
        if (is_alpha(c) || is_digit(c) || c == #char "_") && c != #char "."
            result[it_index] = c;
        else
            result[it_index] = #char "_";
    }

    return result;
}

#import "Compiler";
#import "Basic";
#import "String";
