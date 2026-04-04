SHADOW_MAP_DEFAULT_SIZE :: 2048;

Shadow_Map :: struct {
    size: u32 = SHADOW_MAP_DEFAULT_SIZE;
    map_texture: Gpu_Texture;
    map_view: Gpu_Texture_View;
    depth_texture: Gpu_Texture;
    depth_view: Gpu_Texture_View;
    sampler: Gpu_Sampler;

    light_dir: Vector3 = .{0.32152066, -0.9186305, 0.22965762};
    center: Vector3 = .{0.0, 1.5, -10.0};
    extent: float = 18.0;
    distance: float = 20.0;
    near_plane: float = 0.1;
    far_plane: float = 48.0;
    bias: float = 0.0035;

    view_proj: Matrix4 = Matrix4_Identity;
}

shadow_map_init :: (shadow: *Shadow_Map, size: u32 = SHADOW_MAP_DEFAULT_SIZE) {
    shadow.* = .{size = max(size, 1)};
    shadow.sampler = gpu_create_sampler(.{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mip_filter = .NEAREST,
        min_lod = 0.0,
        max_lod = 0.0,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    });
    assert(shadow.sampler != 0, "Shadow map sampler creation failed.");
    shadow_map_ensure_targets(shadow);
    shadow_map_update_view_proj(shadow);
}

shadow_map_deinit :: (using shadow: *Shadow_Map) {
    gpu_delete(*map_texture);
    gpu_delete(*depth_texture);
    gpu_delete(*sampler);
    shadow.* = .{};
}

shadow_map_ensure_targets :: (using shadow: *Shadow_Map) {
    if map_view != 0 && depth_view != 0 return;

    res_map, map_texture= := gpu_create_texture({
        dimensions = .[size, size, 1],
        format = .R32_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    });
    assert(res_map == .SUCCESS, tprint("Shadow map texture creation failed: %", res_map));
    assert(map_texture != 0, "Shadow map texture handle invalid.");
    map_view = gpu_texture_view(map_texture);
    assert(map_view != 0, "Shadow map view creation failed.");

    res_depth, depth_texture= := gpu_create_texture({
        dimensions = .[size, size, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    });

    assert(res_depth == .SUCCESS, tprint("Shadow depth texture creation failed: %", res_depth));
    assert(depth_texture != 0, "Shadow depth texture handle invalid.");

    depth_view = gpu_texture_view(shadow.depth_texture);
    assert(depth_view != 0, "Shadow depth view creation failed.");
}

shadow_map_update_view_proj :: (using shadow: *Shadow_Map) {
    light_forward := -normalize(light_dir);
    light_ref_up := Vector3.{0.0, 0.0, 1.0};
    if abs(dot(light_forward, light_ref_up)) > 0.98 {
        light_ref_up = .{0.0, 1.0, 0.0};
    }

    light_pos := shadow.center - shadow.light_dir * shadow.distance;
    light_view := make_look_at_matrix(
        viewpoint = light_pos,
        look_at = shadow.center,
        reference_up_vector = light_ref_up,
        x_is_forward = false);
    light_proj := orthographic_projection_matrix(
        -extent, extent, -extent, extent,
         near_plane, far_plane,
         depth_range_01 = true);
    view_proj = light_proj * light_view;
}

shadow_map_binding :: (using shadow: *Shadow_Map) -> Vector4 {
    tex_idx := cast(float) gpu_texture_view_index(map_view);
    sampler_idx := cast(float) (cast(u32) shadow.sampler - 1);
    texel := 1.0 / cast(float) shadow.size;
    return {tex_idx, sampler_idx, shadow.bias, texel};
}

#scope_file

#import "Math";
