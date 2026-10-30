#!/usr/bin/env bash
# Webcam: build libcamera 0.7.2 with floopflop's SL7 patch (software ISP,
# lens shading, AWB, AE, denoise for the ov02c10) and install it to
# /usr/local, alongside the distro's libcamera 0.2.0 (different soname, so
# nothing that uses the system copy is affected). 0.2.0 has no IPA for the
# IPU7 pipeline ("No IPA found"); 0.7.2's simple pipeline + software ISP
# needs none.
#
# Also installs the 70-sl7-dma-heap udev rule (dma-buf access for the
# software ISP) and swaps the distro's GStreamer libcamera plugin for ours
# via dpkg-divert, so Cheese and other GStreamer apps see the webcam.
#
# Run from the repo root: ./scripts/03-install-libcamera.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHDIR="$REPO_ROOT/patches/libcamera"
CONFDIR="$REPO_ROOT/configs"
BUILD="$REPO_ROOT/.build/libcamera"
LC_VER=0.7.2
SRC="$BUILD/libcamera-v$LC_VER"

echo "== Build dependencies =="
sudo apt-get install -y meson ninja-build g++ pkg-config python3-yaml python3-ply \
  python3-jinja2 libyaml-dev libgnutls28-dev libudev-dev libevent-dev libdrm-dev \
  libjpeg-dev libtiff-dev libegl-dev libgles-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev

mkdir -p "$BUILD"
if [[ ! -d "$SRC" ]]; then
  echo "== Fetching libcamera v$LC_VER =="
  curl -sfL "https://gitlab.freedesktop.org/camera/libcamera/-/archive/v$LC_VER/libcamera-v$LC_VER.tar.bz2" \
    | tar -xj -C "$BUILD"
fi
if [[ ! -f "$SRC/.sl7-patched" ]]; then
  patch -d "$SRC" -p1 -s < "$PATCHDIR/libcamera-$LC_VER-sl7.patch"
  touch "$SRC/.sl7-patched"
fi

echo "== Building (takes a few minutes) =="
rm -rf "$SRC/build"
meson setup "$SRC/build" "$SRC" --prefix=/usr/local --buildtype=release \
  -Dpipelines=simple,uvcvideo -Dipas=simple -Dv4l2=enabled -Dgstreamer=enabled \
  -Dcam=enabled -Dqcam=disabled -Dlc-compliance=disabled -Dpycamera=disabled \
  -Ddocumentation=disabled -Dtest=false > "$BUILD/meson-setup.log" 2>&1 \
  || { tail -20 "$BUILD/meson-setup.log"; echo "meson setup failed (missing dependencies?)"; exit 1; }
ninja -C "$SRC/build" > "$BUILD/build.log" 2>&1 \
  || { tail -20 "$BUILD/build.log"; echo "BUILD FAILED, see $BUILD/build.log"; exit 1; }

echo "== Installing to /usr/local =="
sudo ninja -C "$SRC/build" install > /dev/null
sudo install -D -m 644 "$PATCHDIR/ov02c10.yaml" /usr/local/share/libcamera/ipa/simple/ov02c10.yaml
sudo ldconfig

sudo install -D -m 644 "$CONFDIR/etc/udev/rules.d/70-sl7-dma-heap.rules" /etc/udev/rules.d/70-sl7-dma-heap.rules
sudo udevadm control --reload-rules
sudo udevadm trigger /dev/dma_heap/system /dev/udmabuf 2>/dev/null || true

# GStreamer only searches the system plugin dir, and gnome-snapshot depends
# on the distro's 0.2.0 plugin package, so divert that plugin aside (package
# updates then write to the diverted name) and link ours in its place.
GST_SYS=/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so
if ! dpkg-divert --list "$GST_SYS" | grep -q distrib-0.2; then
  sudo dpkg-divert --local --rename --divert "$GST_SYS.distrib-0.2" --add "$GST_SYS"
fi
sudo ln -sfn /usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so "$GST_SYS"
# superseded by the divert above
sudo rm -f /etc/environment.d/90-sl7-libcamera.conf

# Virtual webcam for V4L2-only apps (Chrome Flatpak): v4l2loopback device
# /dev/video50 "Surface Camera", fed by the sl7-webcam user service.
echo "== Virtual webcam (v4l2loopback) =="
sudo install -D -m 644 "$CONFDIR/etc/modules-load.d/sl7-v4l2loopback.conf" /etc/modules-load.d/sl7-v4l2loopback.conf
sudo install -D -m 644 "$CONFDIR/etc/modprobe.d/sl7-v4l2loopback.conf" /etc/modprobe.d/sl7-v4l2loopback.conf
sudo install -D -m 644 "$CONFDIR/etc/systemd/user/sl7-webcam.service" /etc/systemd/user/sl7-webcam.service
sudo install -D -m 755 "$CONFDIR/usr/local/bin/sl7-webcam" /usr/local/bin/sl7-webcam
sudo install -D -m 644 "$CONFDIR/usr/local/share/applications/sl7-webcam.desktop" /usr/local/share/applications/sl7-webcam.desktop
lsmod | grep -q '^v4l2loopback' || sudo modprobe v4l2loopback
systemctl --user daemon-reload

echo
echo "Done. Test now:  cam -l   (should list 'Internal front camera')"
echo "Cheese and other GStreamer apps should now see the webcam (restart them)."
echo "Chrome: run 'sl7-webcam on' (or the Surface Camera launcher), then pick"
echo "\"Surface Camera\" in Chrome's camera settings. 'sl7-webcam off' when done."
