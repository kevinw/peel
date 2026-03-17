

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
gpu_delete :: (sampler_ptr: *Gpu_Sampler) {
    if sampler_ptr != null {
        sampler := sampler_ptr.*;
        if sampler != 0 {
            gpu_free(sampler);
        }
        sampler_ptr.* = 0;
    }
}

gpu_delete :: (gpu_view: *Gpu_View($T)) {
    if gpu_view != null {
        if gpu_view.cpu.data != null {
            gpu_free(gpu_view.cpu.data);
        }
        gpu_view.* = {};
    }
}

gpu_delete :: (gpu_buffer: *Gpu_Buffer($T)) {
    if gpu_buffer != null {
        if gpu_buffer.cpu != null {
            gpu_free(gpu_buffer.cpu);
        }
        gpu_buffer.* = {};
    }
}

cos :: (v: Vector3) -> Vector3 { return { cos(v.x), cos(v.y), cos(v.z) }; }
sin :: (v: Vector3) -> Vector3 { return { sin(v.x), sin(v.y), sin(v.z) }; }
vec4 :: (v3: Vector3, w: float) -> Vector4 { return { v3.x, v3.y, v3.z, w }; }
