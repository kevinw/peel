#load "Anim_Evaluator.jai";
#load "Scene_Animator.jai";
#scope_module

using ai :: #import "assimp";
#import "Math";
#import "Basic";
using,only(SDL_fmod) SDL :: #import "SDL3";

operator - :: (a: ai.Vector3D, b: ai.Vector3D) -> ai.Vector3D {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator + :: (a: ai.Vector3D, b: ai.Vector3D) -> ai.Vector3D {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator * :: (a: ai.Vector3D, b: float) -> ai.Vector3D {
    ai.Vector3Scale(*a, b);
    return a;
}
