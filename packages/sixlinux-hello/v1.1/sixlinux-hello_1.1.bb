SUMMARY = "SixLinux hello package version 1.1"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://hello.c file://LICENSE"

S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} hello.c -o sixlinux-hello
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 sixlinux-hello ${D}${bindir}/sixlinux-hello
}
