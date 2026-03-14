Scene_Vertex :: struct {
    position: Vector4;
    normal: Vector4;
    bone_indices: Vector4;
    bone_weights: Vector4;
    uv: Vector2;
    _pad0: Vector2;
}

Scene_Material :: struct {
    base_color_factor: Vector4;
    base_color_texture_index: u32;
    _pad0: u32;
    _pad1: u32;
    _pad2: u32;
}

Scene_Mesh :: struct {
    first_index: u32;
    index_count: u32;
    material_index: u32;
    skin_bone_start: u32;
    skin_bone_count: u32;
    _pad0: u32;
}

Scene_Node :: struct {
    parent_index: s32;
    first_child_index: s32;
    next_sibling_index: s32;
    _pad0: s32;
    first_mesh_ref: u32;
    mesh_ref_count: u32;
    _pad1: u32;
    _pad2: u32;
    local: Matrix4;
    world: Matrix4;
}

Scene_Model :: struct {
    name: string;
    root_node_index: s32;
    _pad0: s32;
    node_start: u32;
    node_count: u32;
    mesh_start: u32;
    mesh_count: u32;
    anim_clip_start: u32;
    anim_clip_count: u32;
}

Scene_Bounds :: struct {
    min: Vector3;
    max: Vector3;
}

Scene_Node_Transform :: struct {
    translation: Vector3;
    rotation: Quaternion;
    scale: Vector3;
}

Scene_Mesh_Skin_Bone :: struct {
    node_index: s32;
    _pad0: s32;
    inverse_bind: Matrix4;
}

Scene_Anim_Position_Key :: struct {
    time: float;
    value: Vector3;
}

Scene_Anim_Rotation_Key :: struct {
    time: float;
    value: Quaternion;
}

Scene_Anim_Scale_Key :: struct {
    time: float;
    value: Vector3;
}

Scene_Anim_Channel :: struct {
    node_index: s32;
    _pad0: s32;
    position_key_start: u32;
    position_key_count: u32;
    rotation_key_start: u32;
    rotation_key_count: u32;
    scale_key_start: u32;
    scale_key_count: u32;
}

Scene_Anim_Clip :: struct {
    name: string;
    duration: float;
    ticks_per_second: float;
    channel_start: u32;
    channel_count: u32;
}

Imported_Texture :: struct {
    key: string;
    width: u32;
    height: u32;
    pixels: [..]u8;
}

Imported_Scene :: struct {
    vertices: [..]Scene_Vertex;
    indices: [..]u32;
    materials: [..]Scene_Material;
    textures: [..]Imported_Texture;
    meshes: [..]Scene_Mesh;
    nodes: [..]Scene_Node;
    node_bind_transforms: [..]Scene_Node_Transform;
    node_mesh_refs: [..]u32;
    mesh_skin_bones: [..]Scene_Mesh_Skin_Bone;
    anim_position_keys: [..]Scene_Anim_Position_Key;
    anim_rotation_keys: [..]Scene_Anim_Rotation_Key;
    anim_scale_keys: [..]Scene_Anim_Scale_Key;
    anim_channels: [..]Scene_Anim_Channel;
    anim_clips: [..]Scene_Anim_Clip;
    models: [..]Scene_Model;
}

Scene_Geo :: struct {
    arena: Gpu_Arena;
    vertices: Gpu_View(Scene_Vertex);
    indices: Gpu_View(u32);
    materials: Gpu_View(Scene_Material);

    textures: [..]Gpu_Texture;
    texture_views: [..]Gpu_Texture_View;
    texture_keys: [..]string;
    sampler: Gpu_Sampler;

    meshes: [..]Scene_Mesh;
    nodes: [..]Scene_Node;
    node_bind_transforms: [..]Scene_Node_Transform;
    node_mesh_refs: [..]u32;
    mesh_skin_bones: [..]Scene_Mesh_Skin_Bone;
    anim_position_keys: [..]Scene_Anim_Position_Key;
    anim_rotation_keys: [..]Scene_Anim_Rotation_Key;
    anim_scale_keys: [..]Scene_Anim_Scale_Key;
    anim_channels: [..]Scene_Anim_Channel;
    anim_clips: [..]Scene_Anim_Clip;
    models: [..]Scene_Model;
}

scene_geo_init :: (geo: *Scene_Geo, model_paths: []string) {
    imported: Imported_Scene;
    imported_scene_load_cached(*imported, model_paths);
    defer imported_scene_deinit(*imported);
    scene_geo_init_from_imported(geo, *imported);
}

scene_geo_init_from_imported :: (geo: *Scene_Geo, imported: *Imported_Scene) {
    geo.textures.allocator = context.allocator;
    geo.texture_views.allocator = context.allocator;
    geo.texture_keys.allocator = context.allocator;
    geo.meshes.allocator = context.allocator;
    geo.nodes.allocator = context.allocator;
    geo.node_bind_transforms.allocator = context.allocator;
    geo.node_mesh_refs.allocator = context.allocator;
    geo.mesh_skin_bones.allocator = context.allocator;
    geo.anim_position_keys.allocator = context.allocator;
    geo.anim_rotation_keys.allocator = context.allocator;
    geo.anim_scale_keys.allocator = context.allocator;
    geo.anim_channels.allocator = context.allocator;
    geo.anim_clips.allocator = context.allocator;
    geo.models.allocator = context.allocator;

    for it: imported.textures {
        texture, view := create_texture_from_rgba8(it.pixels, it.width, it.height);
        array_add(*geo.textures, texture);
        array_add(*geo.texture_views, view);
        array_add(*geo.texture_keys, copy_string(it.key));
    }

    geo.sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .REPEAT,
        address_mode_v = .REPEAT,
        address_mode_w = .REPEAT,
    });
    assert(geo.sampler != 0, "Scene_Geo sampler creation failed.");

    total_bytes :=
        imported.vertices.count * size_of(Scene_Vertex) +
        imported.indices.count * size_of(u32) +
        imported.materials.count * size_of(Scene_Material) +
        1024;

    geo.arena = gpu_make_arena(total_bytes, label = "scene geo arena");
    assert(geo.arena.cpu != null, "Scene_Geo arena creation failed.");

    geo.vertices = gpu_alloc_view(*geo.arena, Scene_Vertex, imported.vertices.count);
    geo.indices = gpu_alloc_view(*geo.arena, u32, imported.indices.count);
    geo.materials = gpu_alloc_view(*geo.arena, Scene_Material, imported.materials.count);

    if imported.vertices.count > 0 {
        memcpy(geo.vertices.cpu.data, imported.vertices.data, imported.vertices.count * size_of(Scene_Vertex));
    }
    if imported.indices.count > 0 {
        memcpy(geo.indices.cpu.data, imported.indices.data, imported.indices.count * size_of(u32));
    }
    if imported.materials.count > 0 {
        for imported.materials {
            material := it;
            assert(material.base_color_texture_index < geo.texture_views.count, "Imported texture index % out of range %.", material.base_color_texture_index, geo.texture_views.count);
            material.base_color_texture_index = cast(u32) geo.texture_views[material.base_color_texture_index] - 1;
            geo.materials.cpu[it_index] = material;
        }
    }

    array_copy(*geo.meshes, imported.meshes);
    array_copy(*geo.nodes, imported.nodes);
    array_copy(*geo.node_bind_transforms, imported.node_bind_transforms);
    array_copy(*geo.node_mesh_refs, imported.node_mesh_refs);
    array_copy(*geo.mesh_skin_bones, imported.mesh_skin_bones);
    array_copy(*geo.anim_position_keys, imported.anim_position_keys);
    array_copy(*geo.anim_rotation_keys, imported.anim_rotation_keys);
    array_copy(*geo.anim_scale_keys, imported.anim_scale_keys);
    array_copy(*geo.anim_channels, imported.anim_channels);
    for it: imported.anim_clips {
        array_add(*geo.anim_clips, .{
            name = copy_string(it.name),
            duration = it.duration,
            ticks_per_second = it.ticks_per_second,
            channel_start = it.channel_start,
            channel_count = it.channel_count,
        });
    }
    for it: imported.models {
        array_add(*geo.models, .{
            name = copy_string(it.name),
            root_node_index = it.root_node_index,
            node_start = it.node_start,
            node_count = it.node_count,
            mesh_start = it.mesh_start,
            mesh_count = it.mesh_count,
            anim_clip_start = it.anim_clip_start,
            anim_clip_count = it.anim_clip_count,
        });
    }

    gpu_commit_residency();
}

scene_geo_deinit :: (geo: *Scene_Geo) {
    for geo.texture_keys if it.count != 0 free(it);
    array_free(geo.texture_keys);
    for geo.models if it.name.count != 0 free(it.name);
    for geo.anim_clips if it.name.count != 0 free(it.name);
    array_free(geo.anim_clips);
    array_free(geo.anim_channels);
    array_free(geo.anim_scale_keys);
    array_free(geo.anim_rotation_keys);
    array_free(geo.anim_position_keys);
    array_free(geo.mesh_skin_bones);
    array_free(geo.models);
    array_free(geo.node_bind_transforms);
    array_free(geo.nodes);
    array_free(geo.node_mesh_refs);
    array_free(geo.meshes);

    for geo.textures {
        if it != 0 gpu_free(it);
    }
    array_free(geo.textures);
    array_free(geo.texture_views);

    if geo.sampler != 0 gpu_free(geo.sampler);
    if geo.arena.cpu != null gpu_free_arena(geo.arena);
    geo.* = .{};
}

scene_geo_model_index_by_name :: (geo: *Scene_Geo, name: string) -> s32 {
    for geo.models if it.name == name return cast(s32) it_index;
    return -1;
}

scene_geo_model_clip_index_by_name :: (geo: *Scene_Geo, model_index: s32, name: string) -> s32 {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    model := geo.models[model_index];
    if model.anim_clip_count == 0 return -1;
    for clip_index: model.anim_clip_start .. model.anim_clip_start + model.anim_clip_count - 1 {
        if geo.anim_clips[clip_index].name == name return cast(s32) clip_index;
    }
    return -1;
}

scene_geo_model_bounds :: (geo: *Scene_Geo, model_index: s32) -> Scene_Bounds {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    model := geo.models[model_index];

    bounds: Scene_Bounds;
    bounds.min = .{1000000.0, 1000000.0, 1000000.0};
    bounds.max = .{-1000000.0, -1000000.0, -1000000.0};

    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;

        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            mesh := geo.meshes[mesh_index];

            for index_offset: 0..mesh.index_count-1 {
                vertex_index := geo.indices.cpu[mesh.first_index + index_offset];
                vertex := geo.vertices.cpu[vertex_index];
                world_pos4 := node.world * vertex.position;
                world_pos := Vector3.{world_pos4.x, world_pos4.y, world_pos4.z};

                bounds.min.x = min(bounds.min.x, world_pos.x);
                bounds.min.y = min(bounds.min.y, world_pos.y);
                bounds.min.z = min(bounds.min.z, world_pos.z);
                bounds.max.x = max(bounds.max.x, world_pos.x);
                bounds.max.y = max(bounds.max.y, world_pos.y);
                bounds.max.z = max(bounds.max.z, world_pos.z);
            }
        }
    }

    return bounds;
}

scene_geo_append_model_instances :: (
    batches: *[..]Draw_Batch,
    instances: *[..]Scene_Instance_CPU,
    geo: *Scene_Geo,
    model_index: s32,
    root_transforms: []Matrix4,
    tint: Vector4 = .{1.0, 1.0, 1.0, 1.0},
) {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    model := geo.models[model_index];

    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        node := geo.nodes[node_index];
        if node.mesh_ref_count == 0 continue;
        for mesh_ref_offset: 0..node.mesh_ref_count-1 {
            mesh_index := geo.node_mesh_refs[node.first_mesh_ref + mesh_ref_offset];
            batch := array_add(batches);
            batch.mesh_index = mesh_index;
            batch.first_instance = cast(u32) instances.count;
            batch.instance_count = cast(u32) root_transforms.count;

            for root_transforms {
                world := it * node.world;
                array_add(instances, .{
                    world = world,
                    tint = tint,
                });
            }
        }
    }
}

imported_scene_deinit :: (scene: *Imported_Scene) {
    array_free(scene.vertices);
    array_free(scene.indices);
    array_free(scene.materials);
    for it: scene.textures {
        if it.key.count != 0 free(it.key);
        array_free(it.pixels);
    }
    array_free(scene.textures);
    array_free(scene.meshes);
    array_free(scene.nodes);
    array_free(scene.node_bind_transforms);
    array_free(scene.node_mesh_refs);
    array_free(scene.mesh_skin_bones);
    array_free(scene.anim_position_keys);
    array_free(scene.anim_rotation_keys);
    array_free(scene.anim_scale_keys);
    array_free(scene.anim_channels);
    for it: scene.anim_clips if it.name.count != 0 free(it.name);
    array_free(scene.anim_clips);
    for it: scene.models if it.name.count != 0 free(it.name);
    array_free(scene.models);
    scene.* = .{};
}

imported_scene_load_cached :: (scene: *Imported_Scene, model_paths: []string) {
    cache_path := imported_scene_cache_path(model_paths);
    data, ok := File.read_entire_file(cache_path);
    if ok {
        loaded, parse_ok := imported_scene_deserialize(scene, data);
        free(data);
        if parse_ok && loaded return;
        imported_scene_deinit(scene);
    }

    imported_scene_create_default_white_texture(scene);
    for model_paths load_model_into_imported_scene(scene, it);

    cache_blob: [..]u8;
    cache_blob.allocator = context.allocator;
    serialize_ok := imported_scene_serialize(*cache_blob, scene.*);
    assert(serialize_ok, "Failed to serialize imported scene cache.");
    if cache_blob.count > 0 {
        _ = File.write_entire_file(cache_path, cache_blob.data, cache_blob.count);
    }
    array_free(cache_blob);
}

#scope_file

Hash_Table :: #import "Hash_Table";
using,only(Table, table_find, table_reset, table_set) _ :: Hash_Table;
IMPORTED_SCENE_CACHE_VERSION : u32 : 2;
IMPORTED_SCENE_CACHE_MAGIC : u32 : 0x53474d44; // SGMD

imported_scene_cache_path :: (model_paths: []string) -> string {
    builder: String_Builder;
    append(*builder, tprint("v%|", IMPORTED_SCENE_CACHE_VERSION));
    for model_paths {
        modtime, size, _ := file_modtime_and_size(it);
        append(*builder, tprint("%|%|%|", it, size, modtime));
    }
    key_source := builder_to_string(*builder,, temp);
    hash := fnv1a_hash(key_source.data, key_source.count);
    cache_dir := tprint("%/.build/model_cache", find_workspace_root_for_cache());
    File.make_directory_if_it_does_not_exist(cache_dir, true);
    return tprint("%/scene_geo_%.bin", cache_dir, hash);
}

imported_scene_serialize :: (builder: *[..]u8, scene: Imported_Scene) -> bool {
    cache_put(builder, IMPORTED_SCENE_CACHE_MAGIC);
    cache_put(builder, IMPORTED_SCENE_CACHE_VERSION);
    cache_put_array(builder, scene.vertices);
    cache_put_array(builder, scene.indices);
    cache_put_array(builder, scene.materials);
    cache_put_array(builder, scene.meshes);
    cache_put_array(builder, scene.nodes);
    cache_put_array(builder, scene.node_bind_transforms);
    cache_put_array(builder, scene.node_mesh_refs);
    cache_put_array(builder, scene.mesh_skin_bones);
    cache_put_array(builder, scene.anim_position_keys);
    cache_put_array(builder, scene.anim_rotation_keys);
    cache_put_array(builder, scene.anim_scale_keys);
    cache_put_array(builder, scene.anim_channels);

    cache_put(builder, cast(u32) scene.textures.count);
    for scene.textures {
        cache_put_string(builder, it.key);
        cache_put(builder, it.width);
        cache_put(builder, it.height);
        cache_put_bytes(builder, it.pixels);
    }

    cache_put(builder, cast(u32) scene.models.count);
    for scene.models {
        cache_put_string(builder, it.name);
        cache_put(builder, it.root_node_index);
        cache_put(builder, it._pad0);
        cache_put(builder, it.node_start);
        cache_put(builder, it.node_count);
        cache_put(builder, it.mesh_start);
        cache_put(builder, it.mesh_count);
        cache_put(builder, it.anim_clip_start);
        cache_put(builder, it.anim_clip_count);
    }

    cache_put(builder, cast(u32) scene.anim_clips.count);
    for scene.anim_clips {
        cache_put_string(builder, it.name);
        cache_put(builder, it.duration);
        cache_put(builder, it.ticks_per_second);
        cache_put(builder, it.channel_start);
        cache_put(builder, it.channel_count);
    }
    return true;
}

imported_scene_deserialize :: (scene: *Imported_Scene, source_in: string) -> bool, bool {
    source := source_in;
    magic: u32;
    version: u32;
    if !cache_get(*source, *magic) return false, false;
    if !cache_get(*source, *version) return false, false;
    if magic != IMPORTED_SCENE_CACHE_MAGIC || version != IMPORTED_SCENE_CACHE_VERSION return false, false;

    if !cache_get_array(*source, *scene.vertices) return false, false;
    if !cache_get_array(*source, *scene.indices) return false, false;
    if !cache_get_array(*source, *scene.materials) return false, false;
    if !cache_get_array(*source, *scene.meshes) return false, false;
    if !cache_get_array(*source, *scene.nodes) return false, false;
    if !cache_get_array(*source, *scene.node_bind_transforms) return false, false;
    if !cache_get_array(*source, *scene.node_mesh_refs) return false, false;
    if !cache_get_array(*source, *scene.mesh_skin_bones) return false, false;
    if !cache_get_array(*source, *scene.anim_position_keys) return false, false;
    if !cache_get_array(*source, *scene.anim_rotation_keys) return false, false;
    if !cache_get_array(*source, *scene.anim_scale_keys) return false, false;
    if !cache_get_array(*source, *scene.anim_channels) return false, false;

    texture_count: u32;
    if !cache_get(*source, *texture_count) return false, false;
    for 0..cast(s64) texture_count-1 {
        texture: Imported_Texture;
        texture.pixels.allocator = context.allocator;
        if !cache_get_string(*source, *texture.key) return false, false;
        if !cache_get(*source, *texture.width) return false, false;
        if !cache_get(*source, *texture.height) return false, false;
        if !cache_get_bytes(*source, *texture.pixels) return false, false;
        array_add(*scene.textures, texture);
    }

    model_count: u32;
    if !cache_get(*source, *model_count) return false, false;
    for 0..cast(s64) model_count-1 {
        model: Scene_Model;
        if !cache_get_string(*source, *model.name) return false, false;
        if !cache_get(*source, *model.root_node_index) return false, false;
        if !cache_get(*source, *model._pad0) return false, false;
        if !cache_get(*source, *model.node_start) return false, false;
        if !cache_get(*source, *model.node_count) return false, false;
        if !cache_get(*source, *model.mesh_start) return false, false;
        if !cache_get(*source, *model.mesh_count) return false, false;
        if !cache_get(*source, *model.anim_clip_start) return false, false;
        if !cache_get(*source, *model.anim_clip_count) return false, false;
        array_add(*scene.models, model);
    }

    clip_count: u32;
    if !cache_get(*source, *clip_count) return false, false;
    for 0..cast(s64) clip_count-1 {
        clip: Scene_Anim_Clip;
        if !cache_get_string(*source, *clip.name) return false, false;
        if !cache_get(*source, *clip.duration) return false, false;
        if !cache_get(*source, *clip.ticks_per_second) return false, false;
        if !cache_get(*source, *clip.channel_start) return false, false;
        if !cache_get(*source, *clip.channel_count) return false, false;
        array_add(*scene.anim_clips, clip);
    }

    return true, source.count == 0;
}

cache_put :: (builder: *[..]u8, x: $T) {
    value := x;
    offset := builder.count;
    array_resize(builder, offset + size_of(T));
    memcpy(builder.data + offset, *value, size_of(T));
}

cache_put_array :: (builder: *[..]u8, values: []$T) {
    count := cast(u32) values.count;
    cache_put(builder, count);
    if count > 0 {
        offset := builder.count;
        byte_count := cast(s64) count * size_of(T);
        array_resize(builder, offset + byte_count);
        memcpy(builder.data + offset, values.data, byte_count);
    }
}

cache_put_bytes :: (builder: *[..]u8, values: []u8) {
    count := cast(u32) values.count;
    cache_put(builder, count);
    if count > 0 {
        offset := builder.count;
        array_resize(builder, offset + count);
        memcpy(builder.data + offset, values.data, count);
    }
}

cache_put_string :: (builder: *[..]u8, value: string) {
    count := cast(u32) value.count;
    cache_put(builder, count);
    if count > 0 {
        offset := builder.count;
        array_resize(builder, offset + count);
        memcpy(builder.data + offset, value.data, count);
    }
}

cache_get :: (source: *string, out: *$T) -> bool {
    if source.count < size_of(T) return false;
    memcpy(out, source.data, size_of(T));
    source.data += size_of(T);
    source.count -= size_of(T);
    return true;
}

cache_get_array :: (source: *string, out: *[..]$T) -> bool {
    count: u32;
    if !cache_get(source, *count) return false;
    if count == 0 return true;
    out.allocator = context.allocator;
    array_resize(out, count);
    byte_count := cast(s64) count * size_of(T);
    if source.count < byte_count return false;
    memcpy(out.data, source.data, byte_count);
    source.data += byte_count;
    source.count -= byte_count;
    return true;
}

cache_get_bytes :: (source: *string, out: *[..]u8) -> bool {
    count: u32;
    if !cache_get(source, *count) return false;
    if count == 0 return true;
    out.allocator = context.allocator;
    array_resize(out, count);
    if source.count < count return false;
    memcpy(out.data, source.data, count);
    source.data += count;
    source.count -= count;
    return true;
}

cache_get_string :: (source: *string, out: *string) -> bool {
    count: u32;
    if !cache_get(source, *count) return false;
    if count == 0 {
        out.* = "";
        return true;
    }
    if source.count < count return false;
    out.data = alloc(count);
    if out.data == null return false;
    out.count = count;
    memcpy(out.data, source.data, count);
    source.data += count;
    source.count -= count;
    return true;
}

Texture_Load_Result :: struct {
    texture_index: u32;
}

load_model_into_imported_scene :: (imported: *Imported_Scene, path: string) {
    load_flags: ai.PostProcessSteps :
          .Triangulate | .JoinIdenticalVertices | .ImproveCacheLocality | .OptimizeMeshes
        | .GenUVCoords | .FindInvalidData | .FindDegenerates | .RemoveRedundantMaterials
        | .FlipUVs
    ;

    scene := ai.ImportFileEx(temp_c_string(path), cast,no_check(u32) load_flags, null);
    assert(scene != null, "Assimp import failed for %", path);
    defer ai.FreeScene(scene);

    model_name := String.path_strip_extension(String.path_filename(path));
    model_dir := String.path_strip_filename(path);

    mesh_start := cast(u32) imported.meshes.count;
    node_start := cast(u32) imported.nodes.count;
    material_start := cast(u32) imported.materials.count;
    anim_clip_start := cast(u32) imported.anim_clips.count;
    node_name_to_index: Table(string, s32);
    defer Hash_Table.deinit(*node_name_to_index);

    scene_materials: []*ai.Material = .{ scene.mNumMaterials, scene.mMaterials };
    for scene_materials {
        texture_index := load_material_base_color_texture(imported, scene, it, model_dir, path).texture_index;
        array_add(*imported.materials, .{
            base_color_factor = .{1.0, 1.0, 1.0, 1.0},
            base_color_texture_index = texture_index,
        });
    }

    root_node_index := append_ai_node_recursive(imported, scene, scene.mRootNode, -1, mesh_start, *node_name_to_index);
    compute_world_matrices(imported.nodes, node_start, cast(u32) imported.nodes.count - node_start);

    scene_meshes := ai.meshes(scene);
    for scene_meshes {
        append_ai_mesh(imported, it, material_start, *node_name_to_index);
    }

    for anim, anim_index: ai.animations(scene) {
        append_ai_animation(imported, anim, *node_name_to_index, model_name, cast(s32) anim_index);
    }

    array_add(*imported.models, .{
        name = copy_string(model_name),
        root_node_index = root_node_index,
        node_start = node_start,
        node_count = cast(u32) imported.nodes.count - node_start,
        mesh_start = mesh_start,
        mesh_count = scene.mNumMeshes,
        anim_clip_start = anim_clip_start,
        anim_clip_count = cast(u32) imported.anim_clips.count - anim_clip_start,
    });
}

append_ai_mesh :: (
    imported: *Imported_Scene,
    mesh: *ai.Mesh,
    material_base: u32,
    node_name_to_index: *Table(string, s32),
) {
    base_vertex := cast(u32) imported.vertices.count;
    num_vertices := cast(s64) mesh.mNumVertices;

    normals := cast(*Vector3) mesh.mNormals;
    tex_coords := mesh.mTextureCoords[0];

    for 0..num_vertices-1 {
        pos := cast,force(Vector3) mesh.mVertices[it];
        normal := Vector3.{0.0, 1.0, 0.0};
        if normals != null normal = normals[it];

        uv := Vector2.{0.0, 0.0};
        if tex_coords != null {
            uv3 := tex_coords[it];
            uv = .{uv3.x, uv3.y};
        }

        array_add(*imported.vertices, .{
            position = .{pos.x, pos.y, pos.z, 1.0},
            normal = .{normal.x, normal.y, normal.z, 0.0},
            uv = uv,
        });
    }

    first_index := cast(u32) imported.indices.count;
    for face: ai.faces(mesh) {
        assert(face.mNumIndices == 3, "Only triangulated meshes are supported.");
        array_add(*imported.indices,
            base_vertex + face.mIndices[0],
            base_vertex + face.mIndices[1],
            base_vertex + face.mIndices[2]);
    }

    skin_bone_start := cast(u32) imported.mesh_skin_bones.count;
    skin_bone_count: u32 = 0;
    if mesh.mNumBones > 0 {
        bone_vertex_counts := NewArray(num_vertices, u32);
        defer array_free(bone_vertex_counts);

        for bone: ai.bones(mesh) {
            found, node_index := table_find(node_name_to_index, ai.to_string(bone.mName));
            assert(found, "Bone node '%' not found in imported node table.", ai.to_string(bone.mName));

            local_bone_index := skin_bone_count;
            skin_bone_count += 1;
            array_add(*imported.mesh_skin_bones, .{
                node_index = node_index,
                inverse_bind = cast,force(Matrix4) bone.mOffsetMatrix,
            });

            for vertex_weight: ai.weights(bone) {
                id := cast(s64) vertex_weight.mVertexId;
                nth_bone := bone_vertex_counts[id];
                bone_vertex_counts[id] += 1;
                if nth_bone >= 4 continue;

                vertex := *imported.vertices[base_vertex + id];
                vertex.bone_indices.component[nth_bone] = cast(float) local_bone_index;
                vertex.bone_weights.component[nth_bone] = vertex_weight.mWeight;
            }
        }

        for vertex_offset: 0..num_vertices-1 {
            vertex := *imported.vertices[base_vertex + vertex_offset];
            weight_sum: float = 0.0;
            for i: 0..3 weight_sum += vertex.bone_weights.component[i];
            if weight_sum > 0.0 {
                inv_sum := 1.0 / weight_sum;
                for i: 0..3 vertex.bone_weights.component[i] *= inv_sum;
            }
        }
    }

    if normals == null {
        generate_missing_normals(imported.vertices, imported.indices, first_index, cast(u32) imported.indices.count - first_index);
    }

    material_index := material_base;
    if mesh.mMaterialIndex < cast(u32) imported.materials.count {
        material_index += mesh.mMaterialIndex;
    }

    array_add(*imported.meshes, .{
        first_index = first_index,
        index_count = cast(u32) imported.indices.count - first_index,
        material_index = material_index,
        skin_bone_start = skin_bone_start,
        skin_bone_count = skin_bone_count,
    });
}

generate_missing_normals :: (vertices: []Scene_Vertex, indices: []u32, first_index: u32, index_count: u32) {
    for i: first_index .. first_index + index_count - 1 {
        vertices[indices[i]].normal = .{0.0, 0.0, 0.0, 0.0};
    }

    tri_end := first_index + index_count;
    i := first_index;
    while i < tri_end {
        i0 := indices[i + 0];
        i1 := indices[i + 1];
        i2 := indices[i + 2];
        p0 := vertices[i0].position;
        p1 := vertices[i1].position;
        p2 := vertices[i2].position;
        face_normal := normalize(cross(
            Vector3.{p1.x - p0.x, p1.y - p0.y, p1.z - p0.z},
            Vector3.{p2.x - p0.x, p2.y - p0.y, p2.z - p0.z}));
        vertices[i0].normal += .{face_normal.x, face_normal.y, face_normal.z, 0.0};
        vertices[i1].normal += .{face_normal.x, face_normal.y, face_normal.z, 0.0};
        vertices[i2].normal += .{face_normal.x, face_normal.y, face_normal.z, 0.0};
        i += 3;
    }

    for i: first_index .. first_index + index_count - 1 {
        idx := indices[i];
        normal := normalize(Vector3.{vertices[idx].normal.x, vertices[idx].normal.y, vertices[idx].normal.z});
        vertices[idx].normal = .{normal.x, normal.y, normal.z, 0.0};
    }
}

append_ai_node_recursive :: (
    imported: *Imported_Scene,
    scene: *ai.Scene,
    ai_node: *ai.Node,
    parent_index: s32,
    mesh_base: u32,
    node_name_to_index: *Table(string, s32),
) -> s32 {
    node_index := cast(s32) imported.nodes.count;

    bind_scale: ai.Vector3D;
    bind_rotation: ai.Quaternion;
    bind_translation: ai.Vector3D;
    ai.DecomposeMatrix(*ai_node.mTransformation, *bind_scale, *bind_rotation, *bind_translation);

    array_add(*imported.nodes, .{
        parent_index = parent_index,
        first_child_index = -1,
        next_sibling_index = -1,
        first_mesh_ref = cast(u32) imported.node_mesh_refs.count,
        mesh_ref_count = ai_node.mNumMeshes,
        local = cast,force(Matrix4) ai_node.mTransformation,
        world = Matrix4_Identity,
    });
    array_add(*imported.node_bind_transforms, .{
        translation = .{bind_translation.x, bind_translation.y, bind_translation.z},
        rotation = .{bind_rotation.x, bind_rotation.y, bind_rotation.z, bind_rotation.w},
        scale = .{bind_scale.x, bind_scale.y, bind_scale.z},
    });
    table_set(node_name_to_index, ai.to_string(ai_node.mName), node_index);

    for mesh_index: ai.mesh_indices(ai_node) {
        array_add(*imported.node_mesh_refs, mesh_base + mesh_index);
    }

    prev_child := -1;
    for child: ai.children(ai_node) {
        child_index := append_ai_node_recursive(imported, scene, child, node_index, mesh_base, node_name_to_index);
        if prev_child == -1 {
            imported.nodes[node_index].first_child_index = child_index;
        } else {
            imported.nodes[prev_child].next_sibling_index = child_index;
        }
        prev_child = child_index;
    }

    return node_index;
}

append_ai_animation :: (imported: *Imported_Scene, anim: *ai.Animation, node_name_to_index: *Table(string, s32), model_name: string, anim_index: s32) {
    clip_name := ai.to_string(anim.mName);
    if clip_name.count == 0 clip_name = tprint("%_anim_%", model_name, anim_index);

    clip: Scene_Anim_Clip;
    clip.name = copy_string(clip_name);
    clip.duration = cast(float) anim.mDuration;
    clip.ticks_per_second = ifx anim.mTicksPerSecond != 0 then cast(float) anim.mTicksPerSecond else 25.0;
    clip.channel_start = cast(u32) imported.anim_channels.count;

    for channel: ai.channels(anim) {
        node_name := ai.to_string(channel.mNodeName);
        found, node_index := table_find(node_name_to_index, node_name);
        if !found continue;

        entry: Scene_Anim_Channel;
        entry.node_index = node_index;
        entry.position_key_start = cast(u32) imported.anim_position_keys.count;
        entry.rotation_key_start = cast(u32) imported.anim_rotation_keys.count;
        entry.scale_key_start = cast(u32) imported.anim_scale_keys.count;

        for i: 0..cast(s64) channel.mNumPositionKeys-1 {
            key := channel.mPositionKeys[i];
            array_add(*imported.anim_position_keys, .{
                time = cast(float) key.mTime,
                value = .{key.mValue.x, key.mValue.y, key.mValue.z},
            });
        }
        entry.position_key_count = cast(u32) imported.anim_position_keys.count - entry.position_key_start;

        for i: 0..cast(s64) channel.mNumRotationKeys-1 {
            key := channel.mRotationKeys[i];
            array_add(*imported.anim_rotation_keys, .{
                time = cast(float) key.mTime,
                value = .{key.mValue.x, key.mValue.y, key.mValue.z, key.mValue.w},
            });
        }
        entry.rotation_key_count = cast(u32) imported.anim_rotation_keys.count - entry.rotation_key_start;

        for i: 0..cast(s64) channel.mNumScalingKeys-1 {
            key := channel.mScalingKeys[i];
            array_add(*imported.anim_scale_keys, .{
                time = cast(float) key.mTime,
                value = .{key.mValue.x, key.mValue.y, key.mValue.z},
            });
        }
        entry.scale_key_count = cast(u32) imported.anim_scale_keys.count - entry.scale_key_start;

        array_add(*imported.anim_channels, entry);
    }

    clip.channel_count = cast(u32) imported.anim_channels.count - clip.channel_start;
    array_add(*imported.anim_clips, clip);
}

compute_world_matrices :: (nodes: []Scene_Node, node_start: u32, node_count: u32) {
    for local_index: 0..node_count-1 {
        node_index := node_start + local_index;
        node := *nodes[node_index];
        parent_world := Matrix4_Identity;
        if node.parent_index >= 0 parent_world = nodes[node.parent_index].world;
        node.world = parent_world * node.local;
    }
}

load_material_base_color_texture :: (
    imported: *Imported_Scene,
    scene: *ai.Scene,
    material: *ai.Material,
    model_dir: string,
    model_path: string,
) -> Texture_Load_Result {
    texture_types := ai.TextureType.[.BASE_COLOR, .DIFFUSE];
    for texture_types {
        if ai.GetMaterialTextureCount(material, it) == 0 continue;

        path: ai.String;
        res := ai.GetMaterialTexture(material, it, 0, *path, null, null, null, null, null, null);
        if res != .SUCCESS continue;

        resolved := resolve_assimp_texture_key(scene, model_dir, model_path, ai.to_string(path));
        defer if resolved.count != 0 free(resolved);
        return .{texture_index = get_or_load_texture(imported, scene, resolved, ai.to_string(path))};
    }

    return .{texture_index = 0};
}

resolve_assimp_texture_key :: (scene: *ai.Scene, model_dir: string, model_path: string, path: string) -> string {
    _ = scene;
    if path.count > 0 && path[0] == #char "*" {
        return sprint("%#%", model_path, path);
    }
    return copy_string(String.path_join(model_dir, path));
}

get_or_load_texture :: (imported: *Imported_Scene, scene: *ai.Scene, resolved_key: string, assimp_path: string) -> u32 {
    for imported.textures {
        if it.key == resolved_key return cast(u32) it_index;
    }

    texture := load_scene_texture(scene, resolved_key, assimp_path);
    array_add(*imported.textures, texture);
    return cast(u32) imported.textures.count - 1;
}

load_scene_texture :: (scene: *ai.Scene, resolved_key: string, assimp_path: string) -> Imported_Texture {
    if assimp_path.count > 0 && assimp_path[0] == #char "*" {
        embedded := ai.GetEmbeddedTexture(scene, cast(*u8) assimp_path.data);
        assert(embedded != null, "Embedded texture % not found.", assimp_path);

        if embedded.mHeight == 0 {
            width, height, channels: s32 = 0;
            pixels := stbi_load_from_memory(cast(*u8) embedded.pcData, cast(s32) embedded.mWidth, *width, *height, *channels, 4);
            defer stbi_image_free(pixels);
            assert(pixels != null && width > 0 && height > 0, "Failed to decode embedded texture %", assimp_path);
            rgba := copy_bytes(cast([]u8) .{count = width * height * 4, data = pixels});
            return .{key = copy_string(resolved_key), width = cast(u32) width, height = cast(u32) height, pixels = rgba};
        }

        raw_pixels := cast(*u8) embedded.pcData;
        byte_count := cast(s64) embedded.mWidth * cast(s64) embedded.mHeight * 4;
        rgba := bgra_to_rgba(.{count = byte_count, data = raw_pixels});
        return .{key = copy_string(resolved_key), width = embedded.mWidth, height = embedded.mHeight, pixels = rgba};
    }

    width, height, channels: s32 = 0;
    pixels := stbi_load(temp_c_string(resolved_key), *width, *height, *channels, 4);
    defer stbi_image_free(pixels);
    assert(pixels != null && width > 0 && height > 0, "Failed to load texture %", resolved_key);
    rgba := copy_bytes(cast([]u8) .{count = width * height * 4, data = pixels});
    return .{key = copy_string(resolved_key), width = cast(u32) width, height = cast(u32) height, pixels = rgba};
}

imported_scene_create_default_white_texture :: (imported: *Imported_Scene) {
    pixels: [..]u8;
    pixels.allocator = context.allocator;
    array_add(*pixels, 255, 255, 255, 255);
    array_add(*imported.textures, .{
        key = copy_string("__white__"),
        width = 1,
        height = 1,
        pixels = pixels,
    });
}

create_texture_from_rgba8 :: (pixels: []u8, width: u32, height: u32) -> Gpu_Texture, Gpu_Texture_View {
    result, texture := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS && texture != 0, "Scene_Geo texture creation failed.");

    bgra_pixels: [..]u8;
    bgra_pixels.allocator = temp;
    array_resize(*bgra_pixels, pixels.count);
    memcpy(bgra_pixels.data, pixels.data, pixels.count);

    i := 0;
    while i < bgra_pixels.count {
        r := bgra_pixels[i + 0];
        g := bgra_pixels[i + 1];
        b := bgra_pixels[i + 2];
        a := bgra_pixels[i + 3];
        bgra_pixels[i + 0] = b;
        bgra_pixels[i + 1] = g;
        bgra_pixels[i + 2] = r;
        bgra_pixels[i + 3] = a;
        i += 4;
    }

    gpu_copy_to_texture(texture, bgra_pixels.data);
    view := gpu_texture_view(texture);
    assert(view != 0, "Scene_Geo texture view creation failed.");
    return texture, view;
}

copy_bytes :: (src: []u8) -> [..]u8 {
    dst: [..]u8;
    dst.allocator = context.allocator;
    if src.count == 0 return dst;
    array_resize(*dst, src.count);
    memcpy(dst.data, src.data, src.count);
    return dst;
}

bgra_to_rgba :: (src: []u8) -> [..]u8 {
    dst := copy_bytes(src);
    i := 0;
    while i < dst.count {
        b := dst[i + 0];
        g := dst[i + 1];
        r := dst[i + 2];
        a := dst[i + 3];
        dst[i + 0] = r;
        dst[i + 1] = g;
        dst[i + 2] = b;
        dst[i + 3] = a;
        i += 4;
    }
    return dst;
}

create_texture_from_bgra8 :: (pixels: []u8, width: u32, height: u32) -> Gpu_Texture, Gpu_Texture_View {
    result, texture := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS && texture != 0, "Scene_Geo texture creation failed.");
    gpu_copy_to_texture(texture, pixels.data);
    view := gpu_texture_view(texture);
    assert(view != 0, "Scene_Geo texture view creation failed.");
    return texture, view;
}

ai :: #import "assimp";
String :: #import "String";
File :: #import "File";
File_Utilities :: #import "File_Utilities";
using File_Utilities;
Hash :: #import "Hash";
using Hash;
#import "Math";
#import "stb_image";

find_workspace_root_for_cache :: () -> string {
    cwd := get_working_directory();
    probe := cwd;

    while probe.count != 0 {
        if file_exists(tprint("%/build.jai", probe)) return probe;
        parent := String.path_strip_filename(probe);
        if parent.count != 0 && parent[parent.count-1] == "/" {
            parent.count -= 1;
        }
        if parent == probe break;
        probe = parent;
    }

    return cwd;
}
