# 上游源码

本阶段固定以下版本：

- Yocto `scarthgap` / Poky `5.0.21`，提交 `2a6862e7ed4cb2f030f6341458df61282bf8a5ca`；
- linux-yocto 分支 `v6.6/standard/qemuarm64`，SRCREV `dce83a630a519666f8c5599478cd8db87cf772c2`；
- yocto-kernel-cache 分支 `yocto-6.6`，SRCREV `111e66d07f015c08755ae564c4a2f4a7710863ef`；
- U-Boot `2024.01`，SRCREV `866ca972d6c3cabeaf6dbac431e8e08bb30b3c8e`；
- TF-A `v2.10.0`，提交 `b6c0948400594e3cc4dbb5a4ef04b815d2675808`。

精确版本记录在 `versions.env`。获取源码：

```bash
make fetch-poky
```

内核、U-Boot 和 TF-A 都使用精确提交的浅克隆缓存，避免下载完整 Git 历史。U-Boot 的缓存同时供 BitBake 使用，因此仍放在 `cache/downloads/git2/` 下。上游工作树不提交到项目仓库，项目只跟踪版本和获取脚本。
