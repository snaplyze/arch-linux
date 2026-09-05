#!/usr/bin/env bash
# Root-only synthetic integration for the frozen offline-signing boundary. No production private
# material is read: the fixture creates and destroys one passphrase-protected signing-subkey home.
# shellcheck disable=SC2016

set +x
set -euo pipefail
umask 077
ulimit -c 0

fail() {
    printf 'publication root check failed: %s\n' "$*" >&2
    exit 1
}

assert_real_failure() {
    local status="$1" label="$2"
    [ "$status" -ne 0 ] || fail "negative fixture unexpectedly succeeded: ${label}"
    case "$status" in
        126|127) fail "negative fixture did not execute its subject: ${label} (status ${status})" ;;
    esac
}

[ "$#" -eq 0 ] || fail 'arguments are forbidden'
[ "${BASH_SOURCE[0]}" = "$0" ] || fail 'sourced or evaluated entry is forbidden'
[ "${UID}" -eq 0 ] && [ "${EUID}" -eq 0 ] &&
    [ "$(/usr/bin/id -ru)" -eq 0 ] && [ "$(/usr/bin/id -u)" -eq 0 ] ||
    fail 'initial real and effective host root are required'
[ "$(/usr/bin/awk '{$1=$1; print}' /proc/self/uid_map)" = '0 0 4294967295' ] ||
    fail 'initial host user namespace is required'
[ "${HOME:-}" = /root ] && [ "${LANG:-}" = C ] && [ "${LC_ALL:-}" = C ] &&
    [ "${PATH:-}" = /usr/bin:/usr/sbin ] && [ "${SHLVL:-}" = 1 ] ||
    fail 'exact isolated root environment is required'
exported_environment="$(compgen -e | /usr/bin/sort)"
[ "$exported_environment" = $'HOME\nLANG\nLC_ALL\nPATH\nPWD\nSHLVL' ] ||
    fail 'unexpected exported environment authority'
[ "$(/usr/bin/readlink -e -- /proc/$$/fd/0)" = /dev/null ] ||
    fail 'stdin is not the exact /dev/null boundary'

entry_input="${BASH_SOURCE[0]}"
entry_path="$(/usr/bin/readlink -e -- "$entry_input")" || fail 'entrypoint cannot be resolved'
[ -n "$entry_path" ] && [ -e /proc/$$/fd/255 ] && [ "$entry_path" -ef /proc/$$/fd/255 ] ||
    fail 'Bash is not executing the accepted entry inode on descriptor 255'
case "$entry_path" in
    */tests/publication-root-check.sh) ;;
    *) fail 'entrypoint is outside its exact repository location' ;;
esac
repo_root="${entry_path%/tests/publication-root-check.sh}"
[ "$entry_path" = "$repo_root/tests/publication-root-check.sh" ] ||
    fail 'entrypoint suffix is ambiguous'
[ "$(/usr/bin/pwd -P)" = "$repo_root" ] && [ "${PWD}" = "$repo_root" ] ||
    fail 'publication command was not started at the canonical repository root'
readonly entry_path repo_root

for command_name in awk bash bsdtar cc chmod chown cmp find getent git gpg gpgconf gpgv \
    grep id install kill mkfifo mktemp mount python3 readelf readlink realpath repo-add setpriv \
    sha256sum sleep sort stat tar unlink unshare wc zstd; do
    command -v -- "$command_name" >/dev/null 2>&1 ||
        fail "required release-host command is absent: ${command_name}"
done

assert_root_directory_chain() {
    local path="$1" uid gid mode
    while :; do
        [ -d "$path" ] && [ ! -L "$path" ] || fail "unsafe source ancestor: ${path}"
        IFS=: read -r uid gid mode < <(/usr/bin/stat -c '%u:%g:%a' -- "$path")
        [ "${uid}:${gid}" = 0:0 ] || fail "source ancestor is not root-owned: ${path}"
        (( (8#${mode} & 022) == 0 )) || fail "source ancestor is writable by another identity: ${path}"
        [ "$path" = / ] && break
        path="${path%/*}"
        [ -n "$path" ] || path=/
    done
}

assert_root_directory_chain "$repo_root"
[ "$(/usr/bin/stat -Lc '%u:%g:%a:%h:%F' -- "$entry_path")" = \
    '0:0:755:1:regular file' ] || fail 'publication entrypoint metadata differs'
/usr/bin/python3 -I -B - "$repo_root" <<'PY'
import os
from pathlib import Path
import stat
import subprocess
import sys

root = Path(sys.argv[1])
tracked = subprocess.check_output(
    ["/usr/bin/git", "-c", f"safe.directory={root}", "-C", str(root), "ls-files", "-z"]
).split(b"\0")
for encoded in tracked:
    if not encoded:
        continue
    path = root / os.fsdecode(encoded)
    metadata = path.lstat()
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) not in {0o644, 0o755}
        or metadata.st_nlink != 1
        or os.listxattr(path, follow_symlinks=False)
    ):
        raise SystemExit(f"unsafe tracked source metadata: {path.relative_to(root)}")
for directory, names, _ in os.walk(root, topdown=True, followlinks=False):
    names[:] = [name for name in names if name != ".git"]
    path = Path(directory)
    metadata = path.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) & 0o022
        or os.listxattr(path, follow_symlinks=False)
    ):
        raise SystemExit(f"unsafe accepted source directory: {path}")
PY

[ -z "$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ] &&
    [ -z "$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" clean -ndX)" ] ||
    fail 'accepted source is not an exact clean closure'
commit="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" rev-parse --verify 'HEAD^{commit}')"
tree="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" rev-parse --verify 'HEAD^{tree}')"
[[ "$commit" =~ ^[a-f0-9]{40}$ ]] && [[ "$tree" =~ ^[a-f0-9]{40}$ ]] ||
    fail 'accepted Git identity is malformed'

canonical_source_sha256() {
    local root="$1" file mode
    /usr/bin/git -c safe.directory="$root" -C "$root" ls-files -z |
        while IFS= read -r -d '' file; do
            mode=0644
            [ -x "$root/$file" ] && mode=0755
            printf '%s %s *%s\n' "$mode" \
                "$(/usr/bin/sha256sum --binary -- "$root/$file" | /usr/bin/awk '{print $1}')" "$file"
        done | LC_ALL=C /usr/bin/sort | /usr/bin/sha256sum | /usr/bin/awk '{print $1}'
}
source_tree_sha256="$(canonical_source_sha256 "$repo_root")"
[[ "$source_tree_sha256" =~ ^[a-f0-9]{64}$ ]] || fail 'canonical source SHA-256 is malformed'

passwd_record="$(/usr/bin/getent passwd arch-linux-signing)" || fail 'dedicated signing account is absent'
[ "$(/usr/bin/getent passwd arch-linux-signing | /usr/bin/wc -l)" -eq 1 ] ||
    fail 'dedicated signing account is ambiguous'
IFS=: read -r account_name _ signing_uid signing_gid _ account_home account_shell <<<"$passwd_record"
[ "$account_name" = arch-linux-signing ] && [[ "$signing_uid" =~ ^[1-9][0-9]*$ ]] &&
    [[ "$signing_gid" =~ ^[1-9][0-9]*$ ]] && [ "$account_home" = /nonexistent ] &&
    [ "$account_shell" = /usr/sbin/nologin ] || fail 'dedicated signing account policy differs'
[ ! -e /nonexistent ] && [ ! -L /nonexistent ] || fail 'dedicated signing account has a home object'
group_record="$(/usr/bin/getent group arch-linux-signing)" || fail 'dedicated signing group is absent'
[ "$(/usr/bin/getent group arch-linux-signing | /usr/bin/wc -l)" -eq 1 ] ||
    fail 'dedicated signing group is ambiguous'
IFS=: read -r group_name _ group_gid group_members <<<"$group_record"
[ "$group_name" = arch-linux-signing ] && [ "$group_gid" = "$signing_gid" ] &&
    [ -z "$group_members" ] || fail 'dedicated signing group policy differs'
[ "$(/usr/bin/id -G arch-linux-signing)" = "$signing_gid" ] ||
    fail 'dedicated signing account has supplementary groups'
shadow_record="$(/usr/bin/awk -F: '$1=="arch-linux-signing" {print; count++} END {if(count!=1) exit 1}' /etc/shadow)" ||
    fail 'dedicated signing shadow entry is absent or ambiguous'
case "${shadow_record#*:}" in
    '!'*|'*'*) ;;
    *) fail 'dedicated signing account is not password-locked' ;;
esac

uid_processes() {
    /usr/bin/python3 -I -B - "$1" <<'PY'
from pathlib import Path
import sys
uid = int(sys.argv[1])
for status in sorted(Path('/proc').glob('[1-9]*/status'), key=lambda p: int(p.parent.name)):
    try:
        for line in status.read_text(encoding='ascii').splitlines():
            if line.startswith('Uid:') and int(line.split()[1]) == uid:
                print(status.parent.name)
                break
    except (OSError, UnicodeError, ValueError):
        continue
PY
}
[ -z "$(uid_processes "$signing_uid")" ] || fail 'dedicated signing account is not quiescent'
readonly signing_uid signing_gid passwd_record group_record shadow_record

work="$(/usr/bin/mktemp -d /var/lib/arch-linux-publication-check.XXXXXXXX)"
case "$work" in /var/lib/arch-linux-publication-check.*) ;; *) fail 'unsafe fixture root' ;; esac
[ "$(/usr/bin/stat -c '%u:%g:%a:%F' -- "$work")" = '0:0:700:directory' ] ||
    fail 'fixture root metadata differs'
/usr/bin/chmod 0711 -- "$work"

supervisor_pid=''
supervisor_start=''
watcher_pid=''
watcher_start=''
generation_home=''
signing_home=''
passphrase_file=''

process_identity_is_live() {
    local pid="$1" start="$2" actual
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [[ "$start" =~ ^[1-9][0-9]*$ ]] || return 1
    [ -r "/proc/${pid}/stat" ] || return 1
    actual="$(/usr/bin/awk '{print $22; exit}' "/proc/${pid}/stat" 2>/dev/null)" || return 1
    [ "$actual" = "$start" ]
}

signing_command() {
    /usr/bin/setpriv --reuid="$signing_uid" --regid="$signing_gid" --clear-groups -- "$@"
}

stop_home_agent() {
    local home="$1"
    [ -n "$home" ] && [ -d "$home" ] || return 0
    signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
        /usr/bin/gpgconf --homedir "$home" --kill all >/dev/null 2>&1 || true
}

kill_fixture_processes() {
    local attempt unexpected
    if [[ "${supervisor_pid:-}" =~ ^[1-9][0-9]*$ ]] &&
        [[ "${supervisor_start:-}" =~ ^[1-9][0-9]*$ ]]; then
        if process_identity_is_live "$supervisor_pid" "$supervisor_start"; then
            /usr/bin/kill -KILL -- "$supervisor_pid" 2>/dev/null || true
        fi
        wait "$supervisor_pid" 2>/dev/null || true
    fi
    supervisor_pid=''
    supervisor_start=''
    if [[ "${watcher_pid:-}" =~ ^[1-9][0-9]*$ ]] &&
        [[ "${watcher_start:-}" =~ ^[1-9][0-9]*$ ]]; then
        if process_identity_is_live "$watcher_pid" "$watcher_start"; then
            /usr/bin/kill -TERM -- "$watcher_pid" 2>/dev/null || true
        fi
        wait "$watcher_pid" 2>/dev/null || true
    fi
    watcher_pid=''
    watcher_start=''
    stop_home_agent "${generation_home:-}"
    stop_home_agent "${signing_home:-}"
    for attempt in {1..100}; do
        unexpected="$(uid_processes "$signing_uid")"
        [ -z "$unexpected" ] && return 0
        /usr/bin/sleep 0.05
    done
    printf 'publication root check cleanup failed: unexpected signing-account process remains:\n%s\n' \
        "$unexpected" >&2
    return 1
}

cleanup() {
    local status=$? cleanup_status=0
    trap - EXIT HUP INT TERM
    set +e
    kill_fixture_processes || cleanup_status=$?
    unset fixture_passphrase
    if [ -d "$work" ] && [ ! -L "$work" ] &&
        [ "$(/usr/bin/stat -c '%u:%g' -- "$work" 2>/dev/null)" = 0:0 ]; then
        /usr/bin/find "$work" -xdev -type d -exec /usr/bin/chmod u+rwx -- {} + 2>/dev/null
        /usr/bin/find "$work" -xdev -depth -delete 2>/dev/null
    fi
    if [ "$status" -eq 0 ] && [ "$cleanup_status" -ne 0 ]; then
        status="$cleanup_status"
    fi
    exit "$status"
}
trap cleanup EXIT HUP INT TERM

account_unchanged() {
    [ "$(/usr/bin/getent passwd arch-linux-signing)" = "$passwd_record" ] &&
        [ "$(/usr/bin/getent group arch-linux-signing)" = "$group_record" ] &&
        [ "$(/usr/bin/awk -F: '$1=="arch-linux-signing" {print}' /etc/shadow)" = "$shadow_record" ] &&
        [ "$(/usr/bin/id -G arch-linux-signing)" = "$signing_gid" ] &&
        [ ! -e /nonexistent ] && [ ! -L /nonexistent ]
}

signing_gpg() {
    local home="$1"
    shift
    signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin \
        GNUPGHOME="$home" /usr/bin/gpg "$@"
}

bootstrap="$work/bootstrap"
accepted_sealed="$work/accepted-sealed"
/usr/bin/install -d -m0700 -o 0 -g 0 -- "$bootstrap"
sealer_hash="$(/usr/bin/sha256sum --binary -- "$repo_root/repository/seal-offline-signing-code.py" | /usr/bin/awk '{print $1}')"
/usr/bin/install -m0500 -o 0 -g 0 -- "$repo_root/repository/seal-offline-signing-code.py" "$bootstrap/sealer"
[ "$(/usr/bin/sha256sum --binary -- "$bootstrap/sealer" | /usr/bin/awk '{print $1}')" = "$sealer_hash" ] ||
    fail 'bootstrapped sealer readback differs'
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
    /usr/bin/python3 -I "$bootstrap/sealer" "$repo_root" "$commit" "$tree" \
    "$source_tree_sha256" "$accepted_sealed" </dev/null >"$work/accepted-sealer.log"
[ "$(/usr/bin/sha256sum --binary -- "$bootstrap/sealer" | /usr/bin/awk '{print $1}')" = "$sealer_hash" ] ||
    fail 'sealer changed while capturing the accepted source'
/usr/bin/readelf -h "$accepted_sealed/repository/offline-signing-launcher" |
    /usr/bin/awk '$1=="Type:" && $2=="DYN" {found=1} END {exit !found}' ||
    fail 'accepted launcher is not static PIE ET_DYN'
if /usr/bin/readelf -l "$accepted_sealed/repository/offline-signing-launcher" | /usr/bin/grep -Fq INTERP; then
    fail 'accepted launcher contains PT_INTERP'
fi
signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    /usr/bin/python3 -I "$accepted_sealed/repository/verify-sealed-offline-code.py" \
    "$accepted_sealed" "$commit" "$tree" "$source_tree_sha256" >/dev/null
wrong_commit="0${commit:1}"
[ "$wrong_commit" != "$commit" ] || wrong_commit="1${commit:1}"
set +e
signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    /usr/bin/python3 -I "$accepted_sealed/repository/verify-sealed-offline-code.py" \
    "$accepted_sealed" "$wrong_commit" "$tree" "$source_tree_sha256" >/dev/null 2>&1
negative_status=$?
set -e
assert_real_failure "$negative_status" 'sealed verifier wrong commit'
unexpected_directory_sealed="$work/unexpected-directory-sealed"
/usr/bin/cp -a -- "$accepted_sealed" "$unexpected_directory_sealed"
/usr/bin/chmod 0755 -- "$unexpected_directory_sealed/repository"
/usr/bin/install -d -m0555 -o 0 -g 0 -- \
    "$unexpected_directory_sealed/repository/unexpected-empty-directory"
/usr/bin/chmod 0555 -- "$unexpected_directory_sealed/repository"
set +e
signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    /usr/bin/python3 -I "$unexpected_directory_sealed/repository/verify-sealed-offline-code.py" \
    "$unexpected_directory_sealed" "$commit" "$tree" "$source_tree_sha256" >/dev/null 2>&1
negative_status=$?
set -e
assert_real_failure "$negative_status" 'sealed verifier unexpected empty directory'
set +e
printf '%s\n' /nonexistent /nonexistent |
    /usr/bin/env -i "$accepted_sealed/repository/offline-signing-launcher" snapshot \
        >/dev/null 2>&1
negative_status=$?
set -e
assert_real_failure "$negative_status" 'sealed launcher invalid private request'

tampered_shadow="$work/tampered-shadow"
/usr/bin/python3 -I -B - /etc/shadow "$tampered_shadow" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
matches = 0
for index, line in enumerate(source):
    fields = line.split(":")
    if fields[0] == "arch-linux-signing":
        matches += 1
        fields[1] = "unlocked-fixture"
        source[index] = ":".join(fields)
if matches != 1:
    raise SystemExit(1)
Path(sys.argv[2]).write_text("\n".join(source) + "\n", encoding="utf-8")
PY
/usr/bin/chown 0:0 -- "$tampered_shadow"
/usr/bin/chmod 0600 -- "$tampered_shadow"

tampered_passwd_alias="$work/tampered-passwd-alias"
tampered_passwd_field="$work/tampered-passwd-field"
/usr/bin/python3 -I -B - /etc/passwd "$tampered_passwd_alias" "$tampered_passwd_field" \
    "$signing_uid" "$signing_gid" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
alias = list(source)
alias.append(
    f"arch-linux-signing-alias:x:{sys.argv[4]}:{sys.argv[5]}::/nonexistent:/usr/sbin/nologin"
)
changed = []
matches = 0
for line in source:
    fields = line.split(":")
    if fields[0] == "arch-linux-signing":
        matches += 1
        fields[1] = ""
    changed.append(":".join(fields))
if matches != 1:
    raise SystemExit(1)
Path(sys.argv[2]).write_text("\n".join(alias) + "\n", encoding="utf-8")
Path(sys.argv[3]).write_text("\n".join(changed) + "\n", encoding="utf-8")
PY
/usr/bin/chown 0:0 -- "$tampered_passwd_alias" "$tampered_passwd_field"
/usr/bin/chmod 0644 -- "$tampered_passwd_alias" "$tampered_passwd_field"

private_parent="$work/private"
/usr/bin/install -d -m0711 -o 0 -g 0 -- "$private_parent"
generation_home="$private_parent/generation-home"
signing_home="$private_parent/signing-home"
passphrase_file="$private_parent/passphrase"
/usr/bin/install -d -m0700 -o "$signing_uid" -g "$signing_gid" -- "$generation_home" "$signing_home"
fixture_passphrase="$(/usr/bin/sha256sum --binary -- /proc/sys/kernel/random/uuid | /usr/bin/awk '{print $1}')"
[ -n "$fixture_passphrase" ] || fail 'could not create disposable fixture passphrase'
printf '%s\n' "$fixture_passphrase" >"$passphrase_file"
/usr/bin/chown "$signing_uid:$signing_gid" -- "$passphrase_file"
/usr/bin/chmod 0600 -- "$passphrase_file"

signing_gpg "$generation_home" --batch --no-options --pinentry-mode loopback \
    --passphrase-file "$passphrase_file" --quick-generate-key \
    'Arch Linux offline signing fixture <offline-fixture@invalid>' ed25519 cert 2y >/dev/null 2>&1
key_metadata="$(signing_gpg "$generation_home" --batch --no-options --with-colons --list-keys)"
primary="$(/usr/bin/awk -F: '$1=="fpr" {print toupper($10); exit}' <<<"$key_metadata")"
[[ "$primary" =~ ^[A-F0-9]{40}$ ]] || fail 'fixture primary fingerprint is malformed'
signing_gpg "$generation_home" --batch --no-options --pinentry-mode loopback \
    --passphrase-file "$passphrase_file" --quick-add-key "$primary" ed25519 sign 2y >/dev/null 2>&1
key_metadata="$(signing_gpg "$generation_home" --batch --no-options --with-colons --with-subkey-fingerprint --list-keys)"
signing="$(/usr/bin/awk -F: '$1=="sub" {want=1; next} want && $1=="fpr" {print toupper($10); exit}' <<<"$key_metadata")"
[[ "$signing" =~ ^[A-F0-9]{40}$ ]] || fail 'fixture signing fingerprint is malformed'
fixture_public="$work/fixture-public.gpg"
signing_gpg "$generation_home" --batch --no-options --export -- "$primary" >"$fixture_public"
/usr/bin/chmod 0644 -- "$fixture_public"
secret_transfer="$private_parent/secret-subkey.gpg"
signing_gpg "$generation_home" --batch --no-options --pinentry-mode loopback \
    --passphrase-file "$passphrase_file" --export-secret-subkeys -- "$primary" >"$secret_transfer"
/usr/bin/chown "$signing_uid:$signing_gid" -- "$secret_transfer"
/usr/bin/chmod 0600 -- "$secret_transfer"
signing_gpg "$signing_home" --batch --no-options --import -- "$secret_transfer" >/dev/null 2>&1
/usr/bin/unlink -- "$secret_transfer"
stop_home_agent "$generation_home"
stop_home_agent "$signing_home"
for attempt in {1..100}; do
    [ -z "$(uid_processes "$signing_uid")" ] && break
    /usr/bin/sleep 0.05
done
[ -z "$(uid_processes "$signing_uid")" ] || fail 'fixture key generation left a signing-account process'
secret_shape="$(signing_gpg "$signing_home" --batch --no-options --with-colons --with-subkey-fingerprint \
    --list-secret-keys -- "${signing}!" 2>/dev/null | /usr/bin/awk -F: '
        $1=="sec" {pc++; pa=$15; want="p"; next}
        $1=="ssb" {sc++; sa=$15; cap=$12; gsub(/[A-Z]/,"",cap); want="s"; next}
        want!="" && $1=="fpr" {if(want=="p") pf=toupper($10); else sf=toupper($10); want=""}
        END {printf "%d|%s|%s|%d|%s|%s|%s",pc+0,pf,pa,sc+0,sf,sa,cap}')"
[ "$secret_shape" = "1|${primary}|#|1|${signing}|+|s" ] ||
    fail 'fixture signing home is not certification-primary-offline/subkey-only'
stop_home_agent "$signing_home"
for attempt in {1..100}; do
    [ -z "$(uid_processes "$signing_uid")" ] && break
    /usr/bin/sleep 0.05
done
[ -z "$(uid_processes "$signing_uid")" ] || fail 'signing home inspection left an account process'
private_key_count="$(/usr/bin/find "$signing_home/private-keys-v1.d" -mindepth 1 -maxdepth 1 \
    -type f -links 1 -user "$signing_uid" -perm 0600 -name '*.key' -printf . | /usr/bin/wc -c)"
[ "$private_key_count" -eq 1 ] || fail 'fixture signing home private-key closure differs'
/usr/bin/find "$generation_home" -xdev -depth -delete
generation_home=''
unset fixture_passphrase
account_unchanged || fail 'fixture key preparation changed the dedicated account'

fixture_source="$work/fixture-source"
fixture_packages="$work/fixture-packages"
/usr/bin/install -d -m0755 -o 0 -g 0 -- \
    "$fixture_source/repository/lib" "$fixture_source/repository/trust" \
    "$fixture_source/packages/arch-linux-marble-profile" \
    "$fixture_source/maintenance" "$fixture_packages"
executable_sources=(
    repository/acceptance-manifest.py
    repository/offline-finalize-release.sh
    repository/offline-sign-release.sh
    repository/offline-signing-fd-guard.py
    repository/offline-signing-namespace.sh
    repository/run-offline-signing.sh
    repository/safe-extract-snapshot.py
    repository/snapshot-manifest.py
    repository/verify-release-assets.sh
    repository/verify-signed-repository.sh
    repository/verify-sealed-offline-code.py
    repository/verify-unsigned-build.sh
    repository/lib/common.sh
    tests/vm/run.sh
    tests/vm/frame-evidence.py
    tests/vm/qga-client.py
    tests/vm/https-server.py
    tests/vm/prepare-marble-repository.sh
    tests/vm/guest/bootstrap.sh
    tests/vm/guest/verify.sh
)
for relative in "${executable_sources[@]}"; do
    /usr/bin/install -D -m0755 -o 0 -g 0 -- "$repo_root/$relative" "$fixture_source/$relative"
done
/usr/bin/install -D -m0644 -o 0 -g 0 -- "$repo_root/repository/offline-signing-launcher.c" \
    "$fixture_source/repository/offline-signing-launcher.c"
/usr/bin/install -D -m0644 -o 0 -g 0 -- "$repo_root/repository/source-date-epoch" \
    "$fixture_source/repository/source-date-epoch"
/usr/bin/install -D -m0644 -o 0 -g 0 -- "$repo_root/maintenance/accepted-arch-iso.json" \
    "$fixture_source/maintenance/accepted-arch-iso.json"
/usr/bin/install -D -m0644 -o 0 -g 0 -- "$repo_root/packages/arch-linux-marble-profile/.SRCINFO" \
    "$fixture_source/packages/arch-linux-marble-profile/.SRCINFO"
/usr/bin/install -m0644 -o 0 -g 0 -- "$fixture_public" "$fixture_source/repository/trust/arch-linux.gpg"
printf '%s\n' "$primary" >"$fixture_source/repository/trust/primary-fingerprint"
printf '%s\n' "$signing" >"$fixture_source/repository/trust/signing-subkey-fingerprint"
printf '%s\n' arch-linux-marble-profile >"$fixture_source/repository/package-set"
/usr/bin/chmod 0644 -- "$fixture_source/repository/trust/"* "$fixture_source/repository/package-set"
printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$#" -eq 1 ] && [ "$1" = --version ]; then printf "%s\\n" 1.0.0; exit 0; fi' \
    'exit 2' >"$fixture_source/arch-linux-installer.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fixture_source/install.sh"
/usr/bin/chmod 0755 -- "$fixture_source/arch-linux-installer.sh" "$fixture_source/install.sh"
/usr/bin/python3 -I -B - "$fixture_source/repository/verify-package-metadata.py" \
    "$repo_root/repository/verify-package-metadata.py" \
    "$(/usr/bin/sha256sum --binary -- "$repo_root/repository/verify-package-metadata.py" | /usr/bin/awk '{print $1}')" <<'PY'
import hashlib
import os
from pathlib import Path
import stat
import sys
destination = Path(sys.argv[1])
verifier = sys.argv[2]
expected = sys.argv[3]
destination.write_text(
    '#!/usr/bin/env python3\nimport hashlib,os,stat,sys\nfrom pathlib import Path\n'
    f'p=Path({verifier!r}); e={expected!r}; a=p.lstat(); d=p.read_bytes(); b=p.lstat()\n'
    'i=lambda s:(s.st_dev,s.st_ino,s.st_uid,s.st_gid,s.st_mode,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)\n'
    'ou=int(Path("/proc/sys/kernel/overflowuid").read_text()); og=int(Path("/proc/sys/kernel/overflowgid").read_text())\n'
    'if not stat.S_ISREG(a.st_mode): raise SystemExit("fixture verifier is not regular")\n'
    'if a.st_uid not in {0,ou} or a.st_gid not in {0,og}: raise SystemExit("fixture verifier owner is neither namespace-root nor unmapped host root")\n'
    'if stat.S_IMODE(a.st_mode)!=0o755 or a.st_nlink!=1: raise SystemExit("fixture verifier mode or links differ")\n'
    'if i(a)!=i(b): raise SystemExit("fixture verifier identity changed during read")\n'
    'if hashlib.sha256(d).hexdigest()!=e: raise SystemExit("fixture verifier hash differs")\n'
    f'os.execv("/usr/bin/python3",["/usr/bin/python3","-I",{verifier!r},*sys.argv[1:]])\n',
    encoding='utf-8',
)
PY
/usr/bin/chmod 0755 -- "$fixture_source/repository/verify-package-metadata.py"

PYTHONDONTWRITEBYTECODE=1 PACKAGE_FIXTURE_OUTPUT_DIR="$fixture_packages" \
    /usr/bin/bash "$repo_root/tests/package-checks.sh" >/dev/null
profile_packages=("$fixture_packages/arch-linux-marble-profile-"*.pkg.tar.zst)
[ "${#profile_packages[@]}" -eq 1 ] && [ -f "${profile_packages[0]}" ] ||
    fail 'profile package fixture closure differs'

/usr/bin/git -c safe.directory="$fixture_source" -C "$fixture_source" init --quiet --initial-branch=main
/usr/bin/git -c safe.directory="$fixture_source" -C "$fixture_source" add -- .
/usr/bin/git -c safe.directory="$fixture_source" -C "$fixture_source" \
    -c user.name='Offline Fixture' -c user.email='offline-fixture@invalid' \
    commit --quiet -m 'fixture: trust-bound signer source'
fixture_commit="$(/usr/bin/git -c safe.directory="$fixture_source" -C "$fixture_source" rev-parse 'HEAD^{commit}')"
fixture_tree="$(/usr/bin/git -c safe.directory="$fixture_source" -C "$fixture_source" rev-parse 'HEAD^{tree}')"
fixture_tree_sha256="$(canonical_source_sha256 "$fixture_source")"

unsigned="$work/unsigned"
/usr/bin/install -d -m0755 -o 0 -g 0 -- "$unsigned" "$unsigned/metadata"
profile_name="${profile_packages[0]##*/}"
/usr/bin/install -m0644 -o 0 -g 0 -- "${profile_packages[0]}" "$unsigned/$profile_name"
/usr/bin/install -m0644 -o 0 -g 0 -- "$fixture_source/packages/arch-linux-marble-profile/.SRCINFO" \
    "$unsigned/metadata/arch-linux-marble-profile.SRCINFO"
(
    cd -- "$unsigned"
    while IFS= read -r file; do /usr/bin/sha256sum --binary -- "$file"; done \
        < <(/usr/bin/find . -type f ! -name BUILD-METADATA.json ! -name UNSIGNED-SHA256SUMS \
            -printf '%P\n' | LC_ALL=C /usr/bin/sort)
) >"$unsigned/UNSIGNED-SHA256SUMS"
/usr/bin/chmod 0644 -- "$unsigned/UNSIGNED-SHA256SUMS"
unsigned_hash="$(/usr/bin/sha256sum --binary -- "$unsigned/UNSIGNED-SHA256SUMS" | /usr/bin/awk '{print $1}')"
installer_hash="$(/usr/bin/sha256sum --binary -- "$fixture_source/arch-linux-installer.sh" | /usr/bin/awk '{print $1}')"
package_set_hash="$(/usr/bin/sha256sum --binary -- "$fixture_source/repository/package-set" | /usr/bin/awk '{print $1}')"
source_epoch="$(<"$fixture_source/repository/source-date-epoch")"
/usr/bin/python3 -I -B - "$unsigned/BUILD-METADATA.json" "$fixture_commit" "$fixture_tree" \
    "$installer_hash" "$package_set_hash" "$source_epoch" "$unsigned_hash" "$profile_name" <<'PY'
import json
from pathlib import Path
import sys
value = {
    'schema': 2,
    'sourceCommit': sys.argv[2],
    'sourceTree': sys.argv[3],
    'installerSha256': sys.argv[4],
    'packageSetSha256': sys.argv[5],
    'sourceDateEpoch': int(sys.argv[6]),
    'unsignedManifestSha256': sys.argv[7],
    'packages': [sys.argv[8]],
}
Path(sys.argv[1]).write_text(json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n')
PY
/usr/bin/chmod 0644 -- "$unsigned/BUILD-METADATA.json"
build_hash="$(/usr/bin/sha256sum --binary -- "$unsigned/BUILD-METADATA.json" | /usr/bin/awk '{print $1}')"
/usr/bin/bash "$fixture_source/repository/verify-unsigned-build.sh" "$unsigned" >/dev/null

fixture_sealed="$work/fixture-sealed"
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
    /usr/bin/python3 -I "$bootstrap/sealer" "$fixture_source" "$fixture_commit" "$fixture_tree" \
    "$fixture_tree_sha256" "$fixture_sealed" </dev/null >"$work/fixture-sealer.log"
fixture_launcher="$fixture_sealed/repository/offline-signing-launcher"
signing_command /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin:/bin TMPDIR=/tmp \
    /usr/bin/python3 -I "$fixture_sealed/repository/verify-sealed-offline-code.py" \
    "$fixture_sealed" "$fixture_commit" "$fixture_tree" "$fixture_tree_sha256" >/dev/null

signer_outputs="$work/signer-outputs"
/usr/bin/install -d -m0700 -o "$signing_uid" -g "$signing_gid" -- "$signer_outputs"
ambient="$work/ambient-descriptor"
printf '%s\n' ambient >"$ambient"
/usr/bin/chmod 0644 -- "$ambient"

require_line_once() {
    local payload="$1" wanted="$2" count
    count="$(/usr/bin/grep -Fxc -- "$wanted" <<<"$payload" || true)"
    [ "$count" -eq 1 ] || fail "signer readback is absent or duplicated: ${wanted}"
}

require_boundary_readbacks() {
    local payload="$1"
    require_line_once "$payload" 'Host signing-agent absence: verified'
    require_line_once "$payload" 'Offline signing crash containment: verified'
    require_line_once "$payload" 'Offline signing agent containment: verified'
    require_line_once "$payload" 'Offline signing agent termination: verified'
}

invoke_launcher() {
    local destination="$1" log="$2"
    shift 2
    local output status
    set +e
    output="$(
        printf '%s\n%s\n' "$signing_home" "$passphrase_file" |
            /usr/bin/env -i "$fixture_launcher" "$@" 10<"$ambient"
    )" 2>"$log"
    status=$?
    set -e
    [ "$status" -eq 0 ] || {
        while IFS= read -r failure_line; do
            failure_line="${failure_line//"$work"/<fixture>}"
            printf '%s\n' "$failure_line" >&2
        done <"$log"
        case "$status" in 126|127) fail "launcher subject did not execute (status ${status})" ;; esac
        fail "launcher mode failed for ${destination} (status ${status})"
    }
    require_boundary_readbacks "$output"
    if /usr/bin/grep -Fq -- "$signing_home" <<<"$output" ||
        /usr/bin/grep -Fq -- "$passphrase_file" <<<"$output" ||
        /usr/bin/grep -Fq -- "$signing_home" "$log" ||
        /usr/bin/grep -Fq -- "$passphrase_file" "$log"; then
        fail 'private input pathname escaped into signer output'
    fi
    [ -z "$(uid_processes "$signing_uid")" ] || fail 'launcher left a signing-account process'
    [ -z "$(/usr/bin/find "$signing_home" -type s -print -quit)" ] ||
        fail 'launcher left a signing-agent socket in the retained home'
    printf '%s' "$output"
}

assert_isolated_launcher_rejection() {
    local label="$1" status="$2" marker="$3" stdout="$4" stderr="$5" output="$6"
    assert_real_failure "$status" "$label"
    [ "$status" -eq 1 ] || fail "account-policy rejection status differs: ${label} (status ${status})"
    [ -f "$marker" ] && [ ! -L "$marker" ] &&
        [ "$(<"$marker")" = account-policy-mounted-and-verified ] ||
        fail "account-policy fixture did not verify its mounted mutation: ${label}"
    [ -f "$stdout" ] && [ ! -s "$stdout" ] ||
        fail "account-policy rejection wrote unexpected stdout: ${label}"
    [ -f "$stderr" ] && [ ! -L "$stderr" ] &&
        [ "$(<"$stderr")" = 'ERROR: sealed offline signing launcher failed' ] ||
        fail "account-policy rejection diagnostic differs: ${label}"
    [ ! -e "$output" ] && [ ! -L "$output" ] ||
        fail "account-policy rejection created its otherwise-valid output: ${label}"
    [ -z "$(uid_processes "$signing_uid")" ] ||
        fail "account-policy rejection left a signing-account process: ${label}"
    account_unchanged || fail "account-policy fixture changed the host account: ${label}"
}

run_account_policy_negative() {
    local slug="$1" label="$2" policy_source="$3" policy_target="$4" mutation="$5"
    local output="$signer_outputs/account-negative-${slug}"
    local marker="$work/account-negative-${slug}.mounted"
    local stdout="$work/account-negative-${slug}.stdout"
    local stderr="$work/account-negative-${slug}.stderr"
    local probe_stdout="$work/account-negative-${slug}.probe.stdout"
    local probe_stderr="$work/account-negative-${slug}.probe.stderr"
    local status
    [ ! -e "$output" ] && [ ! -L "$output" ] ||
        fail "account-policy negative output already exists: ${label}"
    [ ! -e "$account_probe_marker" ] && [ ! -L "$account_probe_marker" ] ||
        fail "account-policy probe marker already exists: ${label}"
    set +e
    /usr/bin/unshare --mount --propagation private --fork /usr/bin/bash -c '
        set -euo pipefail
        /usr/bin/mount --bind "$1" "$2"
        [ "$(/usr/bin/stat -Lc "%d:%i" -- "$1")" = \
            "$(/usr/bin/stat -Lc "%d:%i" -- "$2")" ]
        case "$4" in
            unlocked-shadow)
                /usr/bin/awk -F: "
                    \$1==\"arch-linux-signing\" {count++; valid=(\$2==\"unlocked-fixture\")}
                    END {exit !(count==1 && valid)}
                " "$2"
                ;;
            duplicate-uid)
                /usr/bin/awk -F: -v uid="$5" "
                    \$3==uid {same_uid++}
                    \$1==\"arch-linux-signing\" && \$3==uid {canonical++}
                    \$1==\"arch-linux-signing-alias\" && \$3==uid {alias++}
                    END {exit !(same_uid==2 && canonical==1 && alias==1)}
                " "$2"
                ;;
            empty-passwd-password)
                /usr/bin/awk -F: "
                    \$1==\"arch-linux-signing\" {count++; valid=(\$2==\"\")}
                    END {exit !(count==1 && valid)}
                " "$2"
                ;;
            *) exit 92 ;;
        esac
        printf "%s\n" account-policy-mounted-and-verified >"$3"
        set +e
        /usr/bin/env -i "${16}" snapshot \
            --unsigned "$9" --installer "${10}" --output "${11}" \
            --release-version 1.0.0 --build-metadata-sha256 "${12}" \
            --unsigned-manifest-sha256 "${13}" \
            < <(printf "%s\n%s\n" "$6" "$7") >"${18}" 2>"${19}"
        probe_status=$?
        set -e
        [ "$probe_status" -eq 1 ] && [ -f "${18}" ] && [ ! -s "${18}" ] &&
            [ -f "${19}" ] &&
            [ "$(<"${19}")" = "ERROR: sealed offline signing launcher failed" ] &&
            [ ! -e "${17}" ] && [ ! -L "${17}" ]
        /usr/bin/env -i "$8" snapshot \
            --unsigned "$9" --installer "${10}" --output "${11}" \
            --release-version 1.0.0 --build-metadata-sha256 "${12}" \
            --unsigned-manifest-sha256 "${13}" \
            < <(printf "%s\n%s\n" "$6" "$7") >"${14}" 2>"${15}"
    ' bash "$policy_source" "$policy_target" "$marker" "$mutation" "$signing_uid" \
        "$signing_home" "$passphrase_file" "$fixture_launcher" "$unsigned" \
        "$fixture_sealed/arch-linux-installer.sh" "$output" "$build_hash" "$unsigned_hash" \
        "$stdout" "$stderr" "$account_probe" "$account_probe_marker" "$probe_stdout" \
        "$probe_stderr"
    status=$?
    set -e
    assert_isolated_launcher_rejection "$label" "$status" "$marker" "$stdout" "$stderr" "$output"
}

snapshot_output="$signer_outputs/snapshot"
snapshot_log="$work/snapshot.stderr"
snapshot_readback="$(invoke_launcher "$snapshot_output" "$snapshot_log" snapshot \
    --unsigned "$unsigned" --installer "$fixture_sealed/arch-linux-installer.sh" \
    --output "$snapshot_output" --release-version 1.0.0 \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash")"
require_line_once "$snapshot_readback" "offline release signing completed: ${snapshot_output}"
phase_a="$snapshot_output/assets"
expected_phase_a=$'BUILD-METADATA.json\nRELEASE-SHA256SUMS\nRELEASE-SHA256SUMS.sig\nUNSIGNED-SHA256SUMS\narch-linux-installer.sh\narch-linux-installer.sh.sha256\narch-linux-installer.sh.sig\narch-linux-repository-1.0.0.tar.zst\narch-linux-repository-1.0.0.tar.zst.sha256\narch-linux-repository-1.0.0.tar.zst.sig\narch-linux.gpg\ninstall.sh\nprimary-fingerprint\nsigning-subkey-fingerprint'
actual_phase_a="$(/usr/bin/find "$phase_a" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C /usr/bin/sort)"
[ "$actual_phase_a" = "$expected_phase_a" ] && [ "$(printf '%s\n' "$actual_phase_a" | /usr/bin/wc -l)" -eq 14 ] ||
    fail 'snapshot launcher output is not exact 14'
if ! /usr/bin/cmp --silent -- "$unsigned/BUILD-METADATA.json" "$phase_a/BUILD-METADATA.json" ||
    ! /usr/bin/cmp --silent -- "$unsigned/UNSIGNED-SHA256SUMS" "$phase_a/UNSIGNED-SHA256SUMS"; then
    fail 'snapshot launcher changed an accepted build manifest'
fi
/usr/bin/bash "$fixture_source/repository/verify-release-assets.sh" "$phase_a" --phase-a \
    --release-version 1.0.0 --source-commit "$fixture_commit" --source-tree "$fixture_tree" \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" >/dev/null

# The normal snapshot above is the positive control for every account-policy negative below. Each
# negative uses the same valid private inputs and signer argv with only a fresh output name. Keep the
# account check ahead of all public/private request processing so no later pathname or usage failure
# can make a removed account rule look rejected.
/usr/bin/python3 -I -B - "$fixture_source/repository/offline-signing-launcher.c" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
main = source.split("int main(int argc, char **argv) {", 1)[1]
markers = (
    "!validate_account_and_drop_privileges()",
    "!derive_paths(root, sizeof(root)",
    "!parse_invocation(argc, argv, root, &public_paths)",
    "!read_request(request, sizeof(request), &gnupg_home, &passphrase_file)",
)
if any(source.count(marker) != 1 for marker in markers):
    raise SystemExit("launcher account-policy isolation marker differs")
positions = [main.index(marker) for marker in markers]
if positions != sorted(positions) or len(set(positions)) != len(positions):
    raise SystemExit("launcher account policy is not before request validation")
for marker in (
    "passwd_policy_is_exact(passwd_data)",
    "group_policy_is_exact(group_data)",
    "shadow_policy_is_exact(shadow_data)",
):
    if source.count(marker) != 1:
        raise SystemExit(f"launcher account-policy predicate differs: {marker}")
PY

account_probe_source="$work/account-policy-launcher-probe.c"
account_probe="$work/account-policy-launcher-probe"
account_probe_marker="$signer_outputs/account-policy-probe-reached"
/usr/bin/python3 -I -B - "$fixture_source/repository/offline-signing-launcher.c" \
    "$account_probe_source" "$account_probe_marker" <<'PY'
from pathlib import Path
import json
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
destination = Path(sys.argv[2])
marker = json.dumps(sys.argv[3])
anchor = """        !dedicated_account_is_quiescent()) {
        return fail();
    }
"""
if source.count(anchor) != 1:
    raise SystemExit("launcher account-policy probe anchor differs")
probe = f'''    static const char account_probe_payload[] = "account-policy-reached\\n";
    int account_probe_descriptor = open(
        {marker}, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600U);
    if (account_probe_descriptor < 0 ||
        !write_all(account_probe_descriptor, account_probe_payload,
                   sizeof(account_probe_payload) - 1U) ||
        close(account_probe_descriptor) != 0) {{
        return fail();
    }}
    return 0;

'''
destination.write_text(source.replace(anchor, anchor + probe), encoding="utf-8")
PY
/usr/bin/cc -std=c17 -O2 -static-pie -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
    -Wall -Wextra -Werror \
    "-DALI_ACCEPTED_COMMIT_SHA=\"$fixture_commit\"" \
    "-DALI_ACCEPTED_TREE_SHA=\"$fixture_tree\"" \
    "-DALI_ACCEPTED_TREE_SHA256=\"$fixture_tree_sha256\"" \
    "-DALI_SIGNING_UID=$signing_uid" "-DALI_SIGNING_GID=$signing_gid" \
    -o "$account_probe" "$account_probe_source"
[ ! -e "$account_probe_marker" ] && [ ! -L "$account_probe_marker" ] ||
    fail 'launcher account-policy probe marker unexpectedly exists'
account_probe_stdout="$work/account-policy-probe-positive.stdout"
account_probe_stderr="$work/account-policy-probe-positive.stderr"
set +e
/usr/bin/env -i "$account_probe" snapshot \
    --unsigned "$unsigned" --installer "$fixture_sealed/arch-linux-installer.sh" \
    --output "$signer_outputs/account-policy-probe-unused-output" --release-version 1.0.0 \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" \
    < <(printf '%s\n%s\n' "$signing_home" "$passphrase_file") \
    >"$account_probe_stdout" 2>"$account_probe_stderr"
account_probe_status=$?
set -e
[ "$account_probe_status" -eq 0 ] && [ -f "$account_probe_stdout" ] &&
    [ ! -s "$account_probe_stdout" ] && [ -f "$account_probe_stderr" ] &&
    [ ! -s "$account_probe_stderr" ] &&
    [ "$(/usr/bin/stat -Lc '%u:%g:%a:%h:%F' -- "$account_probe_marker")" = \
        "$signing_uid:$signing_gid:600:1:regular file" ] &&
    [ "$(<"$account_probe_marker")" = account-policy-reached ] ||
    fail 'launcher account-policy positive probe did not reach the isolated boundary'
/usr/bin/unlink -- "$account_probe_marker"

nonroot_output="$signer_outputs/account-negative-nonroot"
nonroot_stdout="$work/account-negative-nonroot.stdout"
nonroot_stderr="$work/account-negative-nonroot.stderr"
[ ! -e "$nonroot_output" ] && [ ! -L "$nonroot_output" ] ||
    fail 'nonroot account-policy output already exists'
set +e
signing_command /usr/bin/env -i "$fixture_launcher" snapshot \
    --unsigned "$unsigned" --installer "$fixture_sealed/arch-linux-installer.sh" \
    --output "$nonroot_output" --release-version 1.0.0 \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" \
    < <(printf '%s\n%s\n' "$signing_home" "$passphrase_file") \
    >"$nonroot_stdout" 2>"$nonroot_stderr"
negative_status=$?
set -e
assert_real_failure "$negative_status" 'sealed launcher nonroot entry with valid request'
[ "$negative_status" -eq 1 ] && [ -f "$nonroot_stdout" ] && [ ! -s "$nonroot_stdout" ] &&
    [ "$(<"$nonroot_stderr")" = 'ERROR: sealed offline signing launcher failed' ] &&
    [ ! -e "$nonroot_output" ] && [ ! -L "$nonroot_output" ] ||
    fail 'sealed launcher nonroot rejection was not isolated from its valid request'
[ -z "$(uid_processes "$signing_uid")" ] ||
    fail 'sealed launcher nonroot rejection left a signing-account process'

run_account_policy_negative unlocked-shadow 'sealed launcher unlocked account mutation' \
    "$tampered_shadow" /etc/shadow unlocked-shadow
run_account_policy_negative duplicate-uid 'sealed launcher duplicate passwd UID mutation' \
    "$tampered_passwd_alias" /etc/passwd duplicate-uid
run_account_policy_negative empty-password 'sealed launcher passwd password-field mutation' \
    "$tampered_passwd_field" /etc/passwd empty-passwd-password

account_alias_sealer_output="$work/account-negative-alias-seal"
account_alias_sealer_marker="$work/account-negative-alias-sealer.mounted"
account_alias_sealer_stdout="$work/account-negative-alias-sealer.stdout"
account_alias_sealer_stderr="$work/account-negative-alias-sealer.stderr"
set +e
/usr/bin/unshare --mount --propagation private --fork /usr/bin/bash -c '
    set -euo pipefail
    /usr/bin/mount --bind "$1" /etc/passwd
    [ "$(/usr/bin/stat -Lc "%d:%i" -- "$1")" = \
        "$(/usr/bin/stat -Lc "%d:%i" -- /etc/passwd)" ]
    /usr/bin/awk -F: -v uid="$2" "
        \$3==uid {same_uid++}
        \$1==\"arch-linux-signing\" && \$3==uid {canonical++}
        \$1==\"arch-linux-signing-alias\" && \$3==uid {alias++}
        END {exit !(same_uid==2 && canonical==1 && alias==1)}
    " /etc/passwd
    printf "%s\n" account-policy-mounted-and-verified >"$3"
    /usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
        /usr/bin/python3 -I "$4" "$5" "$6" "$7" "$8" "$9" \
        </dev/null >"${10}" 2>"${11}"
' bash "$tampered_passwd_alias" "$signing_uid" "$account_alias_sealer_marker" \
    "$bootstrap/sealer" "$fixture_source" "$fixture_commit" "$fixture_tree" \
    "$fixture_tree_sha256" "$account_alias_sealer_output" "$account_alias_sealer_stdout" \
    "$account_alias_sealer_stderr"
negative_status=$?
set -e
[ "$negative_status" -eq 1 ] &&
    [ "$(<"$account_alias_sealer_marker")" = account-policy-mounted-and-verified ] &&
    [ -f "$account_alias_sealer_stdout" ] && [ ! -s "$account_alias_sealer_stdout" ] &&
    [ "$(<"$account_alias_sealer_stderr")" = 'ERROR: offline code sealing failed' ] &&
    [ ! -e "$account_alias_sealer_output" ] && [ ! -L "$account_alias_sealer_output" ] ||
    fail 'duplicate-UID sealer rejection was not isolated from its valid request'
account_unchanged || fail 'account-policy negatives changed the dedicated account'

archive="$phase_a/arch-linux-repository-1.0.0.tar.zst"
snapshot_hash="$(/usr/bin/sha256sum --binary -- "$archive" | /usr/bin/awk '{print $1}')"
release_manifest_hash="$(/usr/bin/sha256sum --binary -- "$phase_a/RELEASE-SHA256SUMS" | /usr/bin/awk '{print $1}')"
qemu_root="$work/synthetic-qemu-inputs"
/usr/bin/install -d -m0755 -o 0 -g 0 -- "$qemu_root"
scenarios=(
    minimal-ext4-systemdboot
    stock-gnome-btrfs-luks2-plymouth-grub
    marble-gnome-btrfs-luks2-plymouth-systemdboot
)
repository_manifest="$snapshot_output/repository/repository-manifest.json"
repository_manifest_signature="$snapshot_output/repository/repository-manifest.json.sig"
[ -f "$repository_manifest" ] && [ ! -L "$repository_manifest" ] &&
    [ -f "$repository_manifest_signature" ] && [ ! -L "$repository_manifest_signature" ] ||
    fail 'snapshot repository manifest closure is absent'
/usr/bin/python3 -I -B - "$qemu_root" "$fixture_commit" "$fixture_tree" \
    "$build_hash" "$unsigned_hash" "$snapshot_hash" "$release_manifest_hash" \
    "$repository_manifest" "$repository_manifest_signature" "$phase_a" "$fixture_source" <<'PY'
from __future__ import annotations

import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
commit, tree, build_hash, unsigned_hash, snapshot_hash, release_hash = sys.argv[2:8]
repository_manifest = Path(sys.argv[8]).read_bytes()
repository_signature = Path(sys.argv[9]).read_bytes()
assets = Path(sys.argv[10])
source = Path(sys.argv[11])
spec = importlib.util.spec_from_file_location(
    'acceptance_manifest_fixture', source / 'repository/acceptance-manifest.py')
if spec is None or spec.loader is None:
    raise SystemExit('acceptance manifest fixture module is unavailable')
am = importlib.util.module_from_spec(spec)
spec.loader.exec_module(am)
scenarios = (
    ('minimal-ext4-systemdboot', 'minimal', 'M'),
    ('stock-gnome-btrfs-luks2-plymouth-grub', 'luksgrub', 'G'),
    ('marble-gnome-btrfs-luks2-plymouth-systemdboot', 'marble', 'A'),
)
phases = ('firstboot', 'postreboot')
manifest_value = json.loads(repository_manifest)
objects = manifest_value['files']
object_map = {item['name']: item for item in objects}
primary = (assets / 'primary-fingerprint').read_text().strip()
signing = (assets / 'signing-subkey-fingerprint').read_text().strip()
public_key_hash = hashlib.sha256((assets / 'arch-linux.gpg').read_bytes()).hexdigest()
installer_hash = hashlib.sha256((assets / 'arch-linux-installer.sh').read_bytes()).hexdigest()
bootstrap_hash = hashlib.sha256((assets / 'install.sh').read_bytes()).hexdigest()
iso_hash = json.loads((source / 'maintenance/accepted-arch-iso.json').read_text())['sha256']


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)
    path.chmod(0o644)


def identity(phase, index):
    socket_device = 10 + index // 10
    start_time = 9000 + index if phase == 'firstboot' else 9001 + index
    values = {
        'phase': phase,
        'pid': str(100 + index),
        'start_time': str(start_time),
        'qga_identity': f'{socket_device}:{20 + index}',
        'qmp_identity': f'{socket_device}:{40 + index}',
    }
    raw = ''.join(f'{key}={values[key]}\n' for key in
                  ('phase', 'pid', 'start_time', 'qga_identity', 'qmp_identity')).encode()
    return values, raw


def ppm(width, height, seed):
    pixel = bytes(((seed * 17) % 256, (seed * 31) % 256, (seed * 47) % 256))
    return f'P6\n{width} {height}\n255\n'.encode() + pixel * (width * height)



for index, (scenario, prefix, serial_code) in enumerate(scenarios, 1):
    run = root / scenario
    evidence = run / 'evidence'
    evidence.mkdir(parents=True)
    run_id = f'{prefix}-20260902T00000{index}Z-{index:08x}'
    selected = ([] if prefix == 'luksgrub' else ['firstboot-tty.ppm'] if prefix == 'minimal'
                else [f'diagnostic-{number}.ppm' for number in range(5)])
    identities = {}
    for phase_index, phase in enumerate(phases, 1):
        values, raw = identity(phase, index * 10 + phase_index)
        identities[phase] = values
        write(evidence / f'{phase}-qemu.identity', raw)
    selected_bytes = {
        name: ppm(16, 16, index * 20 + item)
        for item, name in enumerate(selected, 1)
    }
    for name, value in selected_bytes.items():
        write(evidence / name, value)
    object_rows = ''.join(
        f"{item['name']}\t{item['sha256']}\t{item['size']}\n" for item in objects
    ).encode()
    write(evidence / 'repository-objects.tsv', object_rows)
    write(evidence / 'repository-manifest.json', repository_manifest)
    write(evidence / 'repository-manifest.json.sig', repository_signature)
    marker = {'minimal': 'MINIMAL', 'luksgrub': 'LUKSGRUB', 'marble': 'MARBLE'}[prefix]
    log = (
        f'{marker}_QEMU_INSTALLER_EXIT status=0\n'
        f'{marker}_QEMU_INSTALL_COMPLETE run_id={run_id}\n'
    ).encode()
    write(evidence / 'scenario.log.gz', gzip.compress(log, mtime=0))
    write(evidence / 'final-qemu-img-check.txt', b'No errors were found on the image.\n')
    write(
        evidence / 'no-qemu-process.txt',
        f'no matching QEMU process remains for {run_id}\n'.encode())
    harness = b''.join(
        f'{digest((source / name).read_bytes())}  {name}\n'.encode()
        for name in am.HARNESS_FILES)
    write(run / 'harness.sha256', harness)
    write(
        evidence / 'preseal-harness-check.txt',
        b''.join(f'{name}: OK\n'.encode() for name in am.HARNESS_FILES))
    run_path = f'/fixture/{run_id}'
    initial_ovmf = digest(b'OVMF template fixture')
    final_ovmf = digest(f'OVMF final {scenario}'.encode())
    write(
        run / 'OVMF_VARS.initial.sha256',
        f'{initial_ovmf}  {run_path}/OVMF_VARS.fd\n'.encode())
    write(
        run / 'OVMF_VARS.final.sha256',
        f'{final_ovmf}  {run_path}/OVMF_VARS.fd\n'.encode())
    write(
        run / 'payload.iso.sha256',
        f"{digest(f'payload {scenario}'.encode())}  {run_path}/payload.iso\n".encode())
    runtime_names = (
        '/usr/bin/qemu-system-x86_64', '/usr/bin/qemu-img',
        '/usr/share/OVMF/OVMF_CODE_4M.fd', '/usr/share/OVMF/OVMF_VARS_4M.fd',
    )
    write(
        run / 'runtime-inputs.sha256',
        b''.join(f"{digest(f'{scenario}:{name}'.encode())}  {name}\n".encode()
                 for name in runtime_names))
    assertion_rows = []
    assertion_values = []
    for assertion_id in am.EXPECTED_ASSERTIONS[scenario]:
        detail = f'fixture exercises exact required assertion {assertion_id}'
        assertion_rows.append(f'{assertion_id}\tPASS\t{detail}\n')
        assertion_values.append({'id': assertion_id, 'status': 'PASS', 'detail': detail})
    write(run / 'assertions.tsv', ''.join(assertion_rows).encode())
    write(run / 'qemu-version.txt', b'QEMU emulator version 9.2.0\n')
    if prefix == 'marble':
        runtime_suffixes = (
            '/repository/repository.env', '/repository.contract', '/repository-ca.crt',
            '/repository-server.crt',
        )
        write(
            run / 'repository-runtime.sha256',
            b''.join(f"{digest(f'{scenario}:{name}'.encode())}  {run_path}{name}\n".encode()
                     for name in runtime_suffixes))
    retained_counter = 400_000_000 + index
    write(run / 'evidence-size.txt', f'{retained_counter}\n'.encode())
    serial = f'ALI100{serial_code}{index:012X}'
    result = {
        'assertions': assertion_values,
        'buildMetadataSha256': build_hash,
        'exitStatus': 0,
        'failedPhase': None,
        'harnessSha256': digest(harness),
        'inputMode': 'staged',
        'installerSha256': installer_hash,
        'isoSha256': iso_hash,
        'releaseSha256sumsSha256': release_hash,
        'releaseVersion': '1.0.0',
        'repositoryDatabaseSha256': object_map['arch-linux.db.tar.gz']['sha256'],
        'repositoryDatabaseSignatureSha256': object_map['arch-linux.db.tar.gz.sig']['sha256'],
        'repositoryFilesSha256': object_map['arch-linux.files.tar.gz']['sha256'],
        'repositoryFilesSignatureSha256': object_map['arch-linux.files.tar.gz.sig']['sha256'],
        'repositoryManifestSha256': digest(repository_manifest),
        'repositoryManifestSignatureSha256': digest(repository_signature),
        'repositoryObjects': objects,
        'repositoryPackageSetSha256': manifest_value['packageSetSha256'],
        'repositoryPrimaryFingerprint': primary,
        'repositoryPublicKeySha256': public_key_hash,
        'repositorySigningFingerprint': signing,
        'repositorySnapshotSha256': snapshot_hash,
        'retainedEvidenceBytes': retained_counter,
        'runId': run_id,
        'scenario': scenario,
        'screenshots': sorted(selected),
        'snapshotVerification': 'INDEPENDENT_PASS',
        'sourceCommit': commit,
        'sourceTree': tree,
        'status': 'PASS',
        'targetSerial': serial,
        'unsignedManifestSha256': unsigned_hash,
    }
    if set(result) != am.RESULT_KEYS:
        raise SystemExit('synthetic result schema differs')
    model = {'minimal': 'MIN', 'luksgrub': 'GRB', 'marble': 'MAR'}[prefix]
    identity_rows = [
        ('scenario', scenario), ('input_mode', 'staged'), ('release_version', '1.0.0'),
        ('run_id', run_id), ('source_commit', commit), ('source_tree', tree),
        ('installer_sha256', installer_hash), ('bootstrap_sha256', bootstrap_hash),
        ('harness_sha256', digest(harness)), ('iso_sha256', iso_hash),
        ('snapshot_sha256', snapshot_hash), ('build_metadata_sha256', build_hash),
        ('unsigned_manifest_sha256', unsigned_hash), ('target_serial', serial),
        ('target_vendor', 'SNAPLYZE'), ('target_model', f'ALI_{model}_{index:08X}'),
        ('repository_public_key_sha256', public_key_hash),
        ('repository_primary_fingerprint', primary),
        ('repository_signing_fingerprint', signing),
        ('repository_package_set_sha256', manifest_value['packageSetSha256']),
        ('repository_manifest_sha256', digest(repository_manifest)),
        ('repository_manifest_signature_sha256', digest(repository_signature)),
        ('repository_database_sha256', object_map['arch-linux.db.tar.gz']['sha256']),
        ('repository_database_signature_sha256', object_map['arch-linux.db.tar.gz.sig']['sha256']),
        ('repository_files_sha256', object_map['arch-linux.files.tar.gz']['sha256']),
        ('repository_files_signature_sha256', object_map['arch-linux.files.tar.gz.sig']['sha256']),
        ('release_sha256sums_sha256', release_hash),
    ]
    identity_text = ''.join(f'{key}={value}\n' for key, value in identity_rows)
    identity_text += ''.join(
        f"repository_object_sha256={item['sha256']} name={item['name']} size={item['size']}\n"
        for item in objects)
    if prefix == 'marble':
        identity_text += 'repository_server_port=43210\n'
    write(run / 'identity.txt', identity_text.encode())
    result_raw = encoded(result)
    write(run / 'result.json', result_raw)

for base, directories, files in os.walk(root):
    Path(base).chmod(0o755)
    for name in directories:
        (Path(base) / name).chmod(0o755)
    for name in files:
        (Path(base) / name).chmod(0o644)
PY

final_output="$signer_outputs/final-assets"
final_log="$work/finalize.stderr"
final_readback="$(invoke_launcher "$final_output" "$final_log" finalize \
    --phase-a "$phase_a" --output "$final_output" --release-version 1.0.0 \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" \
    --snapshot-sha256 "$snapshot_hash" \
    --minimal-run "$qemu_root/${scenarios[0]}" --stock-run "$qemu_root/${scenarios[1]}" \
    --marble-run "$qemu_root/${scenarios[2]}")"
require_line_once "$final_readback" "offline release finalization completed: ${final_output}"
expected_final="${expected_phase_a}"$'\narch-linux-acceptance-1.0.0.json\narch-linux-acceptance-1.0.0.json.sig\narch-linux-acceptance-evidence-1.0.0.tar.zst\narch-linux-acceptance-evidence-1.0.0.tar.zst.sig'
expected_final="$(printf '%s\n' "$expected_final" | LC_ALL=C /usr/bin/sort)"
actual_final="$(/usr/bin/find "$final_output" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C /usr/bin/sort)"
[ "$actual_final" = "$expected_final" ] && [ "$(printf '%s\n' "$actual_final" | /usr/bin/wc -l)" -eq 18 ] ||
    fail 'finalize launcher output is not exact 18'
while IFS= read -r phase_file; do
    /usr/bin/cmp --silent -- "$phase_a/$phase_file" "$final_output/$phase_file" ||
        fail "finalize changed Phase-A byte: ${phase_file}"
done <<<"$expected_phase_a"
/usr/bin/bash "$fixture_source/repository/verify-release-assets.sh" "$final_output" --finalized \
    --release-version 1.0.0 --source-commit "$fixture_commit" --source-tree "$fixture_tree" \
    --source-tree-sha256 "$fixture_tree_sha256" --build-metadata-sha256 "$build_hash" \
    --unsigned-manifest-sha256 "$unsigned_hash" >/dev/null

# A third real launcher run is killed only after its namespace-local gpg-agent is observed. The
# launcher's parent-death signal and unshare --kill-child boundary must remove the namespace init,
# signer and agent without relying on the normal EXIT cleanup path.
death_fifo="$work/supervisor-death.fifo"
death_output="$signer_outputs/death-snapshot"
death_stdout="$work/supervisor-death.stdout"
death_stderr="$work/supervisor-death.stderr"
watch_result="$work/supervisor-death.agent"
/usr/bin/mkfifo -- "$death_fifo"
/usr/bin/env -i "$fixture_launcher" snapshot \
    --unsigned "$unsigned" --installer "$fixture_sealed/arch-linux-installer.sh" \
    --output "$death_output" --release-version 1.0.0 \
    --build-metadata-sha256 "$build_hash" --unsigned-manifest-sha256 "$unsigned_hash" \
    10<"$ambient" <"$death_fifo" >"$death_stdout" 2>"$death_stderr" &
supervisor_pid=$!
supervisor_start="$(/usr/bin/awk '{print $22; exit}' "/proc/${supervisor_pid}/stat")"
if ! [[ "$supervisor_pid" =~ ^[1-9][0-9]*$ ]] ||
    ! [[ "$supervisor_start" =~ ^[1-9][0-9]*$ ]] ||
    ! process_identity_is_live "$supervisor_pid" "$supervisor_start"; then
    fail 'signer supervisor identity could not be captured'
fi
(
    for attempt in {1..2000}; do
        process_identity_is_live "$supervisor_pid" "$supervisor_start" || exit 1
        for process_status in /proc/[1-9]*/status; do
            [ -r "$process_status" ] || continue
            process_dir="${process_status%/status}"
            [ -r "$process_dir/comm" ] && [ -r "$process_dir/stat" ] || continue
            IFS= read -r process_comm <"$process_dir/comm" || continue
            [ "$process_comm" = gpg-agent ] || continue
            process_uid="$(/usr/bin/awk '/^Uid:/ {print $2; exit}' "$process_status")"
            [ "$process_uid" = "$signing_uid" ] || continue
            agent_pid="${process_dir##*/}"
            agent_start="$(/usr/bin/awk '{print $22; exit}' "$process_dir/stat")"
            printf '%s %s\n' "$agent_pid" "$agent_start"
            process_identity_is_live "$supervisor_pid" "$supervisor_start" || exit 1
            /usr/bin/kill -KILL -- "$supervisor_pid"
            exit 0
        done
        /usr/bin/sleep 0.005
    done
    exit 1
) >"$watch_result" &
watcher_pid=$!
watcher_start="$(/usr/bin/awk '{print $22; exit}' "/proc/${watcher_pid}/stat")"
if ! [[ "$watcher_pid" =~ ^[1-9][0-9]*$ ]] ||
    ! [[ "$watcher_start" =~ ^[1-9][0-9]*$ ]] ||
    ! process_identity_is_live "$watcher_pid" "$watcher_start"; then
    fail 'signer watcher identity could not be captured'
fi
printf '%s\n%s\n' "$signing_home" "$passphrase_file" >"$death_fifo"
set +e
wait "$supervisor_pid"
death_status=$?
set -e
supervisor_pid=''
supervisor_start=''
if ! wait "$watcher_pid"; then
    watcher_pid=''
    watcher_start=''
    fail 'could not observe the namespace-local agent before supervisor completion'
fi
watcher_pid=''
watcher_start=''
assert_real_failure "$death_status" 'intentional signer supervisor death'
read -r killed_agent_pid killed_agent_start <"$watch_result"
[[ "$killed_agent_pid" =~ ^[1-9][0-9]*$ ]] && [[ "$killed_agent_start" =~ ^[1-9][0-9]*$ ]] ||
    fail 'supervisor-death agent identity is malformed'
for ((attempt = 0; attempt < 200; attempt++)); do
    if ! process_identity_is_live "$killed_agent_pid" "$killed_agent_start" &&
        [ -z "$(uid_processes "$signing_uid")" ]; then
        break
    fi
    /usr/bin/sleep 0.05
done
! process_identity_is_live "$killed_agent_pid" "$killed_agent_start" ||
    fail 'namespace-local signing agent survived supervisor death'
[ -z "$(uid_processes "$signing_uid")" ] || fail 'signer descendant survived supervisor death'
[ -z "$(/usr/bin/find "$signing_home" -type s -print -quit)" ] ||
    fail 'signer socket escaped the private namespace after supervisor death'
if /usr/bin/grep -Fq -- "$signing_home" "$death_stdout" "$death_stderr" ||
    /usr/bin/grep -Fq -- "$passphrase_file" "$death_stdout" "$death_stderr"; then
    fail 'private input pathname escaped during supervisor-death fixture'
fi
account_unchanged || fail 'publication integration changed the dedicated account'
final_commit="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" rev-parse --verify 'HEAD^{commit}')"
final_tree="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" rev-parse --verify 'HEAD^{tree}')"
final_source_sha256="$(canonical_source_sha256 "$repo_root")"
final_status="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" status \
    --porcelain=v1 --untracked-files=all)"
final_ignored="$(/usr/bin/git -c safe.directory="$repo_root" -C "$repo_root" clean -ndX)"
if [ "$final_commit" != "$commit" ] || [ "$final_tree" != "$tree" ] ||
    [ "$final_source_sha256" != "$source_tree_sha256" ] || [ -n "$final_status" ] ||
    [ -n "$final_ignored" ]; then
    printf 'publication root check: source custody commit=%s tree=%s bytes=%s status=%s ignored=%s\n' \
        "$([ "$final_commit" = "$commit" ] && printf same || printf changed)" \
        "$([ "$final_tree" = "$tree" ] && printf same || printf changed)" \
        "$([ "$final_source_sha256" = "$source_tree_sha256" ] && printf same || printf changed)" \
        "$([ -z "$final_status" ] && printf clean || printf changed)" \
        "$([ -z "$final_ignored" ] && printf clean || printf changed)" >&2
    if [ -n "$final_ignored" ]; then
        printf '%s\n' "$final_ignored" >&2
    fi
    fail 'accepted source changed during publication integration'
fi
[ "$(/usr/bin/sha256sum --binary -- "$bootstrap/sealer" | /usr/bin/awk '{print $1}')" = "$sealer_hash" ] ||
    fail 'pinned sealer changed during publication integration'

printf 'PUBLICATION_ROOT_CHECK_RESULT schema=1 closure=sealed snapshot_assets=14 final_assets=18 fifo=passed memfd=passed namespaces=4 pid1=passed agent=passed supervisor_death=passed signer=passed deferred=none\n'
