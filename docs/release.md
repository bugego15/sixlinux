# SixLinux 发布与安全配置

## 开发版与发布版

开发版使用 `build/qemuarm64` 和 `debug-tweaks`，便于串口调试。发布版使用独立的 `build/qemuarm64-release` 和 `conf/templates/qemuarm64-release`，不包含 `debug-tweaks`，root 密码由上游处理锁定。

## 登录策略

- 新增 `dev` 用户和 `/home/dev/.ssh/authorized_keys`；
- 使用 ed25519 公钥认证；
- `PermitRootLogin no`；
- `PasswordAuthentication no`；
- `KbdInteractiveAuthentication no`；
- `PermitEmptyPasswords no`；
- `AllowUsers dev`；
- `UsePAM no`，避免锁定密码字段阻断公钥认证；
- 通过 `/etc/ssh/sshd_config.d/99-sixlinux.conf` 应用配置，避免包冲突；
- 预装 ed25519 主机密钥，私钥不纳入公共版本控制。

`dev` 使用空密码字段以允许公钥登录，但密码认证和空密码认证均关闭。`dev` 的 sudo 仅用于本地 QEMU 管理测试，生产系统应重新评估 sudo 策略。

## 密钥管理

`scripts/generate-keys.sh` 在构建前生成 `dev` 登录密钥和 SSH 主机密钥：

- 私钥保存在 `artifacts/keys/`，不提交到仓库；
- 公钥和主机密钥副本写入 security recipe 的 `files/` 目录供构建使用；
- `authorized_keys`、主机密钥和 `.pub` 已加入 `.gitignore`；
- `build-qemuarm64.sh` 会自动调用该脚本，因此全新克隆可以直接构建。

## 发布命令

```bash
make release
make release-test
```

`make release` 会构建 release rootfs、TF-A、U-Boot、DTB，并生成：

```text
artifacts/releases/sixlinux-0.1.0/
├── Image
├── sixlinux-0.1.0.ext4
├── sixlinux-0.1.0.tar.bz2
├── qemu_fw.rom
├── virt.dtb
├── sixlinux-image-minimal.manifest
├── release-info.env
├── RELEASE_NOTES.md
└── SHA256SUMS
```

## 实测安全测试

`tests/release-security.py` 已通过：

- `dev` 公钥 SSH 登录成功；
- `sudo -n` 可执行管理命令；
- `sshd -T` 配置符合预期；
- root SSH 登录被拒绝；
- 密码认证被拒绝；
- `sudo -n poweroff` 正常关机。

测试日志：`artifacts/release-security.log`。

## 软件源签名

release 镜像与开发镜像共用同一套签名软件源配置：

- `/etc/opkg/sixlinux.conf` 中包含 `option check_signature 1` 和 `option signature_type gpg-asc`；
- 镜像内置 `/etc/opkg/gpg/` 公钥 keyring，拒绝未签名或被篡改的索引；
- 源地址由 `SIXLINUX_FEED_BASE` 决定，release 模板可以在 `local.conf` 中覆盖为正式服务器地址。

发布流程：

```bash
make build
make release
make package-repo
make publish-feed     # 输出到 artifacts/feed/published，可复制到正式服务器
```

对外托管时必须同时提供 `Packages.gz` 和 `Packages.asc`；密钥与签名规则见 `docs/signed-feed.md`。

## CI

`scripts/ci.sh` 串联环境检查、源码获取、镜像/固件/仓库构建、启动测试、RTC 驱动测试、板级测试、opkg 签名源测试和 release 安全测试。

GitHub Actions 使用 Ubuntu 24.04，缓存 `cache/downloads` 和 `cache/sstate-cache`，并上传 `artifacts/releases/`。首次 CI 构建耗时较长，后续可复用缓存。
