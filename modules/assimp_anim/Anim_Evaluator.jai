Anim_Evaluator :: struct {
    anim: *Animation;
    last_time: float64;
    last_positions: [..]struct {
        pos: u32;
        rot: u32;
        scl: u32;
    };
    transforms: [..]Matrix4;
}

init :: (a: *Anim_Evaluator, anim: *Animation) {
    assert(anim != null);
    a.anim = anim;
    a.last_time = 0;
    array_resize(*a.last_positions, anim.mNumChannels);
}

deinit :: (using a: *Anim_Evaluator) {
    array_reset(*last_positions);
    array_reset(*transforms);
    anim = null;
    last_time = 0;
}

evaluate :: (using a: *Anim_Evaluator, pTime: float64) {
    // extract ticks per second. Assume default value if not given
    ticks_per_second := ifx anim.mTicksPerSecond else 25.0;

    // every following time calculation happens in ticks
    pTime *= ticks_per_second;

    // map into anim's duration
    time: float64 = 0;
    if anim.mDuration > 0
        time = SDL_fmod(pTime, anim.mDuration);
    
    if transforms.count != anim.mNumChannels
        array_resize(*transforms, anim.mNumChannels);

    // calculate the transformations for each animation channel
    for channel, a: channels(anim) {
        find_frame :: (keys: []$T, last_pos: u32) -> u32 #expand {
            // Look for present frame number. Search from last position if time is after the last time, else from beginning
            // Should be much quicker than always looking from start for the average use case.
            frame: u32 = ifx time >= last_time then last_pos else 0;
            while frame < keys.count - 1 {
                if time < keys[frame + 1].mTime {
                    break;
                }
                frame += 1;
            }
            return frame;
        }

        get_keys_to_interpolate :: (keys: []$T, frame: u32) -> (key: *T, next_key: *T, diff_time: float64) #expand {
            next_frame: u32 = (frame + 1) % keys.count.(u32);
            key: *T = *keys[frame];
            next_key: *T = *keys[next_frame];
            diff_time := next_key.mTime - key.mTime;
            if diff_time < 0.0
                diff_time += anim.mDuration;
            return key, next_key,  diff_time;
        }

        // ******** Position *********
        present_position: Vector3D = .{0, 0, 0};
        pos_keys := position_keys(channel);
        if pos_keys.count > 0 {
            frame := find_frame(pos_keys, last_positions[a].pos);
            defer last_positions[a].pos = frame;

            // interpolate between this frame's value and next frame's value
            key, next_key, diff_time := get_keys_to_interpolate(pos_keys, frame);
            if diff_time > 0 {
                factor := cast(float)((time - key.mTime) / diff_time);
                present_position = key.mValue + (next_key.mValue - key.mValue) * factor;
            } else {
                present_position = key.mValue;
            }

        }

        // ******** Rotation *********
        present_rotation := ai.Quaternion.{1, 0, 0, 0};
        rot_keys := rotation_keys(channel);
        if rot_keys.count > 0 {
            frame := find_frame(rot_keys, last_positions[a].rot);
            defer last_positions[a].rot = frame;

            key, next_key, diff_time := get_keys_to_interpolate(rot_keys, frame);
            if diff_time > 0 {
                factor := cast(float)((time - key.mTime) / diff_time);
                ai.QuaternionInterpolate(*present_rotation, *key.mValue, *next_key.mValue, factor);
            } else {
                present_rotation = key.mValue;
            }
        }

        // ******** Scale *********
        present_scale := ai.Vector3D.{1, 1, 1};
        scl_keys := scaling_keys(channel);
        if scl_keys.count > 0 {
            frame := find_frame(scl_keys, last_positions[a].scl);
            defer last_positions[a].scl = frame;
            present_scale = scl_keys[frame].mValue; // TODO interpolation maybe? This time maybe even logarithmic, not linear
        }

        // Build a transformation matrix from it
        mat := *transforms[a];

        // @WIP
        ai.Matrix4FromScalingQuaternionPosition(cast(*ai.Matrix4x4)mat, 
            scaling=*present_scale, rotation=*present_rotation, position=*present_position);
    }

    last_time = time;
}

#scope_file
scaling_keys  :: (using c: ai.NodeAnim) -> []VectorKey { return .{ mNumScalingKeys, mScalingKeys }; }
rotation_keys :: (using c: ai.NodeAnim) -> []QuatKey   { return .{ mNumRotationKeys, mRotationKeys }; }
position_keys :: (using c: ai.NodeAnim) -> []VectorKey { return .{ mNumPositionKeys, mPositionKeys }; }