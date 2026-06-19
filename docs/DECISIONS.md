# Decision Log — Samwise Armbian Platform

## Format

Each decision is numbered and includes: context, decision, rationale, and consequences.

---

## D001: Use Armbian Build Framework as upstream build engine

**Date:** 2026-06-18
**Status:** Accepted

**Context:** The project needs a reproducible image-build pipeline for an ARM64 tablet. The existing build.sh works but lacks manifest tracking, source pinning, and formal upgrade paths.

**Decision:** Adopt the Armbian Build Framework as the upstream build dependency, pinned by commit SHA. All tablet-specific work lives in a separately versioned overlay.

**Rationale:** Armbian provides kernel, bootloader, rootfs assembly, and containerized cross-build support. It is designed for this class of problem and supports WSL2/Ubuntu 24.04.

**Consequences:** Must learn Armbian's extension/userpatch conventions. Must validate all configuration against the pinned source, not internet examples.

---

## D002: eMMC writes forbidden in initial phases

**Date:** 2026-06-18
**Status:** Accepted

**Context:** The tablet's internal eMMC (~116.5 GiB) contains the vendor Android installation. Accidental writes could brick the device.

**Decision:** No scripted writes to /dev/mmcblk2 in any project script. All flash helpers reject eMMC targets with hard guards.

**Rationale:** The project's value is a safe, removable-media development platform. eMMC migration is a separate, later milestone.

**Consequences:** All images must boot from microSD. Flash scripts require explicit target identification with size/model guards.

---

## D003: Compatibility-first kernel strategy (Track A before Track B)

**Date:** 2026-06-18
**Status:** Accepted

**Context:** The known-good system runs a vendor-derived 6.1.118 kernel with custom display, touch, Wi-Fi, and NPU support. Generic newer kernels may lack these drivers.

**Decision:** First Armbian image preserves 6.1-based kernel behavior (Track A). Newer kernel candidates (Track B) are separate experiments that cannot overwrite Track A artifacts.

**Rationale:** A kernel that boots but loses tablet hardware support is a regression. Compatibility must be proven before modernization.

**Consequences:** Multiple kernel candidate profiles. Independent test reports per candidate. Track A remains reproducible even as Track B evolves.

---

## D004: microSD-only images until boot chain is documented

**Date:** 2026-06-18
**Status:** Accepted

**Context:** The boot mechanism (extlinux vs. U-Boot env vs. other) has not been formally documented from evidence.

**Decision:** All images target removable microSD only. Boot chain discovery (Phase 1) must complete before any bootloader installation decisions.

**Rationale:** Assumptions about boot mechanisms cause bricked devices. Evidence-based discovery prevents this.

**Consequences:** Phase 1 is a blocking gate for image promotion.

---

## D005: Containerized build as release-reference path

**Date:** 2026-06-18
**Status:** Accepted

**Context:** Build reproducibility depends on consistent toolchain and dependency versions.

**Decision:** Containerized Armbian build on Conrad WSL2 Ubuntu 24.04 is the default and release-reference build mode.

**Rationale:** Isolates host package drift, gives reproducible dependency boundary, aligns with Armbian's supported model.

**Consequences:** Docker must be available on the build host. Native builds are a developer convenience, not the release path.

---

## D006: Known-good system runs from eMMC, not SD card

**Date:** 2026-06-18
**Status:** Observed (corrects spec assumption)

**Context:** The spec (Section 2.1) states "Root filesystem: microSD ext4 root currently mounted from `/dev/mmcblk0p4`". Baseline capture on 2026-06-18 shows the live system is actually rooted on **eMMC** (`mmcblk2p25`, 110.4 GiB ext4, mounted at `/`).

**Observed evidence:**
- `lsblk` shows only `mmcblk2p25` has a mountpoint (`/`)
- `cmdline` shows `root=PARTUUID=86190000-0000-4d2d-8000-7ad7000056e0` (eMMC)
- `/boot/` is empty — no kernel or DTB in a filesystem
- SD card (`mmcblk0`) is present with 4 partitions but nothing mounted

**Decision:** Acknowledge that the "known-good system" being captured is the eMMC-resident Debian installation. The SD card boot path is proven by the existing `rk3562deb` build system but was not active during this capture. The eMMC baseline is still valid evidence for device-tree, hardware state, and driver behavior.

**Consequences:**
- SD card boot path for candidate images must be established independently (using the existing build system's extlinux.conf approach, which is proven to work)
- The eMMC protection policy remains unchanged — no writes to mmcblk2
- Future captures should document which boot path was active

---

## D007: Boot configuration method is extlinux (SD) / direct U-Boot (eMMC)

**Date:** 2026-06-18
**Status:** Accepted

**Context:** The spec warned not to assume extlinux. Discovery shows two distinct paths:
- **SD card boot:** Uses `extlinux.conf` on a VFAT boot partition (proven by existing build system)
- **eMMC boot:** U-Boot passes bootargs directly (no extlinux.conf, no `/boot` filesystem)

**Decision:** Candidate Armbian images targeting SD card will use extlinux.conf, matching the existing proven SD card boot path. This is compatible with Armbian's standard boot mechanism.

**Consequences:** Armbian's extlinux-based boot is aligned with the SD card path. No custom boot script needed for Track A.
