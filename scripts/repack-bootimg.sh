#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# WIP — Work in progress. This script is part of the DaemonCores-Phone
# standard Halium build pipeline and is under active development. The
# mkbootimg argument wiring, header-version handling, and partition-size
# enforcement are not yet validated against real device boot images.
# Expect breaking changes until the pipeline reaches a tagged milestone.
#
# repack-bootimg.sh — Package a kernel + ramdisk + dtb into an Android boot.img.
#
# Description:
#   Assembles an Android boot image (boot.img) from a compiled kernel, a
#   ramdisk (the standard Halium initramfs cpio archive), and an optional
#   device-tree blob. The image is produced by mkbootimg and is compatible
#   with the device's partition_layout and boot block declared in the
#   device.yml descriptor.
#
#   The script reads boot-image parameters (header version, base address,
#   page size, kernel command line, extra mkbootimg args, partition size)
#   from the device.yml boot block (passed as a JSON string). Sensible
#   defaults are applied when a field is absent so the script works on
#   legacy boot.img formats that do not declare a boot block.
#
#   This script is the packaging half of the standard Halium build
#   pipeline (P11). It is called by scripts/build-halium.sh after the
#   kernel cross-compile step. It does not build the kernel or the
#   initramfs — it only packages existing artifacts.
#
# Globals:
#   Reads:
#     MKBOOTIMG   Override the mkbootimg binary path (default: searched on
#                 $PATH, then /usr/bin/mkbootimg, then
#                 /usr/lib/android-sdk/build-tools/*/mkbootimg).
#
# Arguments:
#   Positional, in order:
#     $1 = KERNEL              Path to the compiled kernel image
#                              (Image.gz or Image).
#     $2 = RAMDISK             Path to the ramdisk cpio archive (gzipped
#                              or plain). Passed to mkbootimg --ramdisk.
#     $3 = DTB                 Path to the device-tree blob, OR a
#                              directory containing .dtb files, OR empty
#                              when the device has no DTB. When a
#                              directory is given, the first .dtb is
#                              used (build-halium.sh pre-selects when
#                              possible).
#     $4 = PARTITION_LAYOUT_JSON  JSON string of the device.yml
#                              partition_layout block (forwarded verbatim
#                              from build-halium.sh). Currently used for
#                              logging; future use may select the boot
#                              partition for A/B devices.
#     $5 = OUTPUT              Path where the assembled boot.img is
#                              written.
#     $6 = BOOT_JSON           Optional JSON string of the device.yml
#                              `boot` block. May be empty. Carries
#                              header_version, base_address, page_size,
#                              cmdline, mkbootimg_args, partition_size.
#
#   Options:
#     --help, -h               Show this help and exit.
#
# Outputs:
#   stdout: the path of the produced boot.img on success.
#   stderr: diagnostic lines prefixed with [repack-bootimg].
#
# Exit codes:
#   0  Success — boot.img produced at $OUTPUT.
#   1  Usage error (wrong argument count, --help with extra args, missing
#      input file).
#   2  mkbootimg not found on $PATH or via MKBOOTIMG.
#   3  The BOOT_JSON could not be parsed (malformed JSON).
#   4  mkbootimg failed (non-zero exit).
#   5  The produced boot.img exceeds boot.partition_size (when set).
#   6  The output boot.img is missing after a successful mkbootimg exit.
#
# Idempotence:
#   Re-running with the same inputs overwrites $OUTPUT with an identical
#   boot.img. No side effects beyond $OUTPUT.
#
# Header version support:
#   mkbootimg header versions 0 through 4 are supported. The version is
#   selected by --header_version, taken from boot.header_version or
#   defaulting to 1. Version-specific wiring:
#     v0/v1: standard --kernel/--ramdisk/--cmdline/--base/--pagesize.
#     v2:    adds --recovery_dtbo (second DTB slot) — passed via
#            mkbootimg_args when the device needs it.
#     v3/v4: drops --base/--pagesize/--second; the page size is fixed at
#            4096 by mkbootimg. We still forward the values via
#            mkbootimg_args for forward compatibility, but mkbootimg
#            ignores them for v3/v4.
#   Extra arguments from boot.mkbootimg_args are appended AFTER the
#   standard arguments so a device can override any default.

set -eu

# ---------------------------------------------------------------------------
# Constants and defaults
# ---------------------------------------------------------------------------

# Default boot image parameters (used when BOOT_JSON is empty or a field
# is absent). These match the most common legacy boot.img layout.
DEFAULT_HEADER_VERSION=1
DEFAULT_BASE_ADDRESS="0x00000000"
DEFAULT_PAGE_SIZE=2048
DEFAULT_CMDLINE=""
DEFAULT_PARTITION_SIZE=""   # empty = no size cap

# Exit code namespace (mirrors the header comment).
E_USAGE=1
E_MKBOOTIMG_NOTFOUND=2
E_BOOT_JSON=3
E_MKBOOTIMG_FAIL=4
E_TOO_LARGE=5
E_OUTPUT_MISSING=6

# ---------------------------------------------------------------------------
# Logging helpers — stderr only; stdout reserved for the boot.img path.
# ---------------------------------------------------------------------------

log() {
    printf '[repack-bootimg] %s\n' "$*" >&2
}

err() {
    printf '[repack-bootimg] ERROR: %s\n' "$*" >&2
}

die() {
    code="$1"
    shift
    err "$*"
    exit "$code"
}

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------

print_help() {
    cat <<'EOF'
repack-bootimg.sh — Package a kernel + ramdisk + dtb into an Android boot.img.

Usage:
  repack-bootimg.sh [--help|-h] \
    <KERNEL> <RAMDISK> <DTB> <PARTITION_LAYOUT_JSON> <OUTPUT> [<BOOT_JSON>]

Arguments (positional, in order):
  KERNEL                  Path to the compiled kernel image (Image.gz or Image).
  RAMDISK                 Path to the ramdisk cpio archive (the Halium initramfs).
  DTB                     Path to a .dtb file, a directory of .dtb files,
                          or empty ("") when the device has no DTB.
  PARTITION_LAYOUT_JSON   JSON string of the device.yml partition_layout
                          block (forwarded by build-halium.sh).
  OUTPUT                  Path where the assembled boot.img is written.
  BOOT_JSON               Optional JSON string of the device.yml `boot`
                          block. May be empty. Carries header_version,
                          base_address, page_size, cmdline,
                          mkbootimg_args, partition_size.

Options:
  --help, -h              Show this help and exit.

Environment:
  MKBOOTIMG               Override the mkbootimg binary path.

Defaults (applied when BOOT_JSON is empty or a field is absent):
  header_version          1
  base_address            0x00000000
  page_size               2048
  cmdline                 (empty)
  partition_size          (no cap)

Exit codes:
  0  Success — boot.img produced at OUTPUT.
  1  Usage error / missing input file.
  2  mkbootimg not found.
  3  BOOT_JSON parse error.
  4  mkbootimg failed.
  5  boot.img exceeds partition_size.
  6  boot.img missing after a successful mkbootimg exit.

Header version support: 0, 1, 2, 3, 4. Extra arguments from
boot.mkbootimg_args are appended after the standard arguments so a device
can override any default.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# Allow --help as the first and only argument.
if [ $# -ge 1 ]; then
    case "$1" in
        --help|-h)
            if [ $# -ne 1 ]; then
                die "$E_USAGE" "--help does not accept extra arguments"
            fi
            print_help
            exit 0
            ;;
    esac
fi

# We expect 5 or 6 positional arguments. The 6th (BOOT_JSON) is optional
# and may be empty.
if [ $# -lt 5 ] || [ $# -gt 6 ]; then
    err "expected 5 or 6 positional arguments, got $#"
    printf '[repack-bootimg] Run "%s --help" for usage.\n' "$0" >&2
    exit "$E_USAGE"
fi

KERNEL="$1"
RAMDISK="$2"
DTB="$3"
PARTITION_LAYOUT_JSON="$4"
OUTPUT="$5"
BOOT_JSON="${6:-}"

log "arguments:"
log "  kernel              = $KERNEL"
log "  ramdisk             = $RAMDISK"
log "  dtb                 = ${DTB:-<none>}"
log "  partition_layout    = <JSON, ${#PARTITION_LAYOUT_JSON} bytes>"
log "  output              = $OUTPUT"
if [ -n "$BOOT_JSON" ]; then
    log "  boot                = <JSON, ${#BOOT_JSON} bytes>"
else
    log "  boot                = <none — using defaults>"
fi

# Validate inputs that must exist on disk.
if [ ! -f "$KERNEL" ]; then
    die "$E_USAGE" "kernel image not found or not a regular file: $KERNEL"
fi
if [ ! -f "$RAMDISK" ]; then
    die "$E_USAGE" "ramdisk not found or not a regular file: $RAMDISK"
fi
# DTB may be empty, a file, or a directory.
if [ -n "$DTB" ] && [ ! -e "$DTB" ]; then
    die "$E_USAGE" "dtb path does not exist: $DTB"
fi

# Ensure the output directory exists.
OUTPUT_DIR=$(dirname "$OUTPUT")
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" 2>/dev/null || die "$E_USAGE" "cannot create output directory: $OUTPUT_DIR"
fi

# ---------------------------------------------------------------------------
# Locate mkbootimg.
# ---------------------------------------------------------------------------

find_mkbootimg() {
    # Check $MKBOOTIMG override first, then $PATH, then common SDK paths.
    if [ -n "${MKBOOTIMG:-}" ] && [ -x "$MKBOOTIMG" ]; then
        printf '%s' "$MKBOOTIMG"
        return 0
    fi
    if command -v mkbootimg >/dev/null 2>&1; then
        command -v mkbootimg
        return 0
    fi
    # Common Android SDK build-tools locations.
    for cand in \
        /usr/bin/mkbootimg \
        /usr/lib/android-sdk/build-tools/*/mkbootimg \
        /opt/android-sdk/build-tools/*/mkbootimg; do
        # shellcheck disable=SC2086 # glob expansion intended
        for f in $cand; do
            if [ -x "$f" ]; then
                printf '%s' "$f"
                return 0
            fi
        done
    done
    return 1
}

if ! MKBOOTIMG_BIN=$(find_mkbootimg); then
    die "$E_MKBOOTIMG_NOTFOUND" "mkbootimg not found. Set MKBOOTIMG or install it on \$PATH."
fi
log "mkbootimg: $MKBOOTIMG_BIN"

# ---------------------------------------------------------------------------
# Parse the optional BOOT_JSON to extract boot parameters.
#
# We use python3 (already a build-halium.sh dependency) to parse the JSON
# string and emit "key\tvalue" lines. When BOOT_JSON is empty, the
# defaults are used directly.
# ---------------------------------------------------------------------------

HEADER_VERSION="$DEFAULT_HEADER_VERSION"
BASE_ADDRESS="$DEFAULT_BASE_ADDRESS"
PAGE_SIZE="$DEFAULT_PAGE_SIZE"
CMDLINE="$DEFAULT_CMDLINE"
MKBOOTIMG_EXTRA_ARGS=""
PARTITION_SIZE="$DEFAULT_PARTITION_SIZE"

if [ -n "$BOOT_JSON" ]; then
    # Parse the JSON via python3. The script prints key\tvalue lines or
    # exits non-zero on a malformed JSON.
    BOOT_PARSE_OUT=$(printf '%s' "$BOOT_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as exc:
    sys.stderr.write(f"[repack-bootimg] ERROR: failed to parse boot JSON: {exc}\n")
    sys.exit(3)
if not isinstance(data, dict):
    sys.stderr.write("[repack-bootimg] ERROR: boot JSON top-level is not an object\n")
    sys.exit(3)
def emit(key, value):
    if value is None:
        return
    text = str(value).replace("\x00", "").replace("\t", " ").replace("\n", " ")
    sys.stdout.write(f"{key}\t{text}\n")
emit("header_version", data.get("header_version"))
emit("base_address", data.get("base_address"))
emit("page_size", data.get("page_size"))
emit("cmdline", data.get("cmdline"))
emit("mkbootimg_args", data.get("mkbootimg_args"))
ps = data.get("partition_size")
if ps is not None:
    emit("partition_size", ps)
' 2>&1) || {
        rc=$?
        err "boot JSON parsing failed (exit $rc):"
        printf '%s\n' "$BOOT_PARSE_OUT" >&2
        exit "$E_BOOT_JSON"
    }
    # Read the key\tvalue lines.
    boot_get() {
        # $1 = key. Prints the value or empty string.
        printf '%s\n' "$BOOT_PARSE_OUT" | awk -v k="$1" -F'\t' '$1==k {print $2}'
    }
    v=$(boot_get header_version); [ -n "$v" ] && HEADER_VERSION="$v"
    v=$(boot_get base_address);   [ -n "$v" ] && BASE_ADDRESS="$v"
    v=$(boot_get page_size);      [ -n "$v" ] && PAGE_SIZE="$v"
    v=$(boot_get cmdline);        [ -n "$v" ] && CMDLINE="$v"
    v=$(boot_get mkbootimg_args); [ -n "$v" ] && MKBOOTIMG_EXTRA_ARGS="$v"
    v=$(boot_get partition_size); [ -n "$v" ] && PARTITION_SIZE="$v"
fi

# Normalise types / validate.
case "$HEADER_VERSION" in
    0|1|2|3|4) ;;
    *)
        die "$E_BOOT_JSON" "unsupported header_version: $HEADER_VERSION (expected 0-4)"
        ;;
esac

# page_size must be an integer; validate it parses.
case "$PAGE_SIZE" in
    ''|*[!0-9]*)
        die "$E_BOOT_JSON" "invalid page_size: $PAGE_SIZE (expected an integer)"
        ;;
esac

# partition_size, when set, must be an integer.
if [ -n "$PARTITION_SIZE" ]; then
    case "$PARTITION_SIZE" in
        ''|*[!0-9]*)
            die "$E_BOOT_JSON" "invalid partition_size: $PARTITION_SIZE (expected an integer)"
            ;;
    esac
fi

log "resolved boot parameters:"
log "  header_version   = $HEADER_VERSION"
log "  base_address     = $BASE_ADDRESS"
log "  page_size        = $PAGE_SIZE"
log "  cmdline          = ${CMDLINE:-<empty>}"
log "  mkbootimg_args   = ${MKBOOTIMG_EXTRA_ARGS:-<none>}"
log "  partition_size   = ${PARTITION_SIZE:-<no cap>}"

# ---------------------------------------------------------------------------
# Resolve the DTB.
#
# $DTB may be:
#   - empty: no DTB passed.
#   - a .dtb file: used directly.
#   - a directory: pick the first .dtb inside it.
# ---------------------------------------------------------------------------

DTB_FILE=""
if [ -n "$DTB" ]; then
    if [ -f "$DTB" ]; then
        DTB_FILE="$DTB"
    elif [ -d "$DTB" ]; then
        # Pick the first .dtb in the directory.
        for f in "$DTB"/*.dtb; do
            if [ -f "$f" ]; then
                DTB_FILE="$f"
                break
            fi
        done
        if [ -z "$DTB_FILE" ]; then
            log "no .dtb found under directory $DTB — building without dtb"
        fi
    else
        log "dtb path neither file nor directory: $DTB — building without dtb"
    fi
fi

if [ -n "$DTB_FILE" ]; then
    log "dtb selected: $DTB_FILE"
fi

# ---------------------------------------------------------------------------
# Assemble the mkbootimg argument list.
#
# The arguments differ slightly by header version, but mkbootimg accepts
# --header_version and adapts internally. We forward the standard set and
# let mkbootimg ignore the fields that do not apply to the selected
# version. Extra arguments from boot.mkbootimg_args are appended last so
# a device can override any default.
# ---------------------------------------------------------------------------

# Build the argument list in a positional form. We avoid arrays (not
# POSIX) by building a single string and relying on the shell's word
# splitting. Paths here do not contain spaces (kernel build outputs and
# cpio archives are under /tmp build dirs); if a path ever contained a
# space, the caller would need to pre-quote it. We guard the common case.
#
# shellcheck disable=SC2086 # intentional word splitting for arg list

MKBOOTIMG_ARGS="--kernel $KERNEL --ramdisk $RAMDISK --header_version $HEADER_VERSION"

# cmdline: forward only when non-empty.
if [ -n "$CMDLINE" ]; then
    MKBOOTIMG_ARGS="$MKBOOTIMG_ARGS --cmdline $CMDLINE"
fi

# base_address and page_size are meaningful for v0/v1/v2. mkbootimg
# accepts them for v3/v4 but ignores them; we forward unconditionally so
# the device descriptor is the single source of truth.
MKBOOTIMG_ARGS="$MKBOOTIMG_ARGS --base $BASE_ADDRESS --pagesize $PAGE_SIZE"

# DTB: --dtb for v0-v2, --dtb for v3/v4 (mkbootimg supports --dtb across
# versions in modern builds). Forward only when a DTB was resolved.
if [ -n "$DTB_FILE" ]; then
    MKBOOTIMG_ARGS="$MKBOOTIMG_ARGS --dtb $DTB_FILE"
fi

# Extra arguments from boot.mkbootimg_args — appended last so they can
# override anything above (e.g. --header_version, --ramdisk_type,
# --recovery_dtbo).
if [ -n "$MKBOOTIMG_EXTRA_ARGS" ]; then
    MKBOOTIMG_ARGS="$MKBOOTIMG_ARGS $MKBOOTIMG_EXTRA_ARGS"
fi

# Output: mkbootimg writes to -o / --output.
MKBOOTIMG_ARGS="$MKBOOTIMG_ARGS -o $OUTPUT"

log "invoking mkbootimg"
# shellcheck disable=SC2086 # intentional word splitting — see note above
if ! "$MKBOOTIMG_BIN" $MKBOOTIMG_ARGS 1>&2; then
    die "$E_MKBOOTIMG_FAIL" "mkbootimg failed (exit $?)"
fi

if [ ! -f "$OUTPUT" ]; then
    die "$E_OUTPUT_MISSING" "mkbootimg returned success but boot.img is missing: $OUTPUT"
fi

# ---------------------------------------------------------------------------
# Verify the output size does not exceed boot.partition_size (when set).
# ---------------------------------------------------------------------------

OUTPUT_SIZE=$(wc -c < "$OUTPUT" 2>/dev/null | tr -d ' ')
if [ -z "$OUTPUT_SIZE" ]; then
    OUTPUT_SIZE=0
fi
log "boot.img size: $OUTPUT_SIZE bytes"

if [ -n "$PARTITION_SIZE" ]; then
    if [ "$OUTPUT_SIZE" -gt "$PARTITION_SIZE" ]; then
        err "boot.img exceeds partition_size: $OUTPUT_SIZE > $PARTITION_SIZE bytes"
        err "  output: $OUTPUT"
        die "$E_TOO_LARGE" "reduce the kernel/ramdisk size or increase boot.partition_size in device.yml"
    fi
    log "size check passed: $OUTPUT_SIZE <= $PARTITION_SIZE bytes"
fi

# Print the final artifact path to stdout for CI consumption.
printf '%s\n' "$OUTPUT"
log "done: $OUTPUT"