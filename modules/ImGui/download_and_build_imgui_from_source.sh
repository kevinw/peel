#!/bin/bash -xe

# Path setup

# TODO: replace this script with a function in generate.jai! this version should
# be kept in sync with generate.jai's IMGUI_PATH
VERSION=1.92.6

ZIP_URL=https://github.com/ocornut/imgui/archive/refs/tags/v$VERSION.zip
SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Download the source code from github
if [ ! -d "src/imgui-$VERSION" ]; then
    mkdir -p src
    ZIPFILE=imgui-$VERSION.zip
    curl -s -L $ZIP_URL --output src/$ZIPFILE
    pushd src
    unzip -oq $ZIPFILE
    rm $ZIPFILE
    popd
else
    echo "ImGui source found, using it: src/imgui-$VERSION"
fi

# Compile it and move the output to the macos directory
pushd src/imgui-$VERSION
LIBS="-lc++ -framework Cocoa -framework IOKit -framework Metal -framework Foundation -framework GameController"
MIN_TARGET="-mmacosx-version-min=11.0"
SOURCES="imgui.cpp imgui_demo.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp backends/imgui_impl_metal.mm backends/imgui_impl_osx.mm ../../src/imgui_macos_bridge.mm"
OBJS="imgui.o imgui_demo.o imgui_draw.o imgui_tables.o imgui_widgets.o imgui_impl_metal.o imgui_impl_osx.o imgui_macos_bridge.o"
cc -c -O3 -Wall -Wformat -std=c++11 $MIN_TARGET -I. -Ibackends $SOURCES
cc -dynamiclib -headerpad_max_install_names $MIN_TARGET -o ImGui.dylib $OBJS $LIBS
mkdir -p ../../macos
mv ImGui.dylib ../../macos/
popd
install_name_tool -id @rpath/ImGui.dylib macos/ImGui.dylib
echo Built ImGui.dylib
