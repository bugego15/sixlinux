# P6 验证记录

## 阶段目标

在开发镜像之外建立独立的 release 构建：去掉调试入口，锁定 root，只允许非 root 用户用 SSH 公钥登录，并把发布产物打包成可校验的目录。

## 实现内容

### 发布构建配置

- 新增 `layers/meta-sixlinux/conf/templates/qemuarm64-release/`；
- `local.conf.sample` 设置 `EXTRA_IMAGE_FEATURES = ""`，不再继承开发镜像的 `debug-tweaks`；
- 构建目录为 `build/qemuarm64-release`，与开发构建隔离。

### 安全配置 recipe

`layers/meta-sixlinux/recipes-core/sixlinux-security_1.0.bb`：

- 创建 `dev` 用户（uid 1000，空密码字段）和 `dev` 组；
- 安装 `sudoers.d/sixlinux-dev`，允许 `dev` 免密 sudo；
- 安装 sshd drop-in `99-sixlinux.conf`（通过上游 `Include /etc/ssh/sshd_config.d/*.conf` 生效）：

```text
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
AllowUsers dev
X11Forwarding no
```

- 预装 ed25519 SSH 主机密钥和 `dev` 的 `authorized_keys`，避免首次启动生成密钥导致 SSH 不可用。

### 密钥管理

`scripts/generate-keys.sh`：

- 在 `artifacts/keys/` 生成 dev 登录密钥和 SSH 主机密钥；
- 把公钥和主机私钥副本放进 security recipe 的 `files/` 供构建使用；
- `build-qemuarm64.sh` 每次构建前调用它，因此全新克隆也能直接构建；
- 私钥只存在于 `artifacts/keys/`，layer 中的密钥材料加入 `.gitignore`，不提交到仓库。

### 发布脚本

- `scripts/build-release.sh`：用 release 模板构建 `build/qemuarm64-release`；
- `scripts/release-sixlinux.sh`：把内核、ext4、tar.bz2、manifest、`qemu_fw.rom`、`virt.dtb` 复制到 `artifacts/releases/sixlinux-0.1.0/`，生成 `SHA256SUMS`、`release-info.env` 和 `RELEASE_NOTES.md`；
- `scripts/run-release.sh`：用 release 构建产物启动 QEMU；
- `tests/release-security.py`：SSH 验证公钥登录、sudo、root/密码拒绝和 sshd 生效配置。

## 执行命令

```bash
cd /home/dev/sixlinux
make build
make release
make release-test
```

`make build` 会先自动生成密钥；`make release` 使用独立构建目录和 release 模板。

## 构建结果

- 开发镜像：3279 个 BitBake 任务全部成功（46 个实际执行，其余来自 sstate）；
- release 构建：3279 个任务全部成功（14 个实际执行，复用 sstate，约 4 分钟完成）；
- release 镜像中 root 密码字段为 `*`（锁定），`dev` 密码字段为空；
- 镜像内已包含 `99-sixlinux.conf`、`sudoers.d/sixlinux-dev` 和 `/home/dev/.ssh/authorized_keys`。

发布目录 `artifacts/releases/sixlinux-0.1.0/`（约 134 MB）：

| 文件 | 大小 |
| --- | --- |
| `Image` | 23 MB |
| `sixlinux-0.1.0.ext4` | 135 MB |
| `sixlinux-0.1.0.tar.bz2` | 27 MB |
| `qemu_fw.rom` | 64 MB |
| `virt.dtb` | 7.6 KB |
| `sixlinux-image-minimal.manifest` | 3.7 KB |
| `SHA256SUMS` / `release-info.env` / `RELEASE_NOTES.md` | 已生成 |

## 测试结果

`make release-test` 通过：

- 启动 release 镜像后 sshd 正常监听转发端口 2222；
- `dev` 用户公钥登录成功；
- `dev` 可以 `sudo -n` 执行 root 操作；
- 实际生效的 sshd 配置：

```text
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
x11forwarding no
permitemptypasswords no
allowusers dev
```

- root 账号 SSH 登录返回 `Permission denied`；
- 密码认证返回 `Permission denied`；
- `sudo -n systemctl is-system-running` 输出 `running`；
- `sudo -n poweroff` 正常关机，QEMU 退出。

手工验证记录：

```text
$ ssh -i artifacts/keys/sixlinux-dev-key ... dev@127.0.0.1 'id -un; uname -m'
dev
aarch64

$ ssh ... dev@127.0.0.1 'sudo -n id -u root'
0

$ ssh ... root@127.0.0.1 true
root@127.0.0.1: Permission denied (publickey).

$ ssh ... dev@127.0.0.1 'sudo -n poweroff'
poweroff rc=0
```

P6 开发镜像回归通过：

- `make boot-test`：TF-A → U-Boot → Linux 零输入自动启动正常；
- `make driver-test`：RTC 模块正常，AMBA ID `0x00141031`，IRQ `1 → 2`；
- `make opkg-test`：opkg 安装 1.0、升级 1.1 正常。

日志：

- `artifacts/release-security.log`
- `artifacts/firmware-boot.log`
- `artifacts/rtc-driver-test.log`
- `artifacts/opkg-test.log`

## 已知事项

- release 的登录私钥只保存在本地 `artifacts/keys/`，不进入仓库；其他人克隆后重新执行 `make release` 会生成自己的密钥；
- release 镜像的控制台 root 登录同样被锁定，日常调试使用开发镜像；
- BitBake 仍会提示 WSL2 和主机内核 I/O 统计警告，与本阶段功能无关。

## 阶段提交

- `d7fb933 feat: 添加 release 安全登录配置`

本阶段尚未加入本地 CI 和 GitHub Actions，后续阶段继续实现。
