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
    "${RUNNER_ENVIRONMENT:-}" = self-hosted && "${GITHUB_REPOSITORY:-}" = snaplyze/arch-linux &&
    "${GITHUB_WORKFLOW:-}" = Release && "${GITHUB_REF:-}" = refs/heads/main &&
    ( "${GITHUB_JOB:-}" = snapshot || "${GITHUB_JOB:-}" = finalize ) &&
    -f /.dockerenv && ! -L /.dockerenv ]] ||
    fail 'namespace preparation requires the self-hosted Release signing job'
export PATH=/usr/bin:/usr/sbin
[[ "$(awk '{$1=$1; print}' /proc/self/uid_map)" = '0 0 4294967295' ]] ||
    fail 'namespace preparation requires initial host root'

probe() {
    /usr/bin/runuser -u nobody -- /usr/bin/env -i \
        HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
        /usr/bin/unshare --user --map-root-user --net --pid --mount --mount-proc \
        --fork --kill-child=SIGKILL /usr/bin/true
}

# The shared runner administrator provisions the arch-linux-ci AppArmor profile.
# Never change a host-global sysctl from a job on this persistent shared VM.
probe || fail 'namespace probe failed: configure the arch-linux-ci Docker AppArmor profile and seccomp options on the self-hosted runner; host-global sysctl changes are forbidden'
printf 'ACTIONS_NAMESPACES_RESULT state=unchanged\n'
