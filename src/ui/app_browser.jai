//
// A picker for changing apps
//

#if !SINGLE_BINARY {
app_browser_on_ui :: () {
    if !app_ui_enabled return;
    if !app_browser_open return;

    using,except(Viewport) ImGui :: #import "ImGui";

    SetNextWindowSize(.{760, 420}, .FirstUseEver);
    window_flags: WindowFlags = .NoFocusOnAppearing;
    if !Begin("App Browser", *app_browser_open, window_flags) {
        End();
        return;
    }
    defer End();

    Text("Current app: %", APP_STEM);
    Separator();

    avail_w := GetContentRegionAvail().x;
    button_min_w := 160.0;
    columns: s32 = cast(s32) floor((avail_w + 12.0) / (button_min_w + 12.0));
    if columns < 1 columns = 1;
    if BeginTable("app_browser_grid", columns, .SizingStretchSame, .{0.0, 0.0}) {
        defer EndTable();

        for app_source: APP_FILES {
            TableNextColumn();

            app_stem := app_stem_for_source_file(app_source);
            is_current := app_stem == APP_STEM;
            if is_current BeginDisabled();
            if Button(temp_c_string(app_stem), .{-1.0, 56.0}) && !is_current {
                app_browser_requested_app = app_source;
            }
            if is_current {
                EndDisabled();
                TextDisabled("Loaded");
            }
        }
    }
} @on_ui
}
