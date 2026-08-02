# Android Kernel Source Catalogue

Verified sources of Android vendor kernels usable by the DaemonCores-Phone pipeline.

> **Warning:** several sources were initially suggested by ChatGPT. The user explicitly warned
> that GPT hallucinates a lot about technical state. Everything must be verified. Each source
> below has been independently verified via `webfetch`. Unverified sources are marked as such.

## Verified

- **AOSP ACK** — `android.googlesource.com/kernel/common/`
- **LineageOS Poco F1 sdm845** — `github.com/LineageOS/android_kernel_xiaomi_sdm845`
- **LineageOS Poco X3 surya** — `github.com/LineageOS/android_kernel_xiaomi_surya`
- **Xiaomi Kernel OpenSource** — `github.com/MiCode/Xiaomi_Kernel_OpenSource`
  (note: Poco F1 is under codename **dipper** NOT beryllium)
- **OnePlus OSS** — `github.com/OnePlusOSS` (164 repos)
- **Samsung Open Source** — `opensource.samsung.com` (web portal, not GitHub)
- **GrapheneOS Kernel** — `github.com/GrapheneOS/kernel_common-6.12`
- **crDroid Kernel** — `github.com/crdroidandroid` (1327 repos)
- **Evolution X Kernel** — `github.com/Evolution-X` (113 repos)

## Unverified

- **Qualcomm CAF** — `source.codeaurora.org` inaccessible, possible migration to `quic.github.io`
- **CalyxOS Kernel** — not found on GitHub, possible GitLab
- **Google Pixel Kernel** — in AOSP, no standalone repo

## Source priority

1. LineageOS (monthly ASB backports)
2. OEM official
3. Other ROM projects
4. AOSP ACK (reference, may lack device-specific drivers)

## Sources

- AOSP manifest fetched 2026-08-02
- Xiaomi README grep: `beryllium=0 dipper=3`
- OnePlusOSS fetched 2026-08-02
- Samsung fetched 2026-08-02
- GrapheneOS fetched 2026-08-02
- crDroid fetched 2026-08-02
- Evolution X fetched 2026-08-02