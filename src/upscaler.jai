#load "metalfx.jai";

#scope_export

Upscaler_Mode :: enum {
    NONE;
    SPATIAL;
    TEMPORAL;
}

MetalFX_Upscaler :: struct {
    mode: Upscaler_Mode = .SPATIAL;
    supports_spatial: bool;
    supports_temporal: bool;
    temporal_disabled_runtime_bug: bool;
    temporal_history_valid: bool;
    render_target_mode: Upscaler_Mode;

    render_texture: Gpu_Texture;
    render_view: Gpu_Texture_View;
    upscale_texture: Gpu_Texture;
    upscale_view: Gpu_Texture_View;
    temporal_motion_texture: Gpu_Texture;
    temporal_motion_view: Gpu_Texture_View;
    temporal_depth_texture: Gpu_Texture;
    temporal_depth_view: Gpu_Texture_View;

    render_width: s32;
    render_height: s32;

    spatial_scaler: *void;
    temporal_scaler: *void;
}

init :: (upscaler: *MetalFX_Upscaler, env_name: string, default_mode: Upscaler_Mode = .SPATIAL) {
    assert(upscaler != null);
    upscaler.* = .{
        mode = default_mode,
    };

    #if OS == .MACOS {
        gpu_set_swapchain_framebuffer_only(false);
        upscaler.mode = parse_mode_env(upscaler, env_name);
        mtl_device := gpu_get_native_device();
        upscaler.supports_spatial = metalfx_supports_spatial(mtl_device);
        upscaler.supports_temporal = metalfx_supports_temporal(mtl_device);
        if upscaler.supports_temporal {
            upscaler.temporal_disabled_runtime_bug = true;
            upscaler.supports_temporal = false;
        }
        if !upscaler.supports_spatial {
            upscaler.mode = .NONE;
        } else if !upscaler.supports_temporal && upscaler.mode == .TEMPORAL {
            upscaler.mode = .SPATIAL;
        }
    } else {
        upscaler.mode = .NONE;
    }
}

deinit :: (upscaler: *MetalFX_Upscaler) {
    assert(upscaler != null);
    release_targets(upscaler);
    metalfx_release_object(upscaler.temporal_scaler);
    upscaler.temporal_scaler = null;
    metalfx_release_object(upscaler.spatial_scaler);
    upscaler.spatial_scaler = null;
    metalfx_release_compiler();
}

do_ui :: (upscaler: *MetalFX_Upscaler) {
    assert(upscaler != null);
    using ImGui;

    Text("MetalFX: spatial=% temporal=%", upscaler.supports_spatial, upscaler.supports_temporal);
    if SmallButton("Upscale: Off") {
        upscaler.mode = .NONE;
        upscaler.temporal_history_valid = false;
    }
    SameLine();
    if SmallButton("Upscale: Spatial") && upscaler.supports_spatial {
        upscaler.mode = .SPATIAL;
        upscaler.temporal_history_valid = false;
    }
    SameLine();
    if SmallButton("Upscale: Temporal") && upscaler.supports_temporal {
        upscaler.mode = .TEMPORAL;
        upscaler.temporal_history_valid = false;
    }
    Text("Upscaler Mode: %", upscaler.mode);
    if upscaler.temporal_disabled_runtime_bug {
        Text("Temporal MetalFX is disabled on this runtime due to an Apple framework crash during scaler creation.");
    }
}

ensure_render_target :: (
    upscaler: *MetalFX_Upscaler,
    win_w: s32,
    win_h: s32,
    render_scale: float,
    color_format: Format = .B8G8R8A8_UNORM,
    motion_format: Format = .R16G16_SFLOAT,
    depth_format: Format = .R16_SFLOAT
) -> bool {
    assert(upscaler != null);

    target_w := scaled_dim(win_w, render_scale);
    target_h := scaled_dim(win_h, render_scale);
    mode_changed := upscaler.render_target_mode != upscaler.mode;
    if target_w == upscaler.render_width && target_h == upscaler.render_height && upscaler.render_view != 0 && !mode_changed {
        return true;
    }

    if upscaler.render_view != 0 {
        gpu_wait_idle();
    }
    release_targets(upscaler);
    metalfx_release_object(upscaler.spatial_scaler);
    upscaler.spatial_scaler = null;
    metalfx_release_object(upscaler.temporal_scaler);
    upscaler.temporal_scaler = null;
    upscaler.temporal_history_valid = false;

    create_result: Gpu_Result;
    create_result, upscaler.render_texture = gpu_create_texture(.{
        type = ._2D,
        dimensions = .[cast(u32) target_w, cast(u32) target_h, 1],
        format = color_format,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    if create_result != .SUCCESS || upscaler.render_texture == 0 {
        log_error("Upscaler render target creation failed (%), %x%", create_result, target_w, target_h);
        upscaler.render_width = 0;
        upscaler.render_height = 0;
        return false;
    }

    upscaler.render_view = gpu_texture_view(upscaler.render_texture);
    if upscaler.render_view == 0 {
        log_error("Upscaler render target view creation failed.");
        gpu_free(upscaler.render_texture);
        upscaler.render_texture = 0;
        upscaler.render_width = 0;
        upscaler.render_height = 0;
        return false;
    }

    upscaler.render_width = target_w;
    upscaler.render_height = target_h;
    upscaler.render_target_mode = upscaler.mode;

    if upscaler.mode != .NONE {
        create_result, upscaler.upscale_texture = gpu_create_texture(.{
            type = ._2D,
            dimensions = .[cast(u32) max(win_w, 1), cast(u32) max(win_h, 1), 1],
            format = color_format,
            usage = .SAMPLED | .STORAGE | .COLOR_ATTACHMENT,
        });
        if create_result != .SUCCESS || upscaler.upscale_texture == 0 {
            log_error("Upscaler output target creation failed (%), %x%", create_result, win_w, win_h);
            return false;
        }
        upscaler.upscale_view = gpu_texture_view(upscaler.upscale_texture);
        if upscaler.upscale_view == 0 {
            log_error("Upscaler output view creation failed.");
            return false;
        }
    }

    if upscaler.mode == .TEMPORAL {
        create_result, upscaler.temporal_motion_texture = gpu_create_texture(.{
            type = ._2D,
            dimensions = .[cast(u32) target_w, cast(u32) target_h, 1],
            format = motion_format,
            usage = .COLOR_ATTACHMENT | .SAMPLED,
        });
        if create_result != .SUCCESS || upscaler.temporal_motion_texture == 0 {
            log_error("Upscaler temporal motion target creation failed (%), %x%", create_result, target_w, target_h);
            return false;
        }
        upscaler.temporal_motion_view = gpu_texture_view(upscaler.temporal_motion_texture);
        if upscaler.temporal_motion_view == 0 {
            log_error("Upscaler temporal motion view creation failed.");
            return false;
        }

        create_result, upscaler.temporal_depth_texture = gpu_create_texture(.{
            type = ._2D,
            dimensions = .[cast(u32) target_w, cast(u32) target_h, 1],
            format = depth_format,
            usage = .COLOR_ATTACHMENT | .SAMPLED,
        });
        if create_result != .SUCCESS || upscaler.temporal_depth_texture == 0 {
            log_error("Upscaler temporal depth target creation failed (%), %x%", create_result, target_w, target_h);
            return false;
        }
        upscaler.temporal_depth_view = gpu_texture_view(upscaler.temporal_depth_texture);
        if upscaler.temporal_depth_view == 0 {
            log_error("Upscaler temporal depth view creation failed.");
            return false;
        }
    }

    gpu_commit_residency();
    return true;
}

blit_source_view :: (upscaler: *MetalFX_Upscaler) -> Gpu_Texture_View {
    assert(upscaler != null);
    if upscaler.mode == .NONE return upscaler.render_view;
    return upscaler.upscale_view;
}

encode :: (
    upscaler: *MetalFX_Upscaler,
    cmd_buff: Gpu_Command_Buffer,
    win_w: s32,
    win_h: s32,
    source_view: Gpu_Texture_View,
    motion_view: Gpu_Texture_View = 0,
    depth_view: Gpu_Texture_View = 0
) {
    assert(upscaler != null);
    if upscaler.mode == .NONE return;

    gpu_end_native_encoders(cmd_buff);
    native_cmd := gpu_get_native_command_buffer(cmd_buff);
    native_src := gpu_get_native_texture(source_view);
    native_dst := gpu_get_native_texture(upscaler.upscale_view);
    assert(native_cmd != null && native_src != null && native_dst != null, "Upscaler native handles missing.");

    mtl_device := gpu_get_native_device();
    if upscaler.mode == .SPATIAL {
        if upscaler.spatial_scaler == null {
            upscaler.spatial_scaler = metalfx_new_spatial_scaler(
                mtl_device,
                .BGRA8Unorm,
                .BGRA8Unorm,
                cast(u32) upscaler.render_width,
                cast(u32) upscaler.render_height,
                cast(u32) win_w,
                cast(u32) win_h);
            assert(upscaler.spatial_scaler != null, "Spatial MetalFX scaler creation failed.");
        }
        metalfx_spatial_encode(upscaler.spatial_scaler, native_cmd, native_src, native_dst, cast(u32) upscaler.render_width, cast(u32) upscaler.render_height);
        return;
    }

    assert(motion_view != 0 && depth_view != 0, "Temporal upscaler requires motion/depth views.");
    native_motion := gpu_get_native_texture(motion_view);
    native_depth := gpu_get_native_texture(depth_view);
    assert(native_motion != null && native_depth != null, "Temporal MetalFX motion/depth native handles missing.");
    if upscaler.temporal_scaler == null {
        upscaler.temporal_scaler = metalfx_new_temporal_scaler(
            mtl_device,
            .BGRA8Unorm,
            .R16Float,
            .RG16Float,
            .BGRA8Unorm,
            cast(u32) upscaler.render_width,
            cast(u32) upscaler.render_height,
            cast(u32) win_w,
            cast(u32) win_h);
        assert(upscaler.temporal_scaler != null, "Temporal MetalFX scaler creation failed.");
    }
    metalfx_temporal_encode(
        upscaler.temporal_scaler,
        native_cmd,
        native_src,
        native_depth,
        native_motion,
        native_dst,
        cast(u32) upscaler.render_width,
        cast(u32) upscaler.render_height,
        0.0,
        0.0,
        !upscaler.temporal_history_valid);
    upscaler.temporal_history_valid = true;
}

#scope_file

scaled_dim :: (dim: s32, scale: float) -> s32 {
    s := clamp(scale, 0.25, 1.0);
    rounded := cast(s32) floor(cast(float) dim * s + 0.5);
    return max(cast(s32) 1, rounded);
}

parse_mode_env :: (upscaler: *MetalFX_Upscaler, env_name: string) -> Upscaler_Mode {
    value_c := POSIX_Getenv.getenv(temp_c_string(env_name));
    if !value_c return upscaler.mode;

    value_lower := String.to_lower_copy(to_string(value_c, c_style_strlen(value_c)),, temp);
    if value_lower == {
    case "off";      #through;
    case "none";     return .NONE;
    case "spatial";  return .SPATIAL;
    case "temporal"; return .TEMPORAL;
    }

    log_error("% must be one of none|spatial|temporal, got '%'.", env_name, value_lower);
    return upscaler.mode;
}

release_targets :: (upscaler: *MetalFX_Upscaler) {
    if upscaler.temporal_depth_view != 0 {
        gpu_free_texture_view(upscaler.temporal_depth_view);
        upscaler.temporal_depth_view = 0;
    }
    if upscaler.temporal_depth_texture != 0 {
        gpu_free(upscaler.temporal_depth_texture);
        upscaler.temporal_depth_texture = 0;
    }
    if upscaler.temporal_motion_view != 0 {
        gpu_free_texture_view(upscaler.temporal_motion_view);
        upscaler.temporal_motion_view = 0;
    }
    if upscaler.temporal_motion_texture != 0 {
        gpu_free(upscaler.temporal_motion_texture);
        upscaler.temporal_motion_texture = 0;
    }
    if upscaler.upscale_view != 0 {
        gpu_free_texture_view(upscaler.upscale_view);
        upscaler.upscale_view = 0;
    }
    if upscaler.upscale_texture != 0 {
        gpu_free(upscaler.upscale_texture);
        upscaler.upscale_texture = 0;
    }
    if upscaler.render_view != 0 {
        gpu_free_texture_view(upscaler.render_view);
        upscaler.render_view = 0;
    }
    if upscaler.render_texture != 0 {
        gpu_free(upscaler.render_texture);
        upscaler.render_texture = 0;
    }
    upscaler.render_width = 0;
    upscaler.render_height = 0;
}

using,only(getenv) POSIX_Getenv :: #import "POSIX";
String :: #import "String";
