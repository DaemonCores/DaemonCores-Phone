#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# WIP — Work in progress. This script is part of the DaemonCores-Phone
# standard Halium build pipeline and is under active development. Do not
# rely on its current behaviour: the hybris patch step (Step 6) is a
# placeholder, and several wiring points (P03/P11) are pending. Expect
# breaking changes until the pipeline reaches a tagged milestone.
#
# build-halium.sh — Standard Halium build pipeline for a single device.
#
# Reads a device.yml descriptor and runs the generic, device-agnostic Halium
# build pipeline:
#   1. Validate the device.yml path argument exists.
#   2. Parse YAML to extract codename, kernel_repo, defconfig,
#      halium_version, partition_layout, and the optional boot block.
#   3. Create a work directory (/tmp/daemoncores-build-<codename>-<pid>
#      by default, or an override via --work-dir).
#   4. Clone kernel_repo (shallow, single branch).
#   5. Merge kernel/config-fragment-standard into the device defconfig
#      using merge_config.sh from the cloned kernel tree.
#   6. Apply Halium hybris patches (PLACEHOLDER — P03 research pending).
#   7. Cross-compile ARM64 (defconfig then -j$(nproc)) and detect
#      Image.gz / Image / dtb outputs.
#   8. Call scripts/repack-bootimg.sh (assumed to exist) to assemble
#      boot.img from the compiled kernel, the standard initramfs, the
#      dtb, and the device partition_layout.
#   9. Handle errors at each step, log to stderr, exit non-zero on failure.
#
# No per-device branching: every device-specific value comes from the
# device.yml. The hybris patch step is a clearly documented placeholder
# pending P03 research (real wiring lands later).
#
# Usage:
#   build-halium.sh [--work-dir DIR] [--help] <device.yml>
#
# Exit codes:
#   0  Success — boot.img produced (or pipeline completed up to the
#      placeholder hybris step in dry-run contexts).
#   1  Usage error / missing argument / invalid device.yml path.
#   2  YAML parsing error (PyYAML missing or device.yml malformed).
#   3  Work directory creation failure.
#   4  Kernel clone failure.
#   5  Config fragment merge failure.
#   6  Hybris patch step failure (reserved for P03 wiring).
#   7  Cross-compile failure.
#   8  Boot image packaging failure (repack-bootimg.sh).
#   9  Required artifact not found after a step.
#
# Environment:
#   BUILD_HALIUM_INITRAMFS  Override the standard initramfs path
#                           (default: initramfs.cpio.gz relative to
#                           the repository root, or the value from
#                           device.yml if present).
#   CROSS_COMPILE           Override the cross-compile prefix
#                           (default: aarch64-linux-gnu-).

set -eu

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Repository root: directory of this script, resolved to an absolute path.
# POSIX-compliant: avoid readlink -f (not POSIX) — use a portable resolve.
resolve_dir() {
    # $1 = path to a directory. Prints absolute path with symlinks resolved
    # as far as cd allows. Falls back to the literal path if resolution
    # fails.
    ( cd "$1" 2>/dev/null && pwd ) || printf '%s' "$1"
}

SCRIPT_DIR=$(resolve_dir "$(dirname "$0")")
REPO_ROOT=$(resolve_dir "$SCRIPT_DIR/..")

# Standard kernel config fragment, relative to the repository root.
CONFIG_FRAGMENT="$REPO_ROOT/kernel/config-fragment-standard"

# Standard Halium initramfs, relative to the repository root. May be
# overridden by BUILD_HALIUM_INITRAMFS or by a device.yml field (handled
# later, after YAML parsing).
DEFAULT_INITRAMFS="$REPO_ROOT/initramfs.cpio.gz"

# Cross-compile prefix. ARCH is always arm64 for the Halium pipeline.
ARCH="arm64"
CROSS_COMPILE_PREFIX="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Boot image packager, relative to the repository root.
REPACK_SCRIPT="$SCRIPT_DIR/repack-bootimg.sh"

# Exit code namespace (mirrors the header comment).
E_USAGE=1
E_YAML=2
E_WORKDIR=3
E_CLONE=4
E_MERGE=5
E_HYBRIS=6
E_COMPILE=7
E_REPACK=8
E_NOTFOUND=9

# ---------------------------------------------------------------------------
# Logging helpers — stderr only, stdout reserved for machine-parseable
# artifact paths in future CI consumption.
# ---------------------------------------------------------------------------

log() {
    # $@ -> message lines printed to stderr with a [build-halium] prefix.
    printf '[build-halium] %s\n' "$*" 1>&2
}

err() {
    # $@ -> error message to stderr, prefixed with ERROR.
    printf '[build-halium] ERROR: %s\n' "$*" 1>&2
}

die() {
    # $1 = exit code, $2.. = message. Log an error then exit with the code.
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
build-halium.sh — Standard Halium build pipeline for a single device.

Usage:
  build-halium.sh [--work-dir DIR] [--help] <device.yml>

Arguments:
  <device.yml>            Path to a device descriptor YAML file
                          (see device/_schema.yml for the schema).

Options:
  --work-dir DIR          Override the work directory. Default is
                          /tmp/daemoncores-build-<codename>-<pid>.
                          Use this to build in a persistent location
                          (e.g. CI workspace) or to resume a previous
                          build.
  --help, -h              Show this help and exit.

Environment:
  BUILD_HALIUM_INITRAMFS  Override the standard initramfs path
                          (default: initramfs.cpio.gz relative to
                          the repository root, or a device.yml value).
  CROSS_COMPILE           Override the cross-compile prefix
                          (default: aarch64-linux-gnu-).

Pipeline steps:
  1. Validate the device.yml path.
  2. Parse YAML (codename, kernel_repo, defconfig, halium_version,
     partition_layout, optional boot block).
  3. Create the work directory.
  4. Clone kernel_repo (shallow, single branch).
  5. Merge kernel/config-fragment-standard into the device defconfig
     via merge_config.sh from the cloned kernel tree.
  6. Apply Halium hybris patches (PLACEHOLDER — P03 research pending).
  7. Cross-compile ARM64 and detect Image.gz / Image / dtb outputs.
  8. Call scripts/repack-bootimg.sh to assemble boot.img.

Exit codes:
  0  Success.
  1  Usage error / missing or invalid device.yml path.
  2  YAML parsing error (PyYAML missing or malformed device.yml).
  3  Work directory creation failure.
  4  Kernel clone failure.
  5  Config fragment merge failure.
  6  Hybris patch step failure (reserved for P03 wiring).
  7  Cross-compile failure.
  8  Boot image packaging failure.
  9  Required artifact not found after a step.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

WORK_DIR_OVERRIDE=""
DEVICE_YML=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_help
            exit 0
            ;;
        --work-dir)
            if [ $# -lt 2 ]; then
                die "$E_USAGE" "--work-dir requires a directory argument"
            fi
            WORK_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --work-dir=*)
            WORK_DIR_OVERRIDE="${1#--work-dir=}"
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
            if [ -z "$DEVICE_YML" ]; then
                DEVICE_YML="$1"
            else
                die "$E_USAGE" "unexpected extra argument: $1 (only one device.yml is expected)"
            fi
            shift
            ;;
    esac
done

# Accept a trailing positional argument after `--`.
if [ -z "$DEVICE_YML" ] && [ $# -gt 0 ]; then
    DEVICE_YML="$1"
    shift
fi

if [ -z "$DEVICE_YML" ]; then
    err "missing <device.yml> argument"
    printf '[build-halium] Run "%s --help" for usage.\n' "$0" 1>&2
    exit "$E_USAGE"
fi

# Step 1 — validate the device.yml path exists.
if [ ! -f "$DEVICE_YML" ]; then
    die "$E_USAGE" "device.yml not found or not a regular file: $DEVICE_YML"
fi

# Resolve to an absolute path so later cd-based steps do not break.
DEVICE_YML_ABS=$(resolve_dir "$(dirname "$DEVICE_YML")")/$(basename "$DEVICE_YML")
log "device.yml: $DEVICE_YML_ABS"

# ---------------------------------------------------------------------------
# Step 2 — Parse YAML via python3 + PyYAML.
#
# A single python3 invocation extracts every required field and prints
# them as NUL-delimited key=value pairs so the shell can read them without
# worrying about whitespace or special characters in values. If PyYAML is
# missing, python3 exits non-zero and we emit a clear install hint.
# ---------------------------------------------------------------------------

# Fields requested from the Python parser. The partition_layout is a
# nested object; we serialize it back to a compact JSON string on the
# Python side so the shell can pass it through to repack-bootimg.sh
# verbatim. The optional boot block is handled the same way.
#
# Output format: one line per field, "key\tvalue". The Python side
# strips NULs, tabs, and newlines from each value so the shell can
# parse the output line-by-line with `awk -F'\t'` safely. We avoid
# NUL-delimited output because POSIX shells (and bash command
# substitution) silently drop NUL bytes on read.
YAML_PROBE=$(cat <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write(
        "[build-halium] ERROR: PyYAML is not installed.\n"
        "[build-halium]        Install it with one of:\n"
        "[build-halium]          pip install pyyaml\n"
        "[build-halium]          apt install python3-yaml\n"
        "[build-halium]        Then re-run this script.\n"
    )
    sys.exit(2)

import json

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
except Exception as exc:  # noqa: BLE001 — surface any parse error to stderr
    sys.stderr.write(f"[build-halium] ERROR: failed to parse YAML: {exc}\n")
    sys.exit(2)

if not isinstance(data, dict):
    sys.stderr.write("[build-halium] ERROR: device.yml top-level is not a mapping\n")
    sys.exit(2)

required = ["codename", "kernel_repo", "defconfig", "halium_version",
            "partition_layout"]
missing = [k for k in required if k not in data]
if missing:
    sys.stderr.write(
        "[build-halium] ERROR: device.yml missing required field(s): "
        + ", ".join(missing) + "\n"
    )
    sys.exit(2)

# Emit one "key\tvalue" line per field. Nested objects are serialized
# to compact JSON so the shell can forward them unmodified. NULs, tabs,
# and newlines are stripped from the value so a line-based read stays
# aligned (the JSON form already eliminates tabs/newlines via escaping,
# but we strip defensively in case a string field contains them).
def emit(key, value):
    if isinstance(value, (dict, list)):
        value = json.dumps(value, separators=(",", ":"), sort_keys=True)
    text = str(value).replace("\x00", "").replace("\t", " ").replace("\n", " ")
    sys.stdout.write(f"{key}\t{text}\n")

emit("codename", data["codename"])
emit("kernel_repo", data["kernel_repo"])
emit("defconfig", data["defconfig"])
emit("halium_version", data["halium_version"])
emit("partition_layout", data["partition_layout"])
if "boot" in data and data["boot"] is not None:
    emit("boot", data["boot"])
else:
    emit("boot", "")
PYEOF
)

# Run the parser and capture its stdout. We deliberately do NOT use
# set -e for this block: we want to intercept the python3 exit code and
# produce our own die() message. The Python script already prints a
# precise error to stderr.
YAML_STDOUT=$(printf '%s' "$YAML_PROBE" | python3 - "$DEVICE_YML_ABS" 2>&1 1>/tmp/.build-halium-yaml.$$) || {
    # PyYAML missing or YAML malformed: python3 wrote the error to stderr
    # (merged into YAML_OUTPUT because of 2>&1 on the failing command).
    err "YAML parsing failed (exit code $?):"
    printf '%s\n' "$YAML_STDOUT" 1>&2
    rm -f "/tmp/.build-halium-yaml.$$"
    exit "$E_YAML"
}
# On success, the real stdout was redirected to the temp file; move it.
YAML_STDOUT=$(cat /tmp/.build-halium-yaml.$$)
rm -f /tmp/.build-halium-yaml.$$ 2>/dev/null || true

# Helper to read a key from the tab-delimited output.
yaml_get() {
    # $1 = key. Prints the value or empty string if absent.
    key="$1"
    printf '%s\n' "$YAML_STDOUT" | awk -v k="$key" -F'\t' '$1==k {print $2}'
}

CODENAME=$(yaml_get codename)
KERNEL_REPO=$(yaml_get kernel_repo)
DEFCONFIG=$(yaml_get defconfig)
HALIUM_VERSION=$(yaml_get halium_version)
PARTITION_LAYOUT_JSON=$(yaml_get partition_layout)
BOOT_JSON=$(yaml_get boot)

if [ -z "$CODENAME" ] || [ -z "$KERNEL_REPO" ] || [ -z "$DEFCONFIG" ] \
    || [ -z "$HALIUM_VERSION" ] || [ -z "$PARTITION_LAYOUT_JSON" ]; then
    die "$E_YAML" "one or more required YAML fields resolved empty (codename, kernel_repo, defconfig, halium_version, partition_layout)"
fi

log "parsed device descriptor:"
log "  codename        = $CODENAME"
log "  kernel_repo     = $KERNEL_REPO"
log "  defconfig       = $DEFCONFIG"
log "  halium_version  = $HALIUM_VERSION"
log "  partition_layout= <JSON, ${#PARTITION_LAYOUT_JSON} bytes>"
if [ -n "$BOOT_JSON" ]; then
    log "  boot            = <JSON, ${#BOOT_JSON} bytes>"
else
    log "  boot            = <not specified>"
fi

# ---------------------------------------------------------------------------
# Step 3 — Create the work directory.
# ---------------------------------------------------------------------------

PID=$$
if [ -n "$WORK_DIR_OVERRIDE" ]; then
    WORK_DIR="$WORK_DIR_OVERRIDE"
else
    WORK_DIR="/tmp/daemoncores-build-$CODENAME-$PID"
fi

if [ -d "$WORK_DIR" ]; then
    log "work directory already exists, reusing: $WORK_DIR"
else
    mkdir -p "$WORK_DIR" || die "$E_WORKDIR" "failed to create work directory: $WORK_DIR"
    log "created work directory: $WORK_DIR"
fi

# Make all subsequent paths absolute for robustness.
WORK_DIR_ABS=$(resolve_dir "$WORK_DIR")

# ---------------------------------------------------------------------------
# Step 4 — Clone kernel_repo (shallow, single branch).
#
# We do NOT maintain a kernel: the repo is cloned as-is from the upstream
# maintainer (LineageOS priority, then stock, then other). A shallow
# single-branch clone keeps the download small and the build reproducible
# against the default branch of the upstream tree.
# ---------------------------------------------------------------------------

KERNEL_DIR="$WORK_DIR_ABS/kernel"

if [ -d "$KERNEL_DIR/.git" ]; then
    log "kernel already cloned, reusing: $KERNEL_DIR"
else
    log "cloning kernel_repo (shallow, single branch): $KERNEL_REPO"
    # shellcheck disable=SC2086 # we want git to see the URL as one token
    if ! git clone --depth 1 --single-branch "$KERNEL_REPO" "$KERNEL_DIR" 1>&2; then
        die "$E_CLONE" "git clone failed for $KERNEL_REPO"
    fi
    log "kernel cloned to: $KERNEL_DIR"
fi

# ---------------------------------------------------------------------------
# Step 5 — Merge kernel/config-fragment-standard into the device defconfig.
#
# The kernel tree ships scripts/kconfig/merge_config.sh which takes a list
# of config fragment paths and merges them onto a base defconfig, writing
# the merged result to .config. We first build the kconfig tooling
# (merge_config.sh depends on the kernel's scripts/ infrastructure), then
# invoke it with the device defconfig as the base and our standard fragment
# as the overlay.
# ---------------------------------------------------------------------------

if [ ! -f "$CONFIG_FRAGMENT" ]; then
    die "$E_NOTFOUND" "standard config fragment not found: $CONFIG_FRAGMENT (P04 not yet landed?)"
fi
log "config fragment: $CONFIG_FRAGMENT"

MERGE_CONFIG="$KERNEL_DIR/scripts/kconfig/merge_config.sh"
if [ ! -f "$MERGE_CONFIG" ]; then
    # Some vendor trees ship merge_config.sh under scripts/ directly; others
    # require `make scripts` first. Try the canonical path, then build.
    log "merge_config.sh not found at $MERGE_CONFIG — building kconfig scripts"
    if ! make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE_PREFIX" \
            scripts 1>&2; then
        die "$E_MERGE" "failed to build kernel scripts (merge_config.sh unavailable)"
    fi
    if [ ! -f "$MERGE_CONFIG" ]; then
        die "$E_NOTFOUND" "merge_config.sh still missing after `make scripts`: $MERGE_CONFIG"
    fi
fi

# Run the merge from inside the kernel tree so the relative defconfig path
# resolves. merge_config.sh expects fragment paths; we pass our standard
# fragment. The base defconfig is selected first via `make ... defconfig`,
# then the fragment is merged on top.
log "selecting base defconfig: $DEFCONFIG"
( cd "$KERNEL_DIR" \
    && make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE_PREFIX" "$DEFCONFIG" ) \
    1>&2 || die "$E_MERGE" "failed to apply base defconfig $DEFCONFIG"

log "merging standard config fragment onto $DEFCONFIG"
# merge_config.sh reads fragments and merges them into .config in $PWD.
( cd "$KERNEL_DIR" \
    && sh "$MERGE_CONFIG" "$CONFIG_FRAGMENT" ) 1>&2 \
    || die "$E_MERGE" "merge_config.sh failed to merge $CONFIG_FRAGMENT"

log "config merge complete"

# ---------------------------------------------------------------------------
# Step 6 — Apply Halium hybris patches.
#
# PLACEHOLDER: the real hybris patch selection and application logic is
# pending P03 research (which Halium version maps to which patch set, where
# the patch repositories live, how community repos are wired in). The
# function below is a stub so P03 can wire the real logic here without
# changing the pipeline structure.
# ---------------------------------------------------------------------------

apply_hybris_patches() {
    # $1 = halium_version (e.g. "11.0"), $2 = kernel_dir.
    hv="$1"
    kd="$2"
    log "Applying hybris patches for halium_version=$hv (placeholder — P03 research pending)"
    log "  target kernel dir: $kd"
    log "  no patches applied in this step (function is a stub)"
    # P03 will replace this body with real patch discovery + git apply.
    return 0
}

apply_hybris_patches "$HALIUM_VERSION" "$KERNEL_DIR" \
    || die "$E_HYBRIS" "apply_hybris_patches failed (placeholder should not fail — investigate)"

# ---------------------------------------------------------------------------
# Step 7 — Cross-compile ARM64.
#
# The defconfig has already been merged (Step 5 produced .config). We run
# the full build with -j$(nproc) and then probe the canonical output
# locations for the compressed kernel image, the uncompressed image, and
# the device-tree blobs.
# ---------------------------------------------------------------------------

NPROC=$(nproc 2>/dev/null || printf '1')
log "cross-compiling ARM64 with -j$NPROC (this may take a while)"

if ! make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE_PREFIX" \
        -j"$NPROC" 1>&2; then
    die "$E_COMPILE" "kernel cross-compile failed"
fi

# Detect build outputs. Vendor trees vary: some produce arch/arm64/boot/
# Image.gz, some Image, some both. DTBs may be under
# arch/arm64/boot/dts/<vendor>/ or in a flat per-board directory.
BOOT_OUT="$KERNEL_DIR/arch/arm64/boot"
KERNEL_IMAGE=""
for cand in "Image.gz" "Image"; do
    if [ -f "$BOOT_OUT/$cand" ]; then
        KERNEL_IMAGE="$BOOT_OUT/$cand"
        log "detected kernel image: $KERNEL_IMAGE"
        break
    fi
done
if [ -z "$KERNEL_IMAGE" ]; then
    die "$E_NOTFOUND" "no kernel image found under $BOOT_OUT (looked for Image.gz, Image)"
fi

# DTB discovery: prefer a single *.dtb directly under boot/, then the
# common arch/arm64/boot/dts/ tree. The repack script will pick the
# right one from the path we pass; if multiple DTBs exist, we pass the
# whole dts/ directory and let repack-bootimg.sh select.
#
# NOTE: a glob inside `[ -f "$BOOT_OUT"/*.dtb ]` never expands (the whole
# pattern is one quoted argument), so the test would always see a literal
# "*.dtb" path. We iterate the candidates with a POSIX for-loop and break
# on the first match instead.
DTB_PATH=""
found_dtb=""
for cand in "$BOOT_OUT"/*.dtb; do
    # When the glob matches nothing, the shell returns the literal
    # pattern; guard with a real existence check.
    [ -f "$cand" ] || continue
    found_dtb="$cand"
    break
done
if [ -n "$found_dtb" ]; then
    # Single DTB directly under boot/ (rare but supported).
    DTB_PATH="$found_dtb"
    log "detected dtb (flat): $DTB_PATH"
elif [ -d "$BOOT_OUT/dts" ]; then
    DTB_PATH="$BOOT_OUT/dts"
    log "detected dtb directory: $DTB_PATH"
else
    log "WARNING: no dtb output detected under $BOOT_OUT — repack will receive an empty dtb path"
    DTB_PATH=""
fi

# ---------------------------------------------------------------------------
# Step 8 — Assemble boot.img via scripts/repack-bootimg.sh.
#
# repack-bootimg.sh is assumed to exist (P11). It takes the compiled
# kernel, the standard initramfs, the dtb, and the device partition_layout
# and produces a boot.img compatible with the device's mkbootimg layout.
#
# Initramfs resolution order:
#   1. BUILD_HALIUM_INITRAMFS env var (explicit override).
#   2. A path from device.yml's `boot` block if it carries one (future
#      schema extension; not in _schema.yml today, so we leave the hook
#      in place but do not block on it).
#   3. Default: $REPO_ROOT/initramfs.cpio.gz (P11 deliverable).
# ---------------------------------------------------------------------------

INITRAMFS_PATH="${BUILD_HALIUM_INITRAMFS:-$DEFAULT_INITRAMFS}"

if [ ! -f "$INITRAMFS_PATH" ]; then
    die "$E_NOTFOUND" "standard initramfs not found: $INITRAMFS_PATH (P11 not yet landed? set BUILD_HALIUM_INITRAMFS to override)"
fi
log "initramfs: $INITRAMFS_PATH"

if [ ! -x "$REPACK_SCRIPT" ] && [ ! -f "$REPACK_SCRIPT" ]; then
    die "$E_NOTFOUND" "repack-bootimg.sh not found: $REPACK_SCRIPT (P11 not yet landed?)"
fi
log "repack script: $REPACK_SCRIPT"

BOOT_IMG_OUT="$WORK_DIR_ABS/boot.img"

# Invoke the packager. The argument contract is documented in
# scripts/repack-bootimg.sh (P11); we pass:
#   $1 = kernel image path
#   $2 = initramfs path
#   $3 = dtb path (may be empty)
#   $4 = partition_layout (JSON string, forwarded verbatim)
#   $5 = output boot.img path
#   $6 = optional boot block JSON (may be empty)
log "assembling boot.img"
# shellcheck disable=SC2086 # partition_layout JSON must be one arg
if ! sh "$REPACK_SCRIPT" \
        "$KERNEL_IMAGE" \
        "$INITRAMFS_PATH" \
        "$DTB_PATH" \
        "$PARTITION_LAYOUT_JSON" \
        "$BOOT_IMG_OUT" \
        "$BOOT_JSON" 1>&2; then
    die "$E_REPACK" "repack-bootimg.sh failed"
fi

if [ ! -f "$BOOT_IMG_OUT" ]; then
    die "$E_NOTFOUND" "repack-bootimg.sh returned success but boot.img is missing: $BOOT_IMG_OUT"
fi

log "boot.img produced: $BOOT_IMG_OUT"
# Print the final artifact path to stdout for CI consumption.
printf '%s\n' "$BOOT_IMG_OUT"
exit 0