#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BLENDER_EXPORTER_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/blender_paths.sh"

ROOT="$(blender_exporter_repo_root)"
BLENDER_BIN="$(blender_exporter_find_binary)"
LIVE_SYNC_PY="$ROOT/tools/blender_exporter/live_sync.py"

usage() {
    echo "Usage: $0 [--debugger] <input.blend|--factory-startup> [output.peelscene]" >&2
    exit 1
}

USE_DEBUGGER=0
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debugger)
            USE_DEBUGGER=1
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                POSITIONAL_ARGS+=("$1")
                shift
            done
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL_ARGS[@]} -lt 1 || ${#POSITIONAL_ARGS[@]} -gt 2 ]]; then
    usage
fi

INPUT_PATH="${POSITIONAL_ARGS[1]}"
OUTPUT_PATH="${POSITIONAL_ARGS[2]:-}"

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

if (( USE_DEBUGGER )); then
    exec lldb -o run -- "$BLENDER_BIN" "${BLENDER_ARGS[@]}"
fi

exec "$BLENDER_BIN" "${BLENDER_ARGS[@]}"
