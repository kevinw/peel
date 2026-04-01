

AB_Buffer :: struct($T: Type) {
    a_cpu: *T;
    b_cpu: *T;
    a_gpu: Gpu_Ptr;
    b_gpu: Gpu_Ptr;
    src_is_a: bool;
}

ab_buffer_src_cpu :: (buffer: *AB_Buffer($T)) -> *T #expand {
    if buffer.src_is_a return buffer.a_cpu;
    return buffer.b_cpu;
}

ab_buffer_dst_cpu :: (buffer: *AB_Buffer($T)) -> *T #expand {
    if buffer.src_is_a return buffer.b_cpu;
    return buffer.a_cpu;
}

ab_buffer_src_gpu :: (buffer: *AB_Buffer($T)) -> Gpu_Ptr #expand {
    if buffer.src_is_a return buffer.a_gpu;
    return buffer.b_gpu;
}

ab_buffer_dst_gpu :: (buffer: *AB_Buffer($T)) -> Gpu_Ptr #expand {
    if buffer.src_is_a return buffer.b_gpu;
    return buffer.a_gpu;
}

ab_buffer_advance :: (buffer: *AB_Buffer($T)) #expand {
    buffer.src_is_a = !buffer.src_is_a;
}

sgpu_frame_ring_index :: (frame_number: s64 = -1) -> s64 {
    if frame_number < 0 frame_number = cast(s64) gpu_submission_frame_index();
    idx := frame_number % SGPU_FRAMES_IN_FLIGHT;
    if idx < 0 idx += SGPU_FRAMES_IN_FLIGHT;
    return idx;
}

Gpu_Frame_Ring :: struct($T: Type, $N: s64 = SGPU_FRAMES_IN_FLIGHT) {
    view: Gpu_View(T);
}

sgpu_make_frame_ring :: (arena: *Gpu_Arena, $T: Type, min_alignment: s64 = 16) -> Gpu_Frame_Ring(T) {
    return .{
        view = gpu_alloc_view(arena, T, SGPU_FRAMES_IN_FLIGHT, min_alignment),
    };
}

sgpu_arena_alloc_frame_ring :: (arena: *Gpu_Arena, $T: Type, min_alignment: s64 = 16) -> (*[SGPU_FRAMES_IN_FLIGHT] T, Gpu_Ptr) {
    cpu_ring, gpu_ring := gpu_arena_alloc(arena, [SGPU_FRAMES_IN_FLIGHT] T, min_alignment);
    return cpu_ring, gpu_ring;
}

Gpu_Frame_Param_Allocator :: struct($T: Type, $N: s64 = SGPU_FRAMES_IN_FLIGHT) {
    view: Gpu_View(T);
    slots_per_frame: s64;
    frame_epochs: [N] u64;
    cursors: [N] s64;
}

sgpu_make_frame_param_allocator :: (arena: *Gpu_Arena, $T: Type, slots_per_frame: s64 = 1, min_alignment: s64 = 16) -> Gpu_Frame_Param_Allocator(T) {
    assert(slots_per_frame > 0, "sgpu_make_frame_param_allocator requires slots_per_frame > 0.");
    allocator := Gpu_Frame_Param_Allocator(T).{
        view = gpu_alloc_view(arena, T, SGPU_FRAMES_IN_FLIGHT * slots_per_frame, min_alignment),
        slots_per_frame = slots_per_frame,
    };
    for i: 0..SGPU_FRAMES_IN_FLIGHT-1 {
        allocator.frame_epochs[i] = U64_MAX;
    }
    return allocator;
}

sgpu_frame_param_alloc :: (allocator: *Gpu_Frame_Param_Allocator($T), data: T, frame_number: s64 = -1) -> Gpu_Buffer(T) {
    buf := sgpu_frame_param_alloc(allocator=allocator, frame_number=frame_number);
    buf.cpu.* = data;
    return buf;
}

sgpu_frame_param_alloc :: (allocator: *Gpu_Frame_Param_Allocator($T), frame_number: s64 = -1) -> Gpu_Buffer(T) {
    if frame_number < 0 frame_number = cast(s64) gpu_submission_frame_index();
    idx := sgpu_frame_ring_index(frame_number);
    frame_epoch := cast(u64) frame_number;
    if allocator.frame_epochs[idx] != frame_epoch {
        allocator.frame_epochs[idx] = frame_epoch;
        allocator.cursors[idx] = 0;
    }

    slot := allocator.cursors[idx];
    assert(slot < allocator.slots_per_frame,
        "frame param allocator exhausted: slot=% capacity=% frame=%", slot, allocator.slots_per_frame, frame_number);
    allocator.cursors[idx] += 1;

    base := idx * allocator.slots_per_frame + slot;
    return .{
        cpu = allocator.view.cpu.data + base,
        gpu = allocator.view.gpu + (base * size_of(T)).(Gpu_Ptr),
    };
}

sgpu_frame_param_slot_count :: (allocator: *Gpu_Frame_Param_Allocator($T)) -> s64 #expand {
    return allocator.slots_per_frame;
}

sgpu_frame_ring_slot :: (ring: *Gpu_Frame_Ring($T), frame_number: s64 = -1) -> Gpu_Buffer(T) #expand {
    idx := sgpu_frame_ring_index(frame_number);
    return .{
        cpu = ring.view.cpu.data + idx,
        gpu = ring.view.gpu + (idx * size_of(T)).(Gpu_Ptr),
    };
}

sgpu_frame_ring_cpu_slot :: (ring: *[SGPU_FRAMES_IN_FLIGHT] $T, frame_number: s64 = -1) -> *T #expand {
    idx := sgpu_frame_ring_index(frame_number);
    return cast(*T) ring + idx;
}

sgpu_frame_ring_gpu_slot :: (ring_base_gpu: Gpu_Ptr, $T: Type, frame_number: s64 = -1) -> Gpu_Ptr #expand {
    idx := sgpu_frame_ring_index(frame_number);
    return ring_base_gpu + (idx * size_of(T)).(Gpu_Ptr);
}

gpu_begin_scoped_render_pass :: (cmd_buf: Gpu_Command_Buffer, desc: Gpu_Render_Pass_Desc,
    transition_before: Pass_Access = .NONE, transition_after: Pass_Access = .NONE) #expand {
    gpu_begin_render_pass(cmd_buf, desc);
    `defer ifx transition_before != .NONE || transition_after != .NONE
        then gpu_end_render_pass_with_transition(cmd_buf, transition_before, transition_after)
        else gpu_end_render_pass(cmd_buf);
}

//
// some helper functions for deleting gpu resources
//

gpu_delete :: (texture_view_ptr: *Gpu_Texture_View) {
    if texture_view_ptr == null return;

    texture_view := texture_view_ptr.*;
    if texture_view != 0  gpu_free_texture_view(texture_view);
    texture_view_ptr.* = 0;
}

gpu_delete :: (texture_ptr: *Gpu_Texture) {
    if texture_ptr == null return;

    texture := texture_ptr.*;
    if texture != 0  gpu_free(texture);
    texture_ptr.* = 0;
}

gpu_delete :: (sampler_ptr: *Gpu_Sampler) {
    if sampler_ptr == null return;

    sampler := sampler_ptr.*;
    if sampler != 0 gpu_free(sampler);
}

gpu_delete :: (gpu_view: *Gpu_View($T)) {
    if gpu_view == null return;

    if gpu_view.cpu.data != null gpu_free(gpu_view.cpu.data);
    gpu_view.* = {};
}

gpu_delete :: (gpu_buffer: *Gpu_Buffer($T)) {
    if gpu_buffer == null return;

    if gpu_buffer.cpu != null gpu_free(gpu_buffer.cpu);
    gpu_buffer.* = {};
}

gpu_delete :: (pipeline: *Gpu_Pipeline) {
    if pipeline == null return;

    if pipeline.* != 0 gpu_free_pipeline(pipeline.*);
    pipeline.* = 0;
}

cos :: (v: Vector3) -> Vector3 { return { cos(v.x), cos(v.y), cos(v.z) }; }
sin :: (v: Vector3) -> Vector3 { return { sin(v.x), sin(v.y), sin(v.z) }; }
vec4 :: (v3: Vector3, w: float) -> Vector4 { return { v3.x, v3.y, v3.z, w }; }

make_trs_matrix :: inline (pos: Vector3, rot: Quaternion, scale: Vector3) -> Matrix4 {
    return make_translation_matrix4(pos) *
        rotation_matrix(Matrix4, rot) *
        make_scale_matrix4(scale);
}

make_trs_matrix :: inline (pos: Vector3, rot: Quaternion, scale: float) -> Matrix4 {
    return make_translation_matrix4(pos) *
        rotation_matrix(Matrix4, rot) *
        make_scale_matrix4(.{scale, scale, scale});
}

wrap_angle_pi :: (angle: float) -> float {
    wrapped := angle;
    while wrapped > PI  wrapped -= PI * 2.0;
    while wrapped < -PI wrapped += PI * 2.0;
    return wrapped;
}

smooth_yaw_towards :: (current: float, target: float, dt: float, turn_speed: float) -> float {
    max_step := max(0.0, turn_speed) * dt;
    delta := wrap_angle_pi(target - current);
    if abs(delta) <= max_step return current + delta;
    step_sign := ifx delta < 0.0 then -1.0 else 1.0;
    return current + step_sign * max_step;
}

load_texture_rgba8 :: (path: string) -> Gpu_Texture, Gpu_Texture_View {
    width, height, num_channels: s32 = 0;
    pixels := stbi_load(temp_c_string(path), *width, *height, *num_channels, 4);
    defer stbi_image_free(pixels);

    assert(pixels != null && width > 0 && height > 0, tprint("Failed to load texture: %", path));
    texture_result, texture := gpu_create_texture(.{
        dimensions = .[cast(u32) width, cast(u32) height, 1],
        format = .R8G8B8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });

    bgra_pixels: [..]u8;
    bgra_pixels.allocator = temp;
    array_resize(*bgra_pixels, cast(s64) width * cast(s64) height * 4);
    memcpy(bgra_pixels.data, pixels, bgra_pixels.count);

    gpu_copy_to_texture(texture, bgra_pixels.data);

    view := gpu_texture_view(texture);
    return texture, view;
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


#scope_file
#import "stb_image";
