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
  if apt source linux-image-unsigned-"$KVER" 2>/dev/null; then
    mv linux-*/ "linux-source-$KVER"
  else
    echo "Could not fetch matching kernel source for $KVER."
    echo "Point this script at the right tree manually and re-run, or"
    echo "adapt KSRC below."
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
