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
#  - drm_display_helper with patches/0008: the panel drops out of DPCD
#    backlight mode after powering up, so brightness changes are ignored;
#    the patch restores the mode whenever a level is written
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
echo "== drm_display_helper (patch 0008, brightness) =="
VER=${KV%%-*}; case $VER in *.*.0) VER=${VER%.0} ;; esac
TAG="v$VER"
P=drivers/gpu/drm/display
KORG=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain
DC="$CACHE/display-$TAG"
get() {  # <file in $P>
  if [[ ! -s "$DC/$1" ]]; then
    mkdir -p "$DC"
    curl -sfL --connect-timeout 30 -m 120 --retry 3 -o "$DC/$1.part" "$KORG/$P/$1?h=$TAG" \
      || { rm -f "$DC/$1.part"; return 1; }
    mv "$DC/$1.part" "$DC/$1"
  fi
  cp "$DC/$1" "$D/src/$P/$1"
}
mkdir -p "$D/src/$P"
get Makefile || { echo "cannot fetch $P/Makefile at $TAG"; exit 1; }
objs=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$D/src/$P/Makefile" \
       | grep -E '^drm_display_helper' | grep -oE '[a-z0-9_]+\.o' | sort -u)
for o in $objs; do
  get "${o%.o}.c" || { echo "cannot fetch $P/${o%.o}.c"; exit 1; }
done
for h in $(grep -ho '#include "[^"]*"' "$D/src/$P"/*.c | sed 's/#include "//;s/"//' | sort -u); do
  [[ -e "$D/src/$P/$h" ]] || get "$h" || { echo "cannot fetch $P/$h"; exit 1; }
done
patch -d "$D/src" -p1 -s --forward --no-backup-if-mismatch \
  -i "$D/patches/0008-drm-display-edp-backlight-restore-dpcd-mode.patch" </dev/null \
  || { echo "patch 0008 did not apply to $TAG"; exit 1; }
# only drm_display_helper.ko, not drm_dp_aux_bus.ko
grep -v 'DRM_DISPLAY_DP_AUX_BUS' "$D/src/$P/Makefile" > "$D/src/$P/Kbuild"
rm "$D/src/$P/Makefile"
echo 'obj-m += drivers/gpu/drm/display/' >> "$D/src/Kbuild"
echo "sources ready (6 modules)"
