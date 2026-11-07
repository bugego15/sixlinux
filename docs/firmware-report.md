# 完整固件启动链报告

## 版本

- TF-A：v2.10.0，提交 `b6c0948400594e3cc4dbb5a4ef04b815d2675808`
- U-Boot：2024.01，SRCREV `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e`
- Linux：6.6.160
- QEMU：Cortex-A53、GICv3、2 vCPU、2048 MB、`secure=on`

## 启动流程

1. TF-A BL1 从 `qemu_fw.rom` 启动并加载 BL2；
2. BL2 从 FIP 加载 BL31 和 BL33；
3. BL31 初始化 GICv3、运行时服务和 PSCI；
4. BL31 跳转到地址 `0x60000000` 的 U-Boot；
5. U-Boot 自动执行固化的 `CONFIG_BOOTCOMMAND`，通过 `booti 0x40200000 - 0x44000000` 启动 Linux；
6. Linux 使用 `/dev/vda` 中的 SixLinux ext4，进入 systemd。

自动 bootcmd 由 `meta-sixlinux/recipes-bsp/u-boot/files/sixlinux.cfg` 通过 Poky 配置片段合并机制写入，不依赖手工环境变量或串口输入。

## DTB 必要调整

- 使用非 `secure` 视图导出 QEMU DTB；
- 将 `/psci/method` 从 `hvc` 改为 `smc`；
- 将 `/pl061@9030000/status` 设为 `disabled`，避免非安全 Linux 在 `secure=on` 下枚举访问该 GPIO 时触发 external abort；
- RTC 保持启用。

这些修改由 `scripts/build-firmware.sh` 通过 `fdtput` 自动完成。

## 零输入自动验证结果

`make boot-test` 不向 U-Boot 发送启动命令，已通过：

- TF-A BL1/BL2/BL31 日志存在；
- U-Boot 2024.01 自动执行 bootcmd；
- Linux 6.6.160 启动；
- PSCI v1.1 和 SMC Calling Convention 正常；
- 两个 CPU 均上线，`nproc = 2`；
- root 登录成功；
- `uname -m = aarch64`；
- `/etc/os-release` 包含 SixLinux；
- `systemctl is-system-running = running`；
- `poweroff` 正常关机。

自动 bootcmd 不会回显手工输入的 `booti` 文本。测试通过自动倒计时、DTB 地址和未进入默认 `Scanning for bootflows` 来确认启动路径。

完整串口日志：`artifacts/firmware-boot.log`。
