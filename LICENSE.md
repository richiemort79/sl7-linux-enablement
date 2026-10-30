This repository contains files under different licenses, matching the
upstream projects each part modifies.

## patches/0001, 0002, 0003 — Linux kernel patches

These are diffs against Linux kernel sources (drivers/platform/surface,
sound/soc/sdw_utils, drivers/media/i2c) and are licensed GPL-2.0, the
license of the Linux kernel itself. See:
https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

## patches/0004 — iptsd patch

This is a diff against alex-lentz/iptsd (itself a fork of linux-surface's
iptsd) and is licensed GPL-2.0-or-later, matching iptsd's own license.
See: https://github.com/linux-surface/iptsd/blob/master/LICENSE

## patches/libcamera/ — webcam (from floopflop/SL_Intel_Linux)

Copied unchanged from https://github.com/floopflop/SL_Intel_Linux (commit
9f6c109). `libcamera-0.7.2-sl7.patch` modifies libcamera and is
LGPL-2.1-or-later like libcamera itself. `ov02c10.yaml` (the camera
tuning file) is CC0-1.0, as marked in its header.

## configs/ — configuration files

All files under configs/ (systemd units, udev rules, iptsd.d config,
libinput quirks, wireplumber config, the btintel-pcie sleep hook) are
released under CC0 1.0 Universal (public domain dedication). Do whatever
you want with them, no attribution required.
https://creativecommons.org/publicdomain/zero/1.0/

## scripts/ — install and rebuild scripts

Also CC0 1.0 Universal, same as configs/.

## Not included, not covered by any of the above

Factory ICC display color profiles and ACPI table dumps are deliberately
NOT included in this repository. They originate from Microsoft's Windows
driver package / device firmware and are not this project's to
redistribute. See README.md for how to extract your own copies from your
own legitimately obtained driver download.

Hardware identifiers referenced in the patches and configs (ACPI IDs like
MSHW0551, USB/HID IDs like 045E:0C9F) are functional facts about the
hardware, not copyrightable content, and are not subject to any of the
above licenses.
