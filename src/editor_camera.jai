#scope_export

Editor_Camera :: struct {
    position: Vector3;
    yaw: float;
    pitch: float;

    world_up: Vector3 = .{0.0, 1.0, 0.0};
    move_speed: float = 5.0;
    boost_multiplier: float = 2.0;
    mouse_sensitivity: float = 0.0032;
    pitch_min: float = -1.5;
    pitch_max: float = 1.5;
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

editor_camera_set_look_at :: (camera: *Editor_Camera, target: Vector3) {
    editor_camera_set_forward(camera, target - camera.position);
}

editor_camera_basis :: (using camera: *Editor_Camera, forward: *Vector3, right: *Vector3, up: *Vector3) {
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

    forward.* = f;
    right.* = r;
    up.* = u;
}

editor_camera_make_view :: (camera: *Editor_Camera) -> Matrix4 {
    forward, right, up: Vector3;
    editor_camera_basis(camera, *forward, *right, *up);
    return make_look_at_matrix(
        viewpoint = camera.position,
        look_at = camera.position + forward,
        reference_up_vector = up,
        x_is_forward = false);
}

editor_camera_update :: (
    using camera: *Editor_Camera,
    dt: float,
    mouse_x: s64,
    mouse_y: s64,
    mouse_valid: bool,
    allow_move: bool = true,
    allow_look: bool = false,
) -> Editor_Camera_Update_Result {
    result: Editor_Camera_Update_Result;

    if allow_look && mouse_valid {
        mouse := Vector2.{cast(float) mouse_x, cast(float) mouse_y};
        if have_prev_mouse {
            delta := mouse - prev_mouse;
            if delta.x != 0.0 || delta.y != 0.0 {
                yaw += delta.x * mouse_sensitivity;
                pitch += delta.y * mouse_sensitivity;
                pitch = clamp(camera.pitch, pitch_min, pitch_max);
                result.looked = true;
            }
        }
        prev_mouse = mouse;
        have_prev_mouse = true;
    } else {
        have_prev_mouse = false;
    }

    if allow_move {
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
        if move_len_sq > 0.000001 {
            move *= 1.0 / sqrt(move_len_sq);
            speed := camera.move_speed;
            if Input.input_button_states[Input.Key_Code.SHIFT] & .DOWN {
                speed *= max(1.0, camera.boost_multiplier);
            }
            position += move * (speed * dt);
            result.moved = true;
        }
    }

    return result;
}

#scope_file

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
Input :: #import "Input";
