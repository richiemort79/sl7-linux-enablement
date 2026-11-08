#!/usr/bin/env bash
# DKMS PRE_BUILD for linux-surface kernels (e.g. 7.2.15-1-surface).
#
# linux-surface's only change to the files our modules are built from is a
# MSHW0551 -> Snapdragon node group line in surface_aggregator_registry.c,
# so plain kernel.org sources plus floopflop's edits give the module we
# want. fetch-sources.sh and port-patches.py are floopflop's, unchanged
# (https://github.com/floopflop/SL_Intel_Linux, kernel/). On top of that:
#  - v4l2loopback, which linux-surface doesn't ship (the Chrome virtual
#    webcam needs it)
#  - a check that exactly one MSHW0551 entry exists: with two, the first
#    wins and the Intel group would silently be ignored
#
# Usage: sl7-prebuild.sh <kernelver>
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KV="${1:?kernel version}"
V4L2LB=0.15.3
CACHE="${SL7_CACHE:-/var/cache/sl7-enablement}"

SOURCE_CACHE="${SOURCE_CACHE:-/var/cache/surface-laptop-7-intel}" "$D/fetch-sources.sh" "$KV"

REG="$D/src/drivers/platform/surface/surface_aggregator_registry.c"
n=$(grep -c '"MSHW0551"' "$REG" || true)
[[ "$n" -eq 1 ]] || { echo "expected one MSHW0551 entry in the registry, found $n"; exit 1; }
grep -q '"MSHW0551", (unsigned long)ssam_node_group_sl7_intel' "$REG" \
  || { echo "MSHW0551 does not map to the Intel node group"; exit 1; }

echo "== v4l2loopback $V4L2LB =="
mkdir -p "$CACHE" 2>/dev/null || CACHE="$D/cache"
mkdir -p "$CACHE"
TB="$CACHE/v4l2loopback-$V4L2LB.tar.gz"
if [[ ! -s "$TB" ]]; then
  curl -sfL --connect-timeout 30 -m 300 --retry 3 -o "$TB.part" \
    "https://github.com/v4l2loopback/v4l2loopback/archive/refs/tags/v$V4L2LB.tar.gz"
  mv "$TB.part" "$TB"
fi
mkdir -p "$D/src/v4l2loopback"
tar -xzf "$TB" -C "$D/src/v4l2loopback" --strip-components=1
echo 'obj-m += v4l2loopback.o' > "$D/src/v4l2loopback/Kbuild"
echo 'obj-m += v4l2loopback/' >> "$D/src/Kbuild"
echo "sources ready (5 modules)"
