PATH_TO_APP_FILES :: "src/apps";

APP_FILES :: string.[
    "app_peel_surprise.jai",
    "app_peel_boids.jai",
    "app_peel_reaction_diffusion.jai",
    "app_peel_basic.jai",
];

active_app_filename :: () -> string {
    return APP_FILES[0];
}
