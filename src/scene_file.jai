#scope_export

SCENE_FILE_VERSION :: 1;
SCENE_COMPILED_CACHE_VERSION :: 2;
SCENE_COMPILED_CACHE_MAGIC : u32 : 0x53434e45; // SCNE

Scene_Render_Kind :: enum {
    NONE;
    MESH;
    SKINNED_MESH;
}

Scene_Node_Source :: enum {
    ROOT_SCENE;
    PREFAB;
}

Scene_Behavior_Property :: struct {
    key: string;
    value: string;
}

Scene_Behavior_Desc :: struct {
    type_name: string;
    properties: [..]Scene_Behavior_Property;
}

Scene_Import_Settings :: struct {
    scale: Vector3 = .{1.0, 1.0, 1.0};
    rotation_deg: Vector3;
}

Scene_Asset_Desc :: struct {
    name: string;
    model_path: string;
    import_settings_path: string;
    import_settings: Scene_Import_Settings;
}

Scene_Procedural_Ground_Desc :: struct {
    enabled: bool;
    size_x: float = 48.0;
    size_z: float = 46.0;
    center_z: float = -12.0;
    render_grid_x: s32 = 112;
    render_grid_z: s32 = 112;
    physics_grid_x: s32 = 28;
    physics_grid_z: s32 = 28;
    base_color_path: string;
    normal_path: string;
    roughness_path: string;
    ao_path: string;
    ridge: float = 0.16;
    swell: float = 0.11;
    warp:  float = 0.06;
}

Scene_Scatter_Mode :: enum {
    GROUND;
    FLOATING;
}

Scene_Scatter_Desc :: struct {
    enabled: bool;
    assets: [..]string;
    count: s32;
    mode: Scene_Scatter_Mode = .GROUND;
    x_min: float = -10.0;
    x_max: float = 10.0;
    z_min: float = -10.0;
    z_max: float = 10.0;
    y_min: float = 0.0;
    y_max: float = 1.0;
    scale_min: float = 1.0;
    scale_max: float = 1.0;
    yaw_min_deg: float = 0.0;
    yaw_max_deg: float = 360.0;
    ground_y_offset: float = 0.0;
    seed: u64 = 1;
}

Scene_Node_Desc :: struct {
    name: string;
    parent_index: s32 = -1;
    first_child_index: s32 = -1;
    next_sibling_index: s32 = -1;

    position: Vector3;
    rotation_deg: Vector3;
    scale: Vector3 = .{1.0, 1.0, 1.0};

    render_kind: Scene_Render_Kind = .NONE;
    asset_name: string;
    clip_name: string;
    instance_scene_path: string;
    attach_node_name: string;

    ground: Scene_Procedural_Ground_Desc;
    scatter: Scene_Scatter_Desc;
    behavior: Scene_Behavior_Desc;
}

Scene_Document :: struct {
    source_path: string;
    scene_name: string;
    assets: [..]Scene_Asset_Desc;
    nodes: [..]Scene_Node_Desc;
}

Compiled_Scene_Behavior :: struct {
    type_name: string;
    autopilot: bool;
    move_speed: float = 4.15;
}

Compiled_Scene_Node :: struct {
    name: string;
    source_path: string;
    source_kind: Scene_Node_Source;
    parent_index: s32 = -1;
    first_child_index: s32 = -1;
    next_sibling_index: s32 = -1;
    _pad0: s32;

    local_position: Vector3;
    _pad1: float;
    local_rotation_deg: Vector3;
    _pad2: float;
    local_scale: Vector3;
    _pad3: float;

    world: Matrix4;

    render_kind: Scene_Render_Kind = .NONE;
    asset_index: s32 = -1;
    clip_name: string;
    attach_node_name: string;

    ground: Scene_Procedural_Ground_Desc;
    scatter: Scene_Scatter_Desc;
    behavior: Compiled_Scene_Behavior;
}

Compiled_Scene :: struct {
    root_scene_path: string;
    assets: [..]Scene_Asset_Desc;
    nodes: [..]Compiled_Scene_Node;
}

load_scene_document :: (path: string) -> Scene_Document {
    doc := Scene_Document.{source_path = copy_string(path)};
    doc.assets.allocator = context.allocator;
    doc.nodes.allocator = context.allocator;
    scene_parse_into(*doc, path);
    scene_load_import_settings(*doc);
    return doc;
}

deinit :: (doc: *Scene_Document) {
    for *doc.assets {
        free_string(it.name);
        free_string(it.model_path);
        free_string(it.import_settings_path);
    }
    for *doc.nodes {
        free_string(it.name);
        free_string(it.asset_name);
        free_string(it.clip_name);
        free_string(it.instance_scene_path);
        free_string(it.attach_node_name);
        free_string(it.ground.base_color_path);
        free_string(it.ground.normal_path);
        free_string(it.ground.roughness_path);
        free_string(it.ground.ao_path);
        for it.scatter.assets free_string(it);
        array_free(it.scatter.assets);
        free_string(it.behavior.type_name);
        for *it.behavior.properties {
            free_string(it.key);
            free_string(it.value);
        }
        array_free(it.behavior.properties);
    }
    array_free(doc.assets);
    array_free(doc.nodes);
    free_string(doc.source_path);
    free_string(doc.scene_name);
}

deinit :: (scene: *Compiled_Scene) {
    free_string(scene.root_scene_path);
    for *scene.assets {
        free_string(it.name);
        free_string(it.model_path);
        free_string(it.import_settings_path);
    }
    array_free(scene.assets);
    for *scene.nodes {
        free_string(it.name);
        free_string(it.source_path);
        free_string(it.clip_name);
        free_string(it.attach_node_name);
        free_string(it.ground.base_color_path);
        free_string(it.ground.normal_path);
        free_string(it.ground.roughness_path);
        free_string(it.ground.ao_path);
        for it.scatter.assets free_string(it);
        array_free(it.scatter.assets);
        free_string(it.behavior.type_name);
    }
    array_free(scene.nodes);
}

load_compiled_scene_cached :: (root_scene_path: string) -> Scene_Document, Compiled_Scene {
    doc := load_scene_document(root_scene_path);
    compiled: Compiled_Scene;
    compiled.assets.allocator = context.allocator;
    compiled.nodes.allocator = context.allocator;

    dependency_paths: [..]string;
    dependency_paths.allocator = temp;
    collect_scene_dependency_paths(*dependency_paths, doc);
    defer {
        for dependency_paths free_string(it);
        array_free(dependency_paths);
    }

    cache_path := compiled_scene_cache_path(root_scene_path, dependency_paths);
    cache_data, cache_ok := File.read_entire_file(cache_path);
    if cache_ok {
        loaded, fully_consumed := compiled_scene_deserialize(*compiled, cache_data);
        free(cache_data);
        if loaded && fully_consumed return doc, compiled;
        deinit(*compiled);
        compiled = .{};
        compiled.assets.allocator = context.allocator;
        compiled.nodes.allocator = context.allocator;
    }

    if compiled.root_scene_path.count == 0 compiled.root_scene_path = copy_string(root_scene_path);
    compiled_scene_build(*compiled, doc);

    cache_blob: [..]u8;
    cache_blob.allocator = context.allocator;
    serialize_ok := compiled_scene_serialize(*cache_blob, compiled);
    assert(serialize_ok, "Failed to serialize compiled scene cache.");
    if cache_blob.count > 0 _ = File.write_entire_file(cache_path, cache_blob.data, cache_blob.count);
    array_free(cache_blob);
    return doc, compiled;
}

recompile_scene_document :: (doc: Scene_Document) -> Compiled_Scene {
    compiled := Compiled_Scene.{root_scene_path = copy_string(doc.source_path)};
    compiled.assets.allocator = context.allocator;
    compiled.nodes.allocator = context.allocator;
    compiled_scene_build(*compiled, doc);
    return compiled;
}

save_scene_document :: (doc: Scene_Document) -> bool {
    builder: String_Builder;
    append(*builder, tprint("[%]\n", SCENE_FILE_VERSION));
    if doc.scene_name.count > 0 append(*builder, tprint("scene \"%\" {\n", doc.scene_name));
    else                        append(*builder, "scene \"Scene\" {\n");

    for doc.assets {
        append(*builder, tprint("  asset \"%\" {\n", it.name));
        append(*builder, tprint("    model \"%\"\n", it.model_path));
        append(*builder, "  }\n");
    }
    if doc.assets.count > 0 append(*builder, "\n");

    for node_index: 0..doc.nodes.count-1 {
        node := doc.nodes[node_index];
        if node.parent_index >= 0 continue;
        scene_write_node(*builder, doc, cast(s32) node_index, 1);
    }

    append(*builder, "}\n");
    return File.write_entire_file(doc.source_path, builder_to_string(*builder));
}

scan_scene_palette_models :: (directory: string = "./models") -> [..]string {
    results: [..]string;
    results.allocator = context.allocator;
    for File_Utilities.file_list(directory, recursive=true, follow_directory_symlinks=false,, allocator=temp) {
        if !is_supported_model_path(it) continue;
        array_add(*results, copy_string(it));
    }
    return results;
}

place_palette_model :: (doc: *Scene_Document, model_path: string, position: Vector3) -> s32 {
    asset_name := ensure_scene_asset_for_model(doc, model_path);
    node_name := make_unique_node_name(doc.*, String.path_strip_extension(String.path_filename(model_path)));
    node := scene_add_node(doc, node_name, -1);
    node.position = position;
    node.scale = .{1.0, 1.0, 1.0};
    if looks_like_skinned_asset(model_path) {
        node.render_kind = .SKINNED_MESH;
        node.clip_name = copy_string("Run");
    } else {
        node.render_kind = .MESH;
    }
    node.asset_name = copy_string(asset_name);
    return cast(s32) doc.nodes.count - 1;
}

#scope_file

Scene_Parse_Block :: enum {
    ROOT;
    SCENE;
    ASSET;
    NODE;
    BEHAVIOR;
    GROUND;
    SCATTER;
}

Scene_Parse_Frame :: struct {
    kind: Scene_Parse_Block;
    node_index: s32 = -1;
    asset_index: s32 = -1;
}

scene_parse_into :: (doc: *Scene_Document, path: string) {
    handler: Text_File_Handler.Text_File_Handler;
    defer Text_File_Handler.deinit(*handler);
    Text_File_Handler.start_file(*handler, String.path_filename(path), path, false);
    assert(!handler.failed, "Failed to open scene file %", path);
    assert(handler.version == SCENE_FILE_VERSION, "Unsupported scene version in %", path);

    stack: [..]Scene_Parse_Frame;
    stack.allocator = temp;
    array_add(*stack, .{kind = .ROOT});

    found_scene_block := false;

    while true {
        line, found := Text_File_Handler.consume_next_line(*handler);
        if !found break;
        tokens := tokenize_scene_line(line);
        defer free_scene_tokens(tokens);
        if tokens.count == 0 continue;

        if tokens.count == 1 && tokens[0] == "}" {
            assert(stack.count > 1, "Unexpected scene file block close in %", path);
            stack.count -= 1;
            continue;
        }

        top := stack[stack.count - 1];
        if top.kind == .ROOT {
            assert(tokens.count >= 3 && tokens[0] == "scene" && tokens[tokens.count - 1] == "{", "Expected scene block in %", path);
            doc.scene_name = copy_string(tokens[1]);
            array_add(*stack, .{kind = .SCENE});
            found_scene_block = true;
            continue;
        }

        if top.kind == {
        case .SCENE;    parse_scene_scope_line(doc, *stack, tokens);
        case .ASSET;    parse_asset_scope_line(doc, *stack, tokens);
        case .NODE;     parse_node_scope_line(doc, *stack, tokens);
        case .BEHAVIOR; parse_behavior_scope_line(doc, *stack, tokens);
        case .GROUND;   parse_ground_scope_line(doc, *stack, tokens);
        case .SCATTER;  parse_scatter_scope_line(doc, *stack, tokens);
        case;           assert(false, "Unhandled scene parse scope.");
        }
    }

    assert(found_scene_block, "Scene file % is missing a scene block.", path);
    assert(stack.count == 1, "Scene file % has unclosed blocks.", path);
}

parse_scene_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    assert(tokens.count >= 3 && tokens[tokens.count - 1] == "{", "Expected block open in scene scope.");
    if tokens[0] == "asset" {
        asset := array_add(*doc.assets);
        asset.name = copy_string(tokens[1]);
        array_add(stack, .{kind = .ASSET, asset_index = cast(s32) doc.assets.count - 1});
        return;
    }
    if tokens[0] == "node" {
        scene_add_node(doc, tokens[1], -1);
        array_add(stack, .{kind = .NODE, node_index = cast(s32) doc.nodes.count - 1});
        return;
    }
    assert(false, "Unsupported scene declaration '%'.", tokens[0]);
}

parse_asset_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    frame := stack.*[stack.count - 1];
    asset := *doc.assets[frame.asset_index];
    if tokens[0] == "model" {
        assert(tokens.count == 2, "Expected model path.");
        asset.model_path = copy_string(tokens[1]);
        return;
    }
    assert(false, "Unsupported asset property '%'.", tokens[0]);
}

parse_node_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    frame := stack.*[stack.count - 1];
    node := *doc.nodes[frame.node_index];

    if tokens[0] == "node" {
        assert(tokens.count >= 3 && tokens[tokens.count - 1] == "{", "Expected child node block.");
        child := scene_add_node(doc, tokens[1], frame.node_index);
        _ = child;
        array_add(stack, .{kind = .NODE, node_index = cast(s32) doc.nodes.count - 1});
        return;
    }

    if tokens[0] == "behavior" {
        assert(tokens.count >= 3 && tokens[tokens.count - 1] == "{", "Expected behavior block.");
        node.behavior.type_name = copy_string(tokens[1]);
        node.behavior.properties.allocator = context.allocator;
        array_add(stack, .{kind = .BEHAVIOR, node_index = frame.node_index});
        return;
    }

    if tokens[0] == "procedural_ground" {
        assert(tokens.count >= 2 && tokens[tokens.count - 1] == "{", "Expected procedural_ground block.");
        node.ground.enabled = true;
        array_add(stack, .{kind = .GROUND, node_index = frame.node_index});
        return;
    }

    if tokens[0] == "scatter_render" {
        assert(tokens.count >= 2 && tokens[tokens.count - 1] == "{", "Expected scatter_render block.");
        node.scatter.enabled = true;
        node.scatter.assets.allocator = context.allocator;
        array_add(stack, .{kind = .SCATTER, node_index = frame.node_index});
        return;
    }

    if tokens[0] == {
    case "position";
        assert(tokens.count == 4, "Expected position x y z.");
        node.position = parse_vec3(tokens, 1);
        return;
    case "rotation_deg";
        assert(tokens.count == 4, "Expected rotation_deg x y z.");
        node.rotation_deg = parse_vec3(tokens, 1);
        return;
    case "scale";
        assert(tokens.count == 4, "Expected scale x y z.");
        node.scale = parse_vec3(tokens, 1);
        return;
    case "mesh_render";
        assert(tokens.count == 2, "Expected mesh asset name.");
        node.render_kind = .MESH;
        node.asset_name = copy_string(tokens[1]);
        return;
    case "skinned_mesh_render";
        assert(tokens.count == 2, "Expected skinned mesh asset name.");
        node.render_kind = .SKINNED_MESH;
        node.asset_name = copy_string(tokens[1]);
        return;
    case "clip";
        assert(tokens.count == 2, "Expected clip name.");
        node.clip_name = copy_string(tokens[1]);
        return;
    case "instance_scene";
        assert(tokens.count == 2, "Expected instance scene path.");
        node.instance_scene_path = copy_string(tokens[1]);
        return;
    case "attach_node";
        assert(tokens.count == 2, "Expected attach node name.");
        node.attach_node_name = copy_string(tokens[1]);
        return;
    }

    assert(false, "Unsupported node property '%'.", tokens[0]);
}

parse_behavior_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    frame := stack.*[stack.count - 1];
    behavior := *doc.nodes[frame.node_index].behavior;
    value_builder: String_Builder;
    for token_index: 1..tokens.count-1 {
        if token_index > 1 append(*value_builder, " ");
        append(*value_builder, tokens[token_index]);
    }
    array_add(*behavior.properties, .{
        key = copy_string(tokens[0]),
        value = copy_string(builder_to_string(*value_builder,, temp)),
    });
}

parse_ground_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    frame := stack.*[stack.count - 1];
    ground := *doc.nodes[frame.node_index].ground;
    if tokens[0] == {
    case "size";
        assert(tokens.count == 3, "Expected size x z.");
        ground.size_x = parse_real(tokens[1]);
        ground.size_z = parse_real(tokens[2]);
    case "center_z";
        assert(tokens.count == 2, "Expected center_z.");
        ground.center_z = parse_real(tokens[1]);
    case "render_grid";
        assert(tokens.count == 3, "Expected render_grid x z.");
        ground.render_grid_x = parse_int32(tokens[1]);
        ground.render_grid_z = parse_int32(tokens[2]);
    case "physics_grid";
        assert(tokens.count == 3, "Expected physics_grid x z.");
        ground.physics_grid_x = parse_int32(tokens[1]);
        ground.physics_grid_z = parse_int32(tokens[2]);
    case "base_color";
        ground.base_color_path = copy_string(tokens[1]);
    case "normal";
        ground.normal_path = copy_string(tokens[1]);
    case "roughness";
        ground.roughness_path = copy_string(tokens[1]);
    case "ao";
        ground.ao_path = copy_string(tokens[1]);
    case "ridge";
        ground.ridge = parse_real(tokens[1]);
    case "swell";
        ground.swell = parse_real(tokens[1]);
    case "warp";
        ground.warp = parse_real(tokens[1]);
    case;
        assert(false, "Unsupported procedural_ground property '%'.", tokens[0]);
    }
}

parse_scatter_scope_line :: (doc: *Scene_Document, stack: *[..]Scene_Parse_Frame, tokens: []string) {
    frame := stack.*[stack.count - 1];
    scatter := *doc.nodes[frame.node_index].scatter;
    if tokens[0] == {
    case "assets";
        assert(tokens.count >= 2, "Expected at least one scatter asset.");
        for token_index: 1..tokens.count-1 array_add(*scatter.assets, copy_string(tokens[token_index]));
        return;
    case "count";
        scatter.count = parse_int32(tokens[1]);
        return;
    case "mode";
        if tokens[1] == "ground" scatter.mode = .GROUND;
        else if tokens[1] == "floating" scatter.mode = .FLOATING;
        else assert(false, "Unknown scatter mode '%'.", tokens[1]);
        return;
    case "x_range";
        scatter.x_min = parse_real(tokens[1]);
        scatter.x_max = parse_real(tokens[2]);
        return;
    case "z_range";
        scatter.z_min = parse_real(tokens[1]);
        scatter.z_max = parse_real(tokens[2]);
        return;
    case "y_range";
        scatter.y_min = parse_real(tokens[1]);
        scatter.y_max = parse_real(tokens[2]);
        return;
    case "scale_range";
        scatter.scale_min = parse_real(tokens[1]);
        scatter.scale_max = parse_real(tokens[2]);
        return;
    case "yaw_range_deg";
        scatter.yaw_min_deg = parse_real(tokens[1]);
        scatter.yaw_max_deg = parse_real(tokens[2]);
        return;
    case "ground_y_offset";
        scatter.ground_y_offset = parse_real(tokens[1]);
        return;
    case "seed";
        scatter.seed = cast(u64) parse_int64(tokens[1]);
        return;
    }
    assert(false, "Unsupported scatter_render property '%'.", tokens[0]);
}

scene_add_node :: (doc: *Scene_Document, name: string, parent_index: s32) -> *Scene_Node_Desc {
    node := array_add(*doc.nodes);
    node.name = copy_string(name);
    node.parent_index = parent_index;
    if parent_index >= 0 {
        parent := *doc.nodes[parent_index];
        if parent.first_child_index < 0 {
            parent.first_child_index = cast(s32) doc.nodes.count - 1;
        } else {
            last_child := parent.first_child_index;
            while doc.nodes[last_child].next_sibling_index >= 0 last_child = doc.nodes[last_child].next_sibling_index;
            doc.nodes[last_child].next_sibling_index = cast(s32) doc.nodes.count - 1;
        }
    }
    return node;
}

tokenize_scene_line :: (line_in: string) -> [..]string {
    line := strip_scene_comment(line_in);
    tokens: [..]string;
    tokens.allocator = context.allocator;
    i: s64 = 0;
    while i < line.count {
        c := line[i];
        if c == #char " " || c == #char "\t" || c == #char "\r" || c == #char "\n" {
            i += 1;
            continue;
        }
        if c == #char "{" || c == #char "}" {
            array_add(*tokens, copy_string(string.{1, line.data + i}));
            i += 1;
            continue;
        }
        if c == #char "\"" {
            start := i + 1;
            i += 1;
            while i < line.count && line[i] != #char "\"" i += 1;
            assert(i < line.count, "Unterminated string in scene line '%'.", line_in);
            array_add(*tokens, copy_string(string.{i - start, line.data + start}));
            i += 1;
            continue;
        }
        start := i;
        while i < line.count {
            c = line[i];
            if c == #char " " || c == #char "\t" || c == #char "\r" || c == #char "\n" break;
            if c == #char "{" || c == #char "}" break;
            i += 1;
        }
        array_add(*tokens, copy_string(string.{i - start, line.data + start}));
    }
    return tokens;
}

strip_scene_comment :: (line: string) -> string {
    in_quote := false;
    i: s64 = 0;
    while i < line.count - 1 {
        c := line[i];
        if c == #char "\"" in_quote = !in_quote;
        if !in_quote && c == #char "/" && line[i + 1] == #char "/" return scene_trim_ascii_whitespace(string.{i, line.data});
        i += 1;
    }
    return scene_trim_ascii_whitespace(line);
}

free_scene_tokens :: (tokens: [..]string) {
    for tokens free_string(it);
    array_free(tokens);
}

string_less :: (a: string, b: string) -> bool {
    return a < b;
}

parse_vec3 :: (tokens: []string, start_index: s64) -> Vector3 {
    return .{
        parse_real(tokens[start_index + 0]),
        parse_real(tokens[start_index + 1]),
        parse_real(tokens[start_index + 2]),
    };
}

parse_real :: (s: string) -> float {
    cursor := s;
    value, success := String.parse_float(*cursor);
    assert(success, "Failed to parse float from '%'.", s);
    return value;
}

parse_int32 :: (s: string) -> s32 {
    cursor := s;
    value, success := String.parse_int(*cursor, s64);
    assert(success, "Failed to parse integer from '%'.", s);
    return cast(s32) value;
}

parse_int64 :: (s: string) -> s64 {
    cursor := s;
    value, success := String.parse_int(*cursor, s64);
    assert(success, "Failed to parse integer from '%'.", s);
    return value;
}

scene_trim_ascii_whitespace :: (in: string) -> string {
    start: s64 = 0;
    while start < in.count {
        c := in[start];
        if c != #char " " && c != #char "\t" && c != #char "\r" && c != #char "\n" break;
        start += 1;
    }
    end := in.count;
    while end > start {
        c := in[end - 1];
        if c != #char " " && c != #char "\t" && c != #char "\r" && c != #char "\n" break;
        end -= 1;
    }
    return .{end - start, in.data + start};
}

free_string :: (s: string) {
    if s.data != null && s.count > 0 free(s.data);
}

copy_string :: (s: string) -> string {
    if s.count == 0 return "";
    out := alloc(s.count);
    memcpy(out, s.data, s.count);
    return .{s.count, out};
}

scene_load_import_settings :: (doc: *Scene_Document) {
    for *doc.assets {
        if it.import_settings_path.count > 0 {
            free_string(it.import_settings_path);
            it.import_settings_path = "";
        }
        it.import_settings = .{};
        import_path := tprint("%.import", String.path_strip_extension(it.model_path));
        modtime, size, exists := File_Utilities.file_modtime_and_size(import_path);
        _ = modtime; _ = size;
        if !exists continue;
        it.import_settings_path = copy_string(import_path);
        parse_import_settings_file(*it.import_settings, import_path);
    }
}

parse_import_settings_file :: (settings: *Scene_Import_Settings, path: string) {
    handler: Text_File_Handler.Text_File_Handler;
    defer Text_File_Handler.deinit(*handler);
    Text_File_Handler.start_file(*handler, String.path_filename(path), path, false);
    if handler.failed return;
    assert(handler.version == SCENE_FILE_VERSION, "Unsupported import settings version in %", path);
    while true {
        line, found := Text_File_Handler.consume_next_line(*handler);
        if !found break;
        tokens := tokenize_scene_line(line);
        defer free_scene_tokens(tokens);
        if tokens.count == 0 continue;
        if tokens[0] == {
        case "scale";
            settings.scale = parse_vec3(tokens, 1);
        case "rotation_deg";
            settings.rotation_deg = parse_vec3(tokens, 1);
        case;
            assert(false, "Unsupported import setting '%'.", tokens[0]);
        }
    }
}

collect_scene_dependency_paths :: (paths: *[..]string, doc: Scene_Document) {
    scene_collect_dependencies_recursive(paths, doc.source_path, temp);
}

scene_collect_dependencies_recursive :: (paths: *[..]string, scene_path: string, allocator: Allocator) {
    _ = allocator;
    if string_list_contains(paths.*, scene_path) return;
    array_add(paths, copy_string(scene_path));

    doc := load_scene_document(scene_path);
    defer deinit(*doc);
    for doc.assets {
        if it.import_settings_path.count > 0 && !string_list_contains(paths.*, it.import_settings_path) {
            array_add(paths, copy_string(it.import_settings_path));
        }
    }
    for doc.nodes {
        if it.instance_scene_path.count > 0 {
            prefab_path := resolve_scene_path_relative(scene_path, it.instance_scene_path);
            scene_collect_dependencies_recursive(paths, prefab_path, allocator);
            free_string(prefab_path);
        }
    }
}

compiled_scene_cache_path :: (root_scene_path: string, dependency_paths: []string) -> string {
    builder: String_Builder;
    append(*builder, tprint("v%|root=%|", SCENE_COMPILED_CACHE_VERSION, root_scene_path));
    for dependency_paths {
        modtime, size, _ := File_Utilities.file_modtime_and_size(it);
        append(*builder, tprint("%|%|%|", it, size, modtime));
    }
    key_source := builder_to_string(*builder,, temp);
    hash := Hash.fnv1a_hash(key_source.data, key_source.count);
    cache_dir := tprint("%/.build/scene_cache", find_workspace_root_for_cache());
    File.make_directory_if_it_does_not_exist(cache_dir, true);
    return tprint("%/compiled_scene_%.bin", cache_dir, hash);
}

compiled_scene_build :: (compiled: *Compiled_Scene, root_doc: Scene_Document) {
    compile_scene_document_recursive(compiled, root_doc, root_doc.source_path, -1, .ROOT_SCENE);
    compiled_scene_compute_worlds(compiled);
}

compile_scene_document_recursive :: (compiled: *Compiled_Scene, doc: Scene_Document, source_path: string, parent_index: s32, source_kind: Scene_Node_Source) {
    asset_base := compiled.assets.count;
    for doc.assets {
        compiled_scene_add_asset(compiled, it);
    }

    for node_index: 0..doc.nodes.count-1 {
        if doc.nodes[node_index].parent_index >= 0 continue;
        compiled_scene_append_node_recursive(compiled, doc, cast(s32) node_index, asset_base, parent_index, source_path, source_kind);
    }
}

compiled_scene_append_node_recursive :: (
    compiled: *Compiled_Scene,
    doc: Scene_Document,
    node_index: s32,
    asset_base: s64,
    compiled_parent: s32,
    source_path: string,
    source_kind: Scene_Node_Source,
) {
    src := doc.nodes[node_index];
    dst := array_add(*compiled.nodes);
    dst.name = copy_string(src.name);
    dst.source_path = copy_string(source_path);
    dst.source_kind = source_kind;
    dst.parent_index = compiled_parent;
    dst.local_position = src.position;
    dst.local_rotation_deg = src.rotation_deg;
    dst.local_scale = src.scale;
    dst.render_kind = src.render_kind;
    dst.clip_name = copy_string(src.clip_name);
    dst.attach_node_name = copy_string(src.attach_node_name);
    dst.ground = compiled_copy_ground(src.ground);
    dst.scatter = compiled_copy_scatter(src.scatter);
    dst.behavior = compiled_behavior_from_desc(src.behavior);
    if src.asset_name.count > 0 dst.asset_index = compiled_scene_find_asset_index_by_name(compiled.*, src.asset_name, asset_base);
    current_compiled_index := cast(s32) compiled.nodes.count - 1;

    if compiled_parent >= 0 {
        parent := *compiled.nodes[compiled_parent];
        if parent.first_child_index < 0 parent.first_child_index = current_compiled_index;
        else {
            sibling := parent.first_child_index;
            while compiled.nodes[sibling].next_sibling_index >= 0 sibling = compiled.nodes[sibling].next_sibling_index;
            compiled.nodes[sibling].next_sibling_index = current_compiled_index;
        }
    }

    if src.instance_scene_path.count > 0 {
        prefab_path := resolve_scene_path_relative(source_path, src.instance_scene_path);
        prefab_doc := load_scene_document(prefab_path);
        defer deinit(*prefab_doc);
        defer free_string(prefab_path);
        prefab_asset_base := compiled.assets.count;
        for prefab_doc.assets compiled_scene_add_asset(compiled, it);
        for prefab_node_index: 0..prefab_doc.nodes.count-1 {
            if prefab_doc.nodes[prefab_node_index].parent_index >= 0 continue;
            compiled_scene_append_node_recursive(compiled, prefab_doc, cast(s32) prefab_node_index, prefab_asset_base, current_compiled_index, prefab_path, .PREFAB);
        }
    }

    child_index := src.first_child_index;
    while child_index >= 0 {
        compiled_scene_append_node_recursive(compiled, doc, child_index, asset_base, current_compiled_index, source_path, source_kind);
        child_index = doc.nodes[child_index].next_sibling_index;
    }
}

compiled_scene_add_asset :: (compiled: *Compiled_Scene, asset: Scene_Asset_Desc) -> s32 {
    for compiled.assets {
        if it.model_path == asset.model_path return cast(s32) it_index;
    }
    dst := array_add(*compiled.assets);
    dst.name = copy_string(asset.name);
    dst.model_path = copy_string(asset.model_path);
    dst.import_settings_path = copy_string(asset.import_settings_path);
    dst.import_settings = asset.import_settings;
    return cast(s32) compiled.assets.count - 1;
}

compiled_scene_find_asset_index_by_name :: (compiled: Compiled_Scene, asset_name: string, asset_base: s64) -> s32 {
    for index: asset_base .. compiled.assets.count-1 {
        if compiled.assets[index].name == asset_name return cast(s32) index;
    }
    for compiled.assets {
        if it.name == asset_name return cast(s32) it_index;
    }
    assert(false, "Scene asset '%' was not found during compile.", asset_name);
    return -1;
}

compiled_copy_ground :: (src: Scene_Procedural_Ground_Desc) -> Scene_Procedural_Ground_Desc {
    dst := src;
    dst.base_color_path = copy_string(src.base_color_path);
    dst.normal_path = copy_string(src.normal_path);
    dst.roughness_path = copy_string(src.roughness_path);
    dst.ao_path = copy_string(src.ao_path);
    return dst;
}

compiled_copy_scatter :: (src: Scene_Scatter_Desc) -> Scene_Scatter_Desc {
    dst := src;
    dst.assets.data = null;
    dst.assets.count = 0;
    dst.assets.allocated = 0;
    dst.assets.allocator = context.allocator;
    for src.assets array_add(*dst.assets, copy_string(it));
    return dst;
}

compiled_behavior_from_desc :: (src: Scene_Behavior_Desc) -> Compiled_Scene_Behavior {
    out := Compiled_Scene_Behavior.{type_name = copy_string(src.type_name)};
    if src.type_name == "Player_Controller" {
        for src.properties {
            if it.key == "autopilot" out.autopilot = (it.value == "true");
            if it.key == "move_speed" out.move_speed = parse_real(it.value);
        }
    }
    return out;
}

compiled_scene_compute_worlds :: (scene: *Compiled_Scene) {
    for node_index: 0..scene.nodes.count-1 {
        node := *scene.nodes[node_index];
        local :=
            make_translation_matrix4(node.local_position)
            * rotation_matrix(Matrix4, quat_from_euler_deg(node.local_rotation_deg))
            * make_scale_matrix4(node.local_scale);
        node.world = local;
        if node.parent_index >= 0 node.world = scene.nodes[node.parent_index].world * local;
    }
}

quat_from_euler_deg :: (deg: Vector3) -> Quaternion {
    radians := deg * (PI / 180.0);
    hx := radians.x * 0.5;
    hy := radians.y * 0.5;
    hz := radians.z * 0.5;
    cx := cos(hx); sx := sin(hx);
    cy := cos(hy); sy := sin(hy);
    cz := cos(hz); sz := sin(hz);
    qx := Quaternion.{x = sx, y = 0.0, z = 0.0, w = cx};
    qy := Quaternion.{x = 0.0, y = sy, z = 0.0, w = cy};
    qz := Quaternion.{x = 0.0, y = 0.0, z = sz, w = cz};
    q := qz * qy * qx;
    normalize_or_identity(*q);
    return q;
}

ensure_scene_asset_for_model :: (doc: *Scene_Document, model_path: string) -> string {
    for doc.assets {
        if it.model_path == model_path return it.name;
    }
    base_name := String.path_strip_extension(String.path_filename(model_path));
    unique_name := make_unique_asset_name(doc.*, base_name);
    asset := array_add(*doc.assets);
    asset.name = copy_string(unique_name);
    asset.model_path = copy_string(model_path);
    scene_load_import_settings(doc);
    return asset.name;
}

make_unique_asset_name :: (doc: Scene_Document, base_name: string) -> string {
    if !scene_asset_name_exists(doc, base_name) return copy_string(base_name);
    suffix := 1;
    while true {
        candidate := tprint("%_%", base_name, suffix);
        if !scene_asset_name_exists(doc, candidate) return copy_string(candidate);
        suffix += 1;
    }
    return copy_string(base_name);
}

make_unique_node_name :: (doc: Scene_Document, base_name: string) -> string {
    if !scene_node_name_exists(doc, base_name) return copy_string(base_name);
    suffix := 1;
    while true {
        candidate := tprint("%_%", base_name, suffix);
        if !scene_node_name_exists(doc, candidate) return copy_string(candidate);
        suffix += 1;
    }
    return copy_string(base_name);
}

scene_asset_name_exists :: (doc: Scene_Document, name: string) -> bool {
    for doc.assets if it.name == name return true;
    return false;
}

scene_node_name_exists :: (doc: Scene_Document, name: string) -> bool {
    for doc.nodes if it.name == name return true;
    return false;
}

looks_like_skinned_asset :: (model_path: string) -> bool {
    stem := String.path_strip_extension(String.path_filename(model_path));
    return stem == "Lizard run";
}

is_supported_model_path :: (path: string) -> bool {
    lower := String.to_lower_copy(path);
    defer free(lower);
    return String.ends_with(lower, ".obj") || String.ends_with(lower, ".fbx") || String.ends_with(lower, ".glb") || String.ends_with(lower, ".gltf");
}

resolve_scene_path_relative :: (base_scene_path: string, referenced_path: string) -> string {
    if String.starts_with(referenced_path, "/") return copy_string(referenced_path);
    base_dir := String.path_strip_filename(base_scene_path);
    return copy_string(tprint("%/%", base_dir, referenced_path));
}

string_list_contains :: (values: []string, needle: string) -> bool {
    for values if it == needle return true;
    return false;
}

scene_write_node :: (builder: *String_Builder, doc: Scene_Document, node_index: s32, indent: s64) {
    node := doc.nodes[node_index];
    prefix := scene_indent(indent);
    append(builder, tprint("%node \"%\" {\n", prefix, node.name));
    append(builder, tprint("%  position % % %\n", prefix, node.position.x, node.position.y, node.position.z));
    append(builder, tprint("%  rotation_deg % % %\n", prefix, node.rotation_deg.x, node.rotation_deg.y, node.rotation_deg.z));
    append(builder, tprint("%  scale % % %\n", prefix, node.scale.x, node.scale.y, node.scale.z));
    if node.render_kind == .MESH append(builder, tprint("%  mesh_render \"%\"\n", prefix, node.asset_name));
    if node.render_kind == .SKINNED_MESH append(builder, tprint("%  skinned_mesh_render \"%\"\n", prefix, node.asset_name));
    if node.clip_name.count > 0 append(builder, tprint("%  clip \"%\"\n", prefix, node.clip_name));
    if node.instance_scene_path.count > 0 append(builder, tprint("%  instance_scene \"%\"\n", prefix, node.instance_scene_path));
    if node.attach_node_name.count > 0 append(builder, tprint("%  attach_node \"%\"\n", prefix, node.attach_node_name));

    if node.behavior.type_name.count > 0 {
        append(builder, tprint("%  behavior \"%\" {\n", prefix, node.behavior.type_name));
        for node.behavior.properties append(builder, tprint("%    % %\n", prefix, it.key, it.value));
        append(builder, tprint("%  }\n", prefix));
    }

    if node.ground.enabled {
        append(builder, tprint("%  procedural_ground {\n", prefix));
        append(builder, tprint("%    size % %\n", prefix, node.ground.size_x, node.ground.size_z));
        append(builder, tprint("%    center_z %\n", prefix, node.ground.center_z));
        append(builder, tprint("%    render_grid % %\n", prefix, node.ground.render_grid_x, node.ground.render_grid_z));
        append(builder, tprint("%    physics_grid % %\n", prefix, node.ground.physics_grid_x, node.ground.physics_grid_z));
        append(builder, tprint("%    base_color \"%\"\n", prefix, node.ground.base_color_path));
        append(builder, tprint("%    normal \"%\"\n", prefix, node.ground.normal_path));
        append(builder, tprint("%    roughness \"%\"\n", prefix, node.ground.roughness_path));
        append(builder, tprint("%    ao \"%\"\n", prefix, node.ground.ao_path));
        append(builder, tprint("%  }\n", prefix));
    }

    if node.scatter.enabled {
        append(builder, tprint("%  scatter_render {\n", prefix));
        append(builder, tprint("%    assets", prefix));
        for node.scatter.assets append(builder, tprint(" \"%\"", it));
        append(builder, "\n");
        append(builder, tprint("%    count %\n", prefix, node.scatter.count));
        append(builder, tprint("%    mode %\n", prefix, ifx node.scatter.mode == .GROUND then "ground" else "floating"));
        append(builder, tprint("%    x_range % %\n", prefix, node.scatter.x_min, node.scatter.x_max));
        append(builder, tprint("%    z_range % %\n", prefix, node.scatter.z_min, node.scatter.z_max));
        append(builder, tprint("%    y_range % %\n", prefix, node.scatter.y_min, node.scatter.y_max));
        append(builder, tprint("%    scale_range % %\n", prefix, node.scatter.scale_min, node.scatter.scale_max));
        append(builder, tprint("%    yaw_range_deg % %\n", prefix, node.scatter.yaw_min_deg, node.scatter.yaw_max_deg));
        append(builder, tprint("%    ground_y_offset %\n", prefix, node.scatter.ground_y_offset));
        append(builder, tprint("%    seed %\n", prefix, node.scatter.seed));
        append(builder, tprint("%  }\n", prefix));
    }

    child_index := node.first_child_index;
    while child_index >= 0 {
        scene_write_node(builder, doc, child_index, indent + 1);
        child_index = doc.nodes[child_index].next_sibling_index;
    }
    append(builder, tprint("%}\n", prefix));
}

scene_indent :: (count: s64) -> string {
    builder: String_Builder;
    for 0..count-1 append(*builder, "  ");
    return builder_to_string(*builder,, temp);
}

compiled_scene_serialize :: (builder: *[..]u8, scene: Compiled_Scene) -> bool {
    scene_cache_put(builder, SCENE_COMPILED_CACHE_MAGIC);
    scene_cache_put(builder, SCENE_COMPILED_CACHE_VERSION);
    scene_cache_put_string(builder, scene.root_scene_path);

    scene_cache_put(builder, cast(u32) scene.assets.count);
    for scene.assets {
        scene_cache_put_string(builder, it.name);
        scene_cache_put_string(builder, it.model_path);
        scene_cache_put_string(builder, it.import_settings_path);
        scene_cache_put(builder, it.import_settings.scale);
        scene_cache_put(builder, it.import_settings.rotation_deg);
    }

    scene_cache_put(builder, cast(u32) scene.nodes.count);
    for scene.nodes {
        scene_cache_put_string(builder, it.name);
        scene_cache_put_string(builder, it.source_path);
        scene_cache_put(builder, cast(u32) it.source_kind);
        scene_cache_put(builder, it.parent_index);
        scene_cache_put(builder, it.first_child_index);
        scene_cache_put(builder, it.next_sibling_index);
        scene_cache_put(builder, it._pad0);
        scene_cache_put(builder, it.local_position);
        scene_cache_put(builder, it._pad1);
        scene_cache_put(builder, it.local_rotation_deg);
        scene_cache_put(builder, it._pad2);
        scene_cache_put(builder, it.local_scale);
        scene_cache_put(builder, it._pad3);
        scene_cache_put(builder, it.world);
        scene_cache_put(builder, cast(u32) it.render_kind);
        scene_cache_put(builder, it.asset_index);
        scene_cache_put_string(builder, it.clip_name);
        scene_cache_put_string(builder, it.attach_node_name);
        scene_cache_put(builder, it.ground.enabled);
        scene_cache_put(builder, it.ground.size_x);
        scene_cache_put(builder, it.ground.size_z);
        scene_cache_put(builder, it.ground.center_z);
        scene_cache_put(builder, it.ground.render_grid_x);
        scene_cache_put(builder, it.ground.render_grid_z);
        scene_cache_put(builder, it.ground.physics_grid_x);
        scene_cache_put(builder, it.ground.physics_grid_z);
        scene_cache_put_string(builder, it.ground.base_color_path);
        scene_cache_put_string(builder, it.ground.normal_path);
        scene_cache_put_string(builder, it.ground.roughness_path);
        scene_cache_put_string(builder, it.ground.ao_path);
        scene_cache_put(builder, it.ground.ridge);
        scene_cache_put(builder, it.ground.swell);
        scene_cache_put(builder, it.ground.warp);
        scene_cache_put(builder, it.scatter.enabled);
        scene_cache_put(builder, cast(u32) it.scatter.mode);
        scene_cache_put(builder, it.scatter.count);
        scene_cache_put(builder, it.scatter.x_min);
        scene_cache_put(builder, it.scatter.x_max);
        scene_cache_put(builder, it.scatter.z_min);
        scene_cache_put(builder, it.scatter.z_max);
        scene_cache_put(builder, it.scatter.y_min);
        scene_cache_put(builder, it.scatter.y_max);
        scene_cache_put(builder, it.scatter.scale_min);
        scene_cache_put(builder, it.scatter.scale_max);
        scene_cache_put(builder, it.scatter.yaw_min_deg);
        scene_cache_put(builder, it.scatter.yaw_max_deg);
        scene_cache_put(builder, it.scatter.ground_y_offset);
        scene_cache_put(builder, it.scatter.seed);
        scene_cache_put(builder, cast(u32) it.scatter.assets.count);
        for it.scatter.assets scene_cache_put_string(builder, it);
        scene_cache_put_string(builder, it.behavior.type_name);
        scene_cache_put(builder, it.behavior.autopilot);
        scene_cache_put(builder, it.behavior.move_speed);
    }
    return true;
}

compiled_scene_deserialize :: (scene: *Compiled_Scene, source_in: string) -> bool, bool {
    source := source_in;
    magic: u32;
    version: u32;
    if !scene_cache_get(*source, *magic) return false, false;
    if !scene_cache_get(*source, *version) return false, false;
    if magic != SCENE_COMPILED_CACHE_MAGIC || version != SCENE_COMPILED_CACHE_VERSION return false, false;
    if !scene_cache_get_string(*source, *scene.root_scene_path) return false, false;

    asset_count: u32;
    if !scene_cache_get(*source, *asset_count) return false, false;
    for 0..cast(s64) asset_count-1 {
        asset := array_add(*scene.assets);
        if !scene_cache_get_string(*source, *asset.name) return false, false;
        if !scene_cache_get_string(*source, *asset.model_path) return false, false;
        if !scene_cache_get_string(*source, *asset.import_settings_path) return false, false;
        if !scene_cache_get(*source, *asset.import_settings.scale) return false, false;
        if !scene_cache_get(*source, *asset.import_settings.rotation_deg) return false, false;
    }

    node_count: u32;
    if !scene_cache_get(*source, *node_count) return false, false;
    for 0..cast(s64) node_count-1 {
        node := array_add(*scene.nodes);
        if !scene_cache_get_string(*source, *node.name) return false, false;
        if !scene_cache_get_string(*source, *node.source_path) return false, false;
        source_kind_u32: u32;
        render_kind_u32: u32;
        scatter_mode_u32: u32;
        if !scene_cache_get(*source, *source_kind_u32) return false, false;
        node.source_kind = cast(Scene_Node_Source) source_kind_u32;
        if !scene_cache_get(*source, *node.parent_index) return false, false;
        if !scene_cache_get(*source, *node.first_child_index) return false, false;
        if !scene_cache_get(*source, *node.next_sibling_index) return false, false;
        if !scene_cache_get(*source, *node._pad0) return false, false;
        if !scene_cache_get(*source, *node.local_position) return false, false;
        if !scene_cache_get(*source, *node._pad1) return false, false;
        if !scene_cache_get(*source, *node.local_rotation_deg) return false, false;
        if !scene_cache_get(*source, *node._pad2) return false, false;
        if !scene_cache_get(*source, *node.local_scale) return false, false;
        if !scene_cache_get(*source, *node._pad3) return false, false;
        if !scene_cache_get(*source, *node.world) return false, false;
        if !scene_cache_get(*source, *render_kind_u32) return false, false;
        node.render_kind = cast(Scene_Render_Kind) render_kind_u32;
        if !scene_cache_get(*source, *node.asset_index) return false, false;
        if !scene_cache_get_string(*source, *node.clip_name) return false, false;
        if !scene_cache_get_string(*source, *node.attach_node_name) return false, false;
        if !scene_cache_get(*source, *node.ground.enabled) return false, false;
        if !scene_cache_get(*source, *node.ground.size_x) return false, false;
        if !scene_cache_get(*source, *node.ground.size_z) return false, false;
        if !scene_cache_get(*source, *node.ground.center_z) return false, false;
        if !scene_cache_get(*source, *node.ground.render_grid_x) return false, false;
        if !scene_cache_get(*source, *node.ground.render_grid_z) return false, false;
        if !scene_cache_get(*source, *node.ground.physics_grid_x) return false, false;
        if !scene_cache_get(*source, *node.ground.physics_grid_z) return false, false;
        if !scene_cache_get_string(*source, *node.ground.base_color_path) return false, false;
        if !scene_cache_get_string(*source, *node.ground.normal_path) return false, false;
        if !scene_cache_get_string(*source, *node.ground.roughness_path) return false, false;
        if !scene_cache_get_string(*source, *node.ground.ao_path) return false, false;
        if !scene_cache_get(*source, *node.scatter.enabled) return false, false;
        if !scene_cache_get(*source, *scatter_mode_u32) return false, false;
        node.scatter.mode = cast(Scene_Scatter_Mode) scatter_mode_u32;
        if !scene_cache_get(*source, *node.scatter.count) return false, false;
        if !scene_cache_get(*source, *node.scatter.x_min) return false, false;
        if !scene_cache_get(*source, *node.scatter.x_max) return false, false;
        if !scene_cache_get(*source, *node.scatter.z_min) return false, false;
        if !scene_cache_get(*source, *node.scatter.z_max) return false, false;
        if !scene_cache_get(*source, *node.scatter.y_min) return false, false;
        if !scene_cache_get(*source, *node.scatter.y_max) return false, false;
        if !scene_cache_get(*source, *node.scatter.scale_min) return false, false;
        if !scene_cache_get(*source, *node.scatter.scale_max) return false, false;
        if !scene_cache_get(*source, *node.scatter.yaw_min_deg) return false, false;
        if !scene_cache_get(*source, *node.scatter.yaw_max_deg) return false, false;
        if !scene_cache_get(*source, *node.scatter.ground_y_offset) return false, false;
        if !scene_cache_get(*source, *node.scatter.seed) return false, false;
        asset_name_count: u32;
        if !scene_cache_get(*source, *asset_name_count) return false, false;
        node.scatter.assets.allocator = context.allocator;
        for 0..cast(s64) asset_name_count-1 {
            asset_name: string;
            if !scene_cache_get_string(*source, *asset_name) return false, false;
            array_add(*node.scatter.assets, asset_name);
        }
        if !scene_cache_get_string(*source, *node.behavior.type_name) return false, false;
        if !scene_cache_get(*source, *node.behavior.autopilot) return false, false;
        if !scene_cache_get(*source, *node.behavior.move_speed) return false, false;
    }
    return true, source.count == 0;
}

scene_cache_put :: (builder: *[..]u8, x: $T) {
    value := x;
    offset := builder.count;
    array_resize(builder, offset + size_of(T));
    memcpy(builder.data + offset, *value, size_of(T));
}

scene_cache_put_string :: (builder: *[..]u8, value: string) {
    count := cast(u32) value.count;
    scene_cache_put(builder, count);
    if count > 0 {
        offset := builder.count;
        array_resize(builder, offset + count);
        memcpy(builder.data + offset, value.data, count);
    }
}

scene_cache_get :: (source: *string, out: *$T) -> bool {
    if source.count < size_of(T) return false;
    memcpy(out, source.data, size_of(T));
    source.data += size_of(T);
    source.count -= size_of(T);
    return true;
}

scene_cache_get_string :: (source: *string, out: *string) -> bool {
    count: u32;
    if !scene_cache_get(source, *count) return false;
    if count == 0 {
        out.* = "";
        return true;
    }
    if source.count < count return false;
    out.data = alloc(count);
    out.count = count;
    memcpy(out.data, source.data, count);
    source.data += count;
    source.count -= count;
    return true;
}

find_workspace_root_for_cache :: () -> string {
    probe := get_working_directory();
    while true {
        _, _, exists := File_Utilities.file_modtime_and_size(tprint("%/build.jai", probe));
        if exists return probe;
        parent := String.path_strip_filename(probe);
        if parent == probe || parent.count == 0 return get_working_directory();
        probe = parent;
    }
    return get_working_directory();
}

#import "Basic";
#import "Math";
File :: #import "File";
String :: #import "String";
Hash :: #import "Hash";
File_Utilities :: #import "File_Utilities";
Text_File_Handler :: #import "Text_File_Handler";
