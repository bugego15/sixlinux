SUMMARY = "SixLinux board bring-up validation suite"
DESCRIPTION = "Userspace checks for CPU features, SMP, memory, IRQ latency, RTC, block I/O, network and systemd."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://boardtest.c file://LICENSE"

S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} boardtest.c -o sixlinux-boardtest -pthread
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 sixlinux-boardtest ${D}${bindir}/sixlinux-boardtest
}
