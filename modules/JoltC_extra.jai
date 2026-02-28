//
// TODO: have the bindings generator make most of this
//

RMatrix4x4 :: RMat4; // TODO: JoltC has renamed this to be shorter. Remove all instances of RMatrix4x4 in our code.

cInvalidCharacterID: u32 : 0xffffffff;
operator * :: (scalar: float32, vec: Vec3) -> Vec3 { return .{scalar * vec.x, scalar * vec.y, scalar * vec.z}; }
operator * :: (vec: Vec3, scalar: float) -> Vec3   { return .{vec.x * scalar, vec.y * scalar, vec.z * scalar}; }
operator * :: (a: Vec3, b: Vec3) -> Vec3           { return .{a.x * b.x, a.y * b.y, a.z * b.z}; }
operator + :: (a: Vec3, b: Vec3) -> Vec3           { return .{a.x + b.x, a.y + b.y, a.z + b.z}; }
operator - :: (v: Vec3) -> Vec3                    { return .{-v.x, -v.y, -v.z}; }
operator - :: (a: Vec3, b: Vec3) -> Vec3           { return .{a.x - b.x, a.y - b.y, a.z - b.z}; }
operator / :: (a: Vec3, f: float) -> Vec3          { return .{a.x / f, a.y / f, a.z / f}; }
operator * :: (quat: Quat, vec: Vec3) -> Vec3 {
    result: Vec3;
    Quat_Rotate(*quat, *vec, *result);
    return result;
}
Vec3_DotProduct :: (v1: Vec3, v2: Vec3) -> float {
    result: float;
    Vec3_DotProduct(*v1, *v2, *result);
    return result;
}
Vec3_IsNearZero :: (v: Vec3, inMaxDistSq: float = 1.0e-12) -> bool { return Vec3_IsNearZero(*v, inMaxDistSq); }
Vec3_Length     :: (v: Vec3) -> float { return Vec3_Length(*v); }
Quat_FromEulerAngles :: (angles: Vec3) -> Quat {
    result: Quat;
    Quat_FromEulerAngles(*angles, *result);
    return result;
}
Mat4_GetTranslation :: (m: Mat4) -> Vec3 {
    translation: Vec3;
    Mat4_Translation(*m, *translation);
    return translation;
}

make_Color :: (r: u8, g: u8, b: u8, a: u8 = 255) -> Color {
    return (cast(u32)r << 24) |
           (cast(u32)g << 16) |
           (cast(u32)b << 8) |
           (cast(u32)a);
}

CharacterVirtual_GetLinearVelocity :: (character: *CharacterVirtual) -> Vec3 {
    linear_velocity: Vec3;
    CharacterVirtual_GetLinearVelocity(character, *linear_velocity);
    return linear_velocity;
}

CharacterVirtual_GetPosition :: (character_virtual: *CharacterVirtual) -> Vec3 {
    position: Vec3;
    CharacterVirtual_GetPosition(character_virtual, *position);
    return position;
}

CharacterVirtual_SetLinearVelocity :: (character: *CharacterVirtual, new_velocity: Vec3) {
    CharacterVirtual_SetLinearVelocity(character, *new_velocity);
}

CharacterBase_GetUp :: (character: *CharacterBase) -> Vec3 {
    up: Vec3;
    CharacterBase_GetUp(character, *up);
    return up;
}

CharacterBase_IsSlopeTooSteep :: (character: *CharacterBase, slope: Vec3) -> bool {
    return CharacterBase_IsSlopeTooSteep(character, *slope);
}

CharacterBase_GetGroundPosition :: (character: *CharacterBase) -> Vec3 {
    ground_position: Vec3;
    CharacterBase_GetGroundPosition(character, *ground_position);
    return ground_position;
}

CharacterBase_GetGroundNormal :: (character: *CharacterBase) -> Vec3 {
    ground_normal: Vec3;
    CharacterBase_GetGroundNormal(character, *ground_normal);
    return ground_normal;
}

CharacterBase_GetGroundVelocity :: (character: *CharacterBase) -> Vec3 {
    ground_velocity: Vec3;
    CharacterBase_GetGroundVelocity(character, *ground_velocity);
    return ground_velocity;
}

PhysicsSystem_GetGravity :: (system: *PhysicsSystem) -> Vec3 {
    gravity: Vec3;
    PhysicsSystem_GetGravity(system, *gravity);
    return gravity;
}

PhysicsSystem_GetPhysicsSettings :: (system: *PhysicsSystem) -> PhysicsSettings {
    result: PhysicsSettings;
    PhysicsSystem_GetPhysicsSettings(system, *result);
    return result;
}

DebugRenderer_DrawMarker :: (debug_renderer: *DebugRenderer, ground_position: Vec3, color: Color, size: float) {
    DebugRenderer_DrawMarker(debug_renderer, *ground_position, color, size);
}

DebugRenderer_DrawArrow :: (debug_renderer: *DebugRenderer, from: Vec3, to: Vec3, color: Color, size: float) {
    DebugRenderer_DrawArrow(debug_renderer, *from, *to, color, size);
}

Color_green  :: #run make_Color(0,   0,   255);
Color_grey   :: #run make_Color(128, 128, 128);
Color_red    :: #run make_Color(255, 0,   0);
Color_blue   :: #run make_Color(0,   0,   255);
Color_yellow :: #run make_Color(255, 255, 0);
Color_white  :: #run make_Color(255, 255, 255);

DEFAULT_EXTENDED_UPDATE_SETTINGS :: ExtendedUpdateSettings.{
    stickToFloorStepDown      = .{0, -0.5, 0},
    walkStairsStepUp          = .{0, 0.4, 0},
    walkStairsMinStepForward  = 0.02,
    walkStairsStepForwardTest = 0.15,
    walkStairsCosAngleForwardContact = #run cos(DegreesToRadians(75)),
    walkStairsStepDownExtra   = .{0, 0, 0},
};

Vec3_ZERO :: Vec3.{0, 0, 0};
Quat_IDENTITY :: Quat.{0, 0, 0, 1};

v3 :: (x: float32, y: float32, z: float32) -> Vec3 {
    return .{x, y, z};
}

BodyInterface_GetPosition :: inline (_interface: *BodyInterface, bodyId: BodyID) -> Vec3 {
    result: Vec3;
    BodyInterface_GetPosition(_interface, bodyId, *result);
    return result;
}

BodyInterface_GetRotation :: inline (_interface: *BodyInterface, bodyId: BodyID) -> Quat {
    result: Quat;
    BodyInterface_GetRotation(_interface, bodyId, *result);
    return result;
}

CharacterVirtual_SetPosition :: (character: *CharacterVirtual, position: Vec3) {
    CharacterVirtual_SetPosition(character, *position);
}

#scope_file

DegreesToRadians :: (degrees: float) -> float {
    DEG2RAD :: PI/180.0;
    return degrees * DEG2RAD;
}

#import "Math";
#import "JoltC";
