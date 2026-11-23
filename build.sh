#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=versions.lock
source "$PROJECT_ROOT/versions.lock"

VM_NAME=${LKG_VM_NAME:-lkg-build-2604}
CLEAN=0
COMPRESS=0
APPS_ONLY=0
RESUME=0

usage() {
    cat <<'EOF'
Usage: ./build.sh [--clean] [--compress] [--apps-only] [--resume] [--vm NAME]

  --clean      Remove the VM build workspace, cached sources and Trixie chroot first.
  --compress   Also create an xz-compressed release image and checksum.
  --apps-only  Rebuild only menu/player/MCU and update an existing full image.
  --resume     Wait for an existing VM build and collect it without starting a new build.
  --vm NAME    Lima instance name on macOS (default: lkg-build-2604).

The script never writes an SD card. Flash the verified image with balenaEtcher.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean) CLEAN=1 ;;
        --compress) COMPRESS=1 ;;
        --apps-only) APPS_ONLY=1 ;;
        --resume) RESUME=1 ;;
        --vm)
            [ "$#" -ge 2 ] || { echo "--vm requires a name" >&2; exit 2; }
            VM_NAME=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[ "$RESUME" -eq 0 ] || [ "$CLEAN" -eq 0 ] || {
    echo "--resume cannot be combined with --clean" >&2
    exit 2
}
[ "$RESUME" -eq 0 ] || [ "$APPS_ONLY" -eq 0 ] || {
    echo "--resume cannot be combined with --apps-only" >&2
    exit 2
}
[ "$RESUME" -eq 0 ] || [ "$COMPRESS" -eq 0 ] || {
    echo "--resume cannot be combined with --compress" >&2
    exit 2
}
[ "$CLEAN" -eq 0 ] || [ "$APPS_ONLY" -eq 0 ] || {
    echo "--clean cannot be combined with --apps-only" >&2
    exit 2
}
if [ -f "$PROJECT_ROOT/.gitmodules" ] && [ -e "$PROJECT_ROOT/.git" ] && [ ! -e "$PROJECT_ROOT/apps/.git" ]; then
    git -C "$PROJECT_ROOT" submodule update --init --recursive apps
fi

if [ -z "${LKG_REPO_COMMIT:-}" ] && git -C "$PROJECT_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    LKG_REPO_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
    export LKG_REPO_COMMIT
fi
if [ -z "${LKG_APPS_COMMIT:-}" ] && [ -e "$PROJECT_ROOT/apps/.git" ] && \
    git -C "$PROJECT_ROOT/apps" rev-parse HEAD >/dev/null 2>&1; then
    LKG_APPS_COMMIT=$(git -C "$PROJECT_ROOT/apps" rev-parse HEAD)
    export LKG_APPS_COMMIT
fi

mkdir -p "$PROJECT_ROOT/dist"
BUILD_LOG="$PROJECT_ROOT/dist/build.log"
FLAGS=()
[ "$CLEAN" -eq 0 ] || FLAGS+=(--clean)
[ "$COMPRESS" -eq 0 ] || FLAGS+=(--compress)
[ "$APPS_ONLY" -eq 0 ] || FLAGS+=(--apps-only)

run_linux_build() {
    local project=$1
    local workspace=$2
    shift 2
    bash "$project/scripts/build-linux.sh" "$project" "$workspace" "$@"
}

collect_local_output() {
    local source_dir=$1
    local log_file=$2
    local staging="$PROJECT_ROOT/dist.new.$$"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -a "$source_dir/." "$staging/"
    cp "$log_file" "$staging/build.log"
    rm -rf "$PROJECT_ROOT/dist"
    mv "$staging" "$PROJECT_ROOT/dist"
}

resume_local_build() {
    local workspace=$1
    local state="$workspace/build-state.env"
    [ -f "$state" ] || { echo "No resumable build state found: $state" >&2; exit 1; }
    # shellcheck disable=SC1090
    source "$state"
    if [ "$BUILD_STAGE" = complete ]; then
        collect_local_output "$BUILD_OUTPUT" "$workspace/build.log"
        return
    fi
    [ "$BUILD_STAGE" != failed ] || {
        echo "Previous build failed: ${BUILD_ERROR:-see build.log}" >&2
        exit 1
    }
    while kill -0 "$BUILD_PID" 2>/dev/null; do
        sleep 10
    done
    # shellcheck disable=SC1090
    source "$state"
    [ "$BUILD_STAGE" = complete ] || {
        echo "Build ended without a complete result: ${BUILD_ERROR:-$BUILD_STAGE}" >&2
        exit 1
    }
    collect_local_output "$BUILD_OUTPUT" "$workspace/build.log"
}

case "$(uname -s)" in
    Linux)
        WORKSPACE=${LKG_BUILD_WORKSPACE:-"$HOME/lkg-image"}
        mkdir -p "$WORKSPACE"
        if [ "$RESUME" -eq 1 ]; then
            resume_local_build "$WORKSPACE"
        else
            run_linux_build "$PROJECT_ROOT" "$WORKSPACE" ${FLAGS[@]+"${FLAGS[@]}"} 2>&1 | tee "$BUILD_LOG"
            collect_local_output "$WORKSPACE/dist" "$WORKSPACE/build.log"
        fi
        ;;
    Darwin)
        if ! command -v limactl >/dev/null 2>&1; then
            echo "Lima is required on macOS. Install it with: brew install lima" >&2
            exit 1
        fi
        if ! limactl list | awk 'NR > 1 {print $1}' | grep -Fxq "$VM_NAME"; then
            [ "$RESUME" -eq 0 ] || { echo "VM does not exist: $VM_NAME" >&2; exit 1; }
            VM_TYPE=qemu
            [ "$(uname -m)" != "arm64" ] || VM_TYPE=vz
            limactl start --name="$VM_NAME" --arch=aarch64 --vm-type="$VM_TYPE" \
                --mount-none "$PROJECT_ROOT/lima/lkg-build.yaml"
        elif ! limactl list | awk -v name="$VM_NAME" 'NR > 1 && $1 == name {print $2}' | grep -qx Running; then
            limactl start "$VM_NAME"
        fi
        if ! limactl shell "$VM_NAME" -- true >/dev/null 2>&1; then
            echo "Unable to execute commands in VM $VM_NAME; check Lima and SSH." >&2
            exit 1
        fi

        REMOTE_HOME=$(limactl shell "$VM_NAME" -- bash -lc 'printf %s "$HOME"')
        REMOTE_WORKSPACE="$REMOTE_HOME/lkg-image"
        REMOTE_PROJECT="$REMOTE_WORKSPACE/project"
        if [ "$RESUME" -eq 1 ]; then
            STATE_FILE="$REMOTE_WORKSPACE/build-state.env"
            if ! limactl shell "$VM_NAME" -- test -f "$STATE_FILE"; then
                echo "No resumable build state found in $VM_NAME:$STATE_FILE" >&2
                exit 1
            fi
            # shellcheck disable=SC1090
            eval "$(limactl shell "$VM_NAME" -- cat "$STATE_FILE")"
            if [ "$BUILD_STAGE" = failed ]; then
                echo "Previous build failed: ${BUILD_ERROR:-see build.log}" >&2
                exit 1
            fi
            if [ "$BUILD_STAGE" != complete ]; then
                while limactl shell "$VM_NAME" -- kill -0 "$BUILD_PID" 2>/dev/null; do
                    sleep 10
                done
                # shellcheck disable=SC1090
                eval "$(limactl shell "$VM_NAME" -- cat "$STATE_FILE")"
            fi
            [ "$BUILD_STAGE" = complete ] || {
                echo "Build ended without a complete result: ${BUILD_ERROR:-$BUILD_STAGE}" >&2
                exit 1
            }
            STAGING="$PROJECT_ROOT/dist.new.$$"
            rm -rf "$STAGING"
            limactl copy -r "$VM_NAME:$BUILD_OUTPUT" "$STAGING"
            limactl copy "$VM_NAME:$REMOTE_WORKSPACE/build.log" "$STAGING/build.log"
            rm -rf "$PROJECT_ROOT/dist"
            mv "$STAGING" "$PROJECT_ROOT/dist"
        else
            limactl shell "$VM_NAME" -- rm -rf "$REMOTE_PROJECT"
            limactl shell "$VM_NAME" -- mkdir -p "$REMOTE_PROJECT"
            COPYFILE_DISABLE=1 tar -cf - \
                --exclude='.DS_Store' --exclude='._*' \
                -C "$PROJECT_ROOT" source scripts third_party versions.lock | \
                limactl shell "$VM_NAME" -- tar -xf - -C "$REMOTE_PROJECT"
            COPYFILE_DISABLE=1 tar -cf - \
                --exclude='.git' --exclude='.DS_Store' --exclude='._*' \
                --exclude='*.o' --exclude='build' \
                -C "$PROJECT_ROOT" apps | \
                limactl shell "$VM_NAME" -- tar -xf - -C "$REMOTE_PROJECT"

            REMOTE_ENV=()
            for var in \
                LKG_DUFS_ARCHIVE_URL \
                LKG_RTL8723DS_FW_URL LKG_RTL8723DS_CONFIG_URL \
                LKG_USER_PASSWORD LKG_ROOT_PASSWORD \
                LKG_APPS_COMMIT LKG_REPO_COMMIT; do
                if [ -n "${!var:-}" ]; then
                    REMOTE_ENV+=("$var=${!var}")
                fi
            done

            set +e
            limactl shell "$VM_NAME" -- env ${REMOTE_ENV[@]+"${REMOTE_ENV[@]}"} bash \
                "$REMOTE_PROJECT/scripts/build-linux.sh" "$REMOTE_PROJECT" "$REMOTE_WORKSPACE" \
                ${FLAGS[@]+"${FLAGS[@]}"} 2>&1 | tee "$BUILD_LOG"
            BUILD_STATUS=${PIPESTATUS[0]}
            set -e
            if [ "$BUILD_STATUS" -ne 0 ]; then
                echo "Build failed; full log: $BUILD_LOG" >&2
                exit "$BUILD_STATUS"
            fi

            STAGING="$PROJECT_ROOT/dist.new.$$"
            rm -rf "$STAGING"
            limactl copy -r "$VM_NAME:$REMOTE_WORKSPACE/dist" "$STAGING"
            cp "$BUILD_LOG" "$STAGING/build.log"
            rm -rf "$PROJECT_ROOT/dist"
            mv "$STAGING" "$PROJECT_ROOT/dist"
        fi
        ;;
    *)
        echo "Unsupported host: $(uname -s). Use Linux or macOS with Lima." >&2
        exit 1
        ;;
esac

echo
echo "Build outputs: $PROJECT_ROOT/dist"
ls -lh "$PROJECT_ROOT/dist"
