#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/sixlinux-qemuarm64"
OUT_DIR="${OTA_OUT_DIR:-$ROOT_DIR/artifacts/ota}"
OTA_VERSION="${OTA_VERSION:-1.1.0}"
PAYLOAD_VERSION="${OTA_PAYLOAD_VERSION:-$OTA_VERSION}"
KEY_HOME="$ROOT_DIR/artifacts/keys/gnupg-feed"
KEY_ID_FILE="$ROOT_DIR/artifacts/keys/feed-key-id"

if (( EUID == 0 )); then
    printf '错误：请使用 dev 用户构建 OTA 升级包。\n' >&2
    exit 1
fi

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

[[ -f "$KEY_ID_FILE" ]] || die "缺少 feed 签名密钥，请先执行 make package-repo 或 make build"
command -v debugfs >/dev/null 2>&1 || die "缺少 debugfs（e2fsprogs）"

ROOTFS_LINK="$(ls -t "$DEPLOY_DIR"/sixlinux-image-minimal-*.ext4 2>/dev/null | head -n 1 || true)"
[[ -n "$ROOTFS_LINK" ]] && ROOTFS="$(readlink -f "$ROOTFS_LINK")"
[[ -n "$ROOTFS" && -f "$ROOTFS" ]] || die "未找到根文件系统镜像，请先执行 make build"

mkdir -p "$OUT_DIR"
WORK_DIR="$(mktemp -d /tmp/otabundle.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$ROOTFS" "$WORK_DIR/rootfs.ext4"
printf '%s\n' "$PAYLOAD_VERSION" > "$WORK_DIR/version"

# 在 payload 根文件系统里写入版本标记，方便升级后确认当前槽内容。
debugfs -w -R "rm /etc/sixlinux-ota-version" "$WORK_DIR/rootfs.ext4" >/dev/null 2>&1 || true
debugfs -w -R "write $WORK_DIR/version /etc/sixlinux-ota-version" "$WORK_DIR/rootfs.ext4" >/dev/null 2>&1 \
    || die "写入版本标记失败"

(cd "$WORK_DIR" && sha256sum rootfs.ext4 > manifest.sha256)

tar -czf "$WORK_DIR/bundle.tar.gz" -C "$WORK_DIR" rootfs.ext4 manifest.sha256 version
gpg --homedir "$KEY_HOME" --batch --yes --local-user "$(cat "$KEY_ID_FILE")" \
    --detach-sign --armor \
    --output "$WORK_DIR/bundle.tar.gz.sig" "$WORK_DIR/bundle.tar.gz"

BUNDLE_NAME="sixlinux-ota-${OTA_VERSION}.tar.gz"
cp "$WORK_DIR/bundle.tar.gz" "$OUT_DIR/$BUNDLE_NAME"
cp "$WORK_DIR/bundle.tar.gz.sig" "$OUT_DIR/$BUNDLE_NAME.sig"
cp "$WORK_DIR/version" "$OUT_DIR/version"

cat > "$OUT_DIR/ota.env" <<EOF
OTA_BUNDLE=$BUNDLE_NAME
OTA_VERSION=$OTA_VERSION
OTA_PAYLOAD_VERSION=$PAYLOAD_VERSION
OTA_ROOTFS_SHA256=$(sha256sum "$WORK_DIR/rootfs.ext4" | awk '{print $1}')
OTA_BUNDLE_SHA256=$(sha256sum "$WORK_DIR/bundle.tar.gz" | awk '{print $1}')
EOF

printf 'OTA 升级包已生成：%s/%s\n' "$OUT_DIR" "$BUNDLE_NAME"
printf '签名：%s/%s.sig\n' "$OUT_DIR" "$BUNDLE_NAME"
