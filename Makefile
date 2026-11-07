SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check-env fetch-poky build run-direct boot-test-direct

help:
	@printf '%s\n' \
	  'SixLinux development targets:' \
	  '  make check-env        Check host tools and project environment' \
	  '  make fetch-poky       Fetch pinned Poky and kernel repositories' \
	  '  make build            Build the minimal SixLinux AArch64 image' \
	  '  make run-direct       Boot directly with a kernel and rootfs' \
	  '  make boot-test-direct Verify direct kernel boot'

check-env:
	@bash scripts/check-env.sh

fetch-poky:
	@bash scripts/fetch-poky.sh
	@bash scripts/fetch-kernel-cache.sh

build:
	@bash scripts/build-qemuarm64.sh

run-direct:
	@bash scripts/run-qemuarm64.sh

boot-test-direct:
	@python3 tests/boot-qemuarm64.py
