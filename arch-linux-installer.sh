#!/usr/bin/env bash
# shellcheck disable=SC1090

#########################################################
# ARCH LINUX INSTALLER | Automated Arch Linux Installer TUI
#########################################################

# SOURCE:   https://github.com/snaplyze/arch-linux
# AUTHOR:   snaplyze
# LICENSE:  GPL-3.0-only

# CONFIG
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# ENVIRONMENT
: "${DEBUG:=false}"            # DEBUG=true ./installer.sh
: "${FORCE:=false}"            # FORCE=true ./installer.sh
: "${GUM:=/usr/local/bin/gum}" # GUM=/usr/bin/gum ./installer.sh

# SCRIPT
readonly VERSION='1.0.0'
export ARCH_LINUX_INSTALLER_CONFIG_VERSION='1'

# PROJECT REPOSITORY (used by update_installer and release-pinned downloads)
readonly UPDATE_REPO_API='https://api.github.com/repos/snaplyze/arch-linux'
readonly UPDATE_REPO_RAW='https://raw.githubusercontent.com/snaplyze/arch-linux'

# Requested GNOME additions. No Screenshot Box has no Arch/AUR package or tagged GitHub release,
# so its reviewed GNOME Extensions v6 bundle is pinned by both version tag and SHA-256. Every AUR
# input, including Bibata, is pinned below to a reviewed commit and exact source-tree digest.
NO_SCREENSHOT_BOX_UUID='no-screenshot-box@screenshot'
NO_SCREENSHOT_BOX_VERSION_TAG='72860'
NO_SCREENSHOT_BOX_ARCHIVE_SHA256='6b1c5184579ca03dc9bf0ad6ded39d99e618c8baf4577ff5391cfa185eb0736e'
NO_SCREENSHOT_BOX_ARCHIVE_URL="https://extensions.gnome.org/download-extension/${NO_SCREENSHOT_BOX_UUID}.shell-extension.zip?version_tag=${NO_SCREENSHOT_BOX_VERSION_TAG}"
BIBATA_CURSOR_AUR_PACKAGE='bibata-cursor-theme-bin'
BIBATA_CURSOR_THEME='Bibata-Modern-Classic'
MARBLE_PROFILE_PACKAGE='arch-linux-marble-profile'
MARBLE_GDM_PACKAGE='arch-linux-marble-gdm'
MARBLE_SHELL_THEME='ArchLinux-Marble-Blue-Filled-Dark'
MARBLE_GTK_THEME='Colloid-Dark'
MARBLE_ICON_THEME='Colloid-Dark'

# Initial repository trust v1. The immutable release certificate is pinned by SHA-256 and exact
# fingerprints. It contains one certification-only primary and one finite signing-only subkey.
readonly REPOSITORY_TRUST_VERSION='1'
readonly REPOSITORY_NAME='arch-linux'
readonly REPOSITORY_SERVER_URL="https://snaplyze.github.io/arch-linux/repo/\$arch"
readonly REPOSITORY_PUBLIC_KEY_URL="https://github.com/snaplyze/arch-linux/releases/download/${VERSION}/arch-linux.gpg"
readonly REPOSITORY_PUBLIC_KEY_SHA256='2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67'
readonly REPOSITORY_PRIMARY_FINGERPRINT='8C78098D1EAC609CBC73536FB7D2C17447B90CB2'
readonly REPOSITORY_SIGNING_SUBKEY_FINGERPRINT='0AA6F2237FB9674623B6E824428D56A84F558F7C'
readonly REPOSITORY_PUBLICATION_READY='true'
# Experimental GDM remains independently gated from the Stock and Marble desktop profiles.
readonly MARBLE_GDM_PUBLICATION_READY='true'

# A real-QEMU milestone may exercise the exact installer against a disposable signed repository
# before the canonical release endpoints exist. Production trust above remains immutable; this
# state can be populated only from a root-owned contract inside the QEMU live environment.
QEMU_ACCEPTANCE_REPOSITORY_ACTIVE='false'
QEMU_ACCEPTANCE_REPOSITORY_SERVER_URL=''
QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_URL=''
QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_SHA256=''
QEMU_ACCEPTANCE_REPOSITORY_PRIMARY_FINGERPRINT=''
QEMU_ACCEPTANCE_REPOSITORY_SIGNING_SUBKEY_FINGERPRINT=''
QEMU_ACCEPTANCE_REPOSITORY_CA_FILE=''
QEMU_ACCEPTANCE_REPOSITORY_CA_SHA256=''

# GUM
readonly GUM_VERSION='0.17.0'
readonly GUM_ARCHIVE_SHA256='69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb'

# FILES
SCRIPT_CONFIG=''
SCRIPT_LOG=''

# INIT
INIT_FILENAME="initialize"

# Runtime paths remain empty while this file is sourced for function tests. The executed installer
# initializes them only after its working directory has passed the root-state trust gate.
SCRIPT_RUNTIME_CWD=''
SCRIPT_RUNTIME_CWD_IDENTITY=''
SCRIPT_SOURCE_PATH=''
SCRIPT_SOURCE_IDENTITY=''
SCRIPT_MAIN_PID=''
SCRIPT_TMP_DIR=''
ERROR_MSG_TMP_FILE=''
PROCESS_LOG_TMP_FILE=''
PROCESS_RET_TMP_FILE=''
SCRIPT_CONFIG_TMP_FILE=''
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT=''
TARGET_MOUNT_MARKER="${SCRIPT_TMP_DIR}/target-mounted"
CRYPTROOT_MARKER="${SCRIPT_TMP_DIR}/cryptroot-opened"
PROCESS_CGROUP_ACK_TMP_FILE="${SCRIPT_TMP_DIR}/process-cgroup.ready"
PROCESS_CGROUP_DIR=''
PROCESS_CGROUP_RELATIVE=''
PROCESS_ACTIVE_PID=''
PROCESS_ACTIVE_PGID=''
PROCESS_SEQUENCE=0

# COLORS
COLOR_BLACK=0   #  #000000
COLOR_RED=9     #  #ff0000
COLOR_GREEN=10  #  #00ff00
COLOR_YELLOW=11 #  #ffff00
COLOR_BLUE=12   #  #0000ff
COLOR_PURPLE=13 #  #ff00ff
COLOR_CYAN=14   #  #00ffff
COLOR_WHITE=15  #  #ffffff

COLOR_FOREGROUND="${COLOR_BLUE}"
COLOR_BACKGROUND="${COLOR_WHITE}"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

runtime_path_ancestors_are_safe() {
    local candidate="$1" current owner mode

    [[ "$candidate" = /* ]] || return 1
    current="$candidate"
    while :; do
        [ -d "$current" ] && [ ! -L "$current" ] || return 1
        read -r owner mode < <(stat -Lc '%u %a' -- "$current") || return 1
        [ "$owner" = 0 ] || return 1
        (( (8#$mode & 0022) == 0 )) || return 1
        [ "$current" = / ] && break
        current="${current%/*}"
        [ -n "$current" ] || current=/
    done
}

runtime_working_directory_is_safe() {
    local candidate owner mode links candidate_identity dot_identity
    candidate="$(pwd -P)" || return 1
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || return 1
    read -r owner mode links candidate_identity < <(stat -Lc '%u %a %h %d:%i' -- "$candidate") ||
        return 1
    dot_identity="$(stat -Lc '%d:%i' -- .)" || return 1
    [ "$owner" = 0 ] && [ "$mode" = 700 ] && [ "$links" -ge 2 ] || return 1
    [ "$candidate_identity" = "$dot_identity" ] || return 1
    runtime_path_ancestors_are_safe "$candidate" || return 1
    [ "$(pwd -P)" = "$candidate" ] || return 1
    printf '%s\n' "$candidate"
}

runtime_source_file_is_safe() {
    local source_path="$1" runtime_cwd="$2"
    local canonical_source owner mode links identity canonical_after

    canonical_source="$(readlink -f -- "$source_path")" || return 1
    [ "$canonical_source" = "${runtime_cwd}/arch-linux-installer.sh" ] || return 1
    [ -f "$canonical_source" ] && [ ! -L "$canonical_source" ] || return 1
    read -r owner mode links identity < <(stat -Lc '%u %a %h %d:%i' -- "$canonical_source") ||
        return 1
    [ "$owner" = 0 ] && [ "$mode" = 700 ] && [ "$links" = 1 ] || return 1
    canonical_after="$(readlink -f -- "$source_path")" || return 1
    [ "$canonical_after" = "$canonical_source" ] || return 1
    [ "$(stat -Lc '%d:%i' -- "$canonical_after")" = "$identity" ] || return 1
    printf '%s %s\n' "$canonical_source" "$identity"
}

runtime_source_identity_is_stable() {
    local source_info

    [ -n "$SCRIPT_RUNTIME_CWD" ] && [ -n "$SCRIPT_RUNTIME_CWD_IDENTITY" ] &&
        [ -n "$SCRIPT_SOURCE_PATH" ] && [ -n "$SCRIPT_SOURCE_IDENTITY" ] || return 1
    [ "$(pwd -P)" = "$SCRIPT_RUNTIME_CWD" ] || return 1
    [ "$(stat -Lc '%d:%i' -- .)" = "$SCRIPT_RUNTIME_CWD_IDENTITY" ] || return 1
    runtime_path_ancestors_are_safe "$SCRIPT_RUNTIME_CWD" || return 1
    source_info="$(runtime_source_file_is_safe "$SCRIPT_SOURCE_PATH" "$SCRIPT_RUNTIME_CWD")" ||
        return 1
    [ "$source_info" = "$SCRIPT_SOURCE_PATH $SCRIPT_SOURCE_IDENTITY" ]
}

runtime_directory_metadata_is_safe() {
    local candidate="$1" expected_owner="$2" owner mode links
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || return 1
    read -r owner mode links < <(stat -c '%u %a %h' -- "$candidate") || return 1
    [ "$owner" = "$expected_owner" ] && [ "$mode" = 700 ] && [ "$links" -ge 2 ]
}

runtime_init() {
    local runtime_owner runtime_parent runtime_template source_info

    is_choice "$DEBUG" true false || { echo 'DEBUG must be true or false' >&2; return 1; }
    is_choice "$FORCE" true false || { echo 'FORCE must be true or false' >&2; return 1; }
    runtime_owner="$(id -u)"
    SCRIPT_MAIN_PID="$BASHPID"

    if [ "$DEBUG" = false ]; then
        [ "$runtime_owner" -eq 0 ] || {
            echo 'Error: Arch Linux Installer must be run as root' >&2
            return 1
        }
        SCRIPT_RUNTIME_CWD="$(runtime_working_directory_is_safe)" || {
            echo 'Refusing root state outside a private root-owned directory with trusted ancestors' >&2
            return 1
        }
        SCRIPT_RUNTIME_CWD_IDENTITY="$(stat -Lc '%d:%i' -- .)" || return 1
        source_info="$(runtime_source_file_is_safe "${BASH_SOURCE[0]}" "$SCRIPT_RUNTIME_CWD")" || {
            echo 'Refusing an installer source outside the private root-owned runtime directory' >&2
            return 1
        }
        read -r SCRIPT_SOURCE_PATH SCRIPT_SOURCE_IDENTITY <<<"$source_info"
        runtime_source_identity_is_stable || {
            echo 'Refusing an unstable installer source or runtime directory identity' >&2
            return 1
        }
        runtime_parent='/run'
        if ! { [ -d "$runtime_parent" ] && [ ! -L "$runtime_parent" ] &&
            [ "$(stat -c '%u' -- "$runtime_parent")" = 0 ] &&
            (( (8#$(stat -c '%a' -- "$runtime_parent") & 0022) == 0 )); }; then
            echo 'Refusing unsafe runtime directory /run' >&2
            return 1
        fi
        runtime_template='/run/arch-linux-installer.XXXXXXXXXX'
    else
        SCRIPT_RUNTIME_CWD="$(pwd -P)" || return 1
        SCRIPT_RUNTIME_CWD_IDENTITY="$(stat -Lc '%d:%i' -- .)" || return 1
        SCRIPT_SOURCE_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")" || return 1
        SCRIPT_SOURCE_IDENTITY="$(stat -Lc '%d:%i' -- "$SCRIPT_SOURCE_PATH")" || return 1
        runtime_template='/tmp/arch-linux-installer-debug.XXXXXXXXXX'
    fi

    SCRIPT_CONFIG="${SCRIPT_RUNTIME_CWD}/installer.conf"
    SCRIPT_LOG="${SCRIPT_RUNTIME_CWD}/installer.log"
    SCRIPT_TMP_DIR="$(umask 077 && mktemp -d -- "$runtime_template")" || return 1
    if ! runtime_directory_metadata_is_safe "$SCRIPT_TMP_DIR" "$runtime_owner"; then
        case "$SCRIPT_TMP_DIR" in
        /run/arch-linux-installer.* | /tmp/arch-linux-installer-debug.*)
            find "$SCRIPT_TMP_DIR" -xdev -depth -delete 2>/dev/null || true
            ;;
        esac
        SCRIPT_TMP_DIR=''
        echo 'Refusing runtime directory with unexpected metadata' >&2
        return 1
    fi

    ERROR_MSG_TMP_FILE="${SCRIPT_TMP_DIR}/installer.err"
    PROCESS_LOG_TMP_FILE="${SCRIPT_TMP_DIR}/process.log"
    PROCESS_RET_TMP_FILE="${SCRIPT_TMP_DIR}/process.ret"
    SCRIPT_CONFIG_TMP_FILE="${SCRIPT_TMP_DIR}/installer.conf.new"
    TARGET_MOUNT_MARKER="${SCRIPT_TMP_DIR}/target-mounted"
    CRYPTROOT_MARKER="${SCRIPT_TMP_DIR}/cryptroot-opened"
    PROCESS_CGROUP_ACK_TMP_FILE="${SCRIPT_TMP_DIR}/process-cgroup.ready"

    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME[*]-unknown} ${LINENO}' ERR
}

main() {

    # Show short debug warning
    if [ "$DEBUG" = "true" ]; then
        clear && echo "!!! DEBUG MODE IS ENABLED !!!" && sleep 1
    fi

    # Clear logfile
    [ -f "$SCRIPT_LOG" ] && mv -f -- "$SCRIPT_LOG" "${SCRIPT_LOG}.old"

    # Check gum binary or download
    gum_init

    # Print version to logfile
    log_info "Arch Linux ${VERSION}"

    # Offer self update and restart with new version if a newer release is available
    update_installer

    # Apply a disposable repository only after the production updater has completed. The exact
    # production trust constants are never replaced and the contract is Marble-only.
    qemu_acceptance_repository_contract_apply

    # ---------------------------------------------------------------------------------------------------

    # Loop properties step to update screen if user edit properties
    while (true); do

        print_header "Arch Linux Installer" # Show landing page
        gum_white 'Please make sure you have:' && echo
        gum_white '• Backed up your important data'
        gum_white '• A stable internet connection'
        gum_white '• Secure Boot disabled'
        gum_white '• Boot Mode set to UEFI'

        # Ask for load & remove existing config file
        if [ "$FORCE" = "false" ] && [ -f "$SCRIPT_CONFIG" ] && ! gum_confirm "Load existing installer.conf?"; then
            gum_confirm "Remove existing installer.conf?" || trap_gum_exit # If not want remove config > exit script
            echo && gum_title "Properties File"
            mv -f -- "$SCRIPT_CONFIG" "${SCRIPT_CONFIG}.old" && gum_info "installer.conf was moved to installer.conf.old"
            gum_warn "Please restart Arch Linux Installer..."
            echo && exit 0
        fi

        echo # Print new line

        # Load installer.conf as data if it exists, or select a preset.
        until properties_preset_source; do :; done

        # Selectors
        echo && gum_title "Core Setup"
        until select_username; do :; done
        until select_hostname; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_filesystem; do :; done
        until select_bootloader; do :; done
        until select_disk; do :; done
        until select_enable_encryption; do :; done
        echo && gum_title "Desktop Setup"
        until select_enable_desktop_environment; do :; done
        until select_gnome_theme_profile; do :; done
        until select_gdm_theme_profile; do :; done
        until select_enable_desktop_driver; do :; done
        until select_enable_desktop_slim; do :; done
        until select_enable_desktop_keyboard; do :; done
        echo && gum_title "Feature Setup"
        until select_enable_core_tweaks; do :; done
        until select_enable_bootsplash; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_enable_housekeeping; do :; done
        until select_enable_shell_enhancement; do :; done

        # Optional System Tuning: every property below already has a working default from the
        # preset or auto-detection, so skipping keeps the install flow exactly as short as before.
        if [ "$FORCE" = "false" ] && gum_confirm --default=false --negative="Skip" "Configure advanced options? (kernel, mirrors, dual boot, ...)"; then
            echo && gum_title "System Tuning"
            until select_kernel; do :; done
            until select_reflector_country; do :; done
            until select_enable_dual_boot; do :; done
            until select_dual_boot_partitions; do :; done
            until select_enable_desktop_extras; do :; done
            until select_enable_btrfs_snapper; do :; done
            until select_enable_btrfs_assistant; do :; done
            until select_enable_samba_share; do :; done
            until select_enable_vm_support; do :; done
            until select_desktop_keyboard_second; do :; done
        fi

        # Finish & show Advanced Properties
        echo && gum_title "Properties"

        # Open Advanced Properties?
        if [ "$FORCE" = "false" ] && gum_confirm --default=false --negative="Skip" "Open Advanced Setup Editor?"; then
            if properties_edit_config; then
                gum_confirm "Change Password?" && until select_password --change && properties_load; do :; done
            fi
            echo && ! gum_spin --title="Reload Properties in 3 seconds..." -- sleep 3 && trap_gum_exit
            continue # Restart properties step to refresh properties screen
        fi

        # Hard safety gates right at the init of the installation, before touching any disk and
        # before the Summary/confirm below - by the time the user confirms, the install is already
        # known to work. On failure, validate_properties offers to fix it in the Advanced Setup
        # Editor; afterwards it restarts this whole properties step from the top so the corrected
        # values are shown again before the Summary.
        validate_properties_or_fix || continue

        # Print success
        gum_info "Successfully validated"

        ######################################################
        break # Exit properties step and continue installation
        ######################################################
    done

    # ---------------------------------------------------------------------------------------------------

    # Start installation in 5 seconds?
    if [ "$FORCE" = "false" ]; then
        echo && gum_title "Summary" && print_summary
        gum_confirm "Start Arch Linux Installation?" || trap_gum_exit
    fi

    echo && gum_title "Arch Linux Installation"
    local spin_title="Arch Linux Installation starts in 5 seconds. Press CTRL + C to cancel..."
    ! gum_spin --title="$spin_title" -- sleep 5 && trap_gum_exit # CTRL + C pressed

    SECONDS=0 # Measure execution time of installation

    # Executors
    exec_init_installation
    exec_prepare_disk
    exec_pacstrap_core
    exec_enable_multilib
    exec_install_aur_helper
    exec_install_bootsplash
    exec_install_housekeeping
    exec_install_shell_enhancement
    exec_install_graphics_driver
    exec_install_desktop
    exec_install_vm_support
    exec_finalize_arch_linux

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Print duration time info
    local finish_txt="Installation successful in ${duration_min} minutes and ${duration_sec} seconds"
    echo && gum_green --bold "$finish_txt"
    log_info "$finish_txt"

    # Copy installer files to users home
    if [ "$DEBUG" = "false" ]; then
        chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/installer.conf" 0600 <"$SCRIPT_CONFIG"
        chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/installer.log" 0600 <"$SCRIPT_LOG"
    fi

    wait # Wait for sub processes

    # ---------------------------------------------------------------------------------------------------

    # Show reboot & unmount prompt
    local do_reboot do_unmount do_chroot

    # Default values
    do_reboot="false"
    do_chroot="false"
    do_unmount="false"

    # Force values
    if [ "$FORCE" = "true" ]; then
        do_reboot="false"
        do_chroot="false"
        do_unmount="true"
    fi

    # Reboot prompt
    [ "$FORCE" = "false" ] && gum_confirm "Reboot to Arch Linux now?" && do_reboot="true" && do_unmount="true"

    # Unmount
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "false" ] && gum_confirm "Unmount Arch Linux from /mnt?" && do_unmount="true"
    [ "$do_unmount" = "true" ] && echo && gum_warn "Unmounting Arch Linux from /mnt..."
    if [ "$DEBUG" = "false" ] && [ "$do_unmount" = "true" ]; then
        installer_cleanup_created_storage
    fi

    # Do reboot
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "true" ] && gum_warn "Rebooting to Arch Linux..." && [ "$DEBUG" = "false" ] && reboot

    # Chroot
    [ "$FORCE" = "false" ] && [ "$do_unmount" = "false" ] && gum_confirm "Chroot to new Arch Linux?" && do_chroot="true"
    if [ "$do_chroot" = "true" ] && echo && gum_warn "Chrooting Arch Linux at /mnt..."; then
        gum_warn "!! YOU ARE NOW ON YOUR NEW ARCH LINUX SYSTEM !!"
        gum_warn ">> Leave with command 'exit'"
        if [ "$DEBUG" = "false" ]; then
            arch-chroot /mnt </dev/tty || true
        fi
        wait # Wait for subprocesses
        gum_warn "Please reboot manually..."
    fi

    # Print warning
    [ "$do_unmount" = "false" ] && [ "$do_chroot" = "false" ] && echo && gum_warn "Arch Linux is still mounted at /mnt"

    gum_info "Exit" && exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

readonly -a PERSISTED_CONFIG_KEYS=(
    ARCH_LINUX_INSTALLER_CONFIG_VERSION
    ARCH_LINUX_HOSTNAME
    ARCH_LINUX_USERNAME
    ARCH_LINUX_DISK
    ARCH_LINUX_BOOT_PARTITION
    ARCH_LINUX_ROOT_PARTITION
    ARCH_LINUX_DISK_IDENTITY
    ARCH_LINUX_BOOT_PARTITION_IDENTITY
    ARCH_LINUX_ROOT_PARTITION_IDENTITY
    ARCH_LINUX_FILESYSTEM
    ARCH_LINUX_BOOTLOADER
    ARCH_LINUX_DUAL_BOOT_ENABLED
    ARCH_LINUX_BTRFS_SNAPPER_ENABLED
    ARCH_LINUX_BTRFS_ASSISTANT_ENABLED
    ARCH_LINUX_ENCRYPTION_ENABLED
    ARCH_LINUX_TIMEZONE
    ARCH_LINUX_LOCALE_LANG
    ARCH_LINUX_LOCALE_GEN_LIST
    ARCH_LINUX_REFLECTOR_COUNTRY
    ARCH_LINUX_VCONSOLE_KEYMAP
    ARCH_LINUX_VCONSOLE_FONT
    ARCH_LINUX_KERNEL
    ARCH_LINUX_KERNEL_ARGS
    ARCH_LINUX_MICROCODE
    ARCH_LINUX_CORE_TWEAKS_ENABLED
    ARCH_LINUX_MULTILIB_ENABLED
    ARCH_LINUX_AUR_HELPER
    ARCH_LINUX_BOOTSPLASH_ENABLED
    ARCH_LINUX_HOUSEKEEPING_ENABLED
    ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED
    ARCH_LINUX_DESKTOP_ENABLED
    ARCH_LINUX_GNOME_THEME_PROFILE
    ARCH_LINUX_GDM_THEME_PROFILE
    ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER
    ARCH_LINUX_DESKTOP_EXTRAS_ENABLED
    ARCH_LINUX_DESKTOP_SLIM_ENABLED
    ARCH_LINUX_DESKTOP_KEYBOARD_MODEL
    ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT
    ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT
    ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND
    ARCH_LINUX_SAMBA_SHARE_ENABLED
    ARCH_LINUX_VM_SUPPORT_ENABLED
    ARCH_LINUX_ECN_ENABLED
)

properties_config_fail() {
    gum_fail "Invalid installer.conf: $*"
    return 1
}

# Bash variables cannot contain NUL bytes, and read(1) silently discards them. Inspect the file as
# bytes before any record is loaded so an unsafe byte can never normalize into an allowlisted value.
# Schema 1 deliberately needs only LF plus printable ASCII; od emits decimal byte values only and
# the predicate never writes file content to a log or shell variable.
properties_open_file_bytes_are_safe() {
    local open_fd="$1"
    [[ "$open_fd" =~ ^[0-9]+$ ]] || return 1
    LC_ALL=C /usr/bin/od -An -v -tu1 -- "/proc/self/fd/${open_fd}" 2>/dev/null | LC_ALL=C /usr/bin/awk '
        {
            for (field = 1; field <= NF; field++) {
                byte = $field + 0
                if (byte != 10 && (byte < 32 || byte > 126)) exit 1
            }
        }
    '
}

# No-op lifecycle hooks make descriptor/path mutation regressions deterministic without changing
# production semantics. Tests may replace them only after loading the helper range.
properties_config_snapshot_captured() { :; }
properties_config_snapshot_record_parsed() { :; }
properties_config_snapshot_parsed() { :; }

properties_file_bytes_are_safe() {
    local candidate="$1" open_fd result=1
    exec {open_fd}<"$candidate" || return 1
    properties_open_file_bytes_are_safe "$open_fd" && result=0
    exec {open_fd}<&-
    return "$result"
}

locale_entry_is_valid() {
    local entry="$1"
    [[ "$entry" =~ ^([A-Za-z]{2,3}_[A-Za-z0-9]+([.@][A-Za-z0-9_-]+)*|C(\.[A-Za-z0-9-]+)?)\ [A-Za-z0-9-]+$ ]]
}

# Validate the lexical type of one persisted value. Empty is permitted for fields whose selector
# has not run yet; validate_properties enforces the completed install-time contract separately.
properties_value_is_valid() {
    local key="$1" value="$2" entry

    [[ "$value" != *$'\r'* && "$value" != *$'\n'* && "$value" != *$'\t'* ]] || return 1
    case "$key" in
    ARCH_LINUX_INSTALLER_CONFIG_VERSION)
        [ "$value" = '1' ]
        ;;
    ARCH_LINUX_HOSTNAME)
        [ -z "$value" ] || { [ "${#value}" -le 63 ] && [[ "$value" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; }
        ;;
    ARCH_LINUX_USERNAME)
        [ -z "$value" ] || { [ "${#value}" -le 32 ] && [[ "$value" =~ ^[a-z][a-z0-9_-]*$ ]]; }
        ;;
    ARCH_LINUX_DISK | ARCH_LINUX_BOOT_PARTITION | ARCH_LINUX_ROOT_PARTITION)
        [ -z "$value" ] || [[ "$value" =~ ^/dev/[A-Za-z0-9._/-]+$ ]]
        ;;
    ARCH_LINUX_DISK_IDENTITY | ARCH_LINUX_BOOT_PARTITION_IDENTITY | ARCH_LINUX_ROOT_PARTITION_IDENTITY)
        [ -z "$value" ] || [[ "$value" =~ ^[a-f0-9]{64}$ ]]
        ;;
    ARCH_LINUX_FILESYSTEM)
        is_choice "$value" '' btrfs ext4
        ;;
    ARCH_LINUX_BOOTLOADER)
        is_choice "$value" '' grub systemd
        ;;
    ARCH_LINUX_DUAL_BOOT_ENABLED | ARCH_LINUX_BTRFS_SNAPPER_ENABLED | ARCH_LINUX_BTRFS_ASSISTANT_ENABLED | \
        ARCH_LINUX_ENCRYPTION_ENABLED | ARCH_LINUX_CORE_TWEAKS_ENABLED | ARCH_LINUX_MULTILIB_ENABLED | \
        ARCH_LINUX_BOOTSPLASH_ENABLED | ARCH_LINUX_HOUSEKEEPING_ENABLED | ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED | \
        ARCH_LINUX_DESKTOP_ENABLED | ARCH_LINUX_DESKTOP_EXTRAS_ENABLED | ARCH_LINUX_DESKTOP_SLIM_ENABLED | \
        ARCH_LINUX_SAMBA_SHARE_ENABLED | ARCH_LINUX_VM_SUPPORT_ENABLED | \
        ARCH_LINUX_ECN_ENABLED)
        is_choice "$value" '' true false
        ;;
    ARCH_LINUX_TIMEZONE)
        [ -z "$value" ] || timezone_identifier_is_safe "$value"
        ;;
    ARCH_LINUX_LOCALE_LANG)
        [ -z "$value" ] || [[ "$value" =~ ^[A-Za-z0-9_@-]+$ ]]
        ;;
    ARCH_LINUX_LOCALE_GEN_LIST)
        [ -z "$value" ] && return 0
        [[ "$value" != \;* && "$value" != *\; && "$value" != *\;\;* ]] || return 1
        local -a locale_entries=()
        IFS=';' read -r -a locale_entries <<<"$value"
        for entry in "${locale_entries[@]}"; do
            locale_entry_is_valid "$entry" || return 1
        done
        ;;
    ARCH_LINUX_REFLECTOR_COUNTRY)
        [[ "$value" =~ ^[A-Za-z,\ -]*$ ]]
        ;;
    ARCH_LINUX_VCONSOLE_KEYMAP | ARCH_LINUX_VCONSOLE_FONT)
        [ -z "$value" ] || [[ "$value" =~ ^[A-Za-z0-9._+-]+$ ]]
        ;;
    ARCH_LINUX_KERNEL)
        [ -z "$value" ] || [[ "$value" =~ ^[a-z0-9][a-z0-9._+-]*$ ]]
        ;;
    ARCH_LINUX_KERNEL_ARGS)
        local kernel_args_re='^[]A-Za-z0-9 ._=,:+/@%[-]*$'
        [[ "$value" =~ $kernel_args_re ]]
        ;;
    ARCH_LINUX_MICROCODE)
        is_choice "$value" '' intel-ucode amd-ucode none
        ;;
    ARCH_LINUX_AUR_HELPER)
        is_choice "$value" '' paru paru-bin paru-git yay trizen pikaur none
        ;;
    ARCH_LINUX_GNOME_THEME_PROFILE)
        is_choice "$value" '' stock marble
        ;;
    ARCH_LINUX_GDM_THEME_PROFILE)
        is_choice "$value" '' stock marble-experimental
        ;;
    ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER)
        is_choice "$value" '' mesa intel_i915 nvidia amd ati none
        ;;
    ARCH_LINUX_DESKTOP_KEYBOARD_MODEL | ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT | ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT)
        [ -z "$value" ] || [[ "$value" =~ ^[A-Za-z0-9._+-]+$ ]]
        ;;
    ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND)
        [ -z "$value" ] || [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]
        ;;
    *)
        return 1
        ;;
    esac
}

# installer.conf is a strict data file: exactly one KEY=VALUE record for each allowlisted key.
# No line is evaluated as shell, and parsed values are committed only after the whole file passes.
properties_load() {
    local config_path="${1:-$SCRIPT_CONFIG}"
    [ -f "$config_path" ] || { properties_config_fail "${config_path} is not a regular file"; return 1; }
    [ ! -L "$config_path" ] || { properties_config_fail "${config_path} is a symlink"; return 1; }

    local config_fd='' snapshot_write_fd='' snapshot_fd='' snapshot_path=''
    local config_owner config_mode config_size config_links
    local config_metadata path_metadata metadata_after snapshot_size
    local -A allowed=() seen=() parsed=()
    local key line value expected line_number=0 load_error=''

    exec {config_fd}<"$config_path" || {
        properties_config_fail "cannot open ${config_path}"
        return 1
    }
    if ! config_metadata="$(
        /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- \
            "/proc/self/fd/${config_fd}" 2>/dev/null
    )" || ! read -r config_owner config_mode config_size config_links < <(
        /usr/bin/stat -Lc '%u %a %s %h' -- "/proc/self/fd/${config_fd}" 2>/dev/null
    ); then
        load_error="cannot inspect open ${config_path}"
    elif [ "$config_owner" != "$(/usr/bin/id -u)" ]; then
        load_error="${config_path} is not owned by the current user"
    elif (( (8#$config_mode & 0022) != 0 )); then
        load_error="${config_path} is group- or world-writable"
    elif [ "$config_links" -ne 1 ]; then
        load_error="${config_path} must have exactly one hard link"
    elif [ "$config_size" -gt 65536 ]; then
        load_error="${config_path} exceeds 65536 bytes"
    elif [ -L "$config_path" ] || ! path_metadata="$(
        /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- "$config_path" 2>/dev/null
    )" || [ "$path_metadata" != "$config_metadata" ]; then
        load_error="${config_path} changed while it was opened"
    fi

    if [ -z "$load_error" ]; then
        snapshot_path="$(umask 077 && /usr/bin/mktemp --tmpdir arch-linux-installer-config.XXXXXXXX)" ||
            load_error="cannot create a private installer.conf snapshot"
    fi
    if [ -z "$load_error" ]; then
        if ! exec {snapshot_write_fd}<>"$snapshot_path"; then
            load_error="cannot open the private installer.conf snapshot"
        elif ! /usr/bin/rm -- "$snapshot_path"; then
            load_error="cannot unlink the private installer.conf snapshot"
        else
            snapshot_path=''
        fi
    fi
    if [ -z "$load_error" ] && ! /usr/bin/dd \
        if="/proc/self/fd/${config_fd}" of="/proc/self/fd/${snapshot_write_fd}" \
        bs=65537 count=1 iflag=fullblock conv=fsync status=none; then
        load_error="cannot capture installer.conf into a private snapshot"
    fi
    if [ -z "$load_error" ]; then
        snapshot_size="$(/usr/bin/stat -Lc '%s' -- "/proc/self/fd/${snapshot_write_fd}" 2>/dev/null)" ||
            load_error="cannot inspect the private installer.conf snapshot"
    fi
    if [ -z "$load_error" ] && [ "$snapshot_size" != "$config_size" ]; then
        load_error="${config_path} changed while its snapshot was captured"
    fi
    if [ -z "$load_error" ]; then
        if ! exec {snapshot_fd}<"/proc/self/fd/${snapshot_write_fd}"; then
            load_error="cannot seal the private installer.conf snapshot for reading"
        fi
    fi
    if [ -n "$snapshot_write_fd" ]; then
        exec {snapshot_write_fd}>&-
        snapshot_write_fd=''
    fi
    if [ -n "$snapshot_path" ]; then
        /usr/bin/rm -f -- "$snapshot_path"
        snapshot_path=''
    fi
    if [ -z "$load_error" ]; then
        if ! metadata_after="$(
            /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- \
                "/proc/self/fd/${config_fd}" 2>/dev/null
        )" || [ "$metadata_after" != "$config_metadata" ] || [ -L "$config_path" ] ||
            ! path_metadata="$(
                /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- \
                    "$config_path" 2>/dev/null
            )" || [ "$path_metadata" != "$config_metadata" ]; then
            load_error="${config_path} changed while its snapshot was captured"
        elif ! properties_open_file_bytes_are_safe "$snapshot_fd"; then
            load_error="${config_path} contains a control or non-ASCII byte"
        elif ! properties_config_snapshot_captured "$config_path"; then
            load_error="installer.conf snapshot capture hook failed"
        fi
    fi

    for key in "${PERSISTED_CONFIG_KEYS[@]}"; do
        allowed["$key"]='true'
    done

    if [ -z "$load_error" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line_number=$((line_number + 1))
            if ! [[ "$line" =~ ^(ARCH_LINUX_[A-Z0-9_]+)=(.*)$ ]]; then
                load_error="line ${line_number} is not a KEY=VALUE record"
                break
            fi
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            if [ -z "${allowed[$key]+set}" ]; then
                load_error="unknown key ${key} on line ${line_number}"
                break
            fi
            if [ -n "${seen[$key]+set}" ]; then
                load_error="duplicate key ${key} on line ${line_number}"
                break
            fi
            if ! properties_value_is_valid "$key" "$value"; then
                load_error="invalid value for ${key} on line ${line_number}"
                break
            fi
            seen["$key"]='true'
            parsed["$key"]="$value"
            if ! properties_config_snapshot_record_parsed "$config_path" "$line_number"; then
                load_error="installer.conf snapshot record hook failed"
                break
            fi
        done <"/proc/self/fd/${snapshot_fd}"
    fi

    if [ -z "$load_error" ]; then
        for expected in "${PERSISTED_CONFIG_KEYS[@]}"; do
            if [ -z "${seen[$expected]+set}" ]; then
                load_error="missing key ${expected}"
                break
            fi
        done
    fi
    if [ -z "$load_error" ] && ! properties_config_snapshot_parsed "$config_path"; then
        load_error="installer.conf snapshot parse hook failed"
    fi
    if [ -z "$load_error" ]; then
        if ! metadata_after="$(
            /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- \
                "/proc/self/fd/${config_fd}" 2>/dev/null
        )" || [ "$metadata_after" != "$config_metadata" ] || [ -L "$config_path" ] ||
            ! path_metadata="$(
                /usr/bin/stat -Lc '%d:%i:%f:%u:%g:%s:%h:%Y:%Z:%y:%z' -- \
                    "$config_path" 2>/dev/null
            )" || [ "$path_metadata" != "$config_metadata" ]; then
            load_error="${config_path} changed while its snapshot was parsed"
        fi
    fi
    if [ -n "$snapshot_fd" ]; then
        exec {snapshot_fd}<&-
    fi
    if [ -n "$config_fd" ]; then
        exec {config_fd}<&-
    fi
    if [ -n "$load_error" ]; then
        properties_config_fail "$load_error"
        return 1
    fi

    local -a parsed_locales=()
    if [ -n "${parsed[ARCH_LINUX_LOCALE_GEN_LIST]}" ]; then
        IFS=';' read -r -a parsed_locales <<<"${parsed[ARCH_LINUX_LOCALE_GEN_LIST]}"
    fi
    for key in "${PERSISTED_CONFIG_KEYS[@]}"; do
        [ "$key" = 'ARCH_LINUX_LOCALE_GEN_LIST' ] && continue
        printf -v "$key" '%s' "${parsed[$key]}"
        export "${key?}"
    done
    ARCH_LINUX_LOCALE_GEN_LIST=("${parsed_locales[@]}")
    return 0
}

properties_runtime_value() {
    local key="$1" destination_name="$2"
    if [ "$key" = 'ARCH_LINUX_LOCALE_GEN_LIST' ]; then
        local declaration='' locale_value=''
        declaration="$(declare -p ARCH_LINUX_LOCALE_GEN_LIST 2>/dev/null)" || true
        if [ -z "$declaration" ]; then
            printf -v "$destination_name" '%s' ''
            return 0
        fi
        [[ "$declaration" == 'declare -a'* ]] || return 1
        local IFS=';'
        printf -v locale_value '%s' "${ARCH_LINUX_LOCALE_GEN_LIST[*]}"
        printf -v "$destination_name" '%s' "$locale_value"
        return 0
    fi
    printf -v "$destination_name" '%s' "${!key-}"
}

properties_generate() {
    [ ! -L "$SCRIPT_CONFIG" ] || { properties_config_fail "refusing to replace symlink ${SCRIPT_CONFIG}"; return 1; }

    local -A values=()
    local key value
    for key in "${PERSISTED_CONFIG_KEYS[@]}"; do
        value=''
        properties_runtime_value "$key" value || {
            properties_config_fail "runtime value for ${key} has the wrong type"
            return 1
        }
        properties_value_is_valid "$key" "$value" || {
            properties_config_fail "runtime value for ${key} is invalid"
            return 1
        }
        values["$key"]="$value"
    done

    local config_tmp
    config_tmp="$(umask 077 && mktemp -- "${SCRIPT_CONFIG}.tmp.XXXXXX")" || {
        properties_config_fail "cannot create an atomic temporary file next to ${SCRIPT_CONFIG}"
        return 1
    }
    if ! {
        for key in "${PERSISTED_CONFIG_KEYS[@]}"; do
            printf '%s=%s\n' "$key" "${values[$key]}"
        done
    } >"$config_tmp"; then
        rm -f -- "$config_tmp"
        properties_config_fail "cannot write ${SCRIPT_CONFIG}"
        return 1
    fi
    if ! mv -fT -- "$config_tmp" "$SCRIPT_CONFIG"; then
        rm -f -- "$config_tmp"
        properties_config_fail "cannot replace ${SCRIPT_CONFIG} atomically"
        return 1
    fi
    return 0
}

properties_preset_source() {

    # Default presets
    # NOTE: do NOT pre-seed values that have a selector in the main flow. Selectors only prompt
    # while the value is still empty. The hostname suggestion therefore belongs in select_hostname
    # as a pre-filled input value rather than in this preset.
    [ -z "$ARCH_LINUX_KERNEL" ] && ARCH_LINUX_KERNEL="linux-zen"
    [ -z "$ARCH_LINUX_BTRFS_SNAPPER_ENABLED" ] && ARCH_LINUX_BTRFS_SNAPPER_ENABLED='true'
    [ -z "$ARCH_LINUX_BTRFS_ASSISTANT_ENABLED" ] && ARCH_LINUX_BTRFS_ASSISTANT_ENABLED='true'
    [ -z "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" ] && ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
    [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_MODEL" ] && ARCH_LINUX_DESKTOP_KEYBOARD_MODEL="pc105"
    # Off by default: the public share is guest-writable, which is an unsafe default for a laptop
    # on untrusted networks. Opt in via System Tuning or installer.conf.
    [ -z "$ARCH_LINUX_SAMBA_SHARE_ENABLED" ] && ARCH_LINUX_SAMBA_SHARE_ENABLED="false"
    [ -z "$ARCH_LINUX_ECN_ENABLED" ] && ARCH_LINUX_ECN_ENABLED="true"
    [ -z "$ARCH_LINUX_VM_SUPPORT_ENABLED" ] && ARCH_LINUX_VM_SUPPORT_ENABLED="true"
    [ -z "$ARCH_LINUX_DUAL_BOOT_ENABLED" ] && ARCH_LINUX_DUAL_BOOT_ENABLED="false"

    # Set microcode
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="intel-ucode"
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="amd-ucode"

    # Load properties or select preset
    if [ -f "$SCRIPT_CONFIG" ]; then
        if ! properties_load; then
            [ "$FORCE" = "true" ] && exit 130
            gum_confirm --affirmative="Edit" --negative="Exit" "Open invalid installer.conf in the Advanced Setup Editor?" || exit 130
            properties_edit_config || return 1
            return 1
        fi
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded from: ")" "$(gum_white --bold "installer.conf")"
    else
        # Select preset
        local preset options
        options=("desktop - GNOME Desktop Environment (default)" "core    - Minimal Arch Linux TTY Environment" "none    - No pre-selection")
        preset=$(gum_choose --header "+ Choose Setup Preset" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$preset" ] && return 1 # Check if new value is null
        preset="$(echo "$preset" | awk '{print $1}')"

        # Core preset
        if [[ $preset == core* ]]; then
            ARCH_LINUX_BTRFS_SNAPPER_ENABLED='false'
            ARCH_LINUX_BTRFS_ASSISTANT_ENABLED='false'
            ARCH_LINUX_DESKTOP_ENABLED='false'
            ARCH_LINUX_GNOME_THEME_PROFILE='stock'
            ARCH_LINUX_GDM_THEME_PROFILE='stock'
            ARCH_LINUX_MULTILIB_ENABLED='false'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='false'
            ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='false'
            ARCH_LINUX_BOOTSPLASH_ENABLED='false'
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="none"
            ARCH_LINUX_AUR_HELPER='none'
        fi

        # Desktop preset
        if [[ $preset == desktop* ]]; then
            ARCH_LINUX_BTRFS_SNAPPER_ENABLED='true'
            ARCH_LINUX_BTRFS_ASSISTANT_ENABLED='true'
            ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
            ARCH_LINUX_SAMBA_SHARE_ENABLED='false' # Guest-writable share stays opt-in, see properties_preset_source
            ARCH_LINUX_CORE_TWEAKS_ENABLED="true"
            ARCH_LINUX_BOOTSPLASH_ENABLED='true'
            ARCH_LINUX_DESKTOP_ENABLED='true'
            ARCH_LINUX_MULTILIB_ENABLED='true'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='true'
            ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='true'
            ARCH_LINUX_AUR_HELPER='paru'
        fi

        # Write properties
        properties_generate
        properties_load
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded for: ")" "$(gum_white --bold "$preset")"
    fi
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# VALIDATION & HELPERS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

is_boolean() {
    [ "$1" = "true" ] || [ "$1" = "false" ]
}

is_choice() {
    local value="$1" choice
    shift
    for choice in "$@"; do
        [ "$value" = "$choice" ] && return 0
    done
    return 1
}

downloaded_file_is_within_size() {
    local candidate="$1" maximum_bytes="$2" size
    [ -f "$candidate" ] && [ ! -L "$candidate" ] || return 1
    [[ "$maximum_bytes" =~ ^[0-9]+$ ]] && [ "$maximum_bytes" -gt 0 ] || return 1
    size="$(stat -c '%s' -- "$candidate")" || return 1
    [ "$size" -gt 0 ] && [ "$size" -le "$maximum_bytes" ]
}

repository_configuration_is_valid() {
    local name="$1" server_url="$2" public_key_url="$3" public_key_sha256="$4"
    local primary_fingerprint="$5" signing_fingerprint="$6"

    [ "$name" = 'arch-linux' ] || return 1
    # pacman expands this literal architecture token at request time.
    # shellcheck disable=SC2016
    [ "$server_url" = 'https://snaplyze.github.io/arch-linux/repo/$arch' ] || return 1
    [ "$public_key_url" = "https://github.com/snaplyze/arch-linux/releases/download/${VERSION}/arch-linux.gpg" ] || return 1
    [[ "$public_key_sha256" =~ ^[a-f0-9]{64}$ ]] || return 1
    [[ "$primary_fingerprint" =~ ^[A-F0-9]{40}$ ]] || return 1
    [[ "$signing_fingerprint" =~ ^[A-F0-9]{40}$ ]] || return 1
    [ "$primary_fingerprint" != "$signing_fingerprint" ]
}

repository_configuration_ready() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        repository_qemu_acceptance_configuration_is_valid \
            "$QEMU_ACCEPTANCE_REPOSITORY_SERVER_URL" \
            "$QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_URL" \
            "$QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_SHA256" \
            "$QEMU_ACCEPTANCE_REPOSITORY_PRIMARY_FINGERPRINT" \
            "$QEMU_ACCEPTANCE_REPOSITORY_SIGNING_SUBKEY_FINGERPRINT" \
            "$QEMU_ACCEPTANCE_REPOSITORY_CA_FILE" \
            "$QEMU_ACCEPTANCE_REPOSITORY_CA_SHA256"
        return
    fi
    [ "$REPOSITORY_PUBLICATION_READY" = 'true' ] || return 1
    [ "$REPOSITORY_TRUST_VERSION" = '1' ] || return 1
    repository_configuration_is_valid \
        "$REPOSITORY_NAME" \
        "$REPOSITORY_SERVER_URL" \
        "$REPOSITORY_PUBLIC_KEY_URL" \
        "$REPOSITORY_PUBLIC_KEY_SHA256" \
        "$REPOSITORY_PRIMARY_FINGERPRINT" \
        "$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT"
}

repository_qemu_acceptance_configuration_is_valid() {
    local server_url="$1" public_key_url="$2" public_key_sha256="$3"
    local primary_fingerprint="$4" signing_fingerprint="$5" ca_file="$6" ca_sha256="$7"
    local server_port key_port

    # shellcheck disable=SC2016 # pacman expands the literal architecture token.
    [[ "$server_url" =~ ^https://10\.0\.2\.2:([1-9][0-9]{3,4})/repo/\$arch$ ]] || return 1
    server_port="${BASH_REMATCH[1]}"
    [[ "$public_key_url" =~ ^https://10\.0\.2\.2:([1-9][0-9]{3,4})/arch-linux\.gpg$ ]] || return 1
    key_port="${BASH_REMATCH[1]}"
    [ "$server_port" = "$key_port" ] && [ "$server_port" -le 65535 ] || return 1
    [[ "$public_key_sha256" =~ ^[a-f0-9]{64}$ ]] || return 1
    [[ "$primary_fingerprint" =~ ^[A-F0-9]{40}$ ]] || return 1
    [[ "$signing_fingerprint" =~ ^[A-F0-9]{40}$ ]] || return 1
    [ "$primary_fingerprint" != "$signing_fingerprint" ] || return 1
    case "$ca_file" in
    /run/arch-linux-qemu/*.crt) ;;
    *) return 1 ;;
    esac
    [ -f "$ca_file" ] && [ ! -L "$ca_file" ] || return 1
    [ "$(stat -Lc '%u:%a:%h' -- "$ca_file")" = '0:400:1' ] || return 1
    [[ "$ca_sha256" =~ ^[a-f0-9]{64}$ ]] || return 1
    [ "$(sha256sum --binary -- "$ca_file" | awk '{ print $1 }')" = "$ca_sha256" ]
}

qemu_acceptance_repository_contract_line_is_valid() {
    local line="$1"

    [[ "$line" =~ ^[a-z][a-z0-9_]*=[A-Za-z0-9./:\$-]+$ ]]
}

qemu_acceptance_repository_contract_apply() {
    local contract="${ARCH_LINUX_QEMU_REPOSITORY_CONTRACT:-}" line key value
    local owner_mode_links expected_keys actual_keys
    declare -A values=()
    declare -A seen=()
    local allowed='schema server_url public_key_url public_key_sha256 primary_fingerprint signing_subkey_fingerprint ca_file ca_sha256'

    [ -n "$contract" ] || return 0
    [ "${ARCH_LINUX_QEMU_ACCEPTANCE:-}" = 'true' ] || {
        log_fail 'QEMU repository contract requires explicit acceptance mode'
        return 1
    }
    case "$contract" in
    /run/arch-linux-qemu/*.contract) ;;
    *) log_fail 'QEMU repository contract path is outside the private live-environment root'; return 1 ;;
    esac
    [ -f "$contract" ] && [ ! -L "$contract" ] || {
        log_fail 'QEMU repository contract is not a regular file'
        return 1
    }
    owner_mode_links="$(stat -Lc '%u:%a:%h' -- "$contract")" || return 1
    [ "$owner_mode_links" = '0:400:1' ] || {
        log_fail 'QEMU repository contract metadata differs'
        return 1
    }
    runtime_path_ancestors_are_safe "${contract%/*}" || {
        log_fail 'QEMU repository contract has an unsafe ancestor'
        return 1
    }
    if [ ! -r /sys/class/dmi/id/product_name ] || \
        ! grep -Eq '^(QEMU|Standard PC)' /sys/class/dmi/id/product_name; then
        log_fail 'QEMU repository contract is unavailable outside QEMU'
        return 1
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        qemu_acceptance_repository_contract_line_is_valid "$line" || {
            log_fail 'QEMU repository contract contains malformed data'
            return 1
        }
        key="${line%%=*}"
        value="${line#*=}"
        case " ${allowed} " in
        *" ${key} "*) ;;
        *) log_fail "QEMU repository contract contains an unknown key: ${key}"; return 1 ;;
        esac
        [ -z "${seen[${key}]+x}" ] || {
            log_fail "QEMU repository contract repeats a key: ${key}"
            return 1
        }
        seen["$key"]=1
        values["$key"]="$value"
    done <"$contract"
    expected_keys="$(tr ' ' '\n' <<<"$allowed" | LC_ALL=C sort)"
    actual_keys="$(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort)"
    [ "$actual_keys" = "$expected_keys" ] && [ "${values[schema]}" = '1' ] || {
        log_fail 'QEMU repository contract closure differs'
        return 1
    }
    repository_qemu_acceptance_configuration_is_valid \
        "${values[server_url]}" "${values[public_key_url]}" \
        "${values[public_key_sha256]}" "${values[primary_fingerprint]}" \
        "${values[signing_subkey_fingerprint]}" "${values[ca_file]}" \
        "${values[ca_sha256]}" || {
        log_fail 'QEMU repository contract values failed validation'
        return 1
    }

    QEMU_ACCEPTANCE_REPOSITORY_ACTIVE='true'
    QEMU_ACCEPTANCE_REPOSITORY_SERVER_URL="${values[server_url]}"
    QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_URL="${values[public_key_url]}"
    QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_SHA256="${values[public_key_sha256]}"
    QEMU_ACCEPTANCE_REPOSITORY_PRIMARY_FINGERPRINT="${values[primary_fingerprint]}"
    QEMU_ACCEPTANCE_REPOSITORY_SIGNING_SUBKEY_FINGERPRINT="${values[signing_subkey_fingerprint]}"
    QEMU_ACCEPTANCE_REPOSITORY_CA_FILE="${values[ca_file]}"
    QEMU_ACCEPTANCE_REPOSITORY_CA_SHA256="${values[ca_sha256]}"
    unset ARCH_LINUX_QEMU_REPOSITORY_CONTRACT ARCH_LINUX_QEMU_ACCEPTANCE
}

repository_effective_server_url() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        printf '%s\n' "$QEMU_ACCEPTANCE_REPOSITORY_SERVER_URL"
    else
        printf '%s\n' "$REPOSITORY_SERVER_URL"
    fi
}

repository_effective_public_key_url() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        printf '%s\n' "$QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_URL"
    else
        printf '%s\n' "$REPOSITORY_PUBLIC_KEY_URL"
    fi
}

repository_effective_public_key_sha256() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        printf '%s\n' "$QEMU_ACCEPTANCE_REPOSITORY_PUBLIC_KEY_SHA256"
    else
        printf '%s\n' "$REPOSITORY_PUBLIC_KEY_SHA256"
    fi
}

repository_effective_primary_fingerprint() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        printf '%s\n' "$QEMU_ACCEPTANCE_REPOSITORY_PRIMARY_FINGERPRINT"
    else
        printf '%s\n' "$REPOSITORY_PRIMARY_FINGERPRINT"
    fi
}

repository_effective_signing_fingerprint() {
    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        printf '%s\n' "$QEMU_ACCEPTANCE_REPOSITORY_SIGNING_SUBKEY_FINGERPRINT"
    else
        printf '%s\n' "$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT"
    fi
}

repository_key_metadata_matches() {
    local metadata="$1" trust_state="$2" current_epoch="$3"
    local expected_primary="${4:-$REPOSITORY_PRIMARY_FINGERPRINT}"
    local expected_signing="${5:-$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT}"
    local primary_count subkey_count fingerprint_count secret_count
    local primary_fingerprint signing_fingerprint primary_algorithm subkey_algorithm
    local primary_capabilities subkey_capabilities primary_expiry subkey_expiry
    local primary_validity subkey_validity

    [ "$trust_state" = 'untrusted' ] || [ "$trust_state" = 'trusted' ] || return 1
    [[ "$current_epoch" =~ ^[0-9]+$ ]] || return 1

    primary_count="$(awk -F: '$1 == "pub" { count++ } END { print count + 0 }' <<<"$metadata")"
    subkey_count="$(awk -F: '$1 == "sub" { count++ } END { print count + 0 }' <<<"$metadata")"
    fingerprint_count="$(awk -F: '$1 == "fpr" { count++ } END { print count + 0 }' <<<"$metadata")"
    secret_count="$(awk -F: '$1 == "sec" || $1 == "ssb" { count++ } END { print count + 0 }' <<<"$metadata")"
    [ "$primary_count" -eq 1 ] && [ "$subkey_count" -eq 1 ] && \
        [ "$fingerprint_count" -eq 2 ] && [ "$secret_count" -eq 0 ] || return 1

    primary_fingerprint="$(awk -F: '$1 == "fpr" { print toupper($10); exit }' <<<"$metadata")"
    signing_fingerprint="$(awk -F: '$1 == "sub" { want = 1; next } want && $1 == "fpr" { print toupper($10); exit }' <<<"$metadata")"
    [ "$primary_fingerprint" = "$expected_primary" ] || return 1
    [ "$signing_fingerprint" = "$expected_signing" ] || return 1

    primary_algorithm="$(awk -F: '$1 == "pub" { print $4; exit }' <<<"$metadata")"
    subkey_algorithm="$(awk -F: '$1 == "sub" { print $4; exit }' <<<"$metadata")"
    primary_capabilities="$(awk -F: '$1 == "pub" { print $12; exit }' <<<"$metadata")"
    subkey_capabilities="$(awk -F: '$1 == "sub" { print $12; exit }' <<<"$metadata")"
    primary_expiry="$(awk -F: '$1 == "pub" { print $7; exit }' <<<"$metadata")"
    subkey_expiry="$(awk -F: '$1 == "sub" { print $7; exit }' <<<"$metadata")"
    primary_validity="$(awk -F: '$1 == "pub" { print $2; exit }' <<<"$metadata")"
    subkey_validity="$(awk -F: '$1 == "sub" { print $2; exit }' <<<"$metadata")"
    [ "$primary_algorithm" = '22' ] && [ "$subkey_algorithm" = '22' ] || return 1
    # GnuPG uses lowercase letters for this packet's capabilities and uppercase letters for
    # aggregate capabilities inherited from the complete keyblock. Require the exact packet-local
    # certification-only/signing-only split while allowing only those aggregate annotations.
    [[ "$primary_capabilities" =~ ^[cCS]+$ ]] || return 1
    [[ "$subkey_capabilities" =~ ^[sCS]+$ ]] || return 1
    [ "${primary_capabilities//[A-Z]/}" = 'c' ] || return 1
    [ "${subkey_capabilities//[A-Z]/}" = 's' ] || return 1
    case "$primary_validity" in r|e|d|i|n) return 1 ;; esac
    case "$subkey_validity" in r|e|d|i|n) return 1 ;; esac
    if [ "$trust_state" = 'trusted' ]; then
        [ "$primary_validity" = 'f' ] || [ "$primary_validity" = 'u' ] || return 1
        [ "$subkey_validity" = 'f' ] || [ "$subkey_validity" = 'u' ] || return 1
    fi
    { [ -z "$primary_expiry" ] || [ "$primary_expiry" = '0' ]; } || return 1
    [[ "$subkey_expiry" =~ ^[0-9]+$ ]] && [ "$subkey_expiry" -gt "$current_epoch" ]
}

repository_public_key_matches() {
    local public_key="$1" inspection_home="$2"
    local expected_sha="${3:-$REPOSITORY_PUBLIC_KEY_SHA256}"
    local expected_primary="${4:-$REPOSITORY_PRIMARY_FINGERPRINT}"
    local expected_signing="${5:-$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT}"
    local metadata

    [ -f "$public_key" ] && [ ! -L "$public_key" ] || return 1
    [ "$(sha256sum "$public_key" | awk '{ print $1 }')" = "$expected_sha" ] || return 1
    mkdir -p -- "$inspection_home" || return 1
    chmod 0700 "$inspection_home" || return 1
    metadata="$(
        gpg --batch --homedir "$inspection_home" --with-colons --with-subkey-fingerprint \
            --show-keys -- "$public_key" 2>/dev/null
    )" || return 1
    repository_key_metadata_matches \
        "$metadata" 'untrusted' "$(date +%s)" "$expected_primary" "$expected_signing"
}

marble_gdm_configuration_is_valid() {
    local publication_ready="$1" package="$2"
    [ "$publication_ready" = 'true' ] || return 1
    [[ "$package" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]]
}

marble_gdm_configuration_ready() {
    # Keep GDM independently reversible from the repository and desktop-Marble profile.
    marble_gdm_configuration_is_valid "$MARBLE_GDM_PUBLICATION_READY" "$MARBLE_GDM_PACKAGE"
}

aur_helper_command() {
    case "$1" in
    paru | paru-bin | paru-git) printf 'paru' ;;
    yay | trizen | pikaur) printf '%s' "$1" ;;
    none | '') printf 'pacman' ;;
    *) return 1 ;;
    esac
}

timezone_identifier_is_safe() {
    local timezone="${1:-}" component
    local -a components=()

    [ -n "$timezone" ] && [[ "$timezone" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] || return 1
    IFS='/' read -r -a components <<<"$timezone"
    for component in "${components[@]}"; do
        [ -n "$component" ] && [ "$component" != '.' ] && [ "$component" != '..' ] || return 1
    done
}

timezone_path_is_safe() {
    local timezone="${1:-}" zoneinfo_root zoneinfo_path

    timezone_identifier_is_safe "$timezone" || return 1
    zoneinfo_root="$(realpath -e -- /usr/share/zoneinfo)" || return 1
    zoneinfo_path="$(realpath -e -- "/usr/share/zoneinfo/${timezone}")" || return 1
    [ -f "$zoneinfo_path" ] || return 1
    case "$zoneinfo_path" in
    "${zoneinfo_root}"/*) return 0 ;;
    *) return 1 ;;
    esac
}

aur_dependency_is_safe() {
    local dependency="${1:-}"
    [[ "$dependency" =~ ^[a-z0-9][a-z0-9@._+:-]*([\<\>\=]{1,2}[A-Za-z0-9][A-Za-z0-9@._+~:-]*)?$ ]]
}

aur_srcinfo_identity_matches() {
    local expected="${1:-}" srcinfo="${2:-}" line value
    local pkgbase_count=0 expected_package_count=0

    [[ "$expected" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || return 1
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
        'pkgbase = '*)
            value="${line#pkgbase = }"
            [[ "$value" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || return 1
            pkgbase_count=$((pkgbase_count + 1))
            [ "$value" = "$expected" ] || return 1
            ;;
        'pkgname = '*)
            value="${line#pkgname = }"
            [[ "$value" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || return 1
            [ "$value" = "$expected" ] && expected_package_count=$((expected_package_count + 1))
            ;;
        esac
    done <<<"$srcinfo"
    [ "$pkgbase_count" -eq 1 ] && [ "$expected_package_count" -eq 1 ]
}

aur_srcinfo_dependencies() {
    local expected="${1:-}" line dependency current_package=''
    local -A seen=()

    [[ "$expected" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || return 1
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*pkgname[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
            current_package="${BASH_REMATCH[1]}"
            [[ "$current_package" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || return 1
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)?[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
            dependency="${BASH_REMATCH[3]}"
            aur_dependency_is_safe "$dependency" || return 1
            # Base dependencies and the exact requested package are the only allowed sections.
            if [ -z "$current_package" ] || [ "$current_package" = "$expected" ]; then
                if [ -z "${seen[$dependency]+set}" ]; then
                    printf '%s\n' "$dependency"
                    seen[$dependency]=1
                fi
            fi
        elif [[ "$line" =~ ^[[:space:]]*(depends|makedepends|checkdepends)(_x86_64)?[[:space:]]*= ]]; then
            return 1
        fi
    done
}

# AUR metadata is never trusted by name alone. Each permitted package is bound to the exact AUR
# commit, a SHA-256 of `git archive --format=tar`, the checked-in .SRCINFO SHA-256 and the exact
# PKGBUILD SHA-256 after the small reviewed hardening patch below. The archive digest provides an
# algorithm-independent tree check in addition to Git's object identity.
aur_review_metadata() {
    case "${1:-}" in
    bibata-cursor-theme-bin)
        printf '%s\n' '5d418e2c328f988b0b5c4fc51e6ca9619bfda293 887ea3300b82fd7fd8a46617fd00dc9e596daa99e7865c7353cb7d8073b6e2b4 f38772066b7b2510d02ea1b9649df7fc63f4ec37bcec843a1631314c022f3d97 edd7feee7557524eba6ba509169e5106ed8711d421ad73b1045db125eb7763c3'
        ;;
    gnome-shell-extension-blur-my-shell)
        printf '%s\n' '8161ae31d9eee1fe235a203c2bb4512793c2c310 704e0d036582b00bafb793654ad1310295b4bd14f1791765d6eac76b24848564 6dcd291a072f70becc9193aad5ce4f001d669bb7eae0e6c620649d21272c2b5f 8dd8d810175574311426357e4a5d85c9ad138197a35ff413eee0d212a03f944a'
        ;;
    gnome-shell-extension-clipboard-indicator)
        printf '%s\n' '275daf0bd317ff8df1db651e50bcb31f1f9b4c47 19b0112d63ca955b662ce0f11c655a51f314b3217c7d70fcef55aeeebbabaced e66d52fd6625773f33460d30cf7be140b6ebeb350cf0b274434339a75f88e0dc 0d7981518298ae9389a7a63f3ec9918c9f66c8805a24cd20690c661c1ec64fa8'
        ;;
    gnome-shell-extension-dash-to-dock)
        printf '%s\n' 'a1733fcd3f774b768a701dc8fd1414934645f478 9ab94834886058a417fdd33fd1a3719583490e485392b7c2dbdcce2d6fc1e4ee e663abc1001af20b97068a3b5cee7d361e6c8625f9015081faa5956fcd51199e b40333107e29b2f866c6d78a29622a30c76c1bc9d3d06cf800c3e9be1dcb81de'
        ;;
    gnome-shell-extension-just-perfection-desktop)
        printf '%s\n' '57e67cabe41c94858bd7f3cbe2c80eacc491b7cc 8b238aa4db622d608810b62d64c74b7b87beea3c44b8aebd1a59d91d5c58f2e0 9bbd8b52402236f642dcd926dc5a20e137b1d36a474f369ac53bf1ad560f383d 9f0fe0d3c9088b49c67ee1638218aff9ebddbd01f91c976b89139775be47578f'
        ;;
    paru)
        printf '%s\n' '329be2113c590046cb29858c23d9b96a8d7bd586 bdd43155bc97eac5f0075b5eb6bb5aeea483fdeef429a144c6989558e49dfea8 e84755034a22e0ecff5638ee4e96c69a7697f7f6a3ed781f1eeb53742d45be34 514ced7c6bf3be8a3528a383ac4f30e16df696cacdea7d43b88b095d8375658d'
        ;;
    paru-bin)
        printf '%s\n' '92a55429afbec4fceeb2cef843245105307444d2 18272d20abd4fd30e6e379b8eb7096359898b7fa29bcb5c8419fdbee4369b7f2 cb5cce5e588194d4da003d8309d7a8ef964b7b0ccafa4ba19764c1b5d1dce6a3 a6fc599a68d24528fd532184ce5e2f55a907783a9aeb4763971f7c2ae644ff43'
        ;;
    paru-git)
        printf '%s\n' 'f099fdc4d8efd4e4622a8f238b59b6fc540e8304 29f0752db0ac2710e03a2ce3a14eee5fcb66b63b7a7683be9a88496270ca367e 59b834ecd905340a10138cd7d3e92ed8b7b62f5801984b448d0879d06417b6a0 ad02c2dcf3044439adccb0ffe60d6dc5c3f8fd839b6aad1d96f14bbb98526c0a'
        ;;
    pikaur)
        printf '%s\n' '29d9831c6f4327cc0e3ad1c42dc8f961e98c099e 6a42c4067e41134f3914a8a265655ee5193032dd3bdd2149948180f44441fe86 9d1ee4f74af33d589778ef1793eed874688441deeac5551733dbff40f4f2e43d 92d1939e236bb67ce0c61f0b4aa4ba9ec9716e0e1a994637ae9013074f26065a'
        ;;
    plymouth-theme-archlinux)
        printf '%s\n' '3347bb2b0ace31f6fa07e080f2886cd04e3fea1d 508d4c782543fa72a01284c28f43db55819bab23f7915eb3abae2beb2fb4d9c9 e32dcb0c9c1492b9b7e627ff9bced6138a213fa83f841f2c4f8d1ac7a90a9c14 da96a3a7ed16473f6ab7c73fe9dc586a861e62919362bb60f63f0c1b035f8e2b'
        ;;
    trizen)
        printf '%s\n' '8b3bbabdd25e9247a18681ddc27aa287657c86ab a027080e35d0bd24a744d471a8e26b18237d0c9f0eda871eea0ccc0712f01ac5 f34517a663d3fbd9780a4c965300466ab29e5b6c58fde235d7191e650a133ad4 c96a513f286ead7dd8015f620b1eb69c4fa2142461a2d78c31c9cbdc90a3a57d'
        ;;
    yay)
        printf '%s\n' 'cb43f84828ab4f9700f7c6f9c6d7a923d4cfaff0 106c05ca8ea07cd95f44c87f046975db8a9781aab73bd8d9657f172b3b2d9f5c fdc02c822ec787e647001d541aab9d7d26b66d6526b049bc2be480133cdd1163 88387e6e4c2a057f1353a71f5198f13d9a1a6c1f5fed34d9bdcaffd4db244daf'
        ;;
    *) return 1 ;;
    esac
}

aur_review_source_identity_matches() {
    local repo="${1:-}" actual_commit="${2:-}" actual_archive="${3:-}" actual_srcinfo="${4:-}"
    local expected_commit expected_archive expected_srcinfo expected_pkgbuild

    read -r expected_commit expected_archive expected_srcinfo expected_pkgbuild \
        < <(aur_review_metadata "$repo") || return 1
    [ "$actual_commit" = "$expected_commit" ] && [ "$actual_archive" = "$expected_archive" ] &&
        [ "$actual_srcinfo" = "$expected_srcinfo" ]
}

aur_review_pkgbuild_matches() {
    local repo="${1:-}" actual_pkgbuild="${2:-}"
    local expected_commit expected_archive expected_srcinfo expected_pkgbuild

    read -r expected_commit expected_archive expected_srcinfo expected_pkgbuild \
        < <(aur_review_metadata "$repo") || return 1
    [ "$actual_pkgbuild" = "$expected_pkgbuild" ]
}

# This is the root package-manager authority boundary. It is intentionally narrower than merely
# accepting syntactically valid .SRCINFO values: every official dependency for every reviewed AUR
# input is listed exactly, in canonical metadata order.
aur_reviewed_dependencies() {
    case "${1:-}" in
    bibata-cursor-theme-bin) ;;
    gnome-shell-extension-blur-my-shell) printf '%s\n' git jq gnome-shell ;;
    gnome-shell-extension-clipboard-indicator) printf '%s\n' 'gnome-shell>=46.0' ;;
    gnome-shell-extension-dash-to-dock) printf '%s\n' gettext git sassc gnome-shell ;;
    gnome-shell-extension-just-perfection-desktop) printf '%s\n' git gnome-shell ;;
    paru|paru-git) printf '%s\n' cargo git pacman 'libalpm.so>=14' ;;
    paru-bin) printf '%s\n' git pacman 'libalpm.so>=14' ;;
    pikaur)
        printf '%s\n' python-wheel python-hatchling python-build python-installer \
            python-setuptools python-markdown-it-py pyalpm git
        ;;
    plymouth-theme-archlinux) printf '%s\n' git plymouth ;;
    trizen)
        printf '%s\n' git pacutils 'perl>=5.20.0' perl-libwww perl-term-ui pacman perl-json \
            perl-data-dump perl-lwp-protocol-https perl-term-readline-gnu
        ;;
    yay) printf '%s\n' 'go>=1.24' 'pacman>6.1' git ;;
    *) return 1 ;;
    esac
}

aur_extension_uuid() {
    case "${1:-}" in
    gnome-shell-extension-dash-to-dock) printf '%s' 'dash-to-dock@micxgx.gmail.com' ;;
    gnome-shell-extension-blur-my-shell) printf '%s' 'blur-my-shell@aunetx' ;;
    gnome-shell-extension-just-perfection-desktop) printf '%s' 'just-perfection-desktop@just-perfection' ;;
    gnome-shell-extension-clipboard-indicator) printf '%s' 'clipboard-indicator@tudmotu.com' ;;
    *) return 1 ;;
    esac
}

aur_package_output_path_is_safe() {
    local path="${1:-}"

    [[ "$path" =~ ^/var/lib/arch-linux-aur-builder/src-[a-z0-9@._+-]+-[1-5]/[A-Za-z0-9@._:+-]+\.pkg\.tar\.zst$ ]]
}

# Package directories are allowed only so that the reviewed file leaves below have parents. Root
# authority is granted to no generic /etc, hook, PAM, polkit, D-Bus, system-service or keyring path.
aur_package_path_is_allowed() {
    local repo="${1:-}" path="${2:-}" entry_type="${3:-}" uuid=''

    path="${path%/}"
    case "$path" in
    .PKGINFO|.BUILDINFO|.MTREE)
        [ "$entry_type" = '-' ]
        return
        ;;
    usr|usr/bin|usr/lib|usr/share|etc)
        [ "$entry_type" = d ]
        return
        ;;
    esac

    if uuid="$(aur_extension_uuid "$repo" 2>/dev/null)"; then
        case "$path" in
        usr/share/gnome-shell|usr/share/gnome-shell/extensions|usr/share/glib-2.0|usr/share/glib-2.0/schemas|usr/share/licenses|usr/share/licenses/"$repo"|usr/share/locale)
            [ "$entry_type" = d ]
            ;;
        usr/share/gnome-shell/extensions/"$uuid"|usr/share/gnome-shell/extensions/"$uuid"/*|usr/share/glib-2.0/schemas/*|usr/share/licenses/"$repo"/*|usr/share/locale/*)
            ;;
        *) return 1 ;;
        esac
        return
    fi

    if [ "$repo" = pikaur ]; then
        if [[ "$path" =~ ^usr/lib/python3\.[0-9]+(/site-packages)?$ ]]; then
            [ "$entry_type" = d ]
            return
        fi
        if [[ "$path" =~ ^usr/lib/python3\.[0-9]+/site-packages/(pikaur(/.*)?|pikaur-[A-Za-z0-9._+-]+\.dist-info(/.*)?)$ ]]; then
            return
        fi
    fi

    case "$repo:$path" in
    bibata-cursor-theme-bin:usr/share/icons|bibata-cursor-theme-bin:usr/share/icons/Bibata-*) ;;
    plymouth-theme-archlinux:usr/share/plymouth|plymouth-theme-archlinux:usr/share/plymouth/themes|plymouth-theme-archlinux:usr/share/plymouth/themes/archlinux|plymouth-theme-archlinux:usr/share/plymouth/themes/archlinux/*) ;;
    paru:etc/paru.conf|paru-bin:etc/paru.conf|paru-git:etc/paru.conf) ;;
    paru:usr/bin/paru|paru-bin:usr/bin/paru|paru-git:usr/bin/paru) ;;
    yay:usr/bin/yay|trizen:usr/bin/trizen|pikaur:usr/bin/pikaur) ;;
    paru:usr/share/bash-completion|paru-bin:usr/share/bash-completion|paru-git:usr/share/bash-completion|yay:usr/share/bash-completion|trizen:usr/share/bash-completion|pikaur:usr/share/bash-completion) [ "$entry_type" = d ] ;;
    paru:usr/share/bash-completion/*|paru-bin:usr/share/bash-completion/*|paru-git:usr/share/bash-completion/*|yay:usr/share/bash-completion/*|trizen:usr/share/bash-completion/*|pikaur:usr/share/bash-completion/*) ;;
    paru:usr/share/fish|paru-bin:usr/share/fish|paru-git:usr/share/fish|yay:usr/share/fish|trizen:usr/share/fish|pikaur:usr/share/fish) [ "$entry_type" = d ] ;;
    paru:usr/share/fish/*|paru-bin:usr/share/fish/*|paru-git:usr/share/fish/*|yay:usr/share/fish/*|trizen:usr/share/fish/*|pikaur:usr/share/fish/*) ;;
    paru:usr/share/zsh|paru-bin:usr/share/zsh|paru-git:usr/share/zsh|yay:usr/share/zsh|trizen:usr/share/zsh|pikaur:usr/share/zsh) [ "$entry_type" = d ] ;;
    paru:usr/share/zsh/*|paru-bin:usr/share/zsh/*|paru-git:usr/share/zsh/*|yay:usr/share/zsh/*|trizen:usr/share/zsh/*|pikaur:usr/share/zsh/*) ;;
    paru:usr/share/man|paru-bin:usr/share/man|paru-git:usr/share/man|yay:usr/share/man|trizen:usr/share/man|pikaur:usr/share/man) [ "$entry_type" = d ] ;;
    paru:usr/share/man/*|paru-bin:usr/share/man/*|paru-git:usr/share/man/*|yay:usr/share/man/*|trizen:usr/share/man/*|pikaur:usr/share/man/*) ;;
    paru:usr/share/locale|paru-bin:usr/share/locale|paru-git:usr/share/locale|yay:usr/share/locale|pikaur:usr/share/locale) [ "$entry_type" = d ] ;;
    paru:usr/share/locale/*|paru-bin:usr/share/locale/*|paru-git:usr/share/locale/*|yay:usr/share/locale/*|pikaur:usr/share/locale/*) ;;
    pikaur:usr/share/licenses|pikaur:usr/share/licenses/pikaur|pikaur:usr/share/licenses/pikaur/*) ;;
    pikaur:usr/share/pikaur|pikaur:usr/share/pikaur/*) ;;
    pikaur:usr/lib/systemd|pikaur:usr/lib/systemd/user) [ "$entry_type" = d ] ;;
    pikaur:usr/lib/systemd/user/pikaur-cache.service|pikaur:usr/lib/systemd/user/pikaur-cache.timer) [ "$entry_type" = '-' ] ;;
    *) return 1 ;;
    esac
}

aur_package_symlink_is_safe() {
    local repo="${1:-}" path="${2:-}" target="${3:-}" allowed_root resolved

    [ -n "$target" ] && [[ "$target" != /* ]] && [[ "$target" != *'//'* ]] &&
        [[ "$target" =~ ^[A-Za-z0-9@._+/-]+$ ]] || return 1
    case "$repo" in
    bibata-cursor-theme-bin) allowed_root='/usr/share/icons' ;;
    gnome-shell-extension-*) allowed_root="/usr/share/gnome-shell/extensions/$(aur_extension_uuid "$repo")" ;;
    *) return 1 ;;
    esac
    resolved="$(realpath -m -- "/${path%/*}/${target}")" || return 1
    case "$resolved" in
    "$allowed_root"|"$allowed_root"/*) ;;
    *) return 1 ;;
    esac
}

# Validate the complete root-installable archive without extracting it. libarchive escapes control
# characters in list output; the deliberately narrow path alphabet therefore rejects newline and
# other filename tricks as well as absolute/traversing paths. Only regular files, directories and
# contained package-local symlinks with root:root ownership and ordinary 0644/0755 modes survive.
aur_bsdtar_bounded() {
    timeout --signal=TERM --kill-after=5 120 /usr/bin/bsdtar "$@"
}

# libarchive exposes metadata that neither the normal verbose listing nor pacman -Qkk reports.
# In particular, a root-owned executable can carry a file-capability xattr while its path, mode,
# checksum and package database entry all look ordinary. Inspect headers only, with a clean Python
# environment and no extraction, and reject every xattr, ACL, file flag, macOS metadata block,
# hardlink or encrypted entry before the original archive can reach root pacman.
aur_archive_extended_metadata_is_absent() {
    local archive="${1:-}"
    [ -f "$archive" ] && [ ! -L "$archive" ] || return 1
    timeout --signal=TERM --kill-after=5 120 /usr/bin/env -i \
        'HOME=/' 'PATH=/usr/bin:/bin' 'LANG=C.UTF-8' 'LC_ALL=C.UTF-8' \
        /usr/bin/python -I -S - "$archive" <<'PY'
import ctypes
import os
import stat
import sys

ARCHIVE_OK = 0
ARCHIVE_EOF = 1
MAXIMUM_ENTRIES = 100_000


def reject() -> None:
    raise SystemExit(1)


if len(sys.argv) != 2:
    reject()
archive_path = os.fsencode(sys.argv[1])
try:
    archive_stat = os.stat(archive_path, follow_symlinks=False)
except OSError:
    reject()
if not stat.S_ISREG(archive_stat.st_mode) or archive_stat.st_nlink != 1:
    reject()

try:
    libarchive = ctypes.CDLL("/usr/lib/libarchive.so")
except OSError:
    reject()

archive_pointer = ctypes.c_void_p
entry_pointer = ctypes.c_void_p
libarchive.archive_read_new.restype = archive_pointer
libarchive.archive_read_support_filter_all.argtypes = [archive_pointer]
libarchive.archive_read_support_filter_all.restype = ctypes.c_int
libarchive.archive_read_support_format_tar.argtypes = [archive_pointer]
libarchive.archive_read_support_format_tar.restype = ctypes.c_int
libarchive.archive_read_open_filename.argtypes = [archive_pointer, ctypes.c_char_p, ctypes.c_size_t]
libarchive.archive_read_open_filename.restype = ctypes.c_int
libarchive.archive_read_next_header.argtypes = [archive_pointer, ctypes.POINTER(entry_pointer)]
libarchive.archive_read_next_header.restype = ctypes.c_int
libarchive.archive_read_data_skip.argtypes = [archive_pointer]
libarchive.archive_read_data_skip.restype = ctypes.c_int
libarchive.archive_read_free.argtypes = [archive_pointer]
libarchive.archive_read_free.restype = ctypes.c_int
libarchive.archive_entry_xattr_count.argtypes = [entry_pointer]
libarchive.archive_entry_xattr_count.restype = ctypes.c_int
libarchive.archive_entry_acl_types.argtypes = [entry_pointer]
libarchive.archive_entry_acl_types.restype = ctypes.c_int
libarchive.archive_entry_fflags.argtypes = [
    entry_pointer,
    ctypes.POINTER(ctypes.c_ulong),
    ctypes.POINTER(ctypes.c_ulong),
]
libarchive.archive_entry_mac_metadata.argtypes = [entry_pointer, ctypes.POINTER(ctypes.c_size_t)]
libarchive.archive_entry_mac_metadata.restype = ctypes.c_void_p
libarchive.archive_entry_hardlink.argtypes = [entry_pointer]
libarchive.archive_entry_hardlink.restype = ctypes.c_char_p
libarchive.archive_entry_is_encrypted.argtypes = [entry_pointer]
libarchive.archive_entry_is_encrypted.restype = ctypes.c_int

reader = libarchive.archive_read_new()
if not reader:
    reject()
free_required = True
status = 1
try:
    if libarchive.archive_read_support_filter_all(reader) != ARCHIVE_OK:
        reject()
    if libarchive.archive_read_support_format_tar(reader) != ARCHIVE_OK:
        reject()
    if libarchive.archive_read_open_filename(reader, archive_path, 10240) != ARCHIVE_OK:
        reject()
    entry = entry_pointer()
    entry_count = 0
    while True:
        result = libarchive.archive_read_next_header(reader, ctypes.byref(entry))
        if result == ARCHIVE_EOF:
            break
        if result != ARCHIVE_OK or not entry:
            reject()
        entry_count += 1
        if entry_count > MAXIMUM_ENTRIES:
            reject()
        flag_set = ctypes.c_ulong()
        flag_clear = ctypes.c_ulong()
        libarchive.archive_entry_fflags(entry, ctypes.byref(flag_set), ctypes.byref(flag_clear))
        mac_metadata_size = ctypes.c_size_t()
        mac_metadata = libarchive.archive_entry_mac_metadata(entry, ctypes.byref(mac_metadata_size))
        if libarchive.archive_entry_xattr_count(entry) != 0:
            reject()
        if libarchive.archive_entry_acl_types(entry) != 0:
            reject()
        if flag_set.value != 0 or flag_clear.value != 0:
            reject()
        if mac_metadata or mac_metadata_size.value != 0:
            reject()
        if libarchive.archive_entry_hardlink(entry):
            reject()
        if libarchive.archive_entry_is_encrypted(entry) != 0:
            reject()
        if libarchive.archive_read_data_skip(reader) != ARCHIVE_OK:
            reject()
    status = 0
finally:
    if free_required and libarchive.archive_read_free(reader) != ARCHIVE_OK:
        status = 1
raise SystemExit(status)
PY
}

aur_package_archive_is_safe() (
    local repo="${1:-}" archive="${2:-}" package_info package_name mode entry_type path detail
    local link_count numeric_uid numeric_gid entry_size detail_rest target='' link_marker
    local path_listing detail_listing package_info_file archive_size
    local -a paths=() details=()
    local -A seen_paths=()
    local index pkginfo_count=0 buildinfo_count=0 mtree_count=0 regular_size_total=0
    local maximum_regular_entry_size=268435456 maximum_regular_total_size=1073741824

    aur_review_metadata "$repo" >/dev/null || return 1
    [ -f "$archive" ] && [ ! -L "$archive" ] || return 1
    archive_size="$(stat -c '%s' -- "$archive")" || return 1
    [ "$archive_size" -gt 0 ] && [ "$archive_size" -le 536870912 ] || return 1

    package_info_file="$(umask 077 && mktemp -- "${SCRIPT_TMP_DIR}/aur-pkginfo.XXXXXXXXXX")" || return 1
    path_listing="$(umask 077 && mktemp -- "${SCRIPT_TMP_DIR}/aur-paths.XXXXXXXXXX")" || {
        rm -f -- "$package_info_file"
        return 1
    }
    detail_listing="$(umask 077 && mktemp -- "${SCRIPT_TMP_DIR}/aur-details.XXXXXXXXXX")" || {
        rm -f -- "$package_info_file" "$path_listing"
        return 1
    }
    trap 'rm -f -- "$package_info_file" "$path_listing" "$detail_listing"' EXIT
    (ulimit -f 512; LC_ALL=C aur_bsdtar_bounded -xOf "$archive" .PKGINFO) \
        >"$package_info_file" 2>/dev/null || return 1
    [ "$(stat -c '%s' -- "$package_info_file")" -le 262144 ] || return 1
    package_info="$(<"$package_info_file")"
    package_name="$(awk -F' = ' '$1 == "pkgname" { print $2 }' <<<"$package_info")"
    [ "$package_name" = "$repo" ] && [ "$(grep -c '^pkgname = ' <<<"$package_info")" -eq 1 ] || return 1
    ! grep -Eq '^(replaces|install) = ' <<<"$package_info" || return 1

    (ulimit -f 32768; LC_ALL=C aur_bsdtar_bounded -tf "$archive") >"$path_listing" 2>/dev/null || return 1
    (ulimit -f 32768; LC_ALL=C aur_bsdtar_bounded --numeric-owner -tvf "$archive") \
        >"$detail_listing" 2>/dev/null || return 1
    [ "$(stat -c '%s' -- "$path_listing")" -le 16777216 ] &&
        [ "$(stat -c '%s' -- "$detail_listing")" -le 16777216 ] || return 1
    mapfile -t paths <"$path_listing" || return 1
    mapfile -t details <"$detail_listing" || return 1
    [ "${#paths[@]}" -ge 4 ] && [ "${#paths[@]}" -le 100000 ] &&
        [ "${#paths[@]}" -eq "${#details[@]}" ] || return 1

    for index in "${!paths[@]}"; do
        path="${paths[$index]}"
        detail="${details[$index]}"
        [[ "$path" =~ ^(\.(PKGINFO|BUILDINFO|MTREE)|[A-Za-z0-9@._+-]+(/[A-Za-z0-9@._+-]+)*/?)$ ]] || return 1
        [[ "$path" != /* && "$path" != *'//'* && "$path" != */../* && "$path" != ../* && "$path" != */.. ]] || return 1
        [ -z "${seen_paths[$path]+set}" ] || return 1
        seen_paths[$path]=1
        case "$path" in
        .PKGINFO) pkginfo_count=$((pkginfo_count + 1)) ;;
        .BUILDINFO) buildinfo_count=$((buildinfo_count + 1)) ;;
        .MTREE) mtree_count=$((mtree_count + 1)) ;;
        .INSTALL|.CHANGELOG|*/.PKGINFO) return 1 ;;
        esac
        mode="${detail%%[[:space:]]*}"
        entry_type="${mode:0:1}"
        case "$entry_type:$mode" in
        -:-rw-r--r--|-:-rwxr-xr-x|d:drwxr-xr-x|l:lrwxrwxrwx) ;;
        *) return 1 ;;
        esac
        IFS=' ' read -r mode link_count numeric_uid numeric_gid entry_size detail_rest \
            <<<"$detail" || return 1
        [[ "$link_count" =~ ^(0|[1-9][0-9]{0,5})$ ]] || return 1
        [[ "$numeric_uid" =~ ^(0|[1-9][0-9]{0,9})$ ]] && [ "$numeric_uid" = 0 ] || return 1
        [[ "$numeric_gid" =~ ^(0|[1-9][0-9]{0,9})$ ]] && [ "$numeric_gid" = 0 ] || return 1
        [[ "$entry_size" =~ ^(0|[1-9][0-9]{0,9})$ ]] && [ -n "$detail_rest" ] || return 1
        if [ "$entry_type" = '-' ]; then
            [ "$entry_size" -le "$maximum_regular_entry_size" ] || return 1
            [ "$regular_size_total" -le $((maximum_regular_total_size - entry_size)) ] || return 1
            regular_size_total=$((regular_size_total + entry_size))
        else
            [ "$entry_size" -eq 0 ] || return 1
        fi
        case "$path" in
        .PKGINFO) [ "$entry_size" -le 262144 ] || return 1 ;;
        .BUILDINFO) [ "$entry_size" -le 1048576 ] || return 1 ;;
        .MTREE) [ "$entry_size" -le 16777216 ] || return 1 ;;
        esac
        aur_package_path_is_allowed "$repo" "$path" "$entry_type" || return 1
        if [ "$entry_type" = l ]; then
            link_marker=" ${path%/} -> "
            case "$detail" in
            *"$link_marker"*) target="${detail#*"$link_marker"}" ;;
            *) return 1 ;;
            esac
            aur_package_symlink_is_safe "$repo" "${path%/}" "$target" || return 1
        fi
    done
    [ "$pkginfo_count" -eq 1 ] && [ "$buildinfo_count" -eq 1 ] && [ "$mtree_count" -eq 1 ] &&
        aur_archive_extended_metadata_is_absent "$archive"
)

locale_with_utf8() {
    case "$1" in
    *@*) printf '%s.UTF-8@%s' "${1%%@*}" "${1#*@}" ;;
    *) printf '%s.UTF-8' "$1" ;;
    esac
}

grub_unencrypted_kernel_cmdline() {
    local kernel_arg
    local -a grub_kernel_args=()
    for kernel_arg in "$@"; do
        case "$kernel_arg" in
        rw | quiet | loglevel=3 | root=PARTUUID=* | rootflags=subvol=@) ;;
        *) grub_kernel_args+=("$kernel_arg") ;;
        esac
    done
    printf '%s' "${grub_kernel_args[*]}"
}

grub_encrypted_kernel_cmdline() {
    local kernel_arg
    local -a grub_kernel_args=()
    for kernel_arg in "$@"; do
        case "$kernel_arg" in
        rw | quiet | loglevel=3 | root=/dev/mapper/cryptroot | rootflags=subvol=@) ;;
        *) grub_kernel_args+=("$kernel_arg") ;;
        esac
    done
    printf '%s' "${grub_kernel_args[*]}"
}

# Desktop keyboard layouts as an xkb list: "us" or "us,ru". The Latin layout stays first so it is
# the default group at login and so console/X11 fall back to it.
desktop_keyboard_layouts() {
    local layouts="$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
    [ -n "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" ] && layouts="${layouts},${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND}"
    printf '%s' "$layouts"
}

# Matching variant list; the second layout is always used in its default variant
desktop_keyboard_variants() {
    local variants="${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT:-}"
    [ -n "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" ] && variants="${variants},"
    printf '%s' "$variants"
}

# Ptyxis/GTK application accelerators are matched against keysyms, so the physical C key emits
# Cyrillic_es under a Russian layout and no longer matches a plain "c" shortcut. Install the
# verified alternative bindings whenever Russian is selected as the locale or as either desktop
# layout. The original Latin accelerators stay in every value, separated with GTK's "|" syntax.
needs_ptyxis_russian_shortcuts() {
    case "${ARCH_LINUX_LOCALE_LANG:-}" in
    ru_RU | ru_RU@*) return 0 ;;
    esac
    [ "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT:-}" = "ru" ] ||
        [ "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" = "ru" ]
}

partition_name() {
    # /dev/sda -> /dev/sda1, /dev/nvme0n1 -> /dev/nvme0n1p1, /dev/mmcblk0 -> /dev/mmcblk0p1
    local disk="$1" part_number="$2"
    [[ "$disk" =~ [0-9]$ ]] && printf '%sp%s' "$disk" "$part_number" || printf '%s%s' "$disk" "$part_number"
}

# ---------------------------------------------------------------------------------------------------
# Block device probes. Wrapped in functions on purpose: they are the seam the disk-safety tests stub
# out, so validate_partition_targets can be exercised without real hardware (tests/function-checks.sh).

# Resolve to the canonical /dev node, so /dev/disk/by-uuid/... and plain paths compare equal
block_canonical() { readlink -f -- "$1" 2>/dev/null || printf '%s' "$1"; }

# Node exists and is a block device
block_exists() { [ -b "$1" ]; }

# lsblk TYPE: 'disk', 'part', 'loop', 'crypt', ... (empty when the node does not exist)
block_type() { lsblk -dno TYPE -- "$1" 2>/dev/null | head -n1; }

# Parent disk of a partition: /dev/sda1 -> /dev/sda (empty when not a partition)
block_parent() {
    local parent && parent="$(lsblk -dno PKNAME -- "$1" 2>/dev/null | head -n1)"
    [ -n "$parent" ] && printf '/dev/%s' "$parent"
}

block_attribute() {
    local node="$1" attribute="$2" value
    case "$attribute" in
    SIZE | WWN | SERIAL | MODEL | PARTUUID | START | FSTYPE) ;;
    *) return 1 ;;
    esac
    value="$(lsblk -bdno "$attribute" -- "$node" 2>/dev/null | head -n1)" || return 1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

block_paths_for_type() {
    local wanted="$1"
    case "$wanted" in disk | part) ;;
    *) return 1 ;;
    esac
    lsblk -rpno PATH,TYPE 2>/dev/null | awk -v wanted="$wanted" '$2 == wanted { print $1 }'
}

block_identity_field_is_safe() {
    local value="$1" field_re='^[-A-Za-z0-9._:+/@, ]+$'
    [ -n "$value" ] && [[ "$value" =~ $field_re ]]
}

block_disk_identity() {
    local disk canonical size wwn serial model material

    disk="$1"
    canonical="$(block_canonical "$disk")" || return 1
    block_exists "$canonical" && [ "$(block_type "$canonical")" = disk ] || return 1
    size="$(block_attribute "$canonical" SIZE)" || return 1
    wwn="$(block_attribute "$canonical" WWN)" || return 1
    serial="$(block_attribute "$canonical" SERIAL)" || return 1
    model="$(block_attribute "$canonical" MODEL)" || return 1
    wwn="${wwn#"${wwn%%[![:space:]]*}"}" && wwn="${wwn%"${wwn##*[![:space:]]}"}"
    serial="${serial#"${serial%%[![:space:]]*}"}" && serial="${serial%"${serial##*[![:space:]]}"}"
    model="${model#"${model%%[![:space:]]*}"}" && model="${model%"${model##*[![:space:]]}"}"
    [[ "$size" =~ ^[1-9][0-9]*$ ]] && block_identity_field_is_safe "$model" || return 1
    if [ -n "$wwn" ]; then
        block_identity_field_is_safe "$wwn" || return 1
    else
        block_identity_field_is_safe "$serial" || return 1
    fi
    [ -z "$serial" ] || block_identity_field_is_safe "$serial" || return 1
    printf -v material 'size=%s\nwwn=%s\nserial=%s\nmodel=%s\n' \
        "$size" "$wwn" "$serial" "$model"
    printf '%s' "$material" | sha256sum --binary | awk '{ print $1 }'
}

block_partition_identity() {
    local partition canonical parent parent_identity partuuid start size material

    partition="$1"
    canonical="$(block_canonical "$partition")" || return 1
    block_exists "$canonical" && [ "$(block_type "$canonical")" = part ] || return 1
    parent="$(block_parent "$canonical")" || return 1
    parent="$(block_canonical "$parent")" || return 1
    parent_identity="$(block_disk_identity "$parent")" || return 1
    partuuid="$(block_attribute "$canonical" PARTUUID)" || return 1
    start="$(block_attribute "$canonical" START)" || return 1
    size="$(block_attribute "$canonical" SIZE)" || return 1
    [[ "$partuuid" =~ ^[A-Fa-f0-9-]{8,}$ ]] && [[ "$start" =~ ^[0-9]+$ ]] &&
        [[ "$size" =~ ^[1-9][0-9]*$ ]] || return 1
    printf -v material 'disk=%s\npartuuid=%s\nstart=%s\nsize=%s\n' \
        "$parent_identity" "${partuuid,,}" "$start" "$size"
    printf '%s' "$material" | sha256sum --binary | awk '{ print $1 }'
}

block_identity_is_unique() {
    local kind="$1" expected="$2" path candidate count=0

    [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || return 1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$kind" in
        disk) candidate="$(block_disk_identity "$path")" || continue ;;
        part) candidate="$(block_partition_identity "$path")" || continue ;;
        *) return 1 ;;
        esac
        [ "$candidate" = "$expected" ] && count=$((count + 1))
    done < <(block_paths_for_type "$kind")
    [ "$count" -eq 1 ]
}

block_handle_matches_node() {
    local handle="$1" node="$2" handle_device node_device
    [ -b "$handle" ] && [ -b "$node" ] || return 1
    handle_device="$(stat -Lc '%t:%T' -- "$handle")" || return 1
    node_device="$(stat -Lc '%t:%T' -- "$node")" || return 1
    [ "$handle_device" = "$node_device" ]
}

block_disk_handle_is_bound() {
    local handle="$1" disk="$2" expected_identity="$3" actual_identity
    block_handle_matches_node "$handle" "$disk" || return 1
    [ "$(block_type "$disk")" = disk ] || return 1
    actual_identity="$(block_disk_identity "$disk")" || return 1
    [ "$actual_identity" = "$expected_identity" ] &&
        block_identity_is_unique disk "$expected_identity"
}

block_partition_handle_is_bound() {
    local handle="$1" partition="$2" disk="$3" expected_identity="$4" actual_identity
    block_handle_matches_node "$handle" "$partition" || return 1
    [ "$(block_type "$partition")" = part ] || return 1
    [ "$(block_parent "$partition")" = "$disk" ] || return 1
    actual_identity="$(block_partition_identity "$partition")" || return 1
    [ "$actual_identity" = "$expected_identity" ] &&
        block_identity_is_unique part "$expected_identity"
}

# Hard safety gate for every destructive disk target. This must hold on its own: the interactive
# select_dual_boot_partitions is optional (System Tuning), and a loaded installer.conf, the Advanced
# Setup Editor or FORCE=true can all reach exec_prepare_disk without ever passing through that UI.
#
# The two modes have deliberately different rules, because in non-dual mode the partitions do not
# exist yet - exec_prepare_disk creates them:
#   non-dual : BOOT/ROOT must be exactly partition_name(DISK,1|2). No existence check (nothing to
#              check yet), but this alone rules out foreign-disk, whole-disk and BOOT==ROOT targets.
#   dual boot: partitions must already exist, be real partitions, differ, and sit on the chosen disk.
#
# Callers pass a reporter so this works both as a validator (collect failures) and as a pre-flight
# assertion inside the executor subshell (abort immediately).
validate_partition_targets() {
    local report="$1" ok="true"
    local disk boot root disk_type

    disk="$(block_canonical "$ARCH_LINUX_DISK")"
    boot="$(block_canonical "$ARCH_LINUX_BOOT_PARTITION")"
    root="$(block_canonical "$ARCH_LINUX_ROOT_PARTITION")"

    # The install target must be a whole physical/virtual disk, never a partition or loop mapping:
    # sgdisk --zap-all would otherwise destroy the partition table of whatever contains it.
    block_exists "$disk" || { "$report" "ARCH_LINUX_DISK '${ARCH_LINUX_DISK}' is not a block device" && ok="false"; }
    disk_type="$(block_type "$disk")"
    [ "$disk_type" = disk ] || {
        "$report" "ARCH_LINUX_DISK '${ARCH_LINUX_DISK}' must be a whole disk (detected: ${disk_type:-none})" && ok="false"
    }

    # Same canonical node as both ESP and root means the ESP gets formatted as root
    [ "$boot" = "$root" ] && {
        "$report" "ARCH_LINUX_BOOT_PARTITION and ARCH_LINUX_ROOT_PARTITION resolve to the same device '${boot}'" && ok="false"
    }

    if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ]; then
        local part part_type parent label
        for part in "$boot" "$root"; do
            [ "$part" = "$boot" ] && label="ARCH_LINUX_BOOT_PARTITION" || label="ARCH_LINUX_ROOT_PARTITION"
            if ! block_exists "$part"; then
                "$report" "${label} '${part}' does not exist (dual boot reuses existing partitions)" && ok="false"
                continue
            fi
            part_type="$(block_type "$part")"
            [ "$part_type" = "part" ] || { "$report" "${label} '${part}' is not a partition (detected: ${part_type:-none})" && ok="false"; }
            parent="$(block_parent "$part")"
            [ "$parent" = "$disk" ] || { "$report" "${label} '${part}' is not on ${disk} (parent: ${parent:-none})" && ok="false"; }
        done
    else
        # Fresh install: the only supported layout is the one exec_prepare_disk is about to create.
        local expect_boot expect_root
        expect_boot="$(partition_name "$disk" 1)"
        expect_root="$(partition_name "$disk" 2)"
        [ "$boot" = "$expect_boot" ] || { "$report" "ARCH_LINUX_BOOT_PARTITION '${boot}' does not match the layout created on ${disk} (expected ${expect_boot})" && ok="false"; }
        [ "$root" = "$expect_root" ] || { "$report" "ARCH_LINUX_ROOT_PARTITION '${root}' does not match the layout created on ${disk} (expected ${expect_root})" && ok="false"; }
    fi

    [ "$ok" = "true" ]
}

# Revalidate the complete destructive snapshot. Persisted opaque fingerprints bind a stale/FORCE
# config to one unique whole disk and, for dual boot, to the exact two GPT partitions selected.
validate_destructive_targets() {
    local report="$1" ok=true disk_identity boot_identity root_identity boot_type root_bytes

    validate_partition_targets "$report" || ok=false
    disk_identity="$(block_disk_identity "$ARCH_LINUX_DISK")" || disk_identity=''
    if [ -z "${ARCH_LINUX_DISK_IDENTITY:-}" ] ||
        [ "$disk_identity" != "$ARCH_LINUX_DISK_IDENTITY" ]; then
        "$report" "ARCH_LINUX_DISK physical identity is missing or changed" && ok=false
    elif ! block_identity_is_unique disk "$disk_identity"; then
        "$report" "ARCH_LINUX_DISK physical identity is ambiguous" && ok=false
    fi

    if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = true ]; then
        boot_identity="$(block_partition_identity "$ARCH_LINUX_BOOT_PARTITION")" || boot_identity=''
        root_identity="$(block_partition_identity "$ARCH_LINUX_ROOT_PARTITION")" || root_identity=''
        if [ -z "${ARCH_LINUX_BOOT_PARTITION_IDENTITY:-}" ] ||
            [ "$boot_identity" != "$ARCH_LINUX_BOOT_PARTITION_IDENTITY" ] ||
            ! block_identity_is_unique part "$boot_identity"; then
            "$report" "ARCH_LINUX_BOOT_PARTITION identity is missing, changed or ambiguous" && ok=false
        fi
        if [ -z "${ARCH_LINUX_ROOT_PARTITION_IDENTITY:-}" ] ||
            [ "$root_identity" != "$ARCH_LINUX_ROOT_PARTITION_IDENTITY" ] ||
            ! block_identity_is_unique part "$root_identity"; then
            "$report" "ARCH_LINUX_ROOT_PARTITION identity is missing, changed or ambiguous" && ok=false
        fi
        boot_type="$(block_attribute "$ARCH_LINUX_BOOT_PARTITION" FSTYPE)" || boot_type=''
        [ "$boot_type" = vfat ] || {
            "$report" "ARCH_LINUX_BOOT_PARTITION is not the selected vfat EFI partition" && ok=false
        }
        root_bytes="$(block_attribute "$ARCH_LINUX_ROOT_PARTITION" SIZE)" || root_bytes=''
        if ! [[ "$root_bytes" =~ ^[0-9]+$ ]] || [ "$root_bytes" -lt $((8 * 1024 * 1024 * 1024)) ]; then
            "$report" "ARCH_LINUX_ROOT_PARTITION is smaller than 8 GiB" && ok=false
        fi
    elif [ -n "${ARCH_LINUX_BOOT_PARTITION_IDENTITY:-}" ] ||
        [ -n "${ARCH_LINUX_ROOT_PARTITION_IDENTITY:-}" ]; then
        "$report" "Fresh-install partition identities must be empty before partition creation" && ok=false
    fi
    [ "$ok" = true ]
}

destructive_target_snapshot() {
    local disk boot root disk_identity material boot_identity='' root_identity=''
    local boot_type='' root_size=''

    disk="$(block_canonical "$ARCH_LINUX_DISK")" || return 1
    boot="$(block_canonical "$ARCH_LINUX_BOOT_PARTITION")" || return 1
    root="$(block_canonical "$ARCH_LINUX_ROOT_PARTITION")" || return 1
    disk_identity="$(block_disk_identity "$disk")" || return 1
    if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = true ]; then
        boot_identity="$(block_partition_identity "$boot")" || return 1
        root_identity="$(block_partition_identity "$root")" || return 1
        boot_type="$(block_attribute "$boot" FSTYPE)" || return 1
        root_size="$(block_attribute "$root" SIZE)" || return 1
    fi
    printf -v material 'dual=%s\ndisk=%s\ndisk-id=%s\nboot=%s\nboot-id=%s\nboot-type=%s\nroot=%s\nroot-id=%s\nroot-size=%s\n' \
        "$ARCH_LINUX_DUAL_BOOT_ENABLED" "$disk" "$disk_identity" "$boot" "$boot_identity" \
        "$boot_type" "$root" "$root_identity" "$root_size"
    printf '%s' "$material" | sha256sum --binary | awk '{ print $1 }'
}

assert_accepted_destructive_target() {
    local report="$1" current_snapshot

    [ "${ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT:-}" != '' ] || {
        "$report" "Destructive target snapshot was not accepted" && return 1
    }
    validate_destructive_targets "$report" || return 1
    current_snapshot="$(destructive_target_snapshot)" || {
        "$report" "Could not reproduce destructive target snapshot" && return 1
    }
    [ "$current_snapshot" = "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" ] || {
        "$report" "Destructive target changed after validation" && return 1
    }
}

block_belongs_to_disk() {
    local candidate="$1" disk="$2" path canonical_disk

    candidate="${candidate%%\[*}"
    [ -b "$candidate" ] || return 1
    canonical_disk="$(block_canonical "$disk")" || return 1
    while IFS= read -r path; do
        [ "$(block_canonical "$path")" = "$canonical_disk" ] && return 0
    done < <(lsblk -srpno PATH -- "$candidate" 2>/dev/null)
    return 1
}

storage_path_belongs_to_disk() {
    local storage_path="$1" disk="$2" mount_source

    if [ -b "$storage_path" ]; then
        block_belongs_to_disk "$storage_path" "$disk"
        return
    fi
    [ -e "$storage_path" ] || return 1
    mount_source="$(findmnt -rn -o SOURCE -T "$storage_path" 2>/dev/null | head -n1)" || return 1
    block_belongs_to_disk "${mount_source%%\[*}" "$disk"
}

target_storage_is_idle() {
    local report="$1" source swap_path descendant_path descendant_type ok=true

    while IFS= read -r source; do
        [ -n "$source" ] || continue
        if storage_path_belongs_to_disk "${source%%\[*}" "$ARCH_LINUX_DISK"; then
            "$report" "Selected disk has a mounted filesystem; unmount it before installation"
            ok=false
        fi
    done < <(findmnt -rn -o SOURCE 2>/dev/null)
    while IFS= read -r swap_path; do
        [ -n "$swap_path" ] || continue
        if storage_path_belongs_to_disk "$swap_path" "$ARCH_LINUX_DISK"; then
            "$report" "Selected disk has active swap; disable it before installation"
            ok=false
        fi
    done < <(swapon --noheadings --raw --show=NAME 2>/dev/null)
    while read -r descendant_path descendant_type; do
        [ -n "$descendant_path" ] || continue
        case "$descendant_type" in
        disk | part) ;;
        *)
            "$report" "Selected disk has an active ${descendant_type:-unknown} holder: ${descendant_path}"
            ok=false
            ;;
        esac
    done < <(lsblk -rpn -o PATH,TYPE -- "$ARCH_LINUX_DISK" 2>/dev/null)
    if [ -e /dev/mapper/cryptroot ] || [ -L /dev/mapper/cryptroot ]; then
        "$report" "The installer mapper name cryptroot is already in use"
        ok=false
    fi
    if findmnt -rn -M /mnt >/dev/null 2>&1; then
        "$report" "The installer mountpoint /mnt is already mounted"
        ok=false
    fi
    [ "$ok" = true ]
}

storage_marker_state() {
    local marker="$1" current_snapshot marker_state marker_snapshot extra

    [ -f "$marker" ] && [ ! -L "$marker" ] && [ -O "$marker" ] || return 1
    [ "$(stat -c '%a' -- "$marker")" = 600 ] || return 1
    read -r marker_state marker_snapshot extra <"$marker" || return 1
    is_choice "$marker_state" intent active || return 1
    [ -z "$extra" ] && [[ "$marker_snapshot" =~ ^[a-f0-9]{64}$ ]] || return 1
    current_snapshot="$(destructive_target_snapshot)" || return 1
    [ "$marker_snapshot" = "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" ] &&
        [ "$current_snapshot" = "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" ] || return 1
    printf '%s\n' "$marker_state"
}

write_storage_marker() {
    local marker="$1" state="$2" candidate

    is_choice "$state" intent active || return 1
    candidate="$(umask 077 && mktemp -- "${marker}.XXXXXXXXXX")" || return 1
    if ! printf '%s %s\n' "$state" "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT" >"$candidate" ||
        ! chmod 0600 -- "$candidate" || ! mv -T -- "$candidate" "$marker"; then
        rm -f -- "$candidate"
        return 1
    fi
}

mark_storage_intent() {
    local marker="$1" candidate

    [ ! -e "$marker" ] && [ ! -L "$marker" ] || return 1
    write_storage_marker "$marker" intent
}

activate_storage_marker() {
    local marker="$1"
    [ "$(storage_marker_state "$marker")" = intent ] || return 1
    write_storage_marker "$marker" active
}

target_mount_tree_is_owned() {
    local source target found=false

    while read -r source target; do
        found=true
        case "$target" in /mnt | /mnt/*) ;; *) return 1 ;; esac
        source="${source%%\[*}"
        storage_path_belongs_to_disk "$source" "$ARCH_LINUX_DISK" || return 1
    done < <(findmnt -Rrn -o SOURCE,TARGET -M /mnt 2>/dev/null)
    [ "$found" = true ]
}

cryptroot_belongs_to_target() {
    local backing

    [ -b /dev/mapper/cryptroot ] || return 1
    backing="$(cryptsetup status -- cryptroot 2>/dev/null | awk '$1 == "device:" { print $2; exit }')" || return 1
    [ "$(block_canonical "$backing")" = "$(block_canonical "$ARCH_LINUX_ROOT_PARTITION")" ]
}

installer_cleanup_created_storage() {
    local cleanup_ok=true marker_state

    if [ -e "$TARGET_MOUNT_MARKER" ] || [ -L "$TARGET_MOUNT_MARKER" ]; then
        marker_state="$(storage_marker_state "$TARGET_MOUNT_MARKER")" || marker_state=''
        if [ -n "$marker_state" ] && ! findmnt -rn -M /mnt >/dev/null 2>&1 &&
            [ "$marker_state" = intent ]; then
            rm -f -- "$TARGET_MOUNT_MARKER"
        elif [ -n "$marker_state" ] && target_mount_tree_is_owned &&
            umount -R -- /mnt && ! findmnt -rn -M /mnt >/dev/null 2>&1; then
            rm -f -- "$TARGET_MOUNT_MARKER"
        else
            log_fail "Refusing to unmount a target tree that is not owned by this installation"
            cleanup_ok=false
        fi
    fi
    if [ -e "$CRYPTROOT_MARKER" ] || [ -L "$CRYPTROOT_MARKER" ]; then
        marker_state="$(storage_marker_state "$CRYPTROOT_MARKER")" || marker_state=''
        if [ -n "$marker_state" ] && [ ! -e /dev/mapper/cryptroot ] &&
            [ ! -L /dev/mapper/cryptroot ] && [ "$marker_state" = intent ]; then
            rm -f -- "$CRYPTROOT_MARKER"
        elif [ -n "$marker_state" ] && cryptroot_belongs_to_target &&
            cryptsetup close -- cryptroot; then
            rm -f -- "$CRYPTROOT_MARKER"
        else
            log_fail "Refusing to close a cryptroot mapper that is not owned by this installation"
            cleanup_ok=false
        fi
    fi
    [ "$cleanup_ok" = true ]
}

validate_properties_with_reporter() {
    local reporter="$1"
    local valid="true"
    local var value

    validate_fail() {
        "$reporter" "$*"
        valid="false"
    }

    [ "${ARCH_LINUX_INSTALLER_CONFIG_VERSION:-}" = '1' ] || validate_fail "ARCH_LINUX_INSTALLER_CONFIG_VERSION must be 1"
    [[ "$ARCH_LINUX_USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]] || validate_fail "ARCH_LINUX_USERNAME must start with a lowercase letter and contain only a-z, 0-9, _ or -"
    [ "${#ARCH_LINUX_USERNAME}" -le 32 ] || validate_fail "ARCH_LINUX_USERNAME must not exceed 32 characters (useradd limit)"
    [[ "$ARCH_LINUX_HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || validate_fail "ARCH_LINUX_HOSTNAME must be a valid single-label hostname"
    [ -n "$ARCH_LINUX_PASSWORD" ] || validate_fail "ARCH_LINUX_PASSWORD must not be empty"

    is_choice "$ARCH_LINUX_FILESYSTEM" btrfs ext4 || validate_fail "ARCH_LINUX_FILESYSTEM must be btrfs or ext4"
    is_choice "$ARCH_LINUX_BOOTLOADER" grub systemd || validate_fail "ARCH_LINUX_BOOTLOADER must be grub or systemd"
    is_choice "${ARCH_LINUX_AUR_HELPER:-none}" paru paru-bin paru-git yay trizen pikaur none || validate_fail "ARCH_LINUX_AUR_HELPER has an unsupported value"
    is_choice "${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER:-none}" mesa intel_i915 nvidia amd ati none || validate_fail "ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER has an unsupported value"
    is_choice "${ARCH_LINUX_GNOME_THEME_PROFILE:-}" stock marble || validate_fail "ARCH_LINUX_GNOME_THEME_PROFILE must be stock or marble"
    is_choice "${ARCH_LINUX_GDM_THEME_PROFILE:-}" stock marble-experimental || validate_fail "ARCH_LINUX_GDM_THEME_PROFILE must be stock or marble-experimental"
    if [ "${ARCH_LINUX_DESKTOP_ENABLED:-false}" = "true" ] && [ "${ARCH_LINUX_GNOME_THEME_PROFILE:-}" = "marble" ]; then
        repository_configuration_ready || validate_fail "Marble is unavailable because its signed repository is not ready; choose Stock"
    fi
    if [ "${ARCH_LINUX_GDM_THEME_PROFILE:-}" = "marble-experimental" ]; then
        [ "${ARCH_LINUX_DESKTOP_ENABLED:-false}" = "true" ] || validate_fail "Marble GDM requires the GNOME desktop"
        [ "${ARCH_LINUX_GNOME_THEME_PROFILE:-}" = "marble" ] || validate_fail "Marble GDM requires the Marble GNOME appearance"
        marble_gdm_configuration_ready || validate_fail "Marble GDM is unavailable while its signed repository is not ready; choose Stock GDM"
    fi
    is_choice "${ARCH_LINUX_MICROCODE:-none}" intel-ucode amd-ucode none || validate_fail "ARCH_LINUX_MICROCODE must be intel-ucode, amd-ucode, none or empty"
    [[ "${ARCH_LINUX_KERNEL}" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] || validate_fail "ARCH_LINUX_KERNEL must be a lowercase package name beginning with a letter or digit"

    # ARCH_LINUX_KERNEL_ARGS is appended into a '|' delimited sed expression (see exec_pacstrap_core).
    # Use a positive allowlist rather than blocklisting '|', '&' and '\': that also rules out
    # newlines and other control characters, which would produce an unterminated sed command.
    # The class covers everything real kernel parameters need, e.g. 'video=HDMI-A-1:1920x1080@60'.
    # Note the bracket-expression ordering: ']' must be first and '-' last to be literal.
    local kernel_args_re='^[]A-Za-z0-9 ._=,:+/@%[-]*$'
    [[ "${ARCH_LINUX_KERNEL_ARGS:-}" =~ $kernel_args_re ]] || validate_fail "ARCH_LINUX_KERNEL_ARGS contains an unsupported character (allowed: letters, digits, space and . _ - = , : + / @ % [ ])"

    local boolean_vars=(
        ARCH_LINUX_BTRFS_SNAPPER_ENABLED
        ARCH_LINUX_BTRFS_ASSISTANT_ENABLED
        ARCH_LINUX_ENCRYPTION_ENABLED
        ARCH_LINUX_DUAL_BOOT_ENABLED
        ARCH_LINUX_CORE_TWEAKS_ENABLED
        ARCH_LINUX_MULTILIB_ENABLED
        ARCH_LINUX_BOOTSPLASH_ENABLED
        ARCH_LINUX_HOUSEKEEPING_ENABLED
        ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED
        ARCH_LINUX_DESKTOP_ENABLED
        ARCH_LINUX_DESKTOP_EXTRAS_ENABLED
        ARCH_LINUX_DESKTOP_SLIM_ENABLED
        ARCH_LINUX_SAMBA_SHARE_ENABLED
        ARCH_LINUX_VM_SUPPORT_ENABLED
        ARCH_LINUX_ECN_ENABLED
    )
    for var in "${boolean_vars[@]}"; do
        value="${!var:-}"
        is_boolean "$value" || validate_fail "$var must be true or false"
    done

    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        [ -n "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT must not be empty when desktop is enabled"
        [[ "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" =~ ^[A-Za-z0-9._+-]+$ ]] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT contains unsafe characters"
        [[ "${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL:-pc105}" =~ ^[A-Za-z0-9._+-]+$ ]] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_MODEL contains unsafe characters"
        [[ "${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT:-}" =~ ^[A-Za-z0-9._+-]*$ ]] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT contains unsafe characters"
        # Written into xkb config and a gsettings string; keep it to a bare layout code
        [[ "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" =~ ^[A-Za-z0-9._-]*$ ]] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND contains unsafe characters"
        [ "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" != "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ] || validate_fail "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND must differ from the first layout"

    fi

    [[ "$ARCH_LINUX_DISK" =~ ^/dev/[A-Za-z0-9._/-]+$ ]] || validate_fail "ARCH_LINUX_DISK must be a /dev path"
    [[ "$ARCH_LINUX_BOOT_PARTITION" =~ ^/dev/[A-Za-z0-9._/-]+$ ]] || validate_fail "ARCH_LINUX_BOOT_PARTITION must be a /dev path"
    [[ "$ARCH_LINUX_ROOT_PARTITION" =~ ^/dev/[A-Za-z0-9._/-]+$ ]] || validate_fail "ARCH_LINUX_ROOT_PARTITION must be a /dev path"

    if [ "$DEBUG" = "false" ]; then
        timezone_path_is_safe "$ARCH_LINUX_TIMEZONE" || validate_fail "ARCH_LINUX_TIMEZONE is not a safe zoneinfo entry on this ISO"

        # Physical identity, partition identity and dual-boot filesystem/size checks are one shared
        # gate here and immediately before the first storage mutation.
        validate_destructive_targets validate_fail || valid="false"
    fi

    timezone_identifier_is_safe "$ARCH_LINUX_TIMEZONE" || validate_fail "ARCH_LINUX_TIMEZONE is not a normalized timezone identifier"
    [[ "$ARCH_LINUX_LOCALE_LANG" =~ ^[A-Za-z0-9_@-]+$ ]] || validate_fail "ARCH_LINUX_LOCALE_LANG contains unsafe characters or must not include .UTF-8"
    [[ "$ARCH_LINUX_VCONSOLE_KEYMAP" =~ ^[A-Za-z0-9._+-]+$ ]] || validate_fail "ARCH_LINUX_VCONSOLE_KEYMAP contains unsafe characters"
    [[ "${ARCH_LINUX_VCONSOLE_FONT:-}" =~ ^[A-Za-z0-9._+-]*$ ]] || validate_fail "ARCH_LINUX_VCONSOLE_FONT contains unsafe characters"
    # Plain spaces only - [:space:] would also admit newlines, and this value is written verbatim
    # into /etc/xdg/reflector/reflector.conf where a newline would forge an extra directive.
    [[ "${ARCH_LINUX_REFLECTOR_COUNTRY:-}" =~ ^[A-Za-z,\ -]*$ ]] || validate_fail "ARCH_LINUX_REFLECTOR_COUNTRY contains unsafe characters"

    # Every locale.gen entry ends up in /etc/locale.gen; reject anything that is not a plain entry
    local locale_entry
    for locale_entry in "${ARCH_LINUX_LOCALE_GEN_LIST[@]}"; do
        locale_entry_is_valid "$locale_entry" || validate_fail "ARCH_LINUX_LOCALE_GEN_LIST contains an invalid entry: '${locale_entry}'"
    done

    [ "$valid" = "true" ]
}

# Silent, non-interactive and non-mutating predicate. User-facing reporting and recovery live in
# validate_properties_or_fix so callers can safely use this function as a boolean gate.
validate_properties() (
    validate_properties_with_reporter :
)

report_invalid_property() {
    log_fail "Invalid property: $*"
    gum_fail "Invalid property: $*"
}

properties_edit_config() {
    print_header "Arch Linux Installer"
    gum_title "Advanced Setup Editor"
    local header_txt="• Save with CTRL + D or ESC and cancel with CTRL + C"
    if ! gum_write --show-line-numbers --prompt "" --height=18 --width=180 --char-limit=0 --header="${header_txt}" --value="$(cat "$SCRIPT_CONFIG")" >"$SCRIPT_CONFIG_TMP_FILE"; then
        rm -f -- "$SCRIPT_CONFIG_TMP_FILE"
        gum_warn "Advanced Setup canceled"
        return 1
    fi
    if ! chmod 600 -- "$SCRIPT_CONFIG_TMP_FILE"; then
        rm -f -- "$SCRIPT_CONFIG_TMP_FILE"
        gum_fail "Could not secure edited properties"
        return 1
    fi
    if ! properties_load "$SCRIPT_CONFIG_TMP_FILE"; then
        rm -f -- "$SCRIPT_CONFIG_TMP_FILE"
        gum_warn "Properties were not saved"
        return 1
    fi
    if ! mv -fT -- "$SCRIPT_CONFIG_TMP_FILE" "$SCRIPT_CONFIG"; then
        rm -f -- "$SCRIPT_CONFIG_TMP_FILE"
        gum_fail "Could not replace ${SCRIPT_CONFIG}"
        return 1
    fi
    gum_info "Properties saved"
    return 0
}

# Interactive wrapper around the pure validate_properties predicate above: on failure it offers to
# fix the offending values right away in the Advanced Setup Editor instead of a hard exit. A fix
# (or a cancel) makes the caller restart the whole properties step from the top so the corrected
# values are shown again before the Summary. Kept separate so validate_properties stays a pure,
# non-interactive predicate (see tests/function-checks.sh).
validate_properties_or_fix() {
    if validate_properties_with_reporter report_invalid_property; then
        if [ "$DEBUG" = true ]; then
            ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT='debug-only'
        else
            ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(destructive_target_snapshot)" || {
                report_invalid_property "Could not capture the accepted destructive target snapshot"
                return 1
            }
        fi
        return 0
    fi

    [ "$FORCE" = "true" ] && exit 130 # Unattended: no prompt to hang on, just exit
    gum_confirm --affirmative="Fix" --negative="Exit" "Open Advanced Setup Editor?" || exit 130

    properties_edit_config || true
    echo && ! gum_spin --title="Reload Properties in 3 seconds..." -- sleep 3 && trap_gum_exit
    return 1 # Restart the whole properties step from the top (see main)
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "$ARCH_LINUX_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Username (lowercase, must start with letter)") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null

        # Validate username: must start with a letter, contain only lowercase letters, digits, underscores, hyphens
        if [[ ! "$user_input" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            gum_confirm --affirmative="Ok" --negative="" "Invalid username! Must start with a lowercase letter and contain only a-z, 0-9, _ or -"
            return 1
        fi

        ARCH_LINUX_USERNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Username" "$ARCH_LINUX_USERNAME"
    return 0
}


# ---------------------------------------------------------------------------------------------------

select_hostname() {
    if [ -z "$ARCH_LINUX_HOSTNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Hostname" --value "arch-linux") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null

        # Validate hostname: must start with a letter or digit, contain only lowercase letters, digits, hyphens
        # Cannot start or end with hyphen, max 63 chars
        if [[ ! "$user_input" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            gum_confirm --affirmative="Ok" --negative="" "Invalid hostname! Must start with letter/digit, contain only a-z, 0-9, or hyphen (-)"
            return 1
        fi

        ARCH_LINUX_HOSTNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Hostname" "$ARCH_LINUX_HOSTNAME"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_password() { # --change
    if [ "$1" = "--change" ] || [ -z "$ARCH_LINUX_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header "+ Enter Password") || trap_gum_exit_confirm
        if [ -z "$user_password" ]; then
            gum_confirm --affirmative="Ok" --negative="" "Password must not be empty"
            return 1
        fi
        user_password_check=$(gum_input --password --header "+ Enter Password again") || trap_gum_exit_confirm
        if [ "$user_password" != "$user_password_check" ]; then
            gum_confirm --affirmative="Ok" --negative="" "The passwords are not identical"
            return 1
        fi
        # Warn (but allow) on weak passwords; user keeps the final say
        if [ "${#user_password}" -lt 8 ] && ! gum_confirm $'Password is shorter than 8 chars.\nUse anyway?'; then
            return 1
        fi
        ARCH_LINUX_PASSWORD="$user_password" && properties_generate # Set value and generate properties file
    fi
    [ "$1" = "--change" ] && gum_info "Password successfully changed"
    [ "$1" != "--change" ] && gum_property "Password" "*******"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_timezone() {
    if [ -z "$ARCH_LINUX_TIMEZONE" ]; then
        local tz_auto user_input
        # Auto-detect timezone via IP (best-effort) to pre-fill the filter
        tz_auto="$(curl --proto '=https' --proto-redir '=https' --silent --show-error \
            --connect-timeout 5 --max-time 5 --max-filesize 1024 -- \
            https://ip-api.com/line?fields=timezone)" || true
        user_input=$(timedatectl list-timezones | gum_filter --value="$tz_auto" --header "+ Choose Timezone") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                          # Check if new value is null
        ARCH_LINUX_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file
    fi
    gum_property "Timezone" "$ARCH_LINUX_TIMEZONE"
    return 0
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2001
select_language() {
    if [ -z "$ARCH_LINUX_LOCALE_LANG" ] || [ -z "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options filter
        # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
        # Add only available locales (!!! intense command !!!)
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        # Select locale
        user_input=$(gum_filter --value="$filter" --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1  # Check if new value is null
        ARCH_LINUX_LOCALE_LANG="$user_input" # Set property
        # Set locale.gen properties (auto generate ARCH_LINUX_LOCALE_GEN_LIST)
        ARCH_LINUX_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            ARCH_LINUX_LOCALE_GEN_LIST+=("$locale_entry")
            # Remove leading # from matched lang in /etc/locale.gen and add entry to array
        done < <(sed "/^#${ARCH_LINUX_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$ARCH_LINUX_LOCALE_LANG")
        # Add en_US fallback (every language) if not already exists in list
        [[ "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_LINUX_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate # Generate properties file (for ARCH_LINUX_LOCALE_LANG & ARCH_LINUX_LOCALE_GEN_LIST)
    fi
    gum_property "Language" "$ARCH_LINUX_LOCALE_LANG"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_keyboard() {
    if [ -z "$ARCH_LINUX_VCONSOLE_KEYMAP" ]; then
        local user_input items options filter
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        [ -z "$filter" ] && filter="us" # Default to 'us' — 'en' maps to euro layout and renders incorrectly in Plymouth
        user_input=$(gum_filter --value="$filter" --header "+ Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                             # Check if new value is null
        ARCH_LINUX_VCONSOLE_KEYMAP="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Keyboard" "$ARCH_LINUX_VCONSOLE_KEYMAP"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_disk() {
    if [ -z "$ARCH_LINUX_DISK" ] || [ -z "$ARCH_LINUX_BOOT_PARTITION" ] || [ -z "$ARCH_LINUX_ROOT_PARTITION" ]; then
        local user_input selected_identity items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -p -n -o PATH,SIZE,MODEL,SERIAL)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        user_input="$(gum_choose --header "+ Choose Disk (path, size, model, serial)" "${options[@]}")" || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        read -r user_input _ <<<"$user_input"
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        user_input="$(block_canonical "$user_input")" || return 1
        selected_identity="$(block_disk_identity "$user_input")" || {
            gum_confirm --affirmative="Ok" --negative="" "Selected disk lacks a stable serial/WWN, model or size identity"
            return 1
        }
        if ! block_identity_is_unique disk "$selected_identity"; then
            gum_confirm --affirmative="Ok" --negative="" "Selected disk identity is ambiguous"
            return 1
        fi
        ARCH_LINUX_DISK="$user_input" # Set property
        ARCH_LINUX_BOOT_PARTITION="$(partition_name "$ARCH_LINUX_DISK" 1)"
        ARCH_LINUX_ROOT_PARTITION="$(partition_name "$ARCH_LINUX_DISK" 2)"
        ARCH_LINUX_DISK_IDENTITY="$selected_identity"
        ARCH_LINUX_BOOT_PARTITION_IDENTITY=''
        ARCH_LINUX_ROOT_PARTITION_IDENTITY=''
        properties_generate # Generate properties file
    fi
    gum_property "Disk" "$ARCH_LINUX_DISK"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_filesystem() {
    if [ -z "$ARCH_LINUX_FILESYSTEM" ]; then
        local user_input options
        options=("btrfs" "ext4")
        user_input=$(gum_choose --header "+ Choose Filesystem (snapshot support: btrfs)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_FILESYSTEM="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Filesystem" "${ARCH_LINUX_FILESYSTEM}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_bootloader() {
    if [ -z "$ARCH_LINUX_BOOTLOADER" ]; then
        local user_input options
        options=("systemd" "grub")
        user_input=$(gum_choose --header "+ Choose Bootloader (snapshot menu: grub)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_BOOTLOADER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Bootloader" "${ARCH_LINUX_BOOTLOADER}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_encryption() {
    if [ -z "$ARCH_LINUX_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable Disk Encryption?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Disk Encryption" "$ARCH_LINUX_ENCRYPTION_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_core_tweaks() {
    if [ -z "$ARCH_LINUX_CORE_TWEAKS_ENABLED" ]; then
        gum_confirm "Enable Core Tweaks?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_CORE_TWEAKS_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Core Tweaks" "$ARCH_LINUX_CORE_TWEAKS_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_bootsplash() {
    if [ -z "$ARCH_LINUX_BOOTSPLASH_ENABLED" ]; then
        gum_confirm "Enable Bootsplash?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Bootsplash" "$ARCH_LINUX_BOOTSPLASH_ENABLED"
    if [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ]; then
        gum_warn "Plymouth may show a black screen on some NVIDIA systems and can hide the LUKS password prompt. Disable Bootsplash if that happens."
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_environment() {
    if [ -z "$ARCH_LINUX_DESKTOP_ENABLED" ]; then
        local user_input
        gum_confirm "Enable GNOME Desktop Environment?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_DESKTOP_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "GNOME Desktop" "$ARCH_LINUX_DESKTOP_ENABLED"
    return 0
}


# ---------------------------------------------------------------------------------------------------

select_gnome_theme_profile() {
    # A TTY install has no theme payload or repository. Persist Stock so generated configs are
    # complete and validation remains a pure enum check without special missing-value branches.
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ]; then
        if [ -z "${ARCH_LINUX_GNOME_THEME_PROFILE:-}" ]; then
            ARCH_LINUX_GNOME_THEME_PROFILE='stock'
            properties_generate
        fi
        return 0
    fi

    if [ -z "${ARCH_LINUX_GNOME_THEME_PROFILE:-}" ]; then
        local user_input options
        options=(
            "stock  - Stock GNOME (default; keeps the current Bibata and extension profile)"
            "marble - Marble blue/filled/dark Shell with Colloid GTK3 and icons"
        )
        user_input=$(gum_choose --header "+ Choose GNOME Appearance (default: Stock)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        ARCH_LINUX_GNOME_THEME_PROFILE="${user_input%% *}"
        properties_generate
    fi

    if [ "$ARCH_LINUX_GNOME_THEME_PROFILE" = "marble" ]; then
        gum_property "GNOME Appearance" "Marble Shell + Colloid GTK3/icons (GTK4/libadwaita CSS stays Stock)"
    else
        gum_property "GNOME Appearance" "Stock"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_gdm_theme_profile() {
    # TTY and Stock GNOME keep the exact existing GDM path and never show another question. Also
    # repair an incompatible persisted value before validation; validate_properties itself remains
    # a pure predicate for callers that do not run the interactive selector flow.
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] || [ "$ARCH_LINUX_GNOME_THEME_PROFILE" != "marble" ]; then
        if [ "${ARCH_LINUX_GDM_THEME_PROFILE:-}" != "stock" ]; then
            ARCH_LINUX_GDM_THEME_PROFILE='stock'
            properties_generate
        fi
        return 0
    fi

    if [ -z "${ARCH_LINUX_GDM_THEME_PROFILE:-}" ]; then
        local user_input options
        options=(
            "stock               - Stock GDM (default)"
            "marble-experimental - Match Marble Shell + Colloid icons (experimental; GNOME 50 only)"
        )
        user_input=$(gum_choose --header "+ Choose GDM Appearance (default: Stock)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        ARCH_LINUX_GDM_THEME_PROFILE="${user_input%% *}"
        properties_generate
    fi

    if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = "marble-experimental" ]; then
        gum_property "GDM Appearance" "Marble Shell + Colloid icons (experimental; GNOME 50 only)"
    else
        gum_property "GDM Appearance" "Stock"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_slim() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ]; then
        if [ "${ARCH_LINUX_DESKTOP_SLIM_ENABLED:-}" != "false" ]; then
            ARCH_LINUX_DESKTOP_SLIM_ENABLED='false'
            properties_generate
        fi
        return 0
    fi
    if [ -z "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" ]; then
        local user_input
        gum_confirm "Enable Desktop Slim Mode? (GNOME Core Apps only)"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_DESKTOP_SLIM_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Desktop Slim Mode" "$ARCH_LINUX_DESKTOP_SLIM_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

# variant_map (layout -> valid variants) is static reference data, see STATIC INPUT VALUES below
select_enable_desktop_keyboard() {
    [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] && return 0
    if [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ]; then
        local layout variant variants
        local layouts=() variant_list=()
        read -ra layouts <<<"$(desktop_keymap_layouts)"
        # Layout filter, pre-filled from the chosen console keymap (e.g. 'de-latin1-...' -> 'de')
        layout=$(gum_filter --value="${ARCH_LINUX_VCONSOLE_KEYMAP%%-*}" --header "+ Choose Desktop Keyboard Layout" "${layouts[@]}") || trap_gum_exit_confirm
        [ -z "$layout" ] && return 1 # Check if new value is null
        ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT="$layout"
        ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=""
        gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
        # Variant filter restricted to the chosen layout; '(none)' = no variant
        variants="${variant_map[$layout]:-}"
        if [ -n "$variants" ]; then
            read -ra variant_list <<<"$variants"
            variant=$(gum_filter --header "+ Choose Desktop Keyboard Variant" "(none)" "${variant_list[@]}") || trap_gum_exit_confirm
            [ "$variant" != "(none)" ] && ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT="$variant"
        fi
        properties_generate
    else
        gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
    fi
    [ -n "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" ] && gum_property "Desktop Keyboard Variant" "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_driver() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] || [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
            local user_input options
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            # nvidia-open only supports Turing (GTX 16xx / RTX 20xx) and newer. Pascal and older
            # need the legacy nvidia-580xx-dkms series from the AUR, which this installer does not
            # set up - warn instead of silently producing a system that boots without acceleration.
            # https://archlinux.org/news/nvidia-590-driver-drops-pascal-support-main-packages-switch-to-open-kernel-modules/
            user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1 # Check if new value is null
            if [ "$user_input" = "nvidia" ] && ! gum_confirm "NVIDIA uses the open kernel modules (Turing / GTX 16xx and newer).
Pascal and older GPUs need the legacy AUR driver, which this installer does not install.
Continue with nvidia-open?"; then
                return 1
            fi
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="$user_input" && properties_generate # Set value and generate properties file
        fi
        gum_property "Desktop Graphics Driver" "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_aur() {
    if [ -z "$ARCH_LINUX_AUR_HELPER" ]; then
        local user_input options
        options=("paru" "paru-bin" "paru-git" "yay" "trizen" "pikaur" "none")
        user_input=$(gum_choose --header "+ Choose AUR Helper (default: paru)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_AUR_HELPER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "AUR Helper" "$ARCH_LINUX_AUR_HELPER"
    if [ "$ARCH_LINUX_AUR_HELPER" = "none" ] && [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        gum_warn "Four required GNOME extensions and Bibata are still installed from AUR; without a helper their future updates are manual."
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_LINUX_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "32 Bit Support" "$ARCH_LINUX_MULTILIB_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_LINUX_HOUSEKEEPING_ENABLED" ]; then
        gum_confirm "Enable Housekeeping?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Housekeeping" "$ARCH_LINUX_HOUSEKEEPING_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_shell_enhancement() {
    if [ -z "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" ]; then
        gum_confirm "Enable Fish + Starship?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Fish + Starship" "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS (SYSTEM TUNING)
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# Everything below is reachable only through the opt-in "System Tuning" step in main. These
# properties all have a working default (from the preset or auto-detection), which is exactly why
# they have no selector in the main flow: the select_* functions above skip once a value is set,
# so a pre-defaulted property could never prompt. Here the opposite is wanted - the user explicitly
# asked to review these - so tune_toggle always asks and pre-selects the current value instead.
#
# Like every select_* function, these MUST be called as 'until <fn>; do :; done'. Bash disables
# 'set -e' inside a function invoked from an until/while condition, which is what makes the
# 'gum_confirm; local rc=$?' idiom safe; calling them bare would abort the installer on a "No".

tune_toggle() {
    local var_name="$1" prompt="$2" label="$3"
    local default_flag="--default=false"
    [ "${!var_name:-false}" = "true" ] && default_flag="--default=true"
    gum_confirm "$default_flag" "$prompt"
    local user_confirm=$?
    [ "$user_confirm" = "130" ] && {
        trap_gum_exit_confirm
        return 1
    }
    local user_input="true"
    [ "$user_confirm" = "1" ] && user_input="false"
    printf -v "$var_name" '%s' "$user_input" && properties_generate # Set value and generate properties file
    gum_property "$label" "${!var_name}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_kernel() {
    local user_input options
    options=("linux-zen" "linux" "linux-lts" "linux-hardened")
    user_input=$(gum_choose --selected="${ARCH_LINUX_KERNEL:-linux-zen}" --header "+ Choose Kernel" "${options[@]}") || trap_gum_exit_confirm
    [ -z "$user_input" ] && return 1                        # Check if new value is null
    ARCH_LINUX_KERNEL="$user_input" && properties_generate # Set value and generate properties file
    gum_property "Kernel" "$ARCH_LINUX_KERNEL"
    return 0
}

# ---------------------------------------------------------------------------------------------------

# Mirror country for reflector (see exec_install_housekeeping). Empty means "all countries".
# 'reflector --list-countries' is the authoritative list and ships on the Arch ISO; its output is
# a 3-column table with a 2-line header. If parsing yields an implausibly short list (or reflector
# is missing, e.g. under DEBUG on a non-Arch host) fall back to free-form entry rather than
# presenting a truncated list the user cannot correct.
select_reflector_country() {
    local user_input countries=()
    if command -v reflector >/dev/null 2>&1; then
        mapfile -t countries < <(reflector --list-countries 2>/dev/null | tail -n +3 | sed -E 's/[[:space:]]{2,}[A-Za-z]{2}[[:space:]]+[0-9]+[[:space:]]*$//; s/[[:space:]]+$//' | grep -E '^[A-Za-z]' || true)
    fi
    if [ "${#countries[@]}" -ge 10 ]; then
        countries=("(all countries)" "${countries[@]}")
        user_input=$(gum_filter --value="${ARCH_LINUX_REFLECTOR_COUNTRY}" --header "+ Choose Mirror Country" "${countries[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        [ "$user_input" = "(all countries)" ] && user_input=""
    else
        user_input=$(gum_input --header "+ Enter Mirror Country (empty = all, comma separated)" --value "${ARCH_LINUX_REFLECTOR_COUNTRY}") || trap_gum_exit_confirm
    fi
    ARCH_LINUX_REFLECTOR_COUNTRY="$user_input" && properties_generate # Set value and generate properties file
    gum_property "Mirror Country" "${ARCH_LINUX_REFLECTOR_COUNTRY:-all}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_dual_boot() {
    tune_toggle ARCH_LINUX_DUAL_BOOT_ENABLED "Install alongside an existing OS? (dual boot: no disk wipe)" "Dual Boot"
}

# ---------------------------------------------------------------------------------------------------

# Dual boot reuses existing partitions, so the disk-derived p1/p2 defaults from select_disk are
# almost always wrong here - on a typical Windows machine p2 is the Windows system partition, which
# would then be formatted. Ask explicitly instead, showing size/filesystem/label so the right ones
# can be told apart. validate_properties still gates the result (ESP must be vfat, root >= 8 GiB).
# When dual boot is switched back off, restore the derived defaults so the two modes stay coherent.
select_dual_boot_partitions() {
    if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" != "true" ]; then
        ARCH_LINUX_BOOT_PARTITION="$(partition_name "$ARCH_LINUX_DISK" 1)"
        ARCH_LINUX_ROOT_PARTITION="$(partition_name "$ARCH_LINUX_DISK" 2)"
        ARCH_LINUX_BOOT_PARTITION_IDENTITY=''
        ARCH_LINUX_ROOT_PARTITION_IDENTITY=''
        properties_generate
        return 0
    fi

    local parts=() boot_input root_input boot_identity root_identity
    mapfile -t parts < <(lsblk -prno NAME,SIZE,FSTYPE,LABEL "$ARCH_LINUX_DISK" 2>/dev/null | tail -n +2)
    if [ "${#parts[@]}" -lt 2 ]; then
        gum_confirm --affirmative="Ok" --negative="" "Disk ${ARCH_LINUX_DISK} has fewer than 2 partitions - create them first, then rerun"
        return 1
    fi

    boot_input=$(gum_choose --header "+ Choose EXISTING EFI partition (will be reused, not formatted)" "${parts[@]}") || trap_gum_exit_confirm
    [ -z "$boot_input" ] && return 1 # Check if new value is null
    root_input=$(gum_choose --header "+ Choose target root partition (WILL BE FORMATTED)" "${parts[@]}") || trap_gum_exit_confirm
    [ -z "$root_input" ] && return 1 # Check if new value is null

    boot_input="${boot_input%% *}" && root_input="${root_input%% *}" # Keep device path only
    if [ "$boot_input" = "$root_input" ]; then
        gum_confirm --affirmative="Ok" --negative="" "EFI and root partition must be different"
        return 1
    fi
    gum_confirm --default=false "Format ${root_input} and erase everything on it?" || return 1

    boot_identity="$(block_partition_identity "$boot_input")" || {
        gum_confirm --affirmative="Ok" --negative="" "EFI partition lacks a stable GPT identity"
        return 1
    }
    root_identity="$(block_partition_identity "$root_input")" || {
        gum_confirm --affirmative="Ok" --negative="" "Root partition lacks a stable GPT identity"
        return 1
    }
    if ! block_identity_is_unique part "$boot_identity" ||
        ! block_identity_is_unique part "$root_identity"; then
        gum_confirm --affirmative="Ok" --negative="" "Selected partition identity is ambiguous"
        return 1
    fi

    ARCH_LINUX_BOOT_PARTITION="$boot_input"
    ARCH_LINUX_ROOT_PARTITION="$root_input"
    ARCH_LINUX_BOOT_PARTITION_IDENTITY="$boot_identity"
    ARCH_LINUX_ROOT_PARTITION_IDENTITY="$root_identity"
    properties_generate # Set values and generate properties file
    gum_property "EFI Partition" "$ARCH_LINUX_BOOT_PARTITION"
    gum_property "Root Partition" "$ARCH_LINUX_ROOT_PARTITION"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_extras() {
    [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] && return 0
    tune_toggle ARCH_LINUX_DESKTOP_EXTRAS_ENABLED "Install desktop extra packages? (codecs, fonts, utils, VPN)" "Desktop Extras"
}

# ---------------------------------------------------------------------------------------------------

select_enable_btrfs_snapper() {
    [ "$ARCH_LINUX_FILESYSTEM" != "btrfs" ] && return 0
    tune_toggle ARCH_LINUX_BTRFS_SNAPPER_ENABLED "Enable BTRFS snapshots? (Snapper)" "BTRFS Snapper"
}

# ---------------------------------------------------------------------------------------------------

select_enable_btrfs_assistant() {
    [ "$ARCH_LINUX_FILESYSTEM" != "btrfs" ] && return 0
    [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] && return 0
    tune_toggle ARCH_LINUX_BTRFS_ASSISTANT_ENABLED "Install BTRFS Assistant? (snapshot GUI)" "BTRFS Assistant"
}

# ---------------------------------------------------------------------------------------------------

select_enable_samba_share() {
    [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] && return 0
    [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" != "true" ] && return 0 # samba only ships with extras
    tune_toggle ARCH_LINUX_SAMBA_SHARE_ENABLED "Enable Samba home & public share?" "Samba Share"
}

# ---------------------------------------------------------------------------------------------------

select_enable_vm_support() {
    tune_toggle ARCH_LINUX_VM_SUPPORT_ENABLED "Install VM guest utilities (when running in a VM)?" "VM Support"
}

# ---------------------------------------------------------------------------------------------------

# Optional second desktop layout, switched with Super+Space or Alt+Shift. Kept in
# System Tuning rather than the main flow because a single layout is the common case. Selecting a
# Russian here is also what enables the verified Ptyxis shortcut alternatives. Ptyxis additionally
# follows the selected ru_RU locale.
select_desktop_keyboard_second() {
    [ "$ARCH_LINUX_DESKTOP_ENABLED" != "true" ] && return 0
    local user_input layouts=()
    read -ra layouts <<<"$(desktop_keymap_layouts)"
    user_input=$(gum_filter --value="${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND}" --header "+ Choose Second Keyboard Layout (optional)" "(none)" "${layouts[@]}") || trap_gum_exit_confirm
    [ -z "$user_input" ] && return 1 # Check if new value is null
    [ "$user_input" = "(none)" ] && user_input=""
    if [ -n "$user_input" ] && [ "$user_input" = "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ]; then
        gum_confirm --affirmative="Ok" --negative="" "Second layout must differ from the first (${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT})"
        return 1
    fi
    ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND="$user_input" && properties_generate # Set value and generate properties file
    gum_property "Second Keyboard Layout" "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-none}"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init_installation() {
    local process_name="Initialize Installation"
    process_init "$process_name"
    (
        process_enter_cgroup
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
        assert_accepted_destructive_target log_fail || exit 1
        # Check installation prerequisites
        [ ! -d /sys/firmware/efi ] && log_fail "BIOS not supported! Please set your boot mode to UEFI." && exit 1
        log_info "UEFI detected"
        bootctl status | grep "Secure Boot" | grep -q "disabled" || { log_fail "You must disable Secure Boot in UEFI to continue installation" && exit 1; }
        log_info "Secure Boot: disabled"
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1
        log_info "Arch ISO detected"
        # Check internet connection (required for keyring update, pacstrap, AUR, ...).
        # Retry to tolerate a slow link or a network coming up late after boot.
        local internet_ok="false"
        for ((i = 1; i < 6; i++)); do
            [ "$i" -gt 1 ] && log_warn "${i}. Retry internet connection check..."
            if curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
                --connect-timeout 5 --max-time 15 -- https://archlinux.org >/dev/null 2>&1; then
                internet_ok="true" && break # Success: break loop
            fi
            sleep 5 # Wait & try again
        done
        [ "$internet_ok" = "false" ] && log_fail "No internet connection. Please connect to the internet and restart the installer." && exit 1
        log_info "Internet connection detected"
        log_info "Waiting for Reflector from Arch ISO..."
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        # Remove a stale pacman lock, but never while a package manager is actually running:
        # deleting a live lock lets two pacman instances corrupt the same database.
        if [ -e /var/lib/pacman/db.lck ]; then
            if pgrep -x pacman &>/dev/null || pgrep -x pacstrap &>/dev/null; then
                log_fail "pacman is currently running - refusing to remove /var/lib/pacman/db.lck" && exit 1
            fi
            log_warn "Removing stale pacman lock /var/lib/pacman/db.lck"
            rm -f -- /var/lib/pacman/db.lck
        fi
        timedatectl set-ntp true     # Set time
        # Temporarily disable ECN for compatibility with routers that mishandle it.
        [ "$ARCH_LINUX_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0
        pacman -Sy --noconfirm archlinux-keyring # Update keyring
        process_return 0
    ) &>"$PROCESS_LOG_TMP_FILE" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_prepare_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        process_enter_cgroup
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Re-prove the complete accepted target, require it to be idle, then reproduce the snapshot
        # once more immediately before the first storage mutation.
        assert_accepted_destructive_target log_fail || {
            log_fail "Refusing to touch ${ARCH_LINUX_DISK}: destructive target changed"
            exit 1
        }
        target_storage_is_idle log_fail || exit 1
        assert_accepted_destructive_target log_fail || exit 1

        # Bind every destructive command to already-open block-device handles. Canonical pathname,
        # major:minor and the accepted physical fingerprint must all agree after open. A later
        # pathname replacement therefore cannot redirect wipefs/sgdisk/mkfs/cryptsetup/mount.
        local target_disk target_boot target_root target_disk_fd target_boot_fd target_root_fd
        local target_disk_handle target_boot_handle target_root_handle cryptroot_fd cryptroot_handle=''
        local bound_boot_identity='' bound_root_identity=''
        target_disk="$(block_canonical "$ARCH_LINUX_DISK")" || exit 1
        target_boot="$(block_canonical "$ARCH_LINUX_BOOT_PARTITION")" || exit 1
        target_root="$(block_canonical "$ARCH_LINUX_ROOT_PARTITION")" || exit 1
        exec {target_disk_fd}<>"$target_disk" || { log_fail "Could not open the accepted disk"; exit 1; }
        target_disk_handle="/proc/${BASHPID}/fd/${target_disk_fd}"
        block_disk_handle_is_bound \
            "$target_disk_handle" "$target_disk" "$ARCH_LINUX_DISK_IDENTITY" || {
            log_fail "Opened disk handle does not match the accepted physical disk"
            exit 1
        }

        if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = true ]; then
            bound_boot_identity="$ARCH_LINUX_BOOT_PARTITION_IDENTITY"
            bound_root_identity="$ARCH_LINUX_ROOT_PARTITION_IDENTITY"
            exec {target_boot_fd}<>"$target_boot" || { log_fail "Could not open the accepted EFI partition"; exit 1; }
            exec {target_root_fd}<>"$target_root" || { log_fail "Could not open the accepted root partition"; exit 1; }
            target_boot_handle="/proc/${BASHPID}/fd/${target_boot_fd}"
            target_root_handle="/proc/${BASHPID}/fd/${target_root_fd}"
            if ! block_partition_handle_is_bound \
                "$target_boot_handle" "$target_boot" "$target_disk" "$bound_boot_identity" ||
                ! block_partition_handle_is_bound \
                    "$target_root_handle" "$target_root" "$target_disk" "$bound_root_identity"; then
                log_fail "Opened dual-boot partition handles do not match the accepted GPT identities"
                exit 1
            fi
        fi

        assert_bound_disk_handle() {
            block_disk_handle_is_bound \
                "$target_disk_handle" "$target_disk" "$ARCH_LINUX_DISK_IDENTITY" || {
                log_fail "Accepted disk handle changed before a destructive operation"
                return 1
            }
        }
        assert_bound_partition_handles() {
            assert_bound_disk_handle || return 1
            if ! block_partition_handle_is_bound \
                "$target_boot_handle" "$target_boot" "$target_disk" "$bound_boot_identity" ||
                ! block_partition_handle_is_bound \
                    "$target_root_handle" "$target_root" "$target_disk" "$bound_root_identity"; then
                log_fail "Accepted partition handle changed before a destructive operation"
                return 1
            fi
        }
        assert_bound_cryptroot_handle() {
            assert_bound_partition_handles || return 1
            if [ -z "$cryptroot_handle" ] ||
                ! block_handle_matches_node "$cryptroot_handle" /dev/mapper/cryptroot ||
                ! cryptroot_belongs_to_target; then
                log_fail "Accepted cryptroot handle changed before a destructive operation"
                return 1
            fi
        }

        # Wipe and create partitions (skip in dual boot mode: keep existing disk layout of the parallel OS)
        if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" != "true" ]; then
            assert_bound_disk_handle && wipefs -af -- "$target_disk_handle"
            assert_bound_disk_handle && sgdisk --zap-all -- "$target_disk_handle"
            assert_bound_disk_handle && sgdisk -o -- "$target_disk_handle"
            assert_bound_disk_handle && sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot \
                --align-end -- "$target_disk_handle"
            assert_bound_disk_handle && sgdisk -n 2:0:0 -t 2:8300 -c 2:root \
                --align-end -- "$target_disk_handle"
            assert_bound_disk_handle && partprobe -- "$target_disk_handle"

            # Wait for udev to materialise the new nodes, then prove they are really the partitions
            # we just created before any mkfs runs against them.
            udevadm settle 2>/dev/null || sleep 2
            local created
            for created in "$target_boot" "$target_root"; do
                [ -b "$created" ] || { log_fail "Expected partition ${created} was not created on ${target_disk}" && exit 1; }
                [ "$(block_type "$created")" = "part" ] || { log_fail "${created} is not a partition after partprobe" && exit 1; }
                [ "$(block_parent "$created")" = "$target_disk" ] || { log_fail "${created} is not on ${target_disk} after partprobe" && exit 1; }
            done
            bound_boot_identity="$(block_partition_identity "$target_boot")" || exit 1
            bound_root_identity="$(block_partition_identity "$target_root")" || exit 1
            exec {target_boot_fd}<>"$target_boot" || { log_fail "Could not open the created EFI partition"; exit 1; }
            exec {target_root_fd}<>"$target_root" || { log_fail "Could not open the created root partition"; exit 1; }
            target_boot_handle="/proc/${BASHPID}/fd/${target_boot_fd}"
            target_root_handle="/proc/${BASHPID}/fd/${target_root_fd}"
            assert_bound_partition_handles || exit 1
        fi

        # Disk encryption
        if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
            assert_bound_partition_handles || exit 1
            log_info "Enable Disk Encryption for ${target_root}"
            printf '%s' "$ARCH_LINUX_PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - -- "$target_root_handle"
            mark_storage_intent "$CRYPTROOT_MARKER" || { log_fail "Could not record cryptroot creation intent"; exit 1; }
            assert_bound_partition_handles || exit 1
            printf '%s' "$ARCH_LINUX_PASSWORD" | cryptsetup open --key-file - -- "$target_root_handle" cryptroot
            cryptroot_belongs_to_target || { log_fail "cryptroot does not map the accepted root partition"; exit 1; }
            exec {cryptroot_fd}<>/dev/mapper/cryptroot || { log_fail "Could not open the accepted cryptroot mapper"; exit 1; }
            cryptroot_handle="/proc/${BASHPID}/fd/${cryptroot_fd}"
            assert_bound_cryptroot_handle || exit 1
            if ! activate_storage_marker "$CRYPTROOT_MARKER"; then
                log_fail "Could not activate cryptroot ownership marker"
                installer_cleanup_created_storage || log_fail "Immediate cryptroot rollback failed"
                exit 1
            fi
        fi

        # Format /boot partition (skip in dual boot mode: reuse existing ESP, keep other OS bootloaders intact)
        [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ] || {
            assert_bound_partition_handles && mkfs.fat -F 32 -n BOOT -- "$target_boot_handle"
        }

        # EXT4
        if [ "$ARCH_LINUX_FILESYSTEM" = "ext4" ]; then
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && {
                assert_bound_cryptroot_handle && mkfs.ext4 -F -L ROOT -- "$cryptroot_handle"
            }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && {
                assert_bound_partition_handles && mkfs.ext4 -F -L ROOT -- "$target_root_handle"
            }

            # Mount disk to /mnt
            mark_storage_intent "$TARGET_MOUNT_MARKER" || { log_fail "Could not record target mount intent"; exit 1; }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && {
                assert_bound_cryptroot_handle && mount -v -- "$cryptroot_handle" /mnt
            }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && {
                assert_bound_partition_handles && mount -v -- "$target_root_handle" /mnt
            }
            if ! activate_storage_marker "$TARGET_MOUNT_MARKER"; then
                log_fail "Could not activate target mount ownership marker"
                installer_cleanup_created_storage || log_fail "Immediate target mount rollback failed"
                exit 1
            fi

            # Mount /boot
            #mount -v --mkdir LABEL=BOOT /mnt/boot
            assert_bound_partition_handles && mount -v --mkdir -- "$target_boot_handle" /mnt/boot
        fi

        # BTRFS
        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && {
                assert_bound_cryptroot_handle && mkfs.btrfs -f -L BTRFS -- "$cryptroot_handle"
            }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && {
                assert_bound_partition_handles && mkfs.btrfs -f -L BTRFS -- "$target_root_handle"
            }

            # Mount disk to /mnt
            mark_storage_intent "$TARGET_MOUNT_MARKER" || { log_fail "Could not record target mount intent"; exit 1; }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && {
                assert_bound_cryptroot_handle && mount -v -- "$cryptroot_handle" /mnt
            }
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && {
                assert_bound_partition_handles && mount -v -- "$target_root_handle" /mnt
            }
            if ! activate_storage_marker "$TARGET_MOUNT_MARKER"; then
                log_fail "Could not activate target mount ownership marker"
                installer_cleanup_created_storage || log_fail "Immediate target mount rollback failed"
                exit 1
            fi

            # Create subvolumes
            btrfs subvolume create -- /mnt/@
            btrfs subvolume create -- /mnt/@home
            btrfs subvolume create -- /mnt/@snapshots
            #local btrfs_root_id
            #btrfs_root_id="$(btrfs subvolume list /mnt | awk '$NF == "@" {print $2}')"
            #btrfs subvolume set-default "${btrfs_root_id}" /mnt # Set @ as default
            umount -R -- /mnt
            rm -f -- "$TARGET_MOUNT_MARKER"

            # Mount subvolumes
            local mount_target
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mount_target="$target_root_handle"
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mount_target="$cryptroot_handle"

            local mount_opts="defaults,noatime,compress=zstd"
            mark_storage_intent "$TARGET_MOUNT_MARKER" || { log_fail "Could not record target remount intent"; exit 1; }
            if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
                assert_bound_cryptroot_handle || exit 1
            else
                assert_bound_partition_handles || exit 1
            fi
            mount --mkdir -t btrfs -o "${mount_opts},subvol=@" -- "${mount_target}" /mnt
            if ! activate_storage_marker "$TARGET_MOUNT_MARKER"; then
                log_fail "Could not activate target remount ownership marker"
                installer_cleanup_created_storage || log_fail "Immediate target remount rollback failed"
                exit 1
            fi
            if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
                assert_bound_cryptroot_handle || exit 1
            else
                assert_bound_partition_handles || exit 1
            fi
            mount --mkdir -t btrfs -o "${mount_opts},subvol=@home" -- "${mount_target}" /mnt/home
            if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
                assert_bound_cryptroot_handle || exit 1
            else
                assert_bound_partition_handles || exit 1
            fi
            mount --mkdir -t btrfs -o "${mount_opts},subvol=@snapshots" -- "${mount_target}" /mnt/.snapshots

            # Mount /boot
            #mount -v --mkdir LABEL=BOOT /mnt/boot
            assert_bound_partition_handles && mount -v --mkdir -- "$target_boot_handle" /mnt/boot

            # Create dirs instead of subvolumes by systemd
            mkdir -p /mnt/var/lib/portables
            mkdir -p /mnt/var/lib/machines
        fi

        # Return
        process_return 0
    ) &>"$PROCESS_LOG_TMP_FILE" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_pacstrap_core() {
    local process_name="Pacstrap Arch Linux Core"
    process_init "$process_name"
    (
        process_enter_cgroup
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Core packages
        local packages=("$ARCH_LINUX_KERNEL" base base-devel linux-firmware mkinitcpio zram-generator networkmanager)

        # Add microcode package
        [ -n "$ARCH_LINUX_MICROCODE" ] && [ "$ARCH_LINUX_MICROCODE" != "none" ] && packages+=("$ARCH_LINUX_MICROCODE")

        # Add filesystem packages
        packages+=(efibootmgr)                                                                      # Required for UEFI on all filesystems
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs)
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && packages+=(inotify-tools)

        # Add grub packages
        [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && packages+=(grub grub-btrfs)

        # Add os-prober for grub dual boot detection (finds parallel OS like Windows)
        [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ] && packages+=(os-prober)

        # Add snapper packages
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BTRFS_SNAPPER_ENABLED" = "true" ] && packages+=(snapper)

        # Create vconsole.conf BEFORE pacstrap (required for mkinitcpio keymap hook during kernel install)
        mkdir -p /mnt/etc
        echo "KEYMAP=$ARCH_LINUX_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
        [ -n "$ARCH_LINUX_VCONSOLE_FONT" ] && echo "FONT=$ARCH_LINUX_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

        # Install core packages and initialize an empty pacman keyring in the target.
        # Retry on transient connection issues; --disable-download-timeout avoids aborts on slow mirrors.
        local pacstrap_failed="true"
        for ((i = 1; i < 6; i++)); do
            [ "$i" -gt 1 ] && log_warn "${i}. Retry Pacstrap installation..."
            if pacstrap -K /mnt "${packages[@]}" --disable-download-timeout; then
                pacstrap_failed="false" && break # Success: break loop
            fi
            sleep 10 # Wait 10 seconds & try again
        done
        if [ "$pacstrap_failed" = "true" ]; then
            echo "ERROR: pacstrap failed to install packages after 5 retries"
            process_return 1 # Writes the result code and exits this subshell
        fi

        # Generate /etc/fstab
        genfstab -U /mnt >/mnt/etc/fstab

        # Set fstab /boot permissions to 0077
        sed -i '/\/boot/ {s/fmask=[0-9]\+/fmask=0077/g; s/dmask=[0-9]\+/dmask=0077/g}' /mnt/etc/fstab

        # Set timezone & system clock
        arch-chroot /mnt ln -sf -- "/usr/share/zoneinfo/${ARCH_LINUX_TIMEZONE}" /etc/localtime
        arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

        { # Create swap (zram-generator with zstd compression)
            # https://wiki.archlinux.org/title/Zram#Using_zram-generator
            echo '[zram0]'
            echo 'zram-size = min(ram / 2, 8192)'
            echo 'compression-algorithm = zstd'
        } >/mnt/etc/systemd/zram-generator.conf

        { # Optimize swap on zram (https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram)
            echo 'vm.swappiness = 180'
            echo 'vm.watermark_boost_factor = 0'
            echo 'vm.watermark_scale_factor = 125'
            echo 'vm.page-cluster = 0'
        } >/mnt/etc/sysctl.d/99-vm-zram-parameters.conf

        # vconsole.conf already created before pacstrap (see above)

        # Set & Generate Locale
        echo "LANG=$(locale_with_utf8 "$ARCH_LINUX_LOCALE_LANG")" >/mnt/etc/locale.conf
        for ((i = 0; i < ${#ARCH_LINUX_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_LINUX_LOCALE_GEN_LIST[$i]}/${ARCH_LINUX_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
        arch-chroot /mnt locale-gen

        # Set hostname & hosts
        echo "$ARCH_LINUX_HOSTNAME" >/mnt/etc/hostname
        {
            echo '# <ip>     <hostname.domain.org>  <hostname>'
            echo '127.0.0.1  localhost.localdomain  localhost'
            echo '::1        localhost.localdomain  localhost'
            echo "127.0.1.1  ${ARCH_LINUX_HOSTNAME}.localdomain  ${ARCH_LINUX_HOSTNAME}"
        } >/mnt/etc/hosts

        # Create initial ramdisk from /etc/mkinitcpio.conf
        # https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
        # https://wiki.archlinux.org/title/Microcode#mkinitcpio
        local btrfs_hook=""

        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && btrfs_hook=' grub-btrfs-overlayfs'
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block sd-encrypt filesystems fsck${btrfs_hook})/" /mnt/etc/mkinitcpio.conf
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block filesystems fsck${btrfs_hook})/" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P

        # KERNEL PARAMETER
        # Zswap is disabled when zram is active so the two compressed swap layers do not compete.
        # Silent boot: https://wiki.archlinux.org/title/Silent_boot
        local kernel_args=(
            'rw'
            'zswap.enabled=0'
            'quiet'
            'vt.global_cursor_default=0'
            'loglevel=3'
            'rd.udev.log_level=3'
            'udev.log_level=3'
            'systemd.show_status=false'
        )
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && kernel_args+=("rd.luks.name=$(blkid -s UUID -o value "${ARCH_LINUX_ROOT_PARTITION}")=cryptroot" "root=/dev/mapper/cryptroot")
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && kernel_args+=("root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_LINUX_ROOT_PARTITION}")")
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && kernel_args+=('rootflags=subvol=@' 'rootfstype=btrfs')
        [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('nowatchdog')
        [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ] && kernel_args+=('splash')
        # Append user-defined extra kernel parameters (joined via ${kernel_args[*]} below)
        [ -n "$ARCH_LINUX_KERNEL_ARGS" ] && kernel_args+=("$ARCH_LINUX_KERNEL_ARGS")

        # SYSTEMD-BOOT INSTALLATION
        if [ "$ARCH_LINUX_BOOTLOADER" = "systemd" ]; then

            # Install Bootloader to /boot (systemdboot). This adds EFI/systemd/ plus the removable
            # fallback EFI/BOOT/BOOTX64.EFI to the existing ESP. Vendor entries such as Windows Boot
            # Manager (EFI/Microsoft/) are left untouched and auto-detected. The firmware fallback
            # path intentionally resolves to this installed systemd-boot image.
            arch-chroot /mnt bootctl --esp-path=/boot install

            # Show boot menu in dual boot mode so the parallel OS can be selected (otherwise boot Arch Linux directly)
            local loader_timeout='0'
            [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ] && loader_timeout='5'

            { # Create Bootloader config
                echo 'default main.conf'
                echo 'console-mode auto'
                echo "timeout ${loader_timeout}"
                echo 'editor no' # Prevent boot parameter editing without authentication
            } >/mnt/boot/loader/loader.conf

            { # Create default boot entry
                echo 'title   Arch Linux'
                echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
                echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}.img"
                echo "options ${kernel_args[*]}"
            } >/mnt/boot/loader/entries/main.conf

            { # Create fallback boot entry
                echo 'title   Arch Linux (Fallback)'
                echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
                echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}-fallback.img"
                echo "options ${kernel_args[*]}"
            } >/mnt/boot/loader/entries/main-fallback.conf

            # Enable service: Auto bootloader update
            arch-chroot /mnt systemctl enable systemd-boot-update.service
        fi

        # ------------------------------------------------------------------

        # GRUB INSTALLATION
        if [ "$ARCH_LINUX_BOOTLOADER" = "grub" ]; then

            # Add kernel args to /etc/default/grub
            local kernel_cmdline="${kernel_args[*]}"
            if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ]; then
                kernel_cmdline="$(grub_unencrypted_kernel_cmdline "${kernel_args[@]}")"
            else
                kernel_cmdline="$(grub_encrypted_kernel_cmdline "${kernel_args[@]}")"
            fi
            sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${kernel_cmdline}\"|" /mnt/etc/default/grub

            # Arch GRUB's 10_linux emits `rw` and the root= argument itself, and for a Btrfs root it
            # also emits rootflags=subvol=<mounted subvolume>. Keep the quiet defaults in their stock
            # GRUB_CMDLINE_LINUX_DEFAULT slot so regeneration cannot duplicate these arguments.
            sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"|' /mnt/etc/default/grub
            if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ]; then
                if grep -q '^#\?GRUB_DISABLE_LINUX_UUID=' /mnt/etc/default/grub; then
                    sed -i 's|^#\?GRUB_DISABLE_LINUX_UUID=.*|GRUB_DISABLE_LINUX_UUID=true|' /mnt/etc/default/grub
                else
                    echo 'GRUB_DISABLE_LINUX_UUID=true' >>/mnt/etc/default/grub
                fi
                if grep -q '^#\?GRUB_DISABLE_LINUX_PARTUUID=' /mnt/etc/default/grub; then
                    sed -i 's|^#\?GRUB_DISABLE_LINUX_PARTUUID=.*|GRUB_DISABLE_LINUX_PARTUUID=false|' /mnt/etc/default/grub
                else
                    echo 'GRUB_DISABLE_LINUX_PARTUUID=false' >>/mnt/etc/default/grub
                fi
            else
                # With an unlocked encrypted root, GRUB_DEVICE is /dev/mapper/cryptroot. Disabling
                # both UUID forms makes 10_linux emit that mapper exactly once instead of adding the
                # decrypted Btrfs UUID alongside the accepted rd.luks.name=/cryptroot contract.
                if grep -q '^#\?GRUB_DISABLE_LINUX_UUID=' /mnt/etc/default/grub; then
                    sed -i 's|^#\?GRUB_DISABLE_LINUX_UUID=.*|GRUB_DISABLE_LINUX_UUID=true|' /mnt/etc/default/grub
                else
                    echo 'GRUB_DISABLE_LINUX_UUID=true' >>/mnt/etc/default/grub
                fi
                if grep -q '^#\?GRUB_DISABLE_LINUX_PARTUUID=' /mnt/etc/default/grub; then
                    sed -i 's|^#\?GRUB_DISABLE_LINUX_PARTUUID=.*|GRUB_DISABLE_LINUX_PARTUUID=true|' /mnt/etc/default/grub
                else
                    echo 'GRUB_DISABLE_LINUX_PARTUUID=true' >>/mnt/etc/default/grub
                fi
            fi

            # Installing GRUB
            # Distinct bootloader-id so a parallel Linux install keeping the generic "GRUB" entry
            # (and its EFI/GRUB directory) is not overwritten in dual boot setups
            arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux

            # Creating grub config file
            sed -i "s/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/" /mnt/etc/default/grub
            # hidden: no GRUB menu or "Booting..." text shown; Shift/Esc still reveals menu within timeout
            # menu: show full GRUB menu (used when no bootsplash, and always in dual boot mode where
            # the menu is the only way to reach the parallel OS)
            if [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ] && [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" != "true" ]; then
                sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=hidden/" /mnt/etc/default/grub
            else
                sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=menu/" /mnt/etc/default/grub
            fi

            # Enable os-prober in dual boot mode so the parallel OS appears in the grub menu
            # (disabled by default since grub 2.06). Rewrite-or-append keeps reruns idempotent.
            if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ]; then
                if grep -q '^#\?GRUB_DISABLE_OS_PROBER=' /mnt/etc/default/grub; then
                    sed -i "s/^#\?GRUB_DISABLE_OS_PROBER=.*$/GRUB_DISABLE_OS_PROBER=false/" /mnt/etc/default/grub
                else
                    echo 'GRUB_DISABLE_OS_PROBER=false' >>/mnt/etc/default/grub
                fi
            fi

            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            # GRUB emits these status lines after leaving its menu. Keep the transition from the
            # firmware/bootloader UI to the quiet kernel or Plymouth free of command-like text.
            sed -i \
                -e "/^[[:space:]]*echo[[:space:]]*'Loading Linux /d" \
                -e "/^[[:space:]]*echo[[:space:]]*'Loading initial ramdisk /d" \
                /mnt/boot/grub/grub.cfg

            # Enable btrfs update service
            [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && arch-chroot /mnt systemctl enable grub-btrfsd.service
        fi

        # Create new user
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_LINUX_USERNAME"

        # Create the initial user directories before any third-party user code runs. Every later
        # write below /home is performed by the target user, never by the privileged installer.
        arch-chroot /mnt install -d -m0700 \
            -o "$ARCH_LINUX_USERNAME" -g "$ARCH_LINUX_USERNAME" \
            "/home/${ARCH_LINUX_USERNAME}/.config" \
            "/home/${ARCH_LINUX_USERNAME}/.local" \
            "/home/${ARCH_LINUX_USERNAME}/.local/share"

        # Validate each private same-directory candidate before its first atomic installation.
        install_validated_sudoers_dropin \
            /mnt 10-installer-wheel '%wheel ALL=(ALL:ALL) ALL'

        # Change passwords
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_LINUX_USERNAME"

        # Enable services
        arch-chroot /mnt systemctl enable NetworkManager                   # Network Manager
        arch-chroot /mnt systemctl enable fstrim.timer                     # SSD support
        arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service # Swap (zram-generator)
        arch-chroot /mnt systemctl enable systemd-oomd.service             # Out of memory killer (swap is required)
        arch-chroot /mnt systemctl enable systemd-timesyncd.service        # Sync time from internet after boot
        [ "$ARCH_LINUX_DESKTOP_ENABLED" = "false" ] && \
            arch-chroot /mnt systemctl set-default multi-user.target

        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
            # Btrfs scrub timer (systemd path escaping: / → -, /.snapshots → .snapshots)
            arch-chroot /mnt systemctl enable btrfs-scrub@-.timer          # /
            arch-chroot /mnt systemctl enable btrfs-scrub@home.timer       # /home
            arch-chroot /mnt systemctl enable btrfs-scrub@.snapshots.timer # /.snapshots
        fi

        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BTRFS_SNAPPER_ENABLED" = "true" ]; then

            # Create snapper config
            arch-chroot /mnt umount -- /.snapshots
            arch-chroot /mnt rm -r -- /.snapshots
            arch-chroot /mnt snapper --no-dbus -c root create-config /
            arch-chroot /mnt btrfs subvolume delete -- /.snapshots
            arch-chroot /mnt mkdir /.snapshots
            arch-chroot /mnt mount -a
            arch-chroot /mnt chmod 750 /.snapshots
            arch-chroot /mnt chown :wheel /.snapshots

            # Modify snapper config
            # https://www.dwarmstrong.org/btrfs-snapshots-rollbacks/
            # /etc/snapper/configs/root

            # Enable snapper services
            arch-chroot /mnt systemctl enable snapper-timeline.timer
            arch-chroot /mnt systemctl enable snapper-cleanup.timer
            arch-chroot /mnt systemctl enable snapper-boot.timer
        fi

        # Make some Arch Linux tweaks
        if [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ]; then

            # Add password feedback through the same fail-closed sudoers boundary.
            install_validated_sudoers_dropin \
                /mnt 20-installer-pwfeedback 'Defaults pwfeedback'

            # Configure pacman parallel downloads, colors, eyecandy
            sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
            sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf

            # Disable watchdog modules
            mkdir -p /mnt/etc/modprobe.d/
            echo 'blacklist sp5100_tco' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf
            echo 'blacklist iTCO_wdt' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf

            # Disable debug packages when using makepkg
            sed -i '/OPTIONS=.*!debug/!s/\(OPTIONS=.*\)debug/\1!debug/' /mnt/etc/makepkg.conf

            # Set max VMAs (need for some apps/games)
            #echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

            # Reduce shutdown timeout
            #sed -i "s/^\s*#\s*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf
        fi

        # Return
        process_return 0
    ) &>"$PROCESS_LOG_TMP_FILE" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_install_desktop() {
    local process_name="GNOME Desktop"
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            local packages=()

            # GNOME base packages. git/base-devel are explicit because four requested extensions
            # and the Bibata cursor package are built through the reviewed AUR helper below.
            packages+=(gnome ptyxis git base-devel)

            # Extension Manager is an application; the other two packages are extensions from the
            # official Extra repository. Keep these outside Desktop Extras so every GNOME install,
            # including slim/extras-off, gets the requested extension profile.
            packages+=(extension-manager gnome-shell-extension-appindicator gnome-shell-extension-caffeine)
            # Marble Shell uses GNOME's official User Themes extension. Keep this Marble-only so
            # Stock GNOME never gains Marble-only packages.
            [ "$ARCH_LINUX_GNOME_THEME_PROFILE" = "marble" ] && packages+=(gnome-shell-extensions)

            # Packages for services enabled below (don't rely on transitive gnome-group deps).
            # pipewire-pulse and wireplumber in particular are NOT pulled by the gnome group
            # (only 'pipewire' is, via mutter), so enabling their units would fail without these.
            packages+=(bluez bluez-utils avahi pipewire pipewire-pulse wireplumber)

            # GNOME desktop extras
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then

                # GNOME base extras (buggy: power-profiles-daemon)
                packages+=(gnome-browser-connector tuned-ppd cups ghostscript gnome-epub-thumbnailer)

                # GNOME wayland screensharing, flatpak & pipewire support
                packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome flatpak-xdg-utils)

                # Audio (Pipewire replacements + session manager): https://wiki.archlinux.org/title/PipeWire#Installation
                # Core pipewire/pipewire-pulse/wireplumber are installed unconditionally above
                packages+=(pipewire-alsa pipewire-jack)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)
                packages+=(sof-firmware) # Need for intel i5 audio

                # Networking & Access
                packages+=(samba rsync gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-dnssd gvfs-wsdd)
                # Supported NetworkManager VPN plugins; PPTP is intentionally outside the contract.
                packages+=(modemmanager network-manager-sstp networkmanager-l2tp networkmanager-vpnc networkmanager-openvpn networkmanager-openconnect networkmanager-strongswan rygel)

                # Kernel headers
                packages+=("${ARCH_LINUX_KERNEL}-headers")

                # Utils (https://wiki.archlinux.org/title/File_systems)
                # Current filesystem and archive utilities from the official repositories.
                packages+=(base-devel archlinux-contrib pacutils fwupd bash-completion inetutils nfs-utils e2fsprogs f2fs-tools udftools dosfstools ntfs-3g exfatprogs btrfs-progs xfsprogs 7zip zip unzip unrar tar wget curl)
                packages+=(nautilus-image-converter)

                # Runtimes, Builder & Helper
                packages+=(gdb python go rust nodejs npm lua cmake jq zenity gum fzf)

                # Certificates
                packages+=(ca-certificates)

                # Codecs (https://wiki.archlinux.org/title/Codecs_and_containers)
                packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader opus speex libvpx libwebp)
                # Codecs not pulled in as a dependency by the stack above
                packages+=(jasper libmad)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-libvpx lib32-libwebp)

                # Optimization (SDL2 is EOL; compatibility packages map SDL2/SDL1.2 APIs onto SDL3)
                packages+=(gamemode sdl3_image sdl2-compat sdl12-compat)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode lib32-sdl2-compat lib32-sdl12-compat)

                # Fonts
                packages+=(ttf-firacode-nerd ttf-nerd-fonts-symbols woff2-font-awesome noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu adobe-source-sans-fonts adobe-source-serif-fonts)

            fi

            # Add btrfs assistant
            [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BTRFS_ASSISTANT_ENABLED" = "true" ] && packages+=(btrfs-assistant)

            # Installing packages together (preventing conflicts e.g.: jack2 and pipewire-jack)
            chroot_pacman_install "${packages[@]}"

            # Project-owned Marble/Colloid packages use the signed native repository and update
            # through ordinary pacman -Syu. This is outside Extras/Slim and never runs for Stock.
            if [ "$ARCH_LINUX_GNOME_THEME_PROFILE" = "marble" ]; then
                chroot_install_marble_profile
            fi

            # These requested extensions are not packaged in the official repositories. Build the
            # current AUR package as the unprivileged user; chroot_aur_install works independently
            # of the optional ARCH_LINUX_AUR_HELPER setting. The root executor installs strictly
            # parsed dependencies before the user build, which receives no sudo authority.
            local aur_extension
            for aur_extension in \
                gnome-shell-extension-dash-to-dock \
                gnome-shell-extension-blur-my-shell \
                gnome-shell-extension-just-perfection-desktop \
                gnome-shell-extension-clipboard-indicator; do
                chroot_aur_install "$aur_extension"
            done
            chroot_aur_install "$BIBATA_CURSOR_AUR_PACKAGE"

            # No Screenshot Box is distributed as a reviewed GNOME Extensions bundle rather than
            # an Arch/AUR package. Install it as the target user so GNOME Shell and Extension
            # Manager own it in the normal per-user location and can update it later.
            chroot_install_no_screenshot_box

            chroot_remove_gnome_console
            desktop_configure_ptyxis_defaults
            desktop_write_ptyxis_keybindings
            desktop_configure_gnome_locale
            desktop_configure_gnome_cursor
            desktop_configure_gnome_extensions

            # Force remove gnome packages
            if [ "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" = "true" ]; then
                chroot_pacman_remove gnome-calendar || true
                chroot_pacman_remove gnome-maps || true
                chroot_pacman_remove gnome-contacts || true
                chroot_pacman_remove gnome-font-viewer || true
                chroot_pacman_remove gnome-characters || true
                chroot_pacman_remove gnome-clocks || true
                chroot_pacman_remove gnome-connections || true
                chroot_pacman_remove gnome-music || true
                chroot_pacman_remove gnome-weather || true
                chroot_pacman_remove gnome-calculator || true
                chroot_pacman_remove gnome-logs || true
                chroot_pacman_remove gnome-text-editor || true
                chroot_pacman_remove gnome-disk-utility || true
                chroot_pacman_remove simple-scan || true
                chroot_pacman_remove baobab || true
                chroot_pacman_remove snapshot || true
                chroot_pacman_remove epiphany || true
                chroot_pacman_remove loupe || true
                chroot_pacman_remove decibels || true
                chroot_pacman_remove showtime || true
                chroot_pacman_remove papers || true
                #chroot_pacman_remove evince || true # Need for sushi
            fi

            # Add user to other useful groups (https://wiki.archlinux.org/title/Users_and_groups#User_groups)
            arch-chroot /mnt groupadd -f plugdev
            arch-chroot /mnt usermod -aG adm,audio,video,optical,input,tty,plugdev "$ARCH_LINUX_USERNAME"

            # Add user to gamemode group
            [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot /mnt gpasswd -a "$ARCH_LINUX_USERNAME" gamemode

            # Set git-credential-libsecret in ~/.gitconfig when the helper is available
            if arch-chroot /mnt test -x /usr/lib/git-core/git-credential-libsecret; then
                arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret
            fi

            # GnuPG integration (https://wiki.archlinux.org/title/GNOME/Keyring#GnuPG_integration)
            printf '%s\n' 'pinentry-program /usr/bin/pinentry-gnome3' | \
                chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/.gnupg/gpg-agent.conf" 0600

            # Set environment
            # shellcheck disable=SC2016
            {
                echo '# SSH AGENT'
                echo 'SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh' # Set gcr sock (https://wiki.archlinux.org/title/GNOME/Keyring#Setup_gcr)
                echo ''
                echo '# PATH'
                echo 'PATH="${PATH}:${HOME}/.local/bin"'
                echo ''
                echo '# XDG'
                echo 'XDG_CONFIG_HOME="${HOME}/.config"'
                echo 'XDG_DATA_HOME="${HOME}/.local/share"'
                echo 'XDG_STATE_HOME="${HOME}/.local/state"'
                echo 'XDG_CACHE_HOME="${HOME}/.cache"'
            } | chroot_user_write_file \
                "/home/${ARCH_LINUX_USERNAME}/.config/environment.d/00-arch.conf" 0644

            # shellcheck disable=SC2016
            {
                echo '# Workaround for Flatpak aliases'
                echo 'PATH="${PATH}:/var/lib/flatpak/exports/bin"'
            } | chroot_user_write_file \
                "/home/${ARCH_LINUX_USERNAME}/.config/environment.d/99-flatpak.conf" 0644

            # Samba
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then

                # Create samba config
                mkdir -p "/mnt/etc/samba/"
                {
                    echo '[global]'
                    echo '   workgroup = WORKGROUP'
                    echo '   server string = Samba Server'
                    echo '   server role = standalone server'
                    echo '   security = user'
                    echo '   map to guest = Bad User'
                    echo '   log file = /var/log/samba/%m.log'
                    echo '   max log size = 50'
                    echo '   client min protocol = SMB2'
                    echo '   server min protocol = SMB2'
                    if [ "$ARCH_LINUX_SAMBA_SHARE_ENABLED" = "true" ]; then
                        echo
                        echo '[homes]'
                        echo '   comment = Home Directory'
                        echo '   browseable = yes'
                        echo '   read only = no'
                        echo '   create mask = 0700'
                        echo '   directory mask = 0700'
                        echo '   valid users = %S'
                        echo
                        echo '[public]'
                        echo '   comment = Public Share'
                        echo '   path = /srv/samba/public'
                        echo '   browseable = yes'
                        echo '   guest ok = yes'
                        echo '   read only = no'
                        echo '   writable = yes'
                        echo '   create mask = 0777'
                        echo '   directory mask = 0777'
                        echo '   force user = nobody'
                        echo '   force group = users'
                    fi
                } >/mnt/etc/samba/smb.conf

                # Test samba config
                arch-chroot /mnt testparm -s /etc/samba/smb.conf

                if [ "$ARCH_LINUX_SAMBA_SHARE_ENABLED" = "true" ]; then

                    # Create samba public dir
                    arch-chroot /mnt mkdir -p /srv/samba/public
                    arch-chroot /mnt chmod 777 /srv/samba/public
                    arch-chroot /mnt chown -R nobody:users /srv/samba/public

                    # Add user as samba user with same password (different user db)
                    (
                        echo "$ARCH_LINUX_PASSWORD"
                        echo "$ARCH_LINUX_PASSWORD"
                    ) | arch-chroot /mnt smbpasswd -s -a "$ARCH_LINUX_USERNAME"
                fi

                # Set IPv4 only for Windows/WS-Discovery (WSDD)
                grep -q -- '-4' /mnt/etc/conf.d/wsdd || sed -i 's/WSDD_PARAMS="/WSDD_PARAMS="-4 /' /mnt/etc/conf.d/wsdd

                # Set IPv4 only for macOS/Bonjour (avahi/mDNS)
                sed -i -E 's/^#?\s*use-ipv6=.*/use-ipv6=no/' /mnt/etc/avahi/avahi-daemon.conf

                # Enable samba services
                arch-chroot /mnt systemctl enable smb.service

                # https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
                arch-chroot /mnt systemctl enable wsdd.service

                # SMB service discovery uses WSDD; nmb.service is outside the supported profile.
            fi

            # Keyboard layout for X11/XWayland clients
            desktop_write_x11_keyboard_config

            # Set GNOME keyboard layout (Wayland uses input-sources, not 00-keyboard.conf).
            # The Latin layout stays first so it is the one active at login.
            local gnome_keyboard_source="$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
            [ -n "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" ] && gnome_keyboard_source="${gnome_keyboard_source}+${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT}"
            local gnome_sources="('xkb', '${gnome_keyboard_source}')"
            [ -n "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" ] && gnome_sources="${gnome_sources}, ('xkb', '${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND}')"
            # Unlike the keybindings below this one is a full replacement on purpose: 'sources' is
            # a list key whose schema default is empty, so there is no stock value to preserve, and
            # the point here is to *define* the layouts the user picked during installation. Do not
            # "fix" this into an additive write.
            {
                echo "# exec_install_desktop | Set GNOME keyboard layout"
                echo "gsettings set org.gnome.desktop.input-sources sources \"[${gnome_sources}]\""
            } | chroot_user_append_file "/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" 0600

            # Bind the layout switch to Alt+Shift when a second layout was chosen, so nothing has to
            # be configured by hand afterwards. GNOME switches input sources itself on Wayland and
            # ignores the xkb grp:* options, so this has to go through wm.keybindings. Both key
            # orders are bound; left modifiers cycle forward, right modifiers cycle backward.
            #
            # These lists are ADDITIVE on purpose. 'gsettings set' replaces the whole array, and the
            # stock values are ['<Super>space','XF86Keyboard'] (and the <Shift> variants backward),
            # so writing only Alt+Shift would silently take Super+Space and the dedicated keyboard
            # key away from the user - something they would then have to restore by hand.
            if [ -n "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" ]; then
                {
                    echo "# exec_install_desktop | Add Alt+Shift as a layout switch, keeping the GNOME defaults"
                    echo "gsettings set org.gnome.desktop.wm.keybindings switch-input-source \"['<Super>space','XF86Keyboard','<Alt>Shift_L','<Shift>Alt_L']\""
                    echo "gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward \"['<Shift><Super>space','<Shift>XF86Keyboard','<Alt>Shift_R','<Shift>Alt_R']\""
                } | chroot_user_append_file "/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" 0600
            fi

            # Enable Arch Linux Desktop services
            arch-chroot /mnt systemctl enable gdm.service       # GNOME
            arch-chroot /mnt systemctl enable bluetooth.service # Bluetooth
            arch-chroot /mnt systemctl enable avahi-daemon      # Network browsing service

            # Extra services
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                arch-chroot /mnt systemctl enable tuned-ppd   # Power daemon (pulls tuned.service via Requires=)
                arch-chroot /mnt systemctl enable cups.socket # Printer
            fi

            # Enable PipeWire, WirePlumber & GCR ssh-agent for all users (sockets follow via 'Also=').
            # systemctl --global writes to /etc/systemd/user and is robust against future unit changes.
            arch-chroot /mnt systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service gcr-ssh-agent.socket

            # Let the login keyring unlock with the GDM password on the required password login.
            # GDM and gnome-keyring already ship the complete policy; verify package ownership and
            # exact records without copying, shadowing or changing either package's files.
            desktop_validate_gdm_keyring_pam

            # Hide unwanted application launchers in the user's own override directory. These
            # writes deliberately run after privilege drop; an AUR-created symlink therefore
            # cannot redirect the installer into a root-owned target.
            local hidden_application
            local hidden_applications=(
                bssh.desktop
                bvnc.desktop
                avahi-discover.desktop
                qv4l2.desktop
                qvidcap.desktop
                lstopo.desktop
                org.gnome.Evince.desktop
            )
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                hidden_applications+=(
                    stoken-gui.desktop
                    stoken-gui-small.desktop
                    cups.desktop
                    tuned-gui.desktop
                    cmake-gui.desktop
                )
            fi
            if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
                hidden_applications+=(fish.desktop)
            fi
            for hidden_application in "${hidden_applications[@]}"; do
                printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Hidden=true' | \
                    chroot_user_write_file \
                        "/home/${ARCH_LINUX_USERNAME}/.local/share/applications/${hidden_application}" \
                        0644
            done

            # Return
            process_return 0
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------

exec_install_graphics_driver() {
    local process_name="Desktop Driver"
    if [ -n "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] && [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" != "none" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case "${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER}" in
            "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
                # Generic open-stack choice: same Mesa capabilities as the amd/ati branches
                # (layers + OpenCL) plus the software rasteriser for GPUs without a native driver.
                local packages=(mesa mesa-utils vkd3d vulkan-tools vulkan-swrast vulkan-mesa-layers opencl-mesa)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-mesa-utils lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
                chroot_pacman_install "${packages[@]}"
                ;;
            "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
                # intel-media-driver is the supported VA-API path for Gen8+ hardware.
                local packages=(vulkan-intel vkd3d intel-media-driver libvpl vpl-gpu-rt vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-vulkan-intel lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
                # nvidia-open (Turing+) is the supported official-repository option. Precompiled
                # nvidia-open
                # only exists for the exact 'linux' package; every other kernel (zen/lts/hardened/
                # custom) needs nvidia-open-dkms, built against its headers.
                local nvidia_pkg="nvidia-open-dkms"
                local packages=("${ARCH_LINUX_KERNEL}-headers" nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
                if [ "$ARCH_LINUX_KERNEL" = "linux" ]; then
                    nvidia_pkg="nvidia-open"
                    packages=(nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
                fi
                packages+=("$nvidia_pkg")
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-nvidia-utils lib32-opencl-nvidia lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
                # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
                #sed -i "s/systemd zswap.enabled=0/systemd nvidia_drm.modeset=1 nvidia_drm.fbdev=1 zswap.enabled=0/g" /mnt/boot/loader/entries/main.conf
                mkdir -p /mnt/etc/modprobe.d/ && echo -e 'options nvidia_drm modeset=1 fbdev=1' >/mnt/etc/modprobe.d/nvidia.conf
                sed -i "s/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf
                # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
                mkdir -p /mnt/etc/pacman.d/hooks/
                {
                    echo "[Trigger]"
                    echo "Operation=Install"
                    echo "Operation=Upgrade"
                    echo "Operation=Remove"
                    echo "Type=Package"
                    echo "Target=${nvidia_pkg}"
                    echo "Target=${ARCH_LINUX_KERNEL}"
                    echo "# Change the linux part above if a different kernel is used"
                    echo ""
                    echo "[Action]"
                    echo "Description=Update NVIDIA module in initcpio"
                    echo "Depends=mkinitcpio"
                    echo "When=PostTransaction"
                    echo "NeedsTargets"
                    echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
                } >/mnt/etc/pacman.d/hooks/nvidia.hook
                # Rebuild initial ram disk
                arch-chroot /mnt mkinitcpio -P
                ;;
            "amd") # https://wiki.archlinux.org/title/AMDGPU#Installation
                # Kernel modesetting with the current Mesa/Vulkan stack is the supported path.
                local packages=(mesa mesa-utils vulkan-radeon vkd3d vulkan-tools vulkan-mesa-layers opencl-mesa)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vulkan-radeon lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
                chroot_pacman_install "${packages[@]}"
                # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
                sed -i "s/^MODULES=(.*)/MODULES=(amdgpu)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "ati") # https://wiki.archlinux.org/title/ATI#Installation
                # Kernel modesetting with the current Mesa/Vulkan stack is the supported path.
                local packages=(mesa mesa-utils vkd3d vulkan-tools vulkan-mesa-layers vulkan-swrast opencl-mesa)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vkd3d lib32-vulkan-mesa-layers lib32-opencl-mesa)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            esac
            process_return 0
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_enable_multilib() {
    local process_name="Enable Multilib"
    if [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
            arch-chroot /mnt pacman -Sy --noconfirm # Sync only — no upgrade on fresh install
            process_return 0
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_bootsplash() {
    local process_name="Bootsplash"
    if [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0                                       # If debug mode then return
            chroot_pacman_install plymouth git base-devel                                              # Install packages (git+base-devel needed for AUR build)
            chroot_aur_install plymouth-theme-archlinux                                                   # Install Arch Linux branded Plymouth theme
            # The reviewed build recipe incorporates the installed Plymouth spinner's current
            # keymap-render.png before package creation, so Qkk remains clean after installation.
            # Insert plymouth hook after 'sd-vconsole' idempotently
            # Must come AFTER keyboard+sd-vconsole (keymap loaded) and BEFORE block+sd-encrypt (passphrase prompt)
            # Note: Arch Linux 'plymouth' package does not ship 'sd-plymouth' hook, only 'plymouth'
            sed -i '/^HOOKS=/{/plymouth/!s/\(sd-vconsole\)/\1 plymouth/}' /mnt/etc/mkinitcpio.conf
            arch-chroot /mnt plymouth-set-default-theme -R archlinux                                      # Set Theme (Arch Linux spinner) & rebuild initram disk
            process_return 0                                                                           # Return
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_aur_helper() {
    local process_name="AUR Helper"
    if [ -n "$ARCH_LINUX_AUR_HELPER" ] && [ "$ARCH_LINUX_AUR_HELPER" != "none" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            chroot_pacman_install git base-devel                 # Install packages
            chroot_aur_install "$ARCH_LINUX_AUR_HELPER"             # Install AUR helper
            # Paru's intended BottomUp/SudoLoop defaults are incorporated before makepkg records
            # the package checksum; no package-owned /etc file is mutated after installation.
            process_return 0 # Return
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_housekeeping() {
    local process_name="Housekeeping"
    if [ "$ARCH_LINUX_HOUSEKEEPING_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0                            # If debug mode then return
            chroot_pacman_install pacman-contrib reflector pkgfile smartmontools irqbalance # Install Base packages
            {                                                                               # Configure reflector service
                echo "# Reflector config for the systemd service"
                echo "--save /etc/pacman.d/mirrorlist"
                [ -n "$ARCH_LINUX_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_LINUX_REFLECTOR_COUNTRY}"
                #echo "--completion-percent 95"
                echo "--protocol https"
                echo "--age 12"
                echo "--latest 10"
                echo "--sort rate"
            } >/mnt/etc/xdg/reflector/reflector.conf
            # Enable services
            arch-chroot /mnt systemctl enable reflector.timer      # Rank mirrors weekly (reflector)
            arch-chroot /mnt systemctl enable paccache.timer       # Discard cached/unused packages weekly (pacman-contrib)
            arch-chroot /mnt systemctl enable pkgfile-update.timer # Pkgfile update timer (pkgfile)
            arch-chroot /mnt systemctl enable smartd               # SMART check service (smartmontools)
            arch-chroot /mnt systemctl enable irqbalance.service   # IRQ balancing daemon (irqbalance)
            process_return 0                                       # Return
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_shell_enhancement() {
    local process_name="Fish + Starship"
    if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            # Keep the enhanced shell deliberately small: one shell, one prompt and its glyph font.
            local packages=(fish starship ttf-nerd-fonts-symbols)
            chroot_pacman_install "${packages[@]}"

            mkdir -p "/mnt/root/.config/fish" "/mnt/root/.config"
            # shellcheck disable=SC2016
            {
                echo 'if status is-interactive'
                echo '    set -g fish_greeting'
                echo '    set -g fish_handle_reflow 1'
                echo '    if not tty | string match -q "/dev/tty*"'
                echo '        starship init fish | source'
                echo '    end'
                echo 'end'
            } >"/mnt/root/.config/fish/config.fish"
            chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/.config/fish/config.fish" 0644 \
                <"/mnt/root/.config/fish/config.fish"

            arch-chroot /mnt chsh -s /usr/bin/fish
            arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_LINUX_USERNAME"

            # Pin the prompt to this installer's own release tag. A local dev build without a
            # published tag falls back to Starship's built-in preset with the same name.
            local starship_root_target='/mnt/root/.config/starship.toml'
            local starship_download="${SCRIPT_TMP_DIR}/starship.toml"
            local starship_sha='b84828d17d7cbe3c614c0b5eb9ee513a734098b131b0fe72e44915f78b6a8cec'
            if curl --proto '=https' --proto-redir '=https' --fail --location --show-error \
                --connect-timeout 5 --max-time 30 --max-filesize 1048576 \
                --output "$starship_download" -- \
                "${UPDATE_REPO_RAW}/${VERSION}/starship.toml" &&
                downloaded_file_is_within_size "$starship_download" 1048576 &&
                [ "$(sha256sum "$starship_download" | awk '{print $1}')" = "$starship_sha" ]; then
                mv -fT -- "$starship_download" "$starship_root_target"
            else
                rm -f -- "$starship_download"
                arch-chroot /mnt /usr/bin/starship preset nerd-font-symbols -o /root/.config/starship.toml
            fi
            chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/.config/starship.toml" 0644 \
                <"$starship_root_target"
            process_return 0
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_vm_support() {
    local process_name="VM Support"
    if [ "$ARCH_LINUX_VM_SUPPORT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            process_enter_cgroup
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case $(systemd-detect-virt || true) in
            kvm)
                log_info "KVM detected"
                chroot_pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
                arch-chroot /mnt systemctl enable qemu-guest-agent
                ;;
            vmware)
                log_info "VMWare Workstation/ESXi detected"
                chroot_pacman_install open-vm-tools
                arch-chroot /mnt systemctl enable vmtoolsd
                arch-chroot /mnt systemctl enable vmware-vmblock-fuse
                ;;
            oracle)
                log_info "VirtualBox detected"
                chroot_pacman_install virtualbox-guest-utils
                arch-chroot /mnt systemctl enable vboxservice
                ;;
            microsoft)
                log_info "Hyper-V detected"
                chroot_pacman_install hyperv
                arch-chroot /mnt systemctl enable hv_fcopy_daemon
                arch-chroot /mnt systemctl enable hv_kvp_daemon
                arch-chroot /mnt systemctl enable hv_vss_daemon
                ;;
            *) log_info "No VM detected" ;; # Do nothing
            esac
            process_return 0 # Return
        ) &>"$PROCESS_LOG_TMP_FILE" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_finalize_arch_linux() {
    local process_name="Finalize Arch Linux"
    process_init "$process_name"
    (
        process_enter_cgroup
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Finalize first-login state entirely as the target user. No privileged process traverses
        # paths that an earlier AUR build could have replaced with symlinks.
        chroot_user_finalize_init

        # Remove orphans and force return true
        local orphan_packages=()
        mapfile -t orphan_packages < <(arch-chroot /mnt pacman -Qtdq 2>/dev/null || true)
        if [ "${#orphan_packages[@]}" -gt 0 ]; then
            arch-chroot /mnt pacman -Rns --noconfirm -- "${orphan_packages[@]}"
        fi

        # Install snapper pacman hook
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BTRFS_SNAPPER_ENABLED" = "true" ] && chroot_pacman_install snap-pac

        # Add pacman btrfs hook (need to place on the end of script)
        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BTRFS_SNAPPER_ENABLED" = "false" ]; then
            # Create pacman hook (auto create snapshot on pre-transaction)
            mkdir -p /mnt/etc/pacman.d/hooks/
            # shellcheck disable=SC2016
            {
                echo '[Trigger]'
                echo 'Operation = Install'
                echo 'Operation = Upgrade'
                echo 'Operation = Remove'
                echo 'Type = Package'
                echo 'Target = *'
                echo ''
                echo '[Action]'
                echo 'Description = Creating BTRFS snapshot'
                echo 'When = PreTransaction'
                #echo 'Exec = /usr/bin/btrfs subvolume snapshot -r / /.snapshots/$(date +%Y-%m-%d_%H-%M-%S)'
                echo 'Exec = /bin/sh -c '\''/usr/bin/btrfs subvolume snapshot -r / /.snapshots/"$(date "+%Y-%m-%d_%H-%M-%S")"'\'''
            } >/mnt/etc/pacman.d/hooks/50-btrfs-snapshot.hook
        fi

        process_return 0 # Return
    ) &>"$PROCESS_LOG_TMP_FILE" &
    process_capture $! "$process_name"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CHROOT HELPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

sudoers_dropin_metadata_is_safe() {
    local candidate="$1" owner group mode links

    [ -f "$candidate" ] && [ ! -L "$candidate" ] || return 1
    read -r owner group mode links < <(stat -c '%u %g %a %h' -- "$candidate") || return 1
    [ "$owner" = 0 ] && [ "$group" = 0 ] && [ "$mode" = 440 ] && [ "$links" = 1 ]
}

sudoers_directory_metadata_is_safe() {
    local directory="$1" owner group mode

    [ -d "$directory" ] && [ ! -L "$directory" ] || return 1
    read -r owner group mode < <(stat -c '%u %g %a' -- "$directory") || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [ "$owner" = 0 ] && [ "$group" = 0 ] && (( (8#$mode & 8#022) == 0 ))
}

install_validated_sudoers_dropin() {
    local target_root="$1" dropin_name="$2" rule="$3"
    local sudoers_dir final_path candidate='' candidate_relative installed_new='false'

    case "${dropin_name}:${rule}" in
    '10-installer-wheel:%wheel ALL=(ALL:ALL) ALL'|'20-installer-pwfeedback:Defaults pwfeedback') ;;
    *) log_fail "Refusing an unreviewed sudoers drop-in"; return 1 ;;
    esac
    [[ "$target_root" == /* && "$target_root" != *'//' && "$target_root" != */../* ]] &&
        [ -d "$target_root" ] && [ ! -L "$target_root" ] || {
        log_fail "Sudoers target root is unsafe"
        return 1
    }
    [ -d "${target_root}/etc" ] && [ ! -L "${target_root}/etc" ] || {
        log_fail "Sudoers target /etc is unsafe"
        return 1
    }
    sudoers_dir="${target_root}/etc/sudoers.d"
    if [ ! -e "$sudoers_dir" ] && [ ! -L "$sudoers_dir" ]; then
        install -d -m0750 -o 0 -g 0 -- "$sudoers_dir" || return 1
    fi
    [ -d "$sudoers_dir" ] && [ ! -L "$sudoers_dir" ] || {
        log_fail "Sudoers drop-in directory is unsafe"
        return 1
    }
    if ! sudoers_directory_metadata_is_safe "$sudoers_dir"; then
        log_fail "Sudoers drop-in directory has unsafe ownership or permissions"
        return 1
    fi
    final_path="${sudoers_dir}/${dropin_name}"
    if [ -e "$final_path" ] || [ -L "$final_path" ]; then
        sudoers_dropin_metadata_is_safe "$final_path" &&
            [ "$(stat -c '%s' -- "$final_path")" -eq $((${#rule} + 1)) ] &&
            [ "$(<"$final_path")" = "$rule" ] || {
            log_fail "Refusing to replace an existing sudoers path: ${dropin_name}"
            return 1
        }
        if ! arch-chroot "$target_root" /usr/bin/env LC_ALL=C visudo -cf \
            "/etc/sudoers.d/${dropin_name}" >/dev/null ||
            ! arch-chroot "$target_root" /usr/bin/env LC_ALL=C visudo -cf /etc/sudoers >/dev/null; then
            log_fail "Existing sudoers policy is invalid"
            return 1
        fi
        return 0
    fi

    arch-chroot "$target_root" /usr/bin/env LC_ALL=C visudo -cf /etc/sudoers >/dev/null || {
        log_fail "Base sudoers policy is invalid"
        return 1
    }
    candidate="$(umask 077 && mktemp -- "${sudoers_dir}/.${dropin_name}.XXXXXXXXXX")" || return 1
    if ! printf '%s\n' "$rule" >"$candidate" ||
        ! chown 0:0 -- "$candidate" || ! chmod 0440 -- "$candidate" ||
        ! sudoers_dropin_metadata_is_safe "$candidate"; then
        rm -f -- "$candidate"
        log_fail "Could not create a safe sudoers candidate"
        return 1
    fi
    candidate_relative="/etc/sudoers.d/${candidate##*/}"
    if ! arch-chroot "$target_root" /usr/bin/env LC_ALL=C visudo -cf \
        "$candidate_relative" >/dev/null; then
        rm -f -- "$candidate"
        log_fail "Generated sudoers candidate is invalid"
        return 1
    fi
    if [ -e "$final_path" ] || [ -L "$final_path" ] ||
        ! mv -T -- "$candidate" "$final_path"; then
        rm -f -- "$candidate"
        log_fail "Could not install sudoers candidate atomically"
        return 1
    fi
    candidate=''
    installed_new='true'
    if ! sudoers_dropin_metadata_is_safe "$final_path" ||
        [ "$(stat -c '%s' -- "$final_path")" -ne $((${#rule} + 1)) ] ||
        [ "$(<"$final_path")" != "$rule" ] ||
        ! arch-chroot "$target_root" /usr/bin/env LC_ALL=C visudo -cf /etc/sudoers >/dev/null; then
        [ "$installed_new" = true ] && rm -f -- "$final_path"
        log_fail "Installed sudoers policy failed final validation"
        return 1
    fi
}

desktop_validate_gdm_keyring_pam() {
    local target_root="${1:-/mnt}"
    local local_file="${target_root}/etc/pam.d/gdm-password"
    local vendor_file="${target_root}/usr/lib/pam.d/gdm-password"
    local module_file="${target_root}/usr/lib/security/pam_gnome_keyring.so"
    local qkk_output owned_output ownership_output active_relative active_file shadow_file before_sha after_sha
    local -a owned_candidates=()

    [ -d "$target_root" ] && [ ! -L "$target_root" ] || {
        log_fail "GDM PAM validation root is not a real directory: ${target_root}"
        return 1
    }
    arch-chroot "$target_root" /usr/bin/env LC_ALL=C pacman -Q -- gdm gnome-keyring >/dev/null || {
        log_fail "GDM PAM packages are not installed"
        return 1
    }
    qkk_output="$(
        arch-chroot "$target_root" /usr/bin/env LC_ALL=C pacman -Qkk -- gdm gnome-keyring 2>&1
    )" || {
        log_fail "GDM or gnome-keyring has an altered package-owned file"
        return 1
    }
    LC_ALL=C awk '
        $1 == "gdm:" || $1 == "gnome-keyring:" {
            package = $1
            sub(/:$/, "", package)
            if (seen[package]++ || $(NF - 2) != "0" || $(NF - 1) != "altered" || $NF != "files") bad = 1
            lines++
            next
        }
        { bad = 1 }
        END { exit (bad || lines != 2 || seen["gdm"] != 1 || seen["gnome-keyring"] != 1) }
    ' <<<"$qkk_output" || {
        log_fail "GDM or gnome-keyring package verification reported a mismatch"
        return 1
    }

    owned_output="$(
        arch-chroot "$target_root" /usr/bin/env LC_ALL=C pacman -Ql -- gdm 2>/dev/null
    )" || {
        log_fail "Could not read the GDM package file list"
        return 1
    }
    mapfile -t owned_candidates < <(
        awk '$1 == "gdm" && ($2 == "/etc/pam.d/gdm-password" || $2 == "/usr/lib/pam.d/gdm-password") { print $2 }' \
            <<<"$owned_output"
    )
    [ "${#owned_candidates[@]}" -eq 1 ] || {
        log_fail "GDM must own exactly one supported gdm-password policy path"
        return 1
    }
    active_relative="${owned_candidates[0]}"
    case "$active_relative" in
    /etc/pam.d/gdm-password)
        active_file="$local_file"
        shadow_file="$vendor_file"
        ;;
    /usr/lib/pam.d/gdm-password)
        active_file="$vendor_file"
        shadow_file="$local_file"
        ;;
    *) return 1 ;;
    esac

    [ -f "$active_file" ] && [ ! -L "$active_file" ] || {
        log_fail "GDM package-owned PAM policy is not a regular file: ${active_file}"
        return 1
    }
    if [ -e "$shadow_file" ] || [ -L "$shadow_file" ]; then
        log_fail "Refusing a shadow GDM PAM policy outside the package-owned path: ${shadow_file}"
        return 1
    fi
    [ -f "$module_file" ] && [ ! -L "$module_file" ] || {
        log_fail "gnome-keyring PAM module is not a regular package file: ${module_file}"
        return 1
    }
    ownership_output="$(
        arch-chroot "$target_root" /usr/bin/env LC_ALL=C pacman -Qo -- /usr/lib/security/pam_gnome_keyring.so
    )" || {
        log_fail "Could not prove ownership of pam_gnome_keyring.so"
        return 1
    }
    grep -Eq '^/usr/lib/security/pam_gnome_keyring\.so is owned by gnome-keyring [^[:space:]]+$' \
        <<<"$ownership_output" || {
        log_fail "pam_gnome_keyring.so is not owned by the installed gnome-keyring package"
        return 1
    }

    before_sha="$(sha256sum "$active_file" | awk '{ print $1 }')" || return 1
    LC_ALL=C awk '
        /^[[:space:]]*(#|$)/ { next }
        $1 == "auth" && $2 == "optional" && $3 == "pam_gnome_keyring.so" {
            auth++
            if (NF != 3) bad = 1
            next
        }
        $1 == "password" && $2 == "optional" && $3 == "pam_gnome_keyring.so" {
            password++
            if (NF != 4 || $4 != "use_authtok") bad = 1
            next
        }
        $1 == "session" && $2 == "optional" && $3 == "pam_gnome_keyring.so" {
            session++
            if (NF != 4 || $4 != "auto_start") bad = 1
            next
        }
        {
            for (field = 1; field <= NF; field++) {
                if ($field == "pam_gnome_keyring.so") bad = 1
            }
        }
        END { exit (bad || auth != 1 || password != 1 || session != 1) }
    ' "$active_file" || {
        log_fail "GDM PAM is missing the exact reviewed gnome-keyring records: ${active_file}"
        return 1
    }
    after_sha="$(sha256sum "$active_file" | awk '{ print $1 }')" || return 1
    [ "$after_sha" = "$before_sha" ] || {
        log_fail "GDM PAM changed during read-only validation: ${active_file}"
        return 1
    }
}

desktop_configure_ptyxis_defaults() {
    mkdir -p /mnt/etc/environment.d /mnt/etc/profile.d /mnt/etc/xdg
    echo 'TERMINAL=ptyxis' >/mnt/etc/environment.d/10-terminal.conf
    printf '%s\n' 'TERMINAL=ptyxis' | \
        chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/.config/environment.d/10-terminal.conf" 0644
    echo 'export TERMINAL=ptyxis' >/mnt/etc/profile.d/terminal.sh
    echo 'org.gnome.Ptyxis.desktop' >/mnt/etc/xdg/xdg-terminals.list
    echo 'org.gnome.Ptyxis.desktop' >/mnt/etc/xdg/gnome-xdg-terminals.list
    printf '%s\n' 'org.gnome.Ptyxis.desktop' | \
        chroot_user_write_file "/home/${ARCH_LINUX_USERNAME}/.config/xdg-terminals.list" 0644

    {
        echo '# desktop_configure_ptyxis_defaults | Set Ptyxis as the only terminal'
        echo "export TERMINAL='ptyxis'"
        echo 'if command -v dbus-update-activation-environment >/dev/null; then'
        echo '    dbus-update-activation-environment --systemd TERMINAL || true'
        echo 'fi'
        echo 'if command -v xdg-mime >/dev/null; then'
        echo "    xdg-mime default 'org.gnome.Ptyxis.desktop' x-scheme-handler/terminal || true"
        echo 'fi'
        echo 'if command -v gsettings >/dev/null; then'
        echo '    if gsettings writable org.gnome.desktop.default-applications.terminal exec >/dev/null 2>&1; then'
        echo "        gsettings set org.gnome.desktop.default-applications.terminal exec 'ptyxis' || true"
        echo '    fi'
        echo '    if gsettings writable org.gnome.desktop.default-applications.terminal exec-arg >/dev/null 2>&1; then'
        echo "        gsettings set org.gnome.desktop.default-applications.terminal exec-arg '' || true"
        echo '    fi'
        echo 'fi'
    } | chroot_user_append_file "/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" 0600
}

chroot_rollback_marble_bootstrap() {
    local repo_created="$1" include_created="$2" key_created="$3"
    local active_repo_preexisting="${4:-false}" key_trusted_this_attempt="${5:-false}"
    local managed_package managed_package_installed='false'
    local repo_file='/mnt/etc/pacman.d/arch-linux-marble-repository.conf'
    local repo_include='Include = /etc/pacman.d/arch-linux-marble-repository.conf'
    local include_begin='# BEGIN arch-linux Marble profile repository'
    local include_end='# END arch-linux Marble profile repository'
    local pacman_tmp=''
    local expected_repo_sha actual_repo_sha expected_include existing_include
    local include_count begin_count end_count status=0
    local repository_server_url repository_primary_fingerprint

    repository_server_url="$(repository_effective_server_url)" || return 1
    repository_primary_fingerprint="$(repository_effective_primary_fingerprint)" || return 1

    # A failed pacman transaction can still have committed one or more requested packages before a
    # later scriptlet/hook failed. Keep trust and the update path if any exact project package is
    # present; removing either would strand root-installed files outside their authenticated repo.
    for managed_package in \
        "$MARBLE_PROFILE_PACKAGE" \
        "$MARBLE_GDM_PACKAGE" \
        arch-linux-keyring \
        arch-linux-marble-shell \
        arch-linux-colloid-gtk3 \
        arch-linux-colloid-icons; do
        if arch-chroot /mnt pacman -Q -- "$managed_package" >/dev/null 2>&1; then
            managed_package_installed='true'
            break
        fi
    done
    # Never preserve a partial import merely because a same-named package predates this attempt.
    # A key created here is retained only after the exact post-lsign trust readback succeeded.
    if [ "$managed_package_installed" = 'true' ] && \
        { [ "$key_created" != 'true' ] || [ "$key_trusted_this_attempt" = 'true' ]; }; then
        log_warn "One or more Marble project packages are installed; retaining their signed repository and key for update or removal"
        return 0
    fi

    if [ "$include_created" = 'true' ]; then
        expected_include="$(printf '%s\n%s\n%s\n' "$include_begin" "$repo_include" "$include_end")"
        include_count="$(grep -Fxc "$repo_include" /mnt/etc/pacman.conf || true)"
        begin_count="$(grep -Fxc "$include_begin" /mnt/etc/pacman.conf || true)"
        end_count="$(grep -Fxc "$include_end" /mnt/etc/pacman.conf || true)"
        existing_include="$(awk -v begin="$include_begin" '
            $0 == begin { print; getline; print; getline; print; exit }
        ' /mnt/etc/pacman.conf)"
        if [ "$include_count" -ne 1 ] || [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ] || \
            [ "$existing_include" != "$expected_include" ]; then
            log_fail "Refusing to remove a Marble repository Include block whose exact content changed"
            # Keep repo/key because a changed Include may still reference them.
            return 1
        fi
        if ! pacman_tmp="$(mktemp -- /mnt/etc/.pacman.conf.marble-rollback.XXXXXXXXXX)"; then
            log_fail "Failed to create a private pacman.conf rollback candidate"
            return 1
        fi
        if awk -v begin="$include_begin" -v end="$include_end" '
            $0 == begin { skipping = 1; next }
            skipping && $0 == end { skipping = 0; next }
            !skipping { print }
            END { if (skipping) exit 1 }
        ' /mnt/etc/pacman.conf >"$pacman_tmp" && \
            chmod --reference=/mnt/etc/pacman.conf -- "$pacman_tmp" && \
            chown --reference=/mnt/etc/pacman.conf -- "$pacman_tmp"; then
            if ! mv -f -- "$pacman_tmp" /mnt/etc/pacman.conf; then
                rm -f -- "$pacman_tmp" || true
                log_fail "Failed to atomically restore pacman.conf while rolling back Marble"
                # Do not remove the still-required repo/key while its Include may remain active.
                return 1
            fi
        else
            rm -f -- "$pacman_tmp" || true
            log_fail "Failed to roll back the Marble repository Include block"
            # Keep the still-signed repo/key rather than strand pacman with an Include that points
            # to a removed file. The caller still fails and the log makes manual recovery explicit.
            return 1
        fi
    fi

    if [ "$repo_created" = 'true' ]; then
        expected_repo_sha="$(
            printf '%s\n[%s]\n%s\nServer = %s\n' \
                '# Managed by arch-linux-installer: Marble profile' \
                "$REPOSITORY_NAME" \
                'SigLevel = PackageRequired DatabaseRequired TrustedOnly' \
                "$repository_server_url" | sha256sum | awk '{print $1}'
        )"
        if [ -f "$repo_file" ] && [ ! -L "$repo_file" ]; then
            actual_repo_sha="$(sha256sum "$repo_file" | awk '{print $1}')"
        else
            actual_repo_sha=''
        fi
        if [ "$actual_repo_sha" = "$expected_repo_sha" ]; then
            if ! rm -f -- "$repo_file"; then
                log_fail "Failed to remove the exact Marble repository file during rollback"
                status=1
            fi
        else
            log_fail "Refusing to remove a Marble repository file whose exact content or type changed"
            status=1
        fi
    fi

    # If an exact repository and Include were already active before this attempt, retain the
    # newly verified key: removing only its trust root would leave every future pacman -Syu unable
    # to synchronize that still-enabled repository. A repo file without a pre-existing Include is
    # inactive; in that case this attempt's Include is removed above and key cleanup stays safe.
    if [ "$key_created" = 'true' ] && [ "$active_repo_preexisting" = 'true' ] && \
        [ "$key_trusted_this_attempt" = 'true' ]; then
        log_warn "Retaining the verified Marble repository key required by the pre-existing active repository"
    elif [ "$key_created" = 'true' ]; then
        if ! arch-chroot /mnt pacman-key --delete "$repository_primary_fingerprint"; then
            log_fail "Failed to remove the Marble repository key imported by this attempt"
            status=1
        fi
    fi
    return "$status"
}

cleanup_repository_key_staging() {
    local key_target_host="${1:-}" key_stage_dir_host="${2:-}"
    local key_target="${3:-unknown}" key_stage_dir="${4:-unknown}"
    local status=0

    if [ -n "$key_target_host" ] && ! rm -f -- "$key_target_host"; then
        log_fail "Failed to remove Marble repository key staging file: ${key_target}"
        status=1
    fi
    # Remove only the exact empty directory created by mktemp. Unknown content is preserved and
    # reported rather than recursively deleting a concurrently changed path.
    if [ -n "$key_stage_dir_host" ] && ! rmdir -- "$key_stage_dir_host"; then
        log_fail "Failed to remove Marble repository key staging directory: ${key_stage_dir}"
        status=1
    fi
    return "$status"
}

chroot_marble_asset_file_exists() {
    local asset_path="${1:-}"

    [ -n "$asset_path" ] || return 1
    # The Shell alias is an absolute path inside the target. Testing /mnt/usr/share/themes/... from
    # the ISO host follows that symlink against the ISO's /usr/share and reports a false negative.
    # Resolve every installed Marble asset in the target mount namespace instead.
    arch-chroot /mnt /usr/bin/test -f "$asset_path"
}

chroot_activate_marble_gdm() {
    # The signed package owns and validates its versioned /usr payload. Keep the installer coupled
    # only to the stable helper/status contract so a future package layout can evolve without
    # breaking older installers. `stock` after reconciliation is the deliberate fail-closed result
    # on an unsupported or changed GNOME platform; foreign/unsafe state makes --status fail.
    local compatibility_helper='/usr/lib/arch-linux-marble-gdm/update-compatibility'
    local activation_status

    arch-chroot /mnt /usr/bin/test -x "$compatibility_helper" || return 1
    arch-chroot /mnt "$compatibility_helper" || return 1
    activation_status="$(arch-chroot /mnt "$compatibility_helper" --status)" || return 1
    case "$activation_status" in
    active) return 0 ;;
    stock)
        log_warn "Marble GDM is installed but inactive on this GNOME build; retaining Stock GDM"
        return 0
        ;;
    *) return 1 ;;
    esac
}

chroot_install_marble_profile() {
    # This helper is called only by the Marble branch inside exec_install_desktop. Keep the trust
    # gate here as well as in validate_properties: installer.conf may have been edited after
    # validation, and no package/database download may happen without every real trust anchor.
    if ! repository_configuration_ready; then
        log_fail "Refusing repository bootstrap: its initial trust configuration is not ready"
        return 1
    fi
    if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = 'marble-experimental' ] && \
        ! marble_gdm_configuration_ready; then
        log_fail "Refusing Marble GDM installation: its signed repository is not ready"
        return 1
    fi

    local marble_packages=("$MARBLE_PROFILE_PACKAGE")
    if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = 'marble-experimental' ]; then
        marble_packages+=("$MARBLE_GDM_PACKAGE")
    fi
    local key_host="${SCRIPT_TMP_DIR}/arch-linux-repository-key.gpg"
    local key_stage_parent='/var/lib'
    local key_stage_parent_host="/mnt${key_stage_parent}"
    local key_stage_dir_host=''
    local key_stage_dir=''
    local key_target_host=''
    local key_target=''
    local key_inspect_home="${SCRIPT_TMP_DIR}/repository-key-inspection"
    local key_metadata
    local repository_server_url repository_public_key_url repository_public_key_sha256
    local repository_primary_fingerprint repository_signing_fingerprint
    local acceptance_ca_target='/etc/ca-certificates/trust-source/anchors/arch-linux-qemu-acceptance.crt'
    local -a marble_pacman=(pacman)
    local repo_file='/mnt/etc/pacman.d/arch-linux-marble-repository.conf'
    local repo_file_tmp=''
    local repo_include='Include = /etc/pacman.d/arch-linux-marble-repository.conf'
    local include_begin='# BEGIN arch-linux Marble profile repository'
    local include_end='# END arch-linux Marble profile repository'
    local pacman_tmp=''
    local expected_repo existing_repo expected_include existing_include config_candidate
    local repo_preexisting='false' include_preexisting='false'
    local repo_created='false' include_created='false' key_created='false' key_trusted_this_attempt='false'
    local include_count include_variant_count begin_count end_count

    repository_server_url="$(repository_effective_server_url)" || return 1
    repository_public_key_url="$(repository_effective_public_key_url)" || return 1
    repository_public_key_sha256="$(repository_effective_public_key_sha256)" || return 1
    repository_primary_fingerprint="$(repository_effective_primary_fingerprint)" || return 1
    repository_signing_fingerprint="$(repository_effective_signing_fingerprint)" || return 1

    expected_repo="$(
        printf '%s\n[%s]\n%s\nServer = %s\n' \
            '# Managed by arch-linux-installer: Marble profile' \
            "$REPOSITORY_NAME" \
            'SigLevel = PackageRequired DatabaseRequired TrustedOnly' \
            "$repository_server_url"
    )"
    expected_include="$(printf '%s\n%s\n%s\n' "$include_begin" "$repo_include" "$include_end")"

    # Preflight every possible conflict before importing or trusting a key. A rerun is accepted only
    # when the existing project-owned file and Include block contain the exact expected values.
    if [ -e "$repo_file" ] || [ -L "$repo_file" ]; then
        if [ ! -f "$repo_file" ] || [ -L "$repo_file" ]; then
            log_fail "Refusing non-regular Marble repository configuration: ${repo_file#/mnt}"
            return 1
        fi
        existing_repo="$(cat -- "$repo_file")"
        if [ "$existing_repo" != "$expected_repo" ]; then
            log_fail "Refusing to overwrite changed or foreign Marble repository configuration"
            return 1
        fi
        repo_preexisting='true'
    fi
    for config_candidate in /mnt/etc/pacman.conf /mnt/etc/pacman.d/*; do
        [ -f "$config_candidate" ] || continue
        [ "$config_candidate" = "$repo_file" ] && continue
        if grep -Eq "^[[:space:]]*\\[${REPOSITORY_NAME}\\][[:space:]]*$" "$config_candidate"; then
            log_fail "Refusing duplicate [${REPOSITORY_NAME}] section in ${config_candidate#/mnt}"
            return 1
        fi
    done
    include_count="$(grep -Fxc "$repo_include" /mnt/etc/pacman.conf || true)"
    include_variant_count="$(
        grep -Ec '^[[:space:]]*Include[[:space:]]*=[[:space:]]*/etc/pacman\.d/arch-linux-marble-repository\.conf[[:space:]]*$' \
            /mnt/etc/pacman.conf || true
    )"
    begin_count="$(grep -Fxc "$include_begin" /mnt/etc/pacman.conf || true)"
    end_count="$(grep -Fxc "$include_end" /mnt/etc/pacman.conf || true)"
    if [ "$include_variant_count" -ne "$include_count" ]; then
        log_fail "Refusing an unmanaged or whitespace-modified Marble repository Include"
        return 1
    fi
    if [ "$include_count" -gt 0 ] || [ "$begin_count" -gt 0 ] || [ "$end_count" -gt 0 ]; then
        if [ "$include_count" -ne 1 ] || [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
            log_fail "Refusing malformed or duplicate Marble repository Include block"
            return 1
        fi
        existing_include="$(awk -v begin="$include_begin" '
            $0 == begin { print; getline; print; getline; print; exit }
        ' /mnt/etc/pacman.conf)"
        if [ "$existing_include" != "$expected_include" ]; then
            log_fail "Refusing changed or foreign Marble repository Include block"
            return 1
        fi
        include_preexisting='true'
    fi
    if [ "$include_preexisting" = 'true' ] && [ "$repo_preexisting" != 'true' ]; then
        log_fail "Refusing a stale Marble repository Include whose configuration file is missing"
        return 1
    fi

    if ! mkdir -p "$key_inspect_home" || ! chmod 0700 "$key_inspect_home"; then
        log_fail "Failed to prepare isolated Marble key inspection directory"
        return 1
    fi
    if ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --retry 3 --connect-timeout 5 --max-time 60 --max-filesize 1048576 \
        --output "$key_host" -- "$repository_public_key_url"; then
        log_fail "Failed to download the immutable Marble repository signing key"
        return 1
    fi
    if ! downloaded_file_is_within_size "$key_host" 1048576 ||
        ! repository_public_key_matches \
            "$key_host" "$key_inspect_home" "$repository_public_key_sha256" \
            "$repository_primary_fingerprint" "$repository_signing_fingerprint"; then
        log_fail "Repository key does not match the initial trust v1 certificate"
        return 1
    fi

    # Reuse an existing key only if it is already the exact trusted certificate. Never delete or
    # alter such a key on rollback. Otherwise import and locally sign this attempt's verified key.
    if key_metadata="$(
        arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg \
            --with-colons --with-subkey-fingerprint --list-keys -- \
            "${repository_primary_fingerprint}!" 2>/dev/null
    )"; then
        if ! repository_key_metadata_matches \
            "$key_metadata" 'trusted' "$(date +%s)" \
            "$repository_primary_fingerprint" "$repository_signing_fingerprint"; then
            log_fail "Existing Marble repository key is not the exact trusted certificate"
            return 1
        fi
        if arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg \
            --list-secret-keys -- "${repository_primary_fingerprint}!" >/dev/null 2>&1; then
            log_fail "Refusing a Marble repository key with secret material in the pacman keyring"
            return 1
        fi
    else
        if ! key_stage_dir_host="$(
            mktemp -d -- "${key_stage_parent_host}/arch-linux-installer-key.XXXXXXXXXX"
        )"; then
            log_fail "Failed to create a root-owned Marble repository key staging directory"
            return 1
        fi
        key_stage_dir="${key_stage_dir_host#/mnt}"
        key_target="${key_stage_dir}/arch-linux-repository-key.gpg"
        key_target_host="/mnt${key_target}"
        if ! install -m0644 -- "$key_host" "$key_target_host"; then
            cleanup_repository_key_staging \
                "$key_target_host" "$key_stage_dir_host" "$key_target" "$key_stage_dir" || true
            log_fail "Failed to stage the verified Marble repository signing key"
            return 1
        fi
        if ! arch-chroot /mnt pacman-key --add "$key_target"; then
            if arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg \
                --list-keys -- "$repository_primary_fingerprint" >/dev/null 2>&1; then
                key_created='true'
            fi
            cleanup_repository_key_staging \
                "$key_target_host" "$key_stage_dir_host" "$key_target" "$key_stage_dir" || true
            log_fail "Failed to import the verified Marble repository signing key"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        key_created='true'
        if ! arch-chroot /mnt pacman-key --lsign-key "$repository_primary_fingerprint"; then
            cleanup_repository_key_staging \
                "$key_target_host" "$key_stage_dir_host" "$key_target" "$key_stage_dir" || true
            log_fail "Failed to locally trust the verified Marble repository signing key"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        if ! cleanup_repository_key_staging \
            "$key_target_host" "$key_stage_dir_host" "$key_target" "$key_stage_dir"; then
            log_fail "Failed to clean the Marble repository key staging boundary"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
    fi

    if ! arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg --check-trustdb >/dev/null 2>&1 || \
        ! key_metadata="$(
            arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg \
                --with-colons --with-subkey-fingerprint --list-keys -- \
                "${repository_primary_fingerprint}!" 2>/dev/null
        )"; then
        log_fail "Trusted Marble repository key cannot be read back"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if ! repository_key_metadata_matches \
        "$key_metadata" 'trusted' "$(date +%s)" \
        "$repository_primary_fingerprint" "$repository_signing_fingerprint"; then
        log_fail "Marble repository key failed post-trust exact keyblock verification"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if arch-chroot /mnt gpg --batch --homedir /etc/pacman.d/gnupg \
        --list-secret-keys -- "${repository_primary_fingerprint}!" >/dev/null 2>&1; then
        log_fail "Marble repository secret material appeared in the pacman keyring"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    key_trusted_this_attempt='true'

    if [ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = 'true' ]; then
        repository_qemu_acceptance_configuration_is_valid \
            "$repository_server_url" "$repository_public_key_url" \
            "$repository_public_key_sha256" "$repository_primary_fingerprint" \
            "$repository_signing_fingerprint" "$QEMU_ACCEPTANCE_REPOSITORY_CA_FILE" \
            "$QEMU_ACCEPTANCE_REPOSITORY_CA_SHA256" || return 1
        install -Dm0644 -- "$QEMU_ACCEPTANCE_REPOSITORY_CA_FILE" \
            "/mnt${acceptance_ca_target}" || return 1
        arch-chroot /mnt /usr/bin/update-ca-trust || return 1
        marble_pacman=(
            /usr/bin/env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
            /usr/bin/pacman
        )
    fi

    if ! mkdir -p /mnt/etc/pacman.d; then
        log_fail "Failed to prepare the Marble pacman repository directory"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if [ "$repo_preexisting" != 'true' ]; then
        if ! repo_file_tmp="$(mktemp -- /mnt/etc/pacman.d/.arch-linux-marble-repository.conf.XXXXXXXXXX)"; then
            log_fail "Failed to create a private repository configuration candidate"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        if ! printf '%s\n' "$expected_repo" >"$repo_file_tmp" || \
            ! chmod 0644 "$repo_file_tmp" || ! chown root:root "$repo_file_tmp" || \
            ! mv -fT -- "$repo_file_tmp" "$repo_file"; then
            rm -f -- "$repo_file_tmp"
            log_fail "Failed to install Marble pacman repository configuration"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        repo_created='true'
    fi
    if [ "$include_preexisting" != 'true' ]; then
        if ! pacman_tmp="$(mktemp -- /mnt/etc/.pacman.conf.marble-new.XXXXXXXXXX)"; then
            log_fail "Failed to create a private pacman.conf candidate"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        if ! cp -p -- /mnt/etc/pacman.conf "$pacman_tmp" || \
            ! printf '\n%s\n' "$expected_include" >>"$pacman_tmp" || \
            ! mv -fT -- "$pacman_tmp" /mnt/etc/pacman.conf; then
            rm -f -- "$pacman_tmp"
            log_fail "Failed to install Marble repository Include block"
            chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
            return 1
        fi
        include_created='true'
    fi

    # Adding a repository requires a database refresh. Upgrade the fresh target at the same time;
    # pacman -Sy followed by a package install would create an unsupported partial-upgrade state.
    local install_failed='true' i
    for ((i = 1; i < 4; i++)); do
        [ "$i" -gt 1 ] && log_warn "${i}. Retry signed Marble package installation..."
        if arch-chroot /mnt "${marble_pacman[@]}" \
            -Syu --noconfirm --needed --disable-download-timeout \
            "${marble_packages[@]}"; then
            install_failed='false'
            break
        fi
        sleep 10
    done
    if [ "$install_failed" = 'true' ]; then
        log_fail "Failed to install the signed Marble profile package"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi

    if ! arch-chroot /mnt pacman -Q -- "$MARBLE_PROFILE_PACKAGE" >/dev/null; then
        log_fail "Signed Marble profile package is missing after installation"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = 'marble-experimental' ] && \
        ! arch-chroot /mnt pacman -Q -- "$MARBLE_GDM_PACKAGE" >/dev/null; then
        log_fail "Signed Marble GDM package is missing after installation"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if ! arch-chroot /mnt /usr/lib/arch-linux-marble-profile/update-compatibility; then
        log_fail "Marble profile compatibility validation failed"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if [ -f /mnt/etc/dconf/db/local.d/05-arch-linux-marble-profile ] && \
        ! chroot_marble_asset_file_exists "/usr/share/themes/${MARBLE_SHELL_THEME}/gnome-shell/gnome-shell.css"; then
        log_fail "Marble Shell theme is missing after compatibility activation: ${MARBLE_SHELL_THEME}"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if ! chroot_marble_asset_file_exists "/usr/share/themes/${MARBLE_GTK_THEME}/gtk-3.0/gtk.css"; then
        log_fail "Marble GTK3 theme is missing after package installation: ${MARBLE_GTK_THEME}"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if ! chroot_marble_asset_file_exists "/usr/share/icons/${MARBLE_ICON_THEME}/index.theme"; then
        log_fail "Marble icon theme is missing after package installation: ${MARBLE_ICON_THEME}"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
    if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = 'marble-experimental' ] && \
        ! chroot_activate_marble_gdm; then
        log_fail "Marble GDM compatibility activation or stable status verification failed"
        # The package helper removes only its exact managed symlink. If status found foreign state
        # it remains untouched, while this install still fails closed.
        arch-chroot /mnt /usr/lib/arch-linux-marble-gdm/update-compatibility --remove || \
            log_warn "Marble GDM activation could not be rolled back automatically"
        chroot_rollback_marble_bootstrap "$repo_created" "$include_created" "$key_created" "$include_preexisting" "$key_trusted_this_attempt" || true
        return 1
    fi
}

chroot_install_no_screenshot_box() {
    local archive_host="${SCRIPT_TMP_DIR}/no-screenshot-box-v6.shell-extension.zip"
    # arch-chroot deliberately mounts a private tmpfs on /tmp, so a file copied to /mnt/tmp is
    # hidden from commands inside the chroot. Stage the reviewed bundle in an atomically-created,
    # root-owned directory under /var/lib instead. The target user may read the public bundle but
    # cannot replace it between checksum verification and gnome-extensions extraction.
    local archive_stage_parent='/var/lib'
    local archive_stage_parent_host="/mnt${archive_stage_parent}"
    local installed_uuid

    if ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --retry 3 --connect-timeout 5 --max-time 60 --max-filesize 5242880 \
        --output "$archive_host" -- "$NO_SCREENSHOT_BOX_ARCHIVE_URL"; then
        log_fail "Failed to download No Screenshot Box v6"
        return 1
    fi
    if ! downloaded_file_is_within_size "$archive_host" 5242880 ||
        [ "$(sha256sum "$archive_host" | awk '{print $1}')" != "$NO_SCREENSHOT_BOX_ARCHIVE_SHA256" ]; then
        log_fail "No Screenshot Box v6 checksum mismatch"
        return 1
    fi

    # gnome-extensions performs safe extraction, validates metadata, moves the result into
    # XDG_DATA_HOME/gnome-shell/extensions and compiles any schemas with --strict. Explicit XDG
    # paths prevent the Arch ISO root environment from leaking into the target user's install.
    if ! installed_uuid="$(
        local archive_stage_dir_host='' archive_stage_dir='' archive_target_host='' archive_target=''
        local cleanup_status=0

        # shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap below.
        _no_screenshot_box_remove_staging() {
            if [ -n "$archive_target_host" ] && ! rm -f -- "$archive_target_host"; then
                printf 'Failed to remove No Screenshot Box staging file: %s\n' "$archive_target" >&2
                cleanup_status=1
            fi
            if [ -n "$archive_stage_dir_host" ] && ! rmdir -- "$archive_stage_dir_host"; then
                printf 'Failed to remove No Screenshot Box staging directory: %s\n' "$archive_stage_dir" >&2
                cleanup_status=1
            fi
            [ "$cleanup_status" -eq 0 ] || exit 1
        }
        trap _no_screenshot_box_remove_staging EXIT

        archive_stage_dir_host="$(
            mktemp -d -- "${archive_stage_parent_host}/arch-linux-installer.XXXXXXXXXX"
        )" || exit 1
        archive_stage_dir="${archive_stage_dir_host#/mnt}"
        archive_target="${archive_stage_dir}/no-screenshot-box-v6.shell-extension.zip"
        archive_target_host="/mnt${archive_target}"
        install -m0644 -- "$archive_host" "$archive_target_host" || exit 1
        chmod 0755 -- "$archive_stage_dir_host" || exit 1
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- \
            env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
            HOME="/home/${ARCH_LINUX_USERNAME}" \
            XDG_DATA_HOME="/home/${ARCH_LINUX_USERNAME}/.local/share" \
            XDG_CACHE_HOME="/home/${ARCH_LINUX_USERNAME}/.cache" \
            gnome-extensions install --force --print-uuid "$archive_target" || exit 1
    )"; then
        log_fail "Failed to install No Screenshot Box v6"
        return 1
    fi

    if [ "$installed_uuid" != "$NO_SCREENSHOT_BOX_UUID" ]; then
        log_fail "No Screenshot Box bundle UUID mismatch: ${installed_uuid:-empty}"
        return 1
    fi
}

desktop_configure_gnome_locale() {
    # GNOME 50 stores the user's Formats choice in org.gnome.system.locale::region. LANG already
    # makes the first session use these formats; the user-level value also makes the Settings row
    # explicit. Do not make this a system dconf default: GNOME resets region when Language changes,
    # and an underlying non-empty system default would then incorrectly restore the install locale.
    local gnome_region
    gnome_region="$(locale_with_utf8 "$ARCH_LINUX_LOCALE_LANG")"
    {
        echo '# desktop_configure_gnome_locale | Match GNOME Formats to the selected language'
        printf "gsettings set org.gnome.system.locale region '%s'\n" "$gnome_region"
    } | chroot_user_append_file "/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" 0600
}

desktop_configure_gnome_cursor() {
    if [ ! -d "/mnt/usr/share/icons/${BIBATA_CURSOR_THEME}/cursors" ]; then
        log_fail "Bibata cursor theme is missing after AUR installation: ${BIBATA_CURSOR_THEME}"
        return 1
    fi
    mkdir -p /mnt/etc/dconf/db/local.d
    {
        echo '[org/gnome/desktop/interface]'
        printf "cursor-theme='%s'\n" "$BIBATA_CURSOR_THEME"
    } >/mnt/etc/dconf/db/local.d/06-cursor
}

desktop_configure_gnome_extensions() {
    mkdir -p /mnt/etc/dconf/profile /mnt/etc/dconf/db/local.d
    {
        echo 'user-db:user'
        echo 'system-db:local'
    } >/mnt/etc/dconf/profile/user
    {
        echo '[org/gnome/shell]'
        echo "enabled-extensions=['dash-to-dock@micxgx.gmail.com','blur-my-shell@aunetx','just-perfection-desktop@just-perfection','appindicatorsupport@rgcjonas.gmail.com','clipboard-indicator@tudmotu.com','caffeine@patapon.info','no-screenshot-box@screenshot']"
    } >/mnt/etc/dconf/db/local.d/00-extensions

    # Compile system defaults before the first login. Do not add dconf locks: Extension Manager
    # must remain able to disable or reconfigure every extension for the user.
    arch-chroot /mnt dconf update
}

# X11/XWayland keyboard layout. GNOME runs on Wayland by default, but XWayland clients still read
# this file. The GNOME compositor layout is configured separately through gsettings below.
desktop_write_x11_keyboard_config() {
    mkdir -p /mnt/etc/X11/xorg.conf.d/
    {
        echo 'Section "InputClass"'
        echo '    Identifier "system-keyboard"'
        echo '    MatchIsKeyboard "yes"'
        echo '    Option "XkbLayout" "'"$(desktop_keyboard_layouts)"'"'
        echo '    Option "XkbModel" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL}"'"'
        echo '    Option "XkbVariant" "'"$(desktop_keyboard_variants)"'"'
        [ -n "${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND:-}" ] && echo '    Option "XkbOptions" "grp:alt_shift_toggle"'
        echo 'EndSection'
    } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf
}

# Ptyxis application shortcuts break under a non-Latin layout: pressing the physical C key emits a
# Cyrillic keysym, so ctrl+shift+c no longer matches a binding defined in terms of the character
# "c". GTK alternative triggers preserve the Latin shortcut and add its Russian-layout keysym.
desktop_write_ptyxis_keybindings() {
    needs_ptyxis_russian_shortcuts || return 0

    # Ptyxis stores GTK shortcut trigger strings in dconf. Keep every Latin trigger and add the
    # equivalent Cyrillic keysym used by the Russian ЙЦУКЕН layout. These are the values
    # verified against Ubuntu's live Ptyxis 50.1 schema and remain editable system defaults.
    mkdir -p /mnt/etc/dconf/db/local.d
    {
        echo '[org/gnome/Ptyxis/Shortcuts]'
        echo "copy-clipboard='<Control><Shift>c|<Control><Shift>Cyrillic_es'"
        echo "paste-clipboard='<Control><Shift>v|<Control><Shift>Cyrillic_em'"
        echo "new-tab='<ctrl><shift>t|<ctrl><shift>Cyrillic_ie'"
        echo "new-window='<ctrl><shift>n|<ctrl><shift>Cyrillic_te'"
        echo "close-tab='<ctrl><shift>w|<ctrl><shift>Cyrillic_tse'"
        echo "close-window='<ctrl><shift>q|<ctrl><shift>Cyrillic_shorti'"
        echo "search='<ctrl><shift>f|<ctrl><shift>Cyrillic_a'"
        echo "select-all='<ctrl><shift>a|<ctrl><shift>Cyrillic_ef'"
        echo "tab-overview='<ctrl><shift>o|<ctrl><shift>Cyrillic_shcha'"
        echo "preferences='<ctrl>comma|<ctrl>Cyrillic_be'"
        echo "tab-menu='<alt>comma|<alt>Cyrillic_be'"
        echo "undo-close-tab='<ctrl><shift><alt>t|<ctrl><shift><alt>Cyrillic_ie'"
    } >/mnt/etc/dconf/db/local.d/10-ptyxis-shortcuts

    # Do not bind Alt+V as a Ptyxis application action: on native Linux it is not the normal paste
    # shortcut, and intercepting it here would prevent terminal TUIs from receiving the key event.
}

chroot_remove_gnome_console() {
    # The Arch 'gnome' group includes GNOME Console. Remove it after group installation so Ptyxis
    # is the sole terminal, but query first so an absent package is not reported as an error.
    arch-chroot /mnt pacman -Qq gnome-console &>/dev/null || return 0
    chroot_pacman_remove gnome-console
}

chroot_pacman_install() {
    local packages=("$@")
    local pacman_failed="true"
    # Retry installing packages 5 times (in case of connection issues)
    for ((i = 1; i < 6; i++)); do
        # Print log if greater than first try
        [ "$i" -gt 1 ] && log_warn "${i}. Retry Pacman installation..."
        # Try installing packages
        # if ! arch-chroot /mnt bash -c "yes | LC_ALL=en_US.UTF-8 pacman -S --needed --disable-download-timeout ${packages[*]}"; then
        if ! arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout -- "${packages[@]}"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            pacman_failed="false" && break # Success: break loop
        fi
    done
    # Result
    [ "$pacman_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$pacman_failed" = "false" ] && return 0 # Success
}

AUR_BUILD_SEQUENCE=0
AUR_ACTIVE_BUILDER_UID=''
AUR_ACTIVE_BUILDER_HOME=''
AUR_ACTIVE_BUILDER_USER=''

aur_builder_uid_has_live_process() {
    local expected_uid="$1" status_file process_uid
    [[ "$expected_uid" =~ ^[0-9]+$ ]] || return 0
    for status_file in /proc/[0-9]*/status; do
        [ -r "$status_file" ] || continue
        process_uid="$(awk '$1 == "Uid:" { print $2; exit }' "$status_file" 2>/dev/null)" || continue
        [ "$process_uid" != "$expected_uid" ] || return 0
    done
    return 1
}

# A plain `find /mnt -xdev` cannot see the parent filesystem below a nested target mount and also
# skips the nested filesystem itself. Inspect every target-backed filesystem through a separate,
# non-recursive bind view instead. Read-only views are used for assertions; the cleanup mode is the
# only writer and may remove only inodes owned by the exact disposable UID. The public wrappers
# below additionally bind this low-level mechanism to the accepted /mnt mount tree.
aur_builder_owned_inode_is_confined() {
    local scan_mount="$1" home_mount="$2" logical_path="$3" home_host="$4"
    [ -n "$scan_mount" ] && [ -n "$home_mount" ] && [ -n "$logical_path" ] &&
        [ -n "$home_host" ] || return 1
    [ "$scan_mount" = "$home_mount" ] || return 1
    case "$logical_path" in
    "$home_host" | "$home_host"/*) return 0 ;;
    *) return 1 ;;
    esac
}

aur_builder_scan_path_is_normalized() {
    local path="$1"
    [[ "$path" =~ ^/[A-Za-z0-9._/-]+$ ]] && [[ "$path" != *//* ]] &&
        [[ "$path" != *'/./'* ]] && [[ "$path" != *'/../'* ]] &&
        [[ "$path" != */. ]] && [[ "$path" != */.. ]]
}

aur_builder_uid_scan_target_mounts() (
    local target_root="$1" builder_uid="$2" builder_home="$3" mode="$4"
    local minimum_uid="${5:-}" maximum_uid="${6:-}"
    local inventory_before inventory_after mount_targets_text mount_target mount_identity
    local mount_id view_id source_root_identity view_root_identity view_tree view_options
    local scan_parent='' view='' home_host='' home_mount='' owned_path logical_path
    local cleanup_status=0 mounted=false
    local -a mount_targets=()

    cleanup_aur_uid_scan() {
        local original_status=$?
        if [ "$mounted" = true ] && [ -n "$view" ]; then
            umount -- "$view" >/dev/null 2>&1 || cleanup_status=1
            mounted=false
        fi
        if [ -n "$view" ] && [ -d "$view" ] && [ ! -L "$view" ]; then
            rmdir -- "$view" 2>/dev/null || cleanup_status=1
            view=''
        fi
        if [ -n "$scan_parent" ] && [ -d "$scan_parent" ] && [ ! -L "$scan_parent" ]; then
            case "$scan_parent" in
            "${SCRIPT_TMP_DIR}"/aur-uid-scan.*)
                rm -f -- "${scan_parent}/occupied-uids" "${scan_parent}/owned-inodes" 2>/dev/null ||
                    cleanup_status=1
                rmdir -- "$scan_parent" 2>/dev/null || cleanup_status=1
                ;;
            *) cleanup_status=1 ;;
            esac
            scan_parent=''
        fi
        trap - EXIT
        [ "$cleanup_status" -eq 0 ] || original_status=1
        exit "$original_status"
    }
    trap cleanup_aur_uid_scan EXIT

    [[ "$builder_uid" =~ ^[0-9]+$ ]] && [ "$builder_uid" -gt 0 ] || return 1
    case "$mode" in empty | confined | cleanup | occupied-uids) ;; *) return 1 ;; esac
    [ -d "$target_root" ] && [ ! -L "$target_root" ] || return 1
    aur_builder_scan_path_is_normalized "$target_root" || return 1
    [ "$(realpath -e -- "$target_root")" = "$target_root" ] || return 1
    [ -d "$SCRIPT_TMP_DIR" ] && [ ! -L "$SCRIPT_TMP_DIR" ] || return 1
    [ "$(stat -c '%u:%a' -- "$SCRIPT_TMP_DIR")" = "${EUID}:700" ] || return 1
    case "$SCRIPT_TMP_DIR" in "$target_root" | "$target_root"/*) return 1 ;; esac
    case "$target_root" in "$SCRIPT_TMP_DIR" | "$SCRIPT_TMP_DIR"/*) return 1 ;; esac
    [ "$(findmnt -rn -o TARGET -M "$target_root" 2>/dev/null)" = "$target_root" ] || return 1

    if [ "$mode" = confined ]; then
        [ "$builder_home" = '/var/lib/arch-linux-aur-builder' ] || return 1
        home_host="${target_root}${builder_home}"
        [ -d "$home_host" ] && [ ! -L "$home_host" ] || return 1
        [ "$(realpath -e -- "$home_host")" = "$home_host" ] || return 1
        home_mount="$(findmnt -rn -o TARGET -T "$home_host" 2>/dev/null)" || return 1
        case "$home_mount" in "$target_root" | "$target_root"/*) ;; *) return 1 ;; esac
    elif [ "$mode" = occupied-uids ]; then
        [[ "$minimum_uid" =~ ^[0-9]+$ ]] && [[ "$maximum_uid" =~ ^[0-9]+$ ]] &&
            [ "$minimum_uid" -gt 0 ] && [ "$minimum_uid" -le "$maximum_uid" ] || return 1
    else
        [ -z "$builder_home" ] || [ "$builder_home" = '/var/lib/arch-linux-aur-builder' ] || return 1
    fi

    inventory_before="$(LC_ALL=C findmnt -Rrn -o TARGET,ID,MAJ:MIN,FSTYPE,FSROOT,SOURCE -M "$target_root")" ||
        return 1
    mount_targets_text="$(findmnt -Rrn -o TARGET -M "$target_root")" || return 1
    [ -n "$inventory_before" ] && [ -n "$mount_targets_text" ] || return 1
    mapfile -t mount_targets <<<"$mount_targets_text"
    [ "${#mount_targets[@]}" -gt 0 ] && [ "${mount_targets[0]}" = "$target_root" ] || return 1

    scan_parent="$(mktemp -d -- "${SCRIPT_TMP_DIR}/aur-uid-scan.XXXXXXXXXX")" || return 1
    chmod 0700 -- "$scan_parent" || return 1
    [ "$(stat -c '%u:%a' -- "$scan_parent")" = "${EUID}:700" ] || return 1
    : >"${scan_parent}/occupied-uids"
    chmod 0600 -- "${scan_parent}/occupied-uids"

    for mount_target in "${mount_targets[@]}"; do
        case "$mount_target" in "$target_root" | "$target_root"/*) ;; *) return 1 ;; esac
        aur_builder_scan_path_is_normalized "$mount_target" || return 1
        [ -d "$mount_target" ] && [ ! -L "$mount_target" ] || return 1
        [ "$(realpath -e -- "$mount_target")" = "$mount_target" ] || return 1
        mount_identity="$(findmnt -rn -o MAJ:MIN,FSTYPE,FSROOT,SOURCE -M "$mount_target")" || return 1
        mount_id="$(findmnt -rn -o ID -M "$mount_target")" || return 1
        [[ "$mount_id" =~ ^[0-9]+$ ]] && [ -n "$mount_identity" ] || return 1
        source_root_identity="$(stat -Lc '%d:%i' -- "$mount_target")" || return 1

        view="${scan_parent}/view"
        mkdir -- "$view" || return 1
        chmod 0700 -- "$view" || return 1
        mount --bind -- "$mount_target" "$view" >/dev/null || return 1
        mounted=true
        view_id="$(findmnt -rn -o ID -M "$view")" || return 1
        [ "$view_id" != "$mount_id" ] && [[ "$view_id" =~ ^[0-9]+$ ]] || return 1
        [ "$(findmnt -rn -o MAJ:MIN,FSTYPE,FSROOT,SOURCE -M "$view")" = "$mount_identity" ] ||
            return 1
        view_root_identity="$(stat -Lc '%d:%i' -- "$view")" || return 1
        [ "$view_root_identity" = "$source_root_identity" ] || return 1
        view_tree="$(findmnt -Rrn -o TARGET -M "$view")" || return 1
        [ "$view_tree" = "$view" ] || return 1

        if [ "$mode" != cleanup ]; then
            mount -o remount,bind,ro,nosuid,nodev,noexec -- "$view" >/dev/null || return 1
            view_options="$(findmnt -rn -o VFS-OPTIONS -M "$view")" || return 1
            case ",${view_options}," in *,ro,* ) ;; *) return 1 ;; esac
            case ",${view_options}," in *,nosuid,* ) ;; *) return 1 ;; esac
            case ",${view_options}," in *,nodev,* ) ;; *) return 1 ;; esac
            case ",${view_options}," in *,noexec,* ) ;; *) return 1 ;; esac
        fi

        case "$mode" in
        empty)
            [ -z "$(find "$view" -xdev -uid "$builder_uid" -print -quit)" ] || return 1
            ;;
        confined)
            : >"${scan_parent}/owned-inodes"
            chmod 0600 -- "${scan_parent}/owned-inodes"
            find "$view" -xdev -uid "$builder_uid" -print0 >"${scan_parent}/owned-inodes" || return 1
            while IFS= read -r -d '' owned_path; do
                logical_path="${mount_target}${owned_path#"$view"}"
                aur_builder_owned_inode_is_confined \
                    "$mount_target" "$home_mount" "$logical_path" "$home_host" || return 1
            done <"${scan_parent}/owned-inodes"
            rm -f -- "${scan_parent}/owned-inodes"
            ;;
        cleanup)
            find "$view" -xdev -depth -uid "$builder_uid" -delete || return 1
            [ -z "$(find "$view" -xdev -uid "$builder_uid" -print -quit)" ] || return 1
            ;;
        occupied-uids)
            find "$view" -xdev -uid +$((minimum_uid - 1)) -uid -$((maximum_uid + 1)) \
                -printf '%U\n' >>"${scan_parent}/occupied-uids" || return 1
            ;;
        esac

        [ "$(stat -Lc '%d:%i' -- "$mount_target")" = "$source_root_identity" ] || return 1
        umount -- "$view" >/dev/null || return 1
        mounted=false
        rmdir -- "$view" || return 1
        view=''
    done

    inventory_after="$(LC_ALL=C findmnt -Rrn -o TARGET,ID,MAJ:MIN,FSTYPE,FSROOT,SOURCE -M "$target_root")" ||
        return 1
    [ "$inventory_after" = "$inventory_before" ] || return 1
    if [ "$mode" = occupied-uids ]; then
        LC_ALL=C sort -nu -- "${scan_parent}/occupied-uids"
    fi
    rm -f -- "${scan_parent}/occupied-uids"
    rmdir -- "$scan_parent" || return 1
    scan_parent=''
    cleanup_aur_uid_scan
)

aur_builder_target_owned_uids() {
    local minimum_uid="$1" maximum_uid="$2" result
    [ "$EUID" -eq 0 ] && [ "$minimum_uid" = 59000 ] && [ "$maximum_uid" = 60000 ] || return 1
    target_mount_tree_is_owned || return 1
    result="$(aur_builder_uid_scan_target_mounts /mnt 1 '' occupied-uids \
        "$minimum_uid" "$maximum_uid")" || return 1
    target_mount_tree_is_owned || return 1
    printf '%s\n' "$result"
}

aur_builder_uid_target_is_empty() {
    local builder_uid="$1"
    [ "$EUID" -eq 0 ] || return 1
    target_mount_tree_is_owned || return 1
    aur_builder_uid_scan_target_mounts /mnt "$builder_uid" '' empty || return 1
    target_mount_tree_is_owned
}

aur_builder_uid_target_is_confined() {
    local builder_uid="$1" builder_home="$2"
    [ "$EUID" -eq 0 ] && [ "$builder_home" = '/var/lib/arch-linux-aur-builder' ] || return 1
    target_mount_tree_is_owned || return 1
    aur_builder_uid_scan_target_mounts /mnt "$builder_uid" "$builder_home" confined || return 1
    target_mount_tree_is_owned
}

aur_builder_uid_cleanup_target() {
    local builder_uid="$1"
    [ "$EUID" -eq 0 ] || return 1
    ! aur_builder_uid_has_live_process "$builder_uid" || return 1
    target_mount_tree_is_owned || return 1
    aur_builder_uid_scan_target_mounts /mnt "$builder_uid" '' cleanup || return 1
    target_mount_tree_is_owned || return 1
    aur_builder_uid_scan_target_mounts /mnt "$builder_uid" '' empty
}

aur_builder_uid_is_available() {
    local candidate_uid="$1"
    [[ "$candidate_uid" =~ ^[0-9]+$ ]] && [ "$candidate_uid" -ge 59000 ] || return 1
    ! getent passwd "$candidate_uid" >/dev/null 2>&1 || return 1
    ! arch-chroot /mnt getent passwd "$candidate_uid" >/dev/null 2>&1 || return 1
    ! aur_builder_uid_has_live_process "$candidate_uid"
}

aur_builder_subids_are_absent() {
    local builder_user="$1" target_root="${2:-/mnt}"
    local subid_file metadata mode query_output status subid_kind
    local -a query_arguments=()

    [ "$EUID" -eq 0 ] && [[ "$builder_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
    case "$target_root" in
    /mnt) ;;
    /)
        [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ] || return 1
        ;;
    *) return 1 ;;
    esac
    for subid_kind in subuid subgid; do
        subid_file="${target_root%/}/etc/${subid_kind}"
        if [ -e "$subid_file" ] || [ -L "$subid_file" ]; then
            [ -f "$subid_file" ] && [ ! -L "$subid_file" ] || return 1
            metadata="$(stat -c '%u:%g:%h' -- "$subid_file")" || return 1
            [ "$metadata" = '0:0:1' ] || return 1
            mode="$(stat -c '%a' -- "$subid_file")" || return 1
            [[ "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 1
            ! awk -F: -v expected_user="$builder_user" \
                '$1 == expected_user { found = 1 } END { exit !found }' \
                "$subid_file" || return 1
        fi
        if [ "$subid_kind" = subuid ]; then
            query_arguments=("$builder_user")
        else
            query_arguments=(-g "$builder_user")
        fi
        status=0
        if [ "$target_root" = / ]; then
            query_output="$(getsubids "${query_arguments[@]}" 2>/dev/null)" || status=$?
        else
            query_output="$(arch-chroot "$target_root" getsubids \
                "${query_arguments[@]}" 2>/dev/null)" || status=$?
        fi
        [ "$status" -eq 1 ] && [ -z "$query_output" ] || return 1
    done
}

aur_builder_scope_is_empty() {
    local scope="$1"
    [ -r "$scope/cgroup.events" ] && grep -qx 'populated 0' "$scope/cgroup.events"
}

aur_builder_command_handoff_is_safe() {
    local command_status="$1" leftover="$2"
    [[ "$command_status" =~ ^[0-9]+$ ]] || return 1
    is_choice "$leftover" true false || return 1
    [[ "$AUR_ACTIVE_BUILDER_UID" =~ ^[0-9]+$ ]] &&
        [ "$AUR_ACTIVE_BUILDER_UID" -ge 59000 ] &&
        [ "$AUR_ACTIVE_BUILDER_HOME" = '/var/lib/arch-linux-aur-builder' ] &&
        [[ "$AUR_ACTIVE_BUILDER_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
    ! aur_builder_uid_has_live_process "$AUR_ACTIVE_BUILDER_UID" || return 1
    aur_builder_subids_are_absent "$AUR_ACTIVE_BUILDER_USER" || return 1
    if ! aur_builder_uid_target_is_confined \
        "$AUR_ACTIVE_BUILDER_UID" "$AUR_ACTIVE_BUILDER_HOME"; then
        aur_builder_uid_cleanup_target "$AUR_ACTIVE_BUILDER_UID" || return 1
        return 1
    fi
    [ "$leftover" = false ] && [ "$command_status" -eq 0 ]
}

# Run one builder command in a child cgroup of the already isolated executor. The command's first
# process enters that cgroup before arch-chroot/runuser starts; every descendant inherits it. A
# detached or setsid process makes the operation fail, is killed with cgroup.kill, and is proven
# gone before root may inspect or copy any builder-controlled path.
aur_builder_scope_run() {
    local output_file="$1"
    shift
    local scope ack pid ack_pid='' status=1 attempt leftover=false worker_relative=''
    local handoff_safe=false cleanup_safe=true

    [ -n "$PROCESS_CGROUP_DIR" ] && [ -d "$PROCESS_CGROUP_DIR" ] || return 1
    [ -n "$AUR_ACTIVE_BUILDER_UID" ] &&
        aur_builder_command_handoff_is_safe 0 false || return 1
    case "$output_file" in
    "${SCRIPT_TMP_DIR}"/*) ;;
    *) return 1 ;;
    esac
    : >"$output_file" || return 1
    chmod 0600 -- "$output_file" || return 1

    AUR_BUILD_SEQUENCE=$((AUR_BUILD_SEQUENCE + 1))
    scope="${PROCESS_CGROUP_DIR}/aur-build-${BASHPID}-${AUR_BUILD_SEQUENCE}"
    ack="${SCRIPT_TMP_DIR}/aur-build-${AUR_BUILD_SEQUENCE}.ready"
    mkdir -- "$scope" || return 1
    chmod 0700 -- "$scope" || true
    if [ ! -w "$scope/cgroup.procs" ] || [ ! -w "$scope/cgroup.kill" ] ||
        [ ! -r "$scope/cgroup.events" ]; then
        rmdir -- "$scope" 2>/dev/null || true
        return 1
    fi

    (
        printf '%s\n' "$BASHPID" >"${scope}/cgroup.procs" || exit 125
        worker_relative="$(awk -F: '$1 == "0" && $2 == "" { print $3 }' "/proc/${BASHPID}/cgroup")" || exit 125
        [ "$worker_relative" = "${scope#/sys/fs/cgroup}" ] || exit 125
        printf '%s\n' "$BASHPID" >"$ack" || exit 125
        exec "$@"
    ) >"$output_file" &
    pid=$!

    for ((attempt = 0; attempt < 100; attempt++)); do
        if [ -f "$ack" ]; then
            IFS= read -r ack_pid <"$ack" || ack_pid=''
            break
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if [ "$ack_pid" = "$pid" ]; then
        if wait "$pid"; then status=0; else status=$?; fi
    else
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        status=125
    fi

    if ! aur_builder_scope_is_empty "$scope"; then
        leftover=true
        printf '%s\n' 1 >"$scope/cgroup.kill" 2>/dev/null || true
    fi
    for ((attempt = 0; attempt < 100; attempt++)); do
        aur_builder_scope_is_empty "$scope" && break
        sleep 0.05
    done
    if ! aur_builder_scope_is_empty "$scope"; then
        rm -f -- "$ack"
        return 1
    fi
    # Once the cgroup is proven empty, target-wide UID confinement is mandatory on every exit
    # path, including command failure, oversized output and cgroup-directory cleanup failure.
    if aur_builder_command_handoff_is_safe "$status" "$leftover"; then
        handoff_safe=true
    fi
    rmdir -- "$scope" || cleanup_safe=false
    rm -f -- "$ack" || cleanup_safe=false
    [ "$(stat -c '%s' -- "$output_file")" -le 16777216 ] || cleanup_safe=false
    [ "$handoff_safe" = true ] && [ "$cleanup_safe" = true ]
}

aur_builder_account_prepare() {
    local builder_user="$1" builder_home="$2" status uid candidate_uid occupied_uids
    [[ "$builder_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
    [ "$builder_home" = '/var/lib/arch-linux-aur-builder' ] || return 1
    ! arch-chroot /mnt getent passwd "$builder_user" >/dev/null 2>&1 || return 1
    aur_builder_subids_are_absent "$builder_user" || return 1
    [ ! -e "/mnt${builder_home}" ] && [ ! -L "/mnt${builder_home}" ] || return 1
    occupied_uids="$(aur_builder_target_owned_uids 59000 60000)" || return 1
    uid=''
    for ((candidate_uid = 60000; candidate_uid >= 59000; candidate_uid--)); do
        if ! grep -Fxq -- "$candidate_uid" <<<"$occupied_uids" &&
            aur_builder_uid_is_available "$candidate_uid"; then
            uid="$candidate_uid"
            break
        fi
    done
    [ -n "$uid" ] && aur_builder_uid_target_is_empty "$uid" || return 1
    arch-chroot /mnt useradd --system --uid "$uid" --no-user-group --no-log-init --gid users \
        --create-home --home-dir "$builder_home" \
        --shell /usr/bin/nologin -- "$builder_user" || return 1
    [ "$(arch-chroot /mnt id -u -- "$builder_user")" = "$uid" ] || {
        arch-chroot /mnt userdel -- "$builder_user" 2>/dev/null || true
        return 1
    }
    if ! arch-chroot /mnt passwd --lock -- "$builder_user" >/dev/null ||
        ! status="$(arch-chroot /mnt passwd --status -- "$builder_user")" ||
        ! [[ "$status" == "$builder_user L "* ]] ||
        [ "$uid" -le 0 ] || [ "$uid" = "$(arch-chroot /mnt id -u -- "$ARCH_LINUX_USERNAME")" ] ||
        ! aur_builder_subids_are_absent "$builder_user" ||
        ! chmod 0700 -- "/mnt${builder_home}" ||
        [ "$(stat -c '%u %a' -- "/mnt${builder_home}")" != "$uid 700" ] ||
        ! aur_builder_uid_target_is_confined "$uid" "$builder_home"; then
        aur_builder_account_remove "$builder_user" "$builder_home" "$uid" 2>/dev/null || true
        return 1
    fi
    printf '%s\n' "$uid"
}

aur_builder_account_remove() {
    local builder_user="$1" builder_home="$2" builder_uid="$3" home_host
    local subids_were_absent=true
    home_host="/mnt${builder_home}"
    [ "$builder_home" = '/var/lib/arch-linux-aur-builder' ] || return 1
    [[ "$builder_uid" =~ ^[0-9]+$ ]] && [ "$builder_uid" -gt 0 ] || return 1
    [[ "$builder_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
    ! aur_builder_uid_has_live_process "$builder_uid" || return 1
    [ "$(arch-chroot /mnt id -u -- "$builder_user" 2>/dev/null)" = "$builder_uid" ] || return 1
    aur_builder_subids_are_absent "$builder_user" || subids_were_absent=false
    if [ -e "$home_host" ] || [ -L "$home_host" ]; then
        [ -d "$home_host" ] && [ ! -L "$home_host" ] || return 1
        [ "$(stat -c '%u' -- "$home_host")" = "$builder_uid" ] || return 1
    fi
    arch-chroot /mnt userdel -- "$builder_user" || return 1
    aur_builder_uid_cleanup_target "$builder_uid" || return 1
    [ ! -e "$home_host" ] && [ ! -L "$home_host" ] &&
        aur_builder_uid_target_is_empty "$builder_uid" &&
        ! arch-chroot /mnt getent passwd "$builder_user" >/dev/null 2>&1 &&
        aur_builder_subids_are_absent "$builder_user" &&
        [ "$subids_were_absent" = true ]
}

# Copy from one O_NOFOLLOW descriptor while hashing before, during and after the copy. The source
# inode/metadata must remain identical and the destination is created root-private with O_EXCL.
aur_copy_regular_file_stably() {
    local source="$1" destination_dir="$2" prefix="$3" expected_uid="$4"
    [ -d "$destination_dir" ] && [ ! -L "$destination_dir" ] || return 1
    [ "$(stat -c '%u %a' -- "$destination_dir")" = '0 700' ] || return 1
    [[ "$expected_uid" =~ ^[0-9]+$ ]] || return 1
    /usr/bin/env -i 'HOME=/' 'PATH=/usr/bin:/bin' 'LANG=C.UTF-8' 'LC_ALL=C.UTF-8' \
        /usr/bin/python -I -S - "$source" "$destination_dir" "$prefix" "$expected_uid" <<'PY'
import hashlib
import os
import stat
import sys
import tempfile

source, destination_dir, prefix, expected_uid_text = sys.argv[1:]
expected_uid = int(expected_uid_text)
source_fd = os.open(source, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
destination_path = None
destination_fd = None
try:
    before = os.fstat(source_fd)
    if not stat.S_ISREG(before.st_mode):
        raise RuntimeError("source is not regular")
    opened_path = os.stat(source, follow_symlinks=False)
    if not stat.S_ISREG(opened_path.st_mode) or (opened_path.st_dev, opened_path.st_ino) != (before.st_dev, before.st_ino):
        raise RuntimeError("source path changed while opening")
    if before.st_uid != expected_uid or before.st_nlink != 1:
        raise RuntimeError("unexpected source ownership or links")
    if before.st_mode & 0o022 or before.st_size <= 0 or before.st_size > 536870912:
        raise RuntimeError("unsafe source mode or size")

    digest_before = hashlib.sha256()
    while chunk := os.read(source_fd, 1024 * 1024):
        digest_before.update(chunk)
    os.lseek(source_fd, 0, os.SEEK_SET)

    destination_fd, destination_path = tempfile.mkstemp(
        prefix=prefix + ".", suffix=".pkg.tar.zst", dir=destination_dir
    )
    os.fchmod(destination_fd, 0o600)
    digest_copy = hashlib.sha256()
    copied = 0
    while chunk := os.read(source_fd, 1024 * 1024):
        digest_copy.update(chunk)
        copied += len(chunk)
        view = memoryview(chunk)
        while view:
            written = os.write(destination_fd, view)
            if written <= 0:
                raise RuntimeError("short destination write")
            view = view[written:]
    os.fsync(destination_fd)

    os.lseek(source_fd, 0, os.SEEK_SET)
    digest_after = hashlib.sha256()
    while chunk := os.read(source_fd, 1024 * 1024):
        digest_after.update(chunk)
    after = os.fstat(source_fd)
    final_path = os.stat(source, follow_symlinks=False)
    stable_fields = ("st_dev", "st_ino", "st_uid", "st_gid", "st_mode", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")
    if any(getattr(before, field) != getattr(after, field) for field in stable_fields):
        raise RuntimeError("source metadata changed")
    if not stat.S_ISREG(final_path.st_mode) or (final_path.st_dev, final_path.st_ino) != (before.st_dev, before.st_ino):
        raise RuntimeError("source path changed during copy")
    if copied != before.st_size or not (digest_before.digest() == digest_copy.digest() == digest_after.digest()):
        raise RuntimeError("source bytes changed")
    print(destination_path)
except Exception:
    if destination_path is not None:
        try:
            os.unlink(destination_path)
        except FileNotFoundError:
            pass
    raise SystemExit(1)
finally:
    if destination_fd is not None:
        os.close(destination_fd)
    os.close(source_fd)
PY
}

chroot_aur_install() {
    local repo repo_url repo_tmp_dir aur_failed srcinfo pinned_srcinfo
    local parsed_dependencies reviewed_dependencies generated_dependencies
    local aur_commit aur_archive_sha256 aur_srcinfo_sha256 aur_pkgbuild_sha256
    local source_identity actual_commit actual_archive_sha256 actual_srcinfo_sha256 extra_identity actual_pkgbuild_sha256
    local aur_stage_dir_host='' aur_builder_uid='' aur_builder_ready=false
    local aur_builder_user='archlinux-aur-builder' aur_builder_home='/var/lib/arch-linux-aur-builder'
    local aur_capture_file="${SCRIPT_TMP_DIR}/aur-builder-output"
    local -a build_dependencies=() built_packages=() accepted_packages=()
    local -a clean_user_env=()
    repo="$1"
    [[ "$repo" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || { log_fail "Unsafe AUR package name: ${repo}"; return 1; }
    read -r aur_commit aur_archive_sha256 aur_srcinfo_sha256 aur_pkgbuild_sha256 \
        < <(aur_review_metadata "$repo") || {
        log_fail "AUR package is not in the reviewed source allowlist: ${repo}"
        return 1
    }
    [[ "$aur_commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$aur_archive_sha256" =~ ^[a-f0-9]{64}$ ]] &&
        [[ "$aur_srcinfo_sha256" =~ ^[a-f0-9]{64}$ ]] && [[ "$aur_pkgbuild_sha256" =~ ^[a-f0-9]{64}$ ]] || return 1
    repo_url="https://aur.archlinux.org/${repo}.git"
    if ! aur_builder_uid="$(aur_builder_account_prepare "$aur_builder_user" "$aur_builder_home")"; then
        log_fail 'Failed to create the disposable locked AUR builder account'
        return 1
    fi
    aur_builder_ready=true
    AUR_ACTIVE_BUILDER_UID="$aur_builder_uid"
    AUR_ACTIVE_BUILDER_HOME="$aur_builder_home"
    AUR_ACTIVE_BUILDER_USER="$aur_builder_user"
    clean_user_env=(
        /usr/bin/env -i
        "HOME=${aur_builder_home}"
        "USER=${aur_builder_user}"
        "LOGNAME=${aur_builder_user}"
        'PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin'
        'LANG=C.UTF-8'
        'LC_ALL=C.UTF-8'
    )

    # PKGBUILD is untrusted user code. It never receives the installer environment, the account
    # password, a sudoers exception or a privileged package-manager command. Root installs only the
    # explicit dependency list bound to the exact checked-in .SRCINFO, never metadata produced by
    # executing PKGBUILD. The generated metadata must still agree before build runs with --nodeps.
    if ! aur_stage_dir_host="$(mktemp -d -- /mnt/var/lib/arch-linux-installer-aur.XXXXXXXXXX)"; then
        log_fail "Failed to create a root-owned AUR package staging directory"
        aur_builder_account_remove "$aur_builder_user" "$aur_builder_home" "$aur_builder_uid" || true
        return 1
    fi
    _aur_cleanup() {
        case "$aur_stage_dir_host" in
        /mnt/var/lib/arch-linux-installer-aur.*)
            find "$aur_stage_dir_host" -xdev -depth -delete 2>/dev/null || true
            ;;
        esac
        if [ "$aur_builder_ready" = true ]; then
            aur_builder_account_remove "$aur_builder_user" "$aur_builder_home" "$aur_builder_uid" || return 1
            aur_builder_ready=false
        fi
        AUR_ACTIVE_BUILDER_UID=''
        AUR_ACTIVE_BUILDER_HOME=''
        AUR_ACTIVE_BUILDER_USER=''
        rm -f -- "$aur_capture_file"
    }
    trap '_aur_cleanup' RETURN
    chmod 0700 "$aur_stage_dir_host"

    # Retry transient clone, build and package-install failures five times.
    aur_failed="true"
    for ((i = 1; i < 6; i++)); do
        [ "$i" -gt 1 ] && log_warn "${i}. Retry AUR installation..."
        repo_tmp_dir="${aur_builder_home}/src-${repo}-${i}"

        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 300 \
            git clone --no-checkout -- "$repo_url" "$repo_tmp_dir"; then
            sleep 10 && continue
        fi

        # Resolve the immutable commit, independently hash the exact Git archive and validate the
        # committed metadata before running any PKGBUILD code. A changed AUR HEAD is irrelevant;
        # a missing historical object or any byte difference fails closed.
        # shellcheck disable=SC2016 # Positional arguments belong to the clean inner Bash.
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 120 bash -c '
                set -euo pipefail
                cd -- "$1"
                git checkout --quiet --detach "$2"
                printf "%s %s %s\n" \
                    "$(git rev-parse HEAD)" \
                    "$(git archive --format=tar HEAD | sha256sum | awk '\''{ print $1 }'\'')" \
                    "$(sha256sum .SRCINFO | awk '\''{ print $1 }'\'')"
            ' bash "$repo_tmp_dir" "$aur_commit" ||
            ! source_identity="$(<"$aur_capture_file")" || [[ "$source_identity" == *$'\n'* ]]; then
            log_warn "AUR source identity check failed for ${repo}"
            sleep 10 && continue
        fi
        read -r actual_commit actual_archive_sha256 actual_srcinfo_sha256 extra_identity <<<"$source_identity"
        if [ -n "$extra_identity" ] || ! aur_review_source_identity_matches \
            "$repo" "$actual_commit" "$actual_archive_sha256" "$actual_srcinfo_sha256"; then
            log_warn "AUR source bytes differ from the reviewed identity for ${repo}"
            sleep 10 && continue
        fi

        # Capture the committed metadata bytes before any PKGBUILD execution, bind them again to
        # the reviewed SHA-256 and require the parsed dependency closure to equal the explicit
        # package-specific allowlist. This is the only data allowed to reach root pacman.
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 30 \
            cat -- "${repo_tmp_dir}/.SRCINFO" ||
            [ "$(stat -c '%s' -- "$aur_capture_file")" -gt 262144 ] ||
            [ "$(sha256sum "$aur_capture_file" | awk '{ print $1 }')" != "$aur_srcinfo_sha256" ] ||
            ! pinned_srcinfo="$(<"$aur_capture_file")" ||
            ! aur_srcinfo_identity_matches "$repo" "$pinned_srcinfo" ||
            ! parsed_dependencies="$(aur_srcinfo_dependencies "$repo" <<<"$pinned_srcinfo")" ||
            ! reviewed_dependencies="$(aur_reviewed_dependencies "$repo")" ||
            [ "$parsed_dependencies" != "$reviewed_dependencies" ]; then
            log_warn "Reviewed AUR dependency metadata check failed for ${repo}"
            sleep 10 && continue
        fi
        build_dependencies=()
        if [ -n "$reviewed_dependencies" ]; then
            mapfile -t build_dependencies <<<"$reviewed_dependencies"
            if ! chroot_pacman_install "${build_dependencies[@]}"; then
                sleep 10 && continue
            fi
        fi

        # Apply only reviewed deterministic hardening changes as the unprivileged builder: replace
        # VCS tags/HEAD with exact upstream commits, omit executable/changelog package metadata,
        # and incorporate intended config/theme bytes before makepkg records package checksums.
        # shellcheck disable=SC2016 # All expansions and fixed patch cases belong to the inner Bash.
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 120 bash -c '
                set -euo pipefail
                cd -- "$1"
                repo="$2"
                case "$repo" in
                plymouth-theme-archlinux)
                    grep -Fxq "install='\''plymouth-theme-archlinux.install'\''" PKGBUILD
                    sed -i "/^install='\''plymouth-theme-archlinux.install'\''$/d" PKGBUILD
                    grep -Fxq '\''source=("git+$url.git")'\'' PKGBUILD
                    sed -i '\''s|source=("git+$url.git")|source=("git+$url.git#commit=616a662c7c4440661b222609f547ce96ca280ec3")|'\'' PKGBUILD
                    grep -Fxq $'\''\tcp -r ./plymouth-theme-archlinux/archlinux/* "$pkgdir/usr/share/plymouth/themes/archlinux"'\'' PKGBUILD
                    sed -i '\''/^[[:space:]]*cp -r \.\/plymouth-theme-archlinux\/archlinux\/\* /a\
\tinstall -Dm644 /usr/share/plymouth/themes/spinner/keymap-render.png "$pkgdir/usr/share/plymouth/themes/archlinux/keymap-render.png"'\'' PKGBUILD
                    ;;
                gnome-shell-extension-blur-my-shell)
                    grep -Fq '\''#tag=v$pkgver'\'' PKGBUILD
                    sed -i '\''s|#tag=v$pkgver|#commit=444df605b34529dfab7be77d0f434bf54a6dd4cc|'\'' PKGBUILD
                    ;;
                gnome-shell-extension-just-perfection-desktop)
                    grep -Fq '\''#tag=$pkgver.0'\'' PKGBUILD
                    sed -i '\''s|#tag=$pkgver.0|#commit=818aa98baa1d6dbec7b44b70d9074d95d516a499|'\'' PKGBUILD
                    ;;
                gnome-shell-extension-clipboard-indicator)
                    grep -Fxq '\''  rm -f "$pkgdir/usr/share/glib-2.0/schemas/gschemas.compiled"'\'' PKGBUILD
                    sed -i '\''/^  rm -f "$pkgdir\/usr\/share\/glib-2\.0\/schemas\/gschemas\.compiled"$/i\
  rm -f "$pkgdir/usr/share/gnome-shell/extensions/$_uuid/locale/fr_FR/LC_MESSAGES/clipboard-indicator.po~"'\'' PKGBUILD
                    ;;
                paru-git)
                    grep -Fxq '\''source=("git+https://github.com/morganamilo/paru")'\'' PKGBUILD
                    sed -i '\''s|source=("git+https://github.com/morganamilo/paru")|source=("git+https://github.com/morganamilo/paru#commit=9ac3578807a87858651e81a02586ceb947686e7c")|'\'' PKGBUILD
                    ;;
                pikaur)
                    grep -Fxq '\''changelog="CHANGELOG"'\'' PKGBUILD
                    sed -i '\''/^changelog="CHANGELOG"$/d'\'' PKGBUILD
                    ;;
                esac
                case "$repo" in
                paru|paru-bin|paru-git)
                    sed -i '\''/^[[:space:]]*install -Dm644 paru\.conf /i\
  sed -i -e "s/^#BottomUp/BottomUp/" -e "s/^#SudoLoop/SudoLoop/" paru.conf'\'' PKGBUILD
                    ;;
                esac
                printf '\''\noptions+=(!debug)\n'\'' >>PKGBUILD
                sha256sum PKGBUILD | awk '\''{ print $1 }'\''
            ' bash "$repo_tmp_dir" "$repo" ||
            ! actual_pkgbuild_sha256="$(<"$aur_capture_file")" || [[ "$actual_pkgbuild_sha256" == *$'\n'* ]] ||
            ! aur_review_pkgbuild_matches "$repo" "$actual_pkgbuild_sha256"; then
            log_warn "Reviewed AUR hardening patch failed for ${repo}"
            sleep 10 && continue
        fi

        # shellcheck disable=SC2016 # $1 is expanded by the clean inner Bash.
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 120 bash -c \
            'cd -- "$1" && makepkg --printsrcinfo' _ "$repo_tmp_dir" ||
            [ "$(stat -c '%s' -- "$aur_capture_file")" -gt 262144 ] ||
            ! srcinfo="$(<"$aur_capture_file")" || ! aur_srcinfo_identity_matches "$repo" "$srcinfo"; then
            log_warn "AUR metadata is invalid or does not describe exactly ${repo}"
            sleep 10 && continue
        fi
        if ! generated_dependencies="$(aur_srcinfo_dependencies "$repo" <<<"$srcinfo")" ||
            [ "$generated_dependencies" != "$reviewed_dependencies" ]; then
            log_warn "Executed AUR metadata differs from the reviewed dependency closure for ${repo}"
            sleep 10 && continue
        fi

        # No -s/-i and no sudo authority exist while prepare/build/check/package execute.
        # shellcheck disable=SC2016 # $1 must be expanded by the inner bash -c, not here
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 1800 bash -c \
            'cd -- "$1" && makepkg --nodeps --noconfirm --cleanbuild' _ "$repo_tmp_dir"; then
            sleep 10 && continue
        fi

        # User-writable package paths are copied into a unique root-owned directory. Only copied
        # regular bytes whose .PKGINFO names the exact requested package may reach root pacman.
        built_packages=()
        # shellcheck disable=SC2016 # $1 must be expanded by the inner bash -c, not here
        if ! aur_builder_scope_run "$aur_capture_file" \
            arch-chroot /mnt /usr/bin/runuser -u "$aur_builder_user" -- \
            "${clean_user_env[@]}" timeout --signal=TERM --kill-after=10 120 \
            bash -c 'cd -- "$1" && makepkg --packagelist' \
            _ "$repo_tmp_dir"; then
            sleep 10 && continue
        fi
        mapfile -t built_packages <"$aur_capture_file"
        accepted_packages=()
        local pkg canonical_pkg staged_host staged_chroot
        for pkg in "${built_packages[@]}"; do
            aur_package_output_path_is_safe "$pkg" || continue
            canonical_pkg="$(readlink -f -- "/mnt${pkg}" 2>/dev/null)" || continue
            case "$canonical_pkg" in
            "/mnt${repo_tmp_dir}"/*) ;;
            *) continue ;;
            esac
            [ -f "$canonical_pkg" ] && [ ! -L "$canonical_pkg" ] || continue
            [ "$(stat -c '%u' -- "$canonical_pkg")" = "$aur_builder_uid" ] || continue
            staged_host="$(aur_copy_regular_file_stably \
                "$canonical_pkg" "$aur_stage_dir_host" "$repo" "$aur_builder_uid")" || continue
            if ! aur_package_archive_is_safe "$repo" "$staged_host"; then
                rm -f -- "$staged_host"
                continue
            fi
            staged_chroot="${staged_host#/mnt}"
            accepted_packages+=("$staged_chroot")
        done
        if [ "${#accepted_packages[@]}" -ne 1 ]; then
            log_warn "makepkg did not produce exactly one validated ${repo} package"
            sleep 10 && continue
        fi
        # Remove the locked builder account and its entire exact home before privileged package
        # installation. There is then no builder identity, process or writable path left to race.
        if ! aur_builder_account_remove "$aur_builder_user" "$aur_builder_home" "$aur_builder_uid" ||
            ! aur_builder_uid_target_is_empty "$aur_builder_uid"; then
            log_fail 'Could not remove the disposable AUR builder cleanly'
            return 1
        fi
        aur_builder_ready=false
        AUR_ACTIVE_BUILDER_UID=''
        AUR_ACTIVE_BUILDER_HOME=''
        AUR_ACTIVE_BUILDER_USER=''
        if arch-chroot /mnt pacman -U --noconfirm --needed -- "${accepted_packages[@]}"; then
            aur_failed="false"
            break
        fi
        return 1
    done

    trap - RETURN
    _aur_cleanup

    [ "$aur_failed" = "true" ] && return 1
    [ "$aur_failed" = "false" ] && return 0
}

chroot_pacman_remove() { arch-chroot /mnt pacman -Rn --noconfirm -- "$@" || return 1; }

chroot_user_path_is_safe() {
    local target="${1:-}" home_path="/home/${ARCH_LINUX_USERNAME}" component
    local -a components=()

    case "$target" in
    "${home_path}"/*) ;;
    *) return 1 ;;
    esac
    [[ "$target" != *'//'* ]] || return 1
    IFS='/' read -r -a components <<<"$target"
    for component in "${components[@]}"; do
        [ "$component" != '.' ] && [ "$component" != '..' ] || return 1
    done
}

# After an AUR PKGBUILD has executed, a privileged process must never follow a user-controlled
# component below the target user's home. Feed content on stdin and perform every path traversal,
# temporary-file creation and atomic replacement after runuser has dropped privileges. A malicious
# symlink to /etc therefore fails (and is not silently replaced or followed by root).
chroot_user_update_file() {
    local target="${1:-}" mode="${2:-}" operation="${3:-}"
    local home_path="/home/${ARCH_LINUX_USERNAME}"

    chroot_user_path_is_safe "$target" || {
        log_fail "Refusing unsafe user-home target: ${target:-empty}"
        return 1
    }
    [[ "$mode" =~ ^0[0-7]{3}$ ]] || return 1
    [ "$operation" = write ] || [ "$operation" = append ] || return 1

    # shellcheck disable=SC2016 # The inner Bash expands its own positional arguments and state.
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- \
        /usr/bin/env -i \
        "HOME=${home_path}" \
        "USER=${ARCH_LINUX_USERNAME}" \
        "LOGNAME=${ARCH_LINUX_USERNAME}" \
        'PATH=/usr/bin:/bin' \
        'LANG=C.UTF-8' \
        'LC_ALL=C.UTF-8' \
        /usr/bin/bash -c '
            set -euo pipefail
            target="$1"
            mode="$2"
            operation="$3"
            parent="${target%/*}"
            resolved_home="$(realpath -e -- "$HOME")"
            resolved_parent="$(realpath -m -- "$parent")"
            case "$resolved_parent" in
                "$resolved_home"|"$resolved_home"/*) ;;
                *) exit 1 ;;
            esac
            mkdir -p -- "$parent"
            resolved_parent="$(realpath -e -- "$parent")"
            case "$resolved_parent" in
                "$resolved_home"|"$resolved_home"/*) ;;
                *) exit 1 ;;
            esac
            [ ! -L "$target" ]
            if [ -e "$target" ]; then
                [ -f "$target" ] && [ -O "$target" ]
            fi
            candidate="$(mktemp -- "${target}.tmp.XXXXXXXXXX")"
            trap '\''rm -f -- "$candidate"'\'' EXIT
            chmod -- "$mode" "$candidate"
            if [ "$operation" = append ] && [ -e "$target" ]; then
                cat -- "$target" >"$candidate"
            fi
            cat >>"$candidate"
            mv -fT -- "$candidate" "$target"
            trap - EXIT
        ' bash "$target" "$mode" "$operation"
}

chroot_user_write_file() { chroot_user_update_file "$1" "$2" write; }
chroot_user_append_file() { chroot_user_update_file "$1" "$2" append; }

chroot_user_finalize_init() {
    local home_path="/home/${ARCH_LINUX_USERNAME}"

    # shellcheck disable=SC2016 # The inner Bash expands its own positional arguments and state.
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- \
        /usr/bin/env -i \
        "HOME=${home_path}" \
        "USER=${ARCH_LINUX_USERNAME}" \
        "LOGNAME=${ARCH_LINUX_USERNAME}" \
        'PATH=/usr/bin:/bin' \
        'LANG=C.UTF-8' \
        'LC_ALL=C.UTF-8' \
        /usr/bin/bash -c '
            set -euo pipefail
            init_name="$1"
            version="$2"
            source_file="$HOME/${init_name}.sh"
            [ -e "$source_file" ] || { [ ! -L "$source_file" ]; exit; }
            [ -f "$source_file" ] && [ ! -L "$source_file" ] && [ -O "$source_file" ] && [ -s "$source_file" ]
            resolved_home="$(realpath -e -- "$HOME")"
            system_dir="$HOME/.arch-linux/system"
            autostart_dir="$HOME/.config/autostart"
            for directory in "$system_dir" "$autostart_dir"; do
                resolved_directory="$(realpath -m -- "$directory")"
                case "$resolved_directory" in
                    "$resolved_home"|"$resolved_home"/*) ;;
                    *) exit 1 ;;
                esac
                mkdir -p -- "$directory"
                resolved_directory="$(realpath -e -- "$directory")"
                case "$resolved_directory" in
                    "$resolved_home"|"$resolved_home"/*) ;;
                    *) exit 1 ;;
                esac
            done
            final_script="$system_dir/${init_name}.sh"
            autostart_file="$autostart_dir/${init_name}.desktop"
            [ ! -L "$final_script" ] && [ ! -L "$autostart_file" ]
            for existing in "$final_script" "$autostart_file"; do
                if [ -e "$existing" ]; then
                    [ -f "$existing" ] && [ -O "$existing" ]
                fi
            done
            script_candidate="$(mktemp -- "${final_script}.tmp.XXXXXXXXXX")"
            autostart_candidate="$(mktemp -- "${autostart_file}.tmp.XXXXXXXXXX")"
            trap '\''rm -f -- "$script_candidate" "$autostart_candidate"'\'' EXIT
            {
                printf "%s\n" "#!/usr/bin/env bash" "ARCH_LINUX_VERSION=${version}"
                cat -- "$source_file"
                printf "%s\n" \
                    "# exec_finalize_arch_linux | Remove autostart init files" \
                    "rm -f -- \"\$HOME/.config/autostart/${init_name}.desktop\"" \
                    "# exec_finalize_arch_linux | Print initialized info" \
                    "echo \"\$(date '\''+%Y-%m-%d %H:%M:%S'\'') | Arch Linux \${ARCH_LINUX_VERSION} | Initialized\""
            } >"$script_candidate"
            chmod 0700 -- "$script_candidate"
            {
                printf "%s\n" \
                    "[Desktop Entry]" \
                    "Type=Application" \
                    "Name=Arch Linux Initialize" \
                    "Icon=preferences-system"
                printf "Exec=bash -c '\''%s/.arch-linux/system/%s.sh > %s/.arch-linux/system/%s.log'\''\n" \
                    "$HOME" "$init_name" "$HOME" "$init_name"
            } >"$autostart_candidate"
            chmod 0600 -- "$autostart_candidate"
            mv -fT -- "$script_candidate" "$final_script"
            mv -fT -- "$autostart_candidate" "$autostart_file"
            rm -f -- "$source_file"
            trap - EXIT
        ' bash "$INIT_FILENAME" "$VERSION"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAP FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# shellcheck disable=SC2317
trap_error() {
    # If process calls this trap, write error to file to use in exit trap
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >"$ERROR_MSG_TMP_FILE"
}

# shellcheck disable=SC2317
trap_exit() {
    local result_code="$?"

    # Executor subshells are reaped by process_capture. If Bash propagates EXIT in a particular
    # launch context, the child must never clean parent-owned runtime state or accepted storage.
    if [ -n "$SCRIPT_MAIN_PID" ] && [ "$BASHPID" != "$SCRIPT_MAIN_PID" ]; then
        exit "$result_code"
    fi

    # Read error msg from file (written in error trap)
    local error && [ -f "$ERROR_MSG_TMP_FILE" ] && error="$(<"$ERROR_MSG_TMP_FILE")" && rm -f -- "$ERROR_MSG_TMP_FILE"

    # Kill and reap the exact active process scope before reading its log or removing runtime state.
    if [ -n "$PROCESS_ACTIVE_PID" ] || [ -n "$PROCESS_CGROUP_DIR" ]; then
        process_reap_active true || result_code=1
    fi

    # On failure, release only storage resources recorded by this exact accepted installation.
    # A successful run preserves the user's explicit keep-mounted/chroot choice.
    if [ "$result_code" -ne 0 ] && [ "$DEBUG" = false ]; then
        installer_cleanup_created_storage || result_code=1
    fi

    # Cleanup (always: this must run even if gum itself failed to install below, since the trap
    # now also covers gum_init - see the top-level 'trap' call for why)
    unset ARCH_LINUX_PASSWORD
    rm -rf -- "$SCRIPT_TMP_DIR"

    # gum is not guaranteed to be installed yet at this point - fall back to plain output instead
    # of calling gum_* (which would itself exit 1 with a confusing "GUM not found" message)
    if [ ! -x "$GUM" ]; then
        [ "$result_code" -gt "0" ] && [ "$result_code" != "130" ] && echo "${error:-An error occurred}" >&2
        exit "$result_code"
    fi

    # When ctrl + c pressed exit without other stuff below
    [ "$result_code" = "130" ] && gum_warn "Exit..." && {
        exit 1
    }

    # Check if failed and print error
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && gum_fail "$error"            # Print error message (if exists)
        [ -z "$error" ] && gum_fail "An error occurred" # Otherwise print default error message
        gum_warn "See ${SCRIPT_LOG} for more information..."
        gum_confirm "Show Logs?" && gum pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi

    exit "$result_code" # Exit installer.sh
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    local current_relative cgroup_name owner mode
    if [ -z "$SCRIPT_TMP_DIR" ] ||
        ! runtime_directory_metadata_is_safe "$SCRIPT_TMP_DIR" "$(id -u)"; then
        gum_fail 'Installer runtime directory is not initialized safely'
        exit 1
    fi
    [ -z "$PROCESS_ACTIVE_PID" ] && [ -z "$PROCESS_CGROUP_DIR" ] || {
        gum_fail 'A prior installer process scope is still active'
        exit 1
    }
    [ -f "$PROCESS_RET_TMP_FILE" ] && gum_fail "${PROCESS_RET_TMP_FILE} already exists" && exit 1
    printf '%s\n' 1 >"$PROCESS_RET_TMP_FILE"
    rm -f -- "$PROCESS_CGROUP_ACK_TMP_FILE"

    current_relative="$(awk -F: '$1 == "0" && $2 == "" { print $3 }' /proc/self/cgroup)" || current_relative=''
    [[ "$current_relative" == /* ]] && [ "$(wc -l <<<"$current_relative")" -eq 1 ] || {
        gum_fail 'A unique cgroup-v2 scope is required for installer subprocesses'
        exit 1
    }
    PROCESS_SEQUENCE=$((PROCESS_SEQUENCE + 1))
    cgroup_name="arch-linux-installer-${BASHPID}-${PROCESS_SEQUENCE}"
    PROCESS_CGROUP_DIR="/sys/fs/cgroup${current_relative%/}/${cgroup_name}"
    PROCESS_CGROUP_RELATIVE="${current_relative%/}/${cgroup_name}"
    case "$PROCESS_CGROUP_DIR" in
    /sys/fs/cgroup/*/arch-linux-installer-* | /sys/fs/cgroup/arch-linux-installer-*) ;;
    *) gum_fail 'Refusing unexpected installer cgroup path'; exit 1 ;;
    esac
    mkdir -- "$PROCESS_CGROUP_DIR" || {
        PROCESS_CGROUP_DIR=''
        PROCESS_CGROUP_RELATIVE=''
        gum_fail 'Cannot create an isolated installer cgroup'
        exit 1
    }
    chmod 0700 -- "$PROCESS_CGROUP_DIR" || true
    read -r owner mode < <(stat -c '%u %a' -- "$PROCESS_CGROUP_DIR") || true
    if [ "$owner" != 0 ] || ! [[ "$mode" =~ ^[0-7]{3,4}$ ]] || (( (8#$mode & 0022) != 0 )) ||
        [ ! -w "$PROCESS_CGROUP_DIR/cgroup.procs" ] || [ ! -w "$PROCESS_CGROUP_DIR/cgroup.kill" ] ||
        [ ! -r "$PROCESS_CGROUP_DIR/cgroup.events" ]; then
        rmdir -- "$PROCESS_CGROUP_DIR" 2>/dev/null || true
        PROCESS_CGROUP_DIR=''
        PROCESS_CGROUP_RELATIVE=''
        gum_fail 'Installer cgroup does not provide the required containment controls'
        exit 1
    fi
    set -m
    log_proc "${1}..."
}

process_enter_cgroup() {
    # This function must be the first command in every executor subshell. No installer command may
    # start until the parent has an exact cgroup membership acknowledgement for this BASHPID.
    printf '%s\n' "$BASHPID" >"${PROCESS_CGROUP_DIR}/cgroup.procs" || exit 125
    local actual_relative
    actual_relative="$(awk -F: '$1 == "0" && $2 == "" { print $3 }' "/proc/${BASHPID}/cgroup")" || exit 125
    [ "$actual_relative" = "$PROCESS_CGROUP_RELATIVE" ] || exit 125
    printf '%s\n' "$BASHPID" >"$PROCESS_CGROUP_ACK_TMP_FILE" || exit 125
}

process_cgroup_is_empty() {
    [ -n "$PROCESS_CGROUP_DIR" ] || return 0
    [ -r "$PROCESS_CGROUP_DIR/cgroup.events" ] || return 1
    grep -qx 'populated 0' "$PROCESS_CGROUP_DIR/cgroup.events"
}

process_wait_cgroup_empty() {
    local attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
        process_cgroup_is_empty && return 0
        sleep 0.05
    done
    return 1
}

process_kill_contained() {
    [ -n "$PROCESS_CGROUP_DIR" ] && [ -w "$PROCESS_CGROUP_DIR/cgroup.kill" ] || return 1
    printf '%s\n' 1 >"$PROCESS_CGROUP_DIR/cgroup.kill"
}

process_log_contained_members() {
    local pid uid comm exe evidence
    [ -n "$PROCESS_CGROUP_DIR" ] && [ -r "$PROCESS_CGROUP_DIR/cgroup.procs" ] || return 1
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
        uid="$(awk '/^Uid:/ { print $2; exit }' "/proc/${pid}/status" 2>/dev/null)" || uid='unknown'
        comm="$(<"/proc/${pid}/comm")" 2>/dev/null || comm='unknown'
        exe="$(readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || exe='unknown'
        printf -v evidence 'Executor cgroup retained pid=%q uid=%q comm=%q exe=%q' \
            "$pid" "$uid" "$comm" "$exe"
        log_fail "$evidence"
    done <"$PROCESS_CGROUP_DIR/cgroup.procs"
}

process_member_is_expected_gpg_agent() {
    local uid="$1" comm="$2" exe="$3"
    [ "$uid" = 0 ] && [ "$comm" = gpg-agent ] || return 1
    case "$exe" in
    /usr/bin/gpg-agent | /mnt/usr/bin/gpg-agent) return 0 ;;
    *) return 1 ;;
    esac
}

process_terminate_expected_gpg_agents() {
    local pid uid comm exe found=false
    [ -n "$PROCESS_CGROUP_DIR" ] && [ -r "$PROCESS_CGROUP_DIR/cgroup.procs" ] || return 1
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
        uid="$(awk '/^Uid:/ { print $2; exit }' "/proc/${pid}/status" 2>/dev/null)" || return 1
        comm="$(<"/proc/${pid}/comm")" 2>/dev/null || return 1
        exe="$(readlink -f -- "/proc/${pid}/exe" 2>/dev/null)" || return 1
        process_member_is_expected_gpg_agent "$uid" "$comm" "$exe" || return 1
        kill -TERM -- "$pid" || return 1
        found=true
    done <"$PROCESS_CGROUP_DIR/cgroup.procs"
    [ "$found" = true ]
}

process_remove_cgroup() {
    local expected_prefix='/sys/fs/cgroup/'
    [ -n "$PROCESS_CGROUP_DIR" ] || return 0
    case "$PROCESS_CGROUP_DIR" in
    "${expected_prefix}"*'/arch-linux-installer-'*) ;;
    /sys/fs/cgroup/arch-linux-installer-*) ;;
    *) return 1 ;;
    esac
    process_cgroup_is_empty || return 1
    rmdir -- "$PROCESS_CGROUP_DIR" || return 1
    PROCESS_CGROUP_DIR=''
    PROCESS_CGROUP_RELATIVE=''
}

process_reap_active() {
    local terminate="${1:-false}" result=0 attempt unexpected_contained=false
    if [ -n "$PROCESS_ACTIVE_PID" ]; then
        if [ "$terminate" = true ] && [ -n "$PROCESS_ACTIVE_PGID" ]; then
            kill -TERM -- "-${PROCESS_ACTIVE_PGID}" 2>/dev/null || true
            for ((attempt = 0; attempt < 30; attempt++)); do
                kill -0 "$PROCESS_ACTIVE_PID" 2>/dev/null || break
                sleep 0.1
            done
        fi
        # Package hooks can leave short-lived descendants after their direct parent exits. Keep
        # them contained and allow the existing bounded drain before classifying them as leaked.
        if [ "$terminate" = false ] && ! process_wait_cgroup_empty; then
            if process_terminate_expected_gpg_agents && process_wait_cgroup_empty; then
                log_info 'Stopped the completed package transaction gpg-agent'
            else
                unexpected_contained=true
                process_log_contained_members || true
            fi
        fi
        if [ "$terminate" = true ] || [ "$unexpected_contained" = true ]; then
            process_kill_contained 2>/dev/null || true
        fi
        wait "$PROCESS_ACTIVE_PID" 2>/dev/null || result=$?
    fi
    if ! process_wait_cgroup_empty; then
        process_kill_contained 2>/dev/null || true
        process_wait_cgroup_empty || return 1
    fi
    PROCESS_ACTIVE_PID=''
    PROCESS_ACTIVE_PGID=''
    process_remove_cgroup || return 1
    [ "$unexpected_contained" = false ] || return 124
    return "$result"
}

process_capture() {
    local pid="$1" process_name="$2" user_canceled=false child_status=0
    local ack_pid='' actual_pgid='' attempt

    PROCESS_ACTIVE_PID="$pid"
    actual_pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]')" || actual_pgid=''
    PROCESS_ACTIVE_PGID="$actual_pgid"
    set +m
    if [ "$actual_pgid" != "$pid" ]; then
        process_reap_active true || true
        gum_fail "${process_name} did not start in its own process group"
        exit 1
    fi
    for ((attempt = 0; attempt < 100; attempt++)); do
        if [ -f "$PROCESS_CGROUP_ACK_TMP_FILE" ]; then
            IFS= read -r ack_pid <"$PROCESS_CGROUP_ACK_TMP_FILE" || ack_pid=''
            break
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if [ "$ack_pid" != "$pid" ]; then
        process_reap_active true || true
        gum_fail "${process_name} failed before entering its isolated process scope"
        exit 1
    fi

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    # shellcheck disable=SC2016 # $1 is expanded by the inner Bash process.
    gum_spin --title "${process_name}..." -- \
        bash -c 'while kill -0 "$1" &>/dev/null; do sleep 1; done' bash "$pid" ||
        user_canceled=true

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        process_reap_active true || {
            gum_fail "Could not prove complete termination of ${process_name}"
            exit 1
        }
        cat "$PROCESS_LOG_TMP_FILE" >>"$SCRIPT_LOG"
        gum_fail "Process with PID ${pid} was killed by user" && trap_gum_exit
    fi

    process_reap_active false || child_status=$?
    cat "$PROCESS_LOG_TMP_FILE" >>"$SCRIPT_LOG"
    [ "$child_status" -eq 0 ] || { gum_fail "${process_name} failed"; exit 1; }

    # Handle error while executing process
    [ ! -f "$PROCESS_RET_TMP_FILE" ] && gum_fail "${PROCESS_RET_TMP_FILE} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RET_TMP_FILE")" != "0" ] && gum_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not written at the end)

    # Finish
    rm -f -- "$PROCESS_RET_TMP_FILE"        # Remove process result file
    gum_proc "${process_name}" "success" # Print process success
}

process_return() {
    # 1. Write from sub process 0 to file when succeed (at the end of the script part)
    # 2. Read from parent process after sub process finished (0=success 1=failed)
    echo "$1" >"$PROCESS_RET_TMP_FILE"
    exit "$1"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM BINARY
# ////////////////////////////////////////////////////////////////////////////////////////////////////

gum_archive_is_safe() {
    local archive="${1:-}" actual_members expected_members verbose_members gum_member

    [ -f "$archive" ] && [ ! -L "$archive" ] || return 1
    gum_member="gum_${GUM_VERSION}_Linux_x86_64/gum"
    expected_members="$(printf '%s\n' \
        "gum_${GUM_VERSION}_Linux_x86_64/LICENSE" \
        "gum_${GUM_VERSION}_Linux_x86_64/README.md" \
        "gum_${GUM_VERSION}_Linux_x86_64/completions/gum.bash" \
        "gum_${GUM_VERSION}_Linux_x86_64/completions/gum.fish" \
        "gum_${GUM_VERSION}_Linux_x86_64/completions/gum.zsh" \
        "$gum_member" \
        "gum_${GUM_VERSION}_Linux_x86_64/manpages/gum.1.gz" | LC_ALL=C sort)"
    actual_members="$(tar -tzf "$archive" | LC_ALL=C sort)" || return 1
    [ "$actual_members" = "$expected_members" ] || return 1
    verbose_members="$(tar -tvzf "$archive")" || return 1
    [ "$(wc -l <<<"$verbose_members")" -eq 7 ] || return 1
    awk 'substr($1, 1, 1) != "-" || NF != 6 { exit 1 }' <<<"$verbose_members"
}

gum_binary_version_matches() {
    local candidate="${1:-}" reported_version

    [ -f "$candidate" ] && [ ! -L "$candidate" ] && [ -x "$candidate" ] || return 1
    reported_version="$($candidate --version 2>/dev/null | awk 'NR == 1 { sub(/^v/, "", $3); print $3 }')" || return 1
    [ "$reported_version" = "$GUM_VERSION" ]
}

gum_init() {
    # An explicit override is use-only: never create, delete or replace an arbitrary root path.
    if [ "$GUM" != '/usr/local/bin/gum' ]; then
        gum_binary_version_matches "$GUM" || {
            echo "GUM override must be a regular non-symlink Gum ${GUM_VERSION} executable" >&2
            exit 1
        }
        return 0
    fi

    # The automatic destination is exact and root-owned. Existing content is accepted only when it
    # is already the reviewed executable; unexpected files and symlinks are never overwritten.
    if [ -e "$GUM" ] || [ -L "$GUM" ]; then
        gum_binary_version_matches "$GUM" || {
            echo "Refusing unexpected existing Gum destination: ${GUM}" >&2
            exit 1
        }
        return 0
    fi

    clear && echo "Loading Arch Linux Installer..."
    local dl_url archive gum_member gum_verified
    [ "$(uname -s)" = 'Linux' ] && [ "$(uname -m)" = 'x86_64' ] || {
        echo "Unsupported platform for pinned Gum ${GUM_VERSION}" >&2
        exit 1
    }
    dl_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz"
    archive="${SCRIPT_TMP_DIR}/gum.tar.gz"
    gum_member="gum_${GUM_VERSION}_Linux_x86_64/gum"
    gum_verified="${SCRIPT_TMP_DIR}/gum.verified"
    if ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --connect-timeout 5 --max-time 60 --max-filesize 33554432 \
        --output "$archive" -- "$dl_url"; then
        echo "Error downloading pinned Gum archive" >&2
        exit 1
    fi
    downloaded_file_is_within_size "$archive" 33554432 || {
        echo "Pinned Gum archive exceeds its accepted size bound" >&2
        exit 1
    }
    printf '%s  %s\n' "$GUM_ARCHIVE_SHA256" "$archive" | sha256sum --check --strict || {
        echo "Checksum verification failed for pinned Gum archive" >&2
        exit 1
    }

    if ! gum_archive_is_safe "$archive"; then
        echo "Pinned Gum archive member closure or types differ from the reviewed release" >&2
        exit 1
    fi
    if ! tar -xOzf "$archive" -- "$gum_member" >"$gum_verified" || \
        [ "$(stat -c '%s' -- "$gum_verified")" -ne 13738168 ]; then
        echo "Cannot extract the exact reviewed Gum executable" >&2
        exit 1
    fi
    chmod 0700 "$gum_verified"
    gum_binary_version_matches "$gum_verified" || {
        echo "Pinned Gum executable reports an unexpected version" >&2
        exit 1
    }
    install -m0755 -- "$gum_verified" "$GUM" || {
        echo "Error installing verified Gum executable" >&2
        exit 1
    }
}

# Gum wrapper function
gum() {
    if [ -n "$GUM" ] && [ -x "$GUM" ]; then
        "$GUM" "$@"
    else
        echo "Error: GUM '${GUM}' is not found or executable" >&2
        exit 1
    fi
}

# Gum trap functions
trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PRINT FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local title="$1"
    clear && gum_foreground '
 █████  ██████   ██████ ██   ██     ██      ██ ███    ██ ██    ██ ██   ██
██   ██ ██   ██ ██      ██   ██     ██      ██ ████   ██ ██    ██  ██ ██
███████ ██████  ██      ███████     ██      ██ ██ ██  ██ ██    ██   ███
██   ██ ██   ██ ██      ██   ██     ██      ██ ██  ██ ██ ██    ██  ██ ██
██   ██ ██   ██  ██████ ██   ██     ███████ ██ ██   ████  ██████  ██   ██'
    local header_version header_version_label='v.'
    [ "$DEBUG" = "true" ] && header_version_label='d.'
    printf -v header_version '%33s%s %s' '' "$header_version_label" "$VERSION"
    gum_white --margin "1 0" --align left --bold "Welcome to ${title} ${header_version}"
    [ "$FORCE" = "true" ] && gum_red --bold "CAUTION: Force mode enabled. Cancel with: Ctrl + c" && echo
    return 0
}

# ---------------------------------------------------------------------------------------------------

# Last-look summary before the point of no return: short plain-English lines instead of a property
# dump - disk/partition fate (bootloader in parens on the boot partition), then what it means for
# login. Each topic is a top-level bullet with its details broken out as indented sub-bullets on
# their own line, rather than one long sentence - keeps every line short enough to not wrap on
# narrow terminals. The disk itself is highlighted in blue (like gum_title) so it stands out as
# "the one thing to double check"; everything else stays green like gum_property.
print_summary() {
    local disk_size='' disk_model='' disk_serial=''
    disk_size="$(lsblk -dn -o SIZE -- "$ARCH_LINUX_DISK" 2>/dev/null | head -n1)" || disk_size=''
    disk_model="$(lsblk -dn -o MODEL -- "$ARCH_LINUX_DISK" 2>/dev/null | sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}')" || disk_model=''
    disk_serial="$(lsblk -dn -o SERIAL -- "$ARCH_LINUX_DISK" 2>/dev/null | sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}')" || disk_serial=''
    local disk_label="$ARCH_LINUX_DISK"
    disk_label="${ARCH_LINUX_DISK} (size: ${disk_size:-unknown}; model: ${disk_model:-unknown}; serial: ${disk_serial:-unknown})"
    local bootloader_name="GRUB" && [ "$ARCH_LINUX_BOOTLOADER" = "systemd" ] && bootloader_name="systemd-boot"

    if [ "$ARCH_LINUX_DUAL_BOOT_ENABLED" = "true" ]; then
        gum join "$(gum_white "• Shares disk ")" "$(gum_blue --bold "$disk_label")" "$(gum_white " with your other system:")"
        gum join "$(gum_white "  • keeps boot partition ")" "$(gum_green --bold "$ARCH_LINUX_BOOT_PARTITION")" "$(gum_white " (")" "$(gum_green --bold "$bootloader_name")" "$(gum_white ")")"
        gum join "$(gum_white "  • formats root partition ")" "$(gum_green --bold "$ARCH_LINUX_ROOT_PARTITION")" "$(gum_white " as ")" "$(gum_green --bold "$ARCH_LINUX_FILESYSTEM")"
    else
        gum join "$(gum_white "• Erases disk ")" "$(gum_blue --bold "$disk_label")" "$(gum_white ":")"
        gum join "$(gum_white "  • creates boot partition ")" "$(gum_green --bold "$ARCH_LINUX_BOOT_PARTITION")" "$(gum_white " (")" "$(gum_green --bold "$bootloader_name")" "$(gum_white ")")"
        gum join "$(gum_white "  • creates root partition ")" "$(gum_green --bold "$ARCH_LINUX_ROOT_PARTITION")" "$(gum_white ", formats as ")" "$(gum_green --bold "$ARCH_LINUX_FILESYSTEM")"
    fi

    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        gum join "$(gum_white "• Desktop: ")" "$(gum_green --bold "GNOME")" "$(gum_white ", terminal: ")" "$(gum_green --bold "Ptyxis")"
        if [ "$ARCH_LINUX_GNOME_THEME_PROFILE" = "marble" ]; then
            gum join "$(gum_white "  • appearance: ")" "$(gum_green --bold "Marble Shell + Colloid GTK3/icons")"
            if [ "$ARCH_LINUX_GDM_THEME_PROFILE" = "marble-experimental" ]; then
                gum_white "  • GDM Shell: matching Marble theme + Colloid icons (experimental; GNOME 50 only)"
            else
                gum_white "  • GDM Shell: Stock (default)"
            fi
            gum_white "  • GTK4/libadwaita CSS stays Stock; the Colloid icon default is global"
            gum_white "  • Bibata and all seven existing extensions stay enabled"
            gum_white "  • unsupported GNOME majors normally fall back to Stock Shell/GDM during pacman -Syu"
            gum_white "  • an unsafe failure to remove our active GDM link aborts before package changes"
        else
            gum join "$(gum_white "  • appearance: ")" "$(gum_green --bold "Stock GNOME")"
            gum_white "  • GDM Shell: Stock"
            gum_white "  • GTK4/libadwaita CSS: Stock"
        fi

        if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
            gum join "$(gum_white "• Disk encryption ")" "$(gum_green --bold "on")" "$(gum_white ":")"
            gum join "$(gum_white "  • your system also asks for a ")" "$(gum_green --bold "password")" "$(gum_white " at login, two prompts in total")"
        else
            gum_white "• No disk encryption:"
            gum join "$(gum_white "  • your system asks for a ")" "$(gum_green --bold "password")" "$(gum_white " at every login")"
        fi
    fi

    # Network exposure is easy to enable and hard to notice afterwards, so call it out explicitly
    if [ "$ARCH_LINUX_SAMBA_SHARE_ENABLED" = "true" ] && [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
        gum join "$(gum_white "• Samba share ")" "$(gum_yellow --bold "on")" "$(gum_white ":")"
        gum join "$(gum_white "  • ")" "$(gum_yellow --bold "anyone on your network can write to the public share")"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

print_filled_space() {
    local total="$1" && local text="$2" && local length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    local padding=$((total - length)) && printf '%s%*s\n' "$text" "$padding" ""
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Gum colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_foreground() { gum_style --foreground "$COLOR_FOREGROUND" "${@}"; }
gum_background() { gum_style --foreground "$COLOR_BACKGROUND" "${@}"; }
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_black() { gum_style --foreground "$COLOR_BLACK" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_blue() { gum_style --foreground "$COLOR_BLUE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_cyan() { gum_style --foreground "$COLOR_CYAN" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }

# Gum prints
gum_title() { log_head "${*}" && gum join "$(gum_foreground --bold "+ ")" "$(gum_foreground --bold "${*}")"; }
gum_info() { log_info "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "${*}")"; }
gum_warn() { log_warn "$*" && gum join "$(gum_yellow --bold "• ")" "$(gum_white "${*}")"; }
gum_fail() { log_fail "$*" && gum join "$(gum_red --bold "• ")" "$(gum_white "${*}")"; }

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_FOREGROUND" --selected.background "$COLOR_FOREGROUND" --selected.foreground "$COLOR_BACKGROUND" --unselected.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --cursor.foreground "$COLOR_FOREGROUND" --prompt.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_FOREGROUND" --cursor.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_FOREGROUND" --indicator.foreground "$COLOR_FOREGROUND" --match.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_write() { gum write --prompt "> " --show-cursor-line --char-limit 0 --cursor.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_FOREGROUND" --spinner.foreground "$COLOR_FOREGROUND" "${@}"; }

# Gum key & value
gum_proc() { log_proc "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white --bold "$(print_filled_space 24 "${1}")")" "$(gum_white "  >  ")" "$(gum_green "${2}")"; }
gum_property() { log_prop "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "$(print_filled_space 24 "${1}")")" "$(gum_green --bold "  >  ")" "$(gum_white --bold "${2}")"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGGING WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-linux | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_head() { write_log "HEAD | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }
log_prop() { write_log "PROP | ${*}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# STATIC INPUT VALUES
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# Desktop keyboard data embedded for the Arch ISO (which ships no xkeyboard-config).
# Source: localectl list-x11-keymap-layouts / list-x11-keymap-variants <layout>.

desktop_keymap_layouts() { echo "af al am ara at au az ba bd be bg br brai bt bw by ca cd ch cm cn cz de dk dz ee eg epo es et fi fo fr gb ge gh gn gr hr hu id ie il in iq ir is it jp ke kg kh kr kz la latam lk lt lv ma md me mk ml mm mn mt mv my ng nl no np nz ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za"; }

# ---------------------------------------------------------------------------------------------------

# Only valid current layout/variant combinations are offered in select_enable_desktop_keyboard.
declare -A variant_map=(
    [af]="ps uz" [al]="plisi veqilharxhi" [am]="phonetic phonetic-alt eastern eastern-alt western" [ara]="digits azerty azerty_digits buckwalter mac mac-phonetic" [at]="nodeadkeys mac" [az]="cyrillic"
    [ba]="alternatequotes unicode unicodeus us" [bd]="probhat" [be]="oss oss_latin9 iso-alternate nodeadkeys wang" [bg]="phonetic bas_phonetic bekl" [brai]="left_hand left_hand_invert right_hand right_hand_invert"
    [br]="nodeadkeys dvorak nativo nativo-us thinkpad thinkpad_nodeadkeys nativo-epo rus" [by]="latin intl phonetic ru" [ca]="fr-dvorak multix eng ike" [ch]="de_nodeadkeys de_mac fr fr_nodeadkeys fr_mac"
    [cm]="french qwerty azerty dvorak mmuock" [cn]="altgr-pinyin mon_trad mon_trad_todo mon_trad_xibe mon_trad_manchu mon_trad_galik mon_todo_galik mon_manchu_galik tib tib_asciinum ug"
    [cz]="bksl qwerty qwerty_bksl winkeys winkeys-qwerty qwerty-mac ucw dvorak-ucw rus" [de]="deadacute deadgraveacute deadtilde nodeadkeys e1 e2 T3 us dvorak mac mac_nodeadkeys neo qwerty dsb dsb_qwertz ro ro_nodeadkeys ru tr"
    [dk]="nodeadkeys winkeys mac mac_nodeadkeys dvorak" [dz]="ber azerty-deadkeys qwerty-gb-deadkeys qwerty-us-deadkeys ar" [ee]="nodeadkeys dvorak us" [es]="nodeadkeys deadtilde winkeys dvorak ast cat"
    [fi]="winkeys classic nodeadkeys mac smi" [fo]="nodeadkeys" [fr]="nodeadkeys oss oss_nodeadkeys oss_latin9 latin9 latin9_nodeadkeys azerty afnor bepo bepo_latin9 bepo_afnor dvorak ergol ergol_iso mac us bre oci geo"
    [gb]="extd intl dvorak dvorakukp mac mac_intl colemak colemak_dh gla pl" [ge]="ergonomic mess os ru" [gh]="generic gillbt akan avn ewe fula ga hausa" [gr]="simple nodeadkeys polytonic" [hr]="alternatequotes unicode unicodeus us"
    [hu]="standard nodeadkeys qwerty 101_qwertz_comma_dead 101_qwertz_comma_nodead 101_qwertz_dot_dead 101_qwertz_dot_nodead 101_qwerty_comma_dead 101_qwerty_comma_nodead 101_qwerty_dot_dead 101_qwerty_dot_nodead 102_qwertz_comma_dead 102_qwertz_comma_nodead 102_qwertz_dot_dead 102_qwertz_dot_nodead 102_qwerty_comma_dead 102_qwerty_comma_nodead 102_qwerty_dot_dead 102_qwerty_dot_nodead"
    [id]="melayu-phonetic melayu-phoneticx pegon-phonetic javanese" [ie]="UnicodeExpert CloGaelach ogam ogam_is434" [il]="si2 lyx phonetic biblical"
    [in]="asm-kagapa ben ben_probhat ben_baishakhi ben_bornona ben-kagapa ben_gitanjali ben_inscript eng guj guj-kagapa bolnagri hin-wx hin-kagapa kan kan-kagapa mal mal_lalitha mal_enhanced mal_poorna mara mni mar-kagapa marathi ori ori-bolnagri ori-wx guru jhelum san-kagapa sat tamilnet tamilnet_tamilnumbers tamilnet_TAB tamilnet_TSCII tam tam_tamilnumbers tel tel-kagapa tel-sarala urd-phonetic urd-phonetic3 urd-winkeys iipa"
    [iq]="ku ku_alt ku_f ku_ara" [ir]="pes_keypad winkeys azb ku ku_alt ku_f ku_ara" [is]="mac dvorak" [it]="nodeadkeys winkeys mac us ibm fur scn geo" [jp]="kana OADG109A mac dvorak" [ke]="kik" [kg]="phonetic" [kr]="kr104"
    [kz]="kazrus ext latin ruskaz" [la]="stea" [latam]="nodeadkeys deadtilde dvorak colemak" [lk]="us tam_unicode tam_TAB" [lt]="std us ibm lekp lekpa ratise sgs" [lv]="apostrophe tilde fkey modern modern-cyr ergonomic adapted"
    [ma]="tifinagh tifinagh-alt tifinagh-alt-phonetic tifinagh-extended tifinagh-phonetic tifinagh-extended-phonetic french rif" [md]="gag"
    [me]="cyrillic cyrillicyz cyrillicalternatequotes latinunicode latinyz latinunicodeyz latinalternatequotes" [mk]="nodeadkeys" [ml]="fr-oss us-mac us-intl" [mm]="zawgyi mara mnw mnw-a1 shn zgt" [mt]="us alt-us alt-gb"
    [my]="phonetic" [ng]="hausa igbo yoruba" [nl]="us mac std" [no]="nodeadkeys winkeys mac mac_nodeadkeys colemak colemak_dh colemak_dh_wide dvorak smi smi_nodeadkeys" [nz]="mao"
    [ph]="qwerty-bay capewell-dvorak capewell-dvorak-bay capewell-qwerf2k6 capewell-qwerf2k6-bay colemak colemak-bay dvorak dvorak-bay" [pk]="urd-crulp urd-nla pak_urdu_phonetic ara snd"
    [pl]="qwertz dvorak dvorak_quotes dvorak_altquotes dvp csb szl ru_phonetic_dvorak" [pt]="nodeadkeys mac mac_nodeadkeys nativo nativo-us nativo-epo" [ro]="std winkeys"
    [rs]="alternatequotes yz latin latinalternatequotes latinunicode latinyz latinunicodeyz rue"
    [ru]="phonetic phonetic_winkeys phonetic_YAZHERTY phonetic_azerty phonetic_dvorak typewriter ruchey_ru ruchey_en dos mac ab bak cv cv_latin xal kom chm os_winkeys srp tt udm sah"
    [se]="nodeadkeys dvorak us_dvorak svdvorak colemak mac us swl smi rus" [si]="alternatequotes us" [sk]="bksl qwerty qwerty_bksl" [sy]="syc syc_phonetic ku ku_alt ku_f" [th]="tis pat mnc" [tm]="alt"
    [tr]="f e alt intl ku ku_f ku_alt" [tw]="indigenous saisiyat" [ua]="phonetic typewriter winkeys winkeysenhanced macOS homophonic crh crh_f crh_alt"
    [us]="euro intl alt-intl altgr-intl mac mac-iso colemak colemak_dh colemak_dh_wide colemak_dh_ortho colemak_dh_iso colemak_dh_wide_iso dvorak dvorak-intl dvorak-alt-intl dvorak-l dvorak-r dvorak-classic dvp dvorak-mac dvorak-mac-iso norman symbolic workman workman-intl chr haw rus hbs"
    [uz]="latin" [vn]="us fr"
)

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# INSTALLER SELF UPDATE
# ////////////////////////////////////////////////////////////////////////////////////////////////////

cleanup_installer_update_dir() {
    local update_dir="$1"
    case "$update_dir" in
    /tmp/arch-linux-installer-update.*)
        [ ! -e "$update_dir" ] || find "$update_dir" -xdev -depth -delete
        ;;
    *) return 1 ;;
    esac
}

installer_signature_matches() {
    local installer="$1" signature="$2" public_key="$3" inspection_home="$4" status_file="$5"
    local signer_fingerprint primary_fingerprint valid_count

    repository_public_key_matches "$public_key" "$inspection_home" || return 1
    gpgv --status-fd 1 --keyring "$public_key" -- "$signature" "$installer" >"$status_file" 2>/dev/null || return 1
    if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|EXPSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|NO_PUBKEY)\b' \
        "$status_file"; then
        return 1
    fi
    valid_count="$(grep -c '^\[GNUPG:\] VALIDSIG ' "$status_file" || true)"
    [ "$valid_count" -eq 1 ] || return 1
    signer_fingerprint="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print toupper($3); exit }' "$status_file")"
    primary_fingerprint="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print toupper($NF); exit }' "$status_file")"
    [ "$signer_fingerprint" = "$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT" ] || return 1
    [ "$primary_fingerprint" = "$REPOSITORY_PRIMARY_FINGERPRINT" ]
}

update_installer() {
    # Skip in debug mode (protect local working copy) and force mode (non-interactive)
    { [ "$DEBUG" = "true" ] || [ "$FORCE" = "true" ]; } && return 0

    local update_dir release_json latest_version release_base
    update_dir="$(mktemp -d -- '/tmp/arch-linux-installer-update.XXXXXXXXXX')" || return 0
    chmod 0700 "$update_dir" || { cleanup_installer_update_dir "$update_dir"; return 0; }
    release_json="${update_dir}/release.json"
    if ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --connect-timeout 5 --max-time 10 --max-filesize 262144 \
        -H 'Accept: application/vnd.github+json' \
        --output "$release_json" -- "${UPDATE_REPO_API}/releases/latest"; then
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    if ! downloaded_file_is_within_size "$release_json" 262144 || \
        [ "$(grep -Eoc '"immutable"[[:space:]]*:[[:space:]]*true' "$release_json" || true)" -ne 1 ] || \
        [ "$(grep -Eoc '"immutable"[[:space:]]*:' "$release_json" || true)" -ne 1 ]; then
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    latest_version="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$release_json" | cut -d'"' -f4)" || true
    if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    # Skip if local version is already up to date or newer (e.g. dev build / pre-release)
    if [ "$(printf '%s\n%s\n' "$VERSION" "$latest_version" | sort -V | tail -n1)" = "$VERSION" ]; then
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    # Ask user (continue with current version if declined)
    if ! gum_confirm "Installer update available: ${VERSION} → ${latest_version}. Update now?"; then
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    release_base="https://github.com/snaplyze/arch-linux/releases/download/${latest_version}"
    local new_installer checksum_file signature_file public_key status_file inspection_home
    new_installer="${update_dir}/arch-linux-installer.sh"
    checksum_file="${update_dir}/arch-linux-installer.sh.sha256"
    signature_file="${update_dir}/arch-linux-installer.sh.sig"
    public_key="${update_dir}/arch-linux.gpg"
    status_file="${update_dir}/signature.status"
    inspection_home="${update_dir}/key-inspection"
    if ! gum_spin --title="Downloading Arch Linux Installer ${latest_version}..." -- \
        curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 5 --max-time 60 --max-filesize 1048576 \
            --output "$new_installer" -- "${release_base}/arch-linux-installer.sh" || \
        ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 5 --max-time 60 --max-filesize 1024 \
            --output "$checksum_file" -- "${release_base}/arch-linux-installer.sh.sha256" || \
        ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 5 --max-time 60 --max-filesize 65536 \
            --output "$signature_file" -- "${release_base}/arch-linux-installer.sh.sig" || \
        # Trust is deliberately taken from this running release, not from the newer release. A
        # planned signing-subkey change therefore needs the documented one-release compatibility
        # signature; a missed transition or emergency revocation fails closed to manual bootstrap.
        ! curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
            --connect-timeout 5 --max-time 60 --max-filesize 1048576 \
            --output "$public_key" -- "$REPOSITORY_PUBLIC_KEY_URL"; then
        gum_warn "Signed update assets are incomplete, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    if ! downloaded_file_is_within_size "$new_installer" 1048576 ||
        ! downloaded_file_is_within_size "$checksum_file" 1024 ||
        ! downloaded_file_is_within_size "$signature_file" 65536 ||
        ! downloaded_file_is_within_size "$public_key" 1048576; then
        gum_warn "Signed update assets exceed accepted size bounds, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    local checksum_line expected_sha actual_sha
    checksum_line="$(cat -- "$checksum_file")"
    if [ "$(wc -l <"$checksum_file")" -ne 1 ] || \
        ! [[ "$checksum_line" =~ ^([a-f0-9]{64})[[:space:]]\*arch-linux-installer\.sh$ ]]; then
        gum_warn "Update checksum manifest is invalid, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    expected_sha="${BASH_REMATCH[1]}"
    actual_sha="$(sha256sum "$new_installer" | awk '{ print $1 }')"
    if [ "$expected_sha" != "$actual_sha" ] || \
        ! installer_signature_matches "$new_installer" "$signature_file" "$public_key" "$inspection_home" "$status_file" || \
        ! bash -n "$new_installer" || \
        ! grep -qx "readonly VERSION='${latest_version}'" "$new_installer"; then
        gum_warn "Update authenticity verification failed, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi

    local script_path replacement='' saved_umask replacement_identity installed_sha source_info
    if [ "$DEBUG" = true ] || ! runtime_source_identity_is_stable ||
        ! grep -qx "readonly VERSION='${VERSION}'" "$SCRIPT_SOURCE_PATH"; then
        gum_warn "Could not prove a stable protected installer source, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    script_path="$SCRIPT_SOURCE_PATH"
    saved_umask="$(umask)"
    umask 077
    replacement="$(mktemp -- "${script_path}.new.XXXXXXXXXX")" || true
    umask "$saved_umask"
    if [ -z "$replacement" ] || [ ! -f "$replacement" ] || [ -L "$replacement" ]; then
        gum_warn "Could not stage the protected installer replacement, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    if ! install -o 0 -g 0 -m0700 -- "$new_installer" "$replacement"; then
        rm -f -- "$replacement"
        gum_warn "Could not write the protected installer replacement, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    replacement_identity="$(stat -Lc '%u:%a:%h:%d:%i' -- "$replacement")" || true
    installed_sha="$(sha256sum -- "$replacement" | awk '{ print $1 }')" || true
    if [[ ! "$replacement_identity" =~ ^0:700:1:[0-9]+:[0-9]+$ ]] ||
        [ "$installed_sha" != "$expected_sha" ] || ! bash -n "$replacement" ||
        ! runtime_source_identity_is_stable ||
        ! mv -fT -- "$replacement" "$script_path"; then
        if [ -e "$replacement" ] && [ ! -L "$replacement" ]; then
            rm -f -- "$replacement"
        fi
        gum_warn "Protected installer replacement failed closed, continuing with current version (${VERSION})..."
        cleanup_installer_update_dir "$update_dir"
        return 0
    fi
    source_info="$(runtime_source_file_is_safe "$script_path" "$SCRIPT_RUNTIME_CWD")" || true
    installed_sha="$(sha256sum -- "$script_path" | awk '{ print $1 }')" || true
    if [ -z "$source_info" ] || [ "$installed_sha" != "$expected_sha" ]; then
        gum_fail 'Installed updater bytes failed their protected-path readback'
        return 1
    fi
    read -r SCRIPT_SOURCE_PATH SCRIPT_SOURCE_IDENTITY <<<"$source_info"
    runtime_source_identity_is_stable || {
        gum_fail 'Installed updater source identity changed before restart'
        return 1
    }

    gum_info "Updated to ${latest_version}. Restarting installer..."
    cleanup_installer_update_dir "$update_dir"
    find "$SCRIPT_TMP_DIR" -xdev -depth -delete
    exec bash "$SCRIPT_SOURCE_PATH"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# START MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    if [ "$#" -eq 1 ] && [ "$1" = '--version' ]; then
        printf '%s\n' "$VERSION"
        exit 0
    fi
    runtime_init
    main "$@"
fi
