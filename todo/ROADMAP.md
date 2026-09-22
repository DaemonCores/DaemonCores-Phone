# Roadmap

Status is based on files and reproducible evidence in the repository. A design document alone does not mark an implementation complete.

## Current baseline

| Item | Status | Evidence |
| --- | --- | --- |
| Device descriptor schema | Implemented | `device/_schema.yml` |
| Probe JSON to descriptor conversion | Implemented | `scripts/probe-to-yaml.py` |
| Debian bootc image experiments | Implemented as experiments | Three root `Containerfile*` files |
| Shared package/image pipeline caller | Present, needs phone-specific matrix | `.github/workflows/pipeline.yml` |
| Real device descriptor | Not started | No `device/<codename>/device.yml` exists |
| End-to-end phone build | Not started | No device build workflow or build script exists |
| Bootable phone artifact | Not started | No `boot.img` pipeline or release evidence exists |

## Phase 1 — make the current foundation testable

- [ ] Add unit tests for `probe-to-yaml.py` covering valid input, missing fields, schema failures, and deterministic output.
- [ ] Add CI validation for every committed device descriptor.
- [ ] Correct inherited image labels and repository URLs.
- [ ] Remove or isolate server-only package and installer assumptions.
- [ ] Replace generic Containerfile discovery with an explicit supported-architecture matrix.
- [ ] Decide whether image experiments remain here or consume `debian-bootc` as a versioned base.

## Phase 2 — implement probe collection

- [ ] Define a versioned probe JSON schema.
- [ ] Implement the ADB collector without requiring root for basic metadata.
- [ ] Separate measured values from inferred or user-supplied values.
- [ ] Redact serial numbers, account data, and other device identifiers by default.
- [ ] Add fixtures captured from owned test devices.
- [ ] Document every command and required Android permission.

## Phase 3 — one-device vertical slice

- [ ] Select one owned device with a tested recovery path and available kernel source.
- [ ] Commit its descriptor with pinned source revisions.
- [ ] Reproduce the known-good kernel build.
- [ ] Define and audit the required configuration changes.
- [ ] Implement kernel and initramfs builds.
- [ ] Implement boot-image unpack, comparison, assembly, and verification.
- [ ] Publish non-destructive test and recovery procedures.
- [ ] Capture the complete boot log and artifact digests.
- [ ] Reach and validate the Debian root filesystem.

## Phase 4 — hardware enablement

- [ ] Define a hardware test manifest.
- [ ] Validate display, touch, storage, USB, networking, audio, sensors, power, suspend, charging, modem, camera, and GPU independently.
- [ ] Record unavailable functions and required proprietary components.
- [ ] Define repeatable `booted`, `partial`, `functional`, and `full` status gates.

## Phase 5 — update and recovery contract

- [ ] Define compatibility between the Android boot artifacts and OSTree deployment.
- [ ] Implement update ordering across both sides.
- [ ] Implement rollback after a failed rootfs or boot-artifact update.
- [ ] Test interrupted updates and storage exhaustion.
- [ ] Document factory-image restoration.

## Phase 6 — generalization

- [ ] Extract reusable rules from the validated first device.
- [ ] Add a second device with meaningfully different hardware and boot format.
- [ ] Introduce ingestion automation only for fields that can be verified.
- [ ] Publish a device catalogue generated from committed descriptors and CI evidence.

## Deferred product layers

- graphical shell and onboarding;
- telephony UX;
- application distribution;
- Waydroid or another Android application-compatibility layer;
- mass device ingestion.

These should begin after the boot, hardware, update, and recovery contracts are working on real devices.
