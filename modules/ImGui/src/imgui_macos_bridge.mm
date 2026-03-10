#if defined(__APPLE__)

#import <Metal/Metal.h>
#import <AppKit/AppKit.h>

#include "backends/imgui_impl_metal.h"
#include "backends/imgui_impl_osx.h"

extern "C" bool Jai_ImGui_ImplMetal_Init(id<MTLDevice> device) {
    return ImGui_ImplMetal_Init(device);
}

extern "C" void Jai_ImGui_ImplMetal_Shutdown() {
    ImGui_ImplMetal_Shutdown();
}

extern "C" void Jai_ImGui_ImplMetal_NewFrame(MTLRenderPassDescriptor* render_pass_desc) {
    ImGui_ImplMetal_NewFrame(render_pass_desc);
}

extern "C" void Jai_ImGui_ImplMetal4_NewFrame(MTL4RenderPassDescriptor* render_pass_desc) {
    ImGui_ImplMetal4_NewFrame(render_pass_desc);
}

extern "C" void Jai_ImGui_ImplMetal_RenderDrawData(ImDrawData* draw_data,
                                                   id<MTLCommandBuffer> command_buffer,
                                                   id<MTLRenderCommandEncoder> command_encoder) {
    ImGui_ImplMetal_RenderDrawData(draw_data, command_buffer, command_encoder);
}

extern "C" void Jai_ImGui_ImplMetal4_RenderDrawData(ImDrawData* draw_data,
                                                    id<MTL4CommandBuffer> command_buffer,
                                                    id<MTL4RenderCommandEncoder> command_encoder) {
    ImGui_ImplMetal4_RenderDrawData(draw_data, command_buffer, command_encoder);
}

extern "C" void Jai_ImGui_ImplMetal4_ConfigureFrameSynchronization(id<MTLSharedEvent> shared_event,
                                                                   int max_frames_in_flight) {
    ImGui_ImplMetal4_ConfigureFrameSynchronization(shared_event, max_frames_in_flight);
}

extern "C" void Jai_ImGui_ImplMetal4_NotifyFrameSubmitted(id<MTL4CommandQueue> command_queue) {
    ImGui_ImplMetal4_NotifyFrameSubmitted(command_queue);
}

extern "C" bool Jai_ImGui_ImplOSX_Init(NSView* view) {
    return ImGui_ImplOSX_Init(view);
}

extern "C" void Jai_ImGui_ImplOSX_Shutdown() {
    ImGui_ImplOSX_Shutdown();
}

extern "C" void Jai_ImGui_ImplOSX_NewFrame(NSView* view) {
    ImGui_ImplOSX_NewFrame(view);
}

#endif
