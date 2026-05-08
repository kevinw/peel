# Meshlet Perf Notes

## Current Read

The `model_scene` meshlet path is probably slower than `shipagame` for reasons beyond `task_threads = .[1, 1, 1]`.

Both renderers already batch up to 64 meshlets per task invocation:

- `shipagame`: meshlet renderer batches meshlets per task/object chunk.
- `model_scene`: `TASK_EMIT_MESHLET_COUNT = 64` and `task_set_mesh_groups(emit_meshlet_count, 1, 1)`.

So the likely issue is not "we forgot to batch meshlets". The likely issue is that `model_scene` is doing much more work around each emitted meshlet.

## Likely Causes

1. Heavier fragment/material path in `model_scene`.
`model_scene` samples base color, opacity, normal, roughness, AO, and shadow map taps, and also carries debug/shadow branches.
`shipagame` appears materially simpler.

2. More fragmented draw submission in `model_scene`.
`model_scene` loops over many scene batches and issues many `gpu_draw_meshlets` calls with per-batch/per-draw params.
`shipagame` looks more like a single renderer-oriented path.

3. Extra animation overhead in `model_scene`.
`model_scene` supports skinning, morphs, dynamic/static instance partitioning, player runtime, mediapipe runtime, and scene-driven batch setup.

4. Scalar task and mesh shaders in `model_scene`.
The task shader is one-thread-per-object-chunk.
The mesh shader is also scalar and loops over all meshlet vertices/triangles in one lane.
This is real under-parallelization, but it may not be the first-order bottleneck.

5. Double culling work in `model_scene`.
The task shader culls an object/LOD chunk sphere first, then the mesh shader culls each emitted meshlet sphere again.

## First Measurements To Run

1. Disable shadows in `model_scene` and compare FPS.
If FPS jumps, fragment shading and shadow sampling are dominant.

2. Add a flat-material debug mode for meshlets.
Skip normal/AO/roughness/opacity sampling and compare against full shading.

3. Compare meshlet path vs regular indexed draw path for the same scene content.
This helps separate "meshlet implementation overhead" from "scene/material complexity".

4. Count `gpu_draw_meshlets` calls and average `draw_object_group_count`.
Small fragmented draws may be a major part of the gap.

5. Check whether the slow draws are concentrated in alpha-masked or rock/material-heavy batches.

## If The Bottleneck Is Shader Structure

If the shading-side profiling says the task/mesh pipeline itself is the problem, then the next structural changes to test are:

1. Increase task-stage parallelism.
Move from one scalar task thread per object chunk toward cooperative task work.

2. Increase mesh-stage parallelism.
Stop having one mesh thread loop all vertices/triangles for a meshlet.

3. Reduce per-draw parameter traffic.
Look for batch parameters that can move out of the hottest draw path.

4. Revisit culling split.
Check whether object/chunk culling plus per-meshlet culling is worth the extra scalar work.

## Current Hypothesis

Most likely causes, in order:

1. Heavier fragment/material work in `model_scene`.
2. More fragmented draw submission.
3. Animation/morph/skinning overhead.
4. Only after that, lack of intra-task / intra-mesh parallelization.
