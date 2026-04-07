#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";

HDRI_Background_Params :: struct {
    camera_right_proj_x: Vector4;
    camera_up_proj_y: Vector4;
    camera_forward_exposure: Vector4;
    texture_index: u32;
    sampler_index: u32;
    _pad0: u32;
    _pad1: u32;
}

HDRI_Background_Fragment_In :: struct {
    uv: Vector2;
}

hdri_tonemap :: (color: Vector3) -> Vector3 {
    a := Vector3.{2.51, 2.51, 2.51};
    b := Vector3.{0.03, 0.03, 0.03};
    c := Vector3.{2.43, 2.43, 2.43};
    d := Vector3.{0.59, 0.59, 0.59};
    e := Vector3.{0.14, 0.14, 0.14};
    mapped := (color * (a * color + b)) / (color * (c * color + d) + e);
    return clamp(mapped, 0.0, 1.0);
}

hdri_atan2_approx :: (y: float, x: float) -> float {
    pi_over_4 := cast(float) 0.7853981633974483;
    three_pi_over_4 := cast(float) 2.356194490192345;
    abs_y := abs(y) + 0.000001;
    r: float;
    angle: float;
    if x < 0.0 {
        r = (x + abs_y) / (abs_y - x);
        angle = three_pi_over_4;
    } else {
        r = (x - abs_y) / (x + abs_y);
        angle = pi_over_4;
    }
    angle += (cast(float) 0.1963 * r * r - cast(float) 0.9817) * r;
    if y < 0.0 return -angle;
    return angle;
}

hdri_acos_approx :: (x: float) -> float {
    pi := cast(float) 3.141592653589793;
    x_clamped := clamp(x, -1.0, 1.0);
    x_abs := abs(x_clamped);
    negate := ifx x_clamped < 0.0 then 1.0 else 0.0;
    ret := cast(float) -0.0187293;
    ret = ret * x_abs + cast(float) 0.0742610;
    ret = ret * x_abs + cast(float) -0.2121144;
    ret = ret * x_abs + cast(float) 1.5707288;
    ret *= sqrt(max(1.0 - x_abs, 0.0));
    ret = ret - 2.0 * negate * ret;
    return negate * pi + ret;
}

hdri_background_fragment_main :: (using in: HDRI_Background_Fragment_In, params: *HDRI_Background_Params) -> Vector4 @SV_Target0 {
    two_pi := cast(float) 6.283185307179586;
    inv_pi := cast(float) 0.3183098861837907;
    cam_right := params.camera_right_proj_x.xyz;
    cam_up := params.camera_up_proj_y.xyz;
    cam_forward := params.camera_forward_exposure.xyz;
    proj_x := params.camera_right_proj_x.w;
    proj_y := params.camera_up_proj_y.w;
    exposure := max(params.camera_forward_exposure.w, 0.001);

    ndc := uv * 2.0 - 1.0;
    view_dir := normalize(
        cam_forward +
        cam_right * (ndc.x / max(proj_x, 0.0001)) +
        cam_up * (ndc.y / max(proj_y, 0.0001))
    );

    lon := hdri_atan2_approx(view_dir.z, view_dir.x);
    lat := hdri_acos_approx(view_dir.y);
    texcoord := Vector2.{
        lon / two_pi + 0.5,
        lat * inv_pi,
    };

    hdr := sample_2d(params.texture_index, params.sampler_index, texcoord).xyz * exposure;
    color := hdri_tonemap(hdr);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
