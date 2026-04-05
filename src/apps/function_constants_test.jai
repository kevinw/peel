Test_Params :: struct {
    viewport_width: float;
    test_color: Vector3;
    time: float;
}

Function_Constants_Test_VS_Out :: struct {
    position: Vector4; @SV_Position
}

Constant_Params :: struct {
    use_alternate_color: bool = false;
    alt_color: enum u8 { BLUE; MAGENTA; WHITE; } = .MAGENTA;
} @function_constants

gpu_arena: Gpu_Arena;

left_constants: Constant_Params;
right_constants: Constant_Params = { use_alternate_color = true };
pipelines: [2]Gpu_Pipeline; // left and right
params_ring: Gpu_Frame_Ring(Test_Params);
color: Vector4 = .{1, 0, 0, 1};

frag :: (using input: struct { position: Vector4; @SV_Position uv: Vector2; }, using params: *Test_Params, using constants: Constant_Params) -> Vector4 @SV_Target {
    split_x := viewport_width * 0.5;

    // make it wavey
    split_x += sin((time * 2.2 + position.y / 40.0)) * 40 * (sin(time * 5 + 4 * position.y * 0.003));

    if use_alternate_color {
        if input.position.x < split_x discard();

        if alt_color == {
        case .MAGENTA; return {1, 0, 1, 1};
        case .WHITE;   return {1, 1, 1, 1};
        case .BLUE;    return {0, 0, 1, 1};
        }

        return .{0.12, 0.82, 0.24, 1.0};
    } else {
        if input.position.x >= split_x discard();
        return .{test_color.x, test_color.y, test_color.z, 1.0};
    }
} @fragment_shader

gpu_create_graphics_pipeline_with_function_constants :: (metal: []u8,
                                                         raster_desc: Gpu_Raster_Desc,
                                                         shader_meta: Shader_Meta,
                                                         vertex_constants: *MTLFunctionConstantValues = null,
                                                         fragment_constants: *MTLFunctionConstantValues = null) -> Gpu_Pipeline {
    auto_release_temp();
    library := new_scoped_library_or_return_0(metal, "vertex+fragment shader");
    vertex_function_name   := tprint("%_VertexMain", shader_meta.request_name);
    fragment_function_name := tprint("%_FragmentMain", shader_meta.request_name);
    return _internal_gpu_create_graphics_pipeline_with_names_and_constants(
        library, library, raster_desc, vertex_function_name, fragment_function_name, vertex_constants, fragment_constants);
}

do_ui :: () {
    using ImGui;
    base_flags: ColorEditFlags = .None;

    defer End();
    if !Begin("Function Constants Test") { return; }

    {
        PushPopFont(fonts.main, 15);
        TextWrapped("A simple fragment shader uses function constants to know which color to draw.");
    }

    Separator();

    Text("Uniform Color: "); SameLine();
    if ColorEdit4("Color##1", xx *color, .NoInputs | .NoLabel | base_flags) {
        // log("Color changed: %", color);
    }

    Text("Function Constant Enum:");
    if inspect("alt color", *right_constants.alt_color) {
        log("alt color changed: %", right_constants.alt_color);
        rebuild_pipelines();
    }
} @on_ui

shader :: #run get_transpiled_shader(.METAL, fullscreen_tri_vert, frag);
raster_desc : Gpu_Raster_Desc : .{
    cull = .NONE,
    color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
};

on_dll_init :: () {
    gpu_arena = gpu_make_arena(64 * 1024, label = "function constants test arena");
    params_ring = sgpu_make_frame_ring(*gpu_arena, Test_Params);
    rebuild_pipelines();
} @on_dll_init

rebuild_pipelines :: () {
    // default_constants :: #insert #run make_constants_code_string(shader.meta);

    gpu_queue_wait_idle(gpu_get_queue(.MAIN, 0)); // once we have deferred deletion, we can remove this

    gpu_delete(*pipelines[0]);
    gpu_delete(*pipelines[1]);

    left_vals   := scoped_function_constant_values(*left_constants);
    right_vals  := scoped_function_constant_values(*right_constants);
    pipelines[0] = gpu_create_graphics_pipeline_with_function_constants(cast([]u8)shader.source, raster_desc, shader.meta, null, left_vals);
    pipelines[1] = gpu_create_graphics_pipeline_with_function_constants(cast([]u8)shader.source, raster_desc, shader.meta, null, right_vals);

    gpu_commit_residency();
}

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    if !swapchain_image return;

    _, _, win_w, _, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if !dims_ok || win_w == 0 return;

    params := sgpu_frame_ring_slot(*params_ring);
    params.cpu.* = .{
        viewport_width = cast(float) win_w,
        test_color = color.xyz,
        time = cast(float)time,
    };

    if !ImGui.GetIO().WantCaptureMouse && input_pressed(.MOUSE_BUTTON_LEFT) {
        cycle_alt_color();
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    _, cmd_buff := gpu_start_command_recording(main_queue);

    gpu_begin_scoped_render_pass(cmd_buff, .{
        color_targets = .[
            .{
                view = swapchain_image,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color._float = .[0.03, 0.03, 0.05, 1.0],
            }
        ],
    });

    gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .ALWAYS, depth_mode = .NONE});

    for pipelines {
        gpu_set_pipeline(cmd_buff, it);
        gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);
    }

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

// TODO: this metal specific stuff should go into GPU_Tools, or be subsumed by sgpu? not sure

scoped_function_constant_values :: (constants: *$T) -> *MTLFunctionConstantValues #expand {
    vals := build_function_constant_values(constants);
    `defer if vals release(vals);
    return vals;
}

build_function_constant_values :: (constants: *$T) -> *MTLFunctionConstantValues {
    values := objc_new(MTLFunctionConstantValues);
    assert(values != null, "Failed to allocate MTLFunctionConstantValues.");

    ti_struct := type_info(T);
    for ti_struct.members {
        member, offset_in_bytes := get_field(ti_struct, it.name);
        if offset_in_bytes < 0 {
            log_error("build_function_constant_values: member '%s' has negative offset_in_bytes: %", it.name, offset_in_bytes);
            continue;
        }
        metal_data_type := to_mtl_data_type(member.type);
        field_ptr := (cast(*void)constants) + offset_in_bytes;
        MTLFunctionConstantValues.setConstantValue(values, cast(*void) field_ptr, metal_data_type, cast(NSUInteger)it_index);
    }

    return values;
}

to_mtl_data_type :: (member_ti: *Type_Info) -> MTLDataType {
    if member_ti.type == {
        case .BOOL;
            return .Bool;
        case .STRUCT;
            struct_name := member_ti.(*Type_Info_Struct).name; // TODO: don't string match for Vector types
            if struct_name == {
            case "Vector2"; return .Float2;
            case "Vector3"; return .Float3;
            case "Vector4"; return .Float4;
            case;
                assert(false, "TODO: implement more general build_function_constant_values for struct '%'", struct_name);
            }
        case .ENUM;
            // map enums to integer types; the transpiler's SPIRV path doesn't actually emit textual enums.
            return to_mtl_data_type(member_ti.(*Type_Info_Enum).internal_type);
        case .INTEGER;
            signed := member_ti.(*Type_Info_Integer).signed;
            if signed {
                if member_ti.runtime_size == {
                case 1; return .Char;
                case 2; return .Short;
                case 4; return .Int;
                case 8; return .Long;
                case; assert(false, "TODO: implement build_function_constant_values for signed integer size %", member_ti.runtime_size);
                }
            } else {
                if member_ti.runtime_size == {
                case 1; return .UChar;
                case 2; return .UShort;
                case 4; return .UInt;
                case 8; return .ULong;
                case; assert(false, "TODO: implement build_function_constant_values for unsigned integer size %", member_ti.runtime_size);
                }
            }

        case;
            assert(false,"TODO: implement build_function_constant_values for type %", member_ti.type);
    }

    assert(false);
    return .Int;
}

#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Jai-Shader-Transpiler/modules/ShaderLib";
#import "Math";
#if OS == .MACOS {
#import "Objective_C";
}
Input :: #import "Input";

cycle_alt_color :: () {
    using right_constants;
    if alt_color == .WHITE {
        alt_color = .BLUE;
    } else {
        alt_color += 1;
    }
    rebuild_pipelines();
}
