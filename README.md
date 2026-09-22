# DaemonCores-Phone

<p align="center">
  <img src="https://raw.githubusercontent.com/DaemonCores/.github/refs/heads/main/assets/banner.svg" alt="AstralEmu Banner" width="100%"/>
</p>

<p>
  <strong align="left">Simplify and Innovate for Everyone.</strong>
  <a href="https://github.com/DaemonCores/debian-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
  
  <em>Identify gaps and fill them, make improvements where possible, but above all, empower developers to offer more to users.</em>
</p>

---

DaemonCores-Phone is an early-stage research project exploring a schema-driven path from Android device metadata to a Debian/bootc smartphone system.

The repository currently contains the device descriptor contract, a JSON-to-YAML probe converter, Debian bootc image experiments, package recipes, and shared CI integration. It does **not** yet contain a complete Halium device build pipeline or a bootable phone release.

## Current implementation

| Component | State |
| --- | --- |
| `device/_schema.yml` | Implemented JSON Schema for canonical device descriptors. |
| `scripts/probe-to-yaml.py` | Implemented converter and schema validation for an existing probe JSON document. |
| `Containerfile` | Debian bootc image scaffold inherited from the server-oriented base work. |
| `Containerfile.minimal.x86_64` | Reduced x86_64 bootc image experiment. |
| `Containerfile.minimal.arm64` | Reduced generic ARM64/SBC bootc image experiment. |
| Debian package manifest | Builds the inherited bootc, OSTree, composefs, bootupd, first-boot, network, and amd64 GRUB packages. |
| Shared CI caller | Present, but the phone-specific architecture and artifact matrix is not yet finalized. |

## Not implemented yet

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

The converter does not connect to a phone. Collection of the input JSON remains to be implemented.

## Development priorities

1. remove server-only assumptions from the image and package set;
2. make the CI matrix explicit instead of applying every Containerfile to every architecture;
3. add schema tests and converter tests;
4. implement and review the probe collection format;
5. add one device as a narrow vertical slice;
6. build and validate the kernel, initramfs, boot image, rootfs hand-off, and recovery path for that device;
7. generalize only after the first reproducible port works.

## Documentation

- [Current architecture](docs/architecture.md)
- [Halium integration boundary](docs/halium-delta.md)
- [Design decisions](docs/justifications.md)
- [Current image experiments](docs/minimal.md)
- [Kernel-source policy](docs/sources-kernel.md)
- [Roadmap](todo/ROADMAP.md)

---

<p>
  <strong align="left">Made with ⭐ by the DaemonCores community</strong>
  <a href="https://github.com/DaemonCores/debian-bootc/wiki"><img align="right" src="https://img.shields.io/badge/Wiki-FFFFFF?style=for-the-badge&logoColor=white" alt="Documentation"/></a>
  <a href="https://github.com/orgs/DaemonCores/discussions"><img align="right" src="https://img.shields.io/badge/Community-000000?style=for-the-badge&logoColor=white" alt="Community"/></a>
  <a href="https://github.com/DaemonCores/debian-bootc"><img align="right" src="https://img.shields.io/badge/Base_debian_for_all_project-A81D33?style=for-the-badge&logo=debian&logoColor=white" alt="Debian Bootc"/></a>
</p>
