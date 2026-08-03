# Future Product Vision

**The end-user mobile Linux distribution that will be built on top of the DaemonCores-Phone
forge.** This document captures the product vision — it is **not** a forge deliverable and is
**not** the current project. The forge (DaemonCores-Phone, this repo) produces the base rootfs
artifact; the future product adds the UI, the user-facing experience, the commercial model,
and the identity. See [`architecture.md`](architecture.md) §3.5 for the forge-vs-product
separation.

> ⚠️ **This is a vision document, not a build plan.** Nothing here is committed or scheduled.
> It exists so the forge does not lose sight of the downstream product it enables, and so the
> forge's base artifact stays layerable enough to support it.

---

## 1. Separation Principle

DaemonCores-Phone (the forge) and the future end-user product are **two separate projects**:

| | Forge | Product |
|---|---|---|
| **Name** | DaemonCores-Phone | TBD — a different name (see §2) |
| **Repo** | this repo | a separate future repo |
| **Audience** | developers, device contributors, product teams | end users |
| **Deliverable** | `boot.img` + base rootfs artifact (CLI boot) | flashable end-user distribution with a mobile UI |
| **Optimization** | coverage, reproducibility, downstream flexibility | single coherent user experience |

The separation mirrors the [AOSP](https://source.android.com/) / Pixel split: AOSP is the
forge that downstream vendors (Pixel, Samsung, Xiaomi) turn into products;
DaemonCores-Phone is the forge that a future project turns into an end-user mobile Linux
distribution. AOSP does not ship a phone you can buy; it ships the build system. The future
product ships the phone-equivalent you can flash and use daily.

This separation is **non-negotiable** (see [`justifications.md`](justifications.md) §12):
conflating a forge with a product compromises both.

---

## 2. Naming Note

The end-user distribution will **not** be named "DaemonCores-Phone". The forge name describes
the build system (a forge of mobile Linux systems); the product name describes the user-facing
distribution. They serve different audiences and must not be conflated.

The product name is a **product-team decision**, not a forge decision. It will be chosen when
the product project is started, with its own naming process, branding, and identity. The forge
must not preempt it.

---

## 3. Target Audiences

The future product targets three overlapping audiences the forge alone does not serve:

1. **The end user who wants a real Linux phone** — a daily-driver mobile device running a
   proper Linux distribution, with a touch UI, an app store, and Android app compatibility via
   Waydroid. This is the "Android of Linux" audience the founding principle names.
2. **The power user who wants a computer in their pocket** — a device that is a phone on the
   go, a server on the network, and a desktop PC when docked. See §5 for the continuity angle.
3. **The community / ethical-hosting audience** — users who want a mobile Linux distribution hosted
   by a federated, ethical provider rather than a single corporate vendor. See §6 for the
   CHATONS-style commercial model.

The forge's audience (developers, device contributors, product teams) is served by the forge
itself; the product's audience is served by the product built on the forge.

---

## 4. The "Computer in Your Pocket" Angle

The future product is positioned as a **computer in your pocket** — a single device that is a
phone, a server, and a PC depending on context. This is the convergence pitch: the phone is
not a small companion to your computer, it **is** your computer, and the form factor adapts to
the context.

The technical substrate the forge provides makes this possible:

- **Linux, not a mobile-restricted OS** — the base is Debian Trixie + bootc/OSTree, the full
  Debian ecosystem. Anything that runs on Debian runs on the device. There is no "mobile
  edition" limitation.
- **Android app compatibility via Waydroid** — the mobile app gap (banking, messaging, niche
  apps) is closed by the Android compatibility layer baked into the forge's base artifact.
- **bootc/OSTree atomic updates** — the device stays current and rollback-capable regardless
  of which role it is playing (phone, server, PC).
- **Halium vendor driver reuse** — the hardware (modem, GPU, sensors, display) works without
  reverse engineering, so the convergence is not blocked by driver gaps.

The product layer adds the **UX** that makes the convergence usable: a touch shell on the
phone, a desktop shell when docked, and a server-mode management surface when networked. The
forge does not provide these UX layers; it provides the substrate they run on.

---

## 5. Phone / Server / PC Continuity

The product delivers **continuity** across three roles on the same device:

| Role | Context | What the user does |
|---|---|---|
| **Phone** | handheld, touch | daily-driver mobile use — calls, messages, apps, camera |
| **Server** | docked / on the network, headless | hosted services — file sync, media, home automation, dev sandbox |
| **PC** | docked to an external display + keyboard/mouse | desktop Linux session — the same apps, the same files, the same identity as the phone role |

The three roles share:

- **The same filesystem** — one bootc/OSTree deployment, one `/home`, one set of user data.
- **The same app set** — a Debian app running as a phone app adapts to the desktop when docked;
  a Waydroid Android app does the same.
- **The same identity / session** — no separate "phone profile" and "desktop profile"; one
  user, one home, one set of credentials.
- **The same update / rollback model** — bootc/OSTree keeps the whole OS consistent across
  all three roles; a rollback reverts the device to a known-good state in every role at once.

The continuity is a **product-layer UX concern**, not a forge concern. The forge provides the
substrate (a full Linux userspace + Android app compat + atomic updates + working hardware
drivers); the product owns the role-switching UX, the docked/undocked adaptation, and the
server-mode management surface.

---

## 6. Commercial Model — CHATONS-Style Federation

The future product explores a **federated, ethical hosting model** inspired by the
[CHATONS](https://chatons.org/) collective (Collectif des Hébergeurs Alternatifs,
Transparents, Ouverts, Neutres et Solidaires) — a federation of hosting providers offering decentralized,
ethical services as an alternative to Big Tech.

Applied to a mobile Linux distribution, the model means:

- **Hosted image updates** — instead of a single corporate vendor pushing updates, a
  federation of hosting providers (associations, cooperatives, ethical ISPs, universities) each host the
  end-user distribution images and push updates to their subscribers. The bootc/OSTree model makes
  this safe (atomic updates, rollback, content-addressed images), so a subscriber can switch
  hosting providers without losing their device state.
- **Hosted app store / Waydroid image distribution** — Android app compatibility images and
  the product's own app store can be hosted by federation members, decentralizing the app
  distribution and giving users a choice of provider.
- **Hosted continuity services** — the phone-server-PC continuity (§5) needs sync, backup, and
  remote access services. In a CHATONS-style model, these are hosted by federation members
  rather than a single vendor, aligning with the "computer in your pocket" pitch without
  surrendering the user's data to a single cloud.
- **Decentralized, not corporate** — the value proposition is that no single company owns
  your phone, your apps, your updates, or your data. The forge produces the substrate; the
  federation hosts the services; the user owns the device.

This model is a **product-team decision**, not a forge decision. The forge must not bake any
specific commercial model into its base artifact — it must stay neutral so any downstream
product (corporate, federated, community, or self-hosted) can layer on it. The CHATONS-style
angle is recorded here as the leading candidate for the product's commercial direction,
informed by the GPT discussion of the project's positioning.

---

## 7. Technical Prerequisites (Forge Side)

For the future product to be buildable on the forge, the forge's base rootfs artifact must
satisfy these prerequisites. They are tracked in the roadmap as forge-side concerns so the
product is not blocked later:

| Prerequisite | Forge concern | Why the product needs it |
|---|---|---|
| Base artifact boots to a fully-supported CLI | P13 (TODO — current Containerfile is the inherited x86_64 desktop template, not the ARM64 smartphone image) | The product layers its UI `FROM` the base; the base must be solid before the UI lands. |
| Base artifact is layerable (no baked-in UI assumptions) | P15 (DEFERRED) | The product must be able to `FROM` the base and add a touch shell without fighting forge-side UI decisions. |
| Waydroid baked into the base (Layer 3) | P16 (TODO) | The product's Android app compatibility must work out of the box, not be a product-layer integration task. |
| Hardware drivers work (Halium vendor kernel + modules) | P03, P04, P10, P11 (TODO — evidence files not yet on disk) | The product's UI must be able to drive the display, touch, audio, modem, and sensors without re-porting drivers. |
| Atomic updates + rollback (bootc/OSTree) | P13 (TODO — see above) | The continuity model (§5) and the CHATONS-style hosted updates (§6) both depend on atomic, rollback-capable updates. |
| Device database covers the target fleet | P06, P07, P08, P09 | The product's addressable market is the forge's device coverage; the forge must keep expanding it. |

The product-side concerns (UI design, app store, continuity UX, commercial model, branding,
identity) are **not** forge deliverables and are **not** tracked here. They belong to the
future product project.

---

## 8. What This Document Is Not

- **Not a build plan** — nothing here is committed or scheduled. The forge roadmap
  ([`todo/ROADMAP.md`](../todo/ROADMAP.md)) tracks only the forge-side prerequisites (§7).
- **Not a product spec** — the product's own spec will be written when the product project
  starts, by the product team, in the product's repo. This document captures the vision so the
  forge does not lose sight of it.
- **Not a commitment to the CHATONS model** — the commercial model (§6) is a leading candidate
  from the GPT discussion, not a decision. The product team will make that decision.
- **Not a naming decision** — the product name (§2) is a product-team decision.

---

## Related Documents

- [`README.md`](../README.md) — Forge overview (positioned as a forge, not a distribution)
- [`docs/architecture.md`](architecture.md) — Architecture, including §3.5 forge-vs-product separation
- [`docs/justifications.md`](justifications.md) §12 — Justification: forge vs distribution
- [`todo/ROADMAP.md`](../todo/ROADMAP.md) — Forge roadmap; product-vision points are recorded
  under "Future Product" for traceability but are not forge deliverables.