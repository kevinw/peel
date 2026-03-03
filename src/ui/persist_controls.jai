#scope_export

Persist_Source_Target :: struct {
    using #as _: Source_Code_Range;

    key: string;
    variable_name: string;
    valid: bool;
}

SliderFloat :: (label: string, value_expr: Code, min: float, max: float, format := "%.3f", flags: ImGui.SliderFlags = 0) #expand {
    target := #run persist_target_from_pointer_expr(value_expr);
    default_value, has_default := #run persist_default_float_from_pointer_expr(value_expr);
    value_ptr := #insert value_expr;
    persist_slider_float_runtime(label, value_ptr, min, max, format, flags, target, default_value, has_default);
}

SliderInt :: (label: string, value_expr: Code, min: s32, max: s32, format := "%d", flags: ImGui.SliderFlags = 0) #expand {
    target := #run persist_target_from_pointer_expr(value_expr);
    default_value, has_default := #run persist_default_int_from_pointer_expr(value_expr);
    value_ptr := #insert value_expr;
    persist_slider_int_runtime(label, value_ptr, min, max, format, flags, target, default_value, has_default);
}

Checkbox :: (label: string, value_expr: Code) #expand {
    target := #run persist_target_from_pointer_expr(value_expr);
    default_value, has_default := #run persist_default_bool_from_pointer_expr(value_expr);
    value_ptr := #insert value_expr;
    persist_checkbox_runtime(label, value_ptr, target, default_value, has_default);
}

#scope_module

persist_slider_float_runtime :: (label: string, value: *float, min: float, max: float, format: string, flags: ImGui.SliderFlags, target: Persist_Source_Target, compiled_default: float, has_default: bool) -> bool {
    changed := ImGui.SliderFloat(temp_c_string(label), value, min, max, temp_c_string(format), flags);
    if !has_default return changed;

    default_value := persist_effective_default_float(target.key, compiled_default);
    delta := value.* - default_value;
    if delta < 0.0 delta = -delta;
    is_dirty := delta > 0.000001;
    if !is_dirty return changed;

    ImGui.SameLine();
    ImGui.PushID(temp_c_string(target.key));
    defer ImGui.PopID();

    if ImGui.SmallButton("X") {
        value.* = default_value;
        changed = true;
    }

    ImGui.SameLine();
    if ImGui.SmallButton("S") {
        source_text := persist_float_to_source_literal(value.*);
        save_ok := persist_try_save_value(target, source_text);
        if save_ok {
            persist_set_saved_default_float(target.key, value.*);
        }
    }

    return changed;
}

persist_slider_int_runtime :: (label: string, value: *s32, min: s32, max: s32, format: string, flags: ImGui.SliderFlags, target: Persist_Source_Target, compiled_default: s32, has_default: bool) -> bool {
    changed := ImGui.SliderInt(temp_c_string(label), value, min, max, temp_c_string(format), flags);
    if !has_default return changed;

    default_value := persist_effective_default_int(target.key, compiled_default);
    is_dirty := value.* != default_value;
    if !is_dirty return changed;

    ImGui.SameLine();
    ImGui.PushID(temp_c_string(target.key));
    defer ImGui.PopID();

    if ImGui.SmallButton("X") {
        value.* = default_value;
        changed = true;
    }

    ImGui.SameLine();
    if ImGui.SmallButton("S") {
        source_text := tprint("%", value.*);
        save_ok := persist_try_save_value(target, source_text);
        if save_ok {
            persist_set_saved_default_int(target.key, value.*);
        }
    }

    return changed;
}

persist_checkbox_runtime :: (label: string, value: *bool, target: Persist_Source_Target, compiled_default: bool, has_default: bool) -> bool {
    changed := ImGui.Checkbox(temp_c_string(label), value);
    if !has_default return changed;

    default_value := persist_effective_default_bool(target.key, compiled_default);
    is_dirty := value.* != default_value;
    if !is_dirty return changed;

    ImGui.SameLine();
    ImGui.PushID(temp_c_string(target.key));
    defer ImGui.PopID();

    if ImGui.SmallButton("X") {
        value.* = default_value;
        changed = true;
    }

    ImGui.SameLine();
    if ImGui.SmallButton("S") {
        source_text := ifx value.* then "true" else "false";
        save_ok := persist_try_save_value(target, source_text);
        if save_ok {
            persist_set_saved_default_bool(target.key, value.*);
        }
    }

    return changed;
}

persist_float_to_source_literal :: (value: float) -> string {
    text := tprint("%", value);
    has_decimal_or_exp := false;
    for text {
        if it == #char "." || it == #char "e" || it == #char "E" {
            has_decimal_or_exp = true;
            break;
        }
    }
    if has_decimal_or_exp return text;
    return tprint("%.0", text);
}

persist_try_save_value :: (target: Persist_Source_Target, replacement: string) -> bool {
    if !target.valid return false;
    if !persist_path_is_whitelisted(target.fully_pathed_filename) return false;

    source, ok := File.read_entire_file(target.fully_pathed_filename);
    if !ok return false;

    start, start_ok := persist_line_col_to_offset(source, target.line_number_start, target.character_number_start);
    end, end_ok := persist_line_col_to_offset(source, target.line_number_end, target.character_number_end);
    if !start_ok || !end_ok || start < 0 || end < start || end > source.count return false;

    out: String_Builder;
    out.allocator = temp;
    if start > 0 {
        prefix: string;
        prefix.data = source.data;
        prefix.count = start;
        append(*out, prefix);
    }
    append(*out, replacement);
    if end < source.count {
        suffix: string;
        suffix.data = source.data + end;
        suffix.count = source.count - end;
        append(*out, suffix);
    }

    return File.write_entire_file(target.fully_pathed_filename, builder_to_string(*out));
}

persist_line_col_to_offset :: (text: string, line_1_based: s64, col_1_based: s64) -> (s64, bool) {
    if line_1_based <= 0 return 0, false;
    if col_1_based <= 0 return 0, false;

    line: s32 = 1;
    line_start: s64 = 0;
    i: s64 = 0;
    while i < text.count && line < line_1_based {
        if text[i] == #char "\n" {
            line += 1;
            line_start = i + 1;
        }
        i += 1;
    }
    if line != line_1_based return 0, false;

    offset := line_start + (cast(s64) col_1_based - 1);
    if offset < 0 || offset > text.count return 0, false;
    return offset, true;
}

persist_path_is_whitelisted :: (path: string) -> bool {
    if path.count == 0 return false;
    if !String.contains(path, "/src/apps/") return false;
    return true;
}

Persist_Saved_Float :: struct { key: string; value: float; }
Persist_Saved_Int :: struct { key: string; value: s32; }
Persist_Saved_Bool :: struct { key: string; value: bool; }

persist_saved_float_defaults: [..] Persist_Saved_Float;
persist_saved_int_defaults: [..] Persist_Saved_Int;
persist_saved_bool_defaults: [..] Persist_Saved_Bool;

persist_effective_default_float :: (key: string, compiled_default: float) -> float {
    for persist_saved_float_defaults if it.key == key return it.value;
    return compiled_default;
}

persist_effective_default_int :: (key: string, compiled_default: s32) -> s32 {
    for persist_saved_int_defaults if it.key == key return it.value;
    return compiled_default;
}

persist_effective_default_bool :: (key: string, compiled_default: bool) -> bool {
    for persist_saved_bool_defaults if it.key == key return it.value;
    return compiled_default;
}

persist_set_saved_default_float :: (key: string, value: float) {
    for *persist_saved_float_defaults {
        if it.key == key {
            it.value = value;
            return;
        }
    }
    array_add(*persist_saved_float_defaults, .{key = copy_string(key), value = value});
}

persist_set_saved_default_int :: (key: string, value: s32) {
    for *persist_saved_int_defaults {
        if it.key == key {
            it.value = value;
            return;
        }
    }
    array_add(*persist_saved_int_defaults, .{key = copy_string(key), value = value});
}

persist_set_saved_default_bool :: (key: string, value: bool) {
    for *persist_saved_bool_defaults {
        if it.key == key {
            it.value = value;
            return;
        }
    }
    array_add(*persist_saved_bool_defaults, .{key = copy_string(key), value = value});
}

persist_target_from_pointer_expr :: (expr_code: Code) -> Persist_Source_Target #compile_time {
    root, _ := Compiler.compiler_get_nodes(expr_code);
    if root == null return .{};
    if root.kind != .UNARY_OPERATOR return .{};

    unary := cast(*Compiler.Code_Unary_Operator) root;
    if unary.operator_type != cast(Compiler.Operator_Type) #char "*" return .{};
    if unary.subexpression == null || unary.subexpression.kind != .IDENT return .{};

    ident := cast(*Compiler.Code_Ident) unary.subexpression;
    decl := ident.resolved_declaration;
    if decl == null return .{};
    if decl.expression == null return .{};
    if decl.enclosing_load == null return .{};

    file_path := decl.enclosing_load.fully_pathed_filename;
    if file_path.count == 0 return .{};

    expr := decl.expression;
    return .{
        key = tprint("%:%:%", file_path, expr.l0, decl.name),
        variable_name = decl.name,
        fully_pathed_filename = file_path,
        line_number_start = expr.l0,
        character_number_start = expr.c0,
        line_number_end = expr.l1,
        character_number_end = expr.c1,
        valid = true,
    };
}

persist_default_float_from_pointer_expr :: (expr_code: Code) -> (float, bool) #compile_time {
    decl := persist_decl_from_pointer_expr(expr_code);
    if decl == null || decl.expression == null return 0.0, false;
    if decl.expression.kind != .LITERAL return 0.0, false;
    lit := cast(*Compiler.Code_Literal) decl.expression;
    if lit.value_type != .NUMBER return 0.0, false;
    if lit.value_flags & .FLOAT return cast(float) lit._float64, true;
    return cast(float) lit._s64, true;
}

persist_default_int_from_pointer_expr :: (expr_code: Code) -> (s32, bool) #compile_time {
    decl := persist_decl_from_pointer_expr(expr_code);
    if decl == null || decl.expression == null return 0, false;
    if decl.expression.kind != .LITERAL return 0, false;
    lit := cast(*Compiler.Code_Literal) decl.expression;
    if lit.value_type != .NUMBER return 0, false;
    if lit.value_flags & .FLOAT return cast(s32) lit._float64, true;
    return cast(s32) lit._s64, true;
}

persist_default_bool_from_pointer_expr :: (expr_code: Code) -> (bool, bool) #compile_time {
    decl := persist_decl_from_pointer_expr(expr_code);
    if decl == null || decl.expression == null return false, false;
    if decl.expression.kind != .LITERAL return false, false;
    lit := cast(*Compiler.Code_Literal) decl.expression;
    if lit.value_type != .BOOLEAN return false, false;
    return lit._s64 != 0, true;
}

persist_decl_from_pointer_expr :: (expr_code: Code) -> *Compiler.Code_Declaration #compile_time {
    root, _ := Compiler.compiler_get_nodes(expr_code);
    if root == null return null;
    if root.kind != .UNARY_OPERATOR return null;
    unary := cast(*Compiler.Code_Unary_Operator) root;
    if unary.operator_type != cast(Compiler.Operator_Type) #char "*" return null;
    if unary.subexpression == null || unary.subexpression.kind != .IDENT return null;
    ident := cast(*Compiler.Code_Ident) unary.subexpression;
    return ident.resolved_declaration;
}

#scope_file

File :: #import "File";
ImGui :: #import "ImGui";
Compiler :: #import "Compiler";
String :: #import "String";
