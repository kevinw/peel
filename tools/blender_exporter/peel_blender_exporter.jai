EXPORT_LOG_PATH :: "/tmp/peel_blender_exporter.log";
PEEL_BLEND_SCENE_MAGIC :: "PEBLEND1";
PEEL_BLEND_SCENE_VERSION : u32 : 1;

#program_export
peel_export_from_blender :: (snapshot: *PeelExportSnapshot, filepath: *u8) -> bool #c_call {
    push_context,defer_pop;
    reset_export_log();
    log_export("peel_export_from_blender: begin");

    if snapshot == null {
        log_export("snapshot was null");
        return false;
    }
    if filepath == null {
        log_export("filepath was null");
        return false;
    }

    output_path := to_string(filepath);
    log_export("output path: %", output_path);
    log_export("snapshot counts: materials=% meshes=% nodes=% refs=% vertices=% indices=%",
        snapshot.material_count,
        snapshot.mesh_count,
        snapshot.node_count,
        snapshot.node_mesh_ref_count,
        snapshot.vertex_count,
        snapshot.index_count);

    data: [..]u8;
    data.allocator = context.allocator;
    serialize_snapshot(*data, snapshot);
    log_export("serialized output bytes=%", data.count);

    temp_path := tprint("%.tmp", output_path);
    if !File.write_entire_file(temp_path, data.data, data.count) {
        log_export("write failed: %", temp_path);
        return false;
    }
    if !File.file_move(temp_path, output_path) {
        log_export("rename failed: % -> %", temp_path, output_path);
        return false;
    }

    log_export("export succeeded");
    return true;
}

#scope_file

#import "Basic";
File :: #import "File";
POSIX :: #import "POSIX";
#load "peel_bridge_bindings.jai";

serialize_snapshot :: (builder: *[..]u8, snapshot: *PeelExportSnapshot) {
    append_bytes(builder, cast([]u8) PEEL_BLEND_SCENE_MAGIC);
    cache_put(builder, PEEL_BLEND_SCENE_VERSION);
    cache_put(builder, snapshot.material_count);
    cache_put(builder, snapshot.mesh_count);
    cache_put(builder, snapshot.node_count);
    cache_put(builder, snapshot.node_mesh_ref_count);
    cache_put(builder, snapshot.vertex_count);
    cache_put(builder, snapshot.index_count);
    cache_put_c_string(builder, snapshot.model_name);

    for i: 0..cast(s64) snapshot.material_count-1 {
        material := snapshot.materials[i];
        cache_put_c_string(builder, material.name);
        for material.base_color cache_put(builder, it);
    }

    for i: 0..cast(s64) snapshot.mesh_count-1 {
        mesh := snapshot.meshes[i];
        cache_put(builder, mesh.base_vertex);
        cache_put(builder, mesh.vertex_count);
        cache_put(builder, mesh.first_index);
        cache_put(builder, mesh.index_count);
        cache_put(builder, mesh.material_index);
    }

    for i: 0..cast(s64) snapshot.node_count-1 {
        node := snapshot.nodes[i];
        cache_put_c_string(builder, node.name);
        cache_put(builder, node.parent_index);
        cache_put(builder, node.first_child_index);
        cache_put(builder, node.next_sibling_index);
        cache_put(builder, cast(s32) 0);
        cache_put(builder, node.first_mesh_ref);
        cache_put(builder, node.mesh_ref_count);
        cache_put(builder, cast(u32) 0);
        cache_put(builder, cast(u32) 0);
        for node.translation cache_put(builder, it);
        for node.rotation cache_put(builder, it);
        for node.scale cache_put(builder, it);
    }

    for i: 0..cast(s64) snapshot.node_mesh_ref_count-1 {
        cache_put(builder, snapshot.node_mesh_refs[i]);
    }

    for i: 0..cast(s64) snapshot.vertex_count-1 {
        vertex := snapshot.vertices[i];
        for vertex.position cache_put(builder, it);
        cache_put(builder, cast(float) 1.0);
        for vertex.normal cache_put(builder, it);
        cache_put(builder, cast(float) 0.0);
        cache_put(builder, cast(float) 1.0);
        cache_put(builder, cast(float) 0.0);
        cache_put(builder, cast(float) 0.0);
        cache_put(builder, cast(float) 1.0);
        for vertex.uv cache_put(builder, it);
    }

    for i: 0..cast(s64) snapshot.index_count-1 {
        cache_put(builder, snapshot.indices[i]);
    }
}

cache_put :: (builder: *[..]u8, x: $T) {
    value := x;
    offset := builder.count;
    array_resize(builder, offset + size_of(T));
    memcpy(builder.data + offset, *value, size_of(T));
}

cache_put_string :: (builder: *[..]u8, value: string) {
    count := cast(u32) value.count;
    cache_put(builder, count);
    if count == 0 return;
    append_bytes(builder, cast([]u8) value);
}

cache_put_c_string :: (builder: *[..]u8, value: *u8) {
    if value == null {
        cache_put_string(builder, "");
        return;
    }
    cache_put_string(builder, to_string(value));
}

reset_export_log :: () {
    fd := POSIX.creat(EXPORT_LOG_PATH, 420);
    if fd >= 0 {
        POSIX.close(fd);
    }
}

log_export :: (message: string, args: ..Any) {
    builder: String_Builder;
    defer free_buffers(*builder);

    print_to_builder(*builder, message, ..args);
    print_to_builder(*builder, "\n");
    line := builder_to_string(*builder);

    _ = POSIX.write(1, line.data, cast(u64) line.count);

    fd := POSIX.open(EXPORT_LOG_PATH, POSIX.O_WRONLY | POSIX.O_CREAT | POSIX.O_APPEND, 420);
    if fd < 0 return;
    defer POSIX.close(fd);

    _ = POSIX.write(fd, line.data, cast(u64) line.count);
}

append_bytes :: (builder: *[..]u8, data: []u8) {
    if data.count == 0 return;
    offset := builder.count;
    array_resize(builder, offset + data.count);
    memcpy(builder.data + offset, data.data, data.count);
}
