#!/usr/bin/env bash

# Check a runner before the real, destructive-only-inside-QEMU acceptance harness starts.
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C
export PATH=/usr/bin:/usr/sbin
unset BASH_ENV ENV CDPATH GLOBIGNORE

readonly qemu_bin='/usr/bin/qemu-system-x86_64'
readonly qemu_img='/usr/bin/qemu-img'
readonly ovmf_code='/usr/share/OVMF/OVMF_CODE_4M.fd'
readonly ovmf_vars_template='/usr/share/OVMF/OVMF_VARS_4M.fd'

iso_path=''
iso_sha256=''
output_root=''
scenario=''
minimum_free_gib=''
container_kind='none'

usage() {
    printf '%s\n' \
        "Usage: $0 --scenario SCENARIO --iso ABSOLUTE_PATH --iso-sha256 SHA256" \
        '       --output-root ABSOLUTE_PRIVATE_DIRECTORY [--minimum-free-gib GIB]' >&2
}

die() {
    printf 'VM_PREFLIGHT_FAIL: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v -- "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

scenario_requirements() {
    case "${scenario}" in
    minimal-ext4-systemdboot)
        required_memory_kib=$((4 * 1024 * 1024))
        default_free_gib=24
        ;;
    stock-gnome-btrfs-luks2-plymouth-grub | marble-gnome-btrfs-luks2-plymouth-systemdboot)
        required_memory_kib=$((8 * 1024 * 1024))
        default_free_gib=32
        ;;
    *) die 'scenario is outside the release acceptance matrix' ;;
    esac
}

probe_kvm_acceleration() (
    local probe_root probe_log pid status
    probe_root="$(mktemp -d "${TMPDIR:-/tmp}/arch-linux-vm-preflight.XXXXXXXX")" ||
        die 'cannot create the KVM probe directory'
    probe_log="${probe_root}/qemu.log"
    trap 'find "${probe_root}" -xdev -depth -delete 2>/dev/null || true' EXIT
    "${qemu_bin}" -nodefaults -no-user-config -machine 'q35,accel=kvm' -cpu host \
        -display none -S >"${probe_log}" 2>&1 &
    pid=$!
    sleep 1
    if ! kill -0 "${pid}" 2>/dev/null; then
        wait "${pid}" || status=$?
        status="${status:-1}"
        tail -c 4096 -- "${probe_log}" >&2 || true
        die "QEMU KVM acceleration probe exited early: status=${status}"
    fi
    kill -TERM "${pid}" 2>/dev/null || die 'cannot stop the KVM acceleration probe'
    wait "${pid}" || status=$?
    status="${status:-0}"
    [ "${status}" -eq 0 ] || die "QEMU KVM acceleration probe failed: status=${status}"
)

[ "$#" -gt 0 ] || { usage; exit 2; }
while [ "$#" -gt 0 ]; do
    case "$1" in
    --scenario) [ "$#" -ge 2 ] || { usage; exit 2; }; scenario="$2"; shift 2 ;;
    --iso) [ "$#" -ge 2 ] || { usage; exit 2; }; iso_path="$2"; shift 2 ;;
    --iso-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; iso_sha256="$2"; shift 2 ;;
    --output-root) [ "$#" -ge 2 ] || { usage; exit 2; }; output_root="$2"; shift 2 ;;
    --minimum-free-gib) [ "$#" -ge 2 ] || { usage; exit 2; }; minimum_free_gib="$2"; shift 2 ;;
    *) usage; exit 2 ;;
    esac
done

for command_name in awk date df find free id mktemp qemu-img qemu-system-x86_64 sha256sum stat systemd-detect-virt tail uname; do
    require_command "${command_name}"
done
[ "$(uname -s)" = Linux ] || die 'the VM harness requires a Linux runner'
[ "$(id -u)" -ne 0 ] || die 'the VM harness must run as an unprivileged runner user'
scenario_requirements
[[ "${iso_path}" = /* && "${output_root}" = /* ]] || die 'ISO and output paths must be absolute'
[[ "${iso_sha256}" =~ ^[a-f0-9]{64}$ ]] || die 'accepted ISO SHA-256 is malformed'
if [ ! -f "${iso_path}" ] || [ -L "${iso_path}" ]; then
    die 'accepted ISO is unsafe'
fi
[ "$(sha256sum --binary -- "${iso_path}" | awk '{ print $1 }')" = "${iso_sha256}" ] ||
    die 'accepted ISO digest differs'
if [ ! -d "${output_root}" ] || [ -L "${output_root}" ]; then
    die 'output root is unsafe'
fi
[ "$(stat -Lc '%u:%a' -- "${output_root}")" = "$(id -u):700" ] ||
    die 'output root must be owned by the runner and mode 0700'
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    die '/dev/kvm is not accessible to the runner'
fi
for runtime_input in "${qemu_bin}" "${qemu_img}" "${ovmf_code}" "${ovmf_vars_template}"; do
    if [ ! -f "${runtime_input}" ] || [ -L "${runtime_input}" ]; then
        die "required runtime input is unsafe: ${runtime_input}"
    fi
done

if systemd-detect-virt --container >/dev/null 2>&1; then
    container_kind="$(systemd-detect-virt --container)"
fi
available_memory_kib="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
[[ "${available_memory_kib}" =~ ^[1-9][0-9]*$ ]] || die 'available memory is malformed'
[ "${available_memory_kib}" -ge "${required_memory_kib}" ] ||
    die "available memory is below the scenario minimum: ${available_memory_kib}KiB"
if [ -z "${minimum_free_gib}" ]; then
    minimum_free_gib="${default_free_gib}"
fi
[[ "${minimum_free_gib}" =~ ^[1-9][0-9]*$ ]] || die 'minimum free storage must be a positive integer GiB'
available_storage_bytes="$(df -PB1 -- "${output_root}" | awk 'NR == 2 { print $4 }')"
[[ "${available_storage_bytes}" =~ ^[1-9][0-9]*$ ]] || die 'available storage is malformed'
required_storage_bytes=$((minimum_free_gib * 1024 * 1024 * 1024))
[ "${available_storage_bytes}" -ge "${required_storage_bytes}" ] ||
    die "available storage is below the scenario minimum: ${available_storage_bytes} bytes"
runner_epoch="$(date -u +%s)"
if ! [[ "${runner_epoch}" =~ ^[1-9][0-9]*$ ]] || [ "${runner_epoch}" -lt 1700000000 ]; then
    die 'runner UTC clock is implausible'
fi

probe_kvm_acceleration
printf 'VM_PREFLIGHT_RESULT schema=1 scenario=%s kvm=passed container=%s ram_kib=%s storage_bytes=%s clock=passed\n' \
    "${scenario}" "${container_kind}" "${available_memory_kib}" "${available_storage_bytes}"
