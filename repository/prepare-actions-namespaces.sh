#!/usr/bin/env bash
set +x
set -euo pipefail

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

# This host preparation must finish before the isolated signing step receives secrets.
[[ ! -v ARCH_LINUX_SIGNING_KEY && ! -v ARCH_LINUX_SIGNING_PASSPHRASE ]] ||
    fail 'namespace preparation refuses signing secret environment'
[[ "$UID" = 0 && "$EUID" = 0 && "${CI:-}" = true && "${GITHUB_ACTIONS:-}" = true &&
    "${RUNNER_ENVIRONMENT:-}" = github-hosted && "${GITHUB_REPOSITORY:-}" = snaplyze/arch-linux &&
    "${GITHUB_WORKFLOW:-}" = Release && "${GITHUB_REF:-}" = refs/heads/main &&
    ( "${GITHUB_JOB:-}" = snapshot || "${GITHUB_JOB:-}" = finalize ) &&
    -f /.dockerenv && ! -L /.dockerenv ]] ||
    fail 'namespace preparation requires the hosted Release signing job'
export PATH=/usr/bin:/usr/sbin
[[ "$(awk '{$1=$1; print}' /proc/self/uid_map)" = '0 0 4294967295' ]] ||
    fail 'namespace preparation requires initial host root'

probe() {
    /usr/bin/runuser -u nobody -- /usr/bin/env -i \
        HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
        /usr/bin/unshare --user --map-root-user --net --pid --mount --mount-proc \
        --fork --kill-child=SIGKILL /usr/bin/true
}

if probe; then
    printf 'ACTIONS_NAMESPACES_RESULT state=unchanged\n'
    exit 0
fi

# Ubuntu's host AppArmor policy can deny capabilities inside unprivileged user namespaces.
# Change only its recognized transient switch, only on this disposable signing runner.
readonly policy=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
[[ -f "$policy" && ! -L "$policy" && "$(<"$policy")" = 1 ]] ||
    fail 'namespace probe failed without the recognized enabled AppArmor restriction'

rollback_policy() {
    local status=$? current
    trap - EXIT
    trap '' HUP INT TERM
    if [[ -f "$policy" && ! -L "$policy" ]] && current="$(<"$policy")"; then
        if [[ "$current" = 0 ]]; then
            if ! printf '1\n' >"$policy" || [[ "$(<"$policy")" != 1 ]]; then
                printf 'ERROR: AppArmor namespace policy rollback failed\n' >&2
            fi
        elif [[ "$current" != 1 ]]; then
            printf 'ERROR: AppArmor namespace rollback refused unexpected policy state\n' >&2
        fi
    else
        printf 'ERROR: AppArmor namespace policy rollback cannot read its original path\n' >&2
    fi
    exit "$status"
}

trap rollback_policy EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'Namespace probe failed; testing the transient hosted AppArmor adjustment\n'
printf '0\n' >"$policy"
[[ "$(<"$policy")" = 0 ]] || fail 'AppArmor namespace policy readback differs'
probe || fail 'namespace probe still fails after the hosted AppArmor adjustment'
trap - EXIT HUP INT TERM
printf 'ACTIONS_NAMESPACES_RESULT state=apparmor-adjusted\n'
