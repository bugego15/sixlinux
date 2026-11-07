# 自动化测试

所有测试都以 QEMU 串口控制台和 SSH 转发为入口，失败时会打印对应日志路径。

## 平台与启动

- `make smoke-qemu`：只创建并退出 QEMU Cortex-A53 实例，验证 QEMU 平台可用；
- `make boot-test`：零输入验证 TF-A → U-Boot → Linux 自动启动，日志为 `artifacts/firmware-boot.log`；
- `make boot-test-direct`：验证直接内核启动，日志为 `artifacts/qemu-boot.log`。

## RTC 驱动

```bash
make driver-test
```

验证 platform 绑定、AMBA ID、MMIO 数据、第一次 alarm 中断、debugfs 触发后的第二次中断。日志为 `artifacts/rtc-driver-test.log`。

## opkg 在线仓库

```bash
make opkg-test
```

验证 HTTP feed、`sixlinux-hello=1.0-r0` 安装和 1.1 升级。日志为 `artifacts/opkg-test.log` 和 `artifacts/opkg-http.log`。

测试会在主机临时启动 8080 端口的 HTTP 服务，结束后自动清理。

## release 安全测试

```bash
make release-test
```

验证 release 非 root 公钥登录、sudo、sshd 生效配置、root 登录拒绝、密码登录拒绝以及 sudo 关机。日志为 `artifacts/release-security.log`。

## 完整流水线

```bash
make ci
```

依次执行环境检查、源码获取、镜像/固件/仓库构建、四项启动与功能测试、release 构建和安全测试。

## 约定

- 启动测试都带超时和失败清理逻辑，并使用 QEMU `-snapshot` 避免修改原始镜像；
- 需要串口交互的测试通过 `SSH_PORT=none` 关闭主机 2222 端口转发，因此可以与本机手工 `make run` 同时运行；
- release 测试需要 `artifacts/keys/` 中的密钥，缺少时会由构建脚本自动生成。
