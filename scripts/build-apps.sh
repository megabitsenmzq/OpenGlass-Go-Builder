#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

PROJECT_ROOT=$1
CHROOT_DIR=$2
OUTPUT_DIR=$3
# shellcheck source=../versions.lock
source "$PROJECT_ROOT/versions.lock"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

PACKAGES=(
    build-essential pkg-config
    libgbm-dev libegl-dev libgles-dev libdrm-dev libfreetype-dev
    libpng-dev libjpeg-dev libqrencode-dev libheif-dev fonts-dejavu-core
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libswscale-dev
)

if [ ! -f "$CHROOT_DIR/etc/debian_version" ]; then
    "${SUDO[@]}" debootstrap --arch=arm64 --variant=minbase \
        "$DEBIAN_RELEASE" "$CHROOT_DIR" "$DEBIAN_MIRROR"
fi

printf 'deb %s %s main\ndeb https://security.debian.org/debian-security %s-security main\n' \
    "$DEBIAN_MIRROR" "$DEBIAN_RELEASE" "$DEBIAN_RELEASE" | \
    "${SUDO[@]}" tee "$CHROOT_DIR/etc/apt/sources.list" >/dev/null
"${SUDO[@]}" chroot "$CHROOT_DIR" apt-get update
"${SUDO[@]}" chroot "$CHROOT_DIR" env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends "${PACKAGES[@]}"

APP_SOURCE_ROOT="$PROJECT_ROOT/apps"
for app in lkg-menu lkg-player lkg-mcu; do
    [ -d "$APP_SOURCE_ROOT/$app" ] || {
        echo "Missing application source: $APP_SOURCE_ROOT/$app (run: git submodule update --init --recursive apps)" >&2
        exit 1
    }
done

"${SUDO[@]}" rm -rf "$CHROOT_DIR/root/lkg-app-src"
"${SUDO[@]}" mkdir -p "$CHROOT_DIR/root/lkg-app-src"
for app in lkg-menu lkg-player lkg-mcu; do
    "${SUDO[@]}" cp -a "$APP_SOURCE_ROOT/$app" "$CHROOT_DIR/root/lkg-app-src/"
done

"${SUDO[@]}" chroot "$CHROOT_DIR" bash -lc \
    'make -C /root/lkg-app-src/lkg-menu clean && make -C /root/lkg-app-src/lkg-menu -j"$(nproc)"'
"${SUDO[@]}" chroot "$CHROOT_DIR" bash -lc \
    'make -C /root/lkg-app-src/lkg-player clean && make -C /root/lkg-app-src/lkg-player -j"$(nproc)"'
"${SUDO[@]}" chroot "$CHROOT_DIR" bash -lc \
    'make -C /root/lkg-app-src/lkg-mcu clean && make -C /root/lkg-app-src/lkg-mcu -j"$(nproc)"'

mkdir -p "$OUTPUT_DIR"
"${SUDO[@]}" install -m 0755 "$CHROOT_DIR/root/lkg-app-src/lkg-menu/lkg-menu" \
    "$OUTPUT_DIR/lkg-menu"
"${SUDO[@]}" install -m 0755 "$CHROOT_DIR/root/lkg-app-src/lkg-player/lkg-player" \
    "$OUTPUT_DIR/lkg-player"
"${SUDO[@]}" install -m 0755 "$CHROOT_DIR/root/lkg-app-src/lkg-mcu/lkg-mcu" \
    "$OUTPUT_DIR/lkg-mcu"
"${SUDO[@]}" install -m 0755 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-shutdown-prepare" \
    "$OUTPUT_DIR/lkg-shutdown-prepare"
"${SUDO[@]}" install -m 0644 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-shutdown-prepare.service" \
    "$OUTPUT_DIR/lkg-shutdown-prepare.service"
"${SUDO[@]}" install -m 0644 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-usb-mode-watch.service" \
    "$OUTPUT_DIR/lkg-usb-mode-watch.service"
"${SUDO[@]}" install -m 0644 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-mcu.service" \
    "$OUTPUT_DIR/lkg-mcu.service"
"${SUDO[@]}" install -m 0644 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-menu.service" \
    "$OUTPUT_DIR/lkg-menu.service"
"${SUDO[@]}" install -m 0644 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-menu.sudoers" \
    "$OUTPUT_DIR/lkg-menu.sudoers"
"${SUDO[@]}" install -m 0755 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-mcu-poweroff-shutdown" \
    "$OUTPUT_DIR/lkg-mcu-poweroff-shutdown"
"${SUDO[@]}" install -m 0755 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-wifi-restore" \
    "$OUTPUT_DIR/lkg-wifi-restore"
"${SUDO[@]}" install -m 0755 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-usb-media" \
    "$OUTPUT_DIR/lkg-usb-media"
"${SUDO[@]}" install -m 0755 "$PROJECT_ROOT/source/packages/bsp/lkg/lkg-sway-setup" \
    "$OUTPUT_DIR/lkg-sway-setup"

"${SUDO[@]}" chroot "$CHROOT_DIR" /root/lkg-app-src/lkg-menu/lkg-menu --help >/dev/null
"${SUDO[@]}" chroot "$CHROOT_DIR" /root/lkg-app-src/lkg-player/lkg-player --help >/dev/null
"${SUDO[@]}" chroot "$CHROOT_DIR" /root/lkg-app-src/lkg-mcu/lkg-mcu --help >/dev/null
if "${SUDO[@]}" chroot "$CHROOT_DIR" bash -lc \
    'ldd /root/lkg-app-src/lkg-menu/lkg-menu /root/lkg-app-src/lkg-player/lkg-player /root/lkg-app-src/lkg-mcu/lkg-mcu | grep "not found"'; then
    echo "Application dynamic library check failed" >&2
    exit 1
fi

"${SUDO[@]}" chroot "$CHROOT_DIR" dpkg-query -W -f='${Package}\t${Version}\n' \
    > "$OUTPUT_DIR/app-build-packages.txt"
sha256sum "$OUTPUT_DIR/lkg-menu" "$OUTPUT_DIR/lkg-player" "$OUTPUT_DIR/lkg-mcu"
