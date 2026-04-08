SCENE_INVALID_TEXTURE_INDEX :: ~cast(u32) 0;

Scene_Vertex :: struct {
    position: Vector4;
    normal: Vector4;
    tangent: Vector4;
    bone_indices: Vector4;
    bone_weights: Vector4;
    uv: Vector2;
    _pad0: Vector2;
}

LOD_Simplify_Attributes :: struct {
    uv: [2]float;
    normal: [3]float;
    tangent: [4]float;
}

Scene_Material :: struct {
    base_color_factor: Vector4;
    metallic_factor: float;
    roughness_factor: float;
    base_color_texture_index: u32;
    opacity_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    alpha_mode: u32;
    alpha_cutoff: float;
    address_mode_u: u32;
    address_mode_v: u32;
    sampler_index: u32;
    _pad0: u32;
    _pad1: u32;
    _pad2: u32;
    _pad3: u32;
}

Scene_Mesh :: struct {
    base_vertex: u32;
    vertex_count: u32;
    first_index: u32;
    index_count: u32;
    material_index: u32;
    skin_bone_start: u32;
    skin_bone_count: u32;
    morph_target_start: u32;
    morph_target_count: u32;
    lod_mesh_start: u32;
    lod_mesh_count: u32;
}

Scene_Meshlet :: struct {
    vertex_offset: u32;
    triangle_offset: u32;
    vertex_count: u32;
    triangle_count: u32;
}

Scene_Meshlet_Mesh :: struct {
    meshlet_start: u32;
    meshlet_count: u32;
    bounds_center_radius: Vector4;
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

Scene_Sampler_Binding :: struct {
    sampler: Gpu_Sampler;
    mode_u: u32;
    mode_v: u32;
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

Scene_Morph_Target :: struct {
    vertex_delta_start: u32;
    vertex_delta_count: u32;
    default_weight: float;
    _pad0: float;
}

Scene_Morph_Vertex_Delta :: struct {
    position: Vector4;
    normal: Vector4;
    tangent: Vector4;
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

Scene_Anim_Morph_Key :: struct {
    time: float;
    value: float;
}

Scene_Anim_Morph_Channel :: struct {
    morph_target_index: u32;
    key_start: u32;
    key_count: u32;
    _pad0: u32;
}

Scene_Anim_Clip :: struct {
    name: string;
    duration: float;
    ticks_per_second: float;
    channel_start: u32;
    channel_count: u32;
    morph_channel_start: u32;
    morph_channel_count: u32;
}

Imported_Texture :: struct {
    key: string;
    width: u32;
    height: u32;
    pixels: [..]u8;
    has_alpha: bool;
}

Imported_Scene :: struct {
    vertices: [..]Scene_Vertex;
    indices: [..]u32;
    materials: [..]Scene_Material;
    textures: [..]Imported_Texture;
    meshes: [..]Scene_Mesh;
    nodes: [..]Scene_Node;
    node_names: [..]string;
    node_bind_transforms: [..]Scene_Node_Transform;
    node_mesh_refs: [..]u32;
    mesh_skin_bones: [..]Scene_Mesh_Skin_Bone;
    morph_targets: [..]Scene_Morph_Target;
    morph_target_names: [..]string;
    morph_vertex_deltas: [..]Scene_Morph_Vertex_Delta;
    anim_position_keys: [..]Scene_Anim_Position_Key;
    anim_rotation_keys: [..]Scene_Anim_Rotation_Key;
    anim_scale_keys: [..]Scene_Anim_Scale_Key;
    anim_channels: [..]Scene_Anim_Channel;
    anim_morph_keys: [..]Scene_Anim_Morph_Key;
    anim_morph_channels: [..]Scene_Anim_Morph_Channel;
    anim_clips: [..]Scene_Anim_Clip;
    models: [..]Scene_Model;
}

Imported_Scene_Cache_Metadata :: struct {
    materials: [..]Scene_Material;
    textures: [..]Imported_Texture;
    meshes: [..]Scene_Mesh;
    nodes: [..]Scene_Node;
    node_names: [..]string;
    node_bind_transforms: [..]Scene_Node_Transform;
    node_mesh_refs: [..]u32;
    mesh_skin_bones: [..]Scene_Mesh_Skin_Bone;
    morph_targets: [..]Scene_Morph_Target;
    morph_target_names: [..]string;
    morph_vertex_deltas: [..]Scene_Morph_Vertex_Delta;
    anim_position_keys: [..]Scene_Anim_Position_Key;
    anim_rotation_keys: [..]Scene_Anim_Rotation_Key;
    anim_scale_keys: [..]Scene_Anim_Scale_Key;
    anim_channels: [..]Scene_Anim_Channel;
    anim_morph_keys: [..]Scene_Anim_Morph_Key;
    anim_morph_channels: [..]Scene_Anim_Morph_Channel;
    anim_clips: [..]Scene_Anim_Clip;
    models: [..]Scene_Model;
}

Scene_Geo :: struct {
    arena: Gpu_Arena;
    vertices: Gpu_View(Scene_Vertex);
    morph_vertex_deltas: Gpu_View(Scene_Morph_Vertex_Delta);
    indices: Gpu_View(u32);
    materials: Gpu_View(Scene_Material);
    meshlets: Gpu_View(Scene_Meshlet);
    meshlet_vertices: Gpu_View(u32);
    meshlet_triangles: Gpu_View(u32);
    meshlet_bounds: Gpu_View(Vector4);
    meshlet_meshes: Gpu_View(Scene_Meshlet_Mesh);
    max_meshlet_count: u32;

    textures: [..]Gpu_Texture;
    texture_views: [..]Gpu_Texture_View;
    texture_keys: [..]string;
    samplers: [..]Scene_Sampler_Binding;

    meshes: [..]Scene_Mesh;
    nodes: [..]Scene_Node;
    node_names: [..]string;
    node_bind_transforms: [..]Scene_Node_Transform;
    node_mesh_refs: [..]u32;
    mesh_skin_bones: [..]Scene_Mesh_Skin_Bone;
    morph_targets: [..]Scene_Morph_Target;
    morph_target_names: [..]string;
    anim_position_keys: [..]Scene_Anim_Position_Key;
    anim_rotation_keys: [..]Scene_Anim_Rotation_Key;
    anim_scale_keys: [..]Scene_Anim_Scale_Key;
    anim_channels: [..]Scene_Anim_Channel;
    anim_morph_keys: [..]Scene_Anim_Morph_Key;
    anim_morph_channels: [..]Scene_Anim_Morph_Channel;
    anim_clips: [..]Scene_Anim_Clip;
    models: [..]Scene_Model;
    model_bounds: [..]Scene_Bounds;
}

scene_geo_init :: (geo: *Scene_Geo, model_paths: []string) {
    resolved_model_paths := resolve_scene_model_import_paths(model_paths);
    defer if resolved_model_paths.data != null array_free(resolved_model_paths);

    imported: Imported_Scene;
    imported_scene_load_cached(*imported, model_paths, resolved_model_paths);
    defer imported_scene_deinit(*imported);
    scene_geo_init_from_imported(geo, *imported, model_paths, resolved_model_paths);
}

scene_geo_init_from_imported :: (using geo: *Scene_Geo, imported: *Imported_Scene, model_paths: []string, resolved_model_paths: []string) {
    cpu_meshlet_meshes, cpu_meshlets, cpu_meshlet_vertices, cpu_meshlet_triangles, cpu_meshlet_bounds, built_max_meshlet_count :=
        build_scene_meshlets_cached(imported, model_paths, resolved_model_paths);
    defer {
        array_free(cpu_meshlet_meshes);
        array_free(cpu_meshlets);
        array_free(cpu_meshlet_vertices);
        array_free(cpu_meshlet_triangles);
        array_free(cpu_meshlet_bounds);
    }

    for it: imported.textures {
        assert(it.width > 0 && it.height > 0 && it.pixels.count >= cast(s64) it.width * cast(s64) it.height * 4,
            "Imported texture invalid: key=% width=% height=% pixels=%.",
            it.key, it.width, it.height, it.pixels.count);
        texture, view := create_texture_from_rgba8(it.pixels, it.width, it.height);
        array_add(*textures, texture);
        array_add(*texture_views, view);
        array_add(*texture_keys, copy_string(it.key));
    }

    total_bytes :=
        imported.vertices.count * size_of(Scene_Vertex) +
        imported.morph_vertex_deltas.count * size_of(Scene_Morph_Vertex_Delta) +
        imported.indices.count * size_of(u32) +
        imported.materials.count * size_of(Scene_Material) +
        cpu_meshlets.count * size_of(Scene_Meshlet) +
        cpu_meshlet_vertices.count * size_of(u32) +
        cpu_meshlet_triangles.count * size_of(u32) +
        cpu_meshlet_bounds.count * size_of(Vector4) +
        cpu_meshlet_meshes.count * size_of(Scene_Meshlet_Mesh) +
        1024;

    arena = gpu_make_arena(total_bytes, label = "scene geo arena");
    assert(arena.cpu != null, "Scene_Geo arena creation failed.");

    vertices = gpu_alloc_view(*arena, Scene_Vertex, imported.vertices.count);
    morph_vertex_deltas = gpu_alloc_view(*arena, Scene_Morph_Vertex_Delta, imported.morph_vertex_deltas.count);
    indices = gpu_alloc_view(*arena, u32, imported.indices.count);
    materials = gpu_alloc_view(*arena, Scene_Material, imported.materials.count);
    meshlets = gpu_alloc_view(*arena, Scene_Meshlet, cpu_meshlets.count);
    meshlet_vertices = gpu_alloc_view(*arena, u32, cpu_meshlet_vertices.count);
    meshlet_triangles = gpu_alloc_view(*arena, u32, cpu_meshlet_triangles.count);
    meshlet_bounds = gpu_alloc_view(*arena, Vector4, cpu_meshlet_bounds.count);
    meshlet_meshes = gpu_alloc_view(*arena, Scene_Meshlet_Mesh, cpu_meshlet_meshes.count);
    max_meshlet_count = built_max_meshlet_count;

    if imported.vertices.count > 0 {
        memcpy(vertices.cpu.data, imported.vertices.data, imported.vertices.count * size_of(Scene_Vertex));
    }
    if imported.morph_vertex_deltas.count > 0 {
        memcpy(morph_vertex_deltas.cpu.data, imported.morph_vertex_deltas.data, imported.morph_vertex_deltas.count * size_of(Scene_Morph_Vertex_Delta));
    }
    if imported.indices.count > 0 {
        memcpy(indices.cpu.data, imported.indices.data, imported.indices.count * size_of(u32));
    }
    if imported.materials.count > 0 {
        for imported.materials {
            material := it;
            if material.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
                assert(material.base_color_texture_index < texture_views.count, "Imported texture index % out of range %.", material.base_color_texture_index, texture_views.count);
                material.base_color_texture_index = gpu_texture_view_index(texture_views[material.base_color_texture_index]);
            }
            if material.opacity_texture_index != SCENE_INVALID_TEXTURE_INDEX {
                assert(material.opacity_texture_index < texture_views.count, "Imported opacity texture index % out of range %.", material.opacity_texture_index, texture_views.count);
                material.opacity_texture_index = gpu_texture_view_index(texture_views[material.opacity_texture_index]);
            }
            if material.normal_texture_index != SCENE_INVALID_TEXTURE_INDEX {
                assert(material.normal_texture_index < texture_views.count, "Imported normal texture index % out of range %.", material.normal_texture_index, texture_views.count);
                material.normal_texture_index = gpu_texture_view_index(texture_views[material.normal_texture_index]);
            }
            if material.roughness_texture_index != SCENE_INVALID_TEXTURE_INDEX {
                assert(material.roughness_texture_index < texture_views.count, "Imported roughness texture index % out of range %.", material.roughness_texture_index, texture_views.count);
                material.roughness_texture_index = gpu_texture_view_index(texture_views[material.roughness_texture_index]);
            }
            if material.ao_texture_index != SCENE_INVALID_TEXTURE_INDEX {
                assert(material.ao_texture_index < texture_views.count, "Imported AO texture index % out of range %.", material.ao_texture_index, texture_views.count);
                material.ao_texture_index = gpu_texture_view_index(texture_views[material.ao_texture_index]);
            }
            sampler := scene_geo_get_or_create_sampler(geo,
                address_mode_from_assimp(cast(ai.TextureMapMode) material.address_mode_u),
                address_mode_from_assimp(cast(ai.TextureMapMode) material.address_mode_v));
            material.sampler_index = cast(u32) sampler - 1;
            materials.cpu[it_index] = material;
        }
    }
    if cpu_meshlets.count > 0 {
        memcpy(meshlets.cpu.data, cpu_meshlets.data, cpu_meshlets.count * size_of(Scene_Meshlet));
    }
    if cpu_meshlet_vertices.count > 0 {
        memcpy(meshlet_vertices.cpu.data, cpu_meshlet_vertices.data, cpu_meshlet_vertices.count * size_of(u32));
    }
    if cpu_meshlet_triangles.count > 0 {
        memcpy(meshlet_triangles.cpu.data, cpu_meshlet_triangles.data, cpu_meshlet_triangles.count * size_of(u32));
    }
    if cpu_meshlet_bounds.count > 0 {
        memcpy(meshlet_bounds.cpu.data, cpu_meshlet_bounds.data, cpu_meshlet_bounds.count * size_of(Vector4));
    }
    if cpu_meshlet_meshes.count > 0 {
        memcpy(meshlet_meshes.cpu.data, cpu_meshlet_meshes.data, cpu_meshlet_meshes.count * size_of(Scene_Meshlet_Mesh));
    }

    array_copy(*meshes, imported.meshes);
    array_copy(*nodes, imported.nodes);
    for imported.node_names array_add(*node_names, copy_string(it));
    array_copy(*node_bind_transforms, imported.node_bind_transforms);
    array_copy(*node_mesh_refs, imported.node_mesh_refs);
    array_copy(*mesh_skin_bones, imported.mesh_skin_bones);
    array_copy(*morph_targets, imported.morph_targets);
    for imported.morph_target_names array_add(*morph_target_names, copy_string(it));
    array_copy(*anim_position_keys, imported.anim_position_keys);
    array_copy(*anim_rotation_keys, imported.anim_rotation_keys);
    array_copy(*anim_scale_keys, imported.anim_scale_keys);
    array_copy(*anim_channels, imported.anim_channels);
    array_copy(*anim_morph_keys, imported.anim_morph_keys);
    array_copy(*anim_morph_channels, imported.anim_morph_channels);
    for it: imported.anim_clips {
        array_add(*anim_clips, .{
            name = copy_string(it.name),
            duration = it.duration,
            ticks_per_second = it.ticks_per_second,
            channel_start = it.channel_start,
            channel_count = it.channel_count,
            morph_channel_start = it.morph_channel_start,
            morph_channel_count = it.morph_channel_count,
        });
    }
    for it: imported.models {
        model := array_add(*models);
        model.* = it;
        model.name = copy_string(it.name);
    }
    array_reserve(*model_bounds, models.count);
    for model_index: 0..models.count-1 {
        array_add(*model_bounds, compute_model_bounds_from_geo(geo, cast(s32) model_index));
    }

    gpu_commit_residency();
}

scene_geo_deinit :: (using geo: *Scene_Geo) {
    for texture_keys if it.count != 0 free(it);
    array_free(texture_keys);
    for models if it.name.count != 0 free(it.name);
    for anim_clips if it.name.count != 0 free(it.name);
    array_free(anim_clips);
    array_free(anim_morph_channels);
    array_free(anim_morph_keys);
    array_free(anim_channels);
    array_free(anim_scale_keys);
    array_free(anim_rotation_keys);
    array_free(anim_position_keys);
    array_free(morph_targets);
    for morph_target_names if it.count != 0 free(it);
    array_free(morph_target_names);
    array_free(mesh_skin_bones);
    array_free(models);
    for node_names if it.count != 0 free(it);
    array_free(node_names);
    array_free(model_bounds);
    array_free(node_bind_transforms);
    array_free(nodes);
    array_free(node_mesh_refs);
    array_free(meshes);

    for textures {
        if it != 0 gpu_free(it);
    }
    array_free(textures);
    array_free(texture_views);
    for samplers if it.sampler != 0 gpu_free(it.sampler);
    array_free(samplers);
    if arena.cpu != null gpu_free_arena(arena);
    geo.* = .{};
}

scene_geo_model_index_by_name :: (using geo: *Scene_Geo, name: string) -> s32 {
    for models if it.name == name return cast(s32) it_index;
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

scene_geo_model_node_index_by_name :: (geo: *Scene_Geo, model_index: s32, name: string) -> s32 {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    model := geo.models[model_index];
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        if geo.node_names[node_index] == name return cast(s32) node_index;
    }
    lowered_name := String.to_lower_copy(name);
    for node_index: model.node_start .. model.node_start + model.node_count - 1 {
        lowered_node_name := String.to_lower_copy(geo.node_names[node_index]);
        if lowered_node_name == lowered_name return cast(s32) node_index;
    }
    return -1;
}

scene_geo_model_bounds :: (geo: *Scene_Geo, model_index: s32) -> Scene_Bounds {
    assert(model_index >= 0 && model_index < geo.models.count, "Invalid Scene_Geo model index %", model_index);
    return geo.model_bounds[model_index];
}

scene_geo_append_model_instances :: (
    batches: *[..]Draw_Batch,
    instances: *[..]Scene_Instance,
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

imported_scene_deinit :: (using scene: *Imported_Scene) {
    array_free(vertices);
    array_free(indices);
    array_free(materials);
    for textures {
        if it.key.count != 0 free(it.key);
        array_free(it.pixels);
    }
    array_free(textures);
    array_free(meshes);
    array_free(nodes);
    for node_names if it.count != 0 free(it);
    array_free(node_names);
    array_free(node_bind_transforms);
    array_free(node_mesh_refs);
    array_free(mesh_skin_bones);
    array_free(morph_targets);
    for morph_target_names if it.count != 0 free(it);
    array_free(morph_target_names);
    array_free(morph_vertex_deltas);
    array_free(anim_position_keys);
    array_free(anim_rotation_keys);
    array_free(anim_scale_keys);
    array_free(anim_channels);
    array_free(anim_morph_keys);
    array_free(anim_morph_channels);
    for anim_clips if it.name.count != 0 free(it.name);
    array_free(anim_clips);
    for scene.models if it.name.count != 0 free(it.name);
    array_free(models);
    scene.* = .{};
}

imported_scene_load_cached :: (scene: *Imported_Scene, model_paths: []string, resolved_model_paths: []string) {
    cache_path := imported_scene_cache_path(model_paths, resolved_model_paths);
    if file_exists(cache_path) {
        data, ok := File.read_entire_file(cache_path);
        if ok {
            loaded, parse_ok := imported_scene_deserialize(scene, data);
            free(data);
            if parse_ok && loaded {
                log("loaded from cache %", cache_path);
                return;
            }

            imported_scene_deinit(scene);
        }
    }

    imported_scene_create_default_white_texture(scene);
    for resolved_model_paths load_model_into_imported_scene(scene, it);

    cache_blob: [..]u8;
    cache_blob.allocator = context.allocator;
    serialize_ok := imported_scene_serialize(*cache_blob, scene.*);
    assert(serialize_ok, "Failed to serialize imported scene cache.");
    if cache_blob.count > 0 {
        legacy_blob: [..]u8;
        legacy_blob.allocator = context.allocator;
        legacy_ok := imported_scene_serialize_legacy_raw(*legacy_blob, scene.*);
        assert(legacy_ok, "Failed to serialize legacy imported scene cache size probe.");
        _ = File.write_entire_file(cache_path, cache_blob.data, cache_blob.count);
        savings := 100.0 * (1.0 - cast(float) cache_blob.count / cast(float) legacy_blob.count);
        log("built imported scene cache % -> legacy=% bytes encoded=% bytes savings=% percent", cache_path, legacy_blob.count, cache_blob.count, savings);
        array_free(legacy_blob);
    }
    array_free(cache_blob);
}

Meshlet_Cache_Header :: struct {
    vertex_count: u32;
    triangle_count: u32;
    encoded_size: u32;
}

compute_meshlet_cache_raw_size :: (
    meshlet_meshes: []Scene_Meshlet_Mesh,
    meshlets: []Scene_Meshlet,
    meshlet_vertices: []u32,
    meshlet_triangles: []u32,
    meshlet_bounds: []Vector4,
) -> s64 {
    return
        cast(s64) meshlet_meshes.count * size_of(Scene_Meshlet_Mesh) +
        cast(s64) meshlets.count * size_of(Scene_Meshlet) +
        cast(s64) meshlet_vertices.count * size_of(u32) +
        cast(s64) meshlet_triangles.count * size_of(u32) +
        cast(s64) meshlet_bounds.count * size_of(Vector4);
}

imported_scene_meshlet_cache_recipe_hash :: () -> u64 {
    builder: String_Builder;
    builder.allocator = temp;
    append(*builder, tprint("v%|", IMPORTED_SCENE_MESHLET_CACHE_VERSION));
    append(*builder, tprint("meshoptimizer=%|", meshopt.MESHOPTIMIZER_VERSION));
    append(*builder, tprint("meshlets=%|%|", SCENE_GEO_MESHLET_MAX_VERTICES, SCENE_GEO_MESHLET_MAX_TRIANGLES));
    append(*builder, tprint("encode_level=%|", SCENE_GEO_MESHLET_ENCODE_LEVEL));
    key := builder_to_string(*builder,, temp);
    return fnv1a_hash(key.data, key.count);
}

imported_scene_meshlet_cache_serialize :: (
    builder: *[..]u8,
    meshlet_meshes: []Scene_Meshlet_Mesh,
    meshlets: []Scene_Meshlet,
    meshlet_vertices: []u32,
    meshlet_triangles: []u32,
    meshlet_bounds: []Vector4,
    max_meshlet_count: u32,
) -> bool {
    cache_put(builder, IMPORTED_SCENE_MESHLET_CACHE_MAGIC);
    cache_put(builder, IMPORTED_SCENE_MESHLET_CACHE_VERSION);
    cache_put(builder, imported_scene_meshlet_cache_recipe_hash());
    cache_put(builder, max_meshlet_count);
    cache_put_array(builder, meshlet_meshes);
    cache_put_array(builder, meshlet_bounds);
    meshlet_count_u32 := cast(u32) meshlets.count;
    cache_put(builder, meshlet_count_u32);

    encode_bound := cast(s64) meshopt.encodeMeshletBound(SCENE_GEO_MESHLET_MAX_VERTICES, SCENE_GEO_MESHLET_MAX_TRIANGLES);
    encode_buffer := NewArray(encode_bound, u8);
    defer array_free(encode_buffer);

    for meshlets {
        raw_vertex_ptr := meshlet_vertices.data + it.vertex_offset;
        meshlet_triangles_u8 := NewArray(cast(s64) it.triangle_count * 3, u8);
        for tri_i: 0..cast(s64) it.triangle_count-1 {
            packed := meshlet_triangles[it.triangle_offset + tri_i];
            meshlet_triangles_u8[tri_i * 3 + 0] = cast(u8) (packed & 0xff);
            meshlet_triangles_u8[tri_i * 3 + 1] = cast(u8) ((packed >> 8) & 0xff);
            meshlet_triangles_u8[tri_i * 3 + 2] = cast(u8) ((packed >> 16) & 0xff);
        }

        encoded_size := meshopt.encodeMeshlet(
            encode_buffer.data,
            cast(u64) encode_buffer.count,
            raw_vertex_ptr,
            cast(u64) it.vertex_count,
            meshlet_triangles_u8.data,
            cast(u64) it.triangle_count);
        if encoded_size == 0 return false;

        header := Meshlet_Cache_Header.{
            vertex_count = it.vertex_count,
            triangle_count = it.triangle_count,
            encoded_size = cast(u32) encoded_size,
        };
        cache_put(builder, header);
        if header.encoded_size > 0 {
            offset := builder.count;
            array_resize(builder, offset + cast(s64) header.encoded_size);
            memcpy(builder.data + offset, encode_buffer.data, cast(s64) header.encoded_size);
        }
        array_free(meshlet_triangles_u8);
    }

    return true;
}

imported_scene_meshlet_cache_deserialize :: (
    source_in: string,
    meshlet_meshes: *[..]Scene_Meshlet_Mesh,
    meshlets: *[..]Scene_Meshlet,
    meshlet_vertices: *[..]u32,
    meshlet_triangles: *[..]u32,
    meshlet_bounds: *[..]Vector4,
    max_meshlet_count: *u32,
) -> bool, bool {
    source := source_in;
    magic: u32;
    version: u32;
    if !cache_get(*source, *magic) return false, false;
    if !cache_get(*source, *version) return false, false;
    if magic != IMPORTED_SCENE_MESHLET_CACHE_MAGIC || version != IMPORTED_SCENE_MESHLET_CACHE_VERSION return false, false;
    recipe_hash: u64;
    if !cache_get(*source, *recipe_hash) return false, false;
    if recipe_hash != imported_scene_meshlet_cache_recipe_hash() return false, false;
    if !cache_get(*source, max_meshlet_count) return false, false;
    if !cache_get_array(*source, meshlet_meshes) return false, false;
    if !cache_get_array(*source, meshlet_bounds) return false, false;

    meshlet_count: u32;
    if !cache_get(*source, *meshlet_count) return false, false;
    if meshlet_count == 0 return true, source.count == 0;

    array_reserve(meshlets, meshlet_count);
    for meshlet_i: 0..cast(s64) meshlet_count-1 {
        header: Meshlet_Cache_Header;
        if !cache_get(*source, *header) return false, false;
        if source.count < cast(s64) header.encoded_size return false, false;

        vertex_offset := cast(u32) meshlet_vertices.count;
        triangle_offset := cast(u32) meshlet_triangles.count;
        array_add(meshlets, .{
            vertex_offset = vertex_offset,
            triangle_offset = triangle_offset,
            vertex_count = header.vertex_count,
            triangle_count = header.triangle_count,
        });
        array_resize(meshlet_vertices, meshlet_vertices.count + cast(s64) header.vertex_count);
        array_resize(meshlet_triangles, meshlet_triangles.count + cast(s64) header.triangle_count);
        decode_result := meshopt.decodeMeshletRaw(
            meshlet_vertices.data + vertex_offset,
            cast(u64) header.vertex_count,
            meshlet_triangles.data + triangle_offset,
            cast(u64) header.triangle_count,
            cast(*u8) source.data,
            cast(u64) header.encoded_size);
        source.data += header.encoded_size;
        source.count -= header.encoded_size;
        if decode_result != 0 return false, false;
    }

    return true, source.count == 0;
}

build_scene_meshlets_cached :: (
    imported: *Imported_Scene,
    model_paths: []string,
    resolved_model_paths: []string,
) -> [..]Scene_Meshlet_Mesh, [..]Scene_Meshlet, [..]u32, [..]u32, [..]Vector4, u32 {
    cache_path := imported_scene_meshlet_cache_path(model_paths, resolved_model_paths);
    meshlet_meshes: [..]Scene_Meshlet_Mesh;
    meshlets: [..]Scene_Meshlet;
    meshlet_vertices: [..]u32;
    meshlet_triangles: [..]u32;
    meshlet_bounds: [..]Vector4;
    max_meshlet_count: u32;

    if file_exists(cache_path) {
        data, ok := File.read_entire_file(cache_path);
        if ok {
            loaded, parse_ok := imported_scene_meshlet_cache_deserialize(data, *meshlet_meshes, *meshlets, *meshlet_vertices, *meshlet_triangles, *meshlet_bounds, *max_meshlet_count);
            free(data);
            if parse_ok && loaded {
                log("loaded meshlets from cache %", cache_path);
                return meshlet_meshes, meshlets, meshlet_vertices, meshlet_triangles, meshlet_bounds, max_meshlet_count;
            }
            array_free(meshlet_meshes);
            array_free(meshlets);
            array_free(meshlet_vertices);
            array_free(meshlet_triangles);
            array_free(meshlet_bounds);
        }
    }

    meshlet_meshes, meshlets, meshlet_vertices, meshlet_triangles, meshlet_bounds, max_meshlet_count = build_scene_meshlets(imported);
    cache_blob: [..]u8;
    cache_blob.allocator = context.allocator;
    serialize_ok := imported_scene_meshlet_cache_serialize(*cache_blob, meshlet_meshes, meshlets, meshlet_vertices, meshlet_triangles, meshlet_bounds, max_meshlet_count);
    assert(serialize_ok, "Failed to serialize meshlet cache.");
    if cache_blob.count > 0 {
        _ = File.write_entire_file(cache_path, cache_blob.data, cache_blob.count);
        raw_size := compute_meshlet_cache_raw_size(meshlet_meshes, meshlets, meshlet_vertices, meshlet_triangles, meshlet_bounds);
        savings := 100.0 * (1.0 - cast(float) cache_blob.count / cast(float) raw_size);
        log("built meshlet cache % -> raw=% bytes encoded=% bytes savings=% percent", cache_path, raw_size, cache_blob.count, savings);
    }
    array_free(cache_blob);
    return meshlet_meshes, meshlets, meshlet_vertices, meshlet_triangles, meshlet_bounds, max_meshlet_count;
}

#scope_file

compute_model_bounds_from_geo :: (geo: *Scene_Geo, model_index: s32) -> Scene_Bounds {
    model := geo.models[model_index];

    bounds: Scene_Bounds = {
        min = .{1000000.0, 1000000.0, 1000000.0},
        max = .{-1000000.0, -1000000.0, -1000000.0},
    };

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

Hash_Table :: #import "Hash_Table";
using,only(Table, table_find, table_reset, table_set) _ :: Hash_Table;
#load "../tools/blender_exporter/peel_scene_format_bindings.jai";
IMPORTED_SCENE_CACHE_VERSION : u32 : 21;
IMPORTED_SCENE_CACHE_MAGIC : u32 : 0x53474d44; // SGMD
IMPORTED_SCENE_MESHLET_CACHE_VERSION : u32 : 1;
IMPORTED_SCENE_MESHLET_CACHE_MAGIC : u32 : 0x4d534744; // MSGD
SCENE_GEO_MESHLET_ENCODE_LEVEL : s32 : 3;

STATIC_MESH_LOD_TARGET_RATIOS :: float.[0.18, 0.02, 0.002];
STATIC_MESH_LOD_TARGET_TRIANGLE_CAPS :: u32.[50000, 5000, 500];
STATIC_MESH_LOD_TARGET_ERRORS :: float.[0.03, 0.20, 0.45];
STATIC_MESH_LOD_ATTRIBUTE_WEIGHTS :: float.[
    2.25, 2.25, // uv
    0.40, 0.40, 0.40, // normal xyz
    0.20, 0.20, 0.20, 0.08, // tangent xyzw
];
STATIC_MESH_LOD_SIMPLIFY_OPTIONS : u32 : cast(u32) meshopt.Simplify.Regularize;

imported_scene_cache_path :: (model_paths: []string, resolved_model_paths: []string) -> string {
    builder: String_Builder;
    append(*builder, tprint("v%|", IMPORTED_SCENE_CACHE_VERSION));
    append(*builder, tprint("recipe=%|", imported_scene_recipe_hash()));
    path_count := max(model_paths.count, resolved_model_paths.count);
    for i: 0..path_count-1 {
        source_path := ifx i < model_paths.count then model_paths[i] else "";
        resolved_path := ifx i < resolved_model_paths.count then resolved_model_paths[i] else source_path;
        modtime, size, _ := file_modtime_and_size(resolved_path);
        append(*builder, tprint("%|=>%|%|%|", source_path, resolved_path, size, modtime));
    }
    key_source := builder_to_string(*builder,, temp);
    hash := fnv1a_hash(key_source.data, key_source.count);
    cache_dir := tprint("%/.build/model_cache", find_workspace_root_for_cache());
    File.make_directory_if_it_does_not_exist(cache_dir, true);
    return tprint("%/scene_geo_%.bin", cache_dir, hash);
}

imported_scene_meshlet_cache_path :: (model_paths: []string, resolved_model_paths: []string) -> string {
    return tprint("%.meshlets", imported_scene_cache_path(model_paths, resolved_model_paths));
}

imported_scene_serialize :: (builder: *[..]u8, scene: Imported_Scene) -> bool {
    cache_put(builder, IMPORTED_SCENE_CACHE_MAGIC);
    cache_put(builder, IMPORTED_SCENE_CACHE_VERSION);
    cache_put(builder, imported_scene_recipe_hash());
    cache_put(builder, geo_cache_type_hash(type_info(Imported_Scene_Cache_Metadata)));
    cache_put(builder, geo_cache_type_hash(type_info(Scene_Vertex)));
    if !cache_put_scene_vertices_encoded(builder, scene.vertices) return false;
    if !cache_put_scene_indices_encoded(builder, scene.indices) return false;
    metadata := imported_scene_cache_metadata_from_scene(scene);
    return geo_cache_put_reflected(builder, *metadata, type_info(Imported_Scene_Cache_Metadata));
}

imported_scene_serialize_legacy_raw :: (builder: *[..]u8, scene: Imported_Scene) -> bool {
    cache_put(builder, IMPORTED_SCENE_CACHE_MAGIC);
    cache_put(builder, IMPORTED_SCENE_CACHE_VERSION);
    cache_put(builder, imported_scene_recipe_hash());
    cache_put(builder, geo_cache_type_hash(type_info(Imported_Scene)));
    return geo_cache_put_reflected(builder, *scene, type_info(Imported_Scene));
}

imported_scene_deserialize :: (scene: *Imported_Scene, source_in: string) -> bool, bool {
    source := source_in;
    magic: u32;
    version: u32;
    if !cache_get(*source, *magic) return false, false;
    if !cache_get(*source, *version) return false, false;
    if magic != IMPORTED_SCENE_CACHE_MAGIC || version != IMPORTED_SCENE_CACHE_VERSION return false, false;
    recipe_hash: u64;
    if !cache_get(*source, *recipe_hash) return false, false;
    if recipe_hash != imported_scene_recipe_hash() return false, false;
    schema_hash: u64;
    if !cache_get(*source, *schema_hash) return false, false;
    if schema_hash != geo_cache_type_hash(type_info(Imported_Scene_Cache_Metadata)) return false, false;
    vertex_schema_hash: u64;
    if !cache_get(*source, *vertex_schema_hash) return false, false;
    if vertex_schema_hash != geo_cache_type_hash(type_info(Scene_Vertex)) return false, false;
    if !cache_get_scene_vertices_encoded(*source, *scene.vertices) return false, false;
    if !cache_get_scene_indices_encoded(*source, *scene.indices) return false, false;
    metadata: Imported_Scene_Cache_Metadata;
    if !geo_cache_get_reflected(*source, *metadata, type_info(Imported_Scene_Cache_Metadata)) return false, false;
    imported_scene_apply_cache_metadata(scene, metadata);
    return true, source.count == 0;
}

imported_scene_recipe_hash :: () -> u64 {
    builder: String_Builder;
    builder.allocator = temp;
    append(*builder, "static_lod|");
    for STATIC_MESH_LOD_TARGET_RATIOS append(*builder, tprint("%|", it));
    for STATIC_MESH_LOD_TARGET_TRIANGLE_CAPS append(*builder, tprint("%|", it));
    for STATIC_MESH_LOD_TARGET_ERRORS append(*builder, tprint("%|", it));
    append(*builder, "weights|");
    for STATIC_MESH_LOD_ATTRIBUTE_WEIGHTS append(*builder, tprint("%|", it));
    append(*builder, tprint("simplify_options=%|", STATIC_MESH_LOD_SIMPLIFY_OPTIONS));
    append(*builder, tprint("meshlets=%|%|", SCENE_GEO_MESHLET_MAX_VERTICES, SCENE_GEO_MESHLET_MAX_TRIANGLES));
    append(*builder, tprint("blend_scene=%|", PEEL_SCENE_FILE_VERSION));
    append(*builder, tprint("meshoptimizer=%|", meshopt.MESHOPTIMIZER_VERSION));
    key := builder_to_string(*builder,, temp);
    return fnv1a_hash(key.data, key.count);
}

imported_scene_cache_metadata_from_scene :: (scene: Imported_Scene) -> Imported_Scene_Cache_Metadata {
    return .{
        materials = scene.materials,
        textures = scene.textures,
        meshes = scene.meshes,
        nodes = scene.nodes,
        node_names = scene.node_names,
        node_bind_transforms = scene.node_bind_transforms,
        node_mesh_refs = scene.node_mesh_refs,
        mesh_skin_bones = scene.mesh_skin_bones,
        morph_targets = scene.morph_targets,
        morph_target_names = scene.morph_target_names,
        morph_vertex_deltas = scene.morph_vertex_deltas,
        anim_position_keys = scene.anim_position_keys,
        anim_rotation_keys = scene.anim_rotation_keys,
        anim_scale_keys = scene.anim_scale_keys,
        anim_channels = scene.anim_channels,
        anim_morph_keys = scene.anim_morph_keys,
        anim_morph_channels = scene.anim_morph_channels,
        anim_clips = scene.anim_clips,
        models = scene.models,
    };
}

imported_scene_apply_cache_metadata :: (scene: *Imported_Scene, metadata: Imported_Scene_Cache_Metadata) {
    scene.materials = metadata.materials;
    scene.textures = metadata.textures;
    scene.meshes = metadata.meshes;
    scene.nodes = metadata.nodes;
    scene.node_names = metadata.node_names;
    scene.node_bind_transforms = metadata.node_bind_transforms;
    scene.node_mesh_refs = metadata.node_mesh_refs;
    scene.mesh_skin_bones = metadata.mesh_skin_bones;
    scene.morph_targets = metadata.morph_targets;
    scene.morph_target_names = metadata.morph_target_names;
    scene.morph_vertex_deltas = metadata.morph_vertex_deltas;
    scene.anim_position_keys = metadata.anim_position_keys;
    scene.anim_rotation_keys = metadata.anim_rotation_keys;
    scene.anim_scale_keys = metadata.anim_scale_keys;
    scene.anim_channels = metadata.anim_channels;
    scene.anim_morph_keys = metadata.anim_morph_keys;
    scene.anim_morph_channels = metadata.anim_morph_channels;
    scene.anim_clips = metadata.anim_clips;
    scene.models = metadata.models;
}

cache_put_scene_vertices_encoded :: (builder: *[..]u8, vertices: []Scene_Vertex) -> bool {
    count := cast(u32) vertices.count;
    cache_put(builder, count);
    if count == 0 return true;

    encode_bound := cast(s64) meshopt.encodeVertexBufferBound(cast(u64) count, cast(u64) size_of(Scene_Vertex));
    encode_buffer := NewArray(encode_bound, u8);
    defer array_free(encode_buffer);

    encoded_size := meshopt.encodeVertexBuffer(
        encode_buffer.data,
        cast(u64) encode_buffer.count,
        vertices.data,
        cast(u64) count,
        cast(u64) size_of(Scene_Vertex));
    if encoded_size == 0 return false;

    encoded_size_u32 := cast(u32) encoded_size;
    cache_put(builder, encoded_size_u32);
    offset := builder.count;
    array_resize(builder, offset + cast(s64) encoded_size_u32);
    memcpy(builder.data + offset, encode_buffer.data, cast(s64) encoded_size_u32);
    return true;
}

cache_get_scene_vertices_encoded :: (source: *string, out: *[..]Scene_Vertex) -> bool {
    count: u32;
    if !cache_get(source, *count) return false;
    if count == 0 return true;

    encoded_size: u32;
    if !cache_get(source, *encoded_size) return false;
    if source.count < cast(s64) encoded_size return false;

    out.allocator = context.allocator;
    array_resize(out, count);
    decode_result := meshopt.decodeVertexBuffer(
        out.data,
        cast(u64) count,
        cast(u64) size_of(Scene_Vertex),
        cast(*u8) source.data,
        cast(u64) encoded_size);
    source.data += encoded_size;
    source.count -= encoded_size;
    return decode_result == 0;
}

cache_put_scene_indices_encoded :: (builder: *[..]u8, indices: []u32) -> bool {
    count := cast(u32) indices.count;
    cache_put(builder, count);
    if count == 0 return true;

    max_index: u32;
    for indices max_index = max(max_index, it);
    encode_bound := cast(s64) meshopt.encodeIndexBufferBound(cast(u64) count, cast(u64) max_index + 1);
    encode_buffer := NewArray(encode_bound, u8);
    defer array_free(encode_buffer);

    encoded_size := meshopt.encodeIndexBuffer(
        encode_buffer.data,
        cast(u64) encode_buffer.count,
        indices.data,
        cast(u64) count);
    if encoded_size == 0 return false;

    encoded_size_u32 := cast(u32) encoded_size;
    cache_put(builder, encoded_size_u32);
    offset := builder.count;
    array_resize(builder, offset + cast(s64) encoded_size_u32);
    memcpy(builder.data + offset, encode_buffer.data, cast(s64) encoded_size_u32);
    return true;
}

cache_get_scene_indices_encoded :: (source: *string, out: *[..]u32) -> bool {
    count: u32;
    if !cache_get(source, *count) return false;
    if count == 0 return true;

    encoded_size: u32;
    if !cache_get(source, *encoded_size) return false;
    if source.count < cast(s64) encoded_size return false;

    out.allocator = context.allocator;
    array_resize(out, count);
    decode_result := meshopt.decodeIndexBuffer(
        out.data,
        cast(u64) count,
        cast(u64) size_of(u32),
        cast(*u8) source.data,
        cast(u64) encoded_size);
    source.data += encoded_size;
    source.count -= encoded_size;
    return decode_result == 0;
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

geo_cache_type_hash :: (info: *Type_Info) -> u64 {
    builder: String_Builder;
    builder.allocator = temp;
    geo_cache_append_type_signature(*builder, info);
    signature := builder_to_string(*builder,, temp);
    return fnv1a_hash(signature.data, signature.count);
}

geo_cache_append_type_signature :: (builder: *String_Builder, info: *Type_Info) {
    assert(info != null);
    print_to_builder(builder, "%|%|", info.type, info.runtime_size);
    if info.type == {
    case .STRING;
        append(builder, "string|");
    case .ARRAY;
        arr := cast(*Type_Info_Array) info;
        print_to_builder(builder, "array|%|%|", arr.array_count, arr.array_type);
        geo_cache_append_type_signature(builder, arr.element_type);
    case .STRUCT;
        st := cast(*Type_Info_Struct) info;
        print_to_builder(builder, "struct|%|", st.name);
        highest_offset := -1;
        for member: st.members {
            if member.flags & .CONSTANT continue;
            if member.offset_in_bytes < 0 continue;
            if member.offset_in_bytes <= highest_offset continue;
            highest_offset = member.offset_in_bytes;
            print_to_builder(builder, "%|%|", member.name, member.offset_in_bytes);
            geo_cache_append_type_signature(builder, member.type);
        }
    case;
        ;
    }
}

geo_cache_type_is_blob_serializable :: (info: *Type_Info) -> bool {
    assert(info != null);
    if info.type == {
    case .STRING; return false;
    case .POINTER; return false;
    case .ARRAY;
        arr := cast(*Type_Info_Array) info;
        if arr.array_count == -1 return false;
        return geo_cache_type_is_blob_serializable(arr.element_type);
    case .STRUCT;
        st := cast(*Type_Info_Struct) info;
        highest_offset := -1;
        for member: st.members {
            if member.flags & .CONSTANT continue;
            if member.offset_in_bytes < 0 continue;
            if member.offset_in_bytes <= highest_offset continue;
            highest_offset = member.offset_in_bytes;
            if !geo_cache_type_is_blob_serializable(member.type) return false;
        }
        return true;
    case;
        return true;
    }
}

geo_cache_put_reflected :: (builder: *[..]u8, data: *void, info: *Type_Info) -> bool {
    assert(info != null);
    if info.type == {
    case .STRING;
        cache_put_string(builder, (cast(*string) data).*);
        return true;
    case .ARRAY;
        arr := cast(*Type_Info_Array) info;
        elem_size := arr.element_type.runtime_size;
        assert(elem_size >= 0, "Unsupported array element type in reflected cache put.");
        stride := elem_size;
        if arr.array_count == -1 {
            count := (cast(*s64) data).*;
            count_u32 := cast(u32) count;
            cache_put(builder, count_u32);
            data_ptr := (cast(**u8) (data + 8)).*;
            if count_u32 == 0 return true;
            if geo_cache_type_is_blob_serializable(arr.element_type) {
                offset := builder.count;
                byte_count := stride * cast(s64) count_u32;
                array_resize(builder, offset + byte_count);
                memcpy(builder.data + offset, data_ptr, byte_count);
                return true;
            }
            for 0..cast(s64) count_u32-1 {
                if !geo_cache_put_reflected(builder, data_ptr + it * stride, arr.element_type) return false;
            }
            return true;
        }

        if geo_cache_type_is_blob_serializable(arr.element_type) {
            offset := builder.count;
            byte_count := stride * arr.array_count;
            array_resize(builder, offset + byte_count);
            memcpy(builder.data + offset, data, byte_count);
            return true;
        }
        for 0..arr.array_count-1 {
            if !geo_cache_put_reflected(builder, data + it * stride, arr.element_type) return false;
        }
        return true;
    case .STRUCT;
        st := cast(*Type_Info_Struct) info;
        highest_offset := -1;
        for member: st.members {
            if member.flags & .CONSTANT continue;
            if member.offset_in_bytes < 0 continue;
            if member.offset_in_bytes <= highest_offset continue;
            highest_offset = member.offset_in_bytes;
            if !geo_cache_put_reflected(builder, data + member.offset_in_bytes, member.type) return false;
        }
        return true;
    case;
        offset := builder.count;
        array_resize(builder, offset + info.runtime_size);
        memcpy(builder.data + offset, data, info.runtime_size);
        return true;
    }
}

geo_cache_get_reflected :: (source: *string, data: *void, info: *Type_Info) -> bool {
    assert(info != null);
    if info.type == {
    case .STRING;
        return cache_get_string(source, cast(*string) data);
    case .ARRAY;
        arr := cast(*Type_Info_Array) info;
        elem_size := arr.element_type.runtime_size;
        assert(elem_size >= 0, "Unsupported array element type in reflected cache get.");
        stride := elem_size;
        if arr.array_count == -1 {
            count_u32: u32;
            if !cache_get(source, *count_u32) return false;
            count := cast(s64) count_u32;
            count_ptr := cast(*s64) data;
            data_ptr_ptr := cast(**u8) (data + 8);
            alloc_ptr := cast(*s64) (data + 16);
            count_ptr.* = count;
            data_ptr_ptr.* = null;
            alloc_ptr.* = count;
            if count == 0 return true;

            byte_count := stride * count;
            memory := cast(*u8) alloc(byte_count);
            assert(memory != null, "Reflected cache alloc failed.");
            memset(memory, 0, byte_count);
            data_ptr_ptr.* = memory;

            if geo_cache_type_is_blob_serializable(arr.element_type) {
                if source.count < byte_count return false;
                memcpy(memory, source.data, byte_count);
                source.data += byte_count;
                source.count -= byte_count;
                return true;
            }
            for 0..count-1 {
                if !geo_cache_get_reflected(source, memory + it * stride, arr.element_type) return false;
            }
            return true;
        }

        if geo_cache_type_is_blob_serializable(arr.element_type) {
            byte_count := stride * arr.array_count;
            if source.count < byte_count return false;
            memcpy(data, source.data, byte_count);
            source.data += byte_count;
            source.count -= byte_count;
            return true;
        }
        for 0..arr.array_count-1 {
            if !geo_cache_get_reflected(source, data + it * stride, arr.element_type) return false;
        }
        return true;
    case .STRUCT;
        st := cast(*Type_Info_Struct) info;
        highest_offset := -1;
        for member: st.members {
            if member.flags & .CONSTANT continue;
            if member.offset_in_bytes < 0 continue;
            if member.offset_in_bytes <= highest_offset continue;
            highest_offset = member.offset_in_bytes;
            if !geo_cache_get_reflected(source, data + member.offset_in_bytes, member.type) return false;
        }
        return true;
    case;
        if source.count < info.runtime_size return false;
        memcpy(data, source.data, info.runtime_size);
        source.data += info.runtime_size;
        source.count -= info.runtime_size;
        return true;
    }
}

Texture_Load_Result :: struct {
    texture_index: u32;
    map_mode_u: ai.TextureMapMode;
    map_mode_v: ai.TextureMapMode;
    texture_flags: u32;
}

resolve_scene_model_import_paths :: (model_paths: []string) -> [..]string {
    resolved: [..]string;
    resolved.allocator = temp;
    for model_paths {
        array_add(*resolved, resolve_scene_model_import_path(it));
    }
    return resolved;
}

resolve_scene_model_import_path :: (path: string) -> string {
    if !String.ends_with_nocase(path, ".blend") return path;
    return ensure_blend_scene_sidecar(path);
}

ensure_blend_scene_sidecar :: (blend_path: string) -> string {
    assert(file_exists(blend_path), "Blend source file does not exist: %", blend_path);
    output_path := tprint("%.peelscene", blend_path);

    blend_modtime, _, blend_exists := file_modtime_and_size(blend_path);
    output_modtime, _, output_exists := file_modtime_and_size(output_path);
    assert(blend_exists, "Blend source file does not exist: %", blend_path);

    if output_exists {
        sidecar_data, ok := File.read_entire_file(output_path);
        if ok {
            sidecar_source := sidecar_data;
            defer free(sidecar_data);
            header: PeelSceneFileHeader;
            if sidecar_source.count < size_of(PeelSceneFileHeader) ||
               !cache_get(*sidecar_source, *header) ||
               !header_magic_matches(header.magic, PEEL_SCENE_FILE_MAGIC) ||
               header.version != PEEL_SCENE_FILE_VERSION {
                output_exists = false;
            }
        }
        else {
            output_exists = false;
        }
    }

    if !output_exists || output_modtime < blend_modtime {
        workspace_root := find_workspace_root_for_cache();
        export_script := tprint("%/tools/blender_exporter/export_blend.sh", workspace_root);
        assert(file_exists(export_script), "Missing Blender export script: %", export_script);

        result, stdout, stderr, timeout_reached := Process_Module.run_command(
            export_script,
            blend_path,
            output_path,
            working_directory = workspace_root,
            capture_and_return_output = true,
            timeout_ms = 120000);
        assert(!timeout_reached, "Timed out exporting blend scene: %", blend_path);
        assert(result.type == .EXITED && result.exit_code == 0,
            "Blend export failed for %\nstdout:\n%\nstderr:\n%", blend_path, stdout, stderr);

        _, _, output_exists = file_modtime_and_size(output_path);
        assert(output_exists, "Blend export did not produce output: %", output_path);
    }

    return output_path;
}

blend_scene_remap_node_index :: (raw_index: s32, node_base: u32) -> s32 {
    if raw_index < 0 return -1;
    return cast(s32) node_base + raw_index;
}

header_magic_matches :: (magic: []u8, expected: string) -> bool {
    if magic.count != expected.count return false;
    for expected {
        if magic[it_index] != cast(u8) it return false;
    }
    return true;
}

load_peel_blender_scene_into_imported_scene :: (imported: *Imported_Scene, path: string) {
    report("Loading PEEL Blender scene: %", path);

    data, ok := File.read_entire_file(path);
    assert(ok, "Failed to read PEEL Blender scene: %", path);
    defer free(data);

    source := data;
    header: PeelSceneFileHeader;
    assert(cache_get(*source, *header), "PEEL Blender scene too small: %", path);
    assert(header_magic_matches(header.magic, PEEL_SCENE_FILE_MAGIC), "PEEL Blender scene magic mismatch: %", path);
    assert(header.version == PEEL_SCENE_FILE_VERSION,
        "PEEL Blender scene version mismatch for %: %", path, header.version);

    model_name: string;
    assert(cache_get_string(*source, *model_name), "Failed to read model name from %", path);

    material_base := cast(u32) imported.materials.count;
    mesh_base := cast(u32) imported.meshes.count;
    node_base := cast(u32) imported.nodes.count;
    node_mesh_ref_base := cast(u32) imported.node_mesh_refs.count;
    vertex_base := cast(u32) imported.vertices.count;
    index_base := cast(u32) imported.indices.count;

    repeat_address_mode := cast(u32) Gpu_Sampler_Desc.Address_Mode.REPEAT;

    for 0..cast(s64) header.material_count-1 {
        material_name: string;
        assert(cache_get_string(*source, *material_name), "Failed to read material name from %", path);
        material: PeelSceneFileMaterial;
        assert(cache_get(*source, *material), "Failed to read material color from %", path);
        if material_name.count != 0 free(material_name);
        array_add(*imported.materials, .{
            base_color_factor = .{
                material.base_color[0],
                material.base_color[1],
                material.base_color[2],
                material.base_color[3],
            },
            metallic_factor = material.metallic,
            roughness_factor = material.roughness,
            base_color_texture_index = SCENE_INVALID_TEXTURE_INDEX,
            opacity_texture_index = SCENE_INVALID_TEXTURE_INDEX,
            normal_texture_index = SCENE_INVALID_TEXTURE_INDEX,
            roughness_texture_index = SCENE_INVALID_TEXTURE_INDEX,
            ao_texture_index = SCENE_INVALID_TEXTURE_INDEX,
            alpha_mode = SCENE_ALPHA_MODE_OPAQUE,
            alpha_cutoff = 0.5,
            address_mode_u = repeat_address_mode,
            address_mode_v = repeat_address_mode,
        });
    }

    array_reserve(*imported.meshes, cast(s64) header.mesh_count);
    for 0..cast(s64) header.mesh_count-1 {
        mesh: PeelSceneFileMesh;
        assert(cache_get(*source, *mesh));
        array_add(*imported.meshes, .{
            base_vertex = vertex_base + mesh.base_vertex,
            vertex_count = mesh.vertex_count,
            first_index = index_base + mesh.first_index,
            index_count = mesh.index_count,
            material_index = material_base + mesh.material_index,
            skin_bone_start = 0,
            skin_bone_count = 0,
            morph_target_start = 0,
            morph_target_count = 0,
            lod_mesh_start = 0,
            lod_mesh_count = 0,
        });
    }

    for 0..cast(s64) header.node_count-1 {
        node_name: string;
        assert(cache_get_string(*source, *node_name), "Failed to read node name from %", path);

        node: PeelSceneFileNode;
        assert(cache_get(*source, *node));
        translation := Vector3.{node.translation[0], node.translation[1], node.translation[2]};
        rotation := Quaternion.{node.rotation[0], node.rotation[1], node.rotation[2], node.rotation[3]};
        scale := Vector3.{node.scale[0], node.scale[1], node.scale[2]};
        normalize_or_identity(*rotation);

        array_add(*imported.nodes, .{
            parent_index = blend_scene_remap_node_index(node.parent_index, node_base),
            first_child_index = blend_scene_remap_node_index(node.first_child_index, node_base),
            next_sibling_index = blend_scene_remap_node_index(node.next_sibling_index, node_base),
            first_mesh_ref = node_mesh_ref_base + node.first_mesh_ref,
            mesh_ref_count = node.mesh_ref_count,
            local = make_trs_matrix(translation, rotation, scale),
            world = Matrix4_Identity,
        });
        array_add(*imported.node_names, node_name);
        array_add(*imported.node_bind_transforms, .{
            translation = translation,
            rotation = rotation,
            scale = scale,
        });
    }

    for 0..cast(s64) header.node_mesh_ref_count-1 {
        mesh_ref: u32;
        assert(cache_get(*source, *mesh_ref));
        array_add(*imported.node_mesh_refs, mesh_base + mesh_ref);
    }

    array_reserve(*imported.vertices, cast(s64) header.vertex_count);
    for 0..cast(s64) header.vertex_count-1 {
        using file_vertex: PeelSceneFileVertex;
        assert(cache_get(*source, *file_vertex));
        array_add(*imported.vertices, .{
            position = { position[0], position[1], position[2], position[3] },
            normal = .{ normal[0], normal[1], normal[2], normal[3] },
            tangent = .{ tangent[0], tangent[1], tangent[2], tangent[3] },
            uv = .{ uv[0], uv[1] },
        });
    }

    array_reserve(*imported.indices, cast(s64) header.index_count);
    for 0..cast(s64) header.index_count-1 {
        index: u32;
        assert(cache_get(*source, *index));
        array_add(*imported.indices, vertex_base + index);
    }

    assert(source.count == 0, "Unexpected trailing bytes in %", path);

    compute_world_matrices(imported.nodes, node_base, header.node_count);
    for local_mesh_index: 0..cast(s64) header.mesh_count-1 {
        mesh_index := cast(s32) mesh_base + cast(s32) local_mesh_index;
        optimize_imported_mesh_vertex_fetch(imported, mesh_index, allow_compaction = false);
        build_static_mesh_lods(imported, mesh_index);
    }

    array_add(*imported.models, .{
        name = model_name,
        root_node_index = cast(s32) node_base,
        node_start = node_base,
        node_count = header.node_count,
        mesh_start = mesh_base,
        mesh_count = header.mesh_count,
        anim_clip_start = cast(u32) imported.anim_clips.count,
        anim_clip_count = 0,
    });
}

load_model_into_imported_scene :: (imported: *Imported_Scene, path: string) {
    if String.ends_with_nocase(path, ".peelscene") {
        load_peel_blender_scene_into_imported_scene(imported, path);
        return;
    }

    load_flags: ai.PostProcessSteps :
          .Triangulate | .JoinIdenticalVertices | .ImproveCacheLocality | .OptimizeMeshes
        | .GenUVCoords | .CalcTangentSpace | .FindInvalidData | .FindDegenerates | .RemoveRedundantMaterials
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
    mesh_name_to_index: Table(string, s32);
    defer Hash_Table.deinit(*node_name_to_index);
    defer Hash_Table.deinit(*mesh_name_to_index);

    scene_materials: []*ai.Material = .{ scene.mNumMaterials, scene.mMaterials };
    for scene_materials {
        base_color_load := load_material_texture(imported, scene, it, model_dir, path,
            ai.TextureType.[.BASE_COLOR, .DIFFUSE], default_texture_index = 0);
        opacity_texture_index := load_material_texture(imported, scene, it, model_dir, path,
            ai.TextureType.[.OPACITY], default_texture_index = SCENE_INVALID_TEXTURE_INDEX).texture_index;
        normal_texture_index := load_material_texture(imported, scene, it, model_dir, path,
            ai.TextureType.[.NORMALS], default_texture_index = SCENE_INVALID_TEXTURE_INDEX).texture_index;
        roughness_texture_index := load_material_texture(imported, scene, it, model_dir, path,
            ai.TextureType.[.DIFFUSE_ROUGHNESS, .UNKNOWN], default_texture_index = SCENE_INVALID_TEXTURE_INDEX).texture_index;
        ao_texture_index := load_material_texture(imported, scene, it, model_dir, path,
            ai.TextureType.[.AMBIENT_OCCLUSION, .LIGHTMAP], default_texture_index = SCENE_INVALID_TEXTURE_INDEX).texture_index;
        alpha_mode, alpha_cutoff := detect_material_alpha_mode(scene, it, imported.*, base_color_load.texture_index, opacity_texture_index, base_color_load.texture_flags);
        array_add(*imported.materials, .{
            base_color_factor = .{1.0, 1.0, 1.0, 1.0},
            metallic_factor = 0.0,
            roughness_factor = 0.82,
            base_color_texture_index = base_color_load.texture_index,
            opacity_texture_index = opacity_texture_index,
            normal_texture_index = normal_texture_index,
            roughness_texture_index = roughness_texture_index,
            ao_texture_index = ao_texture_index,
            alpha_mode = alpha_mode,
            alpha_cutoff = alpha_cutoff,
            address_mode_u = cast(u32) base_color_load.map_mode_u,
            address_mode_v = cast(u32) base_color_load.map_mode_v,
        });
    }

    root_node_index := append_ai_node_recursive(imported, scene, scene.mRootNode, -1, mesh_start, *node_name_to_index);
    compute_world_matrices(imported.nodes, node_start, cast(u32) imported.nodes.count - node_start);

    scene_meshes := ai.meshes(scene);
    for scene_meshes {
        append_ai_mesh(imported, it, material_start, *node_name_to_index, *mesh_name_to_index);
    }

    for anim, anim_index: ai.animations(scene) {
        append_ai_animation(imported, anim, *node_name_to_index, *mesh_name_to_index, model_name, cast(s32) anim_index);
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
    mesh_name_to_index: *Table(string, s32),
) {
    base_vertex := cast(u32) imported.vertices.count;
    num_vertices := cast(s64) mesh.mNumVertices;

    normals := cast(*Vector3) mesh.mNormals;
    tangents := cast(*Vector3) mesh.mTangents;
    bitangents := cast(*Vector3) mesh.mBitangents;
    tex_coords := mesh.mTextureCoords[0];

    for 0..num_vertices-1 {
        pos := cast,force(Vector3) mesh.mVertices[it];
        normal := Vector3.{0.0, 1.0, 0.0};
        if normals != null normal = normals[it];
        tangent4 := Vector4.{1.0, 0.0, 0.0, 1.0};
        if tangents != null {
            tangent := tangents[it];
            tangent_vec := Vector3.{tangent.x, tangent.y, tangent.z};
            normalize(*tangent_vec, fallback = .{1.0, 0.0, 0.0});
            tangent_sign := 1.0;
            if bitangents != null {
                bitangent := Vector3.{bitangents[it].x, bitangents[it].y, bitangents[it].z};
                tangent_sign = ifx dot(cross(normal, tangent_vec), bitangent) < 0.0 then -1.0 else 1.0;
            }
            tangent4 = .{tangent_vec.x, tangent_vec.y, tangent_vec.z, tangent_sign};
        }

        uv := Vector2.{0.0, 0.0};
        if tex_coords != null {
            uv3 := tex_coords[it];
            uv = .{uv3.x, uv3.y};
        }

        array_add(*imported.vertices, .{
            position = .{pos.x, pos.y, pos.z, 1.0},
            normal = .{normal.x, normal.y, normal.z, 0.0},
            tangent = tangent4,
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

                vertex := *imported.vertices[base_vertex + id];
                assign_top4_bone_weight(vertex, cast(float) local_bone_index, vertex_weight.mWeight, nth_bone);
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
    morph_target_start := cast(u32) imported.morph_targets.count;
    if mesh.mNumAnimMeshes > 0 {
        for anim_mesh, local_target_index: ai.anim_meshes(mesh) {
            assert(anim_mesh.mNumVertices == mesh.mNumVertices, "Anim mesh vertex count mismatch for mesh '%'.", ai.to_string(mesh.mName));
            vertex_delta_start := cast(u32) imported.morph_vertex_deltas.count;
            for vertex_offset: 0..num_vertices-1 {
                delta: Scene_Morph_Vertex_Delta;
                if anim_mesh.mVertices != null {
                    base_pos := mesh.mVertices[vertex_offset];
                    target_pos := anim_mesh.mVertices[vertex_offset];
                    delta.position = .{target_pos.x - base_pos.x, target_pos.y - base_pos.y, target_pos.z - base_pos.z, 0.0};
                }
                if anim_mesh.mNormals != null && mesh.mNormals != null {
                    base_normal := mesh.mNormals[vertex_offset];
                    target_normal := anim_mesh.mNormals[vertex_offset];
                    delta.normal = .{target_normal.x - base_normal.x, target_normal.y - base_normal.y, target_normal.z - base_normal.z, 0.0};
                }
                if anim_mesh.mTangents != null && mesh.mTangents != null {
                    base_tangent := mesh.mTangents[vertex_offset];
                    target_tangent := anim_mesh.mTangents[vertex_offset];
                    delta.tangent = .{target_tangent.x - base_tangent.x, target_tangent.y - base_tangent.y, target_tangent.z - base_tangent.z, 0.0};
                }
                array_add(*imported.morph_vertex_deltas, delta);
            }
            array_add(*imported.morph_targets, .{
                vertex_delta_start = vertex_delta_start,
                vertex_delta_count = cast(u32) num_vertices,
                default_weight = anim_mesh.mWeight,
            });
            morph_target_name := ai.to_string(anim_mesh.mName);
            if morph_target_name.count == 0 morph_target_name = tprint("morph_%", local_target_index);
            array_add(*imported.morph_target_names, copy_string(morph_target_name));

            if local_target_index == 0 && ai.to_string(mesh.mName).count > 0 {
                table_set(mesh_name_to_index, ai.to_string(mesh.mName), cast(s32) imported.meshes.count);
            }
        }
    }

    array_add(*imported.meshes, .{
        base_vertex = base_vertex,
        vertex_count = cast(u32) num_vertices,
        first_index = first_index,
        index_count = cast(u32) imported.indices.count - first_index,
        material_index = material_index,
        skin_bone_start = skin_bone_start,
        skin_bone_count = skin_bone_count,
        morph_target_start = morph_target_start,
        morph_target_count = cast(u32) imported.morph_targets.count - morph_target_start,
    });

    mesh_index := cast(s32) imported.meshes.count - 1;
    optimize_imported_mesh_vertex_fetch(imported, mesh_index, allow_compaction = true);
    build_static_mesh_lods(imported, mesh_index);

    if mesh.mNumAnimMeshes == 0 && ai.to_string(mesh.mName).count > 0 {
        table_set(mesh_name_to_index, ai.to_string(mesh.mName), cast(s32) imported.meshes.count - 1);
    }
}

optimize_imported_mesh_vertex_fetch :: (imported: *Imported_Scene, mesh_index: s32, allow_compaction: bool) {
    if mesh_index < 0 || mesh_index >= imported.meshes.count return;
    mesh := imported.meshes[mesh_index];
    if mesh.vertex_count == 0 || mesh.index_count == 0 return;
    if allow_compaction {
        if mesh.base_vertex + mesh.vertex_count != imported.vertices.count return;
        if mesh.first_index + mesh.index_count != imported.indices.count return;
    }

    local_indices := NewArray(mesh.index_count, u32);
    remapped_indices := NewArray(mesh.index_count, u32);
    remap := NewArray(mesh.vertex_count, u32);
    remapped_vertices := NewArray(mesh.vertex_count, Scene_Vertex);
    defer {
        array_free(local_indices);
        array_free(remapped_indices);
        array_free(remap);
        array_free(remapped_vertices);
    }

    for local_index: 0..cast(s64) mesh.index_count-1 {
        local_indices[local_index] = imported.indices[mesh.first_index + local_index] - mesh.base_vertex;
    }

    new_vertex_count := meshopt.optimizeVertexFetchRemap(
        remap.data,
        local_indices.data,
        cast(u64) mesh.index_count,
        cast(u64) mesh.vertex_count);
    if new_vertex_count == 0 return;
    if !allow_compaction && new_vertex_count != mesh.vertex_count return;

    meshopt.remapVertexBuffer(
        remapped_vertices.data,
        imported.vertices.data + mesh.base_vertex,
        cast(u64) mesh.vertex_count,
        cast(u64) size_of(Scene_Vertex),
        remap.data);
    meshopt.remapIndexBuffer(
        remapped_indices.data,
        local_indices.data,
        cast(u64) mesh.index_count,
        remap.data);

    copy_vertex_count := ifx allow_compaction then cast(s64) new_vertex_count else cast(s64) mesh.vertex_count;
    memcpy(imported.vertices.data + mesh.base_vertex, remapped_vertices.data, copy_vertex_count * size_of(Scene_Vertex));
    if allow_compaction {
        array_resize(*imported.vertices, cast(s64) mesh.base_vertex + cast(s64) new_vertex_count);
    }

    for local_index: 0..cast(s64) mesh.index_count-1 {
        imported.indices[mesh.first_index + local_index] = mesh.base_vertex + remapped_indices[local_index];
    }

    if allow_compaction && mesh.morph_target_count > 0 {
        remapped_deltas := NewArray(mesh.vertex_count, Scene_Morph_Vertex_Delta);
        defer array_free(remapped_deltas);

        dest_cursor := imported.morph_targets[mesh.morph_target_start].vertex_delta_start;
        for target_index: 0..cast(s64) mesh.morph_target_count-1 {
            target := *imported.morph_targets[mesh.morph_target_start + target_index];
            assert(target.vertex_delta_count == mesh.vertex_count, "Unexpected morph delta count for mesh % target %: expected %, got %.", mesh_index, target_index, mesh.vertex_count, target.vertex_delta_count);
            meshopt.remapVertexBuffer(
                remapped_deltas.data,
                imported.morph_vertex_deltas.data + target.vertex_delta_start,
                cast(u64) mesh.vertex_count,
                cast(u64) size_of(Scene_Morph_Vertex_Delta),
                remap.data);
            memcpy(imported.morph_vertex_deltas.data + dest_cursor, remapped_deltas.data, cast(s64) new_vertex_count * size_of(Scene_Morph_Vertex_Delta));
            target.vertex_delta_start = dest_cursor;
            target.vertex_delta_count = cast(u32) new_vertex_count;
            dest_cursor += cast(u32) new_vertex_count;
        }
        array_resize(*imported.morph_vertex_deltas, dest_cursor);
    }

    if allow_compaction {
        mesh.vertex_count = cast(u32) new_vertex_count;
    }
    imported.meshes[mesh_index] = mesh;
}

assign_top4_bone_weight :: (vertex: *Scene_Vertex, bone_index: float, weight: float, nth_bone: u32) {
    if weight <= 0.0 return;

    if nth_bone < 4 {
        vertex.bone_indices.component[nth_bone] = bone_index;
        vertex.bone_weights.component[nth_bone] = weight;
        return;
    }

    lowest_slot: s64 = 0;
    lowest_weight := vertex.bone_weights.component[0];
    for i: 1..3 {
        if vertex.bone_weights.component[i] < lowest_weight {
            lowest_weight = vertex.bone_weights.component[i];
            lowest_slot = i;
        }
    }

    if weight <= lowest_weight return;
    vertex.bone_indices.component[lowest_slot] = bone_index;
    vertex.bone_weights.component[lowest_slot] = weight;
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

build_static_mesh_lods :: (imported: *Imported_Scene, mesh_index: s32) {
    if mesh_index < 0 || mesh_index >= imported.meshes.count return;
    mesh := imported.meshes[mesh_index];
    if mesh.skin_bone_count != 0 return;
    if mesh.morph_target_count != 0 return;
    if mesh.index_count < 192 return;
    if !validate_imported_mesh_indices(imported, mesh, require_mesh_local_range = true) {
        log_error("Skipping LOD build for mesh % due to invalid source indices. first_index=% index_count=% base_vertex=% vertex_count=%",
            mesh_index, mesh.first_index, mesh.index_count, mesh.base_vertex, mesh.vertex_count);
        return;
    }
    source_triangle_count := cast(u64) mesh.index_count / 3;

    source_indices := NewArray(mesh.index_count, u32);
    defer array_free(source_indices);
    for local_index: 0..cast(s64) mesh.index_count-1 {
        source_indices[local_index] = imported.indices[mesh.first_index + local_index] - mesh.base_vertex;
    }
    vertex_positions := cast(*float)(imported.vertices.data + mesh.base_vertex);
    vertex_positions_stride := cast(u64) size_of(Scene_Vertex);
    simplify_attributes := NewArray(mesh.vertex_count, LOD_Simplify_Attributes);
    defer array_free(simplify_attributes);
    for i: 0..cast(s64) mesh.vertex_count-1 {
        vertex := imported.vertices[mesh.base_vertex + cast(u32) i];
        simplify_attributes[i] = .{
            uv = .[vertex.uv.x, vertex.uv.y],
            normal = .[vertex.normal.x, vertex.normal.y, vertex.normal.z],
            tangent = .[vertex.tangent.x, vertex.tangent.y, vertex.tangent.z, vertex.tangent.w],
        };
    }
    lod_mesh_start := cast(u32) imported.meshes.count;
    lod_mesh_count: u32;

    for ratio, lod_i: STATIC_MESH_LOD_TARGET_RATIOS {
        ratio_triangle_count := cast(u64) max(12.0, floor(cast(float) source_triangle_count * ratio));
        target_triangle_count := min(ratio_triangle_count, cast(u64) STATIC_MESH_LOD_TARGET_TRIANGLE_CAPS[lod_i]);
        target_index_count := target_triangle_count * 3;
        if target_index_count >= cast(u64) source_indices.count continue;

        simplified := NewArray(source_indices.count, u32);
        defer array_free(simplified);
        result_error: float;
        simplified_count: u64;
        target_error := STATIC_MESH_LOD_TARGET_ERRORS[lod_i];
        for attempt: 0..5 {
            simplified_count = meshopt.simplifyWithAttributes(
                simplified.data,
                source_indices.data,
                cast(u64) source_indices.count,
                vertex_positions,
                cast(u64) mesh.vertex_count,
                vertex_positions_stride,
                cast(*float) simplify_attributes.data,
                cast(u64) size_of(LOD_Simplify_Attributes),
                cast(*float) STATIC_MESH_LOD_ATTRIBUTE_WEIGHTS.data,
                cast(u64) STATIC_MESH_LOD_ATTRIBUTE_WEIGHTS.count,
                null,
                target_index_count,
                target_error,
                STATIC_MESH_LOD_SIMPLIFY_OPTIONS,
                *result_error);
            if simplified_count <= target_index_count break;
            target_error = min(target_error * 1.8 + 0.01, 1.0);
        }
        if simplified_count < 36 continue;
        simplified_count = (simplified_count / 3) * 3;
        if simplified_count < 36 continue;
        if simplified_count >= cast(u64) source_indices.count continue;

        optimized := NewArray(cast(s64) simplified_count, u32);
        defer array_free(optimized);
        meshopt.optimizeVertexCache(
            optimized.data,
            simplified.data,
            simplified_count,
            cast(u64) mesh.vertex_count);

        invalid_lod := false;
        for 0..cast(s64) simplified_count-1 {
            if optimized[it] >= mesh.vertex_count {
                invalid_lod = true;
                log_error("Skipping invalid LOD % for mesh %: optimized index % out of local vertex range %.",
                    lod_i, mesh_index, optimized[it], mesh.vertex_count);
                break;
            }
        }
        if invalid_lod continue;

        lod_first_index := cast(u32) imported.indices.count;
        for 0..cast(s64) simplified_count-1 {
            array_add(*imported.indices, optimized[it] + mesh.base_vertex);
        }

        array_add(*imported.meshes, .{
            base_vertex = mesh.base_vertex,
            vertex_count = mesh.vertex_count,
            first_index = lod_first_index,
            index_count = cast(u32) simplified_count,
            material_index = mesh.material_index,
            skin_bone_start = 0,
            skin_bone_count = 0,
            morph_target_start = 0,
            morph_target_count = 0,
            lod_mesh_start = 0,
            lod_mesh_count = 0,
        });
        lod_mesh_count += 1;
    }

    if lod_mesh_count > 0 {
        imported.meshes[mesh_index].lod_mesh_start = lod_mesh_start;
        imported.meshes[mesh_index].lod_mesh_count = lod_mesh_count;
    }
}

SCENE_GEO_MESHLET_MAX_VERTICES :: 64;
SCENE_GEO_MESHLET_MAX_TRIANGLES :: 124;

build_scene_meshlets :: (
    imported: *Imported_Scene,
) -> [..]Scene_Meshlet_Mesh, [..]Scene_Meshlet, [..]u32, [..]u32, [..]Vector4, u32 {
    meshlet_meshes: [..]Scene_Meshlet_Mesh;
    meshlets: [..]Scene_Meshlet;
    meshlet_vertices: [..]u32;
    raw_meshlet_triangles: [..]u8;
    packed_meshlet_triangles: [..]u32;
    meshlet_bounds: [..]Vector4;
    max_meshlet_count: u32;
    defer array_free(raw_meshlet_triangles);

    array_resize(*meshlet_meshes, imported.meshes.count);

    for *mesh_src, mesh_index: imported.meshes {
        if !validate_imported_mesh_indices(imported, mesh_src, require_mesh_local_range = true) {
            log_error("Skipping meshlet build for invalid mesh %. first_index=% index_count=% base_vertex=% vertex_count=%",
                mesh_index, mesh_src.first_index, mesh_src.index_count, mesh_src.base_vertex, mesh_src.vertex_count);
            continue;
        }
        meshlet_meshes[mesh_index].bounds_center_radius = compute_imported_mesh_bounds_sphere(imported, mesh_src);
        if mesh_src.index_count < 3 || mesh_src.vertex_count == 0 {
            continue;
        }
        local_indices := NewArray(mesh_src.index_count, u32);
        optimized_indices := NewArray(mesh_src.index_count, u32);
        defer {
            array_free(local_indices);
            array_free(optimized_indices);
        }

        for local_index: 0..cast(s64) mesh_src.index_count-1 {
            local_indices[local_index] = imported.indices[mesh_src.first_index + local_index] - mesh_src.base_vertex;
        }

        meshopt.optimizeVertexCache(
            optimized_indices.data,
            local_indices.data,
            cast(u64) mesh_src.index_count,
            cast(u64) mesh_src.vertex_count);

        max_meshlets := meshopt.buildMeshletsBound(
            cast(u64) mesh_src.index_count,
            SCENE_GEO_MESHLET_MAX_VERTICES,
            SCENE_GEO_MESHLET_MAX_TRIANGLES);
        temp_meshlets := NewArray(cast(s64) max_meshlets, meshopt.Meshlet);
        temp_meshlet_vertices := NewArray(cast(s64) max_meshlets * SCENE_GEO_MESHLET_MAX_VERTICES, u32);
        temp_meshlet_triangles := NewArray(cast(s64) max_meshlets * SCENE_GEO_MESHLET_MAX_TRIANGLES * 3, u8);
        defer {
            array_free(temp_meshlets);
            array_free(temp_meshlet_vertices);
            array_free(temp_meshlet_triangles);
        }

        built_meshlet_count := meshopt.buildMeshletsScan(
            temp_meshlets.data,
            temp_meshlet_vertices.data,
            temp_meshlet_triangles.data,
            optimized_indices.data,
            cast(u64) mesh_src.index_count,
            cast(u64) mesh_src.vertex_count,
            SCENE_GEO_MESHLET_MAX_VERTICES,
            SCENE_GEO_MESHLET_MAX_TRIANGLES);

        meshlet_start := cast(u32) meshlets.count;
        vertex_positions := cast(*float) (imported.vertices.data + mesh_src.base_vertex);

        for temp_i: 0..cast(s64) built_meshlet_count-1 {
            temp_meshlet := temp_meshlets[temp_i];
            if temp_meshlet.triangle_count == 0 || temp_meshlet.vertex_count == 0 continue;

            meshopt.optimizeMeshletLevel(
                temp_meshlet_vertices.data + temp_meshlet.vertex_offset,
                cast(u64) temp_meshlet.vertex_count,
                temp_meshlet_triangles.data + temp_meshlet.triangle_offset,
                cast(u64) temp_meshlet.triangle_count,
                SCENE_GEO_MESHLET_ENCODE_LEVEL);

            vertex_offset := cast(u32) meshlet_vertices.count;
            triangle_offset := cast(u32) raw_meshlet_triangles.count;

            for local_vertex: 0..cast(s64) temp_meshlet.vertex_count-1 {
                local_vertex_index := temp_meshlet_vertices[temp_meshlet.vertex_offset + local_vertex];
                array_add(*meshlet_vertices, local_vertex_index + mesh_src.base_vertex);
            }

            triangle_byte_count := cast(s64) temp_meshlet.triangle_count * 3;
            for triangle_byte: 0..triangle_byte_count-1 {
                array_add(*raw_meshlet_triangles, temp_meshlet_triangles[temp_meshlet.triangle_offset + triangle_byte]);
            }

            bounds := meshopt.computeMeshletBounds(
                temp_meshlet_vertices.data + temp_meshlet.vertex_offset,
                temp_meshlet_triangles.data + temp_meshlet.triangle_offset,
                cast(u64) temp_meshlet.triangle_count,
                vertex_positions,
                cast(u64) mesh_src.vertex_count,
                cast(u64) size_of(Scene_Vertex));

            array_add(*meshlets, .{
                vertex_offset = vertex_offset,
                triangle_offset = triangle_offset,
                vertex_count = temp_meshlet.vertex_count,
                triangle_count = temp_meshlet.triangle_count,
            });
            array_add(*meshlet_bounds, .{
                bounds.center[0],
                bounds.center[1],
                bounds.center[2],
                bounds.radius,
            });
        }

        meshlet_count := cast(u32) meshlets.count - meshlet_start;
        meshlet_meshes[mesh_index].meshlet_start = meshlet_start;
        meshlet_meshes[mesh_index].meshlet_count = meshlet_count;
        max_meshlet_count = max(max_meshlet_count, meshlet_count);
    }

    for *meshlet: meshlets {
        raw_triangle_offset := meshlet.triangle_offset;
        meshlet.triangle_offset = cast(u32) packed_meshlet_triangles.count;
        for tri_i: 0..cast(s64) meshlet.triangle_count-1 {
            raw_tri_offset := cast(s64) raw_triangle_offset + tri_i * 3;
            p0 := cast(u32) raw_meshlet_triangles[raw_tri_offset + 0];
            p1 := cast(u32) raw_meshlet_triangles[raw_tri_offset + 1];
            p2 := cast(u32) raw_meshlet_triangles[raw_tri_offset + 2];
            array_add(*packed_meshlet_triangles, p0 | (p1 << 8) | (p2 << 16));
        }
    }

    return meshlet_meshes, meshlets, meshlet_vertices, packed_meshlet_triangles, meshlet_bounds, max_meshlet_count;
}

compute_imported_mesh_bounds_sphere :: (imported: *Imported_Scene, mesh: *Scene_Mesh) -> Vector4 {
    min_p := Vector3.{1000000.0, 1000000.0, 1000000.0};
    max_p := Vector3.{-1000000.0, -1000000.0, -1000000.0};

    for index_offset: 0..mesh.index_count-1 {
        vertex_index := imported.indices[mesh.first_index + index_offset];
        p := imported.vertices[vertex_index].position.xyz;
        min_p.x = min(min_p.x, p.x);
        min_p.y = min(min_p.y, p.y);
        min_p.z = min(min_p.z, p.z);
        max_p.x = max(max_p.x, p.x);
        max_p.y = max(max_p.y, p.y);
        max_p.z = max(max_p.z, p.z);
    }

    center := (min_p + max_p) * 0.5;
    radius: float;
    for index_offset: 0..mesh.index_count-1 {
        vertex_index := imported.indices[mesh.first_index + index_offset];
        p := imported.vertices[vertex_index].position.xyz;
        radius = max(radius, length(p - center));
    }

    return .{center.x, center.y, center.z, radius};
}

validate_imported_mesh_indices :: (imported: *Imported_Scene, mesh: Scene_Mesh, require_mesh_local_range: bool = false) -> bool {
    if mesh.first_index + mesh.index_count > imported.indices.count return false;
    if mesh.base_vertex + mesh.vertex_count > imported.vertices.count return false;

    mesh_vertex_end := mesh.base_vertex + mesh.vertex_count;
    for index_offset: 0..mesh.index_count-1 {
        vertex_index := imported.indices[mesh.first_index + index_offset];
        if vertex_index >= imported.vertices.count return false;
        if require_mesh_local_range {
            if vertex_index < mesh.base_vertex return false;
            if vertex_index >= mesh_vertex_end return false;
        }
    }

    return true;
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
    array_add(*imported.node_names, copy_string(ai.to_string(ai_node.mName)));
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

append_ai_animation :: (imported: *Imported_Scene, anim: *ai.Animation, node_name_to_index: *Table(string, s32), mesh_name_to_index: *Table(string, s32), model_name: string, anim_index: s32) {
    clip_name := ai.to_string(anim.mName);
    if clip_name.count == 0 clip_name = tprint("%_anim_%", model_name, anim_index);

    clip: Scene_Anim_Clip;
    clip.name = copy_string(clip_name);
    clip.duration = cast(float) anim.mDuration;
    clip.ticks_per_second = ifx anim.mTicksPerSecond != 0 then cast(float) anim.mTicksPerSecond else 25.0;
    clip.channel_start = cast(u32) imported.anim_channels.count;
    clip.morph_channel_start = cast(u32) imported.anim_morph_channels.count;

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
    for morph_channel: ai.morph_channels(anim) {
        mesh_name := ai.to_string(morph_channel.mName);
        found, mesh_index := table_find(mesh_name_to_index, mesh_name);
        if !found continue;

        mesh := imported.meshes[mesh_index];
        for local_target_index: 0..cast(s64) mesh.morph_target_count-1 {
            channel_entry: Scene_Anim_Morph_Channel;
            channel_entry.morph_target_index = mesh.morph_target_start + cast(u32) local_target_index;
            channel_entry.key_start = cast(u32) imported.anim_morph_keys.count;

            for key_index: 0..cast(s64) morph_channel.mNumKeys-1 {
                key := morph_channel.mKeys[key_index];
                value: float = 0.0;
                for value_index: 0..cast(s64) key.mNumValuesAndWeights-1 {
                    if key.mValues[value_index] != cast(u32) local_target_index continue;
                    value = cast(float) key.mWeights[value_index];
                    break;
                }
                array_add(*imported.anim_morph_keys, .{
                    time = cast(float) key.mTime,
                    value = value,
                });
            }
            channel_entry.key_count = cast(u32) imported.anim_morph_keys.count - channel_entry.key_start;
            if channel_entry.key_count > 0 {
                array_add(*imported.anim_morph_channels, channel_entry);
            }
        }
    }
    clip.morph_channel_count = cast(u32) imported.anim_morph_channels.count - clip.morph_channel_start;
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

load_material_texture :: (
    imported: *Imported_Scene,
    scene: *ai.Scene,
    material: *ai.Material,
    model_dir: string,
    model_path: string,
    texture_types: []ai.TextureType,
    default_texture_index: u32,
) -> Texture_Load_Result {
    for texture_types {
        if ai.GetMaterialTextureCount(material, it) == 0 continue;

        path: ai.String;
        map_mode := ai.TextureMapMode.Wrap;
        res := ai.GetMaterialTexture(material, it, 0, *path, null, null, null, null, *map_mode, null);
        if res != .SUCCESS continue;

        resolved := resolve_assimp_texture_key(scene, model_dir, model_path, ai.to_string(path));
        defer if resolved.count != 0 free(resolved);
        return .{
            texture_index = get_or_load_texture(imported, scene, resolved, ai.to_string(path)),
            map_mode_u = map_mode,
            map_mode_v = map_mode,
            texture_flags = flags_from_material_texture(material, it),
        };
    }

    return .{
        texture_index = default_texture_index,
        map_mode_u = .Wrap,
        map_mode_v = .Wrap,
        texture_flags = 0,
    };
}

flags_from_material_texture :: (material: *ai.Material, texture_type: ai.TextureType) -> u32 {
    path: ai.String;
    flags: u32 = 0;
    res := ai.GetMaterialTexture(material, texture_type, 0, *path, null, null, null, null, null, *flags);
    if res != .SUCCESS return 0;
    return flags;
}

resolve_assimp_texture_key :: (scene: *ai.Scene, model_dir: string, model_path: string, path: string) -> string {
    _ = scene;
    if path.count > 0 && path[0] == #char "*" {
        return sprint("%#%", model_path, path);
    }

    normalized_path := String.replace(path, "\\", "/",, temp);
    if normalized_path.count == 0 normalized_path = path;

    if normalized_path.count > 0 && normalized_path[0] == #char "/" {
        return copy_string(normalized_path);
    }

    model_file_dir := directory_parent(model_path);
    candidate_dirs := string.[
        model_dir,
        model_file_dir,
        directory_parent(model_file_dir),
    ];
    for candidate_dirs {
        dir := trim_trailing_slashes(it);
        if dir.count == 0 continue;

        candidate := String.path_join(dir, normalized_path);
        if file_exists(candidate) return copy_string(candidate);
    }

    return copy_string(String.path_join(model_dir, normalized_path));
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
            return .{key = copy_string(resolved_key), width = cast(u32) width, height = cast(u32) height, pixels = rgba, has_alpha = texture_pixels_have_alpha(rgba)};
        }

        raw_pixels := cast(*u8) embedded.pcData;
        byte_count := cast(s64) embedded.mWidth * cast(s64) embedded.mHeight * 4;
        rgba := bgra_to_rgba(.{count = byte_count, data = raw_pixels});
        return .{key = copy_string(resolved_key), width = embedded.mWidth, height = embedded.mHeight, pixels = rgba, has_alpha = texture_pixels_have_alpha(rgba)};
    }

    width, height, channels: s32 = 0;
    pixels := stbi_load(temp_c_string(resolved_key), *width, *height, *channels, 4);
    defer stbi_image_free(pixels);
    assert(pixels != null && width > 0 && height > 0, "Failed to load texture %", resolved_key);
    rgba := copy_bytes(cast([]u8) .{count = width * height * 4, data = pixels});
    return .{key = copy_string(resolved_key), width = cast(u32) width, height = cast(u32) height, pixels = rgba, has_alpha = texture_pixels_have_alpha(rgba)};
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
        has_alpha = false,
    });
}

SCENE_ALPHA_MODE_OPAQUE :: 0;
SCENE_ALPHA_MODE_MASK   :: 1;

texture_pixels_have_alpha :: (pixels: []u8) -> bool {
    if pixels.count < 4 return false;
    alpha_index := cast(s64) 3;
    while alpha_index < pixels.count {
        if pixels[alpha_index] < 250 return true;
        alpha_index += 4;
    }
    return false;
}

material_property_key_contains :: (material: *ai.Material, pattern: string) -> bool {
    for prop_index: 0..cast(s64) material.mNumProperties-1 {
        prop := material.mProperties[prop_index];
        if prop == null continue;
        key := ai.to_string(prop.mKey);
        if String.find_index_from_left(key, pattern) >= 0 return true;
    }
    return false;
}

material_property_float_lt :: (material: *ai.Material, pattern: string, limit: float) -> bool {
    for prop_index: 0..cast(s64) material.mNumProperties-1 {
        prop := material.mProperties[prop_index];
        if prop == null continue;
        key := ai.to_string(prop.mKey);
        if String.find_index_from_left(key, pattern) < 0 continue;
        if prop.mType == .PTI_Float || prop.mType == .PTI_Double {
            value := cast(*float) prop.mData;
            if value != null && value.* < limit return true;
        }
    }
    return false;
}

detect_material_alpha_mode :: (
    scene: *ai.Scene,
    material: *ai.Material,
    imported: Imported_Scene,
    base_color_texture_index: u32,
    opacity_texture_index: u32,
    base_color_texture_flags: u32,
) -> u32, float {
    _ = scene;
    alpha_cutoff := 0.5;
    if opacity_texture_index != SCENE_INVALID_TEXTURE_INDEX return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if base_color_texture_index == SCENE_INVALID_TEXTURE_INDEX return SCENE_ALPHA_MODE_OPAQUE, alpha_cutoff;
    if base_color_texture_index >= imported.textures.count return SCENE_ALPHA_MODE_OPAQUE, alpha_cutoff;

    base_texture := imported.textures[base_color_texture_index];
    if !base_texture.has_alpha return SCENE_ALPHA_MODE_OPAQUE, alpha_cutoff;

    if (base_color_texture_flags & cast(u32) ai.TextureFlags.UseAlpha) != 0 return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if material_property_float_lt(material, "opacity", 0.999) return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if material_property_float_lt(material, "transparent", 0.999) return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if material_property_key_contains(material, "opacity") return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if material_property_key_contains(material, "transparent") return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
    if material_property_key_contains(material, "alpha") return SCENE_ALPHA_MODE_MASK, alpha_cutoff;

    return SCENE_ALPHA_MODE_MASK, alpha_cutoff;
}

create_texture_from_rgba8 :: (pixels: []u8, width: u32, height: u32) -> Gpu_Texture, Gpu_Texture_View {
    result, texture := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .R8G8B8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS && texture != 0, "Scene_Geo texture creation failed.");
    /*

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
    */
    gpu_copy_to_texture(texture, pixels.data);
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

trim_trailing_slashes :: (path: string) -> string {
    result := path;
    while result.count > 0 && (result[result.count-1] == #char "/" || result[result.count-1] == #char "\\") {
        result.count -= 1;
    }
    return result;
}

directory_parent :: (path: string) -> string {
    trimmed := trim_trailing_slashes(path);
    if trimmed.count == 0 return trimmed;
    return trim_trailing_slashes(String.path_strip_filename(trimmed));
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

address_mode_from_assimp :: (mode: ai.TextureMapMode) -> Gpu_Sampler_Desc.Address_Mode {
    if mode == {
    case .Wrap; return .REPEAT;
    case .Mirror; return .MIRRORED_REPEAT;
    case .Clamp; return .CLAMP_TO_EDGE;
    case .Decal; return .CLAMP_TO_EDGE;
    }
    return .CLAMP_TO_EDGE;
}

scene_geo_get_or_create_sampler :: (geo: *Scene_Geo, mode_u: Gpu_Sampler_Desc.Address_Mode, mode_v: Gpu_Sampler_Desc.Address_Mode) -> Gpu_Sampler {
    for geo.samplers {
        if it.sampler == 0 continue;
        if it.mode_u == cast(u32) mode_u && it.mode_v == cast(u32) mode_v {
            return it.sampler;
        }
    }

    sampler := gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = mode_u,
        address_mode_v = mode_v,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(sampler != 0, "Scene_Geo sampler creation failed.");
    array_add(*geo.samplers, .{
        sampler = sampler,
        mode_u = cast(u32) mode_u,
        mode_v = cast(u32) mode_v,
    });
    return sampler;
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
#import "File_Utilities";
#import "Hash";
meshopt :: #import "meshoptimizer";
#import "Math";
Process_Module :: #import "Process";
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
