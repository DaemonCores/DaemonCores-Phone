#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Generate a markdown device status table from all device.yml descriptors.

Reads every ``device/<codename>/device.yml`` in the repository and emits a
markdown table to stdout with one row per device. The table is intended to be
published as a GitHub Release artifact by CI so the device support matrix is
always authoritative and never hand-edited.

Columns (in order):
    codename, vendor, model, status, enabled, maintainer, kernel_source,
    kernel_maintained, security_patches, update_chain, tested_by

Optional fields absent from a descriptor are rendered as ``—`` so partial
descriptors still produce a valid row. Rows are sorted with enabled devices
first, then alphabetically by codename.

``kernel_source`` is derived from the schema's ``kernel_repo`` field (the
column is named ``kernel_source`` in the table per P23, but the data source
is ``kernel_repo``). ``enabled`` is derived from the schema's ``enable``
field (the table column is ``enabled`` per P23; the schema field is
``enable``); absent means the device is not yet enabled in CI builds
(rendered as ``—``).

Example:
    $ python3 scripts/generate-status-table.py
    $ python3 scripts/generate-status-table.py > DEVICE-STATUS.md

Exit codes:
    0  Success — table written to stdout.
    1  No device descriptors found (device/ has no <codename>/device.yml).
    2  A device.yml could not be parsed (YAML error); the offending file is
       reported to stderr and skipped, but processing continues. The exit
       code is set only after all devices are attempted.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml

__all__ = [
    "iter_device_dirs",
    "load_device_yaml",
    "format_cell",
    "build_table",
    "main",
]

# Columns in canonical order (P23).
COLUMNS: tuple[str, ...] = (
    "codename",
    "vendor",
    "model",
    "status",
    "enabled",
    "maintainer",
    "kernel_source",
    "kernel_maintained",
    "security_patches",
    "update_chain",
    "tested_by",
)

# Field name in device.yml that backs the ``kernel_source`` column.
KERNEL_SOURCE_FIELD = "kernel_repo"

# Field name in device.yml that backs the ``enabled`` column.
ENABLED_FIELD = "enable"

ABSENT = "—"


# ---------------------------------------------------------------------------
# Repo layout
# ---------------------------------------------------------------------------


def _repo_root() -> Path:
    """Return the repository root inferred from this script's location.

    The script lives at ``<repo>/scripts/generate-status-table.py``; the
    repository root is therefore one level up from this file's parent.

    Returns:
        Path to the inferred repository root.
    """
    here = Path(__file__).resolve()
    candidate = here.parent.parent
    if not candidate.is_dir():
        raise FileNotFoundError(f"could not infer repository root from {here}")
    return candidate


def iter_device_dirs(repo_root: Path) -> list[Path]:
    """Return the sorted list of ``device/<codename>`` directories.

    A device directory is any direct sub-directory of ``device/`` that
    contains a ``device.yml`` file. The ``_schema.yml`` file lives directly
    in ``device/`` (not in a sub-directory) and is therefore never matched.

    Args:
        repo_root: Path to the repository root.

    Returns:
        Sorted list of device directory paths (each containing device.yml).
    """
    device_root = repo_root / "device"
    if not device_root.is_dir():
        return []
    dirs: list[Path] = []
    for entry in sorted(device_root.iterdir()):
        if entry.is_dir() and (entry / "device.yml").is_file():
            dirs.append(entry)
    return dirs


# ---------------------------------------------------------------------------
# YAML loading
# ---------------------------------------------------------------------------


def load_device_yaml(path: Path) -> dict[str, Any] | None:
    """Load a single device.yml file.

    Args:
        path: Path to the ``device.yml`` file.

    Returns:
        Parsed YAML as a dict, or ``None`` if the file could not be parsed
        (the YAML error is reported to stderr).
    """
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        print(f"warning: skipping {path}: YAML parse error: {exc}", file=sys.stderr)
        return None
    if not isinstance(data, dict):
        print(f"warning: skipping {path}: top-level is not a mapping", file=sys.stderr)
        return None
    return data


# ---------------------------------------------------------------------------
# Table construction
# ---------------------------------------------------------------------------


def format_cell(value: Any) -> str:
    """Render a cell value for the markdown table.

    - ``None`` / missing → ``—``
    - booleans → ``yes`` / ``no``
    - everything else → ``str(value)``, with pipe characters escaped.

    Args:
        value: The raw field value (or ``None``).

    Returns:
        The string to place in the table cell.
    """
    if value is None:
        return ABSENT
    if isinstance(value, bool):
        return "yes" if value else "no"
    text = str(value)
    # Escape pipe characters that would break the markdown table.
    return text.replace("|", "\\|")


def _extract_row(dev_dir: Path, data: dict[str, Any]) -> dict[str, str]:
    """Build a column→cell dict for one device.

    Args:
        dev_dir: The device directory (codename = dir name).
        data: Parsed device.yml content.

    Returns:
        Dict keyed by column name with the rendered cell string.
    """
    # codename: prefer the field, fall back to the directory name.
    codename = data.get("codename") or dev_dir.name
    row: dict[str, str] = {}
    for col in COLUMNS:
        if col == "kernel_source":
            row[col] = format_cell(data.get(KERNEL_SOURCE_FIELD))
        elif col == "enabled":
            row[col] = format_cell(data.get(ENABLED_FIELD))
        elif col == "codename":
            row[col] = format_cell(codename)
        else:
            row[col] = format_cell(data.get(col))
    return row


def _sort_key(row: dict[str, str]) -> tuple[int, str]:
    """Sort key: enabled devices first, then codename alphabetically.

    ``enabled`` is rendered as ``yes``/``no``/``—``. ``yes`` sorts first.
    """
    enabled = row["enabled"]
    # yes -> 0 (first), no -> 1, — -> 2
    enabled_rank = 0 if enabled == "yes" else (1 if enabled == "no" else 2)
    return (enabled_rank, row["codename"].lower())


def build_table(rows: list[dict[str, str]]) -> str:
    """Assemble the markdown table from a list of rendered rows.

    Args:
        rows: List of column→cell dicts (one per device).

    Returns:
        The full markdown table as a string.
    """
    lines: list[str] = []
    header = "| " + " | ".join(COLUMNS) + " |"
    separator = "| " + " | ".join("---" for _ in COLUMNS) + " |"
    lines.append(header)
    lines.append(separator)
    for row in rows:
        lines.append("| " + " | ".join(row[col] for col in COLUMNS) + " |")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """Read all device descriptors and emit the status table to stdout."""
    repo_root = _repo_root()
    dev_dirs = iter_device_dirs(repo_root)
    if not dev_dirs:
        print(
            f"error: no device descriptors found under {repo_root / 'device'}",
            file=sys.stderr,
        )
        return 1

    rows: list[dict[str, str]] = []
    had_parse_error = False
    for dev_dir in dev_dirs:
        data = load_device_yaml(dev_dir / "device.yml")
        if data is None:
            had_parse_error = True
            continue
        rows.append(_extract_row(dev_dir, data))

    if not rows:
        print("error: no valid device descriptors could be parsed", file=sys.stderr)
        return 2

    rows.sort(key=_sort_key)
    sys.stdout.write(build_table(rows))
    return 2 if had_parse_error else 0


if __name__ == "__main__":
    sys.exit(main())