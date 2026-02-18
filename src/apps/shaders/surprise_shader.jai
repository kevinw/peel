#import "Jai-Shader-Transpiler";
#import "Math";

SURPRISE_PARTICLE_COUNT :: 100;

UVector3 :: struct {
    x, y, z: u32;
}

Surprise_State :: struct {
    pos: Vector2;
    vel: Vector2;
    hue: float;
    life: float;
}

Surprise_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Surprise_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Surprise_Vertex_Params :: struct {
    quad: *Vector2;
    sparks: *Surprise_State;
}

Surprise_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    local_uv: Vector2;
    hue: float;
    life: float;
    speed: float;
}

Surprise_Fragment_In :: struct {
    local_uv: Vector2;
    hue: float;
    life: float;
    speed: float;
}

surprise_fract :: (x: float) -> float {
    return x - floor(x);
}

surprise_hash1 :: (x: float) -> float {
    return surprise_fract(sin(x) * cast(float) 43758.5453);
}

surprise_clamp01 :: (x: float) -> float {
    if x < 0.0 return 0.0;
    if x > 1.0 return 1.0;
    return x;
}

surprise_respawn :: (i: u32, old: Surprise_State) -> Surprise_State {
    seed := cast(float) i * 12.9898 + old.hue * 78.233 + old.pos.x * 37.719 + old.pos.y * 11.131;
    angle := surprise_hash1(seed) * 6.2831853;
    radius := 0.08 + 0.35 * surprise_hash1(seed + 1.7);
    p := Vector2.{cos(angle) * radius, sin(angle) * radius};
    tangent := Vector2.{-p.y, p.x};
    speed := 0.002 + 0.006 * surprise_hash1(seed + 4.1);

    out := old;
    out.pos = p;
    out.vel = Vector2.{tangent.x * speed, tangent.y * speed};
    out.hue = surprise_hash1(seed + 8.3);
    out.life = 0.65 + 0.35 * surprise_hash1(seed + 13.9);
    return out;
}

surprise_step_compute :: (using in: Surprise_Compute_In, sparks: *Surprise_State) {
    if thread_id.x >= SURPRISE_PARTICLE_COUNT return;

    i := thread_id.x;
    s := sparks[i];

    next_life := s.life - 0.006;
    r2 := s.pos.x * s.pos.x + s.pos.y * s.pos.y;
    if next_life <= 0.0 || r2 > 2.8 {
        sparks[i] = surprise_respawn(i, s);
        return;
    }

    inv_r := 1.0 / sqrt(max(r2, 0.0004));
    spiral := Vector2.{-s.pos.y * inv_r, s.pos.x * inv_r};
    pull := Vector2.{-s.pos.x * 0.0012, -s.pos.y * 0.0012};
    wobble_phase := s.hue * 6.2831853 + s.life * 24.0;
    wobble := Vector2.{cos(wobble_phase), sin(wobble_phase)};
    wobble = .{wobble.x * 0.0007, wobble.y * 0.0007};

    accel := Vector2.{
        spiral.x * 0.0018 + pull.x + wobble.x,
        spiral.y * 0.0018 + pull.y + wobble.y,
    };

    s.vel = .{s.vel.x * 0.992 + accel.x, s.vel.y * 0.992 + accel.y};
    s.pos = .{s.pos.x + s.vel.x, s.pos.y + s.vel.y};
    s.hue = surprise_fract(s.hue + 0.0012 + 0.0008 * surprise_hash1(cast(float) i + s.life * 31.0));
    s.life = next_life;

    sparks[i] = s;
} @compute_shader

surprise_vertex_main :: (using in: Surprise_Vertex_In, data: *Surprise_Vertex_Params) -> Surprise_Vertex_Out {
    using out: Surprise_Vertex_Out;

    p := data.sparks[instance_id];
    quad := data.quad[vertex_id];

    local_speed := sqrt(p.vel.x * p.vel.x + p.vel.y * p.vel.y);
    size := 0.0045 + (1.0 - p.life) * 0.006 + local_speed * 18.0;

    world := Vector2.{p.pos.x + quad.x * size, p.pos.y + quad.y * size};

    gl_Position = .{world.x, world.y, 0.0, 1.0};
    local_uv = quad;
    hue = p.hue;
    life = p.life;
    speed = local_speed;

    return out;
} @vertex_shader

surprise_fragment_main :: (using in: Surprise_Fragment_In, data: *Surprise_Vertex_Params) -> Vector4 @SV_Target0 {
    _ = data;
    r2 := local_uv.x * local_uv.x + local_uv.y * local_uv.y;
    core := surprise_clamp01(1.0 - r2);
    glow := core * core;

    t := hue;
    red := 0.45 + 0.45 * cos(6.2831853 * (t + 0.00));
    green := 0.45 + 0.45 * cos(6.2831853 * (t + 0.33));
    blue := 0.45 + 0.45 * cos(6.2831853 * (t + 0.66));

    boost := 0.35 + speed * 30.0 + (1.0 - life) * 0.6;
    color := Vector3.{red * boost * glow, green * boost * glow, blue * boost * glow};

    return .{color.x, color.y, color.z, glow * 0.9};
} @fragment_shader
