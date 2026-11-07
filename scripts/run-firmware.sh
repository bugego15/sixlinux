#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
TFA_BUILD="$ROOT_DIR/sources/arm-trusted-firmware/build/qemu/debug"
DEPLOY_DIR="${DEPLOY_DIR:-$BUILD_DIR/tmp/deploy/images/sixlinux-qemuarm64}"
DTB="$ROOT_DIR/artifacts/firmware/virt.dtb"

FIRMWARE="$TFA_BUILD/qemu_fw.rom"
KERNEL="$DEPLOY_DIR/Image"

shopt -s nullglob
rootfs_candidates=("$DEPLOY_DIR"/sixlinux-image-minimal-*.ext4)
shopt -u nullglob
if (( ${#rootfs_candidates[@]} == 0 )); then
    printf '错误：尚未生成根文件系统，请先执行 make build。\n' >&2
    exit 1
fi
ROOTFS="$(ls -t "${rootfs_candidates[@]}" | head -n 1)"

for artifact in "$FIRMWARE" "$KERNEL" "$ROOTFS" "$DTB"; do
    if [[ ! -f "$artifact" ]]; then
        printf '错误：缺少启动产物 %s。\n' "$artifact" >&2
        exit 1
    fi
done

# P2 阶段只验证手动启动链，自动化 bootcmd 在后续阶段实现。
printf 'SixLinux 由 TF-A 和 U-Boot 启动，进入 U-Boot 命令行后手工执行：\n\n'
printf '  setenv bootargs root=/dev/vda rw console=ttyAMA0 earlycon=pl011,0x09000000 keep_bootcon ip=dhcp swiotlb=0\n'
printf '  booti 0x40200000 - 0x44000000\n\n'
printf '退出 QEMU：先执行 poweroff，或按 Ctrl-A 再按 X。\n'

qemu_args=(
    -machine virt,secure=on,gic-version=3
    -cpu cortex-a53
    -smp 2
    -m 2048
    -bios "$FIRMWARE"
    -device loader,file="$KERNEL",addr=0x40200000
    -device loader,file="$DTB",addr=0x44000000
    -drive "file=$ROOTFS,if=none,format=raw,id=disk0"
    -device virtio-blk-pci,drive=disk0
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:35:02
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22
    -object rng-random,filename=/dev/urandom,id=rng0
    -device virtio-rng-pci,rng=rng0
    -serial mon:stdio
    -serial null
    -nographic
    -no-reboot
)

if [[ " $* " == *" snapshot "* ]]; then
    qemu_args+=(-snapshot)
fi

exec qemu-system-aarch64 "${qemu_args[@]}"
