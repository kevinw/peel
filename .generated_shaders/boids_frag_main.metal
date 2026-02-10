#include <metal_stdlib>
using namespace metal;

struct Vertex_Out {
};

struct UnnamedStruct2 {
};

struct UnnamedStruct1 {
    float4 out_color [[color(0)]];
};


fragment UnnamedStruct1 FragmentMain(Vertex_Out in [[stage_in]], constant UnnamedStruct2& un [[buffer(0)]]) {
     float4 out_color;

     UnnamedStruct1 out;
     out.out_color = out_color;
     return out;
}

