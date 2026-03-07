# TODO

- fix Bindings_Generator for MTL4, consider making functions #no_context
- a "noisy" mode for sgpu where all non-success results are logged
- sgpu Metal debug: track residency dirty state and assert/bark on resource use without `gpu_commit_residency()`, using `MTLResidencySet.containsAllocation(...)` checks on bound allocations
- fix jai build.jai - -dll (parallel builds need to build only dylibs)
- add "capture screen" app which saves a grid of images from all the examples
- remove IR_PLAN
- make built binaries go in bin/

## compute shaders to try

- https://syllogi-graphikon.vercel.app/posts/metal-single-pass-downsampler/
- https://blog.maximeheckel.com/posts/shades-of-halftone/
