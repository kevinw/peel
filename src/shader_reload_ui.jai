shader_hot_reload_status_line :: (max_ids_chars: s64 = 72) -> string {
    using reload := shader_hot_reload_current_ctx();
    if !enabled return "";

    if last_result == .NONE return "";
    ids := watcher.last_changed_entry_ids_csv;
    ids_short := ids;
    if max_ids_chars > 0 && ids_short.count > max_ids_chars {
        ids_short.count = max_ids_chars;
        ids_short = tprint("%...", ids_short);
    }

    result_text := tprint("%", last_result);
    if reload.last_event_frame < 0 return tprint("shader_reload=on status=%", result_text);
    if ids_short.count == 0 return tprint("shader_reload=on status=% frame=%", result_text, last_event_frame);
    return tprint("shader_reload=on status=% frame=% ids=%", result_text, last_event_frame, ids_short);
}

shader_hot_reload_imgui :: (monospace_font: *ImGui.ImFont = null) {
    using reload := shader_hot_reload_current_ctx();
    if !reload || !show_error_window || last_error_message.count == 0 return;
    io := ImGui.GetIO();
    overlay_height := clamp(io.DisplaySize.y * 0.45, 220.0, io.DisplaySize.y - 24.0);
    ImGui.SetNextWindowPos(.{0.0, io.DisplaySize.y - overlay_height}, .Always);
    ImGui.SetNextWindowSize(.{io.DisplaySize.x, overlay_height}, .Always);
    open := true;
    window_flags: ImGui.WindowFlags = .NoMove | .NoResize | .NoCollapse | .NoSavedSettings | .NoNav | .NoBringToFrontOnFocus;
    if ImGui.Begin("Live shader reload failed.", *open, window_flags) {
        if monospace_font != null ImGui.PushFont(monospace_font, 0.0);
        defer if monospace_font != null ImGui.PopFont();
        avail := ImGui.GetContentRegionAvail();
        if ImGui.BeginChild("shader_reload_error_text", .{avail.x, avail.y}, .None) {
            draw_error_message_with_links(last_error_message);
        }
        ImGui.EndChild();
    }
    ImGui.End();
    if !open show_error_window = false;
}

shader_hot_reload_build_failed_message :: (log_prefix: string, ids_csv: string, details: string) -> string {
    base := tprint("% build failed for ids=%", log_prefix, ids_csv);
    if details.count == 0 return base;
    return tprint("%\n\n%", base, details);
}

shader_hot_reload_parse_source_location :: (line: string, out_path: *string, out_line: *s64, out_col: *s64) -> bool {
    if line.count == 0 return false;
    jai_marker := ".jai:";
    marker_at: s64 = -1;
    if line.count >= jai_marker.count {
        max_start := line.count - jai_marker.count;
        for i: 0..max_start {
            match := true;
            for j: 0..jai_marker.count-1 {
                if line[i + j] != jai_marker[j] {
                    match = false;
                    break;
                }
            }
            if match {
                marker_at = i;
                break;
            }
        }
    }
    if marker_at <= 0 return false;
    if line[0] != #char "/" return false;

    path_len := marker_at + 4;
    path: string = .{count = path_len, data = line.data};
    i := marker_at + jai_marker.count;
    if i >= line.count return false;

    line_no: s64 = 0;
    has_line_digits := false;
    while i < line.count {
        c := line[i];
        if c < #char "0" || c > #char "9" break;
        has_line_digits = true;
        line_no = line_no * 10 + cast(s64) (c - #char "0");
        i += 1;
    }
    if !has_line_digits return false;

    col_no: s64 = 0;
    if i < line.count && line[i] == #char "," {
        i += 1;
        has_col_digits := false;
        while i < line.count {
            c := line[i];
            if c < #char "0" || c > #char "9" break;
            has_col_digits = true;
            col_no = col_no * 10 + cast(s64) (c - #char "0");
            i += 1;
        }
        if !has_col_digits col_no = 0;
    }

    if i >= line.count || line[i] != #char ":" return false;

    out_path.* = path;
    out_line.* = line_no;
    out_col.* = col_no;
    return true;
}

#scope_file
draw_error_message_with_links :: (message: string) {
    if message.count == 0 return;
    line_idx: s64 = 0;
    for String.split(message, #char "\n") {
        path: string;
        line_no: s64;
        col_no: s64;
        has_loc := shader_hot_reload_parse_source_location(it, *path, *line_no, *col_no);
        if has_loc {
            label := tprint("Open##shader_reload_open_%", line_idx);
            if ImGui.SmallButton(temp_c_string(label)) {
                arg := tprint("%:%", path, line_no);
                _ = Process.run_command("zed", arg, timeout_ms = 5000);
            }
            ImGui.SameLine();
        }
        ImGui.TextUnformatted(it);
        line_idx += 1;
    }
}
