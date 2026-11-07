#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILD_DIR="$ROOT_DIR/build/qemuarm64-release"
export DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/sixlinux-qemuarm64"
bash "$ROOT_DIR/scripts/run-firmware.sh" "$@"
