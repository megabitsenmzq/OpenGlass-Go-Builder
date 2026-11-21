# Third-party inputs, packages, and licenses

[`../versions.lock`](../versions.lock) records pinned upstream source revisions, download URLs, and SHA-256 checksums. [`../scripts/fetch-deps.sh`](../scripts/fetch-deps.sh) verifies downloaded archives before they enter the build. [`blobs.sha256`](./blobs.sha256) covers the small hardware data stored in this repository.

## Core components, bootloader, kernel, firmware, and apps

| Component | Version / Source | License |
| --- | --- | --- |
| OpenGlass Go image builder (this repository) | Build scripts, board config, BSP helpers, systemd units, original patches | GPL-3.0-or-later |
| OpenGlass Go Apps (`apps/` submodule) | `lkg-menu`, `lkg-player`, `lkg-mcu` ([OpenGlass-Go-Apps](https://github.com/megabitsenmzq/OpenGlass-Go-Apps)) | GPL-3.0-or-later |
| Armbian build framework | [armbian/build](https://github.com/armbian/build) (commit pinned in `versions.lock`) | GPL-2.0 |
| Linux kernel | `6.18.63` (kernel.org stable, commit pinned in `versions.lock`) | GPL-2.0 (with `Linux-syscall-note`) |
| Board Device Tree (`sun50i-h618-lookingglass-nano.dts`) | Allwinner H618 Looking Glass Go DTS | GPL-2.0-or-later OR MIT |
| Panel EDID (`LCD_0598AUOQHM01.bin`) | Extracted from Looking Glass Go GPL compliance patch (`9010-drm_edid_nano_portrait.patch` / `drivers/gpu/drm/drm_edid_load.c` in [lkg_go_buildroot_compliance_kit](https://github.com/Looking-Glass/lkg_go_buildroot_compliance_kit)) | GPL-2.0 |
| Visual calibration template (`visual.json`) | Sanitized display geometry template populated at boot from the device STM32 MCU | GPL-3.0-or-later |
| U-Boot | `v2026.10` ([u-boot/u-boot](https://github.com/u-boot/u-boot)) | GPL-2.0-or-later |
| ARM Trusted Firmware (TF-A / ATF) | `lts-v2.14.11` | BSD-3-Clause |
| Debian GNU/Linux (`trixie`) | Base OS and packaged userspace (`deb.debian.org`) | Various DFSG-free licenses (see `/usr/share/doc/*/copyright` in image) |
| `dufs` | `v0.47.0` ([sigoden/dufs](https://github.com/sigoden/dufs/releases/tag/v0.47.0), downloaded at build time) | MIT OR Apache-2.0 (distributed under MIT; notice at `/usr/share/doc/dufs/copyright`) |
| RTL8723DS Bluetooth firmware & config | [armbian/firmware](https://github.com/armbian/firmware) (commit and SHA-256 values in `versions.lock`, downloaded at build time) | Proprietary / Redistributable firmware (Realtek) |
| Lima *(macOS build host only, not in image)* | [lima-vm/lima](https://github.com/lima-vm/lima) | Apache-2.0 |

## Pre-installed Debian packages (`PACKAGE_LIST_BOARD`)

In addition to the minimal Armbian / Debian `trixie` base system, [`../source/config/boards/lookingglassgo.wip`](../source/config/boards/lookingglassgo.wip) explicitly installs the following packages:

### System, networking, storage, and security

| Package | Role | License |
| --- | --- | --- |
| `kbd` | Console fonts and keyboard utilities | GPL-2.0-or-later |
| `wpasupplicant` | Wi-Fi WPA/WPA2/WPA3 supplicant | BSD-3-Clause |
| `sudo` | Privilege escalation for controlled menu/Wi-Fi helpers | ISC |
| `python3-yaml` | YAML parser (`PyYAML`) used by `lkg-wifi` | MIT |
| `openssh-server` | SSH server | OpenSSH (BSD/ISC-style) |
| `avahi-daemon` | mDNS / DNS-SD responder (`lkg.local`) | LGPL-2.1-or-later |
| `dbus` | System and session IPC message bus | AFL-2.1 OR GPL-2.0-or-later |
| `polkitd` | Authorization daemon (power-off rule for `lkg`) | LGPL-2.0-or-later |
| `openssl` | Runtime TLS/RSA key generation for `wayvnc` | Apache-2.0 |
| `exfatprogs` | exFAT formatting and checking for `LKG_DATA` | GPL-2.0 |
| `overlayroot` | Read-only rootfs with tmpfs overlay (`cloud-initramfs-tools`) | GPL-3.0-or-later |
| `busybox-static` | Static utility binary for recovery/initramfs support | GPL-2.0 |

### Wayland desktop (`Desktop (Sway)`), VNC, and GUI utilities

| Package | Role | License |
| --- | --- | --- |
| `sway` | Wayland tiling compositor | MIT |
| `seatd` | Seat management daemon | MIT |
| `wayvnc` | VNC server for the headless `1280×720` display | ISC |
| `foot` | Wayland terminal emulator | MIT |
| `fuzzel` | Application launcher and dmenu popup | MIT |
| `waybar` | Status bar | MIT |
| `mako-notifier` | Wayland notification daemon | MIT |
| `libnotify-bin` | `notify-send` CLI for desktop notifications | LGPL-2.1-or-later |
| `wl-clipboard` | Wayland clipboard CLI utilities | GPL-3.0-or-later |
| `grim` | Wayland screenshot tool | MIT |
| `slurp` | Wayland region selector | MIT |
| `imv` | Wayland image viewer | MIT |
| `thunar` | Graphical file manager | GPL-2.0-or-later |
| `thunar-archive-plugin` | Archive integration plugin for Thunar | GPL-2.0-or-later |
| `xarchiver` | Graphical archive manager | GPL-2.0-or-later |
| `mousepad` | Graphical text editor | GPL-2.0-or-later |
| `adwaita-icon-theme` | Desktop icon and cursor theme | LGPL-3.0-or-later OR CC-BY-SA-3.0 |
| `sound-theme-freedesktop` | System audio feedback sounds | GPL-2.0-or-later / CC-BY-3.0 / CC-BY-SA-3.0 |

### Terminal utilities and archive tools

| Package | Role | License |
| --- | --- | --- |
| `micro` | Terminal text editor | MIT |
| `ranger` | Console file manager | GPL-3.0-or-later |
| `mc` | Midnight Commander console file manager | GPL-3.0-or-later |
| `htop` | Interactive process monitor | GPL-2.0-or-later |
| `pulsemixer` | Terminal audio mixer | MIT |
| `file` | File type identification utility | BSD-2-Clause |
| `xdg-utils` | Desktop integration helpers | MIT |
| `unzip` | ZIP archive extractor | Info-ZIP (BSD-like) |
| `7zip` | 7z/multi-format archiver (DFSG Debian build) | LGPL-2.1-or-later / BSD-3-Clause |
| `bzip2` | bzip2 compression utility | bzip2-1.0.6 (BSD-like) |
| `xz-utils` | XZ compression utility | 0BSD / GPL-2.0-or-later / LGPL-2.1-or-later |

### Audio, video, and multimedia

| Package | Role | License |
| --- | --- | --- |
| `ffmpeg` | Media probing, preprocessing, and transcoding | GPL-2.0-or-later / LGPL-2.1-or-later |
| `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-base-apps` | Core GStreamer plugins and `gst-play-1.0` | LGPL-2.1-or-later |
| `gstreamer1.0-plugins-good` | Standard GStreamer media plugins | LGPL-2.1-or-later |
| `gstreamer1.0-plugins-bad` | Additional plugins including `v4l2codecs` (Cedrus HW decode) | LGPL-2.1-or-later (some plugins GPL-2.0-or-later) |
| `gstreamer1.0-libav` | FFmpeg-backed GStreamer decoders (e.g., `avdec_aac`) | LGPL-2.1-or-later / GPL-2.0-or-later |
| `gstreamer1.0-pipewire` | PipeWire GStreamer sink/source | MIT |
| `gstreamer1.0-tools` | `gst-inspect-1.0` and `gst-launch-1.0` | LGPL-2.1-or-later |
| `pipewire-audio` | PipeWire audio server stack | MIT |
| `wireplumber` | PipeWire session and policy manager | MIT |

### Graphics, image codecs, fonts, and core runtime libraries

| Package | Role | License |
| --- | --- | --- |
| `libdrm2` | Direct Rendering Manager userspace library | MIT |
| `libgbm1`, `libegl1`, `libgles2` | Mesa GBM and libglvnd EGL / OpenGL ES runtime | MIT (with BSD/SGI-B components) |
| `libpng16-16t64` | PNG codec library | libpng-2.0 |
| `libjpeg62-turbo` | JPEG codec library (`libjpeg-turbo`) | IJG / BSD-3-Clause / Zlib |
| `libheif1` | HEIC/HEIF spatial photo decoding (with `libde265` plugin) | LGPL-3.0-or-later |
| `libqrencode4` | QR code generation for file-sharing UI | LGPL-2.1-or-later |
| `libglib2.0-0t64` | GLib core utility library | LGPL-2.1-or-later |
| `zlib1g` | Compression library | Zlib |
| `libfreetype6` | Font rendering library | FTL OR GPL-2.0-or-later |
| `fonts-dejavu-core` | Latin UI/console fonts | Bitstream Vera / Arev (permissive) |
| `fonts-wqy-microhei` | CJK font for Sway/Waybar/GTK | Apache-2.0 OR GPL-3.0 (with font exception) |

## Notes and redistribution

- The exact full list of installed Debian packages (including transitive dependencies and versions) is written to `dist/OpenGlassGo-trixie-current-6.18.63-overlay-data.packages.txt` on every build, and build-chroot packages used to compile `apps/` ([`../scripts/build-apps.sh`](../scripts/build-apps.sh)) are recorded in `dist/app-build-packages.txt`.
- Authoritative copyright and license texts for every installed Debian package are located under `/usr/share/doc/<package>/copyright` inside the generated image (and `/usr/share/doc/dufs/copyright` for `dufs`).
- Before a public binary release, confirm the redistribution terms for the Realtek Bluetooth firmware downloaded during the build, and include all applicable Armbian, Linux, U-Boot, `dufs`, and userspace-package license notices and corresponding source offers.
