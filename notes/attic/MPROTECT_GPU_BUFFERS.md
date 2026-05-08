# Mprotect GPU Buffers

This is a debug-only plan for catching frame-in-flight CPU writes into GPU-visible shared memory.

## Goal

Turn silent frame-ring stomps into immediate deterministic faults.

The target bug class is:

- frame `N` submits GPU work using CPU-mapped shared memory
- CPU starts writing that same frame slot again before GPU completion
- result is visible corruption unless a global `gpu_wait_idle()` hides it

The proposed debug trick is:

- after submitting a frame, mark that frame slot's CPU pages inaccessible with `mprotect`
- when the GPU has completed that frame, unprotect those pages

Then stale CPU reads/writes into in-flight memory fault immediately.

## First Scope

Start with:

- `Gpu_Frame_Param_Allocator`
- `Gpu_Frame_Ring`

in:

- [/Users/kev/src/peel/src/GPU_Tools.jai](/Users/kev/src/peel/src/GPU_Tools.jai)

Do not start with:

- whole arenas
- arbitrary `gpu_alloc_buffer`
- readback buffers
- GPU-only textures

The frame allocators already have explicit slot ownership semantics, so they are the best first target.

## Core Design

Add a debug tracker for CPU-visible frame-ring allocators.

Conceptually:

```jai
Debug_Protected_Frame_Ring :: struct {
    base: *u8;
    page_aligned_frame_stride: s64;
    protected_frame_numbers: [SGPU_FRAMES_IN_FLIGHT] s64;
    is_protected: [SGPU_FRAMES_IN_FLIGHT] bool;
    label: string;
}
```

Then extend `Gpu_Frame_Param_Allocator` with debug-only bookkeeping:

- CPU base pointer
- page-aligned per-frame stride
- tracker state
- optional label

## Allocation Strategy

`mprotect` operates on pages, so frame slots must not share pages.

In debug protect mode:

- each frame region must begin on a page boundary
- each frame region must be rounded up to page size

For `Gpu_Frame_Param_Allocator`, the protected region should be the whole per-frame slice:

- `slots_per_frame * size_of(T)`

rounded up to page size.

That means debug mode allocation becomes:

- `SGPU_FRAMES_IN_FLIGHT * page_aligned_frame_stride`

instead of the current compact contiguous layout.

This increases memory usage, but only in the debug configuration.

## Protect / Unprotect Lifecycle

### On Allocator Init

In:

- [/Users/kev/src/peel/src/GPU_Tools.jai](/Users/kev/src/peel/src/GPU_Tools.jai)

when creating `Gpu_Frame_Param_Allocator`:

- if debug protect mode is enabled:
  - allocate page-aligned frame regions
  - initialize tracker state
  - leave all regions writable

### On Frame Allocation

In:

- `sgpu_frame_param_alloc(...)`

before handing out a slot:

- retire any completed protected frames
- assert that the current frame region is not still protected

If it is still protected, hard-fail with:

- allocator label
- current frame number
- completed GPU frame number
- ring slot index

That catches accidental reuse immediately.

### On Frame Submit

After a frame is submitted/presented:

- protect the CPU-visible region for `frame_index % SGPU_FRAMES_IN_FLIGHT`

Good hook point:

- [/Users/kev/src/peel/modules/sgpu/backend_metal/swapchain.jai](/Users/kev/src/peel/modules/sgpu/backend_metal/swapchain.jai)

Add a small debug callback such as:

```jai
sgpu_debug_on_frame_submitted(frame_index);
```

This should mark all tracked allocator regions for that frame slot as inaccessible.

### On Completion Retirement

Use:

- `gpu_completed_submission_frame_index()`

to reopen any frame regions whose submitted frame is now complete.

Simple first implementation:

- call `sgpu_debug_retire_protected_frames()` at the start of `sgpu_frame_param_alloc(...)`

This keeps the bookkeeping localized and avoids needing a separate render-loop callback.

## OS Primitive

On macOS, use:

- `mprotect(ptr, len, PROT_NONE)` to protect
- `mprotect(ptr, len, PROT_READ | PROT_WRITE)` to unprotect

Use `PROT_NONE`, not just read-only. A read fault is also valuable signal in this mode.

## Suggested File Split

Keep the first version small.

Possible helper file:

- [/Users/kev/src/peel/src/sgpu_debug_memory.jai](/Users/kev/src/peel/src/sgpu_debug_memory.jai)

Responsibilities:

- register tracked frame rings
- protect submitted frame regions
- retire completed frame regions
- page-size helpers
- `mprotect` wrappers

Then:

- `GPU_Tools.jai` owns allocator integration
- `swapchain.jai` owns submit notification

## Suggested Flag

Add a debug-only flag, for example:

- `SGPU_DEBUG_PROTECT_IN_FLIGHT_CPU_MEMORY`

This can be:

- a module parameter
- an env-var override
- or both

Recommended behavior:

- off by default
- hard-fail once enabled

## Good Failure Behavior

When a protected region is touched:

- crash immediately
- if possible, log the allocator label and submitted frame just before protection

The ideal result is:

- instead of a blocky or flickering framebuffer
- you get a deterministic repro tied to a specific frame-ring allocator

## Why This Is Useful

This would have caught the recent `blender_scene` bugs cleanly:

- single depth target was not ringed
- single HDRI params buffer was not ringed

The first is a texture attachment issue and not directly handled by `mprotect`, but the second is exactly the kind of CPU-mapped transient buffer hazard this mode is meant to catch.

It will also help catch future bugs in:

- frame param allocators
- upload rings
- other shared CPU-visible transient buffers

without requiring a global `gpu_wait_idle()`.

## Recommended First Implementation

1. Add debug tracking for `Gpu_Frame_Param_Allocator`.
2. Allocate page-aligned per-frame regions in debug mode.
3. Protect submitted frame regions with `mprotect(PROT_NONE)`.
4. Unprotect completed frame regions when `gpu_completed_submission_frame_index()` advances.
5. Assert in `sgpu_frame_param_alloc(...)` if the requested frame slot is still protected.

That is the smallest useful slice.
