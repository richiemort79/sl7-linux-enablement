#!/usr/bin/env bash
# Quick health check for every component this repo touches.
# Safe to run any time, read-only.
set -uo pipefail

echo "== Kernel =="
uname -r

echo
echo "== Out-of-tree modules loaded =="
for m in surface_aggregator_registry snd_soc_sdw_utils ov02c10; do
  if lsmod | grep -q "^$m"; then
    echo "OK   $m loaded"
  else
    echo "MISS $m NOT loaded"
  fi
done

echo
echo "== Battery / AC =="
if [[ -d /sys/class/power_supply/BAT1 ]]; then
  echo "OK   BAT1 present: $(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)%"
else
  echo "MISS no BAT1"
fi

echo
echo "== Keyboard (SAM) =="
if grep -qi "045E:0C9A" /proc/bus/input/devices 2>/dev/null || \
   grep -qi "Surface" /proc/bus/input/devices 2>/dev/null; then
  echo "OK   SAM keyboard node found in /proc/bus/input/devices"
else
  echo "CHECK manually: grep -i surface /proc/bus/input/devices"
fi

echo
echo "== Ambient light sensor =="
if [[ -e /sys/bus/iio/devices/iio:device0/in_illuminance_raw ]] || \
   compgen -G "/sys/bus/iio/devices/iio:device*/in_illuminance_raw" > /dev/null; then
  echo "OK   ALS iio device present"
else
  echo "MISS no ALS iio device found"
fi

echo
echo "== Audio (SOF / SoundWire) =="
sudo dmesg 2>/dev/null | grep -i "sof-audio-pci-intel-lnl" | tail -5
if aplay -l 2>/dev/null | grep -qi "sof"; then
  echo "OK   SOF card visible in aplay -l"
else
  echo "CHECK aplay -l output above/manually"
fi

echo
echo "== Webcam =="
if v4l2-ctl --list-devices 2>/dev/null | grep -qi "ov02c10\|Front Camera"; then
  echo "OK   camera device present"
else
  echo "CHECK v4l2-ctl --list-devices manually"
fi

echo
echo "== iptsd (touchpad) =="
if systemctl is-active --quiet "iptsd@*" 2>/dev/null || pgrep -x iptsd > /dev/null; then
  echo "OK   iptsd running"
else
  echo "CHECK systemctl status 'iptsd@*'"
fi

echo
echo "== iptsd-resume.service =="
systemctl is-enabled iptsd-resume.service 2>/dev/null || echo "not enabled"

echo
echo "== Speaker output terminal (rt1320 OT23 L/R) =="
[[ -f /etc/udev/rules.d/91-sl7-speaker-unmute.rules ]] && echo "OK   udev rule installed" || echo "MISS udev rule not installed"
SPK_CARD="$(aplay -l 2>/dev/null | awk -F'[ :]' '/sofsoundwire/{print $2; exit}')"
SPK_CARD="${SPK_CARD:-0}"
{ amixer -c "$SPK_CARD" sget 'rt1320-1 OT23 L' || amixer -c "$SPK_CARD" sget 'rt1320-2 OT23 L'; } 2>/dev/null | grep -q '\[on\]' && echo "OK   OT23 L on" || echo "MISS OT23 L off or card not present"
{ amixer -c "$SPK_CARD" sget 'rt1320-1 OT23 R' || amixer -c "$SPK_CARD" sget 'rt1320-2 OT23 R'; } 2>/dev/null | grep -q '\[on\]' && echo "OK   OT23 R on" || echo "MISS OT23 R off or card not present"
grep -qs 'slave.pcm "hw:0,2"' /etc/asound.conf && echo "WARN old /etc/asound.conf override present (bypasses PipeWire) — re-run 00-first-install.sh or remove it" || echo "OK   no old asound.conf override"

echo
echo "== GPE 0xAB mask =="
if grep -q "acpi_mask_gpe=0xAB" /proc/cmdline; then
  echo "OK   present in kernel cmdline"
else
  echo "MISS not in /proc/cmdline — check GRUB config took effect"
fi

echo
echo "== Bluetooth suspend workaround =="
if [[ -x /usr/lib/systemd/system-sleep/btintel-pcie.sh ]]; then
  echo "OK   sleep hook installed and executable"
else
  echo "MISS btintel-pcie.sh missing or not executable"
fi
