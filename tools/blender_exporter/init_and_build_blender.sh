#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BLENDER_EXPORTER_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/blender_paths.sh"

ROOT="$(blender_exporter_repo_root)"
BLENDER_REPO="$(blender_exporter_blender_repo)"
CHECK_ONLY=0

usage() {
    cat <<EOF
Usage: $0 [--check]

Initializes the Blender submodule, checks local build prerequisites, runs
\`make update\` inside the Blender fork, then rebuilds the PEEL Blender app.

Options:
  --check   Only validate prerequisites and print the commands that would run.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

has_brew_formula() {
    brew list --formula "$1" >/dev/null 2>&1
}

print_missing_prereqs() {
    local missing=0

    if ! xcode-select -p >/dev/null 2>&1; then
        missing=1
        cat >&2 <<EOF
Missing Xcode Command Line Tools.
Install with:
  xcode-select --install
EOF
    fi

    if ! need_cmd brew; then
        missing=1
        cat >&2 <<'EOF'
Missing Homebrew.
Install Homebrew from:
  https://brew.sh/
Then install Blender build dependencies with:
  brew install cmake ninja git-lfs
EOF
    else
        local missing_formulae=()
        for formula in cmake ninja git-lfs; do
            if ! has_brew_formula "$formula"; then
                missing_formulae+=("$formula")
            fi
        done

        if (( ${#missing_formulae[@]} > 0 )); then
            missing=1
            echo "Missing Homebrew formulae: ${missing_formulae[*]}" >&2
            echo "Install with:" >&2
            echo "  brew install ${missing_formulae[*]}" >&2
        fi
    fi

    if ! need_cmd git; then
        missing=1
        echo "Missing git. Install Xcode Command Line Tools or Homebrew git." >&2
    fi

    if ! need_cmd make; then
        missing=1
        echo "Missing make. Install Xcode Command Line Tools." >&2
    fi

    if ! need_cmd python3; then
        missing=1
        echo "Missing python3. Install with: brew install python" >&2
    fi

    if ! need_cmd jai; then
        missing=1
        echo "Missing jai in PATH. This script needs the Jai compiler to regenerate PEEL bindings." >&2
    fi

    return "$missing"
}

echo "PEEL root: $ROOT"
echo "Blender repo: $BLENDER_REPO"

if ! print_missing_prereqs; then
    exit 1
fi

cd "$ROOT"

if (( CHECK_ONLY )); then
    cat <<EOF
Prerequisites look good.
Would run:
  git -C "$BLENDER_REPO" lfs install
  git submodule update --init --recursive tools/blender
  make -C "$BLENDER_REPO" update
  "$SCRIPT_DIR/rebuild_plugin.sh"
EOF
    exit 0
fi

if [[ ! -e "$BLENDER_REPO/.git" ]]; then
    echo "Initializing Blender submodule..."
    git submodule update --init --recursive tools/blender
fi

if need_cmd git-lfs; then
    git lfs install >/dev/null
fi

echo "Running Blender dependency sync..."
make -C "$BLENDER_REPO" update

echo "Rebuilding PEEL Blender..."
"$SCRIPT_DIR/rebuild_plugin.sh"
