# P1 验证记录

## 阶段目标

建立固定版本的 Poky 构建环境、自定义 layer、machine、distro 和最小 AArch64 镜像，并用直接内核启动方式验证。

## 执行命令

```bash
cd /home/dev/sixlinux
make fetch-poky
make build
make boot-test-direct
```

## 结果

- Poky 5.0.21 和 Linux 6.6.160 版本固定成功；
- `sixlinux-qemuarm64` machine 和 `sixlinux` distro 解析成功；
- BitBake 共执行 3123 个任务，全部成功；
- QEMU 直接内核启动成功；
- root 登录成功；
- `uname -m = aarch64`；
- `nproc = 2`；
- `/etc/os-release` 包含 SixLinux；
- `systemctl is-system-running = running`；
- `poweroff` 正常关机。

串口日志：`artifacts/qemu-boot.log`。

## 阶段提交

- `a6084f2 chore: add development environment and project skeleton`
- `a821406 feat: add minimal Poky AArch64 image`

本阶段尚未加入 TF-A/U-Boot、RTC 驱动、opkg 软件仓库和 release 安全配置，后续阶段继续实现。
