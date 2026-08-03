#!/usr/bin/env bash
# Re-run after a kernel update to rebuild + reinstall just the 3 out-of-tree
# modules against the new kernel. Does NOT touch iptsd or configs, those
# don't need rebuilding per kernel.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHDIR="$REPO_ROOT/patches"
BUILD="$REPO_ROOT/.build"
KVER="$(uname -r)"

echo "Rebuilding modules for kernel $KVER"

sudo apt install -y linux-headers-"$KVER"
sudo apt-mark hold linux-image-"$KVER" linux-headers-"$KVER" || true

mkdir -p "$BUILD"
cd "$BUILD"

if [[ ! -d "linux-source-$KVER" ]]; then
  KVER_FULL="$(dpkg-query -W -f='${Version}' linux-headers-"$KVER" 2>/dev/null || true)"

  sudo bash -c "
    grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
      | grep -E 'archive\.ubuntu\.com|security\.ubuntu\.com' \
      | sed 's/^deb /deb-src /' | sort -u > /etc/apt/sources.list.d/99-kernel-src.list
  "
  sudo apt update

  FETCHED=0
  if [[ -n "$KVER_FULL" ]] && apt source linux-image-unsigned-"$KVER"="$KVER_FULL" 2>/dev/null; then
    FETCHED=1
  elif apt source linux-image-unsigned-"$KVER" 2>/dev/null; then
    FETCHED=1
  fi

  if [[ "$FETCHED" -eq 1 ]]; then
    mv linux-*/ "linux-source-$KVER"
  else
    echo "Could not fetch matching kernel source for $KVER ($KVER_FULL)."
    echo "Find the right source package name with:"
    echo "  apt-cache showsrc linux-image-unsigned-$KVER | head -5"
    echo "then: apt source <name>=$KVER_FULL"
    exit 1
  fi
fi

cd "linux-source-$KVER"

for p in 0001 0002 0003; do
  patchfile=$(ls "$PATCHDIR/${p}"*.patch)
  patch -p1 --forward -r /dev/null < "$patchfile" || true
done

make olddefconfig
make modules_prepare
make M=drivers/platform/surface
make M=sound/soc/sdw_utils
make M=drivers/media/i2c

sudo mkdir -p /lib/modules/"$KVER"/updates
sudo cp drivers/platform/surface/surface_aggregator_registry.ko /lib/modules/"$KVER"/updates/
sudo cp sound/soc/sdw_utils/snd-soc-sdw-utils.ko /lib/modules/"$KVER"/updates/
sudo cp drivers/media/i2c/ov02c10.ko /lib/modules/"$KVER"/updates/
sudo depmod -a

echo "Done. Reboot to load the rebuilt modules."
