// todo

#load "../App_Common.jai";
#load "../SGPU_App_Common.jai";

on_dll_init :: () {
    log("peel dll init");

    if window == null {
        window = create_window(800, 600, "hello peel");
        result := gpu_init();
        assert(result == .SUCCESS);

        window_type: Native_Window_Type;
        #if      OS == .WINDOWS then window_type = .WIN32;
        else #if OS == .LINUX   then window_type = .X11;
        else #if OS == .MACOS   then window_type = .COCOA;
        else assert(false, "Unsupported OS");

        gpu_init_swapchain(cast(u64)window, window_type);
    }

} @on_dll_init

tick :: () {

} @on_tick

#scope_file
#import "Window_Creation";
#import "sgpu";
