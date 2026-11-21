#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

IMAGE=$1
BLOBS=$2
BSP=$(CDPATH= cd -- "$BLOBS/../../bsp/lkg" && pwd)
[ -f "$IMAGE" ] || { echo "Image not found: $IMAGE" >&2; exit 1; }
[ -d "$BLOBS" ] || { echo "Application blob directory not found: $BLOBS" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

LOOP=$("${SUDO[@]}" losetup --find --show --read-only --partscan "$IMAGE")
MOUNT=$(mktemp -d)
cleanup() {
    if mountpoint -q "$MOUNT"; then
        "${SUDO[@]}" umount "$MOUNT"
    fi
    rmdir "$MOUNT" 2>/dev/null || true
    "${SUDO[@]}" losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT
"${SUDO[@]}" mount -o ro "${LOOP}p1" "$MOUNT"

"${SUDO[@]}" grep -qx '33030144s' "$MOUNT/root/.rootfs_resize"
"${SUDO[@]}" grep -qx 'lkg' "$MOUNT/etc/hostname"
"${SUDO[@]}" grep -qE '(^|[[:space:]])lkg([[:space:]]|$)' "$MOUNT/etc/hosts"
"${SUDO[@]}" grep -qx 'overlayroot=""' "$MOUNT/etc/overlayroot.conf"
"${SUDO[@]}" grep -q '/home/lkg/data.*exfat' "$MOUNT/etc/fstab"
test ! -L "$MOUNT/etc/systemd/system/systemd-remount-fs.service"
cmp "$BSP/systemd-remount-fs-overlay.conf" \
    "$MOUNT/etc/systemd/system/systemd-remount-fs.service.d/overlay.conf"
[ "$(stat -c '%U:%G %a' "$MOUNT/home/lkg/data")" = 'root:root 755' ]
sh -n "$MOUNT/usr/local/sbin/lkg-firstboot-storage"
sh -n "$MOUNT/usr/local/sbin/lkg-wifi-restore"
sh -n "$MOUNT/usr/local/sbin/lkg-usb-disk"
"${SUDO[@]}" grep -qx 'Before=lkg-usb-disk.service lkg-menu.service' \
    "$MOUNT/etc/systemd/system/lkg-firstboot-storage.service"
cmp "$BSP/home-lkg-data.mount" "$MOUNT/etc/systemd/system/home-lkg-data.mount"
test ! -e "$MOUNT/etc/systemd/system/home-lkg-data.mount.d/firstboot.conf"
test -L "$MOUNT/etc/systemd/system/multi-user.target.wants/home-lkg-data.mount"
"${SUDO[@]}" grep -q 'reload-or-restart systemd-networkd.service' \
    "$MOUNT/usr/local/sbin/lkg-wifi-restore"
"${SUDO[@]}" grep -q 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev' \
    "$MOUNT/usr/local/sbin/lkg-wifi-restore"
"${SUDO[@]}" grep -q 'systemctl stop wpa_supplicant@wlan0.service' \
    "$MOUNT/usr/local/sbin/lkg-wifi-restore"
"${SUDO[@]}" grep -q 'reload-or-restart.*systemd-networkd.service' \
    "$MOUNT/usr/local/sbin/lkg-wifi"
"${SUDO[@]}" grep -qx 'CONFIG_PART=/dev/mmcblk0p2' "$MOUNT/usr/local/sbin/lkg-firstboot-storage"
"${SUDO[@]}" grep -qx 'CONFIG_MARKER=/var/lib/lkg/config-initialized' "$MOUNT/usr/local/sbin/lkg-firstboot-storage"
"${SUDO[@]}" grep -qx 'DATA_PART=/dev/mmcblk0p3' "$MOUNT/usr/local/sbin/lkg-firstboot-storage"
"${SUDO[@]}" grep -qx '        file=/dev/mmcblk0p3 \\' "$MOUNT/usr/local/sbin/lkg-usb-disk"
"${SUDO[@]}" grep -qx '        iManufacturer=LKG \\' "$MOUNT/usr/local/sbin/lkg-usb-disk"
"${SUDO[@]}" grep -q '30-lkg-wifi.yaml' "$MOUNT/usr/local/sbin/lkg-wifi-restore"
"${SUDO[@]}" grep -q '30-lkg-wifi.yaml' "$MOUNT/usr/local/sbin/lkg-wifi"
"${SUDO[@]}" grep -qx 'Requires=lkg-firstboot-storage.service' \
    "$MOUNT/etc/systemd/system/lkg-wifi-restore.service"
"${SUDO[@]}" grep -qx 'After=lkg-firstboot-storage.service' \
    "$MOUNT/etc/systemd/system/lkg-wifi-restore.service"
if "${SUDO[@]}" grep -q 'mountpoint -q /home/lkg/data' "$MOUNT/usr/local/sbin/lkg-wifi-restore"; then
    echo "Wi-Fi restore must not depend on the data mount" >&2
    exit 1
fi
"${SUDO[@]}" grep -q 'echo n; echo p; echo 2;.*echo +256M' \
    "$MOUNT/usr/lib/armbian/armbian-resize-filesystem"
"${SUDO[@]}" cmp "$MOUNT/etc/netplan/10-dhcp-all-interfaces.yaml" \
    "$MOUNT/etc/lkg/netplan-base/10-dhcp-all-interfaces.yaml"
sh -n "$MOUNT/usr/local/bin/lkg-menu"
test -x "$MOUNT/usr/local/bin/lkg-menu"
cmp "$BSP/lkg-menu" "$MOUNT/usr/local/bin/lkg-menu"
"${SUDO[@]}" cmp "$BLOBS/lkg-menu.sudoers" "$MOUNT/etc/sudoers.d/lkg-menu"
[ "$(stat -c '%a' "$MOUNT/etc/sudoers.d/lkg-menu")" = '440' ]

for service in \
    armbian-resize-filesystem.service \
    lkg-firstboot-storage.service \
    lkg-wifi-restore.service \
    lkg-usb-disk.service \
    lkg-usb-mode-watch.service \
    lkg-mcu.service \
    lkg-menu.service \
    avahi-daemon.service \
    ssh.service; do
    test -L "$MOUNT/etc/systemd/system/multi-user.target.wants/$service" || {
        echo "Expected enabled service is missing: $service" >&2
        exit 1
    }
done
test -L "$MOUNT/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
for unit in \
    home-lkg-data.mount \
    lkg-firstboot-storage.service \
    lkg-wifi-restore.service \
    lkg-usb-disk.service \
    lkg-usb-mode-watch.service \
    lkg-mcu.service \
    lkg-menu.service \
    lkg-shutdown-prepare.service \
    lkg-usb-media-rescan.service \
    lkg-usb-media@.service \
    dufs.service; do
    "${SUDO[@]}" grep -q '^Description=.*LKG Go' "$MOUNT/etc/systemd/system/$unit"
done
"${SUDO[@]}" grep -qx 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev' \
    "$MOUNT/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
"${SUDO[@]}" grep -qx 'ConditionPathExists=!/etc/netplan/30-lkg-wifi.yaml' \
    "$MOUNT/etc/systemd/system/wpa_supplicant@wlan0.service.d/lkg.conf"
test ! -L "$MOUNT/etc/systemd/system/multi-user.target.wants/dufs.service"
test ! -e "$MOUNT/etc/systemd/system/multi-user.target.wants/dufs.service"
test -f "$MOUNT/usr/share/doc/dufs/copyright"
cmp "$BLOBS/visual.json" "$MOUNT/etc/lkg/visual-template.json"
test ! -e "$MOUNT/etc/lkg/visual.json"
"${SUDO[@]}" grep -qx 'Before=lkg-menu.service' "$MOUNT/etc/systemd/system/lkg-mcu.service"
"${SUDO[@]}" grep -qx 'ExecStart=/usr/local/bin/lkg-mcu init --output /run/lkg/visual.json --template /etc/lkg/visual-template.json' "$MOUNT/etc/systemd/system/lkg-mcu.service"
"${SUDO[@]}" grep -qx 'Requires=lkg-mcu.service' "$MOUNT/etc/systemd/system/lkg-menu.service"
"${SUDO[@]}" grep -qx 'After=seatd.service user@1000.service lkg-mcu.service' "$MOUNT/etc/systemd/system/lkg-menu.service"
cmp "$BLOBS/lkg-shutdown-prepare" "$MOUNT/usr/local/sbin/lkg-shutdown-prepare"
sh -n "$MOUNT/usr/local/sbin/lkg-shutdown-prepare"
if "${SUDO[@]}" grep -q 'lkg-mcu poweroff' "$MOUNT/usr/local/sbin/lkg-shutdown-prepare"; then
    echo "lkg-shutdown-prepare must not invoke lkg-mcu poweroff early" >&2
    exit 1
fi
cmp "$BLOBS/lkg-shutdown-prepare.service" "$MOUNT/etc/systemd/system/lkg-shutdown-prepare.service"
cmp "$BLOBS/lkg-usb-mode-watch.service" "$MOUNT/etc/systemd/system/lkg-usb-mode-watch.service"
cmp "$BLOBS/lkg-mcu-poweroff-shutdown" "$MOUNT/usr/lib/systemd/system-shutdown/lkg-mcu-poweroff"
sh -n "$MOUNT/usr/lib/systemd/system-shutdown/lkg-mcu-poweroff"
test -x "$MOUNT/usr/lib/systemd/system-shutdown/lkg-mcu-poweroff"
"${SUDO[@]}" grep -qx 'Before=poweroff.target' "$MOUNT/etc/systemd/system/lkg-shutdown-prepare.service"
"${SUDO[@]}" grep -q '/usr/local/bin/lkg-mcu poweroff' "$MOUNT/usr/lib/systemd/system-shutdown/lkg-mcu-poweroff"
test -L "$MOUNT/etc/systemd/system/poweroff.target.wants/lkg-shutdown-prepare.service"
test ! -e "$MOUNT/etc/systemd/system/systemd-poweroff.service.d/mcu-poweroff.conf"
test ! -e "$MOUNT/etc/systemd/system/lkg-mcu-poweroff.service"
test ! -e "$MOUNT/usr/local/bin/lkg-mcu-poweroff"
test ! -e "$MOUNT/usr/local/sbin/lkg-usb-mode-watch"
test ! -e "$MOUNT/usr/local/sbin/lkg-usb-desktop"

cmp "$BLOBS/lkg-menu" "$MOUNT/home/lkg/bin/lkg-menu"
cmp "$BLOBS/lkg-player" "$MOUNT/home/lkg/bin/lkg-player"
cmp "$BLOBS/lkg-mcu" "$MOUNT/usr/local/bin/lkg-mcu"
"${SUDO[@]}" chroot "$MOUNT" /home/lkg/bin/lkg-menu --help >/dev/null
"${SUDO[@]}" chroot "$MOUNT" /home/lkg/bin/lkg-player --help >/dev/null
"${SUDO[@]}" chroot "$MOUNT" /usr/local/bin/lkg-mcu --help >/dev/null
if "${SUDO[@]}" chroot "$MOUNT" bash -c \
    'ldd /home/lkg/bin/lkg-menu /home/lkg/bin/lkg-player /usr/local/bin/lkg-mcu | grep "not found"'; then
    echo "Image application dynamic library check failed" >&2
    exit 1
fi
"${SUDO[@]}" chroot "$MOUNT" /usr/bin/gst-inspect-1.0 pipewiresink >/dev/null
test -f "$MOUNT/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"
"${SUDO[@]}" chroot "$MOUNT" /usr/bin/gst-inspect-1.0 avdec_aac >/dev/null
test -e "$MOUNT/usr/lib/aarch64-linux-gnu/libheif/plugins/libheif-libde265.so"
"${SUDO[@]}" grep -q '^URIs: https\?://security.debian.org' "$MOUNT/etc/apt/sources.list.d/debian.sources"
"${SUDO[@]}" grep -q '^Suites:.*trixie-security' "$MOUNT/etc/apt/sources.list.d/debian.sources"
"${SUDO[@]}" grep -q '^SupplementaryGroups=.*\baudio\b' "$MOUNT/etc/systemd/system/lkg-menu.service"
test -L "$MOUNT/etc/systemd/user/default.target.wants/pipewire.service"
test -L "$MOUNT/etc/systemd/user/default.target.wants/pipewire-pulse.service"
test -L "$MOUNT/etc/systemd/user/pipewire.service.wants/wireplumber.service"
cmp "$BLOBS/lkg-usb-media" "$MOUNT/usr/local/sbin/lkg-usb-media"
sh -n "$MOUNT/usr/local/sbin/lkg-usb-media"
cmp "$BLOBS/lkg-sway-setup" "$MOUNT/usr/local/sbin/lkg-sway-setup"
sh -n "$MOUNT/usr/local/sbin/lkg-sway-setup"
for script in lkg-screenshot lkg-volume lkg-window-menu lkg-gst-play lkg-vnc; do
    test -x "$MOUNT/usr/local/bin/$script"
    sh -n "$MOUNT/usr/local/bin/$script"
done
for bin in fuzzel waybar thunar mousepad micro imv-wayland wayvnc gst-play-1.0; do
    test -x "$MOUNT/usr/bin/$bin"
done
test -f "$MOUNT/home/lkg/.config/sway/config"
test -f "$MOUNT/home/lkg/.config/waybar/config.jsonc"
test -f "$MOUNT/home/lkg/.config/fuzzel/fuzzel.ini"
test -f "$MOUNT/home/lkg/.config/gtk-3.0/gtk.css"
"${SUDO[@]}" test -f "$MOUNT/home/lkg/.config/wayvnc/config"
"${SUDO[@]}" grep -q 'seat seat0 xcursor_theme Adwaita 12' "$MOUNT/home/lkg/.config/sway/config"

echo "Static image verification passed: $IMAGE"
