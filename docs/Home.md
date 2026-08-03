# DaemonCores-Phone

**A forge of mobile Linux systems. Standard, autonomous, for all devices.**

DaemonCores-Phone is **not a Linux distribution**. It is a **forge** — a build system that produces
mobile Linux systems the way [AOSP](https://source.android.com/) produces Android systems. Like
AOSP is the source that downstream vendors (Pixel, Samsung, Xiaomi) turn into end-user products,
DaemonCores-Phone is the source that downstream projects turn into end-user mobile Linux
distributions. The end-user distribution is a **separate future product** with its own name, its
own UI, and its own design pass (see [future-product.md](future-product.md)).

What this forge produces today are **build artifacts**: a `boot.img` (Halium-patched kernel +
standard initramfs) and a Debian Trixie + bootc/OSTree **base rootfs artifact** — a
fully-supported-CLI base that any downstream mobile Linux product can layer on. The forge is
based on [Halium](https://halium.org/) and libhybris to run proprietary Android drivers
without reverse engineering — the same standard that powers UBports and Droidian. A single
standard CI pipeline covers every device: no manual port, no per-device kernel maintenance, no
special cases. See the [README](https://github.com/DaemonCores/DaemonCores-Phone/blob/main/README.md)
for the project overview and quick start.

> ⚠️ **DEVELOPMENT IN PROGRESS — WORK IN PROGRESS** ⚠️
> This project is in active development. Nothing is stable, nothing is production-ready.

This wiki is kept in sync with the repository via CI. It documents the architecture, the device
ingestion pipeline, and the design decisions behind the project.

## Repository split

DaemonCores-Phone is the **source of truth** — it holds the scripts, configs, `device.yml`
descriptors, and the documentation. The CI workflows that actually build and release the images live
in the companion repository [DaemonCores-CI](https://github.com/DaemonCores/DaemonCores-CI).

## Future product

The end-user mobile Linux distribution — the "Android of Linux" — is a **separate future project**
built on top of this forge, with its own name, its own repo, and its own design pass. The forge
produces the base rootfs artifact; the future product adds the UI, the user-facing experience, the
commercial model, and the identity. See [future-product.md](future-product.md) for the full vision.

## Wiki Pages

- [Architecture](architecture.md) — The Halium standard pipeline, the `device.yml` format, the
  bootc/OSTree base, the device ingestion flow, and the CI split with DaemonCores-CI.
- [Justifications](justifications.md) — Honest explanations for the smartphone-specific design
  choices (Halium over mainline, vendor kernels over maintained kernels, the device.yml contract,
  VNDK-driven Halium versioning, and more).
- [Future Product](future-product.md) — The end-user product vision (separate project, not a forge
  deliverable): naming, audiences, the "computer in your pocket" angle, the CHATONS-style
  hosting model, and the forge-side prerequisites.
- [Minimal](minimal.md) — The smartphone minimal variant: an ultra-lean bootc/OSTree image for
  ARM64 devices that boots to a fully supported CLI.