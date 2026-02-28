#scope_export

Terrain_Render_Depth_Mode :: enum {
    NONE;
    TEST;
}

Terrain_Render_Context :: struct {
    initialized: bool;
    max_vertices: s64;

    pipeline_no_depth: Gpu_Pipeline;
    pipeline_with_depth: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;

    positions_cpu: []Vector3;
    normals_cpu: []Vector3;
    positions_gpu: Gpu_Ptr;
    normals_gpu: Gpu_Ptr;

    params_cpu: *Terrain_Render_Params_GPU;
    params_gpu: Gpu_Ptr;
    view_projection_cpu: *Matrix4;
    view_projection_gpu: Gpu_Ptr;
}

init :: (ctx: *Terrain_Render_Context, max_vertices: s64 = 1200000) -> bool {
    ctx.* = .{};
    if max_vertices <= 0 max_vertices = 65536;
    ctx.max_vertices = max_vertices;

    shader_source := cast([]u8) TERRAIN_RENDER_METAL_SOURCE;

    blend: Gpu_Blend_Desc = .{
        src_color_factor = .SRC_ALPHA,
        dst_color_factor = .ONE_MINUS_SRC_ALPHA,
        color_op = .ADD,
        src_alpha_factor = .ONE,
        dst_alpha_factor = .ONE_MINUS_SRC_ALPHA,
        alpha_op = .ADD,
        color_write_mask = .R | .G | .B | .A,
    };

    raster_no_depth: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{ format = .B8G8R8A8_UNORM }
        ],
        blend_state = *blend,
    };
    raster_with_depth := raster_no_depth;
    raster_with_depth.depth_format = .D32_SFLOAT;

    ctx.pipeline_no_depth = gpu_create_graphics_pipeline(shader_source, raster_no_depth);
    ctx.pipeline_with_depth = gpu_create_graphics_pipeline(shader_source, raster_with_depth);
    if ctx.pipeline_no_depth == 0 || ctx.pipeline_with_depth == 0 return false;

    bytes := max_vertices * (size_of(Vector3) * 2) + size_of(Terrain_Render_Params_GPU) + size_of(Matrix4) + 4096;
    ctx.gpu_arena = gpu_make_arena(bytes, label = "terrain render arena");
    if ctx.gpu_arena.cpu == null return false;

    ctx.positions_cpu, ctx.positions_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, max_vertices);
    ctx.normals_cpu, ctx.normals_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, max_vertices);
    ctx.params_cpu, ctx.params_gpu = gpu_arena_alloc(*ctx.gpu_arena, Terrain_Render_Params_GPU);
    ctx.view_projection_cpu, ctx.view_projection_gpu = gpu_arena_alloc(*ctx.gpu_arena, Matrix4);
    if ctx.params_cpu == null || ctx.view_projection_cpu == null return false;

    ctx.params_cpu.positions = cast(*Vector3) ctx.positions_gpu;
    ctx.params_cpu.normals = cast(*Vector3) ctx.normals_gpu;
    ctx.params_cpu.view_projection = cast(*Matrix4) ctx.view_projection_gpu;
    ctx.params_cpu.tex_scale = 0.22;
    ctx.params_cpu.tri_sharpness = 3.0;

    ctx.view_projection_cpu.* = Matrix4_Identity;

    gpu_commit_residency();
    ctx.initialized = true;
    return true;
}

deinit :: (ctx: *Terrain_Render_Context) {
    if !ctx.initialized return;
    if ctx.pipeline_no_depth != 0 gpu_free_pipeline(ctx.pipeline_no_depth);
    if ctx.pipeline_with_depth != 0 gpu_free_pipeline(ctx.pipeline_with_depth);
    if ctx.gpu_arena.cpu != null gpu_free_arena(ctx.gpu_arena);
    ctx.* = .{};
}

set_view_projection :: (ctx: *Terrain_Render_Context, view_projection: Matrix4) {
    if !ctx.initialized return;
    ctx.view_projection_cpu.* = view_projection;
}

set_material :: (ctx: *Terrain_Render_Context, tex_scale: float = 0.22, tri_sharpness: float = 3.0) {
    if !ctx.initialized return;
    ctx.params_cpu.tex_scale = tex_scale;
    ctx.params_cpu.tri_sharpness = tri_sharpness;
}

upload :: (ctx: *Terrain_Render_Context, terrain: *Terrain_Voxel.Terrain_Voxel_Context) -> u32 {
    if !ctx.initialized return 0;

    out_count: s64 = 0;
    for Terrain_Voxel.chunks(terrain) {
        m := it.mesh;
        if m.vertex_count <= 0 continue;

        remain := ctx.max_vertices - out_count;
        if remain <= 0 break;

        copy_count := m.vertex_count;
        if copy_count > remain copy_count = remain;

        for i: 0..copy_count - 1 {
            ctx.positions_cpu[out_count + i] = m.positions[i];
            ctx.normals_cpu[out_count + i] = m.normals[i];
        }
        out_count += copy_count;
    }

    return cast(u32) out_count;
}

draw_uploaded :: (ctx: *Terrain_Render_Context, cmd: Gpu_Command_Buffer, vertex_count: u32, depth_mode: Terrain_Render_Depth_Mode = .TEST) -> Gpu_Result {
    if !ctx.initialized return .ERROR_INVALID_PIPELINE;
    if vertex_count == 0 return .SUCCESS;

    pipeline := ctx.pipeline_no_depth;
    if depth_mode == .TEST {
        gpu_set_depth_stencil_state(cmd, .{depth_test = .LESS, depth_mode = .READ});
        pipeline = ctx.pipeline_with_depth;
    } else {
        gpu_set_depth_stencil_state(cmd, .{depth_test = .ALWAYS, depth_mode = .NONE});
    }

    set_result := gpu_set_pipeline(cmd, pipeline);
    if set_result != .SUCCESS return set_result;

    return gpu_draw_instanced_direct(cmd, ctx.params_gpu, vertex_count, 1);
}

draw :: (ctx: *Terrain_Render_Context, cmd: Gpu_Command_Buffer, terrain: *Terrain_Voxel.Terrain_Voxel_Context, depth_mode: Terrain_Render_Depth_Mode = .TEST) -> Gpu_Result {
    vertex_count := upload(ctx, terrain);
    return draw_uploaded(ctx, cmd, vertex_count, depth_mode);
}

#scope_file

Terrain_Render_Params_GPU :: struct {
    positions: *Vector3;
    normals: *Vector3;
    view_projection: *Matrix4;
    tex_scale: float;
    tri_sharpness: float;
    _pad: [2]float;
}

TERRAIN_RENDER_METAL_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Matrix4RowMajor {
    float _11, _12, _13, _14;
    float _21, _22, _23, _24;
    float _31, _32, _33, _34;
    float _41, _42, _43, _44;
};

struct TerrainParams {
    device packed_float3* positions;
    device packed_float3* normals;
    constant Matrix4RowMajor* view_projection;
    float tex_scale;
    float tri_sharpness;
    float _pad0;
    float _pad1;
};

struct VSOut {
    float4 position [[position]];
    float3 world_pos [[user(locn0)]];
    float3 world_nrm [[user(locn1)]];
};

static inline float4 mul_row_major(constant Matrix4RowMajor& m, float4 v) {
    return float4(
        m._11 * v.x + m._12 * v.y + m._13 * v.z + m._14 * v.w,
        m._21 * v.x + m._22 * v.y + m._23 * v.z + m._24 * v.w,
        m._31 * v.x + m._32 * v.y + m._33 * v.z + m._34 * v.w,
        m._41 * v.x + m._42 * v.y + m._43 * v.z + m._44 * v.w
    );
}

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float3 sample_plane(float2 uv) {
    float2 suv = uv * 0.8;
    float2 cell = floor(suv);
    float n = hash12(cell);
    float c = fmod(cell.x + cell.y, 2.0);
    float3 a = float3(0.22, 0.20, 0.18);
    float3 b = float3(0.43, 0.40, 0.35);
    float3 stone = mix(a, b, n * 0.75 + 0.25);
    stone *= mix(0.9, 1.15, c);
    return stone;
}

vertex VSOut VertexMain(const device TerrainParams& params [[buffer(0)]], uint vid [[vertex_id]]) {
    VSOut out = {};
    float3 p = params.positions[vid];
    float3 n = normalize(float3(params.normals[vid]));
    out.world_pos = p;
    out.world_nrm = n;
    out.position = mul_row_major(params.view_projection[0], float4(p, 1.0));
    return out;
}

fragment float4 FragmentMain(VSOut in [[stage_in]], const device TerrainParams& params [[buffer(0)]]) {
    float3 n = normalize(in.world_nrm);
    float3 an = abs(n);
    float sharp = max(params.tri_sharpness, 1.0);
    float3 w = pow(an, float3(sharp));
    float inv = 1.0 / max(w.x + w.y + w.z, 1e-4);
    w *= inv;

    float s = max(params.tex_scale, 1e-4);
    float3 cx = sample_plane(in.world_pos.yz * s);
    float3 cy = sample_plane(in.world_pos.xz * s);
    float3 cz = sample_plane(in.world_pos.xy * s);
    float3 base = cx * w.x + cy * w.y + cz * w.z;

    float3 light_dir = normalize(float3(0.45, 0.9, 0.25));
    float ndl = abs(dot(n, light_dir));
    float lit = 0.25 + ndl * 0.75;

    return float4(base * lit, 1.0);
}
END

Terrain_Voxel :: #import "Terrain_Voxel";
#import "sgpu";
#import "Math";
