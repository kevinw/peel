#!/bin/bash -xe

pushd src/imgui

# Compile imgui... (TODO: ninja? cmake? ugh)
LIBS="-lc++ -framework Cocoa -framework IOKit -framework Metal -framework QuartzCore -framework Foundation -framework GameController"
MIN_TARGET="-mmacosx-version-min=26.0"
METAL_DEFINE=""
METAL_BACKEND_SOURCE="backends/imgui_impl_metal.mm"
METAL_BACKEND_OBJ="imgui_impl_metal.o"
SOURCES="imgui.cpp imgui_demo.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp $METAL_BACKEND_SOURCE backends/imgui_impl_osx.mm ../../src/imgui_macos_bridge.mm"
OBJS="imgui.o imgui_demo.o imgui_draw.o imgui_tables.o imgui_widgets.o $METAL_BACKEND_OBJ imgui_impl_osx.o imgui_macos_bridge.o"
cc -c -Os -Wall -Wextra -Wformat -std=c++11 -ObjC++ -fobjc-arc $MIN_TARGET $METAL_DEFINE -I. -Ibackends $SOURCES
cc -dynamiclib -headerpad_max_install_names $MIN_TARGET -o ImGui.dylib $OBJS $LIBS

# ...and move the output to the macos directory
mkdir -p ../../macos
mv ImGui.dylib ../../macos/
popd
install_name_tool -id @rpath/ImGui.dylib macos/ImGui.dylib
echo Built ImGui.dylib
