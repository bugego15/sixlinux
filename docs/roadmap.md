# SixLinux 分阶段复现路线

原则：每个阶段都执行“修改、构建、验证、提交”，不把完成品直接作为开发历史。

## 阶段 1：环境和项目骨架

- 创建 `.gitignore`、`Makefile`、环境检查脚本和目录说明；
- 验证 `make check-env`；
- 提交 `chore: add development environment and project skeleton`。

## 阶段 2：Poky 最小 AArch64 镜像

- 固定 Poky、Linux 和工具链版本；
- 创建自定义 layer、machine、distro 和最小 image；
- 执行 `make fetch-poky && make build && make boot-test-direct`；
- 提交最小可启动镜像。

## 阶段 3：TF-A + U-Boot 启动链

- 构建 TF-A BL1/BL2/BL31 和 U-Boot BL33；
- 配置 GICv3、SMC PSCI 和 QEMU 固件 ROM；
- 执行 `make firmware && make boot-test`。

## 阶段 4：U-Boot 自动启动

- 通过配置片段固化 `CONFIG_BOOTCOMMAND`；
- 不再依赖手工输入 `setenv` 和 `booti`；
- 执行零输入启动测试。

## 阶段 5：RTC platform driver

- 修改 PL031 设备树绑定；
- 实现 MMIO、IRQ 和 debugfs；
- 执行 `make driver-test`。

## 阶段 6：opkg 软件仓库

- 集成 opkg 和 HTTP feed；
- 构建 hello 1.0/1.1；
- 执行 `make package-repo && make opkg-test`。

## 阶段 7：release 和安全登录

- 独立 release 构建，去除 debug-tweaks；
- 非 root 用户、SSH 公钥、主机密钥和 root/密码拒绝；
- 执行 `make release && make release-test`。

## 阶段 8：CI 和文档

- 加入本地 CI 和 GitHub Actions；
- 完善架构、构建报告、故障排查和发布说明；
- 执行完整 `make ci`。
