Texture_Cache_Format :: enum u32 {
    BC7_SRGB;
    BC7_UNORM;
    BC5_UNORM;
    RGBA8_SRGB;
    RGBA8_UNORM;
}

Texture_Cache_Options :: struct {
    format: Texture_Cache_Format;
    generate_mips: bool = true;
    normal_mode: bool;
    uastc_quality: string;
}

ktx_texture_cache_create_format :: (format: Texture_Cache_Format) -> string {
    if format == {
    case .BC7_SRGB; #through;
    case .RGBA8_SRGB; return "R8G8B8A8_SRGB";
    case .BC7_UNORM; #through;
    case .BC5_UNORM; #through;
    case .RGBA8_UNORM; return "R8G8B8A8_UNORM";
    }
    return "R8G8B8A8_UNORM";
}

ktx_texture_cache_transcode_target :: (format: Texture_Cache_Format) -> string {
    if format == {
    case .BC7_SRGB; #through;
    case .BC7_UNORM; return "bc7";
    case .BC5_UNORM; return "bc5";
    case .RGBA8_SRGB; #through;
    case .RGBA8_UNORM; return "";
    }
    return "";
}

ktx_texture_cache_uastc_quality_arg :: (quality: string) -> string {
    if quality == {
    case "fast"; #through;
    case "fastest"; #through;
    case "faster"; return "0";
    case "medium"; return "1";
    case "slow"; #through;
    case "slower"; return "3";
    case "exhaustive"; return "4";
    }
    return quality;
}

run_ktx_cache_command :: (command_line: string, failure_label: string) -> bool {
    result := cache_run_command_line(command_line);
    ok := result.success;
    if !ok {
        log_error("%", failure_label);
        if result.stdout.count != 0 log_error("ktx stdout:\n%", result.stdout);
        if result.stderr.count != 0 log_error("ktx stderr:\n%", result.stderr);
    }
    cache_free_command_result(*result);
    return ok;
}

ensure_ktx_texture_cache_from_file :: (
    source_path: string,
    cache_path: string,
    options: Texture_Cache_Options,
    failure_prefix := "ktx",
) -> bool {
    if file_exists(cache_path) return true;

    tool := cache_resolve_executable("ktx");
    if tool.count == 0 {
        log_error("%: could not find ktx.", failure_prefix);
        return false;
    }
    defer free(tool);

    staging_path := tprint("%.stage.ktx2", cache_path);
    create_format := ktx_texture_cache_create_format(options.format);
    tf := ifx create_format == "R8G8B8A8_SRGB" then "srgb" else "linear";
    quality_arg := ktx_texture_cache_uastc_quality_arg(options.uastc_quality);
    source_abs := File.get_absolute_path(source_path);

    create_command: string;
    if options.generate_mips && options.normal_mode {
        create_command = tprint("% create --format % --assign-tf % --generate-mipmap --encode uastc --uastc-quality % --normal-mode % %",
            cache_shell_quote(tool), create_format, tf, quality_arg, cache_shell_quote(source_abs), cache_shell_quote(staging_path));
    } else if options.generate_mips {
        create_command = tprint("% create --format % --assign-tf % --generate-mipmap --encode uastc --uastc-quality % % %",
            cache_shell_quote(tool), create_format, tf, quality_arg, cache_shell_quote(source_abs), cache_shell_quote(staging_path));
    } else if options.normal_mode {
        create_command = tprint("% create --format % --assign-tf % --encode uastc --uastc-quality % --normal-mode % %",
            cache_shell_quote(tool), create_format, tf, quality_arg, cache_shell_quote(source_abs), cache_shell_quote(staging_path));
    } else {
        create_command = tprint("% create --format % --assign-tf % --encode uastc --uastc-quality % % %",
            cache_shell_quote(tool), create_format, tf, quality_arg, cache_shell_quote(source_abs), cache_shell_quote(staging_path));
    }

    if !run_ktx_cache_command(create_command, tprint("% create failed for %", failure_prefix, source_path)) return false;

    target := ktx_texture_cache_transcode_target(options.format);
    if target.count == 0 {
        data, ok := File.read_entire_file(staging_path);
        if ok {
            defer free(data);
            _ = File.write_entire_file(cache_path, data.data, data.count);
        }
        return file_exists(cache_path);
    }

    transcode_command := tprint("% transcode --target % % %",
        cache_shell_quote(tool), target, cache_shell_quote(staging_path), cache_shell_quote(cache_path));
    return run_ktx_cache_command(transcode_command, tprint("% transcode failed for %", failure_prefix, source_path)) && file_exists(cache_path);
}

ensure_ktx_texture_cache_from_rgba8 :: (
    source_identity: string,
    rgba: []u8,
    width: u32,
    height: u32,
    cache_path: string,
    options: Texture_Cache_Options,
    failure_prefix := "ktx",
) -> bool {
    if file_exists(cache_path) return true;

    tool := cache_resolve_executable("ktx");
    if tool.count == 0 {
        log_error("%: could not find ktx.", failure_prefix);
        return false;
    }
    defer free(tool);

    raw_path := tprint("%.rgba", cache_path);
    if !File.write_entire_file(raw_path, rgba.data, rgba.count) {
        log_error("%: failed writing temp raw texture for %", failure_prefix, source_identity);
        return false;
    }
    defer _ = File.file_delete(raw_path);

    staging_path := tprint("%.stage.ktx2", cache_path);
    create_format := ktx_texture_cache_create_format(options.format);
    tf := ifx create_format == "R8G8B8A8_SRGB" then "srgb" else "linear";
    quality_arg := ktx_texture_cache_uastc_quality_arg(options.uastc_quality);

    create_command: string;
    if options.normal_mode {
        create_command = tprint("% create --format % --assign-tf % --raw --width % --height % --encode uastc --uastc-quality % --normal-mode % %",
            cache_shell_quote(tool), create_format, tf, width, height, quality_arg, cache_shell_quote(raw_path), cache_shell_quote(staging_path));
    } else {
        create_command = tprint("% create --format % --assign-tf % --raw --width % --height % --encode uastc --uastc-quality % % %",
            cache_shell_quote(tool), create_format, tf, width, height, quality_arg, cache_shell_quote(raw_path), cache_shell_quote(staging_path));
    }
    if !run_ktx_cache_command(create_command, tprint("% raw create failed for %", failure_prefix, source_identity)) return false;

    target := ktx_texture_cache_transcode_target(options.format);
    if target.count == 0 {
        data, ok := File.read_entire_file(staging_path);
        if ok {
            defer free(data);
            _ = File.write_entire_file(cache_path, data.data, data.count);
        }
        return file_exists(cache_path);
    }

    transcode_command := tprint("% transcode --target % % %",
        cache_shell_quote(tool), target, cache_shell_quote(staging_path), cache_shell_quote(cache_path));
    return run_ktx_cache_command(transcode_command, tprint("% raw transcode failed for %", failure_prefix, source_identity)) && file_exists(cache_path);
}
