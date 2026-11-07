# 项目 Layers

`meta-sixlinux` 是本阶段建立的最小 Yocto layer，当前包含：

- `conf/layer.conf`：layer 注册和 Scarthgap 兼容声明；
- `conf/distro/sixlinux.conf`：无桌面、systemd 的发行版配置；
- `conf/machine/sixlinux-qemuarm64.conf`：Cortex-A53、GICv3、2 vCPU、2 GB QEMU 配置；
- `conf/templates/qemuarm64/`：可复现的构建目录模板；
- `recipes-bsp/u-boot/`：U-Boot 配置片段，固化自动 `CONFIG_BOOTCOMMAND`；
- `recipes-kernel/sixlinux-rtc-driver/`：PL031 RTC platform driver 模块源码与 recipe；
- `recipes-apps/sixlinux-hello/`：hello 软件包 recipe；
- `recipes-core/sixlinux-opkg-config/`：目标系统的 opkg feed 配置；
- `recipes-core/images/sixlinux-image-minimal.bb`：带 OpenSSH、RTC 模块和 opkg 配置的最小镜像。

TF-A 不进入 Yocto 构建，由 `scripts/build-firmware.sh` 以 Yocto 部署的 U-Boot 作为 BL33 单独编译。

`recipes-apps/sixlinux-hello/` 在仓库中保存 1.1 版本的 recipe；`scripts/build-package-repo.sh` 会轮流放入 1.0/1.1 源码进行构建。

后续阶段再加入安全 release 配置。
