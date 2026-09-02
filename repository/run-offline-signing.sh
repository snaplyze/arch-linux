#!/usr/bin/bash -p

set +x
set -e
set -u
set -o pipefail
IFS=$' \t\n'
umask 077

# This file is never a public entrypoint.  The root-owned compiled launcher verifies the complete
# sealed code closure before it reads private pathnames, then starts this script under Bash -p with
# an exact empty-derived environment.  Its live parent remains that launcher and supplies a
# one-shot pipe capability.  Direct or sourced execution therefore fails before private-key use.
case "$-" in
    *p*) ;;
    *)
        printf 'ERROR: offline signing requires the sealed compiled launcher\n' >&2
        exit 1
        ;;
esac
PATH=/usr/bin:/bin
LC_ALL=C
LANG=C
HOME=/nonexistent
TMPDIR=/tmp
export PATH LC_ALL LANG HOME TMPDIR
unset BASH_ENV ENV GPG_AGENT_INFO LD_AUDIT LD_LIBRARY_PATH LD_PRELOAD PYTHONPATH PYTHONHOME

[ "$#" -ge 2 ] && [ "$1" = --sealed-broker ] || {
    printf 'ERROR: offline signing requires the sealed compiled launcher\n' >&2
    exit 1
}
shift
[[ "${ARCH_LINUX_OFFLINE_BROKER_PARENT:-}" =~ ^[1-9][0-9]*$ ]] &&
    [ "${PPID}" = "$ARCH_LINUX_OFFLINE_BROKER_PARENT" ] || {
    printf 'ERROR: offline signing broker parent binding failed\n' >&2
    exit 1
}
IFS= read -r broker_inspection <&8 || {
    printf 'ERROR: offline signing parent-inspection gate is unavailable\n' >&2
    exit 1
}
[ "$broker_inspection" = arch-linux-offline-inspection-v1 ] || {
    printf 'ERROR: offline signing parent-inspection gate differs\n' >&2
    exit 1
}
unset broker_inspection

authenticate_launcher_parent_liveness() {
    local expected_parent="${ARCH_LINUX_OFFLINE_BROKER_PARENT:-}"
    local expected_start="${ARCH_LINUX_OFFLINE_BROKER_PARENT_START:-}"
    local expected_uid="${ARCH_LINUX_SIGNING_HOST_UID:-}"
    local expected_gid="${ARCH_LINUX_SIGNING_HOST_GID:-}"
    local actual_start label real effective saved filesystem
    local uid_line='' gid_line=''

    [[ "$expected_parent" =~ ^[1-9][0-9]*$ ]] && [ "$PPID" = "$expected_parent" ] &&
        [[ "$expected_start" =~ ^[1-9][0-9]*$ ]] &&
        [[ "$expected_uid" =~ ^[1-9][0-9]*$ ]] && [[ "$expected_gid" =~ ^[1-9][0-9]*$ ]] ||
        return 1
    actual_start="$(/usr/bin/awk '{print $22; exit}' "/proc/${expected_parent}/stat" \
        6<&- 7<&- 9<&-)" || return 1
    [ "$actual_start" = "$expected_start" ] || return 1
    while IFS=$' \t' read -r label real effective saved filesystem _; do
        case "$label" in
            Uid:) uid_line="${real}:${effective}:${saved}:${filesystem}" ;;
            Gid:) gid_line="${real}:${effective}:${saved}:${filesystem}" ;;
        esac
    done <"/proc/${expected_parent}/status"
    [ "$uid_line" = "${expected_uid}:${expected_uid}:${expected_uid}:${expected_uid}" ] &&
        [ "$gid_line" = "${expected_gid}:${expected_gid}:${expected_gid}:${expected_gid}" ] &&
        [ "$PPID" = "$expected_parent" ] || return 1
    [ "$(/usr/bin/awk '{print $22; exit}' "/proc/${expected_parent}/stat" 6<&- 7<&- 9<&-)" = \
        "$expected_start" ]
}

authenticate_launcher_parent() {
    local expected_parent="${ARCH_LINUX_OFFLINE_BROKER_PARENT:-}"
    local expected_launcher="${ARCH_LINUX_OFFLINE_LAUNCHER:-}"
    local expected_identity="${ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY:-}"
    local actual_path actual_identity

    authenticate_launcher_parent_liveness || return 1
    [[ "$expected_identity" =~ ^[0-9]+(:[0-9]+){6}$ ]] || return 1
    actual_path="$(/usr/bin/readlink -e -- "/proc/${expected_parent}/exe" 6<&- 7<&- 9<&-)" || return 1
    [ "$actual_path" = "$expected_launcher" ] || return 1
    actual_identity="$(/usr/bin/stat -Lc '%d:%i:%u:%g:%a:%h:%s' -- \
        "/proc/${expected_parent}/exe" 6<&- 7<&- 9<&-)" || return 1
    [ "$actual_identity" = "$expected_identity" ] && authenticate_launcher_parent_liveness
}

authenticate_launcher_parent || {
    printf 'ERROR: offline signing launcher-parent authentication failed\n' >&2
    exit 1
}
printf '%s\n' arch-linux-offline-parent-authenticated-v1 >&8 || {
    printf 'ERROR: offline signing launcher-parent acknowledgement failed\n' >&2
    exit 1
}
IFS= read -r broker_capability <&8 || {
    printf 'ERROR: offline signing broker capability is unavailable\n' >&2
    exit 1
}
broker_extra=''
if IFS= read -r -N 1 broker_extra <&8 || [ -n "$broker_extra" ]; then
    printf 'ERROR: offline signing broker capability has trailing data\n' >&2
    exit 1
fi
exec 8<&- 8>&-
[ "$broker_capability" = arch-linux-offline-broker-v1 ] || {
    printf 'ERROR: offline signing broker capability differs\n' >&2
    exit 1
}
unset broker_capability broker_extra

canonical_entry_path="$(/usr/bin/realpath -e -- "${BASH_SOURCE[0]}" 6<&- 7<&- 9<&-)" || {
    printf 'ERROR: cannot resolve sealed offline signing entrypoint\n' >&2
    exit 1
}
script_dir="${canonical_entry_path%/*}"
code_root="${script_dir%/*}"
[ "$code_root" = "${ARCH_LINUX_OFFLINE_CODE_ROOT:-}" ] &&
    [[ "${ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT:-}" =~ ^[a-f0-9]{40}$ ]] &&
    [[ "${ARCH_LINUX_OFFLINE_ACCEPTED_TREE:-}" =~ ^[a-f0-9]{40}$ ]] &&
    [[ "${ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256:-}" =~ ^[a-f0-9]{64}$ ]] &&
    [ "${ARCH_LINUX_OFFLINE_LAUNCHER:-}" = "${script_dir}/offline-signing-launcher" ] || {
    printf 'ERROR: sealed offline signing identity differs\n' >&2
    exit 1
}
/usr/bin/python3 -I "${script_dir}/verify-sealed-offline-code.py" \
    "$code_root" "$ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT" \
    "$ARCH_LINUX_OFFLINE_ACCEPTED_TREE" \
    "$ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256" 6<&- 7<&- 9<&- || {
    printf 'ERROR: sealed offline signing code verification failed\n' >&2
    exit 1
}
ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY="$(/usr/bin/stat -Lc '%d:%i' -- "$code_root" 6<&- 7<&- 9<&-)" || {
    printf 'ERROR: sealed offline signing root identity is unavailable\n' >&2
    exit 1
}
[[ "$ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY" =~ ^[0-9]+:[0-9]+$ ]] || {
    printf 'ERROR: sealed offline signing root identity is malformed\n' >&2
    exit 1
}
export ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY
readonly canonical_entry_path script_dir code_root

if [ -n "${CI+x}" ] || [ -n "${GITHUB_ACTIONS+x}" ] || [ -n "${GNUPGHOME+x}" ] ||
    [ -n "${OFFLINE_SIGN_PASSPHRASE_FILE+x}" ]; then
    printf 'ERROR: private-key signing is forbidden in CI and GitHub Actions\n' >&2
    exit 1
fi
for required in awk flock gpgconf gpg-connect-agent id install mount python3 realpath sleep stat unshare wc; do
    command -v "$required" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$required" >&2
        exit 1
    }
done

case "${1:-}" in
    snapshot) signer="${script_dir}/offline-sign-release.sh" ;;
    finalize) signer="${script_dir}/offline-finalize-release.sh" ;;
    *)
        printf 'Usage: %s {snapshot|finalize} SIGNER_ARGUMENTS...\n' "$0" >&2
        exit 2
        ;;
esac
shift
readonly signer

/usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" assert-bootstrap || {
    printf 'ERROR: captured private-object descriptor hygiene failed\n' >&2
    exit 1
}
gnupg_home_identity="$(/usr/bin/stat -Lc '%d:%i' -- /proc/self/fd/6 7<&- 9<&-)" || {
    printf 'ERROR: cannot inspect captured signing-home descriptor\n' >&2
    exit 1
}
[[ "$gnupg_home_identity" =~ ^[0-9]+:[0-9]+$ ]] &&
    [ "$gnupg_home_identity" = "${ARCH_LINUX_SIGNING_HOME_IDENTITY:-}" ] || {
    printf 'ERROR: captured signing-home descriptor identity differs\n' >&2
    exit 1
}

# Descriptor 6 is the stable object authority retained by the compiled launcher. Duplicate that
# exact open directory for the lock; never reopen a pathname for signing authority.
exec 9<&6 || {
    printf 'ERROR: cannot open the dedicated signing home for locking\n' >&2
    exit 1
}
locked_home_identity="$(/usr/bin/stat -Lc '%d:%i' -- /proc/self/fd/9 6<&- 7<&-)" || {
    printf 'ERROR: cannot inspect the locked signing home\n' >&2
    exit 1
}
[ "$locked_home_identity" = "$gnupg_home_identity" ] || {
    printf 'ERROR: GNUPGHOME identity changed while acquiring its lock\n' >&2
    exit 1
}
/usr/bin/flock --exclusive --nonblock 9 6<&- 7<&- || {
    printf 'ERROR: another offline signing operation is using this signing home\n' >&2
    exit 1
}
export ARCH_LINUX_SIGNING_HOME_IDENTITY="$gnupg_home_identity"
/usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" assert-sealed || {
    printf 'ERROR: inherited descriptor hygiene failed before offline signing\n' >&2
    exit 1
}

unset GPG_AGENT_INFO

# No GnuPG process may touch the private home before its retained descriptor is materialized in the
# network-disabled mount namespace. A dedicated offline signing account therefore starts with no
# same-UID gpg-agent at all; do not connect to or kill one through a mutable pathname.
signing_uid="$(/usr/bin/id -u 6<&- 7<&- 9<&-)"
signing_gid="$(/usr/bin/id -g 6<&- 7<&- 9<&-)"
[[ "$signing_uid" =~ ^[1-9][0-9]*$ ]] && [[ "$signing_gid" =~ ^[1-9][0-9]*$ ]] || {
    printf 'ERROR: dedicated signing account identity is malformed\n' >&2
    exit 1
}
export ARCH_LINUX_SIGNING_HOST_UID="$signing_uid"
export ARCH_LINUX_SIGNING_HOST_GID="$signing_gid"
for process_status in /proc/[1-9]*/status; do
    [ -r "$process_status" ] || continue
    process_dir="${process_status%/status}"
    [ -r "${process_dir}/comm" ] || continue
    IFS= read -r process_comm <"${process_dir}/comm" || continue
    [ "$process_comm" = gpg-agent ] || continue
    process_uid="$(/usr/bin/awk '/^Uid:/ { print $2; exit }' "$process_status" 6<&- 7<&- 9<&-)" || continue
    [ "$process_uid" != "$signing_uid" ] || {
        printf 'ERROR: offline signing account already has a live gpg-agent\n' >&2
        exit 1
    }
done
[ "$(/usr/bin/stat -Lc '%d:%i' -- /proc/self/fd/6 7<&- 9<&-)" = "$gnupg_home_identity" ] || {
    printf 'ERROR: signing-home object changed before namespace entry\n' >&2
    exit 1
}
printf 'Host signing-agent absence: verified\n'

# Mapping the invoking user to namespace-root grants only namespaced privileges.  It is required to
# inspect the nondumpable gpg-agent's namespace descriptors; no host-root authority is acquired.
# The inner wrapper proves it entered new user/network namespaces, then proves that the agent and
# signer share those exact namespaces and see only loopback before private-key use.
export ARCH_LINUX_CALLER_NETNS_INODE
ARCH_LINUX_CALLER_NETNS_INODE="$(/usr/bin/stat -Lc '%i' -- /proc/self/ns/net 6<&- 7<&- 9<&-)"
export ARCH_LINUX_CALLER_USERNS_INODE
ARCH_LINUX_CALLER_USERNS_INODE="$(/usr/bin/stat -Lc '%i' -- /proc/self/ns/user 6<&- 7<&- 9<&-)"
export ARCH_LINUX_CALLER_PIDNS_INODE
ARCH_LINUX_CALLER_PIDNS_INODE="$(/usr/bin/stat -Lc '%i' -- /proc/self/ns/pid 6<&- 7<&- 9<&-)"
export ARCH_LINUX_CALLER_MNTNS_INODE
ARCH_LINUX_CALLER_MNTNS_INODE="$(/usr/bin/stat -Lc '%i' -- /proc/self/ns/mnt 6<&- 7<&- 9<&-)"
[[ "$ARCH_LINUX_CALLER_NETNS_INODE" =~ ^[0-9]+$ ]] &&
    [[ "$ARCH_LINUX_CALLER_USERNS_INODE" =~ ^[0-9]+$ ]] &&
    [[ "$ARCH_LINUX_CALLER_PIDNS_INODE" =~ ^[0-9]+$ ]] &&
    [[ "$ARCH_LINUX_CALLER_MNTNS_INODE" =~ ^[0-9]+$ ]] || {
    printf 'ERROR: caller namespace identity readback failed\n' >&2
    exit 1
}
authenticate_launcher_parent_liveness || {
    printf 'ERROR: offline signing launcher parent changed before namespace entry\n' >&2
    exit 1
}
exec /usr/bin/python3 -I "${script_dir}/offline-signing-fd-guard.py" exec-clean \
    /usr/bin/unshare --user --map-root-user --net --pid --mount-proc --propagation private \
    --kill-child --fork -- \
    /usr/bin/bash -p "${script_dir}/offline-signing-namespace.sh" "${signer}" "$@"
