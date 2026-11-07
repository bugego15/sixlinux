SUMMARY = "SixLinux minimal AArch64 system"
DESCRIPTION = "Headless SixLinux minimal image with systemd and OpenSSH."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES:append = " ssh-server-openssh"
