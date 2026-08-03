# Base Rootfs Artifact (Minimal)

> DaemonCores-Phone smartphone forge — minimal base rootfs layer.

## What it is

The minimal base rootfs is a **Debian Trixie ARM64** bootc/OSTree image that
boots to a fully supported **CLI** on Android smartphones via the
[Halium](https://halium.org/) standard initramfs bridge. The kernel and
initramfs live in the Android `boot.img` (see
[`architecture.md`](architecture.md)); the rootfs documented here is the
bootc/OSTree userspace that the Halium initramfs mounts as the live root
filesystem.

## Role in the forge

This image is a **build artifact** — one layer in the DaemonCores-Phone
pipeline — **not the end-user product**. It is the shared atomic base that
downstream forge stages (Halium integration, device adaptation, UI shells,
end-user images) layer on top of. The end-user vision is described in
[`future-product.md`](future-product.md); the full pipeline in
[`architecture.md`](architecture.md).

## Key characteristics

- **Atomic updates & rollback** — bootc/OSTree transactional upgrades with
  automatic rollback on failed boot; the previous deployment is always
  retained and selectable from the boot menu.
- **Debian ecosystem** — apt packages, Debian Trixie security updates, and
  the full Debian userspace stack flow through the bootc layer unchanged.
- **Halium initramfs bridge** — the Android `boot.img` kernel + Halium
  initramfs perform early device bring-up (display, touch, modem, sensors)
  and hand control to this rootfs as the standard Linux userspace.
- **Composefs integrity** — the rootfs is mounted via composefs so the
  OSTree deployment is cryptographically verified at boot.

## What it does NOT include

This is a deliberate minimal base. It intentionally omits:

- **No UI** — no display server, no Wayland compositor, no graphical shell,
  no launcher. The image boots to a text console.
- **No SSH by default** — no `openssh-server`; access is via the serial
  console (or a downstream layer that adds SSH).
- **No man pages** — `man-db`, `manpages`, and `groff-base` are not
  installed to keep the image small.
- **No desktop packages** — no `bash-completion`, `nano`, `less`,
  `locales`, `console-setup`, `podman`, or interactive niceties.
- **No first-boot user setup** — no `firstboot-user-setup` wizard; the
  image is headless and configured by downstream layers.

Downstream forge stages add the UI, networking, user management, and
device-specific packages on top of this base.

## Cross-links

- [`architecture.md`](architecture.md) — full pipeline description, boot
  chain, and the role of each forge stage.
- [`future-product.md`](future-product.md) — end-user product vision and
  the layers that turn this base rootfs into a usable smartphone
  experience.