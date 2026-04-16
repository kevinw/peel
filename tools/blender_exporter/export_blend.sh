#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BLENDER_EXPORTER_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/blender_paths.sh"

ROOT="$(blender_exporter_repo_root)"
BLENDER_BIN="$(blender_exporter_find_binary)"
PY_DRIVER="$ROOT/tools/blender_exporter/export_blend.py"

usage() {
    echo "Usage: $0 <input.blend|--factory-startup> <output.peelscene>" >&2
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

INPUT_PATH="$1"
OUTPUT_PATH="$2"

export PEEL_EXPORT_OUTPUT="$OUTPUT_PATH"

BLENDER_ARGS=(
    --background
    --python-exit-code 1
    --python "$PY_DRIVER"
)

if [[ "$INPUT_PATH" == "--factory-startup" ]]; then
    BLENDER_ARGS=(--factory-startup "${BLENDER_ARGS[@]}")
else
    if [[ ! -f "$INPUT_PATH" ]]; then
        echo "Missing input blend file: $INPUT_PATH" >&2
        exit 1
    fi
    BLENDER_ARGS=("$INPUT_PATH" "${BLENDER_ARGS[@]}")
fi

"$BLENDER_BIN" "${BLENDER_ARGS[@]}"
