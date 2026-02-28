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
        //drawShape = true;
        //drawShapeWireframe = true;
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
debug_draw_enabled := false;
#load "./debug_renderer.jai";
#load "./testing.jai";
JPH :: #import "JoltC";
using JPH;
#import "Basic";
#import "Math";
