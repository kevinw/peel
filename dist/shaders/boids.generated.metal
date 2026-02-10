#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 3 "shaders/boids.slang"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 3
struct pixelInput_0
{
    float3 color_0 [[user(COLOR)]];
};

struct Vertex_Buffers_0
{
    float2 device* positions_0;
    float4 device* colors_0;
    float2 device* instances_0;
};


#line 1 "shaders/common.slang"
struct VertexParams_0
{
    Vertex_Buffers_0 device* data_0;
};


#line 36 "shaders/boids.slang"
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], VertexParams_0 constant* sp_0 [[buffer(0)]])
{

#line 36
    pixelOutput_0 _S2 = { float4(_S1.color_0, 1.0) };


    return _S2;
}


#line 39
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_1 [[user(COLOR)]];
};


#line 3
struct VS_Output_0
{
    float4 position_1;
    float3 color_2;
};


#line 22
[[vertex]] vertexMain_Result_0 vertexMain(uint vertex_id_0 [[vertex_id]], uint instance_id_0 [[instance_id]], VertexParams_0 constant* sp_1 [[buffer(0)]])
{

#line 19
    thread VS_Output_0 output_1;

    (&output_1)->position_1 = float4(*((*sp_1).data_0->positions_0 + vertex_id_0) + *((*sp_1).data_0->instances_0 + instance_id_0), 0.0, 1.0);
    (&output_1)->color_2 = (*((*sp_1).data_0->colors_0 + vertex_id_0)).xyz;

#line 22
    thread vertexMain_Result_0 _S3;

#line 22
    (&_S3)->position_0 = output_1.position_1;

#line 22
    (&_S3)->color_1 = output_1.color_2;

#line 22
    return _S3;
}

