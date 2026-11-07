#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POKY_DIR="$ROOT_DIR/sources/poky"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/sixlinux-qemuarm64"

if [[ ! -f "$POKY_DIR/oe-init-build-env" ]]; then
    printf '错误：Poky 尚未下载。\n' >&2
    exit 1
fi

shopt -s nullglob
qemuboot_configs=("$DEPLOY_DIR"/*.qemuboot.conf)
if (( ${#qemuboot_configs[@]} == 0 )); then
    printf '错误：尚未生成 qemuboot 配置，请先执行 make build。\n' >&2
    exit 1
fi
latest_qemuboot="$(ls -t "${qemuboot_configs[@]}" | head -n 1)"

export TEMPLATECONF="${TEMPLATECONF:-$ROOT_DIR/layers/meta-sixlinux/conf/templates/qemuarm64}"
set +u
# shellcheck disable=SC1091
source "$POKY_DIR/oe-init-build-env" "$BUILD_DIR"
set -u

exec runqemu "$latest_qemuboot" nographic slirp "$@"
