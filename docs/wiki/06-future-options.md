# 06 — Future Options & Open Questions

## The NPU landscape beyond the vendor stack (evaluated 2026-07)

| Option | Status for RK3562 | Position |
|---|---|---|
| Vendor rknpu + librknnrt | Proven on this device; driver 0.9.8 backported | **Adopted (D008)** |
| Mainline "rocket" DRM accel driver + Mesa Teflon | Merged upstream, **RK3588 only**; no RK3562 support announced | Monitor. The eventual off-ramp from the vendor kernel |
| Out-of-tree DKMS rknpu ([w568w/rknpu-module](https://github.com/w568w/rknpu-module), ~2026-03) | Packages the vendor driver for newer kernels, RK356x-oriented | Candidate bridge for Track B; unproven on RK3562 |
| CPU (onnxruntime/XNNPACK) | Always works, slow | Correctness reference only |
| GPU (Mali-G52) | No supported inference path | Out of scope |

**Structural consequence:** NPU support anchors Track A to the vendor 6.1
kernel. Any Track B (newer/mainline kernel) candidate is *expected* to lose the
NPU until either rocket gains RK3562 support or the DKMS module is validated —
record that capability gap explicitly in any Track B test report, per D003.

References: [LWN on the rocket driver](https://lwn.net/Articles/1029800/),
[Phoronix announcement](https://www.phoronix.com/news/Rocket-Rockchip-NPU-Driver),
[DietPi RK356x mainline-NPU tracking issue](https://github.com/MichaIng/DietPi/issues/7996).

## Kernel pin upgrade path (within Track A)

The pin is `armbian/linux-rockchip @ rk-6.1-rkr3` (6.1.75). Upstream has
rkr4.1 / rkr5 / rkr5.1 / rkr6.1. A pin bump would supersede the 0.9.8 driver
backport (drop the userpatch when the tree includes it natively) but changes
*every* driver at once — treat it as a full test-matrix event, not an NPU
tweak. The surgical backport exists precisely so the pin doesn't have to move
on the NPU's schedule.

If a future runtime (librknnrt > 2.3.x or a newer RKLLM) demands a driver
> 0.9.8, repeat the backport recipe from wiki 03: find the version-bump commit
on a newer rkr branch, take the pristine commit patch, `git apply --check`
against the pinned tree, and watch for helpers the older tree lacks.

## Open questions

1. **Is `/sys/kernel/debug/rknpu/load` live or static?** The rk-tui spec flags
   vendor NPU load reporting as possibly static. Answer during first on-device
   validation: read it idle vs. under inference (wiki 04 §5). If static, the
   project owns the kernel now — the driver can be patched.
2. **Does librknnrt 2.3.2 fully exercise driver 0.9.8 on RK3562?** Expected
   yes (it is the stock pairing); confirmed only when matrix rows 17–18 pass
   on a flashed candidate image.
3. **RKLLM version on stock.** The capture script grabs `librkllmrt` version
   evidence, but the exact stock RKLLM release should be recorded in the
   baseline before the stock system is retired.
4. **Boot chain discovery** (`../BOOT_CHAIN_DISCOVERY.md`) is still the
   prerequisite for any eMMC ambitions; NPU work stays microSD-only with it.

## Near-term roadmap (in dependency order)

1. Flash the two-patch bookworm image; run P0 rows, then rows 17–18.
2. Package `librknnrt` and RKLLM as opt-in versioned debs in the overlay.
3. Stand up the Conrad model-conversion environment (`rknn-toolkit2`, 2.3.x).
4. Wire NPU load/devfreq/thermal into the dashboard collectors, then rk-tui's
   NPU panel (spec: `~/repos/ArmbianBuild/rm_tablet.md`).
5. Revisit rocket/DKMS status before starting any Track B kernel candidate.
