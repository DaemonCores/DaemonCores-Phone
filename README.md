# DaemonCores-Phone

<p align="center">
  <img src="https://raw.githubusercontent.com/DaemonCores/.github/refs/heads/main/assets/banner.svg" alt="AstralEmu Banner" width="100%"/>
</p>

**A forge of mobile Linux systems. Standard, autonomous, for all devices.**

DaemonCores-Phone is **not a Linux distribution**. It is a **forge** — a build system that
produces mobile Linux systems the way [AOSP](https://source.android.com/) produces Android
systems. Like AOSP is the source that downstream vendors (Pixel, Samsung, Xiaomi) turn into
end-user products, DaemonCores-Phone is the source that downstream projects turn into
end-user mobile Linux distributions. The end-user distro is a **separate future product** with
its own name, its own UI, and its own design pass (see
[`docs/future-product.md`](docs/future-product.md)).

What this forge produces today are **build artifacts**: a `boot.img` (Halium-patched kernel +
standard initramfs) and a Debian Trixie + bootc/OSTree **base rootfs artifact** — a
fully-supported-CLI base that any downstream mobile Linux product can layer on. The forge is
based on [Halium](https://halium.org/) and libhybris to run proprietary Android drivers
without reverse engineering — the same standard that powers UBports and Droidian.

The AOSP analogy is exact on the separation: AOSP is the forge; Pixel is a product built on
it. DaemonCores-Phone is the forge; the future end-user distro is a product built on it. The
base rootfs artifact this forge ships is the equivalent of the AOSP system image — it is not
the phone you flash and use daily; it is the substrate a product team turns into that phone.

DaemonCores-Phone is an early-stage research project exploring a schema-driven path from Android device metadata to a Debian/bootc smartphone system.

| Project | Approach | Number of devices |
|---|---|---|
| postmarketOS | Manual mainline port per device | ~200-300 † |
| UBports | Manual Halium port per device | 111 |
| **DaemonCores-Phone** | **Automated standard Halium pipeline** | **Potentially 600+** |

† The postmarketOS device count (~200-300) is an unverified estimate sourced from the pmOS wiki
at the time of writing (2026-08-01); the pmOS wiki was partially blocked by an Anubis challenge,
so the figure was not freshly re-verified and may have changed.

- **Standard CI pipeline**: a single workflow for all devices. No manual port.
- **Zero kernel maintenance**: we use existing vendor kernels (LineageOS, stock) automatically patched with Halium.
- **ADB probe in 30 seconds**: your device is not in the database? Run one command, open a PR, and it is supported.
- **Debian base + bootc/OSTree**: atomic updates, rollback, the entire Debian ecosystem — as a build artifact, not a finished product.
- **Native proprietary Android drivers**: no reverse engineering. The drivers that work on Android work on systems built by this forge.

| Component | State |
| --- | --- |
| `device/_schema.yml` | Implemented JSON Schema for canonical device descriptors. |
| `scripts/probe-to-yaml.py` | Implemented converter and schema validation for an existing probe JSON document. |
| `Containerfile` | Debian bootc image scaffold inherited from the server-oriented base work. |
| `Containerfile.minimal.x86_64` | Reduced x86_64 bootc image experiment. |
| `Containerfile.minimal.arm64` | Reduced generic ARM64/SBC bootc image experiment. |
| Debian package manifest | Builds the inherited bootc, OSTree, composefs, bootupd, first-boot, network, and amd64 GRUB packages. |
| Shared CI caller | Present, but the phone-specific architecture and artifact matrix is not yet finalized. |

Sources (LineageOS, UBports, Halium, pmOS, dumpyara/aospdtgen) -> device.yml -> standard Halium pipeline (hybris patch, kernel compile, initramfs, boot.img) -> GitHub Releases (boot.img + Debian bootc/OSTree base rootfs artifact)

The base rootfs artifact is a **build output of the forge**, not the end-user product. **Waydroid
(Layer 3) is an architectural brick baked into the base rootfs artifact by the forge** — it is a
forge deliverable, not a downstream concern. The future UI and the rest of the end-user product are
downstream concerns, not part of the forge's deliverable contract. See
[`docs/architecture.md`](docs/architecture.md) §3.5 for the forge-vs-product separation.

The following items appeared as completed features in older documentation but are not present in the current tree:

- an ADB collection script (`scripts/probe.sh`);
- automated device ingestion from LineageOS, UBports, Halium, or firmware dumps;
- committed device descriptors under `device/<codename>/device.yml`;
- vendor-kernel checkout, patching, and compilation;
- a standard Halium initramfs;
- Android `boot.img`, `vendor_boot`, or DTBO assembly;
- libhybris or Android HAL integration;
- Waydroid integration;
- a validated phone installation, update, or recovery procedure.

These are roadmap items, not current capabilities. See [`todo/ROADMAP.md`](todo/ROADMAP.md).

## Device descriptor

A descriptor records the minimum information needed to reproduce and review a device port:

- codename, vendor, and model;
- VNDK and intended Halium version;
- kernel repository and defconfig;
- Android partition layout;
- support status;
- provenance for the collected information.

The schema is the current contract. No device should be presented as supported until its descriptor is committed, validated, built by CI, and linked to reproducible boot evidence.

## Convert an existing probe document

Install the converter dependencies:

```bash
python3 -m pip install jsonschema PyYAML
```

Convert and validate a JSON document that already contains every required field:

```bash
python3 scripts/probe-to-yaml.py \
  --input probe.json \
  --codename example \
  --output device/example/device.yml
```

See [todo/ROADMAP.md](todo/ROADMAP.md) for the development plan, and [docs/future-product.md](docs/future-product.md)
for the end-user product vision.

---

<p>
  <strong align="left">Made with ⭐ by the DaemonCores community</strong>
  <a href="https://github.com/DaemonCores/debian-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
</p>
