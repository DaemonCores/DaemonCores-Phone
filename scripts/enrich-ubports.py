#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""DaemonCores-Phone device ingestion script.

WIP — work in progress. Field names are subject to change pending schema
stabilization (see ``device/_schema.yml``).

Enrich ``device/<codename>/device.yml`` files with the VNDK version and
Halium version fetched from the UBports device API. On a 429 or unreachable
API the device is skipped gracefully and a warning is logged to stderr; the
run continues with the next device.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import yaml

__all__ = ["iter_device_dirs", "load_device_yaml", "fetch_ubports", "enrich", "main"]

USER_AGENT = "DaemonCores-Phone-enrich-ubports/0.1 (+https://github.com/DaemonCores/DaemonCores-Phone)"


# ---------------------------------------------------------------------------
# Device discovery + YAML I/O
# ---------------------------------------------------------------------------


def iter_device_dirs(device_dir: str) -> Iterable[str]:
    """Yield codename directories under ``device_dir`` that contain a device.yml.

    The ``_schema.yml`` file at the root of ``device_dir`` is excluded.
    """
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
# UBports API
# ---------------------------------------------------------------------------


def fetch_ubports(api_base: str, codename: str, timeout: float = 30.0) -> dict[str, Any]:
    """Fetch the UBports device document for ``codename``.

    Args:
        api_base: API root, e.g. ``https://api.ubports.com/v1``.
        codename: Device codename.
        timeout: Network timeout in seconds.

    Returns:
        Parsed JSON document from the UBports API.

    Raises:
        HTTPError: on non-2xx responses (caller handles 429/404).
        URLError: on network errors.
    """
    url = f"{api_base.rstrip('/')}/device/{codename}"
    req = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
    return json.loads(raw)


def _extract_vndk_halium(payload: dict[str, Any]) -> tuple[str, str]:
    """Extract (vndk, halium_version) from a UBports device payload.

    The UBports API shape is not fully documented; this helper looks for the
    fields under several common keys and returns the first match. Returns
    empty strings when not found so the caller can skip the update.
    """
    vndk = ""
    for key in ("vndk", "vndkVersion", "vndk_version"):
        val = payload.get(key)
        if val is not None:
            vndk = str(val)
            break
    halium = ""
    for key in ("halium_version", "haliumVersion", "halium"):
        val = payload.get(key)
        if val is not None:
            halium = str(val)
            break
    return vndk, halium


# ---------------------------------------------------------------------------
# Enrichment
# ---------------------------------------------------------------------------


def enrich(
    codename: str,
    device_dir: str,
    api_base: str,
) -> bool:
    """Enrich one device.yml with UBports VNDK/halium_version.

    Returns:
        True if the file was updated, False if skipped.
    """
    yml_path = os.path.join(device_dir, codename, "device.yml")
    try:
        doc = load_device_yaml(yml_path)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        print(f"warn: {codename}: cannot read {yml_path}: {exc}", file=sys.stderr)
        return False

    try:
        payload = fetch_ubports(api_base, codename)
    except HTTPError as exc:
        if exc.code == 429:
            print(f"warn: {codename}: UBports API rate-limited (429), skipping", file=sys.stderr)
        elif exc.code == 404:
            print(f"warn: {codename}: UBports API has no entry for this device (404)", file=sys.stderr)
        else:
            print(f"warn: {codename}: UBports API HTTP {exc.code}, skipping", file=sys.stderr)
        return False
    except (URLError, json.JSONDecodeError, TimeoutError) as exc:
        print(f"warn: {codename}: UBports API unreachable: {exc}, skipping", file=sys.stderr)
        return False

    vndk, halium = _extract_vndk_halium(payload)
    updated = False
    if vndk:
        doc["vndk"] = vndk
        updated = True
    if halium:
        doc["halium_version"] = halium
        updated = True

    if not updated:
        print(f"warn: {codename}: UBports payload had no vndk/halium_version, skipping", file=sys.stderr)
        return False

    try:
        save_device_yaml(yml_path, doc)
    except OSError as exc:
        print(f"error: {codename}: cannot write {yml_path}: {exc}", file=sys.stderr)
        return False

    print(f"ok: {codename}: vndk={vndk} halium_version={halium}")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Enrich device.yml with VNDK/halium_version from the UBports API.",
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
        "--api-base",
        default="https://api.ubports.com/v1",
        help="UBports API root (default: https://api.ubports.com/v1).",
    )
    args = parser.parse_args(argv)

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
            if enrich(cn, args.device_dir, args.api_base):
                updated += 1
        except Exception as exc:  # last-resort guard so one device never kills the run
            print(f"error: {cn}: unexpected failure: {exc}", file=sys.stderr)

    print(f"done: {updated}/{len(codenames)} updated", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())