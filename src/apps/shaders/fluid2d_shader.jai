#import "Jai-Shader-Transpiler";
#import "Math";
#import,file "../../../modules/Jai-Shader-Transpiler/modules/ShaderFuncs/module.jai";

FLUID_WIDTH  :: 320;
FLUID_HEIGHT :: 320;
FLUID_CELL_COUNT :: FLUID_WIDTH * FLUID_HEIGHT;

FLUID_DT :: 1.0 / 60.0;
FLUID_ADVECTION :: 1.8;
FLUID_VISCOSITY :: 0.22;
FLUID_DENSITY_DIFFUSION :: 0.08;
FLUID_VELOCITY_DAMPING :: 0.992;
FLUID_DENSITY_DECAY :: 0.996;
FLUID_CURSOR_RADIUS :: 15.0;
FLUID_CURSOR_FORCE :: 34.0;
FLUID_CURSOR_DENSITY :: 0.38;

Fluid_Compute_In :: struct {
    thread_id: UVector3; @thread_position_in_grid
}

Fluid_Compute_Control :: struct {
    cursor_uv: Vector2;
    cursor_delta_uv: Vector2;
    use_b_as_src: u32;
    cursor_active: u32;
}

Fluid_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Fluid_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Fluid_Fragment_In :: struct {
    uv: Vector2;
}

fluid_cell_index :: (x: u32, y: u32) -> u32 {
    return y * FLUID_WIDTH + x;
}

fluid_wrap_index :: (coord: s64, limit: u32) -> u32 {
    l := cast(s64) limit;
    c := coord % l;
    if c < 0 c += l;
    return cast(u32) c;
}

fluid_sample_wrapped :: (state: *Vector4, src_offset: u32, x: s64, y: s64) -> Vector4 {
    sx := fluid_wrap_index(x, FLUID_WIDTH);
    sy := fluid_wrap_index(y, FLUID_HEIGHT);
    return state[src_offset + fluid_cell_index(sx, sy)];
}

fluid_sample_bilinear :: (state: *Vector4, src_offset: u32, x: float, y: float) -> Vector4 {
    x0 := cast(s64) floor(x);
    y0 := cast(s64) floor(y);
    tx := x - cast(float) x0;
    ty := y - cast(float) y0;

    s00 := fluid_sample_wrapped(state, src_offset, x0, y0);
    s10 := fluid_sample_wrapped(state, src_offset, x0 + 1, y0);
    s01 := fluid_sample_wrapped(state, src_offset, x0, y0 + 1);
    s11 := fluid_sample_wrapped(state, src_offset, x0 + 1, y0 + 1);

    top := mix(s00, s10, tx);
    bottom := mix(s01, s11, tx);
    return mix(top, bottom, ty);
}

fluid_step_compute :: (using in: Fluid_Compute_In, state: *Vector4, control: *Fluid_Compute_Control) {
    if thread_id.x >= FLUID_CELL_COUNT return;

    src_offset: u32 = 0;
    dst_offset: u32 = FLUID_CELL_COUNT;
    if control[0].use_b_as_src != 0 {
        src_offset = FLUID_CELL_COUNT;
        dst_offset = 0;
    }

    i := thread_id.x;
    x := i % FLUID_WIDTH;
    y := i / FLUID_WIDTH;
    sx := cast(s64) x;
    sy := cast(s64) y;

    center := state[src_offset + i];
    left := fluid_sample_wrapped(state, src_offset, sx - 1, sy);
    right := fluid_sample_wrapped(state, src_offset, sx + 1, sy);
    up := fluid_sample_wrapped(state, src_offset, sx, sy - 1);
    down := fluid_sample_wrapped(state, src_offset, sx, sy + 1);

    lap_vel_x := left.x + right.x + up.x + down.x - center.x * 4.0;
    lap_vel_y := left.y + right.y + up.y + down.y - center.y * 4.0;
    lap_density := left.z + right.z + up.z + down.z - center.z * 4.0;

    back_x := cast(float) x - center.x * FLUID_ADVECTION;
    back_y := cast(float) y - center.y * FLUID_ADVECTION;
    adv := fluid_sample_bilinear(state, src_offset, back_x, back_y);

    next_vel_x := adv.x + FLUID_VISCOSITY * lap_vel_x * FLUID_DT;
    next_vel_y := adv.y + FLUID_VISCOSITY * lap_vel_y * FLUID_DT;
    next_density := adv.z + FLUID_DENSITY_DIFFUSION * lap_density * FLUID_DT;

    if control[0].cursor_active != 0 {
        cursor_x := control[0].cursor_uv.x * cast(float) FLUID_WIDTH;
        cursor_y := control[0].cursor_uv.y * cast(float) FLUID_HEIGHT;
        cell_x := cast(float) x + 0.5;
        cell_y := cast(float) y + 0.5;
        dx := cell_x - cursor_x;
        dy := cell_y - cursor_y;
        dist2 := dx * dx + dy * dy;
        brush_r2 := FLUID_CURSOR_RADIUS * FLUID_CURSOR_RADIUS;
        if dist2 < brush_r2 {
            falloff := 1.0 - dist2 / brush_r2;
            impulse_x := control[0].cursor_delta_uv.x * cast(float) FLUID_WIDTH;
            impulse_y := control[0].cursor_delta_uv.y * cast(float) FLUID_HEIGHT;
            next_vel_x += impulse_x * FLUID_CURSOR_FORCE * falloff;
            next_vel_y += impulse_y * FLUID_CURSOR_FORCE * falloff;
            next_density += FLUID_CURSOR_DENSITY * falloff;
        }
    }

    next_vel_x *= FLUID_VELOCITY_DAMPING;
    next_vel_y *= FLUID_VELOCITY_DAMPING;
    next_density = clamp(next_density * FLUID_DENSITY_DECAY, 0.0, 1.0);

    state[dst_offset + i] = .{next_vel_x, next_vel_y, next_density, 0.0};
} @compute_shader

fluid_vertex_corner :: (vid: u32) -> Vector2 {
    if vid == 0 return .{-1, -1};
    if vid == 1 return .{+1, -1};
    if vid == 2 return .{+1, +1};
    if vid == 3 return .{-1, -1};
    if vid == 4 return .{+1, +1};
    return .{-1, +1};
}

fluid_vertex_main :: (using in: Fluid_Vertex_In, state: *[FLUID_CELL_COUNT] Vector4) -> Fluid_Vertex_Out {
    using out: Fluid_Vertex_Out;
    _ = state;
    pos := fluid_vertex_corner(vertex_id);
    gl_Position = .{pos.x, pos.y, 0.0, 1.0};
    uv = .{pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5};
    return out;
} @vertex_shader

fluid_fragment_main :: (using in: Fluid_Fragment_In, state: *[FLUID_CELL_COUNT] Vector4) -> struct { out_color: Vector4; } {
    px := cast(u32) floor(uv.x * cast(float) FLUID_WIDTH);
    py := cast(u32) floor(uv.y * cast(float) FLUID_HEIGHT);
    if px >= FLUID_WIDTH px = FLUID_WIDTH - 1;
    if py >= FLUID_HEIGHT py = FLUID_HEIGHT - 1;

    idx := fluid_cell_index(px, py);
    s := (cast(*Vector4) state)[idx];
    density := clamp(s.z * 1.25, 0.0, 1.0);
    speed := sqrt(s.x * s.x + s.y * s.y);
    turbulence := clamp(speed * 0.25, 0.0, 1.0);

    dark := Vector3.{0.015, 0.020, 0.045};
    smoke := Vector3.{0.10, 0.47, 0.78};
    hot := Vector3.{0.98, 0.70, 0.32};

    base := Vector3.{
        mix(dark.x, smoke.x, density),
        mix(dark.y, smoke.y, density),
        mix(dark.z, smoke.z, density),
    };

    spark := density * turbulence;
    color := mix(base, hot, spark);

    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader
