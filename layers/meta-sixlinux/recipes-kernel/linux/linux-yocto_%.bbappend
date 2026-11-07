FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 启用 QEMU virt 的 PL061 GPIO 驱动，用于直接启动模式下的 GPIO 子系统验证。
SRC_URI += "file://gpio-pl061.cfg"
