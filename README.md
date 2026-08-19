# Surface Laptop 7 (Intel, Lunar Lake) enablement — Zorin OS

Personal build/maintenance repo for keeping a Surface Laptop 7 for Business
(Intel Core Ultra 7 268V, Lunar Lake) fully working on Zorin OS (Ubuntu-based)
with the stock distro kernel, no linux-surface kernel required.

Based on the bring-up work and root-cause analysis from nierdal on
linux-surface/linux-surface#1710, adapted for Ubuntu/Zorin.

## After a kernel update

The 3 out-of-tree modules (keyboard/battery, audio, webcam) are built for
one specific kernel version. After any kernel update, they silently fall
back to the stock (unpatched) versions — keyboard/battery/audio/webcam
will stop working with no error, until you rebuild:

```
cd scripts && ./01-rebuild-modules.sh
sudo modprobe -r surface_aggregator_registry && sudo modprobe surface_aggregator_registry
sudo modprobe -r snd_soc_sdw_utils ov02c10 && sudo modprobe snd_soc_sdw_utils ov02c10
```

To stop this happening automatically, pin the kernel:
`sudo apt-mark hold linux-image-generic linux-headers-generic linux-image-$(uname -r) linux-headers-$(uname -r)`
(trades auto security updates for stability on this hardware-support layer)

## Status

**Working:**
- Keyboard, battery, fan, platform profile
- Ambient light sensor
- Speakers (raw ALSA only — see below)
- Touchpad: cursor, drag, scroll, right-click (two-finger tap, or corner-
  press if enabled in Zorin's touchpad settings)
- Power button wake from s2idle (tested: suspend, then power button wakes it)
- Clean shutdown with audio patches active (tested: no hang/panic)
- Touchpad after suspend/resume (iptsd-resume.service — without it,
  degrades to mouse-only after first sleep, no gestures/drag/right-click)

**Not working:**
- PipeWire-routed audio (browsers, most apps) — silent. Raw ALSA works
  (`configs/etc/asound.conf`)
- Webcam — sensor driver (`ov02c10`) and IPU7 kernel pipeline load fine,
  32 raw `/dev/videoN` nodes exist, but no working image. Root cause:
  `cam -l` (libcamera) reports "No IPA found" — confirmed via filesystem
  search (`find / -iname "*ipu7*ipa*"`) that no IPA plugin exists
  anywhere on the system. Installed libcamera is 0.2.0 (Ubuntu noble),
  which may itself predate solid IPU7 pipeline-handler support — this is
  very new hardware (Lunar Lake, late 2024/2025). Likely needs a newer
  libcamera + IPA, not currently packaged for this distro; not a config
  issue on this machine's end
- Screen brightness control — no effect from keys, GNOME, or direct sysfs
  writes. `i915`/`xe` DPCD kernel params tried, no effect

## Patch notes

Patches beyond the original bring-up report: 0005 adds battery reporting
(missing SAM node references for SL7). 0002 was split from a combined
patch since one of its two target files was already superseded upstream
on newer kernels. The `91-sl7-speaker-unmute.rules` udev rule fixes a
"ghost amp" issue (amp enables fine, but its output-terminal switches
default off) — replaced an earlier two-service approach that was more
fragile and had a permissions bug.

## Repo layout

```
patches/          the 4 kernel/iptsd patches — bundled, verified present
configs/          config files, mirror their install paths under /etc and /usr
scripts/          install and rebuild scripts
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

See `LICENSE.md` for the full breakdown (patches 0001-0003 are GPL-2.0,
patch 0004 is GPL-2.0-or-later, configs/ and scripts/ are CC0). Nothing in
this repo contains Microsoft code, firmware, or ACPI table dumps — those
are not redistributable and are not included.

See `CONTRIBUTING.md` if you want to help get any of this upstreamed into
`linux-surface/kernel`, alsa-devel, or mainline media/ASoC.
