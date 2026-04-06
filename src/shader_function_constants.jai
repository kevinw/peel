shader_hot_reload_capture_function_constant_state :: (constants: *$T) -> ([]u8, []Shader_Hot_Reload_Function_Constant_Info) {
    info: [..] Shader_Hot_Reload_Function_Constant_Info;
    ti_struct := cast(*Type_Info_Struct) type_info(T);
    assert(ti_struct.type == .STRUCT, "Function constants type must be a struct; got %.", ti_struct.type);
    for ti_struct.members {
        array_add(*info, .{
            name = copy_string(it.name),
            type = shader_hot_reload_function_constant_type_from_type_info(it.type),
            offset = cast(s64) it.offset_in_bytes,
        });
    }

    constants_bytes := NewArray(size_of(T), u8);
    memcpy(constants_bytes.data, constants, constants_bytes.count);
    info_storage := NewArray(info.count, Shader_Hot_Reload_Function_Constant_Info);
    for info {
        info_storage[it_index] = it;
    }
    if info.count != 0 free(info.data);

    return constants_bytes, info_storage;
}

shader_hot_reload_function_constant_mtl_type :: (member_ti: *Type_Info) -> MTLDataType {
    if member_ti.type == {
    case .BOOL; return .Bool;
    case .STRUCT;
        struct_name := member_ti.(*Type_Info_Struct).name;
        if struct_name == {
        case "Vector2"; return .Float2;
        case "Vector3"; return .Float3;
        case "Vector4"; return .Float4;
        case; assert(false, "Unsupported function constant struct type '%'.", struct_name);
        }
    case .ENUM;
        return shader_hot_reload_function_constant_mtl_type(member_ti.(*Type_Info_Enum).internal_type);
    case .INTEGER;
        signed := member_ti.(*Type_Info_Integer).signed;
        if signed {
            if member_ti.runtime_size == {
            case 1; return .Char;
            case 2; return .Short;
            case 4; return .Int;
            case 8; return .Long;
            case; assert(false, "Unsupported signed function constant integer size %.", member_ti.runtime_size);
            }
        } else {
            if member_ti.runtime_size == {
            case 1; return .UChar;
            case 2; return .UShort;
            case 4; return .UInt;
            case 8; return .ULong;
            case; assert(false, "Unsupported unsigned function constant integer size %.", member_ti.runtime_size);
            }
        }
    case .FLOAT;
        return .Float;
    case;
        assert(false, "Unsupported function constant type %.", member_ti.type);
    }

    return .Int;
}

shader_hot_reload_function_constant_type_from_type_info :: (member_ti: *Type_Info) -> Shader_Hot_Reload_Function_Constant_Type {
    if member_ti.type == {
    case .BOOL; return .BOOL;
    case .STRUCT;
        struct_name := member_ti.(*Type_Info_Struct).name;
        if struct_name == {
        case "Vector2"; return .FLOAT2;
        case "Vector3"; return .FLOAT3;
        case "Vector4"; return .FLOAT4;
        case; assert(false, "Unsupported function constant struct type '%'.", struct_name);
        }
    case .ENUM;
        return shader_hot_reload_function_constant_type_from_type_info(member_ti.(*Type_Info_Enum).internal_type);
    case .INTEGER;
        signed := member_ti.(*Type_Info_Integer).signed;
        if signed {
            if member_ti.runtime_size == {
            case 1; return .S8;
            case 2; return .S16;
            case 4; return .S32;
            case 8; return .S64;
            case; assert(false, "Unsupported signed function constant integer size %.", member_ti.runtime_size);
            }
        } else {
            if member_ti.runtime_size == {
            case 1; return .U8;
            case 2; return .U16;
            case 4; return .U32;
            case 8; return .U64;
            case; assert(false, "Unsupported unsigned function constant integer size %.", member_ti.runtime_size);
            }
        }
    case .FLOAT;
        return .FLOAT;
    case;
        assert(false, "Unsupported function constant type %.", member_ti.type);
    }

    return .S32;
}

shader_hot_reload_function_constant_mtl_type :: (type: Shader_Hot_Reload_Function_Constant_Type) -> MTLDataType {
    if type == {
    case .BOOL;   return .Bool;
    case .U8;     return .UChar;
    case .S8;     return .Char;
    case .U16;    return .UShort;
    case .S16;    return .Short;
    case .U32;    return .UInt;
    case .S32;    return .Int;
    case .U64;    return .ULong;
    case .S64;    return .Long;
    case .FLOAT;  return .Float;
    case .FLOAT2; return .Float2;
    case .FLOAT3; return .Float3;
    case .FLOAT4; return .Float4;
    }
    return .Int;
}

shader_hot_reload_build_function_constant_values :: (constants: *$T) -> *MTLFunctionConstantValues {
    values := objc_new(MTLFunctionConstantValues);
    assert(values != null, "Failed to allocate MTLFunctionConstantValues.");
    ti_struct := cast(*Type_Info_Struct) type_info(T);
    assert(ti_struct.type == .STRUCT, "Function constants type must be a struct; got %.", ti_struct.type);
    for ti_struct.members {
        member, offset_in_bytes := get_field(ti_struct, it.name);
        if member == null continue;
        metal_data_type := shader_hot_reload_function_constant_mtl_type(member.type);
        field_ptr := cast(*void) ((cast(*u8) constants) + offset_in_bytes);
        MTLFunctionConstantValues.setConstantValue(values, field_ptr, metal_data_type, cast(NSUInteger) it_index);
    }

    return values;
}

NSEnumerator :: struct(T: Type) {
    using #as super: NSObject;
    type :: T;
}

nextObject :: (container: *NSEnumerator($T)) -> T {
    next_object: (*void, Selector) -> T #c_call;
    next_object = xx objc_msgSend;
    return next_object(container, selector("nextObject"));
}

keyEnumerator :: (dict: *NSDictionary($K, $V)) -> *NSEnumerator(K) {
    key_enumerator: (*void, Selector) -> *NSEnumerator(K) #c_call;
    key_enumerator = xx objc_msgSend;
    return key_enumerator(dict, selector("keyEnumerator"));
}

objectForKey :: (dict: *NSDictionary($K, $V), key: K) -> V {
    object_for_key: (*void, Selector, K) -> V #c_call;
    object_for_key = xx objc_msgSend;
    return object_for_key(dict, selector("objectForKey:"), key);
}

shader_hot_reload_source_field_name_from_reflected_name :: (reflected_name: string) -> string {
    suffix :: "_tmp";
    suffix_matches := false;
    if reflected_name.count > suffix.count {
        suffix_matches = true;
        suffix_start := reflected_name.count - suffix.count;
        for suffix {
            if reflected_name[suffix_start + it_index] != cast(u8) it {
                suffix_matches = false;
                break;
            }
        }
    }

    if suffix_matches {
        return .{count = reflected_name.count - 4, data = reflected_name.data};
    }
    return reflected_name;
}

shader_hot_reload_build_function_constant_values_for_function :: (function: *MTLFunction, constants: *$T) -> *MTLFunctionConstantValues {
    fn_constants_dict := function.functionConstantsDictionary(function);
    if fn_constants_dict == null return null;

    ti_struct := cast(*Type_Info_Struct) type_info(T);
    assert(ti_struct.type == .STRUCT, "Function constants type must be a struct; got %.", ti_struct.type);

    values: *MTLFunctionConstantValues = null;
    key_enumerator := keyEnumerator(fn_constants_dict);
    while true {
        field_name_ns := nextObject(key_enumerator);
        if field_name_ns == null break;

        field_name := to_string(field_name_ns);
        source_field_name := shader_hot_reload_source_field_name_from_reflected_name(field_name);
        constant := objectForKey(fn_constants_dict, field_name_ns);
        assert(constant != null, "Failed to reflect function constant '%' for function '%'.", field_name, to_string(MTLFunction.name(function)));

        member, offset_in_bytes := get_field(ti_struct, source_field_name);
        assert(member != null, "Function constants struct '%' is missing reflected field '%' (from Metal constant '%').", ti_struct.name, source_field_name, field_name);

        expected_metal_type := shader_hot_reload_function_constant_mtl_type(member.type);
        reflected_metal_type := MTLFunctionConstant.type(constant);
        assert(expected_metal_type == reflected_metal_type,
            "Function constant '%' type mismatch for function '%': struct has %, Metal expects %.",
            field_name, to_string(MTLFunction.name(function)), expected_metal_type, reflected_metal_type);

        if values == null {
            values = objc_new(MTLFunctionConstantValues);
            assert(values != null, "Failed to allocate MTLFunctionConstantValues.");
        }

        field_ptr := cast(*void) ((cast(*u8) constants) + offset_in_bytes);
        MTLFunctionConstantValues.setConstantValue(values, field_ptr, reflected_metal_type, field_name_ns);
    }

    return values;
}

shader_hot_reload_find_function_constant_info :: (info: []Shader_Hot_Reload_Function_Constant_Info, field_name: string) -> *Shader_Hot_Reload_Function_Constant_Info {
    for *info {
        if it.name == field_name return it;
    }
    return null;
}

shader_hot_reload_build_function_constant_values_for_function_from_bytes :: (
    function: *MTLFunction,
    constants_bytes: []u8,
    info: []Shader_Hot_Reload_Function_Constant_Info
) -> *MTLFunctionConstantValues {
    fn_constants_dict := function.functionConstantsDictionary(function);
    if fn_constants_dict == null return null;

    values: *MTLFunctionConstantValues = null;
    key_enumerator := keyEnumerator(fn_constants_dict);
    while true {
        field_name_ns := nextObject(key_enumerator);
        if field_name_ns == null break;

        field_name := to_string(field_name_ns);
        source_field_name := shader_hot_reload_source_field_name_from_reflected_name(field_name);
        constant := objectForKey(fn_constants_dict, field_name_ns);
        assert(constant != null, "Failed to reflect function constant '%' for function '%'.", field_name, to_string(MTLFunction.name(function)));

        info_entry := shader_hot_reload_find_function_constant_info(info, source_field_name);
        if info_entry == null {
            reflected_index := cast(s64) MTLFunctionConstant.index(constant);
            if reflected_index >= 0 && reflected_index < info.count {
                info_entry = info.data + reflected_index;
            }
        }
        assert(info_entry != null, "Function constants metadata is missing reflected field '%' (from Metal constant '%').", source_field_name, field_name);
        assert(info_entry.offset >= 0 && info_entry.offset < constants_bytes.count, "Function constant '%' has invalid byte offset % for % bytes.", source_field_name, info_entry.offset, constants_bytes.count);

        expected_metal_type := shader_hot_reload_function_constant_mtl_type(info_entry.type);
        reflected_metal_type := MTLFunctionConstant.type(constant);
        assert(expected_metal_type == reflected_metal_type,
            "Function constant '%' type mismatch for function '%': metadata has %, Metal expects %.",
            source_field_name, to_string(MTLFunction.name(function)), expected_metal_type, reflected_metal_type);

        if values == null {
            values = objc_new(MTLFunctionConstantValues);
            assert(values != null, "Failed to allocate MTLFunctionConstantValues.");
        }

        field_ptr := cast(*void) (constants_bytes.data + info_entry.offset);
        MTLFunctionConstantValues.setConstantValue(values, field_ptr, reflected_metal_type, field_name_ns);
    }

    return values;
}

shader_hot_reload_build_function_constant_values_for_metallib_function :: (
    metallib_path: string,
    function_name: string,
    constants_bytes: []u8,
    info: []Shader_Hot_Reload_Function_Constant_Info
) -> *MTLFunctionConstantValues {
    if function_name.count == 0 || constants_bytes.count == 0 return null;
    library := shader_hot_reload_new_library_from_file_or_return_0(metallib_path, "graphics metallib");
    if library == null return null;
    defer release(library);

    function := shader_hot_reload_get_function_from_library(library, function_name);
    assert(function != null, "Failed to find function '%' in metallib '%'.", function_name, metallib_path);
    defer release(function);

    return shader_hot_reload_build_function_constant_values_for_function_from_bytes(function, constants_bytes, info);
}

shader_hot_reload_constants_equal :: (lhs: []u8, rhs: []u8) -> bool {
    if lhs.count != rhs.count return false;
    for i: 0..lhs.count-1 if lhs[i] != rhs[i] return false;
    return true;
}
