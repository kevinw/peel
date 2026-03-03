
inspect_globals :: () {
    if !ui_opts.globals.show return;
    if Begin("Globals", *ui_opts.globals.show, .NoFocusOnAppearing) {
        using ui_opts.globals;

        // Search input text box
        Text("Search");
        SameLine();
        InputText("##Search", *search_text, .None, null, null);

        Separator();

        table_node_id :s32 = 44328;

        if BeginTable("##properties", 2, .Resizable | .ScrollY) {
            defer EndTable();
            PushID(table_node_id);
            defer PopID();

            TableSetupColumn("", .WidthFixed);
            TableSetupColumn("", .WidthStretch, 3.0);

            globals: [..]Global_Entry;
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
                    opts=.{ show_name = false, in_table = true });
            }
        }
    }
    End();
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
    #import "Process";

    using loc := cast(*Source_Code_Location) thread.data;

    args: [..]string;
    array_add(*args, "cursor", "-g", tprint("%:%", fully_pathed_filename, line_number));

    String :: #import "String";
    log(String.join(..args, separator=" "), user_flags=1);

    RELATIVE_PATH_TO_SOURCE_CODE :: "..";

    res, stdout, stderr := run_command(..args, working_directory=RELATIVE_PATH_TO_SOURCE_CODE);
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

Inspect_Opts :: struct {
    is_pointer: bool = false;
    show_name: bool = true;
    in_table: bool = false;
    change_callback: ();
    source_code_location: Source_Code_Location = .{};
}

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

inspect :: (name: *u8, val: *$T, opts: Inspect_Opts = .{}) {
    inspect(name, val, type_info(T), opts);
}

inspect :: (name: *u8, data: *void, info:*Type_Info, opts: Inspect_Opts = .{}) {
    default_size: ImVec2;

    label: *u8;

    name_str: string;
    if !opts.show_name {
        label = tprint("##%\0", name).data;
    } else {
        name_str = to_string(name);
        label = name;
    }

    using Type_Info_Tag;
    if #complete info.type == {
        case .INTEGER;
            ti_int := info.(*Type_Info_Integer);
            data_type: DataType;
            ok := true;
            if info.runtime_size == {
                case 1; data_type = ifx ti_int.signed then DataType.S8  else DataType.U8;
                case 2; data_type = ifx ti_int.signed then DataType.S16 else DataType.U16;
                case 4; data_type = ifx ti_int.signed then DataType.S32 else DataType.U32;
                case 8; data_type = ifx ti_int.signed then DataType.S64 else DataType.U64;
                case;
                    assert(false, "don't know how to handle integer with Type_Info.runtime_size of %");
                    ok = false;
            }
            if ok InputScalar(label, data_type, data);

        case .FLOAT;
            if info.runtime_size == {
                case 4; DragFloat(label, data, 0.01, 1.0);
                case 8; InputDouble(label, data, 0.01, 1.0);
            }
        case .BOOL;
            Checkbox(label, data);
        case .STRING;
            s := data.(*string);
            if s.count InputText(label, s.data, xx s.count, .ReadOnly);    // @@ We could allow editing of strings too.
            else       InputText(label, "(null)", 6,        .ReadOnly);
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
                inspect(label, next_data, info_pointer.pointer_to, opts_copy);
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

            skip_label := opts.in_table;

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
                    DragFloat3(label, data);
                } else if info_struct == cast(*Type_Info_Struct)Math.Vector4 || info_struct == cast(*Type_Info_Struct)Math.Quaternion {
                    DragFloat4(label, data);
                } else if info_struct == cast(*Type_Info_Struct)Math.Matrix4 {
                    for * data.(*Math.Matrix4).v
                        DragFloat4(tprint("##%.%\0", *it.component, name_str, it_index).data, *it.component);
                } else if info_struct == cast(*Type_Info_Struct)Math.Matrix3 {
                    for * data.(*Math.Matrix3).v
                        DragFloat3(tprint("##%.%\0", *it.component, name_str, it_index).data, *it.component);
                } else if TreeNode(label, name_str) {
                    AddSameLineStructName();

                    highest_offset := -1;
                    for member: info_struct.members {
                        if member.flags & .CONSTANT continue; // don't show constant types, etc.
                        if member.offset_in_bytes <= highest_offset continue; // skip #place types, etc.
                        highest_offset = member.offset_in_bytes;

                        if opts.in_table struct_table_row(member.name);
                        inspect(temp_c_string(member.name), data + member.offset_in_bytes, member.type, opts);
                    }
                    TreePop();
                } else {
                    AddSameLineStructName();
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
                    inspect(item_name, array_data + it * element_size, info_array.element_type, opts);
                }
                TreePop();
            } else {
                PopFont();
            }
        case .ANY;
            any := data.(*Any);
            inspect(label, any.value_pointer, any.type, opts);
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
                        CheckboxFlags64(label, data, cast(u64)it);
                    }
                } else {
                    for info_enum.values {
                        if it == 0 continue;
                        if info_enum.names[it_index] == "all" continue;
                        label := tprint(" %\0", info_enum.names[it_index]).data;
                        CheckboxFlags(label, data, cast(u32)it);
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
            inspect(label, data, info.(*Type_Info_Variant).variant_of, opts);
        case .UNTYPED_LITERAL;
            Text("(untyped literal)");
        case .UNTYPED_ENUM;
            Text("(untyped enum)");
    }

}

#scope_file
Reflection :: #import "Reflection";
ImGui :: #import "ImGui";
#import "imgui_extra";
using ImGui;
#import "Basic";
#import "Compiler";
Program_Print :: #import "Program_Print";
#import "Thread";
String :: #import "String";
