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

Note: battery reporting needed a second small patch (0005) beyond the
original bring-up report — the stock `ssam_node_group_sl7[]` array (reused
from the ARM Surface Laptop 7 variant) didn't reference the battery SAM
nodes that SL6/SLS1 already use, even though those node definitions already
exist generically in the file. See patches/0005 and its commit message for
the two-line fix.

Note: even with patches 0002/0006 applied and the audio card enumerating
correctly (ALSA sees Speaker/Jack Out/HDMI devices, no errors anywhere),
speakers were completely silent. Root cause: the rt1320 amp's Output
Terminal switches (`rt1320-2 OT23 L Switch` / `... R Switch`) default to
off on every boot, even though every other stage in the chain (Speaker
Switch, Pre/Post Mixer volumes, FU21 gain) is on and at full volume — the
classic "ghost amp" pattern the original bring-up report warned about.
`configs/etc/systemd/system/sl7-speaker-unmute.service` + `configs/usr/
local/bin/sl7-speaker-unmute.sh` set these on at boot with retry logic
(SOF/SoundWire card enumeration is async, so a fixed systemd ordering
alone isn't reliable). Enabled automatically by `00-first-install.sh`.

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

patches/0005 was added later during real-hardware testing — it fixes
battery reporting, which the original bring-up report's patches didn't
cover (see README "What works after this" for details).

patches/0002 was originally one combined patch touching two files
(soc_sdw_utils.c and soc_sdw_rt_dmic.c). It's now split into 0002
(soc_sdw_utils.c — the DAI-naming/duplicate-device fix that actually
matters) and 0006 (soc_sdw_rt_dmic.c — internal mic backport). This is
because on newer kernel source, soc_sdw_rt_dmic.c's target content is
sometimes already present via an unrelated upstream change, which made
the combined patch report as "already applied"/failed as a whole and
block the audio module build entirely — even though the actual fix
(0002) applied cleanly every time. Splitting them lets each apply and get
tracked independently; the audio module now only requires 0002 to
succeed.

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

See `LICENSE.md` for the full breakdown (patches 0001-0003 are GPL-2.0,
patch 0004 is GPL-2.0-or-later, configs/ and scripts/ are CC0). Nothing in
this repo contains Microsoft code, firmware, or ACPI table dumps — those
are not redistributable and are not included.

See `CONTRIBUTING.md` if you want to help get any of this upstreamed into
`linux-surface/kernel`, alsa-devel, or mainline media/ASoC.
