#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";

SCENE_ALPHA_MODE_OPAQUE :: 0;
SCENE_ALPHA_MODE_MASK   :: 1;

Model_Scene_Debug_Mode :: enum u32 {
    SHADED;
    ALBEDO;
    LODS;
    CHUNKS;
    MESHLETS;
}

Model_Scene_Meshlet_Flags :: enum_flags u32 {
    HAS_SHADOWS          :: 1 << 0;
    HAS_LODS             :: 1 << 1;
    HAS_MORPHS           :: 1 << 2;
    HAS_SKINNING         :: 1 << 3;
    DISABLE_FRUSTUM_CULL :: 1 << 4;
}

Model_Scene_Meshlet_Constants :: struct {
    flags: Model_Scene_Meshlet_Flags = .HAS_SHADOWS | .HAS_LODS | .HAS_MORPHS | .HAS_SKINNING;
    debug_mode: Model_Scene_Debug_Mode = .SHADED;
} @function_constants

Scene_Instance :: struct {
    world: Matrix4;
    tint: Vector4;
    shadow_view_proj: Matrix4;
    shadow_meta: Vector4;
}

Scene_Draw_Params :: struct {
    vertices: *Scene_Vertex;
    indices: *u32;
    materials: *Scene_Material;
    instances: *Scene_Instance;
    morph_vertex_deltas: *Scene_Morph_Vertex_Delta;
    morph_weights: *float;
    skin_matrices: *Vector4;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    material_index: u32;
    object_id: u32;
    mesh_base_vertex: u32;
    skin_matrix_count: u32;
    morph_target_count: u32;
    morph_vertex_count: u32;
}

Ground_Draw_Params :: struct {
    vertices: *Scene_Vertex;
    indices: *u32;
    instances: *Scene_Instance;
    view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    sampler_index: u32;
    base_color_texture_index: u32;
    normal_texture_index: u32;
    roughness_texture_index: u32;
    ao_texture_index: u32;
    _pad2: u32;
}

Grass_Draw_Params :: struct {
    view_proj: Matrix4;
    shadow_view_proj: Matrix4;
    light_dir: Vector3;
    _pad0: float;
    sun_params: Vector4;
    camera_pos: Vector3;
    _pad1: float;
    shadow_meta: Vector4;
    ground_size_center_z_time: Vector4;
    ground_shape: Vector4;
    grass_grid_height_width: Vector4;
    player_pos_radius: Vector4;
    camera_pos_fade_start: Vector4;
    fade_end_far_shade_shadow_end: Vector4;
}

Grass_Shadow_Params :: struct {
    shadow_view_proj: Matrix4;
    ground_size_center_z_time: Vector4;
    ground_shape: Vector4;
    grass_grid_height_width: Vector4;
    player_pos_radius: Vector4;
    camera_pos_fade_start: Vector4;
    fade_end_far_shade_shadow_end: Vector4;
}

Model_Scene_Sky_Params :: struct {
    camera_right_proj_x: Vector4;
    camera_up_proj_y: Vector4;
    camera_forward_time_of_day: Vector4;
    light_dir_sun_strength: Vector4;
    projection_mode_ortho_half_height: Vector4;
}

Model_Scene_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Model_Scene_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    tangent: Vector4;
    uv: Vector2;
    tint: Vector4;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Model_Scene_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    tangent: Vector4;
    uv: Vector2;
    tint: Vector4;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Model_Scene_Shadow_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    depth01: float;
    uv: Vector2;
}

Model_Scene_Shadow_Fragment_In :: struct {
    depth01: float;
    uv: Vector2;
}

Model_Scene_Debug_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Model_Scene_Debug_Fragment_In :: struct {
    uv: Vector2;
}

Model_Scene_Sky_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    uv: Vector2;
}

Model_Scene_Sky_Fragment_In :: struct {
    uv: Vector2;
}

Model_Scene_Present_Params :: struct {
    scene_texture_index: u32;
    sampler_index: u32;
    _pad0: u32;
    _pad1: u32;
    exposure: float;
}

Model_Scene_Present_Fragment_In :: struct {
    uv: Vector2;
}

model_scene_tonemap :: (x: float, exposure: float) -> float {
    hdr := x * max(exposure, 0.001);
    mapped := (hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14);
    return clamp(mapped, 0.0, 1.0);
}

model_scene_linear_to_srgb :: (x: float) -> float {
    if x <= 0.0031308 return 12.92 * x;
    return 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

model_scene_present_fragment_main :: (using input: Model_Scene_Present_Fragment_In, params: *Model_Scene_Present_Params) -> Vector4 @SV_Target0 {
    uv.y = 1.0 - uv.y;
    color := sample_2d(params.scene_texture_index, params.sampler_index, uv).xyz;
    return .{
        model_scene_linear_to_srgb(model_scene_tonemap(color.x, params.exposure)),
        model_scene_linear_to_srgb(model_scene_tonemap(color.y, params.exposure)),
        model_scene_linear_to_srgb(model_scene_tonemap(color.z, params.exposure)),
        1.0,
    };
} @fragment_shader

Ground_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Ground_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Ground_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    uv: Vector2;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Ground_Shadow_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    depth01: float;
}

Ground_Shadow_Fragment_In :: struct {
    depth01: float;
}

Grass_Vertex_In :: struct {
    vertex_id: u32; @SV_VertexID
    instance_id: u32; @SV_InstanceID
}

Grass_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    world_pos: Vector3;
    normal: Vector3;
    blade_t: float;
    fade_t: float;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Grass_Fragment_In :: struct {
    world_pos: Vector3;
    normal: Vector3;
    blade_t: float;
    fade_t: float;
    shadow_uvz: Vector3;
    shadow_meta: Vector4;
}

Grass_Shadow_Vertex_Out :: struct {
    gl_Position: Vector4; @position
    depth01: float;
}

Grass_Shadow_Fragment_In :: struct {
    depth01: float;
}

model_scene_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Vertex_Out {
    using out: Model_Scene_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    local_normal := Vector4.{vertex.normal.x, vertex.normal.y, vertex.normal.z, 0.0};
    local_tangent := Vector4.{vertex.tangent.x, vertex.tangent.y, vertex.tangent.z, 0.0};
    local_vertex_index := vertex_index - params.mesh_base_vertex;
    if params.morph_target_count > 0 && local_vertex_index < params.morph_vertex_count {
        for target_index: 0..cast(s64) params.morph_target_count-1 {
            weight := params.morph_weights[target_index];
            if abs(weight) <= 0.00001 continue;
            delta_index := cast(u32) target_index * params.morph_vertex_count + local_vertex_index;
            delta := params.morph_vertex_deltas[delta_index];
            local_pos += delta.position * weight;
            local_normal += delta.normal * weight;
            local_tangent += delta.tangent * weight;
        }
        local_pos.w = 1.0;
        local_normal.w = 0.0;
        local_tangent.w = 0.0;
    }
    skinned_pos4 := local_pos;
    skinned_normal4 := local_normal;
    skinned_tangent4 := local_tangent;

    if params.skin_matrix_count > 0 {
        skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
        skinned_normal4 = .{0.0, 0.0, 0.0, 0.0};
        skinned_tangent4 = .{0.0, 0.0, 0.0, 0.0};
        total_weight: float = 0.0;
        if vertex.bone_weights.x > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.x;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.x;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.x;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.x;
                total_weight += vertex.bone_weights.x;
            }
        }
        if vertex.bone_weights.y > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.y;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.y;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.y;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.y;
                total_weight += vertex.bone_weights.y;
            }
        }
        if vertex.bone_weights.z > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.z;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.z;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.z;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.z;
                total_weight += vertex.bone_weights.z;
            }
        }
        if vertex.bone_weights.w > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.w;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.w;
                skinned_normal4 += (skin * local_normal) * vertex.bone_weights.w;
                skinned_tangent4 += (skin * local_tangent) * vertex.bone_weights.w;
                total_weight += vertex.bone_weights.w;
            }
        }
        if total_weight <= 0.0 {
            skinned_pos4 = local_pos;
            skinned_normal4 = local_normal;
            skinned_tangent4 = local_tangent;
        }
    }

    world_pos4 := instance.world * skinned_pos4;
    gl_Position = params.view_proj * world_pos4;
    world_pos = .{world_pos4.x, world_pos4.y, world_pos4.z};
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    shadow_uvz = .{light_clip.x * 0.5 + 0.5, light_clip.y * 0.5 + 0.5, light_clip.z};
    shadow_meta = instance.shadow_meta;

    world_normal4 := instance.world * skinned_normal4;
    normal = normalize(Vector3.{world_normal4.x, world_normal4.y, world_normal4.z});
    world_tangent4 := instance.world * skinned_tangent4;
    tangent = .{world_tangent4.x, world_tangent4.y, world_tangent4.z, vertex.tangent.w};
    uv = vertex.uv;
    tint = instance.tint;
    return out;
} @vertex_shader

model_scene_shadow_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Shadow_Vertex_Out {
    using out: Model_Scene_Shadow_Vertex_Out;

    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    local_vertex_index := vertex_index - params.mesh_base_vertex;
    if params.morph_target_count > 0 && local_vertex_index < params.morph_vertex_count {
        for target_index: 0..cast(s64) params.morph_target_count-1 {
            weight := params.morph_weights[target_index];
            if abs(weight) <= 0.00001 continue;
            delta_index := cast(u32) target_index * params.morph_vertex_count + local_vertex_index;
            local_pos += params.morph_vertex_deltas[delta_index].position * weight;
        }
        local_pos.w = 1.0;
    }
    skinned_pos4 := local_pos;

    if params.skin_matrix_count > 0 {
        skinned_pos4 = .{0.0, 0.0, 0.0, 0.0};
        total_weight: float = 0.0;
        if vertex.bone_weights.x > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.x;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.x;
                total_weight += vertex.bone_weights.x;
            }
        }
        if vertex.bone_weights.y > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.y;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.y;
                total_weight += vertex.bone_weights.y;
            }
        }
        if vertex.bone_weights.z > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.z;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.z;
                total_weight += vertex.bone_weights.z;
            }
        }
        if vertex.bone_weights.w > 0.0 {
            bone_index := cast(u32) vertex.bone_indices.w;
            if bone_index < params.skin_matrix_count {
                skin := load_skin_matrix(params.skin_matrices, bone_index);
                skinned_pos4 += (skin * local_pos) * vertex.bone_weights.w;
                total_weight += vertex.bone_weights.w;
            }
        }
        if total_weight <= 0.0 {
            skinned_pos4 = local_pos;
        }
    }

    world_pos4 := instance.world * skinned_pos4;
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    gl_Position = light_clip;
    depth01 = clamp(light_clip.z, 0.0, 1.0);
    uv = vertex.uv;
    return out;
} @vertex_shader

model_scene_shadow_fragment_main :: (using in: Model_Scene_Shadow_Fragment_In, params: *Scene_Draw_Params) -> struct { out_color: Vector4; } {
    material := params.materials[params.material_index];
    alpha := scene_material_alpha(material, uv, 1.0);
    if material.alpha_mode == SCENE_ALPHA_MODE_MASK && alpha < material.alpha_cutoff discard();
    d := clamp(depth01, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_debug_shadow_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Scene_Draw_Params) -> Model_Scene_Debug_Vertex_Out {
    using out: Model_Scene_Debug_Vertex_Out;
    _ = params;

    x0 := 0.56;
    x1 := 0.98;
    y0 := -0.98;
    y1 := -0.56;

    if vertex_id == 0 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{x1, y0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{x0, y0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{x1, y1, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{x0, y1, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

model_scene_debug_shadow_fragment_main :: (using in: Model_Scene_Debug_Fragment_In, params: *Scene_Draw_Params) -> struct { out_color: Vector4; } {
    meta := params.instances[0].shadow_meta;
    tex_idx := cast(u32) meta.x;
    samp_idx := cast(u32) meta.y;
    s := sample_2d(tex_idx, samp_idx, .{uv.x, 1.0 - uv.y});
    d := clamp(s.x, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_debug_pick_fragment_main :: (using in: Model_Scene_Debug_Fragment_In, params: *Scene_Draw_Params) -> struct { out_color: Vector4; } {
    tex_idx := params.object_id;
    samp_idx := params.material_index;
    s := sample_2d(tex_idx, samp_idx, .{uv.x, 1.0 - uv.y});
    return .{out_color = s};
} @fragment_shader

model_scene_sky_base_color :: (view_dir: Vector3, sun_dir: Vector3) -> Vector3 {
    upness := clamp(view_dir.y * 0.5 + 0.5, 0.0, 1.0);
    sun_dot := dot(view_dir, sun_dir);
    toward_sun := clamp((sun_dot + 0.15) / 1.15, 0.0, 1.0);
    away_from_sun := 1.0 - toward_sun;
    horizon := pow(1.0 - clamp(view_dir.y, 0.0, 1.0), 2.0);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);

    night_zenith := Vector3.{0.006, 0.008, 0.016};
    night_horizon := Vector3.{0.015, 0.012, 0.012};
    day_zenith := Vector3.{0.17, 0.34, 0.74};
    day_horizon := Vector3.{0.68, 0.76, 0.92};
    zenith_col := mix(night_zenith, day_zenith, day_t);
    horizon_col := mix(night_horizon, day_horizon, day_t);
    base := mix(horizon_col, zenith_col, upness);
    base = base * mix(0.84, 1.0 - horizon * 0.2, day_t);

    sunset_orange := Vector3.{1.16, 0.45, 0.13};
    twilight_blue := Vector3.{0.10, 0.18, 0.38};
    base += sunset_orange * (horizon * twilight_t * toward_sun * 0.58);
    base += twilight_blue * (twilight_t * away_from_sun * (0.14 + upness * 0.34));
    return base;
}

model_scene_sky_color :: (view_dir: Vector3, sun_dir: Vector3, sun_strength: float) -> Vector3 {
    sun_dot := dot(view_dir, sun_dir);
    sun_amount := clamp(sun_dot, 0.0, 1.0);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);
    day_t := clamp(sun_elevation * 0.85 + 0.33, 0.0, 1.0);
    base := model_scene_sky_base_color(view_dir, sun_dir);

    sun_glow := pow(sun_amount, 18.0) * 0.38;
    sun_core := pow(sun_amount, 140.0);
    warm_day := Vector3.{1.0, 0.77, 0.47};
    warm_twilight := Vector3.{1.25, 0.52, 0.18};
    warm := mix(warm_day, warm_twilight, twilight_t);
    glow_scale := max(sun_strength, 0.0) * mix(0.35, 1.0, day_t + twilight_t * 0.45);

    return base + warm * (sun_glow + sun_core * 1.25) * glow_scale;
}

model_scene_indirect_light :: (N: Vector3, sun_dir: Vector3, sun_strength: float, shadow: float) -> Vector3 {
    upness := clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    horizonness := 1.0 - abs(N.y);
    sun_elevation := clamp(sun_dir.y, -1.0, 1.0);
    twilight_t := 1.0 - clamp(abs(sun_elevation) * 3.0, 0.0, 1.0);

    sky_zenith := model_scene_sky_base_color(Vector3.{0.0, 1.0, 0.0}, sun_dir);
    sky_horizon := model_scene_sky_base_color(normalize(Vector3.{0.0, 0.08, 1.0}), sun_dir);
    sky_fill := mix(sky_horizon, sky_zenith, upness) * (0.34 + horizonness * 0.08);

    ground_day := Vector3.{0.20, 0.18, 0.11};
    ground_twilight := Vector3.{0.28, 0.16, 0.08};
    ground_bounce := mix(ground_day, ground_twilight, twilight_t);
    ground_fill := ground_bounce * (1.0 - upness) * (0.18 + sun_strength * 0.12);

    indirect_shadow := mix(0.82, 1.0, shadow);
    return (sky_fill + ground_fill) * indirect_shadow;
}

scene_material_alpha :: (material: Scene_Material, uv: Vector2, tint_alpha: float) -> float {
    alpha := material.base_color_factor.w * tint_alpha;
    if material.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(material.base_color_texture_index, material.sampler_index, uv).w;
    }
    if material.opacity_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        alpha *= sample_2d(material.opacity_texture_index, material.sampler_index, uv).x;
    }
    return alpha;
}

scene_encode_object_id :: (object_id: u32) -> Vector4 {
    r := cast(float) ((object_id >> 0) & 0xff) / 255.0;
    g := cast(float) ((object_id >> 8) & 0xff) / 255.0;
    b := cast(float) ((object_id >> 16) & 0xff) / 255.0;
    a := cast(float) ((object_id >> 24) & 0xff) / 255.0;
    return .{r, g, b, a};
}

model_scene_fragment_main :: (using in: Model_Scene_Fragment_In, params: *Scene_Draw_Params, using constants: Model_Scene_Meshlet_Constants) -> Vector4 @SV_Target0 {
    material := params.materials[params.material_index];
    tex := material.base_color_factor;
    if material.base_color_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        tex = sample_2d(material.base_color_texture_index, material.sampler_index, uv);
    }
    alpha := scene_material_alpha(material, uv, tint.w);
    if material.alpha_mode == SCENE_ALPHA_MODE_MASK && alpha < material.alpha_cutoff discard();
    base_rgb := Vector3.{
        tex.x * material.base_color_factor.x * tint.x,
        tex.y * material.base_color_factor.y * tint.y,
        tex.z * material.base_color_factor.z * tint.z,
    };
    if debug_mode == .ALBEDO return .{base_rgb.x, base_rgb.y, base_rgb.z, alpha};
    N := normalize(normal);
    ao := 1.0;
    roughness := 0.82;
    if material.normal_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        T := normalize(Vector3.{tangent.x, tangent.y, tangent.z});
        B := normalize(cross(N, T)) * tangent.w;
        n_sample := sample_2d(material.normal_texture_index, material.sampler_index, uv);
        n_ts := decode_bc5_normal(n_sample);
        N = normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
    }
    if material.ao_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        ao = sample_2d(material.ao_texture_index, material.sampler_index, uv).x;
    }
    if material.roughness_texture_index != SCENE_INVALID_TEXTURE_INDEX {
        roughness = sample_2d(material.roughness_texture_index, material.sampler_index, uv).y;
    }
    sun_dir := normalize(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);
    L := sun_dir;
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl_raw := dot(N, L);
    ndl := max(ndl_raw, 0.0);
    ndh := max(dot(N, H), 0.0);
    local_shadow_meta := shadow_meta;
    local_shadow_uvz := shadow_uvz;
    shadow := model_scene_shadow_visibility(local_shadow_meta, local_shadow_uvz);
    indirect := model_scene_indirect_light(N, sun_dir, sun_strength, shadow) * mix(0.62, 1.0, ao);
    wrapped_ndl := clamp((ndl_raw + 0.28) / 1.28, 0.0, 1.0);
    diffuse := wrapped_ndl * 0.74 * shadow * sun_strength;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    specular := pow(ndh, spec_power) * spec_strength * shadow * sun_strength;
    color := base_rgb * indirect + base_rgb * diffuse + sun_col * specular;
    color = apply_atmosphere(color, world_pos, params.camera_pos, sun_dir);
    return .{color.x, color.y, color.z, alpha};
} @fragment_shader

model_scene_pick_fragment_main :: (using in: Model_Scene_Fragment_In, params: *Scene_Draw_Params) -> Vector4 @SV_Target0 {
    material := params.materials[params.material_index];
    alpha := scene_material_alpha(material, uv, tint.w);
    if material.alpha_mode == SCENE_ALPHA_MODE_MASK && alpha < material.alpha_cutoff discard();
    return scene_encode_object_id(params.object_id);
} @fragment_shader

ground_vertex_main :: (using in: Ground_Vertex_In, params: *Ground_Draw_Params) -> Ground_Vertex_Out {
    using out: Ground_Vertex_Out;
    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    local_pos := Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    world_pos4 := instance.world * local_pos;
    gl_Position = params.view_proj * world_pos4;
    world_pos = .{world_pos4.x, world_pos4.y, world_pos4.z};
    normal = normalize(Vector3.{vertex.normal.x, vertex.normal.y, vertex.normal.z});
    uv = vertex.uv;
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    shadow_uvz = .{light_clip.x * 0.5 + 0.5, light_clip.y * 0.5 + 0.5, light_clip.z};
    shadow_meta = instance.shadow_meta;
    return out;
} @vertex_shader

ground_fragment_main :: (using in: Ground_Fragment_In, params: *Ground_Draw_Params, constants: Model_Scene_Meshlet_Constants) -> Vector4 @SV_Target0 {
    tex := sample_2d(params.base_color_texture_index, params.sampler_index, uv);
    base_rgb := Vector3.{tex.x, tex.y, tex.z};
    if constants.debug_mode == .ALBEDO return .{base_rgb.x, base_rgb.y, base_rgb.z, 1.0};
    ao := sample_2d(params.ao_texture_index, params.sampler_index, uv).x;
    roughness := sample_2d(params.roughness_texture_index, params.sampler_index, uv).x;

    N := normalize(normal);
    up := Vector3.{0.0, 1.0, 0.0};
    tangent := cross(up, N);
    tangent_len2 := dot(tangent, tangent);
    if tangent_len2 < 1.0e-5 {
        tangent = .{1.0, 0.0, 0.0};
    } else {
        tangent = tangent / sqrt(tangent_len2);
    }
    bitangent := normalize(cross(N, tangent));
    n_sample := sample_2d(params.normal_texture_index, params.sampler_index, uv);
    n_ts := decode_bc5_normal(n_sample);
    N = normalize(tangent * n_ts.x + bitangent * n_ts.y + N * max(n_ts.z, 0.0));

    sun_dir := normalize(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);
    L := sun_dir;
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl_raw := dot(N, L);
    ndl := max(ndl_raw, 0.0);
    ndh := max(dot(N, H), 0.0);
    shadow := model_scene_shadow_visibility(shadow_meta, shadow_uvz);
    indirect := model_scene_indirect_light(N, sun_dir, sun_strength, shadow) * mix(0.62, 1.0, ao);
    wrapped_ndl := clamp((ndl_raw + 0.24) / 1.24, 0.0, 1.0);
    diffuse := wrapped_ndl * 0.74 * shadow * sun_strength;
    spec_power := mix(48.0, 5.0, clamp(roughness, 0.0, 1.0));
    spec_strength := mix(0.18, 0.035, clamp(roughness, 0.0, 1.0));
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    specular := pow(ndh, spec_power) * spec_strength * shadow * sun_strength;
    color := base_rgb * indirect + base_rgb * diffuse + sun_col * specular;
    color = apply_atmosphere(color, world_pos, params.camera_pos, sun_dir);
    return .{color.x, color.y, color.z, tex.w};
} @fragment_shader

ground_shadow_vertex_main :: (using in: Ground_Vertex_In, params: *Ground_Draw_Params) -> Ground_Shadow_Vertex_Out {
    using out: Ground_Shadow_Vertex_Out;
    vertex_index := params.indices[vertex_id];
    vertex := params.vertices[vertex_index];
    instance := params.instances[instance_id];

    world_pos4 := instance.world * Vector4.{vertex.position.x, vertex.position.y, vertex.position.z, 1.0};
    light_view_proj := load_shadow_view_proj(instance);
    light_clip := light_view_proj * world_pos4;
    gl_Position = light_clip;
    depth01 = clamp(light_clip.z, 0.0, 1.0);
    return out;
} @vertex_shader

ground_shadow_fragment_main :: (using in: Ground_Shadow_Fragment_In, params: *Ground_Draw_Params) -> struct { out_color: Vector4; } {
    _ = params;
    d := clamp(depth01, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_grass_shadow_vertex_main :: (using in: Grass_Vertex_In, params: *Grass_Shadow_Params) -> Grass_Shadow_Vertex_Out {
    using out: Grass_Shadow_Vertex_Out;
    blade_t := grass_blade_vt(vertex_id);
    world_pos := grass_blade_world_pos(vertex_id, instance_id, blade_t, params);
    camera_pos := Vector3.{params.camera_pos_fade_start.x, params.camera_pos_fade_start.y, params.camera_pos_fade_start.z};
    shadow_fade_start := max(params.camera_pos_fade_start.w, 0.0);
    shadow_fade_end := max(params.fade_end_far_shade_shadow_end.z, shadow_fade_start + 0.001);
    shadow_dx := world_pos.x - camera_pos.x;
    shadow_dy := world_pos.y - camera_pos.y;
    shadow_dz := world_pos.z - camera_pos.z;
    shadow_dist := sqrt(max(shadow_dx * shadow_dx + shadow_dy * shadow_dy + shadow_dz * shadow_dz, 0.0));
    shadow_fade_t := clamp((shadow_fade_end - shadow_dist) / (shadow_fade_end - shadow_fade_start), 0.0, 1.0);
    if shadow_fade_t <= 0.0 {
        gl_Position = .{0.0, 0.0, 2.0, 1.0};
        depth01 = 1.0;
        return out;
    }
    clip := params.shadow_view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    gl_Position = clip;
    depth01 = clamp(clip.z, 0.0, 1.0);
    return out;
} @vertex_shader

model_scene_grass_shadow_fragment_main :: (using in: Grass_Shadow_Fragment_In, params: *Grass_Shadow_Params) -> struct { out_color: Vector4; } {
    _ = params;
    d := clamp(depth01, 0.0, 1.0);
    return .{out_color = .{d, d, d, 1.0}};
} @fragment_shader

model_scene_grass_vertex_main :: (using in: Grass_Vertex_In, params: *Grass_Draw_Params) -> Grass_Vertex_Out {
    using out: Grass_Vertex_Out;
    blade_t = grass_blade_vt(vertex_id);
    world_pos = grass_blade_world_pos(vertex_id, instance_id, blade_t, params);
    camera_pos := Vector3.{params.camera_pos_fade_start.x, params.camera_pos_fade_start.y, params.camera_pos_fade_start.z};
    fade_start := max(params.camera_pos_fade_start.w, 0.0);
    fade_end := max(params.fade_end_far_shade_shadow_end.x, fade_start + 0.001);
    dx := world_pos.x - camera_pos.x;
    dy := world_pos.y - camera_pos.y;
    dz := world_pos.z - camera_pos.z;
    dist := sqrt(max(dx * dx + dy * dy + dz * dz, 0.0));
    fade_t = clamp((fade_end - dist) / (fade_end - fade_start), 0.0, 1.0);
    if fade_t <= 0.0 {
        gl_Position = .{0.0, 0.0, 2.0, 1.0};
        shadow_uvz = .{0.0, 0.0, 2.0};
        shadow_meta = params.shadow_meta;
        normal = .{0.0, 1.0, 0.0};
        return out;
    }
    clip := params.view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    gl_Position = clip;
    shadow_clip := params.shadow_view_proj * Vector4.{world_pos.x, world_pos.y, world_pos.z, 1.0};
    shadow_uvz = .{shadow_clip.x * 0.5 + 0.5, shadow_clip.y * 0.5 + 0.5, shadow_clip.z};
    shadow_meta = params.shadow_meta;
    normal = grass_blade_normal(instance_id, world_pos, blade_t, params);
    return out;
} @vertex_shader

model_scene_grass_fragment_main :: (using in: Grass_Fragment_In, params: *Grass_Draw_Params) -> Vector4 @SV_Target0 {
    if fade_t <= 0.0 {
        discard();
    }

    dither_seed := world_pos.x * cast(float) 12.9898 + world_pos.y * cast(float) 78.233 + world_pos.z * cast(float) 37.719 + blade_t * cast(float) 5.173;
    dither := fract(sin(dither_seed) * cast(float) 43758.5453);
    if dither > fade_t {
        discard();
    }

    N := normalize(normal);
    sun_dir := normalize(-params.light_dir);
    sun_strength := max(params.sun_params.x, 0.0);
    L := sun_dir;
    V := normalize(params.camera_pos - world_pos);
    H := normalize(L + V);
    ndl_raw := dot(N, L);
    ndl := max(ndl_raw, 0.0);
    ndh := max(dot(N, H), 0.0);
    far_shade_start := clamp(params.fade_end_far_shade_shadow_end.y, params.camera_pos_fade_start.w, params.fade_end_far_shade_shadow_end.x);
    camera_pos := Vector3.{params.camera_pos_fade_start.x, params.camera_pos_fade_start.y, params.camera_pos_fade_start.z};
    dx := world_pos.x - camera_pos.x;
    dy := world_pos.y - camera_pos.y;
    dz := world_pos.z - camera_pos.z;
    dist := sqrt(max(dx * dx + dy * dy + dz * dz, 0.0));
    far_fade_span := max(far_shade_start - params.camera_pos_fade_start.w, 0.001);
    far_fade_t := clamp((far_shade_start - dist) / far_fade_span, 0.0, 1.0);
    use_far_shading := fade_t < 1.0 && far_fade_t <= 0.0;
    shadow := ifx use_far_shading then 1.0 else model_scene_shadow_visibility(shadow_meta, shadow_uvz);

    root_col := Vector3.{0.22, 0.18, 0.08};
    tip_col := Vector3.{0.74, 0.67, 0.31};
    tint_noise := hash01(world_pos.x * 0.17 + world_pos.z * 0.11 + 17.4);
    cool := Vector3.{0.92, 0.98, 1.03};
    warm := Vector3.{1.08, 1.02, 0.91};
    base := mix(root_col, tip_col, blade_t) * mix(cool, warm, tint_noise);

    indirect := ifx use_far_shading then Vector3.{0.18, 0.19, 0.16} else model_scene_indirect_light(N, sun_dir, sun_strength, shadow);
    wrapped_ndl := clamp((ndl_raw + 0.32) / 1.32, 0.0, 1.0);
    diffuse := wrapped_ndl * (ifx use_far_shading then 0.45 else 0.7) * shadow * sun_strength;
    specular := ifx use_far_shading then 0.0 else pow(ndh, 14.0) * 0.03 * shadow * sun_strength;
    rim := ifx use_far_shading then 0.0 else pow(1.0 - max(dot(N, V), 0.0), 2.3) * 0.08;
    sun_col := mix(Vector3.{1.0, 0.96, 0.9}, Vector3.{1.16, 0.62, 0.32}, 1.0 - clamp(abs(sun_dir.y) * 2.2, 0.0, 1.0));
    color := base * indirect + base * diffuse + sun_col * specular + base * rim;
    color = apply_atmosphere(color, world_pos, params.camera_pos, sun_dir);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader

model_scene_sky_vertex_main :: (using in: Model_Scene_Vertex_In, params: *Model_Scene_Sky_Params) -> Model_Scene_Sky_Vertex_Out {
    using out: Model_Scene_Sky_Vertex_Out;
    _ = params;
    if vertex_id == 0 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 1 { gl_Position = .{1.0, -1.0, 0.0, 1.0}; uv = .{1.0, 0.0}; }
    else if vertex_id == 2 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else if vertex_id == 3 { gl_Position = .{-1.0, -1.0, 0.0, 1.0}; uv = .{0.0, 0.0}; }
    else if vertex_id == 4 { gl_Position = .{1.0, 1.0, 0.0, 1.0}; uv = .{1.0, 1.0}; }
    else { gl_Position = .{-1.0, 1.0, 0.0, 1.0}; uv = .{0.0, 1.0}; }
    return out;
} @vertex_shader

model_scene_sky_fragment_main :: (using in: Model_Scene_Sky_Fragment_In, using params: *Model_Scene_Sky_Params) -> struct { out_color: Vector4; } {
    cam_up      := Vector3.{camera_up_proj_y.x, camera_up_proj_y.y, camera_up_proj_y.z};
    proj_x := camera_right_proj_x.w;
    proj_y := camera_up_proj_y.w;
    projection_mode := cast(u32) projection_mode_ortho_half_height.x;
    sun_dir := normalize(Vector3.{-light_dir_sun_strength.x, -light_dir_sun_strength.y, -light_dir_sun_strength.z});
    sun_strength := max(light_dir_sun_strength.w, 0.0);

    ndc := uv * 2.0 - 1.0;
    view_dir: Vector3;
    if projection_mode == 1 {
        // Keep a directional sky gradient in ortho instead of collapsing to a flat fill.
        view_dir = normalize(camera_forward_time_of_day.xyz + camera_right_proj_x.xyz * (ndc.x * 0.85) + cam_up * (ndc.y * 0.85));
    } else {
        view_dir = normalize(camera_forward_time_of_day.xyz + camera_right_proj_x.xyz * (ndc.x / max(proj_x, 0.0001)) + cam_up * (ndc.y / max(proj_y, 0.0001)));
    }
    color := model_scene_sky_color(view_dir, sun_dir, sun_strength);
    return .{out_color = .{color.x, color.y, color.z, 1.0}};
} @fragment_shader

apply_atmosphere :: (color: Vector3, world_pos: Vector3, camera_pos: Vector3, sun_dir: Vector3) -> Vector3 {
    view_vec := world_pos - camera_pos;
    dist := sqrt(max(dot(view_vec, view_vec), 0.0));
    fog := 1.0 - exp(-dist * 0.012);
    fog = clamp(fog, 0.0, 0.7);
    view_dir := normalize(view_vec);
    sky_col := model_scene_sky_base_color(view_dir, sun_dir);
    return mix(color, sky_col, fog);
}

#scope_file


grass_hash01_2 :: (x: float, y: float, phase: float) -> float {
    v := sin(x * cast(float) 127.1 + y * cast(float) 311.7 + phase * cast(float) 74.7) * cast(float) 43758.5453;
    return v - floor(v);
}

grass_ground_height :: (params: *$T, x: float, z: float) -> float {
    ridge := sin(x * cast(float) 0.23 + z * cast(float) 0.09) * params.ground_shape.x;
    swell := cos(z * cast(float) 0.18 - x * cast(float) 0.05) * params.ground_shape.y;
    warp_scale := params.ground_shape.z;
    warp := sin((x + z) * cast(float) 0.11) * warp_scale + cos((x - z) * cast(float) 0.07) * warp_scale;
    flatten := 1.0 - smoothstep(0.0, 6.0, abs(x) * cast(float) 0.38);
    return ridge + swell + warp - flatten * cast(float) 0.05;
}

grass_tip_dir :: (instance_id: u32, blade_t: float, params: *$T) -> Vector3 {
    t := params.ground_size_center_z_time.w;
    yaw := grass_hash01_2(cast(float) instance_id, cast(float) 1.7, cast(float) 0.23) * cast(float) 6.28318530718;
    bend_phase := grass_hash01_2(cast(float) instance_id, cast(float) 9.1, cast(float) 0.61) * cast(float) 6.28318530718;
    wind := sin(t * cast(float) 1.4 + bend_phase) * cast(float) 0.16 + cos(t * cast(float) 0.73 + bend_phase * cast(float) 1.7) * cast(float) 0.09;
    base_dir := normalize({sin(yaw) * cast(float) 0.2, 1.0, cos(yaw) * cast(float) 0.2});
    wind_dir := normalize({0.7, 0.0, 0.3});
    return normalize(base_dir + wind_dir * wind * blade_t * blade_t);
}

grass_blade_vt :: (vertex_id: u32) -> float #expand {
    GRASS_VERTS :: float.[0, 0, 1, 0, 1, 1];
    return GRASS_VERTS[vertex_id];
}

grass_blade_vx :: (vertex_id: u32) -> float {
    if vertex_id == 0 return -1.0;
    if vertex_id == 1 return 1.0;
    if vertex_id == 2 return -0.28;
    if vertex_id == 3 return 1.0;
    if vertex_id == 4 return 0.28;
    return -0.28;
}

grass_blade_world_pos :: (vertex_id: u32, instance_id: u32, vt: float, using params: *$T) -> Vector3 {
    grid_x := max(cast(u32) grass_grid_height_width.x, 1);
    grid_z := max(cast(u32) grass_grid_height_width.y, 1);
    gx := instance_id % grid_x;
    gz := instance_id / grid_x;
    fx := ifx grid_x > 1 then cast(float) gx / cast(float) (grid_x - 1) else 0.5;
    fz := ifx grid_z > 1 then cast(float) gz / cast(float) (grid_z - 1) else 0.5;

    size_x := ground_size_center_z_time.x;
    size_z := ground_size_center_z_time.y;
    center_z := ground_size_center_z_time.z;
    jitter := grass_grid_height_width.z;
    x := lerp(-size_x * 0.5, size_x * 0.5, fx);
    z := lerp(-size_z * 0.5, size_z * 0.5, fz) + center_z;
    cell_x := size_x / max(cast(float) grid_x, 1.0);
    cell_z := size_z / max(cast(float) grid_z, 1.0);
    x += (grass_hash01_2(cast(float) gx, cast(float) gz, cast(float) 0.11) * 2.0 - 1.0) * cell_x * jitter;
    z += (grass_hash01_2(cast(float) gx, cast(float) gz, cast(float) 0.67) * 2.0 - 1.0) * cell_z * jitter;

    base_y := grass_ground_height(params, x, z);
    blade_height := mix(grass_grid_height_width.w * cast(float) 0.7, grass_grid_height_width.w * cast(float) 1.3, grass_hash01_2(cast(float) gx, cast(float) gz, cast(float) 0.31));
    blade_width := max(blade_height * 0.11, 0.012);
    yaw := grass_hash01_2(cast(float) gx, cast(float) gz, cast(float) 0.83) * cast(float) 6.28318530718;
    right := Vector3.{cos(yaw), 0.0, sin(yaw)};
    vx := grass_blade_vx(vertex_id);

    pos := Vector3.{x, base_y, z} + right * (vx * blade_width) + .{0.0, vt * blade_height, 0.0};

    player_pos := player_pos_radius.xyz;
    player_yaw := player_pos_radius.y;
    player_radius := max(player_pos_radius.w, 0.001);
    delta := Vector2.{x - player_pos.x, z - player_pos.z};
    forward_2d := Vector2.{sin(player_yaw), cos(player_yaw)};
    side_2d := Vector2.{forward_2d.y, -forward_2d.x};
    ellipse_major := player_radius * 1.0;
    ellipse_minor := player_radius * 1.0;
    local_forward := dot(delta, forward_2d);
    local_side := dot(delta, side_2d);
    ellipse_dist2 := (local_forward * local_forward) / max(ellipse_major * ellipse_major, 0.0001) +
        (local_side * local_side) / max(ellipse_minor * ellipse_minor, 0.0001);
    if ellipse_dist2 < 1.0 {
        affect := 1.0 - sqrt(max(ellipse_dist2, 0.0));
        dist := sqrt(max(dot(delta, delta), 0.0));
        if dist > 1.0e-4 {
            away := delta / dist;
            pos.x += away.x * affect * affect * 0.55 * vt;
            pos.z += away.y * affect * affect * 0.55 * vt;
        }
        pos.y -= affect * affect * vt * blade_height * 0.85;
    }

    return pos + grass_tip_dir(instance_id, vt, params) * (vt * vt * 0.06);
}

grass_blade_normal :: (instance_id: u32, world_pos: Vector3, blade_t: float, params: *Grass_Draw_Params) -> Vector3 {
    up_dir := Vector3.{0.0, 1.0, 0.0};
    cam_to_blade := normalize(params.camera_pos - world_pos);
    side := normalize(cross(up_dir, cam_to_blade));
    tip_dir := grass_tip_dir(instance_id, blade_t, params);
    return normalize(cross(side, tip_dir));
}

load_skin_matrix :: (rows: *Vector4, bone_index: u32) -> Matrix4 {
    row_start := bone_index * 4;
    return .{
        rows[row_start + 0].x, rows[row_start + 0].y, rows[row_start + 0].z, rows[row_start + 0].w,
        rows[row_start + 1].x, rows[row_start + 1].y, rows[row_start + 1].z, rows[row_start + 1].w,
        rows[row_start + 2].x, rows[row_start + 2].y, rows[row_start + 2].z, rows[row_start + 2].w,
        rows[row_start + 3].x, rows[row_start + 3].y, rows[row_start + 3].z, rows[row_start + 3].w,
    };
}

model_scene_shadow_visibility :: (shadow_meta: Vector4, shadow_uvz: Vector3) -> float {
    tex_idx := cast(u32) shadow_meta.x;
    samp_idx := cast(u32) shadow_meta.y;
    bias := shadow_meta.z;
    texel := shadow_meta.w;

    u := shadow_uvz.x;
    v := 1.0 - shadow_uvz.y;
    z := shadow_uvz.z;
    if u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0 return 1.0;

    t0 := sample_2d(tex_idx, samp_idx, .{u - texel, v - texel});
    t1 := sample_2d(tex_idx, samp_idx, .{u + texel, v - texel});
    t2 := sample_2d(tex_idx, samp_idx, .{u - texel, v + texel});
    t3 := sample_2d(tex_idx, samp_idx, .{u + texel, v + texel});

    lit: float = 0.0;
    if z <= t0.x + bias lit += 1.0;
    if z <= t1.x + bias lit += 1.0;
    if z <= t2.x + bias lit += 1.0;
    if z <= t3.x + bias lit += 1.0;
    return mix(0.28, 1.0, lit * 0.25);
}

load_shadow_view_proj :: (instance: Scene_Instance) -> Matrix4 {
    return instance.shadow_view_proj;
}
