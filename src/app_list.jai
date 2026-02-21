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
];

active_app_filename :: () -> string {
    return APP_FILES[0];
}
