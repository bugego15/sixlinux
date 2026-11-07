# P11 验证记录

## 阶段目标

在 P9 签名软件源的基础上实现 A/B 双槽 OTA 升级：

- 自组装 A/B 磁盘镜像（FAT 启动分区 + 两个 rootfs 槽）；
- U-Boot 启动脚本读取槽位状态、试启动计数和回滚；
- 目标端 `sixlinux-ota` 工具完成验签、校验和写槽；
- 自动化测试覆盖升级、试启动确认、篡改拒绝和失败回滚。

## 实现内容

### 磁盘与启动

- `scripts/build-ab-disk.sh` 生成 `artifacts/ab/sixlinux-ab.img`：
  - p1：FAT16 启动分区，含 `boot.scr`、`Image`、`virt.dtb`、`state.env`；
  - p2/p3：rootfs slot A/B；
  - 布局信息写入 `artifacts/ab/base.env`。
- `layers/meta-sixlinux/recipes-bsp/u-boot/files/boot-ab.cmd`：A/B 启动脚本；
- `sixlinux.cfg` 的 `CONFIG_BOOTCOMMAND` 改为"先尝试 `boot.scr`，失败回退原启动方式"，普通镜像测试不受影响；
- U-Boot 通过 `env import -t` / `env export -t` + `fatwrite` 持久化 `state.env`。

### 目标端

新增 `sixlinux-ota` recipe（`layers/meta-sixlinux/recipes-core/sixlinux-ota/`）：

- `/usr/bin/sixlinux-ota`：`status` / `install <url>` / `mark-good`；
- `sixlinux-ota-mark-good.service`：`multi-user.target` 后确认试启动；
- 升级时用 `/etc/opkg/gpg` keyring 验签，`sha256sum -c` 校验 payload，再 `dd` 写入非当前槽。

### 宿主编排

- `scripts/build-ota-bundle.sh`：生成 payload rootfs、清单、tar.gz 和 GPG 签名；
- `scripts/run-ab.sh`：QEMU 启动 A/B 磁盘（默认 SSH 转发 2225）；
- `tests/ota-test.py`：7 个阶段的自动化测试；
- `make ab-disk` / `make ota-bundle` / `make ota-test`；
- `scripts/ci.sh` 加入 `make ota-test`；
- `scripts/check-env.sh` 和 GitHub Actions 增加 `sfdisk`、`mkfs.vfat`、`mcopy`、`debugfs`。

## 构建结果

- U-Boot、内核和镜像重新构建：3564 个 BitBake 任务全部成功，其中 3537 个命中 sstate，实际执行 27 个；
- A/B 磁盘：358 MiB（p1 32 MiB，p2/p3 各 162 MiB）；
- OTA 升级包：`sixlinux-ota-1.1.0.tar.gz` 约 32 MiB，GPG 签名校验通过。

## 测试结果

`make ota-test` 7/7 通过：

```text
PASS initial-slot-a     root=/dev/vda2 slot=a
PASS install            bundle 验签通过并写入 slot B
PASS boot-slot-b        root=/dev/vda3 version=1.1.0 pending=0
PASS tamper-rejected    篡改升级包验签失败且启动状态未变
PASS failed-boots       连续 2 次启动失败（预期）
PASS rollback           连续失败后回滚到 slot A
PASS serial-log         串口日志包含回滚与槽位切换记录
```

关键串口日志：

```text
SixLinux A/B: reading boot state
OTA: booting slot a (/dev/vda2) pending=0 bootcount=0
EXT4-fs (vda2): mounted filesystem ...
OTA: booting slot b (/dev/vda3) pending=1 bootcount=1
EXT4-fs (vda3): mounted filesystem ...
OTA: too many failed boots, rollback from b to a
```

## 日志

| 日志 | 内容 |
| --- | --- |
| `artifacts/ota-test.log` | A/B 测试串口日志 |
| `artifacts/ota-test.json` | 各阶段结果 |
| `artifacts/ota-http.log` | 宿主 HTTP 升级包服务 |
| `artifacts/ab/base.env` | A/B 磁盘布局信息 |
| `artifacts/ota/ota.env` | 升级包元数据 |

## 已知事项

- 内核和 DTB 放在共享启动分区，本轮只做 rootfs A/B；
- `state.env` 是 FAT 上的普通文件，掉电时序窗口内可能丢状态，演示级实现；
- 测试用 `panic=5` + `-no-reboot` 模拟断电重启；
- `make ota-test` 依赖 `make build`、`make firmware` 的产物，CI 中顺序执行。

## 阶段提交

- `5564c33 feat: 实现 A/B OTA 升级与回滚`
- `TBD-test test: 验证 A/B OTA 升级与回滚`
