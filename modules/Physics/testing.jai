next_spawn_timer: float;

world: struct {
    // dummy data! testing.
    spheres: [..]struct {
        pos: Vector3;
        rot: Quaternion;
        radius: float;
        body_id: BodyID;
    };
};

random_sphere :: () -> pos: Vec3, radius: float {
    W :: 10.0;
    return .{
        random_get_zero_to_one() * W - W * 0.5,
        30.0 - random_get_zero_to_one() * 20.0,
        random_get_zero_to_one() * W - W * 0.5,
    }, 0.15 + random_get_zero_to_one() * 0.2;
}


update_test_environment :: (dt: float) {
    using physics;
    next_spawn_timer -= dt;
    if next_spawn_timer <= 0.0 {
        next_spawn_timer += 3.0;
        spawn_sphere();
    }
}

spawn_sphere :: () {
    using physics;
    using body_interface;

    pos, radius := random_sphere();
    sphereShape := SphereShape_Create(radius);
    log("Spawning sphere at %", pos);
    sphereSettings := BodyCreationSettings_Create3(sphereShape, *pos, null, .Dynamic, Layers.MOVING);
    defer  BodyCreationSettings_Destroy(sphereSettings);
    BodyInterface_CreateAndAddBody(body_interface, sphereSettings, .Activate);
}

init_test_environment :: () {
    using physics;

    floorId: BodyID;
    {
        boxHalfExtents := Vec3.{15.0, 1.0, 15.0};
        shape := BoxShape_Create(*boxHalfExtents, JPH_DEFAULT_CONVEX_RADIUS);
        pos := Vec3.{0.0, -1.0, 0.0};
        s := BodyCreationSettings_Create3(shape, *pos, null /*identity*/, .Static, Layers.NON_MOVING);
        defer BodyCreationSettings_Destroy(s);
        floorId = BodyInterface_CreateAndAddBody(body_interface, s, .DontActivate);
    }

    {
        boxHalfExtents := Vec3.{1.0, 1.0, 1.0};
        shape := BoxShape_Create(*boxHalfExtents, JPH_DEFAULT_CONVEX_RADIUS);
        pos := Vec3.{3.0, 1.0, -2.0};
        s := BodyCreationSettings_Create3(shape, *pos, null /*identity*/, .Static, Layers.NON_MOVING);
        defer BodyCreationSettings_Destroy(s);
        floorId = BodyInterface_CreateAndAddBody(body_interface, s, .DontActivate);
    }

    // create many spheres
    array_reset(*world.spheres);
    for 0..30 {
        spherePosition, radius := random_sphere();
        sphereShape := SphereShape_Create(radius);
        sphereSettings := BodyCreationSettings_Create3(sphereShape, *spherePosition, null /*identity*/, .Dynamic, Layers.MOVING);
        defer BodyCreationSettings_Destroy(sphereSettings);
        array_add(*world.spheres, {
            pos     = cast,force(Vector3)spherePosition,
            radius  = radius,
            body_id = BodyInterface_CreateAndAddBody(body_interface, sphereSettings, .Activate),
        });
    }

    PhysicsSystem_OptimizeBroadPhase(system);
}

#scope_file
#import "JoltC";
#import "JoltC_extra";
#import "Random";
