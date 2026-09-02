#!/usr/bin/bash -p
# shellcheck disable=SC2016

set +x
set -e
set -u
set -o pipefail
IFS=$' \t\n'
umask 077

case "$-" in
    *p*) ;;
    *)
        printf 'ERROR: offline namespace requires Bash privileged mode\n' >&2
        exit 1
        ;;
esac

namespace_entry="$(/usr/bin/realpath -e -- "${BASH_SOURCE[0]}" 6<&- 7<&- 9<&-)"
script_dir="${namespace_entry%/*}"
readonly script_dir
fd_guard="${script_dir}/offline-signing-fd-guard.py"
readonly fd_guard

public_exec() {
    /usr/bin/python3 -I "$fd_guard" exec-public "$@" 6<&- 7<&- 9<&-
}

[ "$(public_exec /usr/bin/stat -Lc '%d:%i' -- "${ARCH_LINUX_OFFLINE_CODE_ROOT:-}")" = \
    "${ARCH_LINUX_OFFLINE_CODE_ROOT_IDENTITY:-}" ] || {
    printf 'ERROR: sealed offline code identity changed across the namespace boundary\n' >&2
    exit 1
}
/usr/bin/python3 -I "$fd_guard" assert-sealed || {
    printf 'ERROR: inherited descriptor hygiene failed inside offline signing namespace\n' >&2
    exit 1
}
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

[ "$#" -ge 1 ] || die 'offline signer command is missing'
signer="$1"
shift
readonly signer
[ "$signer" = "${script_dir}/offline-sign-release.sh" ] ||
    [ "$signer" = "${script_dir}/offline-finalize-release.sh" ] ||
    die 'offline signer is outside the sealed exact allowlist'

[ -z "${GITHUB_ACTIONS+x}" ] && [ -z "${CI+x}" ] && [ -z "${GNUPGHOME+x}" ] &&
    [ -z "${OFFLINE_SIGN_PASSPHRASE_FILE+x}" ] &&
    [ -z "${ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT+x}" ] &&
    [ -z "${ARCH_LINUX_OFFLINE_METADATA_MODE+x}" ] ||
    die 'private-key signing is forbidden in CI and GitHub Actions'

for required in awk findmnt gpgconf gpg-connect-agent id install mount realpath sleep stat wc; do
    command -v "$required" >/dev/null 2>&1 || die "required offline command is missing: ${required}"
done
[ "$(public_exec /usr/bin/id -u)" = 0 ] || die 'offline signer is not namespace-root'
[[ "${ARCH_LINUX_CALLER_NETNS_INODE:-}" =~ ^[0-9]+$ ]] &&
    [[ "${ARCH_LINUX_CALLER_USERNS_INODE:-}" =~ ^[0-9]+$ ]] &&
    [[ "${ARCH_LINUX_CALLER_PIDNS_INODE:-}" =~ ^[0-9]+$ ]] &&
    [[ "${ARCH_LINUX_CALLER_MNTNS_INODE:-}" =~ ^[0-9]+$ ]] ||
    die 'caller namespace identity is missing'
current_net_inode="$(public_exec /usr/bin/stat -Lc '%i' -- /proc/self/ns/net)" || die 'cannot inspect signer network namespace'
current_user_inode="$(public_exec /usr/bin/stat -Lc '%i' -- /proc/self/ns/user)" || die 'cannot inspect signer user namespace'
current_pid_inode="$(public_exec /usr/bin/stat -Lc '%i' -- /proc/self/ns/pid)" || die 'cannot inspect signer PID namespace'
current_mnt_inode="$(public_exec /usr/bin/stat -Lc '%i' -- /proc/self/ns/mnt)" || die 'cannot inspect signer mount namespace'
[ "$current_net_inode" != "$ARCH_LINUX_CALLER_NETNS_INODE" ] &&
    [ "$current_user_inode" != "$ARCH_LINUX_CALLER_USERNS_INODE" ] &&
    [ "$current_pid_inode" != "$ARCH_LINUX_CALLER_PIDNS_INODE" ] &&
    [ "$current_mnt_inode" != "$ARCH_LINUX_CALLER_MNTNS_INODE" ] ||
    die 'offline signer did not enter fresh user, network, PID and mount namespaces'
namespace_pid="${BASHPID}"
[[ "$namespace_pid" =~ ^[0-9]+$ ]] || die 'cannot inspect signer namespace PID'
[ "$namespace_pid" = 1 ] || die 'offline signer is not PID namespace init'
[ "$(ulimit -c)" = 0 ] || die 'offline signer core-dump limit is not zero'
repository_assert_loopback_only_network 6<&- 7<&- 9<&-
[[ "${ARCH_LINUX_SIGNING_HOST_UID:-}" =~ ^[1-9][0-9]*$ ]] &&
    [[ "${ARCH_LINUX_SIGNING_HOST_GID:-}" =~ ^[1-9][0-9]*$ ]] ||
    die 'dedicated signing host identity is malformed'
[ "$(public_exec /usr/bin/awk '{$1=$1; print}' /proc/self/uid_map)" = \
    "0 ${ARCH_LINUX_SIGNING_HOST_UID} 1" ] &&
    [ "$(public_exec /usr/bin/awk '{$1=$1; print}' /proc/self/gid_map)" = \
    "0 ${ARCH_LINUX_SIGNING_HOST_GID} 1" ] ||
    die 'dedicated signing user/group mapping differs'
ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT=sealed-root-v1
export ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT
readonly ARCH_LINUX_OFFLINE_NAMESPACE_RECEIPT

# Keep every agent socket and the fixed accepted-object bind targets on a private tmpfs. The
# launcher-retained directory FD and sealed passphrase memfd are the only source authority; GnuPG
# never reopens the caller-provided private pathnames.
[ -d /run/user ] && [ ! -L /run/user ] && [ "$(public_exec /usr/bin/realpath -e -- /run/user)" = /run/user ] ||
    die 'private agent runtime mountpoint is unavailable'
public_exec /usr/bin/mount -t tmpfs -o mode=0755,nosuid,nodev,noexec,size=4m tmpfs /run/user ||
    die 'cannot create the private agent runtime filesystem'
[ "$(public_exec /usr/bin/stat -f -c '%T' -- /run/user)" = tmpfs ] ||
    die 'private agent runtime is not tmpfs'
public_exec /usr/bin/install -d -m0700 -- /run/user/0 || die 'cannot create the private agent runtime directory'
[ "$(public_exec /usr/bin/stat -c '%u:%a' -- /run/user/0)" = '0:700' ] ||
    die 'private agent runtime directory metadata is invalid'
private_object_root=/run/user/0/arch-linux-offline
GNUPGHOME="${private_object_root}/gnupg"
OFFLINE_SIGN_PASSPHRASE_FILE=/proc/self/fd/7
public_exec /usr/bin/install -d -m0700 -- "$private_object_root" "$GNUPGHOME" ||
    die 'cannot create private accepted-object mountpoints'
/usr/bin/mount --bind /proc/self/fd/6 "$GNUPGHOME" 7<&- 9<&- ||
    die 'cannot bind the accepted signing-home object'
public_exec /usr/bin/mount -o remount,bind,rw,nosuid,nodev,noexec "$GNUPGHOME" ||
    die 'cannot constrain the accepted signing-home bind mount'
[ "$(public_exec /usr/bin/stat -Lc '%d:%i' -- "$GNUPGHOME")" = \
    "${ARCH_LINUX_SIGNING_HOME_IDENTITY:-}" ] &&
    [ "$(public_exec /usr/bin/stat -c '%u:%a' -- "$GNUPGHOME")" = '0:700' ] &&
    [ "$(public_exec /usr/bin/findmnt -n -o TARGET --target "$GNUPGHOME")" = "$GNUPGHOME" ] ||
    die 'fixed signing-home mount differs from the accepted directory object'
export GNUPGHOME OFFLINE_SIGN_PASSPHRASE_FILE
/usr/bin/python3 -I "$fd_guard" assert-runtime ||
    die 'private-object descriptor authority changed after fixed mount creation'
exec 6<&-
/usr/bin/python3 -I "$fd_guard" assert-supervisor ||
    die 'private-object supervisor authority changed after home materialization'

agent_socket_dir="$(public_exec /usr/bin/gpgconf --homedir "$GNUPGHOME" --list-dirs socketdir)" ||
    die 'cannot resolve the private agent socket directory'
[[ "$agent_socket_dir" =~ ^/run/user/0/gnupg/d\.[a-z0-9]+$ ]] ||
    die 'agent socket directory is outside the private runtime filesystem'
printf 'Offline signing crash containment: verified\n'

unset GPG_AGENT_INFO

agent_pid=''
agent_start_time=''
agent_uid=''
agent_was_launched=false

agent_identity_matches() {
    local comm actual_start_time actual_uid

    [[ "$agent_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ -r "/proc/${agent_pid}/comm" ] && [ -r "/proc/${agent_pid}/stat" ] &&
        [ -r "/proc/${agent_pid}/status" ] || return 1
    IFS= read -r comm <"/proc/${agent_pid}/comm" || return 1
    [ "$comm" = gpg-agent ] || return 1
    actual_start_time="$(public_exec /usr/bin/awk '{ print $22; exit }' "/proc/${agent_pid}/stat" \
        2>/dev/null)" || return 1
    actual_uid="$(public_exec /usr/bin/awk '/^Uid:/ { print $2; exit }' "/proc/${agent_pid}/status" \
        2>/dev/null)" || return 1
    [ "$actual_start_time" = "$agent_start_time" ] && [ "$actual_uid" = "$agent_uid" ]
}

wait_for_agent_exit() {
    local attempt=0

    while [ "$attempt" -lt 50 ]; do
        agent_identity_matches || return 0
        public_exec /usr/bin/sleep 0.1
        attempt=$((attempt + 1))
    done
    return 1
}

assert_agent_sockets_absent() {
    local socket_kind socket_path

    for socket_kind in agent-socket agent-extra-socket agent-browser-socket agent-ssh-socket; do
        socket_path="$(public_exec /usr/bin/gpgconf --homedir "$GNUPGHOME" --list-dirs "$socket_kind")" || return 1
        case "$socket_kind:$socket_path" in
        "agent-socket:${agent_socket_dir}/S.gpg-agent" | \
            "agent-extra-socket:${agent_socket_dir}/S.gpg-agent.extra" | \
            "agent-browser-socket:${agent_socket_dir}/S.gpg-agent.browser" | \
            "agent-ssh-socket:${agent_socket_dir}/S.gpg-agent.ssh") ;;
        *) return 1 ;;
        esac
        [ ! -e "$socket_path" ] && [ ! -L "$socket_path" ] || return 1
    done
}

assert_agent_private_objects_absent() {
    local descriptor_path identity
    local passphrase_object="${ARCH_LINUX_PASSPHRASE_IDENTITY%:*}"

    [[ "$passphrase_object" =~ ^[0-9]+:[0-9]+$ ]] || return 1
    for descriptor_path in "/proc/${agent_pid}/fd/"*; do
        [ -e "$descriptor_path" ] || continue
        identity="$(public_exec /usr/bin/stat -Lc '%d:%i' -- "$descriptor_path")" || return 1
        [ "$identity" != "${ARCH_LINUX_SIGNING_HOME_IDENTITY}" ] || return 1
        [ "$identity" != "$passphrase_object" ] || return 1
    done
}

cleanup_agent() {
    local cleanup_status=0

    public_exec /usr/bin/gpgconf --homedir "$GNUPGHOME" --kill gpg-agent >/dev/null 2>&1 || true
    if ! wait_for_agent_exit; then
        if agent_identity_matches; then
            kill -TERM -- "$agent_pid" 2>/dev/null || true
        fi
        if ! wait_for_agent_exit; then
            if agent_identity_matches; then
                kill -KILL -- "$agent_pid" 2>/dev/null || true
            fi
            wait_for_agent_exit || cleanup_status=1
        fi
    fi
    assert_agent_sockets_absent || cleanup_status=1
    return "$cleanup_status"
}

finish() {
    local signer_status="$1" cleanup_status=0
    trap - EXIT INT TERM HUP
    cleanup_agent || cleanup_status=$?
    if [ "$cleanup_status" -ne 0 ]; then
        printf 'ERROR: offline signing agent did not terminate cleanly\n' >&2
        exit 1
    fi
    if [ "$agent_was_launched" = true ]; then
        printf 'Offline signing agent termination: verified\n'
    fi
    exit "$signer_status"
}
trap 'finish "$?"' EXIT
trap 'exit 130' INT TERM HUP

# The outer wrapper killed the home-specific agent and verified removal of all four sockets.  Refuse
# any socket that appeared between that check and this new namespace before launching a fresh agent.
assert_agent_sockets_absent || die 'a signing-agent socket survived into the offline namespace'
public_exec /usr/bin/gpgconf --homedir "$GNUPGHOME" --launch gpg-agent >/dev/null 2>&1 ||
    die 'could not launch the dedicated offline signing agent'
agent_info="$(
    public_exec /usr/bin/gpg-connect-agent --homedir "$GNUPGHOME" 'GETINFO pid' /bye 2>/dev/null
)" || die 'could not query the dedicated offline signing agent'
agent_pid="$(public_exec /usr/bin/awk '$1 == "D" && $2 ~ /^[1-9][0-9]*$/ { print $2 }' <<<"$agent_info")"
[[ "$agent_pid" =~ ^[1-9][0-9]*$ ]] ||
    die 'offline signing agent returned an invalid process identity'
[ -r "/proc/${agent_pid}/comm" ] && [ "$(<"/proc/${agent_pid}/comm")" = 'gpg-agent' ] ||
    die 'offline signing agent process identity does not resolve to gpg-agent'
current_uid="$(public_exec /usr/bin/id -u)"
agent_uid="$(public_exec /usr/bin/awk '/^Uid:/ { print $2; exit }' "/proc/${agent_pid}/status")" ||
    die 'cannot inspect offline signing agent ownership'
[ "$agent_uid" = "$current_uid" ] || die 'offline signing agent is owned by another user'
agent_start_time="$(public_exec /usr/bin/awk '{ print $22; exit }' "/proc/${agent_pid}/stat")" ||
    die 'cannot inspect offline signing agent start identity'
[[ "$agent_start_time" =~ ^[1-9][0-9]*$ ]] || die 'offline signing agent start identity is invalid'
agent_identity_matches || die 'offline signing agent process identity changed unexpectedly'
agent_net_inode="$(public_exec /usr/bin/stat -Lc '%i' -- "/proc/${agent_pid}/ns/net")" ||
    die 'cannot inspect agent network namespace'
agent_user_inode="$(public_exec /usr/bin/stat -Lc '%i' -- "/proc/${agent_pid}/ns/user")" ||
    die 'cannot inspect agent user namespace'
agent_pid_inode="$(public_exec /usr/bin/stat -Lc '%i' -- "/proc/${agent_pid}/ns/pid")" ||
    die 'cannot inspect agent PID namespace'
agent_mnt_inode="$(public_exec /usr/bin/stat -Lc '%i' -- "/proc/${agent_pid}/ns/mnt")" ||
    die 'cannot inspect agent mount namespace'
[ "$agent_net_inode" = "$current_net_inode" ] ||
    die 'signing agent is outside the network-disabled namespace'
[ "$agent_user_inode" = "$current_user_inode" ] ||
    die 'signing agent is outside the dedicated user namespace'
[ "$agent_pid_inode" = "$current_pid_inode" ] ||
    die 'signing agent is outside the dedicated PID namespace'
[ "$agent_mnt_inode" = "$current_mnt_inode" ] ||
    die 'signing agent is outside the dedicated mount namespace'
repository_assert_loopback_only_network "/proc/${agent_pid}/net/dev" 7<&- 9<&-
for socket_kind in agent-socket agent-extra-socket agent-browser-socket agent-ssh-socket; do
    socket_path="$(public_exec /usr/bin/gpgconf --homedir "$GNUPGHOME" --list-dirs "$socket_kind")" ||
        die 'cannot inspect an offline signing-agent socket'
    [ -S "$socket_path" ] && [ -O "$socket_path" ] ||
        die 'offline signing-agent socket is missing or owned by another user'
done
assert_agent_private_objects_absent ||
    die 'offline signing agent inherited a private retained object'
agent_was_launched=true
printf 'Offline signing agent containment: verified\n'

/usr/bin/python3 -I "$fd_guard" assert-supervisor ||
    die 'private-object descriptors changed immediately before signer entry'
/usr/bin/bash -p "$signer" "$@" 6<&- 9<&-
