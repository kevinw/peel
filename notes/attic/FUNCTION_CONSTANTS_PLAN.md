# Function Constants Plan

## Goal

Add shader function constants to the Jai shader transpiler with a source syntax that feels like a normal Jai variable declaration:

```jai
base_color_map_enabled: bool = false; @function_constant
normal_map_enabled: bool = true; @function_constant
material_mode: u32 = 0; @function_constant
```

The user should not manage numeric indices. The transpiler should:

- detect declarations marked with `@function_constant`
- track which shader entry points or shader pairs actually use them
- assign stable backend indices automatically
- emit backend metadata and host-side helper structs

The host-side API should let callers pass a typed constants struct with normal field access and Jai defaults, rather than juggling raw Metal/Vulkan specialization ids.

## Desired User Experience

### Shader authoring

The shader author writes top-level declarations like:

```jai
base_color_map_enabled: bool = false; @function_constant
normal_map_enabled: bool = true; @function_constant
material_mode: u32 = 0; @function_constant
```

Then uses them naturally in shader code:

```jai
if base_color_map_enabled {
    color *= sample_2d(base_color_tex, samp, uv).xyz;
}
```

### Host-side use

For each emitted shader entry point or graphics pair, the transpiler also generates a typed constants struct:

```jai
PBR_Graphics_Function_Constants :: struct {
    base_color_map_enabled: bool = false;
    normal_map_enabled: bool = true;
    material_mode: u32 = 0;
}
```

This lets host code do:

```jai
constants := PBR_Graphics_Function_Constants.{};
constants.base_color_map_enabled = true;
constants.material_mode = 2;
```

The backend wrapper then converts that struct into:

- Metal `MTLFunctionConstantValues`
- Vulkan specialization constants

## Scope

### In scope for v1

- top-level shader-visible declarations marked with `@function_constant`
- types:
  - `bool`
  - `u32`
  - `s32`
  - `float`
- compile-time constant default values
- usage tracking per shader entry point / shader pair
- deterministic automatic index assignment
- generated host-side constants struct
- generated metadata table for backend packing

### Out of scope for v1

- arrays, vectors, matrices, structs, or texture/sampler/resource types as function constants
- local variables marked `@function_constant`
- user-specified indices
- preserving one global index space across all shaders

## Core Design

### 1. Source syntax

Use a normal variable declaration with a trailing annotation:

```jai
base_color_map_enabled: bool = false; @function_constant
```

This should be treated as:

- a shader-global declaration
- with a default value
- specialized at pipeline creation time

### 2. Internal representation

The transpiler should track two related concepts:

#### Global declarations

All declarations marked `@function_constant`, with:

- symbol name
- type
- default value
- source location:
  - filename
  - line
  - column

#### Per-entry-point usage

For each shader entry point:

- which function constants are referenced
- directly or transitively through helper functions

For graphics shaders, the final emitted constants set should be scoped to the graphics pair, not the whole file.

### 3. Deterministic index assignment

Because compiler callbacks may arrive out of order, index assignment should happen during emission, not during initial declaration collection.

For a given emitted shader entry point or shader pair:

1. gather the used function constants
2. sort them by:
   - filename
   - line
   - column
3. assign indices `0..N-1` in that sorted order

This makes index assignment:

- deterministic
- independent of callback order
- scoped to the emitted shader artifact

### 4. Per-entry-point / pair generated structs

Generate one constants struct per emitted shader entry point or graphics pair.

Examples:

- `pbr_graphics_function_constants`
- `shadow_compute_function_constants`

Do not generate one giant file-global constants struct.

Reason:

- Metal function constants are tied to the function being specialized
- different entry points may use different constants
- smaller generated APIs are easier to use and reason about

## Generated Output

### Generated host struct

For each emitted shader entry point or pair:

```jai
PBR_Graphics_Function_Constants :: struct {
    base_color_map_enabled: bool = false;
    normal_map_enabled: bool = true;
    material_mode: u32 = 0;
}
```

Defaults should come directly from the original Jai declarations.

### Generated metadata

Also generate metadata that the backend wrapper can use:

```jai
Function_Constant_Type :: enum {
    BOOL;
    U32;
    S32;
    FLOAT;
}

Function_Constant_Info :: struct {
    name: string;
    index: u32;
    type: Function_Constant_Type;
    offset: u64;
}
```

Then per emitted shader artifact:

```jai
PBR_Graphics_Function_Constant_Info :: []Function_Constant_Info = .[
    .{name = "base_color_map_enabled", index = 0, type = .BOOL,  offset = ...},
    .{name = "normal_map_enabled",     index = 1, type = .BOOL,  offset = ...},
    .{name = "material_mode",          index = 2, type = .U32,   offset = ...},
];
```

This keeps backend code generic.

## Backend Mapping

### Metal

The generated wrapper should:

1. create `MTLFunctionConstantValues`
2. iterate the generated metadata table
3. read each field from the generated constants struct
4. call `setConstantValue:type:atIndex:`
5. pass the populated constants object into `makeFunction`

Conceptually:

```metal
constant bool base_color_map_enabled [[ function_constant(0) ]];
```

### Vulkan / SPIR-V

Each used function constant should lower to a SPIR-V specialization constant:

- `OpSpecConstantTrue` / `OpSpecConstantFalse` for `bool`
- `OpSpecConstant` for numeric types
- decorated with `SpecId = assigned_index`

The same generated host constants struct can then be used to build:

- `VkSpecializationMapEntry[]`
- specialization data blob

## Emission Strategy

### Transpiler collection

The likely implementation shape in `modules/Jai-Shader-Transpiler/Jai_To_Shader.jai` is:

- collect all global `@function_constant` declarations
- collect symbol references per shader entry point
- compute transitive function-constant usage from the call graph

### Emission

At emission time for a specific entry point or pair:

1. compute the final used function-constant set
2. sort by source location
3. assign stable indices
4. emit:
   - backend shader constants
   - host constants struct
   - metadata table

## Validation Rules

The transpiler should error if:

- `@function_constant` is used on a non-top-level declaration
- the type is unsupported
- the initializer is missing
- the initializer is not compile-time evaluable
- the same declaration is malformed or duplicated in a way that prevents deterministic emission

The transpiler should not require explicit user index declarations in v1.

## Naming Plan

Current generated shader pair names are often long and repetitive. Function-constant struct generation will make this more visible, so pair naming should be cleaned up at the same time.

Desired direction:

- derive a normalized base name from the entry point or graphics pair
- remove redundant repeated tokens like:
  - `_main`
  - `vertex`
  - `fragment`
  - `compute`
  when they are already implied by the emitted artifact type

Examples:

- current style:
  - `transpiled_pair__metal_pbr_vertex_main_pbr_fragment_main`
- preferred normalized base:
  - `pbr_graphics`

Then emit:

- `pbr_graphics_function_constants`
- `pbr_graphics_function_constant_info`

This should be heuristic and deterministic, not user-authored.

## Recommended Implementation Order

1. Parse and store `@function_constant` declarations in `Jai_To_Shader.jai`
2. Restrict to supported scalar types and constant defaults
3. Track usage per shader entry point
4. Add deterministic source-location sorting during emission
5. Emit SPIR-V specialization constants
6. Emit generated host constants structs and metadata
7. Add Metal wrapper support for `MTLFunctionConstantValues`
8. Add Vulkan wrapper support for specialization constants
9. Improve generated pair naming

## Success Criteria

This should be considered successful when:

- shader source can declare function constants without explicit indices
- generated shader artifacts use only the constants they actually reference
- generated indices are deterministic across builds
- host code can specialize shaders by filling a typed Jai struct
- Metal and Vulkan both work from the same generated constants struct

## Concrete Implementation Checklist

### Phase A. Frontend collection in `Jai_To_Shader.jai`

Target file:

- [modules/Jai-Shader-Transpiler/Jai_To_Shader.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/Jai_To_Shader.jai)

Add:

- a collected-record type for function constant declarations:
  - symbol name
  - declaration pointer
  - type kind
  - default-value representation
  - source location
- storage on `Jai_To_Shader_Plugin.impl` for:
  - all declared function constants
  - usage per shader entry point
  - usage per shader pair

Tasks:

1. Detect declarations with `@function_constant`
- likely in the same declaration scanning path that already recognizes shader annotations / notes
- accept only top-level declarations
- reject locals, params, or unsupported contexts with a compiler error

2. Validate declaration shape
- require explicit type
- require initializer
- require compile-time evaluable initializer
- restrict type to:
  - `bool`
  - `u32`
  - `s32`
  - `float`

3. Normalize source location
- store filename / line / column from the compiler message/declaration
- do not assign indices here

4. Collect symbol identity robustly
- preserve a stable symbol or declaration identity even if callbacks arrive out of order
- do not rely on collection order

### Phase B. Usage tracking in `Jai_To_Shader.jai`

Tasks:

1. Extend entry-point dependency collection
- while walking the reachable declarations/helpers for a shader entry point, note any references to collected function constants
- include transitive helper usage, not just direct references in the entry point body

2. Represent usage sets per emitted artifact
- compute:
  - per compute entry point used constants
  - per single shader entry point used constants
  - per graphics pair merged used constants

3. Add duplicate/ambiguity validation
- if the same symbol is recorded multiple times inconsistently, fail early

### Phase C. Deterministic ordering and naming

Primary file:

- [modules/Jai-Shader-Transpiler/Jai_To_Shader.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/Jai_To_Shader.jai)

Tasks:

1. Add deterministic sort for function constants
- sort by:
  - filename
  - line
  - column
  - symbol name as a last tie-breaker

2. Assign indices only after sorting
- assign `0..N-1` per emitted entry point or pair

3. Improve generated entry point / pair base names
- identify where `pair_ctx.name` / emitted symbol names are formed
- introduce a normalization helper that:
  - strips repeated `_main`
  - compresses repeated function-name stems
  - prefers stable suffixes like:
    - `_graphics`
    - `_compute`

4. Use the normalized base name for generated function-constant helper symbols
- examples:
  - `pbr_graphics_function_constants`
  - `pbr_graphics_function_constant_info`

### Phase D. Shared emitted metadata

Likely best location:

- either a small shared helper section in [modules/Jai-Shader-Transpiler/Jai_To_Shader.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/Jai_To_Shader.jai)
- or a dedicated loaded helper file if it gets large

Tasks:

1. Define generated host-facing enum/structs
- `Function_Constant_Type`
- `Function_Constant_Info`

2. Emit one typed constants struct per entry point / pair
- fields in sorted order
- defaults copied from Jai initializers

3. Emit one metadata table per entry point / pair
- field name
- generated index
- scalar type
- byte offset in the generated struct

4. Keep emitted helper scope sane
- generated constants structs should be visible to host code
- helper metadata can be internal if wrappers expose a nicer API

### Phase E. SPIR-V / backend lowering

Primary targets:

- `Jai_To_Shader.jai` for emitted source / metadata wiring
- SPIR-V backend files only if current emission cannot already express specialization constants

Likely files to inspect:

- [modules/Jai-Shader-Transpiler/ir_pipeline/spirv_text_backend.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline/spirv_text_backend.jai)
- [modules/Jai-Shader-Transpiler/ir_pipeline/public_structs.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline/public_structs.jai)
- [modules/Jai-Shader-Transpiler/ir_pipeline/ir_shared.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline/ir_shared.jai)
- [modules/Jai-Shader-Transpiler/ir_pipeline/ir_lowering.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/ir_pipeline/ir_lowering.jai)

Tasks:

1. Decide representation
- either:
  - emit specialization constants directly from frontend metadata
  - or add explicit IR nodes/metadata for function constants

2. For SPIR-V:
- emit `SpecId` decorations
- emit:
  - `OpSpecConstantTrue` / `OpSpecConstantFalse`
  - `OpSpecConstant` for numeric types

3. Ensure specialization constants can be referenced from emitted shader code as ordinary globals

4. Preserve deterministic generated indices from Phase C

### Phase F. Metal / Vulkan host wrappers

Primary likely call sites:

- shader hot reload / pipeline creation helpers in:
  - [src/shader_hot_reload.jai](/Users/kev/src/peel/src/shader_hot_reload.jai)
  - related generated lookup/wrapper emission in [modules/Jai-Shader-Transpiler/Jai_To_Shader.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/Jai_To_Shader.jai)

Tasks:

1. Generate wrapper API that accepts the typed constants struct

2. Metal path:
- create `MTLFunctionConstantValues`
- iterate generated metadata
- map Jai scalar type to Metal constant type
- call `setConstantValue:type:atIndex:`
- create specialized function before pipeline creation

3. Vulkan path:
- build `VkSpecializationMapEntry[]`
- point entries at offsets in the same generated constants struct
- feed specialization info into shader stage creation

4. Keep no-constants path fast
- wrappers should fall back to current pipeline creation flow when no function constants are used

### Phase G. Validation and tests

Primary test targets:

- [modules/Jai-Shader-Transpiler/headless_ir/graphics_semantics_runner.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/headless_ir/graphics_semantics_runner.jai)
- [modules/Jai-Shader-Transpiler/headless_ir/compute_semantics_runner.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/headless_ir/compute_semantics_runner.jai)
- [modules/Jai-Shader-Transpiler/build.jai](/Users/kev/src/peel/modules/Jai-Shader-Transpiler/build.jai)

Add tests for:

1. Collection and validation
- valid bool/u32/s32/float declarations
- rejection of unsupported types
- rejection of missing/non-constant initializers

2. Deterministic ordering
- intentionally declare constants out of order relative to helper/entry-point layout
- verify emitted indices follow source location order, not callback order

3. Usage scoping
- two entry points using different subsets of constants
- verify generated structs/metadata only include used constants

4. Pair scoping
- vertex + fragment pair using overlapping but not identical constants
- verify pair constants are the union, still sorted deterministically

5. Backend output
- SPIR-V contains `SpecId`
- generated MSL path (or emitted metadata path) preserves assigned indices

6. Naming
- regression test for normalized generated pair names staying shorter and stable

7. End-to-end peel app
- add [src/apps/function_constants_test.jai](/Users/kev/src/peel/src/apps/function_constants_test.jai)
- keep it intentionally small and deterministic:
  - fullscreen quad pipeline
  - shader declarations using `@function_constant`
  - two pipeline variants built from the same shader pair
  - left half of the screen drawn with the default constants
  - right half of the screen drawn with an overridden bool constant
- the fragment shader should output obviously different solid colors for the two variants so backend mistakes are easy to spot
- this app should exercise:
  - generated constants struct emission
  - generated metadata table offsets/types
  - Metal `MTLFunctionConstantValues` population
  - Vulkan specialization constant packing
  - distinct pipeline creation/cache entries for distinct constant values
- add a snapshot workflow:
  - run with `PEEL_SNAPSHOT`
  - save a deterministic frame image
  - verify that left and right halves render the two expected colors
- if practical, add a small automated readback/image assertion:
  - sample one pixel from each half
  - compare against expected colors within a small tolerance
  - otherwise, document the manual `PEEL_SNAPSHOT` command in the app header comment and treat the snapshot as the integration sanity check

### Phase H. Cleanup

After feature completion:

1. Update docs
- [FUNCTION_CONSTANTS_PLAN.md](/Users/kev/src/peel/FUNCTION_CONSTANTS_PLAN.md)
- `IR_DONE.md` / `IR_TODO.md` if backend work closes or opens new gaps

2. Remove temporary debug naming/diagnostic scaffolding once tests are in place

3. Keep generated helper symbol names stable once introduced
