# SixLinux 0.1.0 构建与验证报告

## 版本

- Poky：5.0.21 / Scarthgap，提交 `2a6862e7ed4cb2f030f6341458df61282bf8a5ca`
- linux-yocto：6.6.160，SRCREV `dce83a630a519666f8c5599478cd8db87cf772c2`
- yocto-kernel-cache：SRCREV `111e66d07f015c08755ae564c4a2f4a7710863ef`
- U-Boot：2024.01，SRCREV `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e`
- TF-A：v2.10.0，提交 `b6c0948400594e3cc4dbb5a4ef04b815d2675808`
- machine：`sixlinux-qemuarm64`
- image：`sixlinux-image-minimal`

## 构建结果

### 开发镜像（`build/qemuarm64`）

首次从零构建：3123 个 BitBake 任务全部成功。

加入 U-Boot、RTC 模块、opkg 和 release 安全配置后的最终镜像：3279 个任务全部成功，其中 3233 个命中 sstate，实际执行 46 个。

### 发布镜像（`build/qemuarm64-release`）

独立构建目录和 release 模板：3279 个任务全部成功，其中 3265 个命中 sstate，实际执行 14 个，约 4 分钟完成。

### 产物大小

| 产物 | 开发镜像 | 发布镜像 |
| --- | ---: | ---: |
| ext4 rootfs | 140,903,424 字节 | 140,898,304 字节 |
| tar.bz2 rootfs | 27,953,493 字节 | 27,956,980 字节 |
| Linux Image | 23,611,904 字节 | 23,611,904 字节 |

发布目录 `artifacts/releases/sixlinux-0.1.0/` 总计约 134 MB，包含 `SHA256SUMS` 校验和。

## 验证结果

完整启动链（`make boot-test`）：

- TF-A BL1/BL2/BL31 启动，GICv3 初始化，PSCI 使用 SMC；
- U-Boot 2024.01 从 `0x60000000` 启动并自动执行固化的 bootcmd；
- Linux 6.6.160 启动，两个 CPU 上线，`nproc = 2`；
- systemd 状态 `running`，`poweroff` 正常关机。

直接内核启动（`make boot-test-direct`）作为固件链的对照路径保留，用于隔离内核/rootfs 问题。

RTC 驱动（`make driver-test`）：

- platform 绑定成功，AMBA ID `0x00141031`；
- MMIO 数据可读，alarm 中断计数 `1 → 2`。

opkg 仓库（`make opkg-test`）：

- HTTP feed 三个源可访问；
- 安装 `sixlinux-hello=1.0-r0` 输出 v1.0，升级后输出 v1.1。

release 安全（`make release-test`）：

- `dev` 公钥 SSH 登录、sudo、sshd 配置验证通过；
- root 登录和密码认证被拒绝；
- `sudo poweroff` 正常关机。

## 日志

| 日志 | 内容 |
| --- | --- |
| `artifacts/firmware-boot.log` | TF-A/U-Boot/Linux 自动启动 |
| `artifacts/qemu-boot.log` | 直接内核启动 |
| `artifacts/rtc-driver-test.log` | RTC 驱动测试 |
| `artifacts/opkg-test.log`、`artifacts/opkg-http.log` | opkg 仓库测试 |
| `artifacts/release-security.log` | release 安全测试 |

## 复现

```bash
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

或一条命令执行完整流水线：`make ci`。
