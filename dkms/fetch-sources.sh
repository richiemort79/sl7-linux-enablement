#!/usr/bin/env bash
# DKMS PRE_BUILD: lay out the sources of the four patched modules for one
# Ubuntu kernel, exactly as Ubuntu builds them, then apply our patches.
#
# Ubuntu's kernel source package is upstream vX.Y plus one diff.gz (stable
# updates and Ubuntu's own backports; sdw_utils carries an rt1320 mic DAI
# backport that patches 0002/0006 are written against, so plain kernel.org
# sources won't do). We fetch only the files the modules need from
# kernel.org at vX.Y, then apply Ubuntu's diff for those files.
#
# Usage: fetch-sources.sh <kernelver>   (e.g. 7.0.0-30-generic)
# Network is needed the first time per kernel; results are cached.
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KV="${1:-$(uname -r)}"
KDIR="/lib/modules/$KV/build"
SRC="$D/src"
CACHE="${SL7_CACHE:-/var/cache/sl7-enablement}"
KORG="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain"
I=drivers/staging/media/ipu7

# --- which upstream base and which Ubuntu diff ---------------------------
VER=$(awk '/^VERSION =/{print $3}' "$KDIR/Makefile")
PL=$(awk '/^PATCHLEVEL =/{print $3}' "$KDIR/Makefile")
TAG="v$VER.$PL"
read -r SRCPKG SRCVER < <(dpkg-query -W -f='${source:Package} ${source:Version}\n' "linux-modules-$KV")
SRCVER="${SRCVER#*:}"
[[ -n "$SRCPKG" && -n "$SRCVER" ]] || { echo "cannot find the source package of linux-modules-$KV"; exit 1; }
DIFF="${SRCPKG}_${SRCVER}.diff.gz"
echo "== $KV: $TAG + Ubuntu $SRCPKG $SRCVER =="

mkdir -p "$CACHE" 2>/dev/null || CACHE="$D/cache"
mkdir -p "$CACHE"
if [[ ! -s "$CACHE/$DIFF" ]]; then
  # The archive pool keeps current versions only; Launchpad keeps them all.
  for url in "http://archive.ubuntu.com/ubuntu/pool/main/${SRCPKG:0:1}/$SRCPKG/$DIFF" \
             "https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/$SRCPKG/$SRCVER/$DIFF"; do
    echo "-- fetching $url"
    curl -sfL --connect-timeout 30 -m 600 --retry 2 -o "$CACHE/$DIFF.part" "$url" \
      && mv "$CACHE/$DIFF.part" "$CACHE/$DIFF" && break
  done
  [[ -s "$CACHE/$DIFF" ]] || { rm -f "$CACHE/$DIFF.part"; echo "could not download $DIFF"; exit 1; }
fi

# --- helpers --------------------------------------------------------------
korg_cache="$CACHE/korg-$TAG"
try_fetch() {  # <path>: copy one upstream file into $SRC; 1 if it doesn't exist at $TAG
  local f="$1"
  mkdir -p "$SRC/$(dirname "$f")" "$korg_cache/$(dirname "$f")"
  if [[ ! -f "$korg_cache/$f" ]]; then
    curl -sfL --connect-timeout 30 -m 120 --retry 3 -o "$korg_cache/$f.part" "$KORG/$f?h=$TAG" \
      || { rm -f "$korg_cache/$f.part"; return 1; }
    mv "$korg_cache/$f.part" "$korg_cache/$f"
  fi
  cp "$korg_cache/$f" "$SRC/$f"
}
ubuntu_diff_for() {  # <path-prefix>...: Ubuntu's hunks for files under those prefixes
  python3 -I - "$CACHE/$DIFF" "$@" <<'EOF'
import gzip, sys
prefixes = sys.argv[2:]; keep = False; pend = ''
for line in gzip.open(sys.argv[1], 'rt', errors='replace'):
    if line.startswith('--- '):
        keep = False; pend = line; continue
    if line.startswith('+++ '):
        path = line.split()[1].split('/', 1)[1]
        keep = any(path == p or path.startswith(p) for p in prefixes)
        if keep: sys.stdout.write(pend)
    if keep: sys.stdout.write(line)
EOF
}
ubuntu_files() {  # <path-prefix>...: files Ubuntu's diff touches under those prefixes
  ubuntu_diff_for "$@" | awk '/^\+\+\+ /{sub(/^[^\/]*\//, "", $2); print $2}'
}
# --forward never reverses a hunk that looks applied (-t would), and stdin
# is closed so a missing file fails instead of prompting.
apply_ubuntu() {  # <path-prefix>...
  ubuntu_diff_for "$@" > "$SRC/.ubuntu.diff"
  [[ ! -s "$SRC/.ubuntu.diff" ]] \
    || patch -d "$SRC" -p1 -s --forward --no-backup-if-mismatch -i .ubuntu.diff </dev/null
  rm -f "$SRC/.ubuntu.diff"
}
objs_of() {  # <Makefile> <module-var-prefix>: object names on continuation lines
  sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$1" | grep -E "^$2" | grep -oE '[A-Za-z0-9_-]+\.o' | sort -u
}
headers_of() {  # local "..." includes of the given files
  grep -ho '#include "[^"]*"' "$@" 2>/dev/null | sed 's/#include "//;s/"//' | sort -u
}

# --- lay out the sources --------------------------------------------------
# Gather pristine upstream copies of every file needed, then apply Ubuntu's
# diff to them once.
PREFIXES=(drivers/platform/surface/surface_aggregator_registry.c drivers/media/i2c/ov02c10.c
          sound/soc/sdw_utils/ sound/soc/codecs/ $I/)
rm -rf "$SRC"; mkdir -p "$SRC"
for f in "${PREFIXES[@]:0:2}" sound/soc/sdw_utils/Makefile $I/Makefile; do
  try_fetch "$f" || { echo "missing upstream file $f at $TAG"; exit 1; }
done

# Object lists come from Ubuntu's Makefiles (it may add objects).
mkdir -p "$SRC/.mk"
apply_ubuntu sound/soc/sdw_utils/Makefile $I/Makefile
SDW_OBJS=$(objs_of "$SRC/sound/soc/sdw_utils/Makefile" 'snd-soc-sdw-utils')
ISYS_OBJS=$(objs_of "$SRC/$I/Makefile" 'intel-ipu7-isys')
try_fetch sound/soc/sdw_utils/Makefile; try_fetch $I/Makefile   # back to upstream

# A file Ubuntu adds doesn't exist upstream; its diff creates it.
for o in $SDW_OBJS; do try_fetch "sound/soc/sdw_utils/${o%.o}.c" || true; done
for o in $ISYS_OBJS; do try_fetch "$I/${o%.o}.c" || true; done
for f in $(ubuntu_files "${PREFIXES[@]}"); do
  [[ -e "$SRC/$f" ]] || try_fetch "$f" || true
done
fetch_headers() {
  local h f pass
  for pass in 1 2 3; do
    for h in $(headers_of "$SRC"/sound/soc/sdw_utils/*.c); do
      case "$h" in ../*) f="sound/soc/${h#../}" ;; *) f="sound/soc/sdw_utils/$h" ;; esac
      [[ -e "$SRC/$f" ]] || try_fetch "$f" || true
    done
    for h in $(headers_of "$SRC/$I"/*.c "$SRC/$I"/*.h "$SRC/$I"/abi/*.h); do
      [[ -e "$SRC/$I/$h" || -e "$SRC/$I/abi/$h" ]] || try_fetch "$I/$h" || try_fetch "$I/abi/$h" || true
    done
  done
}
fetch_headers
rmdir "$SRC/.mk"
apply_ubuntu "${PREFIXES[@]}" || { echo "Ubuntu's diff did not apply to the $TAG files"; exit 1; }
fetch_headers   # anything newly included by Ubuntu's changes

# --- our patches ----------------------------------------------------------
for p in 0001 0005 0002 0006 0003 0007; do
  pf=$(ls "$D"/patches/"$p"-*.patch)
  if patch -d "$SRC" -p1 -s --forward --dry-run -i "$pf" </dev/null >/dev/null 2>&1; then
    echo "-- applying $(basename "$pf")"
    patch -d "$SRC" -p1 -s --forward --no-backup-if-mismatch -i "$pf" </dev/null
  elif patch -d "$SRC" -p1 -s -R --dry-run -i "$pf" </dev/null >/dev/null 2>&1; then
    # Ubuntu picks up some of these fixes (0006 is in 7.0.0-38)
    echo "-- already in this kernel: $(basename "$pf")"
  else
    patch -d "$SRC" -p1 --forward --dry-run -i "$pf" </dev/null || true
    echo "PATCH FAILED: $(basename "$pf") against $SRCPKG $SRCVER"; exit 1
  fi
done

# --- Kbuild layout: build only the four modules ---------------------------
echo 'obj-m += drivers/platform/surface/ drivers/media/i2c/ sound/soc/sdw_utils/ drivers/staging/media/ipu7/' > "$SRC/Kbuild"
echo 'obj-m += surface_aggregator_registry.o' > "$SRC/drivers/platform/surface/Kbuild"
echo 'obj-m += ov02c10.o' > "$SRC/drivers/media/i2c/Kbuild"
sed 's/^obj-\$(CONFIG_SND_SOC_SDW_UTILS)/obj-m/' "$SRC/sound/soc/sdw_utils/Makefile" > "$SRC/sound/soc/sdw_utils/Kbuild"
# only the isys half of IPU7 is ours; intel-ipu7 itself stays Ubuntu's
sed -e 's/^obj-\$(CONFIG_VIDEO_INTEL_IPU7)[[:space:]]*+= intel-ipu7\.o/obj-n += intel-ipu7.o/' \
    -e 's/^obj-\$(CONFIG_VIDEO_INTEL_IPU7)[[:space:]]*+= intel-ipu7-isys\.o/obj-m += intel-ipu7-isys.o/' \
    "$SRC/$I/Makefile" > "$SRC/$I/Kbuild"
echo "sources ready in $SRC"
