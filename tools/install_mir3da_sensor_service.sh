#!/usr/bin/env bash
set -euo pipefail

# Install the RK3562/RK817 tablet MiraMEMS Mir3DA/DA223 accelerometer
# compatibility service into a Debian rootfs tree.
#
# Usage:
#   sudo ./tools/install_mir3da_sensor_service.sh [ROOTFS]
#
# Defaults to ./out/rootfs when run from the repository root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOTFS_MNT="${1:-${ROOTFS_MNT:-${REPO_ROOT}/out/rootfs}}"

if [[ ! -d "${ROOTFS_MNT}" ]]; then
    echo "[-] Rootfs path does not exist: ${ROOTFS_MNT}" >&2
    exit 1
fi

if [[ ! -d "${ROOTFS_MNT}/etc" || ! -d "${ROOTFS_MNT}/usr" ]]; then
    echo "[-] ${ROOTFS_MNT} does not look like a Debian rootfs." >&2
    exit 1
fi

echo "[*] Installing Mir3DA accelerometer monitor into ${ROOTFS_MNT}"

install -d -m 0755 "${ROOTFS_MNT}/usr/local/bin"
cat > "${ROOTFS_MNT}/usr/local/bin/mir3da-monitor" <<'MONITOR_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Runtime monitor for the MiraMEMS Mir3DA / DA223 accelerometer used on
# RK3562 RK817 tablet boards.
#
# The vendor Rockchip/Android-style driver registers evdev nodes, but on this
# Debian image live motion data is exposed reliably through a private sysfs
# attribute named axis_data on the virtual "mir3da" input device.

OUTDIR="${MIR3DA_OUTDIR:-/run/mir3da}"
INTERVAL="${MIR3DA_INTERVAL:-0.25}"
LOG_CHANGES="${MIR3DA_LOG_CHANGES:-1}"

find_mir3da_base() {
    local name base

    for name in /sys/class/input/input*/name; do
        [[ -r "${name}" ]] || continue
        if [[ "$(cat "${name}" 2>/dev/null)" == "mir3da" ]]; then
            base="$(readlink -f "$(dirname "${name}")")"
            if [[ -r "${base}/axis_data" ]]; then
                printf '%s\n' "${base}"
                return 0
            fi
        fi
    done

    # Fallback for kernels that expose the virtual input node without a useful
    # /sys/class/input symlink.
    for base in /sys/devices/virtual/input/input*; do
        [[ -r "${base}/name" && -r "${base}/axis_data" ]] || continue
        if [[ "$(cat "${base}/name" 2>/dev/null)" == "mir3da" ]]; then
            printf '%s\n' "${base}"
            return 0
        fi
    done

    return 1
}

BASE="${MIR3DA_BASE:-}"
if [[ -z "${BASE}" ]]; then
    if ! BASE="$(find_mir3da_base)"; then
        echo "ERROR: could not find a readable mir3da axis_data sysfs node" >&2
        exit 1
    fi
fi

if [[ ! -r "${BASE}/axis_data" ]]; then
    echo "ERROR: cannot read ${BASE}/axis_data" >&2
    exit 1
fi

mkdir -p "${OUTDIR}"

# Keep the sensor enabled when the vendor driver exposes an enable switch.
if [[ -e "${BASE}/enable" && -w "${BASE}/enable" ]]; then
    echo 1 > "${BASE}/enable" || true
fi

dominant_axis() {
    local x="$1" y="$2" z="$3"
    local ax ay az axis val sign

    (( ax = x < 0 ? -x : x ))
    (( ay = y < 0 ? -y : y ))
    (( az = z < 0 ? -z : z ))

    axis="X"; val="${x}"
    if (( ay >= ax && ay >= az )); then
        axis="Y"; val="${y}"
    elif (( az >= ax && az >= ay )); then
        axis="Z"; val="${z}"
    fi

    if (( val < 0 )); then
        sign="-"
    else
        sign="+"
    fi

    printf '%s%s' "${axis}" "${sign}"
}

prev_dom=""

echo "mir3da-monitor: using ${BASE}/axis_data"

while true; do
    raw="$(cat "${BASE}/axis_data" 2>/dev/null || true)"

    if [[ "${raw}" =~ x=\ *(-?[0-9]+)\;y=\ *(-?[0-9]+)\;z=\ *(-?[0-9]+) ]]; then
        x="${BASH_REMATCH[1]}"
        y="${BASH_REMATCH[2]}"
        z="${BASH_REMATCH[3]}"
        ts="$(date -u '+%Y-%m-%dT%H:%M:%S.%NZ')"
        dom="$(dominant_axis "${x}" "${y}" "${z}")"

        tmp_latest="${OUTDIR}/latest.tmp"
        tmp_env="${OUTDIR}/latest.env.tmp"

        {
            printf 'timestamp=%s\n' "${ts}"
            printf 'x=%s\n' "${x}"
            printf 'y=%s\n' "${y}"
            printf 'z=%s\n' "${z}"
            printf 'dominant_axis=%s\n' "${dom}"
            printf 'base=%s\n' "${BASE}"
            printf 'raw=%s\n' "${raw}"
        } > "${tmp_latest}"

        {
            printf 'MIR3DA_TIMESTAMP=%q\n' "${ts}"
            printf 'MIR3DA_X=%q\n' "${x}"
            printf 'MIR3DA_Y=%q\n' "${y}"
            printf 'MIR3DA_Z=%q\n' "${z}"
            printf 'MIR3DA_DOMINANT_AXIS=%q\n' "${dom}"
            printf 'MIR3DA_BASE=%q\n' "${BASE}"
            printf 'MIR3DA_RAW=%q\n' "${raw}"
        } > "${tmp_env}"

        mv "${tmp_latest}" "${OUTDIR}/latest"
        mv "${tmp_env}" "${OUTDIR}/latest.env"

        if [[ "${LOG_CHANGES}" == "1" && "${dom}" != "${prev_dom}" ]]; then
            echo "dominant_axis=${dom} x=${x} y=${y} z=${z} raw='${raw}'"
            prev_dom="${dom}"
        fi
    else
        echo "WARN: could not parse axis_data from ${BASE}: '${raw}'" >&2
    fi

    sleep "${INTERVAL}"
done
MONITOR_EOF
chmod 0755 "${ROOTFS_MNT}/usr/local/bin/mir3da-monitor"

install -d -m 0755 "${ROOTFS_MNT}/etc/default"
cat > "${ROOTFS_MNT}/etc/default/mir3da-monitor" <<'DEFAULT_EOF'
# MiraMEMS Mir3DA / DA223 accelerometer monitor defaults.
# Override MIR3DA_BASE only if auto-discovery fails.
MIR3DA_INTERVAL=0.25
MIR3DA_LOG_CHANGES=1
# MIR3DA_BASE=/sys/devices/virtual/input/input2
DEFAULT_EOF
chmod 0644 "${ROOTFS_MNT}/etc/default/mir3da-monitor"

install -d -m 0755 "${ROOTFS_MNT}/etc/systemd/system"
cat > "${ROOTFS_MNT}/etc/systemd/system/mir3da-monitor.service" <<'UNIT_EOF'
[Unit]
Description=MiraMEMS Mir3DA / DA223 accelerometer monitor
Documentation=file:/usr/local/bin/mir3da-monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mir3da-monitor
Restart=always
RestartSec=2

# The vendor sysfs interface may require writing the enable node.
User=root
Group=root

EnvironmentFile=-/etc/default/mir3da-monitor
RuntimeDirectory=mir3da
RuntimeDirectoryMode=0755

NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=full

[Install]
WantedBy=multi-user.target
UNIT_EOF
chmod 0644 "${ROOTFS_MNT}/etc/systemd/system/mir3da-monitor.service"

install -d -m 0755 "${ROOTFS_MNT}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/mir3da-monitor.service \
    "${ROOTFS_MNT}/etc/systemd/system/multi-user.target.wants/mir3da-monitor.service"

echo "[+] Installed Mir3DA accelerometer monitor service."
echo "    Runtime output on tablet: /run/mir3da/latest"
