// Build and generate bindings for JoltC
GITHUB_REPO      :: "amerkoleci/joltc";
GITHUB_BRANCH    :: "main";
CMAKE_BUILD_TYPE :: "Release"; // TODO: Maybe build both and make it a module parameter whether to use the debug build or release build?

#run {
    set_build_options_dc(.{do_output = false});
    project: Project_Options;
    array_add(*project.extra_cmake_configure_args,
        "-DGENERATE_DEBUG_SYMBOLS=ON",
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
        "-DVERBOSE=ON",
    );
    init_from_github_clone(*project, repo=GITHUB_REPO, branch=GITHUB_BRANCH);
    #if OS == .MACOS {
        array_add(*project.platform_artifacts, "lib/libjoltc.dylib");
    } else #if OS == .WINDOWS {
        array_add(*project.platform_artifacts,     #run sprint("bin/%/joltc.dll", CMAKE_BUILD_TYPE));
        array_add(*project.extra_binaries_to_copy, #run sprint("lib/%/joltc.lib", CMAKE_BUILD_TYPE));
    } else #if OS == .LINUX {
        array_add(*project.platform_artifacts, "lib/libjoltc.so");
    } else {
        #assert false "TODO";
    }
    project.bindings_options_callback = (using opts: *Generate_Bindings_Options, paths: Build_Project_Paths) {
        array_add(*source_files, "joltc.h");
        array_add(*include_paths, tprint("%/include", paths.src));
        visitor = joltc_visitor;
        will_print_bindings = joltc_will_print_bindings;
        array_add(*strip_prefixes, "JPH_");
    };
    ok, result := build_and_generate_bindings(*project, .{
        cmake_build_type=CMAKE_BUILD_TYPE,
        verbose=false,
    });
    if !ok fail_and_exit("Failed to build and generate bindings");

    // Make Shape pointer types #as castable to their base class type. i.e., CylinderShape is a ConvexShape.
    //
    // TODO: JoltC does "typedef struct Shape Shape;" type erasure on the underlying C++ class hierarchy,
    // so what comes out of Bindings_Generator is a flat list of all the classes with no #as entries.
    // Maybe we could insert the `#as` in the bindings generator visitor function instead of doing text
    // replacement here.
    subtypes :: struct { class_name: string; base_class_name: string; }.[
        .{"PlaneShape",             "Shape"},
        .{"EmptyShape",             "Shape"},
        .{"MeshShape",              "Shape"},
        .{"HeightFieldShape",       "Shape"},

        .{"TaperedCapsuleShape",    "ConvexShape"},
        .{"TaperedCylinderShape",   "ConvexShape"},
        .{"ConvexShape",            "Shape"},
        .{"CapsuleShape",           "ConvexShape"},
        .{"CylinderShape",          "ConvexShape"},
        .{"BoxShape",               "ConvexShape"},
        .{"SphereShape",            "ConvexShape"},
        .{"TriangleShape",          "ConvexShape"},
        .{"ConvexHullShape",        "ConvexShape"},

        .{"StaticCompoundShape",    "CompoundShape"},
        .{"MutableCompoundShape",   "CompoundShape"},
        .{"CompoundShape",          "Shape"},

        .{"DecoratedShape",          "Shape"},
        .{"RotatedTranslatedShape",  "DecoratedShape"},
        .{"ScaledShape",             "DecoratedShape"},
        .{"OffsetCenterOfMassShape", "DecoratedShape"},

        .{"CharacterVirtual",       "CharacterBase"},
        .{"Character",              "CharacterBase"},
    ];

    // Insert `#as _base: ParentClass`
    text_replacements: [..]Text_Replacement;
    for subtypes array_add(*text_replacements, .{
        tprint("% :: struct {}", it.class_name),
        tprint("% :: struct { #as _base: %; }", it.class_name, it.base_class_name),
    });

    // @Perf Slow, bad
    if !replace_texts_in_file(result.generated_bindings_filename, ..text_replacements) {
        fail_and_exit("ERROR: expected exactly one replacement for each subtype string hack");
    }

    log("OK. Generated bindings in %", result.generated_bindings_filename);
}

#scope_file

prim_type_names :: string.["RVec3", "Quat", "Vec3"];
prim_funcs: [..]struct { func: *Function; last_prim_args: s64; };

joltc_visit_function :: (func: *Function) {
    if !String.contains(func.name, "Set")
        return;

    type := func.type.type_of_function;
    last_prim_args := 0;
    for type.arguments {
        arg_type := find_underlying_type(it.type);
        if arg_type && arg_type.pointer_to {
            typedef_ := arg_type.pointer_to.type_of_typedef;
            if typedef_ {
                arg_type_name := typedef_.name;
                is_prim := array_find(prim_type_names, arg_type_name);
                if is_prim {
                    last_prim_args += 1;
                    continue;
                }
            }
        }
        last_prim_args = 0;
    }

    if last_prim_args > 0 {
        array_add(*prim_funcs, .{func, last_prim_args});
    }
}

joltc_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    if decl.kind == .FUNCTION
        joltc_visit_function(cast(*Function)decl);

    return .RECURSE;
}

joltc_will_print_bindings :: () {
    builder: String_Builder;

    // TODO: this is an unfinished experiment to create wrapper functions for functions
    // which take pointers to Vec3s and Quaternions, etc.

    append(*builder, "/* TODO ------- \n");
    //append(*sb, "// TODO: Add overloads for the following functions:\n");
    //for prim_funcs
        //append(*sb, tprint("// %\n", it.func.name));



    for prim_funcs {
        new_func := it.func.*;
        type := new_func.type.type_of_function;
        /*
        new_func.arguments = array_copy(new_func.arguments);

        if new_func.decl_flags & .OMIT_FROM_OUTPUT continue;
        for arg, arg_index: new_func.arguments {
            arg_type := find_underlying_type(arg.type);

            assert(arg_type.pointer_to);
            assert(arg_type.pointer_to.type_of_typedef);
            need_to_rewrite := new_func.args.count - arg_index >= it.last_prim_args;
            if need_to_rewrite {
                print("rewrite arg %\n", arg.name);
            }
        }
        */
        print_declaration_to_builder(*builder, new_func, null, flags=.IS_GLOBAL);
        append(*builder, "\n");
        //array_add(*context.generator.global_scope.members, new_func);
    }

    append(*builder, "*/");
    footer_string := builder_to_string(*builder);

    context.generator_options.footer = tprint("%\n\n%\n",
        context.generator_options.footer, footer_string);

}

#import,file "../CMake_Module/module.jai";
#import "Bindings_Generator";
#load "../Bindings_Common.jai";
#import "Compiler";
#import "Basic";
String :: #import "String";
