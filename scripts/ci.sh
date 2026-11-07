#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

make check-env
make fetch-poky
make build
make firmware
make package-repo
make boot-test
make driver-test
make opkg-test
make release
make release-test
