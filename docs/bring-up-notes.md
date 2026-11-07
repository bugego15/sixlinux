# 构建故障排查记录

| 问题 | 原因 | 处理 |
| --- | --- | --- |
| BitBake 无法启动 | WSL 缺少 `en_US.UTF-8` locale | 使用 `locale-gen en_US.UTF-8`，并加入 `make check-env` |
| 自定义 TEMPLATECONF 被拒绝 | Poky 要求模板位于 layer 的 `conf/templates/<name>` | 将模板移动到 `meta-sixlinux/conf/templates/qemuarm64` |
| 初始化脚本提示 BBSERVER 未定义 | Poky 初始化脚本与 Bash `nounset` 不兼容 | 仅在 source 初始化脚本时暂停 `nounset` |
| machine 出现重复 include 警告 | 同时继承 qemuarm64 和第二套 tune 文件 | 直接复用公共 QEMU 配置，只包含一次 Cortex-A53 tune |
| 多个源码下载失败 | 原始站点在当前网络不可达或较慢 | 使用 Yocto 官方源码镜像，保留默认回退 |
| 远程 sstate 检查长期无响应 | 当前网络不适合逐项检查官方 sstate | 移除远程 sstate，只保留本地缓存和源码镜像 |
| linux-yocto 下载约 4.24 GB | 镜像包包含完整 Git 历史 | 固定 SRCREV，使用真正的浅克隆 bare 缓存 |
| U-Boot 下载约 281 MB | 同样需要避免全历史下载 | 按 Poky SRCREV 创建约 31 MB 的浅克隆缓存 |
| Meson `Clock skew detected` | WSL 时钟/文件时间戳出现亚秒级偏差 | 清理失败的两个 recipe 后重试，未全量清理构建 |
| WIC 找不到 kickstart 文件 | 自定义 machine 没有默认 WKS 匹配 | 初版采用与上游 qemuarm64 一致的 ext4 直接启动 |
| runqemu 找不到 IMAGE_LINK_NAME | 自定义 image 名称无法由当前参数自动推断 | 直接传入生成的 `.qemuboot.conf` |
| TF-A 与 GIC 配置不一致 | TF-A QEMU 平台默认编译 GICv2 | 显式使用 `QEMU_USE_GIC_DRIVER=QEMU_GICV3` 重建 |
| Linux 执行 HVC 后未定义指令异常 | QEMU DTB 默认 PSCI 为 HVC，但 EL3 TF-A 需要 SMC | 使用 `fdtput` 将 `/psci/method` 改为 `smc` |
| Linux AMBA external abort | 非安全 Linux 枚举访问 `secure=on` 下的 `pl061@9030000` | 禁用该 GPIO 节点，保留 RTC 和其他外设 |
| 内核早期没有日志 | 默认 console 初始化前无法看到故障位置 | 在 bootargs 中加入 PL011 earlycon 和 keep_bootcon |
| 自动启动测试误报缺少 booti | 自动 `CONFIG_BOOTCOMMAND` 不回显手工输入的命令 | 检查自动倒计时、DTB 加载以及未进入默认 bootflow |
| RTC recipe 找不到源码 | `FILESEXTRAPATHS` 未指向实际的 recipe 子目录 | 使用 `${THISDIR}/${PN}/files` |
| 模块编译提示 No targets | Kbuild 缺少 `modules` 目标且未设置 `MAKE_TARGETS` | 增加标准 Kbuild 目标并设置 `MAKE_TARGETS = "modules"` |
| RTC 驱动与 AMBA 总线冲突 | PL031 默认进入 AMBA 而非 platform 总线 | DTB 中移除 `arm,primecell`，由项目 platform_driver 匹配 `arm,pl031` |
| AMBA ID 完全相等判断失败 | 实际 ID 含变体位，返回 `0x00141031` | 使用 `0x000fffff` 掩码比较 |
| opkg 配置包找不到 provider | recipe 文件名与 `IMAGE_INSTALL` 包名不一致 | 统一目录、recipe 文件名和安装名称 |
| feed 索引只有最新版本 | `opkg-make-index` 默认按包名和架构去重 | 使用 `-a` 把版本加入索引键，保留 1.0 和 1.1 |
| opkg list 看不到旧版本 | 默认只显示最新版本 | 通过实际安装指定版本和 upgrade 验证 |
| release sshd 为 0 字节 | 旧 OpenSSH sstate 恢复了异常包 | 清理 OpenSSH sstate 并重新编译打包，再重建 rootfs |
| sshd 启动时没有主机密钥 | 自定义配置缺少 HostKey | 在 drop-in 中保留 ed25519 HostKey，并预装主机密钥 |
| dev 公钥登录被拒绝 | shadow 中 `!` 锁定密码阻断账户 | 使用空密码字段，同时保持密码和空密码认证关闭 |
| release 测试关机超时 | root 控制台锁定，不能发送 poweroff 作为登录名 | 通过 dev 公钥和 sudo 执行 poweroff |
| 全新克隆构建缺少 SSH 密钥文件 | security recipe 的 `SRC_URI` 依赖构建期密钥 | `build-qemuarm64.sh` 每次构建前调用 `generate-keys.sh` 生成并复制 |
| 密钥材料可能误提交到仓库 | 生成文件位于 layer 目录内 | 把 `authorized_keys`、主机密钥和 `.pub` 加入 `.gitignore` |
| 自动化测试与手工 QEMU 抢 2222 端口 | 两者都使用 hostfwd 2222 | 自动化测试用 `SSH_PORT=none` 关闭转发，手工 `make run` 保留 |
| release 手工 SSH 偶发 banner 超时 | 只探测到 TCP 端口就立即 SSH，sshd 尚未就绪 | 测试先等待登录提示再发起 SSH |
| WSL 后台 `nohup` 启动的 QEMU 随会话退出 | WSL 实例在最后一个前台进程结束后回收 | 用持续运行的前台命令或工具后台任务托管 QEMU |
| GitHub Actions 上 BitBake 立即失败 | Ubuntu 24.04 runner 通过 AppArmor 限制非特权 user namespace | workflow 中执行 `sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` |
| GitHub Actions 运行器磁盘不足 | 免费 runner 只有约 14 GB 可用空间 | workflow 先删除 Android、.NET、GHC、CodeQL 等预装目录释放空间 |
| 改内核配置后外部模块 `do_package` 失败 | WSL 下 pseudo 数据库记录的 inode 与重建文件不一致 | `bitbake -c cleansstate sixlinux-rtc-driver` 后重建（dev 和 release 构建目录各做一次） |
| 板级测试误判 net namespace 未隔离 | 新 netns 中内核仍会创建 `sit0` | 检查改为"主机物理网卡没有泄漏"，而不是要求接口数等于 1 |
| seccomp 测试取不到 EPERM | glibc `getppid()` 返回 -1 时不设置 errno | 测试改用 `syscall(SYS_getppid)` 判断拦截结果 |
| U-Boot 无法把 bootcount 写回 FAT | 默认环境在 flash，QEMU 下不可写 | 用 `env export -t` + `fatwrite` 把状态文件写回启动分区 |
| OTA 状态里根设备显示 `/dev/root` | `root=` 传设备路径时 /proc/mounts 不保留真实设备名 | 通过 `/proc/self/mountinfo` 的 major:minor 查 `/sys/dev/block` 反推 `/dev/vdaN` |
| A/B 磁盘镜像根分区只有 17 MiB | deploy 目录里 ext4 是符号链接，`stat` 取到链接长度 | 用 `readlink -f` 解析后再计算分区大小 |
| FAT32 在 32 MiB 启动分区上告簇数不足 | FAT32 建议的最小卷更大 | 启动分区改用 FAT16，U-Boot 读取不受影响 |

这些记录用于后续复现和面试讲解，不把环境问题或工具配置问题描述成真实硬件驱动问题。
