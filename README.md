# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 1（P1）：Poky 最小 AArch64 镜像。**

本阶段建立固定版本的 Poky 构建环境、自定义 layer、machine、distro 和最小 image，并用直接内核启动方式验证系统。

后续阶段再加入 TF-A/U-Boot、驱动、软件仓库和 release 安全登录。

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
make boot-test-direct
```

`boot-test-direct` 会启动实际镜像，检查 AArch64、2 个 vCPU、SixLinux 标识和 systemd 状态，并正常关机。

## 当前文件

- `sources/versions.env`：固定 Poky 和 Linux 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和构建模板；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `scripts/`：源码获取、构建和直接启动脚本；
- `tests/boot-qemuarm64.py`：直接启动自动验证。

详细路线见 `docs/roadmap.md`。
