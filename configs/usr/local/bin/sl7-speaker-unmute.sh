#!/bin/sh
# The rt1320 amp's Output Terminal (OT23 L/R) switches default to off
# whenever the sof-soundwire card is created, even though every other
# stage in the speaker signal chain (Speaker Switch, Pre/Post Mixer
# volumes, FU21 gain) is on and at full volume — the "ghost amp" pattern.
# This sets them on. Triggered by udev the instant the card appears
# (see /etc/udev/rules.d/91-sl7-speaker-unmute.rules), so no retry loop
# needed — if the sof-soundwire card isn't present yet, this simply does
# nothing and udev will fire it again when the right device shows up.

CARD="$(aplay -l 2>/dev/null | awk -F'[ :]' '/sofsoundwire/{print $2; exit}')"
[ -z "$CARD" ] && exit 0

# rt1320-1 with the renumbering in patch 0002, rt1320-2 on older builds
for AMP in rt1320-1 rt1320-2; do
  amixer -c "$CARD" sset "$AMP OT23 L" on >/dev/null 2>&1
  amixer -c "$CARD" sset "$AMP OT23 R" on >/dev/null 2>&1
done
