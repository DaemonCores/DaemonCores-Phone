# Design decisions and constraints

## Schema before automation

The project starts with a machine-validated device descriptor because device ports depend on many values that are easy to lose or copy without provenance.

The schema provides a review surface and stable vocabulary. It does not eliminate device-specific work, and it must evolve from real ports rather than attempting to predict every device in advance.

## Provenance is required

Every descriptor requires a `sources` array. Hardware and Android metadata can come from a device, a maintained device tree, a kernel repository, or another project, but the origin must be reviewable.

Source presence is not source verification. Future CI should pin revisions, reject unreachable references, and distinguish direct measurements from copied community data.

## VNDK as recorded input

VNDK is relevant to an Android compatibility layer because it describes the native vendor interface level. The schema records both `vndk` and `halium_version` explicitly rather than deriving one silently at build time.

The correct mapping still needs validation against the chosen Halium release and the target device. A schema-valid pair is not proof of compatibility.

## Separate metadata conversion from collection

`probe-to-yaml.py` consumes a JSON document and validates its output. Keeping transformation separate from ADB collection makes the mapping testable and allows multiple collectors later.

The current repository implements only the converter. Documentation must not shorten that into “connect a phone and run one command” until the collector exists and is tested.

## One device before mass ingestion

Older plans prioritized generating hundreds of descriptors. That would create a large inventory of unverified data before the build and boot contracts exist.

The current priority is one owned device with a reproducible vertical slice. Mass ingestion should follow only when the fields required by a successful port are known.

## Halium remains a proposed compatibility path

Halium and vendor kernels are the current research direction for reusing Android hardware support. The repository does not yet implement that layer, so it is premature to claim that vendor drivers work or that a device requires no maintenance.

The first port should compare the proposed compatibility path with the target's available mainline support and record why one is selected.

## bootc for the root filesystem

The existing images explore bootc/OSTree as a versioned Debian root filesystem. This could provide atomic rootfs deployment and rollback.

On phones, the kernel and early userspace may live in Android-managed boot partitions outside the OSTree deployment. Atomic rootfs updates are not sufficient unless compatibility and rollback across those artifacts are also defined.

## Mobile UI is deferred

The repository currently focuses on metadata, build, boot, recovery, and rootfs questions. A graphical shell, telephony UX, application compatibility, and Waydroid are intentionally outside the first vertical slice.

Deferring UI prevents presentation work from obscuring missing boot and hardware foundations. It does not imply that those layers are optional for a usable phone distribution.

## Shared CI with an explicit phone matrix

Reusing DaemonCores-CI is desirable for package publication, image signing, and tests. The generic workflow currently discovers all root Containerfiles for both architectures, which does not match architecture-specific phone experiments.

The phone project needs an explicit matrix or metadata contract before it can safely reuse the publication workflow. Silent generation of invalid architecture combinations is worse than separate, narrow jobs.

## Support claims require evidence

Potential device counts, community project counts, and theoretical compatibility are not support metrics. The repository should publish only devices for which it can point to source revisions, build artifacts, boot logs, recovery instructions, and hardware test results.
