# P10 验证记录

## 阶段目标

在 P8 的 8 项板级检查基础上扩展内核相关验证，并把 GPIO 子系统纳入直接启动模式的板级测试：

- 内核配置启用 QEMU virt 的 PL061 GPIO 驱动；
- 板级套件新增 `kernel`、`cgroup`、`ns`、`seccomp`、`gpio` 五个子命令；
- 固件启动模式覆盖 12 项检查，GPIO 单独走 `make gpio-test`（secure=off 直接启动）；
- 全部纳入本地 CI。

## 实现内容

### 内核配置片段

新增 `layers/meta-sixlinux/recipes-kernel/linux/`：

- `linux-yocto_%.bbappend` 把 `gpio-pl061.cfg` 加入 `SRC_URI`；
- `files/gpio-pl061.cfg` 内容为 `CONFIG_GPIO_PL061=y`。

重新构建内核后，`/proc/config.gz` 中出现 `CONFIG_GPIO_PL061=y`。

### 板级测试新增子命令

`layers/meta-sixlinux/recipes-apps/sixlinux-boardtest/files/boardtest.c`：

| 子命令 | 检查内容 |
| --- | --- |
| `kernel` | 内核版本、cmdline、`dmesg` 无 BUG/Oops/Call trace/panic、8 个关键内核配置、taint 信息 |
| `cgroup` | v2 统一层级、memory/pids 控制器、`memory.max=32M` 下子进程被 OOM 杀死、`pids.max` |
| `ns` | UTS/mount/net/PID namespace 隔离、tmpfs 挂载、PID namespace 内子进程 pid=1、无接口泄漏 |
| `seccomp` | `PR_SET_NO_NEW_PRIVS`、BPF 过滤器、`getppid` 返回 EPERM、`Seccomp: 2` |
| `gpio` | `/dev/gpiochip0`、`GPIO_CHIPINFO`（name/label/lines）、debugfs GPIO 列表（仅直接启动） |

### 直接启动 GPIO 测试

新增 `tests/gpio-test.py` 和 `make gpio-test`：

- 用 `scripts/run-qemuarm64.sh`（runqemu，secure=off）启动镜像；
- root 控制台登录后运行 `sixlinux-boardtest gpio`；
- 校验 `SUMMARY gpio PASS` 并打印检查结果。

`tests/board-suite.py` 在固件启动模式下跳过 `gpio`，并提示改走 `make gpio-test`。

### CI

`scripts/ci.sh` 在 `make board-test` 之后加入 `make gpio-test`。

## 执行命令

```bash
cd /home/dev/sixlinux
make build
make board-test
make gpio-test
make ci
```

## 构建结果

- 内核启用 `CONFIG_GPIO_PL061=y` 后重新构建成功；
- 期间遇到一次 WSL 下 `sixlinux-rtc-driver:do_package` 的 pseudo inode 不匹配，`bitbake -c cleansstate sixlinux-rtc-driver` 后恢复正常；
- 最终镜像构建：3547 个 BitBake 任务全部成功，其中 3520 个命中 sstate，实际执行 27 个；
- 镜像内 `/proc/config.gz` 可见 `CONFIG_GPIO_PL061=y`、`CONFIG_GPIO_CDEV=y`、`CONFIG_CGROUPS=y` 等配置。

## 测试结果

### 固件启动模式（`make board-test`）

12/12 通过：

```text
PASS kernel   pass=11 fail=0
PASS cpu      pass=8  fail=0
PASS smp      pass=5  fail=0
PASS mm       pass=6  fail=0
PASS irq      pass=3  fail=0
PASS rtc      pass=7  fail=0
PASS blk      pass=5  fail=0
PASS net      pass=5  fail=0
PASS cgroup   pass=7  fail=0
PASS seccomp  pass=5  fail=0
PASS systemd  pass=6  fail=0
PASS ns       pass=7  fail=0
```

关键证据：

```text
CHECK kernel/dmesg PASS 异常行=0
CHECK kernel/config PASS CONFIG_GPIO_PL061=y
CHECK cgroup/oom PASS 子进程被 OOM 杀死=1 oom_kill=1
CHECK seccomp/blocked PASS getppid 被拒绝（返回=-1 errno=1）
CHECK ns/net PASS host 接口=3 新 netns 接口=2 泄漏=0
CHECK ns/pid PASS 子进程在新 PID namespace 中 pid=1
```

### 直接启动 GPIO（`make gpio-test`）

```text
PL061 GPIO 直接启动验证通过。
CHECK gpio/chip PASS name=gpiochip0 label=9030000.pl061 lines=8
CHECK gpio/lines PASS GPIO 线数=8
CHECK gpio/debugfs PASS debugfs gpio 行数=1 pl061=1
```

### 完整 CI

首次 `make ci` 在 release 构建目录遇到与开发目录相同的 pseudo inode 问题（内核配置变更后外部模块 `do_package` 失败）。清理 release 目录的 RTC 模块后重新执行，完整流水线一次通过：

```text
check-env → fetch-poky → build → firmware → package-repo → boot-test
→ driver-test → board-test → gpio-test → opkg-test → release → release-test
```

```bash
source sources/poky/oe-init-build-env build/qemuarm64-release
bitbake -c cleansstate sixlinux-rtc-driver
```

## 日志

| 日志 | 内容 |
| --- | --- |
| `artifacts/board-test.log` | 12 项板级测试详细输出 |
| `artifacts/board-test.json` | 板级测试汇总 JSON |
| `artifacts/gpio-test.log` | 直接启动 GPIO 测试 |
| `artifacts/firmware-boot.log` | CI 内固件启动回归 |

## 已知事项

- `seccomp` 测试用原始 `syscall(SYS_getppid)` 判断拦截结果，因为 glibc 的 `getppid()` 在返回 -1 时不会设置 errno（本机验证过）；
- 新 net namespace 里会出现 `sit0`（内核按 namespace 创建），因此 `ns/net` 检查改为"主机物理网卡没有泄漏"；
- `cgroup` 测试会故意触发 OOM，`dmesg` 中出现 OOM 日志是预期行为；`kernel` 子命令排在 `cgroup` 之前执行，避免把 OOM 日志误判为内核异常；
- 固件启动 `secure=on` 下 PL061 被禁用（非安全世界访问会触发 AMBA abort），GPIO 验证只在直接启动 `secure=off` 模式进行；
- 内核 taint 值为 4096（out-of-tree 模块标记），来自项目自己的 RTC 驱动，属于预期。

## 阶段提交

- `e80d33c feat: 扩展板级测试与内核验证`
