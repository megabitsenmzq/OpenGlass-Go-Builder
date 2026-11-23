#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

IMAGE=$1
BLOBS=$2
[ -f "$IMAGE" ] || { echo "Image not found: $IMAGE" >&2; exit 1; }
[ -d "$BLOBS" ] || { echo "Application blob directory not found: $BLOBS" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

LOOP=$("${SUDO[@]}" losetup --find --show --partscan "$IMAGE")
MOUNT=$(mktemp -d)
DNS_TARGET=
cleanup() {
    if [ -n "$DNS_TARGET" ] && mountpoint -q "$DNS_TARGET"; then
        "${SUDO[@]}" umount "$DNS_TARGET"
    fi
    if mountpoint -q "$MOUNT"; then
        "${SUDO[@]}" umount "$MOUNT"
    fi
    rmdir "$MOUNT" 2>/dev/null || true
    "${SUDO[@]}" losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT
"${SUDO[@]}" mount "${LOOP}p1" "$MOUNT"
"${SUDO[@]}" install -o 1000 -g 1000 -m755 "$BLOBS/lkg-menu" "$MOUNT/home/lkg/bin/lkg-menu"
"${SUDO[@]}" install -o 1000 -g 1000 -m755 "$BLOBS/lkg-player" "$MOUNT/home/lkg/bin/lkg-player"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-mcu" "$MOUNT/usr/local/bin/lkg-mcu"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-shutdown-prepare" "$MOUNT/usr/local/sbin/lkg-shutdown-prepare"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-wifi" "$MOUNT/usr/local/sbin/lkg-wifi"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-wifi-restore" "$MOUNT/usr/local/sbin/lkg-wifi-restore"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-usb-media" "$MOUNT/usr/local/sbin/lkg-usb-media"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-sway-setup" "$MOUNT/usr/local/sbin/lkg-sway-setup"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-usb-disk" "$MOUNT/usr/local/sbin/lkg-usb-disk"
"${SUDO[@]}" rm -f "$MOUNT/usr/local/bin/lkg-mcu-poweroff" \
    "$MOUNT/usr/local/sbin/lkg-usb-mode-watch" \
    "$MOUNT/usr/local/sbin/lkg-usb-desktop"
"${SUDO[@]}" install -o root -g root -m440 "$BLOBS/lkg-menu.sudoers" "$MOUNT/etc/sudoers.d/lkg-menu"
"${SUDO[@]}" install -o root -g root -m644 "$BLOBS/lkg-shutdown-prepare.service" \
    "$MOUNT/etc/systemd/system/lkg-shutdown-prepare.service"
"${SUDO[@]}" install -o root -g root -m644 "$BLOBS/lkg-usb-mode-watch.service" \
    "$MOUNT/etc/systemd/system/lkg-usb-mode-watch.service"
"${SUDO[@]}" install -o root -g root -m644 "$BLOBS/lkg-mcu.service" \
    "$MOUNT/etc/systemd/system/lkg-mcu.service"
"${SUDO[@]}" install -o root -g root -m644 "$BLOBS/lkg-menu.service" \
    "$MOUNT/etc/systemd/system/lkg-menu.service"
"${SUDO[@]}" ln -sf ../lkg-usb-mode-watch.service \
    "$MOUNT/etc/systemd/system/multi-user.target.wants/lkg-usb-mode-watch.service"
"${SUDO[@]}" install -d "$MOUNT/etc/systemd/system/poweroff.target.wants" \
    "$MOUNT/usr/lib/systemd/system-shutdown"
"${SUDO[@]}" ln -sf ../lkg-shutdown-prepare.service \
    "$MOUNT/etc/systemd/system/poweroff.target.wants/lkg-shutdown-prepare.service"
"${SUDO[@]}" install -o root -g root -m755 "$BLOBS/lkg-mcu-poweroff-shutdown" \
    "$MOUNT/usr/lib/systemd/system-shutdown/lkg-mcu-poweroff"
"${SUDO[@]}" rm -f "$MOUNT/etc/systemd/system/systemd-poweroff.service.d/mcu-poweroff.conf" \
    "$MOUNT/etc/systemd/system/lkg-mcu-poweroff.service"
"${SUDO[@]}" rmdir "$MOUNT/etc/systemd/system/systemd-poweroff.service.d" 2>/dev/null || true
REQUIRED_PACKAGES=(
    gstreamer1.0-libav
    gstreamer1.0-pipewire
    gstreamer1.0-tools
    gstreamer1.0-plugins-base-apps
    pipewire-audio
    wireplumber
    sound-theme-freedesktop
    libheif1
    fuzzel
    waybar
    thunar
    thunar-archive-plugin
    xarchiver
    mousepad
    micro
    imv
    wl-clipboard
    grim
    slurp
    mako-notifier
    libnotify-bin
    htop
    pulsemixer
    fonts-wqy-microhei
    ranger
    mc
    wayvnc
    unzip
    7zip
    bzip2
    xz-utils
    file
    xdg-utils
    openssl
)
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    "${SUDO[@]}" chroot "$MOUNT" dpkg-query -W -f='${Status}' "$package" 2>/dev/null | \
        grep -q 'ok installed' || MISSING_PACKAGES+=("$package")
done
if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
    HOST_RESOLV=$(readlink -f /etc/resolv.conf)
    if [ -L "$MOUNT/etc/resolv.conf" ]; then
        RESOLV_LINK=$(readlink "$MOUNT/etc/resolv.conf")
        case "$RESOLV_LINK" in
            /*) DNS_TARGET="$MOUNT$RESOLV_LINK" ;;
            *) DNS_TARGET="$MOUNT/etc/$RESOLV_LINK" ;;
        esac
    else
        DNS_TARGET="$MOUNT/etc/resolv.conf"
    fi
    "${SUDO[@]}" install -d "$(dirname "$DNS_TARGET")"
    "${SUDO[@]}" touch "$DNS_TARGET"
    "${SUDO[@]}" mount --bind "$HOST_RESOLV" "$DNS_TARGET"
    "${SUDO[@]}" chroot "$MOUNT" apt-get update -qq
    "${SUDO[@]}" chroot "$MOUNT" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
    "${SUDO[@]}" chroot "$MOUNT" apt-get clean
fi
"${SUDO[@]}" chroot "$MOUNT" /usr/local/sbin/lkg-sway-setup
"${SUDO[@]}" chroot "$MOUNT" usermod --append --groups audio lkg
"${SUDO[@]}" find "$MOUNT/dev" -maxdepth 1 -type f -delete 2>/dev/null || true
"${SUDO[@]}" sync
