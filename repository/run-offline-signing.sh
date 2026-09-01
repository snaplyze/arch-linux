#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly disposable_marker_name='.arch-linux-disposable-signing-home'
readonly disposable_marker_value='arch-linux-offline-signing-disposable-v1'
disposable_home=''
disposable_identity=''
signing_uid="$(id -u)"

usage() {
    cat >&2 <<USAGE
Usage: $0 --unsigned DIR --installer FILE --output DIR --release-version X.Y.Z \
  --build-metadata-sha256 SHA --unsigned-manifest-sha256 SHA

GNUPGHOME must be a caller-prepared /tmp/arch-linux-signing-home.XXXXXXXX
directory owned by the caller, mode 0700, containing a mode-0600 regular marker:
  $disposable_marker_name
whose exact content is:
  $disposable_marker_value
The wrapper never copies or exports private key material. It kills agents bound
to this disposable home and deletes the marked home on success or failure.
USAGE
}

validate_disposable_home() {
    local requested="$1" canonical marker identity
    [ -d "$requested" ] && [ ! -L "$requested" ] || return 1
    canonical="$(realpath -e -- "$requested")" || return 1
    [ "$requested" = "$canonical" ] || return 1
    [ "$(dirname -- "$canonical")" = /tmp ] || return 1
    [[ "${canonical##*/}" =~ ^arch-linux-signing-home\.[A-Za-z0-9]{8,32}$ ]] || return 1
    [ "$(stat -Lc '%u:%a' -- "$canonical")" = "$signing_uid:700" ] || return 1
    identity="$(stat -Lc '%d:%i' -- "$canonical")" || return 1
    [ -z "$disposable_identity" ] || [ "$identity" = "$disposable_identity" ] || return 1
    marker="$canonical/$disposable_marker_name"
    [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
    [ "$(stat -Lc '%u:%a:%h' -- "$marker")" = "$signing_uid:600:1" ] || return 1
    cmp --silent -- "$marker" <(printf '%s\n' "$disposable_marker_value") || return 1
    printf '%s\n' "$canonical"
}

assert_no_signing_agent_sockets() {
    local socket_name socket_path
    for socket_name in agent-socket agent-extra-socket agent-browser-socket agent-ssh-socket; do
        socket_path="$(gpgconf --homedir "$disposable_home" --list-dirs "$socket_name")" || return 1
        [ ! -S "$socket_path" ] || return 1
    done
    [ -z "$(find "$disposable_home" -maxdepth 1 -type s -print -quit)" ] || return 1
}

remove_stale_home_sockets() {
    local socket agent_pid
    agent_pid="$(
        gpg-connect-agent --homedir "$disposable_home" --no-autostart \
            'GETINFO pid' /bye 2>/dev/null | awk '$1 == "D" { print $2; exit }'
    )"
    [ -z "$agent_pid" ] || return 1
    for socket in S.gpg-agent S.gpg-agent.extra S.gpg-agent.browser S.gpg-agent.ssh; do
        if [ -L "$disposable_home/$socket" ]; then return 1; fi
        if [ -e "$disposable_home/$socket" ]; then
            [ -S "$disposable_home/$socket" ] || return 1
            [ "$(stat -Lc '%u:%h' -- "$disposable_home/$socket")" = "$signing_uid:1" ] || return 1
            rm -f -- "$disposable_home/$socket" || return 1
        fi
    done
}

stop_signing_agents() {
    gpgconf --homedir "$disposable_home" --kill all >/dev/null 2>&1 || return 1
    remove_stale_home_sockets || return 1
    assert_no_signing_agent_sockets
}

cleanup_disposable_home() {
    [ -n "$disposable_home" ] || return 0
    stop_signing_agents || {
        printf 'Refusing to delete disposable GNUPGHOME while an associated agent or socket remains.\n' >&2
        return 1
    }
    validate_disposable_home "$disposable_home" >/dev/null || {
        printf 'Refusing to delete a changed or unmarked disposable GNUPGHOME.\n' >&2
        return 1
    }
    rm -rf -- "$disposable_home" || return 1
    [ ! -e "$disposable_home" ] && [ ! -L "$disposable_home" ] || return 1
    disposable_home=''
}

cleanup_on_exit() {
    local status="$?"
    trap - EXIT
    if ! cleanup_disposable_home; then status=1; fi
    exit "$status"
}

[ -n "${GNUPGHOME:-}" ] || { printf 'GNUPGHOME is required.\n' >&2; exit 1; }
for command_name in awk cmp dirname find gpg-connect-agent gpgconf id realpath rm stat unshare; do
    command -v -- "$command_name" >/dev/null 2>&1 || {
        printf 'Required signing command is absent: %s\n' "$command_name" >&2
        exit 1
    }
done
disposable_home="$(validate_disposable_home "$GNUPGHOME")" || {
    disposable_home=''
    printf 'GNUPGHOME is not the explicitly marked canonical disposable signing home.\n' >&2
    exit 1
}
disposable_identity="$(stat -Lc '%d:%i' -- "$disposable_home")"
trap cleanup_on_exit EXIT
[ "${CI:-false}" != true ] && [ "${GITHUB_ACTIONS:-false}" != true ] || {
    printf 'Offline signing is forbidden in CI.\n' >&2
    exit 1
}

arguments=("$@")
build_metadata_hash=''
unsigned_manifest_hash=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-metadata-sha256)
            [ "$#" -ge 2 ] && [ -z "$build_metadata_hash" ] || { usage; exit 2; }
            build_metadata_hash="$2"
            shift 2
            ;;
        --unsigned-manifest-sha256)
            [ "$#" -ge 2 ] && [ -z "$unsigned_manifest_hash" ] || { usage; exit 2; }
            unsigned_manifest_hash="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done
[[ "$build_metadata_hash" =~ ^[0-9a-f]{64}$ ]] &&
    [[ "$unsigned_manifest_hash" =~ ^[0-9a-f]{64}$ ]] || {
    usage
    exit 2
}
stop_signing_agents || {
    printf 'Disposable GNUPGHOME has a pre-existing agent or socket that cannot be stopped.\n' >&2
    exit 1
}
term="${TERM:-dumb}"
gpg_tty="${GPG_TTY:-}"

# The PID namespace guarantees that an agent started for this invocation dies
# with namespace PID 1. Networking exposes only loopback. Pinentry remains the
# only passphrase path; stdin is not repurposed for secret material.
unshare --user --map-root-user --net --pid --fork --kill-child=SIGKILL --mount-proc -- \
    /usr/bin/env -i HOME="$disposable_home" LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
    GNUPGHOME="$disposable_home" TERM="$term" GPG_TTY="$gpg_tty" \
    bash "${script_dir}/offline-sign-release.sh" "${arguments[@]}"
