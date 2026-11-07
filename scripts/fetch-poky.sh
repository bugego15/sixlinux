#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
POKY_DIR="$ROOT_DIR/sources/poky"

# shellcheck disable=SC1091
source "$ROOT_DIR/sources/versions.env"

if [[ ! -d "$POKY_DIR/.git" ]]; then
    if [[ -d "$POKY_DIR" ]] && [[ -n "$(ls -A "$POKY_DIR")" ]]; then
        printf '错误：%s 已存在且不是 Git 工作树。\n' "$POKY_DIR" >&2
        exit 1
    fi
    mkdir -p "$POKY_DIR"
    git -C "$POKY_DIR" init
    git -C "$POKY_DIR" remote add origin "$POKY_URL"
fi

remote_url="$(git -C "$POKY_DIR" remote get-url origin)"
if [[ "$remote_url" != "$POKY_URL" ]]; then
    printf '错误：Poky origin URL 不匹配：%s\n' "$remote_url" >&2
    exit 1
fi

git -C "$POKY_DIR" fetch --depth 1 origin "$POKY_COMMIT"
git -C "$POKY_DIR" checkout --detach "$POKY_COMMIT"

actual_commit="$(git -C "$POKY_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$POKY_COMMIT" ]]; then
    printf '错误：Poky 版本校验失败。\n' >&2
    exit 1
fi

printf 'Poky 已固定到 %s（%s）。\n' "$POKY_VERSION" "$POKY_COMMIT"
