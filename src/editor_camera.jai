#scope_export

Editor_Camera_Projection_Mode :: enum {
    Perspective;
    Orthographic;
}

Editor_Camera :: struct {
    position: Vector3;
    yaw: float;
    pitch: float;
    fov_y: float = PI / 3.2;
    ortho_half_height: float = 1.0;
    projection_mode: Editor_Camera_Projection_Mode = .Perspective;
    target_projection_mode: Editor_Camera_Projection_Mode = .Perspective;
    projection_blend: float;
    projection_transition_speed: float = 7.5;
    transition_anchor_distance: float = 8.0;
    transition_anchor: Vector3;
    have_transition_anchor: bool;

    world_up: Vector3 = .{0.0, 1.0, 0.0};
    move_speed: float = 5.0;
    boost_multiplier: float = 2.0;
    mouse_sensitivity: float = 0.0032;
    mouse_wheel_fov_sensitivity: float = -0.08;
    pitch_min: float = -1.5;
    pitch_max: float = 1.5;
    fov_y_min: float = PI / 12.0;
    fov_y_max: float = PI * 0.9;
    move_planar: bool;

    prev_mouse: Vector2;
    have_prev_mouse: bool;
}

Editor_Camera_Update_Result :: struct {
    moved: bool;
    looked: bool;
}

editor_camera_set_forward :: (using camera: *Editor_Camera, forward: Vector3) {
    yaw, pitch = editor_camera_angles_from_forward(forward);
    pitch = clamp(pitch, pitch_min, pitch_max);
}

editor_camera_apply_look_delta :: (using camera: *Editor_Camera, delta_x: float, delta_y: float) {
    yaw += delta_x * mouse_sensitivity;
    pitch += delta_y * mouse_sensitivity;
    pitch = clamp(pitch, pitch_min, pitch_max);
}

editor_camera_set_look_at :: (camera: *Editor_Camera, target: Vector3) {
    editor_camera_set_forward(camera, target - camera.position);
}

editor_camera_forward :: (using camera: Editor_Camera) -> Vector3 {
    f := editor_camera_forward_from_angles(yaw, pitch);
    normalize(*f, fallback = .{0.0, 0.0, -1.0});
    return f;
}

editor_camera_basis :: (using camera: Editor_Camera, forward: *Vector3, right: *Vector3, up: *Vector3) {
    f, r, u := editor_camera_basis(camera);

    forward.* = f;
    right.* = r;
    up.* = u;
}

editor_camera_basis :: (using camera: Editor_Camera) -> (forward: Vector3, right: Vector3, up: Vector3) {
    f := editor_camera_forward_from_angles(yaw, pitch);
    normalize(*f, fallback = .{0.0, 0.0, -1.0});

    up_axis := world_up;
    if dot(up_axis, up_axis) < 0.000001 {
        up_axis = .{0.0, 1.0, 0.0};
    }

    r := cross(f, up_axis);
    normalize(*r, fallback = .{1.0, 0.0, 0.0});

    u := cross(r, f);
    normalize(*u, fallback = up_axis);

    return f, r, u;
}

editor_camera_make_view :: (camera: *Editor_Camera) -> Matrix4 {
    forward, right, up: Vector3;
    editor_camera_basis(camera, *forward, *right, *up);
    viewpoint := editor_camera_transition_viewpoint(camera.*);
    return make_look_at_matrix(
        viewpoint = viewpoint,
        look_at = viewpoint + forward,
        reference_up_vector = up,
        x_is_forward = false);
}

editor_camera_make_perspective_projection :: (camera: *Editor_Camera, aspect: float, z_near: float, z_far: float) -> Matrix4 {
    return make_projection_matrix(editor_camera_transition_fov_y(camera.*), aspect, z_near, z_far);
}

editor_camera_make_orthographic_projection :: (camera: *Editor_Camera, aspect: float, z_near: float, z_far: float) -> Matrix4 {
    ortho_half_height := max(camera.ortho_half_height, 0.0001);
    ortho_half_width := ortho_half_height * max(aspect, 0.0001);
    depth_extent := max(max(abs(z_near), abs(z_far)), 0.1);
    return orthographic_projection_matrix(
        -ortho_half_width, ortho_half_width,
        -ortho_half_height, ortho_half_height,
        -depth_extent, depth_extent);
}

editor_camera_make_projection :: (camera: *Editor_Camera, aspect: float, z_near: float, z_far: float) -> Matrix4 {
    persp := editor_camera_make_perspective_projection(camera, aspect, z_near, z_far);
    ortho := editor_camera_make_orthographic_projection(camera, aspect, z_near, z_far);

    t := clamp(camera.projection_blend, 0.0, 1.0);
    if t <= 0.0001 return persp;
    if t >= 0.9999 return ortho;
    return persp;
}

editor_camera_projection_lod_scale :: (camera: *Editor_Camera, render_height: float) -> float {
    persp := render_height / max(2.0 * max(tan(editor_camera_transition_fov_y(camera) * 0.5), 0.0001), 0.0001);
    ortho := render_height / max(2.0 * max(camera.ortho_half_height, 0.0001), 0.0001);
    t := clamp(camera.projection_blend, 0.0, 1.0);
    return lerp(persp, ortho, t);
}

editor_camera_transition_anchor :: (camera: *Editor_Camera, target: Vector3 = .{}, has_target: bool = false) -> Vector3 {
    if has_target return target;
    return camera.position + editor_camera_forward(camera.*) * max(0.01, camera.transition_anchor_distance);
}

editor_camera_set_projection_mode :: (camera: *Editor_Camera, mode: Editor_Camera_Projection_Mode, target: Vector3 = .{}, has_target: bool = false) {
    anchor := editor_camera_transition_anchor(camera, target, has_target);
    camera.transition_anchor = anchor;
    camera.have_transition_anchor = true;
    if mode == .Orthographic && camera.target_projection_mode != .Orthographic {
        forward := editor_camera_forward(camera.*);
        anchor_depth := max(dot(anchor - camera.position, forward), 0.01);
        camera.ortho_half_height = max(0.0001, anchor_depth * tan(camera.fov_y * 0.5));
    }
    camera.target_projection_mode = mode;
}

editor_camera_toggle_projection_mode :: (camera: *Editor_Camera, target: Vector3 = .{}, has_target: bool = false) {
    mode: Editor_Camera_Projection_Mode = ifx camera.target_projection_mode == .Orthographic then .Perspective else .Orthographic;
    editor_camera_set_projection_mode(camera, mode, target, has_target);
}

editor_camera_update_projection :: (
    using camera: *Editor_Camera,
    dt: float,
    mouse_valid: bool,
    allow_zoom: bool = true,
) {
    target_blend := ifx target_projection_mode == .Orthographic then 1.0 else 0.0;
    was_orthographic := projection_mode == .Orthographic;
    projection_blend = approach(projection_blend, target_blend, dt * projection_transition_speed);
    if projection_blend <= 0.0001 {
        if was_orthographic && have_transition_anchor {
            position = editor_camera_transition_viewpoint(camera.*);
        }
        projection_blend = 0.0;
        projection_mode = .Perspective;
    } else if projection_blend >= 0.9999 {
        projection_blend = 1.0;
        projection_mode = .Orthographic;
    }

    if allow_zoom && mouse_valid && !ImGui.GetIO().WantCaptureMouse {
        wheel := ImGui.GetIO().MouseWheel;
        if wheel != 0.0 {
            if projection_blend >= 0.9999 {
                ortho_half_height *= exp(-wheel * mouse_wheel_fov_sensitivity);
                ortho_half_height = max(0.01, ortho_half_height);
            } else {
                fov_y -= wheel * mouse_wheel_fov_sensitivity;
                fov_y = clamp(fov_y, fov_y_min, fov_y_max);
            }
        }
    }
}

editor_camera_update_movement :: (
    using camera: *Editor_Camera,
    dt: float,
    allow_move: bool = true,
) -> moved: bool {
    if !allow_move return false;

    forward, right, up: Vector3;
    editor_camera_basis(camera, *forward, *right, *up);

    move := Vector3.{0.0, 0.0, 0.0};
    if move_planar {
        forward = .{forward.x, 0.0, forward.z};
        normalize(*forward, fallback = .{0.0, 0.0, -1.0});
        right = .{right.x, 0.0, right.z};
        normalize(*right, fallback = .{1.0, 0.0, 0.0});
        up = world_up;
    }

    if Input.input_button_states[cast(Input.Key_Code) #char "W"] & .DOWN move += forward;
    if Input.input_button_states[cast(Input.Key_Code) #char "S"] & .DOWN move -= forward;
    if Input.input_button_states[cast(Input.Key_Code) #char "A"] & .DOWN move -= right;
    if Input.input_button_states[cast(Input.Key_Code) #char "D"] & .DOWN move += right;
    if Input.input_button_states[cast(Input.Key_Code) #char "Q"] & .DOWN move -= up;
    if Input.input_button_states[cast(Input.Key_Code) #char "E"] & .DOWN move += up;

    move_len_sq := dot(move, move);
    if move_len_sq <= 0.000001 return false;

    move *= 1.0 / sqrt(move_len_sq);
    speed := camera.move_speed;
    if Input.input_button_states[Input.Key_Code.SHIFT] & .DOWN {
        speed *= max(1.0, camera.boost_multiplier);
    }
    position += move * (speed * dt);
    return true;
}

editor_camera_orbit_around :: (camera: *Editor_Camera, pivot: Vector3, delta_x: float, delta_y: float) {
    orbit_distance := max(distance(camera.position, pivot), 0.01);
    editor_camera_apply_look_delta(camera, delta_x, delta_y);
    camera.position = pivot - editor_camera_forward(camera.*) * orbit_distance;
}

editor_camera_view_position :: (camera: Editor_Camera) -> Vector3 {
    return editor_camera_transition_viewpoint(camera);
}

editor_camera_update :: (
    using camera: *Editor_Camera,
    dt: float,
    mouse_x: s64,
    mouse_y: s64,
    mouse_valid: bool,
    allow_move: bool = true,
    allow_look: bool = false,
    allow_zoom: bool = true,
) -> Editor_Camera_Update_Result {
    result: Editor_Camera_Update_Result;
    editor_camera_update_projection(camera, dt, mouse_valid, allow_zoom);

    if allow_look && mouse_valid {
        mouse := Vector2.{cast(float) mouse_x, cast(float) mouse_y};
        if have_prev_mouse {
            delta := mouse - prev_mouse;
            if delta.x != 0.0 || delta.y != 0.0 {
                editor_camera_apply_look_delta(camera, delta.x, delta.y);
                result.looked = true;
            }
        }
        prev_mouse = mouse;
        have_prev_mouse = true;
    } else {
        have_prev_mouse = false;
    }

    result.moved = editor_camera_update_movement(camera, dt, allow_move);

    return result;
}

#scope_file

EDITOR_CAMERA_TRANSITION_MIN_FOV_Y :: PI / 90.0;

editor_camera_transition_fov_y :: (camera: Editor_Camera) -> float {
    t := editor_camera_transition_smooth_t(camera);
    if t <= 0.0001 return camera.fov_y;
    if t >= 0.9999 return max(min(camera.fov_y, EDITOR_CAMERA_TRANSITION_MIN_FOV_Y), 0.0005);

    base_half_tan := max(tan(camera.fov_y * 0.5), 0.0001);
    min_half_tan := max(tan(min(camera.fov_y, EDITOR_CAMERA_TRANSITION_MIN_FOV_Y) * 0.5), 0.0001);
    return 2.0 * atan(lerp(base_half_tan, min_half_tan, t));
}

editor_camera_transition_viewpoint :: (camera: Editor_Camera) -> Vector3 {
    t := editor_camera_transition_smooth_t(camera);
    if t <= 0.0001 return camera.position;
    if t >= 0.9999 && camera.projection_mode == .Orthographic return camera.position;

    forward := editor_camera_forward(camera);
    anchor := ifx camera.have_transition_anchor
        then camera.transition_anchor
        else camera.position + forward * max(0.01, camera.transition_anchor_distance);
    half_tan := max(tan(editor_camera_transition_fov_y(camera) * 0.5), 0.0001);
    distance := max(camera.ortho_half_height / half_tan, 0.01);
    return anchor - forward * distance;
}

editor_camera_transition_smooth_t :: (camera: Editor_Camera) -> float {
    t := clamp(camera.projection_blend, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

editor_camera_lerp_matrix4 :: (a: Matrix4, b: Matrix4, t: float) -> Matrix4 {
    result: Matrix4;
    for *result.floats {
        it.* = lerp(a.floats[it_index], b.floats[it_index], t);
    }
    return result;
}

editor_camera_forward_from_angles :: (yaw: float, pitch: float) -> Vector3 {
    cp := cos(pitch);
    return .{
        sin(yaw) * cp,
        sin(pitch),
        -cos(yaw) * cp,
    };
}

editor_camera_angles_from_forward :: (forward: Vector3) -> (yaw: float, pitch: float) {
    n := forward;
    normalize(*n, fallback = .{0.0, 0.0, -1.0});
    return atan2(n.x, -n.z), asin(clamp(n.y, -1.0, 1.0));
}

#import "Math";
ImGui :: #import "ImGui";
Input :: #import "Input";
