#!/usr/bin/env bash
set -euo pipefail

# Change to the directory of this script.
cd "$(dirname "$0")"

# First, run Jai transpiler tests
pushd modules/Jai-Shader-Transpiler && jai -quiet build.jai - -run_tests; popd

# Now, run the peel build and validate its generated shaders.
jai -quiet build.jai - -norun && \
    xcrun -sdk macosx metal -fsyntax-only -c .generated_shaders/*.metal
