#!/usr/bin/python3 -I
"""Compare the exported-symbol CRCs of a rebuilt module with the kernel's.

drm_display_helper is used by the graphics driver: if any exported symbol's
CRC differed from the kernel's Module.symvers, xe would refuse to load it
and the display would not come up. sl7-make.sh fails the build instead.

Usage: check-crcs.py <our Module.symvers> <kernel Module.symvers> <module path>
       (module path as in Module.symvers, e.g. drivers/gpu/drm/display/drm_display_helper)
"""
import sys


def load(path, module):
    crcs = {}
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 3 and f[2].endswith(module):
            crcs[f[1]] = f[0]
    return crcs


ours = load(sys.argv[1], sys.argv[3])
ref = load(sys.argv[2], sys.argv[3])
bad = sorted(s for s in ref if ours.get(s) != ref[s])
if not ref or bad:
    sys.exit(f"{sys.argv[3]}: CRC check FAILED ({len(ref)} kernel exports, "
             f"mismatched or missing: {bad[:10]})")
print(f"{sys.argv[3]}: all {len(ref)} exports match the kernel")
