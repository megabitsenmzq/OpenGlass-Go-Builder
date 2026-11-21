#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

PROJECT_ROOT=$1
DOWNLOAD_DIR=$2
# shellcheck source=../versions.lock
source "$PROJECT_ROOT/versions.lock"

mkdir -p "$DOWNLOAD_DIR"

download() {
    local url=$1
    local destination=$2
    local sha256=$3
    local temporary="$destination.tmp.$$"

    if [ -f "$destination" ] && \
        printf '%s  %s\n' "$sha256" "$destination" | sha256sum -c --status; then
        echo "Using cached $(basename "$destination")"
        return
    fi

    rm -f "$destination" "$temporary"
    echo "Downloading $url"
    curl --fail --location --retry 3 --output "$temporary" "$url"
    printf '%s  %s\n' "$sha256" "$temporary" | sha256sum -c -
    mv "$temporary" "$destination"
}

DUFS_ARCHIVE="$DOWNLOAD_DIR/dufs-v$DUFS_VERSION-aarch64-unknown-linux-musl.tar.gz"
download "${LKG_DUFS_ARCHIVE_URL:-$DUFS_ARCHIVE_URL}" \
    "$DUFS_ARCHIVE" "$DUFS_ARCHIVE_SHA256"
download "${LKG_RTL8723DS_FW_URL:-$RTL8723DS_FW_URL}" "$DOWNLOAD_DIR/rtl8723ds_fw.bin" \
    "$RTL8723DS_FW_SHA256"
download "${LKG_RTL8723DS_CONFIG_URL:-$RTL8723DS_CONFIG_URL}" "$DOWNLOAD_DIR/rtl8723ds_config.bin" \
    "$RTL8723DS_CONFIG_SHA256"

EXTRACT_DIR="$DOWNLOAD_DIR/.dufs-extract.$$"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
tar -xzf "$DUFS_ARCHIVE" -C "$EXTRACT_DIR" dufs
printf '%s  %s\n' "$DUFS_BINARY_SHA256" "$EXTRACT_DIR/dufs" | sha256sum -c -
install -m 0755 "$EXTRACT_DIR/dufs" "$DOWNLOAD_DIR/dufs.tmp.$$"
mv "$DOWNLOAD_DIR/dufs.tmp.$$" "$DOWNLOAD_DIR/dufs"
rm -rf "$EXTRACT_DIR"
trap - EXIT
