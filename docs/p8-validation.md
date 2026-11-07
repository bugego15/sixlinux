# P8 验证记录

## 阶段目标

在目标发行版内部运行用户态测试程序，验证板级/内核能力：CPU 特性、SMP、内存、中断、RTC、块设备、网络和 systemd；同时把 P4 的 RTC 驱动扩展为注册标准 RTC 设备。

## 实现内容

### RTC 驱动扩展

`sixlinux_rtc.c` 在保留 MMIO/IRQ/debugfs 的基础上：

- 用 `devm_rtc_allocate_device()` / `devm_rtc_register_device()` 注册标准 RTC 设备；
- 实现 `read_time`（读 `RTC_DR`）和 `set_time`（写 `RTC_LR`）；
- 系统出现 `/dev/rtc0` 和 `/sys/class/rtc/rtc0/`；
- `tests/driver-rtc.py` 增加设备节点、sysfs 名称和 `since_epoch` 检查。

### 板级验证套件

- 目标内程序：`layers/meta-sixlinux/recipes-apps/sixlinux-boardtest/`，打包为 `sixlinux-boardtest` 并安装进镜像；
- 宿主 runner：`tests/board-suite.py`，负责启动 QEMU、通过 SSH 逐项运行测试、汇总 JSON；
- `Makefile` 新增 `make board-test`；
- `scripts/ci.sh` 在 `driver-test` 之后加入 `make board-test`；
- 设计说明见 `docs/board-test.md`。

八个子测试及其检查点见 `docs/board-test.md`。宿主侧同时启动 8080 HTTP 服务，目标系统通过 slirp 网关访问，验证 guest-host 网络路径。

## 执行命令

```bash
cd /home/dev/sixlinux
make build
make driver-test
make board-test
make ci
```

## 验证结果

### RTC 标准设备

`make driver-test` 通过：

- `/dev/rtc0` 存在；
- `/sys/class/rtc/rtc0/name` 为 `sixlinux_rtc 9010000.pl031`；
- `since_epoch` 是合理的当前时间；
- 原有 AMBA ID `0x00141031`、IRQ `1 → 2` 保持通过。

### 板级测试

`make board-test` 连续两次 8/8 通过（本阶段记录一次完整结果）：

| 子测试 | 结果 | 关键数据 |
| --- | --- | --- |
| `cpu` | PASS 8/0 | MIDR `0x410fd034`、页 4096、缓存行 64、NEON/CRC32 实测 |
| `smp` | PASS 5/0 | 2 CPU、atomic 4000000、CPU1 亲和、futex 872us |
| `mm` | PASS 6/0 | MemTotal 1987MB、64MB mmap、memcpy 约 1.0TB/s |
| `irq` | PASS 3/0 | 1481 次 1ms 信号、avg 1013us、max 4630us |
| `rtc` | PASS 7/0 | ioctl 读时/写时回读、sysfs、与系统时间一致 |
| `blk` | PASS 5/0 | ext4 magic、写 78.8MB/s、读 2223MB/s、O_DIRECT |
| `net` | PASS 5/0 | loopback TCP 501MB/s、HTTP 205B、DNS |
| `systemd` | PASS 6/0 | 服务启停、journald、systemd-run 定时器 |

目标侧测试总耗时约 17.3 秒，共 45 个检查点全部通过。宿主汇总写入 `artifacts/board-test.json`。

### 完整 CI 回归

`make ci` 一次通过，顺序执行：

```text
check-env → fetch-poky → build → firmware → package-repo → boot-test
→ driver-test → board-test → opkg-test → release → release-test
```

其中：

- 开发镜像构建 3296 个 BitBake 任务全部成功（27 个实际执行）；
- release 镜像构建 3296 个任务全部成功（64 个实际执行，复用 sstate）；
- boot-test、driver-test、board-test、opkg-test、release-test 全部通过。

## 日志

| 日志 | 内容 |
| --- | --- |
| `artifacts/board-test.log` | 板级测试完整输出 |
| `artifacts/board-test.json` | 宿主汇总结果 |
| `artifacts/driver-rtc.log` / `artifacts/rtc-driver-test.log` | RTC 驱动测试 |
| `artifacts/firmware-boot.log` | 启动链回归 |

## 已知事项

- 板级测试在 QEMU 仿真环境运行，性能数字（memcpy、块 I/O）只用于回归对比，不代表真实硬件；
- `cpu` 子测试把 LSE atomics（`HWCAP_ATOMICS`）作为信息输出，因为 Cortex-A53 是 ARMv8.0，没有 LSE 属正常；
- `irq` 测试使用 1ms POSIX timer 统计信号间隔，QEMU TCG 下抖动明显，阈值放得很宽；
- 板级测试需要主机 2223（SSH 转发）和 8080（HTTP）端口空闲。

## 阶段提交

- `eb7aba7 feat: 扩展 RTC 驱动注册标准 rtc0 设备`
- `a78aac6 feat: 添加板级验证套件`
