# SixLinux 最终验收报告

- 报告日期：2026-11-07
- 最终提交：`57184a1 test: 验证 A/B OTA 升级与回滚`
- 标签：`v1.2.0`（历史标签 `v1.0.0`、`v1.1.0`）
- 仓库：https://github.com/bugego15/sixlinux
- 分支：`main`（唯一分支，默认分支）

## 一、项目定位

SixLinux 是一个用 Yocto 构建的 AArch64 嵌入式 Linux 发行版，面向 QEMU `virt` 仿真平台做板级 bring-up 验证：

- 机器 `sixlinux-qemuarm64`、发行版 `sixlinux`、systemd、无桌面；
- TF-A BL1/BL2/BL31 + U-Boot 2024.01 启动链，`secure=on`、GICv3、PSCI 走 SMC；
- PL031 RTC platform driver，注册标准 `/dev/rtc0`；
- opkg 包管理与 GPG 签名的自有软件源；
- 板级验证套件（固件启动 12 项 + 直接启动 GPIO）；
- release 安全登录（dev 用户 + ed25519 公钥、root/密码禁用）；
- A/B 双槽 OTA 升级、签名升级包、试启动确认和失败自动回滚；
- 本地完整 CI 与 GitHub Actions 配置。

阶段 P0–P11 均按“功能提交 + 验证提交”的中文历史记录复现。

## 二、最终状态

| 项目 | 值 |
| --- | --- |
| 分支 | `main`（唯一，默认） |
| 标签 | `v1.0.0`、`v1.1.0`、`v1.2.0` |
| 提交数 | 28 |
| 跟踪文件 | 99 |
| 仓库 `.git` 体积 | 3.0 MB |
| 跟踪内容体积 | 496 KB |
| GitHub 仓库体积 | 128 KB（压缩后） |

代码规模：

| 类型 | 文件数 | 行数 |
| --- | --- | --- |
| C（驱动 + 板级测试） | 5 | 1735 |
| Shell（构建/编排/测试） | 20 | 930 |
| Python（自动化测试） | 9 | 1184 |
| BitBake recipe | 9 | 189 |
| bbappend / cfg | 4 | 11 |
| Markdown 文档 | 26 | 2331 |

## 三、最终完整 CI 结果

在最终提交上执行 `make ci`，日志保存为 `artifacts/final-ci.log`，**全部阶段通过**：

| 阶段 | 结果 | 关键证据 |
| --- | --- | --- |
| `make check-env` | PASS | 主机工具与依赖齐全 |
| `make fetch-poky` | PASS | Poky/内核/firmware 缓存版本匹配 |
| `make build` | PASS | 3564 个 BitBake 任务全部成功，最终 CI 100% 命中 sstate |
| `make firmware` | PASS | TF-A `qemu_fw.rom`、U-Boot、DTB 生成 |
| `make package-repo` | PASS | 三个架构索引全部签名（密钥 `F115617E…D10266`） |
| `make boot-test` | PASS | “TF-A → U-Boot → SixLinux 零输入自动启动验证通过” |
| `make driver-test` | PASS | AMBA ID `0x00141031`，IRQ 1→2，epoch `1794048405` |
| `make board-test` | PASS | 12/12 子测试，75 项 CHECK 全通过 |
| `make gpio-test` | PASS | `/dev/gpiochip0`，`lines=8`，debugfs 含 PL061 |
| `make ota-test` | PASS | 7/7 阶段（升级、试启动、篡改拒绝、回滚） |
| `make opkg-test` | PASS | 签名源安装/升级、篡改签名被拒绝 |
| `make release` | PASS | 发布包生成到 `artifacts/releases/sixlinux-0.1.0/` |
| `make release-test` | PASS | SSH 公钥登录、root/密码拒绝、sshd 配置 |

### 板级测试 12 项明细

| 子命令 | 检查数 | 结果 |
| --- | --- | --- |
| `kernel` | 11 | PASS |
| `cpu` | 8 | PASS |
| `smp` | 5 | PASS |
| `mm` | 6 | PASS |
| `irq` | 3 | PASS |
| `rtc` | 7 | PASS |
| `blk` | 5 | PASS |
| `net` | 5 | PASS |
| `cgroup` | 7 | PASS |
| `seccomp` | 5 | PASS |
| `systemd` | 6 | PASS |
| `ns` | 7 | PASS |

### A/B OTA 7 阶段明细

```text
PASS initial-slot-a     root=/dev/vda2 slot=a
PASS install            bundle 验签通过并写入 slot B
PASS boot-slot-b        root=/dev/vda3 version=1.1.0 pending=0
PASS tamper-rejected    篡改升级包验签失败且启动状态未变
PASS failed-boots       连续 2 次启动失败（预期）
PASS rollback           连续失败后回滚到 slot A
PASS serial-log         串口日志包含回滚与槽位切换记录
```

## 四、构建产物与体积

| 产物 | 大小 | 说明 |
| --- | --- | --- |
| `Image` | 23 MB | Linux 6.6.160 内核 |
| rootfs ext4 | 146 MB | 已用约 104 MB，空闲 41.9 MB（27.5%） |
| `u-boot-*.bin` | 1.0 MB | U-Boot BL33 |
| `qemu_fw.rom` | 64 MB | TF-A BL1 + FIP（含 BL2/BL31/U-Boot） |
| `virt.dtb` | 7.6 KB | 修正后的 QEMU 设备树 |
| A/B 磁盘镜像 | 358 MB | 启动分区 32 MB + 两个 162 MB 根分区 |
| OTA 升级包 | 32 MB | `sixlinux-ota-1.1.0.tar.gz` + 签名 |
| 签名软件源 | 548 MB | 2620 个 ipk（all 23 / cortexa53 2311 / sixlinux_qemuarm64 286） |
| release 发布包 | 143 MB | Image、ext4、tar.bz2、ROM、DTB、SHA256SUMS |
| 镜像内 opkg 包 | 118 个 | 系统安装的软件包数量 |

## 五、健康检查

### 仓库

- `git status` 干净，无未提交修改；
- 远端只有 `main` 一个分支，默认分支为 `main`；
- 标签 `v1.0.0`、`v1.1.0`、`v1.2.0` 已推送；
- `.gitignore` 覆盖 `build/`、`artifacts/`、`sources/poky/`、SSH 主机密钥、`authorized_keys`、feed 公钥和 GPG home。

### 安全

- 仓库中没有任何私钥：`git grep "PRIVATE KEY"` 无结果，也没有跟踪 `artifacts/keys/`；
- SSH 私钥、feed 签名私钥只存在于本地 `artifacts/keys/`；
- release 镜像 root 锁定、密码/键盘交互认证禁用，只允许 dev 公钥登录；
- opkg feed 强制 GPG 验签，篡改索引被拒绝；
- OTA 升级包强制 GPG 验签，篡改包在写槽前被拒绝。

### 运行时

- 板级套件 `kernel` 检查确认 `dmesg` 无 BUG/Oops/Call trace/panic，8 项关键内核配置齐全；
- systemd 正常运行，临时服务、journald、定时器验证通过；
- 最终 CI 后无残留 QEMU 进程和 HTTP 服务，端口 2222–2225/8080 全部空闲；
- WSL 构建盘剩余 856 GB（使用 11%）。

### 构建效率

- 最终 CI 的 `make build`：3564 个任务 100% 命中 sstate，无需重新编译；
- release 构建：3564 个任务同样全部命中 sstate；
- kernel、U-Boot、镜像和所有测试产物均可从 sstate 复现。

### 文档

- `docs/p1-validation.md` … `docs/p11-validation.md` 阶段验证记录齐全；
- 设计文档覆盖架构、固件、RTC 驱动、板级测试、opkg、签名源、OTA、release；
- 故障排查记录在 `docs/bring-up-notes.md`。

## 六、已知限制

1. **仿真平台**：QEMU `virt` 不能覆盖真实 SoC 的 DDR 初始化、BootROM、时钟/复位、电源域和 pinmux，真板必须单独验证；
2. **内核/DTB 不参与 A/B**：A/B 只做 rootfs 双槽，内核和 DTB 在共享启动分区；
3. **状态文件**：`state.env` 是 FAT 上的普通文件，掉电时序窗口内可能丢失状态，属于演示级实现；
4. **传输安全**：OTA 和 opkg 使用 HTTP，完整性由 GPG 签名保证；生产应换 HTTPS；
5. **版本号**：`DISTRO_VERSION` 保持 `0.1.0`，用标签区分阶段；
6. **软件源体积**：548 MB 未裁剪，包含 dbg/dev/src 包，可按需裁剪；
7. **云端 CI**：GitHub Actions 受 userns 和磁盘限制，完整验证以本地 CI 为准。

## 七、复现方式

```bash
wsl -d Ubuntu-24.04
cd /home/dev/sixlinux
git pull --tags

make check-env
make build
make firmware
make boot-test
make driver-test
make board-test
make gpio-test
make package-repo
make opkg-test
make ab-disk
make ota-bundle
make ota-test
make release
make release-test
```

或一条命令：

```bash
make ci
```

## 八、结论

- 全部 13 个流水线阶段通过，板级 75 项检查、OTA 7 阶段、opkg 与 release 安全测试全部成功；
- 交付物完整：镜像、固件、签名软件源、A/B 盘、OTA 包、release 发布包、日志与文档；
- 仓库状态干净，无密钥泄露风险，历史清晰可复现；
- 项目达到“可演示、可复现、可扩展”的完工状态，后续可在真板移植、安全启动和 HTTPS 源方向继续。
