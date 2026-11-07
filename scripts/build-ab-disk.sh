#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/sixlinux-qemuarm64"
OUT_DIR="${AB_OUT_DIR:-$ROOT_DIR/artifacts/ab}"
IMAGE="${AB_IMAGE_OUT:-$OUT_DIR/sixlinux-ab.img}"
BOOT_SIZE_MB=32
ROOT_RESERVE_MB=16

if (( EUID == 0 )); then
    printf '错误：请使用 dev 用户构建 A/B 磁盘。\n' >&2
    exit 1
fi

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

[[ -f "$DEPLOY_DIR/Image" ]] || die "未找到内核镜像，请先执行 make build"
[[ -f "$ROOT_DIR/artifacts/firmware/virt.dtb" ]] || die "未找到设备树，请先执行 make firmware"

ROOTFS_LINK="$(ls -t "$DEPLOY_DIR"/sixlinux-image-minimal-*.ext4 2>/dev/null | head -n 1 || true)"
[[ -n "$ROOTFS_LINK" ]] && ROOTFS="$(readlink -f "$ROOTFS_LINK")"
[[ -n "$ROOTFS" && -f "$ROOTFS" ]] || die "未找到根文件系统镜像，请先执行 make build"

MKIMAGE="$(find "$BUILD_DIR/tmp/work" -path "*u-boot*/build/tools/mkimage" -type f 2>/dev/null | head -n 1 || true)"
[[ -n "$MKIMAGE" ]] || die "未找到 mkimage，请先执行 make build"

BOOT_CMD="$ROOT_DIR/layers/meta-sixlinux/recipes-bsp/u-boot/files/boot-ab.cmd"
[[ -f "$BOOT_CMD" ]] || die "未找到 boot-ab.cmd"

for tool in mkfs.vfat mcopy sfdisk truncate dd; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少主机工具：$tool"
done

mkdir -p "$OUT_DIR"
WORK_DIR="$(mktemp -d /tmp/abdisk.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

printf '生成 boot.scr...\n'
"$MKIMAGE" -A arm64 -T script -C none -n "SixLinux A/B boot" \
    -d "$BOOT_CMD" "$WORK_DIR/boot.scr" >/dev/null

printf '准备 FAT 启动分区...\n'
BOOT_IMG="$WORK_DIR/boot.vfat"
truncate -s "${BOOT_SIZE_MB}M" "$BOOT_IMG"
mkfs.vfat -F 16 -n BOOT "$BOOT_IMG" >/dev/null
mcopy -i "$BOOT_IMG" "$DEPLOY_DIR/Image" ::Image
mcopy -i "$BOOT_IMG" "$ROOT_DIR/artifacts/firmware/virt.dtb" ::virt.dtb
mcopy -i "$BOOT_IMG" "$WORK_DIR/boot.scr" ::boot.scr
printf 'slot=a\nprev=b\npending=0\nbootcount=0\n' > "$WORK_DIR/state.env"
mcopy -i "$BOOT_IMG" "$WORK_DIR/state.env" ::state.env

ROOTFS_BYTES="$(stat -c %s "$ROOTFS")"
ROOT_MB=$(( (ROOTFS_BYTES + 1048575) / 1048576 + ROOT_RESERVE_MB ))

# MBR 布局（1 MiB 对齐）：
#   p1: FAT 启动分区（boot.scr / Image / virt.dtb / state.env）
#   p2: rootfs slot A
#   p3: rootfs slot B
P1_START_MB=1
P1_SIZE_MB=$BOOT_SIZE_MB
P2_START_MB=$((P1_START_MB + P1_SIZE_MB))
P2_SIZE_MB=$ROOT_MB
P3_START_MB=$((P2_START_MB + P2_SIZE_MB))
P3_SIZE_MB=$ROOT_MB
TOTAL_MB=$((P3_START_MB + P3_SIZE_MB + 1))

printf '磁盘布局：p1=%dMiB@p1=%d, p2=%dMiB@%d, p3=%dMiB@%d, 总计=%dMiB\n' \
    "$P1_SIZE_MB" "$P1_START_MB" "$P2_SIZE_MB" "$P2_START_MB" \
    "$P3_SIZE_MB" "$P3_START_MB" "$TOTAL_MB"

truncate -s "${TOTAL_MB}M" "$IMAGE"
P1_START_SEC=$((P1_START_MB * 2048))
P1_SIZE_SEC=$((P1_SIZE_MB * 2048))
P2_START_SEC=$((P2_START_MB * 2048))
P2_SIZE_SEC=$((P2_SIZE_MB * 2048))
P3_START_SEC=$((P3_START_MB * 2048))
P3_SIZE_SEC=$((P3_SIZE_MB * 2048))

sfdisk -q "$IMAGE" <<EOF
label: dos
start=$P1_START_SEC, size=$P1_SIZE_SEC, type=c, bootable
start=$P2_START_SEC, size=$P2_SIZE_SEC, type=83
start=$P3_START_SEC, size=$P3_SIZE_SEC, type=83
EOF

printf '写入启动分区和双槽根文件系统...\n'
dd if="$BOOT_IMG" of="$IMAGE" bs=1M seek="$P1_START_MB" conv=notrunc status=none
dd if="$ROOTFS" of="$IMAGE" bs=1M seek="$P2_START_MB" conv=notrunc status=none
dd if="$ROOTFS" of="$IMAGE" bs=1M seek="$P3_START_MB" conv=notrunc status=none
sync

cat > "$OUT_DIR/base.env" <<EOF
AB_IMAGE=$IMAGE
AB_BOOT_START_MB=$P1_START_MB
AB_BOOT_SIZE_MB=$P1_SIZE_MB
AB_SLOT_A_START_MB=$P2_START_MB
AB_SLOT_A_SIZE_MB=$P2_SIZE_MB
AB_SLOT_B_START_MB=$P3_START_MB
AB_SLOT_B_SIZE_MB=$P3_SIZE_MB
AB_TOTAL_MB=$TOTAL_MB
AB_ROOTFS_SHA256=$(sha256sum "$ROOTFS" | awk '{print $1}')
EOF

printf 'A/B 磁盘已生成：%s（%d MiB）\n' "$IMAGE" "$TOTAL_MB"
printf '布局信息：%s/base.env\n' "$OUT_DIR"
