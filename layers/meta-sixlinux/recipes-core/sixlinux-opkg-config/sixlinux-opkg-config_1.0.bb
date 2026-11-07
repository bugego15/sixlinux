SUMMARY = "SixLinux opkg repository configuration"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://sixlinux.conf file://LICENSE"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/opkg
    install -m 0644 ${WORKDIR}/sixlinux.conf ${D}${sysconfdir}/opkg/sixlinux.conf
}
