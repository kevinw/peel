#import "Jai-Shader-Transpiler";
#import "Math";

RD_WIDTH  :: 128;
RD_HEIGHT :: 128;
RD_CELL_COUNT :: RD_WIDTH * RD_HEIGHT;

RD_DT      :: 1.0;
RD_DIFF_A  :: 1.0;
RD_DIFF_B  :: 0.5;
RD_FEED    :: 0.055;
RD_KILL    :: 0.062;

RD_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

UVector3 :: struct {
    x, y, z: u32;
}

RD_Compute_Params :: struct {
    src: *Vector2;
    dst: *Vector2;
}

RD_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

RD_Vertex_Params :: struct {
    positions: *Vector2;
    state: *Vector2;
}

RD_Vertex_Out :: struct {
    gl_Position: Vector4; @position
}

RD_Fragment_In :: struct {
    gl_FragCoord: Vector4; @frag_coord
}

rd_cell_index :: (x: u32, y: u32) -> u32 {
    return y * RD_WIDTH + x;
}

rd_wrap_left :: (x: u32) -> u32 {
    if x == 0 return RD_WIDTH - 1;
    return x - 1;
}

rd_wrap_right :: (x: u32) -> u32 {
    n := x + 1;
    if n >= RD_WIDTH return 0;
    return n;
}

rd_wrap_down :: (y: u32) -> u32 {
    if y == 0 return RD_HEIGHT - 1;
    return y - 1;
}

rd_wrap_up :: (y: u32) -> u32 {
    n := y + 1;
    if n >= RD_HEIGHT return 0;
    return n;
}

rd_clamp01 :: (v: float) -> float {
    if v < 0 return 0;
    if v > 1 return 1;
    return v;
}

rd_step_compute :: (using in: RD_Compute_In, data: *RD_Compute_Params) {
    if thread_id.x >= 16384 return;

    i := thread_id.x;
    row_start := i - (i % 128);

    left := i - 1;
    if i == row_start left = row_start + 127;

    right := i + 1;
    if (i + 1) == row_start + 128 right = row_start;

    up := i - 128;
    if i < 128 up = i + 16256;

    down := i + 128;
    if i >= 16256 down = i - 16256;

    s := data.src[i];
    a := s.x;
    b := s.y;

    lap_a := data.src[left].x + data.src[right].x + data.src[up].x + data.src[down].x - 4.0 * a;
    lap_b := data.src[left].y + data.src[right].y + data.src[up].y + data.src[down].y - 4.0 * b;

    reaction := a * b * b;
    next_a := a + (1.0 * lap_a - reaction + 0.055 * (1.0 - a)) * 1.0;
    next_b := b + (0.5 * lap_b + reaction - (0.062 + 0.055) * b) * 1.0;

    data.dst[i] = .{
        rd_clamp01(next_a),
        rd_clamp01(next_b),
    };
} @compute_shader

rd_vertex_corner :: (vid: u32) -> Vector2 {
    if vid == 0 return .{-1, -1};
    if vid == 1 return .{+1, -1};
    if vid == 2 return .{+1, +1};
    if vid == 3 return .{-1, -1};
    if vid == 4 return .{+1, +1};
    return .{-1, +1};
}

rd_vertex_main :: (using in: RD_Vertex_In, data: *RD_Vertex_Params) -> RD_Vertex_Out {
    using out: RD_Vertex_Out;
    pos := data.positions[vertex_id];
    noop := data.state[0].x * 0.0;
    gl_Position = .{ pos.x, pos.y, noop, 1.0 };

    return out;
} @vertex_shader

rd_fragment_main :: (using in: RD_Fragment_In, data: *RD_Vertex_Params) -> struct { out_color: Vector4; } {
    px := cast(u32) (gl_FragCoord.x * 0.10666667);
    py := cast(u32) (gl_FragCoord.y * 0.16);
    if px >= 128 px = 127;
    if py >= 128 py = 127;

    idx := py * 128 + px;
    s := data.state[idx];
    tone := rd_clamp01(s.y - s.x * 0.35);

    return .{
        out_color = .{
            tone * 1.8,
            tone * tone * 0.9 + 0.1,
            1.0 - tone * 0.6,
            1.0,
        }
    };
} @fragment_shader
