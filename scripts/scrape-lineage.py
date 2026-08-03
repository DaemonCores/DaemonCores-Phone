#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""DaemonCores-Phone device ingestion script.

WIP — work in progress. Field names are subject to change pending schema
stabilization (see ``device/_schema.yml``).

Scrape the LineageOS Hudson devices JSON and emit a ``device.yml`` skeleton
for every device, under ``device/<codename>/device.yml``. The skeleton
populates only the fields available from Hudson (codename, vendor, model);
the Halium-specific fields (vndk, kernel_repo, defconfig, partition_layout,
halium_version) are left empty for the enrichment scripts to fill in.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from typing import Any, Iterable
from urllib.error import URLError
from urllib.request import Request, urlopen

import yaml

__all__ = ["fetch_hudson_devices", "build_skeleton", "write_device_yaml", "main"]

HUDSON_URL = "https://github.com/LineageOS/hudson/raw/main/updater/devices.json"
USER_AGENT = "DaemonCores-Phone-scrape-lineage/0.1 (+https://github.com/DaemonCores/DaemonCores-Phone)"


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------


def fetch_hudson_devices(url: str, timeout: float = 30.0) -> list[dict[str, Any]]:
    """Fetch and parse the Hudson devices.json array.

    Args:
        url: URL of the Hudson devices JSON file.
        timeout: Network timeout in seconds.

    Returns:
        List of device dicts (manufacturer, name, codename, model, status...).

    Raises:
        URLError: if the fetch fails.
        json.JSONDecodeError: if the response is not valid JSON.
    """
    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError(f"expected a JSON array from {url}, got {type(data).__name__}")
    return data


# ---------------------------------------------------------------------------
# Skeleton construction
# ---------------------------------------------------------------------------


def build_skeleton(device: dict[str, Any]) -> dict[str, Any]:
    """Build a device.yml skeleton dict from a Hudson device entry.

    Only fields available from Hudson are populated. The Halium-specific
    fields required by the schema are set to empty strings so the resulting
    YAML is structurally complete and the enrichment scripts can fill them.

    Args:
        device: A Hudson device dict with keys manufacturer, name, codename,
            model, status.

    Returns:
        A dict matching the top-level required keys of device/_schema.yml.
    """
    codename = str(device.get("codename", "")).strip()
    vendor = str(device.get("manufacturer", "")).strip()
    model = str(device.get("model", device.get("name", ""))).strip()

    return {
        "codename": codename,
        "vendor": vendor,
        "model": model,
        "vndk": "",
        "kernel_repo": "",
        "defconfig": "",
        "partition_layout": {
            "boot": "",
            "dtbo": "",
            "vendor_boot": "",
        },
        "halium_version": "",
        "status": "booted",
        "sources": [
            {
                "name": "lineageos_hudson",
                "url": HUDSON_URL,
                "date": date.today().isoformat(),
            }
        ],
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def write_device_yaml(
    codename: str,
    doc: dict[str, Any],
    output_dir: str,
    force: bool,
    dry_run: bool,
) -> str | None:
    """Write one device.yml skeleton to disk.

    Args:
        codename: Device codename (used for the directory name).
        doc: Skeleton dict produced by :func:`build_skeleton`.
        output_dir: Root directory under which ``<codename>/device.yml`` is
            created.
        force: If True, overwrite an existing device.yml.
        dry_run: If True, do not write anything; return the would-be path.

    Returns:
        The path that was written (or would be written in dry-run mode),
        or ``None`` if the file was skipped because it already exists and
        ``force`` is False.
    """
    target_dir = os.path.join(output_dir, codename)
    target_file = os.path.join(target_dir, "device.yml")

    if os.path.exists(target_file) and not force:
        print(
            f"skip {codename}: {target_file} already exists (use --force to overwrite)",
            file=sys.stderr,
        )
        return None

    if dry_run:
        print(f"dry-run: would write {target_file}")
        return target_file

    os.makedirs(target_dir, exist_ok=True)
    with open(target_file, "w", encoding="utf-8") as fh:
        fh.write(
            "# WIP — work in progress. Field names subject to change pending "
            "schema stabilization.\n"
        )
        yaml.safe_dump(doc, fh, sort_keys=False, default_flow_style=False)
    return target_file


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def _iter_devices(devices: list[dict[str, Any]]) -> Iterable[dict[str, Any]]:
    """Yield only device entries that have a non-empty codename."""
    for dev in devices:
        cn = str(dev.get("codename", "")).strip()
        if not cn:
            print("skip entry: empty codename", file=sys.stderr)
            continue
        yield dev


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Returns:
        0 on success, 1 on fetch error, 2 on partial failure (some devices
        skipped due to errors but the run continued).
    """
    parser = argparse.ArgumentParser(
        description="Scrape LineageOS Hudson JSON into device.yml skeletons.",
    )
    parser.add_argument(
        "--output-dir",
        default="device",
        help="Root directory for device/<codename>/device.yml (default: device/).",
    )
    parser.add_argument(
        "--url",
        default=HUDSON_URL,
        help="Override the Hudson devices.json URL.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write any file; print what would be written.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing device.yml files.",
    )
    args = parser.parse_args(argv)

    try:
        devices = fetch_hudson_devices(args.url)
    except (URLError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: failed to fetch Hudson devices: {exc}", file=sys.stderr)
        return 1

    written = 0
    skipped = 0
    for dev in _iter_devices(devices):
        codename = str(dev.get("codename", "")).strip()
        try:
            skeleton = build_skeleton(dev)
            path = write_device_yaml(
                codename,
                skeleton,
                args.output_dir,
                args.force,
                args.dry_run,
            )
        except OSError as exc:
            print(f"error: {codename}: {exc}", file=sys.stderr)
            skipped += 1
            continue
        if path is not None:
            written += 1
        else:
            skipped += 1

    print(f"done: {written} written, {skipped} skipped", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())