#include <metal_stdlib>
using namespace metal;

struct Vertex_Out {
};

struct Pixel_Params {
    float device* color;
};

struct UnnamedStruct1 {
    float4 out_color [[color(0)]];
};


fragment UnnamedStruct1 FragmentMain(Vertex_Out in [[stage_in]], constant Pixel_Params* params_ptr [[buffer(0)]]) {
     Pixel_Params params = *params_ptr;
     float4 out_color;

     UnnamedStruct1 out;
     out.out_color = out_color;
     return out;
}

