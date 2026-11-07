# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 2（P2）：TF-A + U-Boot 启动链。**

本阶段在最小镜像的基础上加入 TF-A BL1/BL2/BL31 和 U-Boot BL33，构建 QEMU 固件 ROM，并在 `secure=on`、GICv3 平台下由 TF-A 把控制权交给 U-Boot，再由 U-Boot 启动 Linux。

本阶段仍由人工（或测试脚本）在 U-Boot 中输入 `booti`，自动 bootcmd 留到下一阶段。

后续阶段再加入自动启动、驱动、软件仓库和 release 安全登录。

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

`make firmware` 会构建 U-Boot 和 TF-A，导出 QEMU 设备树并修正 PSCI 与 GPIO 节点。

`make boot-test` 启动完整固件链，等待 U-Boot 命令行，依次输入 `setenv bootargs ...` 和 `booti 0x40200000 - 0x44000000`，然后检查：

- 串口日志包含 TF-A BL1/BL31 和 U-Boot 2024.01；
- 手工输入的 `setenv` 和 `booti` 出现在日志中；
- Linux 启动成功，`uname -m = aarch64`、`nproc = 2`；
- `/etc/os-release` 包含 SixLinux，`systemctl is-system-running = running`；
- `poweroff` 正常关机。

人工体验完整启动链时执行 `make run`，按屏幕提示在 U-Boot 中手工输入同样的两条命令。

## 当前文件

- `sources/versions.env`：固定 Poky、Linux、U-Boot 和 TF-A 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和构建模板；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `scripts/`：源码获取、镜像构建、固件构建和启动脚本；
- `tests/boot-qemuarm64.py`：直接内核启动自动验证；
- `tests/boot-firmware.py`：TF-A/U-Boot 手动启动链自动验证。

详细路线见 `docs/roadmap.md`。
