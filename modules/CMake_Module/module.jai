/*

Not a build system.

Opioniated and simplified Jai bindings gen for C/C++ projects which use CMake or can be built trivially.

*/

option_skip_download_if_already_unzipped := true; // TODO

BUILD_CPP_SRC_DIR_SENTINEL :: "<<build_cpp_src_dir>>";

Project_Options :: struct {
    project_name: string;

    source_provided_manually: bool = false;
    source_zip_url: string;
    build_dir: string = ".build/nabs";
    source_zip_unpacked_dir: string;
    source_zip_file_name: string;
    git_clone_url: string;
    git_clone_depth: int = 1;

    // Must be filled in by the caller. A list of built library files to copy into the platform directory.
    platform_artifacts: [..]string;

    // Extra files to copy to the platform bin directory. (Like .lib files that go alongside .dll files on windows.)
    extra_binaries_to_copy: [..]string;

    relative_path_to_cmakelists_txt: string = "";
    extra_cmake_configure_args: [..]string;

    platforms_jai_will_reference : []Operating_System_Tag = .[
        .WINDOWS,
        .MACOS,
        .LINUX,
    ];

    bindings_options_callback: (opts: *Bindings_Generator.Generate_Bindings_Options, absolute_source_dir: Build_Project_Paths) -> ();
}

Source_Build_Options :: struct {
    clean := true;
    skip_build := false;
    generate_bindings := true;
    verbose := false;
    cmake_build_type: string = "Release";
    cmake_parallel_jobs: u32 = 8;
    single_header_build: struct {
        headers: []string;
        defines: []string;
        build_cpp_extra: []string;
    };
    build_cpp: struct {
        files: []string;
        extra: []string;
        build_type: Build_Type = .DYNAMIC_LIBRARY;
    }
}

// Platform directory for library files, like lib/macos or lib/win
PLATFORM_DIR :: #run get_platform_dir(OS);

init_from_source :: (project_opts: *Project_Options, project_name: string, source_dir: string) {
    project_opts.project_name = project_name;
    project_opts.source_zip_unpacked_dir = source_dir;
    project_opts.source_provided_manually = true;
}

init_from_github_clone :: (using project_opts: *Project_Options, repo: string, branch: string = "main") {
    ok, owner, repo_name := split_from_left(repo, "/");
    if !ok fail_and_exit("We expected the github repo to be in the format of owner/repo, but we got: %", repo);

    project_name = repo_name;
    git_clone_url = sprint("git@github.com:%.git", repo);
    source_zip_unpacked_dir = repo_name;
}

init_from_github_zipfile_with_branch :: (using project_opts: *Project_Options, repo: string, branch: string = "main") {
    ok, owner, repo_name := split_from_left(repo, "/");
    if !ok fail_and_exit("We expected the github repo to be in the format of owner/repo, but we got: %", repo);

    project_name = repo_name;
    source_zip_url = sprint("https://github.com/%/archive/refs/heads/%.zip", repo, branch);
    source_zip_unpacked_dir = sprint("%-%", project_name, branch);
    source_zip_file_name = sprint("%-%.zip", project_name, branch);
}

init_from_github_zipfile_with_release_version :: (using project_opts: *Project_Options, repo: string, release_version: string) {
    ok, owner, repo_name := split_from_left(repo, "/");
    if !ok fail_and_exit("We expected the github repo to be in the format of owner/repo, but we got: %", repo);
    project_name = repo_name;
    source_zip_url = sprint("https://github.com/%/archive/refs/tags/v%.zip", repo, release_version);
    source_zip_unpacked_dir = sprint("%-%", project_name, release_version);
    source_zip_file_name = sprint("%-%.zip", project_name, release_version);
}

g_library_name_for_jai := "";

build_and_generate_bindings :: (using project_opts: Project_Options, build_opts: Source_Build_Options = .{}) -> (ok: bool, result: NABS_Result) {
    if project_name == "" fail_and_exit("project_name is not set");

    make_directory_if_it_does_not_exist(build_dir, recursive=true);
    abs_build_dir := get_absolute_path_assert(build_dir, mkdirs=true);

    // Get the source code
    if !source_provided_manually {
        push_working_directory(abs_build_dir);

        if file_exists(source_zip_unpacked_dir) && option_skip_download_if_already_unzipped {
            log("Skipping download because the source zipfile already exists and option_skip_download_if_already_unzipped is true: %", source_zip_unpacked_dir);
        } else {

            if git_clone_url {
                log("Cloning %...", git_clone_url);
                cmd("git", "clone", tprint("--depth=%", git_clone_depth), "--recursive", git_clone_url);
            } else {
                if source_zip_url == "" fail_and_exit("source_zip_url is not set");
                log("Downloading source ZIP file..."); // TODO: See if curl can see that we don't need to redownload the zipfile if it already exists/matches hash etc
                curl_args: [..]string;
                array_add(*curl_args, "curl");
                if build_opts.verbose array_add(*curl_args, "-v");
                array_add(*curl_args, "-s", "-L", source_zip_url, "--output", source_zip_file_name);
                cmd(..curl_args);

                log("Unzipping source...");
                unzip(source_zip_file_name);
            }

            if !file_exists(source_zip_unpacked_dir)
                fail_and_exit("We didn't find the source to be in its expected place, which is: %", source_zip_unpacked_dir);
        }
    }

    // Build
    absolute_source_dir := get_absolute_path_assert(tprint("%/%", abs_build_dir, source_zip_unpacked_dir), mkdirs=true);
    absolute_build_dir := get_absolute_path_assert(tprint("%/build_%_%", abs_build_dir, project_name, build_opts.cmake_build_type), mkdirs=true);
    log("absolute_build_dir: %", absolute_build_dir);
    if !build_opts.skip_build {
        if build_opts.build_cpp.files.count > 0 {
            // Build C++ files
            push_working_directory(absolute_build_dir);
            log("Building C++ files... (cwd is %)", get_working_directory());
            abs_files: [..]string;
            for build_opts.build_cpp.files {
                source_file := it;
                if !file_exists(source_file) {
                    // TODO: files could come with an enum indicating if they are src-build local or jai-generate local.
                    // for now we just check if the given file exists, and if not, we assume the caller
                    // meant "relative to srcbuild"
                    source_file = path_join(absolute_source_dir, source_file,, temp);
                }
                array_add(*abs_files, source_file);
            }

            extra: [..]string;
            for build_opts.build_cpp.extra {
                array_add(*extra, replace(it, BUILD_CPP_SRC_DIR_SENTINEL, absolute_source_dir));
            }

            if !build_cpp(output_basename = tprint("lib%", project_name),
                          files = ..abs_files,
                          type = build_opts.build_cpp.build_type,
                          debug = false,
                          extra = extra
            ) {
                fail_and_exit("Failed to buildcpp");
            }
        } else if build_opts.single_header_build.headers.count > 0 {
            // Single header build

            using build_opts.single_header_build;
            log("Building single header library...");

            push_working_directory(absolute_build_dir);

            extra: [..]string;
            for defines array_add(*extra, tprint("-D%", it));
            array_add(*extra, tprint("-I%", absolute_source_dir));
            array_add(*extra, ..build_opts.single_header_build.build_cpp_extra);
            sb: String_Builder;
            sb.allocator = temp;
            for headers append(*sb, tprint("#include \"%\"\n", it));
            write_entire_file("temp_build.cpp", builder_to_string(*sb,,temp));

            if !build_cpp(output_basename = tprint("lib%", project_name),
                          files = "temp_build.cpp",
                          type = .STATIC_LIBRARY,
                          debug = false,
                          extra = extra) {
                fail_and_exit("Failed to build single header library: %", build_opts.single_header_build);
            }

            //cmd("cp", tprint("%/%", absolute_source_dir, build_opts.single_header_build), tprint("%/%", absolute_build_dir, build_opts.single_header_build));
        } else {
            // CMake

            log("Configuring %...", project_name);
            {
                if build_opts.cmake_build_type == ""
                    fail_and_exit("We expected the cmake_build_type to be set, but it was not");
                configure_args: [..]string;
                configure_args.allocator = temp;

                absolute_path_to_cmakelists_txt_dir := absolute_source_dir;
                if relative_path_to_cmakelists_txt {
                    absolute_path_to_cmakelists_txt_dir = tprint("%/%", absolute_path_to_cmakelists_txt_dir, relative_path_to_cmakelists_txt);
                }
                array_add(*configure_args, "cmake",
                    tprint("-S%", absolute_path_to_cmakelists_txt_dir),
                    tprint("-B%", absolute_build_dir),
                    tprint("-DCMAKE_BUILD_TYPE=%", build_opts.cmake_build_type),
                );
                array_add(*configure_args, ..extra_cmake_configure_args);
                cmd(..configure_args);
            }

            log("Building %...", project_name);
            {
                build_args: [..]string;
                build_args.allocator = temp;
                array_add(*build_args, "cmake", "--build", absolute_build_dir);
                if build_opts.cmake_parallel_jobs > 0
                    array_add(*build_args, "--parallel", tprint("%", build_opts.cmake_parallel_jobs));

                // Select release builds on windows with --config Release.
                #if OS == .WINDOWS
                    if build_opts.cmake_build_type == "Release"
                        array_add(*build_args, "--config", "Release");

                if build_opts.verbose
                    array_add(*build_args, "--", "VERBOSE=1");
                cmd(..build_args);
            }
        }

        make_directory_if_it_does_not_exist(PLATFORM_DIR, recursive=true);
        for platform_artifacts {
            artifact_path := tprint("%/%", absolute_build_dir, it);
            ext, found_ext := path_extension(artifact_path);
            if !found_ext {
                // When specified without an extension, assume it's .dll or .dylib etc.
                //
                lib_or_dll_extension: string;
                if build_opts.build_cpp.build_type == .DYNAMIC_LIBRARY {
                    lib_or_dll_extension = platform_dynamic_library_extension;
                } else {
                    lib_or_dll_extension = platform_static_library_extension;
                }

                artifact_path = tprint("%.%", artifact_path, lib_or_dll_extension);
            }
            if !file_exists(artifact_path) {
                fail_and_exit("We didn't find an artifact to be in its expected place, which is: %", artifact_path);
            }
            copy_dll(artifact_path, PLATFORM_DIR);
        }

        for extra_binaries_to_copy {
            artifact_path := tprint("%/%", absolute_build_dir, it);
            if !file_exists(artifact_path)
                fail_and_exit("We didn't find an extra_binaries_to_copy to be in its expected place, which is: %", artifact_path);
            copy_dll(artifact_path, PLATFORM_DIR);
        }
    }

    absolute_platform_dir := get_absolute_path_assert(PLATFORM_DIR, mkdirs=true);

    output_filename := "";

    // Bindings generation
    if build_opts.generate_bindings {
        if platform_artifacts.count == 0 fail_and_exit("CMake_Module: error - cannot generate bindings, because Project_Options.platform_artifacts is not set");
        output_filename = sprint("%.jai", PLATFORM_NAME);
        log("Generating bindings for %...", project_name);
        write_entire_file("module.jai", get_platform_load_statements());
        using opts: Bindings_Generator.Generate_Bindings_Options;
        array_add(*library_search_paths, PLATFORM_DIR);
        library_name_strings: [..]string;
        for path_to_artifact: platform_artifacts {
            it := path_filename(path_to_artifact);
            array_add(*library_name_strings, it);
            if OS == .MACOS && ends_with(it, ".a") {
                libname := it;
                libname.count -= 2;
                array_add(*opts.libraries, Bindings_Generator.Library.{filename=libname, identifier=""});
            } else {
                array_add(*opts.libraries, Bindings_Generator.Library.{filename=it, identifier=""});
            }
        }
        log_stripped_declarations = true;
        generate_compile_time_struct_checks = false;
        try_to_preserve_comments = true;
        alias_original_enum_names = false;
        mimic_spacing_flags = 0;
        generate_library_declarations = false;

        g_library_name_for_jai = copy_string(library_name_strings[0]); // TODO more than one
        if ends_with(g_library_name_for_jai, ".a") {
            g_library_name_for_jai.count -= 2;
        }

        /* this is terrible and very bad
        we should get rid of "platform artifacts" and just use the libaries part of Bindings_Generator directly.
         */

        if ends_with(g_library_name_for_jai, ".dylib") g_library_name_for_jai.count -= 6;
        if ends_with(g_library_name_for_jai, ".dll")   g_library_name_for_jai.count -= 4;
        if ends_with(g_library_name_for_jai, ".so")    g_library_name_for_jai.count -= 3;
        if ends_with(g_library_name_for_jai, ".lib")   g_library_name_for_jai.count -= 4;

        library_filename_on_disk := copy_string(g_library_name_for_jai);
        replace_chars(g_library_name_for_jai, "-", #char "_");

        will_print_bindings = () {
            // Change the library name to be the same on all platforms
            // so that we don't have to generate identical bindings for every platform just because the library name is different.
            if context.generator.libraries.count == 0 {
                fail_and_exit("Error: The Bindings_Generator didn't find any libraries to generate bindings for.");
            }

            context.generator.libraries[0].identifier = get_library_filename(g_library_name_for_jai);
        };

        footer_builder := String_Builder.{allocator=temp};
        jai_lib_identifier := get_library_filename(g_library_name_for_jai);
        for platform: platforms_jai_will_reference {
            append(*footer_builder, tprint(#string END
#if OS == .% {
    % :: #library,no_dll "%/%";
}
END, platform, jai_lib_identifier, get_platform_dir(platform), library_filename_on_disk));
        }
        footer = builder_to_string(*footer_builder);
        // print("FOOTER\n%\n\n", footer);
        if bindings_options_callback == null {
            fail_and_exit("bindings_options_callback is not set");
        } else {
            paths: Build_Project_Paths;
            paths.src = absolute_source_dir;
            paths.build = absolute_build_dir;
            bindings_options_callback(*opts, paths);
        }

        success := Bindings_Generator.generate_bindings(opts, output_filename);
        if !success fail_and_exit("Failed to generate bindings");
    }

    return true, .{
        absolute_build_dir    = absolute_build_dir,
        absolute_src_dir      = absolute_source_dir,
        absolute_platform_dir = absolute_platform_dir ,
        generated_bindings_filename = output_filename,
    };
}

Build_Project_Paths :: struct {
    src: string;
    build: string;
}

NABS_Result :: struct {
    absolute_build_dir: string;
    absolute_src_dir: string;
    absolute_platform_dir: string;
    generated_bindings_filename: string;
}

Text_Replacement :: struct {
    text: string;
    replacement: string;
};

replace_texts_in_file :: (filename: string, args: ..Text_Replacement) -> (every_replacement_had_one_occurrence: bool) {
    String :: #import "String";
    File :: #import "File";
    contents, ok := File.read_entire_file(filename);
    if !ok fail_and_exit("Failed to read file: %", filename);
    every_replacement_had_one_occurrence := true;
    for args {
        old_contents := contents;
        occurrences := 0;
        contents, occurrences = String.replace(old_contents, it.text, it.replacement);
        free(old_contents);
        print("Replaced % occurrences of '%' with '%' in %\n", occurrences, it.text, it.replacement, filename);
        if occurrences != 1
            every_replacement_had_one_occurrence = false;
    }
    File.write_entire_file(filename, contents);
    free(contents);
    return every_replacement_had_one_occurrence;
}

#scope_file

push_working_directory :: (path: string) #expand {
    old_working_directory := get_working_directory();
    set_working_directory(path);
    `defer set_working_directory(old_working_directory);
}

#scope_file

get_library_filename :: (library_name: string) -> string {
    library_name_without_dots := replace(library_name, ".", "_");
    if OS == .WINDOWS return library_name_without_dots;
    if begins_with(library_name_without_dots, "lib") return library_name_without_dots;
    return sprint("lib%", library_name_without_dots);
}


Bindings_Generator :: #import "Bindings_Generator";
#import "Basic";
#import "String";
#import "File_Utilities";
#import "File";
#import "Process";
#import "Compiler";
#import "BuildCpp";
#import,file "../Bindings_Common.jai";

/*
TODO: re: "platform_artifacts" above--we could possibly parse build_projectname_Release/CMakeFiles/cmake_projectname.dir/link.txt to see what files were linked into the final .a/.so/.dylib etc

the contents for meshoptimizer for example:

/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar qc libmeshoptimizer.a CMakeFiles/meshoptimizer.dir/src/allocator.cpp.o CMakeFiles/meshoptimizer.dir/src/clusterizer.cpp.o CMakeFiles/meshoptimizer.dir/src/indexanalyzer.cpp.o CMakeFiles/meshoptimizer.dir/src/indexcodec.cpp.o CMakeFiles/meshoptimizer.dir/src/indexgenerator.cpp.o CMakeFiles/meshoptimizer.dir/src/overdrawoptimizer.cpp.o CMakeFiles/meshoptimizer.dir/src/partition.cpp.o CMakeFiles/meshoptimizer.dir/src/quantization.cpp.o CMakeFiles/meshoptimizer.dir/src/rasterizer.cpp.o CMakeFiles/meshoptimizer.dir/src/simplifier.cpp.o CMakeFiles/meshoptimizer.dir/src/spatialorder.cpp.o CMakeFiles/meshoptimizer.dir/src/stripifier.cpp.o CMakeFiles/meshoptimizer.dir/src/vcacheoptimizer.cpp.o CMakeFiles/meshoptimizer.dir/src/vertexcodec.cpp.o CMakeFiles/meshoptimizer.dir/src/vertexfilter.cpp.o CMakeFiles/meshoptimizer.dir/src/vfetchoptimizer.cpp.o
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib libmeshoptimizer.a
*/
