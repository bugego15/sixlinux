# P7 验证记录

## 阶段目标

把前面各阶段的构建和测试串成一条可重复执行的流水线，补齐项目文档，并让 GitHub 上的仓库具备自动 CI 能力。

## 实现内容

### 本地 CI

`scripts/ci.sh` 依次执行：

```text
make check-env
make fetch-poky
make build
make firmware
make package-repo
make boot-test
make driver-test
make opkg-test
make release
make release-test
```

任何一步失败都会立即退出，便于定位问题。

### Makefile

新增两个目标：

- `make smoke-qemu`：只创建并退出 QEMU Cortex-A53 实例，快速验证 QEMU 平台；
- `make ci`：调用 `scripts/ci.sh` 执行完整流水线。

### 测试辅助

- `tests/qemu-smoke.sh`：QMP 最小冒烟测试；
- `tests/debug-sshd.py`：release 镜像 sshd 现场调试脚本；
- `tests/README.md`：所有测试的用途、日志和约定。

### 文档

新增并整合：

- `docs/architecture.md`：平台、启动链、调试回退和仿真边界；
- `docs/build-report.md`：构建结果、产物大小和验证汇总；
- `docs/firmware-report.md`：TF-A/U-Boot 固件启动链细节；
- `docs/rtc-driver.md`：RTC platform driver 设计与验证；
- `docs/opkg-repository.md`：opkg feed 架构和测试流程；
- `docs/release.md`：release 构建、安全策略和密钥管理；
- `docs/bring-up-notes.md`：故障排查记录（新增密钥、端口、SSH 就绪等条目）；
- `README.md`：项目总览、阶段与提交、常用命令、产物和文档索引。

### GitHub Actions

`.github/workflows/ci.yml`：

- 在 `ubuntu-24.04` 上安装 Yocto 依赖、AArch64 交叉工具链、QEMU 和 test 工具；
- 缓存 `cache/downloads` 和 `cache/sstate-cache`；
- 执行 `./scripts/ci.sh`；
- 上传 `artifacts/releases/` 作为构建产物。

推送前用临时分支验证了当前凭据已具备 `workflow` 权限，可以正常推送 GitHub Actions 工作流。

## 执行命令

```bash
cd /home/dev/sixlinux
make check-env
make smoke-qemu
make ci
```

## 验证结果

`make ci` 一次通过（复用本地 sstate，全流程约 6 分钟）：

| 阶段 | 结果 |
| --- | --- |
| `check-env` | 环境检查通过 |
| `fetch-poky` | 所有源码缓存命中固定提交 |
| `build` | 3279 个 BitBake 任务全部成功 |
| `firmware` | U-Boot 1104 个任务全部成功，TF-A 重新链接 |
| `package-repo` | hello 1.0/1.1 已存在，索引重建成功 |
| `boot-test` | TF-A → U-Boot → SixLinux 零输入启动通过 |
| `driver-test` | AMBA ID `0x00141031`，IRQ `1 → 2` |
| `opkg-test` | 1.0 安装、1.1 升级通过 |
| `release` | release 镜像 3279 个任务全部成功（全部命中 sstate），发布目录重新生成 |
| `release-test` | dev 公钥登录、sudo、root/密码拒绝、关机全部通过 |

测试时间线（本次执行）：

```text
12:17:21  opkg feed 索引重建
12:17:46  boot-test 通过
12:18:14  driver-test 通过
12:18:39  opkg-test 通过
12:19:27  release-test 通过
```

`make smoke-qemu` 单独验证通过：

```text
QEMU Cortex-A53 平台实例化测试通过（尚未加载内核）。
```

## 已知事项

- 本地 CI 依赖事前完成过的下载和 sstate 缓存；全新环境第一次运行会显著更久；
- GitHub Actions 首次云端运行需要重新下载依赖和源码缓存，可能较慢，后续可复用 Actions 缓存；
- WSL2 和主机内核 I/O 统计提示属于环境警告，不影响流水线结果；
- `artifacts/` 目录（含日志和发布产物）不进入版本库，由各次构建重新生成。

## 最终状态

`dev` 分支包含从 P0 到 P7 的完整增量历史，最终代码合并到 `main` 分支并推送到 GitHub。

## 阶段提交

- `951dbcc ci: 添加本地 CI 流水线`
- `d9b40b5 docs: 补全架构、构建、固件和发布文档`
- `115a5ed ci: 添加 GitHub Actions 工作流`
