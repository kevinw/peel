PATH_TO_APP_FILES :: "src/apps";

APP_FILES :: string.[
    "particles.jai",
    "boids.jai",
    "reaction_diffusion.jai",
    "hello.jai",
];

active_app_filename :: () -> string {
    return APP_FILES[0];
}
