# Current architecture

## Project boundary

DaemonCores-Phone currently has two partially connected foundations:

1. a metadata layer for describing an Android device and recording source provenance;
2. Debian/bootc image experiments derived from the DaemonCores server-image work.

The device build and boot layers that would connect them have not yet been implemented.

## Implemented components

### Device schema

`device/_schema.yml` is a YAML-encoded JSON Schema document. A device descriptor must currently include:

| Field | Purpose |
| --- | --- |
| `codename` | Stable device identifier and intended directory name. |
| `vendor` and `model` | Human-readable hardware identity. |
| `vndk` | Android native interface level used by the intended compatibility layer. |
| `kernel_repo` | HTTPS GitHub source for the device kernel. |
| `defconfig` | Kernel configuration entry point. |
| `partition_layout` | Boot, DTBO, vendor-boot, and optional system/userdata paths. |
| `halium_version` | Intended Halium compatibility version. |
| `status` | One of `booted`, `partial`, `functional`, or `full`. |
| `sources` | Provenance records for the descriptor. |

Optional sections cover boot-image arguments, firmware blobs, kernel modules, HAL services, patch sources, platform data, and known quirks.

The schema validates shape and vocabulary. It does not prove that a source is trustworthy, that a kernel builds, or that a device boots.

### Probe conversion

`scripts/probe-to-yaml.py`:

- reads an existing JSON object;
- maps known fields into the descriptor shape;
- accepts a codename override;
- fills source dates and default branches where applicable;
- validates the result against `device/_schema.yml`;
- writes YAML to stdout or the requested file.

The repository does not currently contain the `scripts/probe.sh` collector referenced by old documentation. The converter is therefore a transformation and validation tool, not an end-to-end device probe.

### Image experiments

The root contains three image definitions:

- `Containerfile`: an amd64-oriented general Debian bootc image inherited from the base project;
- `Containerfile.minimal.x86_64`: a reduced x86_64 image;
- `Containerfile.minimal.arm64`: a reduced generic ARM64/SBC image using U-Boot tools.

These images exercise bootc, OSTree, networking, and reduced system composition. They do not include the Android boot chain, a vendor kernel, Halium initramfs logic, libhybris, mobile UI, modem integration, or device-specific firmware assembly.

### Package and CI scaffolding

The package manifest builds the bootc foundation and selected Debian repacks. The repository calls the shared DaemonCores full pipeline for packages, images, and ISO artifacts.

The shared image workflow discovers every `Containerfile*` and normally schedules every discovered file for amd64 and arm64. This repository's filenames are architecture-specific, so the current generic discovery model is not yet the final phone build matrix. It must be corrected before published tags can be treated as a support statement.

## Missing device pipeline

A complete device pipeline needs explicit, reviewable stages:

1. collect device metadata and boot-image parameters;
2. validate and commit `device/<codename>/device.yml`;
3. fetch a pinned kernel source and patch set;
4. merge a reviewed kernel configuration;
5. compile the kernel and required modules;
6. construct the early userspace required by the target boot chain;
7. assemble and verify boot, vendor-boot, DTBO, and rootfs artifacts as applicable;
8. provide a reversible flash or test procedure;
9. capture serial/USB boot evidence and hardware test results;
10. publish artifacts only after the device-specific checks pass.

None of those stages should be inferred from the presence of schema fields alone.

## Proposed first vertical slice

The next architecture milestone should target one owned, recoverable device. The goal is not broad compatibility; it is a reproducible path with evidence for every transition:

```text
probe data -> validated descriptor -> pinned sources -> built kernel
-> assembled boot artifact -> recoverable test -> boot log -> rootfs hand-off
```

Only after this path works should the project extract reusable rules for additional devices.

## Support-state policy

The schema's status values need evidence requirements:

| Status | Minimum evidence |
| --- | --- |
| `booted` | Published source revisions, build log, artifact digest, and boot log reaching the project kernel. |
| `partial` | `booted` evidence plus a recorded hardware matrix with at least one working subsystem. |
| `functional` | Repeatable installation/update path and the project's defined core phone functions. |
| `full` | Maintained hardware matrix, recovery path, upgrade tests, and documented remaining limitations. |

No current device descriptor is committed, so the project does not currently claim a supported device.
