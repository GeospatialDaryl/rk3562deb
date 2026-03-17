# Chromium Hardware Acceleration for RK3562

**Date:** 2026-03-17
**Status:** Approved (revised after spec review)

## Problem

Chromium on the RK3562 tablet (Debian Bookworm, Sway/Wayland, kernel 5.10) runs entirely in software mode. YouTube 1080p playback stutters badly because:

1. **GPU compositing uses SwiftShader (CPU)** — the build script chose SwiftShader because Mali G52's EGL blob lacks `EGL_KHR_platform_wayland`. All rendering, compositing, and rasterization goes through the CPU.
2. **VAAPI hardware video decode is non-functional** — the community `rockchip_drv_video.so` driver failed to build due to missing/incorrect dependencies, so the build script fell back to SW-only Chromium flags.

### Rejected Alternative: V4L2 Stateless Decode

The original design proposed V4L2 stateless video decode. This was **rejected** after testing on the actual device revealed that the BSP kernel 5.10 does NOT expose V4L2 M2M codec devices (no rkvdec/hantro in `/sys/class/video4linux/*/name`). All V4L2 devices are camera-related (rkcif, rkisp). Video decode on this SoC goes exclusively through MPP (`/dev/mpp_service`).

### Rejected Alternative: Vulkan Compositing

No Mali Vulkan ICD is installed (`/usr/share/vulkan/icd.d/` contains only mesa ICDs for other GPUs). The `libmali-bifrost-g52-g13p0-gbm.so` blob variant does not ship Vulkan support.

## Solution: Native Mali EGL + Fixed VAAPI Build

Two independent improvements that together solve the stuttering:

1. **GPU compositing:** Switch from SwiftShader to native Mali EGL via GBM platform
2. **Video decode:** Fix the `rockchip_drv_video.so` VAAPI driver build so MPP hardware decode works

### Key Insight: Mali EGL via GBM

Mali G52's EGL blob exposes `EGL_KHR_platform_gbm`. Chromium's Ozone Wayland backend can use native EGL via GBM — it does NOT require `EGL_KHR_platform_wayland`. The SwiftShader workaround was unnecessary.

### Key Insight: Why VAAPI Build Fails

The current build script (lines 426-482) clones `sujit-168/rk_hw_base` and runs `make`, but `rk_hw_base` requires:
- MPP headers and library (from HermanChen's fork or the installed `librockchip-mpp-dev`)
- RGA library built with meson from the `jellyfin-rga` fork (not the `airockchip/librga` prebuilt that the build script installs)

The build fails silently because the dependencies aren't correctly set up.

## Changes

### Change 1: Chromium Flags Rewrite

Replace `/etc/chromium.d/rk3562-hw-accel` contents.

**Remove:**
- `--use-gl=angle` / `--use-angle=swiftshader` (SwiftShader compositing)

**New flags (when VAAPI driver is present):**
```bash
# RK3562 hardware acceleration — sourced by /usr/bin/chromium wrapper
# Native Mali EGL (GBM platform) for compositing.
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
```

**New flags (when VAAPI driver is absent — fallback):**
```bash
# RK3562 — native Mali EGL compositing, software video decode
# (VAAPI driver not found at build time)
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ozone-platform=wayland"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=egl"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ignore-gpu-blocklist"
CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --enable-gpu-rasterization"
```

**Note:** The fallback branch intentionally omits `--disable-gpu-sandbox` — without VAAPI, there is no need for `/dev/mpp_service` access from the GPU process, so the sandbox can stay enabled for better security.

**Rationale for each flag:**
- `--use-gl=egl`: Use native EGL (Mali G52 via GBM) instead of ANGLE/SwiftShader
- `--ignore-gpu-blocklist`: Mali G52 is not on Chromium's allowlist
- `--enable-gpu-rasterization`: Tile rasterization via Mali GLES
- `--disable-gpu-sandbox`: VAAPI driver needs access to `/dev/mpp_service`
- `--enable-accelerated-video-decode`: Opt-in for HW video decode
- `VaapiVideoDecoder`: VAAPI H.264/HEVC decode path
- `VaapiVideoDecodeLinuxGL`: Use GL textures for decoded frames
- `VaapiIgnoreDriverChecks`: Bypass Chromium's VAAPI driver allowlist (rockchip driver is unknown to Chromium)
- `--disable-features=UseChromeOSDirectVideoDecoder`: Use standard Linux VAAPI, not ChromeOS path

**Important:** Both branches now use `--use-gl=egl` (native Mali EGL). The only difference is whether VAAPI decode flags are included. Even without VAAPI, GPU compositing via Mali dramatically improves UI responsiveness.

### Change 2: Fix VAAPI Driver Build

The `build_vaapi.sh` section (lines 426-482) needs to be rewritten to properly build the dependency chain.

**Current state on device (verified via SSH):**
- `librockchip-mpp-dev` IS installed — headers at `/usr/include/rockchip/`
- `librga.so` is MISSING — the airockchip prebuilt copy never made it to the rootfs
- `libva-dev` is NOT installed (only runtime `libva2`)
- `pkg-config`, `meson`, `ninja-build` are NOT installed
- `/usr/include/rga/` does NOT exist (headers never copied)

**Fix — rewrite `build_vaapi.sh` heredoc with these steps:**

1. **Install build dependencies inside the chroot** (at the top of `build_vaapi.sh`):
   ```bash
   apt-get install -y libva-dev libdrm-dev pkg-config meson ninja-build
   ```

2. **librga** — Keep the `airockchip/librga` prebuilt approach (it's a binary blob, meson build is only needed if building from source). Fix the install by:
   - Copying `librga.so` to `/usr/lib/aarch64-linux-gnu/`
   - Checking SONAME with `objdump -p librga.so | grep SONAME` and creating the matching symlink
   - Copying headers to `/usr/include/rga/`
   - Running `ldconfig`

3. **rk_hw_base** — Build with explicit include/library paths:
   ```bash
   make CFLAGS="-I/usr/include/rockchip -I/usr/include/rga" \
        LDFLAGS="-L/usr/lib/aarch64-linux-gnu"
   ```
   After building, install system-wide:
   - Copy `lib/librk_hw_base.so` to `/usr/lib/aarch64-linux-gnu/`
   - Copy headers to `/usr/include/rk_hw_base/`
   - Run `ldconfig`

4. **rk_vaapi_driver** — Build with paths to `rk_hw_base` and other deps:
   ```bash
   make CFLAGS="-I/usr/include/rockchip -I/usr/include/rga -I/usr/include/rk_hw_base" \
        LDFLAGS="-L/usr/lib/aarch64-linux-gnu"
   ```
   Install `lib/rockchip_drv_video.so` to `/usr/lib/aarch64-linux-gnu/dri/`

5. **Cleanup** — Remove build deps to keep rootfs small:
   ```bash
   apt-get purge -y meson ninja-build
   apt-get autoremove -y
   ```
   Keep `libva-dev` (needed at runtime for the VAAPI driver to work? — verify; if only headers, purge it too).

6. **Remove the second `rk_hw_base` clone** — since headers/lib are installed system-wide after step 3, `rk_vaapi_driver` no longer needs a sibling clone.

**Build order:** librga install → rk_hw_base → rk_vaapi_driver

### Change 3: Build Script Conditional Logic

The `if [ "${FF_VAAPI_ENABLED}" = "true" ]` conditional at line 690 stays (it correctly branches on whether `rockchip_drv_video.so` exists). Both branches are updated to use `--use-gl=egl` instead of `--use-gl=angle --use-angle=swiftshader`.

### Change 4: No New Udev Rules Needed

The existing `98-rockchip-mpp.rules` (lines 345-351) already provides `GROUP="video", MODE="0660"` for `mpp_service`, `rkvdec*`, `rkvenc*`, `vepu*`, `vdpu*`. The existing `99-mali.rules` covers `mali0`. No new udev rules are needed — V4L2 stateless approach was rejected, so no V4L2 device rules required.

### Change 5: Manual SW Fallback in Comments

The generated config file includes a commented-out SwiftShader fallback block with the complete flag set for manual activation:

```bash
# ── FALLBACK: uncomment below and comment above if Mali EGL crashes Chromium ──
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-gl=angle"
# CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --use-angle=swiftshader"
```

## Files Modified

- `build_rootfs.sh`:
  - Lines 426-482: Rewrite VAAPI driver build to fix dependency chain
  - Lines 673-679: Update comment block (remove stale "Mali lacks Wayland platform" justification for SwiftShader)
  - Lines 688-717: Update Chromium flags (both branches: SwiftShader → native EGL)

## Testing

### Happy Path
1. Rebuild rootfs and flash to tablet
2. Verify VAAPI driver exists: `ls /usr/lib/aarch64-linux-gnu/dri/rockchip_drv_video.so`
3. Verify VAAPI works: `DISPLAY= WAYLAND_DISPLAY= LIBVA_DRIVER_NAME=rockchip LIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri vainfo` should show rockchip driver with H.264/H.265 profiles
4. Launch Chromium, check `chrome://gpu`:
   - GL renderer should show "Mali-G52" (not SwiftShader)
   - "Video Decode" should show "Hardware accelerated"
   - "Rasterization" should show "Hardware accelerated"
5. Play YouTube 1080p H.264 video — should be smooth
6. Check `chrome://media-internals` during playback: look for `kVideoDecoderName: VaapiVideoDecoder`
7. Monitor CPU usage: `top` should show significantly lower CPU than before during 1080p playback
8. Test WebGL: visit `chrome://gpu` and confirm WebGL 2.0 is available

### Failure Cases
9. If `chrome://gpu` shows SwiftShader despite new flags → Mali EGL init failed; check Chromium log with `--enable-logging=stderr --v=1`
10. If video plays but `media-internals` shows software decoder → VAAPI path not activating; check `vainfo` output and `LIBVA_DRIVER_NAME` env var
11. Test VP9 content: YouTube may serve VP9 which has no HW decode; verify graceful software fallback (should still play, just with higher CPU)

## Risks

- **Mali GBM EGL + Chromium Ozone:** If Chromium's GPU process crashes on init, the browser won't start. Mitigation: commented-out SwiftShader fallback in config file.
- **VAAPI driver stability:** `rk_vaapi_driver` is a small community project (6 commits, 1 star). May have bugs with certain video streams. Mitigation: Chromium falls back to software decode if VAAPI fails for a specific stream.
- **VP9/AV1 content:** MPP only handles H.264/HEVC. YouTube may serve VP9 by default and Chromium will software-decode it (may stutter at 1080p on this CPU). Mitigation: install the `h264ify` browser extension to force YouTube to serve H.264, or add `--disable-features=Vp9Decoder` to force software VP9 off entirely.
- **`--disable-gpu-sandbox` security:** Disabling the GPU sandbox is a security trade-off. Acceptable on a personal tablet. The VAAPI driver needs `/dev/mpp_service` access which the sandbox blocks.
