#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_PATH="${1:-/tmp/peel_e2e_default_cube.peelscene}"

rm -f "$OUTPUT_PATH"

export PEEL_EXPORT_EXPECT_NAME=Cube

"$ROOT/tools/blender_exporter/export_blend.sh" \
    --factory-startup \
    "$OUTPUT_PATH"

if [[ ! -f "$OUTPUT_PATH" ]]; then
    echo "Expected export output was not created: $OUTPUT_PATH" >&2
    exit 1
fi

echo "PEEL E2E passed: $OUTPUT_PATH"
