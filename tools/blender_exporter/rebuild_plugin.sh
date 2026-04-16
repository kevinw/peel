#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BLENDER_EXPORTER_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/blender_paths.sh"

# Regenerate importer bindings for the shared .peelscene file-format header, then
# rebuild the Blender app that contains the native exporter.
ROOT="$(blender_exporter_repo_root)"
BLENDER_REPO="$(blender_exporter_blender_repo)"
cd "$ROOT"
jai -quiet "$ROOT/tools/blender_exporter/generate.jai"

cd "$BLENDER_REPO"
make release ninja
