#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 3 "shaders/hello_square_vs.slang"
struct main_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
};


#line 8
struct Vertex_Buffers_0
{
    float2 device* positions_0;
    float4 device* colors_0;
};


#line 1 "shaders/common.slang"
struct VertexParams_0
{
    Vertex_Buffers_0 device* data_0;
};


#line 3 "shaders/hello_square_vs.slang"
struct VS_Output_0
{
    float4 position_1;
    float3 color_1;
};


#line 20
[[vertex]] main_Result_0 main_0(uint vertex_id_0 [[vertex_id]], VertexParams_0 constant* sp_0 [[buffer(0)]])
{

#line 18
    thread VS_Output_0 output_0;
    (&output_0)->position_1 = float4(*((*sp_0).data_0->positions_0 + vertex_id_0), 0.0, 1.0);
    (&output_0)->color_1 = (*((*sp_0).data_0->colors_0 + vertex_id_0)).xyz;

#line 20
    thread main_Result_0 _S1;

#line 20
    (&_S1)->position_0 = output_0.position_1;

#line 20
    (&_S1)->color_0 = output_0.color_1;

#line 20
    return _S1;
}

