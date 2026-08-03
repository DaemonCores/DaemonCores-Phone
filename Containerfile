#####################################################################################
# Containerfile.minimal — multi-arch (x86_64 + ARM64)
#
# Ultra-minimal bootc/ostree image for x86_64 (AMD7) and ARM64 (AArch64).
# Research target (lead-research): ~50 MB RAM idle realistic with aggressive
# masking; the < 10 MB stretch goal is unreachable without dropping systemd.
#
# Multi-arch strategy (BuildKit):
#   - Single FROM debian:trixie; the image is built NATIVELY on the target-arch
#     runner (no QEMU cross-build), so apt pulls arch-matching .deb packages.
#   - ARG ARCH (default amd64; CI overrides to arm64 via --build-arg ARCH=arm64)
#     selects the kernel and firmware packages via the linux-image-${ARCH}
#     naming pattern. BOOT_PKG is a separate ARG because arm64 uses u-boot-tools
#     instead of grub-efi-arm64.
#
# Architecture-specific package selection:
#   x86_64 (amd64):  linux-image-amd64, grub-efi-amd64 (+ signed hold)
#   arm64   (arm64): linux-image-arm64, u-boot-tools, firmware-linux-free,
#                    firmware-misc-nonfree
#
# Both architectures share:
#   - debian:trixie base (no -slim variant published for trixie as of 2025)
#   - bootc / dracut / ostree stack (from the bootc APT repo)
#   - systemd-networkd (shipped by systemd, not a separate package on Trixie)
#   - systemd-timesyncd (repacked with network-online drop-in from bootc repo)
#   - journald Storage=none (no persistent logging)
#   - aggressive service masking (cron, getty tty2-6, apt-daily, rsyslog, etc.)
#   - kernel cmdline: quiet init_on_alloc=0 (arm64 adds serial consoles)
#
# Custom kernel (optional):
#   ARG KERNEL_VARIANT=minimal installs `linux-image-minimal-${ARCH}` (built from
#   the fragments in kernel/config-minimal-<arch>) instead of the stock Debian
#   `linux-image-stock-${ARCH}` metapackage. Default is `stock` for zero regression.
#   The CI builds the .deb with the right `linux-image-${KERNEL_VARIANT}-${ARCH}`
#   name, so the Containerfile installs it directly with no if/else.
#   See P02 in todo/registry.md and docs/minimal.md#kernel.
#
# Per-device modules (optional):
#   ARG DEVICE (default `generic` = no extra modules). When set to a device
#   name present in modules-kernel/ (rpi3, rpi4, rpi5, rk3588, x86_64), the
#   image installs the matching linux-modules-<device> deb built by the
#   bootc-debs-builder pipeline from the overlay in modules-kernel/<device>.
#   The modules are optional — the base image (linux-image-common) works
#   without them. The default `generic` installs `linux-modules-generic`, a
#   harmless empty meta-package (no modules) built from the empty overlay in
#   modules-kernel/generic; this avoids the empty-package-name edge case that
#   relied on apt silently ignoring `linux-modules-`. The CI matrix builds one
#   image per DEVICE value and tags it with a device suffix:
#   :latest_rpi4, :latest_rk3588, etc.
#
# Auto-update variant:
#   ARG AUTOUPDATE=1 writes `1` to /usr/lib/bootc/autoupdate. Set AUTOUPDATE=0 to
#   write `0` (bootc treats content `0` as disabled) for the `_lock` tag variant
#   (auto-update disabled for minimal RAM). See P04 in todo/registry.md.
#
# Trade-offs (documented in docs/minimal.md):
#   - No SSH server (use console or downstream layer to add openssh-server)
#   - No man pages, no nano, no bash-completion
#   - No logging persistence (journald volatile only)
#   - No getty on tty2-6 (single tty1 console)
#
# This file intentionally does NOT touch the original Containerfile.
# #####################################################################################

FROM ghcr.io/daemoncores/debian-bootc:latest
STOPSIGNAL SIGRTMIN+3

LABEL org.opencontainers.image.title="DaemonCores Phone"
LABEL org.opencontainers.image.description="Debian 13 Trixie bootc/ostree image for Phone."
LABEL org.opencontainers.image.base.name="ghcr.io/daemoncores/debian-bootc:latest"
LABEL org.opencontainers.image.source="https://github.com/DaemonCores/DaemonCores-Phone"
LABEL org.opencontainers.image.licenses="LGPL-2.1"
LABEL containers.bootc=1
LABEL ostree.bootable=1

# Target architecture: amd64 (x86_64) default; CI overrides to arm64 via --build-arg ARCH=arm64.
# Drives the kernel package name (linux-image-${ARCH}) and the boot stack:
# grub-efi-${ARCH} on x86_64, u-boot-tools on arm64 SBCs (via BOOT_PKG override).
ARG ARCH=amd64
# Boot stack: grub-efi-amd64 (x86_64) or u-boot-tools (arm64 SBCs). Kept as a
# separate ARG because arm64 does NOT follow the grub-efi-${ARCH} pattern.
ARG BOOT_PKG=grub-efi-amd64
# Firmware packages: empty on x86_64 (downstream adds microcode); arm64 ships
# firmware-linux-free firmware-misc-nonfree for SBC peripherals.
ARG FIRMWARE_PKGS=""
# Extra kernel cmdline for serial consoles: empty on x86_64; arm64 adds
# console=ttyAMA0,115200 console=ttyS0,115200 console=ttyAML0,115200.
ARG KERNEL_CMDLINE_SERIAL=""
# `stock` (default) installs the Debian linux-image-stock-<arch> metapackage;
# `minimal` installs linux-image-minimal-<arch> (custom kernel built from
# kernel/config-minimal-<arch> by the bootc-debs-builder pipeline). See P02 in
# todo/registry.md. The CI builds the .deb with the matching KERNEL_VARIANT-<arch>
# name, so the Containerfile installs it directly with no if/else.
ARG KERNEL_VARIANT=stock
# `1` (default) writes /usr/lib/bootc/autoupdate so bootc performs automated ostree
# upgrades (the `_autoupdate` tag variant); `0` writes `0` to that file, disabling
# auto-update for the `_lock` tag variant (minimal RAM, no background upgrade
# overhead). bootc reads the file content (0 = disabled); presence alone is not
# sufficient. See P04 in todo/registry.md.
ARG AUTOUPDATE=1
# Per-device kernel modules overlay. `generic` (default) installs
# linux-modules-generic — a harmless empty meta-package (no modules) built
# from the empty overlay in modules-kernel/generic. When set to a device name
# present in modules-kernel/ (rpi3, rpi4, rpi5, rk3588, x86_64), the image
# installs the matching linux-modules-<device> deb on top of the kernel
# package. The modules are OPTIONAL — the base image works without them. The
# CI matrix tags the resulting image with a device suffix: :latest_<device>.
ARG DEVICE=generic
# SHA-256 of the bootc APT repo signing key. Update when the key at
# https://daemoncores.github.io/debian-bootc/gpg.key is rotated.
ARG BOOTC_GPG_SHA256=557c791d14da63c4621725fb335c6bd336c57afc6f1ffe3afcf25fc489b65680
# Product display name (dashes -> spaces); empty falls back to /etc/os-release NAME.
ARG PRODUCT_NAME=""

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# Phase 2: Trust the bootc APT repository
# -----------------------------------------------------------------------------
# COPY ./src/bootcpreinstall / must precede the sed below: the sources file
# /etc/apt/sources.list.d/debian-bootc.sources (carrying the {{ ARCH }} token)
# is shipped by this layer. Without the COPY first, sed fails under
# `set -euo pipefail` because the file does not exist yet. Mirrors the main
# Containerfile (COPY then sed, same order).
COPY ./src/debianpreinstall /
RUN sed -i "s/{{ ARCH }}/${ARCH}/g" \
        /etc/apt/sources.list.d/DaemonCores-Phone.sources \
    && wget \
        -O /usr/share/keyrings/DaemonCores-Phone-keyring.gpg \
        https://daemoncores.github.io/DaemonCores-Phone/gpg.key \
    && printf '%s  /usr/share/keyrings/DaemonCores-Phone-keyring.gpg\n' "${BOOTC_GPG_SHA256}" \
        | sha256sum -c - \
    && mkdir -p /usr/lib/bootc \

# -----------------------------------------------------------------------------
# Phase 3: Install the ultra-minimal package set (arch-conditional via ARG)
# -----------------------------------------------------------------------------
# Arch-specific kernel package is derived from KERNEL_VARIANT and ARCH via the
# linux-image-${KERNEL_VARIANT}-${ARCH} naming pattern, so there is no if/else
# here. The CI builds the matching .deb name, so apt installs it directly.
# BOOT_PKG and FIRMWARE_PKGS stay separate ARGs because arm64 does NOT follow
# the grub-efi-${ARCH} pattern (u-boot-tools) and firmware is empty on x86_64.
# DEVICE (default `generic`) installs linux-modules-${DEVICE} on top of the
# kernel package; the modules are OPTIONAL — the base image works without
# them. The default `generic` installs linux-modules-generic, a harmless empty
# meta-package (no modules), so the install line always resolves to a real
# package name (zero regression vs the previous empty-name edge case).
RUN apt update \
    && apt install -y --no-install-recommends \
        linux-image-${KERNEL_VARIANT}-${ARCH} \
        linux-modules-${DEVICE} \
        ${BOOT_PKG} \
        ${FIRMWARE_PKGS} \
    && rm -rf \
        /tmp/* \
        /var/tmp/* \
        /run/* \
        /usr/sbin/policy-rc.d

# -----------------------------------------------------------------------------
# Phase 4: ostree filesystem migration
# -----------------------------------------------------------------------------
# bootc/ostree requires /home, /root, /mnt, /srv, /opt as symlinks into /var so the
# read-only /usr tree can be swapped atomically while mutable state persists in /var.
# Mirrors the main Containerfile exactly; do NOT change the layout or bootc fails.
RUN mkdir -p /var/home \
        /var/roothome \
        /var/mnt \
        /var/srv \
        /var/opt \
        /var/usr/lib/locale \
        /sysroot/ostree \
    && cp -r /usr/lib/locale/* /var/usr/lib/locale/ || true \
    && rm -rf /home /root /mnt /srv /opt /usr/lib/locale \
    && ln -s var/home /home \
    && ln -s var/mnt /mnt \
    && ln -s var/srv /srv \
    && ln -s var/opt /opt \
    && ln -s var/roothome /root \
    && ln -s sysroot/ostree /ostree \
    && ln -s var/usr/lib/locale /usr/lib/locale

# -----------------------------------------------------------------------------
# Phase 8: Healthcheck
# -----------------------------------------------------------------------------
# bootc images are updated in-place via ostree; a healthcheck would spawn a
# process on a schedule, defeating the minimal RAM target.
HEALTHCHECK NONE