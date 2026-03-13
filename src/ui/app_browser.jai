//
// A picker for changing apps
//

#if !SINGLE_BINARY {
App_Browser_Preview :: struct {
    source_file: string;
    resolved_path: string;
    texture: Gpu_Texture;
    view: Gpu_Texture_View;
    width: s32;
    height: s32;
    file_modification: Apollo_Time;
    file_size: s64;
    load_attempted: bool;
}

app_browser_previews: [..] App_Browser_Preview;

app_browser_on_ui :: () {
    if !app_ui_enabled return;
    if !app_browser_open return;

    using,except(Viewport) ImGui :: #import "ImGui";

    SetNextWindowSize(.{980, 620}, .FirstUseEver);
    window_flags: WindowFlags = .NoFocusOnAppearing;
    if !Begin("App Browser", *app_browser_open, window_flags) {
        End();
        return;
    }
    defer End();


    Text("Current app: %", APP_STEM);
    TextDisabled("Previews come from '%'.", APP_CAPTURE_DIR);
    Separator();

    avail_w := GetContentRegionAvail().x;
    card_min_w := 220.0;
    columns: s32 = cast(s32) floor((avail_w + 14.0) / (card_min_w + 14.0));
    if columns < 1 columns = 1;

    if BeginTable("app_browser_grid", columns, .SizingStretchSame, .{0.0, 0.0}) {
        defer EndTable();

        for app_source: APP_FILES {
            TableNextColumn();

            app_stem := app_stem_for_source_file(app_source);
            is_current := app_stem == APP_STEM;
            preview := app_browser_get_or_load_preview(app_source);

            BeginGroup();
            draw_list := GetWindowDrawList();
            min := GetCursorScreenPos();
            card_w := GetContentRegionAvail().x;
            if card_w <= 0.0 card_w = card_min_w;
            preview_h :: 118.0;
            preview_size := ImVec2.{card_w, preview_h};
            frame_color := ifx is_current then GetColorU32(.ButtonActive) else GetColorU32(.FrameBg);
            if is_current BeginDisabled();
            preview_clicked := Button(temp_c_string(tprint("%##preview_%", app_stem, app_stem)), preview_size);
            if is_current EndDisabled();
            max := ImVec2.{min.x + preview_size.x, min.y + preview_size.y};
            ImGui.ImDrawList.AddRectFilled(draw_list, min, max, frame_color, 8.0);

            if preview != null && preview.view != 0 {
                native_texture := gpu_get_native_texture(preview.view);
                if native_texture != null && preview.width > 0 && preview.height > 0 {
                    tex_ref := ImTextureRef.{_TexID = cast(ImTextureID) native_texture};
                    image_min, image_max := app_browser_fit_rect(min, preview_size, cast(float) preview.width, cast(float) preview.height);
                    ImGui.ImDrawList.AddImage(draw_list, tex_ref, image_min, image_max);
                } else {
                    ImGui.ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "No screenshot");
                }
            } else {
                ImGui.ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "No screenshot");
            }
            if preview_clicked && !is_current {
                app_browser_requested_app = app_source;
            }

            spacing_y := GetStyle().ItemSpacing.y;
            SetCursorPosY(GetCursorPosY() + spacing_y);
            Text("%", app_stem);
            if is_current {
                TextDisabled("Loaded");
            }
            EndGroup();
        }
    }
} @on_ui

app_browser_get_or_load_preview :: (app_source: string) -> *App_Browser_Preview {
    for *app_browser_previews {
        if it.source_file == app_source {
            app_browser_refresh_preview_if_needed(it);
            return it;
        }
    }

    preview := App_Browser_Preview.{
        source_file = copy_string(app_source),
    };
    array_add(*app_browser_previews, preview);
    out := app_browser_previews.data + (app_browser_previews.count - 1);
    app_browser_refresh_preview_if_needed(out);
    return out;
}

app_browser_refresh_preview_if_needed :: (preview: *App_Browser_Preview) {
    resolved_path := app_browser_resolve_capture_path(preview.source_file);
    if resolved_path.count == 0 {
        preview.load_attempted = true;
        return;
    }

    modtime, size, exists := File_Utilities.file_modtime_and_size(resolved_path);
    if !exists return;
    if preview.view != 0 && preview.resolved_path == resolved_path && preview.file_size == size && compare_apollo_times(modtime, preview.file_modification) == 0 {
        return;
    }

    app_browser_release_preview(preview);
    texture, view, image_w, image_h, loaded := app_browser_load_preview_texture(resolved_path);
    if !loaded return;

    preview.texture = texture;
    preview.view = view;
    preview.width = image_w;
    preview.height = image_h;
    preview.file_modification = modtime;
    preview.file_size = size;
    preview.resolved_path = copy_string(resolved_path);
    preview.load_attempted = true;
}

app_browser_resolve_capture_path :: (app_source: string) -> string {
    direct := app_capture_path_for_source_file(app_source);
    if File_Utilities.file_exists(direct) return copy_string(direct);

    parent := String.path_join("..", app_capture_path_for_source_file(app_source),, temp);
    if File_Utilities.file_exists(parent) return copy_string(parent);

    return "";
}

app_browser_load_preview_texture :: (path: string) -> Gpu_Texture, Gpu_Texture_View, s32, s32, bool {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);
    if pixels == null || width <= 0 || height <= 0 {
        log_error("App Browser: failed to load screenshot '%'.", path);
        return 0, 0, 0, 0, false;
    }

    texture_result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    if texture_result != .SUCCESS || texture == 0 {
        log_error("App Browser: failed to create texture for '%': %.", path, texture_result);
        return 0, 0, 0, 0, false;
    }

    gpu_copy_to_texture(texture, pixels);
    view := gpu_texture_view(texture);
    if view == 0 {
        log_error("App Browser: failed to create texture view for '%'.", path);
        return texture, 0, 0, 0, false;
    }

    gpu_commit_residency();

    return texture, view, width, height, true;
}

app_browser_release_preview :: (preview: *App_Browser_Preview) {
    if preview.view != 0 {
        gpu_free_texture_view(preview.view);
        preview.view = 0;
    }
    if preview.resolved_path.count != 0 {
        free(preview.resolved_path);
        preview.resolved_path = "";
    }
    preview.texture = 0;
    preview.width = 0;
    preview.height = 0;
    preview.file_modification = .{};
    preview.file_size = 0;
}

app_browser_fit_rect :: (origin: Vector2, bounds: Vector2, image_w: float, image_h: float) -> Vector2, Vector2 {
    scale_x := bounds.x / image_w;
    scale_y := bounds.y / image_h;
    scale := min(scale_x, scale_y);
    fit_w := image_w * scale;
    fit_h := image_h * scale;
    offset_x := (bounds.x - fit_w) * 0.5;
    offset_y := (bounds.y - fit_h) * 0.5;
    return Vector2.{origin.x + offset_x, origin.y + offset_y}, Vector2.{origin.x + offset_x + fit_w, origin.y + offset_y + fit_h};
}

app_browser_shutdown :: () {
    for *app_browser_previews {
        app_browser_release_preview(it);
        if it.source_file.count != 0 {
            free(it.source_file);
            it.source_file = "";
        }
    }
    array_reset(*app_browser_previews);
} @on_unload

File_Utilities :: #import "File_Utilities";
#import "stb_image";
}
