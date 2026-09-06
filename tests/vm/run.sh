#!/usr/bin/env bash

# Deliberately narrow real-VM paths for accepted Minimal, Stock GNOME, and Marble contracts.
set -Eeuo pipefail
set +x
umask 077
export LC_ALL=C
export PATH=/usr/bin:/usr/sbin
unset BASH_ENV ENV CDPATH GLOBIGNORE

readonly qemu_bin='/usr/bin/qemu-system-x86_64'
readonly qemu_img='/usr/bin/qemu-img'
readonly python_bin='/usr/bin/python3'
readonly ovmf_code='/usr/share/OVMF/OVMF_CODE_4M.fd'
readonly ovmf_vars_template='/usr/share/OVMF/OVMF_VARS_4M.fd'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd -- "${script_dir}/../.." && pwd -P)"
readonly script_dir repository_root

iso_path=''
iso_sha256=''
output_parent=''
input_mode=''
release_assets=''
release_version=''
snapshot_sha256=''
build_metadata_sha256=''
unsigned_manifest_sha256=''
bootstrap_url=''
installer_url=''
public_key_url=''
pages_url=''
bootstrap_sha256=''
snapshot_verification='UNVERIFIED'
scenario_id=''
run_prefix=''
marker_prefix=''
guest_hostname=''
guest_memory_mib=''
target_size_bytes=''
target_size=''
run_id=''
run_root=''
runtime_dir=''
evidence=''
assertions_file=''
source_commit=''
source_tree=''
harness_commit=''
harness_tree=''
installer_sha256=''
harness_sha256=''
target_serial=''
target_model=''
qemu_pid=''
qemu_start_time=''
qga_socket=''
qga_socket_identity=''
hmp_socket=''
qmp_socket=''
qmp_socket_identity=''
serial_socket=''
serial_bridge_pid=''
serial_bridge_input_fd=''
current_phase='preflight'
last_boot_id=''
runtime_password=''
repository_primary_fingerprint='-'
repository_signing_fingerprint='-'
repository_public_key_sha256='-'
repository_package_set_sha256='-'
repository_manifest_sha256='-'
repository_manifest_signature_sha256='-'
repository_database_sha256='-'
repository_database_signature_sha256='-'
repository_files_sha256='-'
repository_files_signature_sha256='-'
release_sha256sums_sha256='-'
repository_server_port=''
repository_server_pid=''
repository_server_start_time=''
repository_server_executable=''
repository_server_root=''
repository_ca_file=''
repository_server_certificate=''
repository_server_private_key=''
repository_ca_private_key=''
repository_ready_file=''
evidence_size_bytes=0
run_storage_finalized='false'
declare -a qemu_pids=()
declare -A repository_package_hashes=()

usage() {
    printf '%s\n' \
        "Usage: $0 SCENARIO (Minimal, Stock ext4/Btrfs with systemd-boot/GRUB, or Marble)" \
        '       --iso ABSOLUTE_PATH --iso-sha256 SHA256' \
        '       --output-root ABSOLUTE_PRIVATE_DIRECTORY' \
        '       --mode staged --release-assets ABSOLUTE_DIRECTORY --release-version VERSION' \
        '       --snapshot-sha256 SHA256 --build-metadata-sha256 SHA256 --unsigned-manifest-sha256 SHA256' \
        '   or: --mode public --release-version VERSION --snapshot-sha256 SHA256' \
        '       --bootstrap-url URL --installer-url URL --public-key-url URL --pages-url URL' >&2
}

die() {
    printf 'QEMU_HOST_FAIL: %s\n' "$*" >&2
    return 1
}

require_command() {
    command -v -- "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

process_start_time() {
    local pid="$1" value
    [ -r "/proc/${pid}/stat" ] || return 1
    value="$(sed 's/^.*) //' "/proc/${pid}/stat" | awk '{ print $20 }')"
    [[ "${value}" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "${value}"
}

process_is_exact_qemu() {
    local pid="$1" start_time="$2"
    [ "$(process_start_time "${pid}" 2>/dev/null || true)" = "${start_time}" ] &&
        [ "$(readlink -f -- "/proc/${pid}/exe" 2>/dev/null || true)" = "${qemu_bin}" ]
}

process_is_exact_repository_server() {
    local pid="$1" start_time="$2"
    [ "$(process_start_time "${pid}" 2>/dev/null || true)" = "${start_time}" ] &&
        [ "$(readlink -f -- "/proc/${pid}/exe" 2>/dev/null || true)" = "${repository_server_executable}" ] &&
        tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | grep -Fxq -- "${script_dir}/https-server.py"
}

find_run_qemu_processes() {
    local marker="$1"
    python3 - "${marker}" "${qemu_bin}" <<'PY'
import os
import pathlib
import sys

marker, executable = sys.argv[1:]
matches = []
for entry in pathlib.Path('/proc').iterdir():
    if not entry.name.isdigit():
        continue
    try:
        if os.path.realpath(entry / 'exe') != executable:
            continue
        argv = (entry / 'cmdline').read_bytes().split(b'\0')
    except OSError:
        continue
    if any(marker.encode() in value for value in argv):
        matches.append(entry.name)
print(' '.join(matches))
PY
}

stop_repository_server() {
    local deadline
    if [[ "${repository_server_pid}" =~ ^[1-9][0-9]*$ ]] &&
        process_is_exact_repository_server "${repository_server_pid}" "${repository_server_start_time}"; then
        kill -TERM -- "${repository_server_pid}" 2>/dev/null || true
        deadline=$((SECONDS + 15))
        while process_is_exact_repository_server "${repository_server_pid}" "${repository_server_start_time}" &&
            [ "${SECONDS}" -lt "${deadline}" ]; do
            sleep 1
        done
        if process_is_exact_repository_server "${repository_server_pid}" "${repository_server_start_time}"; then
            kill -KILL -- "${repository_server_pid}" 2>/dev/null || true
        fi
        wait "${repository_server_pid}" 2>/dev/null || true
    fi
    repository_server_pid=''
    repository_server_start_time=''
    if [ -n "${repository_server_private_key}" ]; then
        rm -f -- "${repository_server_private_key}"
    fi
    if [ -n "${repository_ca_private_key}" ]; then
        rm -f -- "${repository_ca_private_key}"
    fi
}

remove_exact_run_tree() {
    local target="$1"
    [ -n "${run_root}" ] && [ "${target#"${run_root}/"}" != "${target}" ] || {
        die 'refusing cleanup outside the exact run root'
        return 1
    }
    if [ -e "${target}" ] || [ -L "${target}" ]; then
        [ -d "${target}" ] && [ ! -L "${target}" ] || {
            die "run-owned cleanup target is not a real directory: ${target}"
            return 1
        }
        find "${target}" -xdev -depth -delete || return 1
        [ ! -e "${target}" ] && [ ! -L "${target}" ] || {
            die "run-owned directory cleanup did not complete: ${target}"
            return 1
        }
    fi
}

remove_secret_bearing_evidence() {
    local candidate
    [ -n "${runtime_password:-}" ] || return 0
    # The qcow2, OVMF state, payload ISO and extracted repository are never retained and have
    # already been removed. Bound this scan to compact text/JSON metadata; never stream a VM disk,
    # firmware image, socket or other large binary through grep during cleanup.
    while IFS= read -r -d '' candidate; do
        rm -f -- "${candidate}" || return 1
    done < <(find "${evidence}" -maxdepth 1 -type f ! -name '*.ppm' -size +16777216c -print0)
    while IFS= read -r -d '' candidate; do
        if grep -aFq -- "${runtime_password}" "${candidate}" 2>/dev/null; then
            rm -f -- "${candidate}" || return 1
        fi
    done < <(find "${run_root}" -xdev -maxdepth 2 -type f ! -name '*.ppm' \
        -size -16777217c -print0)
    while IFS= read -r -d '' candidate; do
        if grep -aFq -- "${runtime_password}" "${candidate}" 2>/dev/null; then
            die 'runtime credential could not be removed from compact run evidence'
            return 1
        fi
    done < <(find "${run_root}" -xdev -maxdepth 2 -type f ! -name '*.ppm' \
        -size -16777217c -print0)
}

compact_run_evidence() {
    local candidate basename summary
    [ -d "${evidence}" ] && [ ! -L "${evidence}" ] || return 0
    remove_secret_bearing_evidence || return 1
    summary="${run_root}/scenario.log"
    : >"${summary}" || return 1
    while IFS= read -r -d '' candidate; do
        case "${candidate}" in
        *.ppm | *.request.json | *.start.json | *.status.json) continue ;;
        esac
        grep -aEh '^[[:space:]]*([A-Z]+_QEMU_(READY|INSTALLER_EXIT|INSTALL_COMPLETE|NEIGHBOR_PRESERVED|GUEST_PASS|GUEST_FAIL)|QEMU_HOST_FAIL|QEMU_DIAGNOSTIC_WARNING:|SCREENSHOT_WARNING:|exit_status=|qemu-img|signed repository checks passed|release asset checks passed)' \
            "${candidate}" 2>/dev/null || true
    done < <(find "${evidence}" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z) |
        awk 'NR <= 2000 { print substr($0, 1, 4096) }' >>"${summary}" || return 1
    gzip -n -9 -- "${summary}" || return 1
    mv -- "${summary}.gz" "${evidence}/scenario.log.gz" || return 1

    while IFS= read -r -d '' candidate; do
        basename="${candidate##*/}"
        case "${basename}" in
        *.ppm | scenario.log.gz | final-qemu-img-check.txt | no-qemu-process.txt | \
            repository-manifest.json | repository-manifest.json.sig | repository-objects.tsv | \
            firstboot-qemu.identity | postreboot-qemu.identity | preseal-harness-check.txt) ;;
        *) rm -f -- "${candidate}" || return 1 ;;
        esac
    done < <(find "${evidence}" -maxdepth 1 -type f -print0)
}

remove_heavy_run_inputs() {
    [ -n "${run_root}" ] || return 0
    rm -f -- \
        "${run_root}/target.qcow2" "${run_root}/target.qcow2.sha256" \
        "${run_root}/OVMF_VARS.fd" "${run_root}/payload.iso" \
        "${run_root}/repository-ca.crt" "${run_root}/repository-server.crt" \
        "${run_root}/repository-ca.srl" \
        "${run_root}/repository.contract" "${run_root}/public.contract" || return 1
    remove_exact_run_tree "${run_root}/payload" || return 1
    remove_exact_run_tree "${run_root}/repository" || return 1
}

enforce_evidence_budget() {
    [ -d "${output_parent}" ] && [ ! -L "${output_parent}" ] || {
        die 'evidence root disappeared during finalization'
        return 1
    }
    evidence_size_bytes="$(du -sb -- "${output_parent}" | awk '{ print $1 }')"
    [[ "${evidence_size_bytes}" =~ ^[0-9]+$ ]] || { die 'evidence size is malformed'; return 1; }
    [ "${evidence_size_bytes}" -le 524288000 ] || {
        die 'retained acceptance evidence exceeds 500 MiB'
        return 1
    }
    printf '%s\n' "${evidence_size_bytes}" >"${run_root}/evidence-size.txt" || return 1
    evidence_size_bytes="$(du -sb -- "${output_parent}" | awk '{ print $1 }')"
    [ "${evidence_size_bytes}" -le 524288000 ] || {
        die 'retained acceptance evidence exceeds 500 MiB'
        return 1
    }
    printf '%s\n' "${evidence_size_bytes}" >"${run_root}/evidence-size.txt" || return 1
}

finalize_run_storage() {
    remove_heavy_run_inputs || return 1
    compact_run_evidence || return 1
    enforce_evidence_budget || return 1
    run_storage_finalized='true'
}

bind_vm_source_identities() {
    harness_commit="$(git -C "${repository_root}" rev-parse HEAD)"
    harness_tree="$(git -C "${repository_root}" rev-parse 'HEAD^{tree}')"
    source_commit="${harness_commit}"
    source_tree="${harness_tree}"
    if [ "${input_mode}" = public ]; then
        # Public acceptance tests immutable release bytes, even after a test-only fix.
        [ "$(git -C "${repository_root}" cat-file -t "refs/tags/${release_version}")" = tag ] ||
            die 'public acceptance requires an annotated release tag' || return 1
        source_commit="$(git -C "${repository_root}" rev-parse "refs/tags/${release_version}^{commit}")"
        source_tree="$(git -C "${repository_root}" rev-parse "refs/tags/${release_version}^{tree}")"
        git -C "${repository_root}" merge-base --is-ancestor "${source_commit}" "${harness_commit}" ||
            die 'released source is not an ancestor of the test checkout' || return 1
        git -C "${repository_root}" diff --quiet "${source_commit}" "${harness_commit}" -- \
            install.sh arch-linux-installer.sh packages repository maintenance ||
            die 'public test checkout changes release product inputs' || return 1
    fi
}

verify_frozen_source_unchanged() {
    [ "$(git -C "${repository_root}" status --porcelain=v1 --untracked-files=all)" = '' ] ||
        die 'source drifted during the VM run'
    [ "$(git -C "${repository_root}" rev-parse HEAD)" = "${harness_commit}" ] ||
        die 'source commit drifted during the VM run'
    [ "$(git -C "${repository_root}" rev-parse 'HEAD^{tree}')" = "${harness_tree}" ] ||
        die 'source tree drifted during the VM run'
    if [ "${input_mode}" = public ]; then
        [ "$(git -C "${repository_root}" rev-parse "refs/tags/${release_version}^{commit}")" = \
            "${source_commit}" ] || die 'release tag drifted during the VM run'
    fi
    [ "$(sha256sum --binary -- "${repository_root}/arch-linux-installer.sh" | awk '{ print $1 }')" = \
        "${installer_sha256}" ] || die 'installer bytes drifted during the VM run'
    [ "$(stat -Lc '%u:%a:%h' -- "${run_root}/harness.sha256")" = "$(id -u):600:1" ] ||
        die 'harness manifest metadata drifted during the VM run'
    [ "$(sha256sum --binary -- "${run_root}/harness.sha256" | awk '{ print $1 }')" = \
        "${harness_sha256}" ] || die 'harness manifest drifted during the VM run'
    (cd -- "${repository_root}" && sha256sum --strict --check -- "${run_root}/harness.sha256") \
        >"${evidence}/preseal-harness-check.txt" || die 'harness bytes drifted during the VM run'
}

cleanup() {
    local status=$? deadline image_status=0 remaining_qemu=''
    trap - EXIT INT TERM
    set +e
    stop_repository_server
    if [[ "${serial_bridge_input_fd}" =~ ^[0-9]+$ ]]; then
        exec {serial_bridge_input_fd}>&-
    fi
    serial_bridge_input_fd=''
    if [[ "${serial_bridge_pid}" =~ ^[1-9][0-9]*$ ]] && kill -0 "${serial_bridge_pid}" 2>/dev/null; then
        kill -TERM -- "${serial_bridge_pid}" 2>/dev/null
        wait "${serial_bridge_pid}" 2>/dev/null
    fi
    serial_bridge_pid=''
    if [ -n "${qemu_pid}" ] && [ -n "${qemu_start_time}" ] &&
        process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}"; then
        kill -TERM -- "${qemu_pid}" 2>/dev/null
        deadline=$((SECONDS + 15))
        while process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" && [ "${SECONDS}" -lt "${deadline}" ]; do
            sleep 1
        done
        if process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}"; then
            kill -KILL -- "${qemu_pid}" 2>/dev/null
        fi
        wait "${qemu_pid}" 2>/dev/null
    fi
    if [ "${status}" -ne 0 ] && [ -n "${run_root}" ] && [ -d "${run_root}" ] &&
        [ -f "${run_root}/target.qcow2" ] && [ -d "${evidence}" ]; then
        "${qemu_img}" check -- "${run_root}/target.qcow2" \
            >"${evidence}/final-qemu-img-check.txt" 2>&1
        image_status=$?
        printf 'exit_status=%s\n' "${image_status}" >>"${evidence}/final-qemu-img-check.txt"
    fi
    if [ -n "${run_id}" ] && [ -d "${evidence}" ]; then
        remaining_qemu="$(find_run_qemu_processes "${run_id}")"
        if [ -n "${remaining_qemu}" ]; then
            status=1
            current_phase='qemu-cleanup'
        else
            printf 'no matching QEMU process remains for %s\n' "${run_id}" \
                >"${evidence}/no-qemu-process.txt"
        fi
    fi
    if [ "${status}" -ne 0 ] && [ -n "${run_root}" ] && [ -d "${run_root}" ]; then
        printf 'status=FAIL\nexit_status=%s\nphase=%s\nrun_id=%s\n' \
            "${status}" "${current_phase}" "${run_id:-unassigned}" >"${run_root}/FAILURE.txt"
        printf 'FAIL run_id=%s phase=%s exit_status=%s\n' \
            "${run_id:-unassigned}" "${current_phase}" "${status}" >&2
    fi
    if [ -n "${run_root}" ] && [ -d "${run_root}" ] && [ "${run_storage_finalized}" != true ]; then
        if ! finalize_run_storage; then
            status=1
            current_phase='evidence-finalization'
            printf 'status=FAIL\nexit_status=1\nphase=evidence-finalization\nrun_id=%s\n' \
                "${run_id:-unassigned}" >"${run_root}/FAILURE.txt"
        fi
    fi
    if [ "${status}" -ne 0 ] && [ -n "${run_root}" ] && [ -d "${run_root}" ]; then
        if ! build_result FAIL "${status}" "${current_phase}"; then
            status=1
        elif ! enforce_evidence_budget || ! build_result FAIL "${status}" "${current_phase}"; then
            status=1
        fi
    fi
    runtime_password=''
    unset runtime_password
    if [ -n "${runtime_dir}" ] && [ -d "${runtime_dir}" ]; then
        rm -f -- "${runtime_dir}/qga.sock" "${runtime_dir}/hmp.sock" \
            "${runtime_dir}/qmp.sock" \
            "${runtime_dir}/serial.sock" "${runtime_dir}/repository.port" \
            "${runtime_dir}/repository-ca.key" "${runtime_dir}/repository-server.key" \
            "${runtime_dir}/repository-server.csr" "${runtime_dir}/repository-server.ext"
        rmdir -- "${runtime_dir}" 2>/dev/null || true
    fi
    exit "${status}"
}
trap cleanup EXIT INT TERM

record_assertion() {
    local id="$1" detail="$2"
    [[ "${id}" =~ ^[a-z0-9-]+$ ]] || die 'assertion id is malformed'
    [[ "${detail}" != *$'\t'* && "${detail}" != *$'\n'* ]] || die 'assertion detail is malformed'
    printf '%s\tPASS\t%s\n' "${id}" "${detail}" >>"${assertions_file}"
}

wait_for_socket() {
    local path="$1" timeout="$2"
    local deadline=$((SECONDS + timeout))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        [ -S "${path}" ] && return 0
        if [ -n "${qemu_pid}" ] && ! process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}"; then
            return 1
        fi
        sleep 1
    done
    return 1
}

wait_for_marker() {
    local file="$1" marker="$2" timeout="$3"
    local deadline=$((SECONDS + timeout))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ -f "${file}" ] && grep -aFq -- "${marker}" "${file}"; then
            return 0
        fi
        if [ -n "${qemu_pid}" ] && ! process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}"; then
            return 1
        fi
        if [[ "${serial_bridge_pid}" =~ ^[1-9][0-9]*$ ]] &&
            ! kill -0 "${serial_bridge_pid}" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

wait_for_install_outcome() {
    local file="$1" success_marker="$2" failure_marker="$3" timeout="$4"
    local deadline=$((SECONDS + timeout))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ -f "${file}" ] && grep -aFq -- "${success_marker}" "${file}"; then
            return 0
        fi
        if [ -f "${file}" ] && grep -aFq -- "${failure_marker}" "${file}"; then
            return 2
        fi
        if [ -n "${qemu_pid}" ] && ! process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}"; then
            return 1
        fi
        if [[ "${serial_bridge_pid}" =~ ^[1-9][0-9]*$ ]] &&
            ! kill -0 "${serial_bridge_pid}" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

hmp_request() {
    local operation="$1" value="$2"
    python3 - "${hmp_socket}" "${qemu_pid}" "${operation}" "${value}" <<'PY'
import os
import socket
import struct
import sys
import time

path, expected_pid_text, operation, value = sys.argv[1:]
expected_pid = int(expected_pid_text)

def frame(connection):
    data = bytearray()
    deadline = time.monotonic() + 30
    while not data.endswith(b'(qemu) '):
        if time.monotonic() >= deadline:
            raise SystemExit('HMP prompt timeout')
        connection.settimeout(min(1.0, deadline - time.monotonic()))
        try:
            chunk = connection.recv(65536)
        except TimeoutError:
            continue
        if not chunk:
            raise SystemExit('HMP disconnected')
        data.extend(chunk)
        if len(data) > 1048576:
            raise SystemExit('HMP response too large')
    lowered = bytes(data).lower()
    if any(x in lowered for x in (b'unknown command', b'invalid parameter', b'command not found')):
        raise SystemExit('HMP reported an error')

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(30)
    connection.connect(path)
    peer_pid, peer_uid, _ = struct.unpack(
        '3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i'))
    )
    if peer_pid != expected_pid or peer_uid != os.getuid():
        raise SystemExit('HMP peer identity differs')
    frame(connection)
    if operation == 'type':
        mapping = {' ': 'spc', '/': 'slash', '-': 'minus', ';': 'semicolon', '=': 'equal', '.': 'dot'}
        keys = []
        for char in value:
            if 'a' <= char <= 'z' or '0' <= char <= '9':
                keys.append(char)
            elif 'A' <= char <= 'Z':
                keys.append('shift-' + char.lower())
            elif char in mapping:
                keys.append(mapping[char])
            else:
                raise SystemExit(f'unsupported bootstrap character: {char!r}')
        keys.append('ret')
        for key in keys:
            connection.sendall(f'sendkey {key} 50\n'.encode('ascii'))
            frame(connection)
            time.sleep(0.08)
    elif operation == 'key':
        if value != 'ret':
            raise SystemExit('unsupported HMP key')
        connection.sendall(f'sendkey {value} 50\n'.encode('ascii'))
        frame(connection)
    else:
        raise SystemExit('unsupported HMP operation')
PY
}

hmp_type_password() {
    [[ "${runtime_password}" =~ ^[a-f0-9]{48}$ ]] || die 'runtime password is malformed'
    python3 /dev/fd/3 "${hmp_socket}" "${qemu_pid}" 3<<'PY' <<<"${runtime_password}"
import os
import socket
import struct
import sys
import time

path, expected_pid_text = sys.argv[1:]
expected_pid = int(expected_pid_text)
secret = sys.stdin.buffer.readline(64).rstrip(b'\n')
if len(secret) != 48 or any(value not in b'0123456789abcdef' for value in secret):
    raise SystemExit('credential input is malformed')

def frame(connection):
    data = bytearray()
    deadline = time.monotonic() + 30
    while not data.endswith(b'(qemu) '):
        if time.monotonic() >= deadline:
            raise SystemExit('HMP prompt timeout')
        connection.settimeout(min(1.0, deadline - time.monotonic()))
        try:
            chunk = connection.recv(65536)
        except TimeoutError:
            continue
        if not chunk:
            raise SystemExit('HMP disconnected')
        data.extend(chunk)
        if len(data) > 1048576:
            raise SystemExit('HMP response too large')
    lowered = bytes(data).lower()
    if any(value in lowered for value in (b'unknown command', b'invalid parameter', b'command not found')):
        raise SystemExit('HMP reported an error')

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(30)
    connection.connect(path)
    peer_pid, peer_uid, _ = struct.unpack(
        '3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i'))
    )
    if peer_pid != expected_pid or peer_uid != os.getuid():
        raise SystemExit('HMP peer identity differs')
    frame(connection)
    for character in secret.decode('ascii'):
        connection.sendall(f'sendkey {character} 50\n'.encode('ascii'))
        frame(connection)
        time.sleep(0.08)
    connection.sendall(b'sendkey ret 50\n')
    frame(connection)
    secret = b''
PY
}

is_btrfs_scenario() {
    case "${scenario_id}" in
    stock-gnome-btrfs-systemdboot | stock-gnome-btrfs-grub | \
        stock-gnome-btrfs-luks2-plymouth-systemdboot | stock-gnome-btrfs-luks2-plymouth-grub | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm) return 0 ;;
    *) return 1 ;;
    esac
}

is_luks_scenario() {
    case "${scenario_id}" in
    stock-gnome-btrfs-luks2-plymouth-systemdboot | stock-gnome-btrfs-luks2-plymouth-grub | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm) return 0 ;;
    *) return 1 ;;
    esac
}

is_marble_scenario() {
    [[ "${scenario_id}" = marble-gnome-* ]]
}

is_grub_scenario() {
    case "${scenario_id}" in
    stock-gnome-btrfs-grub | stock-gnome-btrfs-luks2-plymouth-grub) return 0 ;;
    *) return 1 ;;
    esac
}

is_encrypted_grub_scenario() {
    [ "${scenario_id}" = stock-gnome-btrfs-luks2-plymouth-grub ]
}

capture_screen() {
    local name="$1"
    if ! "${python_bin}" -I "${script_dir}/frame-evidence.py" capture \
        --run-root "${run_root}" --qmp-socket "${qmp_socket}" \
        --qemu-pid "${qemu_pid}" --qemu-start "${qemu_start_time}" --name "${name}" \
        >"${evidence}/${name}.capture.log" 2>&1; then
        printf 'SCREENSHOT_WARNING: optional capture unavailable: %s\n' "${name}" >&2
    fi
    return 0
}

capture_and_unlock_luks_prompt() {
    local phase="$1" retain_frame="${2:-true}" framebuffer='not-retained'
    is_luks_scenario || die 'LUKS prompt handling is limited to the encrypted scenario'
    sleep 15
    if [ "${retain_frame}" = true ]; then
        capture_screen "${phase}-plymouth-luks"
        [ ! -s "${evidence}/${phase}-plymouth-luks.ppm" ] || framebuffer="${phase}-plymouth-luks.ppm"
    elif [ "${retain_frame}" != false ]; then
        die 'LUKS screenshot retention selector is invalid'
    fi
    hmp_type_password
    printf 'phase=%s\ntransport=hmp-virtual-keyboard\ncredential_length=48\nsubmit_key=enter\nsecret_recorded=no\nframebuffer=%s\n' \
        "${phase}" "${framebuffer}" >"${evidence}/${phase}-luks-unlock-input.txt"
}

start_serial_bridge() {
    local ready output_fd
    [ -z "${serial_bridge_pid}" ] && [ -z "${serial_bridge_input_fd}" ] ||
        die 'serial bridge is already active'
    coproc ALI_SERIAL_BRIDGE {
        python3 /dev/fd/3 "${serial_socket}" "${qemu_pid}" "${evidence}/install-serial.log" 3<<'PY'
import os
import select
import socket
import struct
import sys
import time

path = sys.argv[1]
expected_pid = int(sys.argv[2])
log_path = sys.argv[3]
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(30)
    connection.connect(path)
    peer_pid, peer_uid, _ = struct.unpack(
        '3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i'))
    )
    if peer_pid != expected_pid or peer_uid != os.getuid():
        raise SystemExit('serial peer identity differs')
    connection.setblocking(False)
    print('SERIAL_BRIDGE_READY', flush=True)
    readers = [connection, sys.stdin.buffer]
    credential = b''
    with open(log_path, 'xb', buffering=0) as serial_log:
        while connection in readers:
            readable, _, _ = select.select(readers, [], [])
            if connection in readable:
                output = connection.recv(65536)
                if not output:
                    break
                serial_log.write(output)
            if sys.stdin.buffer in readable:
                value = os.read(sys.stdin.fileno(), 4096)
                if not value:
                    readers.remove(sys.stdin.buffer)
                    continue
                credential += value
                if b'\n' not in credential:
                    continue
                secret, trailing = credential.split(b'\n', 1)
                if trailing or len(secret) != 48 or any(c not in b'0123456789abcdef' for c in secret):
                    raise SystemExit('credential input is malformed')
                connection.sendall(secret + b'\r')
                time.sleep(1)
                connection.sendall(secret + b'\r')
                secret = b''
                credential = b''
                readers.remove(sys.stdin.buffer)
PY
    }
    serial_bridge_pid="${ALI_SERIAL_BRIDGE_PID}"
    serial_bridge_input_fd="${ALI_SERIAL_BRIDGE[1]}"
    output_fd="${ALI_SERIAL_BRIDGE[0]}"
    IFS= read -r -u "${output_fd}" ready || die 'serial bridge did not connect'
    exec {output_fd}<&-
    [ "${ready}" = SERIAL_BRIDGE_READY ] || die 'serial bridge readiness marker is invalid'
}

send_password() {
    [[ "${serial_bridge_input_fd}" =~ ^[0-9]+$ ]] || die 'serial bridge input is unavailable'
    [[ "${serial_bridge_pid}" =~ ^[1-9][0-9]*$ ]] || die 'serial bridge process is unavailable'
    [[ "${runtime_password}" =~ ^[a-f0-9]{48}$ ]] || die 'generated password is malformed'
    printf '%s\n' "${runtime_password}" >&"${serial_bridge_input_fd}"
    exec {serial_bridge_input_fd}>&-
    serial_bridge_input_fd=''
    kill -0 "${serial_bridge_pid}" 2>/dev/null || die 'protected serial credential delivery failed'
}

load_release_trust() {
    local trust_root="$1" primary_file signing_file key_file
    primary_file="${trust_root}/primary-fingerprint"
    signing_file="${trust_root}/signing-subkey-fingerprint"
    key_file="${trust_root}/arch-linux.gpg"
    for candidate in "${primary_file}" "${signing_file}" "${key_file}"; do
        [ -f "${candidate}" ] && [ ! -L "${candidate}" ] ||
            die "release trust input is unsafe: ${candidate}"
    done
    repository_primary_fingerprint="$(tr -d '\n' <"${primary_file}")"
    repository_signing_fingerprint="$(tr -d '\n' <"${signing_file}")"
    repository_public_key_sha256="$(sha256sum --binary -- "${key_file}" | awk '{ print $1 }')"
    repository_package_set_sha256="$(sha256sum --binary -- "${repository_root}/repository/package-set" | awk '{ print $1 }')"
    [[ "${repository_primary_fingerprint}" =~ ^[A-F0-9]{40}$ ]]
    [[ "${repository_signing_fingerprint}" =~ ^[A-F0-9]{40}$ ]]
    [ "${repository_primary_fingerprint}" != "${repository_signing_fingerprint}" ]
    [[ "${repository_public_key_sha256}" =~ ^[a-f0-9]{64}$ ]]
    [[ "${repository_package_set_sha256}" =~ ^[a-f0-9]{64}$ ]]
}

verify_staged_release_input() {
    local archive
    archive="${release_assets}/arch-linux-repository-${release_version}.tar.zst"
    "${repository_root}/repository/verify-release-assets.sh" \
        "${release_assets}" --phase-a \
        --release-version "${release_version}" \
        --source-commit "${source_commit}" \
        --source-tree "${source_tree}" \
        --build-metadata-sha256 "${build_metadata_sha256}" \
        --unsigned-manifest-sha256 "${unsigned_manifest_sha256}" \
        >"${evidence}/verify-release-assets.stdout" \
        2>"${evidence}/verify-release-assets.stderr"
    [ -f "${archive}" ] && [ ! -L "${archive}" ] || die 'signed repository archive is unsafe'
    [ "$(sha256sum --binary -- "${archive}" | awk '{ print $1 }')" = "${snapshot_sha256}" ] ||
        die 'signed repository snapshot SHA-256 differs'
    release_sha256sums_sha256="$(sha256sum --binary -- \
        "${release_assets}/RELEASE-SHA256SUMS" | awk '{ print $1 }')"
    [[ "${release_sha256sums_sha256}" =~ ^[a-f0-9]{64}$ ]] ||
        die 'Phase-A release manifest SHA-256 is malformed'
    load_release_trust "${release_assets}"
}

load_marble_repository_metadata() {
    local metadata="$1" line key value normalized package suffix matched metadata_count=0
    local -a expected_packages=()
    local -A seen=()
    mapfile -t expected_packages <"${repository_root}/repository/package-set"
    [ "${#expected_packages[@]}" -eq 6 ] || die 'repository metadata package closure is not six'
    [ -f "${metadata}" ] && [ ! -L "${metadata}" ] || die 'repository metadata is unsafe'
    while IFS= read -r line || [ -n "${line}" ]; do
        [[ "${line}" =~ ^([A-Za-z0-9_]+)=([A-Fa-f0-9]{40,64})$ ]] ||
            die 'repository metadata contains malformed data'
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        normalized="${key^^}"
        [ -z "${seen[${normalized}]+x}" ] || die "repository metadata repeats ${normalized}"
        seen["${normalized}"]=1
        metadata_count=$((metadata_count + 1))
        case "${normalized}" in
        PUBLIC_KEY_SHA256) repository_public_key_sha256="${value,,}" ;;
        PRIMARY_FINGERPRINT) repository_primary_fingerprint="${value^^}" ;;
        SIGNING_SUBKEY_FINGERPRINT) repository_signing_fingerprint="${value^^}" ;;
        PACKAGE_SET_SHA256) repository_package_set_sha256="${value,,}" ;;
        SNAPSHOT_SHA256)
            [ "${value,,}" = "${snapshot_sha256}" ] || die 'prepared snapshot digest differs'
            ;;
        BUILD_METADATA_SHA256)
            [ "${value,,}" = "${build_metadata_sha256}" ] || die 'prepared build metadata digest differs'
            ;;
        UNSIGNED_MANIFEST_SHA256)
            [ "${value,,}" = "${unsigned_manifest_sha256}" ] || die 'prepared unsigned manifest digest differs'
            ;;
        REPOSITORY_MANIFEST_SHA256) repository_manifest_sha256="${value,,}" ;;
        REPOSITORY_MANIFEST_SIGNATURE_SHA256) repository_manifest_signature_sha256="${value,,}" ;;
        REPOSITORY_DATABASE_SHA256) repository_database_sha256="${value,,}" ;;
        REPOSITORY_DATABASE_SIGNATURE_SHA256) repository_database_signature_sha256="${value,,}" ;;
        REPOSITORY_FILES_SHA256) repository_files_sha256="${value,,}" ;;
        REPOSITORY_FILES_SIGNATURE_SHA256) repository_files_signature_sha256="${value,,}" ;;
        PACKAGE_SHA256_*)
            matched='false'
            for package in "${expected_packages[@]}"; do
                suffix="${package^^}"
                suffix="${suffix//-/_}"
                if [ "${normalized}" = "PACKAGE_SHA256_${suffix}" ]; then
                    [ -z "${repository_package_hashes[${package}]+x}" ] ||
                        die "repository metadata repeats package hash: ${package}"
                    repository_package_hashes["${package}"]="${value,,}"
                    matched='true'
                    break
                fi
            done
            [ "${matched}" = true ] || die "repository metadata contains unknown package key: ${key}"
            ;;
        *) die "repository metadata contains unknown key: ${key}" ;;
        esac
    done <"${metadata}"
    [ "${metadata_count}" -eq 19 ] || die 'repository metadata key closure differs'
    [[ "${repository_public_key_sha256}" =~ ^[a-f0-9]{64}$ ]]
    [[ "${repository_primary_fingerprint}" =~ ^[A-F0-9]{40}$ ]]
    [[ "${repository_signing_fingerprint}" =~ ^[A-F0-9]{40}$ ]]
    [ "${repository_primary_fingerprint}" != "${repository_signing_fingerprint}" ]
    [[ "${repository_package_set_sha256}" =~ ^[a-f0-9]{64}$ ]]
    for value in "${repository_manifest_sha256}" "${repository_manifest_signature_sha256}" \
        "${repository_database_sha256}" "${repository_database_signature_sha256}" \
        "${repository_files_sha256}" "${repository_files_signature_sha256}"; do
        [[ "${value}" =~ ^[a-f0-9]{64}$ ]] || die 'repository object metadata digest is malformed'
    done
    for package in "${expected_packages[@]}"; do
        [[ "${repository_package_hashes[${package}]:-}" =~ ^[a-f0-9]{64}$ ]] ||
            die "repository package metadata is missing: ${package}"
    done
}

verify_retained_manifest_signature() {
    local manifest="$1" signature="$2" status valid
    status="$(gpgv --status-fd 1 \
        --keyring "${repository_root}/repository/trust/arch-linux.gpg" \
        -- "${signature}" "${manifest}" 2>/dev/null)" ||
        die 'retained repository manifest signature is invalid'
    if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|REVKEYSIG|EXPSIG)\b' <<<"${status}"; then
        die 'retained repository manifest has a rejected signature status'
    fi
    valid="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print toupper($3) ":" toupper($NF) }' \
        <<<"${status}")"
    [ "${valid}" = "${repository_signing_fingerprint}:${repository_primary_fingerprint}" ] ||
        die 'retained repository manifest signer identity differs'
}

retain_repository_manifest() {
    local manifest="$1" signature="$2" temporary_tsv package package_file package_hash pair
    local actual_manifest_hash actual_signature_hash expected_names actual_names
    local actual_database_hash actual_database_signature_hash actual_files_hash actual_files_signature_hash
    local source_file target_file
    local -a package_matches=()
    [ -f "${manifest}" ] && [ ! -L "${manifest}" ] && [ -s "${manifest}" ] ||
        die 'repository manifest evidence is unsafe'
    [ -f "${signature}" ] && [ ! -L "${signature}" ] && [ -s "${signature}" ] ||
        die 'repository manifest signature evidence is unsafe'
    actual_manifest_hash="$(sha256sum --binary -- "${manifest}" | awk '{ print $1 }')"
    actual_signature_hash="$(sha256sum --binary -- "${signature}" | awk '{ print $1 }')"
    if [ "${repository_manifest_sha256}" != - ]; then
        [ "${actual_manifest_hash}" = "${repository_manifest_sha256}" ] ||
            die 'repository manifest digest differs from verified metadata'
        [ "${actual_signature_hash}" = "${repository_manifest_signature_sha256}" ] ||
            die 'repository manifest signature digest differs from verified metadata'
    else
        repository_manifest_sha256="${actual_manifest_hash}"
        repository_manifest_signature_sha256="${actual_signature_hash}"
    fi
    verify_retained_manifest_signature "${manifest}" "${signature}"
    jq -e --arg version "${release_version}" --arg source_commit "${source_commit}" \
        --arg source_tree "${source_tree}" --arg installer_sha256 "${installer_sha256}" \
        --arg package_set_sha256 "${repository_package_set_sha256}" \
        --arg build_metadata_sha256 "${build_metadata_sha256}" \
        --arg unsigned_manifest_sha256 "${unsigned_manifest_sha256}" '
        type == "object" and
        (keys == ["architecture","buildMetadataSha256","files","installerSha256",
          "packageSetSha256","releaseVersion","repository","schema","sourceCommit",
          "sourceDateEpoch","sourceTree","unsignedManifestSha256"]) and
        .schema == 2 and .repository == "arch-linux" and .architecture == "x86_64" and
        .releaseVersion == $version and .sourceCommit == $source_commit and
        .sourceTree == $source_tree and .installerSha256 == $installer_sha256 and
        .packageSetSha256 == $package_set_sha256 and
        .buildMetadataSha256 == $build_metadata_sha256 and
        .unsignedManifestSha256 == $unsigned_manifest_sha256 and
        (.sourceDateEpoch | type == "number" and . > 0 and floor == .) and
        (.files | type == "array" and length == 23 and all(.[];
          type == "object" and keys == ["name","sha256","size"] and
          (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9+._-]*$")) and
          (.sha256 | type == "string" and test("^[a-f0-9]{64}$")) and
          (.size | type == "number" and . > 0 and floor == .)))
    ' "${manifest}" >/dev/null || die 'repository manifest identity or schema differs'

    temporary_tsv="${run_root}/.repository-objects.tsv"
    jq -r '.files[] | [.name,.sha256,(.size|tostring)] | @tsv' "${manifest}" >"${temporary_tsv}"
    [ "$(wc -l <"${temporary_tsv}")" -eq 23 ] || die 'repository object closure is not 23 files'
    actual_names="$(cut -f1 -- "${temporary_tsv}")"
    [ "${actual_names}" = "$(printf '%s\n' "${actual_names}" | LC_ALL=C sort -u)" ] ||
        die 'repository object names are not strictly sorted and unique'
    expected_names="$(printf '%s\n' \
        arch-linux.db arch-linux.db.sig arch-linux.db.tar.gz arch-linux.db.tar.gz.sig \
        arch-linux.files arch-linux.files.sig arch-linux.files.tar.gz arch-linux.files.tar.gz.sig \
        arch-linux.gpg primary-fingerprint signing-subkey-fingerprint | LC_ALL=C sort)"
    while IFS= read -r package; do
        mapfile -t package_matches < <(awk -F '\t' -v prefix="${package}-" '
            index($1,prefix) == 1 && $1 ~ /[.]pkg[.]tar[.]zst$/ { print $1 }' "${temporary_tsv}")
        [ "${#package_matches[@]}" -eq 1 ] || die "repository manifest package closure differs: ${package}"
        package_file="${package_matches[0]}"
        grep -Fxq "${package_file}.sig" <<<"${actual_names}" ||
            die "repository manifest package signature is missing: ${package}"
        package_hash="$(awk -F '\t' -v name="${package_file}" '$1 == name { print $2 }' "${temporary_tsv}")"
        if [ -n "${repository_package_hashes[${package}]:-}" ]; then
            [ "${repository_package_hashes[${package}]}" = "${package_hash}" ] ||
                die "repository package hash differs from verified metadata: ${package}"
        else
            repository_package_hashes["${package}"]="${package_hash}"
        fi
        expected_names="$(printf '%s\n%s\n%s\n' "${expected_names}" "${package_file}" \
            "${package_file}.sig" | LC_ALL=C sort)"
    done <"${repository_root}/repository/package-set"
    [ "${actual_names}" = "${expected_names}" ] || die 'repository manifest filename closure differs'

    actual_database_hash="$(repository_hash_from_tsv_from "${temporary_tsv}" arch-linux.db.tar.gz)"
    actual_database_signature_hash="$(repository_hash_from_tsv_from "${temporary_tsv}" arch-linux.db.tar.gz.sig)"
    actual_files_hash="$(repository_hash_from_tsv_from "${temporary_tsv}" arch-linux.files.tar.gz)"
    actual_files_signature_hash="$(repository_hash_from_tsv_from "${temporary_tsv}" arch-linux.files.tar.gz.sig)"
    if [ "${repository_database_sha256}" != - ]; then
        [ "${repository_database_sha256}" = "${actual_database_hash}" ] &&
            [ "${repository_database_signature_sha256}" = "${actual_database_signature_hash}" ] &&
            [ "${repository_files_sha256}" = "${actual_files_hash}" ] &&
            [ "${repository_files_signature_sha256}" = "${actual_files_signature_hash}" ] ||
            die 'repository database hashes differ from verified metadata'
    else
        repository_database_sha256="${actual_database_hash}"
        repository_database_signature_sha256="${actual_database_signature_hash}"
        repository_files_sha256="${actual_files_hash}"
        repository_files_signature_sha256="${actual_files_signature_hash}"
    fi
    if [ -e "${evidence}/repository-objects.tsv" ]; then
        cmp -s -- "${temporary_tsv}" "${evidence}/repository-objects.tsv" ||
            die 'repository object evidence changed within one VM run'
        rm -f -- "${temporary_tsv}"
    else
        chmod 0444 -- "${temporary_tsv}"
        mv -- "${temporary_tsv}" "${evidence}/repository-objects.tsv"
    fi
    for pair in "${manifest}:repository-manifest.json" \
        "${signature}:repository-manifest.json.sig"; do
        source_file="${pair%%:*}"
        target_file="${evidence}/${pair#*:}"
        if [ -e "${target_file}" ]; then
            cmp -s -- "${source_file}" "${target_file}" ||
                die 'retained repository manifest evidence changed within one VM run'
        else
            install -m0444 -- "${source_file}" "${target_file}"
        fi
    done
}

repository_hash_from_tsv_from() {
    local tsv="$1" name="$2"
    awk -F '\t' -v expected="${name}" '$1 == expected { print $2; count++ } END { if (count != 1) exit 1 }' \
        "${tsv}"
}

append_repository_identity() {
    local name checksum size
    [ "${repository_manifest_sha256}" != - ] || return 0
    grep -Fq 'repository_manifest_sha256=' "${run_root}/identity.txt" 2>/dev/null && return 0
    printf 'repository_manifest_sha256=%s\nrepository_manifest_signature_sha256=%s\nrepository_database_sha256=%s\nrepository_database_signature_sha256=%s\nrepository_files_sha256=%s\nrepository_files_signature_sha256=%s\n' \
        "${repository_manifest_sha256}" "${repository_manifest_signature_sha256}" \
        "${repository_database_sha256}" "${repository_database_signature_sha256}" \
        "${repository_files_sha256}" "${repository_files_signature_sha256}" \
        >>"${run_root}/identity.txt"
    if [ "${release_sha256sums_sha256}" != - ]; then
        printf 'release_sha256sums_sha256=%s\n' "${release_sha256sums_sha256}" \
            >>"${run_root}/identity.txt"
    fi
    while IFS=$'\t' read -r name checksum size; do
        printf 'repository_object_sha256=%s name=%s size=%s\n' "${checksum}" "${name}" "${size}"
    done <"${evidence}/repository-objects.tsv" >>"${run_root}/identity.txt"
}

prepare_signed_repository_input() {
    repository_server_root="${run_root}/repository"
    "${script_dir}/prepare-marble-repository.sh" \
        --source-root "${repository_root}" \
        --release-assets "${release_assets}" \
        --release-version "${release_version}" \
        --source-commit "${source_commit}" \
        --source-tree "${source_tree}" \
        --build-metadata-sha256 "${build_metadata_sha256}" \
        --unsigned-manifest-sha256 "${unsigned_manifest_sha256}" \
        --snapshot-sha256 "${snapshot_sha256}" \
        --output "${repository_server_root}" \
        >"${evidence}/prepare-marble-repository.stdout" \
        2>"${evidence}/prepare-marble-repository.stderr"
    load_marble_repository_metadata "${repository_server_root}/repository.env"
    [ "$(sha256sum --binary -- "${repository_server_root}/arch-linux.gpg" | awk '{ print $1 }')" = \
        "${repository_public_key_sha256}" ] || die 'prepared repository public key digest differs'
    retain_repository_manifest \
        "${repository_server_root}/repo/x86_64/repository-manifest.json" \
        "${repository_server_root}/repo/x86_64/repository-manifest.json.sig"
}

start_marble_repository_runtime() {
    local ca_sha server_url key_url readback_key
    repository_ca_private_key="${runtime_dir}/repository-ca.key"
    repository_server_private_key="${runtime_dir}/repository-server.key"
    repository_ready_file="${runtime_dir}/repository.port"
    repository_ca_file="${run_root}/repository-ca.crt"
    repository_server_certificate="${run_root}/repository-server.crt"
    openssl req -x509 -new -newkey rsa:3072 -nodes -sha256 -days 2 \
        -subj "/CN=arch-linux VM ${run_id}" \
        -keyout "${repository_ca_private_key}" -out "${repository_ca_file}" \
        >"${evidence}/repository-ca-openssl.stdout" 2>"${evidence}/repository-ca-openssl.stderr"
    openssl req -new -newkey rsa:3072 -nodes -sha256 \
        -subj '/CN=10.0.2.2' \
        -keyout "${repository_server_private_key}" \
        -out "${runtime_dir}/repository-server.csr" \
        >"${evidence}/repository-server-req.stdout" 2>"${evidence}/repository-server-req.stderr"
    printf '%s\n' \
        'basicConstraints=critical,CA:FALSE' \
        'keyUsage=critical,digitalSignature,keyEncipherment' \
        'extendedKeyUsage=serverAuth' \
        'subjectAltName=IP:10.0.2.2,IP:127.0.0.1' \
        >"${runtime_dir}/repository-server.ext"
    openssl x509 -req -sha256 -days 2 \
        -in "${runtime_dir}/repository-server.csr" \
        -CA "${repository_ca_file}" -CAkey "${repository_ca_private_key}" -CAcreateserial \
        -extfile "${runtime_dir}/repository-server.ext" \
        -out "${repository_server_certificate}" \
        >"${evidence}/repository-server-sign.stdout" 2>"${evidence}/repository-server-sign.stderr"
    rm -f -- "${repository_ca_private_key}" "${repository_ca_file}.srl"
    repository_ca_private_key=''
    openssl verify -CAfile "${repository_ca_file}" "${repository_server_certificate}" \
        >"${evidence}/repository-server-verify.txt"

    repository_server_executable="$(readlink -f -- /usr/bin/python3)"
    python3 -I "${script_dir}/https-server.py" "${repository_server_root}" \
        "${repository_server_certificate}" "${repository_server_private_key}" \
        "${repository_ready_file}" \
        >"${evidence}/repository-server.stdout" 2>"${evidence}/repository-server.stderr" &
    repository_server_pid=$!
    repository_server_start_time="$(process_start_time "${repository_server_pid}")" ||
        die 'cannot bind repository server process'
    process_is_exact_repository_server "${repository_server_pid}" "${repository_server_start_time}" ||
        die 'repository server process identity differs'
    for _ in {1..100}; do
        [ -f "${repository_ready_file}" ] && break
        process_is_exact_repository_server "${repository_server_pid}" "${repository_server_start_time}" ||
            die 'repository server exited before readiness'
        sleep 0.1
    done
    repository_server_port="$(tr -d '\n' <"${repository_ready_file}")"
    [[ "${repository_server_port}" =~ ^[1-9][0-9]{3,4}$ ]] &&
        [ "${repository_server_port}" -le 65535 ] || die 'repository server port is invalid'
    readback_key="${runtime_dir}/arch-linux.readback.gpg"
    curl --proto '=https' --fail --silent --show-error \
        --cacert "${repository_ca_file}" \
        --output "${readback_key}" -- \
        "https://127.0.0.1:${repository_server_port}/arch-linux.gpg"
    cmp -s -- "${readback_key}" "${repository_server_root}/arch-linux.gpg" ||
        die 'repository TLS readback differs'
    rm -f -- "${readback_key}"
    server_url="https://10.0.2.2:${repository_server_port}/repo/\$arch"
    key_url="https://10.0.2.2:${repository_server_port}/arch-linux.gpg"
    ca_sha="$(sha256sum --binary -- "${repository_ca_file}" | awk '{ print $1 }')"
    printf '%s\n' \
        'schema=1' \
        "server_url=${server_url}" \
        "public_key_url=${key_url}" \
        "public_key_sha256=${repository_public_key_sha256}" \
        "primary_fingerprint=${repository_primary_fingerprint}" \
        "signing_subkey_fingerprint=${repository_signing_fingerprint}" \
        'ca_file=/run/arch-linux-qemu/acceptance-ca.crt' \
        "ca_sha256=${ca_sha}" \
        >"${run_root}/repository.contract"
    chmod 0400 -- "${run_root}/repository.contract"
    sha256sum -- "${repository_server_root}/repository.env" "${run_root}/repository.contract" \
        "${repository_ca_file}" "${repository_server_certificate}" \
        >"${run_root}/repository-runtime.sha256"
}

launch_qemu() {
    local phase="$1" install_phase="$2" bootindex=1
    [ "${install_phase}" = true ] && bootindex=2
    local -a command=(
        "${qemu_bin}"
        -nodefaults
        -no-user-config
        -name "ali-${run_prefix}-${run_id}-${phase}"
        -machine 'q35,accel=kvm'
        -cpu host
        -smp 4
        -m "${guest_memory_mib}"
        -rtc 'base=utc,clock=host'
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${ovmf_code}"
        -drive "if=pflash,format=raw,unit=1,file=${run_root}/OVMF_VARS.fd"
        -drive "if=none,id=target,format=qcow2,file=${run_root}/target.qcow2,cache=writeback,discard=unmap"
        -device 'virtio-scsi-pci,id=scsi0'
        -device "scsi-hd,id=targetdev,drive=target,bus=scsi0.0,serial=${target_serial},vendor=SNAPLYZE,product=${target_model},bootindex=${bootindex}"
        -device 'virtio-vga,id=display0'
        -device virtio-serial-pci
        -chardev "socket,id=qga0,path=${runtime_dir}/qga.sock,server=on,wait=off"
        -device 'virtserialport,chardev=qga0,name=org.qemu.guest_agent.0'
        -chardev "socket,id=hmp0,path=${runtime_dir}/hmp.sock,server=on,wait=off"
        -mon 'chardev=hmp0,mode=readline'
        -qmp "unix:${runtime_dir}/qmp.sock,server=on,wait=off"
        -display none
        -boot 'menu=off,strict=on'
        -no-reboot
        -nic 'user,model=virtio-net-pci'
        -sandbox 'on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny'
    )
    if [ "${install_phase}" = true ]; then
        command+=(
            -chardev "socket,id=seriallog,path=${runtime_dir}/serial.sock,server=on,wait=off"
            -device 'isa-serial,chardev=seriallog,index=0'
            -chardev "file,id=installerlog,path=${evidence}/install-installer.log,append=on"
            -device 'isa-serial,chardev=installerlog,index=1'
            -drive "if=none,id=installiso,format=raw,media=cdrom,readonly=on,file=${iso_path}"
            -device 'ide-cd,id=installcd,drive=installiso,bootindex=1'
            -drive "if=none,id=payload0,format=raw,readonly=on,file=${run_root}/payload.iso"
            -device 'virtio-blk-pci,id=payloaddev,drive=payload0,serial=ALI100PAYLOAD'
        )
    else
        command+=(
            -chardev "file,id=seriallog,path=${evidence}/${phase}-serial.log,append=on"
            -device 'isa-serial,chardev=seriallog,index=0'
        )
    fi
    rm -f -- "${runtime_dir}/qga.sock" "${runtime_dir}/hmp.sock" \
        "${runtime_dir}/qmp.sock" \
        "${runtime_dir}/serial.sock"
    command+=( -D "${evidence}/${phase}-qemu-debug.log" )
    "${command[@]}" >"${evidence}/${phase}-qemu.stdout" 2>"${evidence}/${phase}-qemu.stderr" &
    qemu_pid=$!
    qemu_start_time="$(process_start_time "${qemu_pid}")" || die "cannot bind QEMU process: ${phase}"
    process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" || die "QEMU process identity differs: ${phase}"
    qemu_pids+=("${qemu_pid}")
    hmp_socket="${runtime_dir}/hmp.sock"
    qmp_socket="${runtime_dir}/qmp.sock"
    qga_socket="${runtime_dir}/qga.sock"
    serial_socket="${runtime_dir}/serial.sock"
    wait_for_socket "${hmp_socket}" 30 || die "HMP socket did not appear: ${phase}"
    wait_for_socket "${qmp_socket}" 30 || die "QMP socket did not appear: ${phase}"
    wait_for_socket "${qga_socket}" 30 || die "QGA socket did not appear: ${phase}"
    if [ "${install_phase}" = true ]; then
        wait_for_socket "${serial_socket}" 30 || die 'password serial socket did not appear'
        start_serial_bridge
    fi
    qga_socket_identity="$(stat -Lc '%d:%i' -- "${qga_socket}")"
    qmp_socket_identity="$(stat -Lc '%d:%i' -- "${qmp_socket}")"
    if [ "${install_phase}" = false ]; then
        printf 'phase=%s\npid=%s\nstart_time=%s\nqga_identity=%s\nqmp_identity=%s\n' \
            "${phase}" "${qemu_pid}" "${qemu_start_time}" "${qga_socket_identity}" \
            "${qmp_socket_identity}" \
            >"${evidence}/${phase}-qemu.identity"
    fi
}

wait_qemu_exit() {
    local phase="$1" timeout="$2" status bridge_status
    local deadline=$((SECONDS + timeout))
    while process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" && [ "${SECONDS}" -lt "${deadline}" ]; do
        sleep 1
    done
    process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" && die "QEMU did not exit: ${phase}"
    set +e
    wait "${qemu_pid}"
    status=$?
    set -e
    printf 'phase=%s\nexit_status=%s\n' "${phase}" "${status}" >"${evidence}/${phase}-qemu.exit"
    [ "${status}" -eq 0 ] || die "QEMU exited unsuccessfully: ${phase}: ${status}"
    qemu_pid=''
    qemu_start_time=''
    qmp_socket=''
    qmp_socket_identity=''
    if [[ "${serial_bridge_pid}" =~ ^[1-9][0-9]*$ ]]; then
        if [[ "${serial_bridge_input_fd}" =~ ^[0-9]+$ ]]; then
            exec {serial_bridge_input_fd}>&-
        fi
        serial_bridge_input_fd=''
        set +e
        wait "${serial_bridge_pid}"
        bridge_status=$?
        set -e
        serial_bridge_pid=''
        [ "${bridge_status}" -eq 0 ] || die "serial transcript bridge failed: ${phase}: ${bridge_status}"
    fi
}

qga_call() {
    local request="$1"
    process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" || return 1
    printf '%s\n' "${request}" | python3 -I "${script_dir}/qga-client.py" \
        "${qga_socket}" "${qemu_pid}" "${qga_socket_identity}"
}

wait_qga() {
    local response deadline=$((SECONDS + 300)) request
    request="$(jq -cn '{execute:"guest-ping"}')"
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if response="$(qga_call "${request}" 2>/dev/null)" &&
            jq -e '.return == {}' <<<"${response}" >/dev/null; then
            return 0
        fi
        process_is_exact_qemu "${qemu_pid}" "${qemu_start_time}" || return 1
        sleep 1
    done
    return 1
}

capture_public_repository_evidence() {
    local stdout_file="$1" binding_line manifest_line signature_line manifest_b64 signature_b64
    local temporary_manifest temporary_signature
    [ "${input_mode}" = public ] || return 0
    [ "$(grep -c '^MARBLE_PUBLIC_SNAPSHOT_BINDING_PASS ' "${stdout_file}")" -eq 1 ] ||
        die 'public snapshot binding marker count differs'
    binding_line="$(grep '^MARBLE_PUBLIC_SNAPSHOT_BINDING_PASS ' "${stdout_file}")"
    [[ "${binding_line}" =~ ^MARBLE_PUBLIC_SNAPSHOT_BINDING_PASS\ run_id=${run_id}\ snapshot_sha256=${snapshot_sha256}\ release_sums_sha256=([a-f0-9]{64})\ repository_manifest_sha256=([a-f0-9]{64})\ repository_manifest_signature_sha256=([a-f0-9]{64})\ pages_objects=23\ package_signatures=6\ database_signatures=2$ ]] ||
        die 'public snapshot binding marker differs'
    release_sha256sums_sha256="${BASH_REMATCH[1]}"
    repository_manifest_sha256="${BASH_REMATCH[2]}"
    repository_manifest_signature_sha256="${BASH_REMATCH[3]}"
    [ "$(grep -c '^PUBLIC_REPOSITORY_MANIFEST_BASE64 ' "${stdout_file}")" -eq 1 ] &&
        [ "$(grep -c '^PUBLIC_REPOSITORY_MANIFEST_SIGNATURE_BASE64 ' "${stdout_file}")" -eq 1 ] ||
        die 'public repository manifest evidence count differs'
    manifest_line="$(grep '^PUBLIC_REPOSITORY_MANIFEST_BASE64 ' "${stdout_file}")"
    signature_line="$(grep '^PUBLIC_REPOSITORY_MANIFEST_SIGNATURE_BASE64 ' "${stdout_file}")"
    manifest_b64="${manifest_line#PUBLIC_REPOSITORY_MANIFEST_BASE64 run_id="${run_id}" value=}"
    signature_b64="${signature_line#PUBLIC_REPOSITORY_MANIFEST_SIGNATURE_BASE64 run_id="${run_id}" value=}"
    [ "${manifest_line}" != "${manifest_b64}" ] && [ "${signature_line}" != "${signature_b64}" ] ||
        die 'public repository manifest evidence run identity differs'
    [[ "${manifest_b64}" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] &&
        [[ "${signature_b64}" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] ||
        die 'public repository manifest evidence encoding is malformed'
    temporary_manifest="${run_root}/.public-repository-manifest.json"
    temporary_signature="${run_root}/.public-repository-manifest.json.sig"
    printf '%s' "${manifest_b64}" | base64 --decode >"${temporary_manifest}" ||
        die 'cannot decode public repository manifest evidence'
    printf '%s' "${signature_b64}" | base64 --decode >"${temporary_signature}" ||
        die 'cannot decode public repository manifest signature evidence'
    [ "$(sha256sum --binary -- "${temporary_manifest}" | awk '{ print $1 }')" = \
        "${repository_manifest_sha256}" ] || die 'public repository manifest evidence digest differs'
    [ "$(sha256sum --binary -- "${temporary_signature}" | awk '{ print $1 }')" = \
        "${repository_manifest_signature_sha256}" ] ||
        die 'public repository manifest signature evidence digest differs'
    retain_repository_manifest "${temporary_manifest}" "${temporary_signature}"
    rm -f -- "${temporary_manifest}" "${temporary_signature}"
    append_repository_identity
    snapshot_verification='PUBLIC_RELEASE_PAGES_BINDING_PASS'
}

qga_verify() {
    local phase="$1" stem="$2"
    local request start guest_pid status_request status_response=''
    local guest_script stdout_file stderr_file attempts=900
    guest_script="$(<"${script_dir}/guest/verify.sh")"
    request="$(jq -cn --arg script "${guest_script}" --arg phase "${phase}" \
        --arg serial "${target_serial}" --arg vendor SNAPLYZE --arg model "${target_model}" \
        --arg username vmtest --arg scenario "${scenario_id}" --arg run_id "${run_id}" \
        --arg repository_primary "${repository_primary_fingerprint}" \
        --arg repository_signing "${repository_signing_fingerprint}" \
        --arg input_mode "${input_mode}" --arg release_version "${release_version}" \
        --arg pages_url "${pages_url:--}" --arg public_key_url "${public_key_url:--}" \
        --arg snapshot_sha256 "${snapshot_sha256}" --arg source_commit "${source_commit}" \
        --arg source_tree "${source_tree}" --arg installer_sha256 "${installer_sha256}" \
        --arg package_set_sha256 "${repository_package_set_sha256}" \
        --arg build_metadata_sha256 "${build_metadata_sha256}" \
        --arg unsigned_manifest_sha256 "${unsigned_manifest_sha256}" \
        --arg public_key_sha256 "${repository_public_key_sha256}" '
        {execute:"guest-exec",arguments:{path:"/usr/bin/bash","capture-output":true,
          arg:["-c",$script,"minimal-verify",$phase,$serial,$vendor,$model,$username,$scenario,$run_id,
            $repository_primary,$repository_signing,$input_mode,$release_version,$pages_url,$public_key_url,
            $snapshot_sha256,$source_commit,$source_tree,$installer_sha256,$package_set_sha256,
            $build_metadata_sha256,$unsigned_manifest_sha256,$public_key_sha256]}}')"
    printf '%s\n' "${request}" | jq -cS . >"${evidence}/${stem}.request.json"
    start="$(qga_call "${request}")" || die "QGA verification did not start: ${phase}"
    printf '%s\n' "${start}" | jq -cS . >"${evidence}/${stem}.start.json"
    guest_pid="$(jq -er '.return.pid | select(type == "number" and . > 0)' <<<"${start}")" ||
        die "QGA verification PID is invalid: ${phase}"
    status_request="$(jq -cn --argjson pid "${guest_pid}" \
        '{execute:"guest-exec-status",arguments:{pid:$pid}}')"
    [ "${phase}" = update ] && attempts=3600
    for ((attempt = 0; attempt < attempts; attempt++)); do
        if status_response="$(qga_call "${status_request}")" &&
            jq -e '.return.exited == true' <<<"${status_response}" >/dev/null; then
            break
        fi
        sleep 2
    done
    [ -n "${status_response}" ] || die "QGA verification produced no status: ${phase}"
    printf '%s\n' "${status_response}" | jq -cS . >"${evidence}/${stem}.status.json"
    stdout_file="${evidence}/${stem}.stdout"
    stderr_file="${evidence}/${stem}.stderr"
    jq -r '.return["out-data"] // ""' <<<"${status_response}" | base64 --decode >"${stdout_file}"
    jq -r '.return["err-data"] // ""' <<<"${status_response}" | base64 --decode >"${stderr_file}"
    jq -e '.return.exited == true and .return.exitcode == 0 and
        (.return["out-truncated"] // false) == false and
        (.return["err-truncated"] // false) == false' <<<"${status_response}" >/dev/null ||
        die "guest verification failed: ${phase}"
    if [ -s "${stderr_file}" ]; then
        printf 'QEMU_DIAGNOSTIC_WARNING: successful guest check wrote stderr: %s\n' "${phase}" >&2
    fi
    grep -aFq -- "${marker_prefix}_QEMU_GUEST_PASS run_id=${run_id} scenario=${scenario_id} phase=${phase}" \
        "${stdout_file}" || die "guest verification marker is missing: ${phase}"
    last_boot_id="$(sed -n 's/^.* boot_id=\([a-f0-9-]\{36\}\) .*$/\1/p' "${stdout_file}" | head -n1)"
    [[ "${last_boot_id}" =~ ^[a-f0-9-]{36}$ ]] || die "guest boot id is missing: ${phase}"
    if [ "${input_mode}" = public ] && [ "${phase}" = prelogin ]; then
        capture_public_repository_evidence "${stdout_file}"
    fi
}

schedule_transition() {
    local mode="$1" phase="$2" request start guest_pid status_request status_response=''
    request="$(jq -cn --arg unit "ali-${run_prefix}-${mode}-${run_id}" --arg mode "${mode}" '
      {execute:"guest-exec",arguments:{path:"/usr/bin/systemd-run","capture-output":true,
        arg:["--quiet","--no-block","--collect","--on-active=3s",("--unit="+$unit),
          "/usr/bin/systemctl",$mode]}}')"
    printf '%s\n' "${request}" | jq -cS . >"${evidence}/${phase}-${mode}.request.json"
    start="$(qga_call "${request}")" || die "guest ${mode} scheduler did not start"
    printf '%s\n' "${start}" | jq -cS . >"${evidence}/${phase}-${mode}.start.json"
    guest_pid="$(jq -er '.return.pid | select(type == "number" and . > 0)' <<<"${start}")" ||
        die "guest ${mode} scheduler PID is invalid"
    status_request="$(jq -cn --argjson pid "${guest_pid}" \
        '{execute:"guest-exec-status",arguments:{pid:$pid}}')"
    for _ in {1..100}; do
        if status_response="$(qga_call "${status_request}")" &&
            jq -e '.return.exited == true' <<<"${status_response}" >/dev/null; then
            break
        fi
        sleep 0.1
    done
    printf '%s\n' "${status_response}" | jq -cS . >"${evidence}/${phase}-${mode}.status.json"
    jq -e '.return.exited == true and .return.exitcode == 0' \
        <<<"${status_response}" >/dev/null || die "guest ${mode} scheduler failed"
}

marble_gdm_login() {
    local phase="$1" stem="$2" password_capture="${3:-}"
    hmp_request key ret
    sleep 3
    if [ -n "${password_capture}" ]; then
        capture_screen "${password_capture}"
    fi
    hmp_type_password
    printf 'phase=%s\ntransport=hmp-virtual-keyboard\ncredential_length=48\nsubmit_key=enter\nsecret_recorded=no\n' \
        "${phase}" >"${evidence}/${stem}-login-input.txt"
    qga_verify "${phase}" "${stem}-login"
}

run_marble_acceptance() {
    local first_boot_id post_boot_id

    qga_verify prelogin firstboot-prelogin
    first_boot_id="${last_boot_id}"
    if [ "${input_mode}" = public ]; then
        record_assertion public-release-pages-snapshot-binding \
            'signed public RELEASE-SHA256SUMS and archive bytes bound the exact snapshot digest to the byte-identical signed Pages manifest and all 23 HTTPS object hashes/signatures'
    fi
    capture_screen firstboot-gdm
    if [[ "${scenario_id}" = *-stock-gdm ]]; then
        record_assertion encrypted-btrfs-systemdboot-marble-stock-gdm \
            'installer selected Marble desktop with Stock GDM; the separate Marble GDM package was absent'
    else
        record_assertion encrypted-btrfs-systemdboot-marble-optin \
            'the exact installer selected Btrfs, LUKS2, Plymouth, systemd-boot, Marble desktop and experimental Marble GDM explicitly'
        record_assertion experimental-gdm-stock-fallback \
            'experimental GDM was active only through its separate fail-closed compatibility contract with Stock retained as fallback'
    fi
    record_assertion graphical-plymouth-unlock \
        'virtual-keyboard LUKS unlock reached GDM without repair; any screenshot is diagnostic only'

    marble_gdm_login firstlogin firstboot firstboot-gdm-password
    capture_screen firstboot-desktop
    record_assertion gdm-user-password-no-autologin \
        'the real Wayland GDM greeter required password authentication with autologin disabled'
    record_assertion first-gdm-login-wayland \
        'the first real gdm-password authentication reached the exact vmtest GNOME Wayland session'
    record_assertion marble-shell-active \
        'the supported Marble blue dark Shell alias and effective User Themes setting were active'
    record_assertion colloid-gtk3-icons-bibata-gtk4-stock \
        'Colloid Dark GTK3 and icons plus Bibata were effective while project GTK4/libadwaita CSS remained absent'
    record_assertion user-themes-extension-profile \
        'the official User Themes extension joined the seven editable Stock extensions for an exact 8/8 enabled profile'
    if [[ "${scenario_id}" = *-stock-gdm ]]; then
        record_assertion stock-gdm-no-project-overlay \
            'Stock GDM ran without the Marble GDM package or resource overlay'
    else
        record_assertion gdm-process-scoped-overlays \
            'the GDM Shell process alone carried exact G_RESOURCE_OVERLAYS and DCONF_PROFILE values with locked Colloid icons'
    fi
    record_assertion user-shell-overlay-isolation \
        'the authenticated user gnome-shell process inherited neither G_RESOURCE_OVERLAYS nor DCONF_PROFILE'
    record_assertion vendor-paths-clean \
        'project ownership avoided forbidden GNOME, GDM, GTK4, PAM, home and vendor-resource paths and reviewed vendor hashes matched'
    record_assertion project-packages-qkk-clean \
        'all selected project packages plus gnome-shell and gdm reported zero altered files'

    qga_verify lock firstboot-lock-start
    hmp_request key ret
    sleep 2
    hmp_type_password
    qga_verify unlock firstboot-lock-finish
    record_assertion lock-password-unlock \
        'only the real password unlock restored the same locked GNOME Wayland session'

    qga_verify update firstboot-update
    record_assertion update-hooks-safe \
        'pacman -Syu completed through the strict repository; Marble hooks revalidated active state and every Qkk gate stayed clean'
    schedule_transition reboot firstboot
    wait_qemu_exit firstboot-reboot 300

    current_phase='postreboot'
    launch_qemu postreboot false
    capture_and_unlock_luks_prompt postreboot false
    wait_qga || die 'post-reboot Marble guest agent did not become ready'
    qga_verify postreboot-prelogin postreboot-prelogin
    post_boot_id="${last_boot_id}"
    [ "${first_boot_id}" != "${post_boot_id}" ] || die 'Marble reboot did not produce a new boot id'
    record_assertion reboot-plymouth-gdm-reactivation \
        'reboot changed boot ID, repeated graphical Plymouth unlock and returned to the selected GDM profile'
    marble_gdm_login secondlogin postreboot
    record_assertion second-gdm-login-wayland \
        'the second real GDM password authentication reached Marble GNOME Wayland with storage, isolation and Qkk intact'
    if [ "${input_mode}" = staged ] && [[ "${scenario_id}" != *-stock-gdm ]]; then
        current_phase='marble-lifecycle'
        qga_verify incompatible-fixture fallback-enable
        qga_verify incompatible-prelogin fallback-greeter
        marble_gdm_login incompatible-login fallback
        qga_verify restore-marble fallback-restore
        qga_verify restored-prelogin restored-greeter
        marble_gdm_login restored-login restored
        record_assertion gdm-stock-fallback-and-restore \
            'an administrator GDM profile caused Stock fallback; removing that conflict restored Marble and real password login'
        qga_verify remove-marble profile-remove
        qga_verify removed-prelogin removed-greeter
        marble_gdm_login removed-login removed
        record_assertion marble-package-removal-stock \
            'pacman removed the project profile; Stock GDM and Stock user GNOME remained usable through a real login'
        qga_verify reinstall-marble profile-reinstall
        qga_verify reinstalled-prelogin reinstalled-greeter
        marble_gdm_login reinstalled-login reinstalled
        record_assertion marble-package-reinstall \
            'pacman reinstalled the signed packages and restored Marble desktop/GDM with clean package integrity and login'
    fi
    current_phase='clean-shutdown'
    schedule_transition poweroff postreboot
    wait_qemu_exit postreboot-poweroff 300
}

build_result() {
    local result_status="$1" exit_status="$2" failed_phase="$3"
    local assertions_json screenshots_json repository_objects_json='[]'
    case "${result_status}" in
    PASS)
        [ "${exit_status}" -eq 0 ] && [ "${failed_phase}" = - ] || {
            die 'PASS result status arguments are inconsistent'
            return 1
        }
        ;;
    FAIL)
        [[ "${exit_status}" =~ ^[1-9][0-9]*$ ]] && [[ "${failed_phase}" =~ ^[a-z0-9-]+$ ]] || {
            die 'FAIL result status arguments are inconsistent'
            return 1
        }
        ;;
    *) die 'structured result status is invalid'; return 1 ;;
    esac
    assertions_json="$(jq -Rn '[inputs | split("\t") | {id:.[0],status:.[1],detail:.[2]}]' \
        <"${assertions_file}")" || return 1
    screenshots_json="$(find "${evidence}" -maxdepth 1 -type f -name '*.ppm' \
        -printf '%f\n' |
        LC_ALL=C sort | jq -Rn '[inputs]')" || return 1
    if [ -f "${evidence}/repository-objects.tsv" ]; then
        repository_objects_json="$(jq -Rn '
          [inputs | split("\t") |
            {name:.[0],sha256:.[1],size:(.[2] | tonumber)}]' \
            <"${evidence}/repository-objects.tsv")" || return 1
    fi
    jq -cS -n \
        --arg status "${result_status}" --argjson exitStatus "${exit_status}" \
        --arg failedPhase "${failed_phase}" \
        --arg scenario "${scenario_id}" --arg runId "${run_id}" \
        --arg inputMode "${input_mode}" --arg releaseVersion "${release_version}" \
        --arg sourceCommit "${source_commit}" --arg sourceTree "${source_tree}" \
        --arg installerSha256 "${installer_sha256}" --arg harnessSha256 "${harness_sha256}" \
        --arg isoSha256 "${iso_sha256}" --arg targetSerial "${target_serial}" \
        --arg repositoryPrimaryFingerprint "${repository_primary_fingerprint}" \
        --arg repositorySigningFingerprint "${repository_signing_fingerprint}" \
        --arg repositoryPublicKeySha256 "${repository_public_key_sha256}" \
        --arg repositoryPackageSetSha256 "${repository_package_set_sha256}" \
        --arg repositorySnapshotSha256 "${snapshot_sha256}" \
        --arg repositoryManifestSha256 "${repository_manifest_sha256}" \
        --arg repositoryManifestSignatureSha256 "${repository_manifest_signature_sha256}" \
        --arg repositoryDatabaseSha256 "${repository_database_sha256}" \
        --arg repositoryDatabaseSignatureSha256 "${repository_database_signature_sha256}" \
        --arg repositoryFilesSha256 "${repository_files_sha256}" \
        --arg repositoryFilesSignatureSha256 "${repository_files_signature_sha256}" \
        --arg releaseSha256sumsSha256 "${release_sha256sums_sha256}" \
        --arg snapshotVerification "${snapshot_verification}" \
        --arg buildMetadataSha256 "${build_metadata_sha256}" \
        --arg unsignedManifestSha256 "${unsigned_manifest_sha256}" \
        --argjson retainedEvidenceBytes "${evidence_size_bytes}" \
        --argjson screenshots "${screenshots_json}" --argjson assertions "${assertions_json}" \
        --argjson repositoryObjects "${repository_objects_json}" \
        '{assertions:$assertions,buildMetadataSha256:$buildMetadataSha256,
          exitStatus:$exitStatus,failedPhase:(if $failedPhase == "-" then null else $failedPhase end),
          harnessSha256:$harnessSha256,inputMode:$inputMode,
          installerSha256:$installerSha256,isoSha256:$isoSha256,runId:$runId,scenario:$scenario,
          releaseSha256sumsSha256:$releaseSha256sumsSha256,
          repositoryDatabaseSha256:$repositoryDatabaseSha256,
          repositoryDatabaseSignatureSha256:$repositoryDatabaseSignatureSha256,
          repositoryFilesSha256:$repositoryFilesSha256,
          repositoryFilesSignatureSha256:$repositoryFilesSignatureSha256,
          repositoryManifestSha256:$repositoryManifestSha256,
          repositoryManifestSignatureSha256:$repositoryManifestSignatureSha256,
          repositoryObjects:$repositoryObjects,
          repositoryPackageSetSha256:$repositoryPackageSetSha256,
          repositoryPrimaryFingerprint:$repositoryPrimaryFingerprint,
          repositoryPublicKeySha256:$repositoryPublicKeySha256,
          repositorySnapshotSha256:$repositorySnapshotSha256,
          repositorySigningFingerprint:$repositorySigningFingerprint,
          releaseVersion:$releaseVersion,retainedEvidenceBytes:$retainedEvidenceBytes,
          screenshots:$screenshots,snapshotVerification:$snapshotVerification,
          sourceCommit:$sourceCommit,sourceTree:$sourceTree,status:$status,
          targetSerial:$targetSerial,unsignedManifestSha256:$unsignedManifestSha256}' \
        >"${run_root}/result.json" || return 1
    jq -e --arg expected_status "${result_status}" --argjson expected_exit "${exit_status}" \
        --arg expected_phase "${failed_phase}" '
        .status == $expected_status and .exitStatus == $expected_exit and
        (if $expected_status == "PASS"
         then .failedPhase == null and .exitStatus == 0
         else .failedPhase == $expected_phase and .exitStatus > 0 end)
    ' "${run_root}/result.json" >/dev/null || {
        die 'structured result status self-check failed'
        return 1
    }
}

assert_forced_failure_result_contract() {
    local fixture
    fixture='{"status":"FAIL","exitStatus":23,"failedPhase":"forced-failure"}'
    jq -e '.status == "FAIL" and .exitStatus == 23 and .failedPhase == "forced-failure"' \
        <<<"${fixture}" >/dev/null || die 'forced FAIL result fixture was rejected'
    if jq -e '.status == "PASS" or .exitStatus == 0 or .failedPhase == null' \
        <<<"${fixture}" >/dev/null; then
        die 'forced FAIL result fixture could be interpreted as PASS'
    fi
}

bind_frozen_inputs() {
    local binding="${output_parent}/frozen-inputs.txt" expected
    expected="$(printf '%s\n' \
        "source_commit=${source_commit}" \
        "source_tree=${source_tree}" \
        "harness_commit=${harness_commit}" \
        "harness_tree=${harness_tree}" \
        "installer_sha256=${installer_sha256}" \
        "bootstrap_sha256=${bootstrap_sha256}" \
        "iso_sha256=${iso_sha256}" \
        "release_version=${release_version}" \
        "snapshot_sha256=${snapshot_sha256}" \
        "build_metadata_sha256=${build_metadata_sha256}" \
        "unsigned_manifest_sha256=${unsigned_manifest_sha256}")"
    if [ ! -e "${binding}" ] && [ ! -L "${binding}" ]; then
        if ! (set -o noclobber; printf '%s\n' "${expected}" >"${binding}") 2>/dev/null; then
            [ -f "${binding}" ] || die 'cannot create frozen VM input binding'
        fi
        chmod 0600 -- "${binding}"
    fi
    [ -f "${binding}" ] && [ ! -L "${binding}" ] || die 'frozen VM input binding is unsafe'
    [ "$(stat -Lc '%u:%a:%h' -- "${binding}")" = "$(id -u):600:1" ] ||
        die 'frozen VM input binding metadata differs'
    [ "$(cat -- "${binding}")" = "${expected}" ] ||
        die 'VM run inputs differ from the frozen acceptance cycle'
}

main() {
    local bootstrap_command='mkdir -p /run/a;mount -o ro LABEL=ALIPAY /run/a;bash /run/a/b'
    local first_boot_id post_boot_id final_qemu_matches install_outcome
    local bootstrap_timeout=300 shutdown_phase=postreboot
    local -a harness_files=(
        tests/vm/run.sh
        tests/vm/frame-evidence.py
        tests/vm/qga-client.py
        tests/vm/https-server.py
        tests/vm/prepare-marble-repository.sh
        tests/vm/guest/bootstrap.sh
        tests/vm/guest/verify.sh
    )

    [ "$#" -ge 1 ] || { usage; exit 2; }
    scenario_id="$1"
    case "${scenario_id}" in
    minimal-ext4-systemdboot)
        run_prefix='minimal'
        marker_prefix='MINIMAL'
        guest_hostname='ali-minimal'
        guest_memory_mib=4096
        target_size='32G'
        target_size_bytes=34359738368
        ;;
    minimal-dualboot-ext4-systemdboot)
        run_prefix='dualboot'
        marker_prefix='MINIMAL'
        guest_hostname='ali-dualboot'
        guest_memory_mib=4096
        target_size='32G'
        target_size_bytes=34359738368
        ;;
    stock-gnome-ext4-systemdboot)
        run_prefix='stock'
        marker_prefix='STOCK'
        guest_hostname='ali-stock'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    stock-gnome-btrfs-systemdboot)
        run_prefix='btrfs'
        marker_prefix='BTRFS'
        guest_hostname='ali-btrfs'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    stock-gnome-btrfs-grub)
        run_prefix='grub'
        marker_prefix='GRUB'
        guest_hostname='ali-grub'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    stock-gnome-btrfs-luks2-plymouth-systemdboot)
        run_prefix='luks'
        marker_prefix='LUKS'
        guest_hostname='ali-luks'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    stock-gnome-btrfs-luks2-plymouth-grub)
        run_prefix='luksgrub'
        marker_prefix='LUKSGRUB'
        guest_hostname='ali-luks-grub'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    marble-gnome-btrfs-luks2-plymouth-systemdboot)
        run_prefix='marble'
        marker_prefix='MARBLE'
        guest_hostname='ali-marble'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;    marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm)
        run_prefix='marblestock'
        marker_prefix='MARBLE'
        guest_hostname='ali-marble-stock'
        guest_memory_mib=8192
        target_size='64G'
        target_size_bytes=68719476736
        ;;
    *) usage; exit 2 ;;
    esac
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --iso) [ "$#" -ge 2 ] || { usage; exit 2; }; iso_path="$2"; shift 2 ;;
        --iso-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; iso_sha256="$2"; shift 2 ;;
        --output-root) [ "$#" -ge 2 ] || { usage; exit 2; }; output_parent="$2"; shift 2 ;;
        --mode) [ "$#" -ge 2 ] || { usage; exit 2; }; input_mode="$2"; shift 2 ;;
        --release-assets) [ "$#" -ge 2 ] || { usage; exit 2; }; release_assets="$2"; shift 2 ;;
        --release-version) [ "$#" -ge 2 ] || { usage; exit 2; }; release_version="$2"; shift 2 ;;
        --snapshot-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; snapshot_sha256="$2"; shift 2 ;;
        --build-metadata-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; build_metadata_sha256="$2"; shift 2 ;;
        --unsigned-manifest-sha256) [ "$#" -ge 2 ] || { usage; exit 2; }; unsigned_manifest_sha256="$2"; shift 2 ;;
        --bootstrap-url) [ "$#" -ge 2 ] || { usage; exit 2; }; bootstrap_url="$2"; shift 2 ;;
        --installer-url) [ "$#" -ge 2 ] || { usage; exit 2; }; installer_url="$2"; shift 2 ;;
        --public-key-url) [ "$#" -ge 2 ] || { usage; exit 2; }; public_key_url="$2"; shift 2 ;;
        --pages-url) [ "$#" -ge 2 ] || { usage; exit 2; }; pages_url="$2"; shift 2 ;;
        *) usage; exit 2 ;;
        esac
    done

    for command_name in awk base64 bash cmp curl du find genisoimage git gpgv grep gzip install jq openssl \
        python3 qemu-img qemu-system-x86_64 readlink sed sha256sum sort stat; do
        require_command "${command_name}"
    done
    assert_forced_failure_result_contract
    [[ "${iso_path}" = /* && "${output_parent}" = /* ]] || die 'ISO and output paths must be absolute'
    case "${input_mode}:${scenario_id}" in
    staged:* | \
        public:marble-gnome-btrfs-luks2-plymouth-systemdboot) ;;
    *) die 'mode/scenario is outside the release acceptance matrix' ;;
    esac
    [[ "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'release version is malformed'
    [ "${release_version}" = 1.0.1 ] || die 'this frozen acceptance harness is release-pinned to 1.0.1'
    for digest in "${snapshot_sha256}" "${build_metadata_sha256}" "${unsigned_manifest_sha256}"; do
        [[ "${digest}" =~ ^[a-f0-9]{64}$ ]] || die 'release input SHA-256 is malformed'
    done
    if [ "${input_mode}" = staged ]; then
        [[ "${release_assets}" = /* ]] || die 'release assets path must be absolute in staged mode'
        [ -d "${release_assets}" ] && [ ! -L "${release_assets}" ] ||
            die 'release assets directory is unsafe'
        [ -z "${bootstrap_url}${installer_url}${public_key_url}${pages_url}" ] ||
            die 'public URLs are forbidden in staged mode'
    else
        [ -z "${release_assets}" ] || die 'local release assets are forbidden in public mode'
        [ "${bootstrap_url}" = "https://raw.githubusercontent.com/snaplyze/arch-linux/${release_version}/install.sh" ] ||
            die 'public bootstrap URL differs from the immutable release tag'
        [ "${installer_url}" = "https://github.com/snaplyze/arch-linux/releases/download/${release_version}/arch-linux-installer.sh" ] ||
            die 'public installer URL differs from the immutable Release asset'
        [ "${public_key_url}" = "https://github.com/snaplyze/arch-linux/releases/download/${release_version}/arch-linux.gpg" ] ||
            die 'public key URL differs from the immutable Release asset'
        [ "${pages_url}" = "https://snaplyze.github.io/arch-linux/repo/\$arch" ] ||
            die 'public Pages repository URL differs'
    fi
    [[ "${iso_sha256}" =~ ^[a-f0-9]{64}$ ]] || die 'accepted ISO SHA-256 is malformed'
    [ -f "${iso_path}" ] && [ ! -L "${iso_path}" ] || die 'accepted ISO is not a regular non-symlink file'
    [ -r /dev/kvm ] && [ -w /dev/kvm ] || die '/dev/kvm is not accessible'
    for input in "${qemu_bin}" "${qemu_img}" "${ovmf_code}" "${ovmf_vars_template}"; do
        [ -f "${input}" ] && [ ! -L "${input}" ] || die "required runtime input is unsafe: ${input}"
    done
    [ "$(sha256sum --binary -- "${iso_path}" | awk '{ print $1 }')" = "${iso_sha256}" ] ||
        die 'accepted ISO digest differs'
    [ "$(git -C "${repository_root}" status --porcelain=v1 --untracked-files=all)" = '' ] ||
        die 'run must start from a completely clean exact committed canonical checkout'
    for member in arch-linux-installer.sh "${harness_files[@]}"; do
        git -C "${repository_root}" ls-files --error-unmatch -- "${member}" >/dev/null ||
            die "runtime source is not tracked: ${member}"
    done

    bind_vm_source_identities
    installer_sha256="$(sha256sum --binary -- "${repository_root}/arch-linux-installer.sh" | awk '{ print $1 }')"
    bootstrap_sha256="$(sha256sum --binary -- "${repository_root}/install.sh" | awk '{ print $1 }')"
    run_id="${run_prefix}-$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 4)"
    if [ "${run_prefix}" = minimal ] || [ "${run_prefix}" = dualboot ]; then
        target_serial="ALI100M$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_MIN_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    elif [ "${run_prefix}" = stock ]; then
        target_serial="ALI100S$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_STK_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    elif [ "${run_prefix}" = btrfs ]; then
        target_serial="ALI100B$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_BTR_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    elif [ "${run_prefix}" = grub ] || [ "${run_prefix}" = luksgrub ]; then
        target_serial="ALI100G$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_GRB_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    elif [ "${run_prefix}" = luks ]; then
        target_serial="ALI100L$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_LUK_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    elif [ "${run_prefix}" = marble ] || [ "${run_prefix}" = marblestock ]; then
        target_serial="ALI100A$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_MAR_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    else
        target_serial="ALI100R$(openssl rand -hex 6 | tr '[:lower:]' '[:upper:]')"
        target_model="ALI_LGR_$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    fi
    [[ "${run_id}" =~ ^(minimal|dualboot|stock|btrfs|grub|luks|luksgrub|marble|marblestock)-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    runtime_password="$(openssl rand -hex 24)"
    [[ "${runtime_password}" =~ ^[a-f0-9]{48}$ ]] || die 'generated password is malformed'
    [ ! -e "${output_parent}" ] && install -d -m 0700 -- "${output_parent}"
    [ -d "${output_parent}" ] && [ ! -L "${output_parent}" ] || die 'output root is unsafe'
    [ "$(stat -Lc '%u:%a' -- "${output_parent}")" = "$(id -u):700" ] || die 'output root must be owned and mode 0700'
    bind_frozen_inputs
    run_root="${output_parent}/${run_id}"
    [ ! -e "${run_root}" ] || die 'new run root already exists'
    install -d -m 0700 -- "${run_root}" "${run_root}/evidence" "${run_root}/payload"
    runtime_dir="/run/user/$(id -u)/ali-qemu/${run_id}"
    [ "${#runtime_dir}" -lt 80 ] || die 'QEMU runtime socket root is too long'
    [ ! -e "${runtime_dir}" ] || die 'new QEMU runtime directory already exists'
    install -d -m 0700 -- "${runtime_dir}"
    evidence="${run_root}/evidence"
    assertions_file="${run_root}/assertions.tsv"
    : >"${assertions_file}"

    (
        cd -- "${repository_root}"
        sha256sum -- "${harness_files[@]}"
    ) >"${run_root}/harness.sha256"
    harness_sha256="$(sha256sum --binary -- "${run_root}/harness.sha256" | awk '{ print $1 }')"
    if [ "${input_mode}" = public ]; then
        printf 'harness_commit=%s\nharness_tree=%s\nrelease_commit=%s\nrelease_tree=%s\n' \
            "${harness_commit}" "${harness_tree}" "${source_commit}" "${source_tree}" \
            >"${run_root}/harness-source.txt"
    fi
    if [ "${input_mode}" = staged ]; then
        verify_staged_release_input
        prepare_signed_repository_input
        snapshot_verification='INDEPENDENT_PASS'
    else
        load_release_trust "${repository_root}/repository/trust"
        snapshot_verification='PENDING_PUBLIC_RELEASE_PAGES_BINDING'
    fi
    if [ "${input_mode}" = staged ] && is_marble_scenario; then
        start_marble_repository_runtime
    fi
    printf 'scenario=%s\ninput_mode=%s\nrelease_version=%s\nrun_id=%s\nsource_commit=%s\nsource_tree=%s\ninstaller_sha256=%s\nbootstrap_sha256=%s\nharness_sha256=%s\niso_sha256=%s\nsnapshot_sha256=%s\nbuild_metadata_sha256=%s\nunsigned_manifest_sha256=%s\ntarget_serial=%s\ntarget_vendor=SNAPLYZE\ntarget_model=%s\n' \
        "${scenario_id}" "${input_mode}" "${release_version}" "${run_id}" \
        "${source_commit}" "${source_tree}" "${installer_sha256}" "${bootstrap_sha256}" \
        "${harness_sha256}" "${iso_sha256}" "${snapshot_sha256}" \
        "${build_metadata_sha256}" "${unsigned_manifest_sha256}" \
        "${target_serial}" "${target_model}" >"${run_root}/identity.txt"
    printf 'repository_public_key_sha256=%s\nrepository_primary_fingerprint=%s\nrepository_signing_fingerprint=%s\nrepository_package_set_sha256=%s\n' \
        "${repository_public_key_sha256}" "${repository_primary_fingerprint}" \
        "${repository_signing_fingerprint}" "${repository_package_set_sha256}" \
        >>"${run_root}/identity.txt"
    [ "${input_mode}" != staged ] || append_repository_identity
    if [ "${input_mode}" = staged ] && is_marble_scenario; then
        printf 'repository_server_port=%s\n' "${repository_server_port}" >>"${run_root}/identity.txt"
    elif [ "${input_mode}" = public ]; then
        printf 'bootstrap_url=%s\ninstaller_url=%s\npublic_key_url=%s\npages_url=%s\n' \
            "${bootstrap_url}" "${installer_url}" "${public_key_url}" "${pages_url}" \
            >>"${run_root}/identity.txt"
    fi
    sha256sum -- "${qemu_bin}" "${qemu_img}" "${ovmf_code}" "${ovmf_vars_template}" \
        >"${run_root}/runtime-inputs.sha256"
    "${qemu_bin}" --version >"${run_root}/qemu-version.txt"
    cp --reflink=never -- "${ovmf_vars_template}" "${run_root}/OVMF_VARS.fd"
    sha256sum -- "${run_root}/OVMF_VARS.fd" >"${run_root}/OVMF_VARS.initial.sha256"

    install -m 0555 -- "${script_dir}/guest/bootstrap.sh" "${run_root}/payload/b"
    if [ "${input_mode}" = staged ]; then
        install -m 0555 -- "${repository_root}/arch-linux-installer.sh" \
            "${run_root}/payload/arch-linux-installer.sh"
    else
        printf '%s\n' \
            'schema=1' \
            "bootstrap_url=${bootstrap_url}" \
            "installer_url=${installer_url}" \
            "public_key_url=${public_key_url}" \
            "pages_url=${pages_url}" \
            >"${run_root}/payload/public.contract"
        chmod 0444 -- "${run_root}/payload/public.contract"
    fi
    if [ "${input_mode}" = staged ] && is_marble_scenario; then
        install -m 0444 -- "${repository_ca_file}" "${run_root}/payload/acceptance-ca.crt"
        install -m 0444 -- "${run_root}/repository.contract" \
            "${run_root}/payload/repository.contract"
    fi
    {
        printf 'SCENARIO=%s\nRUN_ID=%s\nTARGET_SERIAL=%s\nTARGET_VENDOR=SNAPLYZE\nTARGET_MODEL=%s\n' \
            "${scenario_id}" "${run_id}" "${target_serial}" "${target_model}"
        printf 'HOSTNAME=%s\nUSERNAME=vmtest\nMICROCODE=none\n' "${guest_hostname}"
        printf 'SOURCE_COMMIT=%s\nSOURCE_TREE=%s\nINSTALLER_SHA256=%s\nHARNESS_SHA256=%s\nISO_SHA256=%s\n' \
            "${source_commit}" "${source_tree}" "${installer_sha256}" "${harness_sha256}" "${iso_sha256}"
        printf 'INPUT_MODE=%s\nRELEASE_VERSION=%s\nBOOTSTRAP_SHA256=%s\nSNAPSHOT_SHA256=%s\nBUILD_METADATA_SHA256=%s\nUNSIGNED_MANIFEST_SHA256=%s\nPUBLIC_KEY_SHA256=%s\nPRIMARY_FINGERPRINT=%s\nSIGNING_SUBKEY_FINGERPRINT=%s\n' \
            "${input_mode}" "${release_version}" "${bootstrap_sha256}" "${snapshot_sha256}" \
            "${build_metadata_sha256}" "${unsigned_manifest_sha256}" \
            "${repository_public_key_sha256}" "${repository_primary_fingerprint}" \
            "${repository_signing_fingerprint}"
    } >"${run_root}/payload/IDENTITY"
    (
        cd -- "${run_root}/payload"
        if [ "${input_mode}" = public ]; then
            sha256sum -- IDENTITY b public.contract >MANIFEST.sha256
        elif is_marble_scenario; then
            sha256sum -- IDENTITY acceptance-ca.crt arch-linux-installer.sh b \
                repository.contract >MANIFEST.sha256
        else
            sha256sum -- IDENTITY arch-linux-installer.sh b >MANIFEST.sha256
        fi
        sha256sum --check --strict MANIFEST.sha256 >/dev/null
    )
    chmod 0444 -- "${run_root}/payload/IDENTITY" "${run_root}/payload/MANIFEST.sha256"
    genisoimage -quiet -R -J -V ALIPAY -o "${run_root}/payload.iso" "${run_root}/payload"
    sha256sum -- "${run_root}/payload.iso" >"${run_root}/payload.iso.sha256"
    "${qemu_img}" create -q -f qcow2 -o compat=1.1,lazy_refcounts=on,cluster_size=2M \
        -- "${run_root}/target.qcow2" "${target_size}"
    "${qemu_img}" info --output=json -- "${run_root}/target.qcow2" >"${evidence}/initial-qemu-img-info.json"
    jq -e --argjson size "${target_size_bytes}" \
        '.format == "qcow2" and .["virtual-size"] == $size and (has("backing-filename") | not)' \
        "${evidence}/initial-qemu-img-info.json" >/dev/null || die 'new target qcow2 identity is invalid'

    current_phase='install-archiso'
    launch_qemu install true
    sleep 60
    hmp_request type "${bootstrap_command}"
    [ "${scenario_id}" != minimal-dualboot-ext4-systemdboot ] || bootstrap_timeout=1800
    wait_for_marker "${evidence}/install-serial.log" \
        "${marker_prefix}_QEMU_READY run_id=${run_id} scenario=${scenario_id}" "${bootstrap_timeout}" ||
        die 'Arch ISO bootstrap did not reach the installer'
    wait_for_marker "${evidence}/install-serial.log" 'Enter Password' 300 ||
        die 'installer did not reach its runtime-only password prompt'
    send_password
    set +e
    wait_for_install_outcome "${evidence}/install-serial.log" \
        "${marker_prefix}_QEMU_INSTALL_COMPLETE run_id=${run_id} scenario=${scenario_id} powering_off=yes" \
        'Show Logs?' 7200
    install_outcome=$?
    set -e
    if [ "${install_outcome}" -eq 2 ]; then
        sleep 3
        die 'actual installer reported failure; its raw log was captured on the diagnostic serial port'
    fi
    [ "${install_outcome}" -eq 0 ] || die 'actual installer did not complete within two hours'
    wait_qemu_exit install 300
    grep -aFq -- "${marker_prefix}_QEMU_INSTALLER_EXIT status=0" "${evidence}/install-serial.log" ||
        die 'installer zero-exit marker is missing'
    "${qemu_img}" check -- "${run_root}/target.qcow2" >"${evidence}/postinstall-qemu-img-check.txt"
    if [ "${input_mode}" = public ]; then
        record_assertion accepted-public-bootstrap-installer \
            'the official Arch ISO downloaded the immutable public bootstrap, verified Release installer/key/signature bytes, then executed the exact accepted public installer SHA-256'
    elif is_marble_scenario; then
        record_assertion accepted-iso-exact-installer \
            'the accepted signed Arch ISO booted under KVM/OVMF and executed the exact committed installer bytes from the read-only source-bound payload'
    else
        record_assertion accepted-official-arch-iso 'accepted signed Arch ISO booted under KVM and OVMF into its UEFI live environment'
        record_assertion actual-installer-executes 'exact committed installer bytes executed from the read-only payload and exited zero'
    fi
    if ! is_btrfs_scenario; then
        record_assertion install-completes 'installer reached its normal successful completion and powered off the live guest'
    fi

    current_phase='firstboot'
    launch_qemu firstboot false
    if is_luks_scenario; then
        capture_and_unlock_luks_prompt firstboot
    fi
    wait_qga || die 'first boot QEMU guest agent did not become ready'
    if is_marble_scenario; then
        run_marble_acceptance
    elif [[ "${scenario_id}" = minimal-* ]]; then
        qga_verify firstboot firstboot-verify
        first_boot_id="${last_boot_id}"
        capture_screen firstboot-tty
        record_assertion uefi-gpt-ext4-systemd-boot 'installed disk booted in UEFI with GPT, ext4 root, and systemd-boot'
        record_assertion minimal-tty-profile 'desktop and shell enhancement are off; multi-user target and tty1 getty are active'
        record_assertion installed-tty-boot 'installed qcow2 reached the tty1 login console'
        record_assertion network-works 'NetworkManager is active and Arch Linux DNS resolution succeeds'
        record_assertion failed-units-zero-firstboot 'systemctl --failed is empty on first boot'
        current_phase='full-system-update'
        qga_verify update firstboot-update
        record_assertion pacman-syu 'pacman -Syu completed successfully inside the installed guest'
        schedule_transition reboot firstboot
        wait_qemu_exit firstboot-reboot 300

        current_phase='postreboot'
        launch_qemu postreboot false
        wait_qga || die 'post-reboot QEMU guest agent did not become ready'
        qga_verify postreboot postreboot-verify
        post_boot_id="${last_boot_id}"
        capture_screen postreboot-tty
        [ "${first_boot_id}" != "${post_boot_id}" ] || die 'reboot did not produce a new kernel boot identity'
        record_assertion reboot-and-tty-return 'guest rebooted with a new boot id and tty1 returned'
        record_assertion failed-units-zero-postreboot 'systemctl --failed remains empty after reboot'
        if [ "${scenario_id}" = minimal-dualboot-ext4-systemdboot ]; then
            grep -aFq "MINIMAL_QEMU_NEIGHBOR_PRESERVED run_id=${run_id}" \
                "${evidence}/install-serial.log" || die 'neighbor preservation check is absent'
            qga_verify neighbor-select neighbor-select
            schedule_transition reboot postreboot
            wait_qemu_exit neighbor-transition 300
            current_phase='neighbor-boot'
            launch_qemu neighbor false
            wait_qga || die 'existing neighboring Linux did not boot'
            qga_verify neighbor neighbor-verify
            capture_screen neighbor-tty
            record_assertion dual-boot-neighbor-preserved \
                'installer reused the EFI partition and root partition3; neighboring Linux data and boot files were preserved'
            record_assertion dual-boot-both-systems-boot \
                'the installed Arch system and the preserved neighboring Linux both booted through systemd-boot'
            shutdown_phase=neighbor
        fi
        current_phase='clean-shutdown'
        schedule_transition poweroff "${shutdown_phase}"
        wait_qemu_exit "${shutdown_phase}-poweroff" 300
        record_assertion clean-shutdown 'installed guest completed a systemd poweroff without manual repair'
        record_assertion qemu-exits 'install, reboot, and final poweroff QEMU processes all exited zero'
    else
        qga_verify prelogin firstboot-prelogin
        first_boot_id="${last_boot_id}"
        if is_encrypted_grub_scenario; then
            record_assertion uefi-gpt-luks2-btrfs-grub 'installed disk booted with UEFI/GPT, a LUKS2 root container, decrypted Btrfs, and the ArchLinux GRUB EFI target'
            record_assertion stock-plymouth-no-repair 'Plymouth and Stock GNOME/GDM are on while shell enhancement, Snapper, and Btrfs Assistant are off; installation required no manual guest repair'
            record_assertion luks-partition-mapper-binding 'cryptroot maps exactly to partition 2 of the accepted serial/model-bound target disk'
            record_assertion encrypted-btrfs-subvolumes-fstab 'decrypted Btrfs has @, @home, and @snapshots with the required mounts, policy, health, and matching fstab entries'
            record_assertion systemd-sd-encrypt-plymouth-grub-initramfs 'mkinitcpio and the installed initramfs contain the accepted systemd, sd-encrypt, Plymouth, and GRUB/Btrfs path'
            record_assertion grub-efi-archlinux-target 'the regular ArchLinux GRUB EFI image exists and BootCurrent resolves to its exact firmware target'
            record_assertion grub-config-encrypted-root-contract 'grub.cfg is regular and syntax-valid and every Linux entry has exactly one matching rd.luks.name, cryptroot, Btrfs subvolume, and filesystem contract without stale PARTUUID root'
            record_assertion first-grub-plymouth-luks-framebuffer 'the first installed boot selected ArchLinux GRUB and reached the LUKS unlock path'
            record_assertion first-luks-unlock-to-gdm 'virtual keyboard unlock succeeded without credential evidence and continued to the real Stock Wayland GDM greeter'
        elif is_luks_scenario; then
            record_assertion uefi-gpt-btrfs-luks2-systemd-boot 'installed disk booted with UEFI/GPT, a LUKS2 root container, decrypted Btrfs, and systemd-boot'
            record_assertion stock-plymouth-profile 'Plymouth is on while Stock GNOME/GDM is active and shell enhancement, Snapper, and Btrfs Assistant are off'
            record_assertion install-completes-no-repair 'the exact installer completed and powered off without any manual guest repair'
            record_assertion luks-partition-mapper-binding 'cryptroot maps exactly to partition 2 of the accepted serial/model-bound target disk'
            record_assertion encrypted-btrfs-subvolumes-fstab 'decrypted Btrfs has @, @home, and @snapshots with the required mounts, policy, and matching fstab entries'
            record_assertion systemd-sd-encrypt-plymouth-initramfs 'mkinitcpio hooks and the installed initramfs image contain the accepted systemd, sd-encrypt, and Plymouth path'
            record_assertion encrypted-systemd-boot-contract 'both boot entries and the running kernel contain one matching rd.luks.name, mapper root, and Btrfs arguments without stale PARTUUID root'
            record_assertion first-plymouth-luks-framebuffer 'the first installed boot reached the Plymouth LUKS unlock path'
            record_assertion first-luks-unlock-to-gdm 'virtual keyboard unlock succeeded and the installed system continued to the real Stock Wayland GDM greeter'
        elif is_grub_scenario; then
            record_assertion uefi-gpt-btrfs-grub-encryption-off 'installed disk booted with UEFI/GPT, Btrfs, GRUB, and encryption explicitly off'
            record_assertion stock-install-completes-no-repair 'the exact installer completed with Stock GNOME/GDM and powered off without any manual guest repair'
            record_assertion grub-packages-from-arch 'grub and grub-btrfs are installed from the accepted Arch package transaction'
            record_assertion grub-efi-archlinux-target 'the regular ArchLinux GRUB EFI image exists and BootCurrent resolves to its exact firmware target'
            record_assertion grub-config-valid-root-contract 'grub.cfg is regular, syntax-valid, uses /vmlinuz-linux, and every Linux entry has exactly the accepted PARTUUID/Btrfs root contract'
            record_assertion installed-grub-boot-and-btrfs-contract 'the installed qcow2 actually booted through GRUB into the accepted Btrfs @ root with matching running kernel arguments'
            record_assertion btrfs-subvolumes-fstab-health 'the @, @home, and @snapshots mounts, fstab mapping, compression policy, and Btrfs health are correct'
            record_assertion grub-btrfsd-qkk-firstboot 'grub-btrfsd is enabled and active and pacman -Qkk reports zero altered files for grub and grub-btrfs'
        elif is_btrfs_scenario; then
            record_assertion uefi-gpt-btrfs-systemd-boot-encryption-off 'installed disk booted with UEFI/GPT, Btrfs, systemd-boot, and encryption explicitly off'
            record_assertion stock-profile-no-snapper-assistant 'Stock GNOME/GDM is active with shell enhancement, Snapper, and Btrfs Assistant explicitly off'
            record_assertion install-completes-no-repair 'the exact installer completed and powered off without any manual guest repair'
            record_assertion btrfs-root 'the installed root filesystem is Btrfs rather than ext4'
            record_assertion btrfs-expected-subvolumes 'the expected @, @home, and @snapshots subvolumes exist'
            record_assertion btrfs-mounted-subvolumes 'root, home, and snapshots are mounted from /@, /@home, and /@snapshots on the accepted root partition'
            record_assertion btrfs-policy-and-fstab 'active mounts and matching fstab entries retain noatime, zstd compression, and the expected subvolume mapping'
            record_assertion systemd-boot-btrfs-root-contract 'systemd-boot and the running kernel use the exact root PARTUUID with rootflags=subvol=@ and rootfstype=btrfs'
            record_assertion graphical-target-and-gdm 'graphical.target and gdm.service are active and the real Stock Wayland greeter reached the login screen'
        else
            record_assertion uefi-gpt-ext4-systemd-boot 'installed disk booted in UEFI with GPT, ext4 root, and systemd-boot'
            record_assertion stock-gnome-profile 'desktop is on with Stock GNOME and Stock GDM; shell enhancement is off'
            record_assertion graphical-target 'the installed system reached active graphical.target'
            record_assertion stock-gdm-greeter 'gdm.service is active and its real Wayland greeter session reached the login screen'
        fi
        hmp_request key ret
        sleep 3
        capture_screen firstboot-gdm-password
        hmp_type_password
        printf 'phase=firstlogin\ntransport=hmp-virtual-keyboard\ncredential_length=48\nsubmit_key=enter\nsecret_recorded=no\n' \
            >"${evidence}/firstboot-login-input.txt"
        qga_verify firstlogin firstboot-login
        capture_screen firstboot-desktop
        if is_encrypted_grub_scenario; then
            record_assertion real-gdm-password-login-first 'a real gdm-password login reached the exact target-user GNOME/Wayland session after the LUKS unlock'
            record_assertion stock-network-dns-zero-failures 'the Stock desktop baseline, NetworkManager, DNS, and zero-failed-unit contract are all green after the first real login'
            record_assertion luks2-btrfs-health 'LUKS2 type, UUID, cipher, mapper binding and Btrfs readback are correct with every device error counter zero'
        elif is_luks_scenario; then
            record_assertion real-gdm-password-login-first 'a real gdm-password login reached the exact target-user GNOME/Wayland session after the LUKS unlock'
            record_assertion stock-desktop-baseline 'Ptyxis, seven Stock extensions, Bibata, Adwaita, Stock GDM, and Marble inactivity remain correct'
            record_assertion network-dns-failed-units-zero 'NetworkManager and DNS work and systemctl --failed is empty after the first real login'
            record_assertion luks2-btrfs-health 'LUKS2 type, UUID, cipher, mapper binding and Btrfs readback are correct with every device error counter zero'
        elif is_grub_scenario; then
            record_assertion real-gdm-password-login-first 'virtual keyboard password input authenticated through gdm-password into the target-user GNOME/Wayland session'
            record_assertion stock-desktop-baseline 'Ptyxis, seven Stock extensions, Bibata, Adwaita, Stock GDM, and Marble inactivity remain correct'
            record_assertion network-dns-failed-units-zero 'NetworkManager and DNS work and systemctl --failed is empty after the first real login'
        elif is_btrfs_scenario; then
            record_assertion real-gdm-password-login-first 'virtual keyboard password input authenticated through gdm-password into the target-user GNOME/Wayland session'
            record_assertion stock-desktop-baseline 'Ptyxis, seven Stock extensions, Bibata, Adwaita, Stock GDM, and Marble inactivity remain correct'
            record_assertion network-dns 'NetworkManager is active and Arch Linux DNS resolution succeeds'
            record_assertion failed-units-zero-firstlogin 'systemctl --failed is empty after the first real login'
            record_assertion btrfs-health 'Btrfs filesystem readback succeeds and every device error counter is zero'
        else
            record_assertion real-gdm-password-login-first 'virtual keyboard password input authenticated through a gdm-password user session'
            record_assertion gnome-wayland-first 'the resulting target-user desktop session is GNOME on Wayland'
            record_assertion target-user-session-first 'the active graphical session has the exact vmtest user and UID identity'
            record_assertion ptyxis-console-contract 'Ptyxis is installed and executable; GNOME Console is absent'
            record_assertion stock-extensions-enabled 'all seven required Stock extension UUIDs are installed and effectively enabled after login'
            record_assertion bibata-stock-no-marble 'Bibata is effective while Stock GTK, icons, Shell and GDM remain free of Marble project activation'
            record_assertion network-dns 'NetworkManager is active and Arch Linux DNS resolution succeeds'
            record_assertion failed-units-zero-firstlogin 'systemctl --failed is empty after the first real login'
        fi
        if is_encrypted_grub_scenario; then
            record_assertion locale-keyboard-formats-shortcuts \
                'Stock retained en_US.UTF-8 locale and Formats, primary Latin plus Russian layouts, both GNOME switch directions, and all 12 Ptyxis Latin/Cyrillic shortcut pairs'
        fi
        qga_verify lock firstboot-lock-start
        hmp_request key ret
        sleep 2
        capture_screen firstboot-lock
        hmp_type_password
        qga_verify unlock firstboot-lock-finish
        record_assertion lock-password-unlock \
            'the real Stock GNOME session entered LockedHint=yes and only HMP password input restored the same gdm-password Wayland session'
        current_phase='full-system-update'
        qga_verify update firstboot-update
        record_assertion pacman-syu 'pacman -Syu completed successfully inside the installed guest'
        if is_encrypted_grub_scenario; then
            record_assertion grub-regeneration-qkk 'post-update grub-mkconfig succeeds, its configuration is syntax-valid and encrypted-root-safe, and pacman -Qkk remains clean for grub and grub-btrfs'
        elif is_grub_scenario; then
            record_assertion grub-regeneration 'grub-mkconfig succeeds after the update and its configuration is syntax-valid and root-safe'
            record_assertion grub-qkk-clean-after-regeneration 'pacman -Qkk grub grub-btrfs remains at zero altered files after GRUB regeneration'
        fi
        schedule_transition reboot firstboot
        wait_qemu_exit firstboot-reboot 300

        current_phase='postreboot'
        launch_qemu postreboot false
        if is_luks_scenario; then
            capture_and_unlock_luks_prompt postreboot false
        fi
        wait_qga || die 'post-reboot QEMU guest agent did not become ready'
        qga_verify postreboot-prelogin postreboot-prelogin
        post_boot_id="${last_boot_id}"
        [ "${first_boot_id}" != "${post_boot_id}" ] || die 'reboot did not produce a new kernel boot identity'
        if is_encrypted_grub_scenario; then
            record_assertion reboot-and-second-grub-plymouth-luks 'reboot changed boot ID, selected the same ArchLinux GRUB target, and repeated the LUKS unlock'
        elif is_luks_scenario; then
            record_assertion reboot-and-second-plymouth-luks 'reboot changed boot ID and repeated the LUKS unlock'
        elif is_grub_scenario; then
            record_assertion reboot-through-grub 'reboot changed boot ID, booted through the same ArchLinux GRUB target, and returned to Stock GDM with the accepted root contract'
        elif is_btrfs_scenario; then
            record_assertion reboot-preserves-btrfs 'the reboot changed boot ID, returned to Stock GDM, and preserved the Btrfs mounts, subvolumes, fstab, boot entry, and health contract'
        else
            record_assertion reboot-new-boot-id 'the reboot produced a new kernel boot identity and returned to Stock GDM'
        fi
        hmp_request key ret
        sleep 3
        hmp_type_password
        printf 'phase=secondlogin\ntransport=hmp-virtual-keyboard\ncredential_length=48\nsubmit_key=enter\nsecret_recorded=no\n' \
            >"${evidence}/postreboot-login-input.txt"
        qga_verify secondlogin postreboot-login
        if is_encrypted_grub_scenario; then
            record_assertion second-unlock-gdm-login 'the second keyboard LUKS unlock succeeded and a second real Stock GDM password login reached GNOME/Wayland'
            record_assertion reboot-preserves-encrypted-grub-contract 'failed units remain zero and the LUKS2 mapper, encrypted GRUB config/cmdline/EFI/Qkk, Btrfs subvolumes, fstab, and health contract remain correct after reboot'
        elif is_luks_scenario; then
            record_assertion second-unlock-gdm-login 'the second keyboard LUKS unlock succeeded, Stock GDM returned, and a second real password login reached GNOME/Wayland'
            record_assertion reboot-preserves-encrypted-contract 'failed units remain zero and the LUKS2 mapper, Btrfs subvolumes, fstab, boot entries, and health contract are unchanged after reboot'
        elif is_grub_scenario; then
            record_assertion real-gdm-password-login-second 'Stock GDM accepted a second real password login into the target-user GNOME/Wayland session'
            record_assertion postreboot-grub-btrfs-failed-units 'failed units remain zero and the GRUB EFI/config/cmdline/Qkk plus Btrfs contract remain correct after reboot'
        elif is_btrfs_scenario; then
            record_assertion gdm-second-login-and-zero-failures 'Stock GDM returned, accepted a second real password login into GNOME/Wayland, and systemctl --failed remains empty'
        else
            record_assertion gdm-second-real-login 'Stock GDM accepted a second virtual-keyboard password login into GNOME on Wayland'
            record_assertion failed-units-zero-secondlogin 'systemctl --failed remains empty after reboot and the second login'
        fi
        current_phase='clean-shutdown'
        schedule_transition poweroff postreboot
        wait_qemu_exit postreboot-poweroff 300
    fi

    current_phase='final-image-check'
    "${qemu_img}" check -- "${run_root}/target.qcow2" >"${evidence}/final-qemu-img-check.txt"
    "${qemu_img}" info --output=json -- "${run_root}/target.qcow2" >"${evidence}/final-qemu-img-info.json"
    sha256sum -- "${run_root}/OVMF_VARS.fd" >"${run_root}/OVMF_VARS.final.sha256"
    final_qemu_matches="$(find_run_qemu_processes "${run_id}")"
    [ -z "${final_qemu_matches}" ] || die "QEMU process remains: ${final_qemu_matches}"
    printf 'no matching QEMU process remains for %s\n' "${run_id}" >"${evidence}/no-qemu-process.txt"
    stop_repository_server
    rm -f -- "${runtime_dir}/repository.port" "${runtime_dir}/repository-server.csr" \
        "${runtime_dir}/repository-server.ext" "${runtime_dir}/qga.sock" \
        "${runtime_dir}/hmp.sock" "${runtime_dir}/qmp.sock" \
        "${runtime_dir}/serial.sock"
    [ -z "$(find "${runtime_dir}" -mindepth 1 -print -quit)" ] ||
        die 'run-owned runtime directory retains residue'
    rmdir -- "${runtime_dir}"
    runtime_dir=''
    if is_marble_scenario; then
        record_assertion clean-poweroff-image-health-hygiene \
            'clean poweroff exited QEMU zero; qemu-img was healthy; no run-owned QEMU/server process, VM workspace or credential artifact remained'
    elif [[ "${scenario_id}" = minimal-* ]]; then
        record_assertion qemu-img-check-and-no-process 'final qemu-img check passed and no run-owned QEMU process remains'
    else
        record_assertion clean-shutdown-image-no-qemu 'clean poweroff exited QEMU zero; qemu-img check passed and no run-owned QEMU remains'
    fi
    if [ "${input_mode}" = public ]; then
        [ "${snapshot_verification}" = PUBLIC_RELEASE_PAGES_BINDING_PASS ] ||
            die 'public Release-to-Pages snapshot binding did not pass'
    fi
    verify_frozen_source_unchanged
    remove_heavy_run_inputs
    finalize_run_storage
    build_result PASS 0 -
    enforce_evidence_budget
    build_result PASS 0 -
    [ "$(du -sb -- "${output_parent}" | awk '{ print $1 }')" = "${evidence_size_bytes}" ] ||
        die 'final evidence size changed after writing the structured result'
    runtime_password=''
    unset runtime_password
    current_phase='complete'
    printf 'PASS run_id=%s run_root=%s result=%s\n' \
        "${run_id}" "${run_root}" "${run_root}/result.json"
}

main "$@"
