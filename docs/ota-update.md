# 阶段 11：A/B OTA 升级与回滚

## 目标

在六西Linux发行版上实现可回滚的 A/B 双槽 OTA 升级：

- 系统根文件系统分 A、B 两个槽，升级只写非当前槽；
- 升级包必须通过 GPG 验签和内容校验；
- 新槽首次启动是“试启动”，成功进入 userspace 后自动确认；
- 试启动连续失败时，U-Boot 自动回滚到旧槽。

## 磁盘布局

`make ab-disk` 生成 `artifacts/ab/sixlinux-ab.img`（MBR 分区表，1 MiB 对齐）：

| 分区 | 起始 | 大小 | 内容 |
| --- | --- | --- | --- |
| p1 | 1 MiB | 32 MiB | FAT16 启动分区：`boot.scr`、`Image`、`virt.dtb`、`state.env` |
| p2 | 33 MiB | 根文件系统大小 + 16 MiB | rootfs slot A |
| p3 | p2 之后 | 同上 | rootfs slot B |

启动分区是 U-Boot 和 Linux 用户态共享的状态介质：U-Boot 读 `state.env`，用户态工具通过挂载 `/dev/vda1` 读写它。

## 启动与回滚流程

`CONFIG_BOOTCOMMAND` 先尝试从 `virtio 0:1` 加载 `boot.scr`，失败时回退到原来的 QEMU loader 启动方式，因此普通镜像的启动测试不受影响。

`boot-ab.cmd` 的逻辑：

1. `fatload` 读取 `state.env`，`env import -t` 导入 `slot`、`prev`、`pending`、`bootcount`；
2. 首次启动没有状态文件时，初始化为 `slot=a`、`prev=b`、`pending=0`；
3. 如果 `pending=1`（试启动新槽）：
   - `bootcount + 1`，通过 `env export -t` + `fatwrite` 写回启动分区（U-Boot 对 FAT 有写支持）；
   - 超过 2 次仍失败则回滚：`slot=prev`、`pending=0`、`bootcount=0`；
4. 根据槽位设置 `root=/dev/vda2` 或 `/dev/vda3`，从启动分区加载 `Image` 和 `virt.dtb`，`booti` 启动；
5. 命令行为 `panic=5`，内核 panic 后 5 秒重启。

用户态确认：

- `sixlinux-ota-mark-good.service` 在 `multi-user.target` 之后运行；
- 如果状态中 `pending=1`，说明当前是新槽的试启动，写回 `pending=0`、`bootcount=0`，即确认本次升级成功。

失败回滚的判定不需要外部输入：U-Boot 每次启动都会先把 `bootcount` 写回磁盘，只有用户态成功启动才会清零。

## 状态文件格式

`state.env` 是 U-Boot 的文本环境格式：

```text
slot=b
prev=a
pending=1
bootcount=0
```

- `slot`：当前应启动的槽；
- `prev`：回滚目标槽；
- `pending`：1 表示当前槽是未确认的试启动；
- `bootcount`：试启动失败计数。

## OTA 升级包

`make ota-bundle` 生成：

```text
artifacts/ota/sixlinux-ota-1.1.0.tar.gz
artifacts/ota/sixlinux-ota-1.1.0.tar.gz.sig
artifacts/ota/ota.env
```

包内容：

```text
rootfs.ext4       完整根文件系统镜像（含 /etc/sixlinux-ota-version 版本标记）
manifest.sha256   rootfs.ext4 的 SHA256
version           新版本号
```

签名：

- 使用 `make package-repo` 生成的同一个 feed 签名密钥；
- `gpg --detach-sign --armor` 生成 `.sig`，目标端用 `/etc/opkg/gpg` keyring 验签；
- 除了签名，目标端还会用 `sha256sum -c` 校验包内容。

## 目标端工具

`sixlinux-ota`（`/usr/bin/sixlinux-ota`）：

```sh
sixlinux-ota status            # 查看启动槽、根设备、系统版本
sixlinux-ota install <url>     # 下载、验签、校验并写入非当前槽
sixlinux-ota mark-good         # 试启动确认（由 systemd 服务调用）
```

`install` 流程：

1. 读取状态，确定非当前槽（A→`/dev/vda3`，B→`/dev/vda2`）；
2. `wget` 下载升级包和 `.sig`；
3. `gpg --homedir /etc/opkg/gpg --verify` 验签，失败直接退出；
4. 解包并 `sha256sum -c` 校验；
5. `dd` 写入非当前槽；
6. 写回状态：`slot=目标槽`、`prev=原槽`、`pending=1`、`bootcount=0`；
7. 提示重启。

升级不影响正在运行的根文件系统。

## 宿主编排

| 命令 | 作用 |
| --- | --- |
| `make ab-disk` | 组装 A/B 磁盘镜像（FAT 启动分区 + 双 rootfs 槽） |
| `make ota-bundle` | 生成并签名 OTA 升级包 |
| `make run-ab`（`scripts/run-ab.sh`） | 用 QEMU 启动 A/B 磁盘，默认 SSH 转发 2225 |
| `make ota-test` | 自动验证升级、试启动确认、篡改拒绝和失败回滚 |

## 自动化测试（`make ota-test`）

1. 复制基础磁盘为 `artifacts/ab/work.img`，启动 HTTP 服务提供升级包；
2. **initial-slot-a**：系统运行在 `/dev/vda2`，状态 `slot=a`；
3. **install**：从 `http://10.0.2.2:8080` 下载并验签，写入 slot B；
4. **boot-slot-b**：重启后根设备为 `/dev/vda3`，版本标记为 OTA 包版本，`pending=0`；
5. **tamper-rejected**：篡改升级包后安装失败（签名校验拒绝），启动状态不变；
6. **failed-boots**：破坏 slot B 后连续两次启动失败；
7. **rollback**：第三次启动时 U-Boot 自动回滚到 slot A，系统正常登录；
8. **serial-log**：串口日志包含槽位切换和回滚记录。

结果写入 `artifacts/ota-test.log` 和 `artifacts/ota-test.json`。

## 安全说明

- 升级包必须验签，未签名或篡改的包会被拒绝；
- 签名私钥不进入仓库，构建时在 `artifacts/keys/gnupg-feed` 生成；
- 传输使用 HTTP，机密性不依赖传输层，完整性由 GPG 签名保证；生产环境可把源地址换成 HTTPS；
- 试启动确认只认用户态启动成功，不依赖网络或外部服务。

## 边界

- 当前 A/B 磁盘是 QEMU virtio 磁盘 + 自组装 MBR 镜像，没有使用 Yocto wic；
- 内核和 DTB 放在共享启动分区，不做内核 A/B；
- 状态文件是 FAT 上的普通文件，掉电窗口内可能出现旧状态，属于演示级实现；
- `panic=5` + `-no-reboot` 是测试环境中模拟“断电重启”的方式，真实板卡由复位或看门狗完成。
