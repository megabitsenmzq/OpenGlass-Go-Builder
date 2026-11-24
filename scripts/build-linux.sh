#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

PROJECT_ROOT=$1
WORKSPACE=$2
shift 2
# shellcheck source=../versions.lock
source "$PROJECT_ROOT/versions.lock"

CLEAN=0
COMPRESS=0
APPS_ONLY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) CLEAN=1 ;;
        --compress) COMPRESS=1 ;;
        --apps-only) APPS_ONLY=1 ;;
        *) echo "Unknown build-linux option: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "The verified application build requires an ARM64 Linux host/VM." >&2; exit 1 ;;
esac
[ -n "$WORKSPACE" ] && [ "$WORKSPACE" != / ] && [ "$WORKSPACE" != "$HOME" ] || {
    echo "Unsafe build workspace: $WORKSPACE" >&2
    exit 1
}
if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi
HOST_PACKAGES=(git debootstrap debian-archive-keyring rsync xz-utils curl ca-certificates)
MISSING_PACKAGES=()
for package in "${HOST_PACKAGES[@]}"; do
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'ok installed' || \
        MISSING_PACKAGES+=("$package")
done
if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
    command -v apt-get >/dev/null 2>&1 || {
        echo "Install these host packages first: ${MISSING_PACKAGES[*]}" >&2
        exit 1
    }
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
fi

ARMBIAN_DIR="$WORKSPACE/armbian-build"
CACHE_DIR="$WORKSPACE/cache"
CHROOT_DIR="$WORKSPACE/trixie-chroot"
DIST_DIR="$WORKSPACE/dist"
STATE_FILE="$WORKSPACE/build-state.env"
BUILD_LOG="$WORKSPACE/build.log"
BUILD_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_MODE=full
[ "$APPS_ONLY" -eq 0 ] || BUILD_MODE=apps-only

write_state() {
    local stage=$1
    local reason=${2:-}
    mkdir -p "$WORKSPACE"
    printf 'BUILD_PID=%q\nBUILD_STAGE=%q\nBUILD_STARTED=%q\nBUILD_OUTPUT=%q\nBUILD_MODE=%q\nBUILD_ERROR=%q\n' \
        "$$" "$stage" "$BUILD_STARTED" "$DIST_DIR" "$BUILD_MODE" "$reason" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

find_armbian_image() {
    local image_dir="$ARMBIAN_DIR/output/images"
    local version_file="$ARMBIAN_DIR/VERSION"
    if [ -f "$version_file" ]; then
        local armbian_version
        armbian_version=$(tr -d '[:space:]' < "$version_file")
        local candidate="$image_dir/Armbian-unofficial_${armbian_version}_Lookingglassgo_${DEBIAN_RELEASE}_current_${KERNEL_VERSION}_minimal.img"
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    local matches=()
    shopt -s nullglob
    matches=("$image_dir"/Armbian*_Lookingglassgo_"${DEBIAN_RELEASE}"_current_"${KERNEL_VERSION}"_minimal.img)
    shopt -u nullglob
    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s\n' "${matches[0]}"
        return 0
    fi
    return 1
}

on_exit() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        write_state failed "exit status $status; see build.log"
    fi
    exit "$status"
}
trap on_exit EXIT
exec > >(tee "$BUILD_LOG") 2>&1
write_state building

if [ "$CLEAN" -eq 1 ]; then
    "${SUDO[@]}" rm -rf "$ARMBIAN_DIR" "$CACHE_DIR" "$CHROOT_DIR" "$DIST_DIR"
fi
mkdir -p "$WORKSPACE" "$CACHE_DIR" "$DIST_DIR"
DOWNLOAD_DIR="$CACHE_DIR/downloads"
bash "$PROJECT_ROOT/scripts/fetch-deps.sh" "$PROJECT_ROOT" "$DOWNLOAD_DIR"
(
    cd "$PROJECT_ROOT"
    sha256sum -c third_party/blobs.sha256
)

ARMBIAN_IMAGE=
if [ "$APPS_ONLY" -eq 1 ]; then
    ARMBIAN_IMAGE=$(find_armbian_image) || {
        echo "No existing full image for --apps-only in $ARMBIAN_DIR/output/images" >&2
        exit 1
    }
else
    "${SUDO[@]}" rm -rf "$ARMBIAN_DIR"
    git clone --filter=blob:none "$ARMBIAN_REPOSITORY" "$ARMBIAN_DIR"
    git -C "$ARMBIAN_DIR" checkout --detach "$ARMBIAN_COMMIT"
    test "$(git -C "$ARMBIAN_DIR" rev-parse HEAD)" = "$ARMBIAN_COMMIT"
    ln -s "$CACHE_DIR" "$ARMBIAN_DIR/cache"
    cp -a "$PROJECT_ROOT/source/." "$ARMBIAN_DIR/"

    rm -f "$ARMBIAN_DIR/patch/kernel/archive/sunxi-6.18/patches.armbian/drv-rtc-pcf8563-pass-driver-data-to-irq-handler.patch"
    sed -i '\#drv-rtc-pcf8563-pass-driver-data-to-irq-handler.patch#d' \
        "$ARMBIAN_DIR/patch/kernel/archive/sunxi-6.18/series.conf"
fi

install -m 0755 "$DOWNLOAD_DIR/dufs" "$ARMBIAN_DIR/packages/blobs/lkg/dufs"
install -m 0644 "$DOWNLOAD_DIR/rtl8723ds_fw.bin" \
    "$ARMBIAN_DIR/packages/blobs/lkg/rtl8723ds_fw.bin"
install -m 0644 "$DOWNLOAD_DIR/rtl8723ds_config.bin" \
    "$ARMBIAN_DIR/packages/blobs/lkg/rtl8723ds_config.bin"

bash "$PROJECT_ROOT/scripts/build-apps.sh" "$PROJECT_ROOT" "$CHROOT_DIR" \
    "$ARMBIAN_DIR/packages/blobs/lkg"

if [ "$APPS_ONLY" -eq 0 ]; then
    mkdir -p "$ARMBIAN_DIR/userpatches"
    cat > "$ARMBIAN_DIR/userpatches/lookingglass-go-versions.conf" <<EOF
LKG_KERNEL_COMMIT="$KERNEL_COMMIT"
LKG_ATF_TAG="$ATF_TAG"
LKG_UBOOT_TAG="$UBOOT_TAG"
LKG_IMAGE_VERSION="$IMAGE_VERSION"
EOF
    cd "$ARMBIAN_DIR"
    ./compile.sh build \
        BOARD=lookingglassgo \
        BRANCH=current \
        RELEASE="$DEBIAN_RELEASE" \
        BUILD_MINIMAL=yes \
        BUILD_DESKTOP=no \
        KERNEL_CONFIGURE=no \
        KERNEL_BTF=no \
        FIXED_IMAGE_SIZE="$IMAGE_SIZE_MIB" \
        COMPRESS_OUTPUTIMAGE=sha \
        INCLUDE_HOME_DIR=yes
    ARMBIAN_IMAGE=$(find_armbian_image) || {
        echo "Expected image was not generated in $ARMBIAN_DIR/output/images" >&2
        exit 1
    }
fi

ARMBIAN_INFO="${ARMBIAN_IMAGE%.img}.txt"
[ -f "$ARMBIAN_IMAGE" ] || { echo "Expected image was not generated: $ARMBIAN_IMAGE" >&2; exit 1; }
"${SUDO[@]}" rm -f "$DIST_DIR"/*
IMAGE_NAME="$IMAGE_BASENAME.img"
if [ "$APPS_ONLY" -eq 1 ]; then
    cp "$ARMBIAN_IMAGE" "$DIST_DIR/$IMAGE_NAME"
    bash "$PROJECT_ROOT/scripts/update-image-apps.sh" "$DIST_DIR/$IMAGE_NAME" \
        "$ARMBIAN_DIR/packages/blobs/lkg" "$IMAGE_VERSION"
else
    cp "$ARMBIAN_IMAGE" "$DIST_DIR/$IMAGE_NAME"
fi
[ ! -f "$ARMBIAN_INFO" ] || cp "$ARMBIAN_INFO" "$DIST_DIR/$IMAGE_BASENAME.packages.txt"
cp "$ARMBIAN_DIR/packages/blobs/lkg/app-build-packages.txt" "$DIST_DIR/"

bash "$PROJECT_ROOT/scripts/verify-image.sh" "$DIST_DIR/$IMAGE_NAME" \
    "$ARMBIAN_DIR/packages/blobs/lkg" "$IMAGE_VERSION"

(
    cd "$PROJECT_ROOT"
    find apps \
        \( -name .git -o -name build -o -name .DS_Store -o -name '._*' -o -name '*.o' \) -prune \
        -o -type f -print0 | sort -z | xargs -0 sha256sum
) > "$DIST_DIR/app-sources.sha256"

REPO_COMMIT=${LKG_REPO_COMMIT:-}
if [ -z "$REPO_COMMIT" ]; then
    REPO_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || true)
fi
APPS_COMMIT=${LKG_APPS_COMMIT:-}
if [ -z "$APPS_COMMIT" ] && [ -e "$PROJECT_ROOT/apps/.git" ]; then
    APPS_COMMIT=$(git -C "$PROJECT_ROOT/apps" rev-parse HEAD 2>/dev/null || true)
fi

(
    cd "$DIST_DIR"
    sha256sum "$IMAGE_NAME" > "$IMAGE_NAME.sha256"
    {
        printf 'Image version: %s\n' "$IMAGE_VERSION"
        printf 'Built UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'Build mode: %s\n' "$BUILD_MODE"
        if [ -n "$REPO_COMMIT" ]; then
            printf 'OpenGlassGo commit: %s\n' "$REPO_COMMIT"
        fi
        printf 'Armbian repository: %s\n' "$ARMBIAN_REPOSITORY"
        printf 'Armbian commit: %s\n' "$ARMBIAN_COMMIT"
        printf 'Armbian firmware commit: %s\n' "$ARMBIAN_FIRMWARE_COMMIT"
        printf 'RTL8723DS firmware SHA-256: %s\n' "$RTL8723DS_FW_SHA256"
        printf 'RTL8723DS config SHA-256: %s\n' "$RTL8723DS_CONFIG_SHA256"
        printf 'Kernel repository: %s\n' "$KERNEL_REPOSITORY"
        printf 'Kernel commit: %s\n' "$KERNEL_COMMIT"
        printf 'Kernel version: %s\n' "$KERNEL_VERSION"
        printf 'ATF tag: %s\n' "$ATF_TAG"
        printf 'U-Boot tag: %s\n' "$UBOOT_TAG"
        printf 'U-Boot commit: %s\n' "$UBOOT_COMMIT"
        if [ -n "$APPS_COMMIT" ]; then
            printf 'Applications commit: %s\n' "$APPS_COMMIT"
        else
            printf 'Applications: apps source directory (no Git metadata)\n'
        fi
        printf 'dufs version: %s\n' "$DUFS_VERSION"
        printf 'dufs archive SHA-256: %s\n' "$DUFS_ARCHIVE_SHA256"
        printf 'dufs binary SHA-256: %s\n' "$DUFS_BINARY_SHA256"
        printf 'Debian release: %s\n' "$DEBIAN_RELEASE"
        printf 'Debian mirror: %s\n' "$DEBIAN_MIRROR"
        printf 'Image size MiB: %s\n' "$IMAGE_SIZE_MIB"
        printf 'Static image verification: passed\n'
        (
            cd "$ARMBIAN_DIR/packages/blobs/lkg"
            sha256sum lkg-menu lkg-player lkg-mcu
        )
    } > build-manifest.txt
)

if [ "$COMPRESS" -eq 1 ]; then
    xz --threads=0 -6 -k "$DIST_DIR/$IMAGE_NAME"
    (
        cd "$DIST_DIR"
        xz -t "$IMAGE_NAME.xz"
        sha256sum "$IMAGE_NAME.xz" > "$IMAGE_NAME.xz.sha256"
        sha256sum -c "$IMAGE_NAME.xz.sha256"
    )
fi

(cd "$DIST_DIR" && sha256sum -c "$IMAGE_NAME.sha256")
write_state complete
echo "Image and manifest generated in $DIST_DIR"
