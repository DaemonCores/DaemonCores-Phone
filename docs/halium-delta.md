# Halium Delta — From Kernel Build to Actual Boot

> The `device.yml` produces a kernel + `boot.img`, but a kernel that boots is not a phone that
> works. The gap between the two — the **Halium delta** — is bridged by the deviceinfo contract,
> the hybris patch layer, the HAL service map, the firmware blobs, and the boot image assembly.
> This document describes that delta and how DaemonCores-Phone drives it from a single
> `device.yml`, with `device/beryllium/device.yml` (Xiaomi POCO F1, SDM845) as the concrete example.

This document is a companion to [`docs/architecture.md`](architecture.md) (the standard pipeline and
the `device.yml` contract) and to the boot flow described there (§7). It zooms in on the **delta
between the kernel build output and the first working userspace** — the part that, in Claude's
description of the Halium pipeline, is the real work after the kernel compiles.

---

## 1. The Device Info File — the deviceinfo bridge

Halium — like the broader Android-on-Linux lineage (Mer, Nemo, UBports, Droidian) — is driven by a
**deviceinfo** contract: a declarative description of what the kernel build cannot know on its own,
because it lives in the Android vendor tree rather than in the kernel tree. The `device.yml` is
DaemonCores-Phone's encoding of that contract.

What the deviceinfo contract carries (and what `device.yml` exposes):

| deviceinfo concern | `device.yml` field | What it tells the boot/init |
|---|---|---|
| **Kernel modules to load** | `kernel_modules_builtin[]`, `kernel_modules_loadable[]` | Which modules are compiled in vs. loadable. For `beryllium`, everything is `CONFIG_*=y` (built-in) and `kernel_modules_loadable: []` — no `modprobe` at boot, the WLAN/BT/UFS/audio DRM stack is already in `Image.gz-dtb`. |
| **HAL services to start** | `hal_services[]` | Which Android HAL services must be launched (in LXC or via libhybris) before the userspace can use the hardware. For `beryllium`: `android.hardware.keymaster@3.0`, `vendor.goodix.hardware.fingerprintextension@1.0`, `vendor.qti.hardware.fm@1.0`, all over `hwbinder`. |
| **Firmware blobs** | `firmware_blobs.critical[]` | The `/vendor/firmware/` blobs that must be present on the rootfs overlay for the kernel/HAL to find them at boot. For `beryllium` (from MIUI `V12.0.3.0.QEJMIXM`): audio DSP (`tas2559_uCDSP.bin`), camera ICP (`CAMERA_ICP.elf`), actuator (`bu64748gwz.prog`), acoustic calibration (`Forte/*.acdb`), fingerprint libs, GNSS service, keymaster service, display calibration XMLs. |
| **Boot image format** | `boot.header_version`, `boot.page_size`, `boot.partition_size` | How to package the kernel + initramfs + DTB. For `beryllium`: Android boot header v1, 4096-byte pages, 64 MiB partition. |
| **Kernel cmdline** | `boot.cmdline` | The `androidboot.*` and platform-specific options the bootloader passes to the kernel. For `beryllium` it pins the serial console (`ttyMSM0`), `androidboot.hardware=qcom`, the USB controller, the UFS boot device, and the recovery fallback target. |
| **DTB config** | `kernel_image_name: "Image.gz-dtb"` + `partition_layout.dtbo` | The DTB is appended to the kernel image (`Image.gz-dtb`); a separate `dtbo` partition carries overlays. The `device.yml` declares both the boot and dtbo partition paths under `/dev/block/bootdevice/by-name/`. |
| **Hybris patch set** | `hybris_patches.patch_set` (e.g. `halium-11.0`) | Which hybris patch set the build applies. For `beryllium`, derived from `halium_version: "11.0"` (itself from `vndk: "30"`). |

The point: the deviceinfo bridge is **not a separate file** in DaemonCores-Phone. It is the
`device.yml`, validated by `device/_schema.yml`, consumed by `scripts/build-halium.sh` (for the
build-time side) and by the standard Halium initramfs (for the boot-time side). The same declarative
contract drives both halves of the delta.

---

## 2. The Hybris Patch Bridge — the key enabler

The single most important enabler of the whole approach is **libhybris**: a compatibility shim that
lets a glibc-based Linux userspace call into Android's bionic-compiled vendor libraries, by
translating the bionic libc calling conventions to glibc at the link/loader layer.

Concretely:

- The vendor HAL `.so` files in `/vendor/lib64/hw/` are compiled against Android's bionic libc, with
  bionic-specific pthread semantics, linker behaviour, and property service expectations.
- A normal glibc process cannot `dlopen()` these libraries — they expect bionic's `__system_property_*`
  API, bionic's `pthread_atfork` registration, bionic's TLS layout, etc.
- libhybris provides a **shim layer** that:
  1. Intercepts bionic libc symbols and translates them to glibc equivalents.
  2. Implements the `__system_property_get`/`set` API against a real property store (the initramfs
     runs a property service compatible with bionic's expectations, or `propertyinfoparser` against
     the vendor's `build.prop`).
  3. Translates bionic's `pthread_t`/TLS bookkeeping so bionic-compiled code sees what it expects.
  4. Marshals `hwbinder`/`binder` IPC so a glibc process can call into Android HAL services that
     live in a separate process or in LXC.

The **hybris patch set** (selected by `hybris_patches.patch_set`, e.g. `halium-11.0`) is applied to
the kernel and to the build of the userspace glue so that the kernel exposes the binder/ashmem (or
binderfs on newer kernels) infrastructure these calls need. The kernel-side patches are merged by
`scripts/build-halium.sh` (architecture.md §5, step 3); the userspace-side glue is provided by the
Halium reference builds and by community ports.

For `beryllium`, the community patch sources are recorded explicitly in `device.yml`:

```yaml
hybris_patches:
  patch_set: "halium-11.0"
  community_repos:
    - "https://github.com/Martinvlba/Halium-beryllium"
    - "https://github.com/anarh1st47/halium-beryllium-patches"
    - "https://github.com/Venji10/halium_device_xiaomi_beryllium"
```

**Why this is the key enabler**: without libhybris, every vendor HAL library would have to be
reverse-engineered and rewritten against glibc — which is exactly the mainline-port approach the
project rejects (architecture.md §2). With libhybris, the proprietary vendor blobs run unmodified;
only the glue around them is patched. This is what makes the "Halium for ALL devices" principle
operationally feasible.

---

## 3. HAL Service Mapping

Not every HAL runs the same way. Some HALs are pure libraries that a glibc process loads directly via
libhybris (`dlopen` + symbol translation); others are Android services that must be **running as
processes** (often inside an LXC Android container, or started by a minimal Android init) so that
their `hwbinder` interfaces can be called by the Linux userspace.

The split, for `beryllium` (SDM845), and the general pattern:

| HAL domain | Mechanism | Notes for `beryllium` |
|---|---|---|
| **`android.hardware.audio`** | libhybris + initramfs auto-detect | The initramfs runs `droid-card`, which reads `/vendor/etc/audio_policy.conf` (or `/system/etc/...`) at every service start. The audio HAL `.so` is loaded via libhybris; no separate Android service required. Audio routing is the classic SDM845 `tinymix` problem (see §6). |
| **`graphics.composer`** | libhybris (display) | The HWComposer / `hwcomposer.sdm845.so` is loaded via libhybris by the display stack. The DRM/KMS kernel side (`CONFIG_DRM_SDE_RSC`, `CONFIG_QCOM_KGSL`) is built into the kernel per `kernel_modules_builtin`. |
| **`sensors`** | libhybris (`sensors.ssc.so`) | For `beryllium`, `vendor/lib64/sensors.ssc.so` is listed in `firmware_blobs.critical` — it is loaded via libhybris into the sensors daemon. The SSC (Sensor Software Core) talks to the SLPI DSP via a kernel interface that must be present. |
| **`camera`** | libhybris + `CAMERA_ICP.elf` | The camera HAL library is loaded via libhybris; the ICP firmware (`CAMERA_ICP.elf`) must be present in `/vendor/firmware/` for the camera service to initialise. Listed as critical in `device.yml`. |
| **`gps` / `gnss`** | Android HAL service (LXC) | For `beryllium`, `vendor/bin/hw/android.hardware.gnss@2.0-service-qti` is a real Android service. It is listed as a critical blob because the userspace calls it over `hwbinder`; it must be **running** (started by a minimal Android init or inside an LXC container), not just `dlopen`'d. |
| **`wifi`** | libhybris + kernel driver | The WLAN driver (`CONFIG_QCA_CLD_WLAN=y`, built-in for `beryllium`) handles the data path; the vendor wpa_supplicant/hal shim is loaded via libhybris. Firmware timing is a known quirk (see §6). |
| **`bluetooth`** | libhybris + kernel driver | `CONFIG_BT=y` and `CONFIG_MSM_BT_POWER=y` are built-in. The BT HAL library is loaded via libhybris; the `vendor.qti.hardware.fm@1.0` service is declared in `hal_services` over `hwbinder`. |
| **`RIL` (modem)** | Android HAL service (LXC) + libhybris shim | The RIL/rild layer typically runs as an Android service; the modem data path uses `CONFIG_QMI_WWAN`/`MBIM` from the config fragment (architecture.md §6). The voice/SMS side calls into the RIL HAL, which is bridged. |
| **`keymaster`** | Android HAL service (LXC) | For `beryllium`, `android.hardware.keymaster@3.0-service-qti` is a real service (declared in `hal_services` and listed as a critical blob). It must run in a trusted context; it is consumed over `hwbinder` by any userspace component that needs crypto key operations. |
| **`fingerprint`** | Android HAL service (LXC) + libhybris | `android.hardware.keymaster` plus the vendor extension `vendor.goodix.hardware.fingerprintextension@1.0` (declared in `hal_services`), with the FPC and Goodix vendor libs in `firmware_blobs.critical`. The TEE side (keymaster) and the sensor side (fingerprint HAL) both need running services. |

**Rule of thumb**: a HAL that ships as a `.so` under `/vendor/lib*/hw/` and is purely a library can
usually be loaded via libhybris directly. A HAL that ships as a binary under `vendor/bin/hw/` and
registers an `hwbinder` interface must be **started as a process** — typically inside an LXC Android
container or via a minimal Android init that DaemonCores-Phone runs alongside the Debian userspace.
The `device.yml` records both shapes (`hal_services[]` for the services, `firmware_blobs.critical[]`
for the libraries + firmware).

---

## 4. Firmware Blob Loading

At boot, the kernel and the HAL services expect firmware blobs under `/vendor/firmware/` (and a
few other vendor paths). The standard Halium initramfs mounts the Android vendor partitions as
read-only overlays (architecture.md §7), so these blobs are present on the rootfs without being
shipped inside the bootc/OSTree image itself — they come from the device's vendor partition.

What is loaded, and when:

| Path | Loaded by | Criticality for `beryllium` |
|---|---|---|
| `/vendor/firmware/tas2559_uCDSP.bin` | Audio DSP (SLIMbus/TAS2559) firmware, requested by the audio kernel driver on first use | Critical — without it, the audio amplifier does not initialise and there is no sound. |
| `/vendor/firmware/CAMERA_ICP.elf` | Camera ICP (Image Co-Processor) firmware, loaded by the camera HAL on init | Critical — the camera HAL fails to start without it. |
| `/vendor/firmware/bu64748gwz.prog` | Camera actuator (OIS/AF) firmware | Critical — autofocus/OIS fails without it. |
| `/vendor/etc/acdbdata/Forte/*.acdb` | Acoustic calibration database, read by the audio HAL to tune the codec/amps | Critical — audio output works but is untuned (wrong gains, missing profiles) without it. |
| `/vendor/lib64/hw/fingerprint.fpc.sdm845.so` | FPC fingerprint HAL library | Critical — fingerprint via FPC does not work. |
| `/vendor/lib64/hw/fingerprint.goodix.sdm845.so` | Goodix fingerprint HAL library | Critical — fingerprint via Goodix does not work. |
| `/vendor/lib64/sensors.ssc.so` | Sensors HAL (SSC) library | Critical — accelerometer/proximity/light do not work. |
| `/vendor/bin/hw/android.hardware.gnss@2.0-service-qti` | GNSS Android service binary | Critical — GPS does not work (see §3). |
| `/vendor/bin/hw/android.hardware.keymaster@3.0-service-qti` | Keymaster Android service binary | Critical — crypto key ops fail (impacts encryption, DRM, anything TEE-backed). |
| `/vendor/etc/qdcm_calib_data_*.xml` | Display colour calibration data | Critical — display works but colour profile is wrong/uncalibrated. |

The `device.yml` records the **source** of these blobs (`firmware_blobs.miui_source:
"V12.0.3.0.QEJMIXM"` for `beryllium`) so that the build/ingestion pipeline can verify the right
firmware is extracted from the right vendor ROM dump. The `critical[]` list is the minimum set
without which the device does not reach `status: functional` (architecture.md §4 device status table).

---

## 5. Boot Image Assembly

The `boot.img` is what the device's Android bootloader (XBL/aboot for Qualcomm SDM845) chains to. It
must be a valid Android boot image, or the bootloader refuses it. The `device.yml` carries all the
parameters `mkbootimg` needs.

For `beryllium`:

```yaml
boot:
  header_version: 1
  base_address: "0x00000000"
  page_size: 4096
  cmdline: "console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0xA84000 \
            androidboot.hardware=qcom androidboot.console=ttyMSM0 \
            msm_rtb.filter=0x237 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 \
            service_locator.enable=1 swiotlb=2048 androidboot.configfs=true \
            loop.max_part=7 androidboot.usbcontroller=a600000.dwc3 \
            androidboot.boot_devices=soc/1d84000.ufshc \
            androidboot.init_fatal_reboot_target=recovery"
  mkbootimg_args: "--header_version 1"
  partition_size: 67092480
```

| Parameter | Value for `beryllium` | Role |
|---|---|---|
| `header_version` | `1` | Android Boot Image Header v1 (the format the SDM845 bootloader expects). Newer devices with a `vendor_boot` partition use v3/v4 and split the generic ramdisk into `vendor_boot`; `beryllium` has `vendor_boot` listed in `partition_layout` (Android 11+), so the build must also emit a `vendor_boot.img`. |
| `base_address` | `0x00000000` | The load base for the kernel. SDM845 uses a flat base; the kernel is position-independent for ARM64. |
| `page_size` | `4096` | Page size used to align each section of the boot image (kernel, ramdisk, second stage, dtb). 4096 is the SDM845 norm. |
| `cmdline` | (see above) | The kernel command line. Notable `beryllium` entries: `console=ttyMSM0,115200n8` (debug serial), `androidboot.hardware=qcom` (the Halium hybris glue keys off `ro.hardware`), `androidboot.usbcontroller=a600000.dwc3` (USB gadget binding), `androidboot.boot_devices=soc/1d84000.ufshc` (so the initramfs finds the UFS storage), `androidboot.init_fatal_reboot_target=recovery` (fallback on fatal init failure). |
| `mkbootimg_args` | `--header_version 1` | Passed verbatim to `mkbootimg` by `scripts/repack-bootimg.sh`. |
| `partition_size` | `67092480` (~64 MiB) | Maximum boot image size; the assembled image must fit the `boot` partition. |
| Kernel image | `Image.gz-dtb` | The kernel is built as a gzipped image with the DTB appended (one blob). `scripts/build-halium.sh` outputs this from the device `defconfig` (`beryllium_defconfig`). |
| DTB overlays | `dtbo` partition | The `dtbo.img` is written to the separate `dtbo` partition declared in `partition_layout`. |

`scripts/repack-bootimg.sh` (architecture.md §5) assembles the final `boot.img` from these parameters
+ the compiled kernel + the standard Halium initramfs. The initramfs is the same for all devices;
only the kernel and the `boot.*` parameters vary.

---

## 6. Known Failure Points

The delta is where devices actually fail. These are the recurring failure modes for SDM845-class
devices (and the `beryllium` quirks recorded in `device.yml`):

| Failure point | Symptom | Cause | `beryllium` note |
|---|---|---|---|
| **Audio routing (tinymix)** | No sound, or sound on the wrong output (speaker vs. handset vs. headphones) | The SDM845 audio codec/SLIMbus routing must be set via `tinymix` controls before the audio HAL can produce output; the default mixer state is often wrong. | Recorded as `known_quirks[0]: "Audio routing via tinymix (typical SDM845)"`. The initramfs `droid-card` reads `/vendor/etc/audio_policy.conf` at service start, but the mixer controls still need to be set correctly for the device. |
| **WiFi firmware loading timing** | WiFi does not come up, or comes up only after a long delay / after toggling airplane mode | The WLAN module (`CONFIG_QCA_CLD_WLAN=y`) requests firmware from `/vendor/firmware/`; on some SDM845 boards the request fires before the vendor partition overlay is fully mounted, or the firmware load needs a settle delay. | Recorded as `known_quirks[1]: "WiFi firmware loading timing may need delay"`. |
| **Modem initialization** | No cellular data / no SIM detected | The RIL/modem service must start before the userspace queries it; the modem firmware and the RIL HAL service are interdependent, and the order matters. On `beryllium`, the GNSS and keymaster services (both declared in `hal_services`) are part of this chain — if keymaster is not up, anything TEE-backed (including SIM auth on some carriers) blocks. | Mitigated by ensuring the `hal_services[]` start order and by shipping the critical blobs (`gnss@2.0-service-qti`, `keymaster@3.0-service-qti`) from the right MIUI source. |
| **GPU rendering** | Display blank, or software rendering only (slow UI) | The KGSL DRM driver (`CONFIG_QCOM_KGSL=y`, `CONFIG_DRM_SDE_RSC=y`) must initialise before the display composer HAL can use the GPU. On `beryllium`, these are built-in; the failure mode is usually a missing display calibration (`qdcm_calib_data_*.xml`, listed critical) or a mis-set `androidboot.hardware` cmdline value. | Mitigated by shipping `qdcm_calib_data_*.xml` and by the `androidboot.hardware=qcom` cmdline entry that the hybris glue keys off. |
| **Vibrator** | Vibrator does not respond | On SDM845 the vibrator is often driven via sysfs, not via an Android HAL. | Recorded as `known_quirks[2]: "Vibrator via sysfs"`. The userspace must write to the sysfs path rather than call a HAL. |

The `status` field in `device.yml` (here `functional` — usable daily, architecture.md §4) is the
honest summary of which of these are resolved for the device. A device moves from `booted` →
`partial` → `functional` → `full` as each failure point is closed; the `device.yml` is the single
record of that state.

---

## 7. The Delta, Summarised

```
┌─────────────────────────────┐
│  Kernel build output       │
│  (scripts/build-halium.sh) │
│  - Image.gz-dtb            │
│  - halium-11.0 patches     │
│  - beryllium_defconfig +   │
│    config-fragment-standard│
└──────────────┬──────────────┘
               │
               │  ← the Halium delta (this document) →
               │
               ▼
┌─────────────────────────────┐
│  Working userspace boot     │
│  (scripts/repack-bootimg.sh │
│   + standard initramfs +    │
│   device.yml bridge)        │
│  - boot.img (mkbootimg v1)  │
│  - dtbo.img                 │
│  - vendor partition overlay │
│  - HAL services started     │
│  - firmware blobs available │
│  - libhybris translation    │
└─────────────────────────────┘
```

The delta is closed by three things, all driven from `device.yml`:

1. **The deviceinfo contract** (§1) — what to load, what to start, what firmware to ship, how to
   package the boot image.
2. **The hybris patch bridge** (§2) — libhybris translating bionic → glibc so vendor blobs run
   unmodified.
3. **The HAL/firmware map** (§3, §4) — which HALs are libraries (libhybris) vs. services (LXC),
   and which firmware blobs must be present for them to initialise.

Everything else is the same for every device — the standard pipeline, the standard initramfs, the
bootc/OSTree rootfs. That is what makes the "Halium for ALL devices" principle hold.

---

## 8. Related Documents

- [`docs/architecture.md`](architecture.md) — the standard pipeline, the `device.yml` contract,
  the boot flow, the bootc/OSTree base image.
- [`device/beryllium/device.yml`](../device/beryllium/device.yml) — the concrete device example
  referenced throughout this document.
- [`device/_schema.yml`](../device/_schema.yml) — JSON Schema validating every `device.yml`,
  including the `boot`, `hal_services`, `firmware_blobs`, and `hybris_patches` fields described here.
- [`README.md`](../README.md) — project overview and device status table.