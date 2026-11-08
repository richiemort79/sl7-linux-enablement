# Surface Laptop 7 (Intel, Lunar Lake) enablement — Zorin OS

Personal build/maintenance repo for keeping a Surface Laptop 7 for Business
(Intel Core Ultra 7 268V, Lunar Lake) fully working on Zorin OS (Ubuntu-based)
with either the stock Ubuntu kernel or the linux-surface kernel (see
"Kernels" below; this machine now runs linux-surface 7.2 to get rid of
suspend hangs).

Based on the bring-up work and root-cause analysis from nierdal on
linux-surface/linux-surface#1710, adapted for Ubuntu/Zorin. The PipeWire
speaker fix (ghost-amp timeout and `rt1320-1` renumbering in patch 0002) is
ported from floopflop's Fedora repo,
https://github.com/floopflop/SL_Intel_Linux, as is the webcam's libcamera
patch and tuning in `patches/libcamera/`, the 12 MHz PLL rescaling in
patch 0003 (webcam 9.4 -> ~30 fps) and the IPU7 capture cache sync in
patch 0007 (stale streaks behind moving objects).

## Kernels

Two kernels are supported, each with its own DKMS package
(`./scripts/04-setup-dkms.sh` registers both):

| Kernel | DKMS package | Sources |
|---|---|---|
| Ubuntu `-generic` (7.0) | `sl7-enablement` (`dkms/`) | kernel.org vX.Y + Ubuntu's `diff.gz` + `patches/000[1-7]` |
| linux-surface `-surface` (7.2+) | `sl7-surface` (`dkms-surface/`) | kernel.org vX.Y.Z + floopflop's `port-patches.py` + v4l2loopback + patch 0008 (`drm_display_helper`, brightness) |

**Why linux-surface 7.2:** on Ubuntu 7.0.0-30 the lid sometimes never
woke from suspend (7 hangs in ~250 suspends; one left a BERT firmware
record), matching linux-surface#1710 where 7.2 removed the hangs. The
`sl7-suspend-log` sleep hook counts hangs per kernel
(`./scripts/02-status-check.sh`).

Setting it up (Ubuntu kernels stay blocked by the APT pin below):

```
wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/linux-surface.gpg
echo "deb [arch=amd64] https://pkg.surfacelinux.com/debian release main" | sudo tee /etc/apt/sources.list.d/linux-surface.list
printf 'Package: linux-image-surface linux-headers-surface linux-image-*-surface linux-headers-*-surface\nPin: origin pkg.surfacelinux.com\nPin-Priority: 500\n' | sudo tee /etc/apt/preferences.d/linux-surface
sudo apt update
sudo apt install --no-install-recommends linux-image-surface linux-headers-surface
./scripts/04-setup-dkms.sh      # before rebooting into it
```

Gotchas, all handled by `dkms-surface/` and `04-setup-dkms.sh`:
- `--no-install-recommends` keeps linux-surface's own `iptsd` out (we run
  the patched alex-lentz fork).
- linux-surface maps `MSHW0551` to the **Snapdragon** SAM node group.
  floopflop's fix adds an Intel entry, but the first match wins, so on a
  surface-patched registry it would silently do nothing. We build the
  registry from kernel.org sources instead (linux-surface's only change to
  that file is that line), and `sl7-prebuild.sh` checks there's exactly one
  `MSHW0551` entry, mapped to the Intel group.
- linux-surface kernels are built with gcc 11 (Ubuntu 22.04); `sl7-make.sh`
  builds with the matching `gcc-11`.
- linux-surface doesn't ship `v4l2loopback` (needed for the Chrome virtual
  webcam), so `sl7-surface` builds upstream v0.15.3 as a fifth module.
- None of these modules declare a version, so DKMS treats ours as "not
  newer" than the kernel's and silently keeps the stock module (`dkms
  status` shows "Diff between built and installed module").
  `04-setup-dkms.sh` adds both packages to
  `/usr/share/dkms/modules_to_force_install/` to skip that check, also for
  future kernels.
- The registry module lives in the initramfs, so it's regenerated after
  each DKMS install.

After a kernel update, before rebooting: `dkms status` should list the new
kernel as `installed` with no warnings.

## After a kernel update

The 4 out-of-tree modules (keyboard/battery, audio, webcam sensor, IPU7
capture) are built for one specific kernel version. Without DKMS, after
any kernel update they silently fall back to the stock (unpatched)
versions — keyboard/battery/audio/webcam stop working with no error.

**Recommended: DKMS** (`./scripts/04-setup-dkms.sh`). Every new kernel
gets the modules rebuilt automatically when it's installed. The build
recreates Ubuntu's exact source for that kernel (kernel.org vX.Y plus
Ubuntu's own `diff.gz` from the archive, which carries backports our audio
patches depend on) and applies our patches; a patch Ubuntu has already
picked up is skipped. Needs network at kernel install time; if it fails,
`sl7-dkms-retry.service` retries at the next boot (then reboot once more).
Check with `dkms status`. With DKMS in place, the kernel pin below isn't
needed and you keep getting kernel security updates.

Without DKMS, rebuild by hand after each kernel update:

```
cd scripts && ./01-rebuild-modules.sh
sudo modprobe -r surface_aggregator_registry && sudo modprobe surface_aggregator_registry
sudo modprobe -r snd_soc_sdw_utils ov02c10 intel_ipu7_isys && sudo modprobe snd_soc_sdw_utils ov02c10 intel_ipu7_isys
```

Or, without DKMS, stop kernels changing at all by pinning the kernel.
**`apt-mark hold` is not enough** — confirmed on real hardware that it only blocks the
*installed* kernel packages from being upgraded/removed, but does
nothing to stop a brand new kernel package (different version, different
package name) from being installed fresh alongside it, which
unattended-upgrades will still do. This actually happened here (held
`-29`, `unattended-upgrades` installed `-30` anyway, keyboard broke).

The real fix is an APT preferences pin, which blocks every kernel
package version — old, current, or future — from ever being considered
installable at all:

```
sudo tee /etc/apt/preferences.d/no-kernel-updates > /dev/null << 'EOF'
Package: linux-image-* linux-headers-* linux-generic linux-headers-generic linux-image-generic
Pin: release *
Pin-Priority: -1
EOF
```

Verify it worked: `apt-cache policy linux-image-$(uname -r)` should show
`Candidate: (none)`. (Trades all kernel security updates for stability on
this hardware-support layer — a deliberate tradeoff, not a bug.)

To later allow a kernel update on purpose: remove
`/etc/apt/preferences.d/no-kernel-updates`, update, reboot, then
`./01-rebuild-modules.sh` and re-add the pin file for the new kernel.

## Status

**Working:**
- Keyboard, battery, fan, platform profile
- Ambient light sensor
- Speakers, including PipeWire-routed audio (browsers, GNOME, most apps) —
  PipeWire now exposes separate Speaker / Headphones sinks
- Touchpad: cursor, drag, scroll, right-click (two-finger tap, or corner-
  press if enabled in Zorin's touchpad settings)
- Power button wake from s2idle (tested: suspend, then power button wakes it)
- Clean shutdown with audio patches active (tested: no hang/panic)
- Webcam in Cheese and other GStreamer apps (`scripts/03-install-libcamera.sh`):
  floopflop's patched libcamera 0.7.2 in `/usr/local`, using its software
  ISP. The distro's libcamera 0.2.0 had no IPA for IPU7 ("No IPA found")
- Webcam in Chrome (Flatpak) and other V4L2 apps, via a virtual webcam:
  `sl7-webcam on` (or the "Surface Camera" launcher) feeds libcamera into
  v4l2loopback `/dev/video50`; pick "Surface Camera" in Chrome's camera
  settings, ignore the raw "Intel IPU7" entries. The camera and its light
  stay on until `sl7-webcam off`
- Screen brightness (keys, slider, auto-brightness) on linux-surface
  kernels, with patch 0008 — see "Screen brightness" below
- Touchpad after suspend/resume (iptsd-resume.service — without it,
  degrades to mouse-only after first sleep, no gestures/drag/right-click)

**Not working:**
- Webcam on demand in PipeWire-camera apps — Zorin's PipeWire 1.0.5 has
  no libcamera plugin, hence the switch-it-on-yourself virtual webcam
- Screen brightness on the Ubuntu `-generic` kernel (patch 0008 is only
  built for linux-surface kernels so far)

## Screen brightness

The panel (Sharp LQ150P1JX61) supports brightness over DPCD (AUX) and via
a PWM pin. The `xe` driver uses DPCD: `drm_edp_backlight_enable()` writes
the panel's backlight mode register (`0x721`) to DPCD mode and then sends
levels to `0x722/0x723`. But the panel resets `0x721` to PWM mode (`0x08`)
when it powers up, apparently after the driver's write, and from then on
ignores the DPCD levels. Nothing in the driver sets the mode again, so the
slider had no effect. Measured with `/dev/drm_dp_aux0` (the eDP AUX
channel, "AUX A/DDI A"):

```
sudo dd if=/dev/drm_dp_aux0 bs=1 skip=$((0x721)) count=3 2>/dev/null | od -An -tx1
# 08 xx xx = PWM mode (broken), 0a xx xx = DPCD mode
```

Patch 0008 makes `drm_edp_backlight_set_level()` (in `drm_display_helper`)
put the panel back into DPCD mode whenever it has fallen out of it, so the
first brightness change after any power-up fixes it. `sl7-surface` builds
the patched `drm_display_helper.ko` and fails the build if any exported
symbol CRC differs from the kernel's (the graphics driver would otherwise
refuse to load). Tested: works after boot, after a DPMS off/on cycle and
after suspend. The kernel command line has `xe.enable_dpcd_backlight=2`
(force VESA), which is what was tested.

## Patch notes

Patches beyond the original bring-up report: 0005 adds battery reporting
(missing SAM node references for SL7). 0002 was split from a combined
patch since one of its two target files was already superseded upstream
on newer kernels. The `91-sl7-speaker-unmute.rules` udev rule fixes a
"ghost amp" issue (amp enables fine, but its output-terminal switches
default off) — replaced an earlier two-service approach that was more
fragile and had a permissions bug.

PipeWire audio was silent because the attached amp came up as `rt1320-2`
(the ghost amp declared first in ACPI took slot 1), so the UCM profile
didn't match and PipeWire fell back to the "Jack Out" PCM. Patch 0002 now
renumbers attached amps densely (`rt1320-1`), waits briefly for a real amp
that is still enumerating before treating it as a ghost, and keeps
`num_devs` in step with the skipped ghost. The unmute script and status
check accept either name.

## Repo layout

```
patches/          kernel/iptsd patches, plus libcamera/ (webcam patch + tuning)
configs/          config files, mirror their install paths under /etc and /usr
scripts/          install and rebuild scripts
dkms/             DKMS package for Ubuntu -generic kernels
dkms-surface/     DKMS package for linux-surface kernels (floopflop's scripts + ours)
iptsd-fork/       placeholder — clone alex-lentz/iptsd here at build time
```

## Patches are bundled

All 4 patch files are included directly in `patches/` — nothing to download
separately. `scripts/00-first-install.sh` checks they're present and exits
with a clear error if the directory has been tampered with or is incomplete,
but under normal use this is just a safety check, not a manual step.

Note on the iptsd fork binary: the fork is built and installed as
`/usr/local/bin/iptsd-fork` (not `/usr/bin/iptsd`), so it never overwrites
or conflicts with the distro's stock `iptsd` package. `configs/etc/systemd/
system/iptsd@.service.d/fork.conf` points at that path — if you ever move
or rename the binary, update that override to match.

## Live-session vs installed detection

`scripts/00-first-install.sh` auto-detects whether it's running on a live
(non-persistent) session or a normal installed system, via `/proc/cmdline`
and overlay-mount checks. On a live session it skips kernel pinning, the
GRUB edit, and Timeshift (all pointless there) and tells you how to add
`acpi_mask_gpe=0xAB` manually at the GRUB menu for that boot only. On an
installed system it installs Timeshift if missing and takes a snapshot
before making any changes — if anything goes wrong, boot a recovery/GRUB
rescue kernel and run `sudo timeshift --restore`.

Recommended order: test on a live USB session first (catches build errors
and the shutdown-panic question below at zero risk), then run for real on
your installed system, where the script's Timeshift snapshot gives you a
rollback path.

## Usage

First time setup:
```
./scripts/00-first-install.sh
```

After every kernel update (apt will hold the kernel package, but if you
deliberately upgrade it, or a point release moves you forward):
```
./scripts/01-rebuild-modules.sh
```

Webcam (builds patched libcamera 0.7.2 into `/usr/local`, a few minutes;
also sets up the `sl7-webcam` virtual webcam for Chrome):
```
./scripts/03-install-libcamera.sh
```

Automatic module rebuilds for new kernels (see "After a kernel update"):
```
./scripts/04-setup-dkms.sh
```

Check status of everything:
```
./scripts/02-status-check.sh
```

## Known risk

Reports on Ubuntu-based systems (Debian-6.19.8-surface-3 build, see
linux-surface/linux-surface#1710 comments from ghostplant) noted kernel
panics / hangs on shutdown when the SoundWire audio patch was active. This
was NOT reported on Fedora by nierdal.

**Tested on this machine: shutdown is clean, no hang or panic**, with the
audio patches applied, the module loaded, and `iptsd-resume.service`
enabled. `00-first-install.sh` now enables that service automatically on
the strength of this test — if you're on a different kernel version or
hardware revision, worth re-testing a clean shutdown yourself before
relying on it day-to-day.

## License note

See `LICENSE.md` for the full breakdown (kernel patches 0001-0003 and 0005-0007 are GPL-2.0,
patch 0004 is GPL-2.0-or-later, configs/ and scripts/ are CC0). Nothing in
this repo contains Microsoft code, firmware, or ACPI table dumps — those
are not redistributable and are not included.

See `CONTRIBUTING.md` if you want to help get any of this upstreamed into
`linux-surface/kernel`, alsa-devel, or mainline media/ASoC.
