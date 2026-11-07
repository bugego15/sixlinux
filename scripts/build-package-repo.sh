#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
DEPLOY_IPK="$BUILD_DIR/tmp/deploy/ipk"
RECIPE_DIR="$ROOT_DIR/layers/meta-sixlinux/recipes-apps/sixlinux-hello"
V1_CACHE="$ROOT_DIR/artifacts/feed-v1"
INDEX_BIN="$BUILD_DIR/tmp/work/x86_64-linux/opkg-utils-native/0.6.3/git/opkg-make-index"
KEY_HOME="$ROOT_DIR/artifacts/keys/gnupg-feed"
KEY_ID_FILE="$ROOT_DIR/artifacts/keys/feed-key-id"

if (( EUID == 0 )); then
    printf '错误：请使用 dev 用户构建软件仓库。\n' >&2
    exit 1
fi

build_version() {
    local version="$1"
    if compgen -G "$DEPLOY_IPK/cortexa53/sixlinux-hello_${version}-r0_*.ipk" >/dev/null; then
        printf 'sixlinux-hello %s 已存在，跳过重复构建。\n' "$version"
        return 0
    fi

    printf '构建 sixlinux-hello %s\n' "$version"
    rm -f "$RECIPE_DIR"/sixlinux-hello_*.bb
    cp -a "$ROOT_DIR/packages/sixlinux-hello/v$version/." "$RECIPE_DIR/"
    "$ROOT_DIR/scripts/build-qemuarm64.sh" sixlinux-hello
}

mkdir -p "$RECIPE_DIR" "$V1_CACHE"

build_version 1.0
cp "$DEPLOY_IPK/cortexa53"/sixlinux-hello_1.0-r0_*.ipk "$V1_CACHE/"

build_version 1.1
cp "$V1_CACHE"/*.ipk "$DEPLOY_IPK/cortexa53/"

if [[ ! -x "$INDEX_BIN" ]]; then
    printf '错误：未找到 opkg-make-index：%s\n' "$INDEX_BIN" >&2
    exit 1
fi

for feed in all cortexa53 sixlinux_qemuarm64; do
    printf '更新 feed 索引：%s\n' "$feed"
    (cd "$DEPLOY_IPK/$feed" && "$INDEX_BIN" -a -p Packages .)
done

# 用软件源签名密钥对每个 feed 的 Packages 生成 ASCII 装甲分离签名。
# opkg 下载 Packages.gz 解压后，与 Packages.asc 一起验签。
bash "$ROOT_DIR/scripts/generate-feed-key.sh"
if [[ ! -d "$KEY_HOME" || ! -s "$KEY_ID_FILE" ]]; then
    printf '错误：软件源签名密钥未就绪。\n' >&2
    exit 1
fi
FINGERPRINT="$(cat "$KEY_ID_FILE")"
for feed in all cortexa53 sixlinux_qemuarm64; do
    printf '签名 feed 索引：%s\n' "$feed"
    gpg --homedir "$KEY_HOME" --batch --yes --local-user "$FINGERPRINT" \
        --detach-sign --armor \
        --output "$DEPLOY_IPK/$feed/Packages.asc" \
        "$DEPLOY_IPK/$feed/Packages"
done

printf '软件仓库已生成并签名：%s\n' "$DEPLOY_IPK"
