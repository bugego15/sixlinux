# SixLinux A/B OTA boot script
# 由 U-Boot CONFIG_BOOTCOMMAND 从 FAT 分区加载并执行。

echo "SixLinux A/B: reading boot state"
setenv stateaddr 0x4a000000
setenv scriptaddr 0x49000000

if fatload virtio 0:1 ${stateaddr} state.env; then
    env import -t ${stateaddr}
fi

if test -z "${slot}"; then
    setenv slot a
    setenv prev b
    setenv pending 0
    setenv bootcount 0
fi

if test "x${pending}" = "x1"; then
    setexpr bootcount ${bootcount} + 1
    if test ${bootcount} -gt 2; then
        echo "OTA: too many failed boots, rollback from ${slot} to ${prev}"
        setenv slot ${prev}
        setenv pending 0
        setenv bootcount 0
    fi
    env export -t ${stateaddr} slot prev pending bootcount
    fatwrite virtio 0:1 ${stateaddr} state.env ${filesize}
fi

if test "x${slot}" = "xb"; then
    setenv rootpart 3
else
    setenv rootpart 2
fi

echo "OTA: booting slot ${slot} (/dev/vda${rootpart}) pending=${pending} bootcount=${bootcount}"
setenv bootargs root=/dev/vda${rootpart} rw console=ttyAMA0 earlycon=pl011,0x09000000 keep_bootcon ip=dhcp swiotlb=0 panic=5

fatload virtio 0:1 0x40200000 Image
fatload virtio 0:1 0x44000000 virt.dtb
booti 0x40200000 - 0x44000000
