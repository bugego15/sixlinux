# P9 验证记录

## 阶段目标

把原来只能靠构建机临时 HTTP 目录提供的未签名 opkg feed，升级为"属于 SixLinux 自己的、GPG 签名、地址可配置"的软件源：

- feed 内容由本项目构建，不依赖任何第三方发行版仓库；
- 目标端强制校验索引签名，篡改会被拒绝；
- 源地址通过 `SIXLINUX_FEED_BASE` 配置，可指向本机、局域网或公网 HTTPS；
- 签名私钥只留在构建机，仓库和镜像只包含公钥。

## 实现内容

### 签名密钥

`scripts/generate-feed-key.sh`：

- 在 `artifacts/keys/gnupg-feed/` 生成 RSA 3072 签名密钥（无口令，便于本地自动化）；
- 完整指纹写入 `artifacts/keys/feed-key-id`；
- 把密钥标记为 ultimate trust，满足 opkg 默认的 `TrustOnly`；
- 导出公钥到 `sixlinux-feed.asc` 便于人工核对；
- 生成镜像内 keyring：`pubring.kbx` + `trustdb.gpg` 写入 layer 的 `gpg-home/`；
- 私钥和 keyring 生成物全部由 `.gitignore` 排除。

`build-qemuarm64.sh` 每次构建前调用该脚本，全新克隆可以直接构建。

### 索引签名

`scripts/build-package-repo.sh` 在 `opkg-make-index -a` 之后：

- 用签名密钥对**未压缩的 `Packages`** 生成 ASCII 装甲分离签名 `Packages.asc`。

这是根据 opkg 0.6.3 的实际行为确定的：目标端下载 `Packages.gz` 后解压成本地列表文件，再用 `Packages.asc` 对解压后的内容验签（`pkg_src_download_signature` / `pkg_src_verify`）。

### 目标端配置

`sixlinux-opkg-config` 改为从模板生成配置：

```text
src/gz sixlinux-all        @SIXLINUX_FEED_BASE@/all
src/gz sixlinux-cortexa53  @SIXLINUX_FEED_BASE@/cortexa53
src/gz sixlinux-machine    @SIXLINUX_FEED_BASE@/sixlinux_qemuarm64
option signature_type gpg-asc
option check_signature 1
```

同时安装 `/etc/opkg/gpg/` 公钥 keyring。

`layers/meta-sixlinux/conf/distro/sixlinux.conf`：

- `SIXLINUX_FEED_BASE ?= "http://10.0.2.2:8080"`
- `PACKAGECONFIG:append:pn-opkg = " gpg ssl-curl"`

镜像额外安装 `ca-certificates`，为后续 HTTPS 源做准备。

### 发布

`scripts/publish-feed.sh`（`make publish-feed`）把签名 feed 复制到可发布目录，默认 `artifacts/feed/published`，可用 `FEED_PUBLISH_DIR` 覆盖，并生成使用说明 `README.txt`。

## 执行命令

```bash
cd /home/dev/sixlinux
make check-env
make build
make package-repo
make opkg-test
make publish-feed
make ci
```

## 构建结果

- 开发镜像：3547 个 BitBake 任务全部成功，其中 3256 个命中 sstate，实际执行 291 个（含 opkg 的 GPG/HTTPS 能力重建）；
- release 镜像（CI 内构建）：3547 个任务全部成功，3518 个命中 sstate，实际执行 29 个；
- `bitbake -e opkg` 确认 `PACKAGECONFIG="libsolv gpg ssl-curl"`，`RDEPENDS` 包含 `gnupg-gpg`；
- 镜像内确认：
  - `/etc/opkg/sixlinux.conf` 含三个 `src/gz` 和 `check_signature 1`、`signature_type gpg-asc`；
  - `/etc/opkg/gpg/` 含 `pubring.kbx`、`trustdb.gpg`；
  - `/usr/bin/gpg`、`/etc/ssl/certs` 存在；
  - feed 的三个目录都生成了 `Packages.asc`（每个 659 字节）。

## 验证结果

### 签名源功能与强制验签

`make opkg-test` 通过，串口日志确认：

```text
Updated source 'sixlinux-all'.
Updated source 'sixlinux-cortexa53'.
Updated source 'sixlinux-machine'.
option signature_type gpg-asc
option check_signature 1
pubring.kbx  trustdb.gpg
Installing sixlinux-hello (1.0) on root
SixLinux hello v1.0
Upgrading sixlinux-hello (1.0-r0) to sixlinux-hello (1.1) on root
SixLinux hello v1.1
```

篡改 `cortexa53/Packages.asc` 后：

```text
 * opkg_verify_gpg_signature: Unable to verify signature: No data
 * pkg_src_verify: Signature verification failed for sixlinux-cortexa53.
```

恢复签名并清空列表后，三个源重新 `Updated source` 成功。

### 地址可配置

在构建目录 `local.conf` 中追加：

```bitbake
SIXLINUX_FEED_BASE = "http://10.0.2.2:9090"
```

重新构建后镜像内配置变为 `http://10.0.2.2:9090/{all,cortexa53,sixlinux_qemuarm64}`；恢复默认后重新构建又回到 `http://10.0.2.2:8080`。两次构建均成功。

### 发布

`make publish-feed` 输出：

```text
已发布软件源到：/home/dev/sixlinux/artifacts/feed/published
```

发布目录约 548 MB，包含 `README.txt`、三个 feed 子目录，以及每个目录下的 `Packages`、`Packages.gz`、`Packages.asc` 和全部 ipk。

### 完整 CI 回归

`make ci` 一次通过：

```text
check-env → fetch-poky → build → firmware → package-repo → boot-test
→ driver-test → board-test → opkg-test → release → release-test
```

release 镜像同样带上签名源配置，`release-test` 的 SSH 安全检查不受影响。

## 日志

| 日志 | 内容 |
| --- | --- |
| `artifacts/opkg-test.log` | 签名源更新、安装、升级、篡改拒绝 |
| `artifacts/opkg-http.log` | 本地 HTTP feed 请求 |
| `artifacts/firmware-boot.log` | CI 内启动链回归 |
| `artifacts/release-security.log` | release 安全检查 |

## 已知事项

- 当前只对 feed 索引签名（`check_signature`），未开启逐包签名（`check_pkg_signature`）；索引中包含每个包的校验和，可阻止安装未列入索引或校验和错误的包；
- `TrustOnly` 依赖镜像内随带的 trustdb，更换签名密钥后需要重新构建镜像；如需在线换钥，可改用 `TrustAny` 并严格控制 keyring；
- 签名私钥无口令，仅适合本地开发和演示；生产环境应使用带口令的离线密钥并定期轮换；
- opkg 已编译 HTTPS 能力并安装 CA 证书，本次验证使用本地 HTTP；公网部署还需自行提供 HTTPS 托管和访问控制；
- 发布目录约 548 MB，其中包含全部开发包（含 dbg/dev/src），正式发布前可按需裁剪。

## 阶段提交

- `f666e6d feat: 支持 GPG 签名的自有软件源`
