#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 2; }
}

require_cmd jai

echo "[1/2] Build textured_triangle"
jai build.jai - src/apps/textured_triangle.jai

echo "[2/2] Run smoke probe"
logfile="/tmp/textured_triangle_smoke.log"
set +e
(cd dist && PEEL_SMOKE=1 ./textured_triangle) >"$logfile" 2>&1
code=$?
set -e

tail -n 20 "$logfile" || true

if [[ $code -ne 0 ]]; then
  echo "FAIL: textured_triangle exited with code $code"
  exit "$code"
fi

if ! rg -q "TEXTURED_TRIANGLE_WINDOW_PROBE completed; quitting." "$logfile"; then
  echo "FAIL: smoke probe did not complete."
  exit 3
fi

echo "PASS: textured_triangle smoke probe succeeded."
