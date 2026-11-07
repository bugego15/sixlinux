# 上游源码

本阶段固定以下版本：

- Yocto `scarthgap` / Poky `5.0.21`，提交 `2a6862e7ed4cb2f030f6341458df61282bf8a5ca`；
- linux-yocto 分支 `v6.6/standard/qemuarm64`，SRCREV `dce83a630a519666f8c5599478cd8db87cf772c2`；
- yocto-kernel-cache 分支 `yocto-6.6`，SRCREV `111e66d07f015c08755ae564c4a2f4a7710863ef`。

精确版本记录在 `versions.env`。获取源码：

```bash
make fetch-poky
```

内核使用精确提交的浅克隆缓存，避免下载完整 Git 历史。上游工作树不提交到项目仓库，项目只跟踪版本和获取脚本。
