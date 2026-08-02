# DaemonCores-Phone

**A Linux distribution for smartphones. Standard, autonomous, for all devices.**

DaemonCores-Phone is a Debian Trixie + bootc/OSTree distribution designed to run on the widest
possible range of Android smartphones. It uses [Halium](https://halium.org/) and libhybris to run
proprietary Android drivers without reverse engineering — the same standard that powers UBports and
Droidian. A single standard CI pipeline covers every device: no manual port, no per-device kernel
maintenance, no special cases. See the [README](https://github.com/DaemonCores/DaemonCores-Phone/blob/main/README.md)
for the project overview and quick start.

This wiki is kept in sync with the repository via CI. It documents the architecture, the device
ingestion pipeline, and the design decisions behind the project.

## Repository split

DaemonCores-Phone is the **source of truth** — it holds the scripts, configs, `device.yml`
descriptors, and the documentation. The CI workflows that actually build and release the images live
in the companion repository [DaemonCores-CI](https://github.com/DaemonCores/DaemonCores-CI).

## Wiki Pages

- [Architecture](architecture.md) — The Halium standard pipeline, the `device.yml` format, the
  bootc/OSTree base, the device ingestion flow, and the CI split with DaemonCores-CI.
- [Justifications](justifications.md) — Honest explanations for the smartphone-specific design
  choices (Halium over mainline, vendor kernels over maintained kernels, the device.yml contract,
  VNDK-driven Halium versioning, and more).
- [Minimal](minimal.md) — The smartphone minimal variant: an ultra-lean bootc/OSTree image for
  ARM64 devices that boots to a fully supported CLI.