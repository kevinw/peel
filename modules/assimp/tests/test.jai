#import "Basic";
#import,file "../module.jai";

main :: () {
    post_process_flags := PostProcessSteps.Triangulate | PostProcessSteps.CalcTangentSpace;
    scene := ImportFileEx("cube.fbx", post_process_flags.(u32), null);
    defer FreeScene(scene);
    assert(scene != null, "importing cube.fbx failed. Ensure you are running from INSIDE the 'tests' folder.");

    meshes: []*Mesh = .{
        data = scene.mMeshes,
        count = scene.mNumMeshes,
    };

    for meshes {
        name := string.{data=it.mName.data.data, count=it.mName.length};
        print("mesh:\n  name=%\n  vertices=%\n  normals=%\n", name, it.mNumVertices, it.mNumVertices);
    }
}
