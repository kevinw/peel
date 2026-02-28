#scope_export

Gizmo_Render_Depth_Mode :: enum {
    NONE;
    TEST;
}

Gizmo_Render_Context :: struct {
    initialized: bool;
    max_lines: s64;
    max_triangles: s64;
    bound_gizmo: *Gizmo.Gizmo_Context;

    pipeline_no_depth: Gpu_Pipeline;
    pipeline_with_depth: Gpu_Pipeline;
    triangle_pipeline_no_depth: Gpu_Pipeline;
    triangle_pipeline_with_depth: Gpu_Pipeline;
    gpu_arena: Gpu_Arena;

    line_a_cpu: []Vector3;
    line_b_cpu: []Vector3;
    line_color_cpu: []u32;
    line_thickness_cpu: []u16;

    line_a_gpu: Gpu_Ptr;
    line_b_gpu: Gpu_Ptr;
    line_color_gpu: Gpu_Ptr;
    line_thickness_gpu: Gpu_Ptr;
    triangle_a_cpu: []Vector3;
    triangle_b_cpu: []Vector3;
    triangle_c_cpu: []Vector3;
    triangle_color_cpu: []Vector4;
    triangle_a_gpu: Gpu_Ptr;
    triangle_b_gpu: Gpu_Ptr;
    triangle_c_gpu: Gpu_Ptr;
    triangle_color_gpu: Gpu_Ptr;

    params_cpu: *Gizmo_Render_Params_GPU;
    params_gpu: Gpu_Ptr;
    triangle_params_cpu: *Gizmo_Render_Triangle_Params_GPU;
    triangle_params_gpu: Gpu_Ptr;
    view_projection_cpu: *Matrix4;
    view_projection_gpu: Gpu_Ptr;
    viewport_size_cpu: *Vector2;
    viewport_size_gpu: Gpu_Ptr;
}

init :: (ctx: *Gizmo_Render_Context, max_lines: s64 = 64000) -> bool {
    ctx.* = .{};
    if max_lines <= 0 max_lines = 1024;
    ctx.max_lines = max_lines;
    ctx.max_triangles = max_lines;

    line_shader_source := cast([]u8) GIZMO_RENDER_LINE_METAL_SOURCE;
    triangle_shader_source := cast([]u8) GIZMO_RENDER_TRIANGLE_METAL_SOURCE;

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

    ctx.pipeline_no_depth = gpu_create_graphics_pipeline(line_shader_source, raster_no_depth);
    ctx.pipeline_with_depth = gpu_create_graphics_pipeline(line_shader_source, raster_with_depth);
    ctx.triangle_pipeline_no_depth = gpu_create_graphics_pipeline(triangle_shader_source, raster_no_depth);
    ctx.triangle_pipeline_with_depth = gpu_create_graphics_pipeline(triangle_shader_source, raster_with_depth);
    if ctx.pipeline_no_depth == 0 || ctx.pipeline_with_depth == 0 || ctx.triangle_pipeline_no_depth == 0 || ctx.triangle_pipeline_with_depth == 0 {
        return false;
    }

    line_bytes := max_lines * (size_of(Vector3) * 2 + size_of(u32) + size_of(u16));
    triangle_bytes := ctx.max_triangles * (size_of(Vector3) * 3 + size_of(Vector4));
    bytes := line_bytes + triangle_bytes + size_of(Gizmo_Render_Params_GPU) + size_of(Gizmo_Render_Triangle_Params_GPU) + size_of(Matrix4) + size_of(Vector2) + 4096;
    ctx.gpu_arena = gpu_make_arena(bytes, label = "gizmo render arena");
    if ctx.gpu_arena.cpu == null {
        log_error("failed to allocate gizmo render arena");
        return false;
    }

    ctx.line_a_cpu, ctx.line_a_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, max_lines);
    ctx.line_b_cpu, ctx.line_b_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, max_lines);
    ctx.line_color_cpu, ctx.line_color_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, u32, max_lines);
    ctx.line_thickness_cpu, ctx.line_thickness_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, u16, max_lines);
    ctx.triangle_a_cpu, ctx.triangle_a_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, ctx.max_triangles);
    ctx.triangle_b_cpu, ctx.triangle_b_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, ctx.max_triangles);
    ctx.triangle_c_cpu, ctx.triangle_c_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector3, ctx.max_triangles);
    ctx.triangle_color_cpu, ctx.triangle_color_gpu = gpu_arena_array_alloc(*ctx.gpu_arena, Vector4, ctx.max_triangles);
    ctx.params_cpu, ctx.params_gpu = gpu_arena_alloc(*ctx.gpu_arena, Gizmo_Render_Params_GPU);
    ctx.triangle_params_cpu, ctx.triangle_params_gpu = gpu_arena_alloc(*ctx.gpu_arena, Gizmo_Render_Triangle_Params_GPU);
    ctx.view_projection_cpu, ctx.view_projection_gpu = gpu_arena_alloc(*ctx.gpu_arena, Matrix4);
    ctx.viewport_size_cpu, ctx.viewport_size_gpu = gpu_arena_alloc(*ctx.gpu_arena, Vector2);
    if ctx.params_cpu == null || ctx.triangle_params_cpu == null || ctx.view_projection_cpu == null || ctx.viewport_size_cpu == null {
        log_error("failed to allocate gizmo render buffers");
        return false;
    }

    ctx.params_cpu.a = cast(*Vector3) ctx.line_a_gpu;
    ctx.params_cpu.b = cast(*Vector3) ctx.line_b_gpu;
    ctx.params_cpu.color = cast(*u32) ctx.line_color_gpu;
    ctx.params_cpu.thickness = cast(*u16) ctx.line_thickness_gpu;
    ctx.params_cpu.view_projection = cast(*Matrix4) ctx.view_projection_gpu;
    ctx.params_cpu.viewport_size = cast(*Vector2) ctx.viewport_size_gpu;
    ctx.triangle_params_cpu.a = cast(*Vector3) ctx.triangle_a_gpu;
    ctx.triangle_params_cpu.b = cast(*Vector3) ctx.triangle_b_gpu;
    ctx.triangle_params_cpu.c = cast(*Vector3) ctx.triangle_c_gpu;
    ctx.triangle_params_cpu.color = cast(*Vector4) ctx.triangle_color_gpu;
    ctx.triangle_params_cpu.view_projection = cast(*Matrix4) ctx.view_projection_gpu;

    ctx.view_projection_cpu.* = Matrix4_Identity;
    ctx.viewport_size_cpu.* = .{1.0, 1.0};

    gpu_commit_residency();
    ctx.initialized = true;
    return true;
}

deinit :: (ctx: *Gizmo_Render_Context) {
    if !ctx.initialized return;
    if ctx.bound_gizmo != null {
        Gizmo.clear_external_line_sink(ctx.bound_gizmo);
        Gizmo.clear_external_triangle_sink(ctx.bound_gizmo);
        ctx.bound_gizmo = null;
    }
    if ctx.pipeline_no_depth != 0 gpu_free_pipeline(ctx.pipeline_no_depth);
    if ctx.pipeline_with_depth != 0 gpu_free_pipeline(ctx.pipeline_with_depth);
    if ctx.triangle_pipeline_no_depth != 0 gpu_free_pipeline(ctx.triangle_pipeline_no_depth);
    if ctx.triangle_pipeline_with_depth != 0 gpu_free_pipeline(ctx.triangle_pipeline_with_depth);
    if ctx.gpu_arena.cpu != null gpu_free_arena(ctx.gpu_arena);
    ctx.* = .{};
}

bind_gizmo :: (ctx: *Gizmo_Render_Context, gizmos: *Gizmo.Gizmo_Context) {
    if !ctx.initialized return;
    if gizmos == null return;

    if ctx.bound_gizmo != null && ctx.bound_gizmo != gizmos {
        Gizmo.clear_external_line_sink(ctx.bound_gizmo);
        Gizmo.clear_external_triangle_sink(ctx.bound_gizmo);
    }

    Gizmo.set_external_line_sink(gizmos, ctx.line_a_cpu, ctx.line_b_cpu, ctx.line_color_cpu, ctx.line_thickness_cpu);
    Gizmo.set_external_triangle_sink(gizmos, ctx.triangle_a_cpu, ctx.triangle_b_cpu, ctx.triangle_c_cpu, ctx.triangle_color_cpu);
    ctx.bound_gizmo = gizmos;
}

unbind_gizmo :: (ctx: *Gizmo_Render_Context) {
    if ctx.bound_gizmo == null return;
    Gizmo.clear_external_line_sink(ctx.bound_gizmo);
    Gizmo.clear_external_triangle_sink(ctx.bound_gizmo);
    ctx.bound_gizmo = null;
}

gizmo_render_set_view_projection :: (ctx: *Gizmo_Render_Context, view_projection: Matrix4) {
    if !ctx.initialized return;
    ctx.view_projection_cpu.* = view_projection;
}

gizmo_render_set_identity_view_projection :: (ctx: *Gizmo_Render_Context) {
    gizmo_render_set_view_projection(ctx, Matrix4_Identity);
}

gizmo_render_upload :: (ctx: *Gizmo_Render_Context, gizmos: *Gizmo.Gizmo_Context, viewport_size: Vector2) -> Gizmo_Render_Uploaded {
    if !ctx.initialized return .{};
    if !Gizmo.is_line_sink_bound(gizmos) return .{};
    if !Gizmo.is_triangle_sink_bound(gizmos) return .{};

    line_count := Gizmo.line_count(gizmos);
    if line_count > ctx.max_lines line_count = ctx.max_lines;

    triangle_count := Gizmo.triangle_count(gizmos);
    if triangle_count > ctx.max_triangles {
        triangle_count = ctx.max_triangles;
    }

    ctx.viewport_size_cpu.* = viewport_size;
    return .{
        line_count = cast(u32) line_count,
        triangle_count = cast(u32) triangle_count,
    };
}

gizmo_render_draw_uploaded :: (ctx: *Gizmo_Render_Context, cmd: Gpu_Command_Buffer, counts: Gizmo_Render_Uploaded, depth_mode: Gizmo_Render_Depth_Mode = .NONE) -> Gpu_Result {
    if !ctx.initialized return .ERROR_INVALID_PIPELINE;
    if counts.line_count == 0 && counts.triangle_count == 0 return .SUCCESS;

    triangle_pipeline := ctx.triangle_pipeline_no_depth;
    line_pipeline := ctx.pipeline_no_depth;

    if depth_mode == .TEST {
        gpu_set_depth_stencil_state(cmd, .{depth_test = .LESS, depth_mode = .READ});
        triangle_pipeline = ctx.triangle_pipeline_with_depth;
        line_pipeline = ctx.pipeline_with_depth;
    } else {
        gpu_set_depth_stencil_state(cmd, .{depth_test = .ALWAYS, depth_mode = .NONE});
    }

    if counts.triangle_count > 0 {
        pipeline_result := gpu_set_pipeline(cmd, triangle_pipeline);
        if pipeline_result != .SUCCESS return pipeline_result;
        draw_result := gpu_draw_instanced_direct(cmd, ctx.triangle_params_gpu, 3, counts.triangle_count);
        if draw_result != .SUCCESS return draw_result;
    }

    if counts.line_count > 0 {
        pipeline_result := gpu_set_pipeline(cmd, line_pipeline);
        if pipeline_result != .SUCCESS return pipeline_result;
        draw_result := gpu_draw_instanced_direct(cmd, ctx.params_gpu, 6, counts.line_count);
        if draw_result != .SUCCESS return draw_result;
    }

    return .SUCCESS;
}

gizmo_render_draw :: (ctx: *Gizmo_Render_Context, cmd: Gpu_Command_Buffer, gizmos: *Gizmo.Gizmo_Context, viewport_size: Vector2, depth_mode: Gizmo_Render_Depth_Mode = .NONE) -> Gpu_Result {
    counts := gizmo_render_upload(ctx, gizmos, viewport_size);
    return gizmo_render_draw_uploaded(ctx, cmd, counts, depth_mode);
}

#scope_file

Gizmo_Render_Uploaded :: struct {
    line_count: u32;
    triangle_count: u32;
}

Gizmo_Render_Params_GPU :: struct {
    a: *Vector3;
    b: *Vector3;
    color: *u32;
    thickness: *u16;
    view_projection: *Matrix4;
    viewport_size: *Vector2;
}

Gizmo_Render_Triangle_Params_GPU :: struct {
    a: *Vector3;
    b: *Vector3;
    c: *Vector3;
    color: *Vector4;
    view_projection: *Matrix4;
}

GIZMO_RENDER_LINE_METAL_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Matrix4RowMajor {
    float _11, _12, _13, _14;
    float _21, _22, _23, _24;
    float _31, _32, _33, _34;
    float _41, _42, _43, _44;
};

struct GizmoRenderParams {
    device packed_float3* a;
    device packed_float3* b;
    device uint* color;
    device ushort* thickness;
    constant Matrix4RowMajor* view_projection;
    device float2* viewport_size;
};

struct VSOut {
    float4 position [[position]];
    float4 color [[user(locn0)]];
};

static inline float4 mul_row_major(constant Matrix4RowMajor& m, float4 v) {
    return float4(
        m._11 * v.x + m._12 * v.y + m._13 * v.z + m._14 * v.w,
        m._21 * v.x + m._22 * v.y + m._23 * v.z + m._24 * v.w,
        m._31 * v.x + m._32 * v.y + m._33 * v.z + m._34 * v.w,
        m._41 * v.x + m._42 * v.y + m._43 * v.z + m._44 * v.w
    );
}

static inline float2 quad_corner(uint vertex_id) {
    switch (vertex_id) {
        case 0: return float2(0.0, -1.0);
        case 1: return float2(1.0, -1.0);
        case 2: return float2(1.0,  1.0);
        case 3: return float2(0.0, -1.0);
        case 4: return float2(1.0,  1.0);
        default: return float2(0.0,  1.0);
    }
}

vertex VSOut VertexMain(const device GizmoRenderParams& params [[buffer(0)]], uint vertex_id [[vertex_id]], uint instance_id [[instance_id]]) {
    VSOut out = {};
    float3 a_world = params.a[instance_id];
    float3 b_world = params.b[instance_id];
    uint packed_color = params.color[instance_id];
    float4 line_color = float4(
        float((packed_color >> 0) & 0xff) / 255.0,
        float((packed_color >> 8) & 0xff) / 255.0,
        float((packed_color >> 16) & 0xff) / 255.0,
        float((packed_color >> 24) & 0xff) / 255.0
    );
    float line_thickness = float(as_type<half>(params.thickness[instance_id]));
    float2 viewport = params.viewport_size[0];
    if (viewport.x <= 1.0) viewport.x = 1.0;
    if (viewport.y <= 1.0) viewport.y = 1.0;

    float4 clip_a = mul_row_major(params.view_projection[0], float4(a_world, 1.0));
    float4 clip_b = mul_row_major(params.view_projection[0], float4(b_world, 1.0));
    float wa = (abs(clip_a.w) < 1e-5) ? ((clip_a.w < 0.0) ? -1e-5 : 1e-5) : clip_a.w;
    float wb = (abs(clip_b.w) < 1e-5) ? ((clip_b.w < 0.0) ? -1e-5 : 1e-5) : clip_b.w;
    float3 ndc_a = float3(clip_a.x / wa, clip_a.y / wa, clip_a.z / wa);
    float3 ndc_b = float3(clip_b.x / wb, clip_b.y / wb, clip_b.z / wb);

    float2 a_px = float2((ndc_a.x * 0.5 + 0.5) * viewport.x, (ndc_a.y * 0.5 + 0.5) * viewport.y);
    float2 b_px = float2((ndc_b.x * 0.5 + 0.5) * viewport.x, (ndc_b.y * 0.5 + 0.5) * viewport.y);

    float2 dir = b_px - a_px;
    float len2 = dot(dir, dir);
    if (len2 <= 1e-6) dir = float2(1.0, 0.0);
    else dir *= rsqrt(len2);
    float2 perp = float2(-dir.y, dir.x);

    float2 corner = quad_corner(vertex_id);
    float t = corner.x;
    float side = corner.y;
    float2 center_px = a_px + (b_px - a_px) * t;
    float half_w = line_thickness * 0.5;
    if (half_w < 0.5) half_w = 0.5;
    float2 p_px = center_px + perp * side * half_w;

    float2 delta_px = p_px - center_px;
    float2 delta_ndc = float2((delta_px.x / viewport.x) * 2.0, (delta_px.y / viewport.y) * 2.0);
    float4 base_clip = (t < 0.5) ? clip_a : clip_b;
    out.position = base_clip;
    out.position.x += delta_ndc.x * base_clip.w;
    out.position.y += delta_ndc.y * base_clip.w;
    out.color = line_color;
    return out;
}

fragment float4 FragmentMain(VSOut in [[stage_in]]) {
    return in.color;
}
END

GIZMO_RENDER_TRIANGLE_METAL_SOURCE :: #string END
#include <metal_stdlib>
using namespace metal;

struct Matrix4RowMajor {
    float _11, _12, _13, _14;
    float _21, _22, _23, _24;
    float _31, _32, _33, _34;
    float _41, _42, _43, _44;
};

struct GizmoRenderTriangleParams {
    device packed_float3* a;
    device packed_float3* b;
    device packed_float3* c;
    device float4* color;
    constant Matrix4RowMajor* view_projection;
};

struct VSOut {
    float4 position [[position]];
    float4 color [[user(locn0)]];
};

static inline float4 mul_row_major(constant Matrix4RowMajor& m, float4 v) {
    return float4(
        m._11 * v.x + m._12 * v.y + m._13 * v.z + m._14 * v.w,
        m._21 * v.x + m._22 * v.y + m._23 * v.z + m._24 * v.w,
        m._31 * v.x + m._32 * v.y + m._33 * v.z + m._34 * v.w,
        m._41 * v.x + m._42 * v.y + m._43 * v.z + m._44 * v.w
    );
}

vertex VSOut VertexMain(const device GizmoRenderTriangleParams& params [[buffer(0)]], uint vertex_id [[vertex_id]], uint instance_id [[instance_id]]) {
    VSOut out = {};

    float3 p_world = params.a[instance_id];
    if (vertex_id == 1) p_world = params.b[instance_id];
    else if (vertex_id == 2) p_world = params.c[instance_id];

    out.position = mul_row_major(params.view_projection[0], float4(p_world, 1.0));
    out.color = params.color[instance_id];
    return out;
}

fragment float4 FragmentMain(VSOut in [[stage_in]]) {
    return in.color;
}
END

Gizmo :: #import "Gizmo";
#import "sgpu";
#import "Math";
#import "Basic";
