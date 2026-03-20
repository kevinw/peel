//
// Tools for doing per-pixel objectID mouse-ray-picking
//

scene_pick: struct {
    texture: Gpu_Texture;
    view: Gpu_Texture_View;
    w: u32;
    h: u32;
    pending: bool;
    render_this_frame: bool;
    request_frame: s64 = -1;
    request_x: s64;
    request_y: s64;
    last_object_id: u32;
    last_scene_node_index: s32 = -1;
    request_count: s64;
    apply_count: s64;
    last_request_frame: s64 = -1;
    last_apply_frame: s64 = -1;
    last_applied_x: s64 = -1;
    last_applied_y: s64 = -1;
}

queue_scene_pick_request :: (mx: s32, my: s32) {
    using scene_pick;

    if view == 0 || w == 0 || h == 0 return;
    request_x = clamp(cast(s64) mx, 0, cast(s64) w - 1);
    flipped_y := cast(s64) h - 1 - cast(s64) my;
    request_y = clamp(flipped_y, 0, cast(s64) h - 1);
    pending = true;
    render_this_frame = true;
    request_frame = cast(s64) gpu_submission_frame_index() + 1;
    request_count += 1;
    last_request_frame = request_frame;
}


process_scene_pick_result_if_ready :: () {
    using scene_pick;

    if !pending || view == 0 return;
    if gpu_completed_submission_frame_index() < request_frame {
        return;
    }

    bytes_per_row := cast(s64) w * 4;
    total_bytes := bytes_per_row * cast(s64) h;
    pixels := NewArray(total_bytes, u8);
    defer array_free(pixels);

    if !gpu_readback_texture_view_bgra8(view, pixels, bytes_per_row) {
        log_error("error reading scene pick texture view");
        pending = false;
        render_this_frame = false;
        request_frame = -1;
        return;
    }

    offset := request_y * bytes_per_row + request_x * 4;
    p := pixels.data + offset;
    object_id := cast(u32) p[2] | (cast(u32) p[1] << 8) | (cast(u32) p[0] << 16) | (cast(u32) p[3] << 24);
    log("unpacked object_id from pick texture: %", object_id);
    scene_pick_apply_object_id(object_id);
    pending = false;
    render_this_frame = false;
    request_frame = -1;
}

scene_pick_apply_object_id :: (object_id: u32) {
    using scene_pick;
    last_object_id = object_id;
    apply_count += 1;
    last_apply_frame = cast(s64) gpu_completed_submission_frame_index();
    last_applied_x = request_x;
    last_applied_y = request_y;
    if scene_manip_objects_dirty {
        scene_rebuild_manip_objects();
        scene_manip_objects_dirty = false;
    }
    scene_manip_ctx.active = false;
    scene_manip_ctx.active_kind = .NONE;
    scene_manip_ctx.active_axis = -1;
    scene_manip_ctx.active_plane = -1;

    if object_id == 0 {
        last_scene_node_index = -1;
        scene_manip_ctx.selected_index = -1;
        return;
    }

    node_index := cast(s32) object_id - 1;
    last_scene_node_index = node_index;
    scene_manip_ctx.selected_index = -1;
    for scene_manip_node_indices {
        if it == node_index {
            scene_manip_ctx.selected_index = cast(s32) it_index;
            return;
        }
    }
}

deinit :: (using s: *type_of(scene_pick)) {
    gpu_delete(*view);
    gpu_delete(*texture);
    w = 0;
    h = 0;
}

ensure_scene_pick_target :: (width: u32, height: u32) {
    using scene_pick;

    if width == 0 || height == 0 return;

    if view != 0 && w == width && h == height return;

    if view != 0 {
        gpu_free_texture_view(view);
        view = 0;
    }

    if texture != 0 {
        gpu_free(texture);
        texture = 0;
    }

    res, texture= := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .B8G8R8A8_UNORM,
        usage = .COLOR_ATTACHMENT | .TRANSFER_DST,
    });

    assert(res == .SUCCESS && texture != 0, "Failed to create model_scene pick texture.");

    view = gpu_texture_view(texture);
    assert(view != 0, "Failed to create model_scene pick texture view.");

    w = width;
    h = height;

    gpu_commit_residency();
}
