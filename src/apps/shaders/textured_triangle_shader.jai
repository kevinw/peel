#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

Textured_Triangle_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Textured_Triangle_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Textured_Triangle_Pixel_Params :: struct {
    texture_index: u32;
    sampler_index: u32;
    debug_mode: u32;
    _pad: u32;
}

textured_triangle_vertex_main :: (using in: Textured_Triangle_Vertex_In) -> Textured_Triangle_Vertex_Out {
    using out: Textured_Triangle_Vertex_Out;
    pos: Vector2;
    uv_local: Vector2;

    if vertex_id == 0 {
        pos = .{0.0, 0.82};
        uv_local = .{0.5, 1.0};
    } else if vertex_id == 1 {
        pos = .{-0.82, -0.66};
        uv_local = .{0.0, 0.0};
    } else {
        pos = .{0.82, -0.66};
        uv_local = .{1.0, 0.0};
    }

    _ = instance_id;
    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = uv_local;
    return out;
} @vertex_shader

textured_triangle_fragment_main :: (using in: struct { uv: Vector2; }, params: *Textured_Triangle_Pixel_Params) -> Vector4 @SV_Target0 {
    debug: Vector4 = .{
        min(1.0, cast(float) params[0].texture_index),
        min(1.0, cast(float) params[0].sampler_index),
        0.0,
        1.0
    };
    if (params[0].debug_mode & 1) != 0 {
        return debug;
    }
    if false {
        return Vector4.{uv.x, uv.y, 0, 1};
    }
    return sample_2d(params[0].texture_index, params[0].sampler_index, uv);
} @fragment_shader
