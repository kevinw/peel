PATH_TO_APP_FILES :: "src/apps";

APP_FILES :: string.[
    "textured_triangle.jai",
    "pbr.jai",
    "particles.jai",
    "boids.jai",
    "reaction_diffusion.jai",
    "raymarch.jai",
    "raytracer.jai",
    "fluid2d.jai",
    "ripple_heightfield.jai",
    "flux.jai",
    "sand_toy.jai",
    "gizmos_test.jai",
    "terrain_test.jai",
    "texture3d.jai",
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

#scope_file

String :: #import "String";
