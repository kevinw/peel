#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 11 "shaders/hello_square_ps.slang"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 3
struct pixelInput_0
{
    float3 color_0 [[user(COLOR)]];
};




[[fragment]] pixelOutput_0 main_0(pixelInput_0 _S1 [[stage_in]])
{

#line 11
    pixelOutput_0 _S2 = { float4(_S1.color_0, 1.0) };


    return _S2;
}

