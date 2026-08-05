#!/bin/sh
# The rt1320 amp's Output Terminal (OT23 L/R) switches default to off on
# every boot/module reload, even though every other stage in the speaker
# signal chain (Speaker Switch, Pre/Post Mixer volumes, FU21 gain) is on
# and at full volume. Without this, speakers are completely silent with
# no errors anywhere — the "ghost amp" pattern. This sets them on.
#
# SOF/SoundWire card enumeration is async at boot, so retry briefly
# rather than relying purely on systemd unit ordering.

TRIES=20
DELAY=1

i=0
while [ "$i" -lt "$TRIES" ]; do
	# Resolve the actual card index each try — aplay -l shows it as
	# "card N: sofsoundwire [sof-soundwire], ...". Card ID has no hyphen;
	# the bracketed name does. `amixer -c` wants the numeric index or the
	# ID, not the bracketed name, so parse the ID out explicitly instead
	# of assuming index 0 (which worked in manual testing but could shift
	# if another sound card enumerates first on some boots).
	CARD="$(aplay -l 2>/dev/null | awk -F'[ :]' '/sofsoundwire/{print $2; exit}')"
	CARD="${CARD:-0}"

	if amixer -c "$CARD" sset 'rt1320-2 OT23 L' on >/dev/null 2>&1 \
	   && amixer -c "$CARD" sset 'rt1320-2 OT23 R' on >/dev/null 2>&1; then
		exit 0
	fi
	i=$((i + 1))
	sleep "$DELAY"
done

echo "sl7-speaker-unmute: could not set OT23 L/R after ${TRIES}s, card may not be present" >&2
exit 1
