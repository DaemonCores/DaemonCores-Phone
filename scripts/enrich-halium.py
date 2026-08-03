#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""DaemonCores-Phone device ingestion script.

WIP — work in progress. Field names are subject to change pending schema
stabilization (see ``device/_schema.yml``).

Enrich ``device/<codename>/device.yml`` files with ``kernel_repo`` and
``defconfig`` fetched from the Halium project manifests. The Halium
manifests are XML files (repo manifest format) hosted under the Halium
GitHub organisation; this script fetches the default manifest and any
per-device manifest, greps for the kernel project + its defconfig reference,
and writes the values back into the device descriptor. Devices with no
Halium manifest are skipped gracefully with a warning to stderr.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import yaml

__all__ = [
    "iter_device_dirs",
    "load_device_yaml",
    "save_device_yaml",
    "fetch_manifest",
    "extract_kernel_from_manifest",
    "enrich",
    "main",
]

DEFAULT_MANIFEST_BASE = "https://github.com/Halium/repo-manifest"
USER_AGENT = "DaemonCores-Phone-enrich-halium/0.1 (+https://github.com/DaemonCores/DaemonCores-Phone)"
RAW_BASE = "https://raw.githubusercontent.com/Halium/repo-manifest/main"

# defconfig filename convention: <name>_defconfig
_DEFCONFIG_RE = re.compile(r"([A-Za-z0-9_-]+)_defconfig")


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
# Manifest fetching
# ---------------------------------------------------------------------------


def _raw_url_for(path: str) -> str:
    """Build a raw.githubusercontent URL for a path in the Halium repo-manifest."""
    return f"{RAW_BASE}/{path.lstrip('/')}"


def fetch_manifest(url: str, timeout: float = 30.0) -> str:
    """Fetch a manifest file as text.

    Raises:
        HTTPError: on non-2xx.
        URLError: on network error.
    """
    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


# ---------------------------------------------------------------------------
# Kernel extraction from repo manifest XML
# ---------------------------------------------------------------------------


def extract_kernel_from_manifest(
    xml_text: str,
    codename: str,
) -> tuple[str, str]:
    """Extract (kernel_repo, defconfig) from a repo manifest XML.

    The Halium manifests list projects with ``name`` attributes such as
    ``android_kernel_xiaomi_sdm845``; the kernel repo URL is reconstructed
    as ``https://github.com/< Halium | vendor >/<name>``. The defconfig is
    inferred from the codename (``<codename>_defconfig``) when the kernel
    project is present, since the manifest itself does not carry the
    defconfig name.

    Returns:
        (kernel_repo_url, defconfig) or ("", "") if no kernel project found.
    """
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as exc:
        raise ValueError(f"manifest XML parse error: {exc}") from exc

    kernel_repo = ""
    for project in root.iter("project"):
        name = project.get("name", "")
        if "kernel" in name.lower():
            remote = project.get("remote", "")
            repo_url = project.get("url", "")
            if repo_url:
                kernel_repo = repo_url
            elif name:
                # Reconstruct from the common Halium github org
                kernel_repo = f"https://github.com/{remote or 'Halium'}/{name}"
            break

    defconfig = ""
    if kernel_repo:
        # Prefer <codename>_defconfig, fall back to a platform-derived guess
        defconfig = f"{codename}_defconfig"
        if not _DEFCONFIG_RE.match(defconfig):
            defconfig = ""

    return kernel_repo, defconfig


# ---------------------------------------------------------------------------
# Enrichment
# ---------------------------------------------------------------------------


def enrich(
    codename: str,
    device_dir: str,
    manifest_base: str,
) -> bool:
    """Enrich one device.yml with kernel_repo + defconfig from Halium manifests.

    Tries, in order:
      1. ``<manifest_base>/device/<codename>.xml`` (per-device manifest)
      2. ``<manifest_base>/default.xml`` (shared manifest)

    Returns:
        True if the file was updated, False if skipped.
    """
    yml_path = os.path.join(device_dir, codename, "device.yml")
    try:
        doc = load_device_yaml(yml_path)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        print(f"warn: {codename}: cannot read {yml_path}: {exc}", file=sys.stderr)
        return False

    candidate_urls = [
        f"{manifest_base.rstrip('/')}/device/{codename}.xml",
        f"{manifest_base.rstrip('/')}/default.xml",
    ]

    kernel_repo = ""
    defconfig = ""
    for url in candidate_urls:
        try:
            xml_text = fetch_manifest(url)
        except HTTPError as exc:
            if exc.code == 404:
                continue
            print(f"warn: {codename}: {url} HTTP {exc.code}", file=sys.stderr)
            continue
        except (URLError, TimeoutError) as exc:
            print(f"warn: {codename}: {url} unreachable: {exc}", file=sys.stderr)
            continue

        try:
            kernel_repo, defconfig = extract_kernel_from_manifest(xml_text, codename)
        except ValueError as exc:
            print(f"warn: {codename}: {url}: {exc}", file=sys.stderr)
            continue

        if kernel_repo:
            break

    if not kernel_repo:
        print(f"warn: {codename}: no Halium manifest found, skipping", file=sys.stderr)
        return False

    doc["kernel_repo"] = kernel_repo
    if defconfig:
        doc["defconfig"] = defconfig

    # Record provenance
    sources = doc.get("sources") or []
    sources.append(
        {
            "name": "halium_manifest",
            "url": manifest_base,
        }
    )
    doc["sources"] = sources

    try:
        save_device_yaml(yml_path, doc)
    except OSError as exc:
        print(f"error: {codename}: cannot write {yml_path}: {exc}", file=sys.stderr)
        return False

    print(f"ok: {codename}: kernel_repo={kernel_repo} defconfig={defconfig}")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Enrich device.yml with kernel_repo + defconfig from Halium manifests.",
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
        "--manifest-base",
        default=DEFAULT_MANIFEST_BASE,
        help=f"Halium repo-manifest URL base (default: {DEFAULT_MANIFEST_BASE}).",
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
            if enrich(cn, args.device_dir, args.manifest_base):
                updated += 1
        except Exception as exc:  # never let one device kill the whole run
            print(f"error: {cn}: unexpected failure: {exc}", file=sys.stderr)

    print(f"done: {updated}/{len(codenames)} updated", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())