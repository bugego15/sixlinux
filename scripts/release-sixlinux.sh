#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.1.0"
RELEASE_DIR="$ROOT_DIR/artifacts/releases/sixlinux-$VERSION"
DEPLOY_DIR="$ROOT_DIR/build/qemuarm64-release/tmp/deploy/images/sixlinux-qemuarm64"
TFA_ROM="$ROOT_DIR/sources/arm-trusted-firmware/build/qemu/debug/qemu_fw.rom"

bash "$ROOT_DIR/scripts/build-release.sh" "$@"
mkdir -p "$RELEASE_DIR"

kernel="$(ls -t "$DEPLOY_DIR"/Image--*.bin | head -n 1)"
rootfs="$(ls -t "$DEPLOY_DIR"/sixlinux-image-minimal-*.ext4 | head -n 1)"
rootfs_tar="$(ls -t "$DEPLOY_DIR"/sixlinux-image-minimal-*.tar.bz2 | head -n 1)"
manifest="$(ls -t "$DEPLOY_DIR"/sixlinux-image-minimal-*.manifest | head -n 1)"

cp "$kernel" "$RELEASE_DIR/Image"
cp "$rootfs" "$RELEASE_DIR/sixlinux-$VERSION.ext4"
cp "$rootfs_tar" "$RELEASE_DIR/sixlinux-$VERSION.tar.bz2"
cp "$manifest" "$RELEASE_DIR/sixlinux-image-minimal.manifest"
cp "$TFA_ROM" "$RELEASE_DIR/qemu_fw.rom"
cp "$ROOT_DIR/artifacts/firmware/virt.dtb" "$RELEASE_DIR/virt.dtb"

# shellcheck disable=SC1091
source "$ROOT_DIR/sources/versions.env"
cat > "$RELEASE_DIR/release-info.env" <<EOF
RELEASE_VERSION=$VERSION
RELEASE_DATE_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MACHINE=sixlinux-qemuarm64
DISTRO=sixlinux
POKY_COMMIT=$POKY_COMMIT
LINUX_YOCTO_COMMIT=$LINUX_YOCTO_COMMIT
TFA_COMMIT=$TFA_COMMIT
UBOOT_COMMIT=$UBOOT_COMMIT
SSH_USER=dev
SSH_PRIVATE_KEY=artifacts/keys/sixlinux-dev-key
EOF

cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<'EOF'
# SixLinux 0.1.0

## 内容

- TF-A BL1/BL2/BL31 + U-Boot BL33
- Linux 6.6.160 / systemd / OpenSSH
- RTC platform driver、opkg feed、AArch64 ext4 和 tar.bz2

## 安全策略

- 不包含 debug-tweaks，root 密码锁定
- 禁止 root SSH 登录
- 禁止密码和键盘交互认证，仅允许 dev 用户的 ed25519 公钥认证

启动后通过以下方式登录（端口 2222 转发到访客 22）：

```bash
ssh -i artifacts/keys/sixlinux-dev-key \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 dev@127.0.0.1
```

发布私钥只保留在本地 artifacts/keys 中，不应提交到公共仓库。
EOF

(
    cd "$RELEASE_DIR"
    sha256sum Image sixlinux-$VERSION.ext4 sixlinux-$VERSION.tar.bz2 \
        qemu_fw.rom virt.dtb sixlinux-image-minimal.manifest > SHA256SUMS
)

printf '发布目录已生成：%s\n' "$RELEASE_DIR"
