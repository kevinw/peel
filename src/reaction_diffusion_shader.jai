#import "Jai-Shader-Transpiler";
#import "Math";

RD_WIDTH  :: 256;
RD_HEIGHT :: 256;
RD_CELL_COUNT :: RD_WIDTH * RD_HEIGHT;

RD_DT      :: 0.5;
RD_DIFF_A  :: 1.0;
RD_DIFF_B  :: 0.5;
RD_FEED    :: 0.022;
RD_KILL    :: 0.051;
RD_DEBUG_SHOW_UV :: false;
RD_CURSOR_BRUSH_RADIUS :: 10.0;
RD_CURSOR_B_INJECT :: 0.32;
RD_CURSOR_A_SUPPRESS :: 0.22;

RD_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

UVector3 :: struct {
    x, y, z: u32;
}

RD_Compute_Control :: struct {
    cursor_uv: Vector2;
    use_b_as_src: u32;
    cursor_active: u32;
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
    uv: Vector2;
}

RD_Fragment_In :: struct {
    uv: Vector2;
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

rd_wrap_up :: (y: u32) -> u32 {
    if y == 0 return RD_HEIGHT - 1;
    return y - 1;
}

rd_wrap_down :: (y: u32) -> u32 {
    n := y + 1;
    if n >= RD_HEIGHT return 0;
    return n;
}

rd_clamp01 :: (v: float) -> float {
    if v < 0 return 0;
    if v > 1 return 1;
    return v;
}

rd_abs :: (v: float) -> float {
    if v < 0 return -v;
    return v;
}

rd_lerp :: (a: float, b: float, t: float) -> float {
    return a + (b - a) * t;
}

rd_step_compute :: (using in: RD_Compute_In, state: *Vector2, control: *RD_Compute_Control) {
    if thread_id.x >= RD_CELL_COUNT return;

    src_offset: u32 = 0;
    dst_offset: u32 = RD_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = RD_CELL_COUNT;
        dst_offset = 0;
    }

    i := thread_id.x;
    x := i % RD_WIDTH;
    y := i / RD_WIDTH;

    left_x := rd_wrap_left(x);
    right_x := rd_wrap_right(x);
    up_y := rd_wrap_up(y);
    down_y := rd_wrap_down(y);

    left := src_offset + rd_cell_index(left_x, y);
    right := src_offset + rd_cell_index(right_x, y);
    up := src_offset + rd_cell_index(x, up_y);
    down := src_offset + rd_cell_index(x, down_y);
    up_left := src_offset + rd_cell_index(left_x, up_y);
    up_right := src_offset + rd_cell_index(right_x, up_y);
    down_left := src_offset + rd_cell_index(left_x, down_y);
    down_right := src_offset + rd_cell_index(right_x, down_y);

    s := state[src_offset + i];
    a := s.x;
    b := s.y;

    lap_a := 0.2 * (state[left].x + state[right].x + state[up].x + state[down].x) +
             0.05 * (state[up_left].x + state[up_right].x + state[down_left].x + state[down_right].x) -
             a;
    lap_b := 0.2 * (state[left].y + state[right].y + state[up].y + state[down].y) +
             0.05 * (state[up_left].y + state[up_right].y + state[down_left].y + state[down_right].y) -
             b;

    reaction := a * b * b;
    next_a := a + (RD_DIFF_A * lap_a - reaction + RD_FEED * (1.0 - a)) * RD_DT;
    next_b := b + (RD_DIFF_B * lap_b + reaction - (RD_KILL + RD_FEED) * b) * RD_DT;

    if control[0].cursor_active != 0 {
        cursor_x := control[0].cursor_uv.x * cast(float) RD_WIDTH;
        cursor_y := control[0].cursor_uv.y * cast(float) RD_HEIGHT;
        cell_x := cast(float) x + 0.5;
        cell_y := cast(float) y + 0.5;
        dx := cell_x - cursor_x;
        dy := cell_y - cursor_y;
        dist2 := dx * dx + dy * dy;
        brush_r2 := RD_CURSOR_BRUSH_RADIUS * RD_CURSOR_BRUSH_RADIUS;
        if dist2 < brush_r2 {
            t := 1.0 - dist2 / brush_r2;
            next_b += RD_CURSOR_B_INJECT * t;
            next_a -= RD_CURSOR_A_SUPPRESS * t;
        }
    }

    state[dst_offset + i] = .{
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

rd_vertex_main :: (using in: RD_Vertex_In, state: *[RD_CELL_COUNT] Vector2) -> RD_Vertex_Out {
    using out: RD_Vertex_Out;
    _ = state;
    pos := rd_vertex_corner(vertex_id);
    noop: float = 0.0;
    gl_Position = .{ pos.x, pos.y, noop, 1.0 };
    uv = .{
        pos.x * 0.5 + 0.5,
        pos.y * 0.5 + 0.5,
    };

    return out;
} @vertex_shader

rd_fragment_main :: (using in: RD_Fragment_In, state: *[RD_CELL_COUNT] Vector2) -> struct { out_color: Vector4; } {
    if RD_DEBUG_SHOW_UV {
        return .{
            out_color = .{
                uv.x,
                uv.y,
                0.0,
                1.0,
            }
        };
    }

    px := cast(u32) floor(uv.x * cast(float) RD_WIDTH);
    py := cast(u32) floor(uv.y * cast(float) RD_HEIGHT);
    if px >= RD_WIDTH px = RD_WIDTH - 1;
    if py >= RD_HEIGHT py = RD_HEIGHT - 1;

    idx := py * RD_WIDTH + px;
    s := (cast(*Vector2) state)[idx];
    a := s.x;
    b := s.y;
    tone := rd_clamp01(b * 2.8);
    edge := rd_clamp01(rd_abs(b - a) * 1.2);
    red: float;
    green: float;
    blue: float;
    if tone < 0.33 {
        u := tone / 0.33;
        red = rd_lerp(0.03, 0.00, u);
        green = rd_lerp(0.06, 0.31, u);
        blue = rd_lerp(0.12, 0.46, u);
    } else if tone < 0.66 {
        u := (tone - 0.33) / 0.33;
        red = rd_lerp(0.00, 0.52, u);
        green = rd_lerp(0.31, 0.66, u);
        blue = rd_lerp(0.46, 0.74, u);
    } else {
        u := (tone - 0.66) / 0.34;
        red = rd_lerp(0.52, 0.84, u);
        green = rd_lerp(0.66, 0.36, u);
        blue = rd_lerp(0.74, 0.22, u);
    }
    red = rd_clamp01(red + edge * 0.03);
    green = rd_clamp01(green + edge * 0.02);
    blue = rd_clamp01(blue + edge * 0.01);

    return .{
        out_color = .{
            red,
            green,
            blue,
            1.0,
        }
    };
} @fragment_shader
