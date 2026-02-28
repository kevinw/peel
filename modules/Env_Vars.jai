try_parse_env_int :: (name: string) -> (s64, bool) {
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
