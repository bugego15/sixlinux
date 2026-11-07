# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 3（P3）：U-Boot 自动启动。**

本阶段把 P2 中手工输入的 `setenv bootargs` 和 `booti` 固化进 U-Boot 的 `CONFIG_BOOTCOMMAND`，通过 meta-sixlinux 的配置片段合并机制写入构建，不再依赖串口输入或手工环境变量。

从上电到登录的完整链路为：TF-A BL1 → BL2 → BL31 → U-Boot BL33 → 自动 `booti` → SixLinux。

后续阶段再加入 RTC 驱动、软件仓库和 release 安全登录。

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
```

`make firmware` 会构建带 `CONFIG_BOOTCOMMAND` 配置片段的 U-Boot、TF-A，导出 QEMU 设备树并修正 PSCI 与 GPIO 节点。

`make boot-test` 不向 U-Boot 输入任何命令，直接等待系统自动启动并登录，然后检查：

- 串口日志包含 TF-A BL1/BL31 和 U-Boot 2024.01；
- 自动 `booti` 输出了 `## Flattened Device Tree blob at 44000000`；
- 没有回退到 `Scanning for bootflows`，也没有手工命令回显；
- Linux 启动成功，`uname -m = aarch64`、`nproc = 2`；
- `/etc/os-release` 包含 SixLinux，`systemctl is-system-running = running`；
- `poweroff` 正常关机。

人工观察完整自动启动流程时执行 `make run`，登录后可以自己执行检查和关机。

## 当前文件

- `sources/versions.env`：固定 Poky、Linux、U-Boot 和 TF-A 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和构建模板；
- `layers/meta-sixlinux/recipes-bsp/u-boot/`：固化自动 bootcmd 的 U-Boot 配置片段；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `scripts/`：源码获取、镜像构建、固件构建和启动脚本；
- `tests/boot-qemuarm64.py`：直接内核启动自动验证；
- `tests/boot-firmware.py`：TF-A/U-Boot 零输入自动启动验证。

详细路线见 `docs/roadmap.md`。
