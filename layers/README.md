# 项目 Layers

`meta-sixlinux` 是本阶段建立的最小 Yocto layer，当前包含：

- `conf/layer.conf`：layer 注册和 Scarthgap 兼容声明；
- `conf/distro/sixlinux.conf`：无桌面、systemd 的发行版配置；
- `conf/machine/sixlinux-qemuarm64.conf`：Cortex-A53、GICv3、2 vCPU、2 GB QEMU 配置；
- `conf/templates/qemuarm64/`：开发构建目录模板（含 debug-tweaks）；
- `conf/templates/qemuarm64-release/`：发布构建目录模板（不含 debug-tweaks）；
- `recipes-bsp/u-boot/`：U-Boot 配置片段，固化自动 `CONFIG_BOOTCOMMAND`；
- `recipes-kernel/sixlinux-rtc-driver/`：PL031 RTC platform driver 模块源码与 recipe（同时注册 `/dev/rtc0`）；
- `recipes-apps/sixlinux-hello/`：hello 软件包 recipe；
- `recipes-apps/sixlinux-boardtest/`：板级验证套件（CPU/SMP/内存/中断/RTC/块设备/网络/systemd）；
- `recipes-core/sixlinux-opkg-config/`：目标系统的 opkg feed 配置；
- `recipes-core/sixlinux-security/`：release 的 dev 用户、SSH 公钥登录和 sudo 配置；
- `recipes-core/images/sixlinux-image-minimal.bb`：带 OpenSSH、RTC 模块、板级测试、opkg 配置和安全登录的最小镜像。

TF-A 不进入 Yocto 构建，由 `scripts/build-firmware.sh` 以 Yocto 部署的 U-Boot 作为 BL33 单独编译。

`recipes-apps/sixlinux-hello/` 在仓库中保存 1.1 版本的 recipe；`scripts/build-package-repo.sh` 会轮流放入 1.0/1.1 源码进行构建。

`recipes-core/sixlinux-security/files/` 中的密钥材料由 `scripts/generate-keys.sh` 在构建前生成，不提交到仓库。
