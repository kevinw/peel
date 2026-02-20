// Auto-generated interface module for JDLL 'Game_Sound'

per_frame_update :: () #c_call #foreign Game_Sound_lib;
trigger_sound :: (name: string) #c_call #foreign Game_Sound_lib;
deinit_sounds :: () #c_call #foreign Game_Sound_lib;
load_sounds :: () #c_call #foreign Game_Sound_lib;

#scope_file
#if OS == .MACOS {
    Game_Sound_lib :: #library,no_static_library "macos/Game_Sound";
} else #if OS == .WINDOWS {
    Game_Sound_lib :: #library,no_static_library "win/Game_Sound";
}
