#!/bin/zsh

set -euo pipefail

blender_exporter_script_dir() {
    local source_path
    source_path="${BLENDER_EXPORTER_SCRIPT_DIR:-${(%):-%x}}"
    if [[ -d "$source_path" ]]; then
        cd "$source_path" && pwd
        return 0
    fi
    cd "$(dirname "$source_path")" && pwd
}

blender_exporter_repo_root() {
    local script_dir
    script_dir="$(blender_exporter_script_dir)"
    cd "$script_dir/../.." && pwd
}

blender_exporter_blender_repo() {
    local root
    root="$(blender_exporter_repo_root)"
    echo "${PEEL_BLENDER_REPO:-$root/tools/blender}"
}

blender_exporter_default_candidates() {
    local root blender_repo blender_parent
    root="$(blender_exporter_repo_root)"
    blender_repo="$(blender_exporter_blender_repo)"
    blender_parent="$(cd "$blender_repo/.." && pwd)"

    cat <<EOF
$blender_parent/build_darwin_release/bin/Blender.app/Contents/MacOS/Blender
$blender_parent/build_darwin_release/bin/blender
$blender_parent/build_linux_release/bin/blender
$blender_repo/build_darwin_release/bin/Blender.app/Contents/MacOS/Blender
$blender_repo/build_darwin_release/bin/blender
$blender_repo/build_linux_release/bin/blender
$root/tools/Blender.app/Contents/MacOS/Blender
$root/tools/blender/bin/blender
$HOME/src/build_darwin_release/bin/Blender.app/Contents/MacOS/Blender
EOF
}

blender_exporter_find_binary() {
    if [[ -n "${BLENDER_BIN:-}" ]]; then
        if [[ -x "$BLENDER_BIN" ]]; then
            echo "$BLENDER_BIN"
            return 0
        fi
        echo "BLENDER_BIN is set but not executable: $BLENDER_BIN" >&2
        return 1
    fi

    local candidate
    while IFS= read -r candidate; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done < <(blender_exporter_default_candidates)

    echo "Missing Blender binary. Looked in:" >&2
    blender_exporter_default_candidates | sed 's/^/  - /' >&2
    echo "You can override with BLENDER_BIN=/absolute/path/to/Blender" >&2
    return 1
}
