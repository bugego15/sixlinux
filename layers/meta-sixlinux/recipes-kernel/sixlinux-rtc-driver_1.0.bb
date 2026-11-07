SUMMARY = "SixLinux PL031 RTC MMIO/IRQ platform driver"
DESCRIPTION = "Out-of-tree platform driver demonstrating device-tree binding, MMIO, IRQ handling and debugfs."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"

inherit module

SRC_URI = "file://Makefile \
           file://sixlinux_rtc.c \
           file://LICENSE"

S = "${WORKDIR}"
MAKE_TARGETS = "modules"

KERNEL_MODULE_AUTOLOAD = "sixlinux_rtc"
RPROVIDES:${PN} += "kernel-module-sixlinux-rtc"
