# Shader Layout Robustness

This note is a plan for making CPU <-> JST <-> SPIR-V <-> Metal buffer/parameter struct layout failures obvious, diagnosable, and hard to ship.

The immediate motivating bug class is:

- a Jai shader param struct changes shape
- the host-side mirror still compiles
- the transpiler flattens or reinterprets fields differently than sgpu/host code expects
- rendering artifacts appear instead of a precise failure

## Goals

- Make the shader-facing layout an explicit artifact instead of an implicit byproduct.
- Fail fast when CPU and shader layouts diverge.
- Support flattened `using` struct fields consistently.
- Make hot reload robust: layout changes should either validate cleanly or fail loudly.
- Make runtime debugging cheap enough to leave enabled in debug builds.

## Non-Goals

- Supporting arbitrary foreign ABI rules by accident.
- Preserving compatibility with ambiguous or partially-specified layouts.
- Adding silent fallback paths when layout validation fails.

## Current Problems

- `CPU_Struct(T)` mirrors fields textually, but historically did not encode the same flattening rules as shader buffer lowering.
- JST computes buffer layout internally, but that layout is not surfaced as a first-class artifact for host validation.
- When a struct changes shape, the failure mode is often corrupted rendering instead of a focused mismatch report.
- Mesh/task/fragment pipelines can each consume the same logical data through slightly different structural views, which makes drift easy.
- Nested struct handling and `using` flattening are not consistently modeled across all layout-related code paths.

## Design Principle

There should be one canonical flattened shader layout per bound buffer/param struct.

Everything else should be checked against that:

- host mirror structs
- sgpu bind calls
- generated SPIR-V decorations
- generated Metal structs

## Plan

### 1. Make JST Emit Canonical Layout Metadata

For every shader-visible buffer/param struct, JST should emit metadata describing the final flattened layout:

- struct name
- total byte size
- total alignment
- field list in final ABI order
- per field:
  - flattened field name
  - byte offset
  - byte size
  - kind
  - array count / stride
  - matrix stride if relevant
  - source struct name and source member index for diagnostics

This should reflect the actual layout JST lowers, not just the original Jai source spelling.

Deliverables:

- a shared `Shader_Buffer_Layout` metadata struct
- JST emission of one layout record per relevant buffer/param type
- generated metadata available from host code in debug builds

### 2. Define One Shared Flattening Rule

We need one reusable flattening walk used by all of:

- JST buffer lowering
- JST layout metadata emission
- sgpu `CPU_Struct`
- debug layout comparison tools

Rules should be explicit:

- ordinary nested structs are nested
- embedded `using` struct members are flattened into the parent
- field names for flattened members are direct member names, not `outer.inner`
- fixed arrays and matrices keep explicit stride metadata

Deliverables:

- shared helper for flattened field enumeration
- tests covering:
  - plain structs
  - `using` embedded structs
  - arrays of structs
  - `Vector3 + scalar` padding cases

### 3. Add Compile-Time Layout Assertions

For important app-local param structs, add compile-time assertions near the shader declarations:

- `size_of`
- `align_of`
- key `offset_of(...)`

These are not the full solution, but they are cheap tripwires.

In particular, for mesh/task/fragment structs that are intended to share a prefix, add explicit prefix assertions:

- same offset for each shared field
- same size/alignment for the shared prefix

Deliverables:

- a small helper macro/proc for layout asserts
- first use in `model_scene` meshlet/task params

### 4. Add sgpu Runtime Layout Validation

At shader creation or first bind, sgpu should compare:

- expected JST-emitted layout metadata
- actual CPU mirror layout of the bound type

Validation should check:

- total size
- total alignment
- field count
- flattened field names
- field offsets
- field sizes / strides

On mismatch, hard-fail in debug with a detailed report.

Deliverables:

- `sgpu_validate_shader_layout(cpu_type, shader_layout)`
- debug-only validation on pipeline creation or first param bind
- clear mismatch diagnostics

### 5. Add a Compact Layout Hash

Once full layout metadata exists, compute a deterministic hash over:

- flattened field names
- offsets
- sizes
- strides
- total size/alignment

Use this for fast repeated checks:

- shader artifact carries expected hash
- sgpu computes CPU-side hash
- bind path asserts hash equality in debug

This is not a replacement for detailed comparison, just a fast gate.

Deliverables:

- canonical layout hash function
- hash included in generated JST metadata
- debug mismatch falls back to full structured diff

### 6. Add Runtime Shader-Side Probes

For hard cases, add a lightweight debug mode that proves what the GPU actually read.

Useful probes:

- shader colors output from selected param fields
- write selected param values into a small debug readback buffer
- one-draw capture of:
  - material index
  - batch indices
  - mesh base vertex
  - key transform fields

This is especially useful when the CPU layout and JST metadata agree, but the backend or final platform layout is still suspect.

Deliverables:

- a reusable debug readback path for shader param inspection
- optional debug fragment output for scalar field visualization

### 7. Surface Layout Data in Generated Artifacts

When debugging a build, it should be easy to inspect the final expected layout without reverse-engineering generated Metal.

Add readable layout dumps to `.build/ir_intermediate`:

- human-readable text or markdown
- one file per shader/pipeline or per shared struct

Example contents:

- struct name
- field table
- size/alignment
- layout hash

Deliverables:

- layout dump files emitted by JST in debug/dev builds

### 8. Add Transpiler Regression Tests

We should add explicit tests for the bug class we just hit.

Minimum test cases:

1. Buffer struct with embedded `using` prefix struct plus local tail fields.
2. Same shape mirrored through `CPU_Struct`.
3. Validation that flattened member order is stable.
4. Validation that generated field names are direct member names for `using`.
5. Validation that SPIR-V member offsets are emitted in flattened order.

Deliverables:

- headless JST test coverage for flattened buffer layouts
- regression test named after the `using`-prefix mesh param case

## Suggested Rollout Order

1. JST layout metadata emission.
2. Shared flattening helper used by JST and `CPU_Struct`.
3. sgpu runtime layout validator with detailed diffs.
4. Layout hash fast path.
5. Debug readback probes.
6. Broader compile-time asserts in high-risk apps.

## First Concrete Targets

- `Model_Scene_Task_Params`
- `Model_Scene_Meshlet_Params`
- `Scene_Draw_Params`
- other commonly-bound frame param structs in `src/apps`

## Example Failure Report

Ideal debug output should look like:

```text
SHADER LAYOUT MISMATCH: Model_Scene_Meshlet_Params
cpu size=144 align=16 hash=0x7d9c4f12
gpu size=160 align=16 hash=0x91b38aa0

field 'batch_first_instance': cpu offset 112, gpu offset 128
field 'batch_instance_count': cpu offset 116, gpu offset 132
field 'mesh_base_vertex': cpu offset 128, gpu offset 144
```

That is the level of precision we want instead of “wrong meshes rendered.”

## Open Questions

- Should JST metadata always be embedded, or only in debug/dev builds?
- Should sgpu validate at pipeline creation, first bind, or both?
- Do we want a repo-wide convention that shader param structs avoid ordinary nested structs entirely, except for `using` prefixes?
- How much of the final Metal layout should we explicitly re-check versus trusting SPIR-V + SPIRV-Cross once JST metadata is consistent?

## Summary

The robust version is:

- JST defines the canonical flattened layout.
- sgpu mirrors and validates against it.
- debug builds fail immediately on mismatch.
- runtime probes exist for the rare cases where the platform backend still disagrees.

That should turn this entire class of bugs from “mysterious artifacts” into “one-line ABI mismatch reports.”
