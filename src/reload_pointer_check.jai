//
// Logs potentially stale pointers after a reload, to help identify issues with the reload process.
//
// Useful with Globals_Reload.
//
// TODO: implement the below dladdr(ptr_value, *info) logic for Windows, using VirtualQuery or similar to determine the image a pointer belongs to.
// TODO: make this a module, don't rely on App, just accept filenames and lists of globals
//

reload_pointer_check_after_copy :: (src: *App, dst: *App) {
    if src == null || dst == null return;
    if !src.is_valid || !dst.is_valid return;
    if src.temp_loaded_filepath.count == 0 return;

    #if !(OS == .MACOS || OS == .LINUX) {
        return;
    }

    state: Check_State = {
        old_temp_path = src.temp_loaded_filepath,
        old_temp_filename = String.path_filename(src.temp_loaded_filepath),
    };

    src_globals := src.get_globals(,,temp);
    dst_globals := dst.get_globals(,,temp);

    check_collect_ranges(*state.ranges, src_globals);
    check_collect_ranges(*state.ranges, dst_globals);

    for g: dst_globals {
        if g.data == null || g.ti == null continue;
        root_path := tprint("global[module_hash=% name_hash=%]", g.module_name_hash, g.name_hash);
        check_scan_value(*state, g.data, g.ti, root_path, 0);
    }

    if state.warning_count > 0 {
        log_error("Reload pointer check: found % stale pointer(s) into old DLL image '%'.",
            state.warning_count, state.old_temp_filename);
        if state.warning_count > state.warning_log_count {
            suppressed := state.warning_count - state.warning_log_count;
            log_error("Reload pointer check: suppressed % additional warning(s).", suppressed);
        }
    }

    array_free(state.ranges);
    array_free(state.visited_nodes);
    array_free(state.seen_warning_keys);
}

#scope_file

RELOAD_PTR_CHECK_MAX_DEPTH :: 12;
RELOAD_PTR_CHECK_MAX_FIXED_ARRAY_ELEMS :: 2048;
RELOAD_PTR_CHECK_MAX_DYNAMIC_ARRAY_ELEMS :: 2048;
RELOAD_PTR_CHECK_MAX_LOGGED_WARNINGS :: 4096;

Check_Range :: struct {
    start: u64;
    end: u64;
}

Check_Visited_Node :: struct {
    addr: *void;
    ti: *Type_Info;
}

Check_State :: struct {
    old_temp_path: string;
    old_temp_filename: string;

    ranges: [..]Check_Range;
    visited_nodes: [..]Check_Visited_Node;
    seen_warning_keys: [..]u64;

    warning_count: s64;
    warning_log_count: s64;
    truncated: bool;
}

check_collect_ranges :: (ranges: *[..]Check_Range, globals: []RC.Global_Entry) {
    for g: globals {
        if g.data == null || g.size <= 0 continue;
        start := cast(u64) g.data;
        end := start + cast(u64) g.size;
        if end <= start continue;
        array_add(ranges, .{start = start, end = end});
    }
}

check_scan_value :: (state: *Check_State, addr: *void, ti: *Type_Info, path: string, depth: s32) {
    if state == null || addr == null || ti == null return;
    if depth > RELOAD_PTR_CHECK_MAX_DEPTH return;

    if ti.type == {
        case .POINTER;
            pointer_ti := cast(*Type_Info_Pointer) ti;
            ptr_value := check_read_ptr(addr, 0);
            check_pointer_slot(state, ptr_value, path, pointer_ti.pointer_to, depth);

        case .PROCEDURE;
            scan_callable_words(state, addr, ti, path, depth);

        case .CODE;
            scan_callable_words(state, addr, ti, path, depth);

        case .STRING;
            data_ptr := check_read_ptr(addr, 0);
            check_pointer_slot(state, data_ptr, tprint("%.data", path), null, depth);

        case .ANY;
            value_ti := cast(*Type_Info) check_read_ptr(addr, 0);
            value_ptr := check_read_ptr(addr, cast(s64) size_of(*void));
            check_pointer_slot(state, value_ptr, tprint("%.value_pointer", path), value_ti, depth);

        case .ARRAY;
            arr_ti := cast(*Type_Info_Array) ti;
            check_scan_array(state, addr, arr_ti, path, depth);

        case .STRUCT;
            check_scan_struct(state, addr, cast(*Type_Info_Struct) ti, path, depth);

        case .VARIANT;
            variant_ti := cast(*Type_Info_Variant) ti;
            if variant_ti.variant_of {
                check_scan_value(state, addr, variant_ti.variant_of, path, depth + 1);
            }

        case;
            // Scalars and other non-pointer-bearing types are ignored.
    }
}

check_scan_array :: (state: *Check_State, addr: *void, arr_ti: *Type_Info_Array, path: string, depth: s32) {
    if arr_ti == null || arr_ti.element_type == null return;
    elem_size := arr_ti.element_type.runtime_size;
    if elem_size <= 0 return;

    if arr_ti.array_type == .FIXED {
        count := arr_ti.array_count;
        if count <= 0 return;
        if count > RELOAD_PTR_CHECK_MAX_FIXED_ARRAY_ELEMS {
            count = RELOAD_PTR_CHECK_MAX_FIXED_ARRAY_ELEMS;
            state.truncated = true;
        }

        for 0..count {
            elem_addr := check_ptr_add(addr, it * elem_size);
            elem_path := tprint("%[%]", path, it);
            check_scan_value(state, elem_addr, arr_ti.element_type, elem_path, depth + 1);
        }
        return;
    }

    data_ptr := check_read_ptr(addr, 0);
    count := check_read_s64(addr, cast(s64) size_of(*void));
    check_pointer_slot(state, data_ptr, tprint("%.data", path), null, depth);

    if data_ptr == null || count <= 0 return;
    if !check_addr_in_ranges(state, data_ptr) return;

    if count > RELOAD_PTR_CHECK_MAX_DYNAMIC_ARRAY_ELEMS {
        count = RELOAD_PTR_CHECK_MAX_DYNAMIC_ARRAY_ELEMS;
        state.truncated = true;
    }

    for 0..count {
        elem_addr := check_ptr_add(data_ptr, it * elem_size);
        elem_path := tprint("%[%]", path, it);
        check_scan_value(state, elem_addr, arr_ti.element_type, elem_path, depth + 1);
    }
}

check_scan_struct :: (state: *Check_State, addr: *void, st_ti: *Type_Info_Struct, path: string, depth: s32) {
    if st_ti == null return;
    if !check_mark_visited(state, addr, cast(*Type_Info) st_ti) return;

    for st_ti.members {
        if it.type == null continue;
        if it.offset_in_bytes < 0 continue;
        member_addr := check_ptr_add(addr, it.offset_in_bytes);
        member_path := tprint("%.%", path, it.name);
        check_scan_value(state, member_addr, it.type, member_path, depth + 1);
    }
}

scan_callable_words :: (state: *Check_State, addr: *void, ti: *Type_Info, path: string, depth: s32) {
    // Procedure/Code values can carry one or more pointer-sized words (code/context).
    word_count := ti.runtime_size / cast(s64) size_of(*void);
    if word_count <= 0 word_count = 1;
    if word_count > 4 word_count = 4;
    for 0..word_count {
        ptr_value := check_read_ptr(addr, it * cast(s64) size_of(*void));
        slot_path := tprint("%.[callable_word_%]", path, it);
        check_pointer_slot(state, ptr_value, slot_path, null, depth);
    }
}

check_pointer_slot :: (state: *Check_State, ptr_value: *void, path: string, pointee_ti: *Type_Info, depth: s32) {
    if ptr_value == null return;
    check_emit_if_old_dll_pointer(state, ptr_value, path);

    if pointee_ti == null return;
    if depth >= RELOAD_PTR_CHECK_MAX_DEPTH return;
    if !check_addr_in_ranges(state, ptr_value) return;
    if !check_mark_visited(state, ptr_value, pointee_ti) return;

    check_scan_value(state, ptr_value, pointee_ti, path, depth + 1);
}

check_emit_if_old_dll_pointer :: (state: *Check_State, ptr_value: *void, path: string) {
    #if !(OS == .MACOS || OS == .LINUX) return;

    info: POSIX.Dl_info;
    ok := POSIX.dladdr(ptr_value, *info);
    if ok == 0 return;
    if info.dli_fname == null return;

    image_path := to_string(info.dli_fname);
    if !check_matches_old_image(state, image_path) return;

    warning_key := (cast(u64) ptr_value) ~ (cast(u64) Hash.get_hash(path) << 32);
    if array_find(state.seen_warning_keys, warning_key) return;
    array_add(*state.seen_warning_keys, warning_key);

    state.warning_count += 1;
    if state.warning_log_count >= RELOAD_PTR_CHECK_MAX_LOGGED_WARNINGS return;
    state.warning_log_count += 1;

    symbol_name := ifx info.dli_sname != null then to_string(info.dli_sname) else "";
    if symbol_name.count > 0 {
        log_error("Reload pointer check: stale pointer at % -> % (image='%', symbol='%').",
            path, ptr_value, image_path, symbol_name);
    } else {
        log_error("Reload pointer check: stale pointer at % -> % (image='%').",
            path, ptr_value, image_path);
    }
}

check_matches_old_image :: (state: *Check_State, image_path: string) -> bool {
    if image_path.count == 0 return false;
    if image_path == state.old_temp_path return true;
    if String.ends_with(image_path, state.old_temp_filename) return true;
    if String.path_filename(image_path) == state.old_temp_filename return true;
    return false;
}

check_mark_visited :: (state: *Check_State, addr: *void, ti: *Type_Info) -> bool {
    if state == null || addr == null || ti == null return false;
    for state.visited_nodes {
        if it.addr == addr && it.ti == ti return false;
    }
    array_add(*state.visited_nodes, .{ addr = addr, ti = ti });
    return true;
}

check_addr_in_ranges :: (state: *Check_State, ptr_value: *void) -> bool {
    if ptr_value == null return false;
    p := cast(u64) ptr_value;
    for state.ranges {
        if p >= it.start && p < it.end return true;
    }
    return false;
}

check_ptr_add :: (base: *void, offset: s64) -> *void {
    return cast(*void) ((cast(*u8) base) + offset);
}

check_read_ptr :: (base: *void, offset: s64) -> *void {
    value: u64;
    memcpy(*value, check_ptr_add(base, offset), size_of(u64));
    return cast(*void) value;
}

check_read_s64 :: (base: *void, offset: s64) -> s64 {
    value: s64;
    memcpy(*value, check_ptr_add(base, offset), size_of(s64));
    return value;
}

String :: #import "String";
POSIX :: #import "POSIX";
RC :: #import "Reload_Common";
Hash :: #import "Hash";
