CMAKE_BUILD_TYPE :: "Debug";

#run {
    set_build_options_dc(.{do_output = false});

    project: Project_Options;
    init_from_github_zipfile_with_branch(*project, repo="assimp/assimp", branch="master");
    array_add(*project.extra_cmake_configure_args,
        "-DASSIMP_WARNINGS_AS_ERRORS=ON",
        "-DASSIMP_BUILD_ASSIMP_TOOLS=OFF",
        "-DBUILD_SHARED_LIBS=ON",
        "-DASSIMP_BUILD_TESTS=OFF",
        "-DASSIMP_INSTALL=OFF",
        "-DUSE_STATIC_CRT=OFF",
        "-DASSIMP_BUILD_ASSIMP_VIEW=OFF",
    );
    #if OS == .WINDOWS {
        array_add(*project.extra_cmake_configure_args, "-DUSE_STATIC_CRT=OFF");
    }
    #if OS == .MACOS {
        #if CMAKE_BUILD_TYPE == "Debug" {
            array_add(*project.platform_artifacts, "bin/libassimpd.6.0.2.dylib");
        } else {
            array_add(*project.platform_artifacts, "bin/libassimp.6.0.2.dylib");
        }
    } else #if OS == .WINDOWS {
        // TODO: see if vc143-mt can be programmatically pulled out of cmake's output files
        array_add(*project.platform_artifacts,     #run sprint("bin/%/assimp-vc143-mt.dll", CMAKE_BUILD_TYPE));
        array_add(*project.extra_binaries_to_copy, #run sprint("lib/%/assimp-vc143-mt.lib", CMAKE_BUILD_TYPE));
    } else #if OS == .LINUX {
        array_add(*project.platform_artifacts, "bin/libassimp.so.6.0.2");
    } else {
        #assert false "TODO: implement for this platform";
    }

    project.bindings_options_callback = (using opts: *Generate_Bindings_Options, paths: Build_Project_Paths) {
        array_add(*include_paths, ..get_default_system_include_paths());
        array_add(*path_fragments_to_treat_as_non_system_paths, "assimp/");
        array_add(*include_paths,
            tprint("%/include", paths.src),     // For assimp's source files.
            tprint("%/include", paths.build),   // For the config.h file generated during the assimp build.
        );
        array_add(*strip_prefixes, "ai");
        array_add(*source_files, 
            "assimp/aabb.h",
            "assimp/anim.h",
            "assimp/camera.h",
            "assimp/light.h",
            "assimp/material.h",
            "assimp/mesh.h",
            "assimp/metadata.h",
            "assimp/texture.h",
            "assimp/cimport.h",
            "assimp/cexport.h",
            "assimp/scene.h",
            "assimp/types.h",
            "assimp/postprocess.h",
        );
        visitor = assimp_visitor;
        footer = sprint("%\n\n%", footer, CUSTOM_FOOTER);
    }

    build_and_generate_bindings(*project, .{
        cmake_build_type = CMAKE_BUILD_TYPE,
    });
}

#scope_file

CUSTOM_FOOTER :: #string END
#scope_export
#load "./assimp_extra.jai";

END

assimp_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    return .RECURSE;
}

#import,dir "../CMake_Module";
#import "Compiler";
#import "Basic";
#import "Bindings_Generator";