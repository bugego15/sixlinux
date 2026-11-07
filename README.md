# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

SixLinux 不是 Ubuntu 的裁剪版，而是用上游开源组件（TF-A、U-Boot、Linux、systemd、OpenSSH、opkg）从零构建的可复现实验平台，用来练习板级 bring-up、固件启动链、设备树、平台驱动、软件仓库、发布安全和 CI。

## 能力概览

- TF-A BL1/BL2/BL31 + U-Boot BL33 的完整固件启动链，`secure=on`、GICv3、PSCI 走 SMC；
- 零输入自动启动：`CONFIG_BOOTCOMMAND` 固化 `setenv bootargs` + `booti`；
- PL031 RTC platform driver：设备树绑定、MMIO、IRQ、debugfs，并注册标准 `/dev/rtc0`；
- 板级验证套件：固件启动 12 项检查（含内核状态、cgroup、namespace、seccomp）+ 直接启动 GPIO 验证；
- opkg 在线软件仓库：hello 1.0/1.1 安装与升级；
- 自有签名软件源：GPG 签名的 opkg feed，源地址可通过 `SIXLINUX_FEED_BASE` 指向本机、局域网或公网 HTTPS；
- release 安全登录：无 debug-tweaks、root/密码禁用、dev 用户 ed25519 公钥 + sudo；
- 本地 CI 和 GitHub Actions 流水线。

## 阶段与提交

| 阶段 | 内容 | 提交 |
| --- | --- | --- |
| P0 | 开发环境与项目骨架 | `a6084f2` |
| P1 | Poky 最小 AArch64 镜像 | `a821406`、`2adcbb7` |
| P2 | TF-A + U-Boot 手动启动链 | `8bb05c0`、`788dbfd` |
| P3 | U-Boot 自动启动 | `978d7c6`、`e04837b` |
| P4 | PL031 RTC platform driver | `c57d8ba`、`a2988f7` |
| P5 | opkg 在线软件仓库 | `3846a02`、`16a3305` |
| P6 | release 安全登录与发布打包 | `d7fb933`、`81434d9` |
| P7 | 本地 CI、GitHub Actions 与文档 | `951dbcc`、`d9b40b5`、`115a5ed`、`31ae6a0`、`24a9dad` |
| P8 | 板级验证套件与标准 rtc0 设备 | `eb7aba7`、`a78aac6`、`dc1f43b` |
| P9 | 自有 GPG 签名软件源 | `f666e6d`、`a2ce75f` |
| P10 | 板级测试与内核验证扩展 | `e80d33c` |

每个阶段都有对应的验证记录：`docs/p*-validation.md`。

## 默认启动链

```text
TF-A BL1
  → TF-A BL2
  → TF-A BL31（GICv3、PSCI、运行时服务）
  → U-Boot BL33 @ 0x60000000
  → Linux Image @ 0x40200000 + DTB @ 0x44000000
  → SixLinux ext4 / systemd
```

## 开发环境

```text
Windows
└── WSL2 / Ubuntu 24.04
    ├── 交叉编译和 Yocto 构建
    ├── QEMU AArch64 仿真
    └── 自动化测试
```

- E 仓库：`E:\6linux\sixlinux`，用于版本管理和代码审阅；
- WSL 构建路径：`/home/dev/sixlinux`，用于实际构建和测试；
- 不在 `/mnt/e` 下执行 Yocto 大型构建；
- 不使用 root 运行 BitBake。

## 快速开始

```powershell
wsl -d Ubuntu-24.04
```

```bash
cd /home/dev/sixlinux
make check-env
make fetch-poky
make build          # 自动生成 SSH 密钥和软件源签名密钥并构建镜像
make firmware       # 构建 TF-A、U-Boot 和修正后的 DTB
make boot-test      # 零输入验证完整启动链
make board-test     # 固件启动模式：12 项板级/内核验证
make gpio-test      # 直接启动模式：PL061 GPIO 验证
make package-repo   # 生成签名 opkg feed（Packages + Packages.asc）
```

一条命令执行完整流水线（环境检查、构建、启动、驱动、仓库、release 和安全测试）：

```bash
make ci
```

## 常用命令

| 命令 | 说明 |
| --- | --- |
| `make check-env` | 主机工具和项目环境检查 |
| `make smoke-qemu` | 创建并退出最小 Cortex-A53 QEMU 实例 |
| `make fetch-poky` | 获取固定版本的 Poky、内核、U-Boot 和 TF-A 源码 |
| `make build` | 构建开发镜像 |
| `make firmware` | 构建 TF-A/U-Boot 固件和 QEMU DTB |
| `make package-repo` | 构建 hello 1.0/1.1，重建并签名 opkg feed |
| `make publish-feed` | 把签名 feed 复制到可发布目录（`FEED_PUBLISH_DIR` 可覆盖） |
| `make run` | 交互式启动完整固件链 |
| `make run-direct` | 直接内核启动（调试回退路径） |
| `make boot-test` | 自动验证 TF-A → U-Boot → Linux |
| `make driver-test` | 验证 RTC MMIO/IRQ/debugfs 和 `/dev/rtc0` |
| `make board-test` | 固件启动模式运行内核/cgroup/namespace/seccomp 等 12 项检查 |
| `make gpio-test` | 直接启动模式验证 PL061 GPIO 子系统 |
| `make opkg-test` | 验证 opkg 安装和升级 |
| `make release` | 构建并打包 release 镜像 |
| `make release-test` | 验证 release SSH 安全策略 |
| `make ci` | 执行完整本地 CI |

启动 QEMU 后可以 SSH 登录（仅 `dev` 用户、仅公钥）：

```bash
ssh -i artifacts/keys/sixlinux-dev-key \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 dev@127.0.0.1
```

## 产物

| 路径 | 内容 |
| --- | --- |
| `build/qemuarm64/tmp/deploy/images/sixlinux-qemuarm64/` | 开发镜像、内核、模块、manifest |
| `build/qemuarm64-release/tmp/deploy/images/sixlinux-qemuarm64/` | release 镜像产物 |
| `build/qemuarm64/tmp/deploy/ipk/` | 签名 opkg feed（Packages、Packages.gz、Packages.asc、ipk） |
| `artifacts/feed/published/` | `make publish-feed` 生成的待托管目录 |
| `artifacts/releases/sixlinux-0.1.0/` | 发布包（Image、ext4、tar.bz2、ROM、DTB、SHA256SUMS） |
| `artifacts/board-test.json`、`artifacts/board-test.log` | 板级验证套件的汇总结果和详细日志 |
| `artifacts/keys/` | 本地 SSH 密钥和软件源签名私钥（不提交） |
| `artifacts/*.log` | 各测试串口和运行日志 |

## 文档

- `docs/architecture.md`：目标架构、启动链和边界；
- `docs/build-report.md`：构建结果、产物大小和验证汇总；
- `docs/firmware-report.md`：TF-A/U-Boot 固件链细节；
- `docs/rtc-driver.md`：RTC platform driver 设计与验证；
- `docs/board-test.md`：板级验证套件的设计和运行方式；
- `docs/opkg-repository.md`：opkg feed 架构和测试；
- `docs/signed-feed.md`：自有签名软件源的密钥、签名规则和发布流程；
- `docs/release.md`：release 构建与安全配置；
- `docs/bring-up-notes.md`：构建和调试故障排查记录；
- `docs/roadmap.md`：分阶段复现路线；
- `docs/p1-validation.md` … `docs/p10-validation.md`：各阶段验证记录。

## 安全说明

- 开发镜像保留 `debug-tweaks`，仅用于本地 QEMU 调试；
- release 镜像锁定 root，禁用密码/键盘交互认证，只允许 `dev` 用户公钥登录；
- SSH 私钥和软件源签名私钥只保存在本地 `artifacts/keys/`，仓库与镜像只含公钥；
- opkg 强制校验软件源索引的 GPG 签名，篡改索引会被拒绝；
- QEMU 用户网络只在本机转发 2222 端口，不暴露到外部网络。

## CI

- `scripts/ci.sh`：本地完整流水线；
- `.github/workflows/ci.yml`：GitHub Actions 在 Ubuntu 24.04 上安装 Yocto 依赖，缓存 `cache/downloads` 和 `cache/sstate-cache`，执行 `./scripts/ci.sh` 并上传发布产物。

首次 CI 构建耗时较长，后续可复用缓存加速。


