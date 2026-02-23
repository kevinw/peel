// Auto-generated JDLL interface module 'Game_Sound'

per_frame_update :: () #foreign Game_Sound_lib "_jdll_per_frame_update";
trigger_sound :: (name: string) #foreign Game_Sound_lib "_jdll_trigger_sound";
deinit_sounds :: () #foreign Game_Sound_lib "_jdll_deinit_sounds";
load_sounds :: () #foreign Game_Sound_lib "_jdll_load_sounds";

#scope_file
#if OS == .MACOS   Game_Sound_lib :: #library,no_static_library "macos/Game_Sound";
#if OS == .WINDOWS Game_Sound_lib :: #library,no_static_library "win/Game_Sound";
