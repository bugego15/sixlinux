SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check-env smoke-qemu fetch-poky build firmware package-repo publish-feed run run-direct boot-test boot-test-direct driver-test board-test gpio-test opkg-test ab-disk ota-bundle ota-test release release-test ci

help:
	@printf '%s\n' \
	  'SixLinux development targets:' \
	  '  make check-env        Check host tools and project environment' \
	  '  make smoke-qemu       Create and stop a minimal Cortex-A53 QEMU instance' \
	  '  make fetch-poky       Fetch pinned Poky, kernel and firmware repositories' \
	  '  make build            Build the minimal SixLinux AArch64 image' \
	  '  make firmware         Build TF-A, U-Boot and the QEMU device tree' \
	  '  make package-repo     Build hello 1.0/1.1 and sign the opkg feed' \
	  '  make publish-feed     Copy the signed feed to a publishable directory' \
	  '  make run              Boot through TF-A and U-Boot interactively' \
	  '  make run-direct       Boot directly with a kernel and rootfs' \
	  '  make boot-test        Verify the TF-A/U-Boot/Linux boot chain' \
	  '  make boot-test-direct Verify direct kernel boot' \
	  '  make driver-test      Verify RTC MMIO, IRQ and debugfs' \
	  '  make board-test       Run the on-target board validation suite' \
	  '  make gpio-test        Verify PL061 GPIO in direct-boot mode' \
	  '  make opkg-test        Verify opkg install and upgrade over HTTP' \
	  '  make ab-disk          Build the A/B disk image for OTA' \
	  '  make ota-bundle      Build and sign an OTA upgrade bundle' \
	  '  make ota-test        Verify A/B OTA upgrade and rollback' \
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

publish-feed:
	@bash scripts/publish-feed.sh

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

board-test:
	@python3 tests/board-suite.py

gpio-test:
	@python3 tests/gpio-test.py

opkg-test: package-repo
	@python3 tests/opkg-repo.py

ab-disk:
	@bash scripts/build-ab-disk.sh

ota-bundle:
	@bash scripts/build-ota-bundle.sh

ota-test: ab-disk ota-bundle
	@python3 tests/ota-test.py

release:
	@bash scripts/release-sixlinux.sh

release-test:
	@python3 tests/release-security.py

ci:
	@bash scripts/ci.sh

