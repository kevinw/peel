#include <metal_stdlib>
using namespace metal;

struct Vertex_In {
    float2 a_pos [[attribute(0)]];
    uint vertex_id [[attribute(1)]];
    uint instance_id [[attribute(2)]];
};

struct Vertex_Uniforms {
};

struct Vertex_Out {
    float4 gl_Position [[position]];
};


vertex Vertex_Out VertexMain(Vertex_In in [[stage_in]], constant Vertex_Uniforms& un [[buffer(0)]]) {
     float2 a_pos = in.a_pos;
     uint vertex_id = in.vertex_id;
     uint instance_id = in.instance_id;
     float4 gl_Position;

     gl_Position = float4(vertex_id * 0.2, instance_id * 0.2, 0, 1);
     Vertex_Out out;
     out.gl_Position = gl_Position;
     return out;
}

