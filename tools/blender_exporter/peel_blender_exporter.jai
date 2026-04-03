EXPORT_LOG_PATH :: "/tmp/peel_blender_exporter.log";

#program_export
peel_export_from_blender :: (context_ptr: *void, reports_ptr: *void, filepath: *u8, bridge_api: *PeelBridgeAPI) -> bool #c_call {
    push_context,defer_pop;
    _ = reports_ptr;
    reset_export_log();
    log_export("peel_export_from_blender: begin");
    if context_ptr == null {
        log_export("context_ptr was null");
        return false;
    }
    if filepath == null {
        log_export("filepath was null");
        return false;
    }

    output_path := to_string(filepath);
    log_export("output path: %", output_path);

    if bridge_api == null {
        log_export("bridge_api was null");
        return false;
    }

    using bridge_api;

    if scene_object_count == null {
        log_export("bridge_api.scene_object_count was null");
        return false;
    }
    if scene_objects_fill == null {
        log_export("bridge_api.scene_objects_fill was null");
        return false;
    }
    log_export("bridge API received");

    object_count := scene_object_count(context_ptr);
    log_export("object_count=%", object_count);
    if object_count < 0 {
        log_export("object_count was negative");
        return false;
    }

    objects := NewArray(cast(int)object_count, PeelObjectInfo);
    log_export("allocated object array for % entries", object_count);
    filled_count := scene_objects_fill(context_ptr, objects.data, object_count);
    log_export("filled_count=%", filled_count);
    if filled_count < 0 {
        log_export("filled_count was negative");
        return false;
    }
    if filled_count > object_count {
        log_export("filled_count > object_count");
        return false;
    }
    filled_count_int := cast(int) filled_count;

    builder: String_Builder;
    defer free_buffers(*builder);

    print_to_builder(*builder, "minimal peel export\nversion=2\nobject_count=%\n", filled_count);
    for 0..filled_count_int-1 {
        object := objects[it];
        object_name := "";
        if object.name != null {
            object_name = to_string(object.name);
        }
        print_to_builder(*builder,
            "[object %]\nname=%\ntype=%\nparent_index=%\nworld=% % % % % % % % % % % % % % % %\n",
            it,
            object_name,
            object.type,
            object.parent_index,
            object.world[0],  object.world[1],  object.world[2],  object.world[3],
            object.world[4],  object.world[5],  object.world[6],  object.world[7],
            object.world[8],  object.world[9],  object.world[10], object.world[11],
            object.world[12], object.world[13], object.world[14], object.world[15]);
    }

    output := builder_to_string(*builder);
    log_export("built output text, % bytes", output.count);

    fd := POSIX.creat(filepath, 420);
    if fd < 0 {
        log_export("creat failed, errno=%", POSIX.errno());
        return false;
    }
    defer POSIX.close(fd);

    written := POSIX.write(fd, output.data, cast(u64) output.count);
    log_export("write returned %", written);
    if written != output.count {
        log_export("short write, expected % bytes", output.count);
        return false;
    }

    log_export("export succeeded");
    return true;
}

#scope_file

#import "Basic";
POSIX :: #import "POSIX";
#load "peel_bridge_bindings.jai";

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
