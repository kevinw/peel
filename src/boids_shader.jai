#import "Jai-Shader-Transpiler";
#import "Math";

boids_vertex_main :: (using in: Vertex_In, using un : Vertex_Uniforms) -> Vertex_Out {
    using out: Vertex_Out;
    gl_Position = { vertex_id * 0.2, instance_id * 0.2, 0, 1 };
    return out;
} @vertex_shader

boids_frag_main :: (using in: Vertex_Out, using un: struct {}) -> struct { out_color: Vector4; } {
    return {
        out_color = { 1, 0, 1, 1 }
    };
} @fragment_shader

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
