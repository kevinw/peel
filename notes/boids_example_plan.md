# Boids Example Plan

Goal: build a compute-driven instanced boids sample that also acts as a transpiler feature testbed.

## Milestones

- [x] Milestone 0: app skeleton in `src/apps` with static mesh draw.
- [x] Milestone 1: static instancing with CPU-authored `InstanceData`.
- [ ] Milestone 2: transpiler builtin support for `@instance_id` (and optional `@vertex_id`) across target backends.
- [ ] Milestone 3: vertex-stage access to per-instance storage buffer data.
- [ ] Milestone 4: compute pass updates `InstanceData` each frame.
- [ ] Milestone 5: visual polish without materials/textures/lighting (speed tint, subtle variation).
- [ ] Milestone 6: transpiler regression tests and backend smoke checks.
- [ ] Stretch: compute-written indirect draw arguments.

## Milestone 0 Scope

- New app file in `src/apps`.
- Lifecycle hooks wired (`@on_dll_init`, `@on_tick`).
- Graphics pipeline + GPU arena setup.
- One static indexed mesh rendered each frame.
- No compute, no instancing logic yet.

## Notes

- Keep shader usage simple for Milestone 0 by reusing existing square shaders.
- Milestone 1 will change geometry/data layout toward boids-style instancing.
