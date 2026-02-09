import "common";

struct VS_Output {
    float4 position : SV_POSITION;
    float3 color : COLOR;
}

struct Vertex_Buffers {
    float2* positions;
    float4* colors;
};

[vk::push_constant]
VertexParams<Vertex_Buffers> sp;

[shader("vertex")]
VS_Output vertexMain(uint vertex_id: SV_VertexID) {
    VS_Output output;
    output.position = float4(sp.get().positions[vertex_id], 0., 1.);
    output.color = sp.get().colors[vertex_id].xyz;
    return output;
}

//

struct PS_Input {
    float3 color: COLOR;
}

[vk::push_constant]
PixelParams<float3> color;

[shader("pixel")]
float4 fragmentMain(PS_Input input) : SV_Target0 {
    // can either fetch the color from the shader inputs or from the vertex colors.
    //return float4(float3(color.get()[0]), 1.);
    return float4(input.color, 1.0);
}
