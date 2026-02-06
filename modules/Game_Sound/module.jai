// Auto-generated interface module for JDLL 'Game_Sound'

per_frame_update :: () #elsewhere Game_Sound_lib "per_frame_update";
trigger_sound :: (name: string) #elsewhere Game_Sound_lib "trigger_sound";
deinit_sounds :: () #elsewhere Game_Sound_lib "deinit_sounds";
load_sounds :: () #elsewhere Game_Sound_lib "load_sounds";

#scope_file
#if OS == .MACOS {
Game_Sound_lib :: #library,no_static_library "lib/macos/Game_Sound";
} else #if OS == .WINDOWS {
Game_Sound_lib :: #library,no_static_library "lib/win/Game_Sound";
}
