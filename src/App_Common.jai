num_app_reloads: int = 0;
SAVE_AND_RESTORE_WINDOW_POS :: true;
CHECK_CONTEXT :: false;

//
// #program_export section
//
// NOTE: any functions added here should probably use push_remapped_context_without_stack_trace()
//

#program_export
on_host_message :: (message: Host_Message) -> App_Return_Message {
    push_remapped_context();
    return handle_host_message(message);
}

#program_export
get_globals :: () -> []Global_Entry {
    push_remapped_context();

    #if GLOBALS_RELOAD_PLUGIN_INCLUDED {
        G: [..]Global_Entry;
        #import "Reload_Common";
        get_all_globals(*G);
        return G;
    } else {
        return .[];
    }

    // @Leak
}

/////

#if SINGLE_BINARY {
    // no need to remap context when we're just a single executable
    push_remapped_context :: () #expand { }
} else {
    push_remapped_context :: () #expand {
        dll_context := remap_context();

        #if CHECK_CONTEXT {
            host_context := context;
            check_context(*host_context, host_context.context_info, "host context");
            check_context(dll_context,  dll_context.context_info,  "dll_context");
        }

        `push_context,defer_pop dll_context;
    }
}

dummy_unload :: () { } @on_unload
dummy_reload :: () { } @on_reload

handle_host_message :: (message: Host_Message) -> App_Return_Message {
    result: App_Return_Message;

    if message.type == {
        case .Unload;
            call_event_functions(.unload);
            // log("Game unloaded.", user_flags=1);
        case .Reload;
            // We get a pointer to the game memory before the code reload so we need
            // to assign it to what the game is using.
            num_app_reloads += 1;
            // log("Game reloaded (count=%)", num_app_reloads, user_flags=1);
            call_event_functions(.reload);
        case .Quit;
            host_quit(message.quit_ctx);
        case .Init;
            result.success = host_init(message.init_ctx);
        case .Update;
            app_update(message.update_ctx);
    }

    return result;
}

#if !RELEASE && OS == .WINDOWS {
	enable_d3d12_debug_layer :: () {
		#import "dxgi";
		#import "d3d12";
		using,only(HRESULT, uid) Windows :: #import "Windows";
        debug_interface: *ID3D12Debug1;
		SUCCEEDED :: inline (hr: HRESULT) -> bool { return hr >= 0; }
        if SUCCEEDED(D3D12GetDebugInterface(*uid(ID3D12Debug1_UUID), xx *debug_interface)) {
            ID3D12Debug1_EnableDebugLayer(debug_interface);
            ID3D12Debug1_SetEnableGPUBasedValidation(debug_interface, .TRUE);
            ID3D12Debug1_SetEnableSynchronizedCommandQueueValidation(debug_interface, .TRUE);
            //dxgi_factory_flags |= DXGI_CREATE_FACTORY_DEBUG;
        }
	}
}

#import "General_Utils";
#import "Basic";
#import "Host_App_Common";
#import "Math";
#import "Reload_Common";

#if !SINGLE_BINARY {
    #import "Remap_Context"(VERBOSE=false);
    #load "Program_Parameters_Common.jai";
}

#scope_file

check_context :: (ctx: *void, ti: *Type_Info_Struct, message: string = "") {
    push_context {
        thing_any:= Any.{ ti, ctx };
        log("check_context '%':\n%", message, FormatStruct.{value=thing_any});
    }
}
