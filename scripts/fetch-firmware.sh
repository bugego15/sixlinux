#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TFA_DIR="$ROOT_DIR/sources/arm-trusted-firmware"

# shellcheck disable=SC1091
source "$ROOT_DIR/sources/versions.env"
UBOOT_DIR="$ROOT_DIR/cache/downloads/git2/$UBOOT_CACHE_NAME"

if [[ -d "$TFA_DIR/.git" ]]; then
    current="$(git -C "$TFA_DIR" rev-parse HEAD)"
else
    current=""
fi

if [[ "$current" != "$TFA_COMMIT" ]]; then
    if [[ ! -d "$TFA_DIR/.git" ]]; then
        if [[ -d "$TFA_DIR" ]] && [[ -n "$(ls -A "$TFA_DIR")" ]]; then
            printf '错误：%s 已存在且不是 Git 工作树。\n' "$TFA_DIR" >&2
            exit 1
        fi
        mkdir -p "$TFA_DIR"
        git -C "$TFA_DIR" init
        git -C "$TFA_DIR" remote add origin "$TFA_URL"
    fi
    git -C "$TFA_DIR" fetch --depth 1 origin "$TFA_COMMIT"
    git -C "$TFA_DIR" checkout --detach "$TFA_COMMIT"
fi
printf 'TF-A 已固定到 %s（%s）。\n' "$TFA_VERSION" "$TFA_COMMIT"

current=""
if [[ -d "$UBOOT_DIR" ]]; then
    current="$(git -C "$UBOOT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ "$current" != "$UBOOT_COMMIT" ]]; then
    case "$UBOOT_DIR" in
        "$ROOT_DIR/cache/downloads/git2/"*) rm -rf -- "$UBOOT_DIR" ;;
        *) printf '错误：非法 U-Boot 缓存路径。\n' >&2; exit 1 ;;
    esac
    mkdir -p "$UBOOT_DIR"
    git -C "$UBOOT_DIR" init --bare
    git -C "$UBOOT_DIR" remote add origin "$UBOOT_URL"
    git -C "$UBOOT_DIR" fetch --depth 1 origin "$UBOOT_COMMIT"
    git -C "$UBOOT_DIR" update-ref refs/heads/master "$UBOOT_COMMIT"
    git -C "$UBOOT_DIR" symbolic-ref HEAD refs/heads/master
fi
printf 'U-Boot 已固定到 %s（%s）。\n' "$UBOOT_VERSION" "$UBOOT_COMMIT"
