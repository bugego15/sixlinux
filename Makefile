SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check-env

help:
	@printf '%s\n' \
	  'SixLinux development targets:' \
	  '  make check-env  Check host tools and project environment'

check-env:
	@bash scripts/check-env.sh
