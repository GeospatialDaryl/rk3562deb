# Changelog — Samwise Armbian Platform

## [Unreleased]

### Added
- Phase 0 project scaffold: directory structure, documentation, scripts
- AGENTS.md with project identity and safety rules
- Host preflight script (scripts/host-preflight.sh)
- Baseline capture script (scripts/capture-samwise-baseline.sh)
- Safe flash script with eMMC protection (scripts/flash-image-safely.sh)
- Armbian worktree preparation (scripts/prepare-armbian-worktree.sh)
- Image build wrapper (scripts/build-image.sh)
- Kernel-only build wrapper (scripts/build-kernel-only.sh)
- Artifact verification (scripts/verify-artifact.sh)
- SDK export (scripts/export-sdk.sh)
- Target test report collection (scripts/collect-target-test-report.sh)
- Baseline comparison tool (scripts/compare-baselines.py)
- Build profiles: samwise-minimal, samwise-hardware-test, samwise-tablet-dev
- CMake cross-compilation toolchain file
- Hardware test matrix (docs/HARDWARE_TEST_MATRIX.md)
- Recovery playbook (docs/RECOVERY_PLAYBOOK.md)
- Architecture and decisions documentation
