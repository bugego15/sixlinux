# 板级验证套件

## 目标

前面的测试验证的是“能启动、能登录、能装包”。板级验证套件在目标发行版内部运行用户态程序，检查 CPU 特性、SMP、内存、中断、RTC、块设备、网络、systemd、内核状态、cgroup、namespace、seccomp 和 GPIO 是否按预期工作，输出可汇总的 PASS/FAIL 结果。

## 组成

```text
tests/board-suite.py（宿主）
  ├── 启动 QEMU（SSH_PORT=2223）和本地 HTTP 服务（8080）
  ├── 通过 SSH 在目标系统执行 sixlinux-boardtest <子命令>
  ├── 收集 SUMMARY 行，写入 artifacts/board-test.log / .json
  └── 关机并清理

tests/gpio-test.py（宿主，直接启动模式）
  └── 用 runqemu 启动 secure=off 镜像，验证 PL061 GPIO 子系统

sixlinux-boardtest（目标内 C 程序，opkg 包，镜像默认安装）
  ├── kernel / cpu / smp / mm / irq / rtc / blk / net
  ├── cgroup / seccomp / systemd / ns
  ├── gpio（仅直接启动 secure=off 模式）
  └── 每项输出 CHECK 行和 SUMMARY 行
```

宿主 HTTP 服务提供 `/boardtest.txt`，目标系统通过 slirp 网关 `10.0.2.2:8080` 访问，验证网络路径和 guest-host 转发。

`secure=on` 固件启动时 PL061 被禁用（避免非安全世界访问触发 AMBA abort），因此 GPIO 测试单独走 `make gpio-test` 的直接启动路径。

## 子测试

| 子命令 | 主要检查 |
| --- | --- |
| `kernel` | 内核版本、cmdline、`dmesg` 中无 BUG/Oops/Call trace/panic、`/proc/config.gz` 关键配置、taint 状态 |
| `cpu` | `uname` 架构、MIDR、页大小、缓存行、HWCAP ASIMD/CRC32、NEON 实际运算、CRC32C 指令结果 |
| `smp` | `nproc` 与 `/proc/cpuinfo` 一致、4 线程 atomic 计数、CPU 亲和性、futex 唤醒延迟 |
| `mm` | `/proc/meminfo`、64 MB mmap/写页、mlock、madvise、memcpy 带宽 |
| `irq` | POSIX timer 1 ms 周期信号、信号计数、平均/最大中断间隔 |
| `rtc` | `/dev/rtc0` 是否存在、sysfs `name`/`since_epoch`、`RTC_RD_TIME`、`RTC_SET_TIME` 读写回、与系统时间偏差 |
| `blk` | `/dev/vda` ext4 超级块、块设备大小、32 MB 缓冲读写吞吐、`O_DIRECT` 支持 |
| `net` | loopback TCP 吞吐、UDP 套接字、访问 `10.0.2.2:8080` 的 HTTP 内容、`getaddrinfo` |
| `cgroup` | cgroup v2 统一层级、memory/pids 控制器、`memory.max` OOM 限制、`pids.max` |
| `seccomp` | `PR_SET_NO_NEW_PRIVS`、seccomp BPF 过滤器、被拦截 syscall 返回 EPERM、`Seccomp` 模式 |
| `systemd` | `is-system-running`、临时服务启动/停止、journald 日志、`systemd-run` 定时器触发 |
| `ns` | UTS/mount/net/PID namespace 隔离、tmpfs 挂载、子进程在新 PID namespace 中为 1 |
| `gpio` | `/dev/gpiochip0`、`GPIO_GET_CHIPINFO_IOCTL`、debugfs GPIO 列表（仅直接启动） |

## 输出格式

目标程序：

```text
TEST cpu start
CHECK cpu/arch PASS machine=aarch64
...
SUMMARY cpu PASS pass=8 fail=0
```

宿主汇总：

```json
{
  "total": 12,
  "passed": 12,
  "failed": 0,
  "tests": [
    {"name": "cpu", "status": "PASS", "pass": 8, "fail": 0, "seconds": 0.01}
  ]
}
```

## 运行方式

```bash
cd /home/dev/sixlinux
make build        # 镜像里需要 sixlinux-boardtest 和启用 GPIO 的内核
make board-test   # 固件启动模式：12 项（不含 gpio）
make gpio-test    # 直接启动模式：验证 PL061 GPIO
```

`make board-test` 要求：

- 主机 2223 端口空闲（避免与手工 `make run` 的 2222 冲突）；
- 主机 8080 端口空闲（本地 HTTP 服务）；
- `artifacts/keys/sixlinux-dev-key` 存在（`make build` 会自动生成）。

## 边界

QEMU `virt` 不是真实 SoC，套件验证的是内核/用户态在该仿真平台上的行为和项目的集成质量，不能代替真实板卡的时钟、电源、DDR 和 pinmux 验证。
