# P2 验证记录

## 阶段目标

在最小镜像的基础上加入 TF-A 和 U-Boot，构建 QEMU 固件 ROM，验证完整的三级启动链：

1. QEMU 从 `qemu_fw.rom` 启动 TF-A BL1；
2. BL2 从 FIP 加载 BL31 和 BL33（U-Boot）；
3. BL31 初始化 GICv3 和 PSCI，跳转到 `0x60000000` 的 U-Boot；
4. U-Boot 中手工输入 `booti` 启动 Linux。

自动 bootcmd 属于下一阶段，本阶段有意保留手工输入。

## 版本

- TF-A：v2.10.0，提交 `b6c0948400594e3cc4dbb5a4ef04b815d2675808`；
- U-Boot：2024.01，SRCREV `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e`；
- Linux：6.6.160；
- QEMU：Cortex-A53、GICv3、2 vCPU、2048 MB、`secure=on`。

## 执行命令

```bash
cd /home/dev/sixlinux
make fetch-poky
make build
make firmware
make boot-test
```

## 构建结果

- U-Boot 由 BitBake 按 Poky 固定的 SRCREV 构建，1104 个任务全部成功（其中 49 个实际执行，其余来自 sstate 缓存）；
- TF-A 使用 `QEMU_USE_GIC_DRIVER=QEMU_GICV3` 和 `BL33=u-boot.bin` 构建，生成 64 MB 的 `qemu_fw.rom`；
- QEMU 导出的设备树做了两处调整：`/psci/method` 改为 `smc`，`/pl061@9030000/status` 设为 `disabled`。

## 启动结果

串口日志确认：

- TF-A BL1、BL2、BL31 均输出版本日志；
- BL31 检测到 GICv3 并在 EL3 初始化，最大 SPI 为 287；
- BL31 跳转到 `0x60000000` 的 U-Boot；
- `U-Boot 2024.01` 启动，识别 2 GiB DRAM 和 virtio-net；
- 自动化测试在 U-Boot 命令行输入 `setenv bootargs ...` 和 `booti 0x40200000 - 0x44000000`；
- Linux 通过 SMC 使用 PSCI v1.1，`SMC Calling Convention v1.4`；
- `CPU: All CPU(s) started at EL1`，两个 CPU 均上线；
- root 登录成功，`uname -m = aarch64`、`nproc = 2`；
- `/etc/os-release` 包含 SixLinux，`systemctl is-system-running = running`；
- `poweroff` 正常关机，QEMU 退出。

串口日志：`artifacts/firmware-boot.log`。

## 已知警告

- TF-A 在 BL1/BL31 阶段提示 Cortex-A53 的 835769、843419、855873、1530924 勘误规避缺失：这是 QEMU 通用平台的预期警告，不影响仿真启动；
- U-Boot 提示 `bad CRC, using default environment`：固件 ROM 中没有持久化环境变量，本阶段本来就不依赖保存的环境，测试使用 `-snapshot` 磁盘启动也不会写回环境。

## 阶段提交

- `8bb05c0 feat: 添加 TF-A 和 U-Boot 启动链`

本阶段尚未固化自动 bootcmd，也没有 RTC 驱动、opkg 软件仓库和 release 安全配置，后续阶段继续实现。
