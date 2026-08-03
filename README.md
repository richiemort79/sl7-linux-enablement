# Surface Laptop 7 (Intel, Lunar Lake) enablement — Zorin OS

Personal build/maintenance repo for keeping a Surface Laptop 7 for Business
(Intel Core Ultra 7 268V, Lunar Lake) fully working on Zorin OS (Ubuntu-based)
with the stock distro kernel, no linux-surface kernel required.

Based on the bring-up work and root-cause analysis from nierdal on
linux-surface/linux-surface#1710, adapted for Ubuntu/Zorin.

## What works after this

- Keyboard, battery, fan, platform profile (MSHW0551 registry fix)
- Ambient light sensor with native auto brightness
- Speakers, headset jack, internal mic array (SoundWire fixes)
- Webcam at ~18.8 fps (12 MHz clock tolerance patch)
- Full touchpad: cursor, gestures, physical clicks (iptsd fork + tuning)
- Power button wake from s2idle, no keyboard-dead-at-greeter race
- No GPE storm / sleep-of-death on resume

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

## Known risk (read before enabling audio + resume together)

Reports on Ubuntu-based systems (Debian-6.19.8-surface-3 build, see
linux-surface/linux-surface#1710 comments from ghostplant) noted kernel
panics / hangs on shutdown when the SoundWire audio patch was active. This
was NOT reported on Fedora by nierdal. Test a clean shutdown BEFORE enabling
`iptsd-resume.service`, so you can isolate which component is responsible if
something hangs.

## License note

Patches 0001-0003 modify Linux kernel sources (GPL-2.0). Patch 0004 is under
iptsd's license (GPL-2.0-or-later). Config files here are public domain
(CC0). Nothing in this repo contains Microsoft code, firmware, or ACPI table
dumps — those are not redistributable and are not included.
