#scope_export

Character_Collision_Layers :: struct {
    NON_MOVING :: 0;
    MOVING     :: 1;
    NUM_LAYERS :: 2;
}

Character_Broad_Phase_Layers :: struct {
    NON_MOVING : BroadPhaseLayer : 0;
    MOVING     : BroadPhaseLayer : 1;
    NUM_LAYERS :: 2;
}

Character_Physics_World :: struct {
    job_system: *JobSystem;
    system: *PhysicsSystem;
    body_interface: *BodyInterface;
    object_layer_pair_filter: *ObjectLayerPairFilter;
    broad_phase_layer_interface: *BroadPhaseLayerInterface;
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter;
    floor_body: BodyID;
    accumulator: float;
}

DEFAULT_WALK_SPEED :: 4.15;

Character_Controller :: struct {
    character: *CharacterVirtual;
    shape: *Shape;
    facing_yaw: float;
    visual_yaw_offset: float;
    walk_speed: float = DEFAULT_WALK_SPEED;
    accel: float = 9.0;
    animation_time: float;
    animation_blend: float;
}

character_physics_init :: (world: *Character_Physics_World, floor_half_extents: Vector3 = .{24.0, 1.0, 24.0}, floor_center: Vector3 = .{0.0, -1.0, 0.0}) {
    did_init := JPH.Init();
    assert(did_init, "Failed to initialize JoltC for character world.");

    world.job_system = JobSystemThreadPool_Create(null);
    assert(world.job_system != null, "Character world job system creation failed.");

    world.object_layer_pair_filter = ObjectLayerPairFilterTable_Create(Character_Collision_Layers.NUM_LAYERS);
    ObjectLayerPairFilterTable_EnableCollision(world.object_layer_pair_filter, Character_Collision_Layers.NON_MOVING, Character_Collision_Layers.MOVING);
    ObjectLayerPairFilterTable_EnableCollision(world.object_layer_pair_filter, Character_Collision_Layers.MOVING, Character_Collision_Layers.NON_MOVING);
    ObjectLayerPairFilterTable_EnableCollision(world.object_layer_pair_filter, Character_Collision_Layers.MOVING, Character_Collision_Layers.MOVING);

    world.broad_phase_layer_interface = BroadPhaseLayerInterfaceTable_Create(Character_Collision_Layers.NUM_LAYERS, Character_Broad_Phase_Layers.NUM_LAYERS);
    BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(world.broad_phase_layer_interface, Character_Collision_Layers.NON_MOVING, Character_Broad_Phase_Layers.NON_MOVING);
    BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(world.broad_phase_layer_interface, Character_Collision_Layers.MOVING, Character_Broad_Phase_Layers.MOVING);

    world.object_vs_broad_phase_layer_filter = ObjectVsBroadPhaseLayerFilterTable_Create(
        world.broad_phase_layer_interface,
        Character_Broad_Phase_Layers.NUM_LAYERS,
        world.object_layer_pair_filter,
        Character_Collision_Layers.NUM_LAYERS);

    settings := PhysicsSystemSettings.{
        maxBodies = 4096,
        numBodyMutexes = 0,
        maxBodyPairs = 4096,
        maxContactConstraints = 4096,
        broadPhaseLayerInterface = world.broad_phase_layer_interface,
        objectLayerPairFilter = world.object_layer_pair_filter,
        objectVsBroadPhaseLayerFilter = world.object_vs_broad_phase_layer_filter,
    };

    world.system = PhysicsSystem_Create(*settings);
    assert(world.system != null, "Character world physics system creation failed.");
    world.body_interface = PhysicsSystem_GetBodyInterface(world.system);
    assert(world.body_interface != null, "Character world body interface creation failed.");

    floor_half_extents_jph := cast,force(Vec3) floor_half_extents;
    floor_center_jph := cast,force(Vec3) floor_center;
    floor_shape := BoxShape_Create(*floor_half_extents_jph, JPH_DEFAULT_CONVEX_RADIUS);
    floor_settings := BodyCreationSettings_Create3(
        floor_shape,
        *floor_center_jph,
        null,
        .Static,
        Character_Collision_Layers.NON_MOVING);
    defer BodyCreationSettings_Destroy(floor_settings);
    world.floor_body = BodyInterface_CreateAndAddBody(world.body_interface, floor_settings, .DontActivate);

    PhysicsSystem_OptimizeBroadPhase(world.system);
}

character_physics_tick :: (world: *Character_Physics_World, dt: float) {
    FIXED_TIMESTEP :: 1.0 / 60.0;
    COLLISION_STEPS :: 1;

    world.accumulator += dt;
    while world.accumulator >= FIXED_TIMESTEP {
        world.accumulator -= FIXED_TIMESTEP;
        PhysicsSystem_Update(world.system, FIXED_TIMESTEP, COLLISION_STEPS, world.job_system);
    }
}

character_physics_deinit :: (world: *Character_Physics_World) {
    if world.body_interface != null {
        BodyInterface_RemoveAndDestroyBody(world.body_interface, world.floor_body);
    }
    if world.job_system != null {
        JobSystem_Destroy(world.job_system);
    }
    if world.system != null {
        PhysicsSystem_Destroy(world.system);
    }
    JPH.Shutdown();
    world.* = .{};
}

character_controller_init :: (
    controller: *Character_Controller,
    world: *Character_Physics_World,
    start_position: Vector3,
    walk_speed: float = -1,
    visual_yaw_offset: float = PI,
) {
    character_controller_init_in_system(controller, world.system, start_position, walk_speed, visual_yaw_offset);
}

character_controller_init_in_system :: (
    controller: *Character_Controller,
    system: *PhysicsSystem,
    start_position: Vector3,
    walk_speed: float = -1,
    visual_yaw_offset: float = PI,
) {
    controller_deinit(controller);

    settings: CharacterVirtualSettings;
    CharacterVirtualSettings_Init(*settings);
    using settings;
    using settings.base;

    character_height :: 0.85;
    character_radius :: 0.34;
    shape_offset := Vec3.{0.0, 0.5 * character_height + character_radius, 0.0};
    capsule_shape := CapsuleShape_Create(0.5 * character_height, character_radius);
    controller.shape = RotatedTranslatedShape_Create(*shape_offset, null, xx capsule_shape);

    maxSlopeAngle = 45.0 * PI / 180.0;
    maxStrength = 100.0;
    shape = controller.shape;
    backFaceMode = .CollideWithBackFaces;
    characterPadding = 0.02;
    penetrationRecoverySpeed = 1.0;
    predictiveContactDistance = 0.1;
    supportingVolume = Plane.{.{0.0, 1.0, 0.0}, -character_radius};

    start_position_jph := cast,force(Vec3) start_position;
    identity_quat := Quat_IDENTITY;
    controller.character = CharacterVirtual_Create(*settings, *start_position_jph, *identity_quat, 0, system);
    assert(controller.character != null, "Character controller creation failed.");

    if walk_speed >= 0 controller.walk_speed = walk_speed;
    controller.visual_yaw_offset = visual_yaw_offset;
    controller.facing_yaw = 0.0;
    controller.animation_time = 0.0;
    controller.animation_blend = 0.0;
}

controller_deinit :: (controller: *Character_Controller) {
    if controller.character != null {
        CharacterBase_Destroy(cast(*CharacterBase) controller.character);
    }
    if controller.shape != null {
        Shape_Destroy(controller.shape);
    }
    controller.* = .{};
}

character_controller_update :: (controller: *Character_Controller, world: *Character_Physics_World, desired_move_world: Vector3, dt: float) {
    character_controller_update_in_system(controller, world.system, desired_move_world, dt);
}

character_controller_update_in_system :: (controller: *Character_Controller, system: *PhysicsSystem, desired_move_world: Vector3, dt: float) {
    assert(controller.character != null);

    desired := desired_move_world;
    desired.y = 0.0;
    desired_len := length(desired);
    if desired_len > 1.0e-5 {
        desired *= 1.0 / desired_len;
    } else {
        desired = .{0.0, 0.0, 0.0};
    }

    current_velocity := cast,force(Vector3) CharacterVirtual_GetLinearVelocity(controller.character);
    horizontal_velocity := Vector3.{current_velocity.x, 0.0, current_velocity.z};
    target_velocity := desired * controller.walk_speed;
    accel_t := clamp(dt * controller.accel, 0.0, 1.0);
    horizontal_velocity = lerp(horizontal_velocity, target_velocity, accel_t);

    if dot(desired, desired) < 1.0e-6 {
        horizontal_velocity = lerp(horizontal_velocity, Vector3.{0.0, 0.0, 0.0}, clamp(dt * 10.0, 0.0, 1.0));
    }

    new_velocity := Vector3.{horizontal_velocity.x, current_velocity.y, horizontal_velocity.z};
    CharacterVirtual_SetLinearVelocity(controller.character, cast,force(Vec3) new_velocity);
    CharacterVirtual_UpdateGroundVelocity(controller.character);

    update_settings: ExtendedUpdateSettings = DEFAULT_EXTENDED_UPDATE_SETTINGS;
    CharacterVirtual_ExtendedUpdate(
        controller.character,
        dt,
        *update_settings,
        Character_Collision_Layers.MOVING,
        system,
        null,
        null);

    actual_velocity := cast,force(Vector3) CharacterVirtual_GetLinearVelocity(controller.character);
    actual_horizontal := Vector3.{actual_velocity.x, 0.0, actual_velocity.z};
    actual_speed := length(actual_horizontal);
    controller.animation_blend = clamp(actual_speed / max(controller.walk_speed, 0.001), 0.0, 1.0);

    if actual_speed > 0.05 {
        target_yaw := atan2(actual_horizontal.x, actual_horizontal.z);
        controller.facing_yaw = lerp_angle(controller.facing_yaw, target_yaw, clamp(dt * 8.0, 0.0, 1.0));
    }

    controller.animation_time += dt * controller.animation_blend * 1.6;
}

character_controller_position :: (controller: *Character_Controller) -> Vector3 {
    assert(controller.character != null);
    return cast,force(Vector3) CharacterVirtual_GetPosition(controller.character);
}

character_controller_root_matrix :: (controller: *Character_Controller, uniform_scale: float) -> Matrix4 {
    q: Quaternion;
    set_from_axis_and_angle(*q, Vector3.{0.0, 1.0, 0.0}, controller.facing_yaw + controller.visual_yaw_offset);
    return make_translation_matrix4(character_controller_position(controller))
        * rotation_matrix(Matrix4, q)
        * make_scale_matrix4(.{uniform_scale, uniform_scale, uniform_scale});
}

#scope_file

lerp_angle :: (a: float, b: float, t: float) -> float {
    delta := b - a;
    while delta > PI delta -= 2.0 * PI;
    while delta < -PI delta += 2.0 * PI;
    return a + delta * t;
}

JPH :: #import "JoltC";
using JPH;
#import "JoltC_extra";
#import "Math";
