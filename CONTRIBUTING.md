# Contributing / upstreaming

This repo exists to keep one Surface Laptop 7 (Intel, Lunar Lake) running
well on Zorin OS with the stock distro kernel. It is not itself an upstream
project, but the fixes here are meant to be upstreamable, and pointers are
below for anyone who wants to take them further.

## Where this came from

The patches and root-cause analysis originate from a bring-up report on:
https://github.com/linux-surface/linux-surface/issues/1710

That issue is the canonical discussion thread for Surface Laptop 7 (Intel)
Linux support in general. If you hit a problem not covered here, or want
to report back that something works/doesn't on a different distro or
kernel version, that issue is the right place, not this repo.

## Where each fix belongs upstream

Not all four patches have the same destination — they differ in scope:

- **patches/0001** (MSHW0551 registry entry + ALS sensor node) —
  Surface-specific, belongs in `linux-surface/kernel`'s own patch set
  (`drivers/platform/surface/surface_aggregator_registry.c`). Small,
  mechanical, and the node group (`ssam_node_group_sl7`) already exists in
  mainline for the ARM variant, so this is a low-risk, high-value PR
  against the fork, and arguably worth proposing to mainline directly too.

- **patches/0002** (SoundWire audio: DAI naming, ghost-amp skip, mic
  backport, amp renumbering) — mixed. The DAI-type-suffix and
  ghost-amp-skip fixes are generically useful ASoC/SoundWire
  machine-driver robustness fixes (not Surface-specific) and belong on the
  alsa-devel mailing list or as a PR against the relevant SOF/ASoC tree.
  The mic backport and amp renumbering are more Surface-Laptop-7-specific
  and fit `linux-surface/kernel` more naturally, at least until upstream
  ASoC master already contains the equivalent commits (see patch
  description for what to check).

- **patches/0003** (ov02c10 12 MHz clock support, PLL multipliers 400 -> 640) — belongs in the media
  subsystem (`drivers/media/i2c/ov02c10.c`) upstream; not Surface-specific,
  useful to any Lunar Lake board wiring this sensor to 12 MHz.

- **patches/0004** (iptsd LiftGraceMs option) — belongs as a PR against
  `alex-lentz/iptsd` (the fork this sits on top of) or, if the maintainer
  is interested, against `linux-surface/iptsd` directly, since ghost taps
  from single-frame contact-detection dropouts are a generic
  precision-touchpad problem, not unique to this laptop.

## If you want to open a PR yourself

A few practical notes carried over from testing this on Zorin/Ubuntu:

- Split PRs by subsystem rather than bundling — reviewers for
  `surface_aggregator_registry.c` are not the same people reviewing
  `soc_sdw_utils.c`.
- Include the root-cause explanation, not just the diff. Maintainers
  respond faster when the "why" is already written out (see the original
  issue comment for the level of detail that worked).
- Flag the Ubuntu-specific shutdown/panic reports if you're testing on a
  Debian/Ubuntu-based kernel — this hasn't been reported on Fedora, so it
  may be distro-config-specific and worth narrowing down before or during
  review, not after merge.

## What NOT to send upstream

Config files under `configs/` (systemd units, udev rules, iptsd tuning,
wireplumber rules) are personal/local tuning for one specific unit's
measured hardware tolerances (e.g. touchpad thresholds), not upstream
material. They're useful as a reference for someone else doing their own
bring-up, but shouldn't be proposed as-is to any upstream project.
