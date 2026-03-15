debug_draw_enabled := false;

Layers :: struct {
    NON_MOVING :: 0;
    MOVING     :: 1;
    NUM_LAYERS :: 2;
}

BroadPhaseLayers :: struct {
    NON_MOVING : BroadPhaseLayer : 0;
    MOVING     : BroadPhaseLayer : 1;
    NUM_LAYERS :: 2;
}

set_debug_draw_procs :: () {
    using physics.debug;

    log("set_debug_draw_procs");
    ctx = context; // Save the current context for use in #c_call callbacks.
    
    DebugRenderer_SetProcs(*debug_renderer_procs);

    SetTraceHandler((msg_cstr: *u8) #c_call {
        push_renderer_ctx(*physics.debug.ctx);
        log("JoltC: %", to_string(msg_cstr));
    });

    SetAssertFailureHandler((expression: *u8, msg_cstr: *u8, file: *u8, line: u32) -> bool #c_call {
        push_renderer_ctx(*physics.debug.ctx);
        log_error("JoltC Assert failed: %", to_string(msg_cstr));
        log_error("Expression: %", to_string(expression));
        log_error("File: %, Line: %", to_string(file), line);
        return true;
    });
} @on_reload

init :: () {
    using physics;
    did_init := JPH.Init();
    assert(did_init, "Failed to initialize JoltC");

    job_system = JobSystemThreadPool_Create(null);

	// We use only 2 layers: one for non-moving objects and one for moving objects
	objectLayerPairFilterTable := ObjectLayerPairFilterTable_Create(2);
	ObjectLayerPairFilterTable_EnableCollision(objectLayerPairFilterTable, Layers.NON_MOVING, Layers.MOVING);
	ObjectLayerPairFilterTable_EnableCollision(objectLayerPairFilterTable, Layers.MOVING, Layers.NON_MOVING);
	ObjectLayerPairFilterTable_EnableCollision(objectLayerPairFilterTable, Layers.MOVING, Layers.MOVING);

	// We use a 1-to-1 mapping between object layers and broadphase layers
	broadPhaseLayerInterfaceTable := BroadPhaseLayerInterfaceTable_Create(2, 2);
	BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterfaceTable, Layers.NON_MOVING, BroadPhaseLayers.NON_MOVING);
	BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterfaceTable, Layers.MOVING, BroadPhaseLayers.MOVING);

    objectVsBroadPhaseLayerFilter := ObjectVsBroadPhaseLayerFilterTable_Create(broadPhaseLayerInterfaceTable, 2, objectLayerPairFilterTable, 2);

    settings := PhysicsSystemSettings.{
        maxBodies = 65536,
        numBodyMutexes = 0,
        maxBodyPairs = 65536,
        maxContactConstraints = 65536,
        broadPhaseLayerInterface = broadPhaseLayerInterfaceTable,
        objectLayerPairFilter = objectLayerPairFilterTable,
        objectVsBroadPhaseLayerFilter = objectVsBroadPhaseLayerFilter,
    };

    system = PhysicsSystem_Create(*settings);
    body_interface = PhysicsSystem_GetBodyInterface(system);

    // Initialize debug renderer and context.
    {
        using debug;
        renderer = DebugRenderer_Create(*ctx);
        body_draw_filter = BodyDrawFilter_Create(*ctx);
        DrawSettings_InitDefault(*draw_settings);
        using draw_settings;
        drawShape = true;
        drawShapeWireframe = true;
    }

    set_debug_draw_procs();
    init_test_environment();
}

tick :: (dt: float32) {
    using physics;
    
    update_test_environment(dt);
    
    // We simulate the physics world in discrete time steps. 60 Hz is a good rate to update the physics system.
    FIXED_TIMESTEP :: 1.0 / 60.0;

    // If you take larger steps than 1 / 60th of a second you need to do multiple collision steps in order to keep the simulation stable. Do 1 collision step per 1 / 60th of a second (round up).
    COLLISION_STEPS :: 1;

    accumulator += dt;
    while accumulator >= FIXED_TIMESTEP {
        accumulator -= FIXED_TIMESTEP;
        PhysicsSystem_Update(system, FIXED_TIMESTEP, COLLISION_STEPS, job_system);
    }

    bi := PhysicsSystem_GetBodyInterfaceNoLock(system);
    for * world.spheres {
        it.pos = cast,force(Vector3)BodyInterface_GetPosition(bi, it.body_id);
        it.rot = cast,force(Quaternion)BodyInterface_GetRotation(bi, it.body_id);
    }

    if debug_draw_enabled {
        using debug;
        PhysicsSystem_DrawBodies(system, *draw_settings, renderer, body_draw_filter);
    }
}

deinit :: () {
    using physics;

    if job_system {
        JobSystem_Destroy(job_system);
        job_system = null;
    }

    if system {
        PhysicsSystem_Destroy(system);
        system = null;
    }

    {
        using debug;
        if body_draw_filter {
            BodyDrawFilter_Destroy(body_draw_filter);
            body_draw_filter = null;
        }
        if renderer {
            DebugRenderer_Destroy(renderer);
            renderer = null;
        }
        ctx = .{};
    }

    JPH.Shutdown();
}

Collider_Shape :: struct {
    handle: *void;
}

create_static_heightfield :: (samples: []float, sample_count: u32, offset: Vector3, scale: Vector3) -> BodyID {
    using physics;
    assert(system != null && body_interface != null, "Physics must be initialized before creating a heightfield.");
    assert(sample_count > 1, "Heightfield sample_count must be > 1.");
    assert(samples.count == cast(s64) sample_count * cast(s64) sample_count,
        "Heightfield sample count mismatch: expected %, got %.",
        cast(s64) sample_count * cast(s64) sample_count, samples.count);

    offset_jph := cast,force(Vec3) offset;
    scale_jph := cast,force(Vec3) scale;
    settings := HeightFieldShapeSettings_Create(samples.data, *offset_jph, *scale_jph, sample_count, null);
    assert(settings != null, "HeightFieldShapeSettings creation failed.");
    defer ShapeSettings_Destroy(cast(*ShapeSettings) settings);

    shape := HeightFieldShapeSettings_CreateShape(settings);
    assert(shape != null, "HeightFieldShape creation failed.");
    defer Shape_Destroy(cast(*Shape) shape);

    zero_pos := Vec3.{0.0, 0.0, 0.0};
    body_settings := BodyCreationSettings_Create3(cast(*Shape) shape, *zero_pos, null, .Static, Layers.NON_MOVING);
    assert(body_settings != null, "Heightfield body settings creation failed.");
    defer BodyCreationSettings_Destroy(body_settings);

    return BodyInterface_CreateAndAddBody(body_interface, body_settings, .DontActivate);
}

create_mesh_shape :: (vertices: []Vector3, indices: []u32) -> Collider_Shape {
    using physics;
    assert(system != null && body_interface != null, "Physics must be initialized before creating a mesh shape.");
    assert(indices.count % 3 == 0, "Mesh collider index count must be divisible by 3.");

    verts: [..]Vec3;
    tris: [..]IndexedTriangle;
    verts.allocator = temp;
    tris.allocator = temp;
    array_reserve(*verts, vertices.count);
    array_reserve(*tris, indices.count / 3);

    for vertices array_add(*verts, cast,force(Vec3) it);
    tri_count := indices.count / 3;
    for tri_index: 0..tri_count-1 {
        base := tri_index * 3;
        array_add(*tris, .{
            i1 = indices[base + 0],
            i2 = indices[base + 1],
            i3 = indices[base + 2],
            materialIndex = 0,
            userData = 0,
        });
    }

    settings := MeshShapeSettings_Create2(verts.data, cast(u32) verts.count, tris.data, cast(u32) tris.count);
    assert(settings != null, "MeshShapeSettings creation failed.");
    defer ShapeSettings_Destroy(cast(*ShapeSettings) settings);
    MeshShapeSettings_Sanitize(settings);

    shape := MeshShapeSettings_CreateShape(settings);
    assert(shape != null, "MeshShape creation failed.");
    return .{handle = cast(*void) shape};
}

create_scaled_shape :: (base_shape: Collider_Shape, scale: Vector3) -> Collider_Shape {
    assert(base_shape.handle != null, "Base collider shape is null.");
    scale_jph := cast,force(Vec3) scale;
    shape := ScaledShape_Create(cast(*Shape) base_shape.handle, *scale_jph);
    assert(shape != null, "ScaledShape creation failed.");
    return .{handle = cast(*void) shape};
}

create_static_body_from_shape :: (shape: Collider_Shape, position: Vector3, rotation: Quaternion) -> BodyID {
    using physics;
    assert(system != null && body_interface != null, "Physics must be initialized before creating a body.");
    assert(shape.handle != null, "Collider shape is null.");

    pos_jph := cast,force(Vec3) position;
    rot_jph := cast,force(Quat) rotation;
    body_settings := BodyCreationSettings_Create3(cast(*Shape) shape.handle, *pos_jph, *rot_jph, .Static, Layers.NON_MOVING);
    assert(body_settings != null, "Static body settings creation failed.");
    defer BodyCreationSettings_Destroy(body_settings);
    return BodyInterface_CreateAndAddBody(body_interface, body_settings, .DontActivate);
}

destroy_shape :: (shape: *Collider_Shape) {
    if shape.handle == null return;
    Shape_Destroy(cast(*Shape) shape.handle);
    shape.handle = null;
}

destroy_body :: (body_id: BodyID) {
    using physics;
    if body_interface == null return;
    BodyInterface_RemoveAndDestroyBody(body_interface, body_id);
}

push_renderer_ctx :: (user_data: *void) #expand {
    ctx := cast(*#Context)user_data;

    ctx_without_stack_trace := ctx.*;
    ctx_without_stack_trace.stack_trace = null;
    `push_context,defer_pop ctx_without_stack_trace;
}

physics: struct {
    job_system:     *JobSystem;
    system:         *PhysicsSystem;
    body_interface: *BodyInterface;
    accumulator:    float32;

    debug: struct {
        ctx:              #Context;
        body_draw_filter: *BodyDrawFilter;
        renderer:         *DebugRenderer;
        draw_settings:    DrawSettings;
    };
}

#scope_file
#load "./debug_renderer.jai";
#load "./testing.jai";
JPH :: #import "JoltC";
using JPH;
#import "Basic";
#import "Math";
