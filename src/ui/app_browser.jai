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

BeginOrReturn :: (name: string, open: *bool, window_flags: ImGui.WindowFlags) #expand {
    using ImGui;

    if !Begin(name, open, window_flags) {
        End();
        `return;
    }
    `defer End();
}

app_browser_on_ui :: () {
    if !app_ui_enabled return;
    if !app_browser_open return;

    using ImGui;


    SetNextWindowSize(.{980, 620}, .FirstUseEver);
    BeginOrReturn("App Browser", *app_browser_open, .NoFocusOnAppearing);

    build_in_flight := host_build_state == .QUEUED || host_build_state == .RUNNING;
    if build_in_flight {
        PushPopFont(fonts.monospace);
        if host_build_target.count != 0 {
            Text("% Building %...", get_spinner(), app_stem_for_source_file(host_build_target));
        } else {
            Text("% Building app...", get_spinner());
        }
    } else if host_build_state == .FAILED {
        TextColored(.{1.0, 0.45, 0.45, 1.0}, "Build failed");
        if host_build_target.count != 0 {
            SameLine();
            TextDisabled("%", app_stem_for_source_file(host_build_target));
        }
        if host_build_error.count != 0 {
            TextWrapped("%", host_build_error);
        }
    }

    avail_w := GetContentRegionAvail().x;
    card_min_w := 240.0;
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
            preview_h := card_min_w * 0.75;
            preview_size := ImVec2.{card_w, preview_h};
            corner_radius :: 0.0;
            frame_color := GetColorU32(ImVec4.{0.045, 0.045, 0.055, 1.0});
            if is_current || build_in_flight BeginDisabled();
            preview_clicked := InvisibleButton(temp_c_string(tprint("%##preview_%", app_stem, app_stem)), preview_size);
            if is_current || build_in_flight EndDisabled();
            hovered := IsItemHovered();
            max := ImVec2.{min.x + preview_size.x, min.y + preview_size.y};
            if is_current {
                frame_color = GetColorU32(ImVec4.{0.075, 0.08, 0.095, 1.0});
            } else if hovered && !build_in_flight {
                frame_color = GetColorU32(ImVec4.{0.085, 0.09, 0.105, 1.0});
            }
            ImDrawList.AddRectFilled(draw_list, min, max, frame_color, corner_radius);
            if hovered && !is_current && !build_in_flight {
                ImDrawList.AddRect(draw_list, min, max, GetColorU32(ImVec4.{1.0, 1.0, 1.0, 0.08}), corner_radius, thickness = 1.0);
            }

            if preview != null && preview.view != 0 {
                native_texture := gpu_get_native_texture(preview.view);
                if native_texture != null && preview.width > 0 && preview.height > 0 {
                    tex_ref := ImTextureRef.{_TexID = cast(ImTextureID) native_texture};
                    image_min, image_max := app_browser_fit_rect(min, preview_size, cast(float) preview.width, cast(float) preview.height);
                    ImDrawList.AddImage(draw_list, tex_ref, image_min, image_max);
                } else {
                    ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "No screenshot");
                }
            } else {
                ImDrawList.AddText(draw_list, ImVec2.{min.x + 12.0, min.y + 12.0}, GetColorU32(.TextDisabled), "No screenshot");
            }
            if preview_clicked && !is_current && !build_in_flight {
                app_browser_requested_app = app_source;
            }

            spinner_on_card := host_build_target.count != 0 && app_stem_for_source_file(host_build_target) == app_stem && build_in_flight;
            label := ifx spinner_on_card then tprint("%  %", get_spinner(), app_stem) else app_stem;
            PushFont(fonts.monospace, fonts.MAIN_SIZE + 3.0);
            defer PopFont();
            label_size := CalcTextSize(temp_c_string(label));
            label_pos := ImVec2.{
                min.x + floor((preview_size.x - label_size.x) * 0.5),
                min.y + floor((preview_size.y - label_size.y) * 0.5),
            };
            shadow_pos := ImVec2.{label_pos.x + 1.0, label_pos.y + 1.0};
            ImDrawList.AddText(draw_list, shadow_pos, GetColorU32(ImVec4.{0.0, 0.0, 0.0, 0.85}), label);
            ImDrawList.AddText(draw_list, label_pos, GetColorU32(ImVec4.{1.0, 1.0, 1.0, 0.96}), label);

            if is_current {
                loaded_text :: "Loaded";
                loaded_size := CalcTextSize(loaded_text);
                loaded_pos := ImVec2.{max.x - loaded_size.x - 10.0, max.y - loaded_size.y - 8.0};
                ImDrawList.AddText(draw_list, loaded_pos, GetColorU32(ImVec4.{1.0, 1.0, 1.0, 0.55}), loaded_text);
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
} @on_quit

File_Utilities :: #import "File_Utilities";
#import "stb_image";
}

spinner_frames :: string.["|", "/", "-", "\\"];

get_spinner :: () -> string {
    return spinner_frames[(frame_count / 8) % spinner_frames.count];
}

#scope_file
String :: #import "String";
