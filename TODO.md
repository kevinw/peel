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

- this SebAaltonen tweet:
Codex ported our old GLSL shaders to WGSL and made all vertices full fat fp32 (52 bytes). 
Optimized back to:
position: RGB32_FLOAT
uv: RG16_UNORM ; uv = packed * 16.0 - 8.0
normal: RGB10A2_UNORM
tangent: RGB10A2_UNORM ; w = bitangent.sign
color: RGBA8_UNORM
= 28 bytes
RGB32_FLOAT position could be optimized further as RGBA16_UNORM. Scaled object bounding box to [0,1] and object matrix would have mesh scale matrix multiply inside it. No extra vertex shader cost to decode. But it's extra fuss in CPU side. That's 24 bytes total.
