# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 6（P6）：release 安全登录。**

本阶段在开发镜像之外增加独立的发布构建：去掉 `debug-tweaks`，锁定 root，只允许 `dev` 用户通过 ed25519 公钥登录，并用 sudo 执行管理操作。

具体改动：

- 新增 release 构建模板 `conf/templates/qemuarm64-release/`，`EXTRA_IMAGE_FEATURES = ""`；
- 新增 `sixlinux-security`：创建 `dev` 用户（空密码字段）、`sudo` 免密、sshd drop-in 配置（禁止 root 和密码登录、只允许 dev 公钥）、预装 ed25519 主机密钥和授权公钥；
- `scripts/generate-keys.sh` 在构建前生成 dev 登录密钥和 SSH 主机密钥，私钥只保存在 `artifacts/keys/`，layer 中只保留构建期副本且不提交；
- `scripts/build-release.sh` 使用 release 模板构建到 `build/qemuarm64-release`；
- `scripts/release-sixlinux.sh` 打包镜像、TF-A ROM、DTB、manifest 和 `SHA256SUMS` 到 `artifacts/releases/sixlinux-0.1.0/`；
- `tests/release-security.py` 通过 SSH 验证公钥登录、sudo、root/密码拒绝和 sshd 配置。

后续阶段再加入本地 CI 和 GitHub Actions。

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

## 构建和验证

```powershell
wsl -d Ubuntu-24.04
```

```bash
cd /home/dev/sixlinux
make check-env
make fetch-poky
make build
make firmware
make boot-test
make driver-test
make package-repo
make opkg-test
make release
make release-test
```

`make build` 前会自动调用 `scripts/generate-keys.sh` 生成 SSH 密钥；私钥只存在于 `artifacts/keys/`，不要提交。

`make release` 使用独立构建目录和 release 模板，产出 `artifacts/releases/sixlinux-0.1.0/`：

| 文件 | 说明 |
| --- | --- |
| `Image` | Linux 内核 |
| `sixlinux-0.1.0.ext4` | ext4 根文件系统 |
| `sixlinux-0.1.0.tar.bz2` | tar.bz2 根文件系统 |
| `sixlinux-image-minimal.manifest` | 镜像软件包清单 |
| `qemu_fw.rom` | TF-A 固件 ROM |
| `virt.dtb` | 修正后的 QEMU 设备树 |
| `SHA256SUMS` | 所有镜像产物的校验和 |
| `release-info.env` | 版本与上游提交信息 |
| `RELEASE_NOTES.md` | 发布说明和安全策略 |

`make release-test` 启动 release 镜像并检查：

- `dev` 用户可以用 `artifacts/keys/sixlinux-dev-key` 公钥登录；
- `dev` 用户可 `sudo -n` 执行 root 操作；
- `sshd -T` 包含 `permitrootlogin no`、`passwordauthentication no`、`pubkeyauthentication yes`、`allowusers dev`；
- root 账号 SSH 登录被拒绝，密码认证被拒绝；
- systemd 运行正常，`sudo poweroff` 正常关机。

手动体验 release 镜像：

```bash
bash scripts/run-release.sh
ssh -i artifacts/keys/sixlinux-dev-key \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 dev@127.0.0.1
```

## 当前文件

- `sources/versions.env`：固定 Poky、Linux、U-Boot 和 TF-A 版本；
- `layers/meta-sixlinux/conf/`：layer、machine、distro 和 dev/release 两套构建模板；
- `layers/meta-sixlinux/recipes-bsp/u-boot/`：固化自动 bootcmd 的 U-Boot 配置片段；
- `layers/meta-sixlinux/recipes-kernel/sixlinux-rtc-driver/`：PL031 platform driver 源码和 recipe；
- `layers/meta-sixlinux/recipes-apps/sixlinux-hello/`：hello 软件包 recipe；
- `layers/meta-sixlinux/recipes-core/sixlinux-opkg-config/`：目标系统 opkg feed 配置；
- `layers/meta-sixlinux/recipes-core/sixlinux-security/`：release SSH 用户、密钥和 sudo 配置；
- `layers/meta-sixlinux/recipes-core/images/`：最小镜像 recipe；
- `packages/sixlinux-hello/v1.0`、`v1.1`：两个版本的软件包源码；
- `scripts/`：源码获取、镜像/固件/仓库/release 构建、密钥生成和启动脚本；
- `tests/`：直接启动、固件启动、RTC 驱动、opkg 仓库和 release 安全的自动验证脚本。

详细路线见 `docs/roadmap.md`。
