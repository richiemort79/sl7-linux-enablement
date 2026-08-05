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

sudo apt install -y linux-headers-"$KVER" flex bison libssl-dev libelf-dev bc libdw-dev dwarves rsync cpio kmod
sudo apt-mark hold linux-image-"$KVER" linux-headers-"$KVER" || true

mkdir -p "$BUILD"
cd "$BUILD"

if [[ ! -d "linux-source-$KVER" ]]; then
  # Clear any stale extracted source trees from earlier attempts so the
  # directory-match below can't collide with leftovers.
  find . -maxdepth 1 -type d -name 'linux-*' ! -name "linux-source-$KVER" -exec rm -rf {} +

  sudo bash -c "
    grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
      | grep -E 'archive\.ubuntu\.com|security\.ubuntu\.com' \
      | sed 's/^deb /deb-src /' | sort -u > /etc/apt/sources.list.d/99-kernel-src.list
  "
  sudo apt update

  SRC_LINE="$(apt-cache show linux-image-unsigned-"$KVER" 2>/dev/null | awk -F': ' '/^Source:/{print $2; exit}')"
  SRC_NAME="$(echo "$SRC_LINE" | awk '{print $1}')"
  SRC_VER="$(echo "$SRC_LINE" | grep -oP '\(\K[^)]+' || true)"
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
    EXTRACTED_DIRS=(linux-*/)
    if [[ "${#EXTRACTED_DIRS[@]}" -eq 1 && -d "${EXTRACTED_DIRS[0]}" ]]; then
      mv "${EXTRACTED_DIRS[0]}" "linux-source-$KVER"
    else
      echo "ERROR: expected exactly one extracted directory, found"
      echo "${#EXTRACTED_DIRS[@]}: ${EXTRACTED_DIRS[*]}. Clean up $BUILD manually."
      exit 1
    fi
  else
    echo "Could not fetch kernel source for $KVER."
    echo "Check manually: apt-cache show linux-image-unsigned-$KVER"
    exit 1
  fi
fi

cd "linux-source-$KVER"

declare -A PATCH_OK
for p in 0001 0005 0002 0003; do
  patchfile=$(ls "$PATCHDIR/${p}"*.patch)
  echo "-- dry run: $patchfile"
  if patch -p1 --forward --dry-run < "$patchfile"; then
    PATCH_OK[$p]=1
  else
    PATCH_OK[$p]=0
    echo "WARNING: $patchfile did not apply cleanly. Skipping this"
    echo "patch/module; the others will still be attempted."
  fi
done

for p in 0001 0005 0002 0003; do
  if [[ "${PATCH_OK[$p]}" -eq 1 ]]; then
    patchfile=$(ls "$PATCHDIR/${p}"*.patch)
    echo "-- applying: $patchfile"
    patch -p1 --forward < "$patchfile"
  fi
done

make olddefconfig
make modules_prepare

if [[ -f /usr/src/linux-headers-"$KVER"/Module.symvers ]]; then
  cp /usr/src/linux-headers-"$KVER"/Module.symvers Module.symvers
else
  echo "WARNING: Module.symvers not found at /usr/src/linux-headers-$KVER/."
  echo "modpost may fail with undefined-symbol errors without it."
fi

[[ "${PATCH_OK[0001]}" -eq 1 ]] && make M=drivers/platform/surface
[[ "${PATCH_OK[0002]}" -eq 1 ]] && make M=sound/soc/sdw_utils
[[ "${PATCH_OK[0003]}" -eq 1 ]] && make M=drivers/media/i2c

sudo mkdir -p /lib/modules/"$KVER"/updates
[[ "${PATCH_OK[0001]}" -eq 1 ]] && sudo cp drivers/platform/surface/surface_aggregator_registry.ko /lib/modules/"$KVER"/updates/
[[ "${PATCH_OK[0002]}" -eq 1 ]] && sudo cp sound/soc/sdw_utils/snd-soc-sdw-utils.ko /lib/modules/"$KVER"/updates/
[[ "${PATCH_OK[0003]}" -eq 1 ]] && sudo cp drivers/media/i2c/ov02c10.ko /lib/modules/"$KVER"/updates/
sudo depmod -a

echo "Done. Reboot to load the rebuilt modules."
