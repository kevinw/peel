#if SINGLE_BINARY || true {

INSPIRATION_DIR :: "./inspiration";
INSPIRATION_BOARD_PATH :: "./inspiration/board.txt";
INSPIRATION_THUMB_DIR :: "./inspiration/thumbs";
INSPIRATION_ASSET_DIR :: "./inspiration/assets";
INSPIRATION_THUMB_MAX_DIM :: 256;
INSPIRATION_MIN_ITEM_SIZE :: 48.0;

Inspiration_Item :: struct {
    source_path: string;
    url: string;
    thumb_cache_path: string;
    source_modtime: Apollo_Time;
    source_size: s64;

    x: float;
    y: float;
    width: float;
    height: float;
    image_width: s32;
    image_height: s32;

    thumb_texture: Gpu_Texture;
    thumb_view: Gpu_Texture_View;
    full_texture: Gpu_Texture;
    full_view: Gpu_Texture_View;

    full_requested: bool;
    full_upload_pending: bool;
}

Inspiration_Drag_Mode :: enum {
    NONE;
    PAN;
    MOVE_ITEM;
    RESIZE_TL;
    RESIZE_TR;
    RESIZE_BL;
    RESIZE_BR;
}

Inspiration_Load_Request :: struct {
    source_path: string;
}

Inspiration_Load_Completion :: struct {
    source_path: string;
    pixels: *u8;
    width: s32;
    height: s32;
    success: bool;
}

Inspiration_Load_Worker :: struct {
    started: bool;
    should_exit: bool;
    thread: Thread.Thread;
    wake: Thread.Semaphore;
    mutex: Thread.Mutex;
    pending: [..]Inspiration_Load_Request;
    completed: [..]Inspiration_Load_Completion;
}

Inspiration_View_Parse :: struct {
    xy: Vector2;
    z: float;
}

Inspiration_Board :: struct {
    initialized: bool;
    content_loaded: bool;
    open: bool;
    dirty: bool;

    items: [..]Inspiration_Item;
    selected_index: s32 = -1;
    hovered_index: s32 = -1;

    view_offset: Vector2 = .{120.0, 120.0};
    zoom: float = 1.0;
    last_canvas_min: Vector2;
    last_canvas_max: Vector2;
    canvas_hovered: bool;

    drag_mode: Inspiration_Drag_Mode;
    drag_item_index: s32 = -1;
    drag_mouse_start_screen: Vector2;
    drag_view_offset_start: Vector2;
    drag_item_start_x: float;
    drag_item_start_y: float;
    drag_item_start_w: float;
    drag_item_start_h: float;
    click_open_candidate_index: s32 = -1;

    full_load_worker: Inspiration_Load_Worker;
    dropped_paths: [..]string;

    context_item_index: s32 = -1;
    url_input_buffer: [1024]u8;
}

inspiration_board: Inspiration_Board;

inspiration_board_set_open :: (open: bool) {
    ensure_init(*inspiration_board);
    inspiration_board.open = open;
    if open {
        ensure_content_loaded(*inspiration_board);
        app_ui_enabled = true;
    }
}

inspiration_board_toggle :: () {
    inspiration_board_set_open(!inspiration_board.open);
}

inspiration_board_note_dropped_file :: (path: string) {
    ensure_init(*inspiration_board);
    #if _VERBOSE log("Inspiration DnD: note dropped file '%'", path);
    array_add(*inspiration_board.dropped_paths, copy_string(path));
    #if _VERBOSE log("Inspiration DnD: queued dropped file, pending paths=%", inspiration_board.dropped_paths.count);
}

ensure_init :: (using board: *Inspiration_Board) {
    if initialized return;

    items.allocator = context.allocator;
    dropped_paths.allocator = context.allocator;
    full_load_worker.pending.allocator = context.allocator;
    full_load_worker.completed.allocator = context.allocator;
    File.make_directory_if_it_does_not_exist(INSPIRATION_DIR, true);
    File.make_directory_if_it_does_not_exist(INSPIRATION_THUMB_DIR, true);
    File.make_directory_if_it_does_not_exist(INSPIRATION_ASSET_DIR, true);
    initialized = true;
}

ensure_content_loaded :: (using board: *Inspiration_Board) {
    ensure_init(board);
    if content_loaded return;
    init(*full_load_worker);
    load(board);
    content_loaded = true;
    #if _VERBOSE log("Inspiration: content loaded, items=%", items.count);
}

init :: (worker: *Inspiration_Load_Worker) {
    if worker.started return;
    Thread.init(*worker.wake, 0);
    Thread.init(*worker.mutex, "inspiration_loader");
    ok := Thread.thread_init(*worker.thread, inspiration_load_worker_proc);
    if !ok {
        log_error("Inspiration: failed to start background image loader thread.");
        return;
    }
    worker.thread.data = worker;
    Thread.thread_start(*worker.thread);
    worker.started = true;
    #if _VERBOSE log("Inspiration: background worker started");
}

deinit :: (worker: *Inspiration_Load_Worker) {
    if worker.started {
        Thread.lock(*worker.mutex);
        worker.should_exit = true;
        Thread.unlock(*worker.mutex);
        Thread.signal(*worker.wake);
        Thread.thread_deinit(*worker.thread);
        worker.started = false;
    }

    for *worker.pending {
        if it.source_path.count != 0 free(it.source_path);
    }
    for *worker.completed {
        if it.source_path.count != 0 free(it.source_path);
        if it.pixels != null stbi_image_free(it.pixels);
    }
    array_reset(*worker.pending);
    array_reset(*worker.completed);
}

queue :: (worker: *Inspiration_Load_Worker, source_path: string) {
    if !worker.started return;

    Thread.lock(*worker.mutex);
    defer Thread.unlock(*worker.mutex);

    for worker.pending {
        if it.source_path == source_path return;
    }
    for worker.completed {
        if it.source_path == source_path return;
    }

    array_add(*worker.pending, .{source_path = copy_string(source_path)});
    #if _VERBOSE log("Inspiration: queued full image load '%', pending=%", source_path, worker.pending.count);
    Thread.signal(*worker.wake);
}

take_completed :: (worker: *Inspiration_Load_Worker, out: *Inspiration_Load_Completion) -> bool {
    if !worker.started return false;

    Thread.lock(*worker.mutex);
    defer Thread.unlock(*worker.mutex);
    if worker.completed.count <= 0 return false;

    out.* = worker.completed[0];
    array_ordered_remove_by_index(*worker.completed, 0);
    return true;
}

load :: (using board: *Inspiration_Board) {
    #if _VERBOSE log("Inspiration Load: reading '%'", INSPIRATION_BOARD_PATH);
    contents, ok := File.read_entire_file(INSPIRATION_BOARD_PATH, zero_terminated = false, log_errors = false);
    if !ok {
        log("Inspiration Load: no board file");
        return;
    }
    defer free(contents);

    lines := String.split(contents, 10);
    #if _VERBOSE log("Inspiration Load: % lines", lines.count);
    for line_raw: lines {
        line := String.trim(line_raw);
        if line.count == 0 continue;
        if String.starts_with(line, "#") continue;
        #if _VERBOSE log("Inspiration Load: line '%'", line);

        if String.starts_with(line, "view ") {
            parsed, ok_view := inspiration_parse_view_line(line);
            if ok_view {
                view_offset = parsed.xy;
                zoom = parsed.z;
                #if _VERBOSE log("Inspiration Load: view parsed offset=% zoom=%", view_offset, zoom);
            }
            continue;
        }

        if !String.starts_with(line, "item ") continue;
        item, ok_item := inspiration_parse_item_line(line);
        if !ok_item {
            #if _VERBOSE log("Inspiration Load: failed to parse item line");
            continue;
        }
        inspiration_load_item_thumbnail(board.*, item);
        array_add(*items, item.*);
        #if _VERBOSE log("Inspiration Load: added item '%', items=%", item.source_path, items.count);
        free(item);
    }
    #if _VERBOSE log("Inspiration Load: done, items=%", items.count);
}

save :: (using board: *Inspiration_Board) {
    if !content_loaded {
        #if _VERBOSE log("Inspiration Save: skipped because content was never loaded");
        dirty = false;
        return;
    }
    File.make_directory_if_it_does_not_exist(INSPIRATION_DIR, true);
    #if _VERBOSE log("Inspiration Save: begin, items=% selected=% dirty=%", items.count, selected_index, dirty);

    builder: String_Builder;
    builder.allocator = temp;
    print_to_builder(*builder, "# peel inspiration board v1\n");
    print_to_builder(*builder, "view % % %\n", view_offset.x, view_offset.y, zoom);
    for *items {
        #if _VERBOSE log("Inspiration Save: item '%' pos=(%, %) size=(%, %)", it.source_path, it.x, it.y, it.width, it.height);
        escaped := inspiration_escape_string(it.source_path,, temp);
        escaped_url := inspiration_escape_string(it.url,, temp);
        print_to_builder(*builder, "item \"%\" % % % % \"%\"\n", escaped, it.x, it.y, it.width, it.height, escaped_url);
    }

    ok := File.write_entire_file(INSPIRATION_BOARD_PATH, *builder);
    if !ok {
        log_error("Inspiration: failed to write board file '%'.", INSPIRATION_BOARD_PATH);
        return;
    }
    #if _VERBOSE log("Inspiration Save: wrote '%'\n%", INSPIRATION_BOARD_PATH, builder_to_string(*builder));
    dirty = false;
}

do_ui :: (using board: *Inspiration_Board) {
    if !open return;
    if !app_ui_enabled return;
    ensure_content_loaded(board);
    process_async_completions(board);
    inspiration_consume_dropped_paths(board);

    using,except(Viewport) ImGui;

    SetNextWindowSize(.{1100.0, 760.0}, .FirstUseEver);
    begin_or_return("Inspiration", *board.open, .NoFocusOnAppearing | .NoScrollbar | .NoScrollWithMouse);

    if Button("Save") save(board);
    SameLine();
    TextDisabled("F4 toggles this board");
    SameLine();
    TextDisabled("Zoom %.2fx", zoom);
    SameLine();
    TextDisabled("Images %", items.count);
    SameLine();
    selected_path := ifx selected_index >= 0 && selected_index < items.count then items[selected_index].source_path else "-";
    TextDisabled("Selected %", selected_path);

    canvas_min := GetCursorScreenPos();
    canvas_size := GetContentRegionAvail();
    if canvas_size.x < 64.0 canvas_size.x = 64.0;
    if canvas_size.y < 64.0 canvas_size.y = 64.0;

    _ = InvisibleButton("##inspiration_canvas", canvas_size, .MouseButtonLeft | .MouseButtonMiddle);
    last_canvas_min = .{canvas_min.x, canvas_min.y};
    last_canvas_max = .{canvas_min.x + canvas_size.x, canvas_min.y + canvas_size.y};
    canvas_hovered = IsItemHovered();

    draw := GetWindowDrawList();
    canvas_max := ImVec2.{canvas_min.x + canvas_size.x, canvas_min.y + canvas_size.y};
    ImDrawList.AddRectFilled(draw, canvas_min, canvas_max, GetColorU32(ImVec4.{0.055, 0.058, 0.066, 1.0}), 0.0);
    ImDrawList.PushClipRect(draw, canvas_min, canvas_max, true);
    defer ImDrawList.PopClipRect(draw);

    inspiration_draw_grid(board.*, draw, canvas_min, canvas_size);
    inspiration_handle_canvas_input(board, canvas_min, canvas_size);
    inspiration_draw_items(board, draw, canvas_min);
    inspiration_draw_context_popup(board);

    if drag_mode == .NONE && canvas_hovered && IsMouseClicked(.Left, false) && hovered_index < 0 {
        selected_index = -1;
        dirty = true;
    }

    if selected_index >= 0 && IsKeyPressed(.Delete) {
        inspiration_remove_selected(board);
    }
    if dirty save(board);
}

inspiration_board_on_ui :: () {
    do_ui(*inspiration_board);
} @on_ui

begin_or_return :: (name: string, open: *bool, window_flags: ImGui.WindowFlags) #expand {
    using ImGui;
    if !Begin(name, open, window_flags) {
        End();
        `return;
    }
    `defer End();
}

process_input_events :: (using board: *Inspiration_Board, events: []Input.Event) {
    ensure_init(board);
    for events {
        if it.type != .DRAG_AND_DROP_FILES continue;
        if !open continue;
        ensure_content_loaded(board);
        #if _VERBOSE log("Inspiration DnD: input event delivered with % files", it.files.count);
        for path: it.files {
            #if _VERBOSE log("Inspiration DnD: input event path '%'", path);
            inspiration_add_image(board, path);
        }
    }
}

shutdown :: (using board: *Inspiration_Board) {
    if !initialized return;
    if content_loaded save(board);
    for *items {
        inspiration_release_item(it);
    }
    for dropped_paths {
        if it.count != 0 free(it);
    }
    array_reset(*items);
    array_reset(*dropped_paths);
    deinit(*full_load_worker);
    board.* = .{};
}

inspiration_board_on_unload :: () {
    shutdown(*inspiration_board);
} @on_unload

#scope_file

inspiration_add_image :: (using board: *Inspiration_Board, path: string) {
    #if _VERBOSE log("Inspiration Add: begin '%'", path);
    if !inspiration_path_looks_like_image(path) return;

    source_path := copy_string(path);
    modtime, size, exists := File_Utilities.file_modtime_and_size(source_path);
    if !exists {
        log("Inspiration Add: file does not exist '%'", source_path);
        free(source_path);
        return;
    }

    normalized := inspiration_copy_asset_into_board(source_path, modtime, size);
    free(source_path);
    if normalized.count == 0 return;
    modtime, size, exists = File_Utilities.file_modtime_and_size(normalized);
    if !exists {
        log_error("Inspiration Add: file does not exist '%'", normalized);
        free(normalized);
        return;
    }

    for *items {
        if it.source_path == normalized {
            log_error("Inspiration Add: already present '%'", normalized);
            selected_index = cast(s32) it_index;
            free(normalized);
            return;
        }
    }

    item := Inspiration_Item.{
        source_path = normalized,
        source_modtime = modtime,
        source_size = size,
        x = cast(float) items.count * 80.0,
        y = cast(float) items.count * 60.0,
        width = 320.0,
        height = 240.0,
    };
    item.thumb_cache_path = inspiration_thumbnail_cache_path(item.source_path, item.source_modtime, item.source_size);
    #if _VERBOSE log("Inspiration Add: thumb cache path '%'", item.thumb_cache_path);
    inspiration_generate_thumbnail_if_needed(*item);
    #if _VERBOSE log("Inspiration Add: thumbnail ready/load attempt '%'", item.source_path);
    inspiration_load_item_thumbnail(board.*, *item);
    if item.image_width > 0 && item.image_height > 0 {
        item.height = item.width * cast(float) item.image_height / cast(float) item.image_width;
    }
    array_add(*items, item);
    selected_index = cast(s32) items.count - 1;
    dirty = true;
    #if _VERBOSE log("Inspiration Add: added '%', items=% thumb_view=% full_view=% size=%x%", item.source_path, items.count, item.thumb_view, item.full_view, item.image_width, item.image_height);
}

inspiration_consume_dropped_paths :: (using board: *Inspiration_Board) {
    if dropped_paths.count <= 0 return;
    #if _VERBOSE log("Inspiration DnD: consuming % queued dropped paths", dropped_paths.count);
    for path: dropped_paths {
        #if _VERBOSE log("Inspiration DnD: consume '%'", path);
        inspiration_add_image(board, path);
        if path.count != 0 free(path);
    }
    array_reset(*dropped_paths);
    #if _VERBOSE log("Inspiration DnD: consume complete");
}

inspiration_remove_selected :: (using board: *Inspiration_Board) {
    if selected_index < 0 || selected_index >= items.count return;
    item := items[selected_index];
    array_ordered_remove_by_index(*items, cast(int) selected_index);
    inspiration_release_item(*item);
    if selected_index >= items.count selected_index = cast(s32) items.count - 1;
    dirty = true;
}

inspiration_release_item :: (item: *Inspiration_Item) {
    if item.thumb_view != 0 gpu_free_texture_view(item.thumb_view);
    if item.full_view != 0 gpu_free_texture_view(item.full_view);
    if item.source_path.count != 0 free(item.source_path);
    if item.url.count != 0 free(item.url);
    if item.thumb_cache_path.count != 0 free(item.thumb_cache_path);
    item.* = .{};
}

inspiration_handle_canvas_input :: (using board: *Inspiration_Board, canvas_min: ImGui.ImVec2, canvas_size: ImGui.ImVec2) {
    using ImGui;

    io := GetIO();
    mouse := GetMousePos();
    mouse_v := Vector2.{mouse.x, mouse.y};
    mouse_world := inspiration_screen_to_world(board.*, mouse_v);

    if canvas_hovered {
        wheel := io.MouseWheel;
        if abs(wheel) > 0.0001 {
            old_world := mouse_world;
            zoom = clamp(zoom * (1.0 + wheel * 0.12), 0.1, 8.0);
            new_screen := inspiration_world_to_screen(board.*, old_world);
            view_offset += mouse_v - new_screen;
            dirty = true;
        }
    }

    if drag_mode == .NONE && canvas_hovered && IsMouseClicked(.Middle, false) {
        drag_mode = .PAN;
        drag_mouse_start_screen = mouse_v;
        drag_view_offset_start = view_offset;
    }

    if drag_mode == .PAN {
        if IsMouseDown(.Middle) {
            view_offset = drag_view_offset_start + (mouse_v - drag_mouse_start_screen);
            dirty = true;
        } else {
            drag_mode = .NONE;
        }
    }
}

inspiration_draw_grid :: (using board: Inspiration_Board, draw: *ImGui.ImDrawList, canvas_min: ImGui.ImVec2, canvas_size: ImGui.ImVec2) {
    minor_world := 128.0;
    major_world := 512.0;

    view_w := canvas_size.x / zoom;
    view_h := canvas_size.y / zoom;
    world_min := Vector2.{-view_offset.x / zoom, -view_offset.y / zoom};
    world_max := world_min + .{view_w, view_h};

    inspiration_draw_grid_lines(board, draw, canvas_min, world_min, world_max, minor_world, ImGui.GetColorU32(ImGui.ImVec4.{1, 1, 1, 0.035}));
    inspiration_draw_grid_lines(board, draw, canvas_min, world_min, world_max, major_world, ImGui.GetColorU32(ImGui.ImVec4.{1, 1, 1, 0.08}));
}

inspiration_draw_grid_lines :: (using board: Inspiration_Board, draw: *ImGui.ImDrawList, canvas_min: ImGui.ImVec2, world_min: Vector2, world_max: Vector2, spacing: float, color: ImGui.ImU32) {
    start_x := floor(world_min.x / spacing) * spacing;
    end_x := ceil(world_max.x / spacing) * spacing;
    x := start_x;
    while x <= end_x {
        s0 := inspiration_world_to_screen(board, .{x, world_min.y});
        s1 := inspiration_world_to_screen(board, .{x, world_max.y});
        ImGui.ImDrawList.AddLine(draw, .{s0.x, s0.y}, .{s1.x, s1.y}, color, 1.0);
        x += spacing;
    }

    start_y := floor(world_min.y / spacing) * spacing;
    end_y := ceil(world_max.y / spacing) * spacing;
    y := start_y;
    while y <= end_y {
        s0 := inspiration_world_to_screen(board, .{world_min.x, y});
        s1 := inspiration_world_to_screen(board, .{world_max.x, y});
        ImGui.ImDrawList.AddLine(draw, .{s0.x, s0.y}, .{s1.x, s1.y}, color, 1.0);
        y += spacing;
    }
}

inspiration_draw_items :: (using board: *Inspiration_Board, draw: *ImGui.ImDrawList, canvas_min: ImGui.ImVec2) {
    using ImGui;

    mouse := GetMousePos();
    mouse_v := Vector2.{mouse.x, mouse.y};
    hovered_index = -1;

    for *items {
        min_screen := inspiration_world_to_screen(board.*, .{it.x, it.y});
        max_screen := inspiration_world_to_screen(board.*, .{it.x + it.width, it.y + it.height});
        if max_screen.x < last_canvas_min.x || min_screen.x > last_canvas_max.x || max_screen.y < last_canvas_min.y || min_screen.y > last_canvas_max.y {
            continue;
        }

        view := ifx it.full_view != 0 then it.full_view else it.thumb_view;
        if view != 0 {
            native_texture := gpu_get_native_texture(view);
            if native_texture != null {
                tex_ref := ImTextureRef.{_TexID = cast(ImTextureID) native_texture};
                ImDrawList.AddImage(draw, tex_ref, .{min_screen.x, min_screen.y}, .{max_screen.x, max_screen.y});
            }
        }

        bg_col := GetColorU32(ImVec4.{0.09, 0.09, 0.11, 0.7});
        if view == 0 {
            ImDrawList.AddRectFilled(draw, .{min_screen.x, min_screen.y}, .{max_screen.x, max_screen.y}, bg_col, 4.0);
            ImDrawList.AddText(draw, .{min_screen.x + 12.0, min_screen.y + 12.0}, GetColorU32(.TextDisabled), "Loading...");
        }

        hovered := inspiration_point_in_rect(mouse_v, min_screen, max_screen);
        if hovered hovered_index = cast(s32) it_index;
        if hovered && it.url.count != 0 && drag_mode == .NONE {
            SetMouseCursor(.Hand);
        }

        selected := selected_index == cast(s32) it_index;
        border_col := ifx selected then GetColorU32(ImVec4.{1.0, 0.78, 0.2, 1.0}) else ifx hovered then GetColorU32(ImVec4.{0.8, 0.84, 1.0, 0.55}) else GetColorU32(ImVec4.{1.0, 1.0, 1.0, 0.15});
        border_thickness := ifx selected then 2.5 else 1.0;
        ImDrawList.AddRect(draw, .{min_screen.x, min_screen.y}, .{max_screen.x, max_screen.y}, border_col, 4.0, .None, border_thickness);

        if hovered && drag_mode == .NONE && IsMouseClicked(.Right, false) {
            selected_index = cast(s32) it_index;
            context_item_index = cast(s32) it_index;
            inspiration_set_url_buffer(board, it.url);
            OpenPopup("InspirationItemMenu");
        }

        if hovered && drag_mode == .NONE && IsMouseClicked(.Left, false) {
            mode := inspiration_resize_handle_hit(board.*, it.*, mouse_v);
            was_selected := selected;
            selected_index = cast(s32) it_index;
            drag_item_index = cast(s32) it_index;
            drag_mouse_start_screen = mouse_v;
            drag_item_start_x = it.x;
            drag_item_start_y = it.y;
            drag_item_start_w = it.width;
            drag_item_start_h = it.height;
            drag_mode = ifx mode != .NONE then mode else .MOVE_ITEM;
            click_open_candidate_index = ifx it.url.count != 0 && was_selected && mode == .NONE then cast(s32) it_index else -1;
            dirty = true;
        }

        if selected {
            inspiration_draw_resize_handles(board.*, draw, it.*);
            inspiration_request_full_image(board, it);
        }
    }

    if drag_mode == .MOVE_ITEM || inspiration_drag_mode_is_resize(drag_mode) {
        if !IsMouseDown(.Left) {
            if click_open_candidate_index >= 0 && drag_item_index == click_open_candidate_index {
                delta_screen := mouse_v - drag_mouse_start_screen;
                if dot(delta_screen, delta_screen) <= 16.0 && drag_item_index < items.count {
                    item := items[drag_item_index];
                    if item.url.count != 0 {
                        inspiration_open_url(item.url);
                    }
                }
            }
            drag_mode = .NONE;
            drag_item_index = -1;
            click_open_candidate_index = -1;
        } else if drag_item_index >= 0 && drag_item_index < items.count {
            item := items.data + drag_item_index;
            delta_screen := mouse_v - drag_mouse_start_screen;
            delta_world := delta_screen / zoom;
            if drag_mode == .MOVE_ITEM {
                item.x = drag_item_start_x + delta_world.x;
                item.y = drag_item_start_y + delta_world.y;
            } else {
                inspiration_apply_resize_drag(board.*, item, mouse_v);
            }
            dirty = true;
        }
    }
}

inspiration_draw_context_popup :: (using board: *Inspiration_Board) {
    using ImGui;

    if !BeginPopup("InspirationItemMenu") return;
    defer EndPopup();

    if context_item_index < 0 || context_item_index >= items.count {
        TextDisabled("No image selected");
        return;
    }

    item := items.data + context_item_index;
    Text("Image");
    TextDisabled("%", String.path_filename(item.source_path));
    Separator();
    Text("URL");
    InputText("##InspirationURL", url_input_buffer.data, url_input_buffer.count);
    if Button("Attach URL") {
        inspiration_commit_url_from_buffer(item, url_input_buffer);
        dirty = true;
        CloseCurrentPopup();
    }
    SameLine();
    if Button("Clear URL") {
        if item.url.count != 0 free(item.url);
        item.url = "";
        url_input_buffer[0] = 0;
        dirty = true;
        CloseCurrentPopup();
    }
    if item.url.count != 0 {
        SameLine();
        if Button("Open URL") {
            inspiration_open_url(item.url);
            CloseCurrentPopup();
        }
    }
}

inspiration_draw_resize_handles :: (using board: Inspiration_Board, draw: *ImGui.ImDrawList, item: Inspiration_Item) {
    col := ImGui.GetColorU32(ImGui.ImVec4.{1.0, 0.78, 0.2, 1.0});
    for handle: inspiration_handle_points(board, item) {
        ImGui.ImDrawList.AddRectFilled(draw, .{handle.x - 4.0, handle.y - 4.0}, .{handle.x + 4.0, handle.y + 4.0}, col, 1.0);
    }
}

inspiration_handle_points :: (using board: Inspiration_Board, item: Inspiration_Item) -> [4]Vector2 {
    tl := inspiration_world_to_screen(board, .{item.x, item.y});
    tr := inspiration_world_to_screen(board, .{item.x + item.width, item.y});
    bl := inspiration_world_to_screen(board, .{item.x, item.y + item.height});
    br := inspiration_world_to_screen(board, .{item.x + item.width, item.y + item.height});
    return .[tl, tr, bl, br];
}

inspiration_resize_handle_hit :: (using board: Inspiration_Board, item: Inspiration_Item, mouse_screen: Vector2) -> Inspiration_Drag_Mode {
    points := inspiration_handle_points(board, item);
    if inspiration_point_near(mouse_screen, points[0], 8.0) return .RESIZE_TL;
    if inspiration_point_near(mouse_screen, points[1], 8.0) return .RESIZE_TR;
    if inspiration_point_near(mouse_screen, points[2], 8.0) return .RESIZE_BL;
    if inspiration_point_near(mouse_screen, points[3], 8.0) return .RESIZE_BR;
    return .NONE;
}

inspiration_apply_resize_drag :: (using board: Inspiration_Board, item: *Inspiration_Item, mouse_screen: Vector2) {
    aspect := ifx drag_item_start_h > 0.0 then drag_item_start_w / drag_item_start_h else 1.0;
    anchor_x := drag_item_start_x;
    anchor_y := drag_item_start_y;
    sign_x := 1.0;
    sign_y := 1.0;

    if drag_mode == {
    case .RESIZE_TL;
        anchor_x = drag_item_start_x + drag_item_start_w;
        anchor_y = drag_item_start_y + drag_item_start_h;
        sign_x = -1.0;
        sign_y = -1.0;
    case .RESIZE_TR;
        anchor_x = drag_item_start_x;
        anchor_y = drag_item_start_y + drag_item_start_h;
        sign_x = 1.0;
        sign_y = -1.0;
    case .RESIZE_BL;
        anchor_x = drag_item_start_x + drag_item_start_w;
        anchor_y = drag_item_start_y;
        sign_x = -1.0;
        sign_y = 1.0;
    case .RESIZE_BR;
        anchor_x = drag_item_start_x;
        anchor_y = drag_item_start_y;
        sign_x = 1.0;
        sign_y = 1.0;
    }

    mouse_world := inspiration_screen_to_world(board, mouse_screen);
    local_x := (mouse_world.x - anchor_x) * sign_x;
    local_y := (mouse_world.y - anchor_y) * sign_y;
    local_x = max(local_x, INSPIRATION_MIN_ITEM_SIZE);
    local_y = max(local_y, INSPIRATION_MIN_ITEM_SIZE);

    width := local_x;
    height := width / aspect;
    if height < local_y {
        height = local_y;
        width = height * aspect;
    }
    width = max(width, INSPIRATION_MIN_ITEM_SIZE);
    height = max(height, INSPIRATION_MIN_ITEM_SIZE);

    item.width = width;
    item.height = height;
    item.x = ifx sign_x > 0.0 then anchor_x else anchor_x - width;
    item.y = ifx sign_y > 0.0 then anchor_y else anchor_y - height;
}

inspiration_request_full_image :: (using board: *Inspiration_Board, item: *Inspiration_Item) {
    if item.full_view != 0 return;
    if item.full_requested return;
    queue(*full_load_worker, item.source_path);
    item.full_requested = true;
}

process_async_completions :: (using board: *Inspiration_Board) {
    completion: Inspiration_Load_Completion;
    while take_completed(*full_load_worker, *completion) {
        #if _VERBOSE log("Inspiration Async: completion '%', success=% size=%x%", completion.source_path, completion.success, completion.width, completion.height);
        defer {
            if completion.source_path.count != 0 free(completion.source_path);
            if completion.pixels != null stbi_image_free(completion.pixels);
        }

        if !completion.success continue;
        for *items {
            if it.source_path != completion.source_path continue;
            texture, view, ok := inspiration_make_texture_from_rgba8(completion.pixels, completion.width, completion.height);
            #if _VERBOSE log("Inspiration Async: upload '%', ok=% texture=% view=%", completion.source_path, ok, texture, view);
            if !ok continue;
            if it.full_view != 0 gpu_free_texture_view(it.full_view);
            it.full_texture = texture;
            it.full_view = view;
            if it.image_width <= 0 || it.image_height <= 0 {
                it.image_width = completion.width;
                it.image_height = completion.height;
            }
            gpu_commit_residency();
            break;
        }
    }
}

inspiration_make_texture_from_rgba8 :: (pixels: *u8, width: s32, height: s32) -> Gpu_Texture, Gpu_Texture_View, bool {
    if pixels == null || width <= 0 || height <= 0 return 0, 0, false;
    #if _VERBOSE log("Inspiration GPU: create texture %x%", width, height);
    result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    if result != .SUCCESS || texture == 0 return 0, 0, false;
    gpu_copy_to_texture(texture, pixels);
    view := gpu_texture_view(texture);
    #if _VERBOSE log("Inspiration GPU: create texture result=% texture=% view=%", result, texture, view);
    if view == 0 return texture, 0, false;
    return texture, view, true;
}

inspiration_load_item_thumbnail :: (using board: Inspiration_Board, item: *Inspiration_Item) {
    if item.thumb_view != 0 return;
    #if _VERBOSE log("Inspiration Thumb: load '%'", item.thumb_cache_path);
    width, height, channels: s32 = 0;
    pixels := stbi_load(temp_c_string(item.thumb_cache_path), *width, *height, *channels, 4);
    defer if pixels != null stbi_image_free(pixels);
    if pixels == null || width <= 0 || height <= 0 {
        log_error("Inspiration Thumb: load failed '%'", item.thumb_cache_path);
        return;
    }
    texture, view, ok := inspiration_make_texture_from_rgba8(pixels, width, height);
    if !ok return;
    item.thumb_texture = texture;
    item.thumb_view = view;
    item.image_width = width;
    item.image_height = height;
    gpu_commit_residency();
    #if _VERBOSE log("Inspiration Thumb: load complete '%', texture=% view=% size=%x%", item.thumb_cache_path, texture, view, width, height);
}

inspiration_generate_thumbnail_if_needed :: (item: *Inspiration_Item) {
    if File_Utilities.file_exists(item.thumb_cache_path) {
        #if _VERBOSE log("Inspiration Thumb: cache hit '%'", item.thumb_cache_path);
        return;
    }

    #if _VERBOSE log("Inspiration Thumb: generate '%'", item.source_path);

    width, height, channels: s32 = 0;
    pixels := stbi_load(temp_c_string(item.source_path), *width, *height, *channels, 4);
    defer if pixels != null stbi_image_free(pixels);
    if pixels == null || width <= 0 || height <= 0 {
        log_error("Inspiration: failed to load image '%'.", item.source_path);
        return;
    }

    thumb_w, thumb_h := inspiration_fit_thumb_dimensions(width, height, INSPIRATION_THUMB_MAX_DIM);
    thumb_bytes := cast(s64) thumb_w * cast(s64) thumb_h * 4;
    thumb := NewArray(thumb_bytes, u8);
    defer array_free(thumb);

    for y: 0..thumb_h-1 {
        src_y := clamp(cast(s32) floor((cast(float) y + 0.5) * cast(float) height / cast(float) thumb_h), 0, height - 1);
        for x: 0..thumb_w-1 {
            src_x := clamp(cast(s32) floor((cast(float) x + 0.5) * cast(float) width / cast(float) thumb_w), 0, width - 1);
            src_i := (cast(s64) src_y * cast(s64) width + src_x) * 4;
            dst_i := (cast(s64) y * cast(s64) thumb_w + x) * 4;
            thumb[dst_i + 0] = pixels[src_i + 0];
            thumb[dst_i + 1] = pixels[src_i + 1];
            thumb[dst_i + 2] = pixels[src_i + 2];
            thumb[dst_i + 3] = pixels[src_i + 3];
        }
    }

    ok := stbi_write_png(temp_c_string(item.thumb_cache_path), thumb_w, thumb_h, 4, thumb.data, thumb_w * 4) != 0;
    if !ok {
        log_error("Inspiration: failed to write thumbnail '%'.", item.thumb_cache_path);
    } else {
        #if _VERBOSE log("Inspiration Thumb: wrote '%', size=%x%", item.thumb_cache_path, thumb_w, thumb_h);
    }
}

inspiration_fit_thumb_dimensions :: (width: s32, height: s32, max_dim: s32) -> s32, s32 {
    if width <= max_dim && height <= max_dim return width, height;
    scale := min(cast(float) max_dim / cast(float) width, cast(float) max_dim / cast(float) height);
    thumb_w := max(cast(s32) 1, cast(s32) floor(cast(float) width * scale));
    thumb_h := max(cast(s32) 1, cast(s32) floor(cast(float) height * scale));
    return thumb_w, thumb_h;
}

inspiration_world_to_screen :: (using board: Inspiration_Board, world: Vector2) -> Vector2 {
    return last_canvas_min + view_offset + world * zoom;
}

inspiration_screen_to_world :: (using board: Inspiration_Board, screen: Vector2) -> Vector2 {
    return (screen - last_canvas_min - view_offset) / zoom;
}

inspiration_point_in_rect :: (p: Vector2, min: Vector2, max: Vector2) -> bool {
    return p.x >= min.x && p.y >= min.y && p.x <= max.x && p.y <= max.y;
}

inspiration_point_near :: (a: Vector2, b: Vector2, radius: float) -> bool {
    d := a - b;
    return dot(d, d) <= radius * radius;
}

inspiration_drag_mode_is_resize :: (mode: Inspiration_Drag_Mode) -> bool {
    return mode == .RESIZE_TL || mode == .RESIZE_TR || mode == .RESIZE_BL || mode == .RESIZE_BR;
}

inspiration_thumbnail_cache_path :: (source_path: string, modtime: Apollo_Time, size: s64) -> string {
    key_source := tprint("%|%|%:%", source_path, size, modtime.low, modtime.high);
    key_hash := Hash.fnv1a_hash(key_source.data, key_source.count);
    return copy_string(sprint("%/%_thumb.png", INSPIRATION_THUMB_DIR, key_hash));
}

inspiration_asset_copy_path :: (source_path: string, modtime: Apollo_Time, size: s64) -> string {
    filename := String.path_filename(source_path);
    stem := String.path_strip_extension(filename);
    ext, found_ext := String.path_extension(filename);
    key_source := tprint("%|%|%:%", source_path, size, modtime.low, modtime.high);
    key_hash := Hash.fnv1a_hash(key_source.data, key_source.count);
    if inspiration_asset_should_convert_to_jpeg(source_path) {
        return copy_string(sprint("%/%_%_.jpg", INSPIRATION_ASSET_DIR, stem, key_hash));
    }
    if found_ext {
        return copy_string(sprint("%/%_%_%.%", INSPIRATION_ASSET_DIR, stem, key_hash, ext));
    }
    return copy_string(sprint("%/%_%", INSPIRATION_ASSET_DIR, stem, key_hash));
}

inspiration_copy_asset_into_board :: (source_path: string, modtime: Apollo_Time, size: s64) -> string {
    File.make_directory_if_it_does_not_exist(INSPIRATION_ASSET_DIR, true);
    dest_path := inspiration_asset_copy_path(source_path, modtime, size);
    if source_path == dest_path return dest_path;
    if !File_Utilities.file_exists(dest_path) {
        ok := true;
        if inspiration_asset_should_convert_to_jpeg(source_path) {
            ok = inspiration_convert_image_to_jpeg(source_path, dest_path, 80);
        } else {
            ok = File_Utilities.copy_file(source_path, dest_path);
        }
        if !ok {
            log_error("Inspiration: failed to copy '%' to '%'.", source_path, dest_path);
            free(dest_path);
            return "";
        }
    }
    return dest_path;
}

inspiration_asset_should_convert_to_jpeg :: (path: string) -> bool {
    lower := String.to_lower_copy(path);
    defer free(lower);
    return String.ends_with(lower, ".png");
}

inspiration_convert_image_to_jpeg :: (source_path: string, dest_path: string, quality: s32) -> bool {
    width, height, channels: s32 = 0;
    pixels := stbi_load(temp_c_string(source_path), *width, *height, *channels, 3);
    defer if pixels != null stbi_image_free(pixels);
    if pixels == null || width <= 0 || height <= 0 {
        log_error("Inspiration: failed to load png for jpeg conversion '%'.", source_path);
        return false;
    }

    ok := stbi_write_jpg(temp_c_string(dest_path), width, height, 3, pixels, quality) != 0;
    if !ok {
        log_error("Inspiration: failed to write jpeg '%'.", dest_path);
        return false;
    }
    return true;
}

inspiration_path_looks_like_image :: (path: string) -> bool {
    lower := String.to_lower_copy(path);
    defer free(lower);
    if String.ends_with(lower, ".png") return true;
    if String.ends_with(lower, ".jpg") return true;
    if String.ends_with(lower, ".jpeg") return true;
    if String.ends_with(lower, ".webp") return true;
    if String.ends_with(lower, ".bmp") return true;
    if String.ends_with(lower, ".tga") return true;
    return false;
}

inspiration_escape_string :: (src: string, allocator := context.allocator) -> string {
    builder: String_Builder;
    builder.allocator = allocator;
    for src {
        if it == 92 {
            print_to_builder(*builder, "\\\\");
        } else if it == 34 {
            print_to_builder(*builder, "\\\"");
        } else if it == 10 {
            print_to_builder(*builder, "\\n");
        } else {
            append(*builder, it);
        }
    }
    return builder_to_string(*builder);
}

inspiration_unescape_string :: (src: string, allocator := context.allocator) -> string {
    builder: String_Builder;
    builder.allocator = allocator;
    i := 0;
    while i < src.count {
        c := src[i];
        if c == 92 && i + 1 < src.count {
            next := src[i + 1];
            if next == 110 {
                append(*builder, 10);
            } else {
                append(*builder, next);
            }
            i += 2;
            continue;
        }
        append(*builder, c);
        i += 1;
    }
    return builder_to_string(*builder);
}

inspiration_parse_view_line :: (line: string) -> Inspiration_View_Parse, bool {
    result: Inspiration_View_Parse;
    rest := String.slice(line, 5, line.count);
    tokens := String.split(String.trim(rest), #char " ");
    compact := inspiration_compact_tokens(tokens);
    if compact.count < 3 return result, false;
    x, ok_x := string_to_float(compact[0]);
    y, ok_y := string_to_float(compact[1]);
    z, ok_z := string_to_float(compact[2]);
    if !ok_x || !ok_y || !ok_z return result, false;
    result.xy = .{cast(float)x, cast(float)y};
    result.z = cast(float) z;
    return result, true;
}

inspiration_parse_item_line :: (line: string) -> (*Inspiration_Item, bool) {
    start_quote := String.find_index_from_left(line, #char "\"");
    if start_quote < 0 return null, false;
    end_quote := inspiration_find_closing_quote(line, start_quote + 1);
    if end_quote < 0 return null, false;

    escaped_path := String.slice(line, start_quote + 1, end_quote - (start_quote + 1));
    path := inspiration_unescape_string(escaped_path);
    rest := String.trim(String.slice(line, end_quote + 1, line.count));
    tokens := inspiration_compact_tokens(String.split(rest, #char " "));
    if tokens.count < 4 {
        free(path);
        return null, false;
    }

    x, ok_x := string_to_float(tokens[0]);
    y, ok_y := string_to_float(tokens[1]);
    w, ok_w := string_to_float(tokens[2]);
    h, ok_h := string_to_float(tokens[3]);
    if !ok_x || !ok_y || !ok_w || !ok_h {
        free(path);
        return null, false;
    }

    modtime, size, exists := File_Utilities.file_modtime_and_size(path);
    if !exists {
        free(path);
        return null, false;
    }

    url := "";
    url_quote_start := String.find_index_from_left(rest, #char "\"");
    if url_quote_start >= 0 {
        url_quote_end := inspiration_find_closing_quote(rest, url_quote_start + 1);
        if url_quote_end < 0 {
            free(path);
            return null, false;
        }
        escaped_url := String.slice(rest, url_quote_start + 1, url_quote_end - (url_quote_start + 1));
        url = inspiration_unescape_string(escaped_url);
    }

    item := New(Inspiration_Item);
    item.* = .{
        source_path = path,
        url = url,
        source_modtime = modtime,
        source_size = size,
        x = cast(float) x,
        y = cast(float) y,
        width = cast(float) w,
        height = cast(float) h,
    };
    item.thumb_cache_path = inspiration_thumbnail_cache_path(item.source_path, item.source_modtime, item.source_size);
    inspiration_generate_thumbnail_if_needed(item);
    return item, true;
}

inspiration_set_url_buffer :: (using board: *Inspiration_Board, url: string) {
    count := min(url.count, url_input_buffer.count - 1);
    for i: 0..count-1 url_input_buffer[i] = url[i];
    url_input_buffer[count] = 0;
}

inspiration_string_from_c_buffer :: (buffer: []u8) -> string {
    count := 0;
    while count < buffer.count && buffer[count] != 0 count += 1;
    return String.trim(string.{count, buffer.data});
}

inspiration_commit_url_from_buffer :: (item: *Inspiration_Item, buffer: []u8) {
    new_url := inspiration_string_from_c_buffer(buffer);
    if item.url.count != 0 free(item.url);
    item.url = ifx new_url.count != 0 then copy_string(new_url) else "";
}

inspiration_open_url :: (url: string) {
    if url.count == 0 return;
    result, _, _, timeout_reached := Process_Module.run_command("open", url, capture_and_return_output = false, timeout_ms = 1500);
    if timeout_reached || result.exit_code != 0 {
        log_error("Inspiration: failed to open url '%'.", url);
    }
}

inspiration_find_closing_quote :: (line: string, start: int) -> int {
    escaped := false;
    for i: start..line.count-1 {
        if escaped {
            escaped = false;
            continue;
        }
        if line[i] == 92 {
            escaped = true;
            continue;
        }
        if line[i] == 34 return i;
    }
    return -1;
}

inspiration_compact_tokens :: (tokens: []string) -> []string {
    out: [..]string;
    out.allocator = temp;
    for tokens {
        trimmed := String.trim(it);
        if trimmed.count == 0 continue;
        array_add(*out, trimmed);
    }
    return out;
}

inspiration_load_worker_proc :: (thread: *Thread.Thread) -> s64 {
    worker := cast(*Inspiration_Load_Worker) thread.data;
    log("Inspiration Async: worker thread started");
    while true {
        _ = Thread.wait_for(*worker.wake);

        request: Inspiration_Load_Request;
        Thread.lock(*worker.mutex);
        if worker.should_exit {
            Thread.unlock(*worker.mutex);
            break;
        }
        if worker.pending.count <= 0 {
            Thread.unlock(*worker.mutex);
            continue;
        }
        request = worker.pending[0];
        array_ordered_remove_by_index(*worker.pending, 0);
        Thread.unlock(*worker.mutex);
        log("Inspiration Async: begin load '%'", request.source_path);

        completion := Inspiration_Load_Completion.{source_path = request.source_path};
        width, height, channels: s32 = 0;
        pixels := stbi_load(temp_c_string(request.source_path), *width, *height, *channels, 4);
        if pixels != null && width > 0 && height > 0 {
            completion.success = true;
            completion.pixels = pixels;
            completion.width = width;
            completion.height = height;
        } else {
            completion.success = false;
            completion.pixels = null;
            completion.width = 0;
            completion.height = 0;
        }

        Thread.lock(*worker.mutex);
        array_add(*worker.completed, completion);
        Thread.unlock(*worker.mutex);
        #if _VERBOSE log("Inspiration Async: completed load '%', success=% size=%x%", completion.source_path, completion.success, completion.width, completion.height);
    }
    return 0;
}

Thread :: #import "Thread";
File :: #import "File";
using,only(file_exists, copy_file) File_Utilities :: #import "File_Utilities";
Hash :: #import "Hash";
String :: #import "String";
Process_Module :: #import "Process";
Input :: #import "Input";
ImGui :: #import "ImGui";
#import "stb_image";
#import "stb_image_write";

}

_VERBOSE :: false;
