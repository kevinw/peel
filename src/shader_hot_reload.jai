#import "Basic";
#import "Compiler";
#import "sgpu";
#import "Thread";
String :: #import "String";
Process :: #import "Process";
Hash :: #import "Hash";
JTS :: #import "Jai-Shader-Transpiler";
ImGui :: #import "ImGui";
#if OS == .MACOS {
#import "Objective_C";
#import "Metal";
#import "Objective_C_Tools";
}

SRM :: #import,file "../modules/Jai-Shader-Transpiler/modules/shader_reload_manifest.jai";

path_to_shader_module :: #run JTS.compute_path_to_shader_bucket_module(get_current_workspace());

shader_reload_ctx: *Shader_Hot_Reload; // the one global implicit shader reload context

Shader_Hot_Reload_Last_Result :: enum {
    NONE;
    BUILD_QUEUED;
    BUILD_RUNNING;
    BUILD_FAILED;
    SWAP_PARTIAL;
    SWAP_OK;
}

Shader_Hot_Reload_Base :: struct {
    entry_id: string;
    pipeline: *Gpu_Pipeline;
}

Shader_Hot_Reload_Function_Constant_Type :: enum {
    BOOL;
    U8;
    S8;
    U16;
    S16;
    U32;
    S32;
    U64;
    S64;
    FLOAT;
    FLOAT2;
    FLOAT3;
    FLOAT4;
}

Shader_Hot_Reload_Function_Constant_Info :: struct {
    name: string;
    type: Shader_Hot_Reload_Function_Constant_Type;
    offset: s64;
}

Shader_Hot_Reload_Target_Base :: struct {
    using #as base: Shader_Hot_Reload_Base;
    default_function_constants_bytes: []u8;
    function_constant_info: []Shader_Hot_Reload_Function_Constant_Info;
}

Shader_Hot_Reload_Mesh_Desc :: struct {
    raster_desc: Gpu_Raster_Desc;
    task_threads: [3]u32;
    mesh_threads: [3]u32;
    payload_memory_length: u32;
    max_total_threadgroups_per_mesh_grid: u32;
}

Shader_Hot_Reload_Graphics_Target :: struct {
    using #as target_base: Shader_Hot_Reload_Target_Base;
    raster_desc: Gpu_Raster_Desc;
}

Shader_Hot_Reload_Compute_Target :: struct {
    using #as base: Shader_Hot_Reload_Base;
}

Shader_Hot_Reload_Mesh_Target :: struct {
    using #as target_base: Shader_Hot_Reload_Target_Base;
    desc: Shader_Hot_Reload_Mesh_Desc;
}

Shader_Hot_Reload :: struct {
    enabled: bool;
    use_background_thread: bool;
    log_prefix: string;
    watcher: SRM.Shader_Reload_Watcher;
    graphics_targets: [..] Shader_Hot_Reload_Graphics_Target;
    compute_targets: [..] Shader_Hot_Reload_Compute_Target;
    mesh_targets: [..] Shader_Hot_Reload_Mesh_Target;
    last_event_frame: s64;
    last_result: Shader_Hot_Reload_Last_Result;
    worker_started: bool;
    worker_thread: Thread;
    worker_wake: Semaphore;
    worker_mutex: Mutex;
    worker_should_exit: bool;
    worker_has_pending: bool;
    worker_pending_ids_csv: string;
    worker_build_in_flight: bool;
    worker_has_completed: bool;
    worker_completed_ok: bool;
    worker_completed_ids_csv: string;
    worker_completed_error_message: string;
    last_error_message: string;
    show_error_window: bool;
    reload_generation: u64;
}

take_background_completion :: (using reload: *Shader_Hot_Reload, completed_ok: *bool, completed_ids_csv: *string, completed_error: *string) -> bool {
    if !worker_started return false;
    lock(*worker_mutex);
    defer unlock(*worker_mutex);

    if !worker_has_completed return false;
    worker_has_completed = false;
    completed_ok.* = worker_completed_ok;
    completed_ids_csv.* = worker_completed_ids_csv;
    completed_error.* = worker_completed_error_message;
    worker_completed_ids_csv = "";
    worker_completed_error_message = "";
    return true;
}

proc_name_from_code_compile_time :: (code: Code) -> string {
    root, _ := compiler_get_nodes(code);
    if !root || root.kind != .IDENT return "";
    return (cast(*Code_Ident) root).name;
}

shader_hot_reload_current_ctx :: () -> *Shader_Hot_Reload {
    assert(shader_reload_ctx != null, "shader_reload_ctx is null. Initialize SHR.shader_reload_ctx before using shader hot reload.");
    return shader_reload_ctx;
}

#load "./shader_function_constants.jai";
#load "./shader_api.jai";
#load "./shader_reload_ui.jai";
#load "./shader_reload_runtime.jai";

