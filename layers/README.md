# 项目 Layers

`meta-sixlinux` 是本阶段建立的最小 Yocto layer，当前包含：

- `conf/layer.conf`：layer 注册和 Scarthgap 兼容声明；
- `conf/distro/sixlinux.conf`：无桌面、systemd 的发行版配置；
- `conf/machine/sixlinux-qemuarm64.conf`：Cortex-A53、GICv3、2 vCPU、2 GB QEMU 配置；
- `conf/templates/qemuarm64/`：可复现的构建目录模板；
- `recipes-core/images/sixlinux-image-minimal.bb`：带 OpenSSH 的最小镜像。

后续阶段再逐步加入 TF-A/U-Boot、RTC 驱动、opkg 配置和安全 release 配置。
