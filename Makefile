SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check-env smoke-qemu fetch-poky build firmware package-repo run run-direct boot-test boot-test-direct driver-test opkg-test release release-test ci

help:
	@printf '%s\n' \
	  'SixLinux development targets:' \
	  '  make check-env        Check host tools and project environment' \
	  '  make smoke-qemu       Create and stop a minimal Cortex-A53 QEMU instance' \
	  '  make fetch-poky       Fetch pinned Poky, kernel and firmware repositories' \
	  '  make build            Build the minimal SixLinux AArch64 image' \
	  '  make firmware         Build TF-A, U-Boot and the QEMU device tree' \
	  '  make package-repo     Build hello 1.0/1.1 and the opkg feed' \
	  '  make run              Boot through TF-A and U-Boot interactively' \
	  '  make run-direct       Boot directly with a kernel and rootfs' \
	  '  make boot-test        Verify the TF-A/U-Boot/Linux boot chain' \
	  '  make boot-test-direct Verify direct kernel boot' \
	  '  make driver-test      Verify RTC MMIO, IRQ and debugfs' \
	  '  make opkg-test        Verify opkg install and upgrade over HTTP' \
	  '  make release          Build and package the secure release image' \
	  '  make release-test     Verify release SSH security and poweroff' \
	  '  make ci               Run the complete local CI pipeline'

check-env:
	@bash scripts/check-env.sh

smoke-qemu:
	@bash tests/qemu-smoke.sh

fetch-poky:
	@bash scripts/fetch-poky.sh
	@bash scripts/fetch-kernel-cache.sh
	@bash scripts/fetch-firmware.sh

build:
	@bash scripts/build-qemuarm64.sh

firmware:
	@bash scripts/build-firmware.sh

package-repo:
	@bash scripts/build-package-repo.sh

run:
	@bash scripts/run-firmware.sh

run-direct:
	@bash scripts/run-qemuarm64.sh

boot-test:
	@python3 tests/boot-firmware.py

boot-test-direct:
	@python3 tests/boot-qemuarm64.py

driver-test:
	@python3 tests/driver-rtc.py

opkg-test:
	@python3 tests/opkg-repo.py

release:
	@bash scripts/release-sixlinux.sh

release-test:
	@python3 tests/release-security.py

ci:
	@bash scripts/ci.sh
