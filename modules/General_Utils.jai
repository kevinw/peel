/*

TODO: separate out this module by category

*/

temp_string_builder :: (code: Code) -> string #expand {
    `sb: String_Builder;
    `sb.allocator = temp;
    #insert code;
    return builder_to_string(*sb,, temp);
}

tptr :: (val: $T) -> *T {
	ptr : *T = talloc(size_of(T));
	ptr.* = val;
	return ptr;
}

clamp_length :: (v: *Vector2, max_length: float) {
    len := length(v.*);
    if len > max_length
        v.* /= len;
}

approach :: (from: float, target: float, max_delta: float) -> float {
    if from > target
    return max(from - max_delta, target);

    return min(from + max_delta, target);
}

approach :: (from: *float, target: float, max_delta: float) {
    if from.* > target {
        from.* = max(from.* - max_delta, target);
        return;
    }

}

approach :: (from: $R, target: R, max_delta: float) -> R
#modify {
    // This lerp only applies to the types below:
    return (R == Vector2) || (R == Vector3) || (R == Vector4);
} {
    if (from == target) {
        return target;
    }

    diff := target - from;
    if (length_squared(diff) <= max_delta * max_delta) {
        return target;
    }

    return from + normalize(diff) * max_delta;
}

approach :: (from: *$R, target: R, max_delta: float)
#modify {
    // This lerp only applies to the types below:
    return (R == Vector2) || (R == Vector3) || (R == Vector4);
} {
    if (from.* == target) return;

    diff := target - from.*;
    if (length_squared(diff) <= max_delta * max_delta) {
        from.* = target;
        return;
    }

    from.* += normalize(diff) * max_delta;
}

move_toward :: (a_pointer: *Vector2, target: Vector2, dt: float, rate_up: float, rate_down: float = -1.0) {
    a := a_pointer.*;
    // TODO: this is wrong. a unit circle should be used instead, so that the diagonals aren't faster.
    if a.x > target.x {
        if rate_down == -1.0 rate_down = rate_up;
        a.x -= dt * rate_down;
        if a.x < target.x { a.x = target.x; }
    } else if a.x < target.x {
        a.x += dt * rate_up;
        if a.x > target.x { a.x = target.x; }
    }
    if a.y > target.y {
        if rate_down == -1.0 rate_down = rate_up;
        a.y -= dt * rate_down;
        if a.y < target.y { a.y = target.y; }
    } else if a.y < target.y {
        a.y += dt * rate_up;
        if a.y > target.y { a.y = target.y; }
    }
    a_pointer.* = a;
}

move_toward :: (a_pointer: *float, target: float, dt: float, rate_up: float, rate_down: float = -1.0) {
    a := a_pointer.*;

    if a > target {
        if rate_down == -1.0 rate_down = rate_up;
        a -= dt * rate_down;
        if a < target { a = target; }
    } else if a < target {
        a += dt * rate_up;
        if a > target { a = target; }
    }

    a_pointer.* = a;
}

V4 :: struct($T: Type) {
    x: T;
    y: T;
    z: T;
    w: T;
}

V2 :: struct($T: Type) {
    x: T;
    y: T;
}

operator + :: (a: V2($T), b: V2(T)) -> V2(T) {
    return .{a.x + b.x, a.y + b.y};
}

operator += :: (a: *V2($T), b: V2(T)) {
    a.* = a.* + b;
}


clamp :: (x: Vector2, a: Vector2, b: Vector2) -> Vector2 {
    return .{clamp(x.x, a.x, b.x), clamp(x.y, a.y, b.y)};
}


smooth_damp :: (current: *float, target: float, current_velocity: *float, smooth_time: float, max_speed: float = 9999999.0, delta_time: float = 1.0) {
    current.* = smooth_damp(current.*, target, current_velocity, smooth_time, max_speed, delta_time);
}

smooth_damp :: (current: float, target: float, current_velocity: *float, smooth_time: float, max_speed: float = 9999999.0, delta_time: float = 1.0) -> float {
    delta_time = max(0.00000001, delta_time);
    smooth_time = max(0.00000001, smooth_time);

    omega := 2.0 / smooth_time;
    x := omega * delta_time;
    exp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);
    change := current - target;
    original_to := target;
    max_change := max_speed * smooth_time;
    change = clamp(change, -max_change, max_change);
    target = current - change;
    temp := (current_velocity.* + omega * change) * delta_time;
    current_velocity.* = (current_velocity.* - omega * temp) * exp;
    output := target + (change + temp) * exp;
    if (original_to - current > 0) == (output > original_to) {
        output = original_to;
        current_velocity.* = (output - original_to) / delta_time;
    }
    return output;
}


smooth_damp :: (current: *Vector2, target: Vector2, currentVelocity: *Vector2, smoothTime: float, maxSpeed: float = -FLOAT32_INFINITY, deltaTime: float = -1.0) {
    current.* = smooth_damp(current.*, target, currentVelocity, smoothTime, maxSpeed, deltaTime);
}

smooth_damp :: (current: Vector2, target_: Vector2, currentVelocity: *Vector2, smoothTime: float, maxSpeed: float = -FLOAT32_INFINITY, deltaTime: float = -1.0) -> Vector2
{
    target := target_;
    if deltaTime == -1.0 assert(false); //deltaTime = GetFrameTime();

    // Based on Game Programming Gems 4 Chapter 1.10
    smoothTime = max(0.0001, smoothTime);
    omega := 2.0 / smoothTime;

    x := omega * deltaTime;
    exp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);
    change := current - target;
    originalTo := target;

    // Clamp maximum speed
    maxChange := maxSpeed * smoothTime;

    maxChangeSq := maxChange * maxChange;
    sqDist := change.x * change.x + change.y * change.y;
    if sqDist > maxChangeSq {
        mag := sqrt(sqDist);
        change = change / mag * maxChange;
    }

    target = current - change;
    tmp := (currentVelocity.* + omega * change) * deltaTime;
    currentVelocity.* = (currentVelocity.* - omega * tmp) * exp;

    output := target + (change + tmp) * exp;

    // Prevent overshooting
    origMinusCurrent := originalTo - current;
    outMinusOrig := output - originalTo;

    if origMinusCurrent.x * outMinusOrig.x + origMinusCurrent.y * outMinusOrig.y > 0 {
        output = originalTo;
        currentVelocity.* = (output - originalTo) / deltaTime;
    }

    return output;
}

easeval :: (val: float, smooth_time: float = 0.12) -> Ease_Value(float) {
    return .{value = val, target = val, velocity = 0, smooth_time = smooth_time};
}

Ease_Value :: struct(T: Type) {
    #as value: T;
    target: T;
    velocity: T;
    smooth_time: float = 1.0;
}

update :: (ev: *Ease_Value($T), dt: float) #expand {
    smooth_damp(*ev.value, ev.target, *ev.velocity, smooth_time=ev.smooth_time, delta_time=dt);
}


inverse_or_log :: (m: Matrix4, name: string = "") -> Matrix4 {
    ok, inv := inverse(m);
    if !ok {
        log_error("failed to invert matrix '%'", name);
        log("matrix which failed to invert: %", m);
        return .{};
    }
    return inv;
}

or_return_false :: (ptr: *$T) -> *T #expand {
	if ptr == null `return false;
	return ptr;
}

or_return_false :: (val: bool, msg: string, fmt_args: ..Any) #expand {
	if !val {
		if msg log_error(msg, ..fmt_args);
		`return false;
	}
}

human_readable_bytes :: (bytes: u64, trailing_width := 1) -> string {
    builder: String_Builder;

    formatter := FormatFloat.{
        trailing_width=trailing_width,
        zero_removal=.NO
    };

    if bytes >= 1024*1024*1024 {
        formatter.value = bytes/(1024.0*1024.0*1024.0);
        print_to_builder(*builder, "% GB", formatter);
    } else if bytes >= 1024*1024 {
        formatter.value = bytes/(1024.0*1024.0);
        print_to_builder(*builder, "% MB", formatter);
    } else if bytes >= 1024 {
        formatter.value = bytes/(1024.0);
        print_to_builder(*builder, "% KB", formatter);
    } else {
        formatter.value = bytes.(float);
        print_to_builder(*builder, "% B", formatter);
    }

    str := builder_to_string(*builder);
    return str;
}

#scope_file
#import "Math";
#import "Basic";
