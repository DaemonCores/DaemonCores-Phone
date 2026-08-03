# DaemonCores-Phone Architecture

**Halium standard pipeline on a Debian Trixie + bootc/OSTree base, for Android smartphones.**

This document describes the architecture of DaemonCores-Phone: the founding principle, the
`device.yml` contract, the standard Halium build pipeline, the bootc/OSTree base image, the
Waydroid Android compatibility layer, the device ingestion flow, and the CI split with
DaemonCores-CI.

---

## 1. Project Overview

DaemonCores-Phone is **not a Linux distribution**. It is a **forge of mobile Linux systems** —
a build system that produces mobile Linux systems the way [AOSP](https://source.android.com/)
produces Android systems. The end-user distribution is a **separate future product** with its
own name, its own UI, and its own design pass (see [`future-product.md`](future-product.md)).
What this forge produces today are build artifacts: a `boot.img` and a Debian Trixie +
bootc/OSTree **base rootfs artifact** that any downstream mobile Linux product can layer on.
The forge is built on four pillars:

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
manual-port projects (postmarketOS ~200–300, unverified estimate sourced from the pmOS wiki at the
time of writing, 2026-08-01; the wiki was partially blocked by an Anubis challenge so the figure was
not freshly re-verified; UBports 111) — because it reuses vendor kernels and
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
| **DaemonCores-Phone** (this repo) | Source of truth | `device.yml` descriptors, build scripts (`scripts/build-halium.sh`, `scripts/repack-bootimg.sh`), ingestion scripts (`scripts/scrape-lineage.py`, `scripts/enrich-ubports.py`, `scripts/enrich-halium.py`, `scripts/enrich-aospdtgen.py` — **planned, not yet present on disk**), the ADB probe (`scripts/probe.sh`; `scripts/probe-to-yaml.py` — present), the kernel config fragment (`kernel/config-fragment-standard`), the `Containerfile` (the DaemonCores Phone Containerfile, multi-arch amd64/arm64; see P13), the initramfs (`initramfs/`), and the docs |
| **DaemonCores-CI** | Execution | The CI workflows (`workflows/build-device.yml`, `workflows/ingest-devices.yml`) and the ARM/AMD build matrices that call the scripts in this repo |

This repo does **not** contain CI workflows. The scripts are here; the workflows that invoke them
live in DaemonCores-CI. This separation keeps the source of truth forkable and reviewable
independently of the execution infrastructure.

---

## 3.5 Forge vs Product — The AOSP/Pixel Separation

DaemonCores-Phone is a **forge**, not a product. The separation is the same as the one between
[AOSP](https://source.android.com/) and the Pixel phone:

| | Forge | Product |
|---|---|---|
| **Android world** | AOSP (source) | Pixel, Samsung One UI, Xiaomi HyperOS |
| **Mobile Linux world** | **DaemonCores-Phone** (this repo — the forge) | Future end-user distro (separate name, separate repo, separate design pass) |

AOSP is the source that downstream vendors turn into end-user products. DaemonCores-Phone is
the source that downstream projects turn into end-user mobile Linux distributions. AOSP does
not ship a phone you can buy; it ships the build system and the system image that a product
team turns into a phone you can buy. DaemonCores-Phone does not ship an end-user distro you
flash and use daily; it ships the build pipeline and the base rootfs artifact that a product
team turns into that distro.

This separation is **non-negotiable** for two reasons:

1. **Scope discipline** — a forge and a product have different optimization targets. A forge
   optimizes for coverage, reproducibility, and downstream flexibility. A product optimizes
   for a single coherent user experience. Conflating the two produces a forge that compromises
   its build generality to appease one product's UX, and a product that is constrained by the
   forge's build-time decisions. Keeping them separate lets each optimize for its own target.
2. **Design freedom** — the end-user mobile Linux product ("the Android of Linux") deserves
   its own design pass. The UI, the default app set, the onboarding flow, the branding, and
   the commercial model are product decisions, not forge decisions. They belong to a separate
   project with its own name, its own repository, and its own team. The forge must not bake any
   of them into its base artifact.

### What the forge ships vs what the product adds

| Artifact | Owner | Notes |
|---|---|---|
| Build pipeline (`scripts/build-halium.sh`, ingestion scripts) | Forge | Source of truth in this repo |
| `device.yml` descriptors + JSON Schema | Forge | The contract every device must satisfy |
| `boot.img` (Halium-patched kernel + standard initramfs) | Forge | Build output, published to GitHub Releases |
| **Base rootfs artifact** (Debian Trixie + bootc/OSTree, CLI boot) | Forge | **A build artifact, not the end-user product.** See §8. |
| Waydroid integration (Layer 3) | Forge | Architectural brick baked into the base, not a product concern |
| UI / shell / onboarding / branding | **Product** | Separate future project |
| Default app set / app store / commercial model | **Product** | Separate future project |
| End-user distribution name and identity | **Product** | Separate future project |

### Clarification on Layer 2 (base rootfs artifact)

Layer 2 of the architecture (Debian Trixie + bootc/OSTree, see §8) is a **base rootfs artifact
produced by the forge** — it is not the end-user product. It is the equivalent of the AOSP
system image: the substrate a downstream product layers on. A product team builds a downstream
image `FROM` this base artifact and adds the UI, the shell, the default apps, the branding,
and the onboarding flow. The forge guarantees the base boots to a fully-supported CLI and that
the Halium + Waydroid substrate is correct; the product team owns everything the user sees on
top of that CLI.

This clarification matters because it reframes the CLI-first target (P13, see
[Roadmap](../todo/ROADMAP.md)) as a **forge deliverable** (the base artifact boots to a
supported CLI), not as a product limitation (the end-user distro is CLI-only). The end-user
distro will not be CLI-only; it will have a proper mobile UI — but that UI is a product-layer
concern, built on top of the forge's base artifact, not a forge-layer concern.

See [`future-product.md`](future-product.md) for the end-user product vision.

---

## 4. The `device.yml` Contract

Every supported device is described by a single `device/<codename>/device.yml` file. This file is
the input to the standard pipeline. It is validated against
[`device/_schema.yml`](../device/_schema.yml) (JSON Schema draft 2020-12) by CI — an invalid descriptor is
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

### Kernel strategy: zero maintenance, per-device compilation

> We prefer a kernel developed by a random contributor that applies recent security patches over
> an old official kernel that is obsolete and has security holes.

The pipeline **compiles a kernel per device**, because each device has a different vendor kernel
tree and a different `defconfig`. The flow, per `device.yml`, is: clone the device-specific
`kernel_repo`, apply the Halium hybris patches, merge `kernel/config-fragment-standard` into the
device `defconfig`, and cross-compile for ARM64. The compiled kernel is packaged into the device's
`boot.img`. The forge therefore compiles per device, but it **maintains no kernel**: each
`kernel_repo` is cloned as-is from its upstream maintainer (LineageOS priority, then stock, then
other) and never forked into this repository. The device-support surface is carried entirely by the
upstream vendor tree plus the standard config fragment merged at build time — there is no
forge-maintained kernel branch, no per-SoC strategy, and no special cases.

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
│  (initramfs/)               │
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

### Standard Halium initramfs (`initramfs/`)

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

The rootfs target is a Debian Trixie ARM64 image built with bootc/OSTree, adapted from the
[debian-bootc](https://github.com/DaemonCores/debian-bootc) base. The bootc/OSTree model is
preserved: the entire OS is built as an OCI container image, applied atomically to the device, and
fully rollback-capable.

> **Current state (honest).** The `Containerfile` at the repo root is now a proper DaemonCores Phone
> multi-arch bootc/ostree image — `FROM ghcr.io/daemoncores/debian-bootc:latest`, labelled
> `org.opencontainers.image.title="DaemonCores Phone"` — no longer the inherited x86_64 desktop
> template. It builds natively on x86_64 (`ARCH=amd64` default) and ARM64 (CI `--build-arg
> ARCH=arm64`) via a single `linux-image-${KERNEL_VARIANT}-${ARCH}` install line, with optional
> per-device module overlays (rpi3/rpi4/rpi5/rk3588). It is **ultra-minimal**: no SSH, no man
> pages, no logging persistence, single tty1 console — the smartphone UI remains a separate
> Phase 2 (Roadmap P15). What the Containerfile does **not** yet provide is the bootable smartphone
> kernel: the Halium-patched kernel packaged in a `boot.img` with the Halium initramfs is still
> tracked by Roadmap P13 (TODO as of 2026-08-03) and is built upstream, outside this Containerfile.

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
official repositories of Fedora and Void Linux, with Debian/Ubuntu availability tracked on the
official Waydroid documentation site (`docs.waydro.id`). Refer to `docs.waydro.id` for the current
list of distributions that ship Waydroid in their official repositories; availability on
Debian/Ubuntu depends on the Waydroid install instructions published there and should not be
assumed from upstream release cadence.

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
- [`Containerfile`](../Containerfile) — Multi-arch (x86_64 + ARM64) DaemonCores Phone bootc/ostree image (FROM ghcr.io/daemoncores/debian-bootc:latest); the bootable Halium kernel (boot.img) is tracked by Roadmap P13 (TODO)