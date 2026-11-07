# 项目 Layers

后续自定义 Yocto layer 将放在 `layers/` 下。

计划结构：

```text
layers/meta-sixlinux/
├── conf/
│   ├── layer.conf
│   ├── distro/
│   ├── machine/
│   └── templates/
├── recipes-core/
│   ├── images/
│   ├── opkg-config/
│   └── sixlinux-security/
├── recipes-bsp/
│   └── u-boot/
├── recipes-kernel/
│   └── sixlinux-rtc-driver/
└── recipes-apps/
    └── sixlinux-hello/
```

本阶段只记录目录约定，不创建镜像、驱动或软件包 recipe。
