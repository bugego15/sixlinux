#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${AB_IMAGE:-$ROOT_DIR/artifacts/ab/sixlinux-ab.img}"
SSH_PORT="${SSH_PORT:-2225}"
FIRMWARE="$ROOT_DIR/sources/arm-trusted-firmware/build/qemu/debug/qemu_fw.rom"

if [[ ! -f "$IMAGE" ]]; then
    printf '错误：未找到 A/B 磁盘 %s，请先执行 make ab-disk。\n' "$IMAGE" >&2
    exit 1
fi
if [[ ! -f "$FIRMWARE" ]]; then
    printf '错误：未找到 TF-A 固件，请先执行 make firmware。\n' >&2
    exit 1
fi

printf 'SixLinux A/B 启动：%s\n' "$IMAGE"
printf '主机 SSH 转发端口：%s\n' "$SSH_PORT"

qemu_args=(
    -machine virt,secure=on,gic-version=3
    -cpu cortex-a53
    -smp 2
    -m 2048
    -bios "$FIRMWARE"
    -drive "file=$IMAGE,if=none,format=raw,id=disk0"
    -device virtio-blk-pci,drive=disk0
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:35:04
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
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
