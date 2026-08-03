#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# WIP — Work in progress. This helper script is part of the
# DaemonCores-Phone standard Halium initramfs and is under active
# development. The partition label set, the by-name directory probing,
# and the symlink resolution are not yet validated against the full
# device fleet. Expect breaking changes until the pipeline reaches a
# tagged milestone.
#
# detect-partitions.sh — Populate environment variables from /dev/block/by-name/.
#
# Description:
#   Scans the Android partition symlinks exposed under /dev/block/by-name/
#   (and the alternate /dev/block/bootdevice/by-name/ path used by some
#   Qualcomm vendor trees) and exports a set of SYS_* environment variables
#   pointing at the resolved block device for each standard Android
#   partition. The variables are emitted on stdout as shell-compatible
#   "KEY=value" assignments so a caller can eval them, and are also
#   exported into the current environment when the script is sourced.
#
#   The script is generic: it carries no hardcoded device codename, vendor,
#   or SoC name. It detects partitions purely by the well-known Android
#   by-name labels (system, vendor, userdata, boot, dtbo, recovery, cache,
#   metadata, persist, vendor_boot, super, init_boot). Unknown labels are
#   ignored.
#
# Globals:
#   Reads:
#     BY_NAME_DIR   Optional override for the by-name directory path.
#                   Defaults are probed in order: /dev/block/by-name then
#                   /dev/block/bootdevice/by-name.
#   Writes (exported when sourced, printed when executed):
#     SYS_SYSTEM, SYS_VENDOR, SYS_USERDATA, SYS_BOOT, SYS_DTBO,
#     SYS_RECOVERY, SYS_CACHE, SYS_METADATA, SYS_PERSIST,
#     SYS_VENDOR_BOOT, SYS_SUPER, SYS_INIT_BOOT
#     PARTITION_BY_NAME_DIR  The directory actually scanned.
#
# Arguments:
#   None.
#
# Outputs:
#   stdout: one "KEY=value" line per detected partition, shell-compatible
#           (safe to eval). When the script is executed directly, the same
#           lines are printed; when sourced, the variables are exported
#           and no output is produced unless the caller redirects.
#   stderr: diagnostic lines prefixed with [detect-partitions].
#
# Returns:
#   0  At least one standard partition was detected.
#   1  No by-name directory was found.
#   2  The by-name directory exists but no standard partition was
#      recognised.
#
# Idempotence:
#   Safe to re-run: the script only reads /dev and prints/exports
#   variables; it never mounts, writes, or modifies anything.

set -u

# Standard Android partition labels we care about. The list is deliberately
# broad: a given device exposes only a subset, and unknown labels are
# silently ignored. Order does not matter.
PARTITION_LABELS="system vendor userdata boot dtbo recovery cache metadata persist vendor_boot super init_boot"

# Map a partition label to the variable name we export.
label_to_var() {
    # $1 = label. Prints the variable name (e.g. "system" -> "SYS_SYSTEM").
    printf 'SYS_%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
}

# Find the by-name directory. Some vendor trees expose it under
# /dev/block/by-name/ (Android standard), others under
# /dev/block/bootdevice/by-name/ (Qualcomm-style). An explicit override via
# BY_NAME_DIR wins.
find_by_name_dir() {
    if [ -n "${BY_NAME_DIR:-}" ] && [ -d "$BY_NAME_DIR" ]; then
        printf '%s' "$BY_NAME_DIR"
        return 0
    fi
    for cand in /dev/block/by-name /dev/block/bootdevice/by-name; do
        if [ -d "$cand" ]; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

BY_NAME_DIR_RESOLVED=""
if ! BY_NAME_DIR_RESOLVED=$(find_by_name_dir); then
    printf '[detect-partitions] ERROR: no by-name directory found under /dev/block/by-name or /dev/block/bootdevice/by-name\n' >&2
    printf '[detect-partitions]        Set BY_NAME_DIR to override, or ensure /dev/block is populated (mdev/udev).\n' >&2
    exit 1
fi
printf '[detect-partitions] scanning: %s\n' "$BY_NAME_DIR_RESOLVED" >&2

# Resolve a by-name symlink to its real block device. Some by-name entries
# are symlinks (e.g. system -> /dev/block/mmcblk0p42); others are plain
# device nodes. We prefer readlink -f when available, fall back to the
# entry path itself.
resolve_link() {
    # $1 = full path under the by-name directory.
    target="$1"
    # readlink -f is widely available on busybox and util-linux; if absent,
    # the entry is used as-is (it may already be a device node).
    if command -v readlink >/dev/null 2>&1; then
        resolved=$(readlink -f "$target" 2>/dev/null) && [ -n "$resolved" ] && target="$resolved"
    fi
    printf '%s' "$target"
}

FOUND=0
EMIT=""

for label in $PARTITION_LABELS; do
    entry="$BY_NAME_DIR_RESOLVED/$label"
    if [ -e "$entry" ] || [ -L "$entry" ]; then
        dev=$(resolve_link "$entry")
        var=$(label_to_var "$label")
        EMIT="$EMIT
$var=$dev"
        printf '[detect-partitions] %s -> %s\n' "$label" "$dev" >&2
        FOUND=$((FOUND + 1))
    fi
done

if [ "$FOUND" -eq 0 ]; then
    printf '[detect-partitions] ERROR: directory %s contains none of the standard partition labels\n' "$BY_NAME_DIR_RESOLVED" >&2
    exit 2
fi

# Emit the leading newline-free block. $EMIT starts with a newline; strip it.
printf '%s\n' "$EMIT" | sed -n '2,$p'
printf 'PARTITION_BY_NAME_DIR=%s\n' "$BY_NAME_DIR_RESOLVED"

exit 0