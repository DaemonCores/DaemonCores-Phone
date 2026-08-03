#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# WIP — Work in progress. This helper script is part of the
# DaemonCores-Phone standard Halium initramfs and is under active
# development. The overlayfs setup, the tmpfs upper/work dir layout,
# and the bind-mount fallback are not yet validated against real
# devices. Expect breaking changes until the pipeline reaches a tagged
# milestone.
#
# overlay-mount.sh — Set up overlayfs mounts for vendor and system partitions.
#
# Description:
#   Mounts the Android vendor and system partitions read-only, then layers
#   a tmpfs-backed overlayfs on top so the Halium/Debian userspace can
#   write transiently to /vendor and /system without modifying the
#   underlying read-only Android partitions. The lower layer is the real
#   partition mount; the upper layer and work directory live in tmpfs so
#   they vanish on reboot (the Android partitions are never written to).
#
#   The script is generic: it takes the lower (real) directory and the
#   overlay mount point as arguments. It does not hardcode any device path
#   or partition label — the caller (init) supplies the resolved paths
#   after running detect-partitions.sh.
#
#   If the kernel lacks overlayfs support, the script falls back to a
#   plain read-only bind mount of the lower directory onto the target, so
#   the boot can proceed (without write capability) on kernels compiled
#   without CONFIG_OVERLAY_FS.
#
# Globals:
#   Reads:
#     OVERLAY_UPPER_DIR  Base directory for overlay upper/work dirs
#                        (default: /mnt/overlay). Created if missing.
#   Writes:
#     None beyond the requested mount.
#
# Arguments:
#   $1 = lower_dir   The real (read-only) source directory to overlay.
#   $2 = target_dir  The mount point where the overlay should appear.
#                    Created if missing (mkdir -p).
#
# Outputs:
#   stderr: diagnostic lines prefixed with [overlay-mount].
#
# Returns:
#   0  Overlay (or fallback bind mount) established successfully.
#   1  Usage error (wrong number of arguments).
#   2  lower_dir does not exist or is not a directory.
#   3  target_dir could not be created.
#   4  The lower directory could not be mounted read-only (when not
#      already mounted).
#   5  The overlayfs mount failed AND the bind-mount fallback failed.
#
# Idempotence:
#   If target_dir is already a mount point, the script reports it and
#   returns 0 without re-mounting. Safe to re-run.

set -u

OVERLAY_UPPER_BASE="${OVERLAY_UPPER_DIR:-/mnt/overlay}"

log() {
    printf '[overlay-mount] %s\n' "$*" >&2
}

err() {
    printf '[overlay-mount] ERROR: %s\n' "$*" >&2
}

if [ $# -ne 2 ]; then
    err "usage: overlay-mount.sh <lower_dir> <target_dir>"
    exit 1
fi

LOWER="$1"
TARGET="$2"

if [ ! -d "$LOWER" ]; then
    err "lower_dir is not a directory: $LOWER"
    exit 2
fi

# Create the target mount point idempotently.
if [ ! -d "$TARGET" ]; then
    if ! mkdir -p "$TARGET" 2>/dev/null; then
        err "failed to create target mount point: $TARGET"
        exit 3
    fi
fi

# If the target is already a mount point, assume the overlay is already in
# place and return success. Detecting a mount point portably: /proc/mounts
# contains an entry whose second field is the target.
if [ -r /proc/mounts ]; then
    if awk -v t="$TARGET" '$2 == t {found=1} END {exit found ? 0 : 1}' /proc/mounts 2>/dev/null; then
        log "target already mounted: $TARGET (skipping)"
        exit 0
    fi
fi

# Mount the lower directory read-only if it is not already mounted. We
# probe /proc/mounts for the lower path; if absent, we bind-mount it onto
# itself read-only so the overlay lowerdir resolves.
LOWER_MOUNTED=0
if [ -r /proc/mounts ]; then
    if awk -v l="$LOWER" '$2 == l {found=1} END {exit found ? 0 : 1}' /proc/mounts 2>/dev/null; then
        LOWER_MOUNTED=1
    fi
fi
if [ "$LOWER_MOUNTED" -eq 0 ]; then
    # Some init environments expect the real partition to already be
    # mounted by the time we overlay it. We attempt a read-only bind mount
    # of the lower dir onto itself so overlayfs can use it as lowerdir.
    if mount --bind "$LOWER" "$LOWER" 2>/dev/null; then
        mount -o remount,ro,bind "$LOWER" 2>/dev/null || true
        log "lower dir bind-mounted read-only: $LOWER"
    else
        # If the bind mount fails, the lower dir may already be a
        # filesystem root (e.g. an already-mounted partition). Proceed;
        # overlayfs can use it directly.
        log "lower dir not bind-mounted (using as-is): $LOWER"
    fi
fi

# Prepare the overlay upper and work directories in tmpfs-backed /tmp or
# the configured base. Use /tmp when available (typical initramfs tmpfs)
# so overlay writes never hit persistent storage.
OVERLAY_ROOT="$OVERLAY_UPPER_BASE"
if [ ! -d "$OVERLAY_ROOT" ]; then
    mkdir -p "$OVERLAY_ROOT" 2>/dev/null || OVERLAY_ROOT="/tmp/overlay"
fi
if [ ! -d "$OVERLAY_ROOT" ]; then
    mkdir -p "$OVERLAY_ROOT" 2>/dev/null || {
        err "failed to create overlay upper base: $OVERLAY_ROOT"
        exit 3
    }
fi

# Derive a per-target suffix so multiple overlays do not collide.
# Sanitise the target path into a directory-name-safe suffix.
SUFFIX=$(printf '%s' "$TARGET" | tr -c '[:alnum:]' '_')
UPPER="$OVERLAY_ROOT/upper$SUFFIX"
WORK="$OVERLAY_ROOT/work$SUFFIX"
mkdir -p "$UPPER" "$WORK" 2>/dev/null || {
    err "failed to create overlay upper/work dirs under $OVERLAY_ROOT"
    exit 3
}

# Attempt the overlayfs mount. Use lowerdir + upperdir + workdir. The
# mount is read-write (the upper layer is tmpfs, so writes are transient).
if mount -t overlay overlay \
        -o "lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK" \
        "$TARGET" 2>/dev/null; then
    log "overlay mounted: $TARGET (lower=$LOWER upper=$UPPER work=$WORK)"
    exit 0
fi

# Fallback: overlayfs not supported (CONFIG_OVERLAY_FS missing) or mount
# failed for another reason. Bind-mount the lower dir read-only onto the
# target so the boot can proceed without write capability.
log "overlayfs mount failed — falling back to read-only bind mount"
if mount --bind "$LOWER" "$TARGET" 2>/dev/null; then
    mount -o remount,ro,bind "$TARGET" 2>/dev/null || true
    log "bind-mounted read-only (no write capability): $TARGET -> $LOWER"
    exit 0
fi

err "both overlayfs and bind-mount fallback failed for $TARGET"
exit 5