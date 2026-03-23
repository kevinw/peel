reports: [..]struct {
    text: string;
    time_left: float;
    loc: Source_Code_Location;
    common_flags: Log_Flags;
};

DEFAULT_TIMEOUT_SECONDS :: 3.0;

report_replace :: (text: string, fmt_args: ..Any, timeout_seconds := 3.0, loc := #caller_location) {
    for * reports {
        if it.loc == loc {
            free(it.text);
            it.text = sprint(text, ..fmt_args);
            it.time_left = max(0.0, timeout_seconds);
            return;
        }
    }

    report(text, ..fmt_args, timeout_seconds=timeout_seconds, loc=loc);
}

report :: (text: string, fmt_args: ..Any, timeout_seconds:float = 0, common_flags := Log_Flags.NONE, loc := #caller_location) {
    if timeout_seconds <= 0 {
        timeout_seconds = DEFAULT_TIMEOUT_SECONDS;
        if common_flags & .ERROR != 0
            timeout_seconds = 7.0;
    }

    new_report := array_add(*reports);
    new_report.text = sprint(text, ..fmt_args);
    new_report.time_left = max(0.0, timeout_seconds);
    new_report.loc = loc;
    new_report.common_flags = common_flags;
}

update_and_render_reports :: () {
    dt := editor_dt;
    draw_list := GetForegroundDrawList();
    viewport_work_width := GetMainViewport().WorkSize.x;
    total_screen_height := GetMainViewport().WorkSize.y;

    font_size := fonts.LARGE_SIZE;
    PushPopFont(fonts.main, font_size);

    y :float = total_screen_height / 5.0;
    shadow_offset := font_size * 0.06;
    for * reports {
        it.time_left -= dt;
        if it.time_left <= 0.0 {
            free(it.text);
            remove it;
            continue;
        }
        centered_x := (viewport_work_width - CalcTextSize(it.text).x) / 2.0;

        // AA BB GG RR
        color:        u32 = 0xffffffff;
        shadow_color: u32 = 0xaa000000;
        if it.common_flags & .ERROR != 0
            color = 0xff5555ff;

        draw_list.AddText(draw_list, .{centered_x + shadow_offset, y + shadow_offset}, shadow_color, it.text);
        draw_list.AddText(draw_list, .{centered_x, y}, color, it.text);
        y += font_size;
    }
} @on_ui

operator == :: (a: Source_Code_Location, b: Source_Code_Location) -> bool {
    return a.fully_pathed_filename == b.fully_pathed_filename && a.line_number == b.line_number && a.character_number == b.character_number;
}

#scope_file
using ImGui;
