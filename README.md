# SixLinux

面向 AArch64 的嵌入式 Linux 发行版与板级启动验证平台。

## 当前阶段

**阶段 1：开发环境和项目骨架。**

本阶段只建立开发环境检查、目录约定和后续实施路线，尚未开始生成 Linux 镜像。

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

## 环境检查

```powershell
wsl -d Ubuntu-24.04
```

```bash
cd /home/dev/sixlinux
make check-env
```

检查内容包括：非 root 用户、编译和仿真工具、AArch64 工具链、QEMU Cortex-A53、UTF-8 locale 和 WSL 原生文件系统。

## 后续路线

1. 环境和项目骨架；
2. Poky 最小 AArch64 镜像；
3. TF-A + U-Boot 启动链；
4. U-Boot 自动启动；
5. RTC platform driver；
6. opkg 软件仓库和版本升级；
7. release 安全登录和发布产物；
8. CI 与文档完善。

每个阶段都执行“修改、构建、验证、提交”，详细路线见 `docs/roadmap.md`。
