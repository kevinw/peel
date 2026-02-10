import "common";

struct VS_Output {
    float4 position : SV_POSITION;
    float3 color : COLOR;
}

struct Vertex_Buffers {
    float2* positions;
    float4* colors;
    float2* instances;
};

[vk::push_constant]
VertexParams<Vertex_Buffers> sp;

[shader("vertex")]
VS_Output vertexMain(uint vertex_id: SV_VertexID, uint instance_id: SV_InstanceID) {
    float2 instance_position = sp.get().instances[instance_id];
    VS_Output out;
    out.position = float4(sp.get().positions[vertex_id] + instance_position, 0., 1.);
    out.color = sp.get().colors[vertex_id].xyz;
    return out;
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
