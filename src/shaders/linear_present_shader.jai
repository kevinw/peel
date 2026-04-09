#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";

Linear_Present_Params :: struct {
    scene_texture_index: u32;
    sampler_index: u32;
    flip_y: u32;
    _pad0: u32;
    exposure: float;
}

Linear_Present_Fragment_In :: struct {
    uv: Vector2;
}

linear_present_tonemap :: (x: float, exposure: float) -> float {
    hdr := x * max(exposure, 0.001);
    mapped := (hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14);
    return clamp(mapped, 0.0, 1.0);
}

linear_present_linear_to_srgb :: (x: float) -> float {
    if x <= 0.0031308 return 12.92 * x;
    return 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

linear_present_tonemap :: (color: Vector3, exposure: float) -> Vector3 {
    hdr := color * max(exposure, 0.001);
    a := Vector3.{2.51, 2.51, 2.51};
    b := Vector3.{0.03, 0.03, 0.03};
    c := Vector3.{2.43, 2.43, 2.43};
    d := Vector3.{0.59, 0.59, 0.59};
    e := Vector3.{0.14, 0.14, 0.14};
    mapped := (hdr * (a * hdr + b)) / (hdr * (c * hdr + d) + e);
    return clamp(mapped, 0.0, 1.0);
}

linear_present_linear_to_srgb :: (c: Vector3) -> Vector3 {
    return .{
        linear_present_linear_to_srgb(c.x),
        linear_present_linear_to_srgb(c.y),
        linear_present_linear_to_srgb(c.z),
    };
}

linear_present_fragment_main :: (using input: Linear_Present_Fragment_In, params: *Linear_Present_Params) -> Vector4 @SV_Target0 {
    sample_uv := uv;
    if params.flip_y != 0 sample_uv.y = 1.0 - sample_uv.y;
    color := sample_2d(params.scene_texture_index, params.sampler_index, sample_uv).xyz;
    color = linear_present_tonemap(color, params.exposure);
    color = linear_present_linear_to_srgb(color);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
