#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MKLOCK_TOOL="${MKLOCK_TOOL:-$HOME/Library/Application Support/MK Locks/mklock}"
if [[ -x "$MKLOCK_TOOL" && "${MONITORSWITCH_BUILD_LOCKED:-0}" != "1" ]]; then
  exec "$MKLOCK_TOOL" build "MonitorSwitch: build usage sampler" env MONITORSWITCH_BUILD_LOCKED=1 taskpolicy -b nice -n 19 /bin/bash "$PWD/scripts/build_usage_sampler.sh"
fi
mkdir -p build
xcrun clang -O2 -Wall -Wextra -Werror scripts/measure_usage.c -lproc -o build/measure-usage
