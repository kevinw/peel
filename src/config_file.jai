Config_Entry :: struct { name: string; value: Any; };

free_config_entries :: (entries: [..]Config_Entry) {
    for entries  {
        free(it.name);
        free(it.value.value_pointer);
    }
    array_free(entries);
}

parse_globals_file :: () -> [..]Config_Entry {
    #import "Text_File_Handler";
    handler: Text_File_Handler = { do_version_number = false };
    defer deinit(*handler);

    filename :: "dev.cfg";

    start_file(*handler, filename, filename, optional=true);
    entries: [..]Config_Entry;
    if handler.failed return entries;
    while true {
        line, found := consume_next_line(*handler);
        if !found break;
        name, value := break_by_spaces(line);
        if name.count == 0 || value.count == 0 {
            log("% - ignoring line: %s", filename, line);
            continue;
        }

        heap_any :: (val: $V) -> Any {
            ptr := cast(*V)alloc(size_of(V));
            ptr.* = val;
            return Any.{
                type = type_info(V),
                value_pointer = ptr,
            };
        }

        add :: (value: $V) #expand {
            array_add(*entries, { copy_string(name), heap_any(value) });
        }

        parse_bool :: (value: string) -> (parse_ok: bool, value: bool) {
            if value == {
            case "yes"; #through;
            case "1"; #through;
            case "True"; #through;
            case "true";
                return true, true;
            case "no"; #through;
            case "0"; #through;
            case "False"; #through;
            case "false";
                return true, false;
            }
            return false, false;
        }

        // host-side globals
        if name == {
        case "gpu_validation";
            ok, val := parse_bool(value);
            if ok gpu_validation = val;
        }

        if value == {
        case "true"; add(true);
        case "false"; add(false);
        }
    }

    return entries;
}
