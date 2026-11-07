#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_HOME="$ROOT_DIR/artifacts/keys/gnupg-feed"
KEY_ID_FILE="$ROOT_DIR/artifacts/keys/feed-key-id"
CONFIG_FILES_DIR="$ROOT_DIR/layers/meta-sixlinux/recipes-core/sixlinux-opkg-config/files"
IMAGE_KEYRING_DIR="$CONFIG_FILES_DIR/gpg-home"
KEY_UID="SixLinux Feed Signing <feed@sixlinux.local>"

if ! command -v gpg >/dev/null 2>&1; then
    printf '错误：缺少 gpg，无法生成软件源签名密钥。\n' >&2
    exit 1
fi

mkdir -p "$KEY_HOME" "$CONFIG_FILES_DIR"
chmod 0700 "$KEY_HOME"

if [[ ! -s "$KEY_HOME/pubring.kbx" ]]; then
    printf '生成 SixLinux 软件源签名密钥...\n'
    rm -rf "$KEY_HOME"
    mkdir -p "$KEY_HOME"
    chmod 0700 "$KEY_HOME"
    cat > "$KEY_HOME/genkey.conf" <<EOF
%echo generating sixlinux feed signing key
Key-Type: RSA
Key-Length: 3072
Key-Usage: sign
Name-Real: SixLinux Feed Signing
Name-Email: feed@sixlinux.local
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
    gpg --homedir "$KEY_HOME" --batch --gen-key "$KEY_HOME/genkey.conf" >/dev/null 2>&1
fi

FINGERPRINT="$(gpg --homedir "$KEY_HOME" --batch --with-colons --list-keys "$KEY_UID" 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')"
if [[ -z "$FINGERPRINT" ]]; then
    printf '错误：无法获取软件源签名密钥指纹。\n' >&2
    exit 1
fi
printf '%s\n' "$FINGERPRINT" > "$KEY_ID_FILE"

# 把签名密钥标记为完全信任，满足 opkg 默认的 TrustOnly 校验。
printf '%s:6:\n' "$FINGERPRINT" | gpg --homedir "$KEY_HOME" --batch --import-ownertrust >/dev/null 2>&1 || true
gpg --homedir "$KEY_HOME" --batch --check-trustdb >/dev/null 2>&1 || true

# 导出公钥（供人工核对）并准备镜像内的 keyring 副本。
gpg --homedir "$KEY_HOME" --batch --armor --export "$FINGERPRINT" > "$CONFIG_FILES_DIR/sixlinux-feed.asc"
rm -rf "$IMAGE_KEYRING_DIR"
mkdir -p "$IMAGE_KEYRING_DIR"
cp "$KEY_HOME/pubring.kbx" "$IMAGE_KEYRING_DIR/"
if [[ -f "$KEY_HOME/trustdb.gpg" ]]; then
    cp "$KEY_HOME/trustdb.gpg" "$IMAGE_KEYRING_DIR/"
fi
chmod 0600 "$IMAGE_KEYRING_DIR"/*

printf '软件源签名密钥已就绪：%s\n' "$FINGERPRINT"
