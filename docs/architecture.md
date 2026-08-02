# DaemonCores-Phone Architecture

**Halium standard pipeline on a Debian Trixie + bootc/OSTree base, for Android smartphones.**

This document describes the architecture of DaemonCores-Phone: the founding principle, the
`device.yml` contract, the standard Halium build pipeline, the bootc/OSTree base image, the
Waydroid Android compatibility layer, the device ingestion flow, and the CI split with
DaemonCores-CI.

---

## 1. Project Overview

DaemonCores-Phone is a Linux distribution for smartphones built on four pillars:

1. **Halium standard** — proprietary Android drivers run unmodified via libhybris, the same
   approach used by UBports and Droidian. No reverse engineering, no mainline port per device.
2. **Standard CI pipeline** — a single workflow builds every device. The CI scrapes existing
   sources (LineageOS hudson, UBports, Halium manifests, pmOS wiki, `dumpyara`/`aospdtgen`),
   produces a `device.yml`, runs the generic Halium pipeline, and publishes a `boot.img` plus the
   Debian bootc/OSTree rootfs. No manual port, no special cases.
3. **Debian Trixie + bootc/OSTree** — atomic updates, rollback, and the entire Debian ecosystem
   on the rootfs. The kernel + initramfs live in the Android `boot.img`; the userspace is a
   bootc/OSTree image applied atomically to the device.
4. **Waydroid** — Android app compatibility via LineageOS-based container images, with native
   Halium support (vendor images stripped of Mesa GPU drivers). Source: docs.waydro.id,
   github.com/waydroid/waydroid/releases

The project targets **600+ devices** from a single pipeline — an order of magnitude more than
manual-port projects (postmarketOS ~200–300, UBports 111) — because it reuses vendor kernels and
the Halium compatibility layer instead of porting each device to mainline.

---

## 2. Founding Principle (NON-NEGOTIABLE)

> Halium for ALL devices. Standard and autonomous CI pipeline. The CI scrapes existing sources
> → `device.yml` → generic Halium pipeline → `boot.img`. No per-SoC strategy. No per-device
> kernel maintained. No special cases.

This principle drives every architectural decision below. Anything that would require
per-device kernel work, per-SoC strategy, or a special case is rejected.

---

## 3. Repository Split

| Repository | Role | Contents |
|---|---|---|
| **DaemonCores-Phone** (this repo) | Source of truth | `device.yml` descriptors, build scripts (`scripts/build-halium.sh`, `scripts/repack-bootimg.sh`), ingestion scripts (`scripts/scrape-lineage.py`, `scripts/enrich-ubports.py`, `scripts/enrich-halium.py`, `scripts/enrich-aospdtgen.py`), the ADB probe (`scripts/probe.sh`), the kernel config fragment (`kernel/config-fragment-standard`), the `Containerfile`, the initramfs (`src/initramfs/`), and the docs |
| **DaemonCores-CI** | Execution | The CI workflows (`workflows/build-device.yml`, `workflows/ingest-devices.yml`) and the ARM/AMD build matrices that call the scripts in this repo |

This repo does **not** contain CI workflows. The scripts are here; the workflows that invoke them
live in DaemonCores-CI. This separation keeps the source of truth forkable and reviewable
independently of the execution infrastructure.

---

## 4. The `device.yml` Contract

Every supported device is described by a single `device/<codename>/device.yml` file. This file is
the input to the standard pipeline. It is validated against
[`device/_schema.yml`](_schema.yml) (JSON Schema draft 2020-12) by CI — an invalid descriptor is
rejected before any build runs.

### Required fields

| Field | Type | Purpose |
|---|---|---|
| `codename` | string (`^[a-z0-9_]+$`) | Device codename (e.g. `beryllium`); must match the directory name |
| `vendor` | string | Manufacturer (e.g. `Xiaomi`) |
| `model` | string | Commercial model name (e.g. `POCO F1`) |
| `vndk` | string (`^(2[7-9]\|3[0-5]\|current)$`) | Android VNDK version. **Critical**: determines the Halium version and the hybris patch set |
| `kernel_repo` | URI (`^https://github\.com/`) | Git URL of the vendor kernel. LineageOS priority |
| `defconfig` | string (`^[a-zA-Z0-9_-]+_defconfig$`) | Kernel defconfig (relative to `arch/arm64/configs/`) |
| `partition_layout` | object | Boot image assembly: `boot`, `dtbo`, `vendor_boot` (Android 11+), optional `system`, `userdata` |
| `halium_version` | enum (`7.1`–`14.0`) | Halium version, derived from VNDK. Determines the hybris patch set |
| `status` | enum (`booted`/`partial`/`functional`/`full`) | Transparent device support status |
| `sources` | array (min 1) | Provenance of each field: `lineageos_hudson`, `ubports_api`, `halium_manifest`, `aospdtgen`, `adb_probe`, `community_pr` |
| `notes` | string (optional) | Free-form quirks, known issues, special instructions |

### Why VNDK, not Android version

The decisive field is `vndk`, not the Android version displayed on the device. Google now allows
vendors to run a newer Android on top of an older VNDK; the VNDK defines the native API surface
that Halium must match. A OnePlus 11 running Android 15 reports VNDK 33 (Android 13), and the
`device.yml` must record `vndk: "33"` / `halium_version: "13.0"`. The `vndk` is obtained via
`adb shell getprop | grep vndk` (ADB probe) or from a firmware dump (`aospdtgen`).

### Device status

Each `device.yml` carries a transparent status so users know what to expect before flashing:

| Status | Meaning |
|---|---|
| `booted` | The kernel boots, that's it |
| `partial` | Network or audio works |
| `functional` | Usable daily |
| `full` | Everything works |

---

## 5. Standard Halium Build Pipeline

The pipeline is **generic**: the same script runs for every device, parameterised only by the
`device.yml`. There is no per-device branch in the build logic.

```
┌─────────────────────────┐
│  device.yml (input)     │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│  scripts/build-halium.sh│
│  1. Clone kernel_repo   │
│  2. Merge config-       │
│     fragment-standard   │
│     (Waydroid + mobile + │
│      Halium) into the    │
│      device defconfig    │
│  3. Apply Halium hybris  │
│     patches             │
│  4. Cross-compile ARM64  │
│  5. Assemble boot.img    │
│     (kernel + initramfs  │
│      + DTB)              │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│  GitHub Releases        │
│  - boot.img             │
│  - Debian bootc/OSTree  │
│    rootfs               │
└─────────────────────────┘
```

### `scripts/build-halium.sh`

The single build entry point. It takes a `device.yml` as input and performs:

1. **Clone `kernel_repo`** — the vendor kernel (LineageOS priority, then stock, then other).
   We maintain **no kernel**: the repo is cloned as-is from the upstream maintainer.
2. **Merge `kernel/config-fragment-standard`** into the device `defconfig` via
   `merge_config.sh`. The fragment carries the Waydroid dependencies, the mobile optimisations,
   and the Halium hybris requirements (see §6).
3. **Apply Halium hybris patches** — the standard hybris patch set for the `halium_version`
   declared in the `device.yml`. The patch set is selected by the VNDK-derived version, not by
   the device.
4. **Cross-compile ARM64** — `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`.
5. **Assemble `boot.img`** — kernel + standard Halium initramfs + DTB, packaged with
   `mkbootimg` (`scripts/repack-bootimg.sh`).

### `scripts/repack-bootimg.sh`

Packages the compiled kernel, the standard Halium initramfs, and the DTB into an Android
`boot.img` compatible with the device's `partition_layout`.

### Kernel strategy: zero maintenance

> We prefer a kernel developed by a random contributor that applies recent security patches over
> an old official kernel that is obsolete and has security holes.

The pipeline **does not recompile a kernel per device**. A single global kernel is built per major
version, and device support is added via an external kernel module package that plugs into the
global block. If there is nothing to optimise or fix in the kernel output of the external
device-support module, the pipeline does not rebuild it — it builds on an already-packaged,
functional source.

LineageOS maintains vendor kernels for 100+ devices with monthly backports of the Android
Security Bulletin (ASB). The pipeline reuses that work: the `kernel_repo` field points at the
LineageOS kernel repo, and the security patches flow automatically with each rebuild.

---

## 6. Kernel Config Fragment (`kernel/config-fragment-standard`)

A single standard config fragment is merged into **every** device's `defconfig`. It carries three
categories of options required across the whole fleet:

### Waydroid dependencies

```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_PSI=y
CONFIG_IPV6=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_NAMESPACES=y
```

### Mobile optimisations

- **CPUFreq** — dynamic CPU frequency scaling
- **CPUIdle** — idle states for power saving
- **Runtime PM** — runtime power management
- **Suspend/Resume** — sleep/wake support
- **GPU DRM/MSM** — Qualcomm display stack
- **Modem** — `QMI_WWAN`, `MBIM` for cellular data
- **IIO sensors** — accelerometer, proximity, light sensors
- **HID I2C/SPI** — touchscreens and other HID peripherals

### Halium hybris requirements

The hybris patch set needs the binder and ashmem (or binderfs on newer kernels) infrastructure
enabled. The fragment consolidates these so a single merge step covers Waydroid, mobile, and
Halium at once.

---

## 7. Boot Flow

DaemonCores-Phone boots through the Android bootloader chain, then hands off to a Linux
initramfs that mounts the Debian bootc/OSTree rootfs:

```
┌─────────────────────────────┐
│  Android bootloader        │
│  (device-specific: aboot,  │
│   XBL, U-Boot, etc.)        │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│  boot.img                   │
│  - Halium-patched kernel    │
│  - Standard Halium initramfs│
│  - DTB                      │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│  Halium initramfs           │
│  (src/initramfs/)           │
│  - Linux init               │
│  - overlayfs mount scripts  │
│  - Auto-detection at boot:  │
│    * droid-card (audio)     │
│    * partitions              │
│    * vendor HALs             │
└──────────────┬──────────────┘
               ▼
┌─────────────────────────────┐
│  Debian Trixie rootfs       │
│  (bootc/OSTree)             │
│  systemd multi-user.target  │
└─────────────────────────────┘
```

### Standard Halium initramfs (`src/initramfs/`)

The initramfs is **the same for all devices**. It performs the Halium standard early boot:

- **Linux init** — standard systemd-based init
- **overlayfs mount scripts** — mount the Android vendor partitions as read-only overlays
- **Auto-detection at boot** — the config layer is largely self-resolving at runtime:
  - `droid-card` reads the audio config from `/vendor/etc/audio_policy.conf` or
    `/system/etc/audio_policy.conf` at every service start — no config file to generate
  - Partition layout from `/dev/block/by-name/`
  - Vendor properties via `getprop`
  - Available HALs from `/vendor/lib*/hw/`

What is **not** auto-detected — and is the real gate — is the kernel. It must be compiled with
the Halium patches, the right `defconfig`, and packaged in a `boot.img` with the Halium initramfs
**before** the first boot. No detection produces a booting kernel; that work happens upstream, at
build time, in the standard pipeline.

---

## 8. bootc/OSTree Base Image

The rootfs is a Debian Trixie ARM64 image built with bootc/OSTree, adapted from the
[debian-bootc](https://github.com/DaemonCores/debian-bootc) base. The bootc/OSTree model is
preserved: the entire OS is built as an OCI container image, applied atomically to the device, and
fully rollback-capable.

| Component | Role |
|---|---|
| **bootc / ostree** | Atomic OS management, content-addressed filesystem, rollback |
| **composefs** | fs-verity integrity protection for the deployed OS tree |
| **dracut** | Initramfs generator (the Halium initramfs is a dracut output) |
| **Debian Trixie ARM64** | Userspace base — the full Debian ecosystem on the phone |

The base image provides a fully supported CLI boot. The UI and user-friendliness are a separate
Phase 2 (see [Roadmap](../todo/ROADMAP.md), P15) — "the Android of Linux" deserves its own design
pass. For now, if it boots to a fully supported CLI, that is the target.

### Why bootc/OSTree on a phone

- **Atomic updates** — the whole OS is replaced in one transaction; a failed update is rolled
  back from the bootloader.
- **Rollback** — every previous deployment is kept; a bad update never bricks the phone.
- **Debian ecosystem** — `apt`, the full Debian archive, and every Debian package run natively.
- **Shared infrastructure** — the bootc/OSTree stack is the same one that powers the
  DaemonCores-VE and debian-bootc projects; the smartphone inherits a proven, maintained base.

---

## 9. Waydroid — Android App Compatibility Layer

Waydroid provides a minimal Android system image based on LineageOS (currently Android 13, with
Android 16 support in development as of v1.6.3, May 2025). It runs in a Wayland session and exposes
the DRM render node for direct GPU access. Waydroid officially supports HALIUM systems: the OTA
channels provide special vendor images stripped of Mesa GPU drivers, activated by setting
`TARGET_USE_MESA=false` at build time.

### Kernel requirements

```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_PSI=y
CONFIG_IPV6=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_NAMESPACES=y
```

### Distribution and maintenance

Waydroid is actively maintained (4 releases between Nov 2024 and May 2025) and is available in
official repositories of Debian 14+, Ubuntu 26.10+, Fedora, and Void Linux.

### Sources

- `docs.waydro.id`
- `docs.waydro.id/development/compile-waydroid-lineage-os-based-images`
- `github.com/waydroid/waydroid/releases`
- `wiki.archlinux.org/title/Waydroid`

---

## 10. Device Ingestion Flow

The device database is populated by a multi-source ingestion pipeline. No single source is
authoritative; each `device.yml` records its provenance in the `sources[]` array.

```
┌──────────────────────────────────────────────────────────────┐
│  Sources (scraped/enriched)                                  │
│  - LineageOS hudson (~290 active + 600 historical)           │
│  - UBports API (111 devices)                                 │
│  - Halium manifests                                           │
│  - pmOS wiki (VNDK, kernel_repo, defconfig)                  │
│  - aospdtgen (firmware dump -> device tree)                  │
│  - dumpyara (stock ROM dump)                                 │
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│  Ingestion scripts (this repo)                               │
│  - scripts/scrape-lineage.py   (hudson JSON -> device.yml)   │
│  - scripts/enrich-ubports.py   (UBports API -> VNDK)         │
│  - scripts/enrich-halium.py   (Halium manifests ->          │
│                                 kernel_repo, defconfig)       │
│  - scripts/enrich-aospdtgen.py (firmware dump -> device tree)│
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│  device/<codename>/device.yml  (validated by _schema.yml)     │
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│  CI in DaemonCores-CI: build-device.yml                       │
│  (calls scripts/build-halium.sh for each device)             │
└──────────────────────────────────────────────────────────────┘
```

### ADB probe for the truly unknown (`scripts/probe.sh`)

For a device on no list, the user runs the probe **on the existing Android** (stock or LineageOS),
not on a custom OS. The probe reads:

- `getprop | grep vndk` → `vndk` / `halium_version` (the critical field)
- `getprop ro.product.device`, `ro.board.platform`, `ro.treble.enabled`
- `ls -l /dev/block/by-name/` → `partition_layout`
- `/proc/config.gz` → the exact `defconfig` of the running kernel
- `/vendor/etc/audio_policy.conf` and `/vendor/lib*/hw/` → audio stack and available HALs

It outputs a `device.yml` directly. The user opens a PR; CI validates it against the JSON Schema,
making review near-instant. The "30 seconds to add a device" target is realistic because the
schema validation does the review.

### `aospdtgen` for devices nobody owns

For devices nobody has on hand, `aospdtgen` builds a LineageOS-compatible device tree from a stock
ROM dump produced by `dumpyara`. It works on any Treble device (Android 8.0+ with VNDK enabled).
The chain — dump → device tree → VNDK → kernel repo → build — is fully automatable upstream, so
the database can grow without anyone touching the device.

---

## 11. Microkernel Verdict

A research pass (Roadmap P05) evaluated microkernels for the smartphone form factor:

| Microkernel | Verdict |
|---|---|
| seL4 | No smartphone port |
| Zircon / Fuchsia | Nest only; smartphone deprecated |
| Redox | Boot POC 2025; zero drivers |
| Minix 3 | Dormant |

**Decision:** monolithic Linux for the short/medium term. The Halium approach (vendor kernel +
modules) is already the "juste milieu" (middle ground) the project seeks — a full kernel, but
with device support added as an external module rather than compiled in per device. seL4 is
watched as the only credible long-term option, but it has no smartphone port today.

---

## 12. Documentation Toolchain

| Component | Tool | Output |
|---|---|---|
| Inline docs | POSIX shell header blocks (scripts), Doxygen (C) | Source code |
| Static docs | Markdown in `docs/` | GitHub web UI, wiki |
| Wiki sync | CI workflow (`docs-wiki-sync.yml` in DaemonCores-CI) | GitHub wiki |
| Reference extraction | `shdoc` (shell scripts) | Markdown |

The `docs/reference/` directory is auto-generated by CI from inline header blocks and is **not
committed** to the repository.

---

## 13. Related Documents

- [`README.md`](../README.md) — Project overview, device status table, quick start
- [`docs/justifications.md`](justifications.md) — Honest justifications for the smartphone-specific
  design choices
- [`docs/sources-kernel.md`](sources-kernel.md) — Android Kernel Source Catalogue (verified vendor
  kernel sources)
- [`docs/minimal.md`](minimal.md) — The smartphone minimal variant
- [`device/_schema.yml`](../device/_schema.yml) — JSON Schema validating every `device.yml`
- [`todo/ROADMAP.md`](../todo/ROADMAP.md) — Development roadmap with structural markers
- [`Containerfile`](../Containerfile) — ARM64 Debian Trixie bootc/OSTree image definition