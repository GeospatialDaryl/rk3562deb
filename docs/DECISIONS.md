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

---

## D008: NPU uses the vendor RKNPU stack; NPU enablement pins Track A to the vendor kernel

**Date:** 2026-07-04
**Status:** Accepted

**Context:** The stock system runs RKNN/RKLLM workloads on the RK3562's 1-TOPS NPU via the vendor `rknpu` kernel driver (0.9.7 in the pinned rk35xx-vendor-6.1 tree) plus Rockchip's `librknnrt` userspace. The mainline "rocket" DRM accel driver supports RK3588 only, with no announced RK3562 support; an out-of-tree DKMS module exists for RK356x but is unproven. Audit of the first built image (2026-06-20, vendor 6.1.75) found `rk3562.dtsi` leaves the NPU and its IOMMU `status = "disabled"` and `rk3562-rk817-tablet-v10.dts` never enables them, while the stock DTB (baseline `device-tree/fdt.dts`) runs the NPU enabled with `rknpu-supply` on the `vdd_npu` PWM regulator.

**Decision:** Track A uses the vendor RKNPU stack exclusively: in-tree `rknpu` driver, DT nodes enabled via userpatch `enable-rknpu-rk3562-rk817-tablet.patch` (mirrors stock/EVB wiring: `&rknpu` okay + `rknpu-supply = <&vdd_npu>`, `&rknpu_mmu` okay), and `librknnrt`/RKLLM packaged as opt-in, separately versioned userland. CPU inference (XNNPACK/onnxruntime) is a correctness reference only; GPU (Mali-G52) inference is out of scope.

**Rationale:** The vendor stack is the only production-viable NPU path for RK3562 and is already proven on this exact tablet. `librknnrt` enforces a minimum kernel-driver version, so driver and runtime versions must be recorded together (baseline capture now collects both).

**Consequences:** NPU support anchors samwise to the vendor 6.1 kernel; any Track B (newer kernel) candidate is expected to lose NPU functionality until mainline gains RK3562 support, and must record that gap explicitly. Stock driver/runtime versions must be captured from the device before reflashing (`/sys/kernel/debug/rknpu/version`, `librknnrt.so` version string) to confirm the ≤ 0.9.7 compatibility assumption.

**Update (2026-07-04):** Provenance captured from the stock device: RKNPU driver **v0.9.8**, librknnrt **2.3.2** (2025-04-09). The pinned tree's 0.9.7 driver is below RKLLM's documented ≥ 0.9.8 minimum, so upstream commit `736d89f34415` ("driver: rknpu: Update rknpu driver, version: 0.9.8", rk-6.1-rkr4.1) is backported as userpatch `rknpu-driver-0.9.8-backport.patch` alongside the DT enable patch. The pristine commit applies cleanly to the rkr3 tree; the intermediate rk3576 devfreq change was deliberately excluded (depends on `rockchip_opp_set_low_length`, absent from the pinned tree).

**Update (2026-07-05):** The ≥ 0.9.8 driver contract is now empirically confirmed, not just documented. `librkllmrt` **1.3.0** (RKLLM SDK, RK3562-supported since release-v1.2.0) was packaged as `debs/librkllmrt_1.3.0-2_arm64.deb` (runtime `.so` + `rkllm.h` pinned to the same upstream tag — mixing versions across a re-package is an ABI hazard; `llm_demo` built from upstream source, since no prebuilt Linux binary is shipped upstream). Running the packaged `llm_demo` on the stock eMMC system (still driver 0.9.8) printed `rkllm-runtime version: 1.3.0, rknpu driver version: 0.9.8, platform: RK3562` with no driver-too-low warning, and a converted Qwen3-0.6B model (w4a16_g64, `scripts/convert-rkllm-model.sh`) produced a correct answer end-to-end through `librkllmrt` + the vendor driver — the first LLM inference run on this project's NPU stack. This is stock-system precedent only; hardware test matrix row 18 still requires the same run on a flashed candidate image. (A literal `"0.9.7"` string is also present in `librkllmrt.so` near the version-warning format strings; the actual check substitutes runtime `%d.%d.%d` values, so the documented ≥ 0.9.8 floor stands, not 0.9.7.)

Packaging lesson (toolchain ABI): the first packaging attempt (`librkllmrt_1.3.0-1`, superseded and deleted) cross-compiled `llm_demo` with Conrad's native Ubuntu 24.04 sysroot, which leaked `GLIBC_2.38`/`GLIBCXX_3.4.32` symbol requirements into the binary — both above what Debian 12 Bookworm (the target OS) ships (2.36/3.4.30), so the binary failed to start on target with `version 'GLIBC_2.38' not found`. Root cause: GCC's cross-compiler bundles its own libstdc++ headers/library ahead of any `--sysroot`, and Ubuntu 24.04's `<stdlib.h>` substitutes `__isoc23_strtol` for plain `strtol()` at compile time. Fix (`-2`): cross-compile against a locally fetched Debian 12 Bookworm arm64 sysroot with explicit `-isystem`/`-nostdlib++` flags forcing the Bookworm libc/libstdc++ ahead of the toolchain's own. General rule for this project: any target-userland binary built on Conrad (not just RKLLM) must be linked against a Bookworm sysroot, not Conrad's native one — full root-cause writeup lives in the packaged deb's own `/usr/share/doc/librkllmrt/README.samwise`.

---

## D009: ggml/llama.cpp NPU backend evaluated and deferred for RK3562

**Date:** 2026-07-04
**Status:** Deferred (revisit if upstream changes; see Consequences)

**Context:** As a possible alternative or complement to the proprietary vendor RKLLM runtime (D008), the ggml/llama.cpp ecosystem's NPU backend work was evaluated as a research question: does a more standard, actively-maintained inference stack exist for this hardware? The live project in this space, `invisiofficial/rk-llama.cpp`, targets **RK3588 only** and builds on RKNPU's matmul acceleration for that chip. Rockchip's own `rknn_matmul_api.h` header (RKNN SDK 2.3.2) documents RK3562's matmul support as **int8 + fp16 only — no int4 matmul pipeline**. The mainline "rocket" DRM accel driver (tracked in wiki 06) is also RK3588-only as of 2026-07, with no announced RK3562 work.

**Decision:** Do not pursue a ggml/llama.cpp NPU backend for RK3562 at this time. RKLLM (D008) remains the sole LLM inference runtime for this platform.

**Rationale:** `rk-llama.cpp` has no RK3562 fork or support, so adopting it would mean a from-scratch port, not a drop-in. Even on its native RK3588 target, the project's own published numbers show *decode* throughput regressing versus plain CPU llama.cpp (25.8 to 20.2 tok/s), with only prefill improving (~2.8x) — a mixed result on the hardware it was designed for. RK3562 additionally lacks the int4 matmul pipeline the RK3588 int4 quant paths rely on, so even a port would need a different, unproven quantization strategy. RKLLM already gives RK3562 a working, vendor-supported w4a16 quantized path (D008 update, 2026-07-05, on-device confirmed), so switching runtimes for a regression on unsupported hardware is not justified.

**Consequences:** Track A's LLM serving path stays vendor-only (RKLLM), matching the RKNN vision-inference stance in D008. Revisit if: (a) `rk-llama.cpp` or a fork adds real RK3562 support, (b) its RK3588 decode regression is resolved, or (c) the mainline rocket driver gains RK3562 support (wiki 06 open item), any of which would change the cost/benefit of a from-scratch backend. No project code or packaging changes result from this decision; it is recorded to avoid re-litigating the same research question later.
