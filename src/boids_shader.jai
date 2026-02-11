#import "Jai-Shader-Transpiler";
#import "Math";

boids_vertex_main :: (using in: Vertex_In, vertex_data: *Vertex_Params) -> Vertex_Out {
    using out: Vertex_Out;
    instance_position := vertex_data.instances[instance_id];
    pos := vertex_data.positions[vertex_id] + instance_position;
    gl_Position = { pos.x, pos.y, 0, 1 };
    return out;
} @vertex_shader

boids_frag_main :: (using in: Vertex_Out, fragment_data: *Pixel_Params) -> struct { out_color: Vector4; } {
    return {
        out_color = { fragment_data.color[0], fragment_data.color[1], fragment_data.color[2], 1 }
    };
} @fragment_shader

Vertex_Params :: struct {
    positions: *Vector2;
    colors: *Vector4;
    instances: *Vector2;
}

Pixel_Params :: struct {
    color: *float;
}

#scope_file

Vertex_Out :: struct {
    gl_Position: Vector4; @position
}

Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Vertex_Uniforms :: struct {}
