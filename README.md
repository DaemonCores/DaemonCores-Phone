> ⚠️ **DEVELOPMENT IN PROGRESS — WORK IN PROGRESS** ⚠️
> This project is in active development. Nothing is stable, nothing is production-ready.
> Contributions and feedback are welcome, but expect major changes.

DaemonCores-Phone
=================

**A Linux distribution for smartphones. Standard, autonomous, for all devices.**

DaemonCores-Phone is a Linux distribution based on Debian Trixie and bootc/OSTree,
designed to run on the widest possible range of Android smartphones.
It uses [Halium](https://halium.org/) and libhybris to run proprietary Android
drivers without reverse engineering — the same standard that powers UBports and Droidian.

Why DaemonCores-Phone?
----------------------

| Project | Approach | Number of devices |
|---|---|---|
| postmarketOS | Manual mainline port per device | ~200-300 |
| UBports | Manual Halium port per device | 111 |
| **DaemonCores-Phone** | **Automated standard Halium pipeline** | **Potentially 600+** |

- **Standard CI pipeline**: a single workflow for all devices. No manual port.
- **Zero kernel maintenance**: we use existing vendor kernels (LineageOS, stock) automatically patched with Halium.
- **ADB probe in 30 seconds**: your device is not in the database? Run one command, open a PR, and it is supported.
- **Debian base + bootc/OSTree**: atomic updates, rollback, the entire Debian ecosystem.
- **Native proprietary Android drivers**: no reverse engineering. The drivers that work on Android work on DaemonCores-Phone.

Architecture
------------

Sources (LineageOS, UBports, Halium, pmOS, dumpyara/aospdtgen) -> device.yml -> standard Halium pipeline (hybris patch, kernel compile, initramfs, boot.img) -> GitHub Releases (boot.img + Debian bootc/OSTree rootfs)

Device status
--------------

Each device has a transparent status in its device.yml:

| Status | Meaning |
|---|---|
| booted | The kernel boots, that's it |
| partial | Network or audio works |
| functional | Usable daily |
| full | Everything works |

Add your device
--------------

Your device is not yet supported?

1. Connect your Android phone via USB (debugging enabled)
2. Run ./scripts/probe.sh
3. Open a PR with the generated device.yml
4. The CI automatically builds the boot.img

30 seconds. That's it.

Quick start (developers)
--------------------------

```
git clone https://github.com/DaemonCores/DaemonCores-Phone.git
cd DaemonCores-Phone
```

See todo/ROADMAP.md for the development plan.

License
-------

[LGPL-2.1](LICENSE)