#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";

Decal_Painter_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
}

Decal_Painter_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4;
}

Decal_Painter_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    base_color: Vector4;
}

decal_painter_vertex_main :: (using in: Decal_Painter_Vertex_In, params: *Decal_Painter_Draw_Params) -> Decal_Painter_Vertex_Out {
    using out: Decal_Painter_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    world4 := params.model * vec4(vertex.position.xyz, 1.0);
    world_normal := normalize((params.model * vec4(vertex.normal.xyz, 0.0)).xyz);

    world_pos = world4.xyz;
    normal = world_normal;
    base_color = params.base_color;
    gl_Position = params.view_proj * world4;
    return out;
} @vertex_shader

decal_painter_fragment_main :: (using in: Decal_Painter_Fragment_In, params: *Decal_Painter_Draw_Params) -> Vector4 @SV_Target0 {
    n := normalize(normal);
    light_dir := normalize(-params.light_dir);
    ndl := max(dot(n, light_dir), 0.0);
    hemi := dot(n, .{0.0, 1.0, 0.0}) * 0.5 + 0.5;

    albedo := base_color.xyz;
    grid_uv := Vector2.{world_pos.x, world_pos.z};
    grid_axis := abs(fract(grid_uv * 0.5) - .{0.5, 0.5});
    grid_line := 1.0 - smoothstep(0.44, 0.50, min(grid_axis.x, grid_axis.y));
    albedo *= 0.92 + 0.08 * sin(world_pos.x * 0.35 + world_pos.z * 0.22 + params.time * 0.35);
    albedo += Vector3.{grid_line * 0.04, grid_line * 0.04, grid_line * 0.04};

    for decal_i: 0..cast(s64) params.decal_count-1 {
        decal_pos_radius := params.decal_pos_radius[decal_i];
        decal_color_opacity := params.decal_color_opacity[decal_i];
        decal_misc := params.decal_misc[decal_i];

        if dot(n, .{0.0, 1.0, 0.0}) < decal_misc.w continue;

        delta := world_pos - decal_pos_radius.xyz;
        if abs(delta.y) > decal_misc.z continue;

        angle := decal_misc.x;
        c := cos(angle);
        s := sin(angle);
        local := Vector2.{
            delta.x * c - delta.z * s,
            delta.x * s + delta.z * c,
        };
        radius := max(0.0001, decal_pos_radius.w);
        mask: float;

        shape := cast(s32) (decal_misc.y + 0.5);
        if shape == DECAL_PAINTER_SHAPE_CIRCLE {
            dist := length(local);
            mask = 1.0 - smoothstep(radius * 0.65, radius, dist);
        } else if shape == DECAL_PAINTER_SHAPE_BOX {
            dist := max(abs(local.x), abs(local.y));
            mask = 1.0 - smoothstep(radius * 0.65, radius, dist);
        } else {
            span := 1.0 - smoothstep(radius * 0.72, radius, abs(local.x));
            stripe := 1.0 - smoothstep(radius * 0.10, radius * 0.28, abs(local.y));
            band := 0.65 + 0.35 * sin(local.x / radius * 10.0);
            mask = span * stripe * band;
        }

        height_mask := 1.0 - smoothstep(decal_misc.z * 0.35, decal_misc.z, abs(delta.y));
        blend := clamp(mask * height_mask * decal_color_opacity.w, 0.0, 1.0);
        albedo = lerp(albedo, decal_color_opacity.xyz, blend);
    }

    lit := albedo * (0.22 + hemi * 0.18 + ndl * 0.60);
    rim := pow(1.0 - max(dot(n, normalize(params.camera_pos - world_pos)), 0.0), 3.0) * 0.08;
    return vec4(lit + Vector3.{rim, rim, rim}, 1.0);
} @fragment_shader
