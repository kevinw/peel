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
  Host_Build_State :: enum u8 {
    NONE;
    QUEUED;
    RUNNING;
    FAILED;
  }

  //
  // Flags from the host to the app.
  //
  host_flags: enum u8 {
    Take_Sync_Screenshot :: 1 << 0; // app has requested that the host take a screenshot. host sets screenshot_filename field.
  };
  host_data: union {
    screenshot_filename: string;
  }
  host_build_state: Host_Build_State;
  host_build_target: string;
  host_build_error: string;

  app_return_flags: App_Return_Flags;
  app_return_data: union {
    load_app: string;
    build_app: string;
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
    Build_And_Load_App :: 1 << 4; // app has requested that the host build an app DLL, then load it. app sets build_app to the source file.
}

Quit_Ctx :: struct {
  keep_window_device_and_sdl: bool;
}

Host_Runtime_Ptrs :: struct {
  window: *void;
  gfx_device: *void;
  #if OS == .MACOS {
    services: MacOS_Runtime_Services;
  }
}

MacOS_Runtime_Dimensions :: struct {
  x: s32;
  y: s32;
  width: s32;
  height: s32;
  success: bool;
}

MacOS_Runtime_Mouse_Position :: struct {
  x: int;
  y: int;
  success: bool;
}

MacOS_Runtime_Services :: struct {
  set_window_title:           *void;
  get_dimensions:             *void;
  get_mouse_pointer_position: *void;
  window_is_occluded:         *void;
  window_has_focus:           *void;
  take_quit_requested:        *void;
  set_custom_cursor_handling: *void;
  ensure_window_frontmost:    *void;
}

Init_Ctx :: struct {
  keep_window_device_and_sdl: bool;
  max_frames: int;
  runtime: Host_Runtime_Ptrs;
}

App_Return_Message :: struct {
  success: bool = true;
  error: string = "";
}
