#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""DaemonCores-Phone device ingestion script.

WIP — work in progress. Field names are subject to change pending schema
stabilization (see ``device/_schema.yml``).

Enrich ``device/<codename>/device.yml`` files by running ``aospdtgen`` on a
firmware dump provided by the user, then extracting the VNDK version,
defconfig name, and partition layout from the generated Android device tree.
If ``aospdtgen`` is not installed or fails for a device, that device is
skipped gracefully with an error to stderr and the run continues.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Iterable

import yaml

__all__ = [
    "iter_device_dirs",
    "load_device_yaml",
    "save_device_yaml",
    "run_aospdtgen",
    "extract_from_device_tree",
    "enrich",
    "main",
]

_DEFCONFIG_RE = re.compile(r"([A-Za-z0-9_-]+)_defconfig")
_VNDK_RE = re.compile(r"\b(2[7-9]|3[0-5])\b")


# ---------------------------------------------------------------------------
# Device discovery + YAML I/O
# ---------------------------------------------------------------------------


def iter_device_dirs(device_dir: str) -> Iterable[str]:
    """Yield codename directories under ``device_dir`` that contain a device.yml."""
    if not os.path.isdir(device_dir):
        return
    for entry in sorted(os.listdir(device_dir)):
        if entry.startswith("_"):
            continue
        full = os.path.join(device_dir, entry)
        if os.path.isdir(full) and os.path.isfile(os.path.join(full, "device.yml")):
            yield entry


def load_device_yaml(path: str) -> dict[str, Any]:
    """Load a device.yml file into a dict."""
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        raise ValueError(f"{path}: expected a YAML mapping, got {type(doc).__name__}")
    return doc


def save_device_yaml(path: str, doc: dict[str, Any]) -> None:
    """Write a device dict back to ``path`` preserving the WIP header."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(
            "# WIP — work in progress. Field names subject to change pending "
            "schema stabilization.\n"
        )
        yaml.safe_dump(doc, fh, sort_keys=False, default_flow_style=False)


# ---------------------------------------------------------------------------
# aospdtgen execution
# ---------------------------------------------------------------------------


def run_aospdtgen(
    aospdtgen_bin: str,
    dump_path: str,
    out_dir: str,
    timeout: float = 300.0,
) -> subprocess.CompletedProcess[str]:
    """Run aospdtgen on a firmware dump, writing the device tree to ``out_dir``.

    Raises:
        FileNotFoundError: if the binary is not on PATH.
        subprocess.TimeoutExpired: if the run exceeds ``timeout``.
        subprocess.CalledProcessError: if aospdtgen exits non-zero.
    """
    if shutil.which(aospdtgen_bin) is None and not os.path.isfile(aospdtgen_bin):
        raise FileNotFoundError(f"aospdtgen binary not found: {aospdtgen_bin}")

    cmd = [aospdtgen_bin, dump_path, "-o", out_dir]
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True,
    )


# ---------------------------------------------------------------------------
# Extraction from generated device tree
# ---------------------------------------------------------------------------


def _walk_files(root: str) -> Iterable[str]:
    """Yield absolute file paths under ``root``."""
    for dirpath, _dirs, files in os.walk(root):
        for fname in files:
            yield os.path.join(dirpath, fname)


def _extract_vndk(tree_dir: str) -> str:
    """Extract the VNDK version from the generated device tree.

    Looks for ``BOARD_VNDK_VERSION`` or ``VNDK_VERSION`` in BoardConfig.mk
    and similar files.
    """
    for path in _walk_files(tree_dir):
        if not path.endswith((".mk", ".prop", ".txt")):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
        except OSError:
            continue
        m = re.search(r"BOARD_VNDK_VERSION\s*[:=]\s*(\S+)", text)
        if m:
            return m.group(1).strip("\"'")
        m = re.search(r"VNDK_VERSION\s*[:=]\s*(\S+)", text)
        if m:
            return m.group(1).strip("\"'")
    return ""


def _extract_defconfig(tree_dir: str, codename: str) -> str:
    """Extract the defconfig name from the generated device tree.

    Prefers ``<codename>_defconfig`` if present, otherwise the first
    ``*_defconfig`` reference found in any Makefile / .mk.
    """
    preferred = f"{codename}_defconfig"
    fallback = ""
    for path in _walk_files(tree_dir):
        if not path.endswith((".mk", "Makefile", ".txt", ".json")):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
        except OSError:
            continue
        if preferred in text:
            return preferred
        if not fallback:
            m = _DEFCONFIG_RE.search(text)
            if m:
                fallback = m.group(0)
    return fallback


def _extract_partition_layout(tree_dir: str) -> dict[str, str]:
    """Extract partition layout from the device tree.

    Looks for a fstab.qcom or similar fstab file and maps partition labels
    to their /dev/block/by-name/ paths.
    """
    layout: dict[str, str] = {}
    for path in _walk_files(tree_dir):
        base = os.path.basename(path)
        if not base.startswith("fstab.") and not base.startswith("fstab_"):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split()
                    if len(parts) < 2:
                        continue
                    label = parts[0].lstrip("/")
                    dev_path = parts[1]
                    if label in ("boot", "dtbo", "vendor_boot", "system", "userdata"):
                        layout[label] = dev_path
        except OSError:
            continue
    return layout


def extract_from_device_tree(
    tree_dir: str,
    codename: str,
) -> tuple[str, str, dict[str, str]]:
    """Extract (vndk, defconfig, partition_layout) from a generated device tree.

    Returns empty values for fields that could not be found.
    """
    vndk = _extract_vndk(tree_dir)
    defconfig = _extract_defconfig(tree_dir, codename)
    layout = _extract_partition_layout(tree_dir)
    return vndk, defconfig, layout


# ---------------------------------------------------------------------------
# Enrichment
# ---------------------------------------------------------------------------


def enrich(
    codename: str,
    device_dir: str,
    dump_path: str,
    aospdtgen_bin: str,
) -> bool:
    """Enrich one device.yml via aospdtgen on a firmware dump.

    Returns:
        True if the file was updated, False if skipped.
    """
    yml_path = os.path.join(device_dir, codename, "device.yml")
    try:
        doc = load_device_yaml(yml_path)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        print(f"warn: {codename}: cannot read {yml_path}: {exc}", file=sys.stderr)
        return False

    with tempfile.TemporaryDirectory(prefix=f"aospdtgen-{codename}-") as tmp:
        try:
            run_aospdtgen(aospdtgen_bin, dump_path, tmp)
        except FileNotFoundError as exc:
            print(f"error: {codename}: {exc}", file=sys.stderr)
            return False
        except subprocess.TimeoutExpired:
            print(f"error: {codename}: aospdtgen timed out", file=sys.stderr)
            return False
        except subprocess.CalledProcessError as exc:
            print(f"error: {codename}: aospdtgen failed: {exc.stderr.strip()}", file=sys.stderr)
            return False

        vndk, defconfig, layout = extract_from_device_tree(tmp, codename)

    updated = False
    if vndk:
        doc["vndk"] = vndk
        updated = True
    if defconfig:
        doc["defconfig"] = defconfig
        updated = True
    if layout:
        existing = doc.get("partition_layout") or {}
        existing.update(layout)
        doc["partition_layout"] = existing
        updated = True

    if not updated:
        print(f"warn: {codename}: aospdtgen tree yielded no extractable fields", file=sys.stderr)
        return False

    sources = doc.get("sources") or []
    sources.append({"name": "aospdtgen", "url": dump_path})
    doc["sources"] = sources

    try:
        save_device_yaml(yml_path, doc)
    except OSError as exc:
        print(f"error: {codename}: cannot write {yml_path}: {exc}", file=sys.stderr)
        return False

    print(f"ok: {codename}: vndk={vndk} defconfig={defconfig} partitions={list(layout)}")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Enrich device.yml with VNDK/defconfig/partition_layout from aospdtgen output.",
    )
    parser.add_argument(
        "--device-dir",
        default="device",
        help="Root directory containing device/<codename>/device.yml (default: device/).",
    )
    parser.add_argument(
        "--codename",
        default=None,
        help="Target a single device codename instead of iterating all.",
    )
    parser.add_argument(
        "--dump-path",
        required=True,
        help="Path to the firmware dump (REQUIRED).",
    )
    parser.add_argument(
        "--aospdtgen-bin",
        default="aospdtgen",
        help="aospdtgen binary name or path (default: aospdtgen on PATH).",
    )
    args = parser.parse_args(argv)

    if not os.path.exists(args.dump_path):
        print(f"error: --dump-path does not exist: {args.dump_path}", file=sys.stderr)
        return 1

    if args.codename:
        codenames = [args.codename]
    else:
        codenames = list(iter_device_dirs(args.device_dir))

    if not codenames:
        print("no devices to process", file=sys.stderr)
        return 0

    updated = 0
    for cn in codenames:
        try:
            if enrich(cn, args.device_dir, args.dump_path, args.aospdtgen_bin):
                updated += 1
        except Exception as exc:  # never let one device kill the whole run
            print(f"error: {cn}: unexpected failure: {exc}", file=sys.stderr)

    print(f"done: {updated}/{len(codenames)} updated", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())