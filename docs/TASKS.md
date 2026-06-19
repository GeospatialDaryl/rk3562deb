# Task Tracker — Samwise Armbian Platform

## Phase 0 — Project and Recovery Foundation

- [x] Repository structure created
- [x] AGENTS.md written
- [x] PROJECT_CONTEXT.md written
- [x] ARCHITECTURE.md written
- [x] DECISIONS.md initialized
- [x] RECOVERY_PLAYBOOK.md written
- [x] HARDWARE_TEST_MATRIX.md initialized
- [x] host-preflight.sh implemented
- [x] capture-samwise-baseline.sh implemented
- [x] flash-image-safely.sh with eMMC protection
- [x] verify-artifact.sh implemented
- [x] compare-baselines.py implemented
- [x] Build profiles created (minimal, hardware-test, tablet-dev)
- [x] CMake toolchain file created
- [x] .gitignore updated
- [ ] Run host-preflight.sh on Conrad — verify pass
- [ ] Run capture-samwise-baseline.sh against known-good system
- [ ] Verify known-good card image checksum
- [ ] Commit baseline data

## Phase 1 — Boot-Chain and Device-Tree Discovery

- [x] Capture baseline from live system (54 files + 231 DT compatible strings)
- [x] Capture raw FDT binary (155,648 bytes, SHA-256: 4f4f90a7...)
- [x] Document boot configuration mechanism (extlinux on SD, direct U-Boot on eMMC)
- [x] Identify actual DTB filename: `rk3562-rk817-tablet-v10.dtb`
- [x] Document kernel image format: uncompressed `Image` on VFAT boot partition
- [x] Identify U-Boot: Firefly `rk356x/firefly-5.10`, FIT image at 8 MiB offset
- [x] Record compatible strings: `rockchip,rk3562-rk817-tablet` / `rockchip,rk3562`
- [x] Write BOOT_CHAIN_DISCOVERY.md (Phase 1 complete)
- [ ] Write KERNEL_PROVENANCE.md (needs kernel source tree analysis)
- [ ] Decision: Armbian board definition strategy (D006 — pending Phase 2)
- [x] Key finding: live system boots from eMMC, not SD card (D006 recorded)

## Phase 2 — Pinned Armbian Build Skeleton

- [ ] Initialize armbian-build as submodule or pinned clone
- [ ] Create initial source lockfiles
- [ ] Test prepare-armbian-worktree.sh
- [ ] Run first Armbian build (generic, not tablet-specific)
- [ ] Verify manifest generation
- [ ] Verify clean-worktree rebuild reproducibility

## Phase 3+ — Deferred

See spec sections 15.3–15.6 for Phase 3–6 deliverables.
