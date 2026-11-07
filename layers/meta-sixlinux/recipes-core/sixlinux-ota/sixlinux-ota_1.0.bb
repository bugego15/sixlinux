SUMMARY = "SixLinux A/B OTA update tool"
DESCRIPTION = "A/B slot update tool with signed OTA bundles and trial-boot confirmation."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

inherit systemd

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://sixlinux-ota \
           file://sixlinux-ota-mark-good.service \
           file://LICENSE"

S = "${WORKDIR}"

RDEPENDS:${PN} = "gnupg-gpg"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/sixlinux-ota ${D}${bindir}/sixlinux-ota

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/sixlinux-ota-mark-good.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/sixlinux-ota-mark-good.service"
SYSTEMD_SERVICE:${PN} = "sixlinux-ota-mark-good.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
