#!/bin/zsh

set -euo pipefail

cd ~/src/peel
jai -quiet ~/src/peel/tools/blender_exporter/generate.jai
jai -quiet ~/src/peel/tools/blender_exporter/build.jai

# cd ~/src/blender && make debug developer ninja
cd ~/src/blender && make release ninja
