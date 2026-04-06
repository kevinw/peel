gpu_arena: Gpu_Arena;
pixel_params: Gpu_Frame_Param_Allocator(Textured_Triangle_Pixel_Params);

noise_texture: Gpu_Texture;
noise_texture_view: Gpu_Texture_View;
noise_sampler: Gpu_Sampler;

shader: Shader(vert_main, frag_main, {
    cull = .NONE,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
});

on_dll_init :: () {
    SHR.init(*shader);

    gpu_arena = gpu_make_arena(1024 * 1024, label = "textured triangle arena");
    texture_result, noise_texture= := gpu_create_texture({
        dimensions = .[NOISE_SZ, NOISE_SZ, 1],
        format = .B8G8R8A8_UNORM,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    noise_texture_view = gpu_texture_view(noise_texture);
    noise_sampler = gpu_create_sampler({});

    noise_pixels := gpu_alloc_view(*gpu_arena, u8, NOISE_SZ * NOISE_SZ * 4);
    noise_fill_rgba8(noise_pixels.cpu);
    gpu_copy_to_texture(noise_texture, noise_pixels.cpu.data);

    pixel_params = sgpu_make_frame_param_allocator(*gpu_arena, Textured_Triangle_Pixel_Params);

    gpu_commit_residency();
} @on_dll_init

unload :: () {
    gpu_free_arena(gpu_arena);
    gpu_delete(*noise_texture_view);
    gpu_delete(*noise_texture);
    gpu_delete(*noise_sampler);
} @on_unload

tick :: () {
    _, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0, 0, 0, 1.0],
            }
        ]
    });
    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});
    gpu_set_pipeline(cmd_buff, shader.pipeline);

    params := sgpu_frame_param_alloc(*pixel_params, {
        texture_index = gpu_texture_view_index(noise_texture_view),
        sampler_index = cast(u32) noise_sampler - 1,
    });

    gpu_draw_instanced_direct(cmd_buff, params.gpu, 3, 1);

    if app_ui_enabled {
        using ImGui;
        if Begin("Textured Triangle") {
            Text("Hello, triangle!");
        }
        End();
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

Textured_Triangle_Pixel_Params :: struct {
    texture_index: u32;
    sampler_index: u32;
    debug_mode: u32;
    _pad: u32;
}

Vert_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Vert_Out :: struct {
    position: Vector4; @position
    uv: Vector2;
}

vert_main :: (using in: Vert_In) -> Vert_Out {
    positions :: Vector2.[ {0.0, 0.82}, {-0.82, -0.66}, {0.82, -0.66} ];
    uvs       :: Vector2.[ {0.5, 1.0}, {0.0, 0.0}, {1.0, 0.0} ];

    pos := positions[vertex_id];
    uv_local := uvs[vertex_id];

    return {
        position = .{pos.x, pos.y, 0.0, 1.0},
        uv = uv_local,
    };
} @vertex

frag_main :: (using in: struct { uv: Vector2; }, using params: *Textured_Triangle_Pixel_Params) -> Vector4 @SV_Target0 {
    if debug_mode & 1 != 0 {
        return {
            min(1.0, cast(float) texture_index),
            min(1.0, cast(float) sampler_index),
            0.0,
            1.0
        };
    }

    if false {
        return {uv.x, uv.y, 0, 1};
    }

    return sample_2d(params.texture_index, params.sampler_index, uv);
} @fragment

#scope_file

noise_fill_rgba8 :: (pixels: []u8) {
    for y: 0..NOISE_SZ - 1 {
        for x: 0..NOISE_SZ - 1 {
            i := y * NOISE_SZ + x;
            idx := i * 4;
            // Deterministic checker + gradients so texture sampling is visibly non-uniform.
            r := cast(u8) ((x * 255) / (NOISE_SZ - 1));
            g := cast(u8) ((y * 255) / (NOISE_SZ - 1));
            checker := cast(u8) 32;
            if (((x / 8) + (y / 8)) & 1) == 0 checker = 220;
            b := checker;
            pixels[idx + 0] = b;
            pixels[idx + 1] = g;
            pixels[idx + 2] = r;
            pixels[idx + 3] = 255;
        }
    }
}

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Random";
ImGui :: #import "ImGui";
NOISE_SZ :: 256;
