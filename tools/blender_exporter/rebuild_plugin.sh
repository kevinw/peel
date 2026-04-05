#!/bin/zsh

set -euo pipefail

# Regenerate importer bindings for the shared .peelscene file-format header, then
# rebuild the Blender app that contains the native exporter.
cd ~/src/peel
jai -quiet ~/src/peel/tools/blender_exporter/generate.jai

cd ~/src/blender && make release ninja
