getenv_int :: (val: *$E, name: string) -> bool {
    text := getenv_string(name);
    if text.count != 0 {
        value, ok := string_to_int(text);
        assert(ok, "% must be an integer, got '%'.", name, text);
        val.* = cast(E)value;
        return true;
    }
    return false;
}

getenv_string :: (name: string, default: string = "") -> string {
    value_c := getenv(temp_c_string(name));
    if !value_c return default;
    return to_string(value_c, c_style_strlen(value_c));
}

try_parse_env_int :: (name: string, into_value: *$T) -> bool {
    assert(into_value != null);
    env_val, set := try_parse_env_int(name);
    if set {
        into_value.* = cast(T)env_val;
        return true;
    }

    return false;
}

try_parse_env_int :: (name: string) -> (s64, bool) {
    assert(name.count > 0);
    value_c := getenv(temp_c_string(name));
    if !value_c return 0, false;
    value_str := to_string(value_c, c_style_strlen(value_c));
    parsed, ok, _ := String.string_to_int(value_str);
    if !ok {
        log_error("Invalid %='%'. Expected integer.", name, value_str);
        return 0, false;
    }
    return cast(s64) parsed, true;
}

#scope_file
#import "Basic";
String :: #import "String";
using,only(getenv) POSIX :: #import "POSIX";
