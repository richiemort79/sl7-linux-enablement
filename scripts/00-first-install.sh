#!/usr/bin/env bash
# First-time setup: deps, kernel pin, patch + build the 3 modules,
# build iptsd fork, install configs, set GRUB flag.
#
# Run from the repo root: ./scripts/00-first-install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHDIR="$REPO_ROOT/patches"
CONFDIR="$REPO_ROOT/configs"
BUILD="$REPO_ROOT/.build"
KVER="$(uname -r)"

REQUIRED_PATCHES=(
  "0001-platform-surface-aggregator_registry-SL7-Intel-MSHW0551-and-ALS.patch"
  "0002-ASoC-sdw_utils-SL7-speakers-and-internal-mic.patch"
  "0003-media-ov02c10-tolerate-12MHz-external-clock.patch"
  "0004-iptsd-add-Touchpad-LiftGraceMs-option.patch"
)

## --- Live vs installed detection ---------------------------------------
# Live sessions (casper/live-boot) run from an overlay/tmpfs root and reset
# on reboot, so persistence-oriented steps (kernel pin, GRUB edit, Timeshift)
# are either meaningless or actively wrong to run there.
IS_LIVE=0
if grep -qE '\b(boot=casper|boot=live)\b' /proc/cmdline 2>/dev/null; then
  IS_LIVE=1
elif [[ -d /rofs ]] || [[ -d /run/live ]] || mount | grep -q ' / .*overlay.*upperdir=/cow'; then
  IS_LIVE=1
fi

if [[ "$IS_LIVE" -eq 1 ]]; then
  echo "== Detected a LIVE session (non-persistent) =="
  echo "Skipping: kernel pin, Timeshift snapshot, GRUB edit."
  echo "Remember: acpi_mask_gpe=0xAB will need to be added manually at the"
  echo "GRUB menu (press 'e' on the boot entry) since there is no persistent"
  echo "/etc/default/grub to edit here."
else
  echo "== Detected a normal (installed, persistent) system =="

  if ! command -v timeshift >/dev/null 2>&1; then
    echo "-- Installing Timeshift for a pre-change snapshot --"
    sudo apt update
    sudo apt install -y timeshift
  fi

  echo "-- Creating a Timeshift snapshot before making any changes --"
  if sudo timeshift --create --comments "pre sl7-linux-enablement install" --tags D; then
    echo "Snapshot created. If anything goes wrong, boot a recovery/GRUB"
    echo "rescue kernel and run: sudo timeshift --restore"
  else
    echo "WARNING: Timeshift snapshot failed or is not configured (no"
    echo "snapshot device set up yet). Strongly consider running"
    echo "'sudo timeshift-gtk' or 'sudo timeshift --setup' once, then"
    echo "re-running this script, before proceeding on a real install."
    read -rp "Continue anyway without a snapshot? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
  fi
fi
## ------------------------------------------------------------------------

echo "== Checking patch files =="
missing=0
for p in "${REQUIRED_PATCHES[@]}"; do
  if [[ ! -f "$PATCHDIR/$p" ]]; then
    echo "MISSING: patches/$p"
    missing=1
  fi
done
if [[ "$missing" -eq 1 ]]; then
  echo
  echo "Patch files are not included in this repo (see README). Get them"
  echo "from the source discussion and place them in patches/ with the"
  echo "exact filenames above, then re-run this script."
  exit 1
fi

echo "== Installing build dependencies =="
sudo apt update
sudo apt install -y \
  linux-headers-"$KVER" build-essential git meson ninja-build \
  libevdev-dev libudev-dev pkg-config libspdlog-dev nlohmann-json3-dev \
  libgles2-mesa-dev libegl1-mesa-dev libgl1-mesa-dev \
  flex bison libssl-dev libelf-dev bc

if [[ "$IS_LIVE" -eq 0 ]]; then
  echo "== Pinning current kernel so it won't move under us =="
  sudo apt-mark hold linux-image-"$KVER" linux-headers-"$KVER" || true
else
  echo "== Skipping kernel pin (live session) =="
fi

mkdir -p "$BUILD"

echo "== Fetching kernel source matching $KVER =="
cd "$BUILD"
if [[ ! -d linux-source ]]; then
  echo "-- Ensuring deb-src is enabled for archive/security.ubuntu.com --"
  sudo bash -c "
    grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null \
      | grep -E 'archive\.ubuntu\.com|security\.ubuntu\.com' \
      | sed 's/^deb /deb-src /' | sort -u > /etc/apt/sources.list.d/99-kernel-src.list
  "
  sudo apt update

  # Read the actual Source: field (name + exact version) rather than
  # guessing at "apt source pkg=version" syntax, which does not reliably
  # resolve the source version when the binary->source name differs
  # (e.g. linux-image-unsigned-X-generic -> linux-hwe-6.17). Format is
  # either "Source: name" or "Source: name (version)".
  SRC_LINE="$(apt-cache show linux-image-unsigned-"$KVER" 2>/dev/null | awk -F': ' '/^Source:/{print $2; exit}')"
  SRC_NAME="$(echo "$SRC_LINE" | awk '{print $1}')"
  SRC_VER="$(echo "$SRC_LINE" | grep -oP '\(\K[^)]+' || true)"
  # If no explicit version in parens, source version == binary version
  SRC_VER="${SRC_VER:-$(dpkg-query -W -f='${Version}' linux-headers-"$KVER" 2>/dev/null)}"

  echo "Resolved source package: ${SRC_NAME:-unknown} version ${SRC_VER:-unknown}"

  FETCHED=0
  if [[ -n "$SRC_NAME" && -n "$SRC_VER" ]] && apt source "$SRC_NAME"="$SRC_VER" 2>/dev/null; then
    FETCHED=1
  elif [[ -n "$SRC_NAME" ]] && apt source "$SRC_NAME" 2>/dev/null; then
    echo "WARNING: could not pin exact version $SRC_VER — fetched latest"
    echo "available source for $SRC_NAME instead. Patches may not apply"
    echo "cleanly if this drifted far from your running kernel."
    FETCHED=1
  fi

  if [[ "$FETCHED" -eq 1 ]]; then
    mv linux-*/ linux-source
  else
    echo "Could not fetch kernel source at all for $KVER."
    echo "Check manually: apt-cache show linux-image-unsigned-$KVER"
    echo "Skipping automatic kernel module build."
    KSRC=""
  fi
fi
KSRC="${KSRC:-$BUILD/linux-source}"

if [[ -n "$KSRC" && -d "$KSRC" ]]; then
  cd "$KSRC"

  echo "== Applying kernel patches (dry run first) =="
  declare -A PATCH_OK
  for p in 0001 0002 0003; do
    patchfile=$(ls "$PATCHDIR/${p}"*.patch)
    echo "-- dry run: $patchfile"
    if patch -p1 --forward --dry-run < "$patchfile"; then
      PATCH_OK[$p]=1
    else
      PATCH_OK[$p]=0
      echo "WARNING: $patchfile did not apply cleanly against this kernel"
      echo "source (see hunk failures above — likely a version mismatch"
      echo "between the fetched source and your running kernel). Skipping"
      echo "just this patch/module; the others will still be attempted."
    fi
  done

  for p in 0001 0002 0003; do
    if [[ "${PATCH_OK[$p]}" -eq 1 ]]; then
      patchfile=$(ls "$PATCHDIR/${p}"*.patch)
      echo "-- applying: $patchfile"
      patch -p1 --forward < "$patchfile"
    fi
  done

  echo "== Building whichever out-of-tree modules patched cleanly =="
  make olddefconfig
  make modules_prepare
  [[ "${PATCH_OK[0001]}" -eq 1 ]] && make M=drivers/platform/surface
  [[ "${PATCH_OK[0002]}" -eq 1 ]] && make M=sound/soc/sdw_utils
  [[ "${PATCH_OK[0003]}" -eq 1 ]] && make M=drivers/media/i2c

  echo "== Installing modules that built =="
  sudo mkdir -p /lib/modules/"$KVER"/updates
  [[ "${PATCH_OK[0001]}" -eq 1 ]] && sudo cp drivers/platform/surface/surface_aggregator_registry.ko /lib/modules/"$KVER"/updates/
  [[ "${PATCH_OK[0002]}" -eq 1 ]] && sudo cp sound/soc/sdw_utils/snd-soc-sdw-utils.ko /lib/modules/"$KVER"/updates/
  [[ "${PATCH_OK[0003]}" -eq 1 ]] && sudo cp drivers/media/i2c/ov02c10.ko /lib/modules/"$KVER"/updates/
  sudo depmod -a

  if [[ "${PATCH_OK[0001]}" -eq 0 || "${PATCH_OK[0002]}" -eq 0 || "${PATCH_OK[0003]}" -eq 0 ]]; then
    echo "NOTE: one or more patches were skipped above due to hunk"
    echo "failures. Those modules were not built. See scripts/01-rebuild-"
    echo "modules.sh or fetch an exact-matching kernel source to retry."
  fi
else
  echo "Skipped kernel module build (no matching source tree found)."
  echo "Re-run scripts/01-rebuild-modules.sh once KSRC is set correctly."
fi

echo "== Building iptsd fork (alex-lentz) with LiftGraceMs patch =="
cd "$REPO_ROOT/iptsd-fork"
if [[ ! -d iptsd ]]; then
  git clone https://github.com/alex-lentz/iptsd.git
fi
cd iptsd
git checkout .
patch -p1 < "$PATCHDIR/0004-iptsd-add-Touchpad-LiftGraceMs-option.patch"
meson setup build --wipe 2>/dev/null || meson setup build
ninja -C build

# Install as iptsd-fork under /usr/local/bin rather than overwriting the
# distro's stock iptsd package at /usr/bin/iptsd. This matches the actual
# etc/systemd/system/iptsd@.service.d/fork.conf shipped in configs/, which
# points ExecStart at /usr/local/bin/iptsd-fork.
BUILT_BIN="$(find build -maxdepth 1 -type f -name iptsd -executable | head -1)"
if [[ -z "$BUILT_BIN" ]]; then
  echo "Could not find built iptsd binary in build/ — check the meson build"
  echo "output above and adjust this step manually."
  exit 1
fi
sudo install -m 755 "$BUILT_BIN" /usr/local/bin/iptsd-fork

echo "== Installing config files =="
sudo cp -r "$CONFDIR"/etc/. /etc/
if [[ -f "$CONFDIR/usr/lib/systemd/system-sleep/btintel-pcie.sh" ]]; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo cp "$CONFDIR/usr/lib/systemd/system-sleep/btintel-pcie.sh" /usr/lib/systemd/system-sleep/
  sudo chmod +x /usr/lib/systemd/system-sleep/btintel-pcie.sh
fi
sudo systemctl daemon-reload

if [[ "$IS_LIVE" -eq 0 ]]; then
  echo "== Setting kernel command line (acpi_mask_gpe=0xAB) =="
  if ! grep -q 'acpi_mask_gpe=0xAB' /etc/default/grub; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="acpi_mask_gpe=0xAB /' /etc/default/grub
    sudo update-grub
  else
    echo "Already present, skipping."
  fi
else
  echo "== Skipping GRUB edit (live session) =="
  echo "Add acpi_mask_gpe=0xAB manually at the GRUB menu this boot only:"
  echo "  press 'e' on the boot entry, append it to the line starting"
  echo "  'linux', then Ctrl+X to boot with it."
fi

if [[ "$IS_LIVE" -eq 1 ]]; then
cat <<'EOF'

== Done (live session) ==

This session is non-persistent — nothing here survived a reboot except
whatever you're testing right now. Suggested checks before trusting a real
install:
  1. Run scripts/02-status-check.sh now and review every line.
  2. Test audio playback and mic capture.
  3. Test a full shutdown (not just logout) — this is the check that
     matters most, see README "Known risk" section.
  4. Test one suspend/resume cycle if you have time.
  5. None of this proves GRUB persistence or service-enable-on-boot —
     for that you need either a real install or an external-drive install.

EOF
else
cat <<'EOF'

== Done ==

A Timeshift snapshot was taken before any changes (unless you chose to
skip it). To roll back: boot a recovery/GRUB rescue kernel and run
'sudo timeshift --restore'.

Next steps (manual, deliberately not automated):
  1. Disable Secure Boot in firmware settings if you haven't already.
  2. Reboot.
  3. Verify keyboard / battery / touchpad first.
  4. THEN check audio (dmesg | grep -i sdw / sof) before assuming it's fine.
  5. Test a full shutdown BEFORE enabling iptsd-resume.service — see
     README "Known risk" section re: Ubuntu-based shutdown/panic reports.
  6. If shutdown is clean:
       sudo systemctl enable iptsd-resume.service

EOF
fi
