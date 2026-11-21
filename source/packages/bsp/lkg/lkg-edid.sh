#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
PREREQ=""
prereqs() {
	echo "$PREREQ"
}
case "$1" in
	prereqs)
		prereqs
		exit 0
		;;
esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p "${DESTDIR}/lib/firmware/edid"
cp /lib/firmware/edid/LCD_0598AUOQHM01.bin "${DESTDIR}/lib/firmware/edid/"
exit 0
