#!/usr/bin/env bash
# Run only in a disposable Arch build environment as root. All keyrings are ephemeral test data.
# Literal mock-script and child-shell strings below are regression fixtures, not local expansions.
# shellcheck disable=SC2016,SC2034
set +x
set -euo pipefail

fail() {
    printf 'keyring rotation check failed: %s\n' "$*" >&2
    exit 1
}

assert_real_rejection_status() {
    local status="$1" description="$2"
    [ "$status" -ne 0 ] || fail "negative fixture unexpectedly succeeded: ${description}"
    case "$status" in
        126|127) fail "negative fixture did not execute its subject: ${description} (status ${status})" ;;
    esac
}

[ "$#" -eq 0 ] || fail 'arguments are forbidden'
[ "${BASH_SOURCE[0]}" = "$0" ] || fail 'sourced or evaluated entry is forbidden'
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly repo_root

umask 077
[ "$(umask)" = 0077 ] || fail 'restrictive keyring-test umask was not established'

[ "${EUID}" -eq 0 ] || fail 'real pacman-key regression requires root in an isolated Arch environment'
[ -f /etc/arch-release ] && [ ! -L /etc/arch-release ] ||
    fail 'keyring rotation checks require a disposable Arch environment'
for command_name in awk bash bsdtar cat chmod chown cp date find getcap getent getfacl gpg grep \
    id install ln mkfifo mktemp mv pacman-key paste python realpath rm runuser sed setcap setfacl \
    sha256sum sh stat truncate; do
    command -v -- "${command_name}" >/dev/null 2>&1 || fail "missing command: ${command_name}"
done
case "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" in
true | false) ;;
*) fail 'ARCH_LINUX_PRIVILEGED_ACCEPTANCE must be true or false' ;;
esac
if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    for command_name in losetup wipefs sgdisk partprobe udevadm mkfs.ext4 blkid cryptsetup \
        fallocate truncate head base64 mount umount findmnt setpriv useradd userdel usermod \
        groupdel cc python3 ps timeout getsubids; do
        command -v -- "${command_name}" >/dev/null 2>&1 ||
            fail "missing privileged acceptance command: ${command_name}"
    done
fi

test_root="$(mktemp -d /tmp/arch-linux-keyring.XXXXXXXX)"
cleanup_test_root() {
    case "${test_root}" in /tmp/arch-linux-keyring.*) ;; *) return 1 ;; esac
    [ -d "${test_root}" ] && [ ! -L "${test_root}" ] &&
        [ "$(stat -c '%u:%a' -- "${test_root}")" = '0:700' ] || return 1
    find "${test_root}" -xdev -depth -delete
}
trap cleanup_test_root EXIT
packet_home="${test_root}/packet-home"
install -d -m0700 -- "${packet_home}"

# shellcheck source=repository/lib/common.sh
source "${repo_root}/repository/lib/common.sh"
declare -F repository_assert_public_certificate >/dev/null ||
    fail 'repository public-certificate predicate is absent'
repository_assert_public_certificate \
    "${repo_root}/repository/trust/arch-linux.gpg" \
    "${repo_root}/repository/trust/primary-fingerprint" \
    "${repo_root}/repository/trust/signing-subkey-fingerprint" 15552000
public_packets="$(gpg --batch --no-options --homedir "${packet_home}" --list-packets -- \
    "${repo_root}/repository/trust/arch-linux.gpg" 2>/dev/null)" ||
    fail 'tracked public certificate packet scan did not execute'
set +e
grep -Eq '^:(secret key packet|secret sub key packet):' <<<"$public_packets"
packet_status=$?
set -e
case "$packet_status" in
    0) fail 'tracked public certificate contains secret packets' ;;
    1) ;;
    126|127) fail "tracked public certificate scan did not execute (status ${packet_status})" ;;
    *) fail "tracked public certificate scan failed diagnostically (status ${packet_status})" ;;
esac

signing_home="${test_root}/signing-home"
client_home="${test_root}/pacman-gnupg"
import_dir="${test_root}/keyrings"
SCRIPT_TMP_DIR="${test_root}/aur-validation-runtime"
install -d -m0700 -- "${signing_home}" "${client_home}" "${SCRIPT_TMP_DIR}"
[ "$(stat -c '%u:%a' -- "${SCRIPT_TMP_DIR}")" = '0:700' ] ||
    fail 'AUR validation runtime directory metadata is invalid'
install -d -m0755 -- "${import_dir}"

runtime_source_boundary_acceptance() (
    local safe_runtime unsafe_source_parent unsafe_ancestor_parent unsafe_leaf nobody_uid

    safe_runtime="$(mktemp -d /run/arch-linux-source-safe.XXXXXXXX)"
    unsafe_source_parent="$(mktemp -d /run/arch-linux-source-user.XXXXXXXX)"
    unsafe_ancestor_parent="$(mktemp -d /run/arch-linux-ancestor-user.XXXXXXXX)"
    unsafe_leaf="${unsafe_ancestor_parent}/launch"
    install -d -m0700 -- "${unsafe_leaf}"
    install -o 0 -g 0 -m0700 -- "${repo_root}/arch-linux-installer.sh" \
        "${safe_runtime}/arch-linux-installer.sh"
    install -o 0 -g 0 -m0700 -- "${repo_root}/arch-linux-installer.sh" \
        "${unsafe_source_parent}/arch-linux-installer.sh"
    install -o 0 -g 0 -m0700 -- "${repo_root}/arch-linux-installer.sh" \
        "${unsafe_leaf}/arch-linux-installer.sh"
    nobody_uid="$(id -u nobody)"
    chown "${nobody_uid}:${nobody_uid}" -- "${unsafe_source_parent}" "${unsafe_ancestor_parent}"

    # Invoked by the subshell EXIT trap.
    # shellcheck disable=SC2329
    cleanup_runtime_source_boundary() {
        local fixture
        chown 0:0 -- "${unsafe_source_parent}" "${unsafe_ancestor_parent}" 2>/dev/null || true
        for fixture in "${safe_runtime}" "${unsafe_source_parent}" "${unsafe_ancestor_parent}"; do
            case "${fixture}" in
                /run/arch-linux-source-safe.*|/run/arch-linux-source-user.*|/run/arch-linux-ancestor-user.*)
                    if [ -d "${fixture}" ] && [ ! -L "${fixture}" ] &&
                        [ "$(stat -c '%u' -- "${fixture}")" = 0 ]; then
                        find "${fixture}" -xdev -depth -delete
                    fi
                    ;;
            esac
        done
    }
    trap cleanup_runtime_source_boundary EXIT

    set +e
    bash -c '
        set -euo pipefail
        cd -- "$1"
        source "$2"
        DEBUG=false FORCE=false runtime_init
    ' bash "${safe_runtime}" "${unsafe_source_parent}/arch-linux-installer.sh" \
        >/dev/null 2>&1
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'runtime protected CWD with installer source under an unprivileged owner'
    [ ! -e "${safe_runtime}/installer.conf" ] && [ ! -e "${safe_runtime}/installer.log" ] ||
        fail 'unsafe external source created persistent installer state'

    set +e
    bash -c '
        set -euo pipefail
        cd -- "$1"
        source ./arch-linux-installer.sh
        DEBUG=false FORCE=false runtime_init
    ' bash "${unsafe_leaf}" >/dev/null 2>&1
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'runtime private leaf beneath an unprivileged-owned ancestor'
    [ ! -e "${unsafe_leaf}/installer.conf" ] && [ ! -e "${unsafe_leaf}/installer.log" ] ||
        fail 'unsafe ancestor chain created persistent installer state'

    bash -c '
        set -euo pipefail
        cd -- "$1"
        source ./arch-linux-installer.sh
        declare -F runtime_init >/dev/null &&
            declare -F runtime_source_identity_is_stable >/dev/null || exit 125
        DEBUG=false FORCE=false runtime_init
        install -o 0 -g 0 -m0700 -- "$2" ./replacement
        mv -fT -- ./replacement ./arch-linux-installer.sh
        set +e
        runtime_source_identity_is_stable
        identity_status=$?
        set -e
        [ "$identity_status" -ne 0 ] && [ "$identity_status" -ne 126 ] &&
            [ "$identity_status" -ne 127 ] || exit 1
    ' bash "${safe_runtime}" "${repo_root}/arch-linux-installer.sh" >/dev/null 2>&1 ||
        fail 'runtime did not reject a replaced executing source inode'
)

runtime_source_boundary_acceptance

privileged_block_fd_acceptance() (
    local image loop_device='' partition_one partition_two mapper_name mapper_path backing
    local disk_fd='' partition_one_fd='' partition_two_fd='' mapper_fd='' test_phrase=''
    local disk_handle partition_one_handle partition_two_handle mapper_handle cleanup_ok=true

    # A loop device proves that destructive utilities operate through stable opened block FDs.
    # It deliberately does not claim the installer's physical TYPE=disk identity; that remains a
    # real-disk QEMU gate.
    image="${test_root}/block-fd.img"
    mapper_name="arch-linux-fd-probe-${BASHPID}"
    mapper_path="/dev/mapper/${mapper_name}"
    truncate -s 384M -- "${image}"

    cleanup_block_fd_probe() {
        if [[ "${mapper_fd:-}" =~ ^[0-9]+$ ]]; then exec {mapper_fd}>&- || cleanup_ok=false; fi
        if [[ "${partition_two_fd:-}" =~ ^[0-9]+$ ]]; then exec {partition_two_fd}>&- || cleanup_ok=false; fi
        if [[ "${partition_one_fd:-}" =~ ^[0-9]+$ ]]; then exec {partition_one_fd}>&- || cleanup_ok=false; fi
        if [[ "${disk_fd:-}" =~ ^[0-9]+$ ]]; then exec {disk_fd}>&- || cleanup_ok=false; fi
        if cryptsetup status -- "${mapper_name}" >/dev/null 2>&1; then
            backing="$(cryptsetup status -- "${mapper_name}" 2>/dev/null |
                awk '$1 == "device:" { print $2; exit }')" || backing=''
            if [ -n "${partition_two:-}" ] &&
                [ "$(realpath -e -- "${backing}" 2>/dev/null)" = "$(realpath -e -- "${partition_two}" 2>/dev/null)" ]; then
                cryptsetup close -- "${mapper_name}" || cleanup_ok=false
            else
                cleanup_ok=false
            fi
        fi
        if [ -n "${loop_device}" ]; then
            backing="$(losetup -n -O BACK-FILE "${loop_device}" 2>/dev/null || true)"
            if [ "${backing}" = "${image}" ]; then
                losetup -d "${loop_device}" || cleanup_ok=false
                loop_device=''
            else
                cleanup_ok=false
            fi
        fi
        unset test_phrase
        [ "${cleanup_ok}" = true ] ||
            printf 'keyring rotation check failed: block-FD cleanup identity mismatch\n' >&2
    }
    trap cleanup_block_fd_probe EXIT

    loop_device="$(losetup --find --show --partscan -- "${image}")"
    [[ "${loop_device}" =~ ^/dev/loop[0-9]+$ ]] || fail 'unexpected loop-device path'
    [ "$(losetup -n -O BACK-FILE "${loop_device}")" = "${image}" ] ||
        fail 'loop-device backing readback mismatch'

    exec {disk_fd}<>"${loop_device}"
    disk_handle="/proc/${BASHPID}/fd/${disk_fd}"
    [ -b "${disk_handle}" ] &&
        [ "$(stat -Lc '%t:%T' -- "${disk_handle}")" = "$(stat -Lc '%t:%T' -- "${loop_device}")" ] ||
        fail 'opened loop-disk descriptor is not bound to the selected device'
    wipefs -af -- "${disk_handle}" >/dev/null
    sgdisk --zap-all -- "${disk_handle}" >/dev/null
    sgdisk -o -- "${disk_handle}" >/dev/null
    sgdisk -n 1:2048:+96M -t 1:8300 -c 1:fd-plain -- "${disk_handle}" >/dev/null
    sgdisk -n 2:0:0 -t 2:8300 -c 2:fd-luks -- "${disk_handle}" >/dev/null
    partprobe -- "${disk_handle}"
    udevadm settle

    partition_one="${loop_device}p1"
    partition_two="${loop_device}p2"
    [ -b "${partition_one}" ] && [ -b "${partition_two}" ] ||
        fail 'loop partitions did not materialize'
    exec {partition_one_fd}<>"${partition_one}"
    exec {partition_two_fd}<>"${partition_two}"
    partition_one_handle="/proc/${BASHPID}/fd/${partition_one_fd}"
    partition_two_handle="/proc/${BASHPID}/fd/${partition_two_fd}"
    [ "$(stat -Lc '%t:%T' -- "${partition_one_handle}")" = "$(stat -Lc '%t:%T' -- "${partition_one}")" ] &&
        [ "$(stat -Lc '%t:%T' -- "${partition_two_handle}")" = "$(stat -Lc '%t:%T' -- "${partition_two}")" ] ||
        fail 'opened partition descriptor is not bound to its selected partition'
    mkfs.ext4 -q -F -L FDPLAIN -- "${partition_one_handle}"
    [ "$(blkid -s LABEL -o value -- "${partition_one}")" = FDPLAIN ] ||
        fail 'filesystem utility did not operate on the opened partition descriptor'

    test_phrase="$(head -c 48 /dev/urandom | base64 -w0)"
    [ -n "${test_phrase}" ] || fail 'could not generate ephemeral LUKS test phrase'
    printf '%s' "${test_phrase}" | cryptsetup luksFormat --type luks2 --batch-mode \
        --key-file - -- "${partition_two_handle}"
    printf '%s' "${test_phrase}" | cryptsetup open --key-file - -- \
        "${partition_two_handle}" "${mapper_name}"
    unset test_phrase
    [ -b "${mapper_path}" ] || fail 'LUKS mapper did not materialize'
    exec {mapper_fd}<>"${mapper_path}"
    mapper_handle="/proc/${BASHPID}/fd/${mapper_fd}"
    [ "$(stat -Lc '%t:%T' -- "${mapper_handle}")" = "$(stat -Lc '%t:%T' -- "${mapper_path}")" ] ||
        fail 'opened mapper descriptor is not bound to the accepted LUKS mapping'
    backing="$(cryptsetup status -- "${mapper_name}" |
        awk '$1 == "device:" { print $2; exit }')"
    [ "$(realpath -e -- "${backing}")" = "$(realpath -e -- "${partition_two}")" ] ||
        fail 'LUKS mapper backing differs from the opened root partition'
    mkfs.ext4 -q -F -L FDLUKS -- "${mapper_handle}"
    [ "$(blkid -s LABEL -o value -- "${mapper_path}")" = FDLUKS ] ||
        fail 'filesystem utility did not operate on the opened mapper descriptor'

    cleanup_block_fd_probe
    [ "${cleanup_ok}" = true ] || fail 'block-FD acceptance cleanup failed'
    trap - EXIT
)

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    privileged_block_fd_acceptance
fi

# Load only the pure AUR archive/path validators. These fixtures prove that a package with the
# expected pkgname cannot obtain root authority through payload paths, executable metadata,
# ownership, modes or archive link/special-file types.
# shellcheck disable=SC1090
source <(awk '
    /^aur_review_metadata\(\)/ { capture=1 }
    /^locale_with_utf8\(\)/ { capture=0 }
    capture { print }
' "${repo_root}/arch-linux-installer.sh")
for extracted_function in \
    aur_review_metadata aur_review_source_identity_matches aur_review_pkgbuild_matches \
    aur_reviewed_dependencies aur_extension_uuid aur_package_output_path_is_safe \
    aur_package_path_is_allowed aur_package_symlink_is_safe aur_bsdtar_bounded \
    aur_archive_extended_metadata_is_absent aur_package_archive_is_safe; do
    declare -F -- "$extracted_function" >/dev/null ||
        fail "installer function extraction omitted ${extracted_function}"
done

aur_archive_fixture_acceptance() (
    # Real package metadata is mode 0644. Keep that public-package shape deterministic even when
    # the surrounding secret-bearing root regression correctly runs with a restrictive umask.
    umask 022
    [ "$(umask)" = 0022 ] || fail 'AUR archive fixture umask was not established'

    aur_fixture_root="${test_root}/aur-fixture"
    aur_fixture_archive="${test_root}/aur-fixture.pkg.tar.zst"
    aur_fixture_reset() {
        [ ! -e "${aur_fixture_root}" ] || find "${aur_fixture_root}" -xdev -depth -delete
        install -d -m0755 -- "${aur_fixture_root}/usr/bin"
        printf '%s\n' 'pkgname = yay' 'pkgver = 1.0-1' >"${aur_fixture_root}/.PKGINFO"
        printf '%s\n' 'format = 2' >"${aur_fixture_root}/.BUILDINFO"
        printf '%s\n' '#mtree' >"${aur_fixture_root}/.MTREE"
        printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"${aur_fixture_root}/usr/bin/yay"
        chmod 0755 -- "${aur_fixture_root}/usr/bin/yay"
    }
    aur_fixture_pack() {
        local -a archive_options=("$@")
        local -a members=(.BUILDINFO .MTREE .PKGINFO)
        [ ! -e "${aur_fixture_root}/.INSTALL" ] || members+=(.INSTALL)
        [ ! -e "${aur_fixture_root}/.CHANGELOG" ] || members+=(.CHANGELOG)
        [ ! -e "${aur_fixture_root}/etc" ] || members+=(etc)
        [ ! -e "${aur_fixture_root}/usr" ] || members+=(usr)
        bsdtar "${archive_options[@]}" -caf "${aur_fixture_archive}" \
            -C "${aur_fixture_root}" -- "${members[@]}"
    }
    aur_fixture_must_reject() {
        local reason="$1" status
        set +e
        aur_package_archive_is_safe yay "${aur_fixture_archive}"
        status=$?
        set -e
        assert_real_rejection_status "$status" "AUR archive ${reason}"
    }

    aur_fixture_reset
    aur_fixture_pack
    aur_package_archive_is_safe yay "${aur_fixture_archive}" ||
        fail 'AUR archive validator rejected the minimal allowed Yay payload'

    aur_fixture_reset
    install -d -m0755 -- "${aur_fixture_root}/etc"
    printf '%s\n' 'unexpected' >"${aur_fixture_root}/etc/passwd"
    aur_fixture_pack
    aur_fixture_must_reject 'an /etc payload outside the exact package allowlist'

    aur_fixture_reset
    printf '%s\n' 'post_install() { :; }' >"${aur_fixture_root}/.INSTALL"
    aur_fixture_pack
    aur_fixture_must_reject 'executable .INSTALL metadata'

    aur_fixture_reset
    install -d -m0755 -- "${aur_fixture_root}/usr/share/libalpm/hooks"
    printf '%s\n' '[Trigger]' >"${aur_fixture_root}/usr/share/libalpm/hooks/evil.hook"
    aur_fixture_pack
    aur_fixture_must_reject 'a pacman hook'

    aur_fixture_reset
    mkfifo -- "${aur_fixture_root}/usr/bin/yay-fifo"
    aur_fixture_pack
    aur_fixture_must_reject 'a special-file payload'

    aur_fixture_reset
    chmod 0775 -- "${aur_fixture_root}/usr/bin/yay"
    aur_fixture_pack
    aur_fixture_must_reject 'a group-writable executable'

    aur_fixture_reset
    chown -R nobody:nobody -- "${aur_fixture_root}"
    aur_fixture_pack
    aur_fixture_must_reject 'non-root archive ownership'

    # PAX names can claim "root" even when the numeric owner is unprivileged. Prove the deceptive
    # human listing and the authoritative numeric listing describe the same real archive, then require
    # the production validator to reject it.
    aur_fixture_reset
    aur_fixture_pack --format pax --uid 12345 --gid 23456 --uname root --gname root
    LC_ALL=C bsdtar -tvf "${aur_fixture_archive}" |
        awk '$3 == "root" && $4 == "root" { found = 1 } END { exit !found }' ||
        fail 'numeric-owner spoof fixture lacks deceptive root names'
    LC_ALL=C bsdtar --numeric-owner -tvf "${aur_fixture_archive}" |
        awk '$3 == 12345 && $4 == 23456 { found = 1 } END { exit !found }' ||
        fail 'numeric-owner spoof fixture lacks non-root numeric IDs'
    aur_fixture_must_reject 'non-root numeric ownership disguised by root names'

    # A package capability is invisible to pacman -Qkk and can turn an otherwise ordinary executable
    # into a privilege boundary. Preserve the source xattr in a real package archive and require the
    # direct libarchive metadata oracle to stop it before pacman.
    aur_fixture_reset
    setcap cap_setuid=ep "${aur_fixture_root}/usr/bin/yay"
    getcap "${aur_fixture_root}/usr/bin/yay" | grep -q 'cap_setuid=ep' ||
        fail 'file-capability fixture was not created'
    aur_fixture_pack --xattrs
    aur_fixture_must_reject 'a file-capability extended attribute'

    aur_fixture_reset
    setfacl -m u:daemon:r-x -- "${aur_fixture_root}/usr/bin/yay"
    getfacl -cp -- "${aur_fixture_root}/usr/bin/yay" | grep -q '^user:daemon:r-x$' ||
        fail 'extended ACL fixture was not created'
    aur_fixture_pack --acls
    aur_fixture_must_reject 'an extended POSIX ACL'

    # Highly compressed or sparse inputs are bounded by their logical installed payload, not by the
    # small .pkg.tar.zst byte size. Exercise both the per-entry and aggregate limits with real archives.
    aur_fixture_reset
    truncate -s 268435457 -- "${aur_fixture_root}/usr/bin/yay"
    chmod 0755 -- "${aur_fixture_root}/usr/bin/yay"
    aur_fixture_pack
    [ "$(stat -c '%s' -- "${aur_fixture_archive}")" -le 536870912 ] ||
        fail 'per-entry logical-size fixture did not remain compressed'
    aur_fixture_must_reject 'a regular file above the logical-size ceiling'

    aur_fixture_reset
    install -d -m0755 -- "${aur_fixture_root}/usr/share/bash-completion"
    for aggregate_member in a b c d e; do
        truncate -s 214748365 -- \
            "${aur_fixture_root}/usr/share/bash-completion/${aggregate_member}"
        chmod 0644 -- "${aur_fixture_root}/usr/share/bash-completion/${aggregate_member}"
    done
    aur_fixture_pack
    [ "$(stat -c '%s' -- "${aur_fixture_archive}")" -le 536870912 ] ||
        fail 'aggregate logical-size fixture did not remain compressed'
    aur_fixture_must_reject 'an aggregate logical payload above one GiB'

    # A Bibata-shaped archive permits contained cursor aliases but rejects both escaping symlinks and
    # hardlink entries even when their names stay inside the otherwise allowed icon prefix.
    aur_fixture_reset
    printf '%s\n' 'pkgname = bibata-cursor-theme-bin' 'pkgver = 1.0-1' >"${aur_fixture_root}/.PKGINFO"
    find "${aur_fixture_root}/usr" -xdev -depth -delete
    install -d -m0755 -- "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors"
    printf '%s\n' 'cursor' >"${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/left_ptr"
    ln -s -- left_ptr "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/default"
    aur_fixture_pack
    aur_package_archive_is_safe bibata-cursor-theme-bin "${aur_fixture_archive}" ||
        fail 'AUR archive validator rejected a contained Bibata cursor alias'

    rm -f -- "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/default"
    ln -s -- ../../../../../../etc/passwd \
        "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/default"
    aur_fixture_pack
    set +e
    aur_package_archive_is_safe bibata-cursor-theme-bin "${aur_fixture_archive}"
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" 'AUR archive escaping symlink'

    rm -f -- "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/default"
    ln -- "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/left_ptr" \
        "${aur_fixture_root}/usr/share/icons/Bibata-Fixture/cursors/default"
    aur_fixture_pack
    set +e
    aur_package_archive_is_safe bibata-cursor-theme-bin "${aur_fixture_archive}"
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" 'AUR archive hardlink entry'
)

aur_archive_fixture_acceptance

# Exercise the exact user-home writer through a local arch-chroot shim. The standard nobody
# account has no login credentials; the temporary home is created only when the path is absent and
# is removed with a guarded exact-path cleanup. All writes still run after runuser drops privilege.
getent passwd nobody >/dev/null || fail 'nobody account missing for user-home regression'
# Read by the installer helpers loaded dynamically below.
# shellcheck disable=SC2034
ARCH_LINUX_USERNAME='nobody'
nobody_home="/home/${ARCH_LINUX_USERNAME}"
[ ! -e "${nobody_home}" ] || fail 'refusing to reuse the fixture user home in disposable test'
install -d -m0700 -o nobody -g nobody -- "${nobody_home}"
cleanup_nobody_home() {
    case "${nobody_home}" in
    "/home/${ARCH_LINUX_USERNAME}") find "${nobody_home}" -xdev -depth -delete ;;
    *) return 1 ;;
    esac
}
cleanup_all_test_state() {
    cleanup_nobody_home
    cleanup_test_root
}
trap cleanup_all_test_state EXIT
log_fail() { :; }
arch-chroot() {
    [ "$1" = /mnt ] || return 1
    shift
    "$@"
}
# shellcheck disable=SC1090
source <(awk '
    /^chroot_user_path_is_safe\(\)/ { capture=1 }
    /^# TRAP FUNCTIONS$/ { capture=0 }
    capture { print }
' "${repo_root}/arch-linux-installer.sh")
for extracted_function in \
    chroot_user_path_is_safe chroot_user_update_file chroot_user_write_file \
    chroot_user_append_file chroot_user_finalize_init; do
    declare -F -- "$extracted_function" >/dev/null ||
        fail "installer function extraction omitted ${extracted_function}"
done

printf '%s\n' 'root sentinel' >"${test_root}/home-write-sentinel"
sentinel_before="$(sha256sum "${test_root}/home-write-sentinel" | awk '{ print $1 }')"
install -d -m0700 -o nobody -g nobody -- "${nobody_home}/.config"
ln -s -- "${test_root}/home-write-sentinel" "${nobody_home}/.config/target"
chown -h nobody:nobody -- "${nobody_home}/.config/target"
set +e
printf '%s\n' 'attacker bytes' | chroot_user_write_file "${nobody_home}/.config/target" 0600
user_home_rejection_status=$?
set -e
assert_real_rejection_status "$user_home_rejection_status" 'user-home final symlink'
[ "$(sha256sum "${test_root}/home-write-sentinel" | awk '{ print $1 }')" = "${sentinel_before}" ] ||
    fail 'user-home symlink regression changed the root sentinel'
rm -f -- "${nobody_home}/.config/target"
printf '%s\n' 'safe bytes' | chroot_user_write_file "${nobody_home}/.config/target" 0600
[ "$(cat -- "${nobody_home}/.config/target")" = 'safe bytes' ] || fail 'user-home safe write changed bytes'
[ "$(stat -c '%U:%G:%a' -- "${nobody_home}/.config/target")" = 'nobody:nobody:600' ] ||
    fail 'user-home safe write has the wrong owner or mode'

# The disposable AUR builder is a different locked identity and must not be able to traverse or
# replace the final user's 0700 home, even with a final-component symlink attempt.
if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    getent passwd daemon >/dev/null || fail 'daemon account missing for AUR isolation acceptance'
    daemon_uid="$(id -u daemon)"
    [ "${daemon_uid}" != "$(id -u nobody)" ] || fail 'AUR fixture identity aliases target user'
    target_before="$(sha256sum "${nobody_home}/.config/target" | awk '{ print $1 }')"
    set +e
    runuser -u daemon -- sh -c 'printf "%s\n" attacker >"$1"' sh \
        "${nobody_home}/.config/target" >/dev/null 2>&1
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" 'AUR builder write into final user home'
    set +e
    runuser -u daemon -- ln -sf -- "${test_root}/home-write-sentinel" \
        "${nobody_home}/.config/target" >/dev/null 2>&1
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'AUR builder symlink replacement in final user home'
    [ "$(sha256sum "${nobody_home}/.config/target" | awk '{ print $1 }')" = "${target_before}" ] &&
        [ -f "${nobody_home}/.config/target" ] && [ ! -L "${nobody_home}/.config/target" ] ||
        fail 'AUR final-home isolation changed the accepted user file'
fi

# Load the complete production AUR identity/cgroup/opened-file boundary separately; it is
# intentionally outside the archive-validator range sourced above. The privileged fixtures must
# exercise real helpers, never absent commands whose status 127 could masquerade as safe rejection.
# shellcheck disable=SC1090
source <(awk '
    /^is_choice\(\)/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "${repo_root}/arch-linux-installer.sh")
declare -F -- is_choice >/dev/null || fail 'installer function extraction omitted is_choice'
# shellcheck disable=SC1090
source <(awk '
    /^AUR_BUILD_SEQUENCE=0$/ { capture=1 }
    /^aur_copy_regular_file_stably\(\)/ { copy_function=1 }
    capture { print }
    copy_function && /^}$/ { exit }
' "${repo_root}/arch-linux-installer.sh")
for extracted_function in \
    aur_builder_uid_has_live_process aur_builder_owned_inode_is_confined \
    aur_builder_scan_path_is_normalized aur_builder_uid_scan_target_mounts \
    aur_builder_target_owned_uids aur_builder_uid_target_is_empty \
    aur_builder_uid_target_is_confined aur_builder_uid_cleanup_target \
    aur_builder_uid_is_available aur_builder_subids_are_absent \
    aur_builder_scope_is_empty aur_builder_command_handoff_is_safe \
    aur_builder_scope_run aur_builder_account_prepare aur_builder_account_remove \
    aur_copy_regular_file_stably; do
    declare -F -- "$extracted_function" >/dev/null ||
        fail "installer function extraction omitted ${extracted_function}"
done

privileged_aur_stable_copy_acceptance() (
    local race_root source replacement opened_source destination result_file
    local copy_job='' python_pid='' child_pid fd_path opened=false copy_status=0 children_text=''
    local -a copy_processes=() child_processes=()

    race_root="$(mktemp -d /tmp/arch-linux-aur-copy.XXXXXXXX)"
    case "${race_root}" in /tmp/arch-linux-aur-copy.*) ;; *) fail 'unsafe AUR race root' ;; esac
    [ -d "${race_root}" ] && [ ! -L "${race_root}" ] || fail 'invalid AUR race root'
    chown daemon:daemon -- "${race_root}"
    chmod 0700 -- "${race_root}"
    source="${race_root}/candidate.pkg.tar.zst"
    opened_source="${race_root}/opened.pkg.tar.zst"
    replacement="${race_root}/replacement.pkg.tar.zst"
    destination="${test_root}/aur-stable-copy"
    result_file="${test_root}/aur-stable-copy.result"
    install -d -m0700 -- "${destination}"

    cleanup_aur_copy_probe() {
        if [[ "${python_pid:-}" =~ ^[0-9]+$ ]] && kill -0 "${python_pid}" 2>/dev/null; then
            kill -TERM "${python_pid}" 2>/dev/null || true
        fi
        if [[ "${copy_job:-}" =~ ^[0-9]+$ ]] && kill -0 "${copy_job}" 2>/dev/null; then
            kill -TERM "${copy_job}" 2>/dev/null || true
            wait "${copy_job}" 2>/dev/null || true
        fi
        if [ -d "${race_root}" ] && [ ! -L "${race_root}" ]; then
            find "${race_root}" -xdev -depth -delete
        fi
    }
    trap cleanup_aur_copy_probe EXIT

    fallocate -l 536870912 -- "${source}"
    printf '%s\n' replacement >"${replacement}"
    chown daemon:daemon -- "${source}" "${replacement}"
    chmod 0644 -- "${source}" "${replacement}"

    aur_copy_regular_file_stably "${source}" "${destination}" candidate "${daemon_uid}" \
        >"${result_file}" 2>/dev/null &
    copy_job=$!
    for ((attempt = 0; attempt < 1000; attempt++)); do
        copy_processes=("$copy_job")
        if [ -r "/proc/${copy_job}/task/${copy_job}/children" ]; then
            children_text="$(<"/proc/${copy_job}/task/${copy_job}/children")" || children_text=''
            if [ -n "$children_text" ]; then
                read -r -a child_processes <<<"$children_text"
                copy_processes+=("${child_processes[@]}")
            fi
        fi
        for child_pid in "${copy_processes[@]}"; do
            [[ "${child_pid}" =~ ^[0-9]+$ ]] || continue
            for fd_path in /proc/"${child_pid}"/fd/*; do
                [ "$(readlink -- "${fd_path}" 2>/dev/null || true)" = "${source}" ] || continue
                python_pid="${child_pid}"
                opened=true
                break 3
            done
        done
        kill -0 "${copy_job}" 2>/dev/null || break
        sleep 0.005
    done
    if [ "${opened}" != true ]; then
        if wait "${copy_job}"; then copy_status=0; else copy_status=$?; fi
        copy_job=''
        fail "could not synchronize AUR opened-file race fixture (copy status ${copy_status})"
    fi
    runuser -u daemon -- sh -c 'mv -- "$1" "$2"; mv -- "$3" "$1"' sh \
        "${source}" "${opened_source}" "${replacement}"
    if wait "${copy_job}"; then copy_status=0; else copy_status=$?; fi
    copy_job=''
    python_pid=''
    assert_real_rejection_status "$copy_status" 'AUR stable-copy pathname replacement race'
    [ -z "$(find "${destination}" -mindepth 1 -print -quit)" ] ||
        fail 'AUR stable copy left root-owned output after a pathname race'

    cleanup_aur_copy_probe
    trap - EXIT
)

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    privileged_aur_stable_copy_acceptance
fi

privileged_aur_uid_inode_acceptance() (
    local target_root='' nested_target='' builder_home='/var/lib/arch-linux-aur-builder'
    local home_host inode_fixture_uid=59999 occupied_uids cleanup_ok=true
    local nested_mounted=false root_mounted=false

    cleanup_aur_uid_inode_probe() {
        if [ "$nested_mounted" = true ]; then
            umount -- "$nested_target" 2>/dev/null || cleanup_ok=false
            nested_mounted=false
        fi
        if [ "$root_mounted" = true ]; then
            umount -- "$target_root" 2>/dev/null || cleanup_ok=false
            root_mounted=false
        fi
        if [ -n "$target_root" ]; then
            case "$target_root" in
            /tmp/arch-linux-aur-uid-target.*)
                if [ -d "$target_root" ] && [ ! -L "$target_root" ]; then
                    find "$target_root" -xdev -depth -delete || cleanup_ok=false
                elif [ -e "$target_root" ] || [ -L "$target_root" ]; then
                    cleanup_ok=false
                fi
                ;;
            *) cleanup_ok=false ;;
            esac
            target_root=''
        fi
        [ "$cleanup_ok" = true ] ||
            printf 'keyring rotation check failed: AUR UID inode fixture cleanup mismatch\n' >&2
    }
    trap cleanup_aur_uid_inode_probe EXIT

    ! aur_builder_uid_has_live_process "$inode_fixture_uid" ||
        fail 'disposable AUR UID fixture already has a live process'
    target_root="$(mktemp -d /tmp/arch-linux-aur-uid-target.XXXXXXXX)"
    case "$target_root" in /tmp/arch-linux-aur-uid-target.*) ;; *) fail 'unsafe AUR UID target root' ;; esac
    chmod 0755 -- "$target_root"
    mount -t tmpfs -o nodev,nosuid,noexec,mode=0755 \
        "arch-linux-aur-root-${BASHPID}" "$target_root"
    root_mounted=true
    install -d -m1777 -- "$target_root/var/tmp"
    install -d -m0755 -- "$target_root/var/lib" "$target_root/other"

    # One inode is hidden in the parent filesystem by a separate target mount and another lives
    # in the nested filesystem. The scanner must see both independent filesystem roots.
    install -o "$inode_fixture_uid" -g "$inode_fixture_uid" -m0600 \
        /dev/null "$target_root/other/hidden-parent"
    nested_target="$target_root/other"
    mount -t tmpfs -o nodev,nosuid,noexec,mode=0755 \
        "arch-linux-aur-nested-${BASHPID}" "$nested_target"
    nested_mounted=true
    install -d -m1777 -- "$nested_target/writable"
    install -o "$inode_fixture_uid" -g "$inode_fixture_uid" -m0600 \
        /dev/null "$nested_target/nested-preexisting"
    set +e
    aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' empty
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'AUR UID scanner preexisting inodes across target filesystems'
    occupied_uids="$(aur_builder_uid_scan_target_mounts "$target_root" 1 '' occupied-uids \
        "$inode_fixture_uid" "$inode_fixture_uid")" ||
        fail 'AUR UID range inventory failed across target filesystems'
    [ "$occupied_uids" = "$inode_fixture_uid" ] ||
        fail 'AUR UID range inventory missed the occupied candidate'
    aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' cleanup ||
        fail 'AUR UID scanner could not clean preexisting UID-owned inodes'
    aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' empty ||
        fail 'AUR UID scanner did not prove the selected UID empty'

    home_host="${target_root}${builder_home}"
    install -d -o "$inode_fixture_uid" -g "$inode_fixture_uid" -m0700 -- "$home_host"
    AUR_ACTIVE_BUILDER_UID="$inode_fixture_uid"
    AUR_ACTIVE_BUILDER_HOME="$builder_home"
    AUR_ACTIVE_BUILDER_USER='archlinux-aur-builder'
    # Test seam invoked indirectly by the production handoff helper.
    # shellcheck disable=SC2329
    aur_builder_subids_are_absent() {
        [ "$1" = "$AUR_ACTIVE_BUILDER_USER" ] && [ "${2:-/mnt}" = /mnt ]
    }
    aur_builder_uid_target_is_confined() {
        [ "$1" = "$inode_fixture_uid" ] && [ "$2" = "$builder_home" ] &&
            aur_builder_uid_scan_target_mounts \
                "$target_root" "$inode_fixture_uid" "$builder_home" confined
    }
    aur_builder_uid_cleanup_target() {
        [ "$1" = "$inode_fixture_uid" ] &&
            ! aur_builder_uid_has_live_process "$inode_fixture_uid" &&
            aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' cleanup &&
            aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' empty
    }
    setpriv --reuid "$inode_fixture_uid" --regid "$inode_fixture_uid" --clear-groups \
        sh -c 'printf "%s\n" safe >"$1"' sh "$home_host/build-state"
    aur_builder_uid_target_is_confined "$inode_fixture_uid" "$builder_home" ||
        fail 'AUR UID fixture confinement adapter rejected the exact home'
    aur_builder_command_handoff_is_safe 0 false ||
        fail 'AUR UID scanner rejected the exact disposable builder home'

    setpriv --reuid "$inode_fixture_uid" --regid "$inode_fixture_uid" --clear-groups \
        sh -c 'printf "%s\n" escaped >"$1"' sh \
        "$target_root/var/tmp/aur-escape"
    set +e
    aur_builder_command_handoff_is_safe 0 false
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" 'AUR UID scanner /var/tmp escape'
    aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' empty ||
        fail 'AUR UID-scoped cleanup left /var/tmp ownership behind'

    install -d -o "$inode_fixture_uid" -g "$inode_fixture_uid" -m0700 -- "$home_host"
    setpriv --reuid "$inode_fixture_uid" --regid "$inode_fixture_uid" --clear-groups \
        sh -c 'printf "%s\n" escaped >"$1"' sh \
        "$nested_target/writable/aur-escape"
    set +e
    aur_builder_command_handoff_is_safe 0 false
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" 'AUR UID scanner nested mount escape'
    aur_builder_uid_cleanup_target "$inode_fixture_uid" ||
        fail 'AUR UID cleanup adapter failed its final zero-state readback'
    aur_builder_uid_scan_target_mounts "$target_root" "$inode_fixture_uid" '' empty ||
        fail 'AUR UID-scoped cleanup left target inodes behind'
    [ ! -e "$home_host" ] && [ ! -L "$home_host" ] ||
        fail 'AUR UID-scoped cleanup retained the disposable home'

    cleanup_aur_uid_inode_probe
    [ "$cleanup_ok" = true ] || fail 'AUR UID inode acceptance cleanup failed'
    trap - EXIT
)

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    privileged_aur_uid_inode_acceptance
fi

# Current Arch useradd allocates subordinate ranges for regular users. The production account is
# deliberately a system account, and every command handoff independently requires both the text
# databases and getsubids' effective view to remain empty. Exercise creation, late delegation,
# cleanup and the exact production predicate without exposing assigned ranges in test output.
privileged_aur_subid_acceptance() (
    local regular_user="alreg${BASHPID}" system_user="alsys${BASHPID}"
    local regular_uid='' system_uid='' candidate_uid range_start range_end
    local regular_created=false system_created=false cleanup_ok=true

    cleanup_aur_subid_probe() {
        if [ "$system_created" = true ]; then
            userdel -- "$system_user" >/dev/null 2>&1 || cleanup_ok=false
            system_created=false
        fi
        if [ "$regular_created" = true ]; then
            userdel -- "$regular_user" >/dev/null 2>&1 || cleanup_ok=false
            regular_created=false
        fi
        ! getent passwd "$system_user" >/dev/null 2>&1 || cleanup_ok=false
        ! getent passwd "$regular_user" >/dev/null 2>&1 || cleanup_ok=false
        [ "$cleanup_ok" = true ] ||
            printf 'keyring rotation check failed: AUR subordinate-ID fixture cleanup mismatch\n' >&2
    }
    trap cleanup_aur_subid_probe EXIT

    [[ "$regular_user" =~ ^[a-z][a-z0-9]{1,31}$ ]] &&
        [[ "$system_user" =~ ^[a-z][a-z0-9]{1,31}$ ]] ||
        fail 'invalid AUR subordinate-ID fixture names'
    if getent passwd "$regular_user" >/dev/null 2>&1 ||
        getent passwd "$system_user" >/dev/null 2>&1; then
        fail 'AUR subordinate-ID fixture account already exists'
    fi
    for ((candidate_uid = 58000; candidate_uid <= 58999; candidate_uid++)); do
        if ! getent passwd "$candidate_uid" >/dev/null 2>&1; then
            if [ -z "$regular_uid" ]; then
                regular_uid="$candidate_uid"
            else
                system_uid="$candidate_uid"
                break
            fi
        fi
    done
    [ -n "$regular_uid" ] && [ -n "$system_uid" ] ||
        fail 'could not reserve two AUR subordinate-ID fixture UIDs'

    useradd --uid "$regular_uid" --no-user-group --no-log-init --gid users \
        --no-create-home --home-dir /nonexistent --shell /usr/bin/nologin -- \
        "$regular_user" >/dev/null 2>&1 || fail 'could not create regular subid fixture account'
    regular_created=true
    if ! getsubids "$regular_user" >/dev/null 2>&1 ||
        ! getsubids -g "$regular_user" >/dev/null 2>&1; then
        fail 'regular Arch account did not receive effective subordinate IDs'
    fi
    set +e
    aur_builder_subids_are_absent "$regular_user" /
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'AUR subordinate-ID predicate regular-user delegation'
    userdel -- "$regular_user" >/dev/null 2>&1 || fail 'could not remove regular subid fixture account'
    regular_created=false
    aur_builder_subids_are_absent "$regular_user" / ||
        fail 'regular-user subordinate IDs survived account deletion'

    useradd --system --uid "$system_uid" --no-user-group --no-log-init --gid users \
        --no-create-home --home-dir /var/lib/arch-linux-aur-builder \
        --shell /usr/bin/nologin -- "$system_user" >/dev/null 2>&1 ||
        fail 'could not create system subid fixture account'
    system_created=true
    aur_builder_subids_are_absent "$system_user" / ||
        fail 'system AUR fixture account received subordinate IDs'

    range_start=$((3000000000 + BASHPID % 1000000))
    range_end="$range_start"
    usermod --add-subuids "${range_start}-${range_end}" \
        --add-subgids "${range_start}-${range_end}" -- "$system_user" >/dev/null 2>&1 ||
        fail 'could not create late subordinate-ID delegation fixture'
    if ! getsubids "$system_user" >/dev/null 2>&1 ||
        ! getsubids -g "$system_user" >/dev/null 2>&1; then
        fail 'late subordinate-ID delegation is not effective'
    fi
    set +e
    aur_builder_subids_are_absent "$system_user" /
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        'AUR subordinate-ID predicate late effective delegation'
    userdel -- "$system_user" >/dev/null 2>&1 || fail 'could not remove system subid fixture account'
    system_created=false
    aur_builder_subids_are_absent "$system_user" / ||
        fail 'late subordinate IDs survived system-account deletion'

    cleanup_aur_subid_probe
    [ "$cleanup_ok" = true ] || fail 'AUR subordinate-ID fixture cleanup failed'
    trap - EXIT
)

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    privileged_aur_subid_acceptance
fi

privileged_process_containment_acceptance() (
    local process_probe_root detached_pid_file detached_marker worker_pid ack_pid='' process_status=0
    local detached_pid='' actual_pgid='' attempt scope_root='' scope_pid_file scope_marker scope_output
    local child_scope cleanup_ok=true scope_user="alscope${BASHPID}" scope_uid=59998
    local scope_user_created=false

    cleanup_process_containment_probe() {
        # A failed assertion must not strand the exact worker or any descendant test cgroup. The
        # production teardown remains the subject under test; this trap is only a final emergency
        # boundary for the disposable acceptance environment.
        set +m
        if [[ "${worker_pid:-}" =~ ^[0-9]+$ ]] && kill -0 "${worker_pid}" 2>/dev/null; then
            actual_pgid="$(ps -o pgid= -p "${worker_pid}" 2>/dev/null | tr -d '[:space:]')"
            if [ "${actual_pgid}" = "${worker_pid}" ]; then
                kill -TERM -- "-${actual_pgid}" 2>/dev/null || true
            else
                kill -TERM -- "${worker_pid}" 2>/dev/null || true
            fi
        fi
        case "${PROCESS_CGROUP_DIR:-}" in
        /sys/fs/cgroup/*/arch-linux-installer-* | /sys/fs/cgroup/arch-linux-installer-*)
            if [ -d "${PROCESS_CGROUP_DIR}" ]; then
                [ ! -w "${PROCESS_CGROUP_DIR}/cgroup.kill" ] ||
                    printf '%s\n' 1 >"${PROCESS_CGROUP_DIR}/cgroup.kill" 2>/dev/null || cleanup_ok=false
                for ((attempt = 0; attempt < 100; attempt++)); do
                    grep -qx 'populated 0' "${PROCESS_CGROUP_DIR}/cgroup.events" 2>/dev/null && break
                    sleep 0.05
                done
                for child_scope in "${PROCESS_CGROUP_DIR}"/aur-build-*; do
                    [ -d "${child_scope}" ] || continue
                    case "${child_scope}" in
                    "${PROCESS_CGROUP_DIR}"/aur-build-*) ;;
                    *) cleanup_ok=false; continue ;;
                    esac
                    grep -qx 'populated 0' "${child_scope}/cgroup.events" 2>/dev/null || {
                        [ ! -w "${child_scope}/cgroup.kill" ] ||
                            printf '%s\n' 1 >"${child_scope}/cgroup.kill" 2>/dev/null || cleanup_ok=false
                    }
                    rmdir -- "${child_scope}" 2>/dev/null || cleanup_ok=false
                done
                rmdir -- "${PROCESS_CGROUP_DIR}" 2>/dev/null || cleanup_ok=false
            fi
            ;;
        '') ;;
        *) cleanup_ok=false ;;
        esac
        if [[ "${worker_pid:-}" =~ ^[0-9]+$ ]]; then
            wait "${worker_pid}" 2>/dev/null || true
            worker_pid=''
        fi
        if [ -n "${scope_root}" ]; then
            case "${scope_root}" in
            /tmp/arch-linux-aur-scope.*)
                if [ -d "${scope_root}" ] && [ ! -L "${scope_root}" ] &&
                    [ "$(stat -c '%u:%a' -- "${scope_root}" 2>/dev/null)" = "${scope_uid}:700" ]; then
                    find "${scope_root}" -xdev -depth -delete || cleanup_ok=false
                elif [ -e "${scope_root}" ] || [ -L "${scope_root}" ]; then
                    cleanup_ok=false
                fi
                ;;
            *) cleanup_ok=false ;;
            esac
            scope_root=''
        fi
        if [ "$scope_user_created" = true ]; then
            if [ "$(id -u -- "$scope_user" 2>/dev/null)" = "$scope_uid" ]; then
                userdel -- "$scope_user" >/dev/null 2>&1 || cleanup_ok=false
            else
                cleanup_ok=false
            fi
            scope_user_created=false
        fi
        ! getent passwd "$scope_user" >/dev/null 2>&1 || cleanup_ok=false
        [ "${cleanup_ok}" = true ] ||
            printf 'keyring rotation check failed: process-containment cleanup mismatch\n' >&2
    }
    trap cleanup_process_containment_probe EXIT

    # Load only the production cgroup lifecycle used by every executor.
    # shellcheck disable=SC1090
    source <(awk '
        /^process_init\(\)/ { capture=1 }
        /^# GUM BINARY$/ { capture=0 }
        capture { print }
    ' "${repo_root}/arch-linux-installer.sh")
    for extracted_function in \
        process_init process_enter_cgroup process_cgroup_is_empty \
        process_wait_cgroup_empty process_kill_contained process_log_contained_members \
        process_member_is_expected_gpg_agent process_terminate_expected_gpg_agents \
        process_remove_cgroup process_reap_active process_capture process_return; do
        declare -F -- "$extracted_function" >/dev/null ||
            fail "installer function extraction omitted ${extracted_function}"
    done

    process_probe_root="${test_root}/process-containment"
    install -d -m0700 -- "${process_probe_root}"
    SCRIPT_TMP_DIR="${process_probe_root}"
    PROCESS_RET_TMP_FILE="${process_probe_root}/process.ret"
    PROCESS_LOG_TMP_FILE="${process_probe_root}/process.log"
    PROCESS_CGROUP_ACK_TMP_FILE="${process_probe_root}/process.ready"
    SCRIPT_LOG="${process_probe_root}/installer.log"
    PROCESS_SEQUENCE=0
    PROCESS_ACTIVE_PID=''
    PROCESS_ACTIVE_PGID=''
    PROCESS_CGROUP_DIR=''
    PROCESS_CGROUP_RELATIVE=''
    # These test seams are invoked by the production functions loaded dynamically above.
    # shellcheck disable=SC2329
    runtime_directory_metadata_is_safe() {
        [ "$1" = "${SCRIPT_TMP_DIR}" ] && [ "$2" = 0 ] &&
            [ -d "$1" ] && [ ! -L "$1" ] && [ "$(stat -c '%u:%a' -- "$1")" = '0:700' ]
    }
    # shellcheck disable=SC2329
    gum_fail() { fail "$*"; }
    # shellcheck disable=SC2329
    log_proc() { :; }

    detached_pid_file="${process_probe_root}/detached.pid"
    detached_marker="${process_probe_root}/detached.marker"
    process_init 'Detached executor fixture'
    (
        process_enter_cgroup
        setsid bash -c '
            printf "%s\n" "$BASHPID" >"$1"
            trap "" TERM
            sleep 30
            printf "%s\n" escaped >"$2"
        ' bash "${detached_pid_file}" "${detached_marker}" &
        for ((attempt = 0; attempt < 100; attempt++)); do
            [ -s "${detached_pid_file}" ] && break
            sleep 0.01
        done
        [ -s "${detached_pid_file}" ] || exit 125
        process_return 0
    ) >"${PROCESS_LOG_TMP_FILE}" 2>&1 &
    worker_pid=$!
    actual_pgid="$(ps -o pgid= -p "${worker_pid}" | tr -d '[:space:]')"
    [ "${actual_pgid}" = "${worker_pid}" ] || fail 'executor fixture lacks its own process group'
    for ((attempt = 0; attempt < 100; attempt++)); do
        if [ -s "${PROCESS_CGROUP_ACK_TMP_FILE}" ]; then
            IFS= read -r ack_pid <"${PROCESS_CGROUP_ACK_TMP_FILE}" || ack_pid=''
            break
        fi
        kill -0 "${worker_pid}" 2>/dev/null || break
        sleep 0.01
    done
    [ "${ack_pid}" = "${worker_pid}" ] || fail 'executor did not acknowledge exact cgroup membership'
    for ((attempt = 0; attempt < 100; attempt++)); do
        [ -s "${detached_pid_file}" ] && break
        sleep 0.01
    done
    [ -s "${detached_pid_file}" ] || fail 'detached executor fixture did not start'
    IFS= read -r detached_pid <"${detached_pid_file}"
    [[ "${detached_pid}" =~ ^[0-9]+$ ]] || fail 'invalid detached executor PID evidence'
    PROCESS_ACTIVE_PID="${worker_pid}"
    PROCESS_ACTIVE_PGID="${actual_pgid}"
    set +m
    if process_reap_active false; then process_status=0; else process_status=$?; fi
    [ "${process_status}" -eq 124 ] || fail 'detached executor was not reported as containment failure'
    [ -z "${PROCESS_CGROUP_DIR}" ] && [ -z "${PROCESS_ACTIVE_PID}" ] ||
        fail 'executor cgroup was not removed after containment failure'
    for ((attempt = 0; attempt < 100; attempt++)); do
        kill -0 "${detached_pid}" 2>/dev/null || break
        sleep 0.01
    done
    ! kill -0 "${detached_pid}" 2>/dev/null || fail 'detached executor survived cgroup.kill'
    [ ! -e "${detached_marker}" ] || fail 'detached executor wrote after containment teardown'
    unlink -- "${PROCESS_RET_TMP_FILE}"
    unlink -- "${PROCESS_CGROUP_ACK_TMP_FILE}"

    # Exercise the narrower AUR child cgroup with a real unprivileged, setsid descendant. The
    # command exits successfully only after the descendant exists; the runner must still fail,
    # kill it and prove both the cgroup and builder UID empty before root handoff.
    [[ "$scope_user" =~ ^[a-z][a-z0-9]{1,31}$ ]] || fail 'invalid AUR scope fixture name'
    ! getent passwd "$scope_user" >/dev/null 2>&1 || fail 'AUR scope fixture account exists'
    ! getent passwd "$scope_uid" >/dev/null 2>&1 || fail 'AUR scope fixture UID is occupied'
    useradd --system --uid "$scope_uid" --no-user-group --no-log-init --gid users \
        --no-create-home --home-dir /var/lib/arch-linux-aur-builder \
        --shell /usr/bin/nologin -- "$scope_user" >/dev/null 2>&1 ||
        fail 'could not create AUR scope fixture account'
    scope_user_created=true
    scope_root="$(mktemp -d /tmp/arch-linux-aur-scope.XXXXXXXX)"
    case "${scope_root}" in /tmp/arch-linux-aur-scope.*) ;; *) fail 'unsafe AUR scope root' ;; esac
    chown "$scope_uid:$(id -g -- "$scope_user")" -- "${scope_root}"
    chmod 0700 -- "${scope_root}"
    scope_pid_file="${scope_root}/detached.pid"
    scope_marker="${scope_root}/detached.marker"
    scope_output="${SCRIPT_TMP_DIR}/aur-scope.output"
    process_init 'AUR detached fixture'
    AUR_ACTIVE_BUILDER_UID="$scope_uid"
    AUR_ACTIVE_BUILDER_HOME='/var/lib/arch-linux-aur-builder'
    AUR_ACTIVE_BUILDER_USER="$scope_user"
    # Test seams invoked indirectly by the production AUR cgroup runner.
    # shellcheck disable=SC2329
    aur_builder_subids_are_absent() {
        [ "$1" = "$AUR_ACTIVE_BUILDER_USER" ] && [ "${2:-/mnt}" = /mnt ]
    }
    # shellcheck disable=SC2329
    aur_builder_uid_target_is_confined() {
        [ "$1" = "$AUR_ACTIVE_BUILDER_UID" ] &&
            [ "$2" = "$AUR_ACTIVE_BUILDER_HOME" ]
    }
    # shellcheck disable=SC2329
    aur_builder_uid_cleanup_target() { [ "$1" = "$AUR_ACTIVE_BUILDER_UID" ]; }
    if aur_builder_uid_has_live_process "${AUR_ACTIVE_BUILDER_UID}"; then
        fail 'AUR fixture UID already has a live process'
    fi
    set +e
    aur_builder_scope_run "${scope_output}" runuser -u "$scope_user" -- bash -c '
        setsid bash -c '\''
            printf "%s\n" "$BASHPID" >"$1"
            trap "" TERM
            sleep 30
            printf "%s\n" escaped >"$2"
        '\'' bash "$1" "$2" &
        for ((attempt = 0; attempt < 100; attempt++)); do
            [ -s "$1" ] && exit 0
            sleep 0.01
        done
        exit 125
    ' bash "${scope_pid_file}" "${scope_marker}"
    scope_status=$?
    set -e
    assert_real_rejection_status "$scope_status" \
        'AUR child-cgroup runner detached descendant'
    [ -s "${scope_pid_file}" ] || fail 'AUR detached fixture did not record its PID'
    IFS= read -r detached_pid <"${scope_pid_file}"
    [[ "${detached_pid}" =~ ^[0-9]+$ ]] || fail 'invalid AUR detached PID evidence'
    for ((attempt = 0; attempt < 100; attempt++)); do
        kill -0 "${detached_pid}" 2>/dev/null || break
        sleep 0.01
    done
    ! kill -0 "${detached_pid}" 2>/dev/null || fail 'AUR detached descendant survived cgroup.kill'
    [ ! -e "${scope_marker}" ] || fail 'AUR detached descendant wrote after scope teardown'
    ! aur_builder_uid_has_live_process "${AUR_ACTIVE_BUILDER_UID}" ||
        fail 'AUR builder UID retained a live process after scope teardown'
    process_remove_cgroup || fail 'AUR parent cgroup did not become empty'
    set +m
    unlink -- "${PROCESS_RET_TMP_FILE}"
    unlink -- "${scope_output}"
    [ ! -e "${PROCESS_CGROUP_ACK_TMP_FILE}" ] || unlink -- "${PROCESS_CGROUP_ACK_TMP_FILE}"
    find "${scope_root}" -xdev -depth -delete
    scope_root=''
    cleanup_process_containment_probe
    [ "${cleanup_ok}" = true ] || fail 'process-containment acceptance cleanup failed'
    trap - EXIT
)

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    privileged_process_containment_acceptance
fi

# Exercise every fail-closed scriptlet branch without replacing the package-owned pacman-key on
# the disposable test host. The temporary copy differs only in the absolute command path.
mock_pacman_key="${test_root}/mock-pacman-key"
mock_install="${test_root}/arch-linux-keyring.install"
mock_log="${test_root}/mock-pacman-key.log"
{
    printf '%s\n' 'case "$1" in'
    printf '%s\n' '    --list-keys) stage=list ;;'
    printf '%s\n' '    --populate) stage=populate ;;'
    printf '%s\n' '    --updatedb) stage=updatedb ;;'
    printf '%s\n' '    *) exit 2 ;;'
    printf '%s\n' 'esac'
    printf '%s\n' 'printf '\''%s\n'\'' "${stage}" >>"${ARCH_LINUX_KEYRING_MOCK_LOG}"'
    printf '%s\n' '[ "${ARCH_LINUX_KEYRING_FAIL_STAGE:-none}" != "${stage}" ]'
} >"${mock_pacman_key}"
sed "s#/usr/bin/pacman-key#/bin/sh ${mock_pacman_key}#g" \
    "${repo_root}/packages/arch-linux-keyring/arch-linux-keyring.install" \
    >"${mock_install}"
for failure_stage in list populate updatedb; do
    : >"${mock_log}"
    set +e
    env ARCH_LINUX_KEYRING_FAIL_STAGE="${failure_stage}" \
        ARCH_LINUX_KEYRING_MOCK_LOG="${mock_log}" \
        sh -c '. "$1"; command -v refresh_arch_linux_keyring >/dev/null || exit 127; refresh_arch_linux_keyring' sh "${mock_install}" >/dev/null 2>&1
    rejection_status=$?
    set -e
    assert_real_rejection_status "$rejection_status" \
        "keyring scriptlet ${failure_stage} failure"
done
: >"${mock_log}"
env ARCH_LINUX_KEYRING_FAIL_STAGE=none ARCH_LINUX_KEYRING_MOCK_LOG="${mock_log}" \
    sh -c '. "$1"; command -v refresh_arch_linux_keyring >/dev/null || exit 127; refresh_arch_linux_keyring' sh "${mock_install}" >/dev/null 2>&1 ||
    fail 'keyring scriptlet rejected a successful certificate refresh'

gpg --batch --no-options --homedir "${signing_home}" --pinentry-mode loopback --passphrase '' \
    --quick-generate-key 'arch-linux pacman-key rotation fixture' ed25519 cert 0 >/dev/null 2>&1
primary_fingerprint="$(gpg --batch --no-options --homedir "${signing_home}" --with-colons \
    --fingerprint 2>/dev/null | awk -F: '$1 == "fpr" { print toupper($10); exit }')"
[[ "${primary_fingerprint}" =~ ^[A-F0-9]{40}$ ]] || fail 'cannot generate fixture primary'
gpg --batch --no-options --homedir "${signing_home}" --pinentry-mode loopback --passphrase '' \
    --quick-add-key "${primary_fingerprint}" ed25519 sign 1d >/dev/null 2>&1
current_subkey="$(gpg --batch --no-options --homedir "${signing_home}" --with-colons \
    --with-subkey-fingerprint --list-secret-keys -- "${primary_fingerprint}" 2>/dev/null |
    awk -F: '$1 == "ssb" { want=1; next } want && $1 == "fpr" { print toupper($10); exit }')"
[[ "${current_subkey}" =~ ^[A-F0-9]{40}$ ]] || fail 'cannot select current signing subkey'
gpg --batch --no-options --homedir "${signing_home}" --export -- "${primary_fingerprint}" \
    >"${test_root}/current-certificate.gpg" 2>/dev/null

pacman-key --gpgdir "${client_home}" --init >/dev/null 2>&1
pacman-key --gpgdir "${client_home}" --add "${test_root}/current-certificate.gpg" >/dev/null 2>&1
pacman-key --gpgdir "${client_home}" --lsign-key "${primary_fingerprint}" >/dev/null 2>&1
gpg --batch --no-options --homedir "${client_home}" --check-trustdb >/dev/null 2>&1
current_validity="$(gpg --batch --no-options --homedir "${client_home}" --with-colons \
    --list-keys -- "${primary_fingerprint}" 2>/dev/null | awk -F: '$1 == "pub" { print $2; exit }')"
case "${current_validity}" in
    f|u) ;;
    *) fail 'fixture primary is not locally trusted before refresh' ;;
esac
current_metadata="$(
    gpg --batch --no-options --homedir "${client_home}" --with-colons \
        --with-subkey-fingerprint --list-keys -- "${primary_fingerprint}!" 2>/dev/null
)"
export REPOSITORY_PRIMARY_FINGERPRINT="${primary_fingerprint}"
export REPOSITORY_SIGNING_SUBKEY_FINGERPRINT="${current_subkey}"
# Load only the pure predicate; sourcing the installer would install runtime traps and state.
# shellcheck disable=SC1090
source <(sed -n '/^repository_key_metadata_matches()/,/^}/p' "${repo_root}/arch-linux-installer.sh")
declare -F -- repository_key_metadata_matches >/dev/null ||
    fail 'installer function extraction omitted repository_key_metadata_matches'
if ! repository_key_metadata_matches "${current_metadata}" trusted "$(date +%s)"; then
    current_shape="$(awk -F: '$1 == "pub" || $1 == "sub" { print $1 "/validity=" $2 "/algo=" $4 "/expiry=" $7 "/caps=" $12 }' <<<"${current_metadata}" | paste -sd, -)"
    fail "installer exact-keyblock predicate rejected the one-subkey locally trusted keyblock (${current_shape})"
fi
set +e
gpg --batch --no-options --homedir "${client_home}" \
    --list-secret-keys -- "${primary_fingerprint}!" >/dev/null 2>&1
rejection_status=$?
set -e
assert_real_rejection_status "$rejection_status" \
    'public pacman keyring fixture secret material'

gpg --batch --no-options --homedir "${signing_home}" --pinentry-mode loopback --passphrase '' \
    --quick-add-key "${primary_fingerprint}" ed25519 sign 1d >/dev/null 2>&1
mapfile -t signing_subkeys < <(
    gpg --batch --no-options --homedir "${signing_home}" --with-colons \
        --with-subkey-fingerprint --list-secret-keys -- "${primary_fingerprint}" 2>/dev/null |
        awk -F: '$1 == "ssb" { want=1; next } want && $1 == "fpr" { print toupper($10); want=0 }'
)
[ "${#signing_subkeys[@]}" -eq 2 ] || fail 'fixture does not contain two signing subkeys'
replacement_subkey="${signing_subkeys[1]}"
set +e
gpg --batch --no-options --homedir "${client_home}" --list-keys -- "${replacement_subkey}!" \
    >/dev/null 2>&1
rejection_status=$?
set -e
assert_real_rejection_status "$rejection_status" \
    'client replacement signing subkey before certificate refresh'

gpg --batch --no-options --homedir "${signing_home}" --export -- "${primary_fingerprint}" \
    >"${import_dir}/arch-linux.gpg" 2>/dev/null
[ ! -e "${import_dir}/arch-linux-trusted" ] || fail 'fixture must not grant ownertrust'
pacman-key --gpgdir "${client_home}" --populate-from "${import_dir}" \
    --populate arch-linux >/dev/null 2>&1
pacman-key --gpgdir "${client_home}" --updatedb >/dev/null 2>&1

refreshed_validity="$(gpg --batch --no-options --homedir "${client_home}" --with-colons \
    --list-keys -- "${primary_fingerprint}" 2>/dev/null | awk -F: '$1 == "pub" { print $2; exit }')"
case "${refreshed_validity}" in
    f|u) ;;
    *) fail 'certificate refresh lost the installer-created local trust' ;;
esac
gpg --batch --no-options --homedir "${client_home}" --list-keys -- "${replacement_subkey}!" \
    >/dev/null 2>&1 || fail 'real pacman-key populate did not import the replacement signing subkey'

printf 'replacement signing-subkey payload\n' >"${test_root}/payload"
gpg --batch --no-options --homedir "${signing_home}" --pinentry-mode loopback --passphrase '' \
    --local-user "${replacement_subkey}!" --detach-sign --output "${test_root}/payload.sig" \
    -- "${test_root}/payload" >/dev/null 2>&1
pacman-key --gpgdir "${client_home}" --verify \
    "${test_root}/payload.sig" "${test_root}/payload" >/dev/null 2>&1 ||
    fail 'pacman-key rejected a signature from the authenticated replacement subkey'

# Reproduce the installer-specific merge threat with the real pacman keyring. The former
# first-fingerprint/first-subkey predicate would still accept this locally trusted keyblock even
# though pacman now accepts the second signing subkey. The current exact-shape predicate must stop
# it before any repository configuration or transaction is enabled.
merged_metadata="$(
    gpg --batch --no-options --homedir "${client_home}" --with-colons \
        --with-subkey-fingerprint --list-keys -- "${primary_fingerprint}!" 2>/dev/null
)"
first_only_primary="$(awk -F: '$1 == "fpr" { print toupper($10); exit }' <<<"${merged_metadata}")"
first_only_signing="$(awk -F: '$1 == "sub" { want=1; next } want && $1 == "fpr" { print toupper($10); exit }' <<<"${merged_metadata}")"
first_only_validity="$(awk -F: '$1 == "pub" { print $2; exit }' <<<"${merged_metadata}")"
[ "${first_only_primary}" = "${primary_fingerprint}" ] || fail 'first-only predicate did not select the expected primary'
[ "${first_only_signing}" = "${current_subkey}" ] || fail 'first-only predicate did not select the expected first signing subkey'
case "${first_only_validity}" in
    f|u) ;;
    *) fail 'first-only predicate fixture is not locally trusted' ;;
esac

set +e
repository_key_metadata_matches "${merged_metadata}" trusted "$(date +%s)"
merged_key_rejection_status=$?
set -e
assert_real_rejection_status "$merged_key_rejection_status" \
    'installer exact-keyblock predicate additional trusted signing subkey'

if [ "${ARCH_LINUX_PRIVILEGED_ACCEPTANCE:-false}" = true ]; then
    printf 'KEYRING_ROTATION_CHECKS_RESULT schema=1 mode=privileged namespace_fixtures=full scenarios=10 signer=passed deferred=none\n'
else
    printf 'KEYRING_ROTATION_CHECKS_RESULT schema=1 mode=ordinary namespace_fixtures=partial scenarios=5 signer=passed deferred=privileged\n'
fi
