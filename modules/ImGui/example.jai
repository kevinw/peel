#import "Basic";
ImGui :: #import,file "module.jai";

main :: () {
    ctx := ImGui.CreateContext();
    log("ImGui context created: %", ctx);
    log("ImGui version: %", to_string(ImGui.GetVersion()));
    log("OK!");
}

