# Justifications

**Honest explanations for the controversial or non-obvious design choices in DaemonCores-Phone.**

This document follows a transparency principle: every decision that could be questioned is
documented here with its rationale, its risks, and the alternatives.

---

## 1. Halium Instead of Mainline Kernels

### What we do

DaemonCores-Phone uses [Halium](https://halium.org/) and libhybris to run proprietary Android
drivers, rather than porting each device to the mainline Linux kernel.

### Why it is necessary

Mainline Linux supports only a handful of Android phones — the postmarketOS mainline ports cover
~200–300 devices after years of manual work (unverified estimate sourced from the pmOS wiki at the
time of writing, 2026-08-01; the wiki was partially blocked by an Anubis challenge so the figure was
not freshly re-verified; it may have changed), and even then the support is often partial (Wi-Fi
broken, modem missing, camera basic). The proprietary Android drivers that ship with the device
work on Android; Halium + libhybris make them work on a GNU/Linux userspace without reverse
engineering. This is the same approach UBports and Droidian use, and it is the only approach that
scales to the 600+ devices the project targets.

The trade-off is explicit: we get massive device coverage and zero reverse-engineering work, at
the cost of running a vendor (downstream) kernel instead of mainline. For a project whose goal is
"all devices", this trade-off is non-negotiable.

### Risks

- Vendor kernels are downstream and may lag mainline on security fixes. Mitigated by preferring
  LineageOS kernels, which backport the Android Security Bulletin (ASB) monthly.
- libhybris is an additional compatibility layer that can introduce subtle bugs in audio, camera,
  and sensors. Mitigated by the Halium standard, which is maintained upstream and used by UBports
  and Droidian.
- The vendor kernel may enable only the features the vendor shipped; mainline-only features
  (e.g., newer filesystems) may be unavailable.

### Alternative

Port each device to mainline Linux. This is the postmarketOS approach. It produces a cleaner
kernel and direct driver support, but requires per-device work that does not scale beyond a few
hundred devices even with a large contributor base. Rejected for a project whose explicit goal is
to support 600+ devices from a single pipeline.

---

## 2. Vendor Kernels, Zero Maintenance

### What we do

For each device, the `device.yml` references a `kernel_repo` (LineageOS priority, then stock, then
other). The pipeline clones the repo, applies the Halium hybris patches, compiles with the
`defconfig`, and produces the kernel. **We maintain no kernel.**

### Why it is necessary

> We prefer a kernel developed by a random contributor that applies recent security patches over
> an old official kernel that is obsolete and has security holes, if we have the choice.

Maintaining a kernel per device is the single largest sink of effort in mobile Linux projects.
LineageOS already maintains vendor kernels for 100+ devices with monthly ASB backports — that work
is reused, not duplicated. The pipeline **compiles a kernel per device**, because each device has
a different vendor kernel tree and a different `defconfig`: it clones the device-specific
`kernel_repo`, applies the Halium hybris patches, merges `kernel/config-fragment-standard` into the
device `defconfig`, and cross-compiles for ARM64. The forge therefore compiles per device, but it
**maintains no kernel** — each `kernel_repo` is cloned as-is from its upstream maintainer and never
forked into this repository. The device-support surface is carried entirely by the upstream vendor
tree plus the standard config fragment merged at build time.

### Risks

- The upstream LineageOS kernel maintainer may abandon the device. The `kernel_repo` field is a
  git URL; if the repo disappears, the build breaks. Mitigated by the multi-source ingestion
  (the `sources[]` array records provenance) and by the ability to point at a fork.
- A vendor kernel may have unfixed CVEs that LineageOS has not backported. The trade-off is
  accepted: a maintained-by-someone-else kernel with recent ASB patches is preferable to an
  abandoned official kernel with known holes.

### Alternative

Maintain a kernel per device in this repository. Rejected — the project would end up maintaining
hundreds of kernels, which is the exact failure mode the founding principle forbids.

---

## 3. VNDK-Driven Halium Versioning

### What we do

The `vndk` field in `device.yml` — not the displayed Android version — determines the
`halium_version` and the hybris patch set applied to the kernel.

### Why it is necessary

Google now allows vendors to run a newer Android on top of an older VNDK. The VNDK defines the
native API surface that Halium must match; the displayed Android version does not. A OnePlus 11
running Android 15 reports VNDK 33 (Android 13), and the `device.yml` must record `vndk: "33"` /
`halium_version: "13.0"`. Deriving the Halium version from the displayed Android version would
apply the wrong hybris patch set and break the build.

The `vndk` is obtained via `adb shell getprop | grep vndk` (ADB probe) or from a firmware dump
(`aospdtgen`). The schema enforces the pattern `^(2[7-9]|3[0-5]|current)$` and the
`halium_version` enum (`7.1` through `14.0`).

### Risks

- A device on a VNDK not in the schema range is rejected by CI. The range covers Android 8.1
  (VNDK 27) through Android 15 (VNDK 35); devices outside this range are pre-Treble and need
  `twrpdtgen` instead of `aospdtgen`.
- The VNDK may change after a vendor OTA. The `device.yml` is pinned to a snapshot; if the
  vendor updates the VNDK, the descriptor needs a new PR.

### Alternative

Derive the Halium version from the displayed Android version. Rejected — it produces the wrong
hybris patch set on any device where the VNDK and the Android version diverge, which is now the
common case on recent hardware.

---

## 4. The `device.yml` Contract (Single Source of Truth)

### What we do

Every device is described by exactly one `device/<codename>/device.yml`, validated against
`device/_schema.yml` (JSON Schema draft 2020-12). CI rejects an invalid descriptor before any
build runs.

### Why it is necessary

A single, schema-validated descriptor per device is what makes the "30 seconds to add a device"
target realistic. The user runs `scripts/probe.sh` on their existing Android, gets a `device.yml`,
opens a PR, and the CI validates it against the schema — review is near-instant because the schema
does the mechanical checking. Without a contract, every PR would need a human to verify the
fields by hand, which does not scale to 600+ devices.

The schema enforces:

- Required fields (`codename`, `vendor`, `model`, `vndk`, `kernel_repo`, `defconfig`,
  `partition_layout`, `halium_version`, `status`, `sources`)
- Format patterns (`codename` = `^[a-z0-9_]+$`, `kernel_repo` = `^https://github\.com/`,
  `defconfig` = `^[a-zA-Z0-9_-]+_defconfig$`)
- Enumerations (`halium_version` 7.1–14.0, `status` booted/partial/functional/full, `sources`
  from a fixed list)
- Provenance (`sources[]` min 1 item, each with `name` + `url`)

### Risks

- A valid descriptor is not necessarily a *correct* descriptor — the schema checks the format,
  not whether the `defconfig` actually boots. The `status` field carries the transparency: a
  `booted` device is honestly labelled as "the kernel boots, that's it".
- The schema must evolve as new Halium versions and source types appear. The enum lists are
  intentionally bounded; adding a new value is a schema PR.

### Alternative

Free-form per-device README files. Rejected — unstructured docs cannot be validated by CI and
do not scale to the target device count.

---

## 5. CI in a Separate Repository (DaemonCores-CI)

### What we do

The CI workflows live in [DaemonCores-CI](https://github.com/DaemonCores/DaemonCores-CI), not in
this repository. This repository holds the scripts, configs, `device.yml` descriptors, and docs;
DaemonCores-CI holds the workflows and the ARM/AMD build matrices that call those scripts.

### Why it is necessary

The split keeps the source of truth (this repo) forkable and reviewable independently of the
execution infrastructure. A contributor adding a device only needs to touch `device/` and the
schema; they never need to read or modify a workflow. The workflows can be refactored, retooled,
or migrated to a different CI provider without churning the device database or the build scripts.

It also matches the debian-bootc / DaemonCores-CI split the project inherits from: the
debian-bootc template already uses DaemonCores-CI for its reusable workflows (`bootc-build.yml`,
`iso-builder.yml`). DaemonCores-Phone reuses the same pattern.

### Risks

- A change to a script in this repo may break a workflow in DaemonCores-CI that is not updated in
  the same PR. Mitigated by the workflows calling scripts by tag or by pinning, and by running
  the workflow on the PR via `workflow_dispatch`.
- Two repositories to maintain instead of one. Accepted for the separation-of-concerns benefit.

### Alternative

Monorepo with workflows in `.github/workflows/`. Rejected — it couples the device database to
the CI infrastructure and forces every device contributor to reason about workflows.

---

## 6. bootc/OSTree on a Phone

### What we do

The rootfs is a Debian Trixie ARM64 bootc/OSTree image, adapted from the
[debian-bootc](https://github.com/DaemonCores/debian-bootc) base.

### Why it is necessary

- **Atomic updates** — the whole OS is replaced in one transaction. A phone is a device people
  depend on daily; a failed update that bricks it is unacceptable. bootc/OSTree keeps every
  previous deployment and rolls back from the bootloader.
- **Rollback** — every previous deployment is kept on disk; a bad update never bricks the phone.
- **Debian ecosystem** — `apt`, the full Debian archive, and every Debian package run natively.
  This is the "standard" half of "standard, autonomous, for all devices".
- **Shared infrastructure** — the bootc/OSTree stack is the same one that powers DaemonCores-VE
  and debian-bootc; the smartphone inherits a proven, maintained base rather than reinventing
  an update mechanism.

### Risks

- bootc/OSTree is designed for servers and desktops; the phone boot path is different (Android
  bootloader → `boot.img` → Halium initramfs → rootfs). The initramfs bridges this — it performs
  the Halium early boot and then hands off to the bootc/OSTree rootfs.
- The rootfs lives on a partition the Android bootloader does not manage; the update model is
  atomic on the rootfs side, but the `boot.img` (kernel + initramfs) is updated separately via the
  pipeline's GitHub Releases. A kernel update requires re-flashing `boot.img`.

### Alternative

A traditional mutable rootfs with `apt upgrade`. Rejected — no rollback, no atomicity, and a
failed `apt` halfway through leaves the phone in a broken state with no recovery path.

---

## 7. Debian Trixie (Testing) as the Base Rootfs Artifact

### What we do

The forge produces a base rootfs artifact built on Debian 13 (Trixie), which is currently the
**testing** distribution, not stable. This artifact is a **build output of the forge**, not
the end-user product — a downstream mobile Linux distribution layers `FROM` it (see
`architecture.md` §3.5).

### Why testing instead of stable

1. **Kernel recency** — bootc, ostree, and the Halium stack require kernel and userspace features
   (composefs, fs-verity, newer systemd, libhybris against recent glibc) that are too old in
   Debian Stable (Bookworm, 12). Trixie provides a kernel and userspace new enough to satisfy the
   dependency chain.
2. **bootc/ostree evolution** — the bootc and ostree ecosystems are evolving rapidly. Building on
   stable would mean backporting a significant fraction of the base infrastructure.
3. **Future stability** — Debian Trixie will become the next stable release. Tracking testing now
   means the project naturally migrates to stable when Trixie freezes, with minimal disruption.
4. **ARM64 maturity** — Trixie's ARM64 port is the primary mobile-relevant Debian port; the
   toolchain and archive are well-tested on the architecture the project targets.

### Risks

- Testing packages can change without notice. The CI rebuilds mitigate this by rebuilding from
  scratch on a cadence, incorporating the latest testing snapshot.
- Security updates in testing are not as strictly coordinated as in stable. The trade-off is
  accepted for the features gained.

### Alternative

Wait for Debian 14 (the next stable release) and freeze on it. This would delay the project by
1–2 years. The current approach tracks Trixie and migrates to the next stable release when it is
published.

---

## 8. CLI-First, UI Deferred to Phase 2

### What we do

The immediate target is a fully supported CLI boot. The UI and user-friendliness are a separate
Phase 2, deferred until the CLI base is solid.

### Why it is necessary

> Don't worry about the UI or user-friendliness for now. We'll debate that in a second phase,
> because I really want to make the Android of Linux, and that deserves its own design.

A phone UI is a design problem of its own — it is not a thin layer over a CLI base. Deferring it
lets the project nail the hard infrastructure first (Halium pipeline, bootc/OSTree, device
database) without the UI constraining the base design. The result is a base that any UI
(Phosh, Plasma Mobile, a custom "Android of Linux" shell) can build on.

### Risks

- The project is not usable as a daily phone until the UI lands. Accepted — the README clearly
  labels the project as work-in-progress, and the device `status` field is transparent about what
  works today.
- A CLI-first base may bake in assumptions (serial console, no touch input in the base image) that
  the UI layer must override. Mitigated by the bootc/OSTree layering model — the UI is a
  downstream layer `FROM` the base, not a modification of it.

### Alternative

Build the UI in parallel with the base. Rejected — it couples the UI design to an unstable base
and forces decisions (input stack, display server, shell) before the base is solid.

---

## 9. Microkernel: Deferred (Monolithic Linux for Now)

### What we do

The project uses a monolithic Linux kernel. A microkernel was evaluated and deferred.

### Why it is necessary

A research pass (Roadmap P05) evaluated seL4, Zircon/Fuchsia, Redox, and Minix 3. None has a
viable smartphone port today:

- **seL4** — no smartphone port. The only credible long-term option; watched.
- **Zircon / Fuchsia** — Nest only; smartphone deprecated.
- **Redox** — boot POC 2025; zero drivers.
- **Minix 3** — dormant.

The Halium approach (vendor kernel + external device-support module) is already the "juste
milieu" (middle ground) the project seeks — a full kernel, but with device support added as a
module rather than compiled in per device. A microkernel would need a full driver stack that does
not exist today for any smartphone.

### Risks

- A monolithic kernel has a larger attack surface than a microkernel. Mitigated by the
  bootc/OSTree rollback model and by the vendor kernel ASB backports.
- The project is locked into the Linux/Halium stack for the medium term. Accepted — there is no
  viable alternative today.

### Alternative

Build on seL4. Rejected — no smartphone port, no Android driver story. Watched for the long
term.

---

## 10. Mega-Kernel Approach: Rejected

### What we do

A mega-kernel merging all vendor kernel trees via `ifdef` was evaluated and rejected.

### Why it is necessary

Technical evidence:

- `allyesconfig` builds cause OOM on 32 GB machines (Peter Zijlstra patch, Feb 2023,
  `lwn.net/Articles/922654/`; LWN content is subscriber-locked, an archive copy is at
  `web.archive.org/web/2024/https://lwn.net/Articles/922654/`).
- LTO dead code elimination is limited because exported symbols must be preserved for future
  modules (`lwn.net/Articles/512548/`; archive: `web.archive.org/web/2024/https://lwn.net/Articles/512548/`).
- Symbol namespaces govern access, not collision prevention
  (`docs.kernel.org/core-api/symbol-namespaces.html`).
- The Android GKI model (one kernel plus vendor modules) is the correct approach but only applies
  to Android 12+ devices. For older devices, the zero-build-kernel approach (clone vendor kernel,
  apply Halium patches, compile) remains the only viable path.

### Decision

Keep the current approach. No mega-kernel.

### Alternative

Merge all vendor kernel trees via `ifdef` into a single mega-kernel. Rejected — OOM on 32 GB
machines, LTO dead-code limits, symbol namespaces do not prevent collisions, and the Android GKI
model only applies to Android 12+ devices.

---

## 11. Waydroid as Central Brick

### What we do

Waydroid is not a Phase 2 bonus. It is a central architectural brick providing Android app
compatibility via LineageOS-based container images with native Halium support.

### Why it is necessary

The architecture is:

- **Layer 1** — hardware support via Halium vendor kernels
- **Layer 2** — base rootfs artifact, Debian Trixie + bootc/OSTree
- **Layer 3** — Android compatibility via Waydroid

> **Naming note.** Earlier drafts referred to Layer 2 as "Galium distribution". "Galium" was an
> early product-concept name for the end-user distribution, not the forge's base artifact. It has
> been retired here to avoid conflating the forge's build output (a base rootfs artifact that any
> downstream product layers `FROM`) with the future end-user product (which has its own naming
> process, see [`future-product.md`](future-product.md) §2). Layer 2 is the forge's base rootfs
> artifact; the end-user distribution is a separate future product built on top of it.

This is the same model as ChromeOS (Linux + Android container). Waydroid images are based on
LineageOS, creating a direct synergy with the pipeline that scrapes LineageOS hudson for kernel
sources.

### Alternative

Treat Waydroid as a Phase 2 bonus, deferred with the UI. Rejected — it is a central
architectural brick, not a UI concern.

### Sources

- `docs.waydro.id`
- `docs.waydro.id/development/compile-waydroid-lineage-os-based-images`

---

## 12. Forge vs Distribution — Why DaemonCores-Phone Is Not a Linux Distribution

### What we do

DaemonCores-Phone is a **forge of mobile Linux systems**, not a Linux distribution. The forge
produces build artifacts (a `boot.img` and a Debian Trixie + bootc/OSTree base rootfs artifact)
that a downstream project turns into an end-user mobile Linux distribution with its own name,
its own UI, and its own design pass. See [`future-product.md`](future-product.md) for the
end-user product vision.

The separation is the same as the one between [AOSP](https://source.android.com/) and the
Pixel phone: AOSP is the forge (the source and build system); Pixel is a product built on it.
DaemonCores-Phone is the forge; the future end-user distro is a product built on it.

### Why it is necessary

1. **Scope discipline** — a forge and a product optimize for different targets. A forge
   optimizes for coverage, reproducibility, and downstream flexibility (one pipeline, 600+
   devices, layerable base). A product optimizes for a single coherent user experience (one
   UI, one app set, one onboarding flow, one brand). Conflating the two compromises both: the
   forge bends its build generality to appease one product's UX, and the product is
   constrained by the forge's build-time decisions.
2. **Design freedom** — the end-user mobile Linux product ("the Android of Linux") deserves
   its own design pass. The UI, the default app set, the onboarding flow, the branding, and the
   commercial model are product decisions, not forge decisions. They belong to a separate
   project with its own name, its own repository, and its own team. The forge must not bake any
   of them into its base artifact.
3. **Naming and identity** — the end-user distro will have a different name than
   DaemonCores-Phone. The forge name describes the build system; the product name describes
   the user-facing distribution. Keeping them separate from the start avoids a rebranding
   crisis later and lets each name serve its audience (forge users are developers and product
   teams; product users are end users).
4. **Reuse and federation** — a forge can power multiple downstream products. A future
   community could build a privacy-first distro, a gaming-focused distro, or an enterprise
   distro, all `FROM` the same base rootfs artifact. Tying the forge to a single product
   forecloses that possibility.

### Risks

- The separation may confuse contributors who expect a single flashable distro. Mitigated by
  the README and this document stating clearly what the forge ships vs what the product adds,
  and by `docs/future-product.md` capturing the product vision so the destination is visible.
- The future product depends on the forge producing a clean, layerable base artifact. This is
  a real constraint on the forge — the base must not bake in UI assumptions or serial-console-
  only constraints. Tracked as P15 in the roadmap.
- The two-project model requires coordination between the forge team and the product team. The
  forge's base artifact is the contract between them; it must stay stable enough to layer on.

### Alternative

Ship DaemonCores-Phone as a single end-user distribution. Rejected — it conflates a build
system with a product, compromises the forge's generality, forecloses multi-product reuse, and
forces the UI / branding / commercial model decisions to be made inside the forge before the
base is solid. The AOSP/Pixel separation exists precisely because the concerns are different;
DaemonCores-Phone follows the same split.

---

## Summary Table

| Decision | Justification | Risk Level | Alternative |
|---|---|---|---|
| Halium over mainline | 600+ devices vs ~200–300; zero reverse engineering | Medium (downstream kernel, libhybris layer) | Mainline per device (postmarketOS) |
| Vendor kernels, zero maintenance | LineageOS ASB backports reused; no per-device kernel work | Medium (upstream abandonment) | Maintain a kernel per device |
| VNDK-driven Halium versioning | VNDK defines the API surface, not the displayed Android version | Low (schema-enforced) | Derive from Android version (wrong patch set) |
| `device.yml` contract (schema-validated) | "30 seconds to add a device" via CI schema validation | Low (format, not correctness) | Free-form per-device README |
| CI in DaemonCores-CI | Source of truth forkable independently of execution | Low (two repos) | Monorepo with workflows |
| bootc/OSTree on phone | Atomic updates, rollback, Debian ecosystem | Medium (phone boot path bridged by initramfs) | Mutable rootfs with apt upgrade |
| Debian Trixie (testing) | Kernel/userspace recency for Halium + bootc | Medium (testing instability) | Wait for Debian 14 stable |
| CLI-first, UI deferred | UI is a separate design problem; nail the base first | Low (project labelled WIP) | Build UI in parallel |
| Monolithic Linux (microkernel deferred) | No viable microkernel smartphone port today | Medium (attack surface) | seL4 (no port, watched) |
| Mega-kernel approach (rejected) | allyesconfig OOM on 32 GB; LTO dead-code limits; symbol namespaces govern access not collision; GKI only Android 12+ | N/A (rejected) | Keep zero-build-kernel approach |
| Waydroid as central brick | Android app compatibility via LineageOS containers; native Halium support; same model as ChromeOS | Low (actively maintained; distribution availability tracked on docs.waydro.id) | Treat as Phase 2 bonus (rejected) |

---

## Related Documents

- [`README.md`](../README.md) — Project overview, device status, quick start
- [`docs/architecture.md`](architecture.md) — Architecture: Halium pipeline, `device.yml`, bootc/OSTree, CI split
- [`docs/minimal.md`](minimal.md) — The smartphone minimal variant
- [`device/_schema.yml`](../device/_schema.yml) — JSON Schema validating every `device.yml`
- [`todo/ROADMAP.md`](../todo/ROADMAP.md) — Development roadmap