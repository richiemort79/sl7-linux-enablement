#!/usr/bin/env bash
# DKMS MAKE for linux-surface kernels: build with the compiler major
# version the kernel itself was built with. linux-surface builds on Ubuntu
# 22.04 (gcc 11); the system gcc on 24.04 is 13, and features such as
# CONFIG_ZERO_CALL_USED_REGS and the return-thunk mitigations depend on it.
#
# Usage: sl7-make.sh <kernel_source_dir>
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDIR="${1:?kernel source dir}"

ver=$(sed -n 's/^CONFIG_GCC_VERSION=\([0-9]*\)$/\1/p' "$KDIR/.config")
CC=gcc
if [[ -n "$ver" ]] && command -v "gcc-$((ver / 10000))" >/dev/null; then
  CC="gcc-$((ver / 10000))"
elif [[ -n "$ver" ]]; then
  echo "WARNING: kernel built with gcc $((ver / 10000)), not installed; using $(gcc -dumpversion)"
  echo "         (sudo apt install gcc-$((ver / 10000)))"
fi
echo "== building with $CC =="
make -C "$KDIR" M="$D/src" CC="$CC" modules -j"$(nproc)"
