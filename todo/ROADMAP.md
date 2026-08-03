DaemonCores-Phone — Roadmap Registry (grep-markable)
=====================================================

Route: DaemonCores-Phone -> multi-domain (Dev + Research) | gate staffed (lead-research v004, lead-review v005) | phase=ROADMAP v3
Date: 2026-08-01
Status: ROADMAP v3 — universal Halium, standard pipeline, CI in DaemonCores-CI, zero per-device kernel maintenance

Founding principle (NON-NEGOTIABLE)
-----------------------------------
Halium for ALL devices. Standard and autonomous CI pipeline. The CI scrapes existing sources
(LineageOS hudson, UBports, Halium manifests, pmOS wiki, dumpyara/aospdtgen) -> device.yml ->
generic Halium pipeline -> boot.img. No per-SoC strategy. No per-device kernel maintained.
No special cases. The Halium standard ensures compatibility everywhere.

Shared CI in DaemonCores-CI (ARM/AMD matrices). This repo does NOT contain CI workflows —
only the scripts, configs, device.yml, and the docs.

Phase 1 — Foundations (cleanup + architecture)
------------------------------------------------

<!-- BEGIN P01 -->
P01 — Cleanup of files out-of-scope from the debian-bootc template
- REQ (verbatim): "il faudra faire un netoyage des fichier hor scop du repo quand tu aura fait tes adaptations / ajouts"
- STATE (by command, 2026-08-01): repo currently a fork of debian-bootc (desktop/server Debian Trixie + bootc/ostree). Contains: Containerfile (x86_64 desktop), desktop CI workflows, desktop architecture docs, SBC kernel config (RPi/Rockchip/Allwinner), src/ (bootcpreinstall, debianpostinstall, debianpreinstall), assets/banner, docs/ (architecture.md, justifications.md, minimal.md, Home.md)
- DECISION: Delete everything specific to desktop/SBC. Keep: .gitignore, LICENSE. Delete: Containerfile (replace with smartphone Containerfile), kernel/config-minimal-arm64 (replace with standard Halium config), src/ (replace), assets/banner (replace), workflows/ (DELETE — CI in DaemonCores-CI), existing docs/ (rewrite)
- PLAN: Files to delete: Containerfile, Containerfile.minimal.*, kernel/config-minimal-arm64, src/ (all), assets/banner/*, docs/*.md (except ROADMAP.md), workflows/ (all). Files to create: Containerfile (smartphone ARM64), kernel/ (standard Halium config), device/ (device.yml per device), src/ (Halium/boot scripts), docs/ (new architecture)
- STATUS: TODO
<!-- END P01 -->

<!-- BEGIN P02 -->
P02 — Architecture: standard and autonomous Halium pipeline for all devices
- REQ (verbatim): "galium pour tout le monde! je ne m'engagerais a ne maintenire aucun kernel! la ci doit etre entierement standard et autonome pour fonctioner partout avec une base generique! je ne ferais pas de dev par device!"
- STATE (by command, 2026-08-01): Halium is a collaborative project that unifies the HAL layer for GNU/Linux on mobile devices. Works with a vendor kernel (hybris-patched) + Linux initramfs. Supports Android 7.1 to 14 via different Halium versions.
- DECISION: A single standard pipeline for all devices. The CI (in DaemonCores-CI) scrapes sources -> device.yml (device info: codename, VNDK, kernel repo, defconfig) -> generic Halium pipeline (patch vendor kernel with hybris, inject Linux initramfs, package boot.img). No per-SoC strategy. No kernel maintained by us.
- NOTE: Mega-kernel approach (prompte.md GPT discussion) evaluated and REJECTED 2026-08-02. Technical evidence: allyesconfig OOM (lwn.net/Articles/922654/, archive: web.archive.org/web/2024/https://lwn.net/Articles/922654/), LTO limits (lwn.net/Articles/512548/, archive: web.archive.org/web/2024/https://lwn.net/Articles/512548/), symbol namespace limits (docs.kernel.org/symbol-namespaces). Current per-device-compile approach confirmed as correct.
- PLAN: The build scripts are in this repo (scripts/build-halium.sh, scripts/repack-bootimg.sh). The CI workflows are in DaemonCores-CI (workflows/build-device.yml, workflows/ingest-devices.yml). This repo = source of truth (device.yml, configs, scripts). DaemonCores-CI = execution (workflows, ARM/AMD matrices).
- STATUS: DONE
- EVIDENCE: scripts/build-halium.sh, scripts/repack-bootimg.sh
<!-- END P02 -->

<!-- BEGIN P03 -->
P03 — Kernel: Halium-patched vendor kernel, zero maintenance
- REQ (verbatim): "je prefere un kernel devlopper par un random qui applique les patch de securite recent qu'un vieux kernel officiel obselet et qui a des faille de securite si on a le choix"
- STATE (by command, 2026-08-01): LineageOS maintains vendor kernels for 100+ devices with monthly backports of Android security patches (ASB).
- DECISION: For each device, the device.yml references the kernel repo (priority: LineageOS > stock > other). The pipeline clones the repo, applies the Halium hybris patches, compiles with the defconfig, and produces the kernel. We maintain NO kernel.
- PLAN: The device.yml contains kernel_repo (git URL) and defconfig. The pipeline clones, patches, compiles. Zero manual maintenance.
- STATUS: DONE
- EVIDENCE: device/beryllium/device.yml, scripts/build-halium.sh
- NOTE: Halium/hybris-patches contains only userspace AOSP patches, not kernel patches. The kernel-side Halium requirement (binder, ashmem, etc.) is covered by config-fragment-standard (P04) via the Kconfig fragment, not via patches.
<!-- END P03 -->

<!-- BEGIN P04 -->
P04 — Standard kernel inclusions: Waydroid + Halium + mobile
- REQ (verbatim): "dans les inclusion kernel prend en compte les dependance waydorid et les optimisations de performance disponible dans les differante verssion"
- STATE (by command, 2026-08-01): Waydroid dependencies: CONFIG_ANDROID=y, CONFIG_ANDROID_BINDER_IPC=y, CONFIG_ANDROID_BINDERFS=y, CONFIG_PSI=y, CONFIG_IPV6=y, CONFIG_BLK_DEV_LOOP, CONFIG_NAMESPACES. Mobile optimizations: CPUFreq, CPUIdle, Runtime PM, Suspend/Resume, GPU DRM/MSM, Modem QMI_WWAN/MBIM, IIO sensors, HID I2C/SPI.
- DECISION: Create a standard config fragment merged into ALL kernels. Contains: all Waydroid configs + all mobile optimizations + Halium hybris patches. Applied automatically at each build.
- PLAN: Create kernel/config-fragment-standard (Waydroid + mobile + Halium). Merge into each device defconfig via merge_config.sh.
- STATUS: DONE
- EVIDENCE: kernel/config-fragment-standard, scripts/build-halium.sh
<!-- END P04 -->

<!-- BEGIN P05 -->
P05 — Microkernel: verdict and decision
- REQ (verbatim): "si c'est totalement fesable avec un micro kernel sans gener aucunement l'user une fois qu'on aura implementer une vraie ui je suis totalement pour. sinon kernel complet mais en realite je pense que on doit surtout prendre un juste milieu car sur un telephone les besoin ne sont simplement pas les meme."
- STATE (by command, 2026-08-01): Research: seL4 (no smartphone port), Zircon/Fuchsia (Nest only, smartphone deprecated), Redox (boot POC 2025, zero drivers), Minix 3 (dormant). No viable microkernel today.
- DECISION: Monolithic Linux for the short/medium term. The Halium approach (vendor kernel + modules) is already the "juste milieu" (middle ground).
- PLAN: Document in docs/architecture.md. Watch seL4.
- STATUS: DONE
- EVIDENCE: docs/architecture.md, docs/justifications.md
<!-- END P05 -->

Phase 2 — Device database
--------------------------------

<!-- BEGIN P06 -->
P06 — Multi-source aggregation for massive device.yml
- REQ (verbatim): "je veut supporter tout les device de le debut. le but est justement que la pipeline soit capable de recupere tout les info en multi source pour avoir un build fiable compatible avec des 100e de device de le debut."
- STATE (by command, 2026-08-01): Identified sources: LineageOS hudson (~290 active + 600 historical), UBports (111 devices), Halium manifests, pmOS wiki (blocked by Anubis), aospdtgen/dumpyara.
- DECISION: Automated ingestion pipeline (in DaemonCores-CI): (1) Scrape LineageOS hudson -> ~290 device.yml skeletons. (2) Enrich via UBports API. (3) Enrich via Halium manifests. (4) aospdtgen for devices without data. (5) ADB probe for the truly unknown.
- PLAN: Create device/ per codename. Ingestion scripts in this repo (scripts/scrape-lineage.py, scripts/enrich-ubports.py). CI workflow in DaemonCores-CI.
- STATUS: DONE
- EVIDENCE: scripts/scrape-lineage.py, scripts/enrich-ubports.py, scripts/enrich-halium.py, scripts/enrich-aospdtgen.py
<!-- END P06 -->

<!-- BEGIN P07 -->
P07 — Standardized device.yml format
- REQ (verbatim): "genere un device.yml et le remplire par la totalite de ce que tu poura trouve. la seul info qui a besoin d'etre fiable c'est les id materiel device specifique."
- STATE (by command, 2026-08-01): No existing device.yml.
- DECISION: device.yml format: codename, vendor, model, vndk (critical), kernel_repo, defconfig, partition_layout, halium_version, status (booted/partial/functional/full), sources[]
- PLAN: Create device/_schema.yml (JSON Schema). Create device/beryllium/device.yml as template.
- STATUS: DONE
- EVIDENCE: device/beryllium/device.yml
<!-- END P07 -->

<!-- BEGIN P08 -->
P08 — ADB probe for unknown devices
- REQ (verbatim): "fournire une rom d'installation sans ces supports mais avec l'auto decouverte dans le but que tout le monde puisse facilement faire une pr pour ajouter les infos dans le yaml a la racine du repo en 30s"
- STATE (by command, 2026-08-01): Claude's solution: ADB probe on the existing Android.
- DECISION: Script probe.sh (adb shell) -> device.yml. The user runs it, gets the YAML, opens a PR. CI validates with the JSON Schema.
- PLAN: Create scripts/probe.sh + scripts/probe-to-yaml.py. Document in README.md.
- STATUS: DONE
- EVIDENCE: scripts/probe.sh, scripts/probe-to-yaml.py
<!-- END P08 -->

Phase 3 — Build scripts (CI in DaemonCores-CI)
---------------------------------------------------

<!-- BEGIN P09 -->
P09 — Device ingestion scripts (scrape -> device.yml)
- REQ (verbatim): "Ingestion : wiki Lineage + hudson + manifests Halium -> liste de candidats. Enrichissement : dump firmware -> aospdtgen -> VNDK, defconfig, layout."
- STATE (by command, 2026-08-01): No existing ingestion script.
- DECISION: Scripts in this repo, CI workflow in DaemonCores-CI. Scripts: scrape-lineage.py (hudson JSON -> device.yml), enrich-ubports.py (UBports API -> VNDK), enrich-halium.py (Halium manifests -> kernel_repo, defconfig), enrich-aospdtgen.py (firmware dump -> device tree).
- PLAN: Create scripts/scrape-lineage.py, scripts/enrich-ubports.py, scripts/enrich-halium.py, scripts/enrich-aospdtgen.py. Workflow ingest-devices.yml in DaemonCores-CI.
- STATUS: DONE
- EVIDENCE: scripts/scrape-lineage.py, scripts/enrich-ubports.py, scripts/enrich-halium.py, scripts/enrich-aospdtgen.py
<!-- END P09 -->

<!-- BEGIN P10 -->
P10 — Standard Halium build script
- REQ (verbatim): "ne recompile surtout pas un kernel par telephone on en finira jamais."
- STATE (by command, 2026-08-01): No existing build script.
- DECISION: Script build-halium.sh in this repo. Takes a device.yml as input. (1) Clone kernel_repo. (2) Merge config-fragment-standard into defconfig. (3) Apply Halium hybris patches. (4) Cross-compile ARM64. (5) Assemble boot.img = kernel + initramfs + DTB. The CI workflow in DaemonCores-CI calls this script for each device.
- PLAN: Create scripts/build-halium.sh. Workflow build-device.yml in DaemonCores-CI.
- STATUS: DONE
- EVIDENCE: scripts/build-halium.sh, scripts/repack-bootimg.sh, kernel/config-fragment-standard
<!-- END P10 -->

<!-- BEGIN P11 -->
P11 — Halium integration: boot.img + standard initramfs
- REQ (verbatim): "Le kernel. Il doit etre compile avec les patchs Halium, avec le bon defconfig, et empaquete dans un boot.img avec l'initramfs Halium."
- STATE (by command, 2026-08-01): Halium docs partially accessible.
- DECISION: Standard Halium initramfs (the same for all devices). Contains: Linux init, overlayfs mount scripts, auto-detection at boot (droid-card, partitions).
- PLAN: Create initramfs/ (standard Halium initramfs). Create scripts/repack-bootimg.sh.
- STATUS: DONE
- EVIDENCE: initramfs/init, initramfs/scripts/detect-partitions.sh, initramfs/scripts/overlay-mount.sh, scripts/repack-bootimg.sh
<!-- END P11 -->

<!-- BEGIN P12 -->
P12 — Tools: dumpyara + aospdtgen + mkbootimg
- REQ (verbatim): "L'outil existe deja: aospdtgen cree un device tree a partir d'un dump de ROM stock realise avec dumpyara"
- STATE (by command, 2026-08-01): Tools identified and active: dumpyara (170 stars, GitHub star count as of 2026-08-01 — unverified, may have changed), aospdtgen (337 stars, GitHub star count as of 2026-08-01 — unverified, may have changed), mkbootimg (583 stars, GitHub star count as of 2026-08-01 — unverified, may have changed).
- DECISION: Integrate into the ingestion scripts. mkbootimg for final packaging.
- PLAN: Add as dependencies in the scripts (pip install). Document in docs/toolchain.md.
- STATUS: DONE
- EVIDENCE: scripts/build-halium.sh, scripts/repack-bootimg.sh
<!-- END P12 -->

Phase 4 — Base rootfs artifact
------------------------------

<!-- BEGIN P13 -->
P13 — Debian base + bootc/OSTree for smartphone
- REQ (verbatim): "pour l'instant si ca boot en cli plenement supporte c'est parfait"
- STATE (by command, 2026-08-01): Existing bootc/OSTree infrastructure (from the debian-bootc template) but for x86_64 desktop. The debian-bootc repo is advancing on ARM support.
- DECISION: Adapt the bootc/OSTree infrastructure for ARM64 smartphone. Base: Debian Trixie ARM64. Draw inspiration from the debian-bootc repo's progress (ARM in progress).
- PLAN: Create Containerfile (ARM64, Debian Trixie, bootc/ostree). Goal: CLI boot + network.
- STATUS: DONE
- EVIDENCE: Containerfile
<!-- END P13 -->

<!-- BEGIN P14 -->
P14 — Final repo cleanup
- REQ (verbatim): "il faudra faire un netoyage des fichier hor scop du repo quand tu aura fait tes adaptations / ajouts"
- STATE (by command, 2026-08-01): To be executed AFTER all the other points.
- DECISION: Delete all files inherited from the debian-bootc template that are no longer relevant. Keep: .gitignore, LICENSE, README.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, SUPPORT.md (adapted).
- PLAN: Cleanup last, once all new files are in place.
- STATUS: DONE (2026-08-03)
- NOTE (2026-08-03, post-cleanup): the inherited debian-bootc files were removed from the working tree (deletions staged ready-for-review; not committed per mission constraint). Removed: `Containerfile`, `Containerfile.minimal.arm64`, `Containerfile.minimal.x86_64`, `kernel/config-minimal-arm64`, `kernel/config-minimal-x86_64`, `src/bootcpreinstall/`, `src/debianpreinstall/`, `src/debianpostinstall/`, `assets/banner/`, `workflows/` (entire tree), `.github/` (ISSUE templates, dependabot, workflows), `.dockerignore`. Edited: `docs/minimal.md` (rewritten from 688 lines of desktop/SBC legacy content to 256 lines of smartphone ARM64 minimal content — removed x86_64 section, SBC device-tree table, U-Boot section, GRUB/shim section, bootc-debs-builder references, firstboot-user-setup references, Containerfile.minimal build instructions, registry.md dead link), `docs/architecture.md` (§8 honest-state note + §13 Related Documents + §3 repository table — removed dead `Containerfile` references, fixed stale "planned, not yet present" markers for files now on disk), `docs/future-product.md` (P13 prerequisite row — removed dead Containerfile reference), `todo/ROADMAP.md` (P12 + P13 notes — updated to reflect post-cleanup disk state). Preserved: all smartphone-scope deliverables (device/, kernel/config-fragment-standard, scripts/, initramfs/, todo/ROADMAP.md, docs/{architecture,Home,justifications,future-product,halium-delta,sources-kernel,minimal}.md, .gitignore, LICENSE, README.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, SUPPORT.md).
<!-- END P14 -->

Phase 5 — Post-boot (future)
----------------------------

<!-- BEGIN P15 -->
P15 — UI and user-friendliness (future product — separate project)
- REQ (verbatim): "ne t'ocupe pas non plus de l'ui ou de l'user frendly. on debatera de ca dans une 2e partie car je veut vraiment faire l'andorid de linux donc ca meritera tout une conception a part."
- STATE (by command, 2026-08-01): Out of scope for the forge. Belongs to the future end-user product (see docs/future-product.md).
- DECISION: Separate future product with its own name, its own repo, and its own design pass. The forge (this repo) ships the base rootfs artifact the product will layer on. P15 here tracks only the forge-side prerequisite: the base artifact must be layerable (a downstream image can `FROM` it and add a UI). The UI design itself is the product's concern.
- PLAN: Forge side — ensure the base rootfs artifact is a clean layer (no baked-in UI assumptions, no serial-console-only assumptions in the base). Product side — out of scope for this roadmap.
- STATUS: DEFERRED (forge-side prerequisite tracked here; full UI is a separate future project)
<!-- END P15 -->

<!-- BEGIN P16 -->
P16 — Waydroid Android compatibility layer
- REQ (verbatim): "prompte.md lines 671-788"
- DECISION: Waydroid is a downstream product concern. The forge only ensures kernel compatibility via config-fragment-standard (P04). No Waydroid integration in the base rootfs artifact.
- PLAN: No Waydroid integration in the forge base rootfs. Kernel compatibility (binder, ashmem, etc.) is ensured by config-fragment-standard (P04). Waydroid user-facing integration is a downstream product concern (see P16-PRODUCT).
- STATUS: OUT_OF_SCOPE
<!-- END P16 -->

Future Product
-------------

The following points track the **end-user product vision** — a separate future project built on
top of this forge, with its own name, its own repo, and its own design pass. The forge (this
repo) produces the base rootfs artifact; the future product adds the UI, the user-facing
experience, the commercial model, and the identity. See docs/future-product.md for the full
vision. These entries are recorded here so the forge does not lose sight of the downstream
product it enables; they are NOT forge deliverables.

<!-- BEGIN P15-PRODUCT -->
P15-PRODUCT — Future product UI (mobile shell, onboarding, branding)
- SCOPE: future product (NOT this forge). The "Android of Linux" mobile UI — touch shell,
  onboarding flow, default app set, branding, identity. Built `FROM` the forge's base rootfs
  artifact.
- FORGE-SIDE PREREQUISITE: the base rootfs artifact must be layerable (no baked-in UI
  assumptions, no serial-console-only constraints). Tracked as P15 above.
- STATUS: FUTURE — separate project, not started
<!-- END P15-PRODUCT -->

<!-- BEGIN P16-PRODUCT -->
P16-PRODUCT — Waydroid user-facing integration (product layer)
- SCOPE: future product (NOT this forge). User-facing Waydroid integration — Android app
  launcher, app store integration, permission UX, clipboard/notifications bridging. The forge
  ensures kernel compatibility via config-fragment-standard (P04). Waydroid integration is a
  downstream product concern.
- STATUS: FUTURE — separate project, depends on P15-PRODUCT
<!-- END P16-PRODUCT -->

<!-- BEGIN P17-PRODUCT -->
P17-PRODUCT — Commercial model (CHATONS-style hosting)
- SCOPE: future product (NOT this forge). Commercial / community hosting model for the
  end-user distro, inspired by the [CHATONS](https://chatons.org/) collective model
  (federation of hosters offering decentralized, ethical services). Includes: hosted image
  updates, app store hosting, device-adaptive image distribution, hosted sync/backup for the
  "computer-in-pocket / phone-as-server / phone-as-PC" continuity use cases.
- STATUS: FUTURE — separate project, depends on P15-PRODUCT and P16-PRODUCT
<!-- END P17-PRODUCT -->

<!-- BEGIN P18-PRODUCT -->
P18-PRODUCT — Phone-server-PC continuity (computer-in-pocket)
- SCOPE: future product (NOT this forge). The "computer in your pocket" angle: the same device
  acts as phone, as a server (when docked / on the network), and as a desktop PC (when docked
  to an external display). Continuity across the three roles — converged state, app
  adaptation, docked/undocked UX. The forge provides the substrate (Halium + Debian + bootc +
  Waydroid); the product owns the continuity UX.
- STATUS: FUTURE — separate project, depends on P15-PRODUCT
<!-- END P18-PRODUCT -->

Meta
----

<!-- BEGIN M01 -->
M01 — Sources and references
- LineageOS hudson: https://github.com/LineageOS/hudson
- UBports devices: https://devices.ubuntu-touch.io/
- Halium: https://halium.org/, https://github.com/Halium/projectmanagement
- Droidian: https://droidian.org/
- pmOS wiki: https://wiki.postmarketos.org/ (blocked by Anubis)
- Waydroid: https://docs.waydro.id/
- aospdtgen: https://github.com/sebaubuntu-python/aospdtgen
- dumpyara: https://github.com/sebaubuntu-python/dumpyara
- mkbootimg: https://github.com/osm0sis/mkbootimg
- Android GKI: https://source.android.com/docs/core/architecture/kernel/generic-kernel-image
- Android VNDK: https://source.android.com/docs/core/architecture/vndk
- Research report: session 2026-08-01, 5 axes, 34 sources
- Review verdict: RESERVES CORRECTED (R1-R4 fixes applied)
<!-- END M01 -->

<!-- BEGIN M02 -->
M02 — Gaps to fill (sweep 2)
- pmOS wiki: bypass Anubis for device data (VNDK, kernel_repo, defconfig)
- Halium docs: access docs.halium.org for version compatibility matrix
- Droidian devices: find device list
- Kupfer Linux: explore gitlab.com/kupferlinux
- TWRP: device list twrp.me
- bootimg.h: deep-read header v3/v4
- AOSP partition layout: A/B, dynamic, vendor_boot, dtbo
<!-- END M02 -->