# 目标架构

## 当前平台

| 项目 | 当前实现 |
| --- | --- |
| 架构 | AArch64 / ARMv8-A |
| QEMU 机器 | 自定义 `sixlinux-qemuarm64`，基于 `virt` |
| CPU / 中断 | Cortex-A53、GICv3 |
| 安全启动模式 | `secure=on`，TF-A 提供 EL3/PSCI |
| 验证资源 | 2 vCPU、2048 MB RAM |
| 固件 | TF-A v2.10.0 + U-Boot 2024.01 |
| 内核 | linux-yocto 6.6.160，固定 SRCREV |
| 用户空间 | glibc、systemd、OpenSSH |
| 构建系统 | Poky 5.0.21 + 自定义 layer/DISTRO/image |
| 构建配置 | 开发模板 `qemuarm64`、发布模板 `qemuarm64-release` |
| 包格式 | ipk，支持本地 HTTP opkg feed |
| 登录策略 | `dev` 用户 + ed25519 公钥，root 和密码登录禁用 |
| 根文件系统 | ext4，另有 tar.bz2 |

## 默认启动链

```text
TF-A BL1
  → TF-A BL2
  → TF-A BL31（GICv3、PSCI、运行时服务）
  → U-Boot（BL33，0x60000000）
  → Linux Image（0x40200000）+ DTB（0x44000000）
  → SixLinux ext4 / systemd
```

`qemu_fw.rom` 由 TF-A 构建系统生成，包含 BL1 和 FIP；FIP 包含 BL2、BL31 和 U-Boot。默认 PSCI conduit 为 SMC。

## 调试回退

```text
QEMU virt → Linux Image + ext4 rootfs → systemd
```

使用 `make run-direct` 和 `make boot-test-direct`，便于隔离固件链与内核/rootfs 问题。

## 已验证设备与功能

- PL011 串口 `ttyAMA0` 和 earlycon；
- GICv3、Generic Timer、PSCI/SMC；
- 两个 CPU 上线；
- VirtIO 块设备 `/dev/vda`；
- VirtIO 用户网络，hostfwd 2222→22；
- 标准 RTC 设备 `/dev/rtc0`（项目 PL031 platform driver 注册）；
- systemd `running`；
- PSCI 正常关机；
- 板级验证套件覆盖 CPU/SMP/内存/中断/RTC/块设备/网络/systemd 共 8 项。

## 边界

QEMU `virt` 不是实际 SoC，无法完整覆盖 DDR 初始化、真实 BootROM、时钟/复位、电源域和 pinctrl。真实板卡工作必须单独验证和记录。
