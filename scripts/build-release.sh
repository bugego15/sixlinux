#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT_DIR/scripts/generate-keys.sh"

export BUILD_DIR="$ROOT_DIR/build/qemuarm64-release"
export TEMPLATECONF="$ROOT_DIR/layers/meta-sixlinux/conf/templates/qemuarm64-release"
bash "$ROOT_DIR/scripts/build-qemuarm64.sh" "$@"
