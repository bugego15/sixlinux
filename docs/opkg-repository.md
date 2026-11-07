# opkg 在线软件仓库

## 架构

```text
Yocto deploy/ipk
  → opkg-make-index（-a 保留多版本）
  → WSL Python HTTP server（端口 8080）
  → QEMU slirp 网关 10.0.2.2
  → SixLinux /etc/opkg/sixlinux.conf
  → opkg update / install / upgrade
```

访客通过 `http://10.0.2.2:8080` 访问 WSL 中的 feed，不需要 TAP 或真实外部网络。

## 目标端配置

`/etc/opkg/sixlinux.conf` 由 `sixlinux-opkg-config` 安装，包含：

- `all`
- `cortexa53`
- `sixlinux_qemuarm64`

镜像通过 `package-management` 安装 opkg，并通过 `sixlinux-opkg-config` 安装仓库配置。

## 软件包

`packages/sixlinux-hello/` 保存 1.0 和 1.1 两套 recipe 与源码。`scripts/build-package-repo.sh`：

1. 构建 1.0 并保存 ipk；
2. 构建 1.1；
3. 将 1.0 加回 `cortexa53` feed；
4. 使用 `opkg-make-index -a -p Packages` 生成同时包含两个版本的索引。

重复执行时，如果对应版本 ipk 已存在则跳过构建，避免共享 deploy 区域重复安装错误。

## 实测结果

`make opkg-test` 自动启动 HTTP 服务和 SixLinux，完成：

- `opkg update` 成功；
- `opkg list sixlinux-hello` 默认显示最新 1.1；
- `opkg install sixlinux-hello=1.0-r0` 安装成功；
- `sixlinux-hello` 输出 `SixLinux hello v1.0`；
- `opkg upgrade sixlinux-hello` 升级成功；
- 再次运行输出 `SixLinux hello v1.1`；
- 正常关机并清理 HTTP 服务。

测试日志：`artifacts/opkg-test.log`，HTTP 服务日志：`artifacts/opkg-http.log`。

`opkg list` 默认只显示最新版本，因此测试以实际安装和升级结果为准，而不是要求列表同时显示两个版本。
