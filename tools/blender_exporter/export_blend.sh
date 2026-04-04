#!/bin/zsh

set -euo pipefail

ROOT=/Users/kev/src/peel
BLENDER_BIN="${BLENDER_BIN:-$HOME/src/build_darwin_release/bin/Blender.app/Contents/MacOS/Blender}"
PY_DRIVER="$ROOT/tools/blender_exporter/export_blend.py"
EXPORTER_DYLIB="${PEEL_BLENDER_EXPORTER_LIB:-$ROOT/tools/blender_exporter/.build/peel_blender_exporter.dylib}"

usage() {
    echo "Usage: $0 <input.blend|--factory-startup> <output.peelscene>" >&2
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

INPUT_PATH="$1"
OUTPUT_PATH="$2"

if [[ ! -x "$BLENDER_BIN" ]]; then
    echo "Missing Blender binary: $BLENDER_BIN" >&2
    exit 1
fi

export PEEL_EXPORT_OUTPUT="$OUTPUT_PATH"
export PEEL_BLENDER_EXPORTER_LIB="$EXPORTER_DYLIB"

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
