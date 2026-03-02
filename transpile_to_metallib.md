# Per-App Metallib Plan (with Hot Reload)

## Goal
Reduce startup latency by avoiding runtime shader source compilation. Build and load a per-app `.metallib` artifact, while preserving live shader hot reload during development.

## Non-Goals (for first pass)
- No multi-platform artifact redesign (focus on macOS Metal path first).
- No pipeline binary archive integration yet (can be phase 2).
- No major changes to shader authoring API in app files.

## Current Startup Bottleneck
- App startup currently calls `get_transpiled(.METAL, ...)` and creates pipelines from source text.
- This forces frontend + shader compile work at app startup.

## Proposed Artifact Boundary
- One metallib per app:
  - `dist/shaders/<app_stem>/<app_stem>.metallib`
- Keep one manifest per app for stable entry lookup:
  - maps `entry_id -> function name(s)` and source hash/signature.

Rationale:
- Simple runtime lookup.
- Fewer files and fewer failure modes.
- Still compatible with app-local hot reload and incremental builds.

## Phase 1: Offline Build Artifacts
1. Extend transpiler/build pipeline to emit app Metal source bundle for all registered entry points.
2. Compile Metal sources to `.air` as part of transpiler external-job execution:
   - run `xcrun metal -std=metal3.0 -c <source>.metal -o <source>.air`
   - do this in parallel worker thread groups where possible.
3. After all `.air` jobs finish, run one app-level `xcrun metallib` link step:
   - `xcrun metallib <air...> -o dist/shaders/<app_stem>/<app_stem>.metallib`
4. Keep emitted `.air` files in an app-local intermediate directory for debugging and incremental rebuilds.
5. Write app-level manifest next to metallib containing:
   - `entry_id`
   - shader kind (`graphics_pair` or `compute`)
   - vertex/fragment/compute function names
   - source hash (or build hash)
6. Fail build if `.air` or `.metallib` generation fails (no silent fallback in build stage).

Implementation note from current transpiler structure:
- `Jai_To_Shader.jai` already parallelizes single-shader SPIR-V external jobs (`run_spirv_external_jobs_parallel`).
- We can attach per-job Metal->AIR compilation to that worker flow for single shaders.
- Pair shaders are currently processed outside that worker batch; phase 1 will refactor pair processing into the same external-job worker queue so `.air` generation is parallelized consistently for both single and pair requests.

## Phase 2: Runtime Loading Path
1. Add sgpu API surface for precompiled library usage (Metal backend):
   - load metallib from file/data
   - create graphics pipeline from `(library, vs_name, fs_name, raster_desc)`
   - create compute pipeline from `(library, cs_name)`
2. In app startup (`on_dll_init`):
   - load per-app metallib + manifest
   - create all required pipelines via function names
3. No startup source fallback path; missing/invalid metallib is a hard failure.

## Phase 3: Hot Reload Compatibility
Use metallib for both startup and reload paths.

- Startup path:
  - load prebuilt metallib + manifest.
- Reload path:
  - when watcher detects changed shader entries, rebuild app `.air` set and relink app metallib.
  - reload system then recreates affected pipelines from the updated metallib + manifest function mappings.
- No runtime source-based pipeline rebuild path.

## Runtime Decision Matrix
- `RELEASE`:
  - require metallib path; fail hard if missing.
- `DEBUG`:
  - require metallib path on startup; fail hard if missing.
  - no startup fallback to source compile.
  - keep live reload enabled.

## Minimal Data Model Changes
- Extend shader reload target metadata to include function names and optional library key.
- Add app-level shader asset descriptor:
  - metallib path
  - manifest path
  - app shader version/hash

## Validation Plan
1. Build app with metallib enabled and measure first-frame time.
2. Confirm visual parity against source path.
3. Confirm hot reload still swaps changed pipelines correctly.
4. Test failure behavior:
   - missing metallib
   - outdated manifest
   - bad function name mapping
5. Add an automated shader-reload snapshot mode for deterministic before/after capture:
   - `PEEL_SHADER_RELOAD_SNAPSHOT=1`
   - captures `before` at startup frame
   - waits for shader hot-reload completion event (`shader_hot_reload_tick` reports rebuild completion)
   - captures `after` immediately after successful pipeline swap
   - exits automatically
   - includes timeout guard via `PEEL_SHADER_RELOAD_TIMEOUT_FRAMES` to avoid hangs if no reload occurs.

## Risks
- Function name mismatches between manifest and compiled metallib.
- Drift between startup (metallib) and reload (source) code paths.
- Additional build-tool dependency on Xcode command-line tools.

## Follow-Up (Phase 4)
- Add `MTLBinaryArchive` caching for faster warm startup and reload pipeline creation.
- Potentially split per-app into `core` + `debug` metallibs if startup IO/compile churn warrants it.

## Confirmed Decisions
1. Startup behavior: fail hard if per-app metallib is missing (debug and release).
2. Reload behavior: use metallib-based reload now (no source-based runtime pipeline reload path).
3. Packaging: one metallib per app for now, including debug shaders.
4. Pair refactor: move pair shader external work into worker-thread job flow now (no temporary main-thread path).
5. AIR retention: keep generated `.air` files always (not debug-only).
6. Reload failure behavior: keep old pipelines alive, log error, and surface a dismissible ImGui error window.
