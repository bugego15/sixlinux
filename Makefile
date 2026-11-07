SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check-env fetch-poky build firmware run run-direct boot-test boot-test-direct driver-test

help:
	@printf '%s\n' \
	  'SixLinux development targets:' \
	  '  make check-env        Check host tools and project environment' \
	  '  make fetch-poky       Fetch pinned Poky, kernel and firmware repositories' \
	  '  make build            Build the minimal SixLinux AArch64 image' \
	  '  make firmware         Build TF-A, U-Boot and the QEMU device tree' \
	  '  make run              Boot through TF-A and U-Boot interactively' \
	  '  make run-direct       Boot directly with a kernel and rootfs' \
	  '  make boot-test        Verify the TF-A/U-Boot/Linux boot chain' \
	  '  make boot-test-direct Verify direct kernel boot' \
	  '  make driver-test      Verify RTC MMIO, IRQ and debugfs'

check-env:
	@bash scripts/check-env.sh

fetch-poky:
	@bash scripts/fetch-poky.sh
	@bash scripts/fetch-kernel-cache.sh
	@bash scripts/fetch-firmware.sh

build:
	@bash scripts/build-qemuarm64.sh

firmware:
	@bash scripts/build-firmware.sh

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
