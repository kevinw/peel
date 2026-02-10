#import "Jai-Shader-Transpiler";
#import "Math";

boids_vertex_main :: (using in: Vertex_In, params: Vertex_Params) -> Vertex_Out {
    using out: Vertex_Out;
    instance_position := params.instances[instance_id];
    pos := params.positions[vertex_id] + instance_position;
    gl_Position = { pos.x, pos.y, 0, 1 };
    return out;
} @vertex_shader

boids_frag_main :: (using in: Vertex_Out, params: Pixel_Params) -> struct { out_color: Vector4; } {
    return {
        out_color = { params.color[0], params.color[1], params.color[2], 1 }
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
    a_pos: Vector2;
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Vertex_Uniforms :: struct {}
