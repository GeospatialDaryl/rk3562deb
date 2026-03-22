#!/bin/bash
set -euo pipefail

PHY_MODE="/sys/devices/platform/ff740000.usb2-phy/otg_mode"
DWC3_MODE="/sys/kernel/debug/usb/fe500000.usb/mode"

# Ensure debugfs exists for DWC3 role control.
if ! mountpoint -q /sys/kernel/debug; then
  mount -t debugfs debugfs /sys/kernel/debug || true
fi

for _ in $(seq 1 40); do
  if [ -w "${PHY_MODE}" ] && [ -w "${DWC3_MODE}" ]; then
    break
  fi
  sleep 0.25
done

if [ -w "${PHY_MODE}" ]; then
  echo host > "${PHY_MODE}"
fi

if [ -w "${DWC3_MODE}" ]; then
  echo host > "${DWC3_MODE}"
fi

phy_now="unknown"
dwc3_now="unknown"
[ -r "${PHY_MODE}" ] && phy_now="$(cat "${PHY_MODE}" 2>/dev/null || true)"
[ -r "${DWC3_MODE}" ] && dwc3_now="$(cat "${DWC3_MODE}" 2>/dev/null || true)"
logger -t usb-force-host "applied: phy=${phy_now} dwc3=${dwc3_now}"
