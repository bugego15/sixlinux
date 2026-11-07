SUMMARY = "SixLinux minimal AArch64 system"
DESCRIPTION = "Headless SixLinux image with systemd, OpenSSH and the RTC platform driver."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES:append = " ssh-server-openssh"
IMAGE_INSTALL:append = " kernel-module-sixlinux-rtc"
