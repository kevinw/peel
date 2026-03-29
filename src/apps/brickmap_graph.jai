Brickmap_Graph_Resource :: enum_flags u64 {
    PARAMS;
    STATE;
    QUEUES;
    ATLAS_SDF;
    ATLAS_ALBEDO;
}

Brickmap_Graph_Sync :: enum {
    NONE;
    WAIT_IDLE;
}

BRICKMAP_GRAPH_MAX_PASS_BUFFERS :: 5;
BRICKMAP_GRAPH_MAX_STATS_PASSES :: 16;

Brickmap_Graph_Pass :: struct {
    name: string;
    pipeline: Gpu_Pipeline;
    buffers: [BRICKMAP_GRAPH_MAX_PASS_BUFFERS] Gpu_Ptr;
    buffer_count: s32;
    dispatch: [3] u32;
    indirect_dispatch: Gpu_Ptr;
    barrier_buffer: Gpu_Ptr;
    barrier_src_stage: Stage;
    barrier_src_access: Gpu_Access;
    barrier_dst_stage: Stage;
    barrier_dst_access: Gpu_Access;
    reads: Brickmap_Graph_Resource;
    writes: Brickmap_Graph_Resource;
    sync_after: Brickmap_Graph_Sync;
}

Brickmap_Graph_Stats :: struct {
    encode_ms: float;
    wait_ms: float;
    pass_count: s32;
    pass_names: [BRICKMAP_GRAPH_MAX_STATS_PASSES] string;
    pass_encode_ms: [BRICKMAP_GRAPH_MAX_STATS_PASSES] float;
    pass_wait_ms: [BRICKMAP_GRAPH_MAX_STATS_PASSES] float;
}

Brickmap_Graph :: struct {
    passes: [..]Brickmap_Graph_Pass;
}

init :: (graph: *Brickmap_Graph) {
    graph.passes.allocator = cpu_allocator;
}

reset :: (graph: *Brickmap_Graph) {
    array_reset(*graph.passes);
}

add_compute_pass :: (graph: *Brickmap_Graph, name: string, pipeline: Gpu_Pipeline, buffers: []Gpu_Ptr, dispatch: [3]u32,
    reads: Brickmap_Graph_Resource, writes: Brickmap_Graph_Resource, sync_after: Brickmap_Graph_Sync = .WAIT_IDLE) {

    assert(buffers.count <= BRICKMAP_GRAPH_MAX_PASS_BUFFERS, "Brickmap graph pass '%' has too many buffers: % > %", name, buffers.count, BRICKMAP_GRAPH_MAX_PASS_BUFFERS);
    if dispatch[0] == 0 || dispatch[1] == 0 || dispatch[2] == 0 return;

    pass := Brickmap_Graph_Pass.{
        name = name,
        pipeline = pipeline,
        buffer_count = cast(s32) buffers.count,
        dispatch = dispatch,
        reads = reads,
        writes = writes,
        sync_after = sync_after,
    };
    for i: 0..buffers.count-1 {
        pass.buffers[i] = buffers[i];
    }
    array_add(*graph.passes, pass);
}

add_compute_pass_indirect :: (graph: *Brickmap_Graph, name: string, pipeline: Gpu_Pipeline, buffers: []Gpu_Ptr, indirect_dispatch: Gpu_Ptr,
    reads: Brickmap_Graph_Resource, writes: Brickmap_Graph_Resource, sync_after: Brickmap_Graph_Sync = .WAIT_IDLE) {

    assert(indirect_dispatch != 0, "Brickmap graph indirect pass '%' requires indirect dispatch args.", name);
    assert(buffers.count <= BRICKMAP_GRAPH_MAX_PASS_BUFFERS, "Brickmap graph pass '%' has too many buffers: % > %", name, buffers.count, BRICKMAP_GRAPH_MAX_PASS_BUFFERS);

    pass := Brickmap_Graph_Pass.{
        name = name,
        pipeline = pipeline,
        buffer_count = cast(s32) buffers.count,
        indirect_dispatch = indirect_dispatch,
        reads = reads,
        writes = writes,
        sync_after = sync_after,
    };
    for i: 0..buffers.count-1 {
        pass.buffers[i] = buffers[i];
    }
    array_add(*graph.passes, pass);
}

add_buffer_barrier_pass :: (graph: *Brickmap_Graph, name: string, buffer: Gpu_Ptr,
    src_stage: Stage, src_access: Gpu_Access,
    dst_stage: Stage, dst_access: Gpu_Access,
    sync_after: Brickmap_Graph_Sync = .NONE) {

    assert(buffer != 0, "Brickmap graph barrier pass '%' requires a buffer.", name);
    pass := Brickmap_Graph_Pass.{
        name = name,
        barrier_buffer = buffer,
        barrier_src_stage = src_stage,
        barrier_src_access = src_access,
        barrier_dst_stage = dst_stage,
        barrier_dst_access = dst_access,
        sync_after = sync_after,
    };
    array_add(*graph.passes, pass);
}

execute :: (graph: *Brickmap_Graph, queue: Gpu_Queue, log_passes: bool = false) -> Brickmap_Graph_Stats {
    stats: Brickmap_Graph_Stats;
    if graph.passes.count == 0 return stats;
    result: Gpu_Result;
    active_cmd: Gpu_Command_Buffer;
    cmd_open := false;

    dispatch_pass_buffers :: (cmd: Gpu_Command_Buffer, pass: Brickmap_Graph_Pass) #expand {
        if pass.buffer_count == {
        case 1; gpu_dispatch_buffers(cmd, .[pass.buffers[0]], pass.dispatch);
        case 2; gpu_dispatch_buffers(cmd, .[pass.buffers[0], pass.buffers[1]], pass.dispatch);
        case 3; gpu_dispatch_buffers(cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2]], pass.dispatch);
        case 4; gpu_dispatch_buffers(cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2], pass.buffers[3]], pass.dispatch);
        case 5; gpu_dispatch_buffers(cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2], pass.buffers[3], pass.buffers[4]], pass.dispatch);
        case; assert(false, "Brickmap graph pass '%' has unsupported buffer_count=%", pass.name, pass.buffer_count);
        }
    }

    ensure_cmd :: () #expand {
        if !cmd_open {
            result=, active_cmd = gpu_start_command_recording(queue);
            assert(result == .SUCCESS, "Brickmap graph failed to start command recording: %", result);
            cmd_open = true;
        }
    }

    flush_cmd :: (wait_after_submit: bool, stats_index: s32 = -1) #expand {
        if !cmd_open return;
        gpu_submit(active_cmd);
        cmd_open = false;
        if wait_after_submit {
            wait_start := seconds_since_init();
            gpu_queue_wait_idle(queue);
            wait_ms := cast(float) ((seconds_since_init() - wait_start) * 1000.0);
            stats.wait_ms += wait_ms;
            idx := stats_index;
            if idx >= 0 && idx < BRICKMAP_GRAPH_MAX_STATS_PASSES {
                stats.pass_wait_ms[idx] = wait_ms;
            }
        }
    }

    for pass, pass_index: graph.passes {
        if log_passes {
            if pass.barrier_buffer != 0 {
                log("BRICKMAP graph pass '%' barrier buffer=% %/% -> %/% sync=%",
                    pass.name, pass.barrier_buffer, pass.barrier_src_stage, pass.barrier_src_access, pass.barrier_dst_stage, pass.barrier_dst_access, pass.sync_after);
            } else if pass.indirect_dispatch != 0 {
                log("BRICKMAP graph pass '%' dispatch=indirect:% reads=% writes=% sync=%",
                    pass.name, pass.indirect_dispatch, pass.reads, pass.writes, pass.sync_after);
            } else {
                log("BRICKMAP graph pass '%' dispatch=%x%x% reads=% writes=% sync=%",
                    pass.name, pass.dispatch[0], pass.dispatch[1], pass.dispatch[2], pass.reads, pass.writes, pass.sync_after);
            }
        }

        encode_start := seconds_since_init();
        if pass.barrier_buffer != 0 {
            // Our current Metal path implements compute-write -> indirect-read as a
            // conservative queue-completion boundary. If we already have batched work
            // recorded, submit and wait here so the next pass sees the finished writes.
            if (pass.barrier_dst_access & .INDIRECT_READ) != 0 {
                flush_cmd(true, cast(s32) pass_index);
            } else {
                ensure_cmd();
                result = gpu_buffer_barrier(active_cmd, pass.barrier_buffer, pass.barrier_src_stage, pass.barrier_src_access, pass.barrier_dst_stage, pass.barrier_dst_access);
                assert(result == .SUCCESS, "Brickmap graph barrier pass '%' failed: %", pass.name, result);
            }
        } else {
            ensure_cmd();
            result = gpu_set_pipeline(active_cmd, pass.pipeline);
            assert(result == .SUCCESS, "Brickmap graph pass '%' failed to set pipeline: %", pass.name, result);

            if pass.indirect_dispatch != 0 {
                if pass.buffer_count == {
                case 1; result = gpu_indirect_dispatch_buffers(active_cmd, .[pass.buffers[0]], pass.indirect_dispatch);
                case 2; result = gpu_indirect_dispatch_buffers(active_cmd, .[pass.buffers[0], pass.buffers[1]], pass.indirect_dispatch);
                case 3; result = gpu_indirect_dispatch_buffers(active_cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2]], pass.indirect_dispatch);
                case 4; result = gpu_indirect_dispatch_buffers(active_cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2], pass.buffers[3]], pass.indirect_dispatch);
                case 5; result = gpu_indirect_dispatch_buffers(active_cmd, .[pass.buffers[0], pass.buffers[1], pass.buffers[2], pass.buffers[3], pass.buffers[4]], pass.indirect_dispatch);
                case; assert(false, "Brickmap graph pass '%' has unsupported buffer_count=%", pass.name, pass.buffer_count);
                }
                assert(result == .SUCCESS, "Brickmap graph indirect pass '%' failed to dispatch: %", pass.name, result);
            } else {
                dispatch_pass_buffers(active_cmd, pass);
            }
        }
        pass_encode_ms := cast(float) ((seconds_since_init() - encode_start) * 1000.0);
        stats.encode_ms += pass_encode_ms;

        if pass.sync_after == .WAIT_IDLE {
            flush_cmd(true, cast(s32) pass_index);
        }

        if pass_index < BRICKMAP_GRAPH_MAX_STATS_PASSES {
            stats.pass_names[pass_index] = pass.name;
            stats.pass_encode_ms[pass_index] = pass_encode_ms;
        }
        stats.pass_count += 1;
    }

    flush_cmd(false);
    return stats;
}
