# 自有签名软件源

## 目标

SixLinux 不再只依赖构建机上临时启动的未签名 HTTP 目录，而是提供一套"属于我们自己的、地址可配置、带 GPG 签名"的软件源：

- feed 由本项目构建产生，内容完全可控；
- 目标系统强制校验索引签名，拒绝被篡改的包列表；
- 源地址通过 `SIXLINUX_FEED_BASE` 配置，可指向本机、局域网或公网 HTTPS；
- 私钥只留在构建机，不进入仓库和镜像。

## 架构

```text
构建机
  ├── generate-feed-key.sh   生成 feed 签名密钥（RSA 3072）
  ├── build-package-repo.sh  生成 Packages / Packages.gz / Packages.asc
  ├── publish-feed.sh        复制到可发布目录（本机/LAN/公网服务器根目录）
  └── 私钥 artifacts/keys/gnupg-feed，公钥 keyring 写入 layer files/

目标系统
  ├── /etc/opkg/sixlinux.conf    src/gz 地址 + check_signature 1
  ├── /etc/opkg/gpg/             公钥 keyring（pubring.kbx + trustdb.gpg）
  └── opkg update
        ├── 下载 Packages.gz
        ├── 下载 Packages.asc
        └── 解压 Packages 后用内置公钥验签
```

## 签名规则

opkg 的验签行为（`pkg_src_download` / `pkg_src_download_signature` / `pkg_src_verify`）：

1. 对 `src/gz` 源，下载 `Packages.gz`；
2. 下载同目录的 `Packages.asc`（`signature_type gpg-asc`）或 `Packages.sig`（`gpg`）；
3. 把 `Packages.gz` 解压为本地列表文件；
4. 用公钥对"解压后的 Packages 内容"做分离签名校验。

因此 `scripts/build-package-repo.sh` 对**未压缩的 `Packages`** 生成 ASCII 装甲分离签名 `Packages.asc`，而不是对 `.gz` 签名。签名类型在目标端配置为 `gpg-asc`。

## 密钥管理

- `scripts/generate-feed-key.sh`：
  - 在 `artifacts/keys/gnupg-feed/` 生成 RSA 3072 签名密钥（无口令，便于本地自动化）；
  - 记录完整指纹到 `artifacts/keys/feed-key-id`；
  - 把该密钥标记为 ultimate trust，使 opkg 默认的 `TrustOnly` 策略可以通过；
  - 导出公钥到 `sixlinux-feed.asc` 便于人工核对；
  - 生成镜像内 keyring：`pubring.kbx` + `trustdb.gpg` 写入 layer 的 `gpg-home/`。
- 私钥、trustdb 和导出的公钥都由 `.gitignore` 排除，不进入版本库；
- `build-qemuarm64.sh` 在每次构建前调用该脚本，全新克隆也能直接构建。

## 目标端配置

`sixlinux-opkg-config` 生成 `/etc/opkg/sixlinux.conf`：

```text
src/gz sixlinux-all        @SIXLINUX_FEED_BASE@/all
src/gz sixlinux-cortexa53  @SIXLINUX_FEED_BASE@/cortexa53
src/gz sixlinux-machine    @SIXLINUX_FEED_BASE@/sixlinux_qemuarm64

option signature_type gpg-asc
option check_signature 1
```

`@SIXLINUX_FEED_BASE@` 在构建时由 `SIXLINUX_FEED_BASE` 变量替换，默认 `http://10.0.2.2:8080`。

同时安装 `/etc/opkg/gpg/` 公钥 keyring；opkg 需要由 `PACKAGECONFIG` 打开 `gpg`，镜像会带上 `gnupg-gpg`、`gpgme` 等运行时依赖。

## 地址可配置

distro 配置里默认：

```bitbake
SIXLINUX_FEED_BASE ?= "http://10.0.2.2:8080"
```

在 `build/qemuarm64/conf/local.conf` 或 release 模板中覆盖即可，例如：

```bitbake
SIXLINUX_FEED_BASE = "https://feed.example.com/sixlinux"
```

opkg 已启用 `ssl-curl`，并安装 `ca-certificates`，可以访问 HTTPS 源。

## 发布流程

```bash
make build            # 构建包含 opkg 验签能力的镜像
make package-repo     # 构建 hello 1.0/1.1，重建索引并签名
make publish-feed     # 复制到 artifacts/feed/published（可用 FEED_PUBLISH_DIR 覆盖）
```

托管方式示例：

```bash
cd artifacts/feed/published
python3 -m http.server 8080 --bind 0.0.0.0
```

私有部署时把该目录放到内网 nginx、对象存储或只对特定网段开放的 HTTPS 服务即可；公网部署则应保持 HTTPS 并妥善保管签名私钥。

## 验证

`make opkg-test` 覆盖：

- 目标端配置文件包含 `check_signature 1` 和 `signature_type gpg-asc`；
- `/etc/opkg/gpg/pubring.kbx` 存在；
- `opkg update` 验签通过；
- `opkg install sixlinux-hello=1.0-r0`、`opkg upgrade` 正常；
- **负向测试**：把 `Packages.asc` 篡改为非法内容后，`opkg update` 必须报 `Signature verification failed`；
- 恢复签名后 `opkg update` 重新成功。

## 安全边界

- 当前只对 feed 索引签名（`check_signature`），未开启逐包签名（`check_pkg_signature`）；索引内包含每个包的校验和，可防止安装未列入索引或校验和错误的包；
- 签名私钥保存在构建机 `artifacts/`，仓库中只有公钥 keyring，适合演示与内部使用；生产环境应使用带口令的离线密钥并定期轮换；
- `TrustOnly` 依赖随镜像安装的 trustdb，更换签名密钥后必须重新构建镜像；如需在不重新构建的情况下换钥，可考虑改为 `TrustAny` 并严格控制系统 keyring；
- 图片/镜像不包含签名私钥，泄露仓库不会导致 feed 被伪造。
