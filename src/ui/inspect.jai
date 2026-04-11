Inspect_Opts :: struct {
    is_pointer: bool;
    show_name:  bool = true;
    in_table:   bool;
    flatten_struct: bool;
    change_callback: ();
    source_code_location: Source_Code_Location;
    notes: []string; // at-sign @jai_notes on this field
}


inspect_globals :: (show_window: *bool) {
    using ui_opts.globals;

    if show_window != null && show_window.* == false return;

    defer End();
    if !Begin("Globals", show_window, .NoFocusOnAppearing) return;

    Text("Search"); SameLine();
    InputText("##Search", *search_text, .None, null, null);
    Separator();

    table_node_id: s32 = 44328;
    if BeginTable("##properties", 2, .Resizable | .ScrollY) {
        defer EndTable();
        PushID(table_node_id);
        defer PopID();

        TableSetupColumn("", .WidthFixed);
        TableSetupColumn("", .WidthStretch, 3.0);

        auto_release_temp();
        globals: [..]Global_Entry;
        globals.allocator = temp;
        #if GLOBALS_RELOAD_PLUGIN_INCLUDED get_all_globals(*globals);

        for globals {
            // filter
            if search_text &&
                String.find_index_from_left(it.name, search_text) == -1 &&
                String.find_index_from_left(it.module_name, search_text) == -1 continue;

            label: string;
            if it.module_name label = tprint("%.%", it.module_name, it.name);
            else label = it.name;
            struct_table_row(label, source_code_location=it.source_code_location);

            inspect(
                name=temp_c_string(it.name),
                data=it.data,
                info=it.ti,
                options=.{ show_name = false, in_table = true });
        }
    }
}

struct_table_row :: (field_desc_name: string, source_code_location: Source_Code_Location = .{}) {
    struct_table_row(temp_c_string(field_desc_name), source_code_location=source_code_location);
}

/*
right_align_next_text_in_column :: (text: *u8) {
    posX := (GetCursorPosX() + GetColumnWidth() - CalcTextSize(field_desc_name).x - GetScrollX() - 2 * GetStyle().ItemSpacing.x);
    if posX > GetCursorPosX()
        SetCursorPosX(posX);
}
*/

// TODO: make a "call_on_bg_thread" abstraction? maybe?

go_to_definition_in_editor :: (using source_code_location: Source_Code_Location) {
    #import "Thread";

    data := New(Source_Code_Location);
    data.* = source_code_location;

    thread := New(Thread);
    thread.data = data;
    thread_init(thread, _go_to_definition_in_editor);
    thread_start(thread);
}

_go_to_definition_in_editor :: (thread: *Thread) -> s64 {
    Process :: #import "Process";

    editor: enum {
        Cursor;
        Zed;
    } = .Zed;

    using loc := cast(*Source_Code_Location) thread.data;

    args: [..]string;
    if #complete editor == {
    case .Cursor;
        array_add(*args, "cursor", "-g", tprint("%:%", fully_pathed_filename, line_number));
    case .Zed;
        array_add(*args, "zed", tprint("%:%", fully_pathed_filename, line_number));
    }

    log(String.join(..args, separator=" "), user_flags=1);

    RELATIVE_PATH_TO_SOURCE_CODE :: "..";
    res, stdout, stderr := Process.run_command(..args, working_directory=RELATIVE_PATH_TO_SOURCE_CODE);
    if stdout log("stdout: %\n", stdout);
    if stderr log_error("stderr: %\n", stderr);

    free(thread.data);
    free(thread);

    return 0;
}

struct_table_row :: (field_desc_name: *u8, source_code_location: Source_Code_Location = .{}) {
    TableNextRow();
    PushPopID(field_desc_name);

    // COLUMN: the field name.
    TableNextColumn();
    AlignTextToFramePadding();
    {
        PushPopFont(fonts.mono, fonts.MAIN_SIZE);
        // right_align_next_text_in_column(field_desc_name);
        if Selectable(field_desc_name, false) {
            if source_code_location.fully_pathed_filename != "" {
                go_to_definition_in_editor(source_code_location);
            }
        }
        //TextUnformatted(field_desc_name);

        if BeginPopupContextItem() {
            defer EndPopup();
            if source_code_location.fully_pathed_filename != "" {
                if Button("Go to definition") {
                    go_to_definition_in_editor(source_code_location);
                    CloseCurrentPopup();
                }
            } else {
                TextDisabled("Go to definition (disabled)");
            }
        }
    }

    // COLUMN: the field value.
    TableNextColumn();
}


// a port of ImGui::CheckboxFlagsT from imgui_widgets.cpp
CheckboxFlags64 :: (label: *u8, flags: *u64, flags_value: u64) -> bool {
    all_on := (flags.* & flags_value) == flags_value;
    any_on := (flags.* & flags_value) != 0;

    pressed: bool;

    if !all_on && any_on
    {
        ImGuiItemFlags_MixedValue :: 1 << 6; // must match undocumented flag in imgui_internal.h
        PushItemFlag(xx ImGuiItemFlags_MixedValue, true);
        defer PopItemFlag();
        pressed = Checkbox(label, *all_on);
    }
    else
    {
        pressed = Checkbox(label, *all_on);
    }
    if pressed
    {
        if all_on
            flags.* |= flags_value;
        else
            flags.* &= ~flags_value;
    }
    return pressed;
}

/*
// TODO: clean this up!
insp :: ($c: Code) {
    T :: c.type;
    name :: #run -> string {
        root, expressions := compiler_get_nodes(c);

        //print("CODE: %, T: %\n", c, T);
        //print("root: %\n", root.*);
        //print("expressions(%):\n", expressions.count);
        //for expressions {
            //print("  %: %\n", it_index, it.*);
        //}

        name_for_code :: (code: *Code_Node) -> string {
            if code.kind == .UNARY_OPERATOR {
                unary := cast(*Code_Unary_Operator)code;
                return name_for_code(unary.subexpression);
            }

            if code.kind == .IDENT {
                ident := cast(*Code_Ident)code;
                //print("IDENT! %\n", ident.*);
                //print("name: %\n", ident.name);
                return ident.name;
            }
            return "";
        }

        return name_for_code(root);

    }

    #insert,scope(c) #run tprint("UI.inspect(\"%\", *%);", name, name);
}
*/

inspect :: (name: *u8, val: *$T, opts: Inspect_Opts = .{}) -> bool {
    return inspect(name, val, type_info(T), opts);
}

inspect_flat :: (val: *$T, opts: Inspect_Opts = .{}) -> bool {
    opts_copy := opts;
    opts_copy.flatten_struct = true;
    return inspect(null, val, type_info(T), opts_copy);
}

inspect :: (name: *u8, data: *void, info: *Type_Info, options: Inspect_Opts = .{}) -> bool {
    change := false;
    default_size: ImVec2;
    label: *u8;

    opts := options;
    flatten_struct := opts.flatten_struct;
    opts.flatten_struct = false;

    name_str: string;
    if !opts.show_name || flatten_struct {
        label = tprint("##%\0", name).data;
    } else {
        name_str = to_string(name);
        label = name;
    }

    using Type_Info_Tag;
    if #complete info.type == {
        case .INTEGER;
            ok, data_type := imgui_data_type(cast(*Type_Info_Integer)info);
            if ok {
                InputScalar(label, data_type, data);
            }

        case .FLOAT;
            DEFAULT_MIN :: 0.01;
            DEFAULT_MAX :: 1.0;
            note_parsed, note_min, note_max := parse_range_note_floating_point(opts.notes, DEFAULT_MIN, DEFAULT_MAX);
            if info.runtime_size == {
                case 4;
                    if note_parsed {
                        change |= SliderFloat(label, data, cast(float)note_min, cast(float)note_max);
                    } else {
                        change |= DragFloat(label, data, cast(float)note_min, cast(float)note_max);
                    }
                case 8;
                    if note_parsed {
                        change |= SliderScalar(label, .Double, data, *note_min, *note_max);
                    } else {
                        change = InputDouble(label, data, note_min, note_max);
                    }
            }

        case .BOOL;
            change = Checkbox(label, data);

        case .STRING;
            s := data.(*string);
            if s.count change = InputText(label, s.data, xx s.count, .ReadOnly);    // @@ We could allow editing of strings too.
            else       change = InputText(label, "(null)", 6,        .ReadOnly);
        case .POINTER;
            info_pointer := info.(*Type_Info_Pointer);
            next_data := (cast(**void)data).*;
            if next_data == null {
                PushPopFont(fonts.mono, fonts.MAIN_SIZE);
                if info_pointer.pointer_to.type == .STRUCT
                    TextUnformatted(tprint("%: (%)null", name, (cast(*Type_Info_Struct)info_pointer.pointer_to).name));
                else
                    TextUnformatted(tprint("%: null", name));
            } else {
                opts_copy := opts;
                opts_copy.is_pointer = true;
                change = inspect(label, next_data, info_pointer.pointer_to, opts_copy);
            }
        case .PROCEDURE;
            Text("procedure");
        case .VOID;
            TextUnformatted(tprint("%: % (void)", name_str, data));
        case .CODE;
            Text("Code");
        case .STRUCT;
            info_struct := cast(*Type_Info_Struct) info;

            struct_name := ifx info_struct.name else "<unnamed struct>";

            skip_label := opts.in_table || flatten_struct;

            struct_name_cstr: string;
            if opts.is_pointer struct_name_cstr = tprint("*%\0", struct_name);
            else               struct_name_cstr = tprint("%\0", struct_name);

            if info_struct.members.count == 0 {
                PushPopFont(fonts.mono, fonts.MAIN_SIZE);
                if skip_label {
                    Text(name_str);
                    SameLine();
                }
                PushPopStyleColor(.Text, GetStyle().Colors[Col.TextDisabled]);
                Text(struct_name_cstr);
            } else {
                AddSameLineStructName :: () #expand {
                    // TODO: instead of this, push the tree node label style.  this would be better, because then the entire tree node label would be clickable >:)
                    SameLine();
                    PushPopFont(fonts.mono, fonts.MAIN_SIZE);
                    TextDisabled(struct_name_cstr);
                }

                Math :: #import "Math";
                if info_struct == cast(*Type_Info_Struct)Math.Vector3 {
                    change = DragFloat3(label, data);
                } else if info_struct == cast(*Type_Info_Struct)Math.Vector4 || info_struct == cast(*Type_Info_Struct)Math.Quaternion {
                    change = DragFloat4(label, data);
                } else if info_struct == cast(*Type_Info_Struct)Math.Matrix4 {
                    for * data.(*Math.Matrix4).v
                        change |= DragFloat4(tprint("##%.%\0", *it.component, name_str, it_index).data, *it.component);
                } else if info_struct == cast(*Type_Info_Struct)Math.Matrix3 {
                    for * data.(*Math.Matrix3).v
                        change |= DragFloat3(tprint("##%.%\0", *it.component, name_str, it_index).data, *it.component);
                } else {
                    // here flatten_struct means we are showing the fields of a
                    // struct without any header or type info at the top. so we
                    // can skip the tree node, etc.
                    show_contents := false;
                    need_tree_pop := false;
                    if flatten_struct {
                        show_contents = true;
                    } else {
                        show_contents = TreeNode(label, name_str);
                        if show_contents need_tree_pop = true;
                        AddSameLineStructName();
                    }

                    if show_contents {
                        highest_offset := -1;
                        for member: info_struct.members {
                            if member.flags & .CONSTANT continue;  // don't show constant fields
                            if has_note(member, "no_ui") continue; // don't show fields with @no_ui note

                            if member.name == { // TODO: clean this up?
                            case "pad"; #through;
                            case "_pad1"; #through;
                            case "_pad2"; #through;
                            case "_pad3"; #through;
                            case "_pad4";
                                continue;
                            }

                            if member.offset_in_bytes <= highest_offset continue; // skip #overlay types, etc.
                            highest_offset = member.offset_in_bytes;

                            if opts.in_table struct_table_row(member.name);

                            member_opts := opts;
                            member_opts.notes = member.notes;
                            change |= inspect(temp_c_string(member.name), data + member.offset_in_bytes, member.type, member_opts);
                        }
                        if need_tree_pop TreePop();
                    }
                }
            }
        case .ARRAY;
            info_array := cast(*Type_Info_Array) info;

            count: s64;
            array_data: *void;
            type_label: string;

            element_type_builder: String_Builder = .{ allocator = temp};
            print_type_to_builder(*element_type_builder, info_array.element_type);
            element_type_label := builder_to_string(*element_type_builder,, temp);

            if info_array.array_type == .FIXED {
                count = info_array.array_count;
                array_data = data;
                type_label = tprint("[%]%", count, element_type_label);
            } else {
                // This case works for both VIEW and RESIZABLE, since they are specced to line up.
                array_pointer := cast(*Resizable_Array) data;
                count = array_pointer.count;
                array_data = array_pointer.data;

                if info_array.array_type == .VIEW {
                    type_label = tprint("[]% = .{ count = % }", element_type_label, count);
                } else if info_array.array_type == .RESIZABLE {
                    type_label = tprint("[..]% = .{ count = % }", element_type_label, count);
                } else {
                    assert(false, tprint("unknown array type %", info_array.array_type));
                }
            }

            //array_count, array_data := Reflection.get_array_count_and_data(data, info_array);
            element_size := info_array.element_type.runtime_size;
            PushFont(fonts.mono, fonts.MAIN_SIZE);
            if TreeNode(label, "%", type_label, count) {
                PopFont();
                for 0..count-1 {
                    item_name := temp_c_string(tprint("%[%]", name_str, it));
                    change |= inspect(item_name, array_data + it * element_size, info_array.element_type, opts);
                }
                TreePop();
            } else {
                PopFont();
            }
        case .ANY;
            any := data.(*Any);
            change |= inspect(label, any.value_pointer, any.type, opts);
        case .ENUM;
            info_enum := cast(*Type_Info_Enum) info;
            if info_enum.enum_type_flags & .FLAGS {
                TextUnformatted(name_str);
                PushPopIndent(GetFrameHeight() * 0.5);
                PushPopStyleVar(.ItemInnerSpacing, .{0, 0});
                PushPopStyleVar(.FramePadding, .{0, 0});
                if info_enum.internal_type.runtime_size > 4 {
                    for info_enum.values {
                        if it == 0 continue;
                        label := temp_c_string(info_enum.names[it_index]);
                        if label == "all" continue;
                        change |= CheckboxFlags64(label, data, cast(u64)it);
                    }
                } else {
                    for info_enum.values {
                        if it == 0 continue;
                        if info_enum.names[it_index] == "all" continue;
                        label := tprint(" %\0", info_enum.names[it_index]).data;
                        change |= CheckboxFlags(label, data, cast(u32)it);
                    }
                }
            } else {
                value := Reflection.get_enum_value(data, info_enum);
                value_name := "";
                for info_enum.names
                    if value == info_enum.values[it_index]
                        value_name = it;

                if BeginCombo(label, temp_c_string(value_name)) {
                    for info_enum.names {
                        is_selected := value == info_enum.values[it_index];
                        if Selectable(temp_c_string(it), is_selected, size=*default_size) {
                            Reflection.set_enum_value(data, info_enum, info_enum.values[it_index]);
                            if opts.change_callback {
                                opts.change_callback();
                            }
                            change = true;
                        }
                        if is_selected ImGui.SetItemDefaultFocus();
                    }

                    EndCombo();
                }
            }

        case .POLYMORPHIC_VARIABLE;
            // @@ ??
        case .TYPE;
            sb: String_Builder = .{allocator = temp};
            append(*sb, name_str);
            append(*sb, ": Type ");
            print_type_to_builder(*sb, data.(**Type_Info).*);
            TextUnformatted(builder_to_string(*sb,, allocator=temp));
        case .OVERLOAD_SET;
            // @@
        case .VARIANT;
            // @Incomplete: Can do something better here.
            change |= inspect(label, data, info.(*Type_Info_Variant).variant_of, opts);
        case .UNTYPED_LITERAL;
            Text("(untyped literal)");
        case .UNTYPED_ENUM;
            Text("(untyped enum)");
    }

    return change;
}

#scope_file

has_note :: (s: $S, note: string) -> bool {
    for s.notes if it == note return true;
    return false;
}

parse_range_note_floating_point :: (notes: []string, default_min: float64, default_max: float64) -> (parsed: bool, range_min: float64, range_max: float64) {
    for notes {
        has_parens := it.count > 2 && it[0] == #char "(" && it[it.count - 1] == #char ")";
        if !has_parens continue;

        // omit parens
        text := it;
        text.data += 1;
        text.count -= 2;

        results := String.split(text, #char ",",, temp);
        if results.count != 2 continue;

        left_ok, range_min, remainder   := string_to_float64_new(results[0]);
        if !left_ok || remainder.count continue;

        right_ok, range_max, remainder= := string_to_float64_new(results[1]);
        if !right_ok || remainder.count continue;

        return true, range_min, range_max;
    }

    return false, default_min, default_max;
}

imgui_data_type :: (using ti_integer: *Type_Info_Integer) -> ok: bool, data_type: ImGui.DataType {
    data_type: DataType;
    ok := true;
    if runtime_size == {
        case 1; data_type = ifx signed then .S8  else .U8;
        case 2; data_type = ifx signed then .S16 else .U16;
        case 4; data_type = ifx signed then .S32 else .U32;
        case 8; data_type = ifx signed then .S64 else .U64;
        case;
            assert(false, "Don't know how to handle integer with Type_Info.runtime_size of %");
            ok = false;
    }
    return ok, data_type;

}

using ImGui :: #import "ImGui";
#import "imgui_extra";

Program_Print :: #import "Program_Print";
String :: #import "String";
Reflection :: #import "Reflection";
#import "Thread";
#import "Basic";
#import "Compiler";
