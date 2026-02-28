using JPH :: #import,file "./module.jai"; // import JoltC
#import "Basic";

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

main :: () {
    if !JPH.Init() {
        log_error("Failed to initialize JoltC");
        exit(1);
    }

    JPH.SetTraceHandler((msg_cstr: *u8) #c_call {
        push_context {
            log("JoltC: %", msg_cstr);
        }
    });

    job_system := JPH.JobSystemThreadPool_Create(null);

	// We use only 2 layers: one for non-moving objects and one for moving objects
	objectLayerPairFilterTable := ObjectLayerPairFilterTable_Create(2);
	ObjectLayerPairFilterTable_EnableCollision(objectLayerPairFilterTable, Layers.NON_MOVING, Layers.MOVING);
	ObjectLayerPairFilterTable_EnableCollision(objectLayerPairFilterTable, Layers.MOVING, Layers.NON_MOVING);

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

    system := PhysicsSystem_Create(*settings);
    bodyInterface := PhysicsSystem_GetBodyInterface(system);

    floorId: BodyID;
    {
        // Next we can create a rigid body to serve as the floor, we make a large box
        // Create the settings for the collision volume (the shape). 
        // Note that for simple shapes (like boxes) you can also directly construct a BoxShape.
        boxHalfExtents := JPH.Vec3.{100.0, 1.0, 100.0};
        floorShape := BoxShape_Create(*boxHalfExtents, JPH_DEFAULT_CONVEX_RADIUS);

        floorPosition := JPH.Vec3.{0.0, -1.0, 0.0};
        floorSettings := BodyCreationSettings_Create3(
            xx floorShape,
            *floorPosition,
            null, // identity
            .Static,
            Layers.NON_MOVING
        );

        // Create the actual rigid body
        floorId = BodyInterface_CreateAndAddBody(bodyInterface, floorSettings, .DontActivate);
        BodyCreationSettings_Destroy(floorSettings);
    }

    // sphere
    sphereId: BodyID;
    {
        sphereShape := SphereShape_Create(50.0);
        spherePosition := JPH.Vec3.{0.0, 2.0, 0.0};
        sphereSettings := BodyCreationSettings_Create3(
            xx sphereShape,
            *spherePosition,
            null, // identity
            .Dynamic,
            Layers.MOVING
        );

        sphereId = BodyInterface_CreateAndAddBody(bodyInterface, sphereSettings, .Activate);
        BodyCreationSettings_Destroy(sphereSettings);
    }

    // Now you can interact with the dynamic body, in this case we're going to give it a velocity.
    // (note that if we had used CreateBody then we could have set the velocity straight on the body before adding it to the physics system)
    sphereLinearVelocity := JPH.Vec3.{0.0, -5.0, 0.0};
    BodyInterface_SetLinearVelocity(bodyInterface, sphereId, *sphereLinearVelocity);

    {
        cCharacterHeightStanding :: 1.35;
        cCharacterRadiusStanding :: 0.3;
        cCharacterHeightCrouching :: 0.8;
        cCharacterRadiusCrouching :: 0.3;
        cInnerShapeFraction :: 0.9;

        capsuleShape := CapsuleShape_Create(0.5 * cCharacterHeightStanding, cCharacterRadiusStanding);
        position := Vec3.{0, 0.5 * cCharacterHeightStanding + cCharacterRadiusStanding, 0};
        
        standingShape := RotatedTranslatedShape_Create(*position, null, xx capsuleShape);

        characterSettings: CharacterVirtualSettings;
        CharacterVirtualSettings_Init(*characterSettings);
        characterSettings.base.shape = xx standingShape;
        characterSettings.base.supportingVolume = Plane.{.{0, 1, 0}, -cCharacterRadiusStanding}; // Accept contacts that touch the lower sphere of the capsule
        characterVirtualPosition := RVec3.{-5.0, 0, 3.0};

        animatedCharacterVirtual := CharacterVirtual_Create(*characterSettings, *characterVirtualPosition, null, 0, system);
    }

    jointSettings: SixDOFConstraintSettings;
    SixDOFConstraintSettings_Init(*jointSettings);

    // We simulate the physics world in discrete time steps. 60 Hz is a good rate to update the physics system.
    cDeltaTime :: 1.0 / 60.0;

    // Optional step: Before starting the physics simulation you can optimize the broad phase. This improves collision detection performance (it's pointless here because we only have 2 bodies).
    // You should definitely not call this every frame or when e.g. streaming in a new level section as it is an expensive operation.
    // Instead insert all new objects in batches instead of 1 at a time to keep the broad phase efficient.
    PhysicsSystem_OptimizeBroadPhase(system);

    // Now we're ready to simulate the body, keep simulating until it goes to sleep
    step := 0;
    while BodyInterface_IsActive(bodyInterface, sphereId) {
        // Next step
        step += 1;

        // Output current position and velocity of the sphere
        position: RVec3;
        velocity: Vec3;

        BodyInterface_GetCenterOfMassPosition(bodyInterface, sphereId, *position);
        BodyInterface_GetLinearVelocity(bodyInterface, sphereId, *velocity);
        log("Step %: Position = (%, %, %), Velocity = (%, %, %)\n", step, position.x, position.y, position.z, velocity.x, velocity.y, velocity.z);

        // If you take larger steps than 1 / 60th of a second you need to do multiple collision steps in order to keep the simulation stable. Do 1 collision step per 1 / 60th of a second (round up).
        cCollisionSteps :: 1;

        // Step the world
        PhysicsSystem_Update(system, cDeltaTime, cCollisionSteps, job_system);
    }

    // Remove the destroy sphere from the physics system. Note that the sphere itself keeps all of its state and can be re-added at any time.
    BodyInterface_RemoveAndDestroyBody(bodyInterface, sphereId);

    // Remove and destroy the floor
    BodyInterface_RemoveAndDestroyBody(bodyInterface, floorId);

    JobSystem_Destroy(job_system);

    PhysicsSystem_Destroy(system);
    Shutdown();
}
