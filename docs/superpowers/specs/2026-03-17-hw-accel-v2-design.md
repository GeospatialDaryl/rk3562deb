# Hardware Acceleration v2 for RK3562 Debian Tablet

**Date:** 2026-03-17
**Status:** Approved
**Supersedes:** 2026-03-17-chromium-hw-accel-design.md (v1 — never worked)

## Problem

Chromium on the RK3562 tablet (Debian Bookworm, Sway/Wayland, kernel 5.10.198) runs entirely in software mode. GPU compositing fails and VAAPI video decode is absent. YouTube 1080p stutters badly.

### Root Cause Analysis (4 compounding failures)

| # | Failure | Evidence |
|---|---------|----------|
| 1 | **Wrong Mali blob variant** | Installed `x11-gbm` (no Wayland EGL). Running Sway (Wayland). `eglInitialize` fails on GBM platform. |
| 2 | **KMD/UMD version mismatch** | Kernel driver: g18p0. Userspace blob: g13p0. 5-generation gap. |
| 3 | **Mesa/Mali library conflict** | Mesa's libgbm (68KB) and GLVND dispatcher override Mali's shims. Only Mesa's `50_mesa.json` EGL vendor config exists. |
| 4 | **VAAPI driver never built** | `rockchip_drv_video.so` missing. Build fails silently due to dependency issues. |

### Why v1 Failed

The v1 design correctly identified SwiftShader as a problem and proposed native Mali EGL, but:
- Did not detect the blob variant mismatch (x11-gbm has no Wayland platform support)
- Did not detect the KMD/UMD generation gap (g18p0 kernel vs g13p0 userspace)
- Did not address the Mesa/Mali library conflict (GLVND dispatcher routing to Mesa)
- VAAPI build fixes were incomplete

### Rejected Alternatives

- **Panfrost (open-source Mali driver):** Tested in the newrk3562 project — causes kernel hangs on RK3562. Rejected.
- **V4L2 stateless video decode:** BSP kernel has no V4L2 M2M codec devices. All video decode goes through MPP. Rejected.
- **Vulkan compositing:** No Vulkan ICD available for Mali G52 in any available blob. Rejected.
- **Fixing on kernel 5.10:** KMD g18p0 has no matching UMD available (only g2p0, g13p0, g24p0 exist). Version gap too large. Rejected in favor of kernel upgrade.

## Solution: Kernel 6.1 + Matched Mali Blob + Fixed VAAPI

Four coordinated changes that together solve all 4 root causes:

1. **Kernel upgrade:** 5.10.198 → 6.1.118 (Mali KMD g25p0, matched by g24p0 UMD)
2. **Mali blob swap:** g13p0-x11-gbm → g24p0-wayland-gbm (Wayland-native, close KMD match)
3. **Chromium flags:** ANGLE → native EGL
4. **VAAPI build:** Fix dependency ordering

### Key Insight: The Blob Variant

The `libmali-bifrost-g52-g13p0-x11-gbm` blob does NOT provide `EGL_KHR_platform_wayland`. Under Sway (Wayland compositor), `eglInitialize` fails because the blob can't create a Wayland EGL context. The `wayland-gbm` variant provides this extension. This was the single biggest blocker.

### Key Insight: The KMD/UMD Match

| Kernel | KMD Version | Best Available UMD |
|--------|------------|-------------------|
| 5.10.198 (Firefly) | g18p0 | g13p0 (5 gen gap) or g24p0 (6 gen gap, wrong direction) |
| 6.1.118 (Rockchip) | g25p0 | g24p0 (1 gen gap — excellent match) |

Kernel 6.1 from `rockchip-linux/kernel` branch `develop-6.1` is the clear winner. It was already booted on this tablet in the newrk3562 project (Alpine). The `rk817_battery.c` driver is present in develop-6.1.

## Changes

### Change 1: Kernel Upgrade

**Files:** `build.sh`

Replace kernel source:
```
KERNEL_URL="https://github.com/rockchip-linux/kernel.git"
KERNEL_BRANCH="develop-6.1"
KERNEL_DEFCONFIG="rockchip_linux_defconfig"
```

U-Boot stays on Firefly (`rk356x/firefly-5.10`) — it loads any kernel via extlinux.conf.

**Overlay handling:**
- The existing overlay has custom `rk817_battery.c`, `rk817_charger.c`, `rk808.c` patched for the Firefly 5.10 kernel.
- The develop-6.1 kernel has its own upstream versions of these files.
- Strategy: Build WITHOUT the overlay PMIC patches first. If battery breaks, port the fixes to 6.1 API.
- The overlay defconfig needs updating for `rockchip_linux_defconfig` format.
- Mali Bifrost (g25p0) is already built-in in develop-6.1's default config.

**The `scripts/config` overrides in build.sh** (DYNAMIC_FTRACE, BCMDHD, etc.) stay — they're GCC 14 / WiFi driver fixes independent of kernel version.

### Change 2: Mali Blob Swap

**Files:** `build_rootfs.sh` (lines 279-297), `debs/`, `mali/`

**Remove:**
- `debs/libmali-bifrost-g52-g13p0-x11-gbm_1.9-1_arm64.deb`
- `mali/libmali-bifrost-g52-g13p0-gbm.so`

**Add:**
- `debs/libmali-bifrost-g52-g24p0-wayland-gbm_1.9-1_arm64.deb` from [tsukumijima/libmali-rockchip](https://github.com/tsukumijima/libmali-rockchip) latest release (v1.9-1-20260312-bd33ee2)

**Rewrite Mali install section (lines 279-297):**

The new approach:
1. The `.deb` gets installed via `dpkg -i` in the existing deb-install loop (lines 270-273) — places Mali shims in `/usr/lib/aarch64-linux-gnu/mali/` with `00-aarch64-mali.conf` for ldconfig.
2. After deb install, remove Mesa's conflicting files that override Mali:
   - Remove `libEGL_mesa.so.0*` (Mesa's EGL ICD)
   - Remove `/usr/share/glvnd/egl_vendor.d/50_mesa.json` (GLVND routing to Mesa EGL)
   - Remove Mesa's `libgbm.so.1*` from `/usr/lib/aarch64-linux-gnu/` (Mali provides its own via the `mali/` subdir)
3. Run `ldconfig` — Mali's shims now resolve unambiguously.
4. Remove the old manual symlink loop (lines 286-294) — the deb handles this.
5. Remove the separate `mali/*.so` copy step (lines 283-284) — the deb handles this.

**The `mali/` directory in the project** can be removed entirely once the deb is in `debs/`.

### Change 3: Chromium Flags

**Files:** `build_rootfs.sh` (lines 696-730)

**When VAAPI is present:**
```bash
# RK3562 hardware acceleration — sourced by /usr/bin/chromium wrapper
# Native Mali EGL (wayland-gbm platform) for GPU compositing.
# VAAPI hardware video decode via rockchip_drv_video.so + MPP.
export LIBVA_DRIVER_NAME=rockchip
export LIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ozone-platform=wayland"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=egl"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ignore-gpu-blocklist"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --enable-gpu-rasterization"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --disable-gpu-sandbox"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --enable-accelerated-video-decode"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --enable-features=VaapiVideoDecoder,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --disable-features=UseChromeOSDirectVideoDecoder"
# ── FALLBACK: if --use-gl=egl crashes, try ANGLE instead: ──
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=angle"
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-angle=opengles"
```

**When VAAPI is absent (fallback):**
```bash
# RK3562 — Native Mali EGL compositing, software video decode
# (VAAPI driver not found at build time)
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ozone-platform=wayland"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=egl"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ignore-gpu-blocklist"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --enable-gpu-rasterization"
# ── FALLBACK: if --use-gl=egl crashes, try ANGLE instead: ──
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=angle"
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-angle=opengles"
```

**Rationale for `--use-gl=egl`:** With the wayland-gbm blob properly installed and Mesa EGL removed, Chromium can use native EGL from Mali directly. No ANGLE indirection needed. If Chromium 146 rejects `--use-gl=egl`, the commented ANGLE fallback is ready.

### Change 4: VAAPI Build Fixes

**Files:** `build_rootfs.sh` (lines 426-491)

The build flow stays the same (librga → rk_hw_base → rk_vaapi_driver). Fixes:

1. **Add `libva2 libva-drm2` to the main rootfs apt-get install** (not just as build deps inside the VAAPI chroot). This ensures VAAPI runtime libraries survive the build-dep cleanup purge.

2. **Keep `git` available** until the entire VAAPI build completes. Currently `git` can be purged before the second clone (line 473) if a partial re-run happens.

3. **Don't purge `build-essential`** — actually this IS safe to purge since we only need it for the VAAPI build. Keep current behavior.

No structural changes to the VAAPI build — the sujit-168 repos and build order are correct.

### Change 5: Update Stale Comments

**Files:** `build_rootfs.sh`

- Line 683-684: Remove "this Chromium build only allows ANGLE-based GL backends" — no longer true.
- Line 100: Remove "Mali glamor crashes under Xwayland same as X11" if it was blob-variant-specific.

## Files Modified Summary

- `build.sh`: Kernel URL/branch/defconfig (3 lines)
- `build_rootfs.sh`:
  - Lines 279-297: Rewrite Mali install (remove manual copy, add Mesa cleanup)
  - Lines 426-491: Minor VAAPI dep ordering fix
  - Lines 682-730: Rewrite Chromium flags and comments
- `debs/`: Remove old Mali deb, add new g24p0-wayland-gbm deb
- `mali/`: Remove directory (no longer needed)

## Testing

### Verification Order

1. `uname -r` → `6.1.118`
2. `dmesg | grep mali` → `g25p0` and `Probed as mali0`
3. `cat /sys/class/power_supply/battery/capacity` → percentage (battery driver works)
4. `eglinfo` → Mali-G52, `eglInitialize` succeeds on GBM platform
5. Sway starts, no software rendering fallback
6. `chrome://gpu` → GL renderer "Mali-G52", Rasterization "Hardware accelerated"
7. `LIBVA_DRIVER_NAME=rockchip vainfo` → H.264/H.265 profiles listed
8. YouTube 1080p H.264 → smooth, `chrome://media-internals` shows `VaapiVideoDecoder`
9. `top` during playback → significantly lower CPU than before

### Fallback Paths

| If this fails... | Do this |
|---|---|
| Battery (step 3) | Port overlay PMIC patches from 5.10 to 6.1 kernel API |
| EGL init (step 4) | Try `g13p0-wayland-gbm` blob instead (wider KMD compatibility) |
| Chromium GPU (step 6) | Switch `--use-gl=egl` → `--use-gl=angle --use-angle=opengles` |
| VAAPI (step 7) | GPU compositing still works without VAAPI; video plays via software decode |

## Risks

- **Kernel regression:** New kernel may have different behavior for display, WiFi, touchscreen, or battery. Mitigation: Keep the 5.10 kernel Image as a backup boot option in extlinux.conf.
- **g24p0 UMD instability:** Community blob, less tested than g13p0. Mitigation: g13p0-wayland-gbm is the fallback.
- **`--disable-gpu-sandbox` security:** Required for VAAPI `/dev/mpp_service` access. Acceptable on a personal tablet.
- **VP9/AV1 content:** MPP only handles H.264/HEVC. YouTube may serve VP9. Mitigation: h264ify extension or `--disable-features=Vp9Decoder`.
