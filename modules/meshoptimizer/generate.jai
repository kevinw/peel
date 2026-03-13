/*

Builds the meshoptimizer library and generates bindings for it.

*/

CMAKE_BUILD_TYPE :: "Release";

#run {
    set_build_options_dc(.{do_output = false});
    project: Project_Options;
    init_from_github_zipfile_with_branch(*project, repo="zeux/meshoptimizer", branch="master");
    #if OS == .WINDOWS
        array_add(*project.platform_artifacts, tprint("%/meshoptimizer.lib", CMAKE_BUILD_TYPE));
    else
        array_add(*project.platform_artifacts, "libmeshoptimizer.a");
    project.bindings_options_callback = (using opts: *Generate_Bindings_Options, paths: Build_Project_Paths) {
        array_add(*source_files, "meshoptimizer.h");
        array_add(*include_paths, tprint("%/src", paths.src));
        array_add(*strip_prefixes, "meshopt_");

        // Need to link against libc++ on non-Windows platforms for operator new/delete
        // TODO: maybe patch the usage of operator new/delete in the meshoptimizer codebase?? they already have
        // a function to set a custom allocator.
        footer = sprint("%\n%", footer, #string END
#if OS != .WINDOWS { 
    #library,system,link_always "libc++"; 
}
END);
    }
    ok, result :=build_and_generate_bindings(*project, .{
        cmake_build_type=CMAKE_BUILD_TYPE,
        verbose=false,
    });
    if !ok fail_and_exit("Failed to build and generate bindings");
}

#scope_file
#import,file "../CMake_Module/module.jai";
#import,file "../Bindings_Common.jai";
#import "Bindings_Generator";
#import "Compiler";
#import "Basic";
