# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 4（P4）：PL031 RTC platform driver。**

本阶段在不修改 QEMU 的前提下，把 QEMU 自带的 PL031 RTC 从 AMBA primecell 绑定改为 platform device，并新增一个 out-of-tree 内核模块完成设备树匹配、MMIO 访问、IRQ 处理和 debugfs 观测。

具体改动：

- `scripts/build-firmware.sh` 把 `/pl031@9010000` 的 `compatible` 改为单一的 `arm,pl031`，避免进入 AMBA 总线；
- `layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/` 提供模块源码和 recipe；
- 模块注册 platform driver，映射 MMIO、申请设备树 IRQ、读取 AMBA ID 和 RTC Data Register，并通过 `/sys/kernel/debug/sixlinux_rtc/` 暴露 `id`、`data`、`irq_count`、`trigger`；
- 镜像安装 `kernel-module-sixlinux-rtc` 并自动加载。

后续阶段再加入 opkg 软件仓库和 release 安全登录。

## 开发环境

```text
Windows
└── WSL2 / Ubuntu 24.04
    ├── 交叉编译和 Yocto 构建
    ├── QEMU AArch64 仿真
    └── 自动化测试
```

- E 仓库：`E:\6linux\sixlinux`，用于版本管理和代码审阅；
- WSL 构建路径：`/home/dev/sixlinux`，用于实际构建和测试；
- 不在 `/mnt/e` 下执行 Yocto 大型构建；
- 不使用 root 运行 BitBake。

## 构建和验证

```powershell
wsl -d Ubuntu-24.04
```

```bash
cd /home/dev/sixlinux
make check-env
make fetch-poky
make build
make firmware
make boot-test
make driver-test
```

`make firmware` 构建 U-Boot、TF-A，导出 QEMU 设备树并修正 PSCI、GPIO 和 RTC 节点。

`make boot-test` 零输入验证 TF-A → U-Boot → Linux 自动启动链。

`make driver-test` 启动系统并检查 RTC 驱动：

- `modprobe sixlinux_rtc` 成功，`dmesg` 包含 `SixLinux RTC probed`；
- debugfs 读出的 AMBA ID 为 `0x00141031`（按 `0x000fffff` 掩码比较）；
- probe 时设置的 alarm 产生第一次中断，`irq_count ≥ 1`；
- 向 `trigger` 写入后产生第二次中断，计数增加；
- `poweroff` 正常关机。

## 当前文件

- `sources/versions.env`：固定 Poky、Linux、U-Boot 和 TF-A 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和构建模板；
- `layers/meta-sixlinux/recipes-bsp/u-boot/`：固化自动 bootcmd 的 U-Boot 配置片段；
- `layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/`：PL031 platform driver 源码和 recipe；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `scripts/`：源码获取、镜像构建、固件构建和启动脚本；
- `tests/boot-qemuarm64.py`：直接内核启动自动验证；
- `tests/boot-firmware.py`：TF-A/U-Boot 零输入自动启动验证；
- `tests/driver-rtc.py`：RTC MMIO/IRQ/debugfs 验证。

详细路线见 `docs/roadmap.md`。
