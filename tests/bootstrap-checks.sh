#!/usr/bin/env bash
# Literal grep patterns containing bootstrap variable names are deliberate.
# shellcheck disable=SC2016
set -e
set -u
set -o pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BOOTSTRAP="${ROOT_DIR}/install.sh"
README="${ROOT_DIR}/README.md"
INSTALLATION_DOC="${ROOT_DIR}/docs/installation.md"
TRUST_DIR="${ROOT_DIR}/repository/trust"
EXPECTED_CERTIFICATE_SHA256='2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67'
EXPECTED_PRIMARY='8C78098D1EAC609CBC73536FB7D2C17447B90CB2'
EXPECTED_SIGNER='0AA6F2237FB9674623B6E824428D56A84F558F7C'
EXPECTED_README_COMMAND="curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.0/install.sh | bash"
EXPECTED_VERIFY_COMMAND="curl -fsS https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.0/install.sh | bash -s -- --verify-only"

test_root="$(mktemp -d -- /tmp/arch-linux-bootstrap-checks.XXXXXXXXXX)"
chmod 0700 -- "$test_root"

cleanup() {
    local cleanup_failed='false'
    local gpg_home

    if declare -F bootstrap_cleanup_launch_dir >/dev/null && \
        [ -n "${BOOTSTRAP_LAUNCH_DIR:-}" ]; then
        bootstrap_cleanup_launch_dir || cleanup_failed='true'
    fi
    if declare -F bootstrap_cleanup_work_dir >/dev/null && \
        [ -n "${BOOTSTRAP_WORK_DIR:-}" ]; then
        bootstrap_cleanup_work_dir || cleanup_failed='true'
    fi
    for gpg_home in "$test_root/metadata-home" "$test_root/signing-home"; do
        if [ -d "$gpg_home" ] && [ ! -L "$gpg_home" ]; then
            GNUPGHOME="$gpg_home" gpgconf --kill all >/dev/null 2>&1 || \
                cleanup_failed='true'
        fi
    done
    find "$test_root" -xdev -depth -delete || cleanup_failed='true'
    [ "$cleanup_failed" = 'false' ] || \
        printf '%s\n' 'bootstrap check cleanup failed' >&2
}
trap cleanup EXIT

fail() {
    printf 'bootstrap check failed: %s\n' "$1" >&2
    exit 1
}

test -f "$BOOTSTRAP" || fail 'install.sh is missing'
test -f "$README" || fail 'README is missing'
test -f "$INSTALLATION_DOC" || fail 'installation documentation is missing'
bash -n "$BOOTSTRAP" || fail 'install.sh syntax'

# shellcheck disable=SC1090,SC1091
source "$BOOTSTRAP"

[ "$BOOTSTRAP_VERSION" = '1.0.0' ] || fail 'bootstrap version drifted'
[ "$BOOTSTRAP_RELEASE_URL" = \
    'https://github.com/snaplyze/arch-linux/releases/download/1.0.0' ] || \
    fail 'release URL is not immutable 1.0.0'
[ "$BOOTSTRAP_CERTIFICATE_SHA256" = "$EXPECTED_CERTIFICATE_SHA256" ] || \
    fail 'embedded certificate digest drifted'
[ "$BOOTSTRAP_PRIMARY_FINGERPRINT" = "$EXPECTED_PRIMARY" ] || \
    fail 'embedded primary fingerprint drifted'
[ "$BOOTSTRAP_SIGNING_SUBKEY_FINGERPRINT" = "$EXPECTED_SIGNER" ] || \
    fail 'embedded signing fingerprint drifted'
[ "$(sha256sum --binary -- "$TRUST_DIR/arch-linux.gpg" | awk '{ print $1 }')" = \
    "$EXPECTED_CERTIFICATE_SHA256" ] || fail 'certificate digest and bootstrap disagree'
[ "$(cat -- "$TRUST_DIR/primary-fingerprint")" = "$EXPECTED_PRIMARY" ] || \
    fail 'primary fingerprint file and bootstrap disagree'
[ "$(cat -- "$TRUST_DIR/signing-subkey-fingerprint")" = "$EXPECTED_SIGNER" ] || \
    fail 'signing fingerprint file and bootstrap disagree'

expected_assets="$(printf '%s\n' \
    arch-linux-installer.sh arch-linux-installer.sh.sha256 arch-linux-installer.sh.sig \
    arch-linux.gpg primary-fingerprint signing-subkey-fingerprint)"
actual_assets="$(printf '%s\n' "${BOOTSTRAP_RELEASE_FILES[@]}")"
[ "$actual_assets" = "$expected_assets" ] || fail 'release input closure drifted'

bootstrap_work_dir_path_is_valid '/tmp/arch-linux-installer-download.A1b2C3d4E5' || \
    fail 'exact work path was rejected'
if bootstrap_work_dir_path_is_valid '/tmp/arch-linux-installer-download.bad/path'; then
    fail 'unsafe work path was accepted'
fi
bootstrap_launch_dir_path_is_valid '/run/arch-linux-installer-launch.A1b2C3d4E5' || \
    fail 'exact launch path was rejected'
if bootstrap_launch_dir_path_is_valid '/run/arch-linux-installer-launch.A1b2C3d4E5/extra'; then
    fail 'unsafe launch path was accepted'
fi

fixture_digest="$(printf '%s' 'bootstrap checksum fixture' | sha256sum --binary | awk '{ print $1 }')"
bootstrap_accept_installer_checksum_record \
    "${fixture_digest} *arch-linux-installer.sh" "$fixture_digest" || \
    fail 'valid checksum record was rejected'
[ "$BOOTSTRAP_ACCEPTED_INSTALLER_SHA256" = "$fixture_digest" ] || \
    fail 'accepted checksum was not captured'
if bootstrap_accept_installer_checksum_record \
    "${fixture_digest}  arch-linux-installer.sh" "$fixture_digest"; then
    fail 'non-binary checksum record was accepted'
fi
wrong_fixture_digest="${fixture_digest}"
if [ "${wrong_fixture_digest:0:1}" = 0 ]; then
    wrong_fixture_digest="1${wrong_fixture_digest:1}"
else
    wrong_fixture_digest="0${wrong_fixture_digest:1}"
fi
if bootstrap_accept_installer_checksum_record \
    "${fixture_digest} *arch-linux-installer.sh" "$wrong_fixture_digest"; then
    fail 'checksum mismatch was accepted'
fi

mkdir -m 0700 -- "$test_root/metadata-home"
key_metadata="$(LC_ALL=C GNUPGHOME="$test_root/metadata-home" gpg --batch --no-options \
    --with-colons --with-subkey-fingerprint --with-key-data --show-keys -- \
    "$TRUST_DIR/arch-linux.gpg" 2>/dev/null)"
bootstrap_certificate_metadata_matches "$key_metadata" "$EXPECTED_PRIMARY" "$EXPECTED_SIGNER" || \
    fail 'canonical certificate metadata was rejected'
wrong_signer="$EXPECTED_SIGNER"
if [ "${wrong_signer:0:1}" = 0 ]; then
    wrong_signer="1${wrong_signer:1}"
else
    wrong_signer="0${wrong_signer:1}"
fi
wrong_signer_metadata="${key_metadata//$EXPECTED_SIGNER/$wrong_signer}"
if bootstrap_certificate_metadata_matches \
    "$wrong_signer_metadata" "$EXPECTED_PRIMARY" "$EXPECTED_SIGNER"; then
    fail 'wrong signing fingerprint metadata was accepted'
fi
expired_metadata="$(awk -F: -v OFS=: \
    '$1 == "sub" && !changed++ { $7 = 1 } { print }' <<<"$key_metadata")"
if bootstrap_certificate_metadata_matches \
    "$expired_metadata" "$EXPECTED_PRIMARY" "$EXPECTED_SIGNER"; then
    fail 'expired signing subkey metadata was accepted'
fi

BOOTSTRAP_WORK_DIR="$(mktemp -d -- /tmp/arch-linux-installer-download.XXXXXXXXXX)"
chmod 0700 -- "$BOOTSTRAP_WORK_DIR"
printf '%s\n' fixture >"$BOOTSTRAP_WORK_DIR/file"
bootstrap_cleanup_work_dir || fail 'narrow work cleanup failed'
[ -z "$BOOTSTRAP_WORK_DIR" ] || fail 'work cleanup retained its pathname'

root_mock_available='false'
if [ "$EUID" -eq 0 ]; then
    root_mock_available='true'
elif [ -x /usr/bin/sudo ] && /usr/bin/sudo -n -v >/dev/null 2>&1 &&
    /usr/bin/sudo -n /usr/bin/env -i HOME=/root LANG=C LC_ALL=C \
        PATH=/usr/bin:/usr/sbin /usr/bin/true >/dev/null 2>&1; then
    root_mock_available='true'
fi
if [ "$root_mock_available" = 'true' ]; then
    bootstrap_require_environment verify-only </dev/null || \
        fail 'root verification-only mode unexpectedly requires a terminal'
    poison_bash_env="$test_root/poison-bash-env"
    poison_marker="$test_root/poison-bash-env-ran"
    printf 'printf poison >%q\n' "$poison_marker" >"$poison_bash_env"
    root_environment="$(
        BASH_ENV="$poison_bash_env" ENV="$poison_bash_env" \
            GNUPGHOME="$test_root/poison-gnupg" LD_PRELOAD=/does/not/exist \
            bootstrap_run_as_root /usr/bin/env | /usr/bin/sort
    )" || fail 'clean root environment probe failed'
    BASH_ENV="$poison_bash_env" ENV="$poison_bash_env" \
        bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c : || \
        fail 'root bash environment probe failed'
    [ ! -e "$poison_marker" ] || fail 'root child evaluated poisoned BASH_ENV'
    [ "$root_environment" = $'HOME=/root\nLANG=C\nLC_ALL=C\nPATH=/usr/bin:/usr/sbin' ] || \
        fail 'root command inherited caller environment'
    head -c 2048 /dev/zero >"$test_root/oversized-checksum"
    BOOTSTRAP_LAUNCH_DIR="$(bootstrap_run_as_root /usr/bin/mktemp -d -- \
        /run/arch-linux-installer-launch.XXXXXXXXXX)"
    BOOTSTRAP_LAUNCH_HANDED_OFF='false'
    if bootstrap_stage_asset "$test_root/oversized-checksum" \
        arch-linux-installer.sh.sha256; then
        fail 'root staging accepted an oversized release input'
    fi
    bootstrap_cleanup_launch_dir || fail 'oversized-input root staging cleanup failed'

    signing_home="$test_root/signing-home"
    mkdir -m 0700 -- "$signing_home"
    GNUPGHOME="$signing_home" gpg --batch --no-options --pinentry-mode loopback \
        --passphrase '' --quick-generate-key \
        'Arch Linux Bootstrap Test <bootstrap-test.invalid>' ed25519 cert 0 \
        >/dev/null 2>&1
    mapfile -t test_fingerprints < <(GNUPGHOME="$signing_home" gpg --batch --no-options \
        --with-colons --with-subkey-fingerprint --list-keys 2>/dev/null | \
        awk -F: '$1 == "fpr" { print toupper($10) }')
    [ "${#test_fingerprints[@]}" -eq 1 ] || fail 'test primary generation drifted'
    test_primary="${test_fingerprints[0]}"
    GNUPGHOME="$signing_home" gpg --batch --no-options --pinentry-mode loopback \
        --passphrase '' --quick-add-key "$test_primary" ed25519 sign 1d \
        >/dev/null 2>&1
    mapfile -t test_fingerprints < <(GNUPGHOME="$signing_home" gpg --batch --no-options \
        --with-colons --with-subkey-fingerprint --list-keys 2>/dev/null | \
        awk -F: '$1 == "fpr" { print toupper($10) }')
    [ "${#test_fingerprints[@]}" -eq 2 ] || fail 'test signing-subkey generation drifted'
    test_signer="${test_fingerprints[1]}"

    BOOTSTRAP_WORK_DIR="$(mktemp -d -- /tmp/arch-linux-installer-download.XXXXXXXXXX)"
    chmod 0700 -- "$BOOTSTRAP_WORK_DIR"
    printf '%s\n' '#!/usr/bin/env bash' "readonly VERSION='1.0.0'" \
        >"$BOOTSTRAP_WORK_DIR/arch-linux-installer.sh"
    test_installer_digest="$(sha256sum --binary -- \
        "$BOOTSTRAP_WORK_DIR/arch-linux-installer.sh" | awk '{ print $1 }')"
    printf '%s *arch-linux-installer.sh\n' "$test_installer_digest" \
        >"$BOOTSTRAP_WORK_DIR/arch-linux-installer.sh.sha256"
    GNUPGHOME="$signing_home" gpg --batch --no-options --pinentry-mode loopback \
        --passphrase '' --local-user "${test_signer}!" --detach-sign \
        --output "$BOOTSTRAP_WORK_DIR/arch-linux-installer.sh.sig" -- \
        "$BOOTSTRAP_WORK_DIR/arch-linux-installer.sh" >/dev/null 2>&1
    GNUPGHOME="$signing_home" gpg --batch --no-options --export -- "$test_primary" \
        >"$BOOTSTRAP_WORK_DIR/arch-linux.gpg"
    printf '%s\n' "$test_primary" >"$BOOTSTRAP_WORK_DIR/primary-fingerprint"
    printf '%s\n' "$test_signer" >"$BOOTSTRAP_WORK_DIR/signing-subkey-fingerprint"
    test_certificate_digest="$(sha256sum --binary -- \
        "$BOOTSTRAP_WORK_DIR/arch-linux.gpg" | awk '{ print $1 }')"

    BOOTSTRAP_LAUNCH_DIR="$(bootstrap_run_as_root /usr/bin/mktemp -d -- \
        /run/arch-linux-installer-launch.XXXXXXXXXX)"
    BOOTSTRAP_LAUNCH_HANDED_OFF='false'
    for asset in "${BOOTSTRAP_RELEASE_FILES[@]}"; do
        bootstrap_stage_asset "$BOOTSTRAP_WORK_DIR/$asset" "$asset" || \
            fail "root mock could not stage ${asset}"
    done
    bootstrap_open_staged_snapshot || fail 'root mock snapshot closure failed'
    bootstrap_validate_installer_checksum \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh" \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh.sha256" || \
        fail 'root mock checksum verification failed'
    bootstrap_validate_fingerprint_file "$BOOTSTRAP_LAUNCH_DIR/primary-fingerprint" \
        "$test_primary" || fail 'root mock primary verification failed'
    bootstrap_validate_fingerprint_file \
        "$BOOTSTRAP_LAUNCH_DIR/signing-subkey-fingerprint" "$test_signer" || \
        fail 'root mock signer verification failed'
    root_inspection_home="$BOOTSTRAP_LAUNCH_DIR/.verification"
    bootstrap_prepare_root_verification_home "$root_inspection_home" || \
        fail 'root mock could not create verification home'
    bootstrap_validate_public_certificate "$BOOTSTRAP_LAUNCH_DIR/arch-linux.gpg" \
        "$root_inspection_home" "$test_certificate_digest" "$test_primary" "$test_signer" || \
        fail 'root mock certificate verification failed'
    bootstrap_validate_installer_signature "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh" \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh.sig" "$root_inspection_home" \
        "$test_primary" "$test_signer" \
        "$root_inspection_home/installer-signature.status" || \
        fail 'root mock signature verification failed'
    bootstrap_remove_root_verification_home "$root_inspection_home" || \
        fail 'root mock verification cleanup failed'
    root_mock_identity="$(bootstrap_seal_staged_snapshot)" || \
        fail 'root mock snapshot seal failed'
    bootstrap_cleanup_work_dir || fail 'root mock download cleanup failed'
    bootstrap_complete verify-only "$root_mock_identity" >"$test_root/root-verify-only.stdout"
    grep -qxF -- "Verified Arch Linux Installer 1.0.0: sha256 ${test_installer_digest}" \
        "$test_root/root-verify-only.stdout" || fail 'root mock verify-only output drifted'
    [ -z "$BOOTSTRAP_LAUNCH_DIR" ] || fail 'root mock retained root staging state'
fi

cleanup_called='false'
launch_called='false'
bootstrap_cleanup_launch_dir() {
    cleanup_called='true'
    BOOTSTRAP_LAUNCH_DIR=''
}
bootstrap_launch_installer() {
    launch_called='true'
}
# The sourced completion helper consumes these globals; ShellCheck cannot follow the redefinition
# of its cleanup/launch dependencies above.
# shellcheck disable=SC2034
BOOTSTRAP_LAUNCH_DIR='/run/arch-linux-installer-launch.A1b2C3d4E5'
# shellcheck disable=SC2034
BOOTSTRAP_LAUNCH_HANDED_OFF='false'
BOOTSTRAP_ACCEPTED_INSTALLER_SHA256="$fixture_digest"
bootstrap_complete verify-only 'fixture-identity' >"$test_root/verify-only.stdout"
[ "$cleanup_called" = 'true' ] || fail 'verify-only did not request root staging cleanup'
[ "$launch_called" = 'false' ] || fail 'verify-only launched the installer'
grep -qxF -- "Verified Arch Linux Installer 1.0.0: sha256 ${fixture_digest}" \
    "$test_root/verify-only.stdout" || fail 'verify-only success output drifted'

cleanup_called='false'
launch_called='false'
bootstrap_complete launch 'fixture-identity' >"$test_root/launch.stdout"
[ "$cleanup_called" = 'false' ] || fail 'launch mode removed the accepted state directory'
[ "$launch_called" = 'true' ] || fail 'launch mode did not hand off to the installer'

if bash "$BOOTSTRAP" --unsupported >"$test_root/invalid.stdout" \
    2>"$test_root/invalid.stderr"; then
    fail 'unsupported bootstrap argument was accepted'
fi
test ! -s "$test_root/invalid.stdout" || fail 'argument rejection emitted stdout'
grep -qxF -- 'Arch Linux Installer bootstrap failed: usage: install.sh [--verify-only]' \
    "$test_root/invalid.stderr" || fail 'argument rejection output drifted'
if bash -s -- --unsupported <"$BOOTSTRAP" >"$test_root/pipe-invalid.stdout" \
    2>"$test_root/pipe-invalid.stderr"; then
    fail 'piped bootstrap did not execute argument validation'
fi
test ! -s "$test_root/pipe-invalid.stdout" || fail 'piped argument rejection emitted stdout'
grep -qxF -- 'Arch Linux Installer bootstrap failed: usage: install.sh [--verify-only]' \
    "$test_root/pipe-invalid.stderr" || fail 'piped bootstrap entrypoint drifted'

[ "$(grep -Fxc -- "$EXPECTED_README_COMMAND" "$README")" -eq 1 ] || \
    fail 'README must contain exactly one short immutable bootstrap command'
[ "$(grep -Fxc -- "$EXPECTED_VERIFY_COMMAND" "$INSTALLATION_DOC")" -eq 1 ] || \
    fail 'verification-only documentation command drifted'
if grep -Eq -- 'raw\.githubusercontent\.com/snaplyze/arch-linux/(main|master)/' \
    "$BOOTSTRAP" "$README" "$INSTALLATION_DOC"; then
    fail 'mutable raw branch URL is present'
fi
if grep -F -- "$EXPECTED_README_COMMAND" "$README" | grep -Eq -- '(^| )-L|--location'; then
    fail 'raw bootstrap command permits redirects'
fi
grep -qF -- "--proto '=https' --proto-redir '=https'" "$BOOTSTRAP" || \
    fail 'release-asset downloads are not HTTPS-only across redirects'
grep -qF -- "inspection_home=\"\$BOOTSTRAP_LAUNCH_DIR/.verification\"" "$BOOTSTRAP" || \
    fail 'GnuPG verification home is not under root-owned staging'
if grep -qF -- 'inspection_home="$BOOTSTRAP_WORK_DIR' "$BOOTSTRAP" || \
    grep -qF -- 'status_file="$BOOTSTRAP_WORK_DIR' "$BOOTSTRAP"; then
    fail 'GnuPG verification state returned to the invoking-user work directory'
fi
grep -qF -- 'bootstrap_remove_root_verification_home "$inspection_home"' "$BOOTSTRAP" || \
    fail 'root-only verification state is not removed'
grep -qF -- "BADSIG|ERRSIG|EXPKEYSIG|EXPSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|NO_PUBKEY" \
    "$BOOTSTRAP" || fail 'invalid GnuPG statuses are not fail-closed'
if grep -Eq '^[[:space:]]*set[[:space:]]+-x([[:space:]]|$)' "$BOOTSTRAP"; then
    fail 'bootstrap enables xtrace'
fi

python3 -B - "$BOOTSTRAP" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
main = source[source.index("bootstrap_main() {") :]
ordered = [
    'bootstrap_prepare_root_verification_home "$inspection_home"',
    'bootstrap_validate_public_certificate "$BOOTSTRAP_LAUNCH_DIR/arch-linux.gpg"',
    'bootstrap_validate_installer_signature "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh"',
    'bootstrap_remove_root_verification_home "$inspection_home"',
    'staged_identity="$(bootstrap_seal_staged_snapshot)"',
    'bootstrap_cleanup_work_dir',
    'bootstrap_complete "$mode" "$staged_identity"',
]
positions = [main.index(item) for item in ordered]
if positions != sorted(positions) or len(set(positions)) != len(positions):
    raise SystemExit("bootstrap verification, cleanup and handoff order drifted")
PY

printf '%s\n' 'bootstrap checks passed'
