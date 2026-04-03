#!/bin/zsh

set -euo pipefail

ROOT=/Users/kev/src/peel
BLENDER_BIN="${BLENDER_BIN:-$HOME/src/build_darwin_release/bin/Blender.app/Contents/MacOS/Blender}"
LIVE_SYNC_PY="$ROOT/tools/blender_exporter/live_sync.py"

usage() {
    echo "Usage: $0 <input.blend|--factory-startup> [output.peelscene]" >&2
    exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
fi

INPUT_PATH="$1"
OUTPUT_PATH="${2:-}"

if [[ ! -x "$BLENDER_BIN" ]]; then
    echo "Missing Blender binary: $BLENDER_BIN" >&2
    exit 1
fi

if [[ ! -f "$LIVE_SYNC_PY" ]]; then
    echo "Missing live sync script: $LIVE_SYNC_PY" >&2
    exit 1
fi

if [[ -n "$OUTPUT_PATH" ]]; then
    export PEEL_LIVE_OUTPUT="$OUTPUT_PATH"
fi

BLENDER_ARGS=(
    --python "$LIVE_SYNC_PY"
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
