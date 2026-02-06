Type_Entry :: struct { 
    ti: *Type_Info; suffix: string;
};

g_shader_types : [..]Type_Entry;

Shader_Metaprogram_Plugin :: struct {
    using #as plugin: Metaprogram_Plugin;

    // The suffix to be used in the output filename if no suffix is specified in the @ShaderType note.
    empty_suffix: string = "";

    // The filename to write the generated shader types to. Note that we replace {SUFFIX} with the declarations declared or implied suffix.
    output_filename: string = "generated_shaders{SUFFIX}.metal";

    verbose := false;
}

get_plugin :: () -> *Metaprogram_Plugin {
    p := New(Shader_Metaprogram_Plugin);
    p.message = (p: *Metaprogram_Plugin, message: *Message) {
        me := p.(*Shader_Metaprogram_Plugin);

        if message.kind == {
            case .TYPECHECKED;
                for message.(*Message_Typechecked).declarations
                    HandleDeclarationForShaderCodegen(it.expression, verbose=me.verbose);
            case .COMPLETE;
                GenerateShaderCode(cast(*Shader_Metaprogram_Plugin) p);
        }
    }

    return p;
}

GetMatrixTypeInfo :: (info : *Type_Info) -> (is_matrix_type : bool, matrix_T : *Type_Info, matrix_M : int, matrix_N : int) {
    if info.type == .STRUCT {
        name := info.(*Type_Info_Struct).name;
        if name[0] != #char "M" return false, null, 0, 0;
        // TODO: don't use names, use duck typing
        if name == "Matrix2" return true, type_info(float32), 2, 2;
        if name == "Matrix3" return true, type_info(float32), 3, 3;
        if name == "Matrix4" return true, type_info(float32), 4, 4;
    }

    return false, null, 0, 0;
}

GetVectorTypeInfo :: (info : *Type_Info) -> (is_vector_type : bool, vector_T : *Type_Info, vector_N : int) {
    if info.type == .STRUCT {
        name := info.(*Type_Info_Struct).name;

        if name[0] != #char "V" return false, null, 0;

        // TODO: don't use names, use duck typing
        if name == "Vector2" return true, type_info(float32), 2;
        if name == "Vector3" return true, type_info(float32), 3;
        if name == "Vector4" return true, type_info(float32), 4;
        if name == "Vector2_Float16" return true, type_info(Float16), 2;
        if name == "Vector3_Float16" return true, type_info(Float16), 3;
        if name == "Vector4_Float16" return true, type_info(Float16), 4;
    }

    return false, null, 0;
}


HandleDeclarationForShaderCodegen :: (decl : *Code_Declaration, verbose := false) {
    has_shader_type_note := false;
    suffix := "";
    for note : decl.notes {
        // See if it looks like @ShaderType or @ShaderType,custom_suffix_here
        if note.text.count >= 10 {
            prefix := note.text;
            prefix.count = 10;
            if note.text.count >= 12 && note.text[10] == #char "," {
                suffix = note.text;
                suffix.count = note.text.count - 11;
                suffix.data += 11;
            }
            if prefix == "ShaderType" {
                has_shader_type_note = true;
                break;
            }
        }
    }

    if !has_shader_type_note
        return;

    if !decl.expression {
        log_error("No expression found for declaration %", decl.name);
        return;
    }

    if decl.expression.kind == {
        case .STRUCT;
            if verbose log("Adding %th struct % (%)", g_shader_types.count, (cast(*Code_Struct) decl.expression).defined_type.name, suffix);
            array_add(*g_shader_types, .{(cast(*Code_Struct) decl.expression).defined_type, suffix});
        case .ENUM;
            if verbose log("Adding %th enum % (%)", g_shader_types.count, (cast(*Code_Enum) decl.expression).external_type.name, suffix);
            array_add(*g_shader_types, .{(cast(*Code_Enum) decl.expression).external_type, suffix});
    }
}

GenerateShaderCode :: (using p : *Shader_Metaprogram_Plugin) {
    if output_filename == "" {
        log_error("Shader_Metaprogram: output_filename is empty. Skipping code generation.");
        return;
    }

    defer {
        array_reset(*g_shader_types);
    }

    all_suffixes: [..]string;
    for g_shader_types {
        found := false;
        for suffix: all_suffixes {
            if suffix == it.suffix {
                found = true;
            }
        }
        if !found
            array_add(*all_suffixes, it.suffix);
    }

    if !array_find(all_suffixes, "")
    array_add(*all_suffixes, "");

    for suffix: all_suffixes {
        suffix_for_filename := tprint("_%", ifx suffix else empty_suffix);
        output_filename_with_suffix := String.replace(output_filename, "{SUFFIX}", suffix_for_filename);

        shader_types_for_suffix: [..]Type_Entry;
        for g_shader_types {
            if it.suffix == suffix {
                array_add(*shader_types_for_suffix, it);
            }
        }

        shader_types_in_order : [..]Type_Entry;
        quick_sort(shader_types_for_suffix, CompareTypeNames);
        for shader_types_for_suffix
            PushType(*shader_types_in_order, it, shader_types_for_suffix);

        generated_types: string;
        for shader_types_in_order {
            if generated_types.count > 0
                generated_types = tprint("%, %", generated_types, get_type(it.ti));
            else
                generated_types = tprint("%", get_type(it.ti));
        }


        builder: String_Builder;

        if builder_string_length(*builder) == 0
            append(*builder, "// This file was auto generated by Shader_Metaprogram.jai\n");

        for shader_types_in_order {
            if it.ti.type == .ENUM {
                GenerateShaderEnumDefinition(*builder, cast(*Type_Info_Enum) it.ti);
                append(*builder, ";\n\n");
            } else if it.ti.type == .STRUCT {
                GenerateShaderStructDefinition(*builder, cast(*Type_Info_Struct) it.ti);
                append(*builder, ";\n\n");
            } else {
                log_error("Shader_Metaprogram: unknown type %", it.ti.type);
            }
        }

        if shader_types_in_order.count > 0 {
            output_dir := String.path_strip_filename(output_filename_with_suffix);
            File.make_directory_if_it_does_not_exist(output_dir, recursive=true);
            File.write_entire_file(output_filename_with_suffix, *builder);
            if verbose log("Wrote % generated shader types to %", 
                shader_types_in_order.count, output_filename_with_suffix);
        }
    }
}

RemoveShaderPrefix :: (name : string) -> string {
    // print("TODO: RemoveShaderPrefix %\n", name);
    return name;
}

GenerateShaderEnumDefinition :: (builder : *String_Builder, info : *Type_Info_Enum, indent := 0) {
    name := RemoveShaderPrefix(info.name);
    if info.name
        append(builder, tprint("enum %\n{\n", name));
    else
        append(builder, "enum\n{\n");

    for i : 0..info.values.count - 1 {
        for 1..indent + 1
            append(builder, "    ");

        append(builder, tprint("%_", name));
        for char : info.names[i] {
            if char == #char "_"
                continue;
            append_byte(builder, char);
        }

        append(builder, tprint(" = %,", info.values[i]));
    }

    for 1..indent
        append(builder, "    ");

    append(builder, "}");
}

AppendShaderTypePrefix :: (builder : *String_Builder, info : *Type_Info, indent := 0) {
    a :: (str: string) #expand {
        append(`builder, str);
    }

    if info.type == {
    case .INTEGER;
        int_info := cast(*Type_Info_Integer) info;
        if int_info.signed {
            if int_info.runtime_size == {
            case 1; a("char ");
            case 2; a("short ");
            case 4; a("int ");
            case 8; a("long ");
            }
        } else {
            if int_info.runtime_size == {
            case 1; a("uchar ");
            case 2; a("ushort ");
            case 4; a("uint ");
            case 8; a("ulong ");
            }
        }
    case .BOOL;
        a("bool ");
    case .FLOAT;
        if info.runtime_size == 4
            a("float ");
        else
            a("double ");
    case .STRUCT;
        struct_info := cast(*Type_Info_Struct) info;
        if !struct_info.name {
            GenerateShaderStructDefinition(builder, struct_info, indent);
            a(" ");
            return;
        }

        if struct_info.name == "R8G8B8A8_UNORM" { // TODO : @Hack
            assert(info.runtime_size == 4);
            a("uint ");
        } else {

            is_matrix_type, matrix_T, matrix_M, matrix_N := GetMatrixTypeInfo(info);
            is_vector_type, vector_T, vector_N := GetVectorTypeInfo(info);
            if is_vector_type {
                if vector_T.type == .INTEGER {
                    if vector_T.(*Type_Info_Integer).signed
                        a(tprint("int% ", vector_N));
                    else
                        a(tprint("uint% ", vector_N));
                } else if vector_T.type == .FLOAT {
                    if vector_T.runtime_size == 4
                        a(tprint("float% ", vector_N));
                    else
                        a(tprint("double% ", vector_N));
                } else if vector_T.type == .VARIANT {
                    assert(vector_T.runtime_size == 2);
                    a(tprint("half% ", vector_N));
                } else {
                    a(tprint("% ", RemoveShaderPrefix(struct_info.name)));
                }
            } else if is_matrix_type {
                if matrix_T.type == .INTEGER {
                    if (cast(*Type_Info_Integer) matrix_T).signed
                        a(tprint("int%x% ", matrix_M, matrix_N));
                    else
                        a(tprint("uint%x% ", matrix_M, matrix_N));
                } else if matrix_T.type == .FLOAT {
                    if matrix_T.runtime_size == 4
                        a(tprint("float%x% ", matrix_M, matrix_N));
                    else
                        a(tprint("double%x% ", matrix_M, matrix_N));
                } else {
                    a(tprint("% ", RemoveShaderPrefix(struct_info.name)));
                }
            } else {
                a(tprint("% ", RemoveShaderPrefix(struct_info.name)));
            }
        }
    case .ENUM;
        enum_info := cast(*Type_Info_Enum) info;
        if !enum_info.name {
            GenerateShaderEnumDefinition(builder, enum_info, indent);
            a(" ");
        } else {
            a(tprint("% ", RemoveShaderPrefix(enum_info.name)));
        }
    case .ARRAY;
        AppendShaderTypePrefix(builder, info.(*Type_Info_Array).element_type, indent);
    }
}

AppendShaderTypePostfix :: (builder : *String_Builder, info : *Type_Info, indent := 0) {
    if info.type == {
    case .ARRAY;
        array_info := cast(*Type_Info_Array) info;
        append(builder, "[%]", array_info.array_count);
        AppendShaderTypePostfix(builder, array_info.element_type, indent);
    }
}

GenerateShaderStructDefinition :: (builder : *String_Builder, info : *Type_Info_Struct, indent := 0) {
    name := RemoveShaderPrefix(info.name);
    if name
        append(builder, tprint("struct %\n", name));
    else
        append(builder, "struct\n");

    for i : 1..indent
        append(builder, "    ");

    append(builder, "{\n");

    highest_offset := -1;
    for info.members {
        if it.flags & .CONSTANT || it.offset_in_bytes <= highest_offset
            continue;
        if it.type.type == .VOID
            continue;

        member_name := it.name;
        highest_offset = it.offset_in_bytes;

        for i : 1..indent + 1
            append(builder, "    ");

        semantic: string;
        shaderType: string;
        originalType: string;
        for it.notes {
            semantic = it;

            for i: 0..semantic.count-1 {
                if semantic[i] == #char "," {
                    shaderType = string.{data=semantic.data + i + 1,count=semantic.count-i-1};
                    originalType = member_name;
                    semantic.count = i;
                    break;
                }
            }
            break;
        }

        if shaderType 
            append(builder, tprint("% ", shaderType));
        else
            AppendShaderTypePrefix(builder, it.type, indent + 1);
        append(builder, it.name);
        AppendShaderTypePostfix(builder, it.type, indent + 1);

        if semantic
            append(builder, tprint(" : %", semantic));

        append(builder, ";");
        if shaderType != "" {
            append(builder, tprint(" // CPU type: "));
            AppendShaderTypePrefix(builder, it.type, indent + 1);

        }
        append(builder, "\n");
    }

    for i: 1..indent
        append(builder, "    ");

    append(builder, "}");
}

#scope_file
#import "Compiler";
using Basic :: #import "Basic";
#import "Sort";
File :: #import "File";
String :: #import "String";
#import "Float16";

CompareTypeNames :: (a: Type_Entry, b: Type_Entry) -> int {
    a_name := ifx a.ti.type == .STRUCT
        then (cast(*Type_Info_Struct) a.ti).name
        else (cast(*Type_Info_Enum) a.ti).name;
    b_name := ifx b.ti.type == .STRUCT
        then (cast(*Type_Info_Struct) b.ti).name
        else (cast(*Type_Info_Enum) b.ti).name;

    return compare_strings(a_name, b_name);
}

// Make sure types are generated in order to respect C declaration rules
PushType :: (types : *[..]Type_Entry, type_entry : Type_Entry, shader_types: [..]Type_Entry) {
    if type_entry.ti.type == .STRUCT {
        info_struct := cast(*Type_Info_Struct) type_entry.ti;
        for info_struct.members {
            if it.type.type == .STRUCT || it.type.type == .ENUM
                PushType(types, .{it.type, type_entry.suffix}, shader_types);
        }
    }

    for shader_types {
        if type_entry.ti == it.ti {

            found := false;
            for type: types.* {
                if type.ti == it.ti && type.suffix == it.suffix {
                    found = true;
                    break;
                }
            }
            if !found {
                array_add(types, type_entry);
            }

            break;
        }
    }
}

append_byte :: (builder : *String_Builder, byte: u8) {
    s: string;
    s.count = 1;
    s.data = *byte;
    append(builder, s);
}
