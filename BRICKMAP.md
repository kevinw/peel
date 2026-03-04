# Brickmap Raymarcher Plan

Based on http://www.youtube.com/watch?v=il-TXbn5iMA

Based on the techniques detailed by Mike Turitzin in the video, building a dynamic, high-performance SDF (Signed Distance Field) engine requires shifting away from traditional brute-force raymarching. Instead, the core concept revolves around caching distance values in a sparse data structure and dynamically updating only the regions that change.

Here is a step-by-step implementation plan for prototyping your own brick map SDF raymarcher:

## Phase 1: Core SDF Evaluation & Scene Representation

Before building the caching system, you need a way to mathematically define your world.

Define SDF Edits: Represent your scene as an ordered list of "SDF edits" [03:24]. An edit consists of a shape (sphere, box, capsule), a transform (position, rotation, scale), and a boolean operation (union, subtraction, intersection, smooth blending).

Construct the Distance Function: Write the math to evaluate the final distance for any given point in space by combining all these edits.
(Optional) Build a basic, brute-force raymarcher first just to verify your math is working before introducing the complexity of the grid.

## Phase 2: Sparse Caching via Brick Maps

Evaluating the entire scene's SDF per pixel is too slow [03:51]. To fix this, you will cache distance values on a grid.

The Texture Atlas: Create a large 3D texture on the GPU to act as a memory pool. This will store chunks of distance values [09:47]. Because you only need distances near the surface, you can heavily compress these values (e.g., storing them as single 8-bit integers) [08:03].

Define "Bricks": Subdivide space into small blocks (the video uses 8x8x8 grids per brick) [10:08].

The Brick Map (Pointer Grid): Create a coarser dense grid that acts as a lookup table [09:32]. Each cell in this pointer grid either points to a specific 8x8x8 brick allocated in your 3D texture atlas or is flagged as empty.

Sparse Allocation: When evaluating the scene, only allocate a brick in the texture atlas if the grid cell actually contains the SDF surface (meaning it has both positive and negative distance values) [08:48].

## Phase 3: Raymarching & Trilinear Interpolation

Now that your data is cached, you need to write a custom raymarcher to render it.

Grid Traversal: Instead of stepping blindly, your raymarcher should query the coarse pointer grid. If a cell is empty, the ray can safely jump over it.

Trilinear Reconstruction: When the ray hits a populated brick, do not evaluate the complex mathematical SDF. Instead, fetch the 8 nearest cached distance values from your 3D texture atlas and use trilinear interpolation (which can be done via a single GPU texture fetch) to approximate the distance to the curve [05:42].

Surface Reconstruction: This interpolation natively yields a smooth, complex topology without needing to render actual triangles [07:28].

## Phase 4: Level of Detail (LOD) using Geometry Clip Maps

A uniform grid will consume too much memory for large open worlds. You must introduce LOD to scale the resolution based on camera distance [11:13].

Nested Grids: Implement "Geometry Clip Maps" [11:41]. Instead of one brick map, create a cascade of nested grids centered on the player.

Scaling Resolutions: Each successive grid level should double in physical size and cell dimensions. This naturally enforces that the SDF is evaluated at much coarser resolutions the further away it is from the camera, radically reducing memory footprint [12:33].

## Phase 5: Fast Dynamic Updates via a BVH

The primary goal of this engine architecture is to allow non-destructive, dynamic edits in real-time [13:02].

AABB Tree Structure: Track all of your SDF edits spatially using a Bounding Volume Hierarchy (BVH), specifically a tree of Axis-Aligned Bounding Boxes (AABBs) [13:16]. Share this data structure between the CPU and GPU.

Incremental Regeneration: When an edit moves, is added, or is deleted, query your BVH to find exactly which bricks in space intersect with the bounding box of that change.

Targeted Re-evaluation: Re-evaluate and update the cached distances only for those specific bricks in the texture atlas, rather than recalculating the whole world [14:01].

## Phase 6: Physics Integration (Optional)

If you want gameplay, raymarching alone won't give you collision detection.

Marching Cubes on CPU: Run the Marching Cubes algorithm across multiple CPU threads using your cached distance grid to generate a low-resolution collision mesh [14:58].

Physics Engine Integration: Feed this generated mesh in chunks to an off-the-shelf physics engine (like Jolt Physics) to handle realistic collisions with your dynamic world [15:27].
