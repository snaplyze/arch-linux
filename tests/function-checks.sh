#!/usr/bin/env bash
# Everything here is consumed indirectly, which ShellCheck cannot see:
#   SC2034 - the ARCH_LINUX_* assignments are the inputs to validate_properties, which is sourced
#            from the installer rather than defined in this file.
#   SC2329 - gum_*/lsblk/block_* are stubs called by those same sourced functions.
#   SC2317 - the same finding under ShellCheck < 0.11, which renumbered it to SC2329. Both codes
#            are listed so the suite is clean on either version rather than only on the newest.
#   SC2016 - single-quoted '$' patterns are literal test payloads; expanding them would defeat
#            the very injection they are checking for.
# shellcheck disable=SC2034,SC2329,SC2317,SC2016
set -euo pipefail

script="${1:-arch-linux-installer.sh}"
repo_root="$(cd -- "$(dirname -- "$script")" && pwd)"
# Load function definitions without executing main.
# shellcheck disable=SC1090
source <(sed '/^main "\$@"/d' "$script")

if grep -Fq '61-gdm.rules' "$script"; then
    echo 'function check failed: NVIDIA path retains a stale GDM udev shadow override' >&2
    exit 1
fi

# Sourcing is definition-only: no runtime directory, persistent state or traps may be created by
# the installer itself. The test suite owns one exact private scratch directory and removes it.
[[ -z "$SCRIPT_TMP_DIR" && -z "$SCRIPT_CONFIG" && -z "$SCRIPT_LOG" ]]
function_runtime_dir="$(mktemp -d)"
chmod 0700 -- "$function_runtime_dir"
SCRIPT_TMP_DIR="$function_runtime_dir"
SCRIPT_LOG="${function_runtime_dir}/installer.log"
ERROR_MSG_TMP_FILE="${SCRIPT_TMP_DIR}/installer.err"
PROCESS_LOG_TMP_FILE="${SCRIPT_TMP_DIR}/process.log"
PROCESS_RET_TMP_FILE="${SCRIPT_TMP_DIR}/process.ret"
SCRIPT_CONFIG_TMP_FILE="${SCRIPT_TMP_DIR}/installer.conf.new"
TARGET_MOUNT_MARKER="${SCRIPT_TMP_DIR}/target-mounted"
CRYPTROOT_MARKER="${SCRIPT_TMP_DIR}/cryptroot-opened"
PROCESS_CGROUP_ACK_TMP_FILE="${SCRIPT_TMP_DIR}/process-cgroup.ready"

gum_fail() { :; }
log_fail() { :; }

# Sourcing the installer also installs its ERR/EXIT traps. Those expect installer state (FUNCNAME,
# the tmp dir) and, under this file's 'set -u', turn any failed assertion into an unrelated
# "FUNCNAME: unbound variable" instead of naming the line that actually failed.
trap - ERR EXIT
failed_line() { echo "function check failed at line $1" >&2; }
trap 'failed_line "$LINENO"' ERR
trap 'command rm -rf -- "$function_runtime_dir"' EXIT

[[ "$(partition_name /dev/sda 1)" == "/dev/sda1" ]]
[[ "$(partition_name /dev/nvme0n1 2)" == "/dev/nvme0n1p2" ]]
[[ "$(partition_name /dev/mmcblk0 1)" == "/dev/mmcblk0p1" ]]
[[ "$(grub_unencrypted_kernel_cmdline \
    rw zswap.enabled=0 quiet vt.global_cursor_default=0 loglevel=3 \
    rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false \
    root=PARTUUID=11111111-2222-3333-4444-555555555555 \
    rootflags=subvol=@ rootfstype=btrfs nowatchdog)" == \
    "zswap.enabled=0 vt.global_cursor_default=0 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false rootfstype=btrfs nowatchdog" ]]
[[ "$(grub_encrypted_kernel_cmdline \
    rw zswap.enabled=0 quiet vt.global_cursor_default=0 loglevel=3 \
    rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false \
    rd.luks.name=11111111-2222-3333-4444-555555555555=cryptroot root=/dev/mapper/cryptroot \
    rootflags=subvol=@ rootfstype=btrfs splash nowatchdog)" == \
    "zswap.enabled=0 vt.global_cursor_default=0 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false rd.luks.name=11111111-2222-3333-4444-555555555555=cryptroot rootfstype=btrfs splash nowatchdog" ]]
size_fixture="${function_runtime_dir}/download-size"
printf '1234' >"$size_fixture"
downloaded_file_is_within_size "$size_fixture" 4
if downloaded_file_is_within_size "$size_fixture" 3; then
    echo 'function check failed: oversized download passed the post-size gate' >&2
    exit 1
fi
rm -f -- "$size_fixture"
[[ "$(aur_helper_command paru-bin)" == "paru" ]]
[[ "$(aur_helper_command paru-git)" == "paru" ]]
[[ "$(aur_helper_command yay)" == "yay" ]]
[[ "$(aur_helper_command none)" == "pacman" ]]

aur_package_output_path_is_safe \
    '/var/lib/arch-linux-aur-builder/src-gnome-shell-extension-dash-to-dock-1/gnome-shell-extension-dash-to-dock-1:106-1-any.pkg.tar.zst'
aur_package_output_path_is_safe \
    '/var/lib/arch-linux-aur-builder/src-yay-5/yay-12.5.0-1-x86_64.pkg.tar.zst'
for unsafe_package_output in \
    '/var/lib/arch-linux-aur-builder/src-yay-6/yay-12.5.0-1-x86_64.pkg.tar.zst' \
    '/var/lib/arch-linux-aur-builder/src-yay-1/../yay-12.5.0-1-x86_64.pkg.tar.zst' \
    '/var/lib/arch-linux-aur-builder/src-yay-1/yay;touch-unsafe.pkg.tar.zst'; do
    if aur_package_output_path_is_safe "$unsafe_package_output"; then
        echo "function check failed: unsafe AUR package output path accepted: ${unsafe_package_output}" >&2
        exit 1
    fi
done

for timezone in Europe/Berlin UTC Etc/GMT+5 America/Argentina/Buenos_Aires; do
    timezone_identifier_is_safe "$timezone"
done
for timezone in ../etc/passwd Europe/../etc Europe//Berlin ./UTC Europe/. Europe/.. /UTC UTC/; do
    if timezone_identifier_is_safe "$timezone"; then
        echo "function check failed: unsafe timezone accepted: ${timezone}" >&2
        exit 1
    fi
done

for dependency in git gcc-libs 'glibc>=2.39' 'libalpm.so=15-64' python-build; do
    aur_dependency_is_safe "$dependency"
done
for dependency in --config /etc/passwd 'pkg;id' 'pkg=$(id)' 'pkg name'; do
    if aur_dependency_is_safe "$dependency"; then
        echo "function check failed: unsafe AUR dependency accepted: ${dependency}" >&2
        exit 1
    fi
done
aur_srcinfo_fixture=$'pkgbase = fixture\n\tmakedepends = git\n\tcheckdepends = python\n\npkgname = fixture\n\tdepends = glibc>=2.39\n\npkgname = unrelated-split\n\tdepends = ignored-dependency\n'
aur_srcinfo_identity_matches fixture "$aur_srcinfo_fixture"
[[ "$(aur_srcinfo_dependencies fixture <<<"$aur_srcinfo_fixture")" == $'git\npython\nglibc>=2.39' ]]
if aur_srcinfo_identity_matches other "$aur_srcinfo_fixture"; then
    echo 'function check failed: mismatched AUR package identity accepted' >&2
    exit 1
fi
if aur_srcinfo_dependencies fixture <<< $'pkgbase = fixture\n\tmakedepends = safe;id\n\npkgname = fixture' >/dev/null; then
    echo 'function check failed: command-like AUR dependency accepted' >&2
    exit 1
fi

reviewed_aur_packages=(
    plymouth-theme-archlinux paru paru-bin paru-git yay trizen pikaur
    gnome-shell-extension-dash-to-dock gnome-shell-extension-blur-my-shell
    gnome-shell-extension-just-perfection-desktop gnome-shell-extension-clipboard-indicator
    bibata-cursor-theme-bin
)
for reviewed_aur_package in "${reviewed_aur_packages[@]}"; do
    read -r aur_commit_fixture aur_tree_fixture aur_srcinfo_sha_fixture aur_pkgbuild_sha_fixture \
        < <(aur_review_metadata "$reviewed_aur_package")
    [[ "$aur_commit_fixture" =~ ^[a-f0-9]{40}$ ]]
    [[ "$aur_tree_fixture" =~ ^[a-f0-9]{64}$ ]]
    [[ "$aur_srcinfo_sha_fixture" =~ ^[a-f0-9]{64}$ ]]
    [[ "$aur_pkgbuild_sha_fixture" =~ ^[a-f0-9]{64}$ ]]
    aur_review_source_identity_matches "$reviewed_aur_package" \
        "$aur_commit_fixture" "$aur_tree_fixture" "$aur_srcinfo_sha_fixture"
    aur_review_pkgbuild_matches "$reviewed_aur_package" "$aur_pkgbuild_sha_fixture"
done
read -r _ _ _ clipboard_pkgbuild_sha_fixture \
    < <(aur_review_metadata gnome-shell-extension-clipboard-indicator)
[[ "$clipboard_pkgbuild_sha_fixture" = 0d7981518298ae9389a7a63f3ec9918c9f66c8805a24cd20690c661c1ec64fa8 ]]
if aur_review_metadata unreviewed-package >/dev/null; then
    echo 'function check failed: unreviewed AUR package accepted' >&2
    exit 1
fi
read -r aur_commit_fixture aur_tree_fixture aur_srcinfo_sha_fixture aur_pkgbuild_sha_fixture \
    < <(aur_review_metadata yay)
for changed_field in commit tree srcinfo; do
    test_commit="$aur_commit_fixture"
    test_tree="$aur_tree_fixture"
    test_srcinfo="$aur_srcinfo_sha_fixture"
    case "$changed_field" in
    commit) test_commit="0${test_commit:1}" ;;
    tree) test_tree="0${test_tree:1}" ;;
    srcinfo) test_srcinfo="0${test_srcinfo:1}" ;;
    esac
    if aur_review_source_identity_matches yay "$test_commit" "$test_tree" "$test_srcinfo"; then
        echo "function check failed: changed AUR ${changed_field} identity accepted" >&2
        exit 1
    fi
done
if aur_review_pkgbuild_matches yay "0${aur_pkgbuild_sha_fixture:1}"; then
    echo 'function check failed: changed reviewed PKGBUILD digest accepted' >&2
    exit 1
fi

# Only the mount view that really backs the disposable home may contain builder-owned inodes.
# A matching-looking path in a parent filesystem hidden below another mount remains foreign.
aur_builder_owned_inode_is_confined \
    /mnt /mnt /mnt/var/lib/arch-linux-aur-builder /mnt/var/lib/arch-linux-aur-builder
aur_builder_owned_inode_is_confined \
    /mnt /mnt /mnt/var/lib/arch-linux-aur-builder/src/pkg /mnt/var/lib/arch-linux-aur-builder
for confined_fixture in \
    '/mnt/boot|/mnt|/mnt/var/lib/arch-linux-aur-builder/src/pkg' \
    '/mnt|/mnt/var|/mnt/var/lib/arch-linux-aur-builder/src/pkg' \
    '/mnt|/mnt|/mnt/var/tmp/escaped' \
    '/mnt|/mnt|/mnt/var/lib/arch-linux-aur-builder-escape'; do
    IFS='|' read -r scan_mount_fixture home_mount_fixture logical_path_fixture <<<"$confined_fixture"
    if aur_builder_owned_inode_is_confined \
        "$scan_mount_fixture" "$home_mount_fixture" "$logical_path_fixture" \
        /mnt/var/lib/arch-linux-aur-builder; then
        echo "function check failed: foreign AUR UID inode accepted: ${logical_path_fixture}" >&2
        exit 1
    fi
done
for normalized_scan_path in /mnt /mnt/boot /tmp/arch-linux-target.123/other; do
    aur_builder_scan_path_is_normalized "$normalized_scan_path"
done
for unsafe_scan_path in /mnt//boot /mnt/./boot /mnt/../boot '/mnt/boot path' '/mnt/boot|path'; do
    if aur_builder_scan_path_is_normalized "$unsafe_scan_path"; then
        echo "function check failed: unsafe AUR scan path accepted: ${unsafe_scan_path}" >&2
        exit 1
    fi
done

# Cgroup handoff checks confinement even after a failed command. Foreign ownership invokes the
# exact UID-scoped cleanup and still fails; a clean successful handoff has no cleanup side effect.
(
    AUR_ACTIVE_BUILDER_UID=59999
    AUR_ACTIVE_BUILDER_HOME='/var/lib/arch-linux-aur-builder'
    AUR_ACTIVE_BUILDER_USER='archlinux-aur-builder'
    confinement_state=clean
    subid_state=clean
    cleanup_calls=0
    aur_builder_uid_has_live_process() { return 1; }
    aur_builder_subids_are_absent() { [ "$subid_state" = clean ]; }
    aur_builder_uid_target_is_confined() { [ "$confinement_state" = clean ]; }
    aur_builder_uid_cleanup_target() { cleanup_calls=$((cleanup_calls + 1)); }

    aur_builder_command_handoff_is_safe 0 false
    [ "$cleanup_calls" -eq 0 ]
    if aur_builder_command_handoff_is_safe 7 false; then
        echo 'function check failed: failed AUR builder command crossed root handoff' >&2
        exit 1
    fi
    [ "$cleanup_calls" -eq 0 ]
    subid_state=delegated
    if aur_builder_command_handoff_is_safe 0 false; then
        echo 'function check failed: delegated AUR subordinate ID crossed root handoff' >&2
        exit 1
    fi
    [ "$cleanup_calls" -eq 0 ]
    subid_state=clean
    confinement_state=foreign
    if aur_builder_command_handoff_is_safe 0 false; then
        echo 'function check failed: foreign AUR UID inode crossed root handoff' >&2
        exit 1
    fi
    [ "$cleanup_calls" -eq 1 ]
)

yay_dependency_fixture=$'pkgbase = yay\n\tmakedepends = go>=1.24\n\npkgname = yay\n\tdepends = pacman>6.1\n\tdepends = git\n'
[[ "$(aur_srcinfo_dependencies yay <<<"$yay_dependency_fixture")" = "$(aur_reviewed_dependencies yay)" ]]
yay_changed_dependency_fixture="${yay_dependency_fixture}"$'\tdepends = systemd\n'
if [ "$(aur_srcinfo_dependencies yay <<<"$yay_changed_dependency_fixture")" = \
    "$(aur_reviewed_dependencies yay)" ]; then
    echo 'function check failed: runtime-generated AUR dependency change matched reviewed closure' >&2
    exit 1
fi

aur_package_path_is_allowed bibata-cursor-theme-bin \
    usr/share/icons/Bibata-Modern-Classic/cursors/left_ptr -
aur_package_path_is_allowed gnome-shell-extension-dash-to-dock \
    usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com/extension.js -
aur_package_path_is_allowed paru etc/paru.conf -
aur_package_path_is_allowed pikaur usr/lib/python3.14/site-packages/pikaur/config.py -
for unsafe_aur_path in \
    etc/passwd usr/share/libalpm/hooks/evil.hook usr/lib/systemd/system/evil.service \
    usr/lib/python3.14/site-packages/evil.pth usr/share/gnome-shell/extensions/other/extension.js; do
    if aur_package_path_is_allowed gnome-shell-extension-dash-to-dock "$unsafe_aur_path" - ||
        aur_package_path_is_allowed pikaur "$unsafe_aur_path" -; then
        echo "function check failed: unsafe AUR path accepted: ${unsafe_aur_path}" >&2
        exit 1
    fi
done
aur_package_symlink_is_safe bibata-cursor-theme-bin \
    usr/share/icons/Bibata-Modern-Classic/cursors/default left_ptr
if aur_package_symlink_is_safe bibata-cursor-theme-bin \
    usr/share/icons/Bibata-Modern-Classic/cursors/default ../../../../../etc/passwd; then
    echo 'function check failed: escaping AUR symlink accepted' >&2
    exit 1
fi

# Process substitution hides a producer's non-zero status from mapfile. Both archive listings must
# complete successfully before the syntactically safe partial bytes can be parsed.
for failing_listing in paths details; do
    if (
        partial_archive="$(mktemp)"
        trap 'rm -f -- "$partial_archive"' EXIT
        aur_bsdtar_bounded() {
            case "$1" in
            -xOf)
                printf '%s\n' 'pkgname = yay'
                ;;
            -tf)
                printf '%s\n' .PKGINFO .BUILDINFO .MTREE usr/bin/yay
                [ "$failing_listing" != paths ]
                ;;
            --numeric-owner)
                [ "$2" = -tvf ] || return 1
                printf '%s\n' \
                    '-rw-r--r-- 0 0 0 1 Jan 01 00:00 .PKGINFO' \
                    '-rw-r--r-- 0 0 0 1 Jan 01 00:00 .BUILDINFO' \
                    '-rw-r--r-- 0 0 0 1 Jan 01 00:00 .MTREE' \
                    '-rwxr-xr-x 0 0 0 1 Jan 01 00:00 usr/bin/yay'
                [ "$failing_listing" != details ]
                ;;
            *) return 1 ;;
            esac
        }
        aur_package_archive_is_safe yay "$partial_archive"
    ); then
        echo "function check failed: partial non-zero AUR ${failing_listing} listing was accepted" >&2
        exit 1
    fi
done

# Parse only canonical numeric libarchive fields. Human owner names, leading-zero/oversized
# numbers and compressed payloads whose logical size crosses either ceiling all fail closed.
aur_mock_archive_accepts() (
    local path_fixture="$1" detail_fixture="$2" mock_archive
    mock_archive="$(mktemp)"
    trap 'rm -f -- "$mock_archive"' EXIT
    printf x >"$mock_archive"
    aur_bsdtar_bounded() {
        case "$1" in
        -xOf) printf '%s\n' 'pkgname = yay' ;;
        -tf) printf '%s\n' "$path_fixture" ;;
        --numeric-owner)
            [ "$2" = -tvf ] || return 1
            printf '%s\n' "$detail_fixture"
            ;;
        *) return 1 ;;
        esac
    }
    aur_archive_extended_metadata_is_absent() { return 0; }
    aur_package_archive_is_safe yay "$mock_archive"
)
aur_numeric_paths=$'.PKGINFO\n.BUILDINFO\n.MTREE\nusr/bin/yay'
aur_numeric_details=$'-rw-r--r-- 0 0 0 16 Jan 01 00:00 .PKGINFO\n-rw-r--r-- 0 0 0 10 Jan 01 00:00 .BUILDINFO\n-rw-r--r-- 0 0 0 7 Jan 01 00:00 .MTREE\n-rwxr-xr-x 0 0 0 4096 Jan 01 00:00 usr/bin/yay'
aur_mock_archive_accepts "$aur_numeric_paths" "$aur_numeric_details"
aur_mock_archive_accepts "$aur_numeric_paths" \
    "${aur_numeric_details/0 0 0 4096/0 0 0 268435456}"
for unsafe_numeric_details in \
    "${aur_numeric_details/0 0 0 4096/0 12345 0 4096}" \
    "${aur_numeric_details/0 0 0 4096/0 0 23456 4096}" \
    "${aur_numeric_details/0 0 0 4096/0 0 0 04096}" \
    "${aur_numeric_details/0 0 0 4096/0 0 0 99999999999}" \
    "${aur_numeric_details/0 0 0 4096/0 0 0 268435457}"; do
    if aur_mock_archive_accepts "$aur_numeric_paths" "$unsafe_numeric_details"; then
        echo 'function check failed: unsafe numeric AUR archive detail accepted' >&2
        exit 1
    fi
done
aur_aggregate_paths="${aur_numeric_paths}"$'\nusr/share/bash-completion/a\nusr/share/bash-completion/b\nusr/share/bash-completion/c\nusr/share/bash-completion/d\nusr/share/bash-completion/e'
aur_aggregate_details="${aur_numeric_details}"$'\n-rw-r--r-- 0 0 0 214748365 Jan 01 00:00 usr/share/bash-completion/a\n-rw-r--r-- 0 0 0 214748365 Jan 01 00:00 usr/share/bash-completion/b\n-rw-r--r-- 0 0 0 214748365 Jan 01 00:00 usr/share/bash-completion/c\n-rw-r--r-- 0 0 0 214748365 Jan 01 00:00 usr/share/bash-completion/d\n-rw-r--r-- 0 0 0 214748365 Jan 01 00:00 usr/share/bash-completion/e'
if aur_mock_archive_accepts "$aur_aggregate_paths" "$aur_aggregate_details"; then
    echo 'function check failed: oversized aggregate AUR payload accepted' >&2
    exit 1
fi

ARCH_LINUX_USERNAME='fixture-user'
fixture_home="/home/${ARCH_LINUX_USERNAME}"
for safe_user_path in \
    "${fixture_home}/.config/app.conf" "${fixture_home}/.arch-linux/system/init.sh"; do
    chroot_user_path_is_safe "$safe_user_path"
done
for unsafe_user_path in \
    "${fixture_home}-other/app.conf" "${fixture_home}/../other/app.conf" \
    "${fixture_home}/.config//app.conf" /etc/passwd; do
    if chroot_user_path_is_safe "$unsafe_user_path"; then
        echo "function check failed: unsafe user-home path accepted: ${unsafe_user_path}" >&2
        exit 1
    fi
done

# The pinned Gum archive is inspected before extraction. Exercise exact closure plus extra-member,
# traversal and symlink negative fixtures without executing any fixture bytes.
gum_archive_test_dir="$(mktemp -d)"
gum_payload_root="${gum_archive_test_dir}/payload"
gum_prefix="gum_${GUM_VERSION}_Linux_x86_64"
gum_members=(
    "${gum_prefix}/LICENSE"
    "${gum_prefix}/README.md"
    "${gum_prefix}/completions/gum.bash"
    "${gum_prefix}/completions/gum.fish"
    "${gum_prefix}/completions/gum.zsh"
    "${gum_prefix}/gum"
    "${gum_prefix}/manpages/gum.1.gz"
)
mkdir -p -- \
    "${gum_payload_root}/${gum_prefix}/completions" \
    "${gum_payload_root}/${gum_prefix}/manpages"
for member in "${gum_members[@]}"; do
    printf 'reviewed fixture: %s\n' "$member" >"${gum_payload_root}/${member}"
done
tar -czf "${gum_archive_test_dir}/good.tar.gz" -C "$gum_payload_root" "${gum_members[@]}"
gum_archive_is_safe "${gum_archive_test_dir}/good.tar.gz"

printf 'unexpected\n' >"${gum_payload_root}/${gum_prefix}/unexpected"
tar -czf "${gum_archive_test_dir}/extra.tar.gz" -C "$gum_payload_root" \
    "${gum_members[@]}" "${gum_prefix}/unexpected"
if gum_archive_is_safe "${gum_archive_test_dir}/extra.tar.gz"; then
    echo 'function check failed: Gum archive with an extra member passed' >&2
    exit 1
fi

command rm -f -- "${gum_payload_root}/${gum_prefix}/gum"
ln -s -- LICENSE "${gum_payload_root}/${gum_prefix}/gum"
tar -czf "${gum_archive_test_dir}/symlink.tar.gz" -C "$gum_payload_root" "${gum_members[@]}"
if gum_archive_is_safe "${gum_archive_test_dir}/symlink.tar.gz"; then
    echo 'function check failed: Gum archive with a symlinked executable passed' >&2
    exit 1
fi

command rm -f -- "${gum_payload_root}/${gum_prefix}/gum"
printf 'reviewed fixture\n' >"${gum_payload_root}/${gum_prefix}/gum"
tar -czf "${gum_archive_test_dir}/traversal.tar.gz" \
    --transform="s|${gum_prefix}/LICENSE|../escape|" \
    -C "$gum_payload_root" "${gum_members[@]}"
if gum_archive_is_safe "${gum_archive_test_dir}/traversal.tar.gz"; then
    echo 'function check failed: Gum archive with traversal passed' >&2
    exit 1
fi
command rm -rf -- "$gum_archive_test_dir"

gum_override_test_dir="$(mktemp -d)"
gum_override_file="${gum_override_test_dir}/arbitrary-root-target"
printf 'must remain unchanged\n' >"$gum_override_file"
gum_override_sha="$(sha256sum "$gum_override_file" | cut -d' ' -f1)"
if (GUM="$gum_override_file"; gum_init) 2>/dev/null; then
    echo 'function check failed: non-executable arbitrary GUM override passed' >&2
    exit 1
fi
[[ "$(sha256sum "$gum_override_file" | cut -d' ' -f1)" == "$gum_override_sha" ]]

ln -s -- /bin/true "${gum_override_test_dir}/gum-symlink"
if (GUM="${gum_override_test_dir}/gum-symlink"; gum_init) 2>/dev/null; then
    echo 'function check failed: symlinked GUM override passed' >&2
    exit 1
fi
[[ "$(readlink -- "${gum_override_test_dir}/gum-symlink")" == /bin/true ]]

gum_override_good="${gum_override_test_dir}/gum-good"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' 'gum version v${GUM_VERSION} (fixture)'" >"$gum_override_good"
chmod 0700 "$gum_override_good"
gum_override_good_sha="$(sha256sum "$gum_override_good" | cut -d' ' -f1)"
(GUM="$gum_override_good"; gum_init)
[[ "$(sha256sum "$gum_override_good" | cut -d' ' -f1)" == "$gum_override_good_sha" ]]
command rm -rf -- "$gum_override_test_dir"

[[ "$(locale_with_utf8 de_DE)" == "de_DE.UTF-8" ]]
[[ "$(locale_with_utf8 ru_RU)" == "ru_RU.UTF-8" ]]
[[ "$(locale_with_utf8 sr_RS@latin)" == "sr_RS.UTF-8@latin" ]]

# Sudoers drop-ins cross a private same-directory candidate, candidate visudo, atomic move and a
# final complete-policy visudo. Function seams model root metadata without weakening production.
sudoers_test_dir="$(mktemp -d)"
run_sudoers_install() (
    local target_root="$1" mode="$2" name="$3" rule="$4"
    chown() { :; }
    sudoers_directory_metadata_is_safe() {
        [ -d "$1" ] && [ ! -L "$1" ] && [ "$(stat -c '%a' -- "$1")" = 750 ]
    }
    sudoers_dropin_metadata_is_safe() {
        [ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -c '%a' -- "$1")" = 440 ] &&
            [ "$(stat -c '%h' -- "$1")" = 1 ]
    }
    arch-chroot() {
        local invoked_root="$1"
        shift
        [ "$invoked_root" = "$target_root" ] || return 1
        [ "$1" = /usr/bin/env ] && [ "$2" = LC_ALL=C ] && [ "$3" = visudo ] &&
            [ "$4" = -cf ] || return 1
        case "$5" in
        /etc/sudoers)
            if [ "$mode" = final-invalid ] && [ -e "${target_root}/etc/sudoers.d/${name}" ]; then
                return 1
            fi
            ;;
        /etc/sudoers.d/.*)
            [ "$mode" != candidate-invalid ] || return 1
            ;;
        /etc/sudoers.d/*) ;;
        *) return 1 ;;
        esac
    }
    install_validated_sudoers_dropin "$target_root" "$name" "$rule"
)

for sudoers_name in 10-installer-wheel 20-installer-pwfeedback; do
    sudoers_root="${sudoers_test_dir}/${sudoers_name}"
    mkdir -p -- "${sudoers_root}/etc/sudoers.d"
    chmod 0750 -- "${sudoers_root}/etc/sudoers.d"
    if [ "$sudoers_name" = 10-installer-wheel ]; then
        sudoers_rule='%wheel ALL=(ALL:ALL) ALL'
    else
        sudoers_rule='Defaults pwfeedback'
    fi
    run_sudoers_install "$sudoers_root" valid "$sudoers_name" "$sudoers_rule"
    [[ "$(stat -c '%a' -- "${sudoers_root}/etc/sudoers.d/${sudoers_name}")" == 440 ]]
    [[ "$(<"${sudoers_root}/etc/sudoers.d/${sudoers_name}")" == "$sudoers_rule" ]]
    run_sudoers_install "$sudoers_root" valid "$sudoers_name" "$sudoers_rule"
done

for sudoers_failure in candidate-invalid final-invalid; do
    sudoers_root="${sudoers_test_dir}/${sudoers_failure}"
    mkdir -p -- "${sudoers_root}/etc/sudoers.d"
    chmod 0750 -- "${sudoers_root}/etc/sudoers.d"
    if run_sudoers_install "$sudoers_root" "$sudoers_failure" \
        10-installer-wheel '%wheel ALL=(ALL:ALL) ALL'; then
        echo "function check failed: sudoers accepted ${sudoers_failure}" >&2
        exit 1
    fi
    [[ ! -e "${sudoers_root}/etc/sudoers.d/10-installer-wheel" ]]
done

sudoers_root="${sudoers_test_dir}/foreign"
mkdir -p -- "${sudoers_root}/etc/sudoers.d"
chmod 0750 -- "${sudoers_root}/etc/sudoers.d"
printf '%s\n' foreign >"${sudoers_root}/etc/sudoers.d/10-installer-wheel"
chmod 0440 -- "${sudoers_root}/etc/sudoers.d/10-installer-wheel"
if run_sudoers_install "$sudoers_root" valid 10-installer-wheel '%wheel ALL=(ALL:ALL) ALL'; then
    echo 'function check failed: foreign sudoers file was replaced' >&2
    exit 1
fi
[[ "$(<"${sudoers_root}/etc/sudoers.d/10-installer-wheel")" == foreign ]]
command rm -rf -- "$sudoers_test_dir"

# GDM 50 owns its policy under /etc; GDM 51 owns the same policy under /usr/lib. Both variants and
# pam_gnome_keyring.so are package files. Validate ownership, Qkk and exact records without changing
# either path, and reject shadow overrides, dirty packages, symlinks and unsupported module options.
gdm_pam_test_dir="$(mktemp -d)"
write_gdm_pam_fixture() {
    local destination="$1" auth_suffix="${2:-}"
    mkdir -p -- "$(dirname -- "$destination")"
    printf '%s\n' \
        "auth       optional                    pam_gnome_keyring.so${auth_suffix}" \
        'password   optional                    pam_gnome_keyring.so use_authtok' \
        'session    optional                    pam_gnome_keyring.so auto_start' \
        >"$destination"
}
run_gdm_pam_validation() (
    local target_root="$1" owned_relative="$2" mode="${3:-valid}"
    arch-chroot() {
        local invoked_root="$1"
        shift
        [ "$invoked_root" = "$target_root" ] || return 1
        case "$*" in
        '/usr/bin/env LC_ALL=C pacman -Q -- gdm gnome-keyring')
            [ "$mode" != 'missing-package' ]
            ;;
        '/usr/bin/env LC_ALL=C pacman -Qkk -- gdm gnome-keyring')
            if [ "$mode" = 'dirty-package' ]; then
                printf '%s\n' \
                    'warning: gdm: /etc/gdm/custom.conf (SHA256 checksum mismatch)' \
                    'gdm: 200 total files, 0 altered files' \
                    'gnome-keyring: 100 total files, 0 altered files'
            else
                printf '%s\n' \
                    'gdm: 200 total files, 0 altered files' \
                    'gnome-keyring: 100 total files, 0 altered files'
            fi
            ;;
        '/usr/bin/env LC_ALL=C pacman -Ql -- gdm')
            printf 'gdm %s\n' "$owned_relative"
            [ "$mode" != 'ambiguous-owner' ] || printf '%s\n' 'gdm /usr/lib/pam.d/gdm-password'
            ;;
        '/usr/bin/env LC_ALL=C pacman -Qo -- /usr/lib/security/pam_gnome_keyring.so')
            if [ "$mode" = 'wrong-module-owner' ]; then
                printf '%s\n' '/usr/lib/security/pam_gnome_keyring.so is owned by foreign 1-1'
            else
                printf '%s\n' '/usr/lib/security/pam_gnome_keyring.so is owned by gnome-keyring 1-1'
            fi
            ;;
        *) return 1 ;;
        esac
    }
    desktop_validate_gdm_keyring_pam "$target_root"
)

for gdm_generation in gnome50 gnome51; do
    gdm_root="${gdm_pam_test_dir}/${gdm_generation}"
    mkdir -p -- "${gdm_root}/usr/lib/security"
    printf '%s\n' module >"${gdm_root}/usr/lib/security/pam_gnome_keyring.so"
    if [ "$gdm_generation" = 'gnome50' ]; then
        gdm_owned='/etc/pam.d/gdm-password'
    else
        gdm_owned='/usr/lib/pam.d/gdm-password'
    fi
    write_gdm_pam_fixture "${gdm_root}${gdm_owned}"
    gdm_pam_sha="$(sha256sum "${gdm_root}${gdm_owned}" | cut -d' ' -f1)"
    run_gdm_pam_validation "$gdm_root" "$gdm_owned"
    [[ "$(sha256sum "${gdm_root}${gdm_owned}" | cut -d' ' -f1)" == "$gdm_pam_sha" ]]
done

invalid_root="${gdm_pam_test_dir}/invalid-option"
mkdir -p -- "${invalid_root}/usr/lib/security"
printf '%s\n' module >"${invalid_root}/usr/lib/security/pam_gnome_keyring.so"
write_gdm_pam_fixture "${invalid_root}/usr/lib/pam.d/gdm-password" ' try_first_pass'
if run_gdm_pam_validation "$invalid_root" /usr/lib/pam.d/gdm-password; then
    echo 'function check failed: unsupported GDM PAM module option was accepted' >&2
    exit 1
fi

for extra_pam_case in duplicate extra-control extra-option; do
    extra_pam_root="${gdm_pam_test_dir}/${extra_pam_case}"
    mkdir -p -- "${extra_pam_root}/usr/lib/security"
    printf '%s\n' module >"${extra_pam_root}/usr/lib/security/pam_gnome_keyring.so"
    write_gdm_pam_fixture "${extra_pam_root}/usr/lib/pam.d/gdm-password"
    case "${extra_pam_case}" in
        duplicate)
            printf '%s\n' 'auth optional pam_gnome_keyring.so' \
                >>"${extra_pam_root}/usr/lib/pam.d/gdm-password"
            ;;
        extra-control)
            printf '%s\n' 'auth required pam_gnome_keyring.so' \
                >>"${extra_pam_root}/usr/lib/pam.d/gdm-password"
            ;;
        extra-option)
            printf '%s\n' 'auth optional pam_gnome_keyring.so try_first_pass' \
                >>"${extra_pam_root}/usr/lib/pam.d/gdm-password"
            ;;
    esac
    if run_gdm_pam_validation "${extra_pam_root}" /usr/lib/pam.d/gdm-password; then
        echo "function check failed: extra GDM PAM record was accepted: ${extra_pam_case}" >&2
        exit 1
    fi
done

shadow_root="${gdm_pam_test_dir}/shadow"
mkdir -p -- "${shadow_root}/usr/lib/security"
printf '%s\n' module >"${shadow_root}/usr/lib/security/pam_gnome_keyring.so"
write_gdm_pam_fixture "${shadow_root}/usr/lib/pam.d/gdm-password"
write_gdm_pam_fixture "${shadow_root}/etc/pam.d/gdm-password"
if run_gdm_pam_validation "$shadow_root" /usr/lib/pam.d/gdm-password; then
    echo 'function check failed: shadow GDM PAM override was accepted' >&2
    exit 1
fi

symlink_root="${gdm_pam_test_dir}/symlink"
mkdir -p -- "${symlink_root}/usr/lib/pam.d" "${symlink_root}/usr/lib/security"
printf '%s\n' module >"${symlink_root}/foreign-pam"
printf '%s\n' module >"${symlink_root}/usr/lib/security/pam_gnome_keyring.so"
ln -s ../../../foreign-pam "${symlink_root}/usr/lib/pam.d/gdm-password"
if run_gdm_pam_validation "$symlink_root" /usr/lib/pam.d/gdm-password; then
    echo 'function check failed: symlinked GDM PAM policy was accepted' >&2
    exit 1
fi

for rejected_mode in dirty-package missing-package wrong-module-owner ambiguous-owner; do
    if run_gdm_pam_validation "${gdm_pam_test_dir}/gnome51" /usr/lib/pam.d/gdm-password "$rejected_mode"; then
        echo "function check failed: GDM PAM accepted ${rejected_mode}" >&2
        exit 1
    fi
done
command rm -rf -- "$gdm_pam_test_dir"

# arch-chroot mounts a private tmpfs on /tmp. Exercise the real No Screenshot Box helper with
# command stubs so the regression test proves that its verified archive crosses the chroot boundary
# through a unique root-owned directory and is cleaned after both outcomes.
no_screenshot_test_dir="$(mktemp -d)"
run_no_screenshot_box_install_test() (
    local mode="$1"
    local marker_prefix="${no_screenshot_test_dir}/${mode}"
    local archive_output=''
    ARCH_LINUX_USERNAME='extensiontest'
    SCRIPT_TMP_DIR="$no_screenshot_test_dir"

    curl() {
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-o' ] || [ "$1" = '--output' ]; then
                archive_output="$2"
                shift 2
            else
                shift
            fi
        done
        [ -n "$archive_output" ] || return 1
        printf 'reviewed extension archive\n' >"$archive_output"
    }
    sha256sum() {
        printf '%s  %s\n' "$NO_SCREENSHOT_BOX_ARCHIVE_SHA256" "$1"
    }
    mktemp() {
        printf '%q ' "$@" >"${marker_prefix}-mktemp.args"
        printf '\n' >>"${marker_prefix}-mktemp.args"
        printf '/mnt/var/lib/arch-linux-installer.%s\n' "$mode"
    }
    install() {
        printf '%q ' "$@" >"${marker_prefix}-install.args"
        printf '\n' >>"${marker_prefix}-install.args"
    }
    chmod() {
        printf '%q ' "$@" >"${marker_prefix}-chmod.args"
        printf '\n' >>"${marker_prefix}-chmod.args"
    }
    arch-chroot() {
        printf '%q ' "$@" >>"${marker_prefix}-chroot.calls"
        printf '\n' >>"${marker_prefix}-chroot.calls"
        case " $* " in
            *" gnome-extensions install --force --print-uuid /var/lib/arch-linux-installer.${mode}/no-screenshot-box-v6.shell-extension.zip "*)
                [ "$mode" = 'failure' ] && return 1
                printf '%s\n' "$NO_SCREENSHOT_BOX_UUID"
                ;;
            *)
                return 1
                ;;
        esac
    }
    rm() {
        printf '%q ' "$@" >>"${marker_prefix}-cleanup.calls"
        printf '\n' >>"${marker_prefix}-cleanup.calls"
        [ "$mode" = 'cleanup-failure' ] && return 1
        return 0
    }
    rmdir() {
        printf '%q ' "$@" >>"${marker_prefix}-rmdir.calls"
        printf '\n' >>"${marker_prefix}-rmdir.calls"
        return 0
    }

    chroot_install_no_screenshot_box
)

run_no_screenshot_box_install_test success
no_screenshot_stage_dir='/var/lib/arch-linux-installer.success'
no_screenshot_staged="${no_screenshot_stage_dir}/no-screenshot-box-v6.shell-extension.zip"
grep -qF -- '-d -- /mnt/var/lib/arch-linux-installer.XXXXXXXXXX' "${no_screenshot_test_dir}/success-mktemp.args"
grep -qF -- '-m0644' "${no_screenshot_test_dir}/success-install.args"
grep -qF -- "/mnt${no_screenshot_staged}" "${no_screenshot_test_dir}/success-install.args"
grep -qF -- "0755 -- /mnt${no_screenshot_stage_dir}" "${no_screenshot_test_dir}/success-chmod.args"
grep -qF -- "gnome-extensions install --force --print-uuid ${no_screenshot_staged}" "${no_screenshot_test_dir}/success-chroot.calls"
grep -qF -- "-f -- /mnt${no_screenshot_staged}" "${no_screenshot_test_dir}/success-cleanup.calls"
grep -qF -- "-- /mnt${no_screenshot_stage_dir}" "${no_screenshot_test_dir}/success-rmdir.calls"
if grep -qF -- ' chown ' "${no_screenshot_test_dir}/success-chroot.calls"; then
    echo 'function check failed: No Screenshot Box staging transferred ownership to the target user' >&2
    exit 1
fi
if grep -qF -- '/tmp/no-screenshot-box-v6.shell-extension.zip' "${no_screenshot_test_dir}/success-chroot.calls"; then
    echo 'function check failed: No Screenshot Box archive was staged in chroot-private /tmp' >&2
    exit 1
fi

if run_no_screenshot_box_install_test failure; then
    echo 'function check failed: failed No Screenshot Box install returned success' >&2
    exit 1
fi
grep -qF -- '-f -- /mnt/var/lib/arch-linux-installer.failure/no-screenshot-box-v6.shell-extension.zip' "${no_screenshot_test_dir}/failure-cleanup.calls"
grep -qF -- '-- /mnt/var/lib/arch-linux-installer.failure' "${no_screenshot_test_dir}/failure-rmdir.calls"
cleanup_failure_stderr="${no_screenshot_test_dir}/cleanup-failure.stderr"
if run_no_screenshot_box_install_test cleanup-failure 2>"$cleanup_failure_stderr"; then
    echo 'function check failed: No Screenshot Box staging cleanup failure returned success' >&2
    exit 1
fi
grep -qF -- 'Failed to remove No Screenshot Box staging file: /var/lib/arch-linux-installer.cleanup-failure/no-screenshot-box-v6.shell-extension.zip' "$cleanup_failure_stderr"
command rm -rf -- "$no_screenshot_test_dir"

# The repository public key must use the same chroot-visible boundary. Its cleanup removes only
# the exact staged file and exact empty mktemp directory; foreign content makes cleanup fail closed.
repository_key_stage_test_dir="$(mktemp -d)"
repository_key_stage_file="${repository_key_stage_test_dir}/arch-linux-repository-key.gpg"
printf 'public key fixture\n' >"$repository_key_stage_file"
cleanup_repository_key_staging \
    "$repository_key_stage_file" "$repository_key_stage_test_dir" \
    '/var/lib/arch-linux-installer-key.fixture/arch-linux-repository-key.gpg' \
    '/var/lib/arch-linux-installer-key.fixture'
[[ ! -e "$repository_key_stage_file" && ! -e "$repository_key_stage_test_dir" ]]

repository_key_stage_test_dir="$(mktemp -d)"
repository_key_stage_file="${repository_key_stage_test_dir}/arch-linux-repository-key.gpg"
printf 'public key fixture\n' >"$repository_key_stage_file"
printf 'foreign fixture\n' >"${repository_key_stage_test_dir}/foreign"
if cleanup_repository_key_staging \
    "$repository_key_stage_file" "$repository_key_stage_test_dir" \
    '/var/lib/arch-linux-installer-key.fixture/arch-linux-repository-key.gpg' \
    '/var/lib/arch-linux-installer-key.fixture' 2>/dev/null; then
    echo 'function check failed: repository key cleanup removed a directory with foreign content' >&2
    exit 1
fi
[[ ! -e "$repository_key_stage_file" ]]
[[ -f "${repository_key_stage_test_dir}/foreign" ]]
command rm -rf -- "$repository_key_stage_test_dir"

# Absolute guest symlinks must be resolved by the target root, never by a host-side /mnt test.
marble_asset_test_dir="$(mktemp -d)"
(
    arch-chroot() {
        printf '%q ' "$@" >>"${marble_asset_test_dir}/calls"
        printf '\n' >>"${marble_asset_test_dir}/calls"
        [ "$1" = '/mnt' ] && [ "$2" = '/usr/bin/test' ] && [ "$3" = '-f' ] && \
            [ "$4" = '/usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css' ]
    }

    chroot_marble_asset_file_exists \
        '/usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css'
    if chroot_marble_asset_file_exists '/usr/share/themes/missing/gnome-shell/gnome-shell.css'; then
        echo 'function check failed: missing target Marble asset passed validation' >&2
        exit 1
    fi
)
grep -qF -- '/mnt /usr/bin/test -f /usr/share/themes/ArchLinux-Marble-Blue-Filled-Dark/gnome-shell/gnome-shell.css' \
    "${marble_asset_test_dir}/calls"
command rm -rf -- "$marble_asset_test_dir"

# Experimental GDM activation uses the package's stable helper/status boundary. It accepts either
# active project state or the helper's deliberate Stock fallback; foreign/unsafe status fails.
marble_gdm_activation_test_dir="$(mktemp -d)"
run_marble_gdm_activation_test() (
    local mode="$1"
    local compatibility_helper='/usr/lib/arch-linux-marble-gdm/update-compatibility'

    arch-chroot() {
        printf '%q ' "$@" >>"${marble_gdm_activation_test_dir}/${mode}.calls"
        printf '\n' >>"${marble_gdm_activation_test_dir}/${mode}.calls"
        [ "$1" = '/mnt' ] || return 1
        shift
        case "$1" in
        /usr/bin/test)
            [ "$2" = '-x' ] && [ "$3" = "$compatibility_helper" ]
            ;;
        "$compatibility_helper")
            if [ "$#" -eq 1 ]; then
                : >"${marble_gdm_activation_test_dir}/${mode}.helper-called"
                return 0
            fi
            [ "$#" -eq 2 ] && [ "$2" = '--status' ] || return 1
            if [ "$mode" = 'active' ]; then
                printf '%s\n' active
            elif [ "$mode" = 'stock-fallback' ]; then
                printf '%s\n' stock
            else
                return 1
            fi
            ;;
        *) return 1 ;;
        esac
    }

    chroot_activate_marble_gdm
)

run_marble_gdm_activation_test active
[[ -f "${marble_gdm_activation_test_dir}/active.helper-called" ]]
run_marble_gdm_activation_test stock-fallback
[[ -f "${marble_gdm_activation_test_dir}/stock-fallback.helper-called" ]]
if run_marble_gdm_activation_test unsafe; then
    echo 'function check failed: unsafe/foreign Marble GDM status passed activation' >&2
    exit 1
fi
grep -qF -- '/mnt /usr/bin/test -x /usr/lib/arch-linux-marble-gdm/update-compatibility' \
    "${marble_gdm_activation_test_dir}/active.calls"
grep -qF -- '/mnt /usr/lib/arch-linux-marble-gdm/update-compatibility --status' \
    "${marble_gdm_activation_test_dir}/active.calls"
command rm -rf -- "$marble_gdm_activation_test_dir"

repository_configuration_ready || {
    echo 'function check failed: initial trust v1 repository failed its shipped-default gate' >&2
    exit 1
}
repository_configuration_is_valid \
    "$REPOSITORY_NAME" "$REPOSITORY_SERVER_URL" "$REPOSITORY_PUBLIC_KEY_URL" \
    "$REPOSITORY_PUBLIC_KEY_SHA256" "$REPOSITORY_PRIMARY_FINGERPRINT" \
    "$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT"
for invalid_repository_field in \
    'unsafe name|https://snaplyze.github.io/arch-linux/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg|2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67|8C78098D1EAC609CBC73536FB7D2C17447B90CB2|0AA6F2237FB9674623B6E824428D56A84F558F7C' \
    'arch-linux|https://snaplyze.github.io/arch-linux/main/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg|2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67|8C78098D1EAC609CBC73536FB7D2C17447B90CB2|0AA6F2237FB9674623B6E824428D56A84F558F7C' \
    'arch-linux|https://snaplyze.github.io/arch-linux/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/main/arch-linux.gpg|2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67|8C78098D1EAC609CBC73536FB7D2C17447B90CB2|0AA6F2237FB9674623B6E824428D56A84F558F7C' \
    'arch-linux|https://snaplyze.github.io/arch-linux/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg|not-a-sha256|8C78098D1EAC609CBC73536FB7D2C17447B90CB2|0AA6F2237FB9674623B6E824428D56A84F558F7C' \
    'arch-linux|https://snaplyze.github.io/arch-linux/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg|2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67|not-a-fingerprint|0AA6F2237FB9674623B6E824428D56A84F558F7C' \
    'arch-linux|https://snaplyze.github.io/arch-linux/repo/$arch|https://github.com/snaplyze/arch-linux/releases/download/1.0.0/arch-linux.gpg|2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67|8C78098D1EAC609CBC73536FB7D2C17447B90CB2|8C78098D1EAC609CBC73536FB7D2C17447B90CB2'; do
    IFS='|' read -r test_name test_server test_key_url test_sha test_primary test_signing <<<"$invalid_repository_field"
    if repository_configuration_is_valid "$test_name" "$test_server" "$test_key_url" "$test_sha" "$test_primary" "$test_signing"; then
        echo 'function check failed: invalid initial trust repository configuration passed' >&2
        exit 1
    fi
done

for readonly_name in REPOSITORY_TRUST_VERSION REPOSITORY_NAME REPOSITORY_SERVER_URL \
    REPOSITORY_PUBLIC_KEY_URL REPOSITORY_PUBLIC_KEY_SHA256 REPOSITORY_PRIMARY_FINGERPRINT \
    REPOSITORY_SIGNING_SUBKEY_FINGERPRINT REPOSITORY_PUBLICATION_READY; do
    # shellcheck disable=SC2030 # The dynamic readonly-name probe creates a false $! data-flow edge.
    if (printf -v "$readonly_name" '%s' unsafe 2>/dev/null); then
        echo "function check failed: trust constant is writable: ${readonly_name}" >&2
        exit 1
    fi
done

# The disposable M8 repository is inert by default. Its effective getters must resolve to the
# immutable production trust, and malformed/non-private contracts must fail without changing it.
[[ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = false ]]
[[ "$(repository_effective_server_url)" = "$REPOSITORY_SERVER_URL" ]]
[[ "$(repository_effective_public_key_url)" = "$REPOSITORY_PUBLIC_KEY_URL" ]]
[[ "$(repository_effective_public_key_sha256)" = "$REPOSITORY_PUBLIC_KEY_SHA256" ]]
[[ "$(repository_effective_primary_fingerprint)" = "$REPOSITORY_PRIMARY_FINGERPRINT" ]]
[[ "$(repository_effective_signing_fingerprint)" = "$REPOSITORY_SIGNING_SUBKEY_FINGERPRINT" ]]
repository_qemu_primary="$(printf 'A%.0s' {1..40})"
repository_qemu_signing="$(printf 'B%.0s' {1..40})"
repository_qemu_key_sha="$(printf 'a%.0s' {1..64})"
repository_qemu_ca_sha="$(printf 'c%.0s' {1..64})"
qemu_acceptance_repository_contract_apply
qemu_acceptance_repository_contract_line_is_valid 'schema=1'
qemu_acceptance_repository_contract_line_is_valid \
    'server_url=https://10.0.2.2:8443/repo/$arch'
qemu_acceptance_repository_contract_line_is_valid \
    "public_key_sha256=${repository_qemu_key_sha}"
for invalid_qemu_contract_line in \
    '2schema=1' \
    'public_key_sha256=' \
    'public-key-sha256=aaaaaaaa' \
    'public_key_sha256=aaaaaaaa;unsafe'; do
    if qemu_acceptance_repository_contract_line_is_valid "${invalid_qemu_contract_line}"; then
        echo "function check failed: malformed QEMU contract line passed: ${invalid_qemu_contract_line}" >&2
        exit 1
    fi
done
if repository_qemu_acceptance_configuration_is_valid \
    'https://10.0.2.2:8443/repo/$arch' \
    'https://10.0.2.2:8443/arch-linux.gpg' \
    "$repository_qemu_key_sha" \
    "$repository_qemu_primary" \
    "$repository_qemu_signing" \
    '/tmp/not-private.crt' \
    "$repository_qemu_ca_sha"; then
    echo 'function check failed: QEMU repository accepted a CA outside its private live root' >&2
    exit 1
fi
ARCH_LINUX_QEMU_ACCEPTANCE=true
ARCH_LINUX_QEMU_REPOSITORY_CONTRACT='/tmp/not-private.contract'
if qemu_acceptance_repository_contract_apply; then
    echo 'function check failed: QEMU repository accepted a contract outside its private live root' >&2
    exit 1
fi
unset ARCH_LINUX_QEMU_ACCEPTANCE ARCH_LINUX_QEMU_REPOSITORY_CONTRACT
[[ "$QEMU_ACCEPTANCE_REPOSITORY_ACTIVE" = false ]]

# The Marble verifier must bind gnome-shell to logind's validated greeter UID. GDM 50 does not
# guarantee a passwd entry named gdm, so a legacy `id -u gdm` lookup cannot be part of this path.
(
    eval "$(sed -n '/^gdm_shell_pid() {/,/^}/p' "${repo_root}/tests/vm/guest/verify.sh")"
    greeter_uid_fixture=973
    session_property() {
        [ "$1" = c7 ] && [ "$2" = User ]
        printf '%s' "${greeter_uid_fixture}"
    }
    pgrep() {
        [ "$1" = -u ] && [ "$2" = 973 ] && [ "$3" = -x ] && [ "$4" = gnome-shell ] ||
            return 1
        printf '4242'
    }
    [[ "$(gdm_shell_pid c7)" = 4242 ]]
    greeter_uid_fixture=gdm
    if gdm_shell_pid c7 >/dev/null 2>&1; then
        echo 'function check failed: Marble verifier accepted a non-numeric greeter UID' >&2
        exit 1
    fi
)
(
    eval "$(sed -n '/^stock_gdm_process_environment_is_valid() {/,/^}/p' \
        "${repo_root}/tests/vm/guest/verify.sh")"
    stock_gdm_process_environment_is_valid $'DCONF_PROFILE=gdm\nXDG_SESSION_TYPE=wayland'
    for invalid_environment in \
        $'XDG_SESSION_TYPE=wayland' \
        $'DCONF_PROFILE=/usr/share/arch-linux-marble-gdm/50.0.0/dconf/profile' \
        $'DCONF_PROFILE=gdm\nDCONF_PROFILE=gdm' \
        $'DCONF_PROFILE=gdm\nG_RESOURCE_OVERLAYS=/org/gnome/shell/theme=/tmp/project'; do
        if stock_gdm_process_environment_is_valid "${invalid_environment}"; then
            echo 'function check failed: Marble verifier accepted a non-Stock GDM environment' >&2
            exit 1
        fi
    done
)
(
    eval "$(sed -n '/^wait_for_desktop_initialization() {/,/^}/p' \
        "${repo_root}/tests/vm/guest/verify.sh")"
    initialization_fixture="$(mktemp -d)"
    trap 'rm -rf -- "${initialization_fixture}"' EXIT
    autostart="${initialization_fixture}/initialize.desktop"
    wait_for_desktop_initialization "${autostart}"
    : >"${autostart}"
    initialization_waits=0
    sleep() {
        initialization_waits=$((initialization_waits + 1))
        [ "${initialization_waits}" -lt 2 ] || rm -- "${autostart}"
    }
    wait_for_desktop_initialization "${autostart}"
    [ "${initialization_waits}" -eq 2 ]
    : >"${autostart}"
    sleep() { SECONDS=$((SECONDS + 301)); }
    if wait_for_desktop_initialization "${autostart}"; then
        echo 'function check failed: incomplete desktop initialization accepted' >&2
        exit 1
    fi
    [ -f "${autostart}" ] # The observer must not remove or execute a pending initializer.
    rm -- "${autostart}"
    ln -s missing-initializer "${autostart}"
    if wait_for_desktop_initialization "${autostart}"; then
        echo 'function check failed: linked desktop initializer accepted' >&2
        exit 1
    fi
)
(
    eval "$(sed -n '/^verify_dual_boot_phase() {/,/^}/p' \
        "${repo_root}/tests/vm/guest/verify.sh")"
    scenario=minimal-dualboot-ext4-systemdboot phase=neighbor run_id=fixture
    neighbor_hostname=ali-neighbor
    find_target() { printf '/dev/sda'; }
    mounted_source_device() { printf '/dev/sda2'; }
    partition_name() { printf '%s%s' "$1" "$2"; }
    hostname() { return 127; } # Not installed by the base-only neighboring system.
    cat() {
        case "$1" in
        /proc/sys/kernel/hostname) printf '%s' "${neighbor_hostname}" ;;
        /neighbor-preserved.txt) printf '%s' "${run_id}" ;;
        /proc/sys/kernel/random/boot_id) printf '11111111-1111-1111-1111-111111111111' ;;
        *) return 1 ;;
        esac
    }
    systemctl() { return 0; }
    getent() { return 0; }
    bootctl() { [ "$1" = is-installed ]; }
    verify_dual_boot_phase >/dev/null
    neighbor_probe="$(declare -f verify_dual_boot_phase find_target mounted_source_device \
        partition_name hostname cat systemctl getent bootctl)"
    if /usr/bin/bash -c 'set -e
        eval "$1"
        scenario=minimal-dualboot-ext4-systemdboot phase=neighbor run_id=fixture
        neighbor_hostname=wrong-system
        verify_dual_boot_phase' neighbor-probe "${neighbor_probe}" >/dev/null; then
        echo 'function check failed: wrong neighboring system accepted' >&2
        exit 1
    fi
)
(
    eval "$(sed -n '/^restart_gdm_after_profile_transition() {/,/^}/p' \
        "${repo_root}/tests/vm/guest/verify.sh")"
    username=vmtest
    gdm_actions=''
    wait_for_user_session() { printf '3'; }
    find_session() {
        [ "$1" = greeter ] && [ "$2" = gdm-greeter ] &&
            [ "$3" = gdm-launch-environment ]
        printf '1'
    }
    gdm_shell_pid() {
        case "$1" in
        1) printf '4242' ;;
        5) printf '5252' ;;
        *) return 1 ;;
        esac
    }
    systemctl() {
        case "$1" in
        stop | start) ;;
        *) return 1 ;;
        esac
        [ "$2" = gdm.service ]
        gdm_actions="${gdm_actions}${gdm_actions:+ }$1"
    }
    session_name_exists() { return 1; }
    kill() {
        [ "$1" = -0 ] && [ "$2" = 4242 ]
        return 1
    }
    wait_for_graphical_stack() { :; }
    wait_for_greeter() { printf '5'; }
    restart_gdm_after_profile_transition
    [ "${gdm_actions}" = 'stop start' ]
)

repository_key_fixture="${repo_root}/repository/trust/arch-linux.gpg"
repository_key_check_home="$(mktemp -d)"
repository_public_key_matches "$repository_key_fixture" "$repository_key_check_home"
command rm -rf -- "$repository_key_check_home"

# The downloaded certificate is exact, but GnuPG imports merge packets into an existing keyblock.
# Lock the post-import predicate independently so only one UID and one primary-certified signing
# subkey can inherit pacman's local trust.
repository_key_metadata_good=$'pub:u:255:22:B7D2C17447B90CB2:1700000000:0:::::cSC:\nfpr:::::::::8C78098D1EAC609CBC73536FB7D2C17447B90CB2:\nuid:u::::1700000000::fixture::Arch Linux repository <fixture@example.invalid>::::::::::0:\nsub:u:255:22:28D56A84F558F7C:1700000000:1800000000:::::s:\nfpr:::::::::0AA6F2237FB9674623B6E824428D56A84F558F7C:'
if ! repository_key_metadata_matches "$repository_key_metadata_good" trusted 1750000000; then
    echo 'function check failed: exact one-UID trusted keyblock was rejected' >&2
    exit 1
fi

# A QEMU milestone certificate is held to the same exact one-primary/one-signing-subkey predicate;
# only its expected fingerprints differ from the immutable production certificate.
repository_key_metadata_qemu="${repository_key_metadata_good//8C78098D1EAC609CBC73536FB7D2C17447B90CB2/${repository_qemu_primary}}"
repository_key_metadata_qemu="${repository_key_metadata_qemu//0AA6F2237FB9674623B6E824428D56A84F558F7C/${repository_qemu_signing}}"
repository_key_metadata_matches \
    "$repository_key_metadata_qemu" trusted 1750000000 \
    "$repository_qemu_primary" "$repository_qemu_signing"
if repository_key_metadata_matches "$repository_key_metadata_qemu" trusted 1750000000; then
    echo 'function check failed: QEMU certificate fingerprints replaced production defaults' >&2
    exit 1
fi

repository_key_metadata_untrusted="${repository_key_metadata_good/pub:u:/pub:-:}"
repository_key_metadata_untrusted="${repository_key_metadata_untrusted/sub:u:/sub:-:}"
repository_key_metadata_matches "$repository_key_metadata_untrusted" untrusted 1750000000
if repository_key_metadata_matches "$repository_key_metadata_untrusted" trusted 1750000000; then
    echo 'function check failed: untrusted pacman keyblock passed the TrustedOnly gate' >&2
    exit 1
fi

repository_key_extra_subkey=$'sub:u:255:22:1111111111111111:1700000000:1800000000:::::s:\nfpr:::::::::1111111111111111111111111111111111111111:'
repository_key_extra_uid='uid:u::::1700000001::fixture2::Second repository identity <second@example.invalid>::::::::::0:'
repository_key_extra_uat='uat:u::::1700000001::fixture-photo:::::::::0:'
repository_key_metadata_missing_uid="$(awk -F: '$1 != "uid"' <<<"$repository_key_metadata_good")"
for repository_key_metadata_bad in \
    "${repository_key_metadata_good}"$'\n'"${repository_key_extra_uid}" \
    "${repository_key_metadata_good}"$'\n'"${repository_key_extra_uat}" \
    "${repository_key_metadata_missing_uid}" \
    "${repository_key_metadata_good}"$'\n'"${repository_key_extra_subkey}" \
    "${repository_key_metadata_good/sub:u:255:22:28D56A84F558F7C:/${repository_key_extra_subkey}"$'\n'"sub:u:255:22:28D56A84F558F7C:}" \
    "${repository_key_metadata_good/pub:u:255:22:/pub:u:255:1:}" \
    "${repository_key_metadata_good/sub:u:255:22:/sub:u:255:1:}" \
    "${repository_key_metadata_good/cSC:/csSC:}" \
    "${repository_key_metadata_good/:::::s:/:::::se:}" \
    "${repository_key_metadata_good/cSC:/cSCE:}" \
    "${repository_key_metadata_good/:::::s:/:::::sA:}" \
    "${repository_key_metadata_good/:1800000000:::::s:/:1750000000:::::s:}" \
    "${repository_key_metadata_good/:1800000000:::::s:/:0:::::s:}" \
    "${repository_key_metadata_good/:1700000000:0:::::cSC:/:1700000000:1800000000:::::cSC:}" \
    "${repository_key_metadata_good/pub:u:/pub:r:}" \
    "${repository_key_metadata_good/uid:u:/uid:r:}" \
    "${repository_key_metadata_good/sub:u:/sub:e:}" \
    "${repository_key_metadata_good/sub:u:/sub:m:}" \
    "${repository_key_metadata_good/sub:u:/sub:q:}" \
    "${repository_key_metadata_good/sub:u:/sub:-:}" \
    "${repository_key_metadata_good}"$'\nsec:u:255:22:B7D2C17447B90CB2:1700000000:0:::::cSC:'; do
    if repository_key_metadata_matches "$repository_key_metadata_bad" trusted 1750000000; then
        echo 'function check failed: malformed or over-broad pacman keyblock passed' >&2
        exit 1
    fi
done

repository_key_tamper_dir="$(mktemp -d)"
cp -- "$repository_key_fixture" "${repository_key_tamper_dir}/arch-linux.gpg"
printf 'tamper\n' >>"${repository_key_tamper_dir}/arch-linux.gpg"
if repository_public_key_matches "${repository_key_tamper_dir}/arch-linux.gpg" "${repository_key_tamper_dir}/inspection"; then
    echo 'function check failed: tampered initial trust certificate passed' >&2
    exit 1
fi
command rm -rf -- "$repository_key_tamper_dir"

installer_signature_status_test_dir="$(mktemp -d)"
run_installer_signature_status_fixture() (
    local mode="$1"
    repository_public_key_matches() { :; }
    gpgv() {
        case "$mode" in
        valid)
            printf '%s\n' "[GNUPG:] VALIDSIG ${REPOSITORY_SIGNING_SUBKEY_FINGERPRINT} 2026-08-24 0 4 0 22 8 00 ${REPOSITORY_PRIMARY_FINGERPRINT}"
            ;;
        expired)
            printf '%s\n' \
                "[GNUPG:] EXPKEYSIG ${REPOSITORY_SIGNING_SUBKEY_FINGERPRINT} fixture" \
                "[GNUPG:] VALIDSIG ${REPOSITORY_SIGNING_SUBKEY_FINGERPRINT} 2026-08-24 0 4 0 22 8 00 ${REPOSITORY_PRIMARY_FINGERPRINT}"
            ;;
        duplicate)
            printf '%s\n' \
                "[GNUPG:] VALIDSIG ${REPOSITORY_SIGNING_SUBKEY_FINGERPRINT} 2026-08-24 0 4 0 22 8 00 ${REPOSITORY_PRIMARY_FINGERPRINT}" \
                "[GNUPG:] VALIDSIG ${REPOSITORY_SIGNING_SUBKEY_FINGERPRINT} 2026-08-24 0 4 0 22 8 00 ${REPOSITORY_PRIMARY_FINGERPRINT}"
            ;;
        esac
    }
    installer_signature_matches fixture-installer fixture-signature fixture-key \
        fixture-inspection "${installer_signature_status_test_dir}/${mode}.status"
)
run_installer_signature_status_fixture valid
if run_installer_signature_status_fixture expired; then
    echo 'function check failed: VALIDSIG plus EXPKEYSIG passed installer verification' >&2
    exit 1
fi
if run_installer_signature_status_fixture duplicate; then
    echo 'function check failed: duplicate VALIDSIG records passed installer verification' >&2
    exit 1
fi
command rm -rf -- "$installer_signature_status_test_dir"

# The GDM flag remains an independent structural gate.
marble_gdm_configuration_ready
if marble_gdm_configuration_is_valid false "$MARBLE_GDM_PACKAGE"; then
    echo 'function check failed: disabled Marble GDM package passed its separate gate' >&2
    exit 1
fi
if marble_gdm_configuration_is_valid true 'unsafe package name'; then
    echo 'function check failed: malformed Marble GDM package identity passed its gate' >&2
    exit 1
fi

DEBUG=true
ARCH_LINUX_INSTALLER_CONFIG_VERSION='1'
ARCH_LINUX_USERNAME='archuser'
ARCH_LINUX_HOSTNAME='arch-linux'
ARCH_LINUX_PASSWORD='strong-password'
ARCH_LINUX_FILESYSTEM='btrfs'
ARCH_LINUX_BOOTLOADER='systemd'
ARCH_LINUX_AUR_HELPER='yay'
ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER='mesa'
ARCH_LINUX_MICROCODE='none'
ARCH_LINUX_KERNEL='linux-zen'
ARCH_LINUX_BTRFS_SNAPPER_ENABLED='true'
ARCH_LINUX_BTRFS_ASSISTANT_ENABLED='true'
ARCH_LINUX_ENCRYPTION_ENABLED='true'
ARCH_LINUX_CORE_TWEAKS_ENABLED='true'
ARCH_LINUX_MULTILIB_ENABLED='true'
ARCH_LINUX_BOOTSPLASH_ENABLED='true'
ARCH_LINUX_HOUSEKEEPING_ENABLED='true'
ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='true'
ARCH_LINUX_DESKTOP_ENABLED='true'
ARCH_LINUX_GNOME_THEME_PROFILE='stock'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
ARCH_LINUX_DESKTOP_SLIM_ENABLED='false'
ARCH_LINUX_SAMBA_SHARE_ENABLED='true'
ARCH_LINUX_VM_SUPPORT_ENABLED='true'
ARCH_LINUX_ECN_ENABLED='true'
ARCH_LINUX_DUAL_BOOT_ENABLED='false'
ARCH_LINUX_KERNEL_ARGS=''
ARCH_LINUX_DISK='/dev/nvme0n1'
ARCH_LINUX_BOOT_PARTITION='/dev/nvme0n1p1'
ARCH_LINUX_ROOT_PARTITION='/dev/nvme0n1p2'
ARCH_LINUX_DISK_IDENTITY='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
ARCH_LINUX_BOOT_PARTITION_IDENTITY=''
ARCH_LINUX_ROOT_PARTITION_IDENTITY=''
ARCH_LINUX_TIMEZONE='Europe/Berlin'
ARCH_LINUX_LOCALE_LANG='de_DE'
ARCH_LINUX_LOCALE_GEN_LIST=('de_DE.UTF-8 UTF-8' 'en_US.UTF-8 UTF-8')
ARCH_LINUX_VCONSOLE_KEYMAP='de-latin1-nodeadkeys'
ARCH_LINUX_VCONSOLE_FONT=''
ARCH_LINUX_REFLECTOR_COUNTRY='Germany,France'
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='de'
ARCH_LINUX_DESKTOP_KEYBOARD_MODEL='pc105'
ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT='nodeadkeys'
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=''

# The schema-1 configuration contract is exactly 43 data-only records. Generation is atomic,
# private, deterministic and never persists the runtime password.
[[ "$VERSION" == '1.0.0' ]]
[[ "${#PERSISTED_CONFIG_KEYS[@]}" -eq 43 ]]
[[ "$(printf '%s\n' "${PERSISTED_CONFIG_KEYS[@]}" | sort -u | wc -l)" -eq 43 ]]
config_test_dir="$(mktemp -d)"
config_test_old_umask="$(umask)"
umask 077
saved_script_config="$SCRIPT_CONFIG"
SCRIPT_CONFIG="${config_test_dir}/installer.conf"
properties_generate
[[ "$(stat -c '%a' "$SCRIPT_CONFIG")" == '600' ]]
[[ "$(wc -l <"$SCRIPT_CONFIG")" -eq 43 ]]
[[ "$(cut -d= -f1 "$SCRIPT_CONFIG" | sort -u | wc -l)" -eq 43 ]]
grep -qxF 'ARCH_LINUX_INSTALLER_CONFIG_VERSION=1' "$SCRIPT_CONFIG"
grep -qxF 'ARCH_LINUX_LOCALE_GEN_LIST=de_DE.UTF-8 UTF-8;en_US.UTF-8 UTF-8' "$SCRIPT_CONFIG"
if grep -qF 'ARCH_LINUX_PASSWORD' "$SCRIPT_CONFIG"; then
    echo 'function check failed: runtime password was persisted' >&2
    exit 1
fi
if grep -qF 'Arch Linux Version:' "$script"; then
    echo 'function check failed: installed config would be prefixed with a non-data comment' >&2
    exit 1
fi
canonical_config="${config_test_dir}/canonical.conf"
cp -- "$SCRIPT_CONFIG" "$canonical_config"

# Generation validates the original Bash value, without command-substitution newline stripping,
# and leaves the prior atomic config unchanged on rejection.
for unsafe_runtime_hostname in $'arch-linux\n' $'arch-linux\n\n'; do
    ARCH_LINUX_HOSTNAME="$unsafe_runtime_hostname"
    if properties_generate; then
        echo 'function check failed: properties_generate normalized a trailing newline' >&2
        exit 1
    fi
    cmp -s -- "$SCRIPT_CONFIG" "$canonical_config"
done
ARCH_LINUX_HOSTNAME='arch-linux'

# A fresh preset may persist empty appearance choices until the visible selectors run. Empty is a
# typed pending value, not a missing key, and Stock remains the selector default.
fresh_config="${config_test_dir}/fresh.conf"
SCRIPT_CONFIG="$fresh_config"
unset ARCH_LINUX_GNOME_THEME_PROFILE ARCH_LINUX_GDM_THEME_PROFILE
properties_generate
grep -qxF 'ARCH_LINUX_GNOME_THEME_PROFILE=' "$fresh_config"
grep -qxF 'ARCH_LINUX_GDM_THEME_PROFILE=' "$fresh_config"
properties_load
[[ -v ARCH_LINUX_GNOME_THEME_PROFILE && -z "$ARCH_LINUX_GNOME_THEME_PROFILE" ]]
[[ -v ARCH_LINUX_GDM_THEME_PROFILE && -z "$ARCH_LINUX_GDM_THEME_PROFILE" ]]
SCRIPT_CONFIG="${config_test_dir}/installer.conf"
properties_load "$canonical_config"

# Loading occurs in two phases. A complete valid file replaces all persisted state while leaving
# ARCH_LINUX_PASSWORD untouched and reconstructing the locale array exactly.
for config_key in "${PERSISTED_CONFIG_KEYS[@]}"; do
    unset "$config_key"
done
ARCH_LINUX_HOSTNAME='sentinel-before-valid-load'
ARCH_LINUX_PASSWORD='runtime-only-secret'
ARCH_LINUX_LOCALE_GEN_LIST=('sentinel locale')
properties_load
[[ "$ARCH_LINUX_INSTALLER_CONFIG_VERSION" == '1' ]]
[[ "$ARCH_LINUX_HOSTNAME" == 'arch-linux' ]]
[[ "$ARCH_LINUX_PASSWORD" == 'runtime-only-secret' ]]
[[ "${#ARCH_LINUX_LOCALE_GEN_LIST[@]}" -eq 2 ]]
[[ "${ARCH_LINUX_LOCALE_GEN_LIST[0]}" == 'de_DE.UTF-8 UTF-8' ]]
[[ "${ARCH_LINUX_LOCALE_GEN_LIST[1]}" == 'en_US.UTF-8 UTF-8' ]]
properties_generate
cmp -s -- "$SCRIPT_CONFIG" "$canonical_config"

config_error_log="${config_test_dir}/errors"
gum_fail() { printf '%s\n' "$*" >>"$config_error_log"; }
expect_config_reject() {
    local description="$1" candidate="$2" expected_error="$3"
    ARCH_LINUX_INSTALLER_CONFIG_VERSION='1'
    ARCH_LINUX_HOSTNAME='unchanged-host'
    ARCH_LINUX_USERNAME='unchanged-user'
    ARCH_LINUX_PASSWORD='runtime-only-secret'
    ARCH_LINUX_LOCALE_GEN_LIST=('unchanged locale')
    : >"$config_error_log"
    if properties_load "$candidate"; then
        echo "function check failed: invalid config accepted (${description})" >&2
        exit 1
    fi
    grep -qF -- "$expected_error" "$config_error_log" || {
        echo "function check failed: unclear config error (${description})" >&2
        exit 1
    }
    [[ "$ARCH_LINUX_INSTALLER_CONFIG_VERSION" == '1' ]]
    [[ "$ARCH_LINUX_HOSTNAME" == 'unchanged-host' ]]
    [[ "$ARCH_LINUX_USERNAME" == 'unchanged-user' ]]
    [[ "$ARCH_LINUX_PASSWORD" == 'runtime-only-secret' ]]
    [[ "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" == 'unchanged locale' ]]
}

candidate="${config_test_dir}/unknown.conf"
cp -- "$canonical_config" "$candidate"
printf '%s\n' 'ARCH_LINUX_PASSWORD=must-not-load' >>"$candidate"
expect_config_reject 'unknown key' "$candidate" 'unknown key ARCH_LINUX_PASSWORD'

candidate="${config_test_dir}/duplicate.conf"
cp -- "$canonical_config" "$candidate"
printf '%s\n' 'ARCH_LINUX_HOSTNAME=other-host' >>"$candidate"
expect_config_reject 'duplicate key' "$candidate" 'duplicate key ARCH_LINUX_HOSTNAME'

candidate="${config_test_dir}/missing.conf"
sed '/^ARCH_LINUX_HOSTNAME=/d' "$canonical_config" >"$candidate"
expect_config_reject 'missing key' "$candidate" 'missing key ARCH_LINUX_HOSTNAME'

candidate="${config_test_dir}/wrong-schema.conf"
sed 's/^ARCH_LINUX_INSTALLER_CONFIG_VERSION=1$/ARCH_LINUX_INSTALLER_CONFIG_VERSION=invalid/' "$canonical_config" >"$candidate"
expect_config_reject 'wrong schema' "$candidate" 'invalid value for ARCH_LINUX_INSTALLER_CONFIG_VERSION'

candidate="${config_test_dir}/quoted.conf"
sed "s/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME='arch-linux'/" "$canonical_config" >"$candidate"
expect_config_reject 'shell quoting' "$candidate" 'invalid value for ARCH_LINUX_HOSTNAME'

candidate="${config_test_dir}/comment.conf"
sed 's/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME=arch-linux # comment/' "$canonical_config" >"$candidate"
expect_config_reject 'trailing shell comment' "$candidate" 'invalid value for ARCH_LINUX_HOSTNAME'

command_marker="${config_test_dir}/command-ran"
candidate="${config_test_dir}/substitution.conf"
sed "s|^ARCH_LINUX_HOSTNAME=.*|ARCH_LINUX_HOSTNAME=\$(touch ${command_marker})|" "$canonical_config" >"$candidate"
expect_config_reject 'command substitution' "$candidate" 'invalid value for ARCH_LINUX_HOSTNAME'
[[ ! -e "$command_marker" ]]

candidate="${config_test_dir}/backticks.conf"
sed 's/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME=`id`/' "$canonical_config" >"$candidate"
expect_config_reject 'backticks' "$candidate" 'invalid value for ARCH_LINUX_HOSTNAME'

candidate="${config_test_dir}/expansion.conf"
sed 's/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME=${PATH}/' "$canonical_config" >"$candidate"
expect_config_reject 'parameter expansion' "$candidate" 'invalid value for ARCH_LINUX_HOSTNAME'

candidate="${config_test_dir}/function.conf"
cp -- "$canonical_config" "$candidate"
printf '%s\n' 'payload() { touch /tmp/should-not-run; }' >>"$candidate"
expect_config_reject 'function definition' "$candidate" 'is not a KEY=VALUE record'

candidate="${config_test_dir}/timezone-traversal.conf"
sed 's|^ARCH_LINUX_TIMEZONE=.*|ARCH_LINUX_TIMEZONE=Europe/../../etc|' "$canonical_config" >"$candidate"
expect_config_reject 'timezone traversal' "$candidate" 'invalid value for ARCH_LINUX_TIMEZONE'

candidate="${config_test_dir}/multiline.conf"
cp -- "$canonical_config" "$candidate"
printf '%s\n' 'touch /tmp/should-not-run' >>"$candidate"
expect_config_reject 'multiline injection' "$candidate" 'is not a KEY=VALUE record'

candidate="${config_test_dir}/blank-line.conf"
cp -- "$canonical_config" "$candidate"
printf '\n' >>"$candidate"
expect_config_reject 'blank record' "$candidate" 'is not a KEY=VALUE record'

candidate="${config_test_dir}/bad-list.conf"
sed 's/^ARCH_LINUX_LOCALE_GEN_LIST=.*/ARCH_LINUX_LOCALE_GEN_LIST=de_DE.UTF-8 UTF-8;touch owned/' "$canonical_config" >"$candidate"
expect_config_reject 'list injection' "$candidate" 'invalid value for ARCH_LINUX_LOCALE_GEN_LIST'

# Byte preflight runs before Bash read can discard NUL or normalize another non-schema byte.
# Exercise NUL at every structural position plus the remaining forbidden byte classes.
write_forbidden_byte_candidate() {
    local output="$1" position="$2" encoded_byte="$3" line
    case "$position" in
    prefix)
        printf '%b' "$encoded_byte" >"$output"
        cat -- "$canonical_config" >>"$output"
        ;;
    middle)
        : >"$output"
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" == ARCH_LINUX_GNOME_THEME_PROFILE=* ]]; then
                {
                    printf '%s' 'ARCH_LINUX_GNOME_THEME_PROFILE=st'
                    printf '%b' "$encoded_byte"
                    printf '%s\n' 'ock'
                } >>"$output"
            else
                printf '%s\n' "$line" >>"$output"
            fi
        done <"$canonical_config"
        ;;
    suffix)
        cat -- "$canonical_config" >"$output"
        printf '%b' "$encoded_byte" >>"$output"
        ;;
    *) return 1 ;;
    esac
}
for byte_case in nul-prefix nul-middle nul-suffix cr tab esc del high-byte; do
    candidate="${config_test_dir}/${byte_case}.conf"
    case "$byte_case" in
    nul-prefix) write_forbidden_byte_candidate "$candidate" prefix '\000' ;;
    nul-middle) write_forbidden_byte_candidate "$candidate" middle '\000' ;;
    nul-suffix) write_forbidden_byte_candidate "$candidate" suffix '\000' ;;
    cr) write_forbidden_byte_candidate "$candidate" middle '\015' ;;
    tab) write_forbidden_byte_candidate "$candidate" middle '\011' ;;
    esc) write_forbidden_byte_candidate "$candidate" middle '\033' ;;
    del) write_forbidden_byte_candidate "$candidate" middle '\177' ;;
    high-byte) write_forbidden_byte_candidate "$candidate" middle '\200' ;;
    esac
    expect_config_reject "$byte_case" "$candidate" 'contains a control or non-ASCII byte'
done

# Every allowlisted key has an independently exercised invalid type/value. The canonical positive
# fixture above exercises the same complete set with valid values, including permitted empties.
declare -A invalid_config_values=(
    [ARCH_LINUX_INSTALLER_CONFIG_VERSION]='invalid'
    [ARCH_LINUX_HOSTNAME]='Upper_Host'
    [ARCH_LINUX_USERNAME]='0user'
    [ARCH_LINUX_DISK]='relative-disk'
    [ARCH_LINUX_BOOT_PARTITION]='boot-partition'
    [ARCH_LINUX_ROOT_PARTITION]='root-partition'
    [ARCH_LINUX_DISK_IDENTITY]='not-a-sha256'
    [ARCH_LINUX_BOOT_PARTITION_IDENTITY]='not-a-sha256'
    [ARCH_LINUX_ROOT_PARTITION_IDENTITY]='not-a-sha256'
    [ARCH_LINUX_FILESYSTEM]='xfs'
    [ARCH_LINUX_BOOTLOADER]='lilo'
    [ARCH_LINUX_DUAL_BOOT_ENABLED]='yes'
    [ARCH_LINUX_BTRFS_SNAPPER_ENABLED]='yes'
    [ARCH_LINUX_BTRFS_ASSISTANT_ENABLED]='yes'
    [ARCH_LINUX_ENCRYPTION_ENABLED]='yes'
    [ARCH_LINUX_TIMEZONE]='Europe/Berlin;id'
    [ARCH_LINUX_LOCALE_LANG]='de_DE.UTF-8'
    [ARCH_LINUX_LOCALE_GEN_LIST]='touch owned'
    [ARCH_LINUX_REFLECTOR_COUNTRY]='Germany|France'
    [ARCH_LINUX_VCONSOLE_KEYMAP]='de keymap'
    [ARCH_LINUX_VCONSOLE_FONT]='font name'
    [ARCH_LINUX_KERNEL]='--root'
    [ARCH_LINUX_KERNEL_ARGS]='quiet;id'
    [ARCH_LINUX_MICROCODE]='cpu-code'
    [ARCH_LINUX_CORE_TWEAKS_ENABLED]='yes'
    [ARCH_LINUX_MULTILIB_ENABLED]='yes'
    [ARCH_LINUX_AUR_HELPER]='pacaur'
    [ARCH_LINUX_BOOTSPLASH_ENABLED]='yes'
    [ARCH_LINUX_HOUSEKEEPING_ENABLED]='yes'
    [ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED]='yes'
    [ARCH_LINUX_DESKTOP_ENABLED]='yes'
    [ARCH_LINUX_GNOME_THEME_PROFILE]='custom'
    [ARCH_LINUX_GDM_THEME_PROFILE]='custom'
    [ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER]='vesa'
    [ARCH_LINUX_DESKTOP_EXTRAS_ENABLED]='yes'
    [ARCH_LINUX_DESKTOP_SLIM_ENABLED]='yes'
    [ARCH_LINUX_DESKTOP_KEYBOARD_MODEL]='pc 105'
    [ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT]='us;id'
    [ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT]='nodead keys'
    [ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND]='ru+ua'
    [ARCH_LINUX_SAMBA_SHARE_ENABLED]='yes'
    [ARCH_LINUX_VM_SUPPORT_ENABLED]='yes'
    [ARCH_LINUX_ECN_ENABLED]='yes'
)
[[ "${#invalid_config_values[@]}" -eq 43 ]]
for config_key in "${PERSISTED_CONFIG_KEYS[@]}"; do
    [ -n "${invalid_config_values[$config_key]+set}" ] || {
        echo "function check failed: no invalid fixture for ${config_key}" >&2
        exit 1
    }
    candidate="${config_test_dir}/invalid-type.conf"
    while IFS= read -r config_record; do
        if [[ "$config_record" == "${config_key}="* ]]; then
            printf '%s=%s\n' "$config_key" "${invalid_config_values[$config_key]}"
        else
            printf '%s\n' "$config_record"
        fi
    done <"$canonical_config" >"$candidate"
    expect_config_reject "invalid value for ${config_key}" "$candidate" "invalid value for ${config_key}"
done

# Kernel names cross the privileged pacstrap boundary. Exercise every rejected character class and
# especially an option-like value; no config value may change pacman's argument parsing.
for invalid_kernel in '--root' 'Linux' 'linux zen' 'linux/custom'; do
    candidate="${config_test_dir}/invalid-kernel.conf"
    sed "s|^ARCH_LINUX_KERNEL=.*|ARCH_LINUX_KERNEL=${invalid_kernel}|" \
        "$canonical_config" >"$candidate"
    expect_config_reject "invalid kernel ${invalid_kernel}" "$candidate" \
        'invalid value for ARCH_LINUX_KERNEL'
done

candidate="${config_test_dir}/writable.conf"
cp -- "$canonical_config" "$candidate"
chmod 666 "$candidate"
expect_config_reject 'writable permissions' "$candidate" 'is group- or world-writable'

candidate="${config_test_dir}/oversized.conf"
cp -- "$canonical_config" "$candidate"
truncate -s 65537 "$candidate"
expect_config_reject 'oversized config' "$candidate" 'exceeds 65536 bytes'

candidate="${config_test_dir}/symlink.conf"
ln -s -- "$canonical_config" "$candidate"
expect_config_reject 'symlink config' "$candidate" 'is a symlink'

candidate="${config_test_dir}/hardlink.conf"
ln -- "$canonical_config" "$candidate"
expect_config_reject 'hard-linked config' "$candidate" 'must have exactly one hard link'
rm -f -- "$candidate"

# Swap the pathname immediately after the parser opens its descriptor. The open inode remains
# valid, but the pathname identity no longer matches and no parsed state may be committed.
candidate="${config_test_dir}/swap-race.conf"
replacement="${config_test_dir}/swap-race.replacement"
cp -- "$canonical_config" "$candidate"
sed 's/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME=swapped-host/' "$canonical_config" >"$replacement"
hostname_before_swap="$ARCH_LINUX_HOSTNAME"
if (
    properties_config_snapshot_captured() {
        mv -fT -- "$replacement" "$candidate"
    }
    properties_load "$candidate"
); then
    echo 'function check failed: config pathname swap passed stable-FD loading' >&2
    exit 1
fi
[[ "$ARCH_LINUX_HOSTNAME" == "$hostname_before_swap" ]]

# Same-inode, same-size edits after byte validation and while the immutable snapshot is parsed must
# invalidate the source identity without changing any runtime value.
mutate_config_hostname_in_place() {
    local mutation_target="$1" old_value="$2" new_value="$3"
    /usr/bin/python3 -I -S - "$mutation_target" "$old_value" "$new_value" <<'PY'
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
old = sys.argv[2].encode("ascii")
new = sys.argv[3].encode("ascii")
if len(old) != len(new):
    raise SystemExit("same-size mutation fixture differs in length")
descriptor = os.open(path, os.O_RDWR | getattr(os, "O_CLOEXEC", 0))
try:
    data = os.pread(descriptor, 65537, 0)
    marker = b"ARCH_LINUX_HOSTNAME=" + old + b"\n"
    position = data.find(marker)
    if position < 0:
        raise SystemExit("hostname mutation marker is absent")
    value_offset = position + len(b"ARCH_LINUX_HOSTNAME=")
    if os.pwrite(descriptor, new, value_offset) != len(new):
        raise SystemExit("hostname mutation write was incomplete")
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
}

for mutation_phase in captured record; do
    candidate="${config_test_dir}/same-inode-${mutation_phase}.conf"
    sed 's/^ARCH_LINUX_HOSTNAME=.*/ARCH_LINUX_HOSTNAME=alpha/' \
        "$canonical_config" >"$candidate"
    chmod 0600 -- "$candidate"
    ARCH_LINUX_HOSTNAME='unchanged-host'
    if (
        if [ "$mutation_phase" = captured ]; then
            properties_config_snapshot_captured() {
                mutate_config_hostname_in_place "$candidate" alpha bravo
            }
        else
            record_hook_ran=false
            properties_config_snapshot_record_parsed() {
                if [ "$record_hook_ran" = false ]; then
                    record_hook_ran=true
                    mutate_config_hostname_in_place "$candidate" alpha bravo
                fi
            }
        fi
        properties_load "$candidate"
    ); then
        echo "function check failed: same-inode ${mutation_phase} mutation passed snapshot loading" >&2
        exit 1
    fi
    [[ "$ARCH_LINUX_HOSTNAME" == 'unchanged-host' ]]
    grep -qxF 'ARCH_LINUX_HOSTNAME=bravo' "$candidate"
done

# Record order is not executable syntax and does not affect parsing.
candidate="${config_test_dir}/reordered.conf"
tac "$canonical_config" >"$candidate"
properties_load "$candidate"
[[ "$ARCH_LINUX_HOSTNAME" == 'arch-linux' ]]
[[ "${#ARCH_LINUX_LOCALE_GEN_LIST[@]}" -eq 2 ]]

# Invalid runtime state must not replace the last known-good config or leave a temporary sibling.
SCRIPT_CONFIG="${config_test_dir}/atomic.conf"
cp -- "$canonical_config" "$SCRIPT_CONFIG"
config_before_sha="$(sha256sum "$SCRIPT_CONFIG" | cut -d' ' -f1)"
ARCH_LINUX_HOSTNAME=$'valid-host\nARCH_LINUX_USERNAME=injected'
if properties_generate; then
    echo 'function check failed: generated a multiline runtime value' >&2
    exit 1
fi
[[ "$(sha256sum "$SCRIPT_CONFIG" | cut -d' ' -f1)" == "$config_before_sha" ]]
if compgen -G "${SCRIPT_CONFIG}.tmp.*" >/dev/null; then
    echo 'function check failed: failed generation left a temporary config' >&2
    exit 1
fi
ARCH_LINUX_HOSTNAME='arch-linux'

# The locale value must remain an array; accepting a scalar would silently lose list semantics.
unset ARCH_LINUX_LOCALE_GEN_LIST
printf -v ARCH_LINUX_LOCALE_GEN_LIST '%s' 'de_DE.UTF-8 UTF-8'
if properties_generate; then
    echo 'function check failed: scalar locale list passed generation' >&2
    exit 1
fi
[[ "$(sha256sum "$SCRIPT_CONFIG" | cut -d' ' -f1)" == "$config_before_sha" ]]
ARCH_LINUX_LOCALE_GEN_LIST=('de_DE.UTF-8 UTF-8' 'en_US.UTF-8 UTF-8')

gum_fail() { :; }
SCRIPT_CONFIG="$saved_script_config"
umask "$config_test_old_umask"
command rm -rf -- "$config_test_dir"

validate_properties

validation_report_file="$(mktemp)"
rm -f -- "$validation_report_file"
gum_fail() { printf 'gum\n' >>"$validation_report_file"; }
log_fail() { printf 'log\n' >>"$validation_report_file"; }
ARCH_LINUX_USERNAME='bad user;rm'
if validate_properties; then
    echo 'function check failed: invalid username accepted' >&2
    exit 1
fi
[[ "$ARCH_LINUX_USERNAME" == 'bad user;rm' ]]
[[ ! -e "$validation_report_file" ]] || {
    echo 'function check failed: validate_properties produced a reporting side effect' >&2
    exit 1
}
if declare -F validate_fail >/dev/null; then
    echo 'function check failed: validate_properties leaked an internal helper' >&2
    exit 1
fi
gum_fail() { :; }
log_fail() { :; }

ARCH_LINUX_USERNAME='archuser'

invalid_config_schema="$((1 + 1))"
ARCH_LINUX_INSTALLER_CONFIG_VERSION="$invalid_config_schema"
if validate_properties; then
    echo 'function check failed: validate_properties accepted config schema other than 1' >&2
    exit 1
fi
[[ "$ARCH_LINUX_INSTALLER_CONFIG_VERSION" == "$invalid_config_schema" ]]
ARCH_LINUX_INSTALLER_CONFIG_VERSION='1'

for invalid_kernel in '--root' 'Linux' 'linux zen' 'linux/custom'; do
    ARCH_LINUX_KERNEL="$invalid_kernel"
    if validate_properties; then
        echo "function check failed: validate_properties accepted unsafe kernel package name: ${invalid_kernel}" >&2
        exit 1
    fi
    [[ "$ARCH_LINUX_KERNEL" == "$invalid_kernel" ]]
done
ARCH_LINUX_KERNEL='linux-zen'
validate_properties

ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='invalid'
if validate_properties; then
    echo 'function check failed: invalid shell enhancement boolean accepted' >&2
    exit 1
fi

ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='true'

ARCH_LINUX_GNOME_THEME_PROFILE='unsafe-theme'
if validate_properties; then
    echo 'function check failed: invalid GNOME theme profile accepted' >&2
    exit 1
fi
ARCH_LINUX_GNOME_THEME_PROFILE='stock'

ARCH_LINUX_GDM_THEME_PROFILE='unsafe-theme'
if validate_properties; then
    echo 'function check failed: invalid GDM theme profile accepted' >&2
    exit 1
fi
ARCH_LINUX_GDM_THEME_PROFILE='stock'

# A failed signed-repository gate blocks Marble before disk work.
ARCH_LINUX_GNOME_THEME_PROFILE='marble'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
if (
    repository_configuration_ready() { return 1; }
    validate_properties
); then
    echo 'function check failed: disabled Marble repository passed pre-install validation' >&2
    exit 1
fi
validate_properties

# Experimental GDM requires all three independent conditions. Validation reports but never repairs
# invalid persisted input; the interactive selector owns that recovery.
ARCH_LINUX_GDM_THEME_PROFILE='marble-experimental'
if (
    marble_gdm_configuration_ready() { return 1; }
    validate_properties
); then
    echo 'function check failed: disabled Marble GDM package passed pre-install validation' >&2
    exit 1
fi
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'marble-experimental' ]]
validate_properties

ARCH_LINUX_GNOME_THEME_PROFILE='stock'
if validate_properties; then
    echo 'function check failed: Marble GDM was accepted with Stock GNOME appearance' >&2
    exit 1
fi
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'marble-experimental' ]]

ARCH_LINUX_GNOME_THEME_PROFILE='marble'
ARCH_LINUX_DESKTOP_ENABLED='false'
if validate_properties; then
    echo 'function check failed: Marble GDM was accepted for a TTY install' >&2
    exit 1
fi
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'marble-experimental' ]]

# A TTY config may contain a dormant Marble Shell value but Stock GDM must not require or install
# either optional repository path.
ARCH_LINUX_GDM_THEME_PROFILE='stock'
(
    repository_configuration_ready() { return 1; }
    validate_properties
)
ARCH_LINUX_DESKTOP_SLIM_ENABLED=''
if validate_properties; then
    echo 'function check failed: blank TTY desktop slim Boolean was accepted' >&2
    exit 1
fi
ARCH_LINUX_DESKTOP_SLIM_ENABLED='false'
validate_properties
ARCH_LINUX_DESKTOP_ENABLED='false'
validate_properties
ARCH_LINUX_DESKTOP_ENABLED='true'
ARCH_LINUX_GNOME_THEME_PROFILE='stock'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
validate_properties

# Extra kernel args must not be able to break out of the GRUB cmdline sed expression
for good_args in '' 'amd_pstate=active mitigations=off' 'video=HDMI-A-1:1920x1080@60' 'resume=UUID=abc-123' 'pci=noaer,nomsi' 'root=/dev/sda1'; do
    ARCH_LINUX_KERNEL_ARGS="$good_args"
    if ! validate_properties; then
        echo "static check failed: valid kernel args rejected: ${good_args}" >&2
        exit 1
    fi
done
for bad_args in 'foo|bar' 'foo&bar' 'foo\bar' 'foo;bar' 'foo`bar' 'foo$bar' "foo'bar" 'foo
bar'; do
    ARCH_LINUX_KERNEL_ARGS="$bad_args"
    if validate_properties; then
        echo "static check failed: unsafe kernel args accepted: ${bad_args}" >&2
        exit 1
    fi
done
ARCH_LINUX_KERNEL_ARGS=''

# Dual boot must be a strict boolean
ARCH_LINUX_DUAL_BOOT_ENABLED='yes'
if validate_properties; then
    echo 'static check failed: invalid dual boot value accepted' >&2
    exit 1
fi
ARCH_LINUX_DUAL_BOOT_ENABLED='false'
validate_properties

# ---------------------------------------------------------------------------------------------------
# System Tuning selectors (stubbed UI). These are normally driven by gum; stub the wrappers so the
# decision logic can be asserted without a TTY.
# ---------------------------------------------------------------------------------------------------

gum_property() { :; }
properties_generate() { :; }
trap_gum_exit_confirm() { :; }

# TTY is a complete schema-1 configuration, so its dormant desktop Boolean is explicitly false.
ARCH_LINUX_DESKTOP_ENABLED='false'
unset ARCH_LINUX_DESKTOP_SLIM_ENABLED
properties_generate_calls=0
properties_generate() { properties_generate_calls=$((properties_generate_calls + 1)); }
until select_enable_desktop_slim; do :; done
[[ "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" == 'false' ]] || {
    echo 'TTY slim selector did not persist false' >&2
    exit 1
}
[[ "$properties_generate_calls" -eq 1 ]] || {
    echo 'TTY slim selector did not persist its one normalization' >&2
    exit 1
}
until select_enable_desktop_slim; do :; done
[[ "$properties_generate_calls" -eq 1 ]] || {
    echo 'TTY slim selector rewrote an already normalized value' >&2
    exit 1
}
properties_generate() { :; }

# GNOME/GDM appearance selectors: TTY and Stock GNOME never show a GDM prompt and persist Stock.
# Marble exposes Stock first/default plus the experimental opt-in; loaded values remain idempotent.
ARCH_LINUX_DESKTOP_ENABLED='false'
unset ARCH_LINUX_GNOME_THEME_PROFILE
unset ARCH_LINUX_GDM_THEME_PROFILE
gum_choose() { echo 'appearance selector must not prompt for TTY' >&2; return 1; }
until select_gnome_theme_profile; do :; done
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GNOME_THEME_PROFILE" == 'stock' ]] || { echo 'TTY theme selector did not persist Stock' >&2; exit 1; }
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'stock' ]] || { echo 'TTY GDM selector did not persist Stock' >&2; exit 1; }

ARCH_LINUX_DESKTOP_ENABLED='true'
unset ARCH_LINUX_GNOME_THEME_PROFILE
ARCH_LINUX_GDM_THEME_PROFILE='marble-experimental'
gum_choose() { echo 'stock  - Stock GNOME (default; keeps the current Bibata and extension profile)'; }
until select_gnome_theme_profile; do :; done
[[ "$ARCH_LINUX_GNOME_THEME_PROFILE" == 'stock' ]] || { echo 'GNOME Stock choice parsed incorrectly' >&2; exit 1; }
gum_choose() { echo 'GDM selector unexpectedly prompted for Stock GNOME' >&2; return 1; }
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'stock' ]] || { echo 'Stock GNOME did not repair GDM to Stock' >&2; exit 1; }

unset ARCH_LINUX_GNOME_THEME_PROFILE
unset ARCH_LINUX_GDM_THEME_PROFILE
gum_choose() { echo 'marble - Marble blue/filled/dark Shell with Colloid GTK3 and icons'; }
until select_gnome_theme_profile; do :; done
[[ "$ARCH_LINUX_GNOME_THEME_PROFILE" == 'marble' ]] || { echo 'GNOME Marble choice parsed incorrectly' >&2; exit 1; }
gum_choose() {
    [ "$#" -eq 4 ] && [ "$1" = '--header' ] &&
        [ "$2" = '+ Choose GDM Appearance (default: Stock)' ] &&
        [ "$3" = 'stock               - Stock GDM (default)' ] &&
        [ "$4" = 'marble-experimental - Match Marble Shell + Colloid icons (experimental; GNOME 50 only)' ] || {
        echo 'GDM selector options/order changed' >&2
        return 1
    }
    echo "$3"
}
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'stock' ]] || { echo 'GDM Stock choice parsed incorrectly' >&2; exit 1; }

unset ARCH_LINUX_GDM_THEME_PROFILE
gum_choose() {
    [ "$#" -eq 4 ] && [ "$1" = '--header' ] &&
        [ "$2" = '+ Choose GDM Appearance (default: Stock)' ] &&
        [ "$3" = 'stock               - Stock GDM (default)' ] &&
        [ "$4" = 'marble-experimental - Match Marble Shell + Colloid icons (experimental; GNOME 50 only)' ] || {
        echo 'GDM selector options/order changed' >&2
        return 1
    }
    echo "$4"
}
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'marble-experimental' ]] || { echo 'experimental Marble GDM choice parsed incorrectly' >&2; exit 1; }

gum_choose() { echo 'loaded GDM selector unexpectedly prompted' >&2; return 1; }
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'marble-experimental' ]]

ARCH_LINUX_GNOME_THEME_PROFILE='stock'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
gum_choose() { echo 'loaded theme selector unexpectedly prompted' >&2; return 1; }
until select_gnome_theme_profile; do :; done
until select_gdm_theme_profile; do :; done
[[ "$ARCH_LINUX_GNOME_THEME_PROFILE" == 'stock' ]]
[[ "$ARCH_LINUX_GDM_THEME_PROFILE" == 'stock' ]]

# The destructive-action summary must name either persisted appearance choice. Color wrappers are
# reduced to their text argument so this exercises the real branch without requiring a terminal.
gum() {
    [ "$1" = 'join' ] || return 1
    shift
    printf '%s\n' "$*"
}
gum_white() { printf '%s\n' "${@: -1}"; }
gum_green() { printf '%s\n' "${@: -1}"; }
gum_blue() { printf '%s\n' "${@: -1}"; }
gum_yellow() { printf '%s\n' "${@: -1}"; }
(
    lsblk() {
        case "$2" in
        SIZE) printf '  34359738368  \n' ;;
        START) printf '  2048  \n' ;;
        MODEL) printf '  Arch Linux Test Disk  \n' ;;
        *) return 1 ;;
        esac
    }
    [ "$(block_attribute /dev/test-disk SIZE)" = 34359738368 ]
    [ "$(block_attribute /dev/test-partition START)" = 2048 ]
    [ "$(block_attribute /dev/test-disk MODEL)" = 'Arch Linux Test Disk' ]
)
lsblk() { printf '100G\n'; }
ARCH_LINUX_DUAL_BOOT_ENABLED='false'
ARCH_LINUX_SAMBA_SHARE_ENABLED='false'
ARCH_LINUX_GNOME_THEME_PROFILE='stock'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
stock_summary="$(print_summary)"
grep -qF 'appearance:  Stock GNOME' <<<"$stock_summary"
grep -qF 'GDM Shell: Stock' <<<"$stock_summary"
grep -qF 'GTK4/libadwaita CSS: Stock' <<<"$stock_summary"
if grep -qF 'Marble Shell + Colloid GTK3/icons' <<<"$stock_summary"; then
    echo 'Stock summary included Marble appearance details' >&2
    exit 1
fi
ARCH_LINUX_GNOME_THEME_PROFILE='marble'
ARCH_LINUX_GDM_THEME_PROFILE='stock'
marble_stock_gdm_summary="$(print_summary)"
grep -qF 'appearance:  Marble Shell + Colloid GTK3/icons' <<<"$marble_stock_gdm_summary"
grep -qF 'GDM Shell: Stock (default)' <<<"$marble_stock_gdm_summary"
grep -qF 'GTK4/libadwaita CSS stays Stock; the Colloid icon default is global' <<<"$marble_stock_gdm_summary"
if grep -qF 'GDM Shell: matching Marble theme' <<<"$marble_stock_gdm_summary"; then
    echo 'Stock GDM summary included the experimental GDM choice' >&2
    exit 1
fi
if grep -qF 'appearance:  Stock GNOME' <<<"$marble_stock_gdm_summary"; then
    echo 'Marble summary reported the Stock selection' >&2
    exit 1
fi

ARCH_LINUX_GDM_THEME_PROFILE='marble-experimental'
marble_gdm_summary="$(print_summary)"
grep -qF 'appearance:  Marble Shell + Colloid GTK3/icons' <<<"$marble_gdm_summary"
grep -qF 'GDM Shell: matching Marble theme + Colloid icons (experimental; GNOME 50 only)' <<<"$marble_gdm_summary"
grep -qF 'GTK4/libadwaita CSS stays Stock; the Colloid icon default is global' <<<"$marble_gdm_summary"
if grep -qF 'GDM Shell: Stock (default)' <<<"$marble_gdm_summary"; then
    echo 'experimental GDM summary reported Stock GDM' >&2
    exit 1
fi

# tune_toggle must always ask, pre-select the current value, and store the answer.
# NOTE: invoked via 'until' exactly as main does. Called bare, the "No" answer (gum_confirm
# returning 1) would trip 'set -e' — bash only disables it inside until/while conditions.
tune_flag="$(mktemp)"
gum_confirm() { printf '%s' "$1" >"$tune_flag"; return 0; } # answer: yes
ARCH_LINUX_VM_SUPPORT_ENABLED='false'
until tune_toggle ARCH_LINUX_VM_SUPPORT_ENABLED 'VM?' 'VM Support'; do :; done
[[ "$ARCH_LINUX_VM_SUPPORT_ENABLED" == "true" ]] || { echo 'tune_toggle: yes must set true' >&2; exit 1; }
[[ "$(cat "$tune_flag")" == "--default=false" ]] || { echo 'tune_toggle: must pre-select current value (false)' >&2; exit 1; }

gum_confirm() { printf '%s' "$1" >"$tune_flag"; return 1; } # answer: no
until tune_toggle ARCH_LINUX_VM_SUPPORT_ENABLED 'VM?' 'VM Support'; do :; done
[[ "$ARCH_LINUX_VM_SUPPORT_ENABLED" == "false" ]] || { echo 'tune_toggle: no must set false' >&2; exit 1; }
[[ "$(cat "$tune_flag")" == "--default=true" ]] || { echo 'tune_toggle: must pre-select current value (true)' >&2; exit 1; }
rm -f "$tune_flag"

# Dual boot partition selection must never silently reuse the disk-derived p1/p2 defaults
ARCH_LINUX_DISK='/dev/nvme0n1'
lsblk() { printf '%s\n' "/dev/nvme0n1 476.9G  " "/dev/nvme0n1p1 512M vfat SYSTEM" "/dev/nvme0n1p3 300G ntfs Windows" "/dev/nvme0n1p5 150G ext4 spare"; }
block_partition_identity() {
    case "$1" in
    /dev/nvme0n1p1) printf '%064d\n' 1 ;;
    /dev/nvme0n1p5) printf '%064d\n' 5 ;;
    *) return 1 ;;
    esac
}
block_identity_is_unique() { [ "$1" = part ] && [[ "$2" =~ ^[0-9]{64}$ ]]; }
pick_counter="$(mktemp)" && echo 0 >"$pick_counter"
gum_choose() {
    local n && n=$(($(cat "$pick_counter") + 1)) && echo "$n" >"$pick_counter"
    [ "$n" = "1" ] && echo "/dev/nvme0n1p1 512M vfat SYSTEM" || echo "/dev/nvme0n1p5 150G ext4 spare"
}
gum_confirm() { return 0; }
ARCH_LINUX_DUAL_BOOT_ENABLED='true'
select_dual_boot_partitions
[[ "$ARCH_LINUX_BOOT_PARTITION" == "/dev/nvme0n1p1" ]] || { echo 'dual boot: ESP path not extracted' >&2; exit 1; }
[[ "$ARCH_LINUX_ROOT_PARTITION" == "/dev/nvme0n1p5" ]] || { echo 'dual boot: root path not extracted' >&2; exit 1; }

# Choosing the same partition for ESP and root must be refused
gum_choose() { echo "/dev/nvme0n1p1 512M vfat SYSTEM"; }
if select_dual_boot_partitions; then
    echo 'dual boot: identical ESP/root accepted' >&2
    exit 1
fi

# Declining the format confirmation must abort instead of proceeding
echo 0 >"$pick_counter"
gum_choose() {
    local n && n=$(($(cat "$pick_counter") + 1)) && echo "$n" >"$pick_counter"
    [ "$n" = "1" ] && echo "/dev/nvme0n1p1 512M vfat SYSTEM" || echo "/dev/nvme0n1p5 150G ext4 spare"
}
gum_confirm() { return 1; }
if select_dual_boot_partitions; then
    echo 'dual boot: proceeded without format consent' >&2
    exit 1
fi

# Turning dual boot off must restore the derived defaults
gum_confirm() { return 0; }
ARCH_LINUX_DUAL_BOOT_ENABLED='false'
ARCH_LINUX_BOOT_PARTITION='/dev/sdz9'
ARCH_LINUX_ROOT_PARTITION='/dev/sdz8'
select_dual_boot_partitions
[[ "$ARCH_LINUX_BOOT_PARTITION" == "/dev/nvme0n1p1" ]] || { echo 'dual boot off: ESP default not restored' >&2; exit 1; }
[[ "$ARCH_LINUX_ROOT_PARTITION" == "/dev/nvme0n1p2" ]] || { echo 'dual boot off: root default not restored' >&2; exit 1; }

# A disk with fewer than two partitions cannot be a dual boot target
lsblk() { printf '%s\n' "/dev/sdb 8G  "; }
ARCH_LINUX_DUAL_BOOT_ENABLED='true'
ARCH_LINUX_DISK='/dev/sdb'
if select_dual_boot_partitions; then
    echo 'dual boot: accepted a disk with <2 partitions' >&2
    exit 1
fi
rm -f "$pick_counter"

# ---------------------------------------------------------------------------------------------------
# Disk safety: validate_partition_targets is the hard gate in front of every destructive operation.
# The block_* probes are stubbed with a fake device table so these run without root or real disks.
#
#   /dev/sda        disk        /dev/sdb        disk (a second, unrelated disk)
#   /dev/sda1..2    part -> sda /dev/sdb1..2    part -> sdb
#   /dev/by-id/alias  symlink to /dev/sda2
# ---------------------------------------------------------------------------------------------------

block_canonical() { [ "$1" = "/dev/by-id/alias" ] && printf '/dev/sda2' || printf '%s' "$1"; }
block_exists() { case "$1" in /dev/sda|/dev/sdb|/dev/sda1|/dev/sda2|/dev/sdb1|/dev/sdb2) return 0 ;; *) return 1 ;; esac; }
block_type() {
    case "$1" in
    /dev/sda | /dev/sdb) printf 'disk' ;;
    /dev/sda1 | /dev/sda2 | /dev/sdb1 | /dev/sdb2) printf 'part' ;;
    esac
}
block_parent() {
    case "$1" in
    /dev/sda1 | /dev/sda2) printf '/dev/sda' ;;
    /dev/sdb1 | /dev/sdb2) printf '/dev/sdb' ;;
    esac
}
silent_report() { :; }

targets_ok() {
    ARCH_LINUX_DUAL_BOOT_ENABLED="$1"
    ARCH_LINUX_DISK="$2"
    ARCH_LINUX_BOOT_PARTITION="$3"
    ARCH_LINUX_ROOT_PARTITION="$4"
    validate_partition_targets silent_report
}

expect_reject() {
    local desc="$1" && shift
    if targets_ok "$@"; then
        echo "disk safety: accepted an unsafe target set (${desc})" >&2
        exit 1
    fi
}
expect_accept() {
    local desc="$1" && shift
    if ! targets_ok "$@"; then
        echo "disk safety: rejected a valid target set (${desc})" >&2
        exit 1
    fi
}

# Fresh install: the layout must be exactly the one exec_prepare_disk is about to create
expect_accept 'plain sda1/sda2 layout'      false /dev/sda /dev/sda1 /dev/sda2
expect_reject 'partitions on another disk'  false /dev/sda /dev/sdb1 /dev/sdb2
expect_reject 'root on another disk'        false /dev/sda /dev/sda1 /dev/sdb2
expect_reject 'boot equals root'            false /dev/sda /dev/sda2 /dev/sda2
expect_reject 'root is the whole disk'      false /dev/sda /dev/sda1 /dev/sda
expect_reject 'disk is a partition'         false /dev/sda1 /dev/sda1 /dev/sda2
expect_reject 'disk does not exist'         false /dev/sdz /dev/sdz1 /dev/sdz2
expect_reject 'swapped partition order'     false /dev/sda /dev/sda2 /dev/sda1
expect_reject 'symlink aliasing root'       false /dev/sda /dev/by-id/alias /dev/sda2

# Dual boot: partitions must already exist, be real partitions and live on the selected disk
expect_accept 'existing pair on the disk'   true /dev/sda /dev/sda1 /dev/sda2
expect_reject 'foreign disk partitions'     true /dev/sda /dev/sdb1 /dev/sdb2
expect_reject 'root on a foreign disk'      true /dev/sda /dev/sda1 /dev/sdb2
expect_reject 'boot equals root'            true /dev/sda /dev/sda2 /dev/sda2
expect_reject 'symlink aliasing root'       true /dev/sda /dev/by-id/alias /dev/sda2
expect_reject 'root is the whole disk'      true /dev/sda /dev/sda1 /dev/sda
expect_reject 'partitions do not exist'     true /dev/sda /dev/sda9 /dev/sda8

# The persisted SHA-256 identities bind the selection to one unique physical disk and, for dual
# boot, to exact GPT partitions. Model/serial drift and duplicate physical identities fail closed.
# Restore the production identity helpers after the narrow selector seam above.
# shellcheck disable=SC1090
source <(sed -n '/^block_partition_identity()/,/^}/p' "$script")
# shellcheck disable=SC1090
source <(sed -n '/^block_identity_is_unique()/,/^}/p' "$script")
sdb_serial='SERIAL-B'
sda2_start='2099200'
block_attribute() {
    local node="$1" field="$2"
    case "${node}:${field}" in
    /dev/sda:SIZE|/dev/sdb:SIZE) printf '107374182400' ;;
    /dev/sda:WWN|/dev/sdb:WWN) printf '' ;;
    /dev/sda:SERIAL) printf 'SERIAL-A' ;;
    /dev/sdb:SERIAL) printf '%s' "$sdb_serial" ;;
    /dev/sda:MODEL|/dev/sdb:MODEL) printf 'QEMU SAFE DISK' ;;
    /dev/sda1:PARTUUID) printf '11111111-1111-1111-1111-111111111111' ;;
    /dev/sda2:PARTUUID) printf '22222222-2222-2222-2222-222222222222' ;;
    /dev/sdb1:PARTUUID) printf '33333333-3333-3333-3333-333333333333' ;;
    /dev/sdb2:PARTUUID) printf '44444444-4444-4444-4444-444444444444' ;;
    /dev/sda1:START|/dev/sdb1:START) printf '2048' ;;
    /dev/sda2:START) printf '%s' "$sda2_start" ;;
    /dev/sdb2:START) printf '2099200' ;;
    /dev/sda1:SIZE|/dev/sdb1:SIZE) printf '1073741824' ;;
    /dev/sda2:SIZE|/dev/sdb2:SIZE) printf '106300440576' ;;
    /dev/sda1:FSTYPE|/dev/sdb1:FSTYPE) printf 'vfat' ;;
    /dev/sda2:FSTYPE|/dev/sdb2:FSTYPE) printf 'ext4' ;;
    *) return 1 ;;
    esac
}
block_paths_for_type() {
    case "$1" in
    disk) printf '%s\n' /dev/sda /dev/sdb ;;
    part) printf '%s\n' /dev/sda1 /dev/sda2 /dev/sdb1 /dev/sdb2 ;;
    *) return 1 ;;
    esac
}

ARCH_LINUX_DUAL_BOOT_ENABLED=false
ARCH_LINUX_DISK=/dev/sda
ARCH_LINUX_BOOT_PARTITION=/dev/sda1
ARCH_LINUX_ROOT_PARTITION=/dev/sda2
ARCH_LINUX_DISK_IDENTITY="$(block_disk_identity /dev/sda)"
ARCH_LINUX_BOOT_PARTITION_IDENTITY=''
ARCH_LINUX_ROOT_PARTITION_IDENTITY=''
validate_destructive_targets silent_report
saved_disk_identity="$ARCH_LINUX_DISK_IDENTITY"
ARCH_LINUX_DISK_IDENTITY='1111111111111111111111111111111111111111111111111111111111111111'
if validate_destructive_targets silent_report; then
    echo 'disk safety: changed persisted disk identity was accepted' >&2
    exit 1
fi
ARCH_LINUX_DISK_IDENTITY="$saved_disk_identity"
sdb_serial='SERIAL-A'
if validate_destructive_targets silent_report; then
    echo 'disk safety: ambiguous physical disk identity was accepted' >&2
    exit 1
fi
sdb_serial='SERIAL-B'

ARCH_LINUX_DUAL_BOOT_ENABLED=true
ARCH_LINUX_BOOT_PARTITION_IDENTITY="$(block_partition_identity /dev/sda1)"
ARCH_LINUX_ROOT_PARTITION_IDENTITY="$(block_partition_identity /dev/sda2)"
validate_destructive_targets silent_report
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT="$(destructive_target_snapshot)"
assert_accepted_destructive_target silent_report
sda2_start='2099201'
if assert_accepted_destructive_target silent_report; then
    echo 'disk safety: changed partition geometry matched the accepted snapshot' >&2
    exit 1
fi
sda2_start='2099200'
ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT=''

# Two-phase storage markers exist before resource creation. An intent with no resource is removed;
# an intent/active marker with an exact owned resource causes exact rollback; malformed markers do
# not authorize cleanup.
(
    storage_test_dir="$(mktemp -d)"
    trap 'command rm -rf -- "$storage_test_dir"' EXIT
    TARGET_MOUNT_MARKER="${storage_test_dir}/mount.marker"
    CRYPTROOT_MARKER="${storage_test_dir}/crypt.marker"
    ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    destructive_target_snapshot() { printf '%s\n' "$ARCH_LINUX_ACCEPTED_TARGET_SNAPSHOT"; }
    log_fail() { :; }
    mount_present=false
    findmnt() { [ "$mount_present" = true ]; }
    target_mount_tree_is_owned() { [ "$mount_present" = true ]; }
    umount() { mount_present=false; : >"${storage_test_dir}/unmounted"; }
    cryptroot_belongs_to_target() { return 0; }
    cryptsetup() { [ "$1" = close ] && [ "$2" = -- ] && [ "$3" = cryptroot ]; : >"${storage_test_dir}/closed"; }

    mark_storage_intent "$TARGET_MOUNT_MARKER"
    installer_cleanup_created_storage
    [[ ! -e "$TARGET_MOUNT_MARKER" && ! -e "${storage_test_dir}/unmounted" ]]

    mark_storage_intent "$TARGET_MOUNT_MARKER"
    mount_present=true
    installer_cleanup_created_storage
    [[ ! -e "$TARGET_MOUNT_MARKER" && -e "${storage_test_dir}/unmounted" ]]

    rm -f -- "${storage_test_dir}/unmounted"
    mark_storage_intent "$TARGET_MOUNT_MARKER"
    activate_storage_marker "$TARGET_MOUNT_MARKER"
    mount_present=true
    installer_cleanup_created_storage
    [[ ! -e "$TARGET_MOUNT_MARKER" && -e "${storage_test_dir}/unmounted" ]]

    mark_storage_intent "$CRYPTROOT_MARKER"
    activate_storage_marker "$CRYPTROOT_MARKER"
    installer_cleanup_created_storage
    [[ ! -e "$CRYPTROOT_MARKER" && -e "${storage_test_dir}/closed" ]]

    rm -f -- "${storage_test_dir}/unmounted"
    printf '%s\n' 'foreign marker' >"$TARGET_MOUNT_MARKER"
    chmod 0600 -- "$TARGET_MOUNT_MARKER"
    mount_present=true
    if installer_cleanup_created_storage; then
        echo 'storage safety: malformed marker authorized cleanup' >&2
        exit 1
    fi
    [[ ! -e "${storage_test_dir}/unmounted" ]]
)

# NVMe / MMC naming must round-trip through the same rules
block_exists() { case "$1" in /dev/nvme0n1|/dev/nvme0n1p1|/dev/nvme0n1p2|/dev/mmcblk0|/dev/mmcblk0p1|/dev/mmcblk0p2) return 0 ;; *) return 1 ;; esac; }
block_type() { case "$1" in /dev/nvme0n1|/dev/mmcblk0) printf 'disk' ;; *p1|*p2) printf 'part' ;; esac; }
block_parent() { case "$1" in /dev/nvme0n1p*) printf '/dev/nvme0n1' ;; /dev/mmcblk0p*) printf '/dev/mmcblk0' ;; esac; }
block_canonical() { printf '%s' "$1"; }
expect_accept 'nvme layout' false /dev/nvme0n1 /dev/nvme0n1p1 /dev/nvme0n1p2
expect_accept 'mmc layout'  false /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2
expect_reject 'nvme without p separator' false /dev/nvme0n1 /dev/nvme0n11 /dev/nvme0n12

# ---------------------------------------------------------------------------------------------------
# Second keyboard layout helpers
# ---------------------------------------------------------------------------------------------------

ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='us'
ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=''
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=''
[[ "$(desktop_keyboard_layouts)" == "us" ]] || { echo 'desktop_keyboard_layouts: single layout wrong' >&2; exit 1; }
[[ "$(desktop_keyboard_variants)" == "" ]] || { echo 'desktop_keyboard_variants: single layout wrong' >&2; exit 1; }

ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND='ru'
[[ "$(desktop_keyboard_layouts)" == "us,ru" ]] || { echo 'desktop_keyboard_layouts: second layout not appended' >&2; exit 1; }
[[ "$(desktop_keyboard_variants)" == "," ]] || { echo 'desktop_keyboard_variants: must stay aligned with the layout list' >&2; exit 1; }

# The Latin layout must stay first so it is the group active at login
[[ "$(desktop_keyboard_layouts)" == us,* ]] || { echo 'first layout must remain the Latin one' >&2; exit 1; }

ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT='dvorak'
[[ "$(desktop_keyboard_variants)" == "dvorak," ]] || { echo 'desktop_keyboard_variants: first variant lost' >&2; exit 1; }
ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT=''

ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND=''

# Executor teardown allows only the existing bounded cgroup drain. A transient descendant may
# exit naturally; a cgroup that is still populated after that bound is killed and remains a FAIL.
(
    PROCESS_CGROUP_DIR='/sys/fs/cgroup/test-transient'
    sleep 0.01 &
    # shellcheck disable=SC2031 # Unrelated to the dynamic readonly-name probe above.
    PROCESS_ACTIVE_PID=$!
    PROCESS_ACTIVE_PGID=''
    drain_calls=0
    process_cgroup_is_empty() { return 1; }
    process_wait_cgroup_empty() { drain_calls=$((drain_calls + 1)); return 0; }
    process_terminate_expected_gpg_agents() { echo 'transient descendant was classified as an agent' >&2; return 1; }
    process_kill_contained() { echo 'transient descendant was killed' >&2; return 1; }
    process_remove_cgroup() { PROCESS_CGROUP_DIR=''; return 0; }
    process_reap_active false
    [ "${drain_calls}" -eq 2 ]
)
(
    PROCESS_CGROUP_DIR='/sys/fs/cgroup/test-stubborn'
    sleep 0.01 &
    # shellcheck disable=SC2031 # Unrelated to the dynamic readonly-name probe above.
    PROCESS_ACTIVE_PID=$!
    PROCESS_ACTIVE_PGID=''
    drain_calls=0
    killed=false
    process_wait_cgroup_empty() {
        drain_calls=$((drain_calls + 1))
        [ "${drain_calls}" -gt 1 ]
    }
    process_terminate_expected_gpg_agents() { return 1; }
    process_kill_contained() { killed=true; return 0; }
    process_remove_cgroup() { PROCESS_CGROUP_DIR=''; return 0; }
    if process_reap_active false; then
        echo 'executor teardown accepted a cgroup that exceeded its drain bound' >&2
        exit 1
    else
        [ "$?" -eq 124 ]
    fi
    [ "${killed}" = true ] && [ "${drain_calls}" -eq 2 ]
)
process_member_is_expected_gpg_agent 0 gpg-agent /usr/bin/gpg-agent
process_member_is_expected_gpg_agent 0 gpg-agent /mnt/usr/bin/gpg-agent
for rejected_agent in \
    '1000|gpg-agent|/usr/bin/gpg-agent' \
    '0|gpg|/usr/bin/gpg-agent' \
    '0|gpg-agent|/tmp/gpg-agent'; do
    IFS='|' read -r agent_uid agent_comm agent_exe <<<"${rejected_agent}"
    if process_member_is_expected_gpg_agent "${agent_uid}" "${agent_comm}" "${agent_exe}"; then
        echo "executor teardown accepted an untrusted gpg-agent identity: ${rejected_agent}" >&2
        exit 1
    fi
done

# Ptyxis receives Russian alternatives for a Russian locale even when the initial desktop layout is
# Latin, and also when Russian is explicitly selected as either layout.
ARCH_LINUX_LOCALE_LANG='en_US'
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='us'
if needs_ptyxis_russian_shortcuts; then
    echo 'needs_ptyxis_russian_shortcuts: English-only setup incorrectly matched' >&2
    exit 1
fi
for russian_locale in ru_RU ru_RU@cyrillic; do
    ARCH_LINUX_LOCALE_LANG="$russian_locale"
    needs_ptyxis_russian_shortcuts || {
        echo "needs_ptyxis_russian_shortcuts: locale ${russian_locale} did not match" >&2
        exit 1
    }
done
ARCH_LINUX_LOCALE_LANG='en_US'
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='ru'
needs_ptyxis_russian_shortcuts || { echo 'needs_ptyxis_russian_shortcuts: primary ru layout did not match' >&2; exit 1; }
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='us'
ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT_SECOND='ru'
needs_ptyxis_russian_shortcuts || { echo 'needs_ptyxis_russian_shortcuts: secondary ru layout did not match' >&2; exit 1; }

echo "function checks passed"
