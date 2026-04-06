/*

Records global declarations marked with @init, and global declarations whose struct
type is marked with @init_group. Then generates:

    call_init_functions();

which merely calls init(...) on each collected target.
*/

Init_Metaprogram :: struct {
    using #as plugin: Metaprogram_Plugin;

    did_generate_code := false;
    verbose := false;

    init_targets: [..] Init_Target;
}

Init_Target :: struct {
    decl: *Code_Declaration;
    member_name: string;
}

get_plugin :: () -> *Metaprogram_Plugin {
    p := New(Init_Metaprogram);
    p.message = on_compiler_message;
    return p;
}

on_compiler_message :: (_p: *Metaprogram_Plugin, msg: *Message) {
    using p := cast(*Init_Metaprogram) _p;

    if msg.kind == {
    case .TYPECHECKED;
        for (cast(*Message_Typechecked) msg).declarations {
            decl := it.expression;
            if !decl return;
            if (decl.flags & .IS_GLOBAL) == 0 continue;

            if decl_has_note(decl, "init") {
                if verbose log("Init_Metaprogram: found @init on global declaration '%'.", decl.name);
                array_add(*init_targets, .{decl = decl});
            }

            struct_decl, struct_node := resolve_struct_declaration_for_global(decl);
            if !struct_has_init_group(struct_decl, struct_node) continue;
            log("STRUCT INIT GROUP %", decl.name);
            if !struct_node || !struct_node.block || !struct_node.block.members {
                compiler_report("@init_group currently requires a struct declaration with explicit field declarations.");
                continue;
            }

            if verbose log("Init_Metaprogram: found @init_group on global struct declaration '%'.", decl.name);
            for member_entry: struct_node.block.members {
                if !member_entry || member_entry.kind != .DECLARATION continue;
                member_decl := cast(*Code_Declaration) member_entry;
                array_add(*init_targets, .{
                    decl = decl,
                    member_name = copy_string(member_decl.name),
                });
            }
        }

    case .PHASE;
        phase := cast(*Message_Phase) msg;
        if phase.phase == .TYPECHECKED_ALL_WE_CAN && !did_generate_code {
            did_generate_code = true;

            if verbose log("Init_Metaprogram: generating code for % init targets.", init_targets.count);

            sb: String_Builder;
            append(*sb, "call_init_functions :: () {\n");
            for init_targets append_init_call(*sb, it);
            append(*sb, "}\n");
            add_build_string(builder_to_string(*sb), p.workspace);
        }
    }
}

#scope_file

decl_has_note :: (decl: *Code_Declaration, note_name: string) -> bool {
    if !decl || note_name.count == 0 return false;
    for decl.notes if it.text == note_name return true;
    return false;
}

struct_has_note :: (st: *Code_Struct, note_name: string) -> bool {
    if !st || note_name.count == 0 return false;
    for st.notes if it.text == note_name return true;
    return false;
}

resolve_struct_node_from_type_expr :: (node: *Code_Node, depth: s64 = 0) -> *Code_Struct {
    if !node || depth > 8 return null;
    if node.kind == .STRUCT return cast(*Code_Struct) node;
    if node.kind == .DECLARATION {
        decl := cast(*Code_Declaration) node;
        if decl.expression return resolve_struct_node_from_type_expr(decl.expression, depth + 1);
        return null;
    }
    if node.kind == .IDENT {
        ident := cast(*Code_Ident) node;
        if ident.resolved_declaration return resolve_struct_node_from_type_expr(cast(*Code_Node) ident.resolved_declaration, depth + 1);
        return null;
    }
    if node.kind == .TYPE_INSTANTIATION {
        inst := cast(*Code_Type_Instantiation) node;
        if inst.type_valued_expression return resolve_struct_node_from_type_expr(inst.type_valued_expression, depth + 1);
        return null;
    }
    return null;
}

resolve_struct_declaration_for_global :: (decl: *Code_Declaration) -> (*Code_Declaration, *Code_Struct) {
    if !decl || !decl.type_inst || !decl.type_inst.result || decl.type_inst.result.type != .STRUCT return null, null;

    struct_node := resolve_struct_node_from_type_expr(decl.type_inst.type_valued_expression);
    type_decl: *Code_Declaration;
    if decl.type_inst.type_valued_expression && decl.type_inst.type_valued_expression.kind == .IDENT {
        ident := cast(*Code_Ident) decl.type_inst.type_valued_expression;
        type_decl = ident.resolved_declaration;
    }
    return type_decl, struct_node;
}

struct_has_init_group :: (struct_decl: *Code_Declaration, struct_node: *Code_Struct) -> bool {
    if struct_has_note(struct_node, "init_group") return true;
    if decl_has_note(struct_decl, "init_group") return true;
    return false;
}

append_init_call :: (sb: *String_Builder, target: Init_Target) {
    decl := target.decl;
    if !decl return;

    if decl.enclosing_load && decl.enclosing_load.enclosing_import && decl.enclosing_load.enclosing_import.module_name {
        import := decl.enclosing_load.enclosing_import;
        module_name := import.module_name;
        module_name_id := sanitize_identifier(module_name);
        import_suffix := "";
        if ends_with(module_name, ".jai") {
            import_suffix = ",file";
            module_name = import.fully_pathed_filename;
        }
        print_to_builder(sb, "    %1 :: #import%4 \"%2\";\n", module_name_id, module_name, decl.name, import_suffix);
        if target.member_name.count != 0 {
            print_to_builder(sb, "    init(*%.%.%);\n", module_name_id, decl.name, target.member_name);
        } else {
            print_to_builder(sb, "    init(*%.%);\n", module_name_id, decl.name);
        }
        return;
    }

    if target.member_name.count != 0 {
        print_to_builder(sb, "    init(*%.%);\n", decl.name, target.member_name);
    } else {
        print_to_builder(sb, "    init(*%);\n", decl.name);
    }
}

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
