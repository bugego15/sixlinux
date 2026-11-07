# P3 验证记录

## 阶段目标

把 P2 中手工输入的 `setenv bootargs` 和 `booti` 固化进 U-Boot，验证从上电到登录的零输入自动启动链：

1. TF-A BL1 → BL2 → BL31；
2. BL31 跳转到 `0x60000000` 的 U-Boot BL33；
3. U-Boot 执行固化的 `CONFIG_BOOTCOMMAND`；
4. Linux 自动启动并进入 systemd，全程不向串口输入任何命令。

## 实现方式

- `layers/meta-sixlinux/recipes-bsp/u-boot/u-boot_%.bbappend` 把 `sixlinux.cfg` 加入 `SRC_URI`；
- `files/sixlinux.cfg` 覆盖 `CONFIG_BOOTCOMMAND`：

```text
CONFIG_BOOTCOMMAND="setenv bootargs root=/dev/vda rw console=ttyAMA0 earlycon=pl011,0x09000000 keep_bootcon ip=dhcp swiotlb=0; booti 0x40200000 - 0x44000000"
```

- Poky 的 `u-boot-configure.inc` 自动收集 `SRC_URI` 中的 `*.cfg`，用 `merge_config.sh` 合并进 `.config`；
- `scripts/run-firmware.sh` 去掉手工命令提示，`tests/boot-firmware.py` 改为零输入测试。

## 执行命令

```bash
cd /home/dev/sixlinux
make fetch-poky
make build
make firmware
make boot-test
```

## 构建结果

- `merge_config.sh` 日志确认配置片段生效：

```text
Value of CONFIG_BOOTCOMMAND is redefined by fragment .../sixlinux.cfg:
Previous value: CONFIG_BOOTCOMMAND="bootflow scan -lb"
New value: CONFIG_BOOTCOMMAND="setenv bootargs root=...; booti 0x40200000 - 0x44000000"
```

- U-Boot 1104 个 BitBake 任务全部成功（23 个实际执行，其余来自 sstate）；
- 新 U-Boot 被重新链入 TF-A：BL33 大小从 `0xFFDD8` 变为 `0xFFE50`，`qemu_fw.rom` 重新生成。

## 启动结果

`make boot-test` 在登录前不发送任何输入，验证通过：

- 串口日志包含 TF-A BL1/BL31 和 `U-Boot 2024.01`；
- U-Boot 倒计时 `2 → 1 → 0` 后自动执行 bootcmd；
- 自动 `booti` 输出 `## Flattened Device Tree blob at 44000000`；
- 没有出现 `Scanning for bootflows`，说明没有回退到默认启动扫描；
- 日志中没有 `setenv bootargs` 回显，说明启动不依赖手工输入；
- Linux 通过 SMC 使用 PSCI v1.1，`uname -m = aarch64`、`nproc = 2`；
- `/etc/os-release` 包含 SixLinux，`systemctl is-system-running = running`；
- `poweroff` 正常关机，QEMU 退出。

串口日志：`artifacts/firmware-boot.log`。

## 已知警告

与 P2 一致：TF-A 的 Cortex-A53 勘误规避提示是 QEMU 通用平台的预期警告；U-Boot 的 `bad CRC, using default environment` 说明 ROM 中没有持久化环境变量，本阶段启动命令已固化在二进制里，不依赖保存的环境。

## 阶段提交

- `978d7c6 feat: 固化 U-Boot 自动启动命令`

本阶段尚未加入 RTC 驱动、opkg 软件仓库和 release 安全配置，后续阶段继续实现。
