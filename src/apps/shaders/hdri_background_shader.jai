#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";

HDRI_Background_Params :: struct {
    camera_right_proj_x: Vector4;
    camera_up_proj_y: Vector4;
    camera_forward_exposure: Vector4;
    skybox_texture_index: u32;
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

hdri_background_fragment_main :: (using in: HDRI_Background_Fragment_In, params: *HDRI_Background_Params) -> Vector4 @SV_Target0 {
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

    hdr := sample_cube(params.skybox_texture_index, params.sampler_index, view_dir).xyz * exposure;
    color := hdri_tonemap(hdr);
    return .{color.x, color.y, color.z, 1.0};
} @fragment_shader
