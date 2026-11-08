#!/usr/bin/env bash
# Register the patched modules with DKMS, so every new kernel gets them
# rebuilt automatically when it is installed, instead of silently falling
# back to the stock modules. Replaces running 01-rebuild-modules.sh by hand.
#
# Two DKMS packages, each limited to its kind of kernel:
#   sl7-enablement (dkms/)        Ubuntu -generic kernels: kernel.org vX.Y
#                                 + Ubuntu's diff.gz + patches/000[1-7]
#   sl7-surface    (dkms-surface/) linux-surface kernels: kernel.org vX.Y.Z
#                                 + floopflop's fixes + v4l2loopback,
#                                 built with the kernel's gcc (gcc-11)
#
# DKMS needs network at kernel install time. If that fails,
# sl7-dkms-retry.service retries at the next boot.
#
# Does not touch the APT kernel pin; see README "After a kernel update".
#
# Run from the repo root: ./scripts/04-setup-dkms.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER=1.0
MODS=(surface_aggregator_registry ov02c10 snd-soc-sdw-utils intel-ipu7-isys v4l2loopback)

DEPS=(dkms curl python3 patch)
ls -d /lib/modules/*-surface >/dev/null 2>&1 && DEPS+=(gcc-11)
echo "== Installing ${DEPS[*]} =="
sudo apt-get install -y "${DEPS[@]}"

register() {  # <name> <repo dir> <files...>
  local name="$1" dir="$2"; shift 2
  local dest="/usr/src/$name-$VER"
  echo "== Registering $name/$VER =="
  # (not "| grep -q": with pipefail, grep quitting early fails the pipe)
  if [[ -n "$(dkms status -m "$name" -v "$VER" 2>/dev/null)" ]]; then
    sudo dkms remove -m "$name" -v "$VER" --all || true
  fi
  sudo rm -rf "$dest"
  sudo install -d "$dest"
  local f
  for f in "$@"; do
    case "$f" in *.sh|*.py) sudo install -m 755 "$REPO_ROOT/$dir/$f" "$dest/" ;;
                 *)         sudo install -m 644 "$REPO_ROOT/$dir/$f" "$dest/" ;; esac
  done
  sudo dkms add -m "$name" -v "$VER"
}

# None of these modules declare a version, so DKMS sees ours as "not newer"
# than the kernel's own and silently keeps the stock module ("Diff between
# built and installed module" in dkms status). Ubuntu's dkms reads this
# directory, also when autoinstalling for a new kernel, to skip that check.
sudo install -d /usr/share/dkms/modules_to_force_install
echo "sl7-enablement_version-override sl7-surface_version-override" \
  | sudo tee /usr/share/dkms/modules_to_force_install/sl7-enablement >/dev/null

register sl7-enablement dkms dkms.conf fetch-sources.sh
sudo install -d "/usr/src/sl7-enablement-$VER/patches"
for p in 0001 0002 0003 0005 0006 0007; do
  sudo install -m 644 "$REPO_ROOT"/patches/"$p"-*.patch "/usr/src/sl7-enablement-$VER/patches/"
done
register sl7-surface dkms-surface dkms.conf fetch-sources.sh port-patches.py sl7-prebuild.sh sl7-make.sh

sudo install -m 644 "$REPO_ROOT/configs/etc/systemd/system/sl7-dkms-retry.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable sl7-dkms-retry.service

# Build now for every installed kernel that has headers.
for kdir in /lib/modules/*/; do
  kv="$(basename "$kdir")"
  [[ -d "$kdir/build" ]] || continue
  case "$kv" in
    *-generic) name=sl7-enablement ;;
    *-surface) name=sl7-surface ;;
    *) echo "== skipping $kv (not a -generic or -surface kernel)"; continue ;;
  esac
  echo "== DKMS build of $name for $kv =="
  if sudo dkms install --force -m "$name" -v "$VER" -k "$kv"; then
    # Only drop hand-built copies (which would compete with DKMS's own in
    # updates/dkms/) once every module DKMS built resolves to its copy.
    ok=1
    for m in $(cd "/var/lib/dkms/$name/$VER/$kv/x86_64/module" && ls | sed 's/\.ko.*//'); do
      case "$(modinfo -k "$kv" -n "$m" 2>/dev/null)" in
        */updates/dkms/*) ;;
        *) echo "ERROR: $m for $kv resolves to $(modinfo -k "$kv" -n "$m" 2>/dev/null), not DKMS's copy"; ok=0 ;;
      esac
    done
    if [[ $ok -eq 1 ]]; then
      for m in "${MODS[@]}"; do sudo rm -f "/lib/modules/$kv/updates/$m.ko"; done
      sudo depmod -a "$kv"
      for m in "${MODS[@]}"; do
        p="$(modinfo -k "$kv" -n "$m" 2>/dev/null || true)"
        [[ -z "$p" || "$p" == */updates/* ]] || echo "NOTE: $m for $kv -> $p"
      done
      # The registry module is in the initramfs; refresh it with DKMS's copy.
      sudo update-initramfs -u -k "$kv"
    else
      echo "WARNING: leaving hand-built modules for $kv in place."
    fi
  else
    echo "WARNING: DKMS build failed for $kv (log under /var/lib/dkms/$name/$VER/build/)."
    echo "Any hand-built modules for $kv are left in place."
  fi
done

echo
dkms status
echo "Done. New kernels will get the patched modules automatically."
