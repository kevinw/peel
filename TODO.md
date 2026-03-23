# TODO

- see if we can use #initializer_of for cpu memory in alloc view
- make build.jai - -dll build the host only once.
- fix Bindings_Generator for MTL4, consider making functions #no_context
- sgpu Metal debug: track residency dirty state and assert/bark on resource use without `gpu_commit_residency()`, using `MTLResidencySet.containsAllocation(...)` checks on bound allocations
- fix jai build.jai - -dll (parallel builds need to build only dylibs)
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
- or this one: https://x.com/SebAaltonen/status/2032555792839200834?s=20
fter porting HypeHype shaders to our new project (and from GLSL to WGSL), I restored gather4 and fp16 optimizations...

Biggest gains:
SSAO: 0.992ms -> 0.555ms (-46%)
Lighting: 0.149ms -> 0.108ms (-28%)

Total frame time in test scene = 1.16ms (M3 Max)
Image

Sebastian Aaltonen
@SebAaltonen
1.16ms for all this:
- 4x shadow cascades (4K atlas)
- G-buffer (3x 32-bit + Z-buffer)
- SSAO (custom GTAO)
- Deferred lighting (GGX/HDR, sun only + IBL indirect)
- Bloom (HDR, very wide kernel)
- Post: ACES tonemap, color grading LUT, vignette
- Temporal AA (custom)

# watch
- Visibility Buffer and Deferred Rendering in DOOM: The Dark Ages https://www.youtube.com/watch?v=fXakIV1OFes
- https://wojtsterna.com/math-for-3d-programmers/

# read
- https://www.rastergrid.com/blog/gpu-tech/2026/03/vulkan-memory-barriers-and-image-layouts-explained/
- https://irradiance.ca/posts/microshadowing-part2/
- https://imadrahmoune.com/pbr/
- https://x.com/miketuritzin/status/2018752653053030463
- render graphs: https://alielmorsy.github.io/the-art-of-render-graphs/
- https://www.khronos.org/blog/new-vulkan-game-engine-tutorial-build-your-own-production-ready-rendering-engine
- https://www.noelberry.ca/posts/making_games_in_2025/
- https://cormullion.github.io/Lindenmayer.jl/stable/
- multicore by default https://www.dgtlgrove.com/p/multi-core-by-default
- https://0byte.io/articles/pytorch_introduction.html
- https://syllogi-graphikon.vercel.app/posts/metal-single-pass-downsampler/
- https://www.cs.cmu.edu/~rdriley/487/papers/Thompson_1984_ReflectionsonTrustingTrust.pdf
