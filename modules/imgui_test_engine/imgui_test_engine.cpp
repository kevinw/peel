// #define IMGUI_DEFINE_MATH_OPERATORS
#include "imgui.h"
#include "imgui_internal.h"
#ifdef IMGUI_ENABLE_FREETYPE
#include "misc/freetype/imgui_freetype.cpp"
#endif

// imgui_app is a helper to wrap multiple Dear ImGui platform/renderer backends
//#include "shared/imgui_app.h"

// Test Engine
#include "imgui_test_engine/imgui_te_engine.h"
#include "imgui_test_engine/imgui_te_ui.h"
#include "imgui_test_engine/imgui_te_utils.h"       // ImOsIsDebuggerPresent()
#include "imgui_test_engine/imgui_te_exporters.h"   // ImGuiTestEngineExportFormat when use is uncommented.