/*

game sounds

*/
PLAY_MUSIC :: false;

sounds: struct {
    footsteps: Sound_Data;
    music: Sound_Data;
}

#program_export
load_sounds :: () {
    push_context {
    sound_player_init(.{});

    using sounds;
    footsteps = load_audio_file("sounds/535220__spycrah__grass-step-left.wav");
    if !footsteps.loaded log_error("Failed to load footsteps sound");

    #if PLAY_MUSIC {
        music = load_audio_file("music/Calm Pond.ogg");
        if !music.loaded log_error("Failed to load music");
        else {
            stream := make_stream(*music, .MUSIC);
            set_repeating(stream, true);
            start_playing(stream);
        }
    }
    }
}

#program_export
deinit_sounds :: () {
    using sounds;
    sound_player_shutdown();
}

stage_sound :: (data: *Sound_Data, category := Sound_Category.GENERAL_SFX, perturb := true) -> *Sound_Stream {
    stream := make_stream(data, category);

    if perturb {
        stream.user_volume_scale = random_get_within_range(0.5, 1.4);
        stream.rate_scale        = random_get_within_range(0.7, 1.22);
    }

    return stream;
}

#program_export
trigger_sound :: (name: string) {
    push_context {
    using sounds;
    sound_data: *Sound_Data;
    if name == {
    case "footstep";
        sound_data = *footsteps;
    }
    if sound_data == null {
        log_error("no sound for event '%'", name);
        return;
    }

    if !footsteps.loaded {
        log_error("sound % not loaded", name);
        return;
    }

    stream := stage_sound(*footsteps, .GENERAL_SFX, true);
    start_playing(stream);
    }
}

#program_export
per_frame_update :: () {
    Sound_Player.update();
}

#scope_file
using Sound_Player :: #import "Sound_Player";
#import "Random";
#import "Basic";
