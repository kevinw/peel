
#load "../SGPU_App_Common.jai";
#import "Jai-Shader-Transpiler";
#import "Jai-Shader-Transpiler/modules/ShaderFuncs";
#import "Math";
#import "Objective_C";

Function_Constants_Test_Params :: struct {
    viewport_width: float;
    test_color: Vector3;
}

Function_Constants_Test_VS_Out :: struct {
    position: Vector4; @SV_Position
}

use_alternate_color: bool = false; @function_constant

vert :: (using in: struct { vertex_id: u32; @Vertex_ID }) -> Function_Constants_Test_VS_Out @vertex_shader {
    positions : [3] Vector2 = .[
        .{-1.0, -1.0},
        .{ 3.0, -1.0},
        .{-1.0,  3.0},
    ];

    p := positions[vertex_id];
    return .{
        position = .{p.x, p.y, 0.0, 1.0},
    };
} @vertex_shader

frag :: (using input: Function_Constants_Test_VS_Out, using params: *Function_Constants_Test_Params) -> Vector4 @SV_Target {
    split_x := viewport_width * 0.5;

    if use_alternate_color {
        if input.position.x < split_x discard();
        return .{0.12, 0.82, 0.24, 1.0};
    }

    if input.position.x >= split_x discard();
    return .{test_color.x, test_color.y, test_color.z, 1.0};
} @fragment_shader

graphics_pipeline_default: Gpu_Pipeline;
graphics_pipeline_alternate: Gpu_Pipeline;
gpu_arena: Gpu_Arena;
params_ring: Gpu_Frame_Ring(Function_Constants_Test_Params);
params: Gpu_Buffer(Function_Constants_Test_Params);

color: Vector4 = .{1, 0, 0, 1};

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
    if ColorEdit4("Color##1", xx *color, .NoInputs | .NoLabel | base_flags) {
        log("Color changed: %", color);
    }
} @on_ui

on_dll_init :: () {
    shader :: #run get_transpiled_shader(.METAL, vert, frag);
    log("SHADER META:\n%\n", FormatStruct.{value=shader.meta});
    raster_desc: Gpu_Raster_Desc = .{
        cull = .NONE,
        color_targets = .[
            .{format = .B8G8R8A8_UNORM},
        ],
    };

    gpu_arena = gpu_make_arena(64 * 1024, label = "function constants test arena");
    params_ring = sgpu_make_frame_ring(*gpu_arena, Function_Constants_Test_Params);
    params = sgpu_frame_ring_slot(*params_ring);
    params.cpu.* = .{};

    default_constants :: #insert #run make_constants_code_string(shader.meta);
    alternate_constants := default_constants;
    alternate_constants.use_alternate_color = true;

    default_values := scoped_function_constant_values(*default_constants);
    alternate_values := scoped_function_constant_values(*alternate_constants);

    graphics_pipeline_default   = gpu_create_graphics_pipeline_with_function_constants(cast([]u8)shader.source, raster_desc, shader.meta, null, default_values);
    graphics_pipeline_alternate = gpu_create_graphics_pipeline_with_function_constants(cast([]u8)shader.source, raster_desc, shader.meta, null, alternate_values);

    gpu_commit_residency();
} @on_dll_init

tick :: () {
    result, swapchain_image := app_swapchain_acquire();
    assert(result == .SUCCESS);
    if !swapchain_image return;

    _, _, win_w, _, dims_ok := get_dimensions(cast(Window_Type) window, true);
    if dims_ok && win_w > 0 {
        params = sgpu_frame_ring_slot(*params_ring);
        params.cpu.viewport_width = cast(float) win_w;
        params.cpu.test_color = .{color.x, color.y, color.z};
    }

    main_queue := gpu_get_queue(.MAIN, 0);
    result=, cmd_buff := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

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

    gpu_set_pipeline(cmd_buff, graphics_pipeline_default);
    draw_result := gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Default function-constants draw failed: %", draw_result));

    gpu_set_pipeline(cmd_buff, graphics_pipeline_alternate);
    draw_result = gpu_draw_instanced(cmd_buff, 0, params.gpu, 3, 1);
    assert(draw_result == .SUCCESS, tprint("Alternate function-constants draw failed: %", draw_result));

    submit_and_present_with_ui(cmd_buff);
} @on_tick

#scope_file

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
        member_ti := member.type;

        log("member.name: % %", member.name, offset_in_bytes);
        metal_data_type: MTLDataType;

        if member_ti.type == {
            case .BOOL;
                metal_data_type = .Bool;
            case .STRUCT;
                struct_name := member_ti.(*Type_Info_Struct).name; // TODO: don't string match for Vector types
                if struct_name == {
                case "Vector2"; metal_data_type = .Float2;
                case "Vector3"; metal_data_type = .Float3;
                case "Vector4"; metal_data_type = .Float4;
                case;
                    log_error("TODO: implement more general build_function_constant_values for struct '%'", struct_name);
                }
            case;
                log_error("TODO: implement build_function_constant_values for type %", member_ti.type);
                continue;
        }

        log("MTLFunctionConstantValues set member '%', byte offset %, index %", it.name, offset_in_bytes, it_index);

        field_ptr := (cast(*void)constants) + offset_in_bytes;
        MTLFunctionConstantValues.setConstantValue(values, cast(*void) field_ptr, metal_data_type, cast(NSUInteger)it_index);
    }

    return values;
}
