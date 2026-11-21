setenv load_addr "0x45000000"
setenv overlay_error "false"
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "7"
setenv rootfstype "ext4"
setenv console "both"
setenv fdtfile "allwinner/sun50i-h618-lookingglass-nano.dtb"
setenv fdtdir "${prefix}dtb"

if gpio input PC8; then
	setenv screen_orientation "screen_orientation=landscape"
else
	setenv screen_orientation "screen_orientation=portrait"
fi

if test -e ${devtype} ${devnum} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${console}" = "display" || test "${console}" = "both"; then
	setenv consoleargs "console=ttyS0,115200 console=tty1"
else
	setenv consoleargs "console=ttyS0,115200"
fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} earlycon consoleblank=0 loglevel=${verbosity} systemd.show_status=true fbcon=font:TER16x32 drm.edid_firmware=edid/LCD_0598AUOQHM01.bin video=HDMI-A-1:1440x2560@60e ${screen_orientation} cma=256M ${extraargs} ${extraboardargs}"

load ${devtype} ${devnum} ${fdt_addr_r} ${fdtdir}/${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 65536

for overlay_file in ${overlays}; do
	setenv overlay_found "false"
	for overlay_prefix_item in ${overlay_prefix}; do
		if test "${overlay_found}" = "false" && test -e ${devtype} ${devnum} ${fdtdir}/overlay/${overlay_prefix_item}-${overlay_file}.dtbo && load ${devtype} ${devnum} ${load_addr} ${fdtdir}/overlay/${overlay_prefix_item}-${overlay_file}.dtbo; then
			setenv overlay_found "true"
			fdt apply ${load_addr} || setenv overlay_error "true"
		fi
	done
done

if test "${overlay_error}" = "true"; then
	load ${devtype} ${devnum} ${fdt_addr_r} ${fdtdir}/${fdtfile}
fi

load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
