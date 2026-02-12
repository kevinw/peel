#import "Jai-Shader-Transpiler";
#import "Math";

boids_vertex_main :: (using in: Vertex_In, data: *All_Params) -> Vertex_Out {
    //using data.v;
    using out: Vertex_Out;
    instance_position := data.v.instances[instance_id];
    pos := data.v.positions[vertex_id] + instance_position;
    gl_Position = { pos.x, pos.y, 0, 1 };
    return out;
} @vertex_shader

boids_frag_main :: (using in: Vertex_Out, data: *All_Params) -> struct { out_color: Vector4; } {
    return {
        //out_color = { data.p.color[0], data.p.color[1], data.p.color[2], 1 }
        out_color = { 1, 0, 1, 1 }
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

All_Params :: struct {
    v: *Vertex_Params;
    p: *Pixel_Params;
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
