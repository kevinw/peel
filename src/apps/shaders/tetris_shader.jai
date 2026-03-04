#import "Jai-Shader-Transpiler";
#import "Math";

TETRIS_MAX_RENDER_INSTANCES :: 8192;

TETRIS_BLOCK_FLAG_GHOST :: cast(u32) 1;
TETRIS_BLOCK_FLAG_BACKGROUND :: cast(u32) 2;
TETRIS_BLOCK_FLAG_PARTICLE :: cast(u32) 4;

Tetris_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Tetris_Block_Instance :: struct {
    center: Vector2;
    half_size: Vector2;
    color: Vector4;
    flags: u32;
    anim: float;
    angle: float;
    pad0: float;
}

Tetris_Vertex_Params :: struct {
    quad: *Vector2;
    blocks: *Tetris_Block_Instance;
}

Tetris_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    local_uv: Vector2;
    color: Vector4;
    flags: float;
    anim: float;
}

Tetris_Fragment_In :: struct {
    local_uv: Vector2;
    color: Vector4;
    flags: float;
    anim: float;
}

tetris_saturate :: (x: float) -> float {
    if x < 0.0 return 0.0;
    if x > 1.0 return 1.0;
    return x;
}

tetris_max2 :: (a: Vector2, b: Vector2) -> Vector2 {
    return .{max(a.x, b.x), max(a.y, b.y)};
}

tetris_abs2 :: (a: Vector2) -> Vector2 {
    return .{abs(a.x), abs(a.y)};
}

tetris_normalize3 :: (v: Vector3) -> Vector3 {
    len2 := dot(v, v);
    if len2 <= 0.0000001 return .{0.0, 0.0, 0.0};
    inv := 1.0 / sqrt(len2);
    return v * inv;
}

tetris_rounded_box_sdf :: (p: Vector2, b: Vector2, r: float) -> float {
    q := tetris_abs2(p) - b;
    outside := length(tetris_max2(q, .{0.0, 0.0}));
    inside := min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

tetris_vertex_main :: (using in: Tetris_Vertex_In, params: *Tetris_Vertex_Params) -> Tetris_Vertex_Out {
    using out: Tetris_Vertex_Out;

    instance := params.blocks[instance_id];
    q := params.quad[vertex_id];

    pulse := 1.0 + 0.12 * instance.anim;
    if (instance.flags & TETRIS_BLOCK_FLAG_PARTICLE) != 0 {
        pulse = 1.0 + 0.35 * instance.anim;
    }

    local := q * pulse;

    if (instance.flags & TETRIS_BLOCK_FLAG_PARTICLE) != 0 {
        c := cos(instance.angle);
        s := sin(instance.angle);
        local = .{
            local.x * c - local.y * s,
            local.x * s + local.y * c,
        };
    }

    pos := instance.center + local * instance.half_size;

    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    local_uv = local;
    color = instance.color;
    flags = cast(float) instance.flags;
    anim = instance.anim;
    return out;
} @vertex_shader

tetris_fragment_main :: (using in: Tetris_Fragment_In, params: *Tetris_Vertex_Params) -> Vector4 @SV_Target0 {
    _ = params;

    size: Vector2 = .{0.74, 0.74};
    radius := 0.28;
    flags_u := cast(u32) (flags + 0.5);
    if (flags_u & TETRIS_BLOCK_FLAG_PARTICLE) != 0 {
        size = .{0.66, 0.66};
        radius = 0.34;
    }

    d := tetris_rounded_box_sdf(local_uv, size, radius);
    alpha := tetris_saturate(1.0 - d * 12.0);
    if alpha <= 0.001 return .{0.0, 0.0, 0.0, 0.0};

    nxy := local_uv * 0.78;
    nz := sqrt(max(0.0, 1.0 - nxy.x * nxy.x - nxy.y * nxy.y));
    normal := tetris_normalize3(Vector3.{nxy.x, nxy.y, nz});

    light_dir := tetris_normalize3(Vector3.{-0.45, 0.72, 0.52});
    view_dir := Vector3.{0.0, 0.0, 1.0};

    ndotl := tetris_saturate(dot(normal, light_dir));
    diffuse := 0.45 + 0.55 * ndotl;

    h := tetris_normalize3(light_dir + view_dir);
    spec := pow(tetris_saturate(dot(normal, h)), 28.0);
    rim := pow(tetris_saturate(1.0 - normal.z), 2.0) * 0.18;

    base_color := Vector3.{color.x, color.y, color.z};
    base := base_color * diffuse;
    highlight := Vector3.{1.0, 0.98, 0.92} * spec * (0.6 + 0.4 * anim);
    out_color := base + highlight + rim * Vector3.{0.3, 0.32, 0.38};

    if (flags_u & TETRIS_BLOCK_FLAG_BACKGROUND) != 0 {
        out_color = base_color * (0.65 + 0.35 * ndotl);
        alpha *= 0.42;
    }

    if (flags_u & TETRIS_BLOCK_FLAG_GHOST) != 0 {
        out_color = base_color * 0.72 + Vector3.{0.08, 0.09, 0.1};
        alpha *= 0.26;
    }

    if (flags_u & TETRIS_BLOCK_FLAG_PARTICLE) != 0 {
        alpha *= 0.85;
        out_color += Vector3.{0.18, 0.17, 0.12} * anim;
    }

    return .{out_color.x, out_color.y, out_color.z, alpha};
} @fragment_shader
