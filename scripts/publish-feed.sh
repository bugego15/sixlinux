#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/qemuarm64}"
FEED_SRC="$BUILD_DIR/tmp/deploy/ipk"
FEED_DEST="${FEED_PUBLISH_DIR:-$ROOT_DIR/artifacts/feed/published}"

if (( EUID == 0 )); then
    printf '错误：请使用 dev 用户发布软件源。\n' >&2
    exit 1
fi

if [[ ! -d "$FEED_SRC" ]]; then
    printf '错误：未找到软件仓库 %s，请先执行 make package-repo。\n' "$FEED_SRC" >&2
    exit 1
fi

for feed in all cortexa53 sixlinux_qemuarm64; do
    if [[ ! -f "$FEED_SRC/$feed/Packages.asc" ]]; then
        printf '错误：%s 缺少 Packages.asc 签名，请先执行 make package-repo。\n' "$feed" >&2
        exit 1
    fi
done

rm -rf "$FEED_DEST"
mkdir -p "$FEED_DEST"
cp -a "$FEED_SRC"/. "$FEED_DEST"/

cat > "$FEED_DEST/README.txt" <<'EOF'
SixLinux signed opkg feed

目录布局：
  all/                 与架构无关的包
  cortexa53/           ARMv8-A Cortex-A53 包
  sixlinux_qemuarm64/  机器相关包

每个目录都包含：
  Packages      未压缩索引（签名对象）
  Packages.gz   目标端实际下载的压缩索引
  Packages.asc  Packages 的 ASCII 装甲分离签名
  *.ipk         软件包

目标系统通过 /etc/opkg/sixlinux.conf 访问本目录，并使用
/etc/opkg/gpg 中的公钥校验 Packages.asc。
EOF

printf '已发布软件源到：%s\n' "$FEED_DEST"
printf '\n本地 HTTP 服务示例：\n'
printf '  cd "%s" && python3 -m http.server 8080 --bind 0.0.0.0\n' "$FEED_DEST"
printf '\n目标系统在 local.conf 中设置源地址后重新构建镜像：\n'
printf '  SIXLINUX_FEED_BASE = "http://<host>:8080"\n'
