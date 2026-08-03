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
  sudo bash -c "
    grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
      | grep -E 'archive\.ubuntu\.com|security\.ubuntu\.com' \
      | sed 's/^deb /deb-src /' | sort -u > /etc/apt/sources.list.d/99-kernel-src.list
  "
  sudo apt update

  SRC_LINE="$(apt-cache show linux-image-unsigned-"$KVER" 2>/dev/null | awk -F': ' '/^Source:/{print $2; exit}')"
  SRC_NAME="$(echo "$SRC_LINE" | awk '{print $1}')"
  SRC_VER="$(echo "$SRC_LINE" | grep -oP '\(\K[^)]+')"
  SRC_VER="${SRC_VER:-$(dpkg-query -W -f='${Version}' linux-headers-"$KVER" 2>/dev/null)}"

  echo "Resolved source package: ${SRC_NAME:-unknown} version ${SRC_VER:-unknown}"

  FETCHED=0
  if [[ -n "$SRC_NAME" && -n "$SRC_VER" ]] && apt source "$SRC_NAME"="$SRC_VER" 2>/dev/null; then
    FETCHED=1
  elif [[ -n "$SRC_NAME" ]] && apt source "$SRC_NAME" 2>/dev/null; then
    echo "WARNING: could not pin exact version — fetched latest instead."
    FETCHED=1
  fi

  if [[ "$FETCHED" -eq 1 ]]; then
    mv linux-*/ "linux-source-$KVER"
  else
    echo "Could not fetch kernel source for $KVER."
    echo "Check manually: apt-cache show linux-image-unsigned-$KVER"
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
