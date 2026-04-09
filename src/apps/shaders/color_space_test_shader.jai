#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";

Color_Space_Test_Params :: struct {
    ground_color_srgb_index: u32;
    ground_color_linear_index: u32;
    snow_color_srgb_index: u32;
    snow_color_linear_index: u32;
    ground_roughness_index: u32;
    ground_ao_index: u32;
    ground_displacement_index: u32;
    ground_normal_index: u32;
    sampler_index: u32;
}

Color_Space_Test_Fragment_In :: struct {
    uv: Vector2;
}

color_space_test_grid_border :: (local_uv: Vector2) -> float {
    edge := min(min(local_uv.x, 1.0 - local_uv.x), min(local_uv.y, 1.0 - local_uv.y));
    return smoothstep(0.0, 0.012, edge);
}

color_space_test_panel_uv :: (uv: Vector2, cols: float, rows: float) -> Vector2 {
    return .{fract(uv.x * cols), fract(uv.y * rows)};
}

color_space_test_sample_panel :: (panel_id: u32, panel_uv: Vector2, params: *Color_Space_Test_Params) -> Vector3 {
    if panel_id == {
    case 0; return sample_2d(params.ground_color_srgb_index, params.sampler_index, panel_uv).xyz;
    case 1; return sample_2d(params.ground_color_linear_index, params.sampler_index, panel_uv).xyz;
    case 2; return sample_2d(params.snow_color_srgb_index, params.sampler_index, panel_uv).xyz;
    case 3; return sample_2d(params.snow_color_linear_index, params.sampler_index, panel_uv).xyz;
    case 4; {
        v := sample_2d(params.ground_roughness_index, params.sampler_index, panel_uv).x;
        return .{v, v, v};
    }
    case 5; {
        v := sample_2d(params.ground_ao_index, params.sampler_index, panel_uv).x;
        return .{v, v, v};
    }
    case 6; {
        v := sample_2d(params.ground_displacement_index, params.sampler_index, panel_uv).x;
        return .{v, v, v};
    }
    case 7; {
        encoded := sample_2d(params.ground_normal_index, params.sampler_index, panel_uv).xyz;
        normal := normalize(encoded * 2.0 - Vector3.{1.0, 1.0, 1.0});
        return normal * 0.5 + Vector3.{0.5, 0.5, 0.5};
    }
    }

    return .{1.0, 0.0, 1.0};
}

color_space_test_fragment_main :: (using in: Color_Space_Test_Fragment_In, params: *Color_Space_Test_Params) -> Vector4 @SV_Target0 {
    cols :: 4.0;
    rows :: 2.0;
    scaled_uv := Vector2.{uv.x * cols, uv.y * rows};
    panel_x := cast(u32) clamp(cast(s32) floor(scaled_uv.x), 0, 3);
    panel_y := cast(u32) clamp(cast(s32) floor(scaled_uv.y), 0, 1);
    panel_id := panel_x + panel_y * 4;
    panel_uv := color_space_test_panel_uv(uv, cols, rows);

    border_mix := color_space_test_grid_border(panel_uv);
    color := color_space_test_sample_panel(panel_id, panel_uv, params);
    border_color := Vector3.{0.045, 0.045, 0.05};
    color = lerp(border_color, color, border_mix);

    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
