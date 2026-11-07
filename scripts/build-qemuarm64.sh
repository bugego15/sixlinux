#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POKY_DIR="$ROOT_DIR/sources/poky"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
TEMPLATECONF="${TEMPLATECONF:-$ROOT_DIR/layers/meta-sixlinux/conf/templates/qemuarm64}"
TARGET="${1:-sixlinux-image-minimal}"

if (( EUID == 0 )); then
    printf '错误：BitBake 不能使用 root 构建，请切换到 dev 用户。\n' >&2
    exit 1
fi

# 密码登录被禁用，构建前必须准备好 release 登录密钥和 SSH 主机密钥。
bash "$ROOT_DIR/scripts/generate-keys.sh"
# 软件源 GPG 签名密钥和镜像内 keyring。
bash "$ROOT_DIR/scripts/generate-feed-key.sh"

if [[ ! -f "$POKY_DIR/oe-init-build-env" ]]; then
    printf '错误：Poky 尚未下载到 %s。\n' "$POKY_DIR" >&2
    exit 1
fi

source "$ROOT_DIR/sources/versions.env"
actual_commit="$(git -C "$POKY_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$POKY_COMMIT" ]]; then
    printf '错误：Poky 提交不匹配。\n期望：%s\n实际：%s\n' \
        "$POKY_COMMIT" "$actual_commit" >&2
    exit 1
fi

bash "$ROOT_DIR/scripts/fetch-kernel-cache.sh"

mkdir -p "$BUILD_DIR"
export TEMPLATECONF
set +u
# shellcheck disable=SC1091
source "$POKY_DIR/oe-init-build-env" "$BUILD_DIR"
set -u

printf '构建目标：%s\n' "$TARGET"
bitbake "$TARGET"
