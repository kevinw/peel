num_app_reloads: int = 0;
SAVE_AND_RESTORE_WINDOW_POS :: true;

USE_GLOBAL_DLL_CONTEXT :: true;
CHECK_CONTEXT :: false;
#if USE_GLOBAL_DLL_CONTEXT {
    bare_context: #Context;
}

////

//
// #program_export section
//
// NOTE: any functions added here should probably use push_remapped_context_without_stack_trace()
//

#program_export
on_host_message :: (message: Host_Message) -> App_Return_Message {
    push_remapped_context_without_stack_trace();
    return handle_host_message(message);
}

#program_export
get_globals :: () -> []Global_Entry {
    push_remapped_context_without_stack_trace();

    G: [..]Global_Entry;
    #import "Reload_Common";
    get_all_globals(*G);
    return G;

    // @Leak
}

/////

#if SINGLE_BINARY {
    // no need to remap context when we're just a single executable
    push_remapped_context_without_stack_trace :: () #expand { }
} else {
    push_remapped_context_without_stack_trace :: () #expand {
        host_context := context;
        #if USE_GLOBAL_DLL_CONTEXT {
            dll_context := *bare_context;
        } else {
            dll_context := remap_context();
        }
        #if CHECK_CONTEXT {
            check_context(*host_context, host_context.context_info, "host context");
            check_context(dll_context,  dll_context.context_info,  "dll_context");
        }

        // With Memory_Debugger enabled, I was seeing crashes when crossing the DLL boundary with a non-c_call function.
        // TODO: investigate/report a bug maybe?
        // The fix here is to cut off the stack trace at the DLL boundary. For now this is fine, since the host is a single main function.
        #if MEMORY_DEBUGGER dll_context.stack_trace = null;

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
    #import "Remap_Context"(VERBOSE=true);
    #load "Program_Parameters_Common.jai";
}

#scope_file

check_context :: (ctx: *void, ti: *Type_Info_Struct, message: string = "") {
    push_context {
        thing_any:= Any.{ ti, ctx };
        log("check_context '%':\n%", message, FormatStruct.{value=thing_any});
    }
}
