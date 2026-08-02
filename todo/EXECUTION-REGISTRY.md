DaemonCores-Phone — Execution Registry (grep-markable)
=====================================================

Route: DaemonCores-Phone -> multi-domain (Dev + Research) | gate staffed (lead-research, lead-review) | phase=EXECUTION v1
Date: 2026-08-01
Status: EXECUTION — 15 points, autonomous mode, no commit

Principe fondateur (NON-NEGOTIABLE)
-----------------------------------
Halium pour TOUS les devices. Pipeline CI standard et autonome. La CI scrape les sources existantes
(LineageOS hudson, UBports, Halium manifests, pmOS wiki, dumpyara/aospdtgen) -> device.yml ->
pipeline Halium generique -> boot.img. Aucune strategie par SoC. Aucun kernel maintenu par device.
Aucun cas particulier. Le standard Halium assure la compatibilite partout.

CI partagee dans DaemonCores-CI (matrices ARM/AMD). Ce repo ne contient PAS de workflows CI —
uniquement les scripts, configs, device.yml, et la doc.

Phase 1 — Fondations (nettoyage + architecture)
------------------------------------------------

<!-- BEGIN P01 -->
P01 — Nettoyage des fichiers hors-scope du template debian-bootc
- REQ (verbatim): "il faudra faire un netoyage des fichier hor scop du repo quand tu aura fait tes adaptations / ajouts"
- DECISION: Supprimer: Containerfile, Containerfile.minimal.*, kernel/config-minimal-arm64, src/ (tout), assets/banner/*, docs/*.md (sauf ROADMAP.md), workflows/ (tout). Garder: .gitignore, LICENSE, README.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, SUPPORT.md.
- PLAN: Nettoyage en dernier (P14), une fois tous les nouveaux fichiers en place.
- STATUS: TODO
<!-- END P01 -->

<!-- BEGIN P02 -->
P02 — Architecture: pipeline Halium standard et autonome pour tous les devices
- REQ (verbatim): "galium pour tout le monde! je ne m'engagerais a ne maintenire aucun kernel! la ci doit etre entierement standard et autonome pour fonctioner partout avec une base generique! je ne ferais pas de dev par device!"
- DECISION: Un seul pipeline standard pour tous les devices. Les scripts de build sont dans ce repo (scripts/build-halium.sh, scripts/repack-bootimg.sh). Les workflows CI sont dans DaemonCores-CI (workflows/build-device.yml, workflows/ingest-devices.yml). Ce repo = source de verite (device.yml, configs, scripts). DaemonCores-CI = execution (workflows, matrices ARM/AMD).
- PLAN: Ecrire docs/architecture.md avec le pipeline Halium standard.
- STATUS: DONE
- EVIDENCE: docs/architecture.md, scripts/build-halium.sh, scripts/repack-bootimg.sh
<!-- END P02 -->

<!-- BEGIN P03 -->
P03 — Kernel: vendor kernel patche Halium, zero maintenance
- REQ (verbatim): "je prefere un kernel devlopper par un random qui applique les patch de securite recent qu'un vieux kernel officiel obselet et qui a des faille de securite si on a le choix"
- DECISION: Pour chaque device, le device.yml reference le kernel repo (priorite: LineageOS > stock > autre). La pipeline clone le repo, applique les patches hybris Halium, compile avec le defconfig, et produit le kernel. Nous ne maintenons AUCUN kernel.
- PLAN: Le device.yml contient kernel_repo (URL git) et defconfig. La pipeline clone, patche, compile. Zero maintenance manuelle.
- STATUS: DONE
- EVIDENCE: device/beryllium/device.yml, device/_schema.yml, scripts/build-halium.sh
<!-- END P03 -->

<!-- BEGIN P04 -->
P04 — Inclusions kernel standard: Waydroid + Halium + mobile
- REQ (verbatim): "dans les inclusion kernel prend en compte les dependance waydorid et les optimisations de performance disponible dans les differante verssion"
- DECISION: Creer un config fragment standard merge dans TOUS les kernels. Contient: toutes les configs Waydroid + toutes les optimisations mobile + les patches hybris Halium. Applique automatiquement a chaque build.
- PLAN: Creer kernel/config-fragment-standard (Waydroid + mobile + Halium). Merge dans chaque defconfig device via merge_config.sh.
- STATUS: DONE
- EVIDENCE: kernel/config, scripts/build-halium.sh, docs/architecture.md
<!-- END P04 -->

<!-- BEGIN P05 -->
P05 — Microkernel: verdict et decision
- REQ (verbatim): "si c'est totalement fesable avec un micro kernel sans gener aucunement l'user une fois qu'on aura implementer une vraie ui je suis totalement pour. sinon kernel complet mais en realite je pense que on doit surtout prendre un juste milieu car sur un telephone les besoin ne sont simplement pas les meme."
- DECISION: Linux monolithique pour le court/moyen terme. L'approche Halium (kernel vendor + modules) est deja le "juste milieu". Aucun microkernel viable aujourd'hui (seL4, Zircon, Redox, Minix).
- PLAN: Documenter dans docs/architecture.md. Veille sur seL4.
- STATUS: DONE
- EVIDENCE: docs/architecture.md, docs/justifications.md
<!-- END P05 -->

Phase 2 — Base de donnees devices
---------------------------------

<!-- BEGIN P06 -->
P06 — Agregation multi-source pour device.yml massif
- REQ (verbatim): "je veut supporter tout les device de le debut. le but est justement que la pipeline soit capable de recupere tout les info en multi source pour avoir un build fiable compatible avec des 100e de device de le debut."
- DECISION: Pipeline d'ingestion automatique (dans DaemonCores-CI): (1) Scrape LineageOS hudson -> ~290 device.yml squelettes. (2) Enrichir via UBports API. (3) Enrichir via Halium manifests. (4) aospdtgen pour les devices sans donnees. (5) Probe ADB pour les vraiment inconnus.
- PLAN: Creer device/ par codename. Scripts d'ingestion dans ce repo (scripts/scrape-lineage.py, scripts/enrich-ubports.py, scripts/enrich-halium.py). Workflow CI dans DaemonCores-CI.
- STATUS: TODO
<!-- END P06 -->

<!-- BEGIN P07 -->
P07 — Format device.yml standardise + JSON Schema
- REQ (verbatim): "genere un device.yml et le remplire par la totalite de ce que tu poura trouve. la seul info qui a besoin d'etre fiable c'est les id materiel device specifique."
- DECISION: Format device.yml: codename, vendor, model, vndk (critique), kernel_repo, defconfig, partition_layout, halium_version, status (booted/partial/functional/full), sources[]
- PLAN: Creer device/_schema.yml (JSON Schema). Creer device/beryllium/device.yml comme template.
- STATUS: DONE
- EVIDENCE: device/_schema.yml, device/beryllium/device.yml
<!-- END P07 -->

<!-- BEGIN P08 -->
P08 — Probe ADB pour devices inconnus
- REQ (verbatim): "fournire une rom d'installation sans ces supports mais avec l'auto decouverte dans le but que tout le monde puisse facilement faire une pr pour ajouter les infos dans le yaml a la racine du repo en 30s"
- DECISION: Script probe.sh (adb shell) -> device.yml. L'utilisateur lance, recupere le YAML, ouvre une PR. CI valide avec JSON Schema.
- PLAN: Creer scripts/probe.sh + scripts/probe-to-yaml.py. Documenter dans README.md.
- STATUS: DONE
- EVIDENCE: scripts/probe.sh, scripts/probe-to-yaml.py
<!-- END P08 -->

Phase 3 — Scripts de build (CI dans DaemonCores-CI)
----------------------------------------------------

<!-- BEGIN P09 -->
P09 — Scripts d'ingestion device (scrape -> device.yml)
- REQ (verbatim): "Ingestion : wiki Lineage + hudson + manifests Halium -> liste de candidats. Enrichissement : dump firmware -> aospdtgen -> VNDK, defconfig, layout."
- DECISION: Scripts dans ce repo, workflow CI dans DaemonCores-CI. Scripts: scrape-lineage.py (hudson JSON -> device.yml), enrich-ubports.py (UBports API -> VNDK), enrich-halium.py (Halium manifests -> kernel_repo, defconfig), enrich-aospdtgen.py (dump firmware -> device tree).
- PLAN: Creer scripts/scrape-lineage.py, scripts/enrich-ubports.py, scripts/enrich-halium.py, scripts/enrich-aospdtgen.py. Workflow ingest-devices.yml dans DaemonCores-CI.
- STATUS: TODO
<!-- END P09 -->

<!-- BEGIN P10 -->
P10 — Script build Halium standard
- REQ (verbatim): "ne recompile surtout pas un kernel par telephone on en finira jamais."
- DECISION: Script build-halium.sh dans ce repo. Prend un device.yml en entree. (1) Clone kernel_repo. (2) Merge config-fragment-standard dans defconfig. (3) Applique patches hybris Halium. (4) Cross-compile ARM64. (5) Assemble boot.img = kernel + initramfs + DTB. Le workflow CI dans DaemonCores-CI appelle ce script pour chaque device.
- PLAN: Creer scripts/build-halium.sh. Workflow build-device.yml dans DaemonCores-CI.
- STATUS: DONE
- EVIDENCE: scripts/build-halium.sh, scripts/repack-bootimg.sh, kernel/config
<!-- END P10 -->

<!-- BEGIN P11 -->
P11 — Integration Halium: boot.img + initramfs standard
- REQ (verbatim): "Le kernel. Il doit etre compile avec les patchs Halium, avec le bon defconfig, et empaquete dans un boot.img avec l'initramfs Halium."
- DECISION: Initramfs Halium standard (le meme pour tous les devices). Contient: init Linux, scripts de montage overlayfs, detection auto au boot (droid-card, partitions).
- PLAN: Creer src/initramfs/ (initramfs Halium standard). Creer scripts/repack-bootimg.sh.
- STATUS: DONE
- EVIDENCE: src/initramfs/init, src/initramfs/scripts, scripts/repack-bootimg.sh
<!-- END P11 -->

<!-- BEGIN P12 -->
P12 — Outils: dumpyara + aospdtgen + mkbootimg
- REQ (verbatim): "L'outil existe deja: aospdtgen cree un device tree a partir d'un dump de ROM stock realise avec dumpyara"
- DECISION: Integrer dans les scripts d'ingestion. mkbootimg pour le packaging final.
- PLAN: Ajouter comme dependances dans les scripts (pip install). Documenter dans docs/toolchain.md.
- STATUS: DONE
- EVIDENCE: scripts/build-halium.sh, scripts/repack-bootimg.sh, scripts/probe-to-yaml.py
<!-- END P12 -->

Phase 4 — Distribution de base
------------------------------

<!-- BEGIN P13 -->
P13 — Base Debian + bootc/OSTree pour smartphone
- REQ (verbatim): "pour l'instant si ca boot en cli plenement supporte c'est parfait"
- DECISION: Adapter l'infrastructure bootc/OSTree pour ARM64 smartphone. Base: Debian Trixie ARM64. S'inspirer des avancees du repo debian-bootc (ARM en cours).
- PLAN: Creer Containerfile (ARM64, Debian Trixie, bootc/ostree). Objectif: boot CLI + reseau.
- STATUS: DONE
- EVIDENCE: Containerfile, docs/architecture.md
<!-- END P13 -->

<!-- BEGIN P14 -->
P14 — Nettoyage final du repo
- REQ (verbatim): "il faudra faire un netoyage des fichier hor scop du repo quand tu aura fait tes adaptations / ajouts"
- DECISION: Supprimer tous les fichiers herites du template debian-bootc non pertinents. Garder: .gitignore, LICENSE, README.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, SUPPORT.md (adaptes).
- PLAN: Nettoyage en dernier, une fois tous les nouveaux fichiers en place. A executer APRES tous les autres points.
- STATUS: TODO
<!-- END P14 -->

Phase 5 — Post-boot (futur)
----------------------------

<!-- BEGIN P15 -->
P15 — UI et user-friendly (Phase 2 — hors scope immediat)
- REQ (verbatim): "ne t'ocupe pas non plus de l'ui ou de l'user frendly. on debatera de ca dans une 2e partie car je veut vraiment faire l'andorid de linux donc ca meritera tout une conception a part."
- DECISION: Phase 2 separee. Objectif: "l'Android de Linux".
- PLAN: Documenter les pistes mais ne pas implementer. Candidats: Waydroid session, Phosh, Plasma Mobile, Sxmo, custom Android-like shell.
- STATUS: DEFERRED
<!-- END P15 -->

Meta
----

<!-- BEGIN M01 -->
M01 — Sources et references
- LineageOS hudson: https://github.com/LineageOS/hudson
- UBports devices: https://devices.ubuntu-touch.io/
- Halium: https://halium.org/, https://github.com/Halium/projectmanagement
- Droidian: https://droidian.org/
- pmOS wiki: https://wiki.postmarketos.org/
- Waydroid: https://docs.waydro.id/
- aospdtgen: https://github.com/sebaubuntu-python/aospdtgen
- dumpyara: https://github.com/sebaubuntu-python/dumpyara
- mkbootimg: https://github.com/osm0sis/mkbootimg
- Android GKI: https://source.android.com/docs/core/architecture/kernel/generic-kernel-image
- Android VNDK: https://source.android.com/docs/core/architecture/vndk
<!-- END M01 -->
