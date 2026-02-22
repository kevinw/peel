#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

RIPPLE_WIDTH :: 384;
RIPPLE_HEIGHT :: 256;
RIPPLE_CELL_COUNT :: RIPPLE_WIDTH * RIPPLE_HEIGHT;

RIPPLE_DT :: 1.0;
RIPPLE_WAVE_SPEED :: 0.28;
RIPPLE_DAMPING :: 0.992;
RIPPLE_CURSOR_RADIUS :: 12.0;
RIPPLE_CURSOR_IMPULSE :: 0.26;
RIPPLE_MAX_HEIGHT :: 1.5;
RIPPLE_MAX_VELOCITY :: 1.0;

Ripple_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Ripple_Compute_Control :: struct {
    cursor_uv: Vector2;
    use_b_as_src: u32;
    cursor_mode: u32; // 0 = none, 1 = positive, 2 = negative
}

Ripple_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Ripple_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Ripple_Fragment_In :: struct {
    uv: Vector2;
}

ripple_cell_index :: (x: u32, y: u32) -> u32 {
    return y * RIPPLE_WIDTH + x;
}

ripple_wrap_index :: (coord: s64, limit: u32) -> u32 {
    l := cast(s64) limit;
    c := coord % l;
    if c < 0 c += l;
    return cast(u32) c;
}

ripple_sample_wrapped :: (state: *Vector2, src_offset: u32, x: s64, y: s64) -> Vector2 {
    sx := ripple_wrap_index(x, RIPPLE_WIDTH);
    sy := ripple_wrap_index(y, RIPPLE_HEIGHT);
    return state[src_offset + ripple_cell_index(sx, sy)];
}

ripple_step_compute :: (using in: Ripple_Compute_In, state: *Vector2, control: *Ripple_Compute_Control) {
    if thread_id.x >= RIPPLE_CELL_COUNT return;

    src_offset: u32 = 0;
    dst_offset: u32 = RIPPLE_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = RIPPLE_CELL_COUNT;
        dst_offset = 0;
    }

    i := thread_id.x;
    x := i % RIPPLE_WIDTH;
    y := i / RIPPLE_WIDTH;
    sx := cast(s64) x;
    sy := cast(s64) y;

    center := state[src_offset + i];
    left := ripple_sample_wrapped(state, src_offset, sx - 1, sy);
    right := ripple_sample_wrapped(state, src_offset, sx + 1, sy);
    up := ripple_sample_wrapped(state, src_offset, sx, sy - 1);
    down := ripple_sample_wrapped(state, src_offset, sx, sy + 1);

    h := center.x;
    v := center.y;
    lap := left.x + right.x + up.x + down.x - h * 4.0;

    next_v := (v + lap * RIPPLE_WAVE_SPEED * RIPPLE_DT) * RIPPLE_DAMPING;
    next_h := h + next_v * RIPPLE_DT;

    if control[0].cursor_mode != 0 {
        cursor_x := control[0].cursor_uv.x * cast(float) RIPPLE_WIDTH;
        cursor_y := control[0].cursor_uv.y * cast(float) RIPPLE_HEIGHT;
        cell_x := cast(float) x + 0.5;
        cell_y := cast(float) y + 0.5;
        dx := cell_x - cursor_x;
        dy := cell_y - cursor_y;
        dist2 := dx * dx + dy * dy;
        brush_r2 := RIPPLE_CURSOR_RADIUS * RIPPLE_CURSOR_RADIUS;
        if dist2 < brush_r2 {
            falloff := 1.0 - dist2 / brush_r2;
            impulse_sign: float = 1.0;
            if control[0].cursor_mode == 2 impulse_sign = -1.0;
            next_h += impulse_sign * RIPPLE_CURSOR_IMPULSE * falloff;
        }
    }

    next_h = clamp(next_h, -RIPPLE_MAX_HEIGHT, RIPPLE_MAX_HEIGHT);
    next_v = clamp(next_v, -RIPPLE_MAX_VELOCITY, RIPPLE_MAX_VELOCITY);
    state[dst_offset + i] = .{next_h, next_v};
} @compute_shader

ripple_vertex_corner :: (vid: u32) -> Vector2 {
    if vid == 0 return .{-1, -1};
    if vid == 1 return .{+1, -1};
    if vid == 2 return .{+1, +1};
    if vid == 3 return .{-1, -1};
    if vid == 4 return .{+1, +1};
    return .{-1, +1};
}

ripple_vertex_main :: (using in: Ripple_Vertex_In, state: *Vector2) -> Ripple_Vertex_Out {
    using out: Ripple_Vertex_Out;
    _ = state;
    pos := ripple_vertex_corner(vertex_id);
    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

ripple_safe_normalize3 :: (v: Vector3) -> Vector3 {
    len2 := v.x * v.x + v.y * v.y + v.z * v.z;
    if len2 < 0.000001 return .{0.0, 0.0, 1.0};
    inv := 1.0 / sqrt(len2);
    return .{v.x * inv, v.y * inv, v.z * inv};
}

ripple_fragment_main :: (using in: Ripple_Fragment_In, state: *Vector2) -> struct { out_color: Vector4; } {
    px := cast(u32) floor(uv.x * cast(float) RIPPLE_WIDTH);
    py := cast(u32) floor(uv.y * cast(float) RIPPLE_HEIGHT);
    if px >= RIPPLE_WIDTH px = RIPPLE_WIDTH - 1;
    if py >= RIPPLE_HEIGHT py = RIPPLE_HEIGHT - 1;

    idx := ripple_cell_index(px, py);
    h := state[idx].x;

    h_left := state[ripple_cell_index(ripple_wrap_index(cast(s64) px - 1, RIPPLE_WIDTH), py)].x;
    h_right := state[ripple_cell_index(ripple_wrap_index(cast(s64) px + 1, RIPPLE_WIDTH), py)].x;
    h_up := state[ripple_cell_index(px, ripple_wrap_index(cast(s64) py - 1, RIPPLE_HEIGHT))].x;
    h_down := state[ripple_cell_index(px, ripple_wrap_index(cast(s64) py + 1, RIPPLE_HEIGHT))].x;

    grad_x := (h_right - h_left) * 0.5;
    grad_y := (h_down - h_up) * 0.5;

    n := ripple_safe_normalize3(.{-grad_x * 2.4, -grad_y * 2.4, 1.0});
    l := ripple_safe_normalize3(.{-0.35, 0.65, 0.68});
    ndotl := clamp(dot(n, l), 0.0, 1.0);

    deep := Vector3.{0.015, 0.032, 0.072};
    mid := Vector3.{0.090, 0.270, 0.520};
    crest := Vector3.{0.620, 0.870, 1.000};

    height_t := clamp(h * 0.5 + 0.5, 0.0, 1.0);
    base := Vector3.{
        mix(deep.x, mid.x, height_t),
        mix(deep.y, mid.y, height_t),
        mix(deep.z, mid.z, height_t),
    };

    fresnel := pow(1.0 - clamp(n.z, 0.0, 1.0), 2.5);
    lit := base * (0.28 + 0.72 * ndotl);
    color := mix(lit, crest, fresnel * 0.6 + ndotl * 0.1);

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader
