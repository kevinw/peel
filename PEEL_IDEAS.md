# Peel Rapid Prototyping Ideas

## Goal
Make app iteration in `src/apps/` faster by removing repeated boilerplate while keeping each prototype expressive.

## High-Value Abstractions

1. `App_2D_Compute_Viewer` base
- Standard app skeleton for: ping-pong state buffer, compute dispatch, fullscreen draw, and overlay UI.
- Targets apps like `ripple_heightfield`, `fluid2d`, `reaction_diffusion`, and `sand_toy`.

2. `Sim_Grid`
- Shared grid-state type: `width`, `height`, `cell_count`, buffer layout, ping-pong offsets.
- Common helpers for initialization/reset/seeding.

3. `Shader_Bundle` + hot-reload wrapper
- One API to register and rebuild `compute + graphics` shader pipelines together.
- Centralize `get_transpiled(...)`, pipeline creation, and hot-reload wiring.

4. `Brush_Controller`
- Shared mouse-to-UV / UV-to-cell mapping, Y-flip policy, drag stamping, and edge-trigger stamping logic.
- Avoid app-specific input bugs and repeated code.

5. `FrameGraph_Lite` for demos
- Tiny pass API (`compute_pass`, `render_pass`) that owns pass ordering and transitions.
- Keeps app `tick` functions focused on simulation behavior.

## Ergonomic Iteration Improvements

1. App template generator
- `tools/new_app.jai --type compute2d` to generate app file, shader file, initial wiring, and `app_list` entry.

2. Live parameter registry
- Declare tunables once; auto-generate ImGui controls.
- Optional persistence to file for per-app defaults.

3. Standard debug overlays
- Reusable FPS/GPU ms/sim stats/brush mode/cell-under-cursor overlays.

4. Deterministic debug mode
- Optional fixed-step + seeded randomness mode for reproducible runs.

5. Snapshot scenario hooks
- Per-app `seed_scenario("interesting_start")` for docs capture and quick smoke visuals.

## Suggested Rollout

1. Build `modules/Prototype2D/` with:
- `ComputeViewer`
- `BrushController`
- `ParamRegistry`

2. Pilot migration:
- Convert `sand_toy` first.
- Validate reduced code size and faster tuning loop.

3. Expand:
- Migrate `ripple_heightfield` and `fluid2d`.
- Keep app-specific simulation rules local, move only shared plumbing.
