#scope_export

Chunk_Res :: Terrain_Voxel.Chunk_Res;
Sample_Res :: Terrain_Voxel.Sample_Res;
Sample_Count :: Terrain_Voxel.Sample_Count;
Cell_Count :: Chunk_Res * Chunk_Res * Chunk_Res;
Voxel_Size :: Terrain_Voxel.Voxel_Size;
Iso_Level :: Terrain_Voxel.Iso_Level;
Density_Scale :: Terrain_Voxel.Density_Scale;

Max_Verts_Per_Cell :: 36;
Max_Verts_Per_Chunk :: Cell_Count * Max_Verts_Per_Cell;

Terrain_Mesh_Compute_Context :: struct {
    initialized: bool;
    pipeline: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;

    density_cpu: *[Sample_Count]float;
    density_gpu: Gpu_Ptr;

    positions_cpu: *[Max_Verts_Per_Chunk]Terrain_Mesh_Float4;
    positions_gpu: Gpu_Ptr;

    normals_cpu: *[Max_Verts_Per_Chunk]Terrain_Mesh_Float4;
    normals_gpu: Gpu_Ptr;

}

init :: (ctx: *Terrain_Mesh_Compute_Context, compute_source: []u8) -> bool {
    ctx.* = .{};

    if compute_source.count == 0 return false;
    ctx.pipeline = gpu_create_compute_pipeline(compute_source);
    if ctx.pipeline == 0 return false;

    bytes: s64 = 0;
    bytes += size_of([Sample_Count]float);
    bytes += size_of([Max_Verts_Per_Chunk]Terrain_Mesh_Float4);
    bytes += size_of([Max_Verts_Per_Chunk]Terrain_Mesh_Float4);
    bytes += 4096;

    ctx.gpu_arena = gpu_make_arena(bytes, label = "terrain mesh compute arena");
    if ctx.gpu_arena.cpu == null return false;

    ctx.density_cpu, ctx.density_gpu = gpu_arena_alloc(*ctx.gpu_arena, [Sample_Count]float);
    ctx.positions_cpu, ctx.positions_gpu = gpu_arena_alloc(*ctx.gpu_arena, [Max_Verts_Per_Chunk]Terrain_Mesh_Float4);
    ctx.normals_cpu, ctx.normals_gpu = gpu_arena_alloc(*ctx.gpu_arena, [Max_Verts_Per_Chunk]Terrain_Mesh_Float4);
    if ctx.density_cpu == null || ctx.positions_cpu == null || ctx.normals_cpu == null return false;

    gpu_commit_residency();
    ctx.initialized = true;
    return true;
}

deinit :: (ctx: *Terrain_Mesh_Compute_Context) {
    if !ctx.initialized return;
    if ctx.pipeline != 0 gpu_free_pipeline(ctx.pipeline);
    if ctx.gpu_arena.cpu != null gpu_free_arena(ctx.gpu_arena);
    ctx.* = .{};
}

rebuild_dirty_meshes :: (ctx: *Terrain_Mesh_Compute_Context, terrain: *Terrain_Voxel.Terrain_Voxel_Context, max_chunks: s64 = 0) -> s64 {
    if !ctx.initialized return 0;

    queue := gpu_get_queue(.MAIN, 0);
    rebuilt: s64 = 0;

    for *terrain.chunks {
        if !it.dirty continue;

        for i: 0..Sample_Count-1 {
            ctx.density_cpu.*[i] = cast(float) it.density[i] / Density_Scale;
        }
        memset(ctx.positions_cpu, 0, size_of([Max_Verts_Per_Chunk]Terrain_Mesh_Float4));
        memset(ctx.normals_cpu,   0, size_of([Max_Verts_Per_Chunk]Terrain_Mesh_Float4));

        result, cmd := gpu_start_command_recording(queue);
        assert(result == .SUCCESS);
        result = gpu_set_pipeline(cmd, ctx.pipeline);
        assert(result == .SUCCESS, tprint("Terrain mesh compute set pipeline failed: %", result));
        // sgpu dispatches threadgroups here, and the Metal backend currently uses a
        // 64-wide compute threadgroup for generic compute pipelines.
        dispatch_x := cast(u32) ((Cell_Count + 63) / 64);
        gpu_dispatch_buffers(cmd, .[ctx.density_gpu, ctx.positions_gpu, ctx.normals_gpu], .[dispatch_x, 1, 1]);
        gpu_submit(cmd);
        gpu_wait_idle();

        array_reset(*it.mesh.positions);
        array_reset(*it.mesh.normals);

        for cell: 0..Cell_Count-1 {
            emitted := cast(u32) floor(ctx.positions_cpu.*[cell * Max_Verts_Per_Cell].w + 0.5);
            if emitted > Max_Verts_Per_Cell emitted = Max_Verts_Per_Cell;
            emitted -= emitted % 3;
            if emitted == 0 continue;

            base := cell * Max_Verts_Per_Cell;
            for v: 0..emitted-1 {
                p4 := ctx.positions_cpu.*[base + v];
                n4 := ctx.normals_cpu.*[base + v];
                p := Vector3.{p4.x + it.origin.x, p4.y + it.origin.y, p4.z + it.origin.z};
                n := Vector3.{n4.x, n4.y, n4.z};
                array_add(*it.mesh.positions, p);
                array_add(*it.mesh.normals, n);
            }
        }

        it.mesh.vertex_count = it.mesh.positions.count;
        it.mesh.dirty = false;
        it.dirty = false;

        rebuilt += 1;

        if max_chunks > 0 {
            if rebuilt >= max_chunks break;
        }
    }

    return rebuilt;
}

#scope_file
Terrain_Mesh_Float4 :: struct {
    x, y, z, w: float;
}

#import "Basic";
#import "sgpu";
#import "Math";
Terrain_Voxel :: #import "Terrain_Voxel";
