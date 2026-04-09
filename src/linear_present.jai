#load "shaders/linear_present_shader.jai";

Linear_Present_Params_CPU :: CPU_Struct(Linear_Present_Params);

linear_present_shader: Shader(fullscreen_tri_vert, linear_present_fragment_main, .{
    cull = .NONE,
    derive_attachment_formats_from_render_pass = true,
});

Linear_Present_State :: struct {
    color: Texture_Ring;
    color_w: u32;
    color_h: u32;
    params: Gpu_Buffer_Ring(Linear_Present_Params_CPU);
    sampler: Gpu_Sampler;
    flip_y: bool = true;
    exposure: float = 1.0;
}

linear_present_init :: (state: *Linear_Present_State, label := "linear present") -> bool {
    if state == null return false;
    assert(SHR.init(*linear_present_shader), "Failed to create linear present pipeline.");
    state.params = gpu_make_buffer_ring(Linear_Present_Params_CPU, label = tprint("% params", label));
    state.sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .LINEAR,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    return state.sampler != 0;
}

linear_present_deinit :: (state: *Linear_Present_State) {
    if state == null return;
    gpu_delete(*state.color);
    gpu_delete(*state.params);
    gpu_delete(*state.sampler);
    state.color_w = 0;
    state.color_h = 0;
    state.exposure = 1.0;
}

linear_present_shutdown_shader :: () {
    gpu_delete(*linear_present_shader.pipeline);
}

linear_present_ensure_color_target :: (state: *Linear_Present_State, width: u32, height: u32,
    format: Format = .R16G16B16A16_SFLOAT) -> bool {
    if state == null return false;
    if width == 0 || height == 0 return true;
    if state.color.views[0] != 0 && state.color_w == width && state.color_h == height && state.color.desc.format == format {
        return true;
    }
    ok := ensure_texture_ring(*state.color, .{
        dimensions = .[width, height, 1],
        format = format,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    if !ok return false;
    state.color_w = width;
    state.color_h = height;
    gpu_commit_residency();
    return true;
}

linear_present_current_color_view :: (state: *Linear_Present_State, frame_number: s64 = -1) -> Gpu_Texture_View {
    return texture_ring_current_view(*state.color, frame_number);
}

linear_present_current_color_texture :: (state: *Linear_Present_State, frame_number: s64 = -1) -> Gpu_Texture {
    return texture_ring_current_texture(*state.color, frame_number);
}

linear_present_present :: (cmd_buff: Gpu_Command_Buffer, state: *Linear_Present_State, swapchain_view: Gpu_Texture_View,
    frame_number: s64 = -1) {
    assert(state != null, "linear_present_present requires a state.");
    params := gpu_buffer_ring_slot(*state.params, frame_number);
    if params.cpu != null {
        params.cpu.* = .{
            scene_texture_index = gpu_texture_view_index(linear_present_current_color_view(state, frame_number)),
            sampler_index = cast(u32) state.sampler - 1,
            flip_y = ifx state.flip_y then cast(u32) 1 else cast(u32) 0,
            exposure = state.exposure,
        };
    }

    pass_desc := Gpu_Render_Pass_Desc.{
        color_targets = .[.{
            view = swapchain_view,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_color._float = .[0.0, 0.0, 0.0, 1.0],
        }],
    };
    gpu_begin_render_pass(cmd_buff, pass_desc);
    gpu_set_pipeline(cmd_buff, SHR.pipeline(*linear_present_shader, pass_desc));
    gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);
}

#scope_file
