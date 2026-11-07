#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if (( EUID == 0 )); then
    printf '错误：请使用非 root 用户执行项目检查和后续 Yocto 构建。\n' >&2
    exit 1
fi

required_commands=(
    git make gcc g++ python3 locale
    qemu-system-aarch64 qemu-img
    aarch64-linux-gnu-gcc aarch64-linux-gnu-g++
    dtc fdtput chrpath socat cpio zstd lz4
    bison flex openssl expect parted sfdisk mkfs.vfat mcopy debugfs
    ssh ssh-keygen sha256sum gpg gpgv
)
missing=()

for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

if (( ${#missing[@]} > 0 )); then
    printf '错误：缺少以下主机命令：\n' >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
fi

if [[ "$ROOT_DIR" == /mnt/* ]]; then
    printf '错误：项目位于 /mnt 下，请将构建目录放在 WSL 原生 ext4 文件系统。\n' >&2
    exit 1
fi

if ! locale -a | awk 'tolower($0) == "en_us.utf8" { found = 1 } END { exit !found }'; then
    printf '错误：缺少 BitBake 所需的 en_US.UTF-8 locale。\n' >&2
    exit 1
fi

printf '项目目录：%s\n' "$ROOT_DIR"
printf '当前用户：%s\n' "$(id -un)"
printf '主机架构：%s\n' "$(uname -m)"
python3 --version
qemu-system-aarch64 --version | sed -n '1p'
aarch64-linux-gnu-gcc --version | sed -n '1p'

if qemu-system-aarch64 -cpu help | awk '$1 == "cortex-a53" { found = 1 } END { exit !found }'; then
    printf 'QEMU CPU 模型：cortex-a53 可用\n'
else
    printf '错误：当前 QEMU 不支持 cortex-a53 CPU 模型。\n' >&2
    exit 1
fi

printf '项目文件系统：\n'
df -h "$ROOT_DIR" | sed -n '1,2p'
printf '环境检查通过。\n'
