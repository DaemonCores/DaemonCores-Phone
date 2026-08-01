#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Convert a probe.sh JSON blob into a device.yml descriptor.

Reads a JSON document produced by ``scripts/probe.sh`` (from stdin by default,
or a file via ``--input``) and emits a ``device.yml`` that conforms to
``device/_schema.yml`` (JSON Schema draft 2020-12).

The probe JSON is a flat dict of fields scraped from the connected device
(``getprop``, ``uname``, ``/proc/cpuinfo``, mkbootimg metadata, etc.). This
module maps the probe fields onto the canonical device descriptor schema,
fills the optional Halium fields where the probe exposes them, drops the
ones it cannot populate, and validates the result against the schema before
writing it out.

Configuration is strictly environment-driven (see ``ENVIRONMENT``). No
credentials are read from this file: any token needed to enrich a source URL
is injected by the caller's environment, never hardcoded here.

Example:
    $ ./scripts/probe.sh | python3 scripts/probe-to-yaml.py --codename beryllium \\
        --output device/beryllium/device.yml
    $ python3 scripts/probe-to-yaml.py --input probe.json --codename surya

Environment:
    PROBE_SCHEMA_PATH   Override the path to the JSON Schema file
                        (default: ``device/_schema.yml`` relative to the
                        repository root discovered from this script).
    PROBE_DEFAULT_BRANCH  Default git branch used when a source carries no
                        ``branch`` field (default: ``lineage-22.2``).
    PROBE_TZ_UTC        Force ``date`` fields to UTC (``1``/``0``). Default: on.
    HOME                Standard, used only to locate the repo root fallback.

Exit codes:
    0  Success — device.yml written and validated.
    1  Invalid probe JSON (could not be parsed or missing required keys).
    2  Schema validation failed (the emitted device.yml is non-conformant).
    3  I/O error (input unreadable, output unwritable).
    4  Configuration error (schema file not found / unparseable).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import sys
from pathlib import Path
from typing import Any, Mapping

import jsonschema
import yaml

__all__ = ["build_device_doc", "load_schema", "main"]

# ---------------------------------------------------------------------------
# Schema loading
# ---------------------------------------------------------------------------


def _repo_root() -> Path:
    """Return the repository root inferred from this script's location.

    The script lives at ``<repo>/scripts/probe-to-yaml.py``; the repository
    root is therefore two levels up from this file. This is a heuristic —
    callers may override the schema path via ``PROBE_SCHEMA_PATH``.

    Returns:
        Path to the inferred repository root.

    Raises:
        FileNotFoundError: if the heuristic path does not exist (the caller
            should fall back to ``PROBE_SCHEMA_PATH``).
    """
    here = Path(__file__).resolve()
    candidate = here.parent.parent
    if not candidate.is_dir():
        raise FileNotFoundError(f"could not infer repository root from {here}")
    return candidate


def load_schema(path: Path | None = None) -> Mapping[str, Any]:
    """Load and return the device descriptor JSON Schema.

    The schema is YAML-encoded JSON Schema (draft 2020-12); ``yaml.safe_load``
    parses it into the same dict structure ``jsonschema.validate`` expects.

    Args:
        path: Explicit path to the schema file. When ``None``, the path is
            taken from the ``PROBE_SCHEMA_PATH`` environment variable, else
            from ``<repo>/device/_schema.yml``.

    Returns:
        The parsed schema as a mapping.

    Raises:
        FileNotFoundError: if the resolved schema path does not exist.
        yaml.YAMLError: if the schema file is not valid YAML.
    """
    if path is None:
        env_path = os.environ.get("PROBE_SCHEMA_PATH")
        if env_path:
            path = Path(env_path)
        else:
            try:
                path = _repo_root() / "device" / "_schema.yml"
            except FileNotFoundError as exc:
                raise FileNotFoundError(
                    "could not locate the schema; set PROBE_SCHEMA_PATH"
                ) from exc
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


# ---------------------------------------------------------------------------
# Field mapping
# ---------------------------------------------------------------------------

# Probe field name -> device.yml field name. Keys are the names used by
# probe.sh; values are the canonical schema property names. Optional fields
# that the probe does not provide are simply omitted from the output (the
# schema marks them as non-required).
_DIRECT_FIELDS: tuple[tuple[str, str], ...] = (
    ("codename", "codename"),
    ("vendor", "vendor"),
    ("model", "model"),
    ("soc", "soc"),
    ("platform", "platform"),
    ("vndk", "vndk"),
    ("halium_version", "halium_version"),
    ("android_base_launch", "android_base_launch"),
    ("kernel_repo", "kernel_repo"),
    ("kernel_branch", "kernel_branch"),
    ("defconfig", "defconfig"),
    ("defconfig_parent", "defconfig_parent"),
    ("defconfig_device", "defconfig_device"),
    ("kernel_image_name", "kernel_image_name"),
    ("partition_layout", "partition_layout"),
    ("firmware_blobs", "firmware_blobs"),
    ("kernel_modules_builtin", "kernel_modules_builtin"),
    ("kernel_modules_loadable", "kernel_modules_loadable"),
    ("hal_services", "hal_services"),
    ("hybris_patches", "hybris_patches"),
    ("known_quirks", "known_quirks"),
    ("status", "status"),
    ("notes", "notes"),
)


def _coerce_boot(probe: Mapping[str, Any]) -> dict[str, Any] | None:
    """Map probe boot sub-fields onto the schema ``boot`` object.

    The probe may carry a flat ``boot`` dict (preferred) or a set of
    ``boot_*`` flat keys (legacy probe output). Both shapes are handled.

    Args:
        probe: The raw probe document.

    Returns:
        A dict suitable as the ``boot`` property, or ``None`` when no boot
        field is present in the probe.
    """
    boot = probe.get("boot")
    if isinstance(boot, Mapping):
        return dict(boot)
    flat = {}
    for key in ("header_version", "base_address", "page_size", "cmdline",
                "mkbootimg_args", "partition_size"):
        val = probe.get(f"boot_{key}")
        if val is not None:
            flat[key] = val
    return flat or None


def _coerce_sources(
    probe: Mapping[str, Any], default_branch: str
) -> list[dict[str, Any]] | None:
    """Map probe sources onto the schema ``sources`` array.

    Each probe source must expose at least ``name`` and ``url`` (the two
    schema-required keys). The optional ``branch`` and ``date`` keys are
    forwarded when present, with ``branch`` defaulting to ``default_branch``
    so the CI can pin a ref even when the probe did not record one.

    Args:
        probe: The raw probe document.
        default_branch: Branch to inject when a source lacks ``branch``.

    Returns:
        A list of source dicts, or ``None`` when the probe exposes no
        sources (the caller must then leave ``sources`` to the user).
    """
    raw = probe.get("sources")
    if not raw:
        return None
    if not isinstance(raw, list):
        raise ValueError("probe 'sources' must be a list of objects")
    out: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, Mapping):
            raise ValueError("each probe source must be an object")
        if "name" not in item or "url" not in item:
            raise ValueError("each probe source needs 'name' and 'url'")
        src: dict[str, Any] = {"name": item["name"], "url": item["url"]}
        if "branch" in item and item["branch"]:
            src["branch"] = item["branch"]
        elif default_branch:
            src["branch"] = default_branch
        if "date" in item and item["date"]:
            src["date"] = item["date"]
        else:
            src["date"] = _today_iso()
        out.append(src)
    return out


def _today_iso() -> str:
    """Return today's date in ISO ``YYYY-MM-DD`` form.

    Honours the ``PROBE_TZ_UTC`` environment variable: when set to ``0`` the
    local timezone is used, otherwise UTC (default).

    Returns:
        An ISO date string.
    """
    if os.environ.get("PROBE_TZ_UTC", "1") == "0":
        return _dt.date.today().isoformat()
    return _dt.datetime.now(_dt.timezone.utc).date().isoformat()


def build_device_doc(
    probe: Mapping[str, Any],
    *,
    codename: str | None = None,
    default_branch: str | None = None,
) -> dict[str, Any]:
    """Build a device.yml descriptor from a probe document.

    Walks the probe document, copies every recognised field into the
    canonical descriptor shape, fills defaults where the probe is silent,
    and returns a plain dict ready to be serialised and validated.

    Args:
        probe: The raw probe document (parsed JSON).
        codename: Override for the ``codename`` field. When provided it
            takes precedence over any ``codename`` present in the probe —
            useful when the probe runs against an unlabelled device.
        default_branch: Branch injected into sources that lack one. When
            ``None``, the ``PROBE_DEFAULT_BRANCH`` env var is read, falling
            back to ``lineage-22.2``.

    Returns:
        A dict conforming (before optional-field omission) to
        ``device/_schema.yml``.

    Raises:
        ValueError: if a required field (``codename``, ``vendor``,
            ``model``, ``vndk``, ``kernel_repo``, ``defconfig``,
            ``partition_layout``, ``halium_version``, ``status``,
            ``sources``) cannot be populated.
    """
    if not isinstance(probe, Mapping):
        raise ValueError("probe document must be a JSON object")

    branch = default_branch or os.environ.get(
        "PROBE_DEFAULT_BRANCH", "lineage-22.2"
    )

    doc: dict[str, Any] = {}

    # Direct 1:1 copies (only carried over when the probe exposes them).
    for probe_key, doc_key in _DIRECT_FIELDS:
        if probe_key in probe and probe[probe_key] is not None:
            doc[doc_key] = probe[probe_key]

    # codename override (CLI argument wins).
    if codename:
        doc["codename"] = codename

    # boot sub-object (flat or nested).
    boot = _coerce_boot(probe)
    if boot:
        doc["boot"] = boot

    # sources array (defaults applied).
    sources = _coerce_sources(probe, branch)
    if sources is not None:
        doc["sources"] = sources

    # Required-field sanity (the schema validator gives the precise error,
    # but a clear up-front message helps the user fix the probe).
    required = (
        "codename", "vendor", "model", "vndk", "kernel_repo",
        "defconfig", "partition_layout", "halium_version", "status",
        "sources",
    )
    missing = [f for f in required if f not in doc or doc[f] in (None, "", [])]
    if missing:
        raise ValueError(
            "probe is missing required fields: " + ", ".join(missing)
        )

    return doc


# ---------------------------------------------------------------------------
# Serialisation + validation
# ---------------------------------------------------------------------------


def dump_yaml(doc: Mapping[str, Any], stream) -> None:
    """Serialise ``doc`` as YAML to ``stream``.

    Uses ``yaml.safe_dump`` with deterministic ordering (``sort_keys=False``)
    so the emitted file mirrors the dict insertion order produced by
    :func:`build_device_doc`, keeping diffs reviewable across probe runs.

    Args:
        doc: The device descriptor dict.
        stream: A writable text stream (e.g. an open file or ``sys.stdout``).
    """
    yaml.safe_dump(
        dict(doc),
        stream,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
        width=100,
    )


def validate_or_die(doc: Mapping[str, Any], schema: Mapping[str, Any]) -> None:
    """Validate ``doc`` against ``schema`` and exit on failure.

    Args:
        doc: The device descriptor dict.
        schema: The parsed JSON Schema (draft 2020-12).

    Raises:
        SystemExit: with code 2 and the validator's error message when the
            document does not conform to the schema.
    """
    try:
        jsonschema.validate(instance=doc, schema=schema)
    except jsonschema.ValidationError as exc:
        sys.stderr.write(f"schema validation failed: {exc.message}\n")
        if exc.absolute_path:
            sys.stderr.write(
                "at path: " + "/".join(str(p) for p in exc.absolute_path) + "\n"
            )
        raise SystemExit(2) from exc


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_arg_parser() -> argparse.ArgumentParser:
    """Build and return the argparse parser for this script.

    Returns:
        The configured ``argparse.ArgumentParser``.
    """
    p = argparse.ArgumentParser(
        prog="probe-to-yaml.py",
        description=(
            "Convert a probe.sh JSON blob into a schema-valid device.yml."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--input", "-i", type=Path, default=None,
        help="path to the probe JSON file (default: stdin)",
    )
    p.add_argument(
        "--output", "-o", type=Path, default=None,
        help="path to write the device.yml (default: stdout)",
    )
    p.add_argument(
        "--codename", "-c", default=None,
        help="override the device codename (required if absent from probe)",
    )
    p.add_argument(
        "--schema", "-s", type=Path, default=None,
        help="path to the JSON Schema file (default: device/_schema.yml)",
    )
    p.add_argument(
        "--default-branch", default=None,
        help=(
            "branch injected into sources lacking one "
            "(default: $PROBE_DEFAULT_BRANCH or lineage-22.2)"
        ),
    )
    p.add_argument(
        "--dry-run", action="store_true",
        help="validate only; do not write any file",
    )
    return p


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Parses arguments, reads the probe document, builds the descriptor,
    validates it against the schema, and writes it to the requested output.

    Args:
        argv: Optional argument list (defaults to ``sys.argv[1:]``).

    Returns:
        Process exit code (see module docstring for the code table).
    """
    args = _build_arg_parser().parse_args(argv)

    # --- load schema ---
    try:
        schema = load_schema(args.schema)
    except FileNotFoundError as exc:
        sys.stderr.write(f"configuration error: {exc}\n")
        return 4
    except yaml.YAMLError as exc:
        sys.stderr.write(f"configuration error: schema is not valid YAML: {exc}\n")
        return 4

    # --- read probe ---
    try:
        if args.input is None:
            raw = sys.stdin.read()
        else:
            raw = args.input.read_text(encoding="utf-8")
    except OSError as exc:
        sys.stderr.write(f"input error: {exc}\n")
        return 3

    try:
        probe = json.loads(raw)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"input error: probe is not valid JSON: {exc}\n")
        return 1

    # --- build descriptor ---
    try:
        doc = build_device_doc(
            probe, codename=args.codename, default_branch=args.default_branch
        )
    except ValueError as exc:
        sys.stderr.write(f"input error: {exc}\n")
        return 1

    # --- validate ---
    validate_or_die(doc, schema)

    if args.dry_run:
        return 0

    # --- write ---
    try:
        if args.output is None:
            dump_yaml(doc, sys.stdout)
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("w", encoding="utf-8") as fh:
                dump_yaml(doc, fh)
    except OSError as exc:
        sys.stderr.write(f"output error: {exc}\n")
        return 3

    return 0


if __name__ == "__main__":
    raise SystemExit(main())