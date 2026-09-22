# Current image experiments

The three root Containerfiles are bootc image experiments. They are not yet a mobile operating-system image.

## Image definitions

| File | Current scope |
| --- | --- |
| `Containerfile` | General Debian bootc image using amd64 kernel packages, SSH, Podman, ifupdown2, firmware, and first-boot tooling. |
| `Containerfile.minimal.x86_64` | Reduced x86_64 image using systemd-networkd and a small runtime package set. |
| `Containerfile.minimal.arm64` | Reduced ARM64/SBC image using Debian's generic ARM64 kernel, U-Boot tools, and serial-console defaults. |

The image labels still contain references inherited from `debian-bootc`. They should be corrected before these artifacts are published as DaemonCores-Phone products.

## What the minimal images implement

Both minimal files:

- derive from Debian Trixie;
- install bootc, dracut, a kernel, network tooling, time synchronization, and CA certificates;
- move mutable directories into the OSTree-compatible `/var` layout;
- enable systemd-networkd with a wired DHCP rule;
- set journald `Storage=none`;
- mask non-essential periodic and console services;
- declare no container healthcheck.

The ARM64 file uses `u-boot-tools` and generic SBC-oriented serial consoles. The x86_64 file uses the amd64 EFI/GRUB path.

## What they do not implement

- Android boot or vendor-boot images;
- device-specific DTB/DTBO selection;
- an Android vendor kernel or Halium patches;
- a Halium initramfs;
- firmware extraction from a device image;
- modem, audio, camera, sensors, GPU, suspend, charging, or touch integration;
- libhybris, Waydroid, or a mobile UI;
- a phone-specific installer or recovery process.

## CI mismatch to resolve

The shared image workflow derives variants from all `Containerfile*` files and schedules amd64 and arm64 for each variant. Architecture-specific filenames alone do not constrain that matrix.

Before enabling publication, the repository should either:

- replace the two minimal files with one architecture-parameterized Containerfile; or
- extend the workflow contract so each file declares its supported architectures.

Until then, tag discovery is an implementation detail, not an artifact-support statement.

## Appropriate use today

The image files are useful for testing reduced Debian/bootc composition and identifying the boundary between the root filesystem and future device boot work. They should not be flashed to a phone.
