#import "Reload_Common";

Host_Message_Type :: enum {
  Unload;
  Reload;
  Quit;
  Init;
  Update;
}

Host_Message :: struct {
  type: Host_Message_Type;
  union {
    update_ctx: *App_Update_Ctx; // app may write to this
    quit_ctx:   Quit_Ctx; // read-only
    init_ctx:   Init_Ctx; // read-only
  }
}

#import "Reload_Common";

// A way for the app to signal back to the host.
App_Update_Ctx :: struct {
  //
  // Flags from the host to the app.
  //
  host_flags: enum u8 {
    Take_Sync_Screenshot :: 1 << 0; // app has requested that the host take a screenshot. host sets screenshot_filename field.
  };
  host_data: union {
    screenshot_filename: string;
  }

  app_return_flags: App_Return_Flags;
  app_return_data: union {
    load_app: string;
  }
}

//
// Flags from the app back up to the host.
//
App_Return_Flags :: enum u8 {
    Quit :: 1 << 0; // app has requested that the host should quit.
    Recompile :: 1 << 1; // app has requested that the host recompile the app dll from source.
    Reload :: 1 << 2; // app has requested that the host load a new app.
    Load_App :: 1 << 3; // app has requested that the host load a new app. app sets load_app field.
}

Quit_Ctx :: struct {
  keep_window_device_and_sdl: bool;
}

Init_Ctx :: struct {
  keep_window_device_and_sdl: bool;
  max_frames: int;
}

App_Return_Message :: struct {
  success: bool = true;
  error: string = "";
}
