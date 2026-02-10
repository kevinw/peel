#include <metal_stdlib>
using namespace metal;

struct Vertex_In {
    float2 a_pos [[attribute(0)]];
    uint vertex_id [[attribute(1)]];
    uint instance_id [[attribute(2)]];
};

struct Vertex_Params {
    float2 device* positions;
    float4 device* colors;
    float2 device* instances;
};

struct Vertex_Out {
    float4 gl_Position [[position]];
};


vertex Vertex_Out VertexMain(Vertex_In in [[stage_in]], constant Vertex_Params* params_ptr [[buffer(0)]]) {
     float2 a_pos = in.a_pos;
     uint vertex_id = in.vertex_id;
     uint instance_id = in.instance_id;
     Vertex_Params params = *params_ptr;
     float4 gl_Position;

     float2 instance_position = params.instances[instance_id];
     float2 pos = params.positions[vertex_id] + instance_position;
     gl_Position = float4(pos.x, pos.y, 0, 1);
     Vertex_Out out;
     out.gl_Position = gl_Position;
     return out;
}

