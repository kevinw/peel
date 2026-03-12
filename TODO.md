# TODO

- make build.jai - -dll build the host only once.
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

## other things to try
- decompile samus or mario player controllers and make a custom one w/ llm
- open PBR impl https://github.com/adobe/openpbr-bsdf
- macos code injection https://mariozechner.at/posts/2024-07-20-macos-code-injection-fun/
- variable rate shading https://www.youtube.com/watch?v=mvCoqCic3nE
- analytic fog rendering https://matejlou.blog/2025/02/11/analytic-fog-rendering-with-volumetric-primitives/
- cone tracing https://x.com/SebAaltonen/status/2030644802925027537?s=20
- in shader debugging tools https://github.com/electronicarts/ShaderToHuman
- try new Metal display HUD https://x.com/Dispatch_Graph/status/2028631974068527258?s=20
