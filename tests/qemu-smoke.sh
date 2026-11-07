#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
    '{"execute":"qmp_capabilities"}' \
    '{"execute":"quit"}' \
| timeout 15s qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    -cpu cortex-a53 \
    -smp 2 \
    -m 2G \
    -display none \
    -serial none \
    -monitor none \
    -S \
    -qmp stdio

printf 'QEMU Cortex-A53 平台实例化测试通过（尚未加载内核）。\n'
