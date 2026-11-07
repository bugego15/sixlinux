# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 5（P5）：opkg 在线软件仓库。**

本阶段把镜像升级为可安装软件包的系统：使用 `package_ipk` 生成软件包，在 WSL 中通过 HTTP 提供 feed，目标系统用 opkg 完成 `update`、指定版本安装和在线升级。

具体改动：

- 新增 `sixlinux-hello` 的 1.0 和 1.1 两套 recipe 与源码，`scripts/build-package-repo.sh` 依次构建两个版本，再用 `opkg-make-index -a` 生成保留多版本的 feed；
- 新增 `sixlinux-opkg-config`，把 `all`、`cortexa53`、`sixlinux_qemuarm64` 三个源写入 `/etc/opkg/sixlinux.conf`，地址指向 QEMU slirp 网关 `10.0.2.2:8080`；
- 镜像启用 `package-management` 并安装仓库配置；
- `tests/opkg-repo.py` 自动启动 HTTP 服务、登录系统并验证安装与升级。

后续阶段再加入 release 安全登录和 CI。

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
make package-repo
make opkg-test
```

`make package-repo` 构建 hello 1.0/1.1 并生成 `build/qemuarm64/tmp/deploy/ipk` 下的软件仓库索引。

`make opkg-test` 启动本地 HTTP feed 和 SixLinux，检查：

- `opkg update` 成功读取三个源；
- `opkg list sixlinux-hello` 显示最新 1.1；
- `opkg install sixlinux-hello=1.0-r0` 安装 1.0，运行输出 `SixLinux hello v1.0`；
- `opkg upgrade sixlinux-hello` 升级到 1.1，运行输出 `SixLinux hello v1.1`；
- 正常关机并清理 HTTP 服务。

## 当前文件

- `sources/versions.env`：固定 Poky、Linux、U-Boot 和 TF-A 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和构建模板；
- `layers/meta-sixlinux/recipes-bsp/u-boot/`：固化自动 bootcmd 的 U-Boot 配置片段；
- `layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/`：PL031 platform driver 源码和 recipe；
- `layers/meta-sixlinux/recipes-apps/sixlinux-hello/`：hello 软件包 recipe（构建仓库时由脚本在 1.0/1.1 之间切换）；
- `layers/meta-sixlinux/recipes-core/sixlinux-opkg-config/`：目标系统 opkg feed 配置；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `packages/sixlinux-hello/v1.0`、`v1.1`：两个版本的软件包源码；
- `scripts/`：源码获取、镜像构建、固件构建、仓库构建和启动脚本；
- `tests/`：直接启动、固件启动、RTC 驱动和 opkg 仓库的自动验证脚本。

详细路线见 `docs/roadmap.md`。
