# RTC platform driver 实验

## 目标

基于 QEMU 现有 PL031 RTC，完成真实设备树绑定、MMIO、IRQ 和 debugfs 验证，不修改 QEMU 源码。

## 设备树与总线选择

PL031 默认兼容字符串为 `arm,pl031\0arm,primecell`，会进入 AMBA 总线。为完成 platform_driver 实验，`scripts/build-firmware.sh` 将兼容字符串改为单一的 `arm,pl031`，从而创建 platform device，并避免与上游 AMBA RTC 驱动冲突。

其他相关 DTB 设置保持：

- PSCI 使用 SMC；
- `pl061@9030000` 禁用；
- RTC 保持启用；
- RTC 中断使用设备树中的 IRQ 2。

## 驱动实现

源码：`layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/files/sixlinux_rtc.c`

主要流程：

- `devm_platform_ioremap_resource()` 映射 MMIO；
- `platform_get_irq()` 获取设备树 IRQ；
- `devm_request_irq()` 注册中断处理函数；
- 读取 AMBA PID0–PID3 和 RTC Data Register；
- 设置 `RTC_CR_EN`、Match Register 和 Interrupt Mask；
- 中断处理函数读取 `RTC_MIS`、清除 `RTC_ICR`、关闭本次 alarm 并更新计数。

debugfs 位于 `/sys/kernel/debug/sixlinux_rtc/`：

| 文件 | 用途 |
| --- | --- |
| `id` | AMBA ID，本次为 `0x00141031` |
| `data` | RTC Data Register 当前值 |
| `irq_count` | 已处理的 alarm 中断次数 |
| `trigger` | 写入非零值，设置 `DR + 1` 并使能一次 alarm |

AMBA ID 使用 `0x000fffff` 掩码比较，允许变体位，与上游驱动的 ID 匹配方式一致。

## Yocto 集成

- `sixlinux-rtc-driver_1.0.bb` 使用 `inherit module`；
- `FILESEXTRAPATHS` 指向实际源码目录；
- `MAKE_TARGETS = "modules"`；
- Kbuild Makefile 提供 `modules`、`modules_install` 和 `clean`；
- `KERNEL_MODULE_AUTOLOAD = "sixlinux_rtc"`；
- 镜像通过 `kernel-module-sixlinux-rtc` 安装模块。

## 实测结果

`make driver-test` 已通过：

- probe 日志包含 `SixLinux RTC probed`；
- AMBA ID 为 `0x00141031`；
- 第一次 alarm 后 `irq_count = 1`；
- debugfs 写入 `trigger` 后 `irq_count = 2`；
- 系统正常关机。

完整日志：`artifacts/rtc-driver-test.log`。
