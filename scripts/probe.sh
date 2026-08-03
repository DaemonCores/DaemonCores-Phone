#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# WIP — Work in progress. This script is part of the DaemonCores-Phone
# device probing flow and is under active development. The collectors,
# the JSON schema mapping, and the probe-to-yaml.py integration are not
# yet validated against the full device fleet. Expect breaking changes
# until the probing flow reaches a tagged milestone.
#
# probe.sh — ADB probe for an unknown Android device.
#
# Connects to a single Android device over ADB, collects read-only facts
# from the running Android system (getprop, /dev/block/by-name/,
# /proc/config.gz, /vendor/etc/audio_policy.conf, /vendor/lib*/hw/), and
# emits a JSON document on stdout that matches the input contract of
# scripts/probe-to-yaml.py.
#
# The probe is strictly READ-ONLY: it never pushes, writes, installs, or
# modifies anything on the device. Every collection step is `adb shell
# <read-only command>`. The device must already be running Android
# (stock or LineageOS) with ADB enabled and authorized.
#
# The emitted JSON is a flat dict that probe-to-yaml.py maps onto the
# canonical device.yml schema (see device/_schema.yml). Fields the probe
# cannot determine from the device alone (notably `kernel_repo` — a
# LineageOS git URL — and sometimes `defconfig`) are LEFT ABSENT in the
# JSON; the user fills them in by hand before opening the PR. The
# probe-to-yaml.py validator will refuse to emit a device.yml missing a
# required field, so the user gets a clear list of what still needs
# sourcing.
#
# Usage:
#   probe.sh [--codename <name>] [--output <device.yml>] [--help]
#            [--vendor-kernel <url>] [--defconfig <name>]
#            [--status <booted|partial|functional|full>]
#
# The optional flags let the user supply the fields the probe cannot
# read from the device (kernel_repo, defconfig, status, codename). They
# are forwarded into the JSON so probe-to-yaml.py picks them up. When an
# --output path is given, the pipeline writes the final device.yml there
# instead of stdout.
#
# Exit codes:
#   0  Success — JSON probe document emitted on stdout (and, when
#      --output is given, device.yml written to that path via
#      probe-to-yaml.py).
#   1  Usage error (bad flag, --help requested with extra args).
#   2  adb not installed.
#   3  No device connected, or more than one device connected.
#   4  Device collection failure (an adb shell step failed and could not
#      be recovered).
#   5  probe-to-yaml.py invocation failed (--output path only).
#   6  python3 not available (--output path only).
#
# Environment:
#   ADB                     Override the adb binary path (default: adb).
#   PROBE_PY                Override the probe-to-yaml.py path (default:
#                           scripts/probe-to-yaml.py relative to this
#                           script's directory).
#   PROBE_ADB_SERIAL        Force a specific device serial when more than
#                           one device is connected. When set, the
#                           "exactly one device" check is skipped and the
#                           serial is passed to adb via -s.
#
# Idempotence:
#   Running probe.sh twice against the same device produces the same
#   JSON output (modulo the `date` field injected by probe-to-yaml.py
#   into sources, which is per-call). No state is kept on disk between
#   runs; the script writes nothing to the device and only emits to
#   stdout (or the --output file).

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants and paths
# ---------------------------------------------------------------------------

# Resolve the script directory and repository root without readlink -f
# (kept POSIX-friendly; build-halium.sh uses the same pattern).
resolve_dir() {
    # $1 = path to a directory. Prints absolute path via cd, falls back
    # to the literal path if cd fails.
    ( cd "$1" 2>/dev/null && pwd ) || printf '%s' "$1"
}

SCRIPT_DIR=$(resolve_dir "$(dirname "$0")")
REPO_ROOT=$(resolve_dir "$SCRIPT_DIR/..")
PROBE_PY="${PROBE_PY:-$SCRIPT_DIR/probe-to-yaml.py}"
ADB_BIN="${ADB:-adb}"

# Exit code namespace (mirrors the header comment).
E_USAGE=1
E_ADB_MISSING=2
E_DEVICE=3
E_COLLECT=4
E_PROBE_PY=5
E_PYTHON=6

# ---------------------------------------------------------------------------
# Logging helpers — stderr only, stdout reserved for the JSON document
# (and the device.yml when --output is used).
# ---------------------------------------------------------------------------

log() {
    # $@ -> message printed to stderr with a [probe] prefix.
    printf '[probe] %s\n' "$*" >&2
}

err() {
    # $@ -> error message to stderr, prefixed with ERROR.
    printf '[probe] ERROR: %s\n' "$*" >&2
}

die() {
    # $1 = exit code, $2.. = message. Log an error then exit with code.
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
probe.sh — ADB probe for an unknown Android device.

Reads device facts over ADB (read-only) and emits a JSON document on
stdout that scripts/probe-to-yaml.py converts into a schema-valid
device.yml.

The probe is strictly read-only: it never pushes, writes, installs, or
modifies anything on the connected device.

Usage:
  probe.sh [OPTIONS]

Options:
  --codename <name>          Device codename (e.g. beryllium). The probe
                              cannot always read this from the device
                              (ro.product.device is sometimes a board
                              name, not the LineageOS codename); supply
                              it explicitly when known.
  --vendor-kernel <url>      git URL of the vendor kernel repository
                              (kernel_repo field). The probe cannot
                              determine this from the device; it must be
                              sourced from LineageOS / the vendor. Required
                              for a valid device.yml.
  --defconfig <name>         Kernel defconfig name (e.g.
                              beryllium_defconfig). Inferred from
                              /proc/config.gz when available, otherwise
                              from the codename; override here when the
                              inference is wrong.
  --status <status>          Device support status (booted|partial|
                              functional|full). Default: booted (the
                              probe only confirms the device boots
                              Android; a real status needs a Halium
                              test boot).
  --output <path>            Write the final device.yml to this path
                              instead of emitting the raw probe JSON on
                              stdout. When set, probe.sh runs
                              probe-to-yaml.py for you.
  --help, -h                 Show this help and exit.

Environment:
  ADB                     Override the adb binary path (default: adb).
  PROBE_PY                Override the probe-to-yaml.py path.
  PROBE_ADB_SERIAL        Force a specific device serial when more than
                          one device is connected.

Exit codes:
  0  Success.
  1  Usage error.
  2  adb not installed.
  3  No device, or more than one device (set PROBE_ADB_SERIAL).
  4  Device collection failure.
  5  probe-to-yaml.py invocation failed (--output only).
  6  python3 not available (--output only).

Examples:
  # Emit the raw probe JSON on stdout (pipe to probe-to-yaml.py yourself):
  ./scripts/probe.sh > probe.json

  # Produce a device.yml directly, supplying the fields the probe cannot
  # read from the device:
  ./scripts/probe.sh \
      --codename beryllium \
      --vendor-kernel https://github.com/LineageOS/android_kernel_xiaomi_sdm845 \
      --defconfig beryllium_defconfig \
      --status booted \
      --output device/beryllium/device.yml

  # Force a specific device when several are connected:
  PROBE_ADB_SERIAL=abc123 ./scripts/probe.sh --codename surya --output device/surya/device.yml

Notes:
  - The connected device must be running Android (stock or LineageOS)
    with ADB enabled and the host authorized.
  - Fields the probe cannot read (kernel_repo, sometimes defconfig and
    codename) are left absent in the JSON; probe-to-yaml.py will list
    the missing required fields so you know exactly what to source.
  - Re-running the probe against the same device yields the same JSON
    (idempotent); no state is written to the device or disk between runs.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

CODENAME_OVERRIDE=""
VENDOR_KERNEL_OVERRIDE=""
DEFCONFIG_OVERRIDE=""
STATUS_OVERRIDE=""
OUTPUT_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            if [ $# -gt 1 ]; then
                die "$E_USAGE" "--help takes no extra arguments"
            fi
            print_help
            exit 0
            ;;
        --codename)
            [ $# -ge 2 ] || die "$E_USAGE" "--codename requires a value"
            CODENAME_OVERRIDE="$2"
            shift 2
            ;;
        --codename=*)
            CODENAME_OVERRIDE="${1#--codename=}"
            shift
            ;;
        --vendor-kernel)
            [ $# -ge 2 ] || die "$E_USAGE" "--vendor-kernel requires a value"
            VENDOR_KERNEL_OVERRIDE="$2"
            shift 2
            ;;
        --vendor-kernel=*)
            VENDOR_KERNEL_OVERRIDE="${1#--vendor-kernel=}"
            shift
            ;;
        --defconfig)
            [ $# -ge 2 ] || die "$E_USAGE" "--defconfig requires a value"
            DEFCONFIG_OVERRIDE="$2"
            shift 2
            ;;
        --defconfig=*)
            DEFCONFIG_OVERRIDE="${1#--defconfig=}"
            shift
            ;;
        --status)
            [ $# -ge 2 ] || die "$E_USAGE" "--status requires a value"
            STATUS_OVERRIDE="$2"
            shift 2
            ;;
        --status=*)
            STATUS_OVERRIDE="${1#--status=}"
            shift
            ;;
        --output)
            [ $# -ge 2 ] || die "$E_USAGE" "--output requires a value"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --output=*)
            OUTPUT_PATH="${1#--output=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "$E_USAGE" "unknown option: $1 (see --help)"
            ;;
        *)
            die "$E_USAGE" "unexpected positional argument: $1 (probe.sh takes only options; see --help)"
            ;;
    esac
done

# Validate --status against the schema enum early (better error than the
# downstream validator's generic message).
if [ -n "$STATUS_OVERRIDE" ]; then
    case "$STATUS_OVERRIDE" in
        booted|partial|functional|full) ;;
        *)
            die "$E_USAGE" "--status must be one of: booted, partial, functional, full (got: $STATUS_OVERRIDE)"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Step 1 — Check adb is installed.
# ---------------------------------------------------------------------------

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    err "adb is not installed (or not on PATH)."
    err "  looked for: $ADB_BIN"
    err "  install it with one of:"
    err "    apt install android-sdk-platform-tools   # Debian/Ubuntu"
    err "    dnf install android-tools                # Fedora"
    err "    pacman -S android-tools                  # Arch"
    err "  or download from https://developer.android.com/tools/releases/platform-tools"
    die "$E_ADB_MISSING" "adb is required to probe a device."
fi
log "adb found: $(command -v "$ADB_BIN")"

# ---------------------------------------------------------------------------
# Step 2 — Check exactly one Android device is connected.
# ---------------------------------------------------------------------------

# Determine the adb serial argument. PROBE_ADB_SERIAL forces a specific
# device; otherwise we require exactly one device in the `adb devices`
# list (excluding the daemon header line and offline/unauthorized entries).
ADB_SERIAL_ARG=""
if [ -n "${PROBE_ADB_SERIAL:-}" ]; then
    ADB_SERIAL_ARG="-s ${PROBE_ADB_SERIAL}"
    log "using forced serial: $PROBE_ADB_SERIAL"
else
    # `adb devices` prints a header line then one line per device:
    #   <serial>\t<state>
    # We count lines whose state is exactly "device" (authorized and
    # ready). Offline/unauthorized devices are ignored.
    devices_output=$("$ADB_BIN" devices 2>/dev/null || true)
    device_count=$(printf '%s\n' "$devices_output" \
        | awk -F'\t' '$2 == "device" { count++ } END { print count+0 }')

    if [ "$device_count" -eq 0 ]; then
        err "no authorized Android device connected."
        err "  check that:"
        err "    - USB debugging is enabled in Developer Options,"
        err "    - the device is plugged in and authorized on this host,"
        err "    - 'adb devices' lists it with state 'device' (not 'offline' or 'unauthorized')."
        err "  full 'adb devices' output:"
        printf '%s\n' "$devices_output" | sed 's/^/    /' >&2
        die "$E_DEVICE" "no authorized device found."
    fi

    if [ "$device_count" -gt 1 ]; then
        err "more than one Android device connected ($device_count found)."
        err "  set PROBE_ADB_SERIAL=<serial> to target one, or disconnect the others."
        err "  full 'adb devices' output:"
        printf '%s\n' "$devices_output" | sed 's/^/    /' >&2
        die "$E_DEVICE" "ambiguous device count; set PROBE_ADB_SERIAL."
    fi

    log "exactly one authorized device connected."
fi

# Helper: run an adb shell command with the serial argument if set.
# $@ = the remote command. stdout is the remote command's stdout.
adb_shell() {
    if [ -n "$ADB_SERIAL_ARG" ]; then
        # shellcheck disable=SC2086 # ADB_SERIAL_ARG is intentionally split
        "$ADB_BIN" $ADB_SERIAL_ARG shell "$@"
    else
        "$ADB_BIN" shell "$@"
    fi
}

# ---------------------------------------------------------------------------
# Step 3 — Collect device facts (read-only).
#
# Each collector is a function that prints its result on stdout. A
# collector may print an empty string when the fact is unavailable on
# the device; the JSON builder treats empty output as "field absent".
# ---------------------------------------------------------------------------

# getprop_value <prop>: print a single getprop value, stripped of
# trailing whitespace and the surrounding brackets getprop adds.
getprop_value() {
    # $1 = property name (e.g. ro.product.device).
    # getprop prints: "[value]" or empty when unset. We tolerate adb
    # failures (device gone, permission denied) by returning empty
    # rather than aborting under `set -e` + pipefail.
    adb_shell getprop "$1" 2>/dev/null \
        | sed -e 's/^\[//' -e 's/\]$//' -e 's/[[:space:]]*$//' \
        | tr -d '\r' || true
}

# Collect ro.vndk.version (the VNDK version string). ro.vndk.lite is
# read separately in collect_notes (it is a notes field, not a schema
# field), so this function only concerns itself with the version.
collect_vndk() {
    vndk_version=$(getprop_value ro.vndk.version)
    if [ -n "$vndk_version" ]; then
        printf '%s' "$vndk_version"
    fi
}

# Collect the partition layout from /dev/block/by-name/ (or the
# bootdevice symlink variant). The schema requires boot, dtbo,
# vendor_boot; system and userdata are optional. We resolve each by-name
# symlink target so the JSON carries a concrete path.
collect_partition_layout() {
    # Prefer /dev/block/by-name/ (legacy), then /dev/block/bootdevice/by-name/
    # (newer Qualcomm). List entries with their resolved targets.
    byname_listing=""
    for base in /dev/block/by-name /dev/block/bootdevice/by-name; do
        byname_listing=$(adb_shell ls -l "$base" 2>/dev/null || true)
        if [ -n "$byname_listing" ]; then
            break
        fi
    done

    if [ -z "$byname_listing" ]; then
        log "WARNING: could not list /dev/block/by-name/ or /dev/block/bootdevice/by-name/ — partition_layout will be incomplete"
        return 0
    fi

    # Extract a partition symlink target by name. ls -l on a by-name
    # directory prints lines like:
    #   lrwxrwxrwx root root ... boot -> /dev/block/sde12
    # We grab the path after '->'.
    part_target() {
        # $1 = partition name (boot, dtbo, ...). Prints the resolved
        # target path or empty.
        printf '%s\n' "$byname_listing" \
            | awk -v name="$1" '
                $0 ~ (" " name " -> ") {
                    # find the " -> " separator and print the tail
                    idx = index($0, " -> ")
                    if (idx > 0) {
                        print substr($0, idx + 4)
                    }
                }
              ' \
            | head -n1 \
            | tr -d '\r'
    }

    boot=$(part_target boot)
    dtbo=$(part_target dtbo)
    vendor_boot=$(part_target vendor_boot)
    system=$(part_target system)
    userdata=$(part_target userdata)
    modem=$(part_target modem)

    # Emit a compact JSON object. The schema requires boot, dtbo,
    # vendor_boot; we always include them (empty string when absent so
    # the user sees what is missing). Optional partitions are included
    # only when present.
    json="{\"boot\":\"${boot}\",\"dtbo\":\"${dtbo}\",\"vendor_boot\":\"${vendor_boot}\""
    [ -n "$system" ]   && json="${json},\"system\":\"${system}\""
    [ -n "$userdata" ] && json="${json},\"userdata\":\"${userdata}\""
    [ -n "$modem" ]    && json="${json},\"modem\":\"${modem}\""
    json="${json}}"
    printf '%s' "$json"
}

# Collect /proc/config.gz (when available) and infer a defconfig name.
# defconfig inference heuristic: look for CONFIG_ARCH_<PLATFORM>=y or a
# vendor-specific CONFIG that names the board, then form
# <platform>_defconfig. This is a best-effort guess; the user can
# override with --defconfig.
collect_defconfig_guess() {
    # Try zcat first (kernel built with CONFIG_IKCONFIG_PROC), then cat
    # (some devices expose /proc/config uncompressed).
    config_text=$(adb_shell zcat /proc/config.gz 2>/dev/null || true)
    if [ -z "$config_text" ]; then
        config_text=$(adb_shell cat /proc/config.gz 2>/dev/null || true)
    fi
    if [ -z "$config_text" ]; then
        log "WARNING: /proc/config.gz not readable — defconfig cannot be inferred from the running kernel"
        return 0
    fi

    # Heuristic 1: a CONFIG_DEFAULT_KERNEL_CONFIG or vendor-defconfig
    # marker (rare). Heuristic 2: ro.board.platform -> <platform>_defconfig
    # is more reliable; we try the platform route in the JSON builder.
    # Here we look for ARCH platform hints to corroborate.
    platform_hint=$(printf '%s\n' "$config_text" \
        | grep -E '^CONFIG_ARCH_[A-Z0-9_]+=y' \
        | head -n1 \
        | sed -E 's/^CONFIG_ARCH_([A-Z0-9_]+)=y$/\1/' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d '\r' || true)
    [ -n "$platform_hint" ] && printf '%s' "${platform_hint}_defconfig"
}

# Collect notes: audio_policy.conf presence, /vendor/lib*/hw/ listing,
# treble state, vndk lite. Assembled as a single human-readable string.
collect_notes() {
    notes=""

    # Treble enabled?
    treble=$(getprop_value ro.treble.enabled)
    [ -n "$treble" ] && notes="${notes}ro.treble.enabled=${treble}; "

    # VNDK lite flag.
    vndk_lite=$(getprop_value ro.vndk.lite)
    [ -n "$vndk_lite" ] && notes="${notes}ro.vndk.lite=${vndk_lite}; "

    # audio_policy.conf location(s).
    audio_policy=""
    for ap in /vendor/etc/audio_policy.conf /system/etc/audio_policy.conf; do
        if adb_shell test -f "$ap" 2>/dev/null; then
            audio_policy="${audio_policy}${ap} "
        fi
    done
    [ -n "$audio_policy" ] && notes="${notes}audio_policy.conf: ${audio_policy%; }; "

    # /vendor/lib*/hw/ listing (available HALs hint).
    hal_dirs=""
    for d in /vendor/lib/hw /vendor/lib64/hw; do
        listing=$(adb_shell ls "$d" 2>/dev/null || true)
        if [ -n "$listing" ]; then
            hal_dirs="${hal_dirs}${d}: $(printf '%s' "$listing" | tr '\n' ' ' | tr -d '\r'); "
        fi
    done
    [ -n "$hal_dirs" ] && notes="${notes}HAL hw dirs: ${hal_dirs%; }; "

    printf '%s' "${notes%; }"
}

# Map VNDK version -> Halium version (schema enum). The mapping follows
# the Halium release table: VNDK 27-28 -> 9.0 (Halium 9), 29 -> 10.0,
# 30-31 -> 11.0, 32 -> 12.0, 33 -> 13.0, 34 -> 14.0. VNDK 27 and below
# map to 7.1 for the oldest devices Halium still targets.
vndk_to_halium() {
    # $1 = vndk version string (digits only). Prints the Halium version
    # or empty when unknown.
    v="$1"
    case "$v" in
        ''|*[!0-9]*) return 0 ;;
    esac
    case "$v" in
        2[0-6]) printf '7.1' ;;
        27|28)  printf '9.0' ;;
        29)     printf '10.0' ;;
        30|31)  printf '11.0' ;;
        32)     printf '12.0' ;;
        33)     printf '13.0' ;;
        34|35)  printf '14.0' ;;
        *)      return 0 ;;   # unknown VNDK; leave halium_version absent
    esac
}

# ---------------------------------------------------------------------------
# Run the collectors.
# ---------------------------------------------------------------------------

log "collecting device facts (read-only)..."

ro_product_device=$(getprop_value ro.product.device)
ro_product_vendor=$(getprop_value ro.product.vendor)
ro_product_manufacturer=$(getprop_value ro.product.manufacturer)
ro_product_model=$(getprop_value ro.product.model)
ro_board_platform=$(getprop_value ro.board.platform)

log "  ro.product.device       = ${ro_product_device:-<unset>}"
log "  ro.product.vendor       = ${ro_product_vendor:-<unset>}"
log "  ro.product.manufacturer = ${ro_product_manufacturer:-<unset>}"
log "  ro.product.model        = ${ro_product_model:-<unset>}"
log "  ro.board.platform       = ${ro_board_platform:-<unset>}"

vndk_version=$(collect_vndk)
log "  ro.vndk.version         = ${vndk_version:-<unset>}"
if [ -z "$vndk_version" ]; then
    log "WARNING: VNDK version not readable (ro.vndk.version unset). The device may be pre-Treble (Android < 8.0); Halium support starts at Android 7.1."
fi

partition_layout_json=$(collect_partition_layout)
log "  partition_layout        = ${partition_layout_json:-<empty>}"

defconfig_guess=$(collect_defconfig_guess)
log "  defconfig guess         = ${defconfig_guess:-<unset>}"

notes_str=$(collect_notes)

# ---------------------------------------------------------------------------
# Step 4 — Assemble the JSON document.
#
# We build the JSON with python3 (available everywhere probe-to-yaml.py
# runs) so escaping is correct and the structure is guaranteed. Fields
# the probe could not read are simply omitted; probe-to-yaml.py then
# reports them as missing required fields.
#
# Field precedence (override > probe):
#   codename        : --codename  > ro.product.device (lowercased, sanitized)
#   vendor          : ro.product.manufacturer (no override; vendor is
#                     usually correct from getprop)
#   model           : ro.product.model (no override)
#   vndk            : ro.vndk.version (no override)
#   halium_version  : derived from vndk via vndk_to_halium
#   soc             : synthesized from manufacturer + platform (best-effort)
#   platform        : ro.board.platform
#   defconfig       : --defconfig > defconfig guess > <platform>_defconfig
#   kernel_repo     : --vendor-kernel (the probe cannot read this)
#   partition_layout: from /dev/block/by-name/
#   status          : --status (default booted — probe only confirms
#                     Android boots, not Halium)
#   sources         : [{ name: adb_probe, url: adb://<serial>, date: today }]
#   notes           : assembled from treble/vndk-lite/audio/hals
# ---------------------------------------------------------------------------

# Resolve the effective field values.
codename_value="$CODENAME_OVERRIDE"
if [ -z "$codename_value" ] && [ -n "$ro_product_device" ]; then
    # ro.product.device is often the codename already (Xiaomi) but may
    # be a board name on some vendors. Lowercase and strip anything
    # outside [a-z0-9_] so it matches the schema pattern.
    codename_value=$(printf '%s' "$ro_product_device" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cd 'a-z0-9_')
fi

defconfig_value="$DEFCONFIG_OVERRIDE"
if [ -z "$defconfig_value" ]; then
    if [ -n "$defconfig_guess" ]; then
        defconfig_value="$defconfig_guess"
    elif [ -n "$ro_board_platform" ]; then
        defconfig_value="${ro_board_platform}_defconfig"
    fi
fi

status_value="${STATUS_OVERRIDE:-booted}"

# Build the JSON via python3 for safe escaping. We pass the raw shell
# values through environment variables and let python3 construct the
# dict, dropping keys whose value is empty. The output is captured into
# PROBE_JSON so we can either print it (default) or feed it to
# probe-to-yaml.py (--output) without re-running collection. set -e +
# pipefail abort on python3 failure; the trailing `|| die` catches the
# rare case where pipefail is masked by the command substitution.
PROBE_JSON=$(PROBE_CODENAME="$codename_value" \
PROBE_VENDOR="$ro_product_manufacturer" \
PROBE_MODEL="$ro_product_model" \
PROBE_VNDK="$vndk_version" \
PROBE_HALIUM=$(vndk_to_halium "$vndk_version") \
PROBE_PLATFORM="$ro_board_platform" \
PROBE_SOC=$([ -n "$ro_board_platform" ] && printf 'Qualcomm %s' "$ro_board_platform" || printf '') \
PROBE_DEFCONFIG="$defconfig_value" \
PROBE_KERNEL_REPO="$VENDOR_KERNEL_OVERRIDE" \
PROBE_PARTITION_LAYOUT="$partition_layout_json" \
PROBE_STATUS="$status_value" \
PROBE_NOTES="$notes_str" \
PROBE_ADB_SERIAL="${PROBE_ADB_SERIAL:-}" \
python3 -c '
import json
import os
import sys

def env(k):
    v = os.environ.get(k, "")
    return v if v != "" else None

doc = {}

codename = env("PROBE_CODENAME")
if codename:
    doc["codename"] = codename
vendor = env("PROBE_VENDOR")
if vendor:
    doc["vendor"] = vendor
model = env("PROBE_MODEL")
if model:
    doc["model"] = model
vndk = env("PROBE_VNDK")
if vndk:
    doc["vndk"] = vndk
halium = env("PROBE_HALIUM")
if halium:
    doc["halium_version"] = halium
platform = env("PROBE_PLATFORM")
if platform:
    doc["platform"] = platform
soc = env("PROBE_SOC")
if soc:
    doc["soc"] = soc
defconfig = env("PROBE_DEFCONFIG")
if defconfig:
    doc["defconfig"] = defconfig
kernel_repo = env("PROBE_KERNEL_REPO")
if kernel_repo:
    doc["kernel_repo"] = kernel_repo
status = env("PROBE_STATUS")
if status:
    doc["status"] = status
notes = env("PROBE_NOTES")
if notes:
    doc["notes"] = notes

pl_raw = env("PROBE_PARTITION_LAYOUT")
if pl_raw:
    try:
        doc["partition_layout"] = json.loads(pl_raw)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[probe] WARNING: partition_layout JSON parse failed: {exc}\n")

serial = env("PROBE_ADB_SERIAL") or "default"
doc["sources"] = [
    {
        "name": "adb_probe",
        "url": f"adb://{serial}",
    }
]

json.dump(doc, sys.stdout, indent=2, sort_keys=False, ensure_ascii=False)
sys.stdout.write("\n")
') || die "$E_COLLECT" "failed to assemble the probe JSON document"

log "probe JSON assembled (${#PROBE_JSON} bytes)."

# ---------------------------------------------------------------------------
# Step 5 — Emit or convert.
#
# Without --output: print the raw probe JSON on stdout (the caller pipes
# it into probe-to-yaml.py themselves, or inspects it).
# With --output: feed the JSON into probe-to-yaml.py via stdin and write
# the resulting device.yml to the requested path.
# ---------------------------------------------------------------------------

if [ -n "$OUTPUT_PATH" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        die "$E_PYTHON" "python3 is required to run probe-to-yaml.py (for --output)."
    fi
    if [ ! -f "$PROBE_PY" ]; then
        die "$E_PROBE_PY" "probe-to-yaml.py not found at: $PROBE_PY (set PROBE_PY to override)."
    fi

    log "running probe-to-yaml.py to produce: $OUTPUT_PATH"
    # Pipe the captured JSON into probe-to-yaml.py. The --codename
    # argument is forwarded so an explicit override wins in the
    # descriptor too (probe-to-yaml.py applies it on top of the JSON).
    # We capture the exit code explicitly because `if !` inverts $?
    # (the body would see 0 from the inverted condition).
    py_args=(--output "$OUTPUT_PATH")
    [ -n "$CODENAME_OVERRIDE" ] && py_args+=(--codename "$CODENAME_OVERRIDE")
    set +e
    printf '%s' "$PROBE_JSON" | python3 "$PROBE_PY" "${py_args[@]}"
    py_rc=$?
    set -e
    if [ "$py_rc" -ne 0 ]; then
        die "$E_PROBE_PY" "probe-to-yaml.py failed (exit code $py_rc). The probe JSON was collected; re-run without --output to inspect it, or fix the missing fields reported above."
    fi
    log "device.yml written to: $OUTPUT_PATH"
else
    printf '%s\n' "$PROBE_JSON"
fi

exit 0