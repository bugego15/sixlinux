SUMMARY = "SixLinux non-root SSH key login and sudo configuration"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aa343fe577ceab96d61d63c987201f5f"

inherit useradd

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}/files:"
SRC_URI = "file://sixlinux-dev-sudoers \
           file://authorized_keys \
           file://99-sixlinux.conf \
           file://ssh_host_ed25519_key \
           file://ssh_host_ed25519_key.pub \
           file://LICENSE"

S = "${WORKDIR}"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "-u 1000 -d /home/dev -g dev -p '' dev"
GROUPADD_PARAM:${PN} = "-g 1000 dev"
RDEPENDS:${PN} = "sudo"

do_install() {
    install -d ${D}${sysconfdir}/sudoers.d
    install -m 0440 ${WORKDIR}/sixlinux-dev-sudoers ${D}${sysconfdir}/sudoers.d/sixlinux-dev

    install -d ${D}${sysconfdir}/ssh/sshd_config.d
    install -m 0644 ${WORKDIR}/99-sixlinux.conf ${D}${sysconfdir}/ssh/sshd_config.d/99-sixlinux.conf
    install -m 0600 ${WORKDIR}/ssh_host_ed25519_key ${D}${sysconfdir}/ssh/ssh_host_ed25519_key
    install -m 0644 ${WORKDIR}/ssh_host_ed25519_key.pub ${D}${sysconfdir}/ssh/ssh_host_ed25519_key.pub

    install -d ${D}/home/dev/.ssh
    install -m 0600 ${WORKDIR}/authorized_keys ${D}/home/dev/.ssh/authorized_keys
    chown -R dev:dev ${D}/home/dev
    chmod 0700 ${D}/home/dev/.ssh
}

FILES:${PN} += "${sysconfdir}/sudoers.d/sixlinux-dev \
                ${sysconfdir}/ssh/sshd_config.d/99-sixlinux.conf \
                ${sysconfdir}/ssh/ssh_host_ed25519_key \
                ${sysconfdir}/ssh/ssh_host_ed25519_key.pub \
                /home/dev/.ssh/authorized_keys"
