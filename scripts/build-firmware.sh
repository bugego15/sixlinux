#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TFA_DIR="$ROOT_DIR/sources/arm-trusted-firmware"
DEPLOY_DIR="$ROOT_DIR/build/qemuarm64/tmp/deploy/images/sixlinux-qemuarm64"
UBOOT_BIN="$DEPLOY_DIR/u-boot-sixlinux-qemuarm64-2024.01-r0.bin"
DTB="$ROOT_DIR/artifacts/firmware/virt.dtb"

if (( EUID == 0 )); then
    printf '错误：请使用 dev 用户构建固件。\n' >&2
    exit 1
fi

bash "$ROOT_DIR/scripts/fetch-firmware.sh"
bash "$ROOT_DIR/scripts/build-qemuarm64.sh" u-boot

if [[ ! -f "$UBOOT_BIN" ]]; then
    printf '错误：未找到 U-Boot 产物 %s。\n' "$UBOOT_BIN" >&2
    exit 1
fi

# QEMU 平台默认编译 GICv2，这里必须与 machine 的 GICv3 配置一致。
# BL33 直接使用 Yocto 部署的 U-Boot 二进制。
make -C "$TFA_DIR" \
    PLAT=qemu \
    CROSS_COMPILE=aarch64-linux-gnu- \
    DEBUG=1 \
    LOG_LEVEL=40 \
    QEMU_USE_GIC_DRIVER=QEMU_GICV3 \
    BL33="$UBOOT_BIN" \
    -j8 all

# 导出非安全世界设备树，再为 TF-A/Non-secure Linux 做必要调整。
mkdir -p "$(dirname -- "$DTB")"
qemu-system-aarch64 \
    -machine virt,gic-version=3,dumpdtb="$DTB" \
    -cpu cortex-a53 \
    -smp 2 \
    -m 2048 \
    -display none

# QEMU 默认 PSCI 为 HVC；EL3 TF-A 需要使用 SMC。
fdtput -t s "$DTB" /psci method smc
# secure=on 下该 GPIO 不允许非安全 Linux 直接枚举访问。
fdtput -t s "$DTB" /pl061@9030000 status disabled

printf '固件构建完成：%s\n' "$TFA_DIR/build/qemu/debug/qemu_fw.rom"
printf 'U-Boot 产物：%s\n' "$UBOOT_BIN"
printf '设备树已生成：%s\n' "$DTB"
