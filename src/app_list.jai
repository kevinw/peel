PATH_TO_APP_FILES :: "src/apps";
APP_CAPTURE_DIR :: ".build/screenshots";

APP_FILES :: string.[
    "textured_triangle.jai",
    "pbr.jai",
    "particles.jai",
    "boids.jai",
    "reaction_diffusion.jai",
    "raymarch.jai",
    "cel_shading.jai",
    "raytracer.jai",
    "fluid2d.jai",
    "ripple_heightfield.jai",
    "flux.jai",
    "shader_to_human.jai",
    "inspiration_test.jai",
    "sand_toy.jai",
    "gizmos_test.jai",
    "terrain_test.jai",
    "texture3d.jai",
    "meshlet_lizard_grid.jai",
    "blender_scene.jai",
    "mesh_shader_triangle.jai",
    "decal_painter.jai",
];

active_app_filename :: () -> string {
    return APP_FILES[0];
}

app_stem_for_source_file :: (source_file: string) -> string {
    return String.path_strip_extension(String.path_filename(source_file));
}

app_dll_basename_for_source_file :: (source_file: string) -> string {
    return app_stem_for_source_file(source_file);
}

app_capture_filename_for_source_file :: (source_file: string) -> string {
    return sprint("%_capture.jpeg", app_stem_for_source_file(source_file));
}

app_capture_path_for_source_file :: (source_file: string, base_dir := APP_CAPTURE_DIR) -> string {
    return String.path_join(base_dir, app_capture_filename_for_source_file(source_file));
}

app_source_path_for_source_file :: (source_file: string, base_dir := PATH_TO_APP_FILES) -> string {
    if String.path_filename(source_file) == source_file {
        return String.path_join(base_dir, source_file);
    }
    return source_file;
}

#scope_file

String :: #import "String";
