#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_GIT_DIR="${DOWNLOAD_GIT_DIR:-$ROOT_DIR/cache/downloads/git2}"

# shellcheck disable=SC1091
source "$ROOT_DIR/sources/versions.env"

fetch_shallow() {
    local url="$1"
    local branch="$2"
    local commit="$3"
    local cache_name="$4"
    local dest="$DOWNLOAD_GIT_DIR/$cache_name"
    local current=""

    if [[ -d "$dest" ]]; then
        current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
        if [[ "$current" == "$commit" ]]; then
            printf '缓存已匹配：%s（%s）\n' "$cache_name" "$commit"
            return 0
        fi
    fi

    if [[ -e "$dest" ]]; then
        case "$dest" in
            "$DOWNLOAD_GIT_DIR"/*)
                rm -rf -- "$dest"
                ;;
            *)
                printf '错误：拒绝清理非下载缓存路径 %s。\n' "$dest" >&2
                exit 1
                ;;
        esac
    fi

    mkdir -p "$dest"
    git -C "$dest" init --bare
    git -C "$dest" remote add origin "$url"
    git -C "$dest" fetch --depth 1 origin "$commit"
    git -C "$dest" update-ref "refs/heads/$branch" "$commit"
    git -C "$dest" symbolic-ref HEAD "refs/heads/$branch"

    current="$(git -C "$dest" rev-parse HEAD)"
    if [[ "$current" != "$commit" ]]; then
        printf '错误：%s 的提交校验失败。\n' "$cache_name" >&2
        exit 1
    fi
    printf '已获取浅克隆：%s（%s）\n' "$cache_name" "$commit"
}

fetch_shallow "$LINUX_YOCTO_URL" "$LINUX_YOCTO_BRANCH" \
    "$LINUX_YOCTO_COMMIT" "$LINUX_YOCTO_CACHE_NAME"
fetch_shallow "$KERNEL_META_URL" "$KERNEL_META_BRANCH" \
    "$KERNEL_META_COMMIT" "$KERNEL_META_CACHE_NAME"
