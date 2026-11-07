# P5 验证记录

## 阶段目标

把 SixLinux 从“只有一个 ext4 根文件系统”升级为可通过 opkg 在线安装和升级软件包的系统：

1. 用 Yocto 的 `package_ipk` 生成 `.ipk`；
2. 在 WSL 中通过 HTTP 提供软件仓库；
3. 目标系统通过 `/etc/opkg/sixlinux.conf` 访问 `10.0.2.2:8080`；
4. 验证 `opkg update`、指定版本安装和在线升级。

## 实现内容

### 软件包

`packages/sixlinux-hello/` 保存 1.0 和 1.1 两套 recipe 与源码，程序分别输出：

```text
SixLinux hello v1.0
SixLinux hello v1.1
```

`scripts/build-package-repo.sh` 的流程：

1. 把 `packages/sixlinux-hello/v1.0` 复制到 layer 的 hello recipe 目录，`bitbake sixlinux-hello` 构建 1.0；
2. 把 1.0 的 ipk 暂存到 `artifacts/feed-v1/`；
3. 再复制 1.1 构建；
4. 把暂存的 1.0 加回 `cortexa53` feed；
5. 对 `all`、`cortexa53`、`sixlinux_qemuarm64` 执行 `opkg-make-index -a -p Packages .`。

`-a` 让索引按“包名+版本”保留条目，因此 feed 中同时存在 1.0 和 1.1；已存在的版本会跳过重复构建。

### 目标系统配置

`sixlinux-opkg-config` 安装 `/etc/opkg/sixlinux.conf`：

```text
src/gz sixlinux-all http://10.0.2.2:8080/all
src/gz sixlinux-cortexa53 http://10.0.2.2:8080/cortexa53
src/gz sixlinux-machine http://10.0.2.2:8080/sixlinux_qemuarm64
```

镜像启用 `package-management`，加入 opkg 和仓库配置；`10.0.2.2` 是 QEMU slirp 网关，指向 WSL 主机。

### 测试脚本

`tests/opkg-repo.py`：

- 在主机启动 `python3 -m http.server 8080` 服务 feed；
- 用 `SSH_PORT=none` 启动 QEMU，避免与其他手工实例的 2222 端口冲突；
- 登录后执行 `opkg update`、`opkg list`、指定版本安装和升级；
- 结束后关闭 QEMU 和 HTTP 服务。

## 执行命令

```bash
cd /home/dev/sixlinux
make build
make package-repo
make opkg-test
```

## 构建结果

- 镜像 BitBake 3245 个任务全部成功（100 个实际执行，其余来自 sstate）；
- `cortexa53` feed 中同时存在 `sixlinux-hello_1.0-r0_cortexa53.ipk` 和 `sixlinux-hello_1.1-r0_cortexa53.ipk`；
- `Packages` 索引中包含两个版本（`Version: 1.0-r0` 和 `Version: 1.1-r0`）；
- 重复执行 `make package-repo` 时两个版本都提示“已存在，跳过重复构建”，索引重新生成成功。

## 测试结果

`make opkg-test` 连续两次通过，串口日志确认：

```text
Downloading http://10.0.2.2:8080/all/Packages.gz.
Downloading http://10.0.2.2:8080/cortexa53/Packages.gz.
Updated source 'sixlinux-cortexa53'.
Downloading http://10.0.2.2:8080/sixlinux_qemuarm64/Packages.gz.

sixlinux-hello - 1.1-r0 - SixLinux hello package version 1.1
Installing sixlinux-hello (1.0) on root
Downloading http://10.0.2.2:8080/cortexa53/sixlinux-hello_1.0-r0_cortexa53.ipk.
SixLinux hello v1.0
Upgrading sixlinux-hello (1.0-r0) to sixlinux-hello (1.1) on root
SixLinux hello v1.1
```

- 三个软件源全部可访问；
- `opkg list` 默认只显示最新的 1.1，因此通过“安装指定版本再升级”验证两个版本都可用；
- 安装 1.0 后程序输出 `SixLinux hello v1.0`，升级后输出 `SixLinux hello v1.1`；
- 关机正常，HTTP 服务被清理。

P5 镜像回归通过：

- `make boot-test`：TF-A → U-Boot → Linux 零输入自动启动正常；
- `make driver-test`：RTC 模块仍自动加载，AMBA ID `0x00141031`，IRQ `1 → 2`。

日志：

- `artifacts/opkg-test.log`
- `artifacts/opkg-http.log`
- `artifacts/firmware-boot.log`
- `artifacts/rtc-driver-test.log`

## 已知事项

- 当前 feed 是本地 HTTP 开发源，不涉及签名和持久化发布，release 加固属于下一阶段；
- `opkg list` 默认不展示旧版本，这是 opkg 的预期行为，测试用实际安装/升级结果作为判据。

## 阶段提交

- `3846a02 feat: 添加 opkg 在线软件仓库`

本阶段尚未加入 release 安全登录和 CI，后续阶段继续实现。
