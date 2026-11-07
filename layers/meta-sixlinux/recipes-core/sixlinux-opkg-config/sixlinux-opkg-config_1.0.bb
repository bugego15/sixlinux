SUMMARY = "SixLinux opkg repository configuration"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://sixlinux.conf.in \
           file://gpg-home/pubring.kbx \
           file://gpg-home/trustdb.gpg \
           file://LICENSE"

S = "${WORKDIR}"

RDEPENDS:${PN} = "opkg"

do_install() {
    install -d ${D}${sysconfdir}/opkg
    sed -e 's|@SIXLINUX_FEED_BASE@|${SIXLINUX_FEED_BASE}|g' \
        ${WORKDIR}/sixlinux.conf.in > ${D}${sysconfdir}/opkg/sixlinux.conf

    # opkg 验签使用的 GPG keyring，由 scripts/generate-feed-key.sh 生成。
    install -d -m 0700 ${D}${sysconfdir}/opkg/gpg
    install -m 0600 ${WORKDIR}/gpg-home/pubring.kbx ${D}${sysconfdir}/opkg/gpg/pubring.kbx
    install -m 0600 ${WORKDIR}/gpg-home/trustdb.gpg ${D}${sysconfdir}/opkg/gpg/trustdb.gpg
}

FILES:${PN} += "${sysconfdir}/opkg/sixlinux.conf ${sysconfdir}/opkg/gpg"
