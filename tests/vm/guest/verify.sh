#!/usr/bin/env bash

set -Eeuo pipefail
umask 077
export LC_ALL=C

marker_prefix=''

guest_error() {
    local status=$? line="$1" command="$2"
    trap - ERR
    printf '%s_QEMU_GUEST_FAIL phase=%s line=%s status=%s command=%q\n' \
        "${marker_prefix:-UNKNOWN}" "${phase:-preflight}" "${line}" "${status}" "${command}" >&2
    exit "${status}"
}
trap 'guest_error "$LINENO" "$BASH_COMMAND"' ERR

[ "$#" -eq 21 ] || { printf 'usage: verify.sh PHASE SERIAL VENDOR MODEL USERNAME SCENARIO RUN_ID REPOSITORY_PRIMARY REPOSITORY_SIGNING INPUT_MODE RELEASE_VERSION PAGES_URL PUBLIC_KEY_URL SNAPSHOT_SHA256 SOURCE_COMMIT SOURCE_TREE INSTALLER_SHA256 PACKAGE_SET_SHA256 BUILD_METADATA_SHA256 UNSIGNED_MANIFEST_SHA256 PUBLIC_KEY_SHA256\n' >&2; exit 2; }
readonly phase="$1" expected_serial="$2" expected_vendor="$3" expected_model="$4"
readonly username="$5" scenario="$6" run_id="$7" repository_primary="$8"
readonly repository_signing="$9" input_mode="${10}" release_version="${11}"
readonly pages_url="${12}" public_key_url="${13}" snapshot_sha256="${14}"
readonly source_commit="${15}" source_tree="${16}" installer_sha256="${17}"
readonly package_set_sha256="${18}" build_metadata_sha256="${19}"
readonly unsigned_manifest_sha256="${20}" public_key_sha256="${21}"
case "${scenario}" in
minimal-ext4-systemdboot)
    marker_prefix='MINIMAL'
    case "${phase}" in firstboot | update | postreboot) ;; *) exit 2 ;; esac
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
    case "${phase}" in prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100S[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_STK_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^stock-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-systemdboot)
    marker_prefix='BTRFS'
    case "${phase}" in prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100B[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_BTR_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^btrfs-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-grub)
    marker_prefix='GRUB'
    case "${phase}" in prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100G[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-luks2-plymouth-systemdboot)
    marker_prefix='LUKS'
    case "${phase}" in prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100L[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_LUK_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^luks-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
stock-gnome-btrfs-luks2-plymouth-grub)
    marker_prefix='LUKSGRUB'
    case "${phase}" in prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;; *) exit 2 ;; esac
    [[ "${expected_serial}" =~ ^ALI100G[A-F0-9]{12}$ ]]
    [[ "${expected_model}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]]
    [[ "${run_id}" =~ ^luksgrub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
    ;;
marble-gnome-btrfs-luks2-plymouth-systemdboot)
    marker_prefix='MARBLE'
    case "${phase}" in
    prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin | \
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
    prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin | \
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
[ "${release_version}" = 1.0.0 ]
[[ "${snapshot_sha256}" =~ ^[a-f0-9]{64}$ ]]
[[ "${source_commit}" =~ ^[a-f0-9]{40}$ ]]
[[ "${source_tree}" =~ ^[a-f0-9]{40}$ ]]
for expected_digest in "${installer_sha256}" "${package_set_sha256}" \
    "${build_metadata_sha256}" "${unsigned_manifest_sha256}" "${public_key_sha256}"; do
    [[ "${expected_digest}" =~ ^[a-f0-9]{64}$ ]]
done
case "${input_mode}" in
staged)
    [ "${pages_url}" = - ] && [ "${public_key_url}" = - ]
    ;;
public)
    [ "${scenario}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ]
    case "${phase}" in
    prelogin | firstlogin | lock | unlock | update | postreboot-prelogin | secondlogin) ;;
    *) exit 2 ;;
    esac
    [ "${pages_url}" = "https://snaplyze.github.io/arch-linux/repo/\$arch" ]
    [ "${public_key_url}" = 'https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg' ]
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
        if [ "${serial}" = "${expected_serial}" ] && [ "${vendor}" = "${expected_vendor}" ] &&
            [ "${model}" = "${expected_model}" ]; then
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

wait_for_user_session() {
    local deadline=$((SECONDS + 300)) candidate=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        candidate="$(find_session user "${username}" gdm-password 2>/dev/null || true)"
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
    local uid="$1" gid
    shift
    gid="$(id -g "${username}")"
    /usr/bin/setpriv --reuid="${uid}" --regid="${gid}" --init-groups /usr/bin/env \
        HOME="/home/${username}" USER="${username}" LOGNAME="${username}" \
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
    local uid="$1" config="/home/${username}/installer.conf" expected_x11 actual key expected shell_pid
    wait_for_desktop_initialization "/home/${username}/.config/autostart/initialize.desktop"
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

wait_for_enabled_extensions() {
    local uid="$1" expected="$2" deadline=$((SECONDS + 180)) actual=''
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if actual="$(run_in_user_session "${uid}" /usr/bin/gnome-extensions list --enabled 2>/dev/null | LC_ALL=C sort)" &&
            [ "${actual}" = "${expected}" ]; then
            printf '%s' "${actual}"
            return 0
        fi
        sleep 1
    done
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
    is_grub_stock && expected_hooks+=' grub-btrfs-overlayfs'
    [ "${hooks}" = "${expected_hooks}" ]
    [ "$(plymouth-set-default-theme)" = archlinux ]
    pacman -Q plymouth plymouth-theme-archlinux >/dev/null
    [ -f "${image}" ] && [ ! -L "${image}" ]
    listing="$(lsinitcpio -l "${image}")"
    grep -Eq '(^|/)systemd-cryptsetup$' <<<"${listing}"
    grep -Eq '(^|/)plymouthd?$' <<<"${listing}"
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
    [ -z "$(pacman -Qq | grep '^arch-linux-' || true)" ]
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
    target="$(verify_common)"
    config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    verify_stock_profile "${config}"
    if is_btrfs_stock; then
        verify_btrfs_contract
        root_contract='root=btrfs btrfs_contract=verified encryption=off snapper=off btrfs_assistant=off'
        if is_luks_stock; then
            root_contract='root=btrfs btrfs_contract=verified encryption=luks2 mapper=cryptroot plymouth=on snapper=off btrfs_assistant=off'
        fi
    fi
    is_grub_stock && bootloader_contract='grub'
    greeter_session="$(wait_for_greeter)"
    [ -n "${greeter_session}" ]
    boot_id="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    [[ "${boot_id}" =~ ^[a-f0-9-]{36}$ ]]
    printf '%s_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s pttype=gpt %s bootloader=%s default_target=graphical.target graphical_target=active gdm=active greeter_session=%s greeter_name=gdm-greeter greeter_service=gdm-launch-environment greeter_class=greeter greeter_type=wayland autologin=disabled network=online failed_units=0 stock_gdm=yes marble=inactive\n' \
        "${marker_prefix}" "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}" \
        "${root_contract}" "${bootloader_contract}" "${greeter_session}"
}

verify_stock_session() {
    local target config user_session uid session_uid shell_pid shell_environment
    local enabled_extensions installed_extensions expected_extensions cursor_theme gtk_theme icon_theme
    local boot_id ptyxis_version root_contract='root=ext4' bootloader_contract='systemd-boot'
    [ "${phase}" = update ] && pacman -Syu --noconfirm --disable-download-timeout
    if [ "${phase}" = update ] && is_grub_stock; then
        verify_grub_regeneration
    fi
    target="$(verify_common)"
    config="/home/${username}/installer.conf"
    [ -f "${config}" ]
    verify_stock_profile "${config}"
    if is_btrfs_stock; then
        verify_btrfs_contract
        root_contract='root=btrfs btrfs_contract=verified encryption=off snapper=off btrfs_assistant=off'
        if is_luks_stock; then
            root_contract='root=btrfs btrfs_contract=verified encryption=luks2 mapper=cryptroot plymouth=on snapper=off btrfs_assistant=off'
        fi
    fi
    is_grub_stock && bootloader_contract='grub'
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
        arch-linux-marble-shell \
        arch-linux-colloid-gtk3 \
        arch-linux-colloid-icons \
        arch-linux-marble-profile
    if marble_gdm_enabled; then
        printf '%s\n' arch-linux-marble-gdm
    fi
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
    if grep -Eq 'TrustAll|PackageOptional|DatabaseOptional|https://10\.0\.2\.2:' \
        "${repository_file}" /etc/pacman.conf; then
        return 1
    fi
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
        info="$(pacman -Qi -- "${package}")"
        grep -Eq '^Validated By[[:space:]]*:[[:space:]]*Signature([[:space:]]|$)' <<<"${info}"
    done < <(marble_project_packages)
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

verify_public_release_pages_binding() (
    local release_base archive_name archive_url pages_base work pages_dir keyring sums sums_signature
    local archive archive_signature archive_checksum release_manifest release_manifest_signature
    local pages_manifest pages_manifest_signature manifest_tsv name checksum size actual_names expected_names
    local package package_file release_sums_hash repository_manifest_hash repository_manifest_signature_hash
    local expected_package_files='' database_filenames='' member filename files_desc_count files_list_count
    local -a package_matches=()
    [ "${input_mode}" = public ] || return 0
    for command_name in awk base64 bsdtar cmp curl cut find gpg gpgv grep jq mktemp sed sha256sum sort stat; do
        command -v -- "${command_name}" >/dev/null
    done
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
        (.files | type == "array" and length == 23 and all(.[];
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
    [ "${files_desc_count}" -eq 6 ] && [ "${files_list_count}" -eq 6 ]

    printf 'MARBLE_PUBLIC_SNAPSHOT_BINDING_PASS run_id=%s snapshot_sha256=%s release_sums_sha256=%s repository_manifest_sha256=%s repository_manifest_signature_sha256=%s pages_objects=23 package_signatures=6 database_signatures=2\n' \
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
        pacman -Q -- "${package}" >/dev/null
    done
    qkk="$(verify_package_qkk_zero "${packages[@]}")"
    project_paths="$(pacman -Qlq "${packages[@]}")"
    if grep -Eq '(^|/)(home|root)/|(^|/)gtk-4\.0/|(^|/)usr/share/icons/default(/|$)|icon-theme\.cache$|gnome-shell-theme\.gresource$|(^|/)usr/share/(gdm|gdm3)(/|$)|(^|/)etc/(gdm|gdm3)(/|$)|(^|/)var/lib/gdm(/|$)' \
        <<<"${project_paths}"; then
        return 1
    fi
    [ -L /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark ]
    [ "$(readlink -- /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark)" = \
        /usr/share/arch-linux-marble/shell/50.0.0/Marble-blue-dark ]
    [ -f /usr/share/themes/Colloid-Dark/gtk-3.0/gtk.css ]
    [ -f /usr/share/icons/Colloid-Dark/index.theme ]
    [ -z "$(find /usr/share/arch-linux-marble \
        -type f -path '*/gtk-4.0/*' -print -quit)" ]
    if marble_gdm_enabled; then
        [ -z "$(find /usr/share/arch-linux-marble-gdm -type f -path '*/gtk-4.0/*' -print -quit)" ]
    else
        if pacman -Q arch-linux-marble-gdm >/dev/null 2>&1; then return 1; fi
        [ ! -e /usr/share/arch-linux-marble-gdm ]
    fi
    printf 'MARBLE_QEMU_PROJECT_QKK run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${qkk}"
}

verify_vendor_integrity() {
    local qkk
    qkk="$(verify_package_qkk_zero gnome-shell gdm)"
    if marble_gdm_enabled; then
        sha256sum --check --strict \
            /usr/share/arch-linux-marble-gdm/known-gnome-50.sha256 >/dev/null
    fi
    [ "$(pacman -Qo /usr/share/gnome-shell/gnome-shell-theme.gresource | awk '{ print $5 }')" = gnome-shell ]
    [ "$(pacman -Qo /usr/share/dconf/profile/gdm | awk '{ print $5 }')" = gdm ]
    printf 'MARBLE_QEMU_VENDOR_QKK run_id=%s phase=%s\n%s\n' "${run_id}" "${phase}" "${qkk}"
}

gdm_shell_pid() {
    local greeter_session="$1" greeter_uid candidate
    # GDM 50 uses the logind gdm-greeter identity without requiring a passwd entry named gdm.
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
    local expected="$1" greeter_session="$2" shell_pid environment helper_status
    helper_status="$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)"
    shell_pid="$(gdm_shell_pid "${greeter_session}")"
    environment="$(tr '\0' '\n' <"/proc/${shell_pid}/environ")"
    if [ "${expected}" = active ]; then
        [ "${helper_status}" = active ]
        [ -L /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf ]
        [ "$(readlink -- /etc/systemd/user/org.gnome.Shell@gdm.service.d/50-arch-linux-marble-gdm.conf)" = \
            /usr/share/arch-linux-marble-gdm/systemd/50-arch-linux-marble-gdm.conf ]
        grep -qx 'G_RESOURCE_OVERLAYS=/org/gnome/shell/theme=/usr/share/arch-linux-marble-gdm/50.0.0/theme' \
            <<<"${environment}"
        grep -qx 'DCONF_PROFILE=/usr/share/arch-linux-marble-gdm/50.0.0/dconf/profile' \
            <<<"${environment}"
        [ "$(DCONF_PROFILE=/usr/share/arch-linux-marble-gdm/50.0.0/dconf/profile \
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
    fallback)
        verify_marble_packages
        verify_vendor_integrity
        [ -f /etc/dconf/profile/gdm ] && [ ! -L /etc/dconf/profile/gdm ]
        verify_marble_gdm_process stock "${greeter_session}"
        ;;
    removed)
        [ -z "$(pacman -Qq | grep '^arch-linux-' || true)" ]
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
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
        [ -z "$(pacman -Qq | grep '^arch-linux-' || true)" ]
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
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

run_marble_phase() {
    local expected_profile
    case "${phase}" in
    prelogin)
        verify_marble_greeter active
        verify_public_release_pages_binding
        ;;
    postreboot-prelogin | restored-prelogin | reinstalled-prelogin)
        verify_marble_greeter active
        ;;
    incompatible-prelogin)
        verify_marble_greeter fallback
        ;;
    removed-prelogin)
        verify_marble_greeter removed
        ;;
    firstlogin | secondlogin | restored-login | reinstalled-login)
        verify_marble_user_session marble
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
        verify_marble_packages
        verify_vendor_integrity
        if marble_gdm_enabled; then
            [ "$(/usr/lib/arch-linux-marble-gdm/update-compatibility --status)" = active ]
        fi
        emit_marble_action_pass pacman-syu-hooks-active-qkk-clean
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
        mapfile -t expected_profile < <(marble_project_packages)
        pacman -Rns --noconfirm "${expected_profile[@]}"
        [ -z "$(pacman -Qq | grep '^arch-linux-' || true)" ]
        [ ! -e /usr/share/arch-linux-marble ] && [ ! -e /usr/share/arch-linux-marble-gdm ]
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
        bootctl set-oneshot neighbor.conf
    else
        expected_root="$(partition_name "${target}" 2)"
        [ "${root_device}" = "${expected_root}" ]
        [ "$(cat /proc/sys/kernel/hostname)" = ali-neighbor ]
        [ "$(cat /neighbor-preserved.txt)" = "${run_id}" ]
        systemctl is-active --quiet systemd-networkd systemd-resolved qemu-guest-agent
        # The installer must preserve and boot this existing OS, not configure its DNS.
        # Network access is already checked in the newly installed target OS.
        [ -z "$(systemctl --failed --no-legend --plain)" ]
        bootctl is-installed
    fi
    boot_id="$(cat /proc/sys/kernel/random/boot_id)"
    printf 'MINIMAL_QEMU_GUEST_PASS run_id=%s scenario=%s phase=%s boot_id=%s target=%s neighbor=preserved\n' \
        "${run_id}" "${scenario}" "${phase}" "${boot_id}" "${target}"
}

if [ "${phase}" = neighbor-select ] || [ "${phase}" = neighbor ]; then
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
