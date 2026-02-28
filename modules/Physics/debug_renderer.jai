debug_renderer_procs :: DebugRenderer_Procs.{ Debug_DrawLine, Debug_DrawTriangle, Debug_DrawText3D, };

to_float_color :: (jph_color: JPH.Color) -> Vector4 {
    r := cast(float)((jph_color >> 24) & 0xff) * 255.0;
    g := cast(float)((jph_color >> 16) & 0xff) * 255.0;
    b := cast(float)((jph_color >> 8) & 0xff) * 255.0;
    a := cast(float)(jph_color & 0xff) * 255.0;
    return { 1, 0, 1, 1 };
}

Debug_DrawLine :: (userdata: *void, from: *Vec3, to: *Vec3, color: JPH.Color) #c_call {
    push_renderer_ctx(userdata);
    Gizmo.line(xx,force from.*, xx,force to.*, color);
}

Debug_DrawTriangle :: (userdata: *void, v1: *Vec3, v2: *Vec3, v3: *Vec3, color: JPH.Color, cast_shadow: DebugRenderer_CastShadow) #c_call {
    push_renderer_ctx(userdata);
    Gizmo.triangle(xx,force v1.*, xx,force v2.*, xx,force v3.*, color, filled=true);
}

Debug_DrawText3D :: (userdata: *void, position: Vec3, str: string, color: JPH.Color, height: float) #c_call {
    push_renderer_ctx(*physics.debug.ctx);
    Debug_DrawText3D(userdata, *position, temp_c_string(str), color, height);
}

Debug_DrawText3D :: (userdata: *void, position: *Vec3, str: *u8, color: JPH.Color, height: float) #c_call {
    push_renderer_ctx(*physics.debug.ctx);

    //UI :: #import "UI";
    //UI.report_replace(to_string(str));
    
    // TODO
}

#scope_file
Gizmo :: #import "Gizmo";
using JPH :: #import "JoltC";
