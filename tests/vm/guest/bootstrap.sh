#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077

exec </dev/ttyS0 >/dev/ttyS0 2>&1
export TERM=xterm-256color
stty -F /dev/ttyS0 rows 40 cols 120 -onlcr -ocrnl

payload_mount="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly payload_mount
readonly work_root='/run/arch-linux-qemu'

marker_prefix=''

fail() {
    printf '%s_QEMU_FAIL: %s\n' "${marker_prefix:-UNKNOWN}" "$*" >&2
    systemctl poweroff --no-block >/dev/null 2>&1 || true
    exit 1
}

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

load_identity() {
    local file="$1" line key value
    local -A seen=()
    local -a allowed=(
        SCENARIO RUN_ID TARGET_SERIAL TARGET_VENDOR TARGET_MODEL HOSTNAME USERNAME MICROCODE
        SOURCE_COMMIT SOURCE_TREE INSTALLER_SHA256 HARNESS_SHA256 ISO_SHA256
        INPUT_MODE RELEASE_VERSION BOOTSTRAP_SHA256 SNAPSHOT_SHA256 BUILD_METADATA_SHA256
        UNSIGNED_MANIFEST_SHA256 PUBLIC_KEY_SHA256 PRIMARY_FINGERPRINT SIGNING_SUBKEY_FINGERPRINT
    )
    declare -gA IDENTITY=()
    while IFS= read -r line || [ -n "${line}" ]; do
        [[ "${line}" =~ ^([A-Z0-9_]+)=([A-Za-z0-9._:-]+)$ ]] || fail 'identity has malformed data'
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case " ${allowed[*]} " in
        *" ${key} "*) ;;
        *) fail "identity contains unknown key: ${key}" ;;
        esac
        [ -z "${seen[${key}]+x}" ] || fail "identity repeats key: ${key}"
        seen["${key}"]=1
        IDENTITY["${key}"]="${value}"
    done <"${file}"
    for key in "${allowed[@]}"; do
        [ -n "${seen[${key}]+x}" ] || fail "identity is missing key: ${key}"
    done
}

disk_identity() {
    local disk="$1" size wwn serial model material
    size="$(lsblk -bdno SIZE -- "${disk}" | trim_value)"
    wwn="$(lsblk -bdno WWN -- "${disk}" | trim_value)"
    serial="$(lsblk -bdno SERIAL -- "${disk}" | trim_value)"
    model="$(lsblk -bdno MODEL -- "${disk}" | trim_value)"
    [[ "${size}" =~ ^[1-9][0-9]*$ ]] || fail 'target size is malformed'
    printf -v material 'size=%s\nwwn=%s\nserial=%s\nmodel=%s\n' \
        "${size}" "${wwn}" "${serial}" "${model}"
    printf '%s' "${material}" | sha256sum --binary | awk '{ print $1 }'
}

partition_identity() {
    local partition="$1" parent="$2" partuuid start size material
    partuuid="$(lsblk -dnro PARTUUID -- "${partition}" | trim_value)"
    start="$(lsblk -bdnro START -- "${partition}" | trim_value)"
    size="$(lsblk -bdnro SIZE -- "${partition}" | trim_value)"
    [[ "${partuuid}" =~ ^[A-Fa-f0-9-]{8,}$ && "${start}" =~ ^[0-9]+$ && "${size}" =~ ^[1-9][0-9]*$ ]]
    printf -v material 'disk=%s\npartuuid=%s\nstart=%s\nsize=%s\n' \
        "$(disk_identity "${parent}")" "${partuuid,,}" "${start}" "${size}"
    printf '%s' "${material}" | sha256sum --binary | awk '{ print $1 }'
}

prepare_dual_boot_neighbor() {
    local target="$1" esp neighbor root_mount esp_uuid neighbor_uuid
    [ "${IDENTITY[SCENARIO]}" = minimal-dualboot-ext4-systemdboot ]
    [ "$(lsblk -dnro SERIAL -- "${target}" | trim_value)" = "${IDENTITY[TARGET_SERIAL]}" ]
    [ "$(lsblk -dnro VENDOR -- "${target}" | trim_value)" = SNAPLYZE ]
    [ -z "$(lsblk -nrpo MOUNTPOINTS -- "${target}" | tr -d '[:space:]')" ]
    [ "$(lsblk -nrpo TYPE -- "${target}" | awk '$1 == "part" { n++ } END { print n+0 }')" -eq 0 ]
    # This runs only inside the disposable guest, on its new serial-bound target.
    sgdisk -o -n 1:0:+1G -t 1:ef00 -n 2:0:+12G -t 2:8300 -n 3:0:0 -t 3:8300 -- "${target}"
    partprobe -- "${target}"
    udevadm settle
    esp="$(partition_name "${target}" 1)"
    neighbor="$(partition_name "${target}" 2)"
    mkfs.fat -F32 -- "${esp}"
    mkfs.ext4 -F -- "${neighbor}"
    root_mount="${work_root}/neighbor"
    install -d -m0700 -- "${root_mount}"
    mount -- "${neighbor}" "${root_mount}"
    install -d -- "${root_mount}/boot"
    mount -- "${esp}" "${root_mount}/boot"
    pacstrap -K "${root_mount}" base linux linux-firmware qemu-guest-agent
    printf 'ali-neighbor\n' >"${root_mount}/etc/hostname"
    printf 'LANG=C.UTF-8\n' >"${root_mount}/etc/locale.conf"
    install -d -- "${root_mount}/etc/systemd/network"
    printf '[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n' \
        >"${root_mount}/etc/systemd/network/20-wired.network"
    # networkd reads public configuration as systemd-network, not root.
    chmod 0644 -- "${root_mount}/etc/systemd/network/20-wired.network"
    ln -sf /run/systemd/resolve/stub-resolv.conf "${root_mount}/etc/resolv.conf"
    systemctl --root="${root_mount}" enable systemd-networkd systemd-resolved qemu-guest-agent
    systemd-machine-id-setup --root="${root_mount}"
    genfstab -U "${root_mount}" >"${root_mount}/etc/fstab"
    arch-chroot "${root_mount}" bootctl --esp-path=/boot install
    install -d -- "${root_mount}/boot/EFI/ali-neighbor" "${root_mount}/boot/loader/entries"
    cp -- "${root_mount}/boot/vmlinuz-linux" "${root_mount}/boot/EFI/ali-neighbor/vmlinuz-linux"
    cp -- "${root_mount}/boot/initramfs-linux.img" "${root_mount}/boot/EFI/ali-neighbor/initramfs-linux.img"
    esp_uuid="$(blkid -s UUID -o value "${esp}")"
    neighbor_uuid="$(blkid -s UUID -o value "${neighbor}")"
    printf 'title Existing Linux neighbor\nlinux /EFI/ali-neighbor/vmlinuz-linux\ninitrd /EFI/ali-neighbor/initramfs-linux.img\noptions root=UUID=%s rw\n' \
        "${neighbor_uuid}" >"${root_mount}/boot/loader/entries/neighbor.conf"
    printf '%s\n' "${IDENTITY[RUN_ID]}" >"${root_mount}/neighbor-preserved.txt"
    printf 'esp_uuid=%s\nneighbor_uuid=%s\n' "${esp_uuid}" "${neighbor_uuid}" \
        >"${work_root}/neighbor-identities.txt"
    (cd -- "${root_mount}"; sha256sum etc/hostname etc/fstab neighbor-preserved.txt \
        boot/EFI/ali-neighbor/vmlinuz-linux boot/EFI/ali-neighbor/initramfs-linux.img \
        boot/loader/entries/neighbor.conf) >"${work_root}/neighbor.sha256"
    umount -- "${root_mount}/boot"
    umount -- "${root_mount}"
    rmdir -- "${root_mount}"
}

check_dual_boot_neighbor() {
    local target="$1" root_mount="${work_root}/neighbor-check"
    [ "$(blkid -s UUID -o value "$(partition_name "${target}" 1)")" = \
        "$(sed -n 's/^esp_uuid=//p' "${work_root}/neighbor-identities.txt")" ]
    [ "$(blkid -s UUID -o value "$(partition_name "${target}" 2)")" = \
        "$(sed -n 's/^neighbor_uuid=//p' "${work_root}/neighbor-identities.txt")" ]
    install -d -m0700 -- "${root_mount}"
    mount -o ro,noload -- "$(partition_name "${target}" 2)" "${root_mount}"
    mount -o ro -- "$(partition_name "${target}" 1)" "${root_mount}/boot"
    (cd -- "${root_mount}"; sha256sum --check --strict "${work_root}/neighbor.sha256")
    umount -- "${root_mount}/boot"
    umount -- "${root_mount}"
    rmdir -- "${root_mount}"
    printf 'MINIMAL_QEMU_NEIGHBOR_PRESERVED run_id=%s\n' "${IDENTITY[RUN_ID]}"
}

write_config() {
    local config="$1" target="$2" target_identity="$3"
    local desktop_enabled='false' filesystem='ext4' graphics_driver='none'
    local encryption_enabled='false' bootsplash_enabled='false' bootloader='systemd'
    local gnome_theme='stock' gdm_theme='stock' second_keyboard_layout=''
    local root_number=2 dual_boot=false boot_identity='' root_identity=''
    if [ "${IDENTITY[SCENARIO]}" = minimal-dualboot-ext4-systemdboot ]; then
        root_number=3
        dual_boot=true
        boot_identity="$(partition_identity "$(partition_name "${target}" 1)" "${target}")"
        root_identity="$(partition_identity "$(partition_name "${target}" 3)" "${target}")"
    fi
    if [[ "${IDENTITY[SCENARIO]}" = stock-gnome-* ]] ||
        [[ "${IDENTITY[SCENARIO]}" = marble-gnome-* ]]; then
        desktop_enabled='true'
        graphics_driver='mesa'
        second_keyboard_layout='ru'
    fi
    if [[ "${IDENTITY[SCENARIO]}" = stock-gnome-btrfs-* ]] ||
        [[ "${IDENTITY[SCENARIO]}" = marble-gnome-btrfs-* ]]; then
        filesystem='btrfs'
    fi
    if [[ "${IDENTITY[SCENARIO]}" = stock-gnome-btrfs-luks2-plymouth-* ]] ||
        [[ "${IDENTITY[SCENARIO]}" = marble-gnome-btrfs-luks2-plymouth-* ]]; then
        encryption_enabled='true'
        bootsplash_enabled='true'
    fi
    if [[ "${IDENTITY[SCENARIO]}" = marble-gnome-* ]]; then
        gnome_theme='marble'
        gdm_theme='marble-experimental'
        [[ "${IDENTITY[SCENARIO]}" != *-stock-gdm ]] || gdm_theme='stock'
    fi
    [[ "${IDENTITY[SCENARIO]}" != *-grub ]] || bootloader='grub'
    {
        printf 'ARCH_LINUX_INSTALLER_CONFIG_VERSION=1\n'
        printf 'ARCH_LINUX_HOSTNAME=%s\n' "${IDENTITY[HOSTNAME]}"
        printf 'ARCH_LINUX_USERNAME=%s\n' "${IDENTITY[USERNAME]}"
        printf 'ARCH_LINUX_DISK=%s\n' "${target}"
        printf 'ARCH_LINUX_BOOT_PARTITION=%s\n' "$(partition_name "${target}" 1)"
        printf 'ARCH_LINUX_ROOT_PARTITION=%s\n' "$(partition_name "${target}" "${root_number}")"
        printf 'ARCH_LINUX_DISK_IDENTITY=%s\n' "${target_identity}"
        printf 'ARCH_LINUX_BOOT_PARTITION_IDENTITY=%s\n' "${boot_identity}"
        printf 'ARCH_LINUX_ROOT_PARTITION_IDENTITY=%s\n' "${root_identity}"
        printf 'ARCH_LINUX_FILESYSTEM=%s\n' "${filesystem}"
        printf 'ARCH_LINUX_BOOTLOADER=%s\n' "${bootloader}"
        printf 'ARCH_LINUX_DUAL_BOOT_ENABLED=%s\n' "${dual_boot}"
        printf 'ARCH_LINUX_BTRFS_SNAPPER_ENABLED=false\n'
        printf 'ARCH_LINUX_BTRFS_ASSISTANT_ENABLED=false\n'
        printf 'ARCH_LINUX_ENCRYPTION_ENABLED=%s\n' "${encryption_enabled}"
        printf 'ARCH_LINUX_TIMEZONE=UTC\n'
        printf 'ARCH_LINUX_LOCALE_LANG=en_US\n'
        printf 'ARCH_LINUX_LOCALE_GEN_LIST=en_US.UTF-8 UTF-8\n'
        printf 'ARCH_LINUX_REFLECTOR_COUNTRY=\n'
        printf 'ARCH_LINUX_VCONSOLE_KEYMAP=us\n'
        printf 'ARCH_LINUX_VCONSOLE_FONT=\n'
        printf 'ARCH_LINUX_KERNEL=linux\n'
        printf 'ARCH_LINUX_KERNEL_ARGS=\n'
        printf 'ARCH_LINUX_MICROCODE=%s\n' "${IDENTITY[MICROCODE]}"
        printf 'ARCH_LINUX_CORE_TWEAKS_ENABLED=false\n'
        printf 'ARCH_LINUX_MULTILIB_ENABLED=false\n'
        printf 'ARCH_LINUX_AUR_HELPER=none\n'
        printf 'ARCH_LINUX_BOOTSPLASH_ENABLED=%s\n' "${bootsplash_enabled}"
        printf 'ARCH_LINUX_HOUSEKEEPING_ENABLED=false\n'
        printf 'ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED=false\n'
        printf 'ARCH_LINUX_DESKTOP_ENABLED=%s\n' "${desktop_enabled}"
        printf 'ARCH_LINUX_GNOME_THEME_PROFILE=%s\n' "${gnome_theme}"
        printf 'ARCH_LINUX_GDM_THEME_PROFILE=%s\n' "${gdm_theme}"
        printf 'ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER=%s\n' "${graphics_driver}"
        printf 'ARCH_LINUX_DESKTOP_EXTRAS_ENABLED=false\n'
        printf 'ARCH_LINUX_DESKTOP_SLIM_ENABLED=false\n'
        printf 'ARCH_LINUX_DESKTOP_KEYBOARD_MODEL=pc105\n'
        printf 'ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT=us\n'
        printf 'ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=\n'
        printf 'ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=%s\n' "${second_keyboard_layout}"
        printf 'ARCH_LINUX_SAMBA_SHARE_ENABLED=false\n'
        printf 'ARCH_LINUX_VM_SUPPORT_ENABLED=true\n'
        printf 'ARCH_LINUX_ECN_ENABLED=true\n'
    } >"${config}"
    chmod 0600 -- "${config}"
    [ "$(wc -l <"${config}")" -eq 43 ] || fail 'generated config does not contain 43 keys'
}

main() {
    local block_path device serial vendor model type target target_identity installer_status log_tail_pid
    local expected_names actual_names forbidden expected_public_contract bootstrap_output accepted_installer_sha
    local public_bootstrap public_installer public_key
    local -a candidates=()

    [ "$(id -u)" -eq 0 ] || fail 'bootstrap must run as root'
    for command_name in awk bash cat curl find findmnt install lsblk mountpoint rm sed sha256sum stat stty systemctl tail update-ca-trust; do
        command -v -- "${command_name}" >/dev/null 2>&1 || fail "guest command is missing: ${command_name}"
    done
    [ -c /dev/ttyS0 ] && [ -c /dev/ttyS1 ] || fail 'required serial devices are unavailable'
    [ -d /sys/firmware/efi ] || fail 'official Arch ISO did not boot with UEFI'
    mountpoint -q -- "${payload_mount}" || fail 'payload is not mounted'
    case ",$(findmnt -nro OPTIONS --target "${payload_mount}")," in
    *,ro,*) ;;
    *) fail 'payload is not read-only' ;;
    esac
    if [ -f "${payload_mount}/public.contract" ]; then
        expected_names="$(printf '%s\n' IDENTITY MANIFEST.sha256 b public.contract | LC_ALL=C sort)"
    elif [ -f "${payload_mount}/repository.contract" ] || [ -f "${payload_mount}/acceptance-ca.crt" ]; then
        [ -f "${payload_mount}/repository.contract" ] && [ -f "${payload_mount}/acceptance-ca.crt" ] ||
            fail 'Marble repository payload is incomplete'
        expected_names="$(printf '%s\n' IDENTITY MANIFEST.sha256 acceptance-ca.crt \
            arch-linux-installer.sh b repository.contract | LC_ALL=C sort)"
    else
        expected_names="$(printf '%s\n' IDENTITY MANIFEST.sha256 arch-linux-installer.sh b | LC_ALL=C sort)"
    fi
    actual_names="$(find "${payload_mount}" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
    [ "${actual_names}" = "${expected_names}" ] || fail 'payload closure is unexpected'
    [ -z "$(find "${payload_mount}" -mindepth 1 ! -type f -print -quit)" ] || fail 'payload has a special entry'
    (cd -- "${payload_mount}"; sha256sum --check --strict MANIFEST.sha256) >/dev/null || fail 'payload digest closure failed'

    load_identity "${payload_mount}/IDENTITY"
    case "${IDENTITY[INPUT_MODE]}" in
    staged)
        [ ! -e "${payload_mount}/public.contract" ] && [ ! -L "${payload_mount}/public.contract" ] ||
            fail 'staged payload contains a public-mode contract'
        [ -f "${payload_mount}/arch-linux-installer.sh" ] || fail 'staged payload lacks the installer'
        ;;
    public)
        [ "${IDENTITY[SCENARIO]}" = marble-gnome-btrfs-luks2-plymouth-systemdboot ] ||
            fail 'public acceptance is limited to Marble with experimental GDM'
        [ -f "${payload_mount}/public.contract" ] && [ ! -L "${payload_mount}/public.contract" ] ||
            fail 'public payload lacks its immutable URL contract'
        for forbidden in arch-linux-installer.sh arch-linux.gpg acceptance-ca.crt repository.contract; do
            [ ! -e "${payload_mount}/${forbidden}" ] && [ ! -L "${payload_mount}/${forbidden}" ] ||
                fail "public payload contains local product material: ${forbidden}"
        done
        ;;
    *) fail 'input mode is invalid' ;;
    esac
    [ "${IDENTITY[RELEASE_VERSION]}" = 1.0.0 ] || fail 'release version differs'
    case "${IDENTITY[SCENARIO]}" in
    minimal-ext4-systemdboot)
        marker_prefix='MINIMAL'
        [[ "${IDENTITY[RUN_ID]}" =~ ^minimal-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100M[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_MIN_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    minimal-dualboot-ext4-systemdboot)
        marker_prefix='MINIMAL'
        [[ "${IDENTITY[RUN_ID]}" =~ ^dualboot-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100M[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_MIN_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    stock-gnome-ext4-systemdboot)
        marker_prefix='STOCK'
        [[ "${IDENTITY[RUN_ID]}" =~ ^stock-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100S[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_STK_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    stock-gnome-btrfs-systemdboot)
        marker_prefix='BTRFS'
        [[ "${IDENTITY[RUN_ID]}" =~ ^btrfs-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100B[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_BTR_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    stock-gnome-btrfs-grub)
        marker_prefix='GRUB'
        [[ "${IDENTITY[RUN_ID]}" =~ ^grub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100G[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    stock-gnome-btrfs-luks2-plymouth-systemdboot)
        marker_prefix='LUKS'
        [[ "${IDENTITY[RUN_ID]}" =~ ^luks-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100L[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_LUK_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    stock-gnome-btrfs-luks2-plymouth-grub)
        marker_prefix='LUKSGRUB'
        [[ "${IDENTITY[RUN_ID]}" =~ ^luksgrub-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100G[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_GRB_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        ;;
    marble-gnome-btrfs-luks2-plymouth-systemdboot)
        marker_prefix='MARBLE'
        [[ "${IDENTITY[RUN_ID]}" =~ ^marble-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100A[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_MAR_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        if [ "${IDENTITY[INPUT_MODE]}" = staged ]; then
            [ -f "${payload_mount}/repository.contract" ] && [ -f "${payload_mount}/acceptance-ca.crt" ] ||
                fail 'staged Marble scenario lacks its repository contract'
        fi
        ;;
    marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm)
        marker_prefix='MARBLE'
        [[ "${IDENTITY[RUN_ID]}" =~ ^marblestock-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || fail 'run identity is invalid'
        [[ "${IDENTITY[TARGET_SERIAL]}" =~ ^ALI100A[A-F0-9]{12}$ ]] || fail 'target serial is invalid'
        [[ "${IDENTITY[TARGET_MODEL]}" =~ ^ALI_MAR_[A-F0-9]{8}$ ]] || fail 'target model is invalid'
        if [ "${IDENTITY[INPUT_MODE]}" = staged ]; then
            [ -f "${payload_mount}/repository.contract" ] && [ -f "${payload_mount}/acceptance-ca.crt" ] ||
                fail 'staged Marble scenario lacks its repository contract'
        fi
        ;;
    *) fail 'scenario identity is invalid' ;;
    esac
    [ "${IDENTITY[TARGET_VENDOR]}" = SNAPLYZE ] || fail 'target vendor is invalid'
    for key in SOURCE_COMMIT SOURCE_TREE; do
        [[ "${IDENTITY[${key}]}" =~ ^[a-f0-9]{40}$ ]] || fail "${key} is malformed"
    done
    for key in INSTALLER_SHA256 HARNESS_SHA256 ISO_SHA256; do
        [[ "${IDENTITY[${key}]}" =~ ^[a-f0-9]{64}$ ]] || fail "${key} is malformed"
    done
    for key in BOOTSTRAP_SHA256 SNAPSHOT_SHA256 BUILD_METADATA_SHA256 \
        UNSIGNED_MANIFEST_SHA256 PUBLIC_KEY_SHA256; do
        [[ "${IDENTITY[${key}]}" =~ ^[a-f0-9]{64}$ ]] || fail "${key} is malformed"
    done
    for key in PRIMARY_FINGERPRINT SIGNING_SUBKEY_FINGERPRINT; do
        [[ "${IDENTITY[${key}]}" =~ ^[A-F0-9]{40}$ ]] || fail "${key} is malformed"
    done
    [ "${IDENTITY[PRIMARY_FINGERPRINT]}" != "${IDENTITY[SIGNING_SUBKEY_FINGERPRINT]}" ] ||
        fail 'repository fingerprints collide'
    if [ "${IDENTITY[INPUT_MODE]}" = staged ]; then
        [ "$(sha256sum --binary -- "${payload_mount}/arch-linux-installer.sh" | awk '{ print $1 }')" = \
            "${IDENTITY[INSTALLER_SHA256]}" ] || fail 'installer payload digest changed'
    fi
    if [ "${IDENTITY[INPUT_MODE]}" = public ]; then
        expected_public_contract="$(printf '%s\n' \
            'schema=1' \
            'bootstrap_url=https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.0/install.sh' \
            'installer_url=https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux-installer.sh' \
            'public_key_url=https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg' \
            "pages_url=https://snaplyze.github.io/arch-linux/repo/\$arch")"
        [ "$(cat -- "${payload_mount}/public.contract")" = "${expected_public_contract}" ] ||
            fail 'public URL contract differs from release 1.0.0'
    fi

    for block_path in /sys/class/block/*; do
        device="/dev/${block_path##*/}"
        [ -b "${device}" ] || continue
        type="$(lsblk -dnro TYPE -- "${device}" | trim_value)"
        [ "${type}" = disk ] || continue
        serial="$(lsblk -dnro SERIAL -- "${device}" | trim_value)"
        vendor="$(lsblk -dnro VENDOR -- "${device}" | trim_value)"
        model="$(lsblk -dnro MODEL -- "${device}" | trim_value)"
        if [ "${serial}" = "${IDENTITY[TARGET_SERIAL]}" ] &&
            [ "${vendor}" = "${IDENTITY[TARGET_VENDOR]}" ] &&
            [ "${model}" = "${IDENTITY[TARGET_MODEL]}" ]; then
            candidates+=("${device}")
        fi
    done
    [ "${#candidates[@]}" -eq 1 ] || fail 'target identity did not resolve exactly once'
    target="${candidates[0]}"
    [ -z "$(lsblk -nro FSTYPE -- "${target}" | tr -d '[:space:]')" ] || fail 'fresh target has a filesystem'
    [ "$(lsblk -nrpo TYPE -- "${target}" | awk '$1 == "part" { n++ } END { print n + 0 }')" -eq 0 ] ||
        fail 'fresh target has partitions'
    target_identity="$(disk_identity "${target}")"

    [ ! -e "${work_root}" ] && [ ! -L "${work_root}" ] || fail 'private installer work root already exists'
    install -d -m 0700 -- "${work_root}"
    if [ "${IDENTITY[SCENARIO]}" = minimal-dualboot-ext4-systemdboot ]; then
        prepare_dual_boot_neighbor "${target}"
    fi
    if [ "${IDENTITY[INPUT_MODE]}" = public ]; then
        public_bootstrap="${work_root}/public-install.sh"
        public_installer="${work_root}/public-arch-linux-installer.sh"
        public_key="${work_root}/public-arch-linux.gpg"
        curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 10 --max-time 120 --max-filesize 1048576 \
            --output "${public_bootstrap}" -- \
            'https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.0/install.sh'
        [ -f "${public_bootstrap}" ] && [ ! -L "${public_bootstrap}" ] ||
            fail 'public bootstrap download is unsafe'
        [ "$(sha256sum --binary -- "${public_bootstrap}" | awk '{ print $1 }')" = \
            "${IDENTITY[BOOTSTRAP_SHA256]}" ] || fail 'public bootstrap differs from the frozen source'
        chmod 0700 -- "${public_bootstrap}"
        bootstrap_output="$(/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
            /usr/bin/bash --noprofile --norc "${public_bootstrap}" --verify-only)" ||
            fail 'public bootstrap verification failed'
        [[ "${bootstrap_output}" =~ ^Verified\ Arch\ Linux\ Installer\ 1\.0\.0:\ sha256\ ([a-f0-9]{64})$ ]] ||
            fail 'public bootstrap verification output is malformed'
        accepted_installer_sha="${BASH_REMATCH[1]}"
        [ "${accepted_installer_sha}" = "${IDENTITY[INSTALLER_SHA256]}" ] ||
            fail 'public bootstrap accepted a different installer than the frozen source'
        curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 10 --max-time 120 --max-filesize 1048576 \
            --output "${public_installer}" -- \
            'https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux-installer.sh'
        [ "$(sha256sum --binary -- "${public_installer}" | awk '{ print $1 }')" = \
            "${accepted_installer_sha}" ] || fail 'public Release installer differs from bootstrap verification'
        curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 10 --max-time 120 --max-filesize 1048576 \
            --output "${public_key}" -- \
            'https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg'
        [ "$(sha256sum --binary -- "${public_key}" | awk '{ print $1 }')" = \
            "${IDENTITY[PUBLIC_KEY_SHA256]}" ] || fail 'public Release key differs from frozen trust'
        install -o 0 -g 0 -m 0700 -- "${public_installer}" "${work_root}/arch-linux-installer.sh"
        rm -f -- "${public_bootstrap}" "${public_installer}" "${public_key}"
        printf 'MARBLE_PUBLIC_BOOTSTRAP_PASS run_id=%s installer_sha256=%s snapshot_sha256=%s\n' \
            "${IDENTITY[RUN_ID]}" "${accepted_installer_sha}" "${IDENTITY[SNAPSHOT_SHA256]}"
    else
        install -o 0 -g 0 -m 0700 -- "${payload_mount}/arch-linux-installer.sh" \
            "${work_root}/arch-linux-installer.sh"
    fi
    if [ "${IDENTITY[INPUT_MODE]}" = staged ] && \
        [[ "${IDENTITY[SCENARIO]}" = marble-gnome-* ]]; then
        install -o 0 -g 0 -m 0400 -- "${payload_mount}/repository.contract" \
            "${work_root}/repository.contract"
        install -o 0 -g 0 -m 0400 -- "${payload_mount}/acceptance-ca.crt" \
            "${work_root}/acceptance-ca.crt"
        install -o 0 -g 0 -m 0644 -- "${work_root}/acceptance-ca.crt" \
            /etc/ca-certificates/trust-source/anchors/arch-linux-qemu-acceptance.crt
        update-ca-trust
    fi
    write_config "${work_root}/installer.conf" "${target}" "${target_identity}"
    printf '%s_QEMU_READY run_id=%s scenario=%s input_mode=%s source_commit=%s source_tree=%s installer_sha256=%s harness_sha256=%s iso_sha256=%s snapshot_sha256=%s\n' \
        "${marker_prefix}" \
        "${IDENTITY[RUN_ID]}" "${IDENTITY[SCENARIO]}" "${IDENTITY[INPUT_MODE]}" \
        "${IDENTITY[SOURCE_COMMIT]}" \
        "${IDENTITY[SOURCE_TREE]}" "${IDENTITY[INSTALLER_SHA256]}" \
        "${IDENTITY[HARNESS_SHA256]}" "${IDENTITY[ISO_SHA256]}" "${IDENTITY[SNAPSHOT_SHA256]}"
    cd -- "${work_root}"
    (
        while [ ! -f installer.log ]; do sleep 0.1; done
        printf '%s_QEMU_INSTALL_LOG_BEGIN run_id=%s scenario=%s\n' "${marker_prefix}" \
            "${IDENTITY[RUN_ID]}" "${IDENTITY[SCENARIO]}"
        tail -n +1 -F -- installer.log
    ) >/dev/ttyS1 2>&1 &
    log_tail_pid=$!
    set +e
    (
        # Match the official Arch ISO root shell. The bootstrap's own files remain under umask 077.
        umask 022
        if [ "${IDENTITY[INPUT_MODE]}" = staged ] && \
            [[ "${IDENTITY[SCENARIO]}" = marble-gnome-* ]]; then
            ARCH_LINUX_QEMU_ACCEPTANCE=true \
                ARCH_LINUX_QEMU_REPOSITORY_CONTRACT="${work_root}/repository.contract" \
                FORCE=true DEBUG=false bash ./arch-linux-installer.sh
        else
            FORCE=true DEBUG=false bash ./arch-linux-installer.sh
        fi
    )
    installer_status=$?
    set -e
    kill -TERM -- "${log_tail_pid}" 2>/dev/null || true
    wait "${log_tail_pid}" 2>/dev/null || true
    printf '%s_QEMU_INSTALL_LOG_FINAL_BEGIN run_id=%s scenario=%s\n' "${marker_prefix}" \
        "${IDENTITY[RUN_ID]}" "${IDENTITY[SCENARIO]}" >/dev/ttyS1
    cat -- installer.log >/dev/ttyS1
    printf '%s_QEMU_INSTALL_LOG_FINAL_END run_id=%s scenario=%s\n' "${marker_prefix}" \
        "${IDENTITY[RUN_ID]}" "${IDENTITY[SCENARIO]}" >/dev/ttyS1
    printf '%s_QEMU_INSTALLER_EXIT status=%s\n' "${marker_prefix}" "${installer_status}"
    sync
    [ "${installer_status}" -eq 0 ] || fail "installer exited with status ${installer_status}"
    if [ "${IDENTITY[SCENARIO]}" = minimal-dualboot-ext4-systemdboot ]; then
        check_dual_boot_neighbor "${target}"
    fi
    printf '%s_QEMU_INSTALL_COMPLETE run_id=%s scenario=%s powering_off=yes\n' "${marker_prefix}" \
        "${IDENTITY[RUN_ID]}" "${IDENTITY[SCENARIO]}"
    systemctl poweroff
}

main "$@"
