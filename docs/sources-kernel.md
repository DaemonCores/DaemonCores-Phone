# Kernel-source acceptance policy

DaemonCores-Phone does not currently maintain a verified device-kernel catalogue. This document defines the evidence required before a kernel source is recorded as usable.

## Source priority

Prefer sources in this order when they are available and buildable for the exact target:

1. vendor-published source corresponding to the installed firmware release;
2. an actively maintained device kernel used by a reproducible Android distribution build;
3. a community kernel with documented device and firmware compatibility;
4. an archived source used only for historical investigation.

Repository popularity or name similarity is not verification.

## Required record

A device descriptor should record or link to:

- exact repository URL;
- immutable commit ID;
- expected toolchain and build environment;
- defconfig path;
- Android and firmware release compatibility;
- kernel version;
- required patch series;
- license information and source-compliance notes;
- successful build log and artifact digest;
- boot evidence for the target device.

## Verification procedure

1. confirm the repository actually contains the target defconfig and device code;
2. check that the source revision matches the target's firmware generation;
3. reproduce the upstream or distribution build before applying project patches;
4. preserve the unmodified build result for comparison;
5. apply patches as a reviewable series;
6. rebuild from a clean environment;
7. compare image format and size with the known-good boot image;
8. test only after recovery and backup procedures are verified.

## Catalogue status

No kernel source is currently marked as verified by this repository because there is no committed device descriptor with corresponding build and boot evidence.

Candidates belong in an issue or pull request until the verification procedure is complete. Once accepted, the canonical record should live in `device/<codename>/device.yml`, not in a free-form list here.
