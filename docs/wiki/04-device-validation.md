# 04 — Device Validation & Flashing

## Safety rails (non-negotiable, D002/D004)

- **Never write to `/dev/mmcblk2`** (the tablet's eMMC — it holds the vendor
  Android install; a bad write can brick the device). All project flash helpers
  hard-reject eMMC targets.
- Candidate images boot from **external microSD only** until the boot chain is
  fully documented.
- Keep the previous known-good microSD image (and `~/backups/samwise`) intact:
  rollback = swap cards.

## Flashing

Preferred: the guarded helper.

```bash
~/repos/rk3562deb/scripts/flash-image-safely.sh \
  --image ~/repos/ArmbianBuild/output/images/Armbian-unofficial_<ver>.img \
  --target /dev/sdX
```

Manual (only after triple-checking the target device with `lsblk`):

```bash
sha256sum --check <image>.sha
sudo dd if=<image>.img of=/dev/sdX bs=1M status=progress conv=fsync
```

Serial console is available at 1500000 baud (`ttyS0`) if boot goes dark;
the cmdline also puts early console output there.

## Post-boot validation, NPU-focused

Run on the booted candidate image. Capture output to files — the test matrix
requires recorded evidence, not a thumbs-up.

```bash
# 1. Identity: which kernel/DTB are we actually running?
uname -a                                   # expect 6.1.75-vendor-rk35xx
cat /proc/device-tree/model

# 2. Driver bound and at the right version
sudo cat /sys/kernel/debug/rknpu/version   # expect: RKNPU driver: v0.9.8
dmesg | grep -i rknpu                      # probe, no bind failures

# 3. Power/clock plumbing
ls /sys/class/devfreq/ff300000.npu
cat /sys/class/devfreq/ff300000.npu/{governor,cur_freq,available_frequencies}
grep -r vdd_npu /sys/kernel/debug/regulator/regulator_summary 2>/dev/null || \
  sudo cat /sys/kernel/debug/regulator/regulator_summary | grep -A1 vdd_npu

# 4. Runtime contract (after installing the runtime, see wiki 05)
#    run the known-good RKNN sample            → matrix row 17
#    run the RKLLM small-model demo            → matrix row 18

# 5. Load reporting (open question for rk-tui)
sudo cat /sys/kernel/debug/rknpu/load        # idle, then again under inference
```

Full sweep: the 20-row procedure in `../HARDWARE_TEST_MATRIX.md` (P0 boot/
display/touch/Wi-Fi rows first — an image that loses those is a regression
regardless of NPU state). `scripts/collect-target-test-report.sh --host
frodo@<tablet-ip>` automates capture and comparison against the baseline.

## Recording results

Per the matrix: record date, image manifest reference, actual command output
(capture file path), and pass/fail per row. Compare against
`baseline/current-system/` with `scripts/compare-baselines.py`.

## Provenance capture from the *stock* system

Do this before replacing/retiring any stock install, from a direct SSH session
on the tablet (Conrad cannot resolve `samwise` — see wiki 02 gotchas):

```bash
~/repos/rk3562deb/scripts/capture-samwise-baseline.sh    # from a host with access
```

The 2026-07-04 capture that set the current version contract is documented in
[01 — Hardware & Software Baseline](01-hardware-baseline.md).
