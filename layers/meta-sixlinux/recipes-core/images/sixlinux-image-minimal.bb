SUMMARY = "SixLinux minimal AArch64 system"
DESCRIPTION = "Headless SixLinux image with systemd, OpenSSH, RTC driver, opkg feed and non-root SSH login."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES:append = " ssh-server-openssh package-management"
IMAGE_INSTALL:append = " kernel-module-sixlinux-rtc sixlinux-opkg-config sixlinux-security"
