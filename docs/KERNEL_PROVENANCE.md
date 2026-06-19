# Kernel Provenance — Samwise

**Status:** Pending Phase 1 investigation

## Purpose

Document the exact origin, version, configuration, and modifications of the kernel running on the known-good samwise system, and establish the provenance chain for any candidate kernel.

## Known-Good Kernel

```
Version:    6.1.118 #2
Source:     (to be confirmed — likely rockchip-linux/kernel develop-6.1 branch)
Config:     (to be captured via /proc/config.gz)
Build:      (cross-compiled, details pending)
```

## Candidate Kernel Labels

| Label | Meaning |
|-------|---------|
| compat-6.1 | Closest known-good vendor-compatible baseline |
| update-6.1 | Later maintained 6.1-compatible candidate |
| lts-6.6 | Experimental newer LTS bring-up |
| lts-6.12 | Experimental newer LTS bring-up |

## Required Provenance for Each Candidate

```
Kernel:
  repository: <exact upstream or vendor source URL>
  branch: <branch name>
  commit: <full SHA>
  tag: <immutable tag, if any>
  config_hash: <SHA-256 of .config>
  patches: <list of applied patches with rationale>
  modules: <list of key modules built>
  build_host: <hostname>
  compiler: <version string>
  build_date: <ISO-8601>
```

## Vendor Modifications

Key vendor changes in the 6.1.118 kernel that tablet functionality depends on:

- [ ] DSI panel driver (identify exact driver and DTS binding)
- [ ] GSL3673 touch driver (out-of-tree)
- [ ] Seekwave EA6621Q Wi-Fi driver (out-of-tree)
- [ ] RK817 PMIC/battery/charger drivers (vendor modifications)
- [ ] Mali GPU driver (out-of-tree, proprietary)
- [ ] MPP / RGA / VPU media drivers
- [ ] RKNN NPU driver
- [ ] DA223/SC7A20/Mir3DA accelerometer driver
- [ ] Camera sensor drivers (s5k5e8, s5k4h5yb)

Each modification must be documented with:
- Source file path
- Whether it's a patch against upstream or a standalone out-of-tree module
- Whether an upstream equivalent exists
- Impact on newer kernel migration
