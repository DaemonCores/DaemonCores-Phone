# Halium integration boundary

This document describes the work that remains between the current repository and a Halium-based phone boot. It is a requirements document, not a description of implemented code.

## Inputs already modelled

The device schema can represent several inputs needed by a future build:

- VNDK and intended Halium version;
- kernel repository, defconfig, branch, and image name;
- boot header, page size, base address, command line, and extra `mkbootimg` arguments;
- boot, DTBO, vendor-boot, system, and userdata partitions;
- firmware blobs, kernel modules, expected HAL services, patch sources, and known quirks.

Before use, every value needs provenance and a pinned revision or artifact digest where possible.

## Missing build stages

### Source acquisition

The build must clone an explicit kernel revision, verify that the defconfig exists, fetch the exact compatible patch set, and record every input in the build metadata. Tracking a moving branch is insufficient for reproducible artifacts.

### Kernel configuration

A shared configuration fragment may be useful, but it cannot be assumed to merge cleanly into every downstream Android kernel. The build must report changed symbols, fail on unresolved required options, and retain the final `.config` as an artifact.

### Early userspace

The repository does not contain a Halium initramfs. A future implementation must define how it:

- locates Android partitions;
- exposes vendor firmware and libraries;
- initializes binder-related filesystems and required device nodes;
- mounts or selects the Debian/OSTree root;
- passes control to the real init system;
- enters a recoverable shell when a required step fails.

### Boot-image assembly

Android boot formats vary by header version and device generation. Kernel, ramdisk, DTB, DTBO, and vendor-boot placement must follow the target's existing images and partition limits. The build must unpack a known-good image, compare parameters, assemble the candidate image, and verify its structure before flashing.

### Userspace compatibility

No libhybris or HAL-service integration exists in the current tree. A future layer must state exactly which Android userspace components are required, how they are obtained, how license and redistribution constraints are handled, and which services are expected to start.

### Rootfs updates

The current bootc image work does not establish how OSTree deployments coexist with an Android boot partition, how a kernel and rootfs update remain compatible, or how rollback spans both artifacts. That update contract must be designed before calling the phone system transactional.

## Validation gates

A device pipeline should stop at the first failed gate:

1. schema validation;
2. source and revision verification;
3. kernel configuration audit;
4. reproducible kernel build;
5. boot-image structural verification;
6. partition-size verification;
7. non-destructive boot or documented recovery preparation;
8. captured kernel log;
9. Debian rootfs hand-off;
10. hardware test matrix.

## Recovery requirement

No flashing instructions should be published until the target has a tested recovery path, original partition backups, verified bootloader state, and a clear statement of which operation can erase user data or permanently disable boot.

## Completion criterion

The Halium delta is closed for a device only when the repository contains the implementation and CI that produce a reproducible, verified boot artifact. An architecture document, schema entry, or proposed script name is not completion evidence.
