# Front Camera Bring-Up Design (S5K5E8)
**Date:** 2026-04-04  
**Goal:** Get the front camera (Samsung S5K5E8) producing valid frames on the RK3562 Debian build, with full parity to rear camera bring-up rigour: test pattern first, real scene second, register analysis if image is bad.

---

## Context

### Hardware
- Front sensor: Samsung S5K5E8 at i2c 4-0x10, chip ID 0x5E80
- Connected via: `rockchip-csi2-dphy4` (2 lanes) → `rockchip-mipi-csi2` → `rkcif-mipi-lvds2`
- Capture node: `/dev/video11` (multiplanar)
- Subdev node: `/dev/v4l-subdev6`
- Media device: `/dev/media1`

### Driver state
- Driver file: `overlay/drivers/media/i2c/s5k5e8.c` (synced to `src/kernel/`)
- Recent hardening: `s5k5e8_global_regs[]` moved onto stream-start path (not s_power)
- Modes supported: 3264×2448 @ 30fps (link 366MHz), 1920×1080 @ 30fps (link 200MHz)
- Format: `SGRBG10_1X10` (BA10 at capture node), 2 bytes/pixel
- New kernel (April 4) confirmed deployed and running on device

### Rear camera reference
The rear S5K5YB4H was found to have a register-map mismatch: 16 of 54 global_regs silently ignored writes, leaving the analog path uninitialized. That produced a flat grey output (mean ~128.7, <50 unique Y values, exposure had zero effect). The same class of bug may or may not affect the S5K5E8.

---

## Architecture

Three components in `tools/`:

| File | Where runs | Purpose |
|------|-----------|---------|
| `tools/capture_front.c` | device (arm64) | Multiplanar V4L2 capture binary |
| `tools/capture_front.sh` | device | Pipeline setup + capture orchestration |
| `tools/analyze_raw.py` | host | Raw→PNG conversion + frame health report |

### Data flow
```
s5k5e8 sensor (i2c 4-0x10)
  → rockchip-csi2-dphy4  (/dev/v4l-subdev5)
  → rockchip-mipi-csi2   (/dev/v4l-subdev4)
  → stream_cif_mipi_id0  (/dev/video11)
  → capture_front binary
  → front_YYYYMMDD_HHMMSS.raw  (written on device, ~15.3 MB)
  → scp to host
  → analyze_raw.py
  → front_YYYYMMDD_HHMMSS.png + one-line health report
```

---

## Components

### `tools/capture_front.c`

Minimal multiplanar V4L2 flow:
1. Open `/dev/video11`
2. `VIDIOC_S_FMT` — type=`V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE`, pixelformat=BA10 (`SGRBG10`), 3264×2448, 1 plane
3. `VIDIOC_REQBUFS` — count=1, memory=`V4L2_MEMORY_MMAP`
4. `VIDIOC_QUERYBUF` + `mmap()` to get buffer pointer and size
5. `VIDIOC_QBUF` → `VIDIOC_STREAMON`
6. `select()` on the fd with 5-second timeout
7. `VIDIOC_DQBUF` → write buffer contents to output file
8. `VIDIOC_STREAMOFF` → unmap → close

Compiled on host:
```bash
aarch64-linux-gnu-gcc -O2 -o tools/capture_front tools/capture_front.c
```

Deployed and run:
```bash
scp tools/capture_front chaos@192.168.2.109:/tmp/
ssh chaos@192.168.2.109 '/tmp/capture_front /tmp/front_$(date +%Y%m%d_%H%M%S).raw'
```

### `tools/capture_front.sh`

Shell script that runs on the device to:
1. Set format on each subdev in the pipeline via `media-ctl --set-v4l2`
2. Optionally enable/disable test pattern via `v4l2-ctl -d /dev/v4l-subdev6 -c test_pattern=<0|1>`
3. Invoke `capture_front` and timestamp the output file

Usage:
```bash
# With test pattern
bash capture_front.sh --test-pattern

# Real scene
bash capture_front.sh
```

### `tools/analyze_raw.py`

Run on host after scp. For a given `.raw` file:
1. Read as `uint16` little-endian, reshape to 2448×3264
2. Print health report:
   - `min`, `max`, `mean` (expected: ~0–1023 range for good image)
   - `unique_count` (flat grey = <50; healthy image = thousands)
   - Column variance (stripe pattern = ADC stuck at reference level)
3. Save 8-bit grayscale PNG (right-shift by 2, clip to 0–255)

Usage:
```bash
python3 tools/analyze_raw.py front_20260404_120000.raw
# → front_20260404_120000.png
# → min=12 max=987 mean=341.2 unique=18432  [HEALTHY]
#    or
# → min=127 max=132 mean=128.7 unique=28    [GREY - investigate registers]
```

---

## Phases

### Phase 1 — Capture Tooling
Write and cross-compile `capture_front.c`. Write `analyze_raw.py`. Write `capture_front.sh`. Verify tooling compiles without error.

### Phase 2 — Test Pattern
1. Deploy binary to device
2. Run `capture_front.sh --test-pattern`
3. scp raw to host, run `analyze_raw.py`

**Pass:** PNG shows distinct vertical color bars, `unique_count` >> 100, meaningful min/max spread.  
**Fail:** flat grey, mean ~128, `unique_count` < 50 → proceed to Phase 4.

### Phase 3 — Real Scene
Repeat Phase 2 without `--test-pattern`. Same pass criterion.

### Phase 4 — Register Analysis (only if Phase 2 fails)

Same methodology as the rear S5K4H5YB debug:
1. With sensor streaming, use `i2c-get` to read back every address in `s5k5e8_global_regs[]`
2. For each register, compare read-back vs written value
3. Build a table of stuck/silent registers (same format as rear camera findings)
4. Update `s5k5e8_global_regs[]` to skip confirmed-broken entries (set to `{REG_NULL, 0x00}` sentinel or remove)
5. Rebuild kernel, redeploy, retest from Phase 2

---

## Pass/Fail Criteria Summary

| Check | Pass | Fail |
|-------|------|------|
| Test pattern unique_count | > 100 | < 50 |
| Test pattern mean | Not ~128 | ~128 |
| Test pattern PNG | Visible color bars | Uniform grey |
| Real scene unique_count | > 1000 | < 50 |
| Register read-back (if needed) | Written == read-back | Discrepancy found |

---

## Files Modified / Created

- `tools/capture_front.c` — new
- `tools/capture_front.sh` — new
- `tools/analyze_raw.py` — new
- `overlay/drivers/media/i2c/s5k5e8.c` — may be updated if Phase 4 needed
- `src/kernel/drivers/media/i2c/s5k5e8.c` — kept in sync with overlay
