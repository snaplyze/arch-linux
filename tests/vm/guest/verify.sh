#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
export LC_ALL=C

marker_prefix=''

guest_error() {
    local status=$? line="$1" command="$2"
    trap - ERR
    if declare -F restore_extension_probe_settings >/dev/null &&
        [ -n "${probe_state:-}" ] && [ -f "${probe_state}/settings.json" ]; then
        restore_extension_probe_settings >/dev/null 2>&1 || true
    fi
    printf '%s_QEMU_GUEST_FAIL phase=%s line=%s status=%s command=%q\n' \
        "${marker_prefix:-UNKNOWN}" "${phase:-preflight}" "${line}" "${status}" "${command}" >&2
    exit "${status}"
}
trap 'guest_error "$LINENO" "$BASH_COMMAND"' ERR

{ [ "$#" -eq 25 ] || [ "$#" -eq 26 ] || [ "$#" -eq 27 ]; } || { printf 'usage: verify.sh PHASE SERIAL VENDOR MODEL USERNAME SCENARIO RUN_ID REPOSITORY_PRIMARY REPOSITORY_SIGNING INPUT_MODE RELEASE_VERSION TARGET_DISK_METADATA PAGES_URL PUBLIC_KEY_URL SNAPSHOT_SHA256 SOURCE_COMMIT SOURCE_TREE INSTALLER_SHA256 PACKAGE_SET_SHA256 BUILD_METADATA_SHA256 UNSIGNED_MANIFEST_SHA256 PUBLIC_KEY_SHA256 LEGACY_RELEASE_VERSION LEGACY_PROFILE_VERSION LEGACY_GTK3_VERSION [MEDIA_QUALIFICATION [GDM_WORKER_BASELINE]]\n' >&2; exit 2; }
readonly phase="$1" expected_serial="$2" expected_vendor="$3" expected_model="$4"
readonly username="$5" scenario="$6" run_id="$7" repository_primary="$8"
readonly repository_signing="$9" input_mode="${10}" release_version="${11}"
readonly target_disk_metadata="${12}" pages_url="${13}" public_key_url="${14}"
readonly snapshot_sha256="${15}" source_commit="${16}" source_tree="${17}"
readonly installer_sha256="${18}" package_set_sha256="${19}"
readonly build_metadata_sha256="${20}" unsigned_manifest_sha256="${21}" public_key_sha256="${22}"
readonly media_qualification="${26:-false}"
readonly gdm_worker_baseline="${27:--}"
readonly legacy_release_version="${23}" legacy_profile_version="${24}" legacy_gtk3_version="${25}"
case "${scenario}" in
minimal-ext4-systemdboot)
    marker_prefix='MINIMAL'
    case "${phase}" in media-readback-prepare | firstboot | update | postreboot) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100M[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_MIN_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^minimal-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
minimal-dualboot-ext4-systemdboot)
    marker_prefix='MINIMAL'
    case "${phase}" in firstboot | update | postreboot | neighbor-select | neighbor) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100M[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_MIN_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^dualboot-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-ext4-systemdboot)
    marker_prefix='STOCK'
    case "${phase}" in gdm-activation-baseline | gdm-activation-check | media-readback-prepare | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100S[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_STK_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^stock-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-systemdboot)
    marker_prefix='BTRFS'
    case "${phase}" in gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100B[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_BTR_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^btrfs-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-grub)
    marker_prefix='GRUB'
    case "${phase}" in gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin | snapshot-prepare | snapshot-prelogin | snapshot-login | snapshot-cleanup) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100G[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-luks2-plymouth-systemdboot)
    marker_prefix='LUKS'
    case "${phase}" in gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100L[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_LUK_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^luks-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-luks2-plymouth-grub)
    marker_prefix='LUKSGRUB'
    case "${phase}" in gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100G[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^luksgrub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
marble-gnome-btrfs-luks2-plymouth-systemdboot)
    marker_prefix='MARBLE'
    case "${phase}" in
    gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin | \
        extension-upgrade-* | extension-postreboot-* | \
        legacy-install | legacy-login | migration-update | migrated-login | \
        gnome51-baseline-install | gnome51-baseline-login | gnome51-upgrade | gnome51-upgraded-login | \
        gtk4-app-smoke-light | gtk4-app-smoke-dark | fresh-user-prepare | \
        fresh-user-login | fresh-user-logout | return-user-login | \
        helper-failure | helper-restored-prelogin | helper-restored-login | \
        deactivate-gdm | deactivated-prelogin | deactivated-login | \
        incompatible-fixture | incompatible-prelogin | incompatible-login | restore-marble | \
        restored-prelogin | restored-login | remove-marble | removed-prelogin | removed-login | \
        reinstall-marble | reinstalled-prelogin | reinstalled-login) ;;
    *) exit 2 ;;
    esac
    [[ "${expected_serial}" =~ ^ALI100A[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_MAR_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^marble-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm)
    marker_prefix='MARBLE'
    case "${phase}" in
    gdm-activation-baseline | gdm-activation-check | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin | \
        helper-failure | helper-restored-prelogin | helper-restored-login | \
        deactivate-gdm | deactivated-prelogin | deactivated-login | \
        incompatible-fixture | incompatible-prelogin | incompatible-login | restore-marble | \
        restored-prelogin | restored-login | remove-marble | removed-prelogin | removed-login | \
        reinstall-marble | reinstalled-prelogin | reinstalled-login) ;;
    *) exit 2 ;;
    esac
    [[ "${expected_serial}" =~ ^ALI100A[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_MAR_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^marblestock-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
*) exit 2 ;;
esac
[ "${expected_vendor}" = SNAPLYZE ]
[[ "${username}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
[[ "${repository_primary}" =~ ^[A-F0-9]{40}$ ]]
[[ "${repository_signing}" =~ ^[A-F0-9]{40}$ ]]
[ "${repository_primary}" != "${repository_signing}" ]
[[ "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
case "${target_disk_metadata}" in
absent | identified) ;;
*) exit 2 ;;
esac
[[ "${snapshot_sha256}" =~ ^[a-f0-9]{64}$ ]]
[[ "${source_commit}" =~ ^[a-f0-9]{40}$ ]]
[[ "${source_tree}" =~ ^[a-f0-9]{40}$ ]]
for expected_digest in "${installer_sha256}" "${package_set_sha256}" \
    "${build_metadata_sha256}" "${unsigned_manifest_sha256}" "${public_key_sha256}"; do
    [[ "${expected_digest}" =~ ^[a-f0-9]{64}$ ]]
done
case "${input_mode}" in
staged)
    [ "${phase}" != media-readback-prepare ]
    [ "${media_qualification}" = false ]
    [ "${pages_url}" = - ] && [ "${public_key_url}" = - ]
    if [ "${scenario}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ]; then
        [[ "${legacy_release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
        [[ "${legacy_profile_version}" =~ ^[A-Za-z0-9.+:_-]+$ ]]
        [[ "${legacy_gtk3_version}" =~ ^[A-Za-z0-9.+:_-]+$ ]]
    else
        [ "${legacy_release_version}${legacy_profile_version}${legacy_gtk3_version}" = --- ]
    fi
    ;;
public)
    case "${media_qualification}:${scenario}" in
    false:marble-gnome-btrfs-luks2-plymouth-systemdboot | \
        true:minimal-ext4-systemdboot | true:stock-gnome-ext4-systemdboot) ;;
    *) exit 2 ;;
    esac
    case "${phase}" in
    gdm-activation-baseline | gdm-activation-check | media-readback-prepare | firstboot | postreboot | prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;;
    *) exit 2 ;;
    esac
    [ "${pages_url}" = "https://snaplyze.github.io/arch-linux/repo/\$arch" ]
    [ "${public_key_url}" = "https://github.com/snaplyze/arch-linux/releases/download/${release_version}/arch-linux.gpg" ]
    [ "${legacy_release_version}${legacy_profile_version}${legacy_gtk3_version}" = --- ]
    ;;
*) exit 2 ;;
esac

trim_value() {
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

partition_name() {
    local disk="$1" number="$2"
    if [[ "${disk}" =~ [0-9]$ ]]; then
        printf '%sp%s' "${disk}" "${number}"
    else
        printf '%s%s' "${disk}" "${number}"
    fi
}

virtual_disk_is_virtio_backed() {
    local disk="$1" name device_path component
    name="${disk##*/}"
    [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    device_path="$(readlink -f -- "/sys/class/block/${name}")" || return 1
    case "${device_path}" in
    /sys/devices/*/block/"${name}") ;;
    *) return 1 ;;
    esac
    while IFS= read -r component; do
        [[ "${component}" =~ ^virtio[0-9]+$ ]] && return 0
    done < <(tr / '\n' <<<"${device_path#/sys/devices/}")
    return 1
}

is_btrfs_stock() {
    case "${scenario}" in
    stock-gnome-btrfs-systemdboot | stock-gnome-btrfs-grub | \
        stock-gnome-btrfs-luks2-plymouth-systemdboot | stock-gnome-btrfs-luks2-plymouth-grub | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm) return 0 ;;
    *) return 1 ;;
    esac
}

is_luks_stock() {
    case "${scenario}" in
    stock-gnome-btrfs-luks2-plymouth-systemdboot | stock-gnome-btrfs-luks2-plymouth-grub | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot | \
        marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm) return 0 ;;
    *) return 1 ;;
    esac
}

is_grub_stock() {
    case "${scenario}" in
    stock-gnome-btrfs-grub | stock-gnome-btrfs-luks2-plymouth-grub) return 0 ;;
    *) return 1 ;;
    esac
}

find_target() {
    local block_path device serial vendor model type
    local -a matches=()
    for block_path in /sys/class/block/*; do
        device="/dev/${block_path##*/}"
        [ -b "${device}" ] || continue
        type="$(lsblk -dnro TYPE -- "${device}" | trim_value)"
        [ "${type}" = disk ] || continue
        serial="$(lsblk -dnro SERIAL -- "${device}" | trim_value)"
        vendor="$(lsblk -dnro VENDOR -- "${device}" | trim_value)"
        model="$(lsblk -dnro MODEL -- "${device}" | trim_value)"
        if { [ "${target_disk_metadata}" = identified ] &&
            [ "${serial}" = "${expected_serial}" ] && [ "${vendor}" = "${expected_vendor}" ] &&
            [ "${model}" = "${expected_model}" ]; } ||
            { [ "${target_disk_metadata}" = absent ] && virtual_disk_is_virtio_backed "${device}" &&
            [ -z "${serial}" ]; }; then
            matches+=("${device}")
        fi
    done
    [ "${#matches[@]}" -eq 1 ]
    printf '%s' "${matches[0]}"
}

clean_kernel_command_line() {
    local required argument count
    local -a arguments=() required_arguments=(
        quiet vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3
        udev.log_level=3 systemd.show_status=false
    )
    read -ra arguments </proc/cmdline
    for required in "${required_arguments[@]}"; do
        count=0
        for argument in "${arguments[@]}"; do
            [ "${argument}" = "${required}" ] && count=$((count + 1))
        done
        [ "${count}" -eq 1 ]
    done
    if is_luks_stock; then
        count=0
        for argument in "${arguments[@]}"; do
            [ "${argument}" = splash ] && count=$((count + 1))
        done
        [ "${count}" -eq 1 ]
    fi
    for argument in "${arguments[@]}"; do
        case "${argument}" in
        splash) is_luks_stock || return 1 ;;
        console=* | rd.systemd.show_status=*) return 1 ;;
        esac
    done
}

session_property() {
    loginctl show-session "$1" --property="$2" --value
}

find_session() {
    local wanted_class="$1" wanted_name="$2" wanted_service="$3"
    local session_id
    local -a matches=()
    while read -r session_id _; do
        [ -n "${session_id}" ] || continue
        if [ "$(session_property "${session_id}" Class)" = "${wanted_class}" ] &&
            [ "$(session_property "${session_id}" Name)" = "${wanted_name}" ] &&
            [ "$(session_property "${session_id}" Service)" = "${wanted_service}" ]; then
            matches+=("${session_id}")
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s' "${matches[0]}"
    fi
}

session_name_exists() {
    local wanted_name="$1" session_id
    while read -r session_id _; do
        [ -n "${session_id}" ] || continue
        [ "$(session_property "${session_id}" Name)" != "${wanted_name}" ] || return 0
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    return 1
}

wait_for_greeter() {
    local deadline=$((SECONDS + 300)) candidate=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        candidate="$(find_session greeter gdm-greeter gdm-launch-environment 2>/dev/null || true)"
        if [ -n "${candidate}" ] && systemctl is-active --quiet gdm.service &&
            systemctl is-active --quiet graphical.target &&
            [ "$(session_property "${candidate}" Type)" = wayland ] &&
            [ "$(session_property "${candidate}" State)" = active ] &&
            [ "$(session_property "${candidate}" Remote)" = no ] &&
            ! session_name_exists "${username}"; then
            printf '%s' "${candidate}"
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_graphical_stack() {
    local deadline=$((SECONDS + 300))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if systemctl is-active --quiet gdm.service &&
            systemctl is-active --quiet graphical.target; then
            return 0
        fi
        sleep 1
    done
    return 1
}

gdm_password_worker_inventory() {
    python3 - "$@" "${run_id:-unknown}" "${phase:-unknown}" <<'GDM_WORKER_PY'
import os
import re
import sys
from pathlib import Path
proc, worker, daemon_text, group, daemon_exe, run_id, phase = sys.argv[1:]
class GuardError(Exception):
    pass

def inventory(proc, worker, daemon_text, group, daemon_exe):
    proc = Path(proc)
    daemon = int(daemon_text)
    if daemon <= 1 or not group.startswith("/") or ".." in group.split("/"):
        raise GuardError("daemon-identity")
    worker_identity = os.stat(worker)
    def record(pid):
        base = proc / str(pid)
        data = (base / "stat").read_text()
        fields = data.rsplit(") ", 1)[1].split()
        if int(data.split(" ", 1)[0]) != pid or len(fields) < 20:
            raise GuardError("process-stat")
        uid = re.search(r"^Uid:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$", (base / "status").read_text(), re.M)
        groups = [line[3:] for line in (base / "cgroup").read_text().splitlines() if line.startswith("0::")]
        if uid is None or [int(item) for item in uid.groups()] != [0, 0, 0, 0] :
            raise GuardError("process-owner")
        if len(groups) != 1:
            raise GuardError("process-cgroup")
        if groups[0] != group and not groups[0].startswith(group + "/"):
            raise GuardError("process-cgroup")
        executable = os.stat(base / "exe")
        return (int(fields[1]), int(fields[19]), groups[0], os.readlink(base / "exe"),
                executable.st_dev, executable.st_ino)
    before = record(daemon)
    if before[3] != daemon_exe:
        raise GuardError("daemon-executable")
    found = []
    for index, base in enumerate(proc.iterdir()):
        if index > 8192: raise GuardError("inventory-limit")
        if not base.name.isdecimal(): continue
        try:
            with (base / "cmdline").open("rb") as stream:
                argv0 = stream.read(8192).split(b"\0", 1)[0]
            if argv0 != b"gdm-session-worker [pam/gdm-password]": continue
            pid = int(base.name)
            identity = record(pid)
            if identity[0] != daemon: raise GuardError("worker-ancestry")
            if identity[3] != worker: raise GuardError("worker-executable")
            if identity[4:] != (worker_identity.st_dev, worker_identity.st_ino):
                raise GuardError("worker-executable-identity")
            if record(pid) != identity: raise GuardError("worker-identity-changed")
            found.append((pid, identity[1]))
        except FileNotFoundError:
            continue
    if record(daemon) != before: raise GuardError("daemon-identity-changed")
    if len(found) > 32: raise GuardError("worker-limit")
    print(str(daemon) + "." + str(before[1]), ",".join(str(pid) + "." + str(start) for pid, start in sorted(found)) or "none")
try:
    inventory(proc, worker, daemon_text, group, daemon_exe)
except GuardError as error:
    reason = error.args[0]
except (OSError, ValueError, IndexError, TypeError):
    reason = "readback-uncertain"
else:
    raise SystemExit(0)
if re.fullmatch(r"[A-Za-z0-9_-]{1,128}", run_id) is None:
    run_id = "unknown"
if re.fullmatch(r"[A-Za-z0-9_-]{1,64}", phase) is None:
    phase = "unknown"
print("GDM_ACTIVATION_DIAGNOSTIC run_id=" + run_id + " phase=" + phase +
      " step=worker-inventory reason=" + reason, file=sys.stderr)
raise SystemExit(1)

GDM_WORKER_PY
}

gdm_activation_failure() {
    printf 'GDM_ACTIVATION_DIAGNOSTIC run_id=%s phase=%s step=%s reason=%s\n' \
        "${run_id}" "${phase}" "$1" "$2" >&2
}

gdm_activation_probe() {
    local daemon daemon_exe group worker inventory identity workers activation greeter baseline_id worker_id new_worker=none permissions
    local new_count=0
    local -a baseline_ids=() worker_ids=()
    [ "${phase}" = gdm-activation-baseline ] || [ "${phase}" = gdm-activation-check ] || { gdm_activation_failure phase unsupported; return 1; }
    if [ "${phase}" = gdm-activation-baseline ]; then
        # Only initial baseline capture waits for a legitimate greeter startup.
        greeter="$(wait_for_greeter)" || { gdm_activation_failure greeter-ready timeout; return 1; }
    else
        greeter="$(find_session greeter gdm-greeter gdm-launch-environment)" || {
            gdm_activation_failure greeter-session readback-uncertain; return 1;
        }
    fi
    systemctl is-active --quiet gdm.service || { gdm_activation_failure gdm-service inactive; return 1; }
    systemctl is-active --quiet graphical.target || { gdm_activation_failure graphical-target inactive; return 1; }
    [[ "${greeter}" =~ ^[A-Za-z0-9_-]+$ ]] || { gdm_activation_failure greeter-session invalid; return 1; }
    [ "$(session_property "${greeter}" Type)" = wayland ] || { gdm_activation_failure greeter-type not-wayland; return 1; }
    [ "$(session_property "${greeter}" State)" = active ] || { gdm_activation_failure greeter-state not-active; return 1; }
    [ "$(session_property "${greeter}" Remote)" = no ] || { gdm_activation_failure greeter-remote not-local; return 1; }
    ! session_name_exists "${username}" || { gdm_activation_failure target-session already-present; return 1; }
    daemon="$(systemctl show gdm.service --property=MainPID --value)" || { gdm_activation_failure daemon-pid readback-uncertain; return 1; }
    [[ "${daemon}" =~ ^[1-9][0-9]*$ ]] || { gdm_activation_failure daemon-pid invalid; return 1; }
    group="$(systemctl show gdm.service --property=ControlGroup --value)" || { gdm_activation_failure daemon-cgroup readback-uncertain; return 1; }
    daemon_exe="$(readlink -e -- "/proc/${daemon}/exe")" || { gdm_activation_failure daemon-executable readback-uncertain; return 1; }
    [ "$(pacman -Qqo -- "${daemon_exe}")" = gdm ] || { gdm_activation_failure daemon-package not-gdm; return 1; }
    [ "$(stat -Lc '%u:%g' -- "${daemon_exe}")" = '0:0' ] || { gdm_activation_failure daemon-owner not-root; return 1; }
    permissions="$(find "${daemon_exe}" -perm /022 -print)" || { gdm_activation_failure daemon-permissions readback-uncertain; return 1; }
    [ -z "${permissions}" ] || { gdm_activation_failure daemon-permissions writable; return 1; }
    worker="$(pacman -Qlq gdm | awk '/\/gdm-session-worker$/ {path=$0; count++} END {if(count!=1) exit 1; print path}')" || { gdm_activation_failure worker-package ambiguous-or-missing; return 1; }
    [[ "${worker}" = /* ]] && [ -f "${worker}" ] && [ ! -L "${worker}" ] || { gdm_activation_failure worker-path not-canonical-regular; return 1; }
    [ "$(stat -Lc '%u:%g:%h' -- "${worker}")" = '0:0:1' ] || { gdm_activation_failure worker-metadata owner-or-link-count; return 1; }
    permissions="$(find "${worker}" -perm /022 -print)" || { gdm_activation_failure worker-permissions readback-uncertain; return 1; }
    [ -z "${permissions}" ] || { gdm_activation_failure worker-permissions writable; return 1; }
    inventory="$(gdm_password_worker_inventory /proc "${worker}" "${daemon}" "${group}" "${daemon_exe}")" || { gdm_activation_failure worker-inventory rejected; return 1; }
    read -r identity workers <<<"${inventory}" || { gdm_activation_failure worker-inventory invalid-output; return 1; }
    activation=baseline
    if [ "${phase}" = gdm-activation-check ]; then
        [[ "${gdm_worker_baseline}" = none || "${gdm_worker_baseline}" =~ ^[1-9][0-9]*\.[1-9][0-9]*(,[1-9][0-9]*\.[1-9][0-9]*)*$ ]] || {
            gdm_activation_failure worker-baseline invalid; return 1;
        }
        [ "${#gdm_worker_baseline}" -le 2048 ] || { gdm_activation_failure worker-baseline limit; return 1; }
        IFS=, read -ra baseline_ids <<<"${gdm_worker_baseline}"
        IFS=, read -ra worker_ids <<<"${workers}"
        for worker_id in "${worker_ids[@]}"; do
            [ "${worker_id}" != none ] || continue
            for baseline_id in "${baseline_ids[@]}"; do
                [ "${worker_id}" != "${baseline_id}" ] || break
            done
            [ "${worker_id}" != "${baseline_id}" ] || continue
            new_count=$((new_count + 1))
            new_worker="${worker_id}"
        done
        [ "${new_count}" -le 1 ] || {
            gdm_activation_failure worker-ambiguity multiple-new-workers
            return 1
        }
        activation=pending
        [ "${new_count}" -eq 0 ] || activation=started
    fi
    printf 'GDM_ACTIVATION_DIAGNOSTIC run_id=%s phase=%s daemon=%s greeter=%s worker_ids=%s new_worker=%s activation=%s\n' \
        "${run_id}" "${phase}" "${identity}" "${greeter}" "${workers}" "${new_worker}" "${activation}"
    emit_runtime_action_pass gdm-password-conversation-probe
}

wait_for_user_session() {
    wait_for_named_user_session "${username}"
}

wait_for_named_user_session() {
    local account="$1"
    local deadline=$((SECONDS + 300)) candidate=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        candidate="$(find_session user "${account}" gdm-password 2>/dev/null || true)"
        if [ -n "${candidate}" ] && [ "$(session_property "${candidate}" Type)" = wayland ] &&
            [ "$(session_property "${candidate}" State)" = active ] &&
            [ "$(session_property "${candidate}" Remote)" = no ] &&
            [ "$(session_property "${candidate}" Seat)" = seat0 ]; then
            printf '%s' "${candidate}"
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_gnome_shell() {
    local uid="$1" deadline=$((SECONDS + 300)) candidate=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if candidate="$(pgrep -u "${uid}" -x gnome-shell)" &&
            [[ "${candidate}" =~ ^[1-9][0-9]*$ ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
        sleep 1
    done
    return 1
}

run_in_user_session() {
    local uid="$1"
    shift
    run_in_named_user_session "${uid}" "${username}" "$@"
}

run_in_named_user_session() {
    local uid="$1" account="$2" gid
    shift 2
    gid="$(id -g "${account}")"
    /usr/bin/setpriv --reuid="${uid}" --regid="${gid}" --init-groups /usr/bin/env \
        HOME="/home/${account}" USER="${account}" LOGNAME="${account}" \
        XDG_RUNTIME_DIR="/run/user/${uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        "$@"
}

wait_for_desktop_initialization() {
    local autostart="$1" deadline=$((SECONDS + 300))
    # A real GDM session can be active before its one-time settings autostart finishes.
    # Observe completion only; never execute or repair the initializer from the test.
    while [ -e "${autostart}" ] && [ "${SECONDS}" -lt "${deadline}" ]; do
        [ -f "${autostart}" ] && [ ! -L "${autostart}" ] || return 1
        sleep 1
    done
    [ ! -e "${autostart}" ] && [ ! -L "${autostart}" ]
}

verify_graphical_locale_keyboard_contract() {
    local uid="$1" config="/home/${username}/installer.conf" init_dir="/home/${username}/.arch-linux/system" \
        expected_x11 actual key expected shell_pid
    wait_for_desktop_initialization "/home/${username}/.config/autostart/initialize.desktop"
    [ -f "${init_dir}/initialize.success" ] && [ ! -L "${init_dir}/initialize.success" ]
    [ "$(stat -c '%a' "${init_dir}/initialize.success")" = 600 ]
    [ "$(stat -c '%u' "${init_dir}/initialize.success")" = "${uid}" ]
    grep -qx 'status=success' "${init_dir}/initialize.success"
    [ -f "${init_dir}/initialize.log" ] && [ ! -L "${init_dir}/initialize.log" ]
    [ "$(stat -c '%a' "${init_dir}/initialize.log")" = 600 ]
    [ "$(stat -c '%u' "${init_dir}/initialize.log")" = "${uid}" ]
    grep -q 'Initialized' "${init_dir}/initialize.log"
    if grep -q 'Initialization failed' "${init_dir}/initialize.log"; then
        return 1
    fi
    [ -f "${config}" ] && [ ! -L "${config}" ]
    grep -qx 'ARCH_LINUX_LOCALE_LANG=en_US' "${config}"
    grep -qx 'ARCH_LINUX_LOCALE_GEN_LIST=en_US.UTF-8 UTF-8' "${config}"
    grep -qx 'ARCH_LINUX_VCONSOLE_KEYMAP=us' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_KEYBOARD_MODEL=pc105' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT=us' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=ru' "${config}"
    [ "$(cat -- /etc/locale.conf)" = 'LANG=en_US.UTF-8' ]
    [ "$(cat -- /etc/vconsole.conf)" = 'KEYMAP=us' ]
    locale -a | grep -Eiq '^en_US[.]utf-?8$'
    shell_pid="$(wait_for_gnome_shell "${uid}")"
    tr '\0' '\n' <"/proc/${shell_pid}/environ" | grep -qx 'LANG=en_US.UTF-8'

    expected_x11="$(printf '%s\n' \
        'Section "InputClass"' \
        '    Identifier "system-keyboard"' \
        '    MatchIsKeyboard "yes"' \
        '    Option "XkbLayout" "us,ru"' \
        '    Option "XkbModel" "pc105"' \
        '    Option "XkbVariant" ","' \
        '    Option "XkbOptions" "grp:alt_shift_toggle"' \
        'EndSection')"
    [ "$(cat -- /etc/X11/xorg.conf.d/00-keyboard.conf)" = "${expected_x11}" ]
    [ "$(run_in_user_session "${uid}" gsettings get org.gnome.system.locale region)" = \
        "'en_US.UTF-8'" ]
    actual="$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.input-sources sources)"
    [ "${actual// /}" = "[('xkb','us'),('xkb','ru')]" ]
    actual="$(run_in_user_session "${uid}" gsettings get \
        org.gnome.desktop.wm.keybindings switch-input-source)"
    [ "${actual// /}" = "['<Super>space','XF86Keyboard','<Alt>Shift_L','<Shift>Alt_L']" ]
    actual="$(run_in_user_session "${uid}" gsettings get \
        org.gnome.desktop.wm.keybindings switch-input-source-backward)"
    [ "${actual// /}" = "['<Shift><Super>space','<Shift>XF86Keyboard','<Alt>Shift_R','<Shift>Alt_R']" ]

    while IFS=$'\t' read -r key expected; do
        actual="$(run_in_user_session "${uid}" gsettings get org.gnome.Ptyxis.Shortcuts "${key}")"
        [ "${actual}" = "'${expected}'" ]
    done <<'SHORTCUTS'
copy-clipboard	<Control><Shift>c|<Control><Shift>Cyrillic_es
paste-clipboard	<Control><Shift>v|<Control><Shift>Cyrillic_em
new-tab	<ctrl><shift>t|<ctrl><shift>Cyrillic_ie
new-window	<ctrl><shift>n|<ctrl><shift>Cyrillic_te
close-tab	<ctrl><shift>w|<ctrl><shift>Cyrillic_tse
close-window	<ctrl><shift>q|<ctrl><shift>Cyrillic_shorti
search	<ctrl><shift>f|<ctrl><shift>Cyrillic_a
select-all	<ctrl><shift>a|<ctrl><shift>Cyrillic_ef
tab-overview	<ctrl><shift>o|<ctrl><shift>Cyrillic_shcha
preferences	<ctrl>comma|<ctrl>Cyrillic_be
tab-menu	<alt>comma|<alt>Cyrillic_be
undo-close-tab	<ctrl><shift><alt>t|<ctrl><shift><alt>Cyrillic_ie
SHORTCUTS
    printf 'GRAPHICAL_LOCALE_KEYBOARD_PASS run_id=%s phase=%s locale=en_US.UTF-8 formats=en_US.UTF-8 layouts=us,ru model=pc105 switch=super-space+alt-shift ptyxis_latin_cyrillic=12/12\n' \
        "${run_id}" "${phase}"
}

emit_gnome_shell_lifecycle_diagnostic() {
    local uid="$1" checkpoint="$2" gid
    gid="$(id -g "${username}")" || return 0
    # Diagnostics never change acceptance or settings. All query output is parsed privately.
    python3 - "${uid}" "${gid}" "${run_id}" "${phase}" "${checkpoint}" "${username}" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import stat
import subprocess
import sys
import tempfile

UNITS = ("org.gnome.Shell@wayland.service", "org.gnome.Shell-disable-extensions.service")
RESULTS = {"success", "exit-code", "signal", "core-dump", "timeout", "watchdog", "oom-kill",
           "start-limit-hit", "resources", "protocol", "exec-condition", "skipped"}
EVENTS = {"39f53479d3a045ac8e11786248231fbf": "started",
          "9d1aaa27d60140bd96365438aad20286": "stopped",
          "d9b373ed55a64feb8242e02dbe79a49c": "failure-result",
          "98e322203f7a4ed290d09fe03c09fe15": "process-exit"}

def query(args, cap=262144):
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=output,
                                    stderr=subprocess.DEVNULL, timeout=5, check=False,
                                    preexec_fn=lambda: resource.setrlimit(resource.RLIMIT_FSIZE, (cap + 1, cap + 1)))
            output.seek(0)
            raw = output.read(cap + 1)
        if result.returncode or len(raw) > cap:
            return None
        return raw.decode("utf-8", errors="strict")
    except (OSError, UnicodeError, subprocess.TimeoutExpired):
        return None

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate field")
        value[key] = item
    return value

def number(value, maximum=(1 << 63) - 1):
    if isinstance(value, str) and re.fullmatch(r"0|[1-9][0-9]{0,18}", value) and int(value) <= maximum:
        return value
    return "unknown"

def diagnose(uid, gid, run_id, phase, checkpoint, account="vmtest"):
    if (not re.fullmatch(r"[0-9]{1,10}", uid) or not re.fullmatch(r"[0-9]{1,10}", gid)
            or not re.fullmatch(r"[A-Za-z0-9-]{1,80}", run_id)
            or not re.fullmatch(r"[a-z0-9-]{1,64}", phase)
            or not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", account)
            or checkpoint not in {"migrated-login", "before-original-user-logout", "extension-timeout"}):
        return
    prefix = f"GNOME_SHELL_DIAGNOSTIC run_id={run_id} phase={phase} checkpoint={checkpoint}"
    user = ["/usr/bin/setpriv", f"--reuid={uid}", f"--regid={gid}", "--init-groups", "/usr/bin/env",
            f"HOME=/home/{account}", f"USER={account}", f"LOGNAME={account}",
            f"XDG_RUNTIME_DIR=/run/user/{uid}", f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"]
    disabled = query(user + ["/usr/bin/gsettings", "get", "org.gnome.shell", "disable-user-extensions"], 64)
    disabled = disabled.strip() if disabled is not None else "unknown"
    if disabled not in {"true", "false"}:
        disabled = "unknown"
    sentinel = "unknown"
    try:
        path = Path(f"/run/user/{uid}/gnome-shell-disable-extensions")
        parent = path.parent.lstat()
        if stat.S_ISDIR(parent.st_mode) and parent.st_uid == int(uid) and not parent.st_mode & 0o077:
            try:
                info = path.lstat()
                if stat.S_ISREG(info.st_mode) and info.st_uid == int(uid) and info.st_nlink == 1 and info.st_size == 0:
                    sentinel = "present"
            except FileNotFoundError:
                sentinel = "absent"
    except OSError:
        pass
    digest = "unknown"
    try:
        path = Path("/usr/lib/systemd/user/org.gnome.Shell-disable-extensions.service")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1 and not info.st_mode & 0o022 and 0 < info.st_size <= 16384:
                raw = os.read(fd, 16385)
                after = os.fstat(fd)
                # Reading may update atime; identity and mutation-sensitive timestamps must stay fixed.
                protected = ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
                             "st_size", "st_mtime_ns", "st_ctime_ns")
                if all(getattr(info, field) == getattr(after, field) for field in protected) and len(raw) == info.st_size:
                    digest = hashlib.sha256(raw).hexdigest()
        finally:
            os.close(fd)
    except OSError:
        pass
    print(f"{prefix} disabled_user_extensions={disabled} early_sentinel={sentinel} recovery_unit_sha256={digest}", file=sys.stderr)
    for unit in UNITS:
        raw = query(user + ["/usr/bin/systemctl", "--user", "show", unit,
                           "--property=LoadState,Result,ExecMainCode,ExecMainStatus,ExecMainStartTimestampMonotonic,InvocationID"], 4096)
        fields = {}
        try:
            if raw is None:
                raise ValueError("query unavailable")
            for line in raw.splitlines():
                key, value = line.split("=", 1)
                if key in fields:
                    raise ValueError("duplicate field")
                fields[key] = value
            if fields.get("LoadState") != "loaded":
                raise ValueError("unit unavailable")
        except ValueError:
            fields = {}
        result = fields.get("Result")
        result = result if result in RESULTS else "unknown"
        code = {"0": "none", "1": "exited", "2": "killed", "3": "dumped"}.get(fields.get("ExecMainCode"), "unknown")
        invocation = fields.get("InvocationID")
        if invocation in {"", "0" * 32}:
            invocation = "no"
        else:
            invocation = "yes" if isinstance(invocation, str) and re.fullmatch(r"[a-f0-9]{32}", invocation) else "unknown"
        print(f"{prefix} unit={unit} result={result} exit_code={code} exit_status={number(fields.get('ExecMainStatus'), 255)} start_monotonic_us={number(fields.get('ExecMainStartTimestampMonotonic'))} invocation={invocation}", file=sys.stderr)
    if checkpoint != "extension-timeout":
        return
    # Current boot includes the migration and original-user logout. Query only these public
    # units for this UID; retain no messages, paths, command lines or unknown identifiers.
    args = ["/usr/bin/journalctl", "--boot=0", "--no-pager", "--lines=129", "--output=json",
            "--output-fields=USER_UNIT,_SYSTEMD_USER_UNIT,MESSAGE_ID,UNIT_RESULT,EXIT_CODE,EXIT_STATUS"]
    for unit in UNITS:
        for field in ("USER_UNIT", "_SYSTEMD_USER_UNIT"):
            if args[-1].startswith(("USER_UNIT=", "_SYSTEMD_USER_UNIT=")):
                args.append("+")
            args.extend([f"_UID={uid}", f"{field}={unit}"])
    raw = query(args)
    query_state = "unknown"
    counts = dict.fromkeys(("records", "stop_events", "failure_events", "killed_events", "timeout_events", "unclassified_events"), "unknown")
    recovery = "unknown"
    try:
        if raw is None:
            raise ValueError("query unavailable")
        records = [json.loads(line, object_pairs_hook=unique_object) for line in raw.splitlines()]
        if len(records) >= 129:
            raise ValueError("bounded window exhausted")
        typed = []
        for record in records:
            if not isinstance(record, dict):
                raise ValueError("invalid record")
            unit = record.get("USER_UNIT", record.get("_SYSTEMD_USER_UNIT"))
            if unit not in UNITS or any(not isinstance(record.get(key, ""), str) for key in ("MESSAGE_ID", "UNIT_RESULT", "EXIT_CODE", "EXIT_STATUS")):
                raise ValueError("invalid fields")
            if record.get("UNIT_RESULT") and record["UNIT_RESULT"] not in RESULTS:
                raise ValueError("invalid result")
            if record.get("EXIT_CODE") and record["EXIT_CODE"] not in {"exited", "killed", "dumped"}:
                raise ValueError("invalid exit code")
            if record.get("EXIT_STATUS") and number(record["EXIT_STATUS"], 255) == "unknown":
                raise ValueError("invalid exit status")
            typed.append((unit, EVENTS.get(record.get("MESSAGE_ID")), record))
        counts = dict.fromkeys(counts, 0)
        counts["records"] = len(typed)
        recovery = "no"
        for unit, event, record in typed:
            counts["unclassified_events"] += event is None
            if unit == UNITS[1] and event == "started":
                recovery = "yes"
            if unit == UNITS[0]:
                counts["stop_events"] += event == "stopped"
                counts["failure_events"] += event == "failure-result"
                counts["timeout_events"] += event == "failure-result" and record.get("UNIT_RESULT") == "timeout"
                counts["killed_events"] += event == "process-exit" and record.get("EXIT_CODE") in {"killed", "dumped"}
        query_state = "ok"
    except (ValueError, TypeError):
        pass
    values = " ".join(f"{key}={value}" for key, value in counts.items())
    print(f"{prefix} journal_scope=current-boot journal_query={query_state} {values} recovery_started={recovery}", file=sys.stderr)

if __name__ == "__main__":
    try:
        diagnose(*sys.argv[1:])
    except Exception:
        # A diagnostic failure must neither repair settings nor replace the functional verdict.
        print("GNOME_SHELL_DIAGNOSTIC query=unknown reason=helper-failed", file=sys.stderr)
PY
    return 0
}

emit_extension_timeout_diagnostic() {
    local uid="$1" expected="$2" actual="$3" query_status="$4"
    local reason=enabled-set-mismatch disabled=unavailable value id line expected_flag enabled_flag state
    local expected_count=0 actual_count=0 missing_known_count=0 unexpected_count=0 duplicate_count=0 i j found
    local -a expected_ids=() actual_ids=() known_ids=(
        appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info
        clipboard-indicator@tudmotu.com dash-to-dock@micxgx.gmail.com
        just-perfection-desktop@just-perfection no-screenshot-box@screenshot
        user-theme@gnome-shell-extensions.gcampax.github.com
    )
    [ "${query_status}" -eq 0 ] || reason=query-failed
    while IFS= read -r line; do
        [ -z "${line}" ] || expected_ids+=("${line}")
    done <<<"${expected}"
    while IFS= read -r line; do
        [ -z "${line}" ] || actual_ids+=("${line}")
    done <<<"${actual}"
    expected_count="${#expected_ids[@]}" actual_count="${#actual_ids[@]}"
    for ((i = 0; i < actual_count; i++)); do
        found=no
        for line in "${expected_ids[@]}"; do
            [ "${actual_ids[i]}" != "${line}" ] || found=yes
        done
        [ "${found}" = yes ] || unexpected_count=$((unexpected_count + 1))
        for ((j = 0; j < i; j++)); do
            if [ "${actual_ids[i]}" = "${actual_ids[j]}" ]; then
                duplicate_count=$((duplicate_count + 1))
                break
            fi
        done
    done
    for id in "${known_ids[@]}"; do
        expected_flag=no enabled_flag=no
        for line in "${expected_ids[@]}"; do [ "${line}" != "${id}" ] || expected_flag=yes; done
        for line in "${actual_ids[@]}"; do [ "${line}" != "${id}" ] || enabled_flag=yes; done
        if [ "${expected_flag}" = yes ] && [ "${enabled_flag}" = no ]; then
            missing_known_count=$((missing_known_count + 1))
        fi
    done
    if value="$(run_in_user_session "${uid}" /usr/bin/timeout 5 /usr/bin/gsettings get \
        org.gnome.shell disable-user-extensions 2>/dev/null)"; then
        case "${value}" in true | false) disabled="${value}" ;; esac
    fi
    printf 'GNOME_EXTENSION_DIAGNOSTIC run_id=%s phase=%s reason=%s expected_count=%s actual_count=%s missing_known_count=%s unexpected_count=%s duplicate_count=%s disabled_user_extensions=%s\n' \
        "${run_id}" "${phase}" "${reason}" "${expected_count}" "${actual_count}" \
        "${missing_known_count}" "${unexpected_count}" "${duplicate_count}" "${disabled}" >&2
    # Only this fixed public allowlist is emitted; unknown query output stays private.
    for id in "${known_ids[@]}"; do
        expected_flag=no enabled_flag=no
        for line in "${expected_ids[@]}"; do [ "${line}" != "${id}" ] || expected_flag=yes; done
        for line in "${actual_ids[@]}"; do [ "${line}" != "${id}" ] || enabled_flag=yes; done
        state=unavailable
        if value="$(run_in_user_session "${uid}" /usr/bin/timeout 5 /usr/bin/gnome-extensions info "${id}" 2>/dev/null)"; then
            value="$(sed -n 's/^[[:space:]]*State:[[:space:]]*\([A-Z _-]*\)[[:space:]]*$/\1/p' <<<"${value}" | sed 's/[[:space:]]*$//')"
            case "${value}" in
            ENABLED | ACTIVE) state=enabled ;;
            DISABLED | INACTIVE) state=disabled ;;
            ERROR) state=error ;;
            'OUT OF DATE' | OUT-OF-DATE | OUT_OF_DATE) state=out-of-date ;;
            INITIALIZED | LOADED) state=initialized ;;
            *) state=unknown ;;
            esac
        fi
        printf 'GNOME_EXTENSION_DIAGNOSTIC run_id=%s phase=%s known_extension=%s expected=%s enabled=%s state=%s\n' \
            "${run_id}" "${phase}" "${id}" "${expected_flag}" "${enabled_flag}" "${state}" >&2
    done
    emit_gnome_shell_lifecycle_diagnostic "${uid}" extension-timeout
}

wait_for_enabled_extensions() {
    local uid="$1" expected="$2" deadline=$((SECONDS + 180)) actual='' query_status=1
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if actual="$(run_in_user_session "${uid}" /usr/bin/gnome-extensions list --enabled 2>/dev/null | LC_ALL=C sort)"; then
            query_status=0
            if [ "${actual}" = "${expected}" ]; then
                printf '%s' "${actual}"
                return 0
            fi
        else
            query_status=$?
        fi
        sleep 1
    done
    emit_extension_timeout_diagnostic "${uid}" "${expected}" "${actual}" "${query_status}"
    return 1
}

verify_common() {
    local target root_source root_device root_partition root_parent expected_fstype='ext4'
    target="$(find_target)"
    root_source="$(findmnt -nro SOURCE --target /)"
    root_device="$(readlink -f -- "${root_source%%\[*}")"
    [ -b "${root_device}" ]
    root_partition="${root_device}"
    if is_luks_stock; then
        [ "$(readlink -f -- /dev/mapper/cryptroot)" = "${root_device}" ]
        root_partition="$(cryptsetup status -- cryptroot | awk '$1 == "device:" { print $2; exit }')"
        root_partition="$(readlink -f -- "${root_partition}")"
        [ -b "${root_partition}" ]
    fi
    root_parent="$(lsblk -dnro PKNAME -- "${root_partition}" | trim_value)"
    [ "${target}" = "/dev/${root_parent}" ]
    [ "$(lsblk -dnro PTTYPE -- "${target}" | trim_value)" = gpt ]
    is_btrfs_stock && expected_fstype='btrfs'
    [ "$(findmnt -nro FSTYPE --target /)" = "${expected_fstype}" ]
    [ -d /sys/firmware/efi ]
    if is_grub_stock; then
        verify_grub_efi_target
    else
        bootctl is-installed
    fi
    systemctl is-active --quiet NetworkManager.service
    systemctl is-active --quiet qemu-guest-agent.service
    nm-online -q --timeout=60
    getent ahostsv4 archlinux.org >/dev/null
    [ -z "$(systemctl --failed --no-legend --plain)" ]
    clean_kernel_command_line
    verify_kernel_initramfs_pair /boot/initramfs-linux.img || return 1
    printf '%s' "${target}"
}

btrfs_options_match_policy() {
    local options="$1"
    case ",${options}," in
    *,noatime,*) ;;
    *) return 1 ;;
    esac
    [[ ",${options}," =~ ,compress=zstd(:[0-9]+)?, ]]
}

mounted_source_device() {
    local mountpoint="$1" source
    source="$(findmnt -nro SOURCE --target "${mountpoint}")"
    readlink -f -- "${source%%\[*}"
}

verify_btrfs_mount() {
    local mountpoint="$1" expected_fsroot="$2" expected_device="$3" options
    [ "$(findmnt -nro FSTYPE --target "${mountpoint}")" = btrfs ]
    [ "$(findmnt -nro FSROOT --target "${mountpoint}")" = "${expected_fsroot}" ]
    [ "$(mounted_source_device "${mountpoint}")" = "${expected_device}" ]
    options="$(findmnt -nro OPTIONS --target "${mountpoint}")"
    btrfs_options_match_policy "${options}"
    btrfs subvolume show "${mountpoint}" >/dev/null
}

fstab_line_for() {
    local mountpoint="$1" count
    count="$(awk -v target="${mountpoint}" '$2 == target { count++ } END { print count + 0 }' /etc/fstab)"
    [ "${count}" -eq 1 ]
    awk -v target="${mountpoint}" '$2 == target { print; exit }' /etc/fstab
}

verify_btrfs_fstab_entry() {
    local mountpoint="$1" expected_subvolume="$2" root_uuid="$3"
    local line source target fstype options dump pass
    line="$(fstab_line_for "${mountpoint}")"
    read -r source target fstype options dump pass <<<"${line}"
    [ "${source}" = "UUID=${root_uuid}" ]
    [ "${target}" = "${mountpoint}" ]
    [ "${fstype}" = btrfs ]
    btrfs_options_match_policy "${options}"
    case ",${options}," in
    *,"subvol=/${expected_subvolume}",*) ;;
    *) return 1 ;;
    esac
    [ "${dump}" = 0 ] && [ "${pass}" = 0 ]
}

require_kernel_argument_once() {
    local arguments_text="$1" required="$2" argument count=0
    local -a arguments=()
    read -ra arguments <<<"${arguments_text}"
    for argument in "${arguments[@]}"; do
        [ "${argument}" = "${required}" ] && count=$((count + 1))
    done
    [ "${count}" -eq 1 ]
}

require_prefixed_kernel_argument_once() {
    local arguments_text="$1" prefix="$2" required="$3" argument count=0
    local -a arguments=()
    read -ra arguments <<<"${arguments_text}"
    for argument in "${arguments[@]}"; do
        case "${argument}" in
        "${prefix}"*)
            count=$((count + 1))
            [ "${argument}" = "${required}" ]
            ;;
        esac
    done
    [ "${count}" -eq 1 ]
}

reject_encrypted_root_arguments() {
    local arguments_text="$1" argument
    local -a arguments=()
    read -ra arguments <<<"${arguments_text}"
    for argument in "${arguments[@]}"; do
        case "${argument}" in
        rd.luks.name=* | root=/dev/mapper/*) return 1 ;;
        esac
    done
}

verify_grub_efi_target() {
    local efi_image='/boot/EFI/ArchLinux/grubx64.efi' efi_state efi_verbose
    local boot_current boot_entry boot_entry_label boot_entry_lower
    command -v efibootmgr >/dev/null
    [ -f "${efi_image}" ] && [ ! -L "${efi_image}" ]
    efi_state="$(efibootmgr)"
    boot_current="$(awk '$1 == "BootCurrent:" { print $2; exit }' <<<"${efi_state}")"
    [[ "${boot_current}" =~ ^[A-Fa-f0-9]{4}$ ]]
    efi_verbose="$(efibootmgr -v)"
    boot_entry="$(awk -v current="${boot_current}" '
        $1 ~ ("^Boot" current "\\*?$") { print; exit }
    ' <<<"${efi_verbose}")"
    [ -n "${boot_entry}" ]
    boot_entry_label="$(awk '{ sub(/^[^[:space:]]+[[:space:]]+/, ""); sub(/[[:space:]].*$/, ""); print }' <<<"${boot_entry}")"
    [ "${boot_entry_label}" = ArchLinux ]
    boot_entry_lower="${boot_entry,,}"
    [[ "${boot_entry_lower}" == *'/\efi\archlinux\grubx64.efi' ]]
}

verify_grub_package_integrity() {
    local qkk
    qkk="$(pacman -Qkk grub grub-btrfs)"
    grep -Eq '^grub: [0-9]+ total files, 0 altered files$' <<<"${qkk}"
    grep -Eq '^grub-btrfs: [0-9]+ total files, 0 altered files$' <<<"${qkk}"
    printf '%s' "${qkk}"
}

verify_grub_config_contract() {
    local root_argument="$1" luks_argument="${2:-}" config='/boot/grub/grub.cfg'
    local line arguments first_arguments=''
    local linux_lines=0
    local -a fields=()
    [ -f "${config}" ] && [ ! -L "${config}" ]
    command -v grub-script-check >/dev/null
    grub-script-check "${config}"
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        read -ra fields <<<"${line}"
        [ "${#fields[@]}" -ge 3 ]
        [ "${fields[0]}" = linux ]
        [ "${fields[1]}" = /vmlinuz-linux ]
        arguments="${fields[*]:2}"
        require_prefixed_kernel_argument_once "${arguments}" 'root=' "${root_argument}"
        require_kernel_argument_once "${arguments}" 'rootflags=subvol=@'
        require_kernel_argument_once "${arguments}" 'rootfstype=btrfs'
        if is_luks_stock; then
            [[ "${luks_argument}" =~ ^rd\.luks\.name=[A-Fa-f0-9-]{36}=cryptroot$ ]]
            require_prefixed_kernel_argument_once "${arguments}" 'rd.luks.name=' "${luks_argument}"
            require_kernel_argument_once "${arguments}" splash
        else
            [ -z "${luks_argument}" ]
            reject_encrypted_root_arguments "${arguments}"
        fi
        [ -n "${first_arguments}" ] || first_arguments="${arguments}"
        linux_lines=$((linux_lines + 1))
    done < <(awk '$1 == "linux" { print }' "${config}")
    [ "${linux_lines}" -gt 0 ]
    printf '%s' "${first_arguments}"
}

verify_grub_runtime_contract() {
    local root_argument="$1" luks_argument="${2:-}" qkk config_arguments encryption_proof='absent'
    pacman -Q grub grub-btrfs >/dev/null
    verify_grub_efi_target
    systemctl is-enabled --quiet grub-btrfsd.service
    systemctl is-active --quiet grub-btrfsd.service
    verify_kernel_initramfs_pair /boot/initramfs-linux.img
    config_arguments="$(verify_grub_config_contract "${root_argument}" "${luks_argument}")"
    qkk="$(verify_grub_package_integrity)"
    [ -z "${luks_argument}" ] || encryption_proof="${luks_argument}"
    printf 'GRUB_QEMU_EFI_PROOF run_id=%s phase=%s efi=/boot/EFI/ArchLinux/grubx64.efi bootloader_id=ArchLinux bootcurrent=matched\n' \
        "${run_id}" "${phase}"
    printf 'GRUB_QEMU_CONFIG_PROOF run_id=%s phase=%s config=/boot/grub/grub.cfg syntax=valid linux=/vmlinuz-linux root_argument=%s rootflags=subvol=@ rootfstype=btrfs encrypted_argument=%s first_options=%q\n' \
        "${run_id}" "${phase}" "${root_argument}" "${encryption_proof}" "${config_arguments}"
    printf 'GRUB_QEMU_SERVICE_PROOF run_id=%s phase=%s grub_btrfsd=enabled,active\n' "${run_id}" "${phase}"
    printf 'GRUB_QEMU_QKK_PROOF run_id=%s phase=%s %q\n' "${run_id}" "${phase}" "${qkk}"
}

run_grub_mkconfig_for_regression() {
    # Diagnostics are not a language-dependent product contract. Preserve exit status;
    # the caller verifies the resulting boot configuration and the next real boot.
    grub-mkconfig -o /boot/grub/grub.cfg
}

verify_grub_regeneration() {
    local target root_partition root_partuuid='' root_argument luks_uuid='' luks_argument=''
    target="$(find_target)"
    root_partition="$(readlink -f -- "$(partition_name "${target}" 2)")"
    [ -b "${root_partition}" ]
    if is_luks_stock; then
        cryptsetup isLuks --type luks2 -- "${root_partition}"
        luks_uuid="$(cryptsetup luksUUID "${root_partition}")"
        [[ "${luks_uuid}" =~ ^[A-Fa-f0-9-]{36}$ ]]
        root_argument='root=/dev/mapper/cryptroot'
        luks_argument="rd.luks.name=${luks_uuid}=cryptroot"
    else
        root_partuuid="$(lsblk -dnro PARTUUID -- "${root_partition}" | trim_value)"
        [[ "${root_partuuid}" =~ ^[A-Fa-f0-9-]+$ ]]
        root_argument="root=PARTUUID=${root_partuuid}"
    fi
    command -v grub-mkconfig >/dev/null
    run_grub_mkconfig_for_regression
    verify_grub_config_contract "${root_argument}" "${luks_argument}" >/dev/null
    verify_grub_package_integrity >/dev/null
    printf 'GRUB_QEMU_REGEN_PROOF run_id=%s phase=%s path=grub-mkconfig generations=1 syntax=valid root_argument=%s encrypted_argument=%s root_contract=valid qkk=clean\n' \
        "${run_id}" "${phase}" "${root_argument}" "${luks_argument:-absent}"
}

verify_btrfs_boot_entry() {
    local file="$1" root_argument="$2" luks_argument="$3" options
    [ -f "${file}" ] && [ ! -L "${file}" ]
    [ "$(grep -c '^options[[:space:]]' "${file}")" -eq 1 ]
    options="$(sed -n 's/^options[[:space:]]\+//p' "${file}")"
    require_kernel_argument_once "${options}" 'rootflags=subvol=@'
    require_kernel_argument_once "${options}" 'rootfstype=btrfs'
    if is_luks_stock; then
        require_prefixed_kernel_argument_once "${options}" 'root=' "${root_argument}"
        require_prefixed_kernel_argument_once "${options}" 'rd.luks.name=' "${luks_argument}"
        require_kernel_argument_once "${options}" splash
    else
        require_kernel_argument_once "${options}" "${root_argument}"
        reject_encrypted_root_arguments "${options}"
    fi
    printf '%s' "${options}"
}

verify_luks_initramfs() {
    local hooks expected_hooks image='/boot/initramfs-linux.img' listing
    hooks="$(sed -n 's/^HOOKS=(\(.*\))$/\1/p' /etc/mkinitcpio.conf)"
    expected_hooks='base systemd keyboard autodetect microcode modconf sd-vconsole plymouth block sd-encrypt filesystems fsck'
    is_grub_stock && expected_hooks+=' sd-volatile'
    [ "${hooks}" = "${expected_hooks}" ]
    [ "$(plymouth-set-default-theme)" = archlinux ]
    pacman -Q plymouth plymouth-theme-archlinux >/dev/null
    [ -f "${image}" ] && [ ! -L "${image}" ]
    listing="$(lsinitcpio -l "${image}")"
    verify_kernel_initramfs_pair "${image}"
    grep -Eq '(^|/)systemd-cryptsetup$' <<<"${listing}"
    grep -Eq '(^|/)plymouthd?$' <<<"${listing}"
    if is_grub_stock; then
        grep -Eq '(^|/)systemd-volatile-root.service$' <<<"${listing}"
        grep -Eq '(^|/)systemd-volatile-root$' <<<"${listing}"
        grep -Eq '(^|/)overlay\.ko([.]zst)?$' <<<"${listing}"
    fi
}

verify_kernel_initramfs_pair() {
    local image="$1" kernel_release listing module_root
    local -a releases=()
    [ -f "${image}" ] && [ ! -L "${image}" ] || return 1
    [ -f /boot/vmlinuz-linux ] && [ ! -L /boot/vmlinuz-linux ] || return 1
    listing="$(lsinitcpio -l "${image}")" || return 1
    mapfile -t releases < <(sed -n 's|^\(\./\)\?usr/lib/modules/\([^/][^/]*\)/.*|\2|p' <<<"${listing}" | LC_ALL=C sort -u)
    [ "${#releases[@]}" -eq 1 ] || return 1
    kernel_release="${releases[0]}"
    [[ "${kernel_release}" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
    module_root="/usr/lib/modules/${kernel_release}"
    [ -d "${module_root}" ] && [ ! -L "${module_root}" ] || return 1
    [ -f "${module_root}/pkgbase" ] && [ ! -L "${module_root}/pkgbase" ] || return 1
    [ "$(cat -- "${module_root}/pkgbase")" = linux ] || return 1
    [ -f "${module_root}/vmlinuz" ] && [ ! -L "${module_root}/vmlinuz" ] || return 1
    cmp -s -- /boot/vmlinuz-linux "${module_root}/vmlinuz" || return 1
    # A full upgrade can replace disk modules while the old kernel still runs.
    # Require runtime pairing again after the following real reboot.
    case "${phase}" in
    update | migration-update | gnome51-upgrade) ;;
    *) [ "$(uname -r)" = "${kernel_release}" ] || return 1 ;;
    esac
    printf 'QEMU_KERNEL_PAIR run_id=%s phase=%s installed_release=%s running_release=%s package=linux systemd=%s mkinitcpio=%s\n' \
        "${run_id}" "${phase}" "${kernel_release}" "$(uname -r)" \
        "$(pacman -Q systemd | awk '{print $2}')" "$(pacman -Q mkinitcpio | awk '{print $2}')" >&2
}

select_snapshot_grub_entry() {
    python3 - "$@" <<'SNAPSHOT_ENTRY_PY'
import re
import shlex
import sys
from pathlib import Path
main, generated, uuid, subvol, device, partuuid = sys.argv[1:7]
inner_only = sys.argv[7:] == ["--inner"]
if sys.argv[7:] and not inner_only: raise ValueError("unknown snapshot selector mode")
headers = re.compile(r"^\s*(submenu|menuentry)\s+(.*)\{\s*$")
def walk(path):
    stack = []
    for line in Path(path).read_text().splitlines():
        match = headers.match(line)
        if match:
            title = shlex.split(match[2])[0]
            if not title or any(c in title for c in ">\n\r"):
                raise ValueError("unsafe menu title")
            stack.append((match[1], title))
        elif line.rstrip().endswith("{"):
            stack.append(("block", ""))
        elif re.match(r"^\s*}\s*$", line):
            if not stack: raise ValueError("unbalanced generated menu")
            stack.pop()
        else:
            yield tuple(item for item in stack if item[0] != "block"), line.strip()
    if stack: raise ValueError("unclosed generated menu")
outer = set()
for stack, line in walk(main):
    if "configfile" in line and "grub-btrfs.cfg" in line and stack:
        outer.add(">".join(title for _, title in stack))
if len(outer) != 1: raise ValueError("snapshot submenu closure differs")
entries = {}
for stack, line in walk(generated):
    if stack and stack[-1][0] == "menuentry":
        entries.setdefault(stack, []).append(line)
accepted = []
for stack, lines in entries.items():
    linux = [shlex.split(line) for line in lines if line.startswith("linux ")]
    initrd = [shlex.split(line) for line in lines if line.startswith("initrd ")]
    if len(linux) != 1 or len(initrd) != 1: continue
    args = linux[0][2:]
    roots = [arg for arg in args if arg.startswith("root=")]
    flags = [arg for arg in args if arg.startswith("rootflags=")]
    if len(roots) != 1 or roots[0] not in {"root=" + device, "root=UUID=" + uuid, "root=PARTUUID=" + partuuid} or len(flags) != 1: continue
    subvols = [flag for flag in flags[0][10:].split(",") if flag.startswith("subvol=")]
    if subvols != ["subvol=" + subvol]: continue
    if args.count("systemd.volatile=overlay") != 1: continue
    if linux[0][1] != "/vmlinuz-linux" or initrd[0][-1] != "/initramfs-linux.img": continue
    if any(".." in part or not part.startswith("/") for part in initrd[0][1:]): continue
    inner = ">".join(title for _, title in stack)
    accepted.append(inner if inner_only else next(iter(outer)) + ">" + inner)
print("SNAPSHOT_ENTRY_DIAGNOSTIC accepted=" + str(len(accepted)) + " entries=" + str(len(entries)) + " expected_device=" + device + " uuid=" + uuid + " partuuid=" + partuuid, file=sys.stderr)
if len(accepted) != 1: raise ValueError("exact snapshot boot entry absent or ambiguous")
print(accepted[0])
SNAPSHOT_ENTRY_PY
}

snapshot_runtime_fail() {
    local reason="$1" identity=unavailable checkpoint=unavailable
    case "${reason}" in
        scenario|state-file|state-mode|state-lines|state-run|state-subvolume|cfg-record|cfg-hash|root-uuid|boot-id|root-filesystem|root-options-query|lower-shape|lower-filesystem|lower-subvolume|lower-options-query|lower-readonly|lower-uuid|lower-property|lower-marker|lower-source-query|target-query|target-partition|cmdline-query|device-shape|partuuid-shape|device-identity|root-argument|volatile-argument|rootflags-argument|rootflags-subvolume|kernel-initramfs|grub-efi|grub-package|services|network|failed-units) ;;
        *) reason=unknown ;;
    esac
    [[ "${run_id:-}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] && identity="${run_id}"
    case "${phase:-}" in snapshot-prelogin|snapshot-login) checkpoint="${phase}" ;; esac
    printf 'SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=%s phase=%s reason=%s\n' \
        "${identity}" "${checkpoint}" "${reason}" >&2
    return 1
}

snapshot_unit_program() {
    cat <<'SNAPSHOT_UNIT_PY'
import re
import resource
import subprocess
import sys
import tempfile

KNOWN = {name + ".service": name for name in (
    "systemd-remount-fs", "systemd-tmpfiles-setup", "systemd-vconsole-setup", "grub-btrfsd", "gdm")}
RESULTS = {"success", "resources", "timeout", "exit-code", "signal", "core-dump", "watchdog", "start-limit-hit", "oom-kill", "exec-condition", "protocol"}
CODES = {"0": "none", "1": "exited", "2": "killed", "3": "dumped"}
def bounded_query(arguments):
    def limit_output():
        resource.setrlimit(resource.RLIMIT_FSIZE, (4096, 4096))
    try:
        with tempfile.TemporaryFile() as output:
            result = subprocess.run(arguments, stdout=output, stderr=subprocess.DEVNULL,
                                    timeout=5, preexec_fn=limit_output, check=False)
            output.seek(0)
            raw = output.read(4097)
            return result.returncode == 0 and len(raw) < 4096, raw
    except (OSError, ValueError, subprocess.SubprocessError):
        return False, b""

def inspect_units(run, phase, query=bounded_query):
    if not re.fullmatch(r"grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}", run) or phase not in {"snapshot-prelogin", "snapshot-login"}:
        return 1
    prefix = "SNAPSHOT_UNIT_DIAGNOSTIC run_id=" + run + " phase=" + phase
    def summary(category, count="unavailable", unknown="unavailable"):
        print(prefix + " query=" + category + " count=" + str(count) + " unknown_count=" + str(unknown), file=sys.stderr)
    success, raw = query(["systemctl", "--failed", "--no-legend", "--plain"])
    if not success:
        summary("failed")
        return 1
    try:
        lines = raw.splitlines()
        if len(raw) >= 4096 or len(lines) > 64:
            raise ValueError("bound")
        units = set()
        for line in lines:
            if not line.strip():
                raise ValueError("empty unit row")
            columns = line.split(None, 4)
            if len(columns) < 4 or columns[1] not in {b"loaded", b"not-found", b"error", b"masked", b"bad-setting"} or columns[2:4] != [b"failed", b"failed"]:
                raise ValueError("unit row")
            unit = columns[0].decode("ascii")
            if not re.fullmatch(r"[A-Za-z0-9@_.:\\-]{1,256}", unit) or unit in units:
                raise ValueError("unit identity")
            units.add(unit)
    except (ValueError, UnicodeError):
        summary("malformed")
        return 1
    if not units:
        return 0
    summary("success", len(units), len(units - KNOWN.keys()))
    for unit in sorted(units & KNOWN.keys()):
        result = code = status = "unavailable"
        success, raw = query(["systemctl", "show", "--property=Result,ExecMainCode,ExecMainStatus", "--", unit])
        if success and len(raw) < 4096:
            try:
                fields = {}
                for line in raw.decode("ascii").splitlines():
                    key, separator, value = line.partition("=")
                    if not separator or key in fields:
                        raise ValueError("property closure")
                    fields[key] = value
                if set(fields) != {"Result", "ExecMainCode", "ExecMainStatus"}:
                    raise ValueError("property closure")
                result = fields["Result"] if fields["Result"] in RESULTS else "unavailable"
                code = CODES.get(fields["ExecMainCode"], "unavailable")
                value = fields["ExecMainStatus"]
                status = value if re.fullmatch(r"0|[1-9][0-9]{0,2}", value) and int(value) <= 255 else "unavailable"
            except (ValueError, UnicodeError):
                result = code = status = "unavailable"
        print(prefix + " unit=" + KNOWN[unit] + " result=" + result + " code=" + code + " status=" + status, file=sys.stderr)
    return 1

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(1)
    raise SystemExit(inspect_units(*sys.argv[1:]))
SNAPSHOT_UNIT_PY
}

snapshot_failed_units() {
    python3 - "${run_id}" "${phase}" < <(snapshot_unit_program)
}

snapshot_overlay_reader_program() {
    cat <<'SNAPSHOT_READER_PY'
import ctypes
import os
import platform
import re
import stat
import sys

class OpenHow(ctypes.Structure):
    _fields_ = [("flags", ctypes.c_uint64), ("mode", ctypes.c_uint64), ("resolve", ctypes.c_uint64)]

libc = ctypes.CDLL(None, use_errno=True)
libc.syscall.restype = ctypes.c_long
libc.syscall.argtypes = [ctypes.c_long, ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t]

def mount_id(fd):
    with open("/proc/self/fdinfo/" + str(fd), "rb") as stream:
        raw = stream.read(4097)
    values = re.findall(rb"^mnt_id:[ \t]*([1-9][0-9]*)$", raw, re.M)
    if len(raw) > 4096 or len(values) != 1:
        raise ValueError("mount identity unavailable")
    return int(values[0])

def identity(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
            metadata.st_gid, metadata.st_nlink, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)

def read_marker(run, root_path="/", relative="var/lib/arch-linux-vm/snapshot-marker"):
    if not re.fullmatch(r"grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}", run) or platform.machine() != "x86_64":
        raise ValueError("reader inputs unsupported")
    expected = (run + "\n").encode("ascii")
    root_fd = os.open(root_path, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)
    marker_fd = -1
    try:
        root_mount = mount_id(root_fd)
        # Linux x86-64 openat2; no symlink, escape or mount crossing is permitted.
        how = OpenHow(os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK, 0, 0x0d)
        marker_fd = libc.syscall(437, root_fd, relative.encode("ascii"), ctypes.byref(how), ctypes.sizeof(how))
        if marker_fd < 0:
            raise OSError(ctypes.get_errno(), "root-relative marker open failed")
        before = os.fstat(marker_fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.geteuid()
                or before.st_mode & 0o7022 or before.st_nlink != 1
                or before.st_size != len(expected) or mount_id(marker_fd) != root_mount):
            raise ValueError("unsafe marker identity")
        data = os.read(marker_fd, len(expected) + 1)
        eof = os.read(marker_fd, 1)
        after = os.fstat(marker_fd)
        if (data != expected or eof or identity(before) != identity(after)
                or mount_id(marker_fd) != root_mount or mount_id(root_fd) != root_mount):
            raise ValueError("marker read changed")
        return data
    finally:
        if marker_fd >= 0:
            os.close(marker_fd)
        os.close(root_fd)

if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("reader arguments")
        data = read_marker(sys.argv[1])
        if os.write(1, data) != len(data):
            raise ValueError("reader output incomplete")
    except (OSError, ValueError, UnicodeError):
        print("SNAPSHOT_OVERLAY_READER_FAIL reason=read", file=sys.stderr)
        raise SystemExit(1)
SNAPSHOT_READER_PY
}

snapshot_backing_probe_program() {
    cat <<'SNAPSHOT_BACKING_BPF'
#!/usr/bin/env bpftrace
// Read-only QA observer. $1: accepted lower inode; $2: exact marker byte length.
// Six independent pairs bound tuple/printf stack; no attachment order is assumed.
BEGIN
{
    assert($1 > 0 && $2 > 0 && $2 <= 128, "marker inputs missing");
    printf("QA_OVERLAY_BPF_ATTACHED schema=1\n");
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@core_pending[tid]) {
            @core_broken = (uint64)1;
        } else {
            @core_pending[tid] = 1;
            @core_inflight = @core_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_inode_number = (uint64)0;
            $v_root_id = (uint64)0;
            $v_root_flags = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $v_inode_number = ($inode->i_ino);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $v_root_id = ($root->root_key.objectid);
                    $v_root_flags = ($root->root_item.flags);
                    if ($iter != 0) { $valid = (uint64)1; }
                }
            }
        }
    }
    $v_valid = ($valid);
            @core_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_start, $v_count, $v_valid, $v_inode_number, $v_root_id, $v_root_flags);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @core_pending[tid]/
{
    $saved = @core_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                if (($inode->i_ino) != $saved.7) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    if (($root->root_key.objectid) != $saved.8) { $stable = (uint64)0; }
                    if (($root->root_item.flags) != $saved.9) { $stable = (uint64)0; }
                    if (1) { $valid = (uint64)1; }
                }
            }
        }
    }
    if ($valid != 1 || $saved.6 != 1) { $stable = (uint64)0; }
    if (@core_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.4 == 0) { $event = (uint64)1; }
    else if ($saved.4 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_CORE event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu inode=%llu root_id=%llu ro=%llu\n", $event, $saved.4, $saved.5, $end, (int64)retval, $valid, $stable, $saved.7, $saved.8, (uint64)(($saved.9 & (uint64)1) != 0));
    $saved_deleted = delete(@core_saved, tid);
    $pending_deleted = delete(@core_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @core_inflight = @core_inflight - 1;
    } else {
        @core_broken = (uint64)1;
    }
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@uuid_a_pending[tid]) {
            @uuid_a_broken = (uint64)1;
        } else {
            @uuid_a_pending[tid] = 1;
            @uuid_a_inflight = @uuid_a_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_p_info = (uint64)0;
            $v_p_fsdev = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_uuid0 = (uint64)0;
            $v_uuid1 = (uint64)0;
            $v_uuid2 = (uint64)0;
            $v_uuid3 = (uint64)0;
            $v_uuid4 = (uint64)0;
            $v_uuid5 = (uint64)0;
            $v_uuid6 = (uint64)0;
            $v_uuid7 = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $info = $root->fs_info;
                    if ($info != 0) {
                        $v_p_info = (uint64)($info);
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            $v_p_fsdev = (uint64)($fsdev);
                            $v_uuid0 = (uint64)((uint8)$fsdev->fsid[0]);
                            $v_uuid1 = (uint64)((uint8)$fsdev->fsid[1]);
                            $v_uuid2 = (uint64)((uint8)$fsdev->fsid[2]);
                            $v_uuid3 = (uint64)((uint8)$fsdev->fsid[3]);
                            $v_uuid4 = (uint64)((uint8)$fsdev->fsid[4]);
                            $v_uuid5 = (uint64)((uint8)$fsdev->fsid[5]);
                            $v_uuid6 = (uint64)((uint8)$fsdev->fsid[6]);
                            $v_uuid7 = (uint64)((uint8)$fsdev->fsid[7]);
                            if ($iter != 0) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    $v_valid = ($valid);
            @uuid_a_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_p_info, $v_p_fsdev, $v_start, $v_count, $v_valid, $v_uuid0, $v_uuid1, $v_uuid2, $v_uuid3, $v_uuid4, $v_uuid5, $v_uuid6, $v_uuid7);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @uuid_a_pending[tid]/
{
    $saved = @uuid_a_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    $info = $root->fs_info;
                    if ($info != 0) {
                        if ((uint64)($info) != $saved.4) { $stable = (uint64)0; }
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            if ((uint64)($fsdev) != $saved.5) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[0]) != $saved.9) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[1]) != $saved.10) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[2]) != $saved.11) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[3]) != $saved.12) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[4]) != $saved.13) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[5]) != $saved.14) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[6]) != $saved.15) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[7]) != $saved.16) { $stable = (uint64)0; }
                            if (1) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    if ($valid != 1 || $saved.8 != 1) { $stable = (uint64)0; }
    if (@uuid_a_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.6 == 0) { $event = (uint64)1; }
    else if ($saved.6 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_UUID_A event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu fsid=%02x%02x%02x%02x%02x%02x%02x%02x\n", $event, $saved.6, $saved.7, $end, (int64)retval, $valid, $stable, $saved.9, $saved.10, $saved.11, $saved.12, $saved.13, $saved.14, $saved.15, $saved.16);
    $saved_deleted = delete(@uuid_a_saved, tid);
    $pending_deleted = delete(@uuid_a_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @uuid_a_inflight = @uuid_a_inflight - 1;
    } else {
        @uuid_a_broken = (uint64)1;
    }
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@uuid_b_pending[tid]) {
            @uuid_b_broken = (uint64)1;
        } else {
            @uuid_b_pending[tid] = 1;
            @uuid_b_inflight = @uuid_b_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_p_info = (uint64)0;
            $v_p_fsdev = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_uuid8 = (uint64)0;
            $v_uuid9 = (uint64)0;
            $v_uuid10 = (uint64)0;
            $v_uuid11 = (uint64)0;
            $v_uuid12 = (uint64)0;
            $v_uuid13 = (uint64)0;
            $v_uuid14 = (uint64)0;
            $v_uuid15 = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $info = $root->fs_info;
                    if ($info != 0) {
                        $v_p_info = (uint64)($info);
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            $v_p_fsdev = (uint64)($fsdev);
                            $v_uuid8 = (uint64)((uint8)$fsdev->fsid[8]);
                            $v_uuid9 = (uint64)((uint8)$fsdev->fsid[9]);
                            $v_uuid10 = (uint64)((uint8)$fsdev->fsid[10]);
                            $v_uuid11 = (uint64)((uint8)$fsdev->fsid[11]);
                            $v_uuid12 = (uint64)((uint8)$fsdev->fsid[12]);
                            $v_uuid13 = (uint64)((uint8)$fsdev->fsid[13]);
                            $v_uuid14 = (uint64)((uint8)$fsdev->fsid[14]);
                            $v_uuid15 = (uint64)((uint8)$fsdev->fsid[15]);
                            if ($iter != 0) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    $v_valid = ($valid);
            @uuid_b_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_p_info, $v_p_fsdev, $v_start, $v_count, $v_valid, $v_uuid8, $v_uuid9, $v_uuid10, $v_uuid11, $v_uuid12, $v_uuid13, $v_uuid14, $v_uuid15);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @uuid_b_pending[tid]/
{
    $saved = @uuid_b_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    $info = $root->fs_info;
                    if ($info != 0) {
                        if ((uint64)($info) != $saved.4) { $stable = (uint64)0; }
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            if ((uint64)($fsdev) != $saved.5) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[8]) != $saved.9) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[9]) != $saved.10) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[10]) != $saved.11) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[11]) != $saved.12) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[12]) != $saved.13) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[13]) != $saved.14) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[14]) != $saved.15) { $stable = (uint64)0; }
                            if ((uint64)((uint8)$fsdev->fsid[15]) != $saved.16) { $stable = (uint64)0; }
                            if (1) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    if ($valid != 1 || $saved.8 != 1) { $stable = (uint64)0; }
    if (@uuid_b_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.6 == 0) { $event = (uint64)1; }
    else if ($saved.6 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_UUID_B event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu fsid=%02x%02x%02x%02x%02x%02x%02x%02x\n", $event, $saved.6, $saved.7, $end, (int64)retval, $valid, $stable, $saved.9, $saved.10, $saved.11, $saved.12, $saved.13, $saved.14, $saved.15, $saved.16);
    $saved_deleted = delete(@uuid_b_saved, tid);
    $pending_deleted = delete(@uuid_b_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @uuid_b_inflight = @uuid_b_inflight - 1;
    } else {
        @uuid_b_broken = (uint64)1;
    }
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@mount_device_pending[tid]) {
            @mount_device_broken = (uint64)1;
        } else {
            @mount_device_pending[tid] = 1;
            @mount_device_inflight = @mount_device_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_p_info = (uint64)0;
            $v_p_fsdev = (uint64)0;
            $v_p_device = (uint64)0;
            $v_p_bdev = (uint64)0;
            $v_p_mnt = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_mount_flags = (uint64)0;
            $v_physical = (uint64)0;
            $v_devt = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $mnt = $file->f_path.mnt;
            if ($mnt != 0) {
                $v_p_mnt = (uint64)($mnt);
                $v_mount_flags = (uint64)($mnt->mnt_flags);
            }
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $info = $root->fs_info;
                    if ($info != 0) {
                        $v_p_info = (uint64)($info);
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            $v_p_fsdev = (uint64)($fsdev);
                            $device = $fsdev->latest_dev;
                            if ($device != 0) {
                                $v_p_device = (uint64)($device);
                                $v_devt = (uint64)($device->devt);
                                $bdev = $device->bdev;
                                if ($bdev != 0) {
                                    $v_p_bdev = (uint64)($bdev);
                                    $v_physical = (uint64)($bdev->bd_dev);
                                    if ($iter != 0 && $mnt != 0) { $valid = (uint64)1; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    $v_valid = ($valid);
            @mount_device_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_p_info, $v_p_fsdev, $v_p_device, $v_p_bdev, $v_p_mnt, $v_start, $v_count, $v_valid, $v_mount_flags, $v_physical, $v_devt);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @mount_device_pending[tid]/
{
    $saved = @mount_device_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $mnt = $file->f_path.mnt;
            if ($mnt != 0) {
                if ((uint64)($mnt) != $saved.8) { $stable = (uint64)0; }
                if ((uint64)($mnt->mnt_flags) != $saved.12) { $stable = (uint64)0; }
            }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    $info = $root->fs_info;
                    if ($info != 0) {
                        if ((uint64)($info) != $saved.4) { $stable = (uint64)0; }
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            if ((uint64)($fsdev) != $saved.5) { $stable = (uint64)0; }
                            $device = $fsdev->latest_dev;
                            if ($device != 0) {
                                if ((uint64)($device) != $saved.6) { $stable = (uint64)0; }
                                if ((uint64)($device->devt) != $saved.14) { $stable = (uint64)0; }
                                $bdev = $device->bdev;
                                if ($bdev != 0) {
                                    if ((uint64)($bdev) != $saved.7) { $stable = (uint64)0; }
                                    if ((uint64)($bdev->bd_dev) != $saved.13) { $stable = (uint64)0; }
                                    if (1 && $mnt != 0) { $valid = (uint64)1; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if ($valid != 1 || $saved.11 != 1) { $stable = (uint64)0; }
    if (@mount_device_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.9 == 0) { $event = (uint64)1; }
    else if ($saved.9 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_MOUNT_DEVICE event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu mount_ro=%llu major=%llu minor=%llu dev_major=%llu dev_minor=%llu\n", $event, $saved.9, $saved.10, $end, (int64)retval, $valid, $stable, (uint64)(($saved.12 & (uint64)64) != 0), $saved.13 >> 20, $saved.13 & (uint64)1048575, $saved.14 >> 20, $saved.14 & (uint64)1048575);
    $saved_deleted = delete(@mount_device_saved, tid);
    $pending_deleted = delete(@mount_device_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @mount_device_inflight = @mount_device_inflight - 1;
    } else {
        @mount_device_broken = (uint64)1;
    }
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@fs_state_pending[tid]) {
            @fs_state_broken = (uint64)1;
        } else {
            @fs_state_pending[tid] = 1;
            @fs_state_inflight = @fs_state_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_p_info = (uint64)0;
            $v_p_fsdev = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_num_devices = (uint64)0;
            $v_open_devices = (uint64)0;
            $v_total_devices = (uint64)0;
            $v_missing_devices = (uint64)0;
            $v_seeding = (uint64)0;
            $v_temp_fsid = (uint64)0;
            $v_seed_next = (uint64)0;
            $v_seed_prev = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $info = $root->fs_info;
                    if ($info != 0) {
                        $v_p_info = (uint64)($info);
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            $v_p_fsdev = (uint64)($fsdev);
                            $v_num_devices = ($fsdev->num_devices);
                            $v_open_devices = ($fsdev->open_devices);
                            $v_total_devices = ($fsdev->total_devices);
                            $v_missing_devices = ($fsdev->missing_devices);
                            $v_seeding = (uint64)($fsdev->seeding);
                            $v_temp_fsid = (uint64)($fsdev->temp_fsid);
                            $v_seed_next = (uint64)($fsdev->seed_list.next);
                            $v_seed_prev = (uint64)($fsdev->seed_list.prev);
                            if ($iter != 0) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    $v_valid = ($valid);
            @fs_state_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_p_info, $v_p_fsdev, $v_start, $v_count, $v_valid, $v_num_devices, $v_open_devices, $v_total_devices, $v_missing_devices, $v_seeding, $v_temp_fsid, $v_seed_next, $v_seed_prev);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @fs_state_pending[tid]/
{
    $saved = @fs_state_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    $info = $root->fs_info;
                    if ($info != 0) {
                        if ((uint64)($info) != $saved.4) { $stable = (uint64)0; }
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            if ((uint64)($fsdev) != $saved.5) { $stable = (uint64)0; }
                            if (($fsdev->num_devices) != $saved.9) { $stable = (uint64)0; }
                            if (($fsdev->open_devices) != $saved.10) { $stable = (uint64)0; }
                            if (($fsdev->total_devices) != $saved.11) { $stable = (uint64)0; }
                            if (($fsdev->missing_devices) != $saved.12) { $stable = (uint64)0; }
                            if ((uint64)($fsdev->seeding) != $saved.13) { $stable = (uint64)0; }
                            if ((uint64)($fsdev->temp_fsid) != $saved.14) { $stable = (uint64)0; }
                            if ((uint64)($fsdev->seed_list.next) != $saved.15) { $stable = (uint64)0; }
                            if ((uint64)($fsdev->seed_list.prev) != $saved.16) { $stable = (uint64)0; }
                            if (1) { $valid = (uint64)1; }
                        }
                    }
                }
            }
        }
    }
    if ($valid != 1 || $saved.8 != 1) { $stable = (uint64)0; }
    if (@fs_state_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.6 == 0) { $event = (uint64)1; }
    else if ($saved.6 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_FS_STATE event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu num_devices=%llu open_devices=%llu total_devices=%llu missing_devices=%llu seeding=%llu temp_fsid=%llu seed_empty=%llu\n", $event, $saved.6, $saved.7, $end, (int64)retval, $valid, $stable, $saved.9, $saved.10, $saved.11, $saved.12, $saved.13, $saved.14, (uint64)($saved.15 == ($saved.5 + (uint64)offsetof(struct btrfs_fs_devices, seed_list)) && $saved.16 == ($saved.5 + (uint64)offsetof(struct btrfs_fs_devices, seed_list))));
    $saved_deleted = delete(@fs_state_saved, tid);
    $pending_deleted = delete(@fs_state_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @fs_state_inflight = @fs_state_inflight - 1;
    } else {
        @fs_state_broken = (uint64)1;
    }
}

kprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid/
{
    $iocb = (struct kiocb *)arg0;
    $iter = (struct iov_iter *)arg1;
    $file = (struct file *)0;
    $match = (uint64)1;
    if ($iocb != 0) { $file = $iocb->ki_filp; }
    if ($file != 0) {
        $inode = $file->f_inode;
        if ($inode != 0) { $match = (uint64)($inode->i_ino == $1); }
    }
    if ($match == 1) {
        if (@dev_state_pending[tid]) {
            @dev_state_broken = (uint64)1;
        } else {
            @dev_state_pending[tid] = 1;
            @dev_state_inflight = @dev_state_inflight + 1;
            $v_p_iocb = (uint64)0;
            $v_p_file = (uint64)0;
            $v_p_inode = (uint64)0;
            $v_p_root = (uint64)0;
            $v_p_info = (uint64)0;
            $v_p_fsdev = (uint64)0;
            $v_p_device = (uint64)0;
            $v_p_bdev = (uint64)0;
            $v_start = (uint64)0;
            $v_count = (uint64)0;
            $v_valid = (uint64)0;
            $v_device_state = (uint64)0;
            $v_device_fsdev_address = (uint64)0;
            $valid = (uint64)0;
            if ($iocb != 0) { $v_start = (uint64)$iocb->ki_pos; }
            if ($iter != 0) { $v_count = $iter->count; }
    if ($iocb != 0) {
        $v_p_iocb = (uint64)($iocb);
        $file = $iocb->ki_filp;
        if ($file != 0) {
            $v_p_file = (uint64)($file);
            $inode = $file->f_inode;
            if ($inode != 0) {
                $v_p_inode = (uint64)($inode);
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    $v_p_root = (uint64)($root);
                    $info = $root->fs_info;
                    if ($info != 0) {
                        $v_p_info = (uint64)($info);
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            $v_p_fsdev = (uint64)($fsdev);
                            $device = $fsdev->latest_dev;
                            if ($device != 0) {
                                $v_p_device = (uint64)($device);
                                $v_device_state = ($device->dev_state);
                                $v_device_fsdev_address = (uint64)($device->fs_devices);
                                $bdev = $device->bdev;
                                if ($bdev != 0) {
                                    $v_p_bdev = (uint64)($bdev);
                                    if ($iter != 0) { $valid = (uint64)1; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    $v_valid = ($valid);
            @dev_state_saved[tid] = ($v_p_iocb, $v_p_file, $v_p_inode, $v_p_root, $v_p_info, $v_p_fsdev, $v_p_device, $v_p_bdev, $v_start, $v_count, $v_valid, $v_device_state, $v_device_fsdev_address);
        }
    }
}

kretprobe:btrfs_file_read_iter
/pid == cpid && tid == cpid && @dev_state_pending[tid]/
{
    $saved = @dev_state_saved[tid];
    $iocb = (struct kiocb *)(int64)$saved.0;
    $valid = (uint64)0;
    $stable = (uint64)1;
    $end = (uint64)0;
    if ($iocb != 0) { $end = (uint64)$iocb->ki_pos; }
    if ($iocb != 0) {
        if ((uint64)($iocb) != $saved.0) { $stable = (uint64)0; }
        $file = $iocb->ki_filp;
        if ($file != 0) {
            if ((uint64)($file) != $saved.1) { $stable = (uint64)0; }
            $inode = $file->f_inode;
            if ($inode != 0) {
                if ((uint64)($inode) != $saved.2) { $stable = (uint64)0; }
                $root = ((struct btrfs_inode *)((int64)$inode - (int64)offsetof(struct btrfs_inode, vfs_inode)))->root;
                if ($root != 0) {
                    if ((uint64)($root) != $saved.3) { $stable = (uint64)0; }
                    $info = $root->fs_info;
                    if ($info != 0) {
                        if ((uint64)($info) != $saved.4) { $stable = (uint64)0; }
                        $fsdev = $info->fs_devices;
                        if ($fsdev != 0) {
                            if ((uint64)($fsdev) != $saved.5) { $stable = (uint64)0; }
                            $device = $fsdev->latest_dev;
                            if ($device != 0) {
                                if ((uint64)($device) != $saved.6) { $stable = (uint64)0; }
                                if (($device->dev_state) != $saved.11) { $stable = (uint64)0; }
                                if ((uint64)($device->fs_devices) != $saved.12) { $stable = (uint64)0; }
                                $bdev = $device->bdev;
                                if ($bdev != 0) {
                                    if ((uint64)($bdev) != $saved.7) { $stable = (uint64)0; }
                                    if (1) { $valid = (uint64)1; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if ($valid != 1 || $saved.10 != 1) { $stable = (uint64)0; }
    if (@dev_state_broken) { $stable = (uint64)0; }
    $event = (uint64)0;
    if ($saved.8 == 0) { $event = (uint64)1; }
    else if ($saved.8 == $2) { $event = (uint64)2; }
    printf("QA_OVERLAY_BPF_DEV_STATE event=%llu start=%llu count=%llu end=%llu retval=%lld valid=%llu stable=%llu device_link=%llu device_clean=%llu\n", $event, $saved.8, $saved.9, $end, (int64)retval, $valid, $stable, (uint64)($saved.12 == $saved.5), (uint64)(($saved.11 & (uint64)12) == 0));
    $saved_deleted = delete(@dev_state_saved, tid);
    $pending_deleted = delete(@dev_state_pending, tid);
    if ($saved_deleted && $pending_deleted) {
        @dev_state_inflight = @dev_state_inflight - 1;
    } else {
        @dev_state_broken = (uint64)1;
    }
}

END
{
    printf("QA_OVERLAY_BPF_COMPLETE schema=1 pending=%llu\n", (uint64)(@core_inflight != 0 || @core_broken != 0 || @uuid_a_inflight != 0 || @uuid_a_broken != 0 || @uuid_b_inflight != 0 || @uuid_b_broken != 0 || @mount_device_inflight != 0 || @mount_device_broken != 0 || @fs_state_inflight != 0 || @fs_state_broken != 0 || @dev_state_inflight != 0 || @dev_state_broken != 0));
    clear(@core_saved);
    clear(@core_pending);
    clear(@core_inflight);
    clear(@core_broken);
    clear(@uuid_a_saved);
    clear(@uuid_a_pending);
    clear(@uuid_a_inflight);
    clear(@uuid_a_broken);
    clear(@uuid_b_saved);
    clear(@uuid_b_pending);
    clear(@uuid_b_inflight);
    clear(@uuid_b_broken);
    clear(@mount_device_saved);
    clear(@mount_device_pending);
    clear(@mount_device_inflight);
    clear(@mount_device_broken);
    clear(@fs_state_saved);
    clear(@fs_state_pending);
    clear(@fs_state_inflight);
    clear(@fs_state_broken);
    clear(@dev_state_saved);
    clear(@dev_state_pending);
    clear(@dev_state_inflight);
    clear(@dev_state_broken);
}
SNAPSHOT_BACKING_BPF
}

snapshot_backing_checker_program() {
    cat <<'SNAPSHOT_CHECKER_PY'
#!/usr/bin/env python3
"""Strictly consume the bounded disposable overlay BPF fixture protocol."""
import json
import os
import re
import stat
import sys

MARKER = "grub-20261004T000000Z-aabbccdd\n"
ATTACHED = "QA_OVERLAY_BPF_ATTACHED schema=1"
COMPLETE = "QA_OVERLAY_BPF_COMPLETE schema=1 pending=0"
BANNER = "Attaching 14 probes..."

class ProofError(Exception):
    pass

def verify(phase, stdout, stderr, expected, status):
    if phase not in {"positive", "negative"} or type(status) is not int or status != 0:
        raise ProofError("native-status")
    if not isinstance(expected, dict) or set(expected) != {"markerInode", "rootId", "fsUuid", "readOnly", "markerText", "major", "minor"}:
        raise ProofError("expected-schema")
    if (any(type(expected[key]) is not int or not 0 < expected[key] < 2**64 for key in ("markerInode", "rootId"))
            or type(expected["major"]) is not int or not 0 < expected["major"] < 4096
            or type(expected["minor"]) is not int or not 0 <= expected["minor"] < 1048576
            or not isinstance(expected["fsUuid"], str)
            or not re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", expected["fsUuid"])
            or expected["fsUuid"].replace("-", "") == "0" * 32
            or expected["readOnly"] is not True or not isinstance(expected["markerText"], str)
            or not re.fullmatch(r"grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}\n", expected["markerText"])):
        raise ProofError("expected-value")
    marker = expected["markerText"]
    if stderr:
        raise ProofError("stderr")
    if len(stdout) > 65536:
        raise ProofError("stdout-bound")
    try:
        lines = stdout.decode("ascii", errors="strict").splitlines()
    except UnicodeError:
        raise ProofError("stdout-encoding") from None
    if (lines.count(ATTACHED) != 1 or lines.count(COMPLETE) != 1 or lines.count(BANNER) > 1
            or lines.index(ATTACHED) >= lines.index(COMPLETE)):
        raise ProofError("control")
    if (lines.count(marker.strip()) != 1 or stdout.count(marker.encode()) != 1
            or not lines.index(ATTACHED) < lines.index(marker.strip()) < lines.index(COMPLETE)):
        raise ProofError("marker")
    number = r"(0|[1-9][0-9]{0,19})"
    common = ("start", "count", "end", "retval", "valid", "stable")
    layouts = {
        "CORE": ("inode", "root_id", "ro"),
        "UUID_A": ("fsid",),
        "UUID_B": ("fsid",),
        "MOUNT_DEVICE": ("mount_ro", "major", "minor", "dev_major", "dev_minor"),
        "FS_STATE": ("num_devices", "open_devices", "total_devices", "missing_devices", "seeding", "temp_fsid", "seed_empty"),
        "DEV_STATE": ("device_link", "device_clean"),
    }
    patterns = {}
    for group, fields in layouts.items():
        pattern = "QA_OVERLAY_BPF_" + group + r" event=([12])"
        for field in common + fields:
            value = r"([a-f0-9]{16})" if field == "fsid" else (r"(0|[1-9][0-9]{0,18}|-[1-9][0-9]{0,18})" if field == "retval" else number)
            pattern += " " + field + "=" + value
        patterns[group] = re.compile(pattern)
    events = {}
    for position, line in enumerate(lines):
        if line in {"", BANNER, ATTACHED, COMPLETE, marker.strip()}:
            continue
        found = None
        for group, pattern in patterns.items():
            match = pattern.fullmatch(line)
            if match:
                found = group, match
                break
        if (found is None or len(line.encode("ascii")) > 256
                or not lines.index(ATTACHED) < position < lines.index(COMPLETE)):
            raise ProofError("stdout-row")
        group, match = found
        event, *values = match.groups()
        groups = events.setdefault(int(event), {})
        if group in groups:
            raise ProofError("group-duplicate")
        groups[group] = dict(zip(common + layouts[group], values))
    if phase == "negative":
        if events:
            raise ProofError("negative-count")
        return 0, 0
    if set(events) not in ({1}, {1, 2}):
        raise ProofError("event-count")
    data = eof = 0
    required = {"mount_ro": 1, "major": expected["major"], "minor": expected["minor"], "dev_major": expected["major"], "dev_minor": expected["minor"], "num_devices": 1, "open_devices": 1, "total_devices": 1, "missing_devices": 0, "seeding": 0, "temp_fsid": 0, "seed_empty": 1, "device_link": 1, "device_clean": 1}
    length = len(marker.encode("ascii"))
    for event, groups in events.items():
        if set(groups) != set(layouts):
            raise ProofError("group-count")
        core = groups["CORE"]
        for group in groups.values():
            if group["valid"] != "1" or group["stable"] != "1":
                raise ProofError("read-backing")
            if any(group[field] != core[field] for field in common):
                raise ProofError("call-mismatch")
        wanted = (0, length + 1, length, length) if event == 1 else (length, 1, length, 0)
        if tuple(int(core[field]) for field in common[:4]) != wanted:
            raise ProofError("call-identity")
        if (int(core["inode"]) != expected["markerInode"] or int(core["root_id"]) != expected["rootId"] or core["ro"] != "1"
                or groups["UUID_A"]["fsid"] + groups["UUID_B"]["fsid"] != expected["fsUuid"].replace("-", "")):
            raise ProofError("read-identity")
        backing = {field: int(value) for group in ("MOUNT_DEVICE", "FS_STATE", "DEV_STATE") for field, value in groups[group].items() if field not in common}
        if backing != required:
            raise ProofError("read-backing")
        if event == 1:
            data += 1
        else:
            eof += 1
    if data != 1 or eof > 1:
        raise ProofError("positive-count")
    return data, eof

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProofError("duplicate-json")
        result[key] = value
    return result

def bounded_file(path, cap):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ProofError("input-type")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            raw = stream.read(cap + 1)
        if len(raw) > cap:
            raise ProofError("input-bound")
        return raw
    finally:
        os.close(fd)

def main(args):
    try:
        if len(args) != 5 or not re.fullmatch(r"0|-?[1-9][0-9]{0,8}", args[4]):
            raise ProofError("arguments")
        phase, stdout, stderr, expected, status = args
        expected = json.loads(bounded_file(expected, 4096), object_pairs_hook=unique_object)
        data, eof = verify(phase, bounded_file(stdout, 65536), bounded_file(stderr, 4096), expected, int(status))
    except ProofError as error:
        print("QA_OVERLAY_BPF_CHECK_FAIL reason=" + str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, UnicodeError, TypeError):
        print("QA_OVERLAY_BPF_CHECK_FAIL reason=input", file=sys.stderr)
        return 1
    print(f"QA_OVERLAY_BPF_CHECK_PASS phase={phase} read_events={data} eof_events={eof} marker_bytes={len(expected['markerText'].encode('ascii'))}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
SNAPSHOT_CHECKER_PY
}

snapshot_lowerdir_matches() {
    local lower="$1" subvol="$2" options
    [ "$(findmnt -nro FSTYPE --target "${lower}")" = btrfs ] || { snapshot_runtime_fail lower-filesystem; return 1; }
    [ "$(findmnt -nro FSROOT --target "${lower}")" = "/${subvol}" ] || { snapshot_runtime_fail lower-subvolume; return 1; }
    options="$(findmnt -nro OPTIONS --target "${lower}")" || { snapshot_runtime_fail lower-options-query; return 1; }
    case ",${options}," in *,ro,*) ;; *) snapshot_runtime_fail lower-readonly; return 1 ;; esac
}

snapshot_root_argument_matches() {
    local arguments_text="$1" device="$2" uuid="$3" partuuid="$4" argument count=0
    local -a arguments=()
    read -ra arguments <<<"${arguments_text}"
    for argument in "${arguments[@]}"; do
        case "${argument}" in
        root=*)
            count=$((count + 1))
            case "${argument}" in "root=${device}" | "root=UUID=${uuid}" | "root=PARTUUID=${partuuid}") ;; *) return 1 ;; esac
            ;;
        esac
    done
    [ "${count}" -eq 1 ]
}

create_snapshot_selector() {
    local inner="$1"
    python3 - "${run_id}" "${inner}" <<'SNAPSHOT_SELECTOR_PY'
import hashlib
import os
from pathlib import Path
import re
import sys
run, inner = sys.argv[1:]
if not re.fullmatch(r"grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}", run):
    raise ValueError("invalid snapshot selector run identity")
if not re.fullmatch(r"[ -~]{1,1024}", inner) or any(c in inner for c in "'\"\\$`;"):
    raise ValueError("unsafe snapshot selector title")
if len(inner.split(">")) < 2 or any(not part.strip() for part in inner.split(">")):
    raise ValueError("snapshot selector hierarchy absent")
parent = Path("/etc/grub.d")
if not parent.is_dir() or any(part.is_symlink() for part in (parent, *parent.parents)):
    raise ValueError("unsafe snapshot selector directory")
fragment = parent / ("42_qa_snapshot_" + run)
text = ("#!/bin/sh\nexec tail -n +3 \"$0\"\n"
        + "menuentry 'QA snapshot " + run + "' --id 'qa-snapshot-" + run + "' {\n"
        + "    set default='" + inner + "'\n    set timeout=0\n"
        + "    export default timeout\n"
        + '    configfile "${prefix}/grub-btrfs.cfg"\n}\n')
data = text.encode("ascii")
fd = os.open(fragment, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o700)
with os.fdopen(fd, "wb") as output:
    output.write(data)
    output.flush()
    os.fchmod(output.fileno(), 0o755)
print(hashlib.sha256(data).hexdigest())
SNAPSHOT_SELECTOR_PY
}

install_snapshot_selector() {
    local state="$1" entry="$2" cfg_sha selector_sha
    [ -f /boot/grub/grub-btrfs.cfg ] && [ ! -L /boot/grub/grub-btrfs.cfg ] || return 1
    cfg_sha="$(sha256sum -- /boot/grub/grub-btrfs.cfg | awk '{print $1}')"
    selector_sha="$(create_snapshot_selector "${entry}")" || return 1
    printf 'selector_sha256=%s\nproduction_cfg_sha256=%s\n' "${selector_sha}" "${cfg_sha}" >>"${state}"
    # Only the run-owned wrapper is added; production snapshot entries stay byte-identical.
    grub-mkconfig -o /boot/grub/grub.cfg || return 1
    grub-script-check /boot/grub/grub.cfg || return 1
    grub-script-check /boot/grub/grub-btrfs.cfg || return 1
    [ "$(sha256sum -- /boot/grub/grub-btrfs.cfg | awk '{print $1}')" = "${cfg_sha}" ] || return 1
    printf 'SNAPSHOT_ENTRY_DIAGNOSTIC wrapper=owned cfg_sha256=%s selector_sha256=%s\n'         "${cfg_sha}" "${selector_sha}" >&2
}

remove_snapshot_selector() {
    local state="$1" fragment="/etc/grub.d/42_qa_snapshot_${run_id}" expected
    [[ "${run_id}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || return 1
    [ -f "${fragment}" ] && [ ! -L "${fragment}" ] || return 1
    [ "$(stat -Lc '%u:%a:%h' -- "${fragment}")" = 0:755:1 ] || return 1
    [ "$(grep -c '^selector_sha256=' "${state}")" -eq 1 ] || return 1
    expected="$(sed -n 's/^selector_sha256=//p' "${state}")"
    [[ "${expected}" =~ ^[a-f0-9]{64}$ ]] || return 1
    [ "$(sha256sum -- "${fragment}" | awk '{print $1}')" = "${expected}" ] || return 1
    rm -- "${fragment}" || return 1
}

snapshot_state_program() {
    cat <<'SNAPSHOT_STATE_PY'
import array
import fcntl
import os
import re
import stat
import sys

FIELDS = {"run_id", "subvol", "root_uuid", "normal_boot_id", "root_device", "root_partuuid", "selector_sha256", "production_cfg_sha256", "snapshot_root_id", "snapshot_marker_inode", "root_major", "root_minor"}
def parse_state(raw, run, subvol):
    if len(raw) > 4096 or not raw.endswith(b"\n"):
        raise ValueError("state bound")
    lines = raw.decode("ascii").splitlines()
    fields = {}
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or key in fields or key not in FIELDS:
            raise ValueError("state closure")
        fields[key] = value
    if len(lines) != 12 or set(fields) != FIELDS:
        raise ValueError("state closure")
    if (not re.fullmatch(r"grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}", run)
            or fields["run_id"] != run or fields["subvol"] != subvol
            or subvol != "@snapshots/qa-" + run):
        raise ValueError("state identity")
    for key in ("root_uuid", "normal_boot_id", "root_partuuid"):
        if not re.fullmatch(r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", fields[key]):
            raise ValueError("state UUID")
    for key in ("selector_sha256", "production_cfg_sha256"):
        if not re.fullmatch(r"[a-f0-9]{64}", fields[key]):
            raise ValueError("state hash")
    if not re.fullmatch(r"/dev/[a-zA-Z0-9_/-]{1,128}", fields["root_device"]):
        raise ValueError("state device")
    for key in ("snapshot_root_id", "snapshot_marker_inode", "root_major", "root_minor"):
        if not re.fullmatch(r"0|[1-9][0-9]{0,19}", fields[key]):
            raise ValueError("state number")
    if (not 0 < int(fields["snapshot_root_id"]) < 2**64
            or not 0 < int(fields["snapshot_marker_inode"]) < 2**64
            or not 0 < int(fields["root_major"]) < 4096
            or not 0 <= int(fields["root_minor"]) < 1048576):
        raise ValueError("state range")
    return fields

def check_metadata(fd, value):
    if not stat.S_ISREG(value.st_mode) or value.st_uid != 0 or value.st_nlink != 1:
        raise ValueError("state ownership")
    mode = stat.S_IMODE(value.st_mode)
    if mode == 0o600:
        return
    if mode != 0o700:
        raise ValueError("state ownership")
    # VFAT synthesizes 0700 under fmask=0077. Prove FAT on this retained FD;
    # POSIX execute permission alone never permits an exception.
    attributes = array.array("I", [0])
    if attributes.itemsize != 4:
        raise ValueError("state attributes")
    try:
        fcntl.ioctl(fd, 0x80047210, attributes, True)  # FAT_IOCTL_GET_ATTRIBUTES
    except OSError:
        raise ValueError("state ownership") from None

def identity(value):
    return (value.st_dev, value.st_ino, value.st_mode, value.st_uid, value.st_gid, value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns)

def load_metadata(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        check_metadata(fd, before)
        if identity(before) != identity(os.fstat(fd)):
            raise ValueError("state changed")
    finally:
        os.close(fd)

def load_state(path, run, subvol):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        check_metadata(fd, before)
        raw = os.read(fd, 4097)
        fields = parse_state(raw, run, subvol)
        after = os.fstat(fd)
        if len(raw) != before.st_size or identity(before) != identity(after):
            raise ValueError("state changed")
        return fields
    finally:
        os.close(fd)

if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--metadata":
            load_metadata(sys.argv[2])
        else:
            load_state(*sys.argv[1:])
    except (OSError, ValueError, UnicodeError, TypeError):
        raise SystemExit(1)

SNAPSHOT_STATE_PY
}

snapshot_validate_state() {
    python3 - "$1" "${run_id}" "$2" < <(snapshot_state_program)
}

snapshot_validate_metadata() {
    python3 - --metadata "$1" < <(snapshot_state_program)
}

snapshot_device_numbers() {
    python3 - "$1" <<'SNAPSHOT_DEVICE_PY'
import os
import stat
import sys
try:
    fd = os.open(sys.argv[1], os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        value = os.fstat(fd)
        if not stat.S_ISBLK(value.st_mode):
            raise ValueError("not a partition")
        print(str(os.major(value.st_rdev)) + ":" + str(os.minor(value.st_rdev)))
    finally:
        os.close(fd)
except (OSError, ValueError):
    raise SystemExit(1)
SNAPSHOT_DEVICE_PY
}

snapshot_expected_readback() {
    local path="$1" device="$2" subvol="$3" uuid="$4" root_id="$5" inode="$6" marker metadata
    mount -o "ro,nosuid,nodev,noexec,subvol=${subvol}" -- "${device}" "${path}" || { snapshot_runtime_fail lower-source-query; return 1; }
    snapshot_lowerdir_matches "${path}" "${subvol}" || return 1
    [ "$(findmnt -nro UUID --target "${path}")" = "${uuid}" ] || { snapshot_runtime_fail lower-uuid; return 1; }
    [ "$(mounted_source_device "${path}")" = "${device}" ] || { snapshot_runtime_fail target-partition; return 1; }
    [ "$(btrfs property get -ts "${path}" ro)" = ro=true ] || { snapshot_runtime_fail lower-property; return 1; }
    [ "$(btrfs inspect-internal rootid "${path}")" = "${root_id}" ] || { snapshot_runtime_fail lower-subvolume; return 1; }
    marker="${path}/var/lib/arch-linux-vm/snapshot-marker"
    [ -f "${marker}" ] && [ ! -L "${marker}" ] || { snapshot_runtime_fail lower-marker; return 1; }
    metadata="$(stat -Lc '%u:%a:%h:%s' -- "${marker}")" || { snapshot_runtime_fail lower-marker; return 1; }
    if [[ ! "${metadata}" =~ ^0:([0-7]{3,4}):1:$(( ${#run_id} + 1 ))$ ]]; then
        snapshot_runtime_fail lower-marker; return 1
    fi
    if (( (8#${BASH_REMATCH[1]} & 022) != 0 )); then
        snapshot_runtime_fail lower-marker; return 1
    fi
    [ "$(stat -Lc '%i' -- "${marker}")" = "${inode}" ] &&
        [ "$(cat -- "${marker}")" = "${run_id}" ] || { snapshot_runtime_fail lower-marker; return 1; }
}

snapshot_backing_executor_program() {
    cat <<'SNAPSHOT_EXECUTOR_SH'
set -euo pipefail
work=$1 device=$2 subvol=$3 uuid=$4 root_id=$5 inode=$6 run_id=$7 phase=$8
trace_owned=0 tmp_owned=0
trap 'status=$?; trap - EXIT; if [ "$trace_owned" = 1 ]; then umount -- /sys/kernel/tracing || status=1; fi; if [ "$tmp_owned" = 1 ]; then umount -- /tmp || status=1; fi; if mountpoint -q "$work/readback"; then umount -- "$work/readback" || status=1; fi; exit "$status"' EXIT
snapshot_expected_readback "$work/readback" "$device" "$subvol" "$uuid" "$root_id" "$inode" || exit 1
# This mount validates expected identities only. The observed reader always opens '/'.
umount -- "$work/readback" || exit 1
mount -t tmpfs -o size=128m,mode=1777,nosuid,nodev tmpfs /tmp || exit 1
tmp_owned=1
mount -t tracefs -o nosuid,nodev,noexec tracefs /sys/kernel/tracing || exit 1
trace_owned=1
status=0
(ulimit -f 128; timeout -k 2 -s INT 60 bpftrace -q -c "/usr/bin/python3 -B -I -S $work/reader.py $run_id" "$work/probe.bt" "$inode" "$(( ${#run_id} + 1 ))") >"$work/probe.stdout" 2>"$work/probe.stderr" || status=$?
python3 -B -I -S "$work/checker.py" positive "$work/probe.stdout" "$work/probe.stderr" "$work/expected.json" "$status" || exit 1
SNAPSHOT_EXECUTOR_SH
}

verify_snapshot_backing() {
(
    local device="$1" subvol="$2" uuid="$3" root_id="$4" inode="$5" major="$6" minor="$7"
    local work status=0 diagnostic=0 tool reason
    for tool in bpftrace unshare python3 timeout mount umount mountpoint; do
        command -v "${tool}" >/dev/null || { snapshot_runtime_fail lower-source-query; return 1; }
    done
    work="$(mktemp -d /run/qa-snapshot.XXXXXXXX)" || { snapshot_runtime_fail lower-source-query; return 1; }
    trap 'status=$?; trap - EXIT; rm -f -- "$work/probe.bt" "$work/reader.py" "$work/checker.py" "$work/expected.json" "$work/executor.sh" "$work/probe.stdout" "$work/probe.stderr" "$work/executor.stdout" "$work/executor.stderr" || status=1; rmdir -- "$work/readback" "$work" || status=1; if [ "$status" != 0 ] && [ "$diagnostic" = 0 ]; then snapshot_runtime_fail lower-source-query; fi; exit "$status"' EXIT
    mkdir -- "${work}/readback" || return 1
    snapshot_backing_probe_program >"${work}/probe.bt" || return 1
    snapshot_overlay_reader_program >"${work}/reader.py" || return 1
    snapshot_backing_checker_program >"${work}/checker.py" || return 1
    {
        declare -f snapshot_runtime_fail snapshot_lowerdir_matches mounted_source_device snapshot_expected_readback || return 1
        snapshot_backing_executor_program
    } >"${work}/executor.sh" || return 1
    python3 - "${work}/expected.json" "${uuid}" "${root_id}" "${inode}" "${major}" "${minor}" "${run_id}" <<'SNAPSHOT_EXPECTED_PY' || return 1
import json
import sys
path, uuid, root_id, inode, major, minor, run = sys.argv[1:]
with open(path, "x", encoding="ascii") as output:
    json.dump({"markerInode": int(inode), "rootId": int(root_id), "fsUuid": uuid.lower(), "readOnly": True, "markerText": run + "\n", "major": int(major), "minor": int(minor)}, output)
SNAPSHOT_EXPECTED_PY
    (ulimit -f 128; timeout -k 2 90 unshare --mount --propagation private -- /usr/bin/bash --noprofile --norc "${work}/executor.sh" "${work}" "${device}" "${subvol}" "${uuid}" "${root_id}" "${inode}" "${run_id}" "${phase}") >"${work}/executor.stdout" 2>"${work}/executor.stderr" || status=$?
    if [ "${status}" -ne 0 ]; then
        reason="$(sed -n "s/^SNAPSHOT_RUNTIME_DIAGNOSTIC run_id=${run_id} phase=${phase} reason=\([a-z-]*\)$/\1/p" "${work}/executor.stderr")"
        [[ "${reason}" != *$'\n'* ]] && [ -n "${reason}" ] || reason="lower-source-query"
        diagnostic=1
        snapshot_runtime_fail "${reason}"
        return 1
    fi
    return 0
)
}

snapshot_prepare_fail() {
    local step="$1"
    [[ "${run_id}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || return 1
    case "${step}" in device-identity | state-validation | grub-reboot) ;; *) return 1 ;; esac
    printf 'SNAPSHOT_PREPARE_DIAGNOSTIC run_id=%s phase=snapshot-prepare step=%s status=failed\n' \
        "${run_id}" "${step}" >&2
    return 1
}

prepare_snapshot_boot() {
    local subvol="@snapshots/qa-${run_id}" path="/.snapshots/qa-${run_id}"
    local state="/boot/qa-snapshot-${run_id}.state" uuid entry device partuuid target root_id inode physical final_uuid final_partuuid
    [ "${scenario}" = stock-gnome-btrfs-grub ]
    [[ "${run_id}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || return 1
    [ ! -e "/etc/grub.d/42_qa_snapshot_${run_id}" ] &&
        [ ! -L "/etc/grub.d/42_qa_snapshot_${run_id}" ] || return 1
    verify_common >/dev/null
    verify_btrfs_contract
    [ ! -e "${path}" ] && [ ! -L "${path}" ] || return 1
    [ ! -e "${state}" ] && [ ! -L "${state}" ] || return 1
    install -d -m0700 /var/lib/arch-linux-vm
    [ ! -e /var/lib/arch-linux-vm/snapshot-marker ] && [ ! -L /var/lib/arch-linux-vm/snapshot-marker ] || return 1
    printf '%s\n' "${run_id}" >/var/lib/arch-linux-vm/snapshot-marker
    target="$(find_target)" || return 1
    device="$(mounted_source_device /)" || return 1
    [ "${device}" = "$(partition_name "${target}" 2)" ] && [ -b "${device}" ] || return 1
    uuid="$(blkid -s UUID -o value -- "${device}")" || return 1
    partuuid="$(blkid -s PARTUUID -o value -- "${device}")" || return 1
    [[ "${uuid}" =~ ^[a-fA-F0-9-]{36}$ ]] && [[ "${partuuid}" =~ ^[a-fA-F0-9-]{36}$ ]] || return 1
    [ "$(findmnt -nro UUID --target /)" = "${uuid}" ] || return 1
    printf 'run_id=%s\nsubvol=%s\nroot_uuid=%s\nnormal_boot_id=%s\nroot_device=%s\nroot_partuuid=%s\n' \
        "${run_id}" "${subvol}" "${uuid}" "$(cat /proc/sys/kernel/random/boot_id)" "${device}" "${partuuid}" >"${state}"
    btrfs subvolume snapshot -r / "${path}"
    [ "$(btrfs property get -ts "${path}" ro)" = ro=true ]
    root_id="$(btrfs inspect-internal rootid "${path}")" || return 1
    inode="$(stat -Lc '%i' -- "${path}/var/lib/arch-linux-vm/snapshot-marker")" || return 1
    physical="$(snapshot_device_numbers "${device}")" || return 1
    [[ "${root_id}" =~ ^[1-9][0-9]*$ ]] && [[ "${inode}" =~ ^[1-9][0-9]*$ ]] &&
        [[ "${physical}" =~ ^[1-9][0-9]*:[0-9]+$ ]] || return 1
    printf 'snapshot_root_id=%s\nsnapshot_marker_inode=%s\nroot_major=%s\nroot_minor=%s\n' \
        "${root_id}" "${inode}" "${physical%%:*}" "${physical#*:}" >>"${state}" || return 1
    # Discover the entry using the installed production grub-btrfs generator.
    grub-mkconfig -o /boot/grub/grub.cfg
    grub-script-check /boot/grub/grub.cfg
    grub-script-check /boot/grub/grub-btrfs.cfg
    entry="$(select_snapshot_grub_entry /boot/grub/grub.cfg /boot/grub/grub-btrfs.cfg "${uuid}" "${subvol}" "${device}" "${partuuid}" --inner)"
    install_snapshot_selector "${state}" "${entry}" || return 1
    final_uuid="$(blkid -s UUID -o value -- "${device}")" || { snapshot_prepare_fail device-identity; return 1; }
    final_partuuid="$(blkid -s PARTUUID -o value -- "${device}")" || { snapshot_prepare_fail device-identity; return 1; }
    [ "${final_uuid}" = "${uuid}" ] && [ "${final_partuuid}" = "${partuuid}" ] || { snapshot_prepare_fail device-identity; return 1; }
    snapshot_validate_state "${state}" "${subvol}" || { snapshot_prepare_fail state-validation; return 1; }
    grub-reboot "qa-snapshot-${run_id}" || { snapshot_prepare_fail grub-reboot; return 1; }
    emit_runtime_action_pass snapshot-production-entry-selected
}

verify_snapshot_runtime() {
    local state="/boot/qa-snapshot-${run_id}.state" subvol="@snapshots/qa-${run_id}"
    local options lower uuid cmdline target device partuuid root_id inode major minor
    [ "${scenario}" = stock-gnome-btrfs-grub ] || { snapshot_runtime_fail scenario; return 1; }
    [ -f "${state}" ] && [ ! -L "${state}" ] || { snapshot_runtime_fail state-file; return 1; }
    snapshot_validate_metadata "${state}" || { snapshot_runtime_fail state-mode; return 1; }
    [ "$(wc -l <"${state}")" -eq 12 ] || { snapshot_runtime_fail state-lines; return 1; }
    grep -qxF "run_id=${run_id}" "${state}" || { snapshot_runtime_fail state-run; return 1; }
    grep -qxF "subvol=${subvol}" "${state}" || { snapshot_runtime_fail state-subvolume; return 1; }
    [ "$(grep -c '^production_cfg_sha256=' "${state}")" -eq 1 ] || { snapshot_runtime_fail cfg-record; return 1; }
    [ "$(sha256sum -- /boot/grub/grub-btrfs.cfg | awk '{print $1}')" = \
        "$(sed -n 's/^production_cfg_sha256=//p' "${state}")" ] || { snapshot_runtime_fail cfg-hash; return 1; }
    uuid="$(sed -n 's/^root_uuid=//p' "${state}")"
    [[ "${uuid}" =~ ^[a-fA-F0-9-]{36}$ ]] || { snapshot_runtime_fail root-uuid; return 1; }
    [ "$(sed -n 's/^normal_boot_id=//p' "${state}")" != "$(cat /proc/sys/kernel/random/boot_id)" ] || { snapshot_runtime_fail boot-id; return 1; }
    [ "$(findmnt -nro FSTYPE --target /)" = overlay ] || { snapshot_runtime_fail root-filesystem; return 1; }
    options="$(findmnt -nro OPTIONS --target /)" || { snapshot_runtime_fail root-options-query; return 1; }
    lower="$(tr ',' '\n' <<<"${options}" | sed -n 's/^lowerdir=//p')"
    [[ "${lower}" = /* ]] && [[ "${lower}" != *:* ]] && [[ "${lower}" != *\\* ]] && [[ "${lower}" != *$'\n'* ]] || { snapshot_runtime_fail lower-shape; return 1; }
    target="$(find_target)" || { snapshot_runtime_fail target-query; return 1; }
    cmdline="$(cat /proc/cmdline)" || { snapshot_runtime_fail cmdline-query; return 1; }
    device="$(sed -n 's/^root_device=//p' "${state}")"
    partuuid="$(sed -n 's/^root_partuuid=//p' "${state}")"
    [ -b "${device}" ] || { snapshot_runtime_fail device-shape; return 1; }
    [ "${device}" = "$(partition_name "${target}" 2)" ] || { snapshot_runtime_fail target-partition; return 1; }
    [[ "${partuuid}" =~ ^[a-fA-F0-9-]{36}$ ]] || { snapshot_runtime_fail partuuid-shape; return 1; }
    [ "$(blkid -s UUID -o value -- "${device}")" = "${uuid}" ] &&
        [ "$(blkid -s PARTUUID -o value -- "${device}")" = "${partuuid}" ] || { snapshot_runtime_fail device-identity; return 1; }
    snapshot_validate_state "${state}" "${subvol}" || { snapshot_runtime_fail state-lines; return 1; }
    root_id="$(sed -n 's/^snapshot_root_id=//p' "${state}")"
    inode="$(sed -n 's/^snapshot_marker_inode=//p' "${state}")"
    major="$(sed -n 's/^root_major=//p' "${state}")"
    minor="$(sed -n 's/^root_minor=//p' "${state}")"
    [ "$(snapshot_device_numbers "${device}")" = "${major}:${minor}" ] || { snapshot_runtime_fail device-identity; return 1; }
    snapshot_root_argument_matches "${cmdline}" "${device}" "${uuid}" "${partuuid}" || { snapshot_runtime_fail root-argument; return 1; }
    require_kernel_argument_once "${cmdline}" systemd.volatile=overlay || { snapshot_runtime_fail volatile-argument; return 1; }
    options="$(tr ' ' '\n' <<<"${cmdline}" | sed -n 's/^rootflags=//p')"
    require_prefixed_kernel_argument_once "${cmdline}" rootflags= "rootflags=${options}" || { snapshot_runtime_fail rootflags-argument; return 1; }
    [ "$(tr ',' '\n' <<<"${options}" | sed -n 's/^subvol=//p')" = "${subvol}" ] || { snapshot_runtime_fail rootflags-subvolume; return 1; }
    verify_snapshot_backing "${device}" "${subvol}" "${uuid}" "${root_id}" "${inode}" "${major}" "${minor}" || return 1
    [ "$(blkid -s UUID -o value -- "${device}")" = "${uuid}" ] &&
        [ "$(blkid -s PARTUUID -o value -- "${device}")" = "${partuuid}" ] &&
        [ "$(snapshot_device_numbers "${device}")" = "${major}:${minor}" ] || { snapshot_runtime_fail device-identity; return 1; }
    verify_kernel_initramfs_pair /boot/initramfs-linux.img || { snapshot_runtime_fail kernel-initramfs; return 1; }
    verify_grub_efi_target || { snapshot_runtime_fail grub-efi; return 1; }
    verify_grub_package_integrity >/dev/null || { snapshot_runtime_fail grub-package; return 1; }
    systemctl is-active --quiet NetworkManager.service qemu-guest-agent.service || { snapshot_runtime_fail services; return 1; }
    nm-online -q --timeout=60 || { snapshot_runtime_fail network; return 1; }
    snapshot_failed_units || { snapshot_runtime_fail failed-units; return 1; }
    printf '%s' "${target}"
}

cleanup_snapshot_boot() {
    local path="/.snapshots/qa-${run_id}" state="/boot/qa-snapshot-${run_id}.state"
    [ "${scenario}" = stock-gnome-btrfs-grub ]
    [ "$(findmnt -nro FSROOT --target /)" = /@ ]
    [ -d "${path}" ] && [ ! -L "${path}" ] || return 1
    [ "$(cat -- "${path}/var/lib/arch-linux-vm/snapshot-marker")" = "${run_id}" ]
    [ "$(btrfs property get -ts "${path}" ro)" = ro=true ]
    [ -f "${state}" ] && [ ! -L "${state}" ] || return 1
    grep -qxF "run_id=${run_id}" "${state}"
    remove_snapshot_selector "${state}" || return 1
    btrfs subvolume delete -- "${path}"
    rm -- "${state}" /var/lib/arch-linux-vm/snapshot-marker
    grub-mkconfig -o /boot/grub/grub.cfg
    verify_common >/dev/null
    verify_btrfs_contract
    emit_runtime_action_pass snapshot-normal-root-restored-owned-cleanup
}

emit_runtime_action_pass() {
    printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s action=%s failed_units=0\n' \
        "${marker_prefix}" "${run_id}" "${scenario}" "${phase}" \
        "$(cat /proc/sys/kernel/random/boot_id)" "$1"
}

verify_btrfs_contract() {
    local target root_source root_device root_uuid root_partition='' expected_root_partition
    local root_partuuid='' luks_uuid='' root_argument luks_argument=''
    local main_options fallback_options cmdline device_stats filesystem_show filesystem_usage
    local crypt_status='' luks_dump='' luks_json='' encryption_contract='off'
    local mountpoint line source fstype options dump pass

    target="$(find_target)"
    expected_root_partition="$(readlink -f -- "$(partition_name "${target}" 2)")"
    [ -b "${expected_root_partition}" ]
    root_source="$(findmnt -nro SOURCE --target /)"
    root_device="$(readlink -f -- "${root_source%%\[*}")"
    [ -b "${root_device}" ]
    root_uuid="$(blkid -s UUID -o value -- "${root_device}")"
    [[ "${root_uuid}" =~ ^[A-Fa-f0-9-]{36}$ ]]

    if is_luks_stock; then
        [ "$(readlink -f -- /dev/mapper/cryptroot)" = "${root_device}" ]
        crypt_status="$(cryptsetup status -- cryptroot)"
        grep -Eq '^[[:space:]]*type:[[:space:]]+LUKS2$' <<<"${crypt_status}"
        grep -Eq '^[[:space:]]*cipher:[[:space:]]+aes-xts-plain64$' <<<"${crypt_status}"
        root_partition="$(awk '$1 == "device:" { print $2; exit }' <<<"${crypt_status}")"
        root_partition="$(readlink -f -- "${root_partition}")"
        [ -b "${root_partition}" ]
        [ "${root_partition}" = "${expected_root_partition}" ]
        cryptsetup isLuks --type luks2 -- "${root_partition}"
        luks_uuid="$(cryptsetup luksUUID "${root_partition}")"
        [[ "${luks_uuid}" =~ ^[A-Fa-f0-9-]{36}$ ]]
        luks_dump="$(cryptsetup luksDump --type luks2 -- "${root_partition}")"
        grep -Eq '^Version:[[:space:]]+2$' <<<"${luks_dump}"
        grep -Eq '^[[:space:]]*cipher:[[:space:]]+aes-xts-plain64$' <<<"${luks_dump}"
        luks_json="$(cryptsetup luksDump --dump-json-metadata -- "${root_partition}")"
        [ "$(grep -Ec '"key_size"[[:space:]]*:[[:space:]]*64[[:space:]]*[,}]' <<<"${luks_json}")" -eq 1 ]
        root_argument='root=/dev/mapper/cryptroot'
        luks_argument="rd.luks.name=${luks_uuid}=cryptroot"
        encryption_contract='luks2 mapper=cryptroot cipher=aes-xts-plain64 keysize=512bits plymouth=on'
        verify_luks_initramfs
    else
        root_partition="${root_device}"
        [ "${root_partition}" = "${expected_root_partition}" ]
        root_partuuid="$(lsblk -dnro PARTUUID -- "${root_partition}" | trim_value)"
        [[ "${root_partuuid}" =~ ^[A-Fa-f0-9-]+$ ]]
        root_argument="root=PARTUUID=${root_partuuid}"
    fi

    verify_btrfs_mount / /@ "${root_device}"
    verify_btrfs_mount /home /@home "${root_device}"
    verify_btrfs_mount /.snapshots /@snapshots "${root_device}"
    verify_btrfs_fstab_entry / @ "${root_uuid}"
    verify_btrfs_fstab_entry /home @home "${root_uuid}"
    verify_btrfs_fstab_entry /.snapshots @snapshots "${root_uuid}"

    if is_grub_stock; then
        main_options="$(verify_grub_config_contract "${root_argument}" "${luks_argument}")"
        verify_grub_runtime_contract "${root_argument}" "${luks_argument}"
    else
        main_options="$(verify_btrfs_boot_entry /boot/loader/entries/main.conf "${root_argument}" "${luks_argument}")"
        fallback_options="$(verify_btrfs_boot_entry /boot/loader/entries/main-fallback.conf "${root_argument}" "${luks_argument}")"
        [ "${main_options}" = "${fallback_options}" ]
    fi
    cmdline="$(tr -d '\n' </proc/cmdline)"
    require_kernel_argument_once "${cmdline}" 'rootflags=subvol=@'
    require_kernel_argument_once "${cmdline}" 'rootfstype=btrfs'
    if is_luks_stock; then
        require_prefixed_kernel_argument_once "${cmdline}" 'root=' "${root_argument}"
        require_prefixed_kernel_argument_once "${cmdline}" 'rd.luks.name=' "${luks_argument}"
        require_kernel_argument_once "${cmdline}" splash
    else
        require_kernel_argument_once "${cmdline}" "${root_argument}"
        reject_encrypted_root_arguments "${cmdline}"
    fi

    device_stats="$(btrfs device stats --check /)"
    filesystem_show="$(btrfs filesystem show /)"
    filesystem_usage="$(btrfs filesystem usage /)"
    [ -n "${filesystem_show}" ] && [ -n "${filesystem_usage}" ]

    printf 'BTRFS_QEMU_STORAGE_PROOF run_id=%s phase=%s root_device=%s root_partition=%s root_uuid=%s root_fsroot=/@ home_fsroot=/@home snapshots_fsroot=/@snapshots subvolumes=@,@home,@snapshots mount_policy=noatime,compress=zstd fstab=consistent device_errors=0\n' \
        "${run_id}" "${phase}" "${root_device}" "${root_partition}" "${root_uuid}"
    printf 'BTRFS_QEMU_BOOT_PROOF run_id=%s phase=%s root_argument=%s rootflags=subvol=@ rootfstype=btrfs encryption=%s main_options=%q\n' \
        "${run_id}" "${phase}" "${root_argument}" "${encryption_contract}" "${main_options}"
    if is_luks_stock; then
        printf 'LUKS_QEMU_PROOF run_id=%s phase=%s luks_uuid=%s root_partition=%s mapper=cryptroot mapper_device=%s type=LUKS2 cipher=aes-xts-plain64 keysize=512bits initramfs=systemd,sd-encrypt,plymouth\n' \
            "${run_id}" "${phase}" "${luks_uuid}" "${root_partition}" "${root_device}"
    fi
    for mountpoint in / /home /.snapshots; do
        line="$(fstab_line_for "${mountpoint}")"
        read -r source target fstype options dump pass <<<"${line}"
        printf 'BTRFS_QEMU_FSTAB_PROOF run_id=%s phase=%s source=%s target=%s fstype=%s options=%s dump=%s pass=%s\n' \
            "${run_id}" "${phase}" "${source}" "${target}" "${fstype}" "${options}" "${dump}" "${pass}"
    done
    printf 'BTRFS_QEMU_DEVICE_STATS run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${device_stats}"
    printf 'BTRFS_QEMU_FILESYSTEM_SHOW run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${filesystem_show}"
    printf 'BTRFS_QEMU_FILESYSTEM_USAGE run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${filesystem_usage}"
}

verify_minimal() {
    local target config forbidden_package boot_id console_devices framebuffer_name
    local framebuffer_index framebuffer_driver framebuffer_rows=0 framebuffer_vt=''
    [ "${phase}" = update ] && pacman -Syu --noconfirm --disable-download-timeout
    target="$(verify_common)"
    for forbidden_package in grub gdm gnome-shell fish starship; do
        if pacman -Q "${forbidden_package}" >/dev/null 2>&1; then
            printf 'unexpected package in minimal scenario: %s\n' "${forbidden_package}" >&2
            exit 1
        fi
    done
    [ -z "$(pacman -Qq | grep '^arch-linux-' || true)" ]
    [ "$(getent passwd "${username}" | cut -d: -f7)" = /bin/bash ]
    config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    grep -qx 'ARCH_LINUX_FILESYSTEM=ext4' "${config}"
    grep -qx 'ARCH_LINUX_BOOTLOADER=systemd' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_ENABLED=false' "${config}"
    grep -qx 'ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED=false' "${config}"
    [ "$(systemctl get-default)" = multi-user.target ]
    systemctl is-enabled --quiet getty@tty1.service
    systemctl is-active --quiet getty@tty1.service
    [ -r /sys/class/tty/tty0/active ]
    [ "$(tr -d '\n' </sys/class/tty/tty0/active)" = tty1 ]
    [ -r /sys/class/tty/console/active ]
    console_devices="$(tr -d '\n' </sys/class/tty/console/active)"
    [[ " ${console_devices} " = *' tty0 '* ]]
    [ -r /proc/fb ]
    while read -r framebuffer_index framebuffer_driver; do
        [[ "${framebuffer_index}" =~ ^[0-9]+$ ]]
        [[ "${framebuffer_driver}" =~ ^[A-Za-z0-9_.+-]+$ ]]
        framebuffer_rows=$((framebuffer_rows + 1))
    done </proc/fb
    [ "${framebuffer_rows}" -ge 1 ]
    [ -e /sys/class/graphics/fb0 ]
    [ -r /sys/class/graphics/fb0/name ]
    framebuffer_name="$(tr -d '\n' </sys/class/graphics/fb0/name)"
    [[ "${framebuffer_name}" =~ ^[A-Za-z0-9_.+\ -]+$ ]]
    [ -n "${framebuffer_name}" ]
    for framebuffer_vt in /sys/class/vtconsole/vtcon*; do
        [ -r "${framebuffer_vt}/name" ] && [ -r "${framebuffer_vt}/bind" ] || continue
        grep -Fqi 'frame buffer' "${framebuffer_vt}/name" || continue
        [ "$(tr -d '\n' <"${framebuffer_vt}/bind")" = 1 ] || continue
        break
    done
    [ -n "${framebuffer_vt}" ] && grep -Fqi 'frame buffer' "${framebuffer_vt}/name" &&
        [ "$(tr -d '\n' <"${framebuffer_vt}/bind")" = 1 ]
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    [[ "${boot_id}" =~ ^[a-f0-9-]{36}$ ]]
    printf 'MINIMAL_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s pttype=gpt root=ext4 bootloader=systemd-boot network=online failed_units=0 desktop=off shell_enhancement=off default_target=multi-user.target getty_tty1=active active_vt=tty1 kernel_console=tty0 framebuffer=%q fbcon=bound\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" "${framebuffer_name}"
}

verify_stock_profile() {
    local config="$1" gdm_environment gdm_dropins
    if is_btrfs_stock; then
        grep -qx 'ARCH_LINUX_FILESYSTEM=btrfs' "${config}"
        grep -qx 'ARCH_LINUX_BTRFS_SNAPPER_ENABLED=false' "${config}"
        grep -qx 'ARCH_LINUX_BTRFS_ASSISTANT_ENABLED=false' "${config}"
        # shellcheck disable=SC2251 # Intentional negative assertion inside this verification function.
        ! pacman -Q snapper >/dev/null 2>&1
        # shellcheck disable=SC2251 # Intentional negative assertion inside this verification function.
        ! pacman -Q btrfs-assistant >/dev/null 2>&1
        if is_luks_stock; then
            grep -qx 'ARCH_LINUX_ENCRYPTION_ENABLED=true' "${config}"
            grep -qx 'ARCH_LINUX_BOOTSPLASH_ENABLED=true' "${config}"
        else
            grep -qx 'ARCH_LINUX_ENCRYPTION_ENABLED=false' "${config}"
            grep -qx 'ARCH_LINUX_BOOTSPLASH_ENABLED=false' "${config}"
        fi
    else
        grep -qx 'ARCH_LINUX_FILESYSTEM=ext4' "${config}"
    fi
    if is_grub_stock; then
        grep -qx 'ARCH_LINUX_BOOTLOADER=grub' "${config}"
    else
        grep -qx 'ARCH_LINUX_BOOTLOADER=systemd' "${config}"
    fi
    grep -qx 'ARCH_LINUX_DESKTOP_ENABLED=true' "${config}"
    grep -qx 'ARCH_LINUX_GNOME_THEME_PROFILE=stock' "${config}"
    grep -qx 'ARCH_LINUX_GDM_THEME_PROFILE=stock' "${config}"
    grep -qx 'ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED=false' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER=mesa' "${config}"
    wait_for_graphical_stack
    [ "$(systemctl get-default)" = graphical.target ]
    systemctl is-enabled --quiet gdm.service
    systemctl is-active --quiet gdm.service
    systemctl is-active --quiet graphical.target
    verify_stock_project_packages
    verify_public_repository_contract
    [ ! -e /etc/dconf/profile/gdm ] && [ ! -L /etc/dconf/profile/gdm ]
    [ ! -e /etc/systemd/system/gdm.service.d/50-arch-linux-marble.conf ] &&
        [ ! -L /etc/systemd/system/gdm.service.d/50-arch-linux-marble.conf ]
    gdm_environment="$(systemctl show gdm.service --property=Environment --value)"
    [[ " ${gdm_environment} " != *' DCONF_PROFILE='* ]]
    gdm_dropins="$(systemctl show gdm.service --property=DropInPaths --value)"
    [[ "${gdm_dropins}" != *arch-linux-marble* ]]
    if [ -f /etc/gdm/custom.conf ]; then
        if grep -Eq '^[[:space:]]*(AutomaticLoginEnable|TimedLoginEnable)[[:space:]]*=[[:space:]]*true([[:space:]]*)$' \
            /etc/gdm/custom.conf; then
            return 1
        fi
    fi
}

verify_stock_greeter() {
    local target config greeter_session boot_id root_contract='root=ext4' bootloader_contract='systemd-boot'
    if [[ "${phase}" = snapshot-* ]]; then
        target="$(verify_snapshot_runtime)"
    else
        target="$(verify_common)"
    fi
    config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    verify_stock_profile "${config}"
    if is_btrfs_stock && [[ "${phase}" != snapshot-* ]]; then
        verify_btrfs_contract
        root_contract='root=btrfs btrfs_contract=verified encryption=off snapper=off btrfs_assistant=off'
        if is_luks_stock; then
            root_contract='root=btrfs btrfs_contract=verified encryption=luks2 mapper=cryptroot plymouth=on snapper=off btrfs_assistant=off'
        fi
    fi
    is_grub_stock && bootloader_contract='grub'
    [[ "${phase}" != snapshot-* ]] || root_contract='root=btrfs-snapshot root_mode=read-only overlay=volatile module_pair=verified'
    greeter_session="$(wait_for_greeter)"
    [ -n "${greeter_session}" ]
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    [[ "${boot_id}" =~ ^[a-f0-9-]{36}$ ]]
    printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s pttype=gpt %s bootloader=%s default_target=graphical.target graphical_target=active gdm=active greeter_session=%s greeter_name=gdm-greeter greeter_service=gdm-launch-environment greeter_class=greeter greeter_type=wayland autologin=disabled network=online failed_units=0 stock_gdm=yes marble=inactive\n' \
        "${marker_prefix}" "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" \
        "${root_contract}" "${bootloader_contract}" "${greeter_session}"
}

upgrade_stock_runtime_tools() {
    [ "${phase}" = update ] || return 1
    if [ "${scenario}" = stock-gnome-btrfs-grub ]; then
        pacman -Syu --noconfirm --disable-download-timeout --needed bpftrace
    else
        pacman -Syu --noconfirm --disable-download-timeout
    fi
}

verify_stock_session() {
    local target config user_session uid session_uid shell_pid shell_environment
    local enabled_extensions installed_extensions expected_extensions cursor_theme gtk_theme icon_theme
    local boot_id ptyxis_version root_contract='root=ext4' bootloader_contract='systemd-boot'
    if [ "${phase}" = update ]; then upgrade_stock_runtime_tools || return 1; fi
    if [ "${phase}" = update ] && is_grub_stock; then
        verify_grub_regeneration
    fi
    if [[ "${phase}" = snapshot-* ]]; then
        target="$(verify_snapshot_runtime)"
    else
        target="$(verify_common)"
    fi
    config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    verify_stock_profile "${config}"
    if is_btrfs_stock && [[ "${phase}" != snapshot-* ]]; then
        verify_btrfs_contract
        root_contract='root=btrfs btrfs_contract=verified encryption=off snapper=off btrfs_assistant=off'
        if is_luks_stock; then
            root_contract='root=btrfs btrfs_contract=verified encryption=luks2 mapper=cryptroot plymouth=on snapper=off btrfs_assistant=off'
        fi
    fi
    is_grub_stock && bootloader_contract='grub'
    [[ "${phase}" != snapshot-* ]] || root_contract='root=btrfs-snapshot root_mode=read-only overlay=volatile module_pair=verified'
    user_session="$(wait_for_user_session)"
    uid="$(id -u "${username}")"
    session_uid="$(session_property "${user_session}" User)"
    [ "${session_uid}" = "${uid}" ]
    # GDM may leave login1's optional Desktop property empty; bind GNOME to the real Shell process.
    [ -S "/run/user/${uid}/bus" ]
    shell_pid="$(wait_for_gnome_shell "${uid}")"
    shell_environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    grep -qx 'XDG_SESSION_TYPE=wayland' <<<"${shell_environment}"
    grep -Eq '^XDG_CURRENT_DESKTOP=(GNOME|GNOME:GNOME)$' <<<"${shell_environment}"
    verify_graphical_locale_keyboard_contract "${uid}"

    pacman -Q ptyxis >/dev/null
    [ -x /usr/bin/ptyxis ]
    ptyxis_version="$(run_in_user_session "${uid}" /usr/bin/ptyxis --version)"
    [ -n "${ptyxis_version}" ]
    if pacman -Q gnome-console >/dev/null 2>&1; then
        return 1
    fi
    [ ! -e /usr/bin/kgx ]
    [ ! -e /usr/share/applications/org.gnome.Console.desktop ]

    expected_extensions="$(printf '%s\n' \
        appindicatorsupport@rgcjonas.gmail.com \
        blur-my-shell@aunetx \
        caffeine@patapon.info \
        clipboard-indicator@tudmotu.com \
        dash-to-dock@micxgx.gmail.com \
        just-perfection-desktop@just-perfection \
        no-screenshot-box@screenshot)"
    installed_extensions="$(run_in_user_session "${uid}" /usr/bin/gnome-extensions list)"
    enabled_extensions="$(wait_for_enabled_extensions "${uid}" "${expected_extensions}")"
    [ "${enabled_extensions}" = "${expected_extensions}" ]
    while IFS= read -r extension_uuid; do
        grep -qxF -- "${extension_uuid}" <<<"${installed_extensions}"
    done <<<"${expected_extensions}"
    [ "$(run_in_user_session "${uid}" /usr/bin/gsettings get org.gnome.shell disable-user-extensions)" = false ]

    cursor_theme="$(run_in_user_session "${uid}" /usr/bin/gsettings get org.gnome.desktop.interface cursor-theme)"
    gtk_theme="$(run_in_user_session "${uid}" /usr/bin/gsettings get org.gnome.desktop.interface gtk-theme)"
    icon_theme="$(run_in_user_session "${uid}" /usr/bin/gsettings get org.gnome.desktop.interface icon-theme)"
    [ "${cursor_theme}" = "'Bibata-Modern-Classic'" ]
    [ "${gtk_theme}" = "'Adwaita'" ]
    [ ! -e /usr/share/themes/Colloid-Dark ]
    [ ! -e /usr/share/arch-linux-marble/gtk4 ]
    [ ! -e "/home/${username}/.config/gtk-4.0/gtk.css" ]
    [ ! -e "/home/${username}/.config/gtk-4.0/gtk-dark.css" ]
    [ "${icon_theme}" = "'Adwaita'" ]
    [ -d /usr/share/icons/Bibata-Modern-Classic/cursors ]
    [ "$(sed -n '1p' /etc/dconf/db/local.d/06-cursor)" = '[org/gnome/desktop/interface]' ]
    [ "$(sed -n '2p' /etc/dconf/db/local.d/06-cursor)" = "cursor-theme='Bibata-Modern-Classic'" ]
    [ "$(wc -l </etc/dconf/db/local.d/06-cursor)" -eq 2 ]

    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    [[ "${boot_id}" =~ ^[a-f0-9-]{36}$ ]]
    printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s pttype=gpt %s bootloader=%s default_target=graphical.target graphical_target=active gdm=active login_service=gdm-password session=%s user=%s uid=%s session_type=wayland desktop=GNOME ptyxis=usable gnome_console=absent extensions=7/7-enabled cursor=Bibata-Modern-Classic gtk=Adwaita icons=Adwaita stock_gdm=yes marble=inactive network=online failed_units=0\n' \
        "${marker_prefix}" "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" \
        "${root_contract}" "${bootloader_contract}" "${user_session}" "${username}" "${uid}"
}

marble_gdm_enabled() {
    [ "${scenario}" != marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm ]
}

marble_project_packages() {
    printf '%s\n' \
        arch-linux-keyring \
        arch-linux-gnome-extensions \
        arch-linux-marble-shell \
        arch-linux-colloid-gtk \
        arch-linux-colloid-icons \
        arch-linux-marble-profile
    if marble_gdm_enabled; then
        printf '%s\n' arch-linux-marble-gdm
    fi
}

marble_theme_packages() {
    printf '%s\n' arch-linux-marble-shell arch-linux-colloid-gtk arch-linux-colloid-icons arch-linux-marble-profile
    if marble_gdm_enabled; then
        printf '%s\n' arch-linux-marble-gdm
    fi
}

graphical_project_packages() {
    case "${scenario}" in
    stock-gnome-*) printf '%s\n' arch-linux-keyring arch-linux-gnome-extensions ;;
    marble-gnome-*) marble_project_packages ;;
    *) return 1 ;;
    esac
}

verify_stock_project_packages() {
    local expected
    expected="$(printf '%s\n' arch-linux-keyring arch-linux-gnome-extensions | LC_ALL=C sort)"
    [ "$(pacman -Qq | grep '^arch-linux-' | LC_ALL=C sort)" = "${expected}" ]
    package_installed_exact arch-linux-keyring
    package_installed_exact arch-linux-gnome-extensions
    verify_package_qkk_zero arch-linux-keyring arch-linux-gnome-extensions >/dev/null
    (cd /usr/share/gnome-shell/extensions && sha256sum --check --status \
        /usr/share/arch-linux-gnome-extensions/extensions.sha256)
}

installed_package_record_exact() {
    local expected="$1" record
    record="$(pacman -Q -- "${expected}")" || return 1
    [ "${record%% *}" = "${expected}" ] || return 1
    [ "$(awk '{ print NF }' <<<"${record}")" -eq 2 ] || return 1
    printf '%s\n' "${record}"
}

installed_package_version_exact() {
    local record
    record="$(installed_package_record_exact "$1")" || return 1
    printf '%s\n' "${record#* }"
}

package_installed_exact() {
    installed_package_record_exact "$1" >/dev/null
}

public_repository_policy_scope_valid() {
    local repository_file="$1" pacman_conf="$2"
    [ -f "${repository_file}" ] && [ -f "${pacman_conf}" ] || return 1
    # Arch's official repositories use DatabaseOptional. The project override is strict.
    ! grep -Eq 'TrustAll|PackageOptional|DatabaseOptional' "${repository_file}" &&
        ! grep -Eq 'https://10\.0\.2\.2:' "${repository_file}" "${pacman_conf}"
}

verify_public_repository_contract() {
    local expected_repository expected_include metadata primary signing package info
    local repository_file='/etc/pacman.d/arch-linux-marble-repository.conf'
    [ "${input_mode}" = public ] || return 0
    expected_repository="$(printf '%s\n[%s]\n%s\nServer = %s\n' \
        '# Managed by arch-linux-installer: Marble profile' \
        arch-linux \
        'SigLevel = PackageRequired DatabaseRequired TrustedOnly' \
        "https://snaplyze.github.io/arch-linux/repo/\$arch")"
    [ -f "${repository_file}" ] && [ ! -L "${repository_file}" ]
    [ "$(cat -- "${repository_file}")" = "${expected_repository}" ]
    expected_include="$(printf '%s\n%s\n%s\n' \
        '# BEGIN arch-linux Marble profile repository' \
        'Include = /etc/pacman.d/arch-linux-marble-repository.conf' \
        '# END arch-linux Marble profile repository')"
    [ "$(awk '/^# BEGIN arch-linux Marble profile repository$/ { print; getline; print; getline; print; exit }' \
        /etc/pacman.conf)" = "${expected_include}" ]
    [ "$(grep -Fxc 'Include = /etc/pacman.d/arch-linux-marble-repository.conf' /etc/pacman.conf)" -eq 1 ]
    public_repository_policy_scope_valid "${repository_file}" /etc/pacman.conf
    [ ! -e /etc/ca-certificates/trust-source/anchors/arch-linux-qemu-acceptance.crt ]
    [ -f /var/lib/pacman/sync/arch-linux.db ] && [ ! -L /var/lib/pacman/sync/arch-linux.db ]

    metadata="$(gpg --batch --no-options --homedir /etc/pacman.d/gnupg --with-colons \
        --with-subkey-fingerprint --list-keys -- "${repository_primary}!")"
    [ "$(grep -c '^pub:' <<<"${metadata}")" -eq 1 ]
    [ "$(grep -c '^sub:' <<<"${metadata}")" -eq 1 ]
    primary="$(awk -F: '$1 == "fpr" { print toupper($10); exit }' <<<"${metadata}")"
    signing="$(awk -F: '$1 == "sub" { want=1; next } want && $1 == "fpr" { print toupper($10); exit }' \
        <<<"${metadata}")"
    [ "${primary}" = "${repository_primary}" ]
    [ "${signing}" = "${repository_signing}" ]
    if gpg --batch --no-options --homedir /etc/pacman.d/gnupg --list-secret-keys -- \
        "${repository_primary}!" >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r package; do
        package_installed_exact "${package}"
        info="$(pacman -Qi -- "${package}")"
        grep -Eq "^Name[[:space:]]*:[[:space:]]*${package}$" <<<"${info}"
        grep -Eq '^Validated By[[:space:]]*:[[:space:]]*Signature([[:space:]]|$)' <<<"${info}"
    done < <(graphical_project_packages)
    printf 'MARBLE_PUBLIC_REPOSITORY_POLICY_PASS run_id=%s phase=%s server=pages package_signatures=required database_signatures=required private_key=absent\n' \
        "${run_id}" "${phase}"
}

verify_public_detached_signature() {
    local keyring="$1" signature="$2" payload="$3" status valid
    status="$(gpgv --status-fd 1 --keyring "${keyring}" -- "${signature}" "${payload}" 2>/dev/null)" ||
        return 1
    if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|REVKEYSIG|EXPSIG)\b' <<<"${status}"; then
        return 1
    fi
    valid="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print toupper($3) ":" toupper($NF) }' \
        <<<"${status}")"
    [ "${valid}" = "${repository_signing}:${repository_primary}" ]
}

public_fetch() {
    local url="$1" output="$2"
    [[ "${url}" = https://* ]]
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --location \
        --silent --show-error --connect-timeout 30 --max-time 900 \
        -H 'Cache-Control: no-cache' --output "${output}" -- "${url}"
    [ -f "${output}" ] && [ ! -L "${output}" ] && [ -s "${output}" ]
    chmod 0600 -- "${output}"
}

release_sum_for() {
    local sums="$1" name="$2"
    awk -v expected="*${name}" '$2 == expected { print $1; count++ } END { if (count != 1) exit 1 }' \
        "${sums}"
}

require_public_readback_tools() {
    local include_jq="${1:-true}" command_name
    for command_name in awk base64 bsdtar cat chmod cmp curl cut find gpg gpgv grep install jq mktemp rm sed sha256sum sort stat tr; do
        if [ "${command_name}" = jq ] && [ "${include_jq}" = false ]; then
            continue
        fi
        command -v -- "${command_name}" >/dev/null || {
            printf 'missing public readback dependency: %s\n' "${command_name}" >&2
            return 1
        }
    done
}

prepare_media_readback() {
    local siglevel boot_id command_name preparation=existing
    [ "${input_mode}" = public ] && [ "${media_qualification}" = true ] || return 1
    case "${scenario}" in minimal-ext4-systemdboot | stock-gnome-ext4-systemdboot) ;; *) return 1 ;; esac
    require_public_readback_tools false || return 1
    if ! command -v -- jq >/dev/null; then
        # Harness-only tooling: use the installed synchronized official repository database,
        # without refreshing it or upgrading the first-boot kernel before its pairing check.
        for command_name in pacman pacman-conf; do
            command -v -- "${command_name}" >/dev/null || {
                printf 'missing public readback dependency: %s\n' "${command_name}" >&2
                return 1
            }
        done
        siglevel="$(pacman-conf --repo extra SigLevel)" || return 1
        if [ -z "${siglevel}" ]; then
            siglevel="$(pacman-conf SigLevel)" || return 1
        fi
        grep -Fxq PackageRequired <<<"${siglevel}" &&
            grep -Fxq PackageTrustedOnly <<<"${siglevel}" || return 1
        pacman -S --noconfirm --needed -- extra/jq || {
            printf 'public media readback preparation failed: official extra/jq installation\n' >&2
            return 1
        }
        preparation=official-extra-install
    fi
    require_public_readback_tools || return 1
    jq --version || return 1
    boot_id="$(cat /proc/sys/kernel/random/boot_id)" || return 1
    printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=public-readback-tools preparation=%s\n' \
        "${marker_prefix}" "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${preparation}"
}

verify_public_release_pages_binding() (
    local release_base archive_name archive_url pages_base work pages_dir keyring sums sums_signature
    local archive archive_signature archive_checksum release_manifest release_manifest_signature
    local pages_manifest pages_manifest_signature manifest_tsv name checksum size actual_names expected_names
    local package package_file release_sums_hash repository_manifest_hash repository_manifest_signature_hash
    local expected_package_files='' database_filenames='' member filename files_desc_count files_list_count
    local -a package_matches=()
    [ "${input_mode}" = public ] || return 0
    require_public_readback_tools || return 1
    release_base="${public_key_url%/arch-linux.gpg}"
    [ "${release_base}" = "https://github.com/snaplyze/arch-linux/releases/download/${release_version}" ]
    archive_name="arch-linux-repository-${release_version}.tar.zst"
    archive_url="${release_base}/${archive_name}"
    # The literal $arch in pacman configuration is resolved only for HTTPS readback.
    pages_base="${pages_url//\$arch/x86_64}"
    [ "${pages_base}" = 'https://snaplyze.github.io/arch-linux/repo/x86_64' ]
    work="$(mktemp -d "/run/arch-linux-public-readback.${run_id}.XXXXXXXX")"
    chmod 0700 -- "${work}"
    trap 'rm -rf -- "${work}"' EXIT HUP INT TERM
    pages_dir="${work}/pages"
    install -d -m0700 -- "${pages_dir}"
    keyring="${work}/arch-linux.gpg"
    sums="${work}/RELEASE-SHA256SUMS"
    sums_signature="${work}/RELEASE-SHA256SUMS.sig"
    archive="${work}/${archive_name}"
    archive_signature="${archive}.sig"
    archive_checksum="${archive}.sha256"
    public_fetch "${public_key_url}" "${keyring}"
    [ "$(sha256sum --binary -- "${keyring}" | awk '{print $1}')" = "${public_key_sha256}" ]
    if gpg --batch --no-options --list-packets -- "${keyring}" 2>/dev/null |
        grep -Eq '^:(secret key|secret sub key) packet:'; then
        return 1
    fi
    public_fetch "${release_base}/RELEASE-SHA256SUMS" "${sums}"
    public_fetch "${release_base}/RELEASE-SHA256SUMS.sig" "${sums_signature}"
    verify_public_detached_signature "${keyring}" "${sums_signature}" "${sums}"
    awk 'NF != 2 || $1 !~ /^[a-f0-9]{64}$/ || $2 !~ /^\*[A-Za-z0-9][A-Za-z0-9+._-]*$/ { exit 1 }
         END { if (NR != 12) exit 1 }' "${sums}"
    release_sums_hash="$(sha256sum --binary -- "${sums}" | awk '{print $1}')"
    [ "$(release_sum_for "${sums}" arch-linux.gpg)" = "${public_key_sha256}" ]
    [ "$(release_sum_for "${sums}" BUILD-METADATA.json)" = "${build_metadata_sha256}" ]
    [ "$(release_sum_for "${sums}" UNSIGNED-SHA256SUMS)" = "${unsigned_manifest_sha256}" ]

    public_fetch "${archive_url}" "${archive}"
    public_fetch "${archive_url}.sig" "${archive_signature}"
    public_fetch "${archive_url}.sha256" "${archive_checksum}"
    [ "$(release_sum_for "${sums}" "${archive_name}")" = "${snapshot_sha256}" ]
    [ "$(sha256sum --binary -- "${archive}" | awk '{print $1}')" = "${snapshot_sha256}" ]
    [ "$(release_sum_for "${sums}" "${archive_name}.sig")" = \
        "$(sha256sum --binary -- "${archive_signature}" | awk '{print $1}')" ]
    [ "$(release_sum_for "${sums}" "${archive_name}.sha256")" = \
        "$(sha256sum --binary -- "${archive_checksum}" | awk '{print $1}')" ]
    [ "$(cat -- "${archive_checksum}")" = "${snapshot_sha256} *${archive_name}" ]
    verify_public_detached_signature "${keyring}" "${archive_signature}" "${archive}"

    [ "$(bsdtar -tf "${archive}" | grep -Fxc 'repo/x86_64/repository-manifest.json')" -eq 1 ]
    [ "$(bsdtar -tf "${archive}" | grep -Fxc 'repo/x86_64/repository-manifest.json.sig')" -eq 1 ]
    release_manifest="${work}/release-repository-manifest.json"
    release_manifest_signature="${release_manifest}.sig"
    bsdtar -xOf "${archive}" repo/x86_64/repository-manifest.json >"${release_manifest}"
    bsdtar -xOf "${archive}" repo/x86_64/repository-manifest.json.sig \
        >"${release_manifest_signature}"
    [ -s "${release_manifest}" ] && [ -s "${release_manifest_signature}" ]
    verify_public_detached_signature "${keyring}" "${release_manifest_signature}" "${release_manifest}"

    pages_manifest="${work}/pages-repository-manifest.json"
    pages_manifest_signature="${pages_manifest}.sig"
    public_fetch "${pages_base}/repository-manifest.json" "${pages_manifest}"
    public_fetch "${pages_base}/repository-manifest.json.sig" "${pages_manifest_signature}"
    cmp -s -- "${release_manifest}" "${pages_manifest}"
    cmp -s -- "${release_manifest_signature}" "${pages_manifest_signature}"
    verify_public_detached_signature "${keyring}" "${pages_manifest_signature}" "${pages_manifest}"
    repository_manifest_hash="$(sha256sum --binary -- "${pages_manifest}" | awk '{print $1}')"
    repository_manifest_signature_hash="$(sha256sum --binary -- "${pages_manifest_signature}" | awk '{print $1}')"
    jq -cS . "${pages_manifest}" >"${work}/canonical-repository-manifest.json"
    cmp -s -- "${work}/canonical-repository-manifest.json" "${pages_manifest}"
    jq -e --arg version "${release_version}" --arg source_commit "${source_commit}" \
        --arg source_tree "${source_tree}" --arg installer_sha256 "${installer_sha256}" \
        --arg package_set_sha256 "${package_set_sha256}" \
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
        (.files | type == "array" and length == 25 and all(.[];
          type == "object" and keys == ["name","sha256","size"] and
          (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9+._-]*$")) and
          (.sha256 | type == "string" and test("^[a-f0-9]{64}$")) and
          (.size | type == "number" and . > 0 and floor == .)))
    ' "${pages_manifest}" >/dev/null
    manifest_tsv="${work}/repository-objects.tsv"
    jq -r '.files[] | [.name,.sha256,(.size|tostring)] | @tsv' "${pages_manifest}" >"${manifest_tsv}"
    actual_names="$(cut -f1 -- "${manifest_tsv}")"
    [ "${actual_names}" = "$(printf '%s\n' "${actual_names}" | LC_ALL=C sort -u)" ]
    expected_names="$(printf '%s\n' \
        arch-linux.db arch-linux.db.sig arch-linux.db.tar.gz arch-linux.db.tar.gz.sig \
        arch-linux.files arch-linux.files.sig arch-linux.files.tar.gz arch-linux.files.tar.gz.sig \
        arch-linux.gpg primary-fingerprint signing-subkey-fingerprint | LC_ALL=C sort)"
    while IFS= read -r package; do
        mapfile -t package_matches < <(awk -F '\t' -v prefix="${package}-" '
            index($1,prefix) == 1 && $1 ~ /[.]pkg[.]tar[.]zst$/ { print $1 }' "${manifest_tsv}")
        [ "${#package_matches[@]}" -eq 1 ]
        package_file="${package_matches[0]}"
        grep -Fxq "${package_file}.sig" <<<"${actual_names}"
        expected_package_files="$(printf '%s\n%s\n' "${expected_package_files}" "${package_file}" |
            sed '/^$/d' | LC_ALL=C sort)"
        expected_names="$(printf '%s\n%s\n%s\n' "${expected_names}" "${package_file}" \
            "${package_file}.sig" | LC_ALL=C sort)"
    done < <(marble_project_packages)
    [ "${actual_names}" = "${expected_names}" ]

    while IFS=$'\t' read -r name checksum size; do
        public_fetch "${pages_base}/${name}" "${pages_dir}/${name}"
        [ "$(stat -c %s -- "${pages_dir}/${name}")" = "${size}" ]
        [ "$(sha256sum --binary -- "${pages_dir}/${name}" | awk '{print $1}')" = "${checksum}" ]
    done <"${manifest_tsv}"
    cmp -s -- "${pages_dir}/arch-linux.gpg" "${keyring}"
    [ "$(tr -d '\n' <"${pages_dir}/primary-fingerprint")" = "${repository_primary}" ]
    [ "$(tr -d '\n' <"${pages_dir}/signing-subkey-fingerprint")" = "${repository_signing}" ]
    [ "$(sha256sum --binary -- "${pages_dir}/arch-linux.db" | awk '{print $1}')" = \
        "$(sha256sum --binary -- "${pages_dir}/arch-linux.db.tar.gz" | awk '{print $1}')" ]
    cmp -s -- "${pages_dir}/arch-linux.db.sig" "${pages_dir}/arch-linux.db.tar.gz.sig"
    [ "$(sha256sum --binary -- "${pages_dir}/arch-linux.files" | awk '{print $1}')" = \
        "$(sha256sum --binary -- "${pages_dir}/arch-linux.files.tar.gz" | awk '{print $1}')" ]
    cmp -s -- "${pages_dir}/arch-linux.files.sig" "${pages_dir}/arch-linux.files.tar.gz.sig"
    verify_public_detached_signature "${keyring}" "${pages_dir}/arch-linux.db.tar.gz.sig" \
        "${pages_dir}/arch-linux.db.tar.gz"
    verify_public_detached_signature "${keyring}" "${pages_dir}/arch-linux.files.tar.gz.sig" \
        "${pages_dir}/arch-linux.files.tar.gz"
    while IFS= read -r package; do
        package_matches=("${pages_dir}/${package}-"*.pkg.tar.zst)
        [ "${#package_matches[@]}" -eq 1 ]
        verify_public_detached_signature "${keyring}" "${package_matches[0]}.sig" \
            "${package_matches[0]}"
    done < <(marble_project_packages)
    while IFS= read -r member; do
        filename="$(bsdtar -xOf "${pages_dir}/arch-linux.db.tar.gz" "${member}" |
            awk '$0 == "%FILENAME%" { getline; print; count++ }
                 END { if (count != 1) exit 1 }')"
        [[ "${filename}" =~ ^[A-Za-z0-9][A-Za-z0-9+._-]*[.]pkg[.]tar[.]zst$ ]]
        database_filenames="$(printf '%s\n%s\n' "${database_filenames}" "${filename}" |
            sed '/^$/d' | LC_ALL=C sort)"
    done < <(bsdtar -tf "${pages_dir}/arch-linux.db.tar.gz" | grep '/desc$')
    [ "${database_filenames}" = "${expected_package_files}" ]
    files_desc_count="$(bsdtar -tf "${pages_dir}/arch-linux.files.tar.gz" | grep -c '/desc$')"
    files_list_count="$(bsdtar -tf "${pages_dir}/arch-linux.files.tar.gz" | grep -c '/files$')"
    [ "${files_desc_count}" -eq 7 ] && [ "${files_list_count}" -eq 7 ]

    printf 'MARBLE_PUBLIC_SNAPSHOT_BINDING_PASS run_id=%s snapshot_sha256=%s release_sums_sha256=%s repository_manifest_sha256=%s repository_manifest_signature_sha256=%s pages_objects=25 package_signatures=7 database_signatures=2\n' \
        "${run_id}" "${snapshot_sha256}" "${release_sums_hash}" "${repository_manifest_hash}" \
        "${repository_manifest_signature_hash}"
    printf 'PUBLIC_REPOSITORY_MANIFEST_BASE64 run_id=%s value=%s\n' \
        "${run_id}" "$(base64 -w0 -- "${pages_manifest}")"
    printf 'PUBLIC_REPOSITORY_MANIFEST_SIGNATURE_BASE64 run_id=%s value=%s\n' \
        "${run_id}" "$(base64 -w0 -- "${pages_manifest_signature}")"
)

verify_package_qkk_zero() {
    local output line_count=0
    output="$(pacman -Qkk "$@")"
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        [[ "${line}" =~ ,[[:space:]]0[[:space:]]altered[[:space:]]files$ ]]
        line_count=$((line_count + 1))
    done <<<"${output}"
    [ "${line_count}" -eq "$#" ]
    printf '%s\n' "${output}"
}

verify_marble_packages() {
    local package qkk project_paths
    local -a packages=()
    mapfile -t packages < <(marble_project_packages)
    for package in "${packages[@]}"; do
        package_installed_exact "${package}"
    done
    qkk="$(verify_package_qkk_zero "${packages[@]}")"
    project_paths="$(pacman -Qlq "${packages[@]}")"
    if grep -Eq '(^|/)(home|root)/|(^|/)usr/share/icons/default(/|$)|icon-theme\.cache$|gnome-shell-theme\.gresource$|(^|/)usr/share/(gdm|gdm3)(/|$)|(^|/)etc/(gdm|gdm3)(/|$)|(^|/)var/lib/gdm(/|$)' \
        <<<"${project_paths}"; then
        return 1
    fi
    [ -L /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark ]
    [ "$(readlink -- /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark)" = \
        /usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark ]
    [ -f /usr/share/themes/Colloid-Dark/gtk-3.0/gtk.css ]
    [ -f /usr/share/themes/Colloid-Dark/gtk-4.0/gtk.css ]
    [ -f /usr/share/arch-linux-marble/gtk4/gtk.css ]
    (cd /usr/share/arch-linux-marble/gtk4 && sha256sum --check --status assets.sha256)
    if package_installed_exact arch-linux-colloid-gtk3; then return 1; fi
    [ -f /usr/share/icons/Colloid-Dark/index.theme ]
    if marble_gdm_enabled; then
        [ -z "$(find /usr/share/arch-linux-marble-gdm -type f -path '*/gtk-4.0/*' -print -quit)" ]
    else
        if package_installed_exact arch-linux-marble-gdm; then return 1; fi
        [ ! -e /usr/share/arch-linux-marble-gdm ]
    fi
    printf 'MARBLE_QEMU_PROJECT_QKK run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${qkk}"
}

marble_gdm_major() {
    local version major
    version="$(installed_package_version_exact gnome-shell)" || return 1
    version="${version#*:}"
    major="${version%%.*}"
    case "${major}" in 50 | 51) printf '%s\n' "${major}" ;; *) return 1 ;; esac
}

verify_vendor_integrity() {
    local qkk major
    qkk="$(verify_package_qkk_zero gnome-shell gdm)"
    if marble_gdm_enabled; then
        major="$(marble_gdm_major)" || return 1
        sha256sum --check --strict \
            "/usr/share/arch-linux-marble-gdm/known-gnome-${major}.sha256" >/dev/null
    fi
    [ "$(pacman -Qo /usr/share/gnome-shell/gnome-shell-theme.gresource | awk '{ print $5 }')" = gnome-shell ]
    [ "$(pacman -Qo /usr/share/dconf/profile/gdm | awk '{ print $5 }')" = gdm ]
    printf 'MARBLE_QEMU_VENDOR_QKK run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${qkk}"
}

gdm_shell_pid() {
    local greeter_session="$1" greeter_uid candidate
    # GDM uses the logind gdm-greeter identity without requiring a passwd entry named gdm.
    # Bind the process check to the already validated greeter session instead of a legacy account.
    greeter_uid="$(session_property "${greeter_session}" User)" || return 1
    [[ "${greeter_uid}" =~ ^[1-9][0-9]*$ ]] || return 1
    candidate="$(pgrep -u "${greeter_uid}" -x gnome-shell)" || return 1
    [[ "${candidate}" =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s' "${candidate}"
}

stock_gdm_process_environment_is_valid() {
    local environment="$1"
    # GDM itself sets the Stock greeter profile; only the project override must disappear.
    if grep -q '^G_RESOURCE_OVERLAYS=' <<<"${environment}"; then
        return 1
    fi
    if [ "$(grep -c '^DCONF_PROFILE=' <<<"${environment}" || true)" -ne 1 ]; then
        return 1
    fi
    grep -qx 'DCONF_PROFILE=gdm' <<<"${environment}"
}

verify_marble_gdm_process() {
    local expected="$1" greeter_session="$2" shell_pid environment helper_status major version_root
    helper_status="$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)"
    shell_pid="$(gdm_shell_pid "${greeter_session}")"
    environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    if [ "${expected}" = active ]; then
        major="$(marble_gdm_major)" || return 1
        version_root="/usr/share/arch-linux-marble-gdm/${major}.0.0"
        [ "${helper_status}" = active ]
        [ -L /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
        [ "$(readlink -- /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf)" = \
            "/usr/share/arch-linux-marble-gdm/systemd/${major}-arch-linux-marble-gdm.conf" ]
        grep -qx "G_RESOURCE_OVERLAYS=/org/gnome/shell/theme=${version_root}/theme" \
            <<<"${environment}"
        grep -qx "DCONF_PROFILE=${version_root}/dconf/profile" \
            <<<"${environment}"
        [ "$(DCONF_PROFILE="${version_root}/dconf/profile" \
            XDG_CONFIG_HOME=/dev/null gsettings get org.gnome.desktop.interface icon-theme)" = \
            "'Colloid-Dark'" ]
    else
        [ "${helper_status}" = stock ]
        [ ! -e /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
        [ ! -L /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
        stock_gdm_process_environment_is_valid "${environment}"
    fi
}

verify_stock_gdm_process_without_project() {
    local greeter_session="$1" shell_pid environment
    shell_pid="$(gdm_shell_pid "${greeter_session}")"
    environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    stock_gdm_process_environment_is_valid "${environment}"
    [ ! -e /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
    [ ! -L /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
}

verify_no_autologin() {
    if [ -f /etc/gdm/custom.conf ]; then
        if grep -Eq '^[[:space:]]*(AutomaticLoginEnable|TimedLoginEnable)[[:space:]]*=[[:space:]]*true[[:space:]]*$' \
            /etc/gdm/custom.conf; then
            return 1
        fi
    fi
}

verify_marble_storage_profile() {
    local config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    grep -qx 'ARCH_LINUX_FILESYSTEM=btrfs' "${config}"
    grep -qx 'ARCH_LINUX_BOOTLOADER=systemd' "${config}"
    grep -qx 'ARCH_LINUX_ENCRYPTION_ENABLED=true' "${config}"
    grep -qx 'ARCH_LINUX_BOOTSPLASH_ENABLED=true' "${config}"
    grep -qx 'ARCH_LINUX_DESKTOP_ENABLED=true' "${config}"
    grep -qx 'ARCH_LINUX_GNOME_THEME_PROFILE=marble' "${config}"
    if marble_gdm_enabled; then
        grep -qx 'ARCH_LINUX_GDM_THEME_PROFILE=marble-experimental' "${config}"
    else
        grep -qx 'ARCH_LINUX_GDM_THEME_PROFILE=stock' "${config}"
    fi
    grep -qx 'ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED=false' "${config}"
    verify_btrfs_contract
}

verify_marble_greeter() {
    local expected="$1" target greeter_session boot_id
    target="$(verify_common)"
    verify_marble_storage_profile
    verify_public_repository_contract
    wait_for_graphical_stack
    greeter_session="$(wait_for_greeter)"
    [ -n "${greeter_session}" ]
    verify_no_autologin
    case "${expected}" in
    active)
        verify_marble_packages
        verify_vendor_integrity
        if marble_gdm_enabled; then
            verify_marble_gdm_process active "${greeter_session}"
        else
            verify_stock_gdm_process_without_project "${greeter_session}"
        fi
        ;;
    fallback | deactivated)
        verify_marble_packages
        verify_vendor_integrity
        if [ "${expected}" = fallback ]; then
            [ -f /etc/dconf/profile/gdm ] && [ ! -L /etc/dconf/profile/gdm ]
        fi
        verify_marble_gdm_process stock "${greeter_session}"
        ;;
    removed)
        verify_stock_project_packages
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk.css" ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk-dark.css" ]
        verify_package_qkk_zero gnome-shell gdm >/dev/null
        verify_stock_gdm_process_without_project "${greeter_session}"
        ;;
    *) return 1 ;;
    esac
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    printf 'MARBLE_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s greeter_session=%s greeter_type=wayland gdm_profile=%s autologin=disabled failed_units=0\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" \
        "${greeter_session}" "${expected}"
}

verify_marble_user_session() {
    local expected="$1" target user_session uid session_uid shell_pid shell_environment
    local installed_extensions enabled_extensions expected_extensions cursor_theme gtk_theme icon_theme
    target="$(verify_common)"
    verify_marble_storage_profile
    verify_public_repository_contract
    user_session="$(wait_for_user_session)"
    uid="$(id -u "${username}")"
    session_uid="$(session_property "${user_session}" User)"
    [ "${session_uid}" = "${uid}" ]
    shell_pid="$(wait_for_gnome_shell "${uid}")"
    if [ "${phase}" = migrated-login ]; then
        emit_gnome_shell_lifecycle_diagnostic "${uid}" migrated-login
    fi
    shell_environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    grep -qx 'XDG_SESSION_TYPE=wayland' <<<"${shell_environment}"
    grep -Eq '^XDG_CURRENT_DESKTOP=(GNOME|GNOME:GNOME)$' <<<"${shell_environment}"
    verify_graphical_locale_keyboard_contract "${uid}"
    if grep -q '^G_RESOURCE_OVERLAYS=' <<<"${shell_environment}" ||
        grep -q '^DCONF_PROFILE=' <<<"${shell_environment}"; then
        return 1
    fi
    cursor_theme="$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface cursor-theme)"
    gtk_theme="$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface gtk-theme)"
    icon_theme="$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface icon-theme)"
    [ "${cursor_theme}" = "'Bibata-Modern-Classic'" ]
    installed_extensions="$(run_in_user_session "${uid}" gnome-extensions list)"
    if [ "${expected}" = marble ] || [ "${expected}" = fallback ]; then
        verify_marble_packages
        verify_vendor_integrity
        expected_extensions="$(printf '%s\n' \
            appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info \
            clipboard-indicator@tudmotu.com dash-to-dock@micxgx.gmail.com \
            just-perfection-desktop@just-perfection no-screenshot-box@screenshot \
            user-theme@gnome-shell-extensions.gcampax.github.com | LC_ALL=C sort)"
        enabled_extensions="$(wait_for_enabled_extensions "${uid}" "${expected_extensions}")"
        [ "${enabled_extensions}" = "${expected_extensions}" ]
        [ "${gtk_theme}" = "'Colloid-Dark'" ]
        [ "$(run_in_user_session "${uid}" /usr/lib/arch-linux-marble-profile/gtk4-session status)" = active ]
        run_in_user_session "${uid}" systemctl --user is-active --quiet arch-linux-marble-gtk4.service
        [ "${icon_theme}" = "'Colloid-Dark'" ]
        [ "$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface color-scheme)" = \
            "'prefer-dark'" ]
        [ "$(run_in_user_session "${uid}" gsettings get org.gnome.shell.extensions.user-theme name)" = \
            "'ArchLinux-Marble-Blue-Filled-Dark'" ]
        if marble_gdm_enabled; then
            [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = \
                "$([ "${expected}" = fallback ] && printf stock || printf active)" ]
        fi
    else
        expected_extensions="$(printf '%s\n' \
            appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info \
            clipboard-indicator@tudmotu.com dash-to-dock@micxgx.gmail.com \
            just-perfection-desktop@just-perfection no-screenshot-box@screenshot | LC_ALL=C sort)"
        enabled_extensions="$(wait_for_enabled_extensions "${uid}" "${expected_extensions}")"
        [ "${enabled_extensions}" = "${expected_extensions}" ]
        [ "${gtk_theme}" = "'Adwaita'" ]
        [ "${icon_theme}" = "'Adwaita'" ]
        verify_stock_project_packages
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk.css" ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk-dark.css" ]
        verify_package_qkk_zero gnome-shell gdm >/dev/null
    fi
    while IFS= read -r extension_uuid; do
        grep -qxF -- "${extension_uuid}" <<<"${installed_extensions}"
    done <<<"${expected_extensions}"
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    printf 'MARBLE_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s session=%s user=%s uid=%s session_type=wayland desktop=GNOME profile=%s extensions=%s cursor=Bibata-Modern-Classic user_overlay_environment=absent failed_units=0\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" "${user_session}" \
        "${username}" "${uid}" "${expected}" "$(wc -l <<<"${expected_extensions}")/enabled"
}

restart_gdm_after_profile_transition() {
    local user_session old_greeter old_shell new_greeter new_shell deadline
    user_session="$(wait_for_user_session)"
    [ -n "${user_session}" ]
    old_greeter="$(find_session greeter gdm-greeter gdm-launch-environment 2>/dev/null || true)"
    old_shell=''
    if [ -n "${old_greeter}" ]; then
        old_shell="$(gdm_shell_pid "${old_greeter}" 2>/dev/null || true)"
    fi
    # A restart may reuse loaded user-manager resources; require a fully stopped old greeter.
    systemctl stop gdm.service
    deadline=$((SECONDS + 120))
    while [ "${SECONDS}" -lt "${deadline}" ] && {
        session_name_exists "${username}" ||
            { [ -n "${old_shell}" ] && kill -0 "${old_shell}" 2>/dev/null; }
    }; do
        sleep 1
    done
    if session_name_exists "${username}"; then
        return 1
    fi
    if [ -n "${old_shell}" ] && kill -0 "${old_shell}" 2>/dev/null; then
        return 1
    fi
    systemctl start gdm.service
    wait_for_graphical_stack
    new_greeter="$(wait_for_greeter)"
    [ -n "${new_greeter}" ]
    new_shell="$(gdm_shell_pid "${new_greeter}")"
    [ -n "${new_shell}" ]
    if [ -n "${old_shell}" ]; then
        [ "${new_shell}" != "${old_shell}" ]
    fi
}

emit_marble_action_pass() {
    local detail="$1" boot_id
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    printf 'MARBLE_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s action=%s failed_units=0\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${detail}"
}

wait_for_named_user_logout() {
    local account="$1" deadline=$((SECONDS + 180)) candidate=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if ! session_name_exists "${account}"; then
            wait_for_greeter >/dev/null
            return 0
        fi
        sleep 1
    done
    printf 'GTK4_SESSION_DIAGNOSTIC phase=%s outcome=logout-timeout account=%s\n' \
        "${phase}" "${account}" >&2
    while read -r candidate _; do
        [ -n "${candidate}" ] || continue
        printf 'GTK4_SESSION_DIAGNOSTIC session=%s name=%s class=%s service=%s type=%s state=%s active=%s\n' \
            "${candidate}" "$(session_property "${candidate}" Name)" \
            "$(session_property "${candidate}" Class)" "$(session_property "${candidate}" Service)" \
            "$(session_property "${candidate}" Type)" "$(session_property "${candidate}" State)" \
            "$(session_property "${candidate}" Active)" >&2
    done < <(loginctl list-sessions --no-legend 2>/dev/null | head -n 16)
    return 1
}

legacy_repository_file='/etc/pacman.d/arch-linux-marble-repository.conf'
legacy_candidate_repository='/var/lib/arch-linux-marble/migration-candidate-repository.conf'
legacy_candidate_packages='/var/lib/arch-linux-marble/migration-candidate-packages.txt'

install_legacy_migration_packages() {
    local candidate_server legacy_server package info
    [ "${input_mode}" = staged ]
    [ "${scenario}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ]
    [ ! -e "${legacy_candidate_repository}" ] && [ ! -e "${legacy_candidate_packages}" ]
    install -Dm0600 -- "${legacy_repository_file}" "${legacy_candidate_repository}"
    while IFS= read -r package; do installed_package_record_exact "${package}"; done < <(marble_project_packages) |
        LC_ALL=C sort >"${legacy_candidate_packages}"
    candidate_server="$(awk '$1 == "Server" && $2 == "=" { print $3; count++ } END { if (count != 1) exit 1 }' \
        "${legacy_repository_file}")"
    legacy_server="${candidate_server/\/repo\/\$arch/\/legacy\/\$arch}"
    [ "${legacy_server}" != "${candidate_server}" ]
    printf '%s\n[%s]\n%s\nServer = %s\n' \
        '# Temporary verified legacy repository for migration acceptance' \
        arch-linux 'SigLevel = PackageRequired DatabaseRequired TrustedOnly' "${legacy_server}" \
        >"${legacy_repository_file}"
    pacman -Rdd --noconfirm arch-linux-marble-profile arch-linux-colloid-gtk
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
        pacman -Syy --noconfirm --disable-download-timeout \
        arch-linux-marble-profile arch-linux-colloid-gtk3
    [ "$(installed_package_version_exact arch-linux-marble-profile)" = "${legacy_profile_version}" ]
    [ "$(installed_package_version_exact arch-linux-colloid-gtk3)" = "${legacy_gtk3_version}" ]
    if package_installed_exact arch-linux-colloid-gtk; then return 1; fi
    for package in arch-linux-marble-profile arch-linux-colloid-gtk3; do
        package_installed_exact "${package}"
        info="$(pacman -Qi -- "${package}")"
        grep -Eq "^Name[[:space:]]*:[[:space:]]*${package}$" <<<"${info}"
        grep -Eq '^Validated By[[:space:]]*:[[:space:]]*Signature([[:space:]]|$)' <<<"${info}"
    done
    emit_marble_action_pass legacy-signed-profile-and-gtk3-installed
}

verify_legacy_user_session() {
    local session uid gnome_version gtk_theme path
    verify_common >/dev/null
    session="$(wait_for_user_session)"
    uid="$(id -u "${username}")"
    [ "$(session_property "${session}" User)" = "${uid}" ]
    [ "$(session_property "${session}" Service)" = gdm-password ]
    [ "$(session_property "${session}" Type)" = wayland ]
    [ "$(installed_package_version_exact arch-linux-marble-profile)" = "${legacy_profile_version}" ]
    [ "$(installed_package_version_exact arch-linux-colloid-gtk3)" = "${legacy_gtk3_version}" ]
    if package_installed_exact arch-linux-colloid-gtk; then return 1; fi
    gnome_version="$(installed_package_version_exact gnome-shell)"
    gtk_theme="$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface gtk-theme)"
    case "${gnome_version#*:}" in
        50.*) [ "${gtk_theme}" = "'Colloid-Dark'" ] ;;
        51.*)
            # The authenticated legacy profile supports GNOME 50 only. On 51 its
            # successful deactivation is the baseline that the update must recover.
            [ "${gtk_theme}" = "'Adwaita'" ]
            for path in /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark \
                /etc/dconf/db/local.d/05-arch-linux-marble-profile; do
                [ ! -e "${path}" ] && [ ! -L "${path}" ] || return 1
            done
            ;;
        *) return 1 ;;
    esac
    [ ! -e "/home/${username}/.config/gtk-4.0/gtk.css" ]
    [ ! -e "/home/${username}/.config/gtk-4.0/gtk-dark.css" ]
    emit_marble_action_pass legacy-real-gdm-wayland-session
}

update_legacy_session_to_candidate() {
    local uid info
    [ -f "${legacy_candidate_repository}" ] && [ -f "${legacy_candidate_packages}" ]
    install -m0644 -- "${legacy_candidate_repository}" "${legacy_repository_file}"
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
        pacman -Syyu --noconfirm --disable-download-timeout
    while IFS= read -r package; do installed_package_record_exact "${package}"; done < <(marble_project_packages) |
        LC_ALL=C sort | cmp -s -- - "${legacy_candidate_packages}"
    package_installed_exact arch-linux-colloid-gtk
    if package_installed_exact arch-linux-colloid-gtk3; then return 1; fi
    info="$(pacman -Qi -- arch-linux-marble-profile)"
    grep -Eq '^Depends On[[:space:]]*:.*arch-linux-colloid-gtk' <<<"${info}"
    verify_marble_packages
    uid="$(id -u "${username}")"
    run_in_user_session "${uid}" /usr/bin/gnome-session-quit --logout --no-prompt
    wait_for_named_user_logout "${username}"
    emit_marble_action_pass legacy-to-candidate-syu-and-logout
}

gnome51_migration_state='/var/lib/arch-linux-marble/gnome51-migration'
gnome51_migration_manifest='/var/lib/arch-linux-marble/gnome51-upgrade-manifest.json'

gnome51_require_platform() {
    local package version
    [ "${input_mode}:${scenario}" = staged:marble-gnome-btrfs-luks2-plymouth-systemdboot ]
    for package in gnome-shell mutter gdm; do
        version="$(installed_package_version_exact "${package}")"
        [[ "${version#*:}" = 51.* ]] || return 1
    done
    [ -f "${gnome51_migration_manifest}" ] && [ ! -L "${gnome51_migration_manifest}" ]
    [ "$(stat -c '%u:%a' "${gnome51_migration_manifest}")" = 0:400 ]
}

gnome51_aur_packages() {
    printf '%s\n' gnome-shell-extension-blur-my-shell gnome-shell-extension-clipboard-indicator \
        gnome-shell-extension-dash-to-dock gnome-shell-extension-just-perfection-desktop
}

gnome51_preferences() {
    local uid="$1"
    run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface clock-show-weekday
    run_in_user_session "${uid}" gsettings get org.gnome.desktop.wm.preferences num-workspaces
    run_in_user_session "${uid}" gsettings get org.gnome.shell enabled-extensions
    run_in_user_session "${uid}" gsettings get org.gnome.shell disable-user-extensions
}

gnome51_download_inputs() {
    local server="$1" name hash size destination
    while IFS=$'\t' read -r name hash size; do
        case "${name}" in aur/* | local/no-screenshot-box.zip) ;;
        *) continue ;;
        esac
        [[ "${name}" =~ ^(aur|local)/[A-Za-z0-9+._-]+$ ]] || return 1
        [[ "${hash}" =~ ^[a-f0-9]{64}$ && "${size}" =~ ^[1-9][0-9]*$ ]] || return 1
        destination="${gnome51_migration_state}/inputs/${name}"
        install -d -m0700 -- "${destination%/*}"
        curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
            --max-time 300 "${server}/gnome51-inputs/${name}" -o "${destination}"
        [ "$(stat -c '%s' "${destination}")" = "${size}" ]
        [ "$(sha256sum --binary -- "${destination}" | awk '{print $1}')" = "${hash}" ]
        chmod 0400 -- "${destination}"
    done < <(jq -r '.files | to_entries | sort_by(.key)[] | [.key,.value.sha256,(.value.size|tostring)] | @tsv' \
        "${gnome51_migration_manifest}")
}

gnome51_verify_baseline_packages() {
    local package version info actual expected
    if package_installed_exact arch-linux-gnome-extensions; then return 1; fi
    expected="$(jq -r '.baseline.packages | keys[]' "${gnome51_migration_manifest}" | LC_ALL=C sort)"
    actual="$(pacman -Qq | sed -n '/^arch-linux-/p' | LC_ALL=C sort)"
    [ "${actual}" = "${expected}" ]
    while IFS=$'\t' read -r package version; do
        [ "$(installed_package_version_exact "${package}")" = "${version}" ]
        info="$(pacman -Qi -- "${package}")"
        grep -Eq '^Validated By[[:space:]]*:[[:space:]]*Signature([[:space:]]|$)' <<<"${info}"
        verify_package_qkk_zero "${package}" >/dev/null
    done < <(jq -r '.baseline.packages | to_entries[] | [.key,.value] | @tsv' "${gnome51_migration_manifest}")
    [ "$(jq '.aur | length' "${gnome51_migration_manifest}")" -eq 4 ]
    [ "$(jq -r '.aur[].name' "${gnome51_migration_manifest}" | LC_ALL=C sort)" = "$(gnome51_aur_packages | LC_ALL=C sort)" ]
    while IFS=$'\t' read -r package version; do
        [ "$(installed_package_version_exact "${package}")" = "${version}" ]
        verify_package_qkk_zero "${package}" >/dev/null
        pacman -Ql -- "${package}" | grep -q '/usr/share/gnome-shell/extensions/'
    done < <(jq -r '.aur[] | [.name,.version] | @tsv' "${gnome51_migration_manifest}")
}

gnome51_record_local_tree() {
    python3 - "/home/${username}/.local/share/gnome-shell/extensions/no-screenshot-box@screenshot" \
        "${gnome51_migration_state}/legacy.sha256" "${gnome51_migration_state}/local-tree.json" <<'GNOME51_TREE_PY'
import hashlib, json, os, pathlib, stat, sys
root, manifest, receipt = map(pathlib.Path, sys.argv[1:])
expected = {}
for line in manifest.read_text().splitlines():
    digest, name = line.split('  ')
    expected[name] = digest
actual = {}; identities = {}
assert root.is_dir() and not root.is_symlink()
for directory, dirs, files in os.walk(root, followlinks=False):
    for name in dirs + files:
        path = pathlib.Path(directory) / name; info = path.lstat()
        assert not stat.S_ISLNK(info.st_mode)
        assert stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)
        if stat.S_ISREG(info.st_mode):
            relative = path.relative_to(root).as_posix()
            actual[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
            identities[relative] = [info.st_dev, info.st_ino]
assert actual == expected, 'installer-created local tree differs from known installed v6'
receipt.write_text(json.dumps({'hashes': actual, 'identities': identities}, sort_keys=True) + '\n')
GNOME51_TREE_PY
}

install_gnome51_baseline() {
    local uid candidate_server server baseline_server package filename zip local_tree
    local -a baseline_packages=() remove_packages=()
    gnome51_require_platform
    [ ! -e "${gnome51_migration_state}" ]
    install -d -m0700 -- "${gnome51_migration_state}"
    install -m0600 -- "${legacy_repository_file}" "${gnome51_migration_state}/candidate-repository.conf"
    install -m0600 -- /usr/share/arch-linux-gnome-extensions/legacy-no-screenshot-box.sha256 \
        "${gnome51_migration_state}/legacy.sha256"
    while IFS= read -r package; do installed_package_record_exact "${package}"; done < <(marble_project_packages) |
        LC_ALL=C sort >"${gnome51_migration_state}/candidate-packages.txt"
    uid="$(id -u "${username}")"
    wait_for_user_session >/dev/null
    # Explicit non-default witnesses belong only to this disposable acceptance user.
    run_in_user_session "${uid}" gsettings set org.gnome.desktop.interface clock-show-weekday true
    run_in_user_session "${uid}" gsettings set org.gnome.desktop.wm.preferences num-workspaces 7
    run_in_user_session "${uid}" gsettings set org.gnome.shell enabled-extensions \
        "$(run_in_user_session "${uid}" gsettings get org.gnome.shell enabled-extensions)"
    gnome51_preferences "${uid}" >"${gnome51_migration_state}/preferences.txt"
    run_in_user_session "${uid}" gnome-session-quit --logout --no-prompt
    wait_for_named_user_logout "${username}"
    candidate_server="$(awk '$1 == "Server" && $2 == "=" {print $3; count++} END {if(count != 1) exit 1}' "${legacy_repository_file}")"
    server="${candidate_server%/repo/\$arch}"
    [ "${server}" != "${candidate_server}" ]
    gnome51_download_inputs "${server}"
    baseline_server="${server}/gnome51-baseline/\$arch"
    printf '[arch-linux]\nSigLevel = PackageRequired DatabaseRequired TrustedOnly\nServer = %s\n' \
        "${baseline_server}" >"${legacy_repository_file}"
    mapfile -t baseline_packages < <(jq -r '.baseline.packages | keys[]' "${gnome51_migration_manifest}")
    [ "${#baseline_packages[@]}" -eq 6 ]
    mapfile -t remove_packages < <(marble_theme_packages)
    pacman -Rdd --noconfirm arch-linux-gnome-extensions "${remove_packages[@]}"
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt pacman -Syy --noconfirm --disable-download-timeout "${baseline_packages[@]}"
    local -a aur_files=()
    while IFS= read -r filename; do
        [[ "${filename}" =~ ^aur/[A-Za-z0-9+._-]+\.pkg\.tar\.(zst|xz|gz)$ ]] || return 1
        aur_files+=("${gnome51_migration_state}/inputs/${filename}")
    done < <(jq -r '.aur[].filename' "${gnome51_migration_manifest}")
    [ "${#aur_files[@]}" -eq 4 ]
    pacman -U --noconfirm -- "${aur_files[@]}"
    local_tree="/home/${username}/.local/share/gnome-shell/extensions/no-screenshot-box@screenshot"
    [ ! -e "${local_tree}" ] && [ ! -L "${local_tree}" ]
    zip="$(mktemp "/home/${username}/.local/share/gnome-shell/gnome51-v6.XXXXXXXX.zip")"
    install -o "${uid}" -g "$(id -g "${username}")" -m0400 -- \
        "${gnome51_migration_state}/inputs/local/no-screenshot-box.zip" "${zip}"
    runuser -u "${username}" -- env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR \
        HOME="/home/${username}" XDG_DATA_HOME="/home/${username}/.local/share" \
        gnome-extensions install --print-uuid "${zip}"
    rm -f -- "${zip}"
    runuser -u "${username}" -- glib-compile-schemas --strict "${local_tree}/schemas"
    gnome51_verify_baseline_packages
    gnome51_record_local_tree
    systemctl restart gdm.service
    wait_for_greeter >/dev/null
    verify_marble_gdm_process stock "$(wait_for_greeter)"
    touch "${gnome51_migration_state}/baseline-gdm-stock-proven"
    emit_marble_action_pass gnome51-authenticated-baseline-and-actual-aur-installed
}

verify_gnome51_baseline_login() {
    local uid session uuid info state failures=0 shell_pid
    gnome51_require_platform
    gnome51_verify_baseline_packages
    [ -f "${gnome51_migration_state}/baseline-gdm-stock-proven" ]
    session="$(wait_for_user_session)"; uid="$(id -u "${username}")"
    [ "$(session_property "${session}" User)" = "${uid}" ]
    [ "$(session_property "${session}" Service)" = gdm-password ]
    [ "$(session_property "${session}" Type)" = wayland ]
    shell_pid="$(wait_for_gnome_shell "${uid}")"
    [ -n "${shell_pid}" ]
    gnome51_preferences "${uid}" | cmp -s -- - "${gnome51_migration_state}/preferences.txt"
    gnome51_record_local_tree
    for uuid in blur-my-shell@aunetx clipboard-indicator@tudmotu.com no-screenshot-box@screenshot dash-to-dock@micxgx.gmail.com; do
        info="$(run_in_user_session "${uid}" gnome-extensions info "${uuid}")"
        state="$(sed -n 's/^[[:space:]]*State:[[:space:]]*//p' <<<"${info}")"
        case "${state}" in 'OUT OF DATE' | OUT_OF_DATE | OUT-OF-DATE | ERROR) failures=$((failures + 1)) ;; *) return 1 ;; esac
        printf 'GNOME_EXTENSION_DIAGNOSTIC run_id=%s phase=%s known_extension=%s expected=old-incompatible state=%s\n' \
            "${run_id}" "${phase}" "${uuid}" "${state}"
    done
    [ "${failures}" -eq 4 ]
    [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = stock ]
    printf 'GNOME51_UPGRADE_BASELINE_PASS run_id=%s project_packages=6 aur_owners=4 local_v6=exact login=gdm-password shell_major=51 old_incompatible=4 preferences=preserved\n' "${run_id}"
    touch "${gnome51_migration_state}/baseline-login-proven"
    emit_marble_action_pass gnome51-real-baseline-login-old-failures-proven
}

upgrade_gnome51_baseline() {
    local uid
    gnome51_require_platform
    [ -f "${gnome51_migration_state}/baseline-login-proven" ]
    gnome51_verify_baseline_packages
    install -m0644 -- "${gnome51_migration_state}/candidate-repository.conf" "${legacy_repository_file}"
    # This is the promised production update: no explicitly named new package or AUR helper.
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt pacman -Syu --noconfirm --disable-download-timeout
    while IFS= read -r package; do installed_package_record_exact "${package}"; done < <(marble_project_packages) |
        LC_ALL=C sort | cmp -s -- - "${gnome51_migration_state}/candidate-packages.txt"
    while IFS= read -r package; do
        if package_installed_exact "${package}"; then return 1; fi
    done < <(gnome51_aur_packages)
    verify_marble_packages
    touch "${gnome51_migration_state}/transaction-proven"
    uid="$(id -u "${username}")"
    run_in_user_session "${uid}" gnome-session-quit --logout --no-prompt
    wait_for_named_user_logout "${username}"
    # Restart the actual greeter so its environment uses the just-upgraded scoped resource.
    systemctl restart gdm.service
    wait_for_greeter >/dev/null
    verify_marble_greeter active
    touch "${gnome51_migration_state}/candidate-gdm-scoped-proven"
    emit_marble_action_pass gnome51-plain-syu-replaced-four-owners
}

verify_gnome51_recovery_login() {
    local uid uuid info state
    gnome51_require_platform
    [ -f "${gnome51_migration_state}/baseline-login-proven" ]
    [ -f "${gnome51_migration_state}/transaction-proven" ]
    verify_marble_user_session marble
    [ "$(session_property "$(wait_for_user_session)" Service)" = gdm-password ]
    [ -f "${gnome51_migration_state}/candidate-gdm-scoped-proven" ]
    [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = active ]
    uid="$(id -u "${username}")"
    gnome51_preferences "${uid}" | cmp -s -- - "${gnome51_migration_state}/preferences.txt"
    while IFS= read -r uuid; do
        info="$(run_in_user_session "${uid}" gnome-extensions info "${uuid}")"
        state="$(sed -n 's/^[[:space:]]*State:[[:space:]]*//p' <<<"${info}")"
        case "${state}" in ENABLED | ACTIVE) ;; *) return 1 ;; esac
    done < <(printf '%s\n' appindicatorsupport@rgcjonas.gmail.com blur-my-shell@aunetx caffeine@patapon.info \
        clipboard-indicator@tudmotu.com dash-to-dock@micxgx.gmail.com just-perfection-desktop@just-perfection \
        no-screenshot-box@screenshot user-theme@gnome-shell-extensions.gcampax.github.com)
    python3 - "/home/${username}/.local/share/gnome-shell" "${gnome51_migration_state}/local-tree.json" <<'GNOME51_CUSTODY_PY'
import hashlib, json, pathlib, re, sys
root, receipt = map(pathlib.Path, sys.argv[1:]); expected = json.loads(receipt.read_text())
assert not (root / 'extensions/no-screenshot-box@screenshot').exists()
found = []
for parent in root.iterdir():
    if re.fullmatch(r'\.arch-linux-marble-custody-[0-9a-f]{32}', parent.name):
        assert not parent.is_symlink()
        tree = parent / 'no-screenshot-box@screenshot'
        if not tree.is_dir() or tree.is_symlink(): continue
        hashes = {}; identities = {}
        for path in tree.rglob('*'):
            assert not path.is_symlink()
            if path.is_file():
                name = path.relative_to(tree).as_posix(); info = path.stat()
                hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
                identities[name] = [info.st_dev, info.st_ino]
        if hashes == expected['hashes'] and identities == expected['identities']: found.append(tree)
assert len(found) == 1, 'exact original directory/inodes must be retained outside extension discovery'
GNOME51_CUSTODY_PY
    printf 'GNOME51_UPGRADE_RECOVERY_PASS run_id=%s transaction=plain-pacman-Syu aur_owners=0 bundle=installed login=gdm-password extensions=8-active custody=original-inodes preferences=preserved gdm=scoped user_overlay=absent\n' "${run_id}"
    emit_marble_action_pass gnome51-real-recovery-login-custody-settings-eight-active
}

verify_extension_probe_receipt() {
    local stage="$1" expected="${2:--}" uid
    uid="$(id -u "${username}")"
    python3 - "${probe_state}" "${stage}" "${expected}" "${run_id}" "${probe_round}" "${uid}" "${probe_source}" "${probe_trusted}" <<'EXTENSION_RECEIPT_PY'
import hashlib, json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1]); stage, expected, run_id, round_name = sys.argv[2:6]; uid = int(sys.argv[6])
source, trusted = map(pathlib.Path, sys.argv[7:9])
trusted_uid = 0
assert stat.S_ISDIR(trusted.lstat().st_mode) and trusted.stat().st_uid == trusted_uid and stat.S_IMODE(trusted.stat().st_mode) == 0o700
assert stat.S_ISREG(source.lstat().st_mode) and source.stat().st_uid == trusted_uid and stat.S_IMODE(source.stat().st_mode) == 0o500
probe = root / 'probe.js'; assert stat.S_ISREG(probe.lstat().st_mode) and probe.stat().st_uid == uid
digest = hashlib.sha256(source.read_bytes()).hexdigest()
assert hashlib.sha256(probe.read_bytes()).hexdigest() == digest
path = root / (stage + '.json'); info = path.lstat()
assert stat.S_ISREG(info.st_mode) and info.st_uid == uid and stat.S_IMODE(info.st_mode) == 0o600
raw = path.read_bytes(); assert len(raw) <= 2048
value = json.loads(raw)
assert set(value) == {'schema','runId','round','probeSha256','stage','valueSha256','pid'}
assert value['schema'] == 1 and value['runId'] == run_id and value['round'] == round_name
assert value['stage'] == stage and value['probeSha256'] == digest
assert value['valueSha256'] == expected and type(value['pid']) is int and value['pid'] > 1
process = pathlib.Path('/proc') / str(value['pid'])
def identity():
    fields = (process / 'stat').read_text().rsplit(')',1)[1].split()
    assert fields[0] != 'Z' and process.stat().st_uid == uid
    executable = os.readlink(process / 'exe'); assert executable == str(pathlib.Path('/usr/bin/gjs').resolve())
    argv = (process / 'cmdline').read_bytes().rstrip(b'\0').decode().split('\0')
    assert pathlib.Path(argv[0]).resolve() == pathlib.Path('/usr/bin/gjs').resolve()
    assert argv[1:] == ['-m',str(probe),str(root),run_id,round_name]
    return {'pid':value['pid'],'starttime':int(fields[19]),'executable':executable,'argv':argv,'probeSha256':digest}
actual = identity(); identity_path = trusted / 'identity.json'
if not identity_path.exists():
    assert stage == 'dash-ready'
    with identity_path.open('x') as output: output.write(json.dumps(actual)+'\n')
    identity_path.chmod(0o600)
info = identity_path.lstat()
assert stat.S_ISREG(info.st_mode) and info.st_uid == trusted_uid and stat.S_IMODE(info.st_mode) == 0o600
assert json.loads(identity_path.read_text()) == actual and identity() == actual
EXTENSION_RECEIPT_PY
}

probe_state=''
probe_round=''
probe_source='/run/arch-linux-qemu-extension-probe.js'
probe_trusted=''

load_extension_probe_state() {
    [ "${input_mode}:${scenario}" = staged:marble-gnome-btrfs-luks2-plymouth-systemdboot ]
    [[ "${phase}" =~ ^extension-(upgrade|postreboot)-([a-z-]+)$ ]]
    probe_round="${BASH_REMATCH[1]}"
    probe_state="/run/user/$(id -u "${username}")/arch-linux-qemu-extension-${run_id}-${probe_round}"
    probe_trusted="${gnome51_migration_state}/extension-${probe_round}"
}

extension_settings_schema() {
    case "$1" in
    dash) printf '%s\n' /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/schemas org.gnome.shell.extensions.dash-to-dock ;;
    clipboard) printf '%s\n' /usr/share/gnome-shell/extensions/clipboard-indicator@tudmotu.com/schemas org.gnome.shell.extensions.clipboard-indicator ;;
    screenshot) printf '%s\n' /usr/share/gnome-shell/extensions/no-screenshot-box@screenshot/schemas org.gnome.shell.extensions.no-screenshot-box ;;
    *) return 1 ;;
    esac
}

set_extension_setting() {
    local uid="$1" kind="$2" key="$3" value="$4"
    local -a schema=()
    mapfile -t schema < <(extension_settings_schema "${kind}")
    [ "${#schema[@]}" -eq 2 ]
    run_in_user_session "${uid}" gsettings --schemadir "${schema[0]}" set "${schema[1]}" "${key}" "${value}"
}

prepare_extension_probe() {
    local uid favorites desktop application path value encoded
    uid="$(id -u "${username}")"
    gnome51_require_platform
    [ -f "${gnome51_migration_state}/transaction-proven" ]
    [ ! -e "${probe_state}" ] && [ ! -L "${probe_state}" ]
    verify_marble_user_session marble
    [ ! -e "${probe_trusted}" ] && [ ! -L "${probe_trusted}" ]
    install -d -o0 -g0 -m0700 -- "${probe_trusted}"
    run_in_user_session "${uid}" mkdir -m0700 -- "${probe_state}"
    install -o "${uid}" -g "$(id -g "${username}")" -m0500 -- /run/arch-linux-qemu-extension-probe.js "${probe_state}/probe.js"
    sha256sum --binary -- "${probe_state}/probe.js" | awk '{print $1}' >"${probe_state}/probe.sha256"
    printf '[]\n' >"${probe_state}/settings.json"
    # Save only scoped, ephemeral test values; restore unset keys with dconf reset.
    for path in /org/gnome/shell/favorite-apps \
        /org/gnome/shell/extensions/dash-to-dock/hot-keys /org/gnome/shell/extensions/dash-to-dock/app-hotkey-1 \
        /org/gnome/shell/extensions/clipboard-indicator/enable-keybindings \
        /org/gnome/shell/extensions/clipboard-indicator/prev-entry /org/gnome/shell/extensions/clipboard-indicator/next-entry \
        /org/gnome/shell/extensions/clipboard-indicator/paste-on-select /org/gnome/shell/extensions/clipboard-indicator/move-item-first \
        /org/gnome/shell/extensions/no-screenshot-box/remove-preselected-box \
        /org/gnome/shell/extensions/no-screenshot-box/screenshot-on-release; do
        value="$(run_in_user_session "${uid}" dconf read "${path}")"
        jq --arg path "${path}" --arg value "${value}" '. + [{path:$path,value:$value}]' \
            "${probe_state}/settings.json" >"${probe_state}/settings.next"
        mv -- "${probe_state}/settings.next" "${probe_state}/settings.json"
    done
    application="org.archlinux.QemuExtensionProbe.${probe_round}"
    desktop="/home/${username}/.local/share/applications/${application}.desktop"
    [ ! -e "${desktop}" ] && [ ! -L "${desktop}" ]
    run_in_user_session "${uid}" mkdir -p -- "${desktop%/*}"
    printf '[Desktop Entry]\nType=Application\nName=Arch Linux extension acceptance\nExec=/usr/bin/gjs -m %s/probe.js %s %s %s\nTerminal=false\n' \
        "${probe_state}" "${probe_state}" "${run_id}" "${probe_round}" >"${probe_state}/probe.desktop"
    install -o "${uid}" -g "$(id -g "${username}")" -m0600 -- "${probe_state}/probe.desktop" "${desktop}"
    favorites="$(run_in_user_session "${uid}" gsettings get org.gnome.shell favorite-apps)"
    favorites="$(python3 - "${favorites}" "${application}.desktop" <<'EXTENSION_FAVORITES_PY'
import ast, sys
raw = sys.argv[1]
if raw.startswith('@as '): raw = raw[4:]
values = ast.literal_eval(raw); assert isinstance(values, list) and all(isinstance(x, str) for x in values)
assert sys.argv[2] not in values
print(repr([sys.argv[2]] + values))
EXTENSION_FAVORITES_PY
)"
    run_in_user_session "${uid}" gsettings set org.gnome.shell favorite-apps "${favorites}"
    set_extension_setting "${uid}" dash hot-keys true
    set_extension_setting "${uid}" dash app-hotkey-1 "['<Super>F6']"
    set_extension_setting "${uid}" clipboard enable-keybindings true
    set_extension_setting "${uid}" clipboard prev-entry "['<Control>F11']"
    set_extension_setting "${uid}" clipboard next-entry "['<Control>F12']"
    set_extension_setting "${uid}" clipboard paste-on-select false
    set_extension_setting "${uid}" clipboard move-item-first false
    sleep 2
    [ ! -e "${probe_state}/dash-ready.json" ]
    emit_marble_action_pass extension-probe-prepared-not-launched
}

wait_extension_probe_receipt() {
    local stage="$1" expected="${2:--}" deadline=$((SECONDS + 30))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ -f "${probe_state}/${stage}.json" ]; then
            verify_extension_probe_receipt "${stage}" "${expected}"
            return
        fi
        sleep 0.2
    done
    printf 'EXTENSION_FUNCTIONAL_FAIL phase=%s feature=observation stage=%s reason=missing-receipt\n' \
        "${probe_round}" "${stage}" >&2
    return 1
}

emit_extension_functional_pass() {
    local feature="$1" facts="$2" session hash
    session="$(wait_for_user_session)"
    [ "$(session_property "${session}" Service)" = gdm-password ]
    hash="$(sha256sum --binary -- "${probe_source}" | awk '{print $1}')"
    printf 'EXTENSION_FUNCTIONAL_PASS phase=%s feature=%s run_id=%s session=%s probe_sha256=%s %s\n' \
        "${probe_round}" "${feature}" "${run_id}" "${session}" "${hash}" "${facts}"
}

record_extension_screenshot_baseline() {
    local uid
    uid="$(id -u "${username}")"
    run_in_user_session "${uid}" gjs -c \
        'const GLib=imports.gi.GLib; print(GLib.build_filenamev([GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)||GLib.get_home_dir(),"Screenshots"]));' \
        >"${probe_state}/screenshot-directory.txt"
    python3 - "${probe_state}" "${uid}" "${username}" <<'EXTENSION_SCREEN_BASELINE_PY'
import json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1]); uid = int(sys.argv[2]); directory = pathlib.Path((root / 'screenshot-directory.txt').read_text().strip())
assert directory.is_absolute() and directory.is_relative_to(pathlib.Path('/home') / sys.argv[3])
assert directory.resolve() == directory
names = []; identities = []
if directory.exists():
    assert stat.S_ISDIR(directory.lstat().st_mode) and directory.stat().st_uid == uid
    for path in directory.iterdir():
        info = path.lstat(); names.append(path.name)
        if stat.S_ISREG(info.st_mode): identities.append([info.st_dev,info.st_ino])
(root / 'screenshot-baseline.json').write_text(json.dumps({'directory':str(directory),'names':sorted(names),'identities':identities})+'\n')
EXTENSION_SCREEN_BASELINE_PY
}

verify_extension_screenshot() {
    local expected="$1" uid
    uid="$(id -u "${username}")"
    python3 - "${probe_state}" "${expected}" "${uid}" <<'EXTENSION_SCREENSHOT_PY'
import binascii, hashlib, json, pathlib, stat, struct, sys, zlib
root = pathlib.Path(sys.argv[1]); expected = sys.argv[2]; uid = int(sys.argv[3])
baseline = json.loads((root / 'screenshot-baseline.json').read_text()); directory = pathlib.Path(baseline['directory'])
assert not directory.is_symlink() and directory.resolve() == directory
new = sorted(path for path in directory.iterdir() if path.name not in baseline['names']) if directory.exists() else []
if expected == 'absent':
    assert not new, 'disabled capture-on-release unexpectedly produced a file'
else:
    assert expected == 'present' and len(new) == 1, 'capture must produce exactly one new file'
    path = new[0]; before = path.lstat()
    assert [before.st_dev,before.st_ino] not in baseline['identities'], 'renamed pre-existing file is not a new capture'
    assert stat.S_ISREG(before.st_mode) and before.st_uid == uid and before.st_nlink == 1
    assert 24 <= before.st_size <= 32 * 1024 * 1024
    data = path.read_bytes(); after = path.stat()
    assert (before.st_ino,before.st_size,before.st_mtime_ns) == (after.st_ino,after.st_size,after.st_mtime_ns)
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR'
    width, height = struct.unpack('>II',data[16:24]); scale = json.loads((root / 'display.json').read_text())['scale']
    assert type(scale) is int and 1 <= scale <= 4 and (width,height) == (301*scale,201*scale), 'capture geometry differs from real drag'
    offset = 8; compressed = bytearray(); ended = False; channels = None
    while offset < len(data):
        size = struct.unpack('>I',data[offset:offset+4])[0]; kind = data[offset+4:offset+8]; chunk = data[offset+8:offset+8+size]
        assert len(chunk) == size and offset+12+size <= len(data)
        crc = struct.unpack('>I',data[offset+8+size:offset+12+size])[0]
        assert binascii.crc32(kind+chunk)&0xffffffff == crc
        if kind == b'IHDR':
            assert size == 13 and chunk[8] == 8 and chunk[9] in (2,6) and chunk[10:13] == b'\0\0\0'
            channels = 3 if chunk[9] == 2 else 4
        elif kind == b'IDAT': compressed.extend(chunk)
        elif kind == b'IEND': ended = True; assert size == 0 and offset+12 == len(data)
        offset += 12+size
    assert ended and channels is not None
    limit = (width*channels+1)*height
    decoded = zlib.decompressobj().decompress(compressed,limit+1)
    assert len(decoded) == limit
    output = {'name':path.name,'directory':str(directory),'sha256':hashlib.sha256(data).hexdigest(),
              'device':after.st_dev,'inode':after.st_ino,'width':width,'height':height}
    (root / 'last-screenshot.json').write_text(json.dumps(output)+'\n')
EXTENSION_SCREENSHOT_PY
}

wait_extension_screenshot() {
    local deadline=$((SECONDS + 30))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if verify_extension_screenshot present 2>/dev/null; then return; fi
        sleep 0.2
    done
    verify_extension_screenshot present
}

restore_extension_probe_settings() {
    local uid path encoded value
    uid="$(id -u "${username}")"
    while IFS=$'\t' read -r path encoded; do
        value="$(printf '%s' "${encoded}" | base64 --decode)"
        if [ -n "${value}" ]; then run_in_user_session "${uid}" dconf write "${path}" "${value}"
        else run_in_user_session "${uid}" dconf reset "${path}"
        fi
        [ "$(run_in_user_session "${uid}" dconf read "${path}")" = "${value}" ]
    done < <(jq -r '.[] | [.path,(.value|@base64)] | @tsv' "${probe_state}/settings.json")
}

cleanup_extension_probe() {
    local uid pid path encoded value desktop
    uid="$(id -u "${username}")"
    verify_extension_probe_receipt dash-ready
    pid="$(jq -er '.pid' "${probe_trusted}/identity.json")"
    [ "$(stat -c '%u' "/proc/${pid}")" = "${uid}" ]
    tr '\0' '\n' <"/proc/${pid}/cmdline" | grep -Fxq "${probe_state}/probe.js"
    kill -TERM -- "${pid}"
    for _ in {1..30}; do [ ! -d "/proc/${pid}" ] && break; sleep 0.1; done
    [ ! -d "/proc/${pid}" ]
    restore_extension_probe_settings
    desktop="/home/${username}/.local/share/applications/org.archlinux.QemuExtensionProbe.${probe_round}.desktop"
    cmp -s -- "${desktop}" "${probe_state}/probe.desktop"
    [ "$(stat -c '%u' "${desktop}")" = "${uid}" ] && [ ! -L "${desktop}" ]
    rm -f -- "${desktop}"
    python3 - "${probe_state}" "${uid}" <<'EXTENSION_CLEANUP_PY'
import hashlib, json, pathlib, stat, sys
root = pathlib.Path(sys.argv[1]); uid = int(sys.argv[2])
assert root.is_dir() and not root.is_symlink() and root.stat().st_uid == uid and root.stat().st_mode&0o777 == 0o700
for name in ['control-screenshot.json','positive-screenshot.json']:
    value = json.loads((root / name).read_text()); path = pathlib.Path(value['directory']) / value['name']; info=path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_uid == uid and info.st_nlink == 1
    assert (info.st_dev,info.st_ino) == (value['device'],value['inode'])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == value['sha256']; path.unlink()
for path in root.iterdir():
    assert path.is_file() and not path.is_symlink() and path.stat().st_uid in (0,uid)
    path.unlink()
root.rmdir()
EXTENSION_CLEANUP_PY
    rm -- "${probe_trusted}/identity.json"
    rmdir -- "${probe_trusted}"
    verify_marble_user_session marble
    emit_marble_action_pass extension-probe-settings-restored-owned-files-removed
}

run_extension_probe_phase() {
    local operation uid hash pid marker
    load_extension_probe_state
    operation="${phase#extension-"${probe_round}"-}"
    uid="$(id -u "${username}")"
    case "${operation}" in
    prepare) prepare_extension_probe ;;
    dash)
        wait_extension_probe_receipt dash-ready
        pid="$(jq -er '.pid' "${probe_state}/dash-ready.json")"
        [ "$(stat -c '%u' "/proc/${pid}")" = "${uid}" ]
        tr '\0' '\n' <"/proc/${pid}/cmdline" | grep -Fxq "${probe_state}/probe.js"
        jq -er 'select(.width>=640 and .width<=8192 and .height>=480 and .height<=8192 and .scale>=1 and .scale<=4) | "EXTENSION_PROBE_DISPLAY width=\(.width) height=\(.height) scale=\(.scale)"' "${probe_state}/display.json"
        emit_extension_functional_pass dash launch=unique-extension-binding
        ;;
    copied-a | copied-b | history-a | history-b | pasted-a | pasted-b)
        marker="archlinux-${run_id}-${probe_round}-${operation##*-}"
        hash="$(printf '%s' "${marker}" | sha256sum | awk '{print $1}')"
        wait_extension_probe_receipt "${operation}" "${hash}"
        if [ "${operation}" = pasted-b ]; then
            emit_extension_functional_pass clipboard history=two-values-real-copy-and-paste
        fi
        ;;
    control-prepare)
        set_extension_setting "${uid}" screenshot remove-preselected-box true
        set_extension_setting "${uid}" screenshot screenshot-on-release false
        record_extension_screenshot_baseline
        ;;
    control-no-capture) sleep 3; verify_extension_screenshot absent ;;
    control-captured)
        wait_extension_screenshot
        cp -- "${probe_state}/last-screenshot.json" "${probe_state}/control-screenshot.json"
        ;;
    positive-prepare)
        set_extension_setting "${uid}" screenshot screenshot-on-release true
        record_extension_screenshot_baseline
        ;;
    positive-captured)
        [ -f "${probe_state}/control-screenshot.json" ]
        wait_extension_screenshot
        cp -- "${probe_state}/last-screenshot.json" "${probe_state}/positive-screenshot.json"
        emit_extension_functional_pass screenshot control=manual-capture-positive=release-capture
        ;;
    cleanup) cleanup_extension_probe; return ;;
    *) return 2 ;;
    esac
    emit_marble_action_pass "extension-observed-${operation}"
}

user_executable_running() {
    local uid="$1" expected="$2" process owner executable
    for process in /proc/[0-9]*; do
        owner="$(stat -c %u -- "${process}" 2>/dev/null || true)"
        [ "${owner}" = "${uid}" ] || continue
        executable="$(readlink -f -- "${process}/exe" 2>/dev/null || true)"
        [ "${executable}" = "${expected}" ] && return 0
    done
    return 1
}

verify_user_manager_graphical_environment() {
    local uid="$1" environment desktop session_type wayland_display
    environment="$(run_in_user_session "${uid}" systemctl --user show-environment)"
    desktop="$(awk -F= '$1 == "XDG_CURRENT_DESKTOP" { print substr($0, index($0, "=") + 1); count++ }
        END { if (count != 1) exit 1 }' <<<"${environment}")" || return 1
    session_type="$(awk -F= '$1 == "XDG_SESSION_TYPE" { print substr($0, index($0, "=") + 1); count++ }
        END { if (count != 1) exit 1 }' <<<"${environment}")" || return 1
    wayland_display="$(awk -F= '$1 == "WAYLAND_DISPLAY" { print substr($0, index($0, "=") + 1); count++ }
        END { if (count != 1) exit 1 }' <<<"${environment}")" || return 1
    [[ ":${desktop}:" == *:GNOME:* ]] &&
        [ "${session_type}" = wayland ] &&
        [[ "${wayland_display}" =~ ^[A-Za-z0-9._-]+$ ]]
}

emit_user_app_diagnostics() {
    local uid="$1" executable="$2" diagnostics line
    diagnostics="$(run_in_user_session "${uid}" journalctl --user --no-pager --output=cat \
        --lines=40 "_EXE=${executable}" 2>/dev/null || true)"
    if [ -n "${diagnostics}" ]; then
        while IFS= read -r line; do
            printf 'GTK4_APP_DIAGNOSTIC executable=%s phase=%s message=%s\n' \
                "${executable}" "${phase}" "${line}" >&2
        done <<<"${diagnostics}"
    fi
}

provision_gtk4_smoke_dependencies() {
    local info
    if ! package_installed_exact gnome-boxes; then
        SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
            pacman -S --needed --noconfirm --disable-download-timeout extra/gnome-boxes
        printf 'GTK4_APP_DIAGNOSTIC executable=/usr/bin/gnome-boxes phase=%s message=test-only-official-package-provisioned\n' \
            "${phase}" >&2
    fi
    package_installed_exact gnome-boxes
    info="$(pacman -Qi -- gnome-boxes)"
    grep -Eq '^Name[[:space:]]*:[[:space:]]*gnome-boxes$' <<<"${info}"
    grep -Eq '^Validated By[[:space:]]*:[[:space:]]*Signature([[:space:]]|$)' <<<"${info}"
}

launch_and_wait_for_user_app() {
    local uid="$1" executable="$2" deadline=$((SECONDS + 60)) unit state diagnostics line
    local launch_status=0
    shift 2
    unit="arch-linux-qemu-${phase}-${executable##*/}"
    if [ ! -x "${executable}" ]; then
        printf 'GTK4_APP_LAUNCH_FAIL executable=%s unit=%s phase=%s category=summary reason=missing-executable\n' \
            "${executable}" "${unit}.service" "${phase}" >&2
        return 1
    fi
    user_executable_running "${uid}" "${executable}" && return 0
    if run_in_user_session "${uid}" systemd-run --user --quiet --collect \
        --property=Type=exec --unit="${unit}" "${executable}" "$@"; then
        while [ "${SECONDS}" -lt "${deadline}" ]; do
            user_executable_running "${uid}" "${executable}" && return 0
            sleep 1
        done
    else
        launch_status=$?
    fi
    state="$(run_in_user_session "${uid}" systemctl --user show "${unit}.service" \
        --property=LoadState --property=ActiveState --property=SubState \
        --property=Result --property=ExecMainStatus 2>&1 || true)"
    diagnostics="$(run_in_user_session "${uid}" journalctl --user --unit="${unit}.service" \
        --no-pager --output=cat --lines=40 2>&1 || true)"
    printf 'GTK4_APP_LAUNCH_FAIL executable=%s unit=%s phase=%s category=summary start_status=%s\n' \
        "${executable}" "${unit}.service" "${phase}" "${launch_status}" >&2
    while IFS= read -r line; do
        printf 'GTK4_APP_LAUNCH_FAIL executable=%s unit=%s phase=%s category=state message=%s\n' \
            "${executable}" "${unit}.service" "${phase}" "${line}" >&2
    done <<<"${state}"
    while IFS= read -r line; do
        printf 'GTK4_APP_LAUNCH_FAIL executable=%s unit=%s phase=%s category=journal message=%s\n' \
            "${executable}" "${unit}.service" "${phase}" "${line}" >&2
    done <<<"${diagnostics}"
    return 1
}

run_gtk4_app_smoke() {
    local scheme="$1" uid
    uid="$(id -u "${username}")"
    wait_for_user_session >/dev/null
    verify_user_manager_graphical_environment "${uid}"
    provision_gtk4_smoke_dependencies
    run_in_user_session "${uid}" gsettings set org.gnome.desktop.interface color-scheme "${scheme}"
    launch_and_wait_for_user_app "${uid}" /usr/bin/nautilus --new-window
    launch_and_wait_for_user_app "${uid}" /usr/bin/ptyxis
    launch_and_wait_for_user_app "${uid}" /usr/bin/gnome-control-center
    launch_and_wait_for_user_app "${uid}" /usr/bin/gnome-boxes
    emit_user_app_diagnostics "${uid}" /usr/bin/nautilus
    emit_user_app_diagnostics "${uid}" /usr/bin/ptyxis
    emit_user_app_diagnostics "${uid}" /usr/bin/gnome-control-center
    emit_user_app_diagnostics "${uid}" /usr/bin/gnome-boxes
    [ "$(run_in_user_session "${uid}" gsettings get org.gnome.desktop.interface color-scheme)" = \
        "'${scheme}'" ]
    [ "$(run_in_user_session "${uid}" /usr/lib/arch-linux-marble-profile/gtk4-session status)" = active ]
    run_in_user_session "${uid}" systemctl --user is-active --quiet arch-linux-marble-gtk4.service
    emit_marble_action_pass "gtk4-app-smoke-${scheme}-functional-rendering-not-visually-verified"
}

prepare_fresh_marble_user() {
    local account=marblefresh
    local uid password_hash greeter_session shell_pid environment major
    local profile='/run/arch-linux-qemu-gdm-profile'
    local database='/run/arch-linux-qemu-gdm-db'
    local keyfiles='/run/arch-linux-qemu-gdm-db.d'
    local dropin='/run/systemd/user/org.gnome.Shell@gdm.service.d/99-arch-linux-qemu-login.conf'
    major="$(marble_gdm_major)" || return 1
    [ ! -e "/home/${account}" ]
    [ ! -e "${profile}" ] && [ ! -e "${database}" ] && [ ! -e "${keyfiles}" ] && [ ! -e "${dropin}" ]
    useradd --create-home --user-group --shell /bin/bash marblefresh
    password_hash="$(getent shadow "${username}" | awk -F: 'NR == 1 { print $2 }')"
    [ -n "${password_hash}" ] && [[ "${password_hash}" != '!'* ]]
    printf '%s:%s\n' marblefresh "${password_hash}" | chpasswd --encrypted
    password_hash=''
    install -d -m0755 -- "${keyfiles}" "${dropin%/*}"
    printf '%s\n%s\n' '[org/gnome/login-screen]' 'disable-user-list=true' >"${keyfiles}/login-screen"
    chmod 0644 -- "${keyfiles}/login-screen"
    dconf compile "${database}" "${keyfiles}"
    chmod 0644 -- "${database}"
    printf '%s\n' \
        'user-db:user' \
        "file-db:${database}" \
        "file-db:/usr/share/arch-linux-marble-gdm/${major}.0.0/dconf/colloid-gdm-defaults" \
        'file-db:/usr/share/gdm/greeter-dconf-defaults' >"${profile}"
    chmod 0644 -- "${profile}"
    printf '%s\n%s\n' '[Service]' "Environment=DCONF_PROFILE=${profile}" >"${dropin}"
    chmod 0644 -- "${dropin}"
    /usr/share/libalpm/scripts/systemd-hook daemon-reload-user
    uid="$(id -u "${username}")"
    emit_gnome_shell_lifecycle_diagnostic "${uid}" before-original-user-logout
    run_in_user_session "${uid}" /usr/bin/gnome-session-quit --logout --no-prompt
    wait_for_named_user_logout "${username}"
    greeter_session="$(wait_for_greeter)"
    shell_pid="$(gdm_shell_pid "${greeter_session}")"
    environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    grep -qx "DCONF_PROFILE=${profile}" <<<"${environment}"
    [ "$(DCONF_PROFILE="${profile}" XDG_CONFIG_HOME=/dev/null \
        gsettings get org.gnome.login-screen disable-user-list)" = true ]
    emit_marble_action_pass fresh-user-created-with-password-user-list-disabled
}

verify_fresh_marble_user() {
    local account=marblefresh session uid shell_pid css expected_css
    session="$(wait_for_named_user_session "${account}")"
    uid="$(id -u "${account}")"
    [ "$(session_property "${session}" User)" = "${uid}" ]
    [ "$(session_property "${session}" Service)" = gdm-password ]
    [ "$(session_property "${session}" Type)" = wayland ]
    shell_pid="$(wait_for_gnome_shell "${uid}")"
    if tr '\0' '\n' <"/proc/${shell_pid}/environ" |
        grep -Eq '^(G_RESOURCE_OVERLAYS|DCONF_PROFILE)='; then
        return 1
    fi
    [ "$(run_in_named_user_session "${uid}" "${account}" gsettings get org.gnome.desktop.interface gtk-theme)" = \
        "'Colloid-Dark'" ]
    [ "$(run_in_named_user_session "${uid}" "${account}" /usr/lib/arch-linux-marble-profile/gtk4-session status)" = active ]
    run_in_named_user_session "${uid}" "${account}" systemctl --user is-active --quiet arch-linux-marble-gtk4.service
    expected_css='@import url("file:///usr/share/arch-linux-marble/gtk4/gtk.css");'
    for css in "/home/${account}/.config/gtk-4.0/gtk.css" \
        "/home/${account}/.config/gtk-4.0/gtk-dark.css"; do
        [ -f "${css}" ] && [ ! -L "${css}" ]
        [ "$(cat -- "${css}")" = "${expected_css}" ]
        [ "$(stat -c %u -- "${css}")" = "${uid}" ]
    done
    emit_marble_action_pass fresh-user-real-gdm-login-automatic-gtk4-active
}

logout_fresh_marble_user() {
    local account=marblefresh uid
    wait_for_named_user_session "${account}" >/dev/null
    uid="$(id -u "${account}")"
    run_in_named_user_session "${uid}" "${account}" /usr/bin/gnome-session-quit --logout --no-prompt
    wait_for_named_user_logout "${account}"
    emit_marble_action_pass fresh-user-real-session-logout
}

cleanup_fresh_marble_user() {
    local account=marblefresh
    local uid deadline
    local profile='/run/arch-linux-qemu-gdm-profile'
    local database='/run/arch-linux-qemu-gdm-db'
    local keyfiles='/run/arch-linux-qemu-gdm-db.d'
    local dropin='/run/systemd/user/org.gnome.Shell@gdm.service.d/99-arch-linux-qemu-login.conf'
    verify_marble_user_session marble
    rm -f -- "${dropin}" "${profile}" "${database}" "${keyfiles}/login-screen"
    rmdir -- "${keyfiles}"
    rmdir -- "${dropin%/*}" 2>/dev/null || true
    /usr/share/libalpm/scripts/systemd-hook daemon-reload-user
    uid="$(id -u marblefresh)"
    loginctl terminate-user marblefresh 2>/dev/null || true
    deadline=$((SECONDS + 60))
    while [ "${SECONDS}" -lt "${deadline}" ] && pgrep -u "${uid}" >/dev/null 2>&1; do
        sleep 1
    done
    if pgrep -u "${uid}" >/dev/null 2>&1; then return 1; fi
    userdel --remove marblefresh
    [ ! -e "/home/${account}" ]
}

run_lock_phase() {
    # /run exists in the installed OS; the live ISO's bootstrap directory does not.
    local state_file="/run/arch-linux-qemu-lock-${run_id}.state" session_id shell_pid uid boot_id deadline
    local -a state=()
    case "${phase}" in
    lock)
        [ ! -e "${state_file}" ] && [ ! -L "${state_file}" ]
        session_id="$(wait_for_user_session)"
        [ "$(session_property "${session_id}" Service)" = gdm-password ]
        [ "$(session_property "${session_id}" Type)" = wayland ]
        uid="$(id -u "${username}")"
        shell_pid="$(wait_for_gnome_shell "${uid}")"
        boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
        (umask 077; set -o noclobber
            printf 'session=%s\nuid=%s\nshell_pid=%s\nboot_id=%s\n' \
                "${session_id}" "${uid}" "${shell_pid}" "${boot_id}" >"${state_file}")
        loginctl lock-session "${session_id}"
        deadline=$((SECONDS + 120))
        while [ "${SECONDS}" -lt "${deadline}" ] &&
            [ "$(session_property "${session_id}" LockedHint)" != yes ]; do sleep 1; done
        [ "$(session_property "${session_id}" LockedHint)" = yes ]
        printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=lock boot_id=%s session=%s login_service=gdm-password session_type=wayland locked=yes failed_units=0\n' \
            "${marker_prefix}" "${run_id}" "${scenario}" "${boot_id}" "${session_id}"
        ;;
    unlock)
        [ -f "${state_file}" ] && [ ! -L "${state_file}" ] &&
            [ "$(stat -Lc '%u:%a:%h' -- "${state_file}")" = '0:600:1' ]
        mapfile -t state <"${state_file}"
        [ "${#state[@]}" -eq 4 ]
        [[ "${state[0]}" =~ ^session=([A-Za-z0-9_-]+)$ ]]
        session_id="${BASH_REMATCH[1]}"
        [[ "${state[1]}" =~ ^uid=([0-9]+)$ ]]
        uid="${BASH_REMATCH[1]}"
        [[ "${state[2]}" =~ ^shell_pid=([1-9][0-9]*)$ ]]
        shell_pid="${BASH_REMATCH[1]}"
        [[ "${state[3]}" =~ ^boot_id=([a-f0-9-]{36})$ ]]
        boot_id="${BASH_REMATCH[1]}"
        deadline=$((SECONDS + 120))
        while [ "${SECONDS}" -lt "${deadline}" ] &&
            [ "$(session_property "${session_id}" LockedHint)" != no ]; do sleep 1; done
        [ "$(session_property "${session_id}" LockedHint)" = no ]
        [ "$(wait_for_user_session)" = "${session_id}" ]
        [ "$(session_property "${session_id}" Service)" = gdm-password ]
        [ "$(session_property "${session_id}" Type)" = wayland ]
        [ "$(wait_for_gnome_shell "${uid}")" = "${shell_pid}" ]
        [ "$(tr -d '\n' </proc/sys/kernel/random/boot_id)" = "${boot_id}" ]
        if [[ "${scenario}" = marble-gnome-* ]]; then
            verify_marble_user_session marble
        else
            verify_stock_session
        fi
        rm -f -- "${state_file}"
        printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=unlock boot_id=%s session=%s login_service=gdm-password session_type=wayland same_session=yes password_transport=hmp failed_units=0\n' \
            "${marker_prefix}" "${run_id}" "${scenario}" "${boot_id}" "${session_id}"
        ;;
    *) return 2 ;;
    esac
}

exercise_gdm_helper_failure() {
    local directory="$1" helper="$2" payload="$3" prepare_status=0 status_status=0
    local override="${directory}/50-arch-linux-marble-gdm.conf"
    [ -d "${directory}" ] && [ ! -L "${directory}" ] || return 1
    [ "$(stat -Lc '%u:%a' -- "${directory}")" = "$(id -u):755" ] || return 1
    [ -L "${override}" ] && [ "$(readlink -- "${override}")" = "${payload}" ] || return 1
    # Only the disposable guest's exact project directory is changed. Restore it
    # before assessing outcomes, including unexpected helper success.
    chmod 0777 -- "${directory}" || return 1
    "${helper}" --prepare >/dev/null 2>&1 || prepare_status=$?
    "${helper}" --status >/dev/null 2>&1 || status_status=$?
    chmod 0755 -- "${directory}" || return 1
    [ "${prepare_status}" -eq 1 ] && [ "${status_status}" -eq 1 ] || return 1
    [ -L "${override}" ] && [ "$(readlink -- "${override}")" = "${payload}" ] || return 1
    printf 'QEMU_GDM_HELPER_FAILURE prepare_status=%s status_status=%s persistent_activation=retained stock_claim=none\n' \
        "${prepare_status}" "${status_status}"
}

run_marble_phase() {
    local expected_profile gdm_major
    case "${phase}" in
    extension-upgrade-* | extension-postreboot-*)
        run_extension_probe_phase
        ;;
    prelogin)
        verify_marble_greeter active
        verify_public_release_pages_binding
        ;;
    postreboot-prelogin | restored-prelogin | reinstalled-prelogin | helper-restored-prelogin)
        verify_marble_greeter active
        ;;
    deactivated-prelogin)
        verify_marble_greeter deactivated
        ;;
    incompatible-prelogin)
        verify_marble_greeter fallback
        ;;
    removed-prelogin)
        verify_marble_greeter removed
        ;;
    firstlogin | secondlogin | migrated-login | restored-login | reinstalled-login | helper-restored-login)
        verify_marble_user_session marble
        ;;
    legacy-install)
        install_legacy_migration_packages
        ;;
    legacy-login)
        verify_legacy_user_session
        ;;
    migration-update)
        update_legacy_session_to_candidate
        ;;
    gnome51-baseline-install)
        install_gnome51_baseline
        ;;
    gnome51-baseline-login)
        verify_gnome51_baseline_login
        ;;
    gnome51-upgrade)
        upgrade_gnome51_baseline
        ;;
    gnome51-upgraded-login)
        verify_gnome51_recovery_login
        ;;
    gtk4-app-smoke-light)
        run_gtk4_app_smoke default
        ;;
    gtk4-app-smoke-dark)
        run_gtk4_app_smoke prefer-dark
        ;;
    fresh-user-prepare)
        prepare_fresh_marble_user
        ;;
    fresh-user-login)
        verify_fresh_marble_user
        ;;
    fresh-user-logout)
        logout_fresh_marble_user
        ;;
    return-user-login)
        cleanup_fresh_marble_user
        ;;
    deactivated-login)
        verify_marble_user_session fallback
        ;;
    incompatible-login)
        verify_marble_user_session fallback
        ;;
    removed-login)
        verify_marble_user_session stock
        ;;
    update)
        if [ "${input_mode}" = public ]; then
            verify_public_repository_contract
            pacman -Syu --noconfirm --disable-download-timeout
            verify_public_repository_contract
        else
            SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
                pacman -Syu --noconfirm --disable-download-timeout
        fi
        verify_kernel_initramfs_pair /boot/initramfs-linux.img
        verify_marble_packages
        verify_vendor_integrity
        if marble_gdm_enabled; then
            [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = active ]
        fi
        emit_marble_action_pass pacman-syu-hooks-active-qkk-clean
        ;;
    helper-failure)
        gdm_major="$(marble_gdm_major)" || return 1
        exercise_gdm_helper_failure /etc/systemd/user/org.gnome.Shell@gdm.service.d \
            /usr/lib/arch-linux-marble-gdm/update-compatibility \
            "/usr/share/arch-linux-marble-gdm/systemd/${gdm_major}-arch-linux-marble-gdm.conf"
        # Failure retained activation; inspect the actual existing authenticated
        # session as Marble instead of inferring a successful Stock transition.
        verify_marble_user_session marble
        restart_gdm_after_profile_transition
        emit_marble_action_pass helper-failure-observed-activation-retained
        ;;
    deactivate-gdm)
        /usr/lib/arch-linux-marble-gdm/update-compatibility --remove
        [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = stock ]
        restart_gdm_after_profile_transition
        emit_marble_action_pass explicit-gdm-deactivation
        ;;
    incompatible-fixture)
        [ ! -e /etc/dconf/profile/gdm ] && [ ! -L /etc/dconf/profile/gdm ]
        install -Dm0644 -- /usr/share/dconf/profile/gdm /etc/dconf/profile/gdm
        /usr/lib/arch-linux-marble-gdm/update-compatibility
        /usr/share/libalpm/scripts/systemd-hook daemon-reload-user
        [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = stock ]
        SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
            pacman -Syu --noconfirm --disable-download-timeout
        [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = stock ]
        restart_gdm_after_profile_transition
        emit_marble_action_pass administrator-profile-stock-fallback
        ;;
    restore-marble)
        cmp -s -- /etc/dconf/profile/gdm /usr/share/dconf/profile/gdm
        rm -f -- /etc/dconf/profile/gdm
        /usr/lib/arch-linux-marble-gdm/update-compatibility
        /usr/share/libalpm/scripts/systemd-hook daemon-reload-user
        [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = active ]
        restart_gdm_after_profile_transition
        emit_marble_action_pass marble-reactivated-after-fixture
        ;;
    remove-marble)
        mapfile -t expected_profile < <(marble_theme_packages)
        pacman -Rns --noconfirm "${expected_profile[@]}"
        verify_stock_project_packages
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk.css" ]
        [ ! -e "/home/${username}/.config/gtk-4.0/gtk-dark.css" ]
        verify_package_qkk_zero gnome-shell gdm >/dev/null
        restart_gdm_after_profile_transition
        emit_marble_action_pass project-packages-removed-stock
        ;;
    reinstall-marble)
        SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt pacman -S --noconfirm \
            arch-linux-marble-profile arch-linux-marble-gdm
        /usr/lib/arch-linux-marble-profile/update-compatibility
        /usr/lib/arch-linux-marble-gdm/update-compatibility
        /usr/share/libalpm/scripts/systemd-hook daemon-reload-user
        verify_marble_packages
        verify_vendor_integrity
        [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = active ]
        restart_gdm_after_profile_transition
        emit_marble_action_pass project-packages-reinstalled-marble-active
        ;;
    *) return 2 ;;
    esac
}

verify_neighbor_readback() {
    local proof="$1" manifest="$2" directory="$3" esp="$4" neighbor="$5" key expected device field
    local expected_names actual_names
    for field in "${proof}" "${manifest}"; do
        [ -f "${field}" ] && [ ! -L "${field}" ] || return 1
        [ "$(stat -Lc '%u:%a:%h' -- "${field}")" = '0:600:1' ] || return 1
    done
    [ "$(wc -l <"${proof}")" -eq 5 ] || return 1
    grep -qxF "run_id=${run_id}" "${proof}" || return 1
    for key in esp_uuid esp_partuuid neighbor_uuid neighbor_partuuid; do
        [ "$(grep -c "^${key}=" "${proof}")" -eq 1 ] || return 1
        expected="$(sed -n "s/^${key}=//p" "${proof}")"
        [[ "${expected}" =~ ^[A-Za-z0-9-]+$ ]] || return 1
        device="${esp}"
        [[ "${key}" = esp_* ]] || device="${neighbor}"
        field=UUID
        [[ "${key}" != *_partuuid ]] || field=PARTUUID
        [ "$(blkid -s "${field}" -o value "${device}")" = "${expected}" ] || return 1
    done
    expected_names="$(printf '%s\n' etc/hostname etc/fstab neighbor-preserved.txt \
        boot/EFI/ali-neighbor/vmlinuz-linux boot/EFI/ali-neighbor/initramfs-linux.img \
        boot/loader/entries/neighbor.conf | LC_ALL=C sort)"
    [ "$(wc -l <"${manifest}")" -eq 6 ] || return 1
    [ "$(grep -Ec '^[a-f0-9]{64}  [A-Za-z0-9_./-]+$' "${manifest}")" -eq 6 ] || return 1
    actual_names="$(cut -c67- "${manifest}" | LC_ALL=C sort)"
    [ "${actual_names}" = "${expected_names}" ] || return 1
    (cd -- "${directory}" && sha256sum --check --strict "${manifest}") || return 1
    printf 'QEMU_NEIGHBOR_READBACK run_id=%s phase=%s identities=preserved hashes=6\n' "${run_id}" "${phase}"
}

verify_dual_boot_preservation() {
    local target="$1"
    (
        set -e
        local work neighbor_mount proof_mount esp neighbor newroot proof_root owned status
        work="$(mktemp -d /run/qa-neighbor.XXXXXXXX)"
        neighbor_mount="${work}/neighbor" proof_mount="${work}/proof"
        mkdir -- "${neighbor_mount}" "${proof_mount}"
        # Preserve a failing check and surface cleanup failures as failures too.
        trap 'status=$?; trap - EXIT; for owned in "${neighbor_mount}/boot" "${neighbor_mount}" "${proof_mount}"; do if mountpoint -q "$owned"; then umount -- "$owned" || status=1; fi; done; rmdir -- "${neighbor_mount}" "${proof_mount}" "${work}" || status=1; exit "$status"' EXIT
        esp="$(partition_name "${target}" 1)"
        neighbor="$(partition_name "${target}" 2)"
        newroot="$(partition_name "${target}" 3)"
        if [ "${phase}" = neighbor ]; then
            [ "$(mounted_source_device /boot)" = "${esp}" ]
            mount -o ro,noload -- "${newroot}" "${proof_mount}"
            proof_root="${proof_mount}/var/lib/arch-linux-vm"
            verify_neighbor_readback "${proof_root}/neighbor-identities.txt" \
                "${proof_root}/neighbor.sha256" / "${esp}" "${neighbor}"
        else
            # The installed ESP is already mounted RW. A second block-device RO
            # mount conflicts with its superblock; give only our readback bind RO.
            [ "$(mounted_source_device /boot)" = "${esp}" ]
            [ "$(findmnt -nro FSTYPE --target /boot)" = vfat ]
            [ "$(findmnt -nro FSROOT --target /boot)" = / ]
            mount -o ro,noload -- "${neighbor}" "${neighbor_mount}"
            mount --bind -- /boot "${neighbor_mount}/boot"
            mount -o remount,bind,ro -- "${neighbor_mount}/boot"
            [ "$(mounted_source_device "${neighbor_mount}/boot")" = "${esp}" ]
            [ "$(findmnt -nro FSTYPE --target "${neighbor_mount}/boot")" = vfat ]
            [ "$(findmnt -nro FSROOT --target "${neighbor_mount}/boot")" = / ]
            case ",$(findmnt -nro VFS-OPTIONS --target "${neighbor_mount}/boot")," in
                *,ro,*) ;;
                *) return 1 ;;
            esac
            proof_root=/var/lib/arch-linux-vm
            verify_neighbor_readback "${proof_root}/neighbor-identities.txt" \
                "${proof_root}/neighbor.sha256" "${neighbor_mount}" "${esp}" "${neighbor}"
        fi
    )
}

verify_dual_boot_phase() {
    local target root_device expected_root boot_id
    [ "${scenario}" = minimal-dualboot-ext4-systemdboot ]
    target="$(find_target)"
    root_device="$(mounted_source_device /)"
    if [ "${phase}" = neighbor-select ]; then
        expected_root="$(partition_name "${target}" 3)"
        [ "${root_device}" = "${expected_root}" ]
        grep -qx 'ARCH_LINUX_DUAL_BOOT_ENABLED=true' "/home/${username}/installer.conf"
        [ -f /boot/loader/entries/neighbor.conf ]
        verify_dual_boot_preservation "${target}"
        bootctl set-oneshot neighbor.conf
    else
        expected_root="$(partition_name "${target}" 2)"
        [ "${root_device}" = "${expected_root}" ]
        [ "$(cat /proc/sys/kernel/hostname)" = ali-neighbor ]
        [ "$(cat /neighbor-preserved.txt)" = "${run_id}" ]
        verify_dual_boot_preservation "${target}"
        # Preserve and boot this existing OS; do not administer its services or network.
        # The newly installed target retains its full network/service/bootloader checks.
    fi
    boot_id="$(cat /proc/sys/kernel/random/boot_id)"
    printf 'MINIMAL_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s neighbor=preserved\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}"
}

if [ "${phase}" = gdm-activation-baseline ] || [ "${phase}" = gdm-activation-check ]; then
    gdm_activation_probe
    exit 0
fi

if [ "${phase}" = media-readback-prepare ]; then
    prepare_media_readback
    exit 0
fi

if [ "${media_qualification}" = true ] &&
    { [ "${phase}" = firstboot ] || [ "${phase}" = prelogin ]; }; then
    verify_public_release_pages_binding
fi

if [ "${phase}" = snapshot-prepare ]; then
    prepare_snapshot_boot
elif [ "${phase}" = snapshot-cleanup ]; then
    cleanup_snapshot_boot
elif [ "${phase}" = snapshot-prelogin ]; then
    verify_stock_greeter
elif [ "${phase}" = snapshot-login ]; then
    verify_stock_session
elif [ "${phase}" = neighbor-select ] || [ "${phase}" = neighbor ]; then
    verify_dual_boot_phase
elif [[ "${scenario}" = minimal-* ]]; then
    verify_minimal
elif [ "${phase}" = lock ] || [ "${phase}" = unlock ]; then
    run_lock_phase
elif [[ "${scenario}" = marble-gnome-* ]]; then
    run_marble_phase
elif [ "${phase}" = prelogin ] || [ "${phase}" = postreboot-prelogin ]; then
    verify_stock_greeter
else
    verify_stock_session
fi
