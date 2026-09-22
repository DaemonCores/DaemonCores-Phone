# Execution registry

This registry is an evidence checklist for the current roadmap. `DONE` requires an implementation path and a verification path in the repository.

## E01 — Descriptor contract

- Status: `DONE`
- Implementation: `device/_schema.yml`
- Verification still to add: automated schema fixtures in CI.

## E02 — Probe document conversion

- Status: `DONE`
- Implementation: `scripts/probe-to-yaml.py`
- Verification still to add: unit tests and fixture round trips.
- Explicit boundary: no ADB collector exists.

## E03 — Image experiment cleanup

- Status: `OPEN`
- Required outcome: phone-owned labels, sources, packages, and artifact names; no inherited server claims.
- Acceptance evidence: clean Containerfiles plus successful architecture-scoped builds.

## E04 — CI architecture matrix

- Status: `OPEN`
- Required outcome: each Containerfile is built only for supported architectures.
- Acceptance evidence: workflow matrix test and successful native jobs without duplicate full-pipeline invocations.

## E05 — Probe collector

- Status: `OPEN`
- Required outcome: privacy-aware ADB collector emitting the versioned probe JSON format.
- Acceptance evidence: script, fixtures, tests, and command documentation.

## E06 — First device descriptor

- Status: `OPEN`
- Required outcome: one descriptor from an owned, recoverable device.
- Acceptance evidence: `device/<codename>/device.yml`, pinned sources, validation job, and review notes.

## E07 — Kernel build

- Status: `OPEN`
- Required outcome: reproduce the known-good kernel and then apply the minimum reviewed project changes.
- Acceptance evidence: build script, pinned toolchain, final config, logs, and digests.

## E08 — Early userspace

- Status: `OPEN`
- Required outcome: initramfs capable of reaching the selected root filesystem and a recovery shell.
- Acceptance evidence: source tree, automated archive inspection, and captured boot log.

## E09 — Android boot artifact

- Status: `OPEN`
- Required outcome: verified assembly for the selected device's boot format.
- Acceptance evidence: unpack/compare/build scripts, size checks, metadata report, and recovery instructions.

## E10 — Debian rootfs hand-off

- Status: `OPEN`
- Required outcome: reach the DaemonCores userspace on the target device.
- Acceptance evidence: serial or USB log, rootfs version, service state, and artifact digests.

## E11 — Hardware matrix

- Status: `OPEN`
- Required outcome: test each core subsystem independently.
- Acceptance evidence: machine-readable results linked to the exact device, firmware, kernel, and rootfs revisions.

## E12 — Update and rollback

- Status: `OPEN`
- Required outcome: coordinated update and recovery across boot artifacts and OSTree state.
- Acceptance evidence: successful update, deliberate failed update, rollback, and factory recovery tests.

## E13 — Second device

- Status: `BLOCKED` by E06–E12.
- Required outcome: validate that the extracted pipeline is reusable rather than accidentally device-specific.
