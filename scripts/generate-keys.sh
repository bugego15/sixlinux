#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="$ROOT_DIR/artifacts/keys"
SECURITY_FILES_DIR="$ROOT_DIR/layers/meta-sixlinux/recipes-core/sixlinux-security/files"

mkdir -p "$KEY_DIR" "$SECURITY_FILES_DIR"

if [[ ! -f "$KEY_DIR/sixlinux-dev-key" ]]; then
    ssh-keygen -t ed25519 -f "$KEY_DIR/sixlinux-dev-key" -N '' -C sixlinux-dev >/dev/null
    printf '已生成 dev 登录密钥：%s\n' "$KEY_DIR/sixlinux-dev-key"
fi
if [[ ! -f "$KEY_DIR/ssh_host_ed25519_key" ]]; then
    ssh-keygen -t ed25519 -f "$KEY_DIR/ssh_host_ed25519_key" -N '' -C sixlinux-host >/dev/null
    printf '已生成 SSH 主机密钥：%s\n' "$KEY_DIR/ssh_host_ed25519_key"
fi

# 私钥只保留在本地 artifacts/keys；recipe 目录只放构建需要的公钥和主机私钥副本。
cp "$KEY_DIR/sixlinux-dev-key.pub" "$SECURITY_FILES_DIR/authorized_keys"
cp "$KEY_DIR/ssh_host_ed25519_key" "$KEY_DIR/ssh_host_ed25519_key.pub" "$SECURITY_FILES_DIR/"
chmod 0600 "$SECURITY_FILES_DIR/ssh_host_ed25519_key"

printf '安全登录密钥已准备好。\n'
