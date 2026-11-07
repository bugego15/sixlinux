# P4 验证记录

## 阶段目标

在 QEMU 自带的 PL031 RTC 上完成一个真实的 platform driver 实验：设备树绑定、MMIO、IRQ 和 debugfs，不修改 QEMU 源码。

## 实现内容

### 设备树

`scripts/build-firmware.sh` 在 P2/P3 的基础上增加一条修改：

```bash
fdtput -t s "$DTB" /pl031@9010000 compatible arm,pl031
```

PL031 原来的兼容字符串是 `arm,pl031` + `arm,primecell`，会进入 AMBA 总线并由上游 AMBA RTC 驱动接管。去掉 `arm,primecell` 后，设备作为 platform device 创建，由项目自己的 platform driver 匹配。

### 驱动

`layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/`：

- `sixlinux_rtc.c`：platform driver，做 MMIO 映射、IRQ 申请、AMBA ID/Data 读取，并提供 debugfs；
- `Makefile`：out-of-tree Kbuild，提供 `modules`、`modules_install`、`clean`；
- `LICENSE`：GPL-2.0-only。

debugfs 接口位于 `/sys/kernel/debug/sixlinux_rtc/`：

| 文件 | 用途 |
| --- | --- |
| `id` | AMBA ID，允许变体位，按 `0x000fffff` 掩码比较 |
| `data` | RTC Data Register 当前值 |
| `irq_count` | 已处理的 alarm 中断次数 |
| `trigger` | 写入非零值，设置 `DR + 1` 并使能一次 alarm |

### Yocto 集成

- `sixlinux-rtc-driver_1.0.bb` 使用 `inherit module` 和 `MAKE_TARGETS = "modules"`；
- `layer.conf` 显式加入 recipe 路径；
- 镜像 recipe 通过 `IMAGE_INSTALL:append = " kernel-module-sixlinux-rtc"` 安装模块；
- `KERNEL_MODULE_AUTOLOAD` 生成 `modules-load.d` 配置，开机自动加载。

### 测试脚本

- `tests/driver-rtc.py` 自动登录、加载模块、读取 debugfs、等待中断、触发新中断并检查 `dmesg`；
- 自动化测试通过 `SSH_PORT=none` 关闭 QEMU 的主机端口转发，因此本机同时开着手工 QEMU 时也不会因 2222 端口冲突失败。

## 执行命令

```bash
cd /home/dev/sixlinux
make build
make firmware
make driver-test
```

## 构建结果

- 镜像 3157 个 BitBake 任务全部成功（46 个实际执行，其余来自 sstate）；
- TF-A 使用新的 U-Boot BL33 重新生成 `qemu_fw.rom`；
- 设备树 `/pl031@9010000` 的 `compatible` 已是单一的 `arm,pl031`；
- 镜像 rootfs 中包含 `sixlinux_rtc.ko` 和自动加载配置。

## 测试结果

`make driver-test` 通过：

- 模块自动加载，`dmesg` 输出 `sixlinux_rtc 9010000.pl031: SixLinux RTC probed: id=0x00141031 irq=26`；
- 设备路径为 `9010000.pl031`，确认走的是 platform 总线；
- debugfs `id` 读出 `1314865`（`0x00141031`），掩码校验通过；
- debugfs `data` 读出 `1794021218`；
- probe 时设置的 alarm 产生第一次中断，`irq_count = 1`；
- 写入 `trigger` 后产生第二次中断，`irq_count = 2`；
- `poweroff` 正常关机。

`make boot-test` 同步回归通过，确认 RTC 绑定改动没有影响 TF-A → U-Boot → Linux 自动启动链。

日志：

- `artifacts/rtc-driver-test.log`
- `artifacts/firmware-boot.log`

## 阶段提交

- `c57d8ba feat: 添加 PL031 RTC platform driver`

本阶段尚未加入 opkg 软件仓库和 release 安全配置，后续阶段继续实现。
