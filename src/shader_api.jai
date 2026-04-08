Shader_Function_Constant_Variant :: struct {
    key_hash: u64;
    constants_bytes: []u8;
    pipeline: Gpu_Pipeline;
}

Shader_Base :: struct {
    pipeline: Gpu_Pipeline;
    function_constant_variants: [..] Shader_Function_Constant_Variant;
    function_constant_variant_generation: u64;
}

Shader :: struct(vert: $V, frag: $F, raster: Gpu_Raster_Desc) {
    using #as base: Shader_Base;

    Vertex_Function :: vert;
    Fragment_Function :: frag;

    raster_desc :: raster;
}

Compute_Shader :: struct(kernel: $K) {
    using #as base: Shader_Base;

    Kernel_Function :: kernel;
}

Mesh_Shader :: struct(mesh: $M, frag: $F, desc: Gpu_Mesh_Pipeline_Desc, task: $T = null) {
    using #as base: Shader_Base;

    Mesh_Function :: mesh;
    Fragment_Function :: frag;
    Task_Function :: task;
    mesh_desc :: desc;
}

shader_hot_reload_pick_function_constants_type_expr :: (required_note: string, loc: Source_Code_Location, procs: ..Code) -> string #compile_time {
    selected: string;
    for procs {
        if it == null continue;
        type_expr := shader_hot_reload_function_constants_type_expr(it, required_note, loc);
        if type_expr.count == 0 continue;
        if selected.count == 0 {
            selected = type_expr;
            continue;
        }
        if type_expr != selected {
            compiler_report(tprint("Function-constant struct mismatch between shader stages: '%' vs '%'.", selected, type_expr), loc=loc);
            return "";
        }
    }
    return selected;
}

init :: (using shader: *Shader, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        vertex_name   :: #procedure_name(Vertex_Function);
        fragment_name :: #procedure_name(Fragment_Function);
        source_expr, meta_expr, constants_expr, ok := JTS.get_transpiled2_named_exprs_with_constants(vertex_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload graphics helper requires direct vertex/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }
        function_constants_type_expr := shader_hot_reload_pick_function_constants_type_expr("", loc, Vertex_Function, Fragment_Function);
        if function_constants_type_expr.count != 0 {
            default_constants_expr := JTS.default_pair_function_constants_expr_from_procs(Vertex_Function, Fragment_Function, loc);
            return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
default_constants := %;
new_pipeline := create_graphics_pipeline_with_function_constants(cast([]u8) shader_source, shader_meta, raster_desc, *default_constants);
assert(new_pipeline != 0, "Graphics pipeline creation with function constants failed for '%', '%'.");
shader.pipeline = new_pipeline;
shader_hot_reload_register_graphics_pipeline_with_function_constants(shader_meta.entry_id, *shader.pipeline, raster_desc, *default_constants);
shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) shader);
gpu_commit_residency();
return true;
END, path_to_shader_module, source_expr, meta_expr, default_constants_expr, vertex_name, fragment_name);
        }
        return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
assert(shader_meta.entry_id.count > 0, "Missing shader hot-reload entry id for graphics shaders '%', '%'.");
ok := shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id(shader_meta.entry_id, *shader.pipeline, cast([]u8) shader_source, raster_desc);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) shader);
return ok;
END, path_to_shader_module, source_expr, meta_expr, vertex_name, fragment_name, vertex_name, fragment_name);
    };
}

init :: (using shader: *Shader, constants: $T, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        vertex_name   :: #procedure_name(Vertex_Function);
        fragment_name :: #procedure_name(Fragment_Function);
        source_expr, meta_expr, ok := JTS.get_transpiled2_named_exprs(vertex_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload graphics helper requires direct vertex/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }
        return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
new_pipeline := create_graphics_pipeline_with_function_constants(cast([]u8) shader_source, shader_meta, raster_desc, *constants);
assert(new_pipeline != 0, "Graphics pipeline creation with function constants failed for '%', '%'.");
shader.pipeline = new_pipeline;
shader_hot_reload_register_graphics_pipeline_with_function_constants(shader_meta.entry_id, *shader.pipeline, raster_desc, *constants);
shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) shader);
gpu_commit_residency();
return true;
END, path_to_shader_module, source_expr, meta_expr, vertex_name, fragment_name);
    };
}

init :: (using compute_shader: *Compute_Shader, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        compute_name :: #run #procedure_name(Kernel_Function);
        source_expr, meta_expr, ok := JTS.get_transpiled_compute_named_exprs(compute_name, loc);
        if !ok {
            compiler_report("Shader hot reload compute helper requires a direct compute procedure identifier.", loc=loc);
            return "return false;";
        }
        return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
assert(shader_meta.entry_id.count > 0, "Missing shader hot-reload entry id for compute shader '%'.");
ok := shader_hot_reload_create_and_register_compute_pipeline_with_entry_id(shader_meta.entry_id, *pipeline, cast([]u8) shader_source);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) compute_shader);
return ok;
END, path_to_shader_module, source_expr, meta_expr, compute_name, compute_name);
    };
}

init :: (using mesh_shader: *Mesh_Shader, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        mesh_name :: #procedure_name(Mesh_Function);
        fragment_name :: #procedure_name(Fragment_Function);
        function_constants_type_expr := shader_hot_reload_pick_function_constants_type_expr("", loc, Task_Function, Mesh_Function, Fragment_Function);

        if Task_Function != null {
            task_name :: #procedure_name(Task_Function);
            bundle_expr, meta_expr, constants_expr, ok := JTS.get_transpiled_task_mesh_pipeline_named_exprs_with_constants(task_name, mesh_name, fragment_name, loc);
            if !ok {
                compiler_report("Shader hot reload mesh helper requires direct task/mesh/fragment procedure identifiers.", loc=loc);
                return "return false;";
            }
            if function_constants_type_expr.count != 0 {
                default_constants_expr := JTS.default_mesh_function_constants_expr_from_procs(Task_Function, Mesh_Function, Fragment_Function, loc);
                return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
default_constants := %;
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for task+mesh pipeline shaders '%', '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc, *default_constants);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, default_constants_expr, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name);
            }
            return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for task+mesh pipeline shaders '%', '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name);
        }

        bundle_expr, meta_expr, constants_expr, ok := JTS.get_transpiled_mesh_pipeline_named_exprs_with_constants(mesh_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload mesh helper requires direct mesh/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }
        if function_constants_type_expr.count != 0 {
            default_constants_expr := JTS.default_mesh_function_constants_expr_from_procs(Mesh_Function, Fragment_Function, loc);
            return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
default_constants := %;
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for mesh pipeline shaders '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc, *default_constants);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, default_constants_expr, mesh_name, fragment_name, mesh_name, fragment_name, mesh_name, fragment_name);
        }
        return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for mesh pipeline shaders '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, mesh_name, fragment_name, mesh_name, fragment_name, mesh_name, fragment_name);
    };
}

init :: (using mesh_shader: *Mesh_Shader, constants: $C, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        mesh_name :: #procedure_name(Mesh_Function);
        fragment_name :: #procedure_name(Fragment_Function);

        if Task_Function != null {
            task_name :: #procedure_name(Task_Function);
            bundle_expr, meta_expr, ok := JTS.get_transpiled_task_mesh_pipeline_named_exprs(task_name, mesh_name, fragment_name, loc);
            if !ok {
                compiler_report("Shader hot reload mesh helper requires direct task/mesh/fragment procedure identifiers.", loc=loc);
                return "return false;";
            }
            return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for task+mesh pipeline shaders '%', '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc, *constants);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name);
        }

        bundle_expr, meta_expr, ok := JTS.get_transpiled_mesh_pipeline_named_exprs(mesh_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload mesh helper requires direct mesh/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }
        return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for mesh pipeline shaders '%', '%'.");
ok := shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, *mesh_shader.pipeline, shader_bundle, mesh_desc, *constants);
if ok shader_hot_reload_reset_function_constant_variants(cast(*Shader_Base) mesh_shader);
return ok;
END, path_to_shader_module, bundle_expr, meta_expr, mesh_name, fragment_name, mesh_name, fragment_name, mesh_name, fragment_name);
    };
}

pipeline :: (using shader: *Shader) -> Gpu_Pipeline {
    return shader.pipeline;
}

pipeline :: (using shader: *Shader, constants: $T, loc: Source_Code_Location = #caller_location) -> Gpu_Pipeline #expand {
    #insert #run,stallable -> string {
        vertex_name :: #procedure_name(Vertex_Function);
        fragment_name :: #procedure_name(Fragment_Function);
        source_expr, meta_expr, ok := JTS.get_transpiled2_named_exprs(vertex_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload graphics helper requires direct vertex/fragment procedure identifiers.", loc=loc);
            return "return 0;";
        }

        return tprint(#string END
{
    G :: #import,file "%";
    shader_source, shader_meta := %, %;
    return shader_hot_reload_get_or_create_graphics_pipeline_variant(cast(*Shader_Base) shader, cast([]u8) shader_source, shader_meta, raster_desc, *constants);
}
END, path_to_shader_module, source_expr, meta_expr);
    };
}

pipeline :: (using mesh_shader: *Mesh_Shader) -> Gpu_Pipeline {
    return mesh_shader.pipeline;
}

pipeline :: (using mesh_shader: *Mesh_Shader, constants: $Constants_Struct, loc: Source_Code_Location = #caller_location) -> Gpu_Pipeline #expand {
    #insert #run,stallable -> string {
        mesh_name :: #procedure_name(Mesh_Function);
        fragment_name :: #procedure_name(Fragment_Function);

        if Task_Function != null {
            task_name :: #procedure_name(Task_Function);
            bundle_expr, meta_expr, ok := JTS.get_transpiled_task_mesh_pipeline_named_exprs(task_name, mesh_name, fragment_name, loc);
            if !ok {
                compiler_report("Shader hot reload mesh helper requires direct task/mesh/fragment procedure identifiers.", loc=loc);
                return "return 0;";
            }
            return tprint(#string END
{
    G :: #import,file "%";
    lookup_bundle := %;
    shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
        task_source = lookup_bundle.task_source,
        mesh_source = lookup_bundle.mesh_source,
        pixel_source = lookup_bundle.pixel_source,
        payload_size_bytes = lookup_bundle.payload_size_bytes,
        payload_memory_length = lookup_bundle.payload_memory_length,
        meta = %,
    };
    return shader_hot_reload_get_or_create_mesh_pipeline_variant(cast(*Shader_Base) mesh_shader, shader_bundle, mesh_desc, *constants);
}
END, path_to_shader_module, bundle_expr, meta_expr);
        }

        bundle_expr, meta_expr, ok := JTS.get_transpiled_mesh_pipeline_named_exprs(mesh_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload mesh helper requires direct mesh/fragment procedure identifiers.", loc=loc);
            return "return 0;";
        }
        return tprint(#string END
{
    G :: #import,file "%";
    lookup_bundle := %;
    shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
        task_source = lookup_bundle.task_source,
        mesh_source = lookup_bundle.mesh_source,
        pixel_source = lookup_bundle.pixel_source,
        payload_size_bytes = lookup_bundle.payload_size_bytes,
        payload_memory_length = lookup_bundle.payload_memory_length,
        meta = %,
    };
    return shader_hot_reload_get_or_create_mesh_pipeline_variant(cast(*Shader_Base) mesh_shader, shader_bundle, mesh_desc, *constants);
}
END, path_to_shader_module, bundle_expr, meta_expr);
    };
}

proc_name_from_caller_arg :: (call: Code, arg_index: s64) -> string {
    root, _ := compiler_get_nodes(call);
    if !root || root.kind != .PROCEDURE_CALL return "";
    pc := cast(*Code_Procedure_Call) root;
    if arg_index < 0 || arg_index >= pc.arguments_unsorted.count return "";
    arg := pc.arguments_unsorted[arg_index].expression;
    if !arg || arg.kind != .IDENT return "";
    return (cast(*Code_Ident) arg).name;
}

shader_hot_reload_code_struct_has_note :: (st: *Code_Struct, note_name: string) -> bool #compile_time {
    if !st || note_name.count == 0 return false;
    for st.notes if it.text == note_name return true;
    return false;
}

shader_hot_reload_decl_has_note :: (decl: *Code_Declaration, note_name: string) -> bool #compile_time {
    if !decl || note_name.count == 0 return false;
    for decl.notes if it.text == note_name return true;
    return false;
}

shader_hot_reload_resolve_struct_node_from_type_expr :: (node: *Code_Node, depth: s64 = 0) -> *Code_Struct #compile_time {
    if !node || depth > 8 return null;
    if node.kind == .STRUCT return cast(*Code_Struct) node;
    if node.kind == .DECLARATION {
        decl := cast(*Code_Declaration) node;
        if decl.expression return shader_hot_reload_resolve_struct_node_from_type_expr(decl.expression, depth + 1);
        return null;
    }
    if node.kind == .IDENT {
        ident := cast(*Code_Ident) node;
        if ident.resolved_declaration return shader_hot_reload_resolve_struct_node_from_type_expr(cast(*Code_Node) ident.resolved_declaration, depth + 1);
        return null;
    }
    if node.kind == .TYPE_INSTANTIATION {
        inst := cast(*Code_Type_Instantiation) node;
        if inst.type_valued_expression return shader_hot_reload_resolve_struct_node_from_type_expr(inst.type_valued_expression, depth + 1);
        return null;
    }
    return null;
}

shader_hot_reload_function_constants_type_expr :: (proc: Code, required_note: string, loc: Source_Code_Location) -> string #compile_time {
    info := JTS.discover_procedure_info(proc, required_note, loc);
    if !info.proc_header return "";
    for info.proc_header.arguments {
        if !it || !it.type_inst || !it.type_inst.result || it.type_inst.result.type != .STRUCT continue;
        struct_node := shader_hot_reload_resolve_struct_node_from_type_expr(it.type_inst.type_valued_expression);
        type_decl: *Code_Declaration;
        if it.type_inst.type_valued_expression && it.type_inst.type_valued_expression.kind == .IDENT {
            ident := cast(*Code_Ident) it.type_inst.type_valued_expression;
            type_decl = ident.resolved_declaration;
        }
        has_note := shader_hot_reload_code_struct_has_note(struct_node, "function_constants");
        if !has_note && type_decl has_note = shader_hot_reload_decl_has_note(type_decl, "function_constants");
        if !has_note continue;
        return JTS.expression_to_source_string(it.type_inst.type_valued_expression);
    }
    return "";
}

gfx_pipeline :: (pipeline: *Gpu_Pipeline, source: []u8, raster_desc: Gpu_Raster_Desc, target: JTS.Transpiled_Target, $vertex_shader: $VERTEX_SHADER, $fragment_shader: $FRAGMENT_SHADER, call: Code = #caller_code) -> bool #expand {
    return shader_hot_reload_create_and_register_graphics_pipeline(pipeline, source, raster_desc, target, vertex_shader, fragment_shader, call);
}

gfx_pipeline :: (pipeline: *Gpu_Pipeline, raster_desc: Gpu_Raster_Desc, $vert_2: $VERTEX_SHADER, $frag_2: $FRAGMENT_SHADER, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        vertex_name   := proc_name_from_caller_arg(call, 2);
        fragment_name := proc_name_from_caller_arg(call, 3);
        source_expr, meta_expr, ok := JTS.get_transpiled2_named_exprs(vertex_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload graphics helper requires direct vertex/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }

        return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
assert(shader_source.count > 0, "Transpilation failed for graphics shaders '%', '%'.");
assert(shader_meta.entry_id.count > 0, "Missing shader hot-reload entry id for graphics shaders '%', '%'.");
return shader_hot_reload_create_and_register_graphics_pipeline_with_entry_id(shader_meta.entry_id, pipeline, cast([]u8) shader_source, raster_desc);
END, path_to_shader_module, source_expr, meta_expr, vertex_name, fragment_name, vertex_name, fragment_name);
    };
}

compute_pipeline :: (pipeline: *Gpu_Pipeline, source: []u8, target: JTS.Transpiled_Target, $compute_shader: $COMPUTE_SHADER, call: Code = #caller_code) -> bool #expand {
    return shader_hot_reload_create_and_register_compute_pipeline(pipeline, source, target, compute_shader, call);
}

compute_pipeline :: (pipeline: *Gpu_Pipeline, $compute_shader: $COMPUTE_SHADER, call: Code = #caller_code, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        compute_name := proc_name_from_caller_arg(call, 1);
        source_expr, meta_expr, ok := JTS.get_transpiled_compute_named_exprs(compute_name, loc);
        if !ok {
            compiler_report("Shader hot reload compute helper requires a direct compute procedure identifier.", loc=loc);
            return "return false;";
        }

        return tprint(#string END
G :: #import,file "%";
shader_source, shader_meta := %, %;
assert(shader_source.count > 0, "Transpilation failed for compute shader '%'.");
assert(shader_meta.entry_id.count > 0, "Missing shader hot-reload entry id for compute shader '%'.");
return shader_hot_reload_create_and_register_compute_pipeline_with_entry_id(shader_meta.entry_id, pipeline, cast([]u8) shader_source);
END, path_to_shader_module, source_expr, meta_expr, compute_name, compute_name);
    };
}

mesh_pipeline :: (pipeline: *Gpu_Pipeline, desc: Gpu_Mesh_Pipeline_Desc, shader: JTS.Transpiled_Mesh_Pipeline) -> bool {
    assert(shader.meta.entry_id.count > 0, "Missing shader hot-reload entry id for mesh pipeline.");
    return shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader.meta.entry_id, pipeline, shader, desc);
}

mesh_pipeline :: (pipeline: *Gpu_Pipeline, desc: Gpu_Mesh_Pipeline_Desc, shader_a: Code, shader_b: Code, shader_c: Code = null, loc: Source_Code_Location = #caller_location) -> bool #expand {
    #insert #run,stallable -> string {
        shader_a_name := proc_name_from_code_compile_time(shader_a);
        shader_b_name := proc_name_from_code_compile_time(shader_b);
        shader_c_name := proc_name_from_code_compile_time(shader_c);

        if shader_c_name.count != 0 {
            task_name := shader_a_name;
            mesh_name := shader_b_name;
            fragment_name := shader_c_name;
            bundle_expr, meta_expr, ok := JTS.get_transpiled_task_mesh_pipeline_named_exprs(task_name, mesh_name, fragment_name, loc);
            if !ok {
                compiler_report("Shader hot reload mesh helper requires direct task/mesh/fragment procedure identifiers.", loc=loc);
                return "return false;";
            }
            return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for task+mesh pipeline shaders '%', '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for task+mesh pipeline shaders '%', '%', '%'.");
return shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, pipeline, shader_bundle, desc);
END, path_to_shader_module, bundle_expr, meta_expr, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name, task_name, mesh_name, fragment_name);
        }

        mesh_name := shader_a_name;
        fragment_name := shader_b_name;
        bundle_expr, meta_expr, ok := JTS.get_transpiled_mesh_pipeline_named_exprs(mesh_name, fragment_name, loc);
        if !ok {
            compiler_report("Shader hot reload mesh helper requires direct mesh/fragment procedure identifiers.", loc=loc);
            return "return false;";
        }
        return tprint(#string END
G :: #import,file "%";
lookup_bundle := %;
shader_bundle := JTS.Transpiled_Mesh_Pipeline.{
    task_source = lookup_bundle.task_source,
    mesh_source = lookup_bundle.mesh_source,
    pixel_source = lookup_bundle.pixel_source,
    payload_size_bytes = lookup_bundle.payload_size_bytes,
    payload_memory_length = lookup_bundle.payload_memory_length,
    meta = %,
};
assert(shader_bundle.mesh_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.pixel_source.count > 0, "Transpilation failed for mesh pipeline shaders '%', '%'.");
assert(shader_bundle.meta.entry_id.count > 0, "Missing shader hot-reload entry id for mesh pipeline shaders '%', '%'.");
return shader_hot_reload_create_and_register_mesh_pipeline_with_entry_id(shader_bundle.meta.entry_id, pipeline, shader_bundle, desc);
END, path_to_shader_module, bundle_expr, meta_expr, mesh_name, fragment_name, mesh_name, fragment_name, mesh_name, fragment_name);
    };
}
