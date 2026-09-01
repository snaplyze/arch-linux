#!/usr/bin/env bash

# This bootstrap is intentionally safe to run through the immutable raw tag URL. Disable tracing
# before handling paths or invoking privilege boundaries; it never accepts or handles secrets.
# The single-quoted root programs are static by design and receive data only as positional argv.
# shellcheck disable=SC2016
set +x
set -e
set -u
set -o pipefail
IFS=$' \t\n'
umask 077

readonly BOOTSTRAP_VERSION='1.0.0'
readonly BOOTSTRAP_RELEASE_URL='https://github.com/snaplyze/arch-linux/releases/download/1.0.0'
readonly BOOTSTRAP_CERTIFICATE_SHA256='2d80a88fb033a6c138399b391cd4347f4461b60d1294d22af166f589b12c7c67'
readonly BOOTSTRAP_PRIMARY_FINGERPRINT='8C78098D1EAC609CBC73536FB7D2C17447B90CB2'
readonly BOOTSTRAP_SIGNING_SUBKEY_FINGERPRINT='0AA6F2237FB9674623B6E824428D56A84F558F7C'
readonly -a BOOTSTRAP_RELEASE_FILES=(
    arch-linux-installer.sh
    arch-linux-installer.sh.sha256
    arch-linux-installer.sh.sig
    arch-linux.gpg
    primary-fingerprint
    signing-subkey-fingerprint
)

BOOTSTRAP_WORK_DIR=''
BOOTSTRAP_LAUNCH_DIR=''
BOOTSTRAP_LAUNCH_HANDED_OFF='false'
BOOTSTRAP_ACCEPTED_INSTALLER_SHA256=''

bootstrap_fail() {
    printf 'Arch Linux Installer bootstrap failed: %s\n' "$1" >&2
    exit 1
}

bootstrap_work_dir_path_is_valid() {
    [[ "$1" =~ ^/tmp/arch-linux-installer-download\.[A-Za-z0-9]{10}$ ]]
}

bootstrap_launch_dir_path_is_valid() {
    [[ "$1" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
}

bootstrap_run_as_root() (
    # env(1) clears the target command's environment. Scrub loader controls in this already-running
    # shell first as well, so direct EUID-0 execution cannot preload code into env(1) itself.
    unset BASH_ENV ENV GNUPGHOME GPG_AGENT_INFO GPG_TTY LD_AUDIT LD_LIBRARY_PATH LD_PRELOAD
    if [ "$EUID" -eq 0 ]; then
        exec /usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin "$@"
    else
        exec /usr/bin/sudo -- /usr/bin/env -i \
            HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin "$@"
    fi
)

bootstrap_cleanup_work_dir() {
    local metadata

    [ -n "$BOOTSTRAP_WORK_DIR" ] || return 0
    bootstrap_work_dir_path_is_valid "$BOOTSTRAP_WORK_DIR" || return 1
    if [ ! -e "$BOOTSTRAP_WORK_DIR" ]; then
        BOOTSTRAP_WORK_DIR=''
        return 0
    fi
    [ -d "$BOOTSTRAP_WORK_DIR" ] && [ ! -L "$BOOTSTRAP_WORK_DIR" ] || return 1
    metadata="$(/usr/bin/stat -Lc '%u:%a' -- "$BOOTSTRAP_WORK_DIR")" || return 1
    [ "$metadata" = "${EUID}:700" ] || return 1
    /usr/bin/find "$BOOTSTRAP_WORK_DIR" -xdev -depth -delete || return 1
    [ ! -e "$BOOTSTRAP_WORK_DIR" ] || return 1
    BOOTSTRAP_WORK_DIR=''
}

bootstrap_cleanup_launch_dir() {
    local launch_dir

    [ "$BOOTSTRAP_LAUNCH_HANDED_OFF" = 'false' ] || return 0
    [ -n "$BOOTSTRAP_LAUNCH_DIR" ] || return 0
    launch_dir="$BOOTSTRAP_LAUNCH_DIR"
    bootstrap_launch_dir_path_is_valid "$launch_dir" || return 1
    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        dir="$1"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        if [ ! -e "${dir}" ]; then
            exit 0
        fi
        [ -d "${dir}" ] && [ ! -L "${dir}" ]
        metadata="$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")"
        [ "${metadata}" = "0:0:700" ] || [ "${metadata}" = "0:0:755" ]
        if [ -d "${dir}/.verification" ] && [ ! -L "${dir}/.verification" ]; then
            /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin \
                GNUPGHOME="${dir}/.verification" /usr/bin/gpgconf --kill all >/dev/null 2>&1
        fi
        /usr/bin/find "${dir}" -xdev -depth -delete
        [ ! -e "${dir}" ]
    ' _ "$launch_dir" || return 1
    BOOTSTRAP_LAUNCH_DIR=''
}

bootstrap_cleanup() {
    local status=$?
    local cleanup_failed='false'

    trap - EXIT HUP INT TERM
    set +e
    bootstrap_cleanup_work_dir || cleanup_failed='true'
    bootstrap_cleanup_launch_dir || cleanup_failed='true'
    if [ "$cleanup_failed" = 'true' ]; then
        printf '%s\n' 'Arch Linux Installer bootstrap cleanup failed; inspect the private staging directories.' >&2
        status=1
    fi
    exit "$status"
}

bootstrap_asset_size_limit() {
    case "$1" in
        arch-linux-installer.sh | arch-linux.gpg)
            printf '%s\n' 1048576
            ;;
        arch-linux-installer.sh.sha256 | primary-fingerprint | signing-subkey-fingerprint)
            printf '%s\n' 1024
            ;;
        arch-linux-installer.sh.sig)
            printf '%s\n' 65536
            ;;
        *)
            return 1
            ;;
    esac
}

bootstrap_download_asset() {
    local name="$1"
    local destination="$2"
    local maximum_size="$3"
    local actual_size

    bootstrap_asset_size_limit "$name" >/dev/null || return 1
    [[ "$maximum_size" =~ ^[1-9][0-9]*$ ]] || return 1
    [ ! -e "$destination" ] || return 1
    /usr/bin/curl --proto '=https' --proto-redir '=https' --fail --location \
        --silent --show-error --retry 3 --connect-timeout 10 --max-time 120 \
        --max-filesize "$maximum_size" --output "$destination" -- \
        "${BOOTSTRAP_RELEASE_URL}/${name}" || return 1
    [ -f "$destination" ] && [ ! -L "$destination" ] || return 1
    actual_size="$(/usr/bin/stat -Lc '%s' -- "$destination")" || return 1
    [[ "$actual_size" =~ ^[0-9]+$ ]] || return 1
    [ "$actual_size" -gt 0 ] && [ "$actual_size" -le "$maximum_size" ] || return 1
    [ "$(/usr/bin/stat -Lc '%u:%a:%h' -- "$destination")" = "${EUID}:600:1" ]
}

bootstrap_stage_asset() {
    local source="$1"
    local name="$2"

    bootstrap_asset_size_limit "$name" >/dev/null || return 1
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    # The invoking, unprivileged shell opens source before sudo. Root consumes only stdin and never
    # follows a caller-controlled source pathname, closing the usual install(1) confused-deputy race.
    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        umask 077
        dir="$1"
        name="$2"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        case "${name}" in
            arch-linux-installer.sh | arch-linux.gpg) maximum_size=1048576 ;;
            arch-linux-installer.sh.sha256 | primary-fingerprint | \
            signing-subkey-fingerprint) maximum_size=1024 ;;
            arch-linux-installer.sh.sig) maximum_size=65536 ;;
            *) exit 1 ;;
        esac
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
        destination="${dir}/${name}"
        [ ! -e "${destination}" ] && [ ! -L "${destination}" ]
        ( set -o noclobber; /usr/bin/head -c "$((maximum_size + 1))" >"${destination}" )
        /usr/bin/chown 0:0 -- "${destination}"
        /usr/bin/chmod 0644 -- "${destination}"
        [ -f "${destination}" ] && [ ! -L "${destination}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h" -- "${destination}")" = "0:0:644:1" ]
        actual_size="$(/usr/bin/stat -Lc "%s" -- "${destination}")"
        [ "${actual_size}" -gt 0 ] && [ "${actual_size}" -le "${maximum_size}" ]
    ' _ "$BOOTSTRAP_LAUNCH_DIR" "$name" <"$source"
}

bootstrap_open_staged_snapshot() {
    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        dir="$1"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        [ -d "${dir}" ] && [ ! -L "${dir}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
        [ "$(/usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 -printf x | /usr/bin/wc -c)" -eq 6 ]
        if /usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 \
            \( ! -type f -o -links +1 -o ! -user root -o ! -group root -o ! -perm 0644 \) \
            -print -quit | /usr/bin/grep -q .; then
            exit 1
        fi
        for name in \
            arch-linux-installer.sh arch-linux-installer.sh.sha256 \
            arch-linux-installer.sh.sig arch-linux.gpg primary-fingerprint \
            signing-subkey-fingerprint; do
            [ -f "${dir}/${name}" ] && [ ! -L "${dir}/${name}" ]
        done
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
    ' _ "$BOOTSTRAP_LAUNCH_DIR"
}

bootstrap_validate_fingerprint_file() {
    local path="$1"
    local expected="$2"

    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        path="$1"
        expected="$2"
        [ -f "${path}" ] && [ ! -L "${path}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h:%s" -- "${path}")" = "0:0:644:1:41" ]
        [ "$(/usr/bin/wc -l <"${path}")" -eq 1 ]
        /usr/bin/grep -qxF -- "${expected}" "${path}"
    ' _ "$path" "$expected"
}

bootstrap_validate_installer_checksum() {
    local installer="$1"
    local checksum_file="$2"
    local checksum_record actual_digest

    checksum_record="$(bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        installer="$1"
        checksum_file="$2"
        [ -f "${installer}" ] && [ ! -L "${installer}" ]
        [ -f "${checksum_file}" ] && [ ! -L "${checksum_file}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h" -- "${installer}")" = "0:0:644:1" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h" -- "${checksum_file}")" = "0:0:644:1" ]
        [ "$(/usr/bin/wc -l <"${checksum_file}")" -eq 1 ]
        /usr/bin/cat -- "${checksum_file}"
    ' _ "$installer" "$checksum_file")" || return 1
    actual_digest="$(bootstrap_run_as_root /usr/bin/sha256sum --binary -- "$installer")" || return 1
    actual_digest="${actual_digest%% *}"
    bootstrap_accept_installer_checksum_record "$checksum_record" "$actual_digest"
}

bootstrap_accept_installer_checksum_record() {
    local checksum_record="$1"
    local actual_digest="$2"

    [[ "$checksum_record" =~ ^[a-f0-9]{64}\ \*arch-linux-installer\.sh$ ]] || return 1
    [[ "$actual_digest" =~ ^[a-f0-9]{64}$ ]] || return 1
    BOOTSTRAP_ACCEPTED_INSTALLER_SHA256="${checksum_record%% *}"
    [ "$actual_digest" = "$BOOTSTRAP_ACCEPTED_INSTALLER_SHA256" ]
}

bootstrap_certificate_metadata_matches() {
    local key_metadata="$1"
    local expected_primary="$2"
    local expected_signer="$3"
    local actual_fingerprints
    local primary_validity subkey_validity primary_caps subkey_caps
    local primary_expiry subkey_expiry

    [ "$(/usr/bin/awk -F: '$1 == "pub" { n++ } END { print n + 0 }' \
        <<<"$key_metadata")" -eq 1 ] || return 1
    [ "$(/usr/bin/awk -F: '$1 == "sub" { n++ } END { print n + 0 }' \
        <<<"$key_metadata")" -eq 1 ] || return 1
    [ "$(/usr/bin/awk -F: '$1 == "fpr" { n++ } END { print n + 0 }' \
        <<<"$key_metadata")" -eq 2 ] || return 1
    actual_fingerprints="$(/usr/bin/awk -F: '$1 == "fpr" { print toupper($10) }' \
        <<<"$key_metadata")"
    [ "$actual_fingerprints" = "$(printf '%s\n%s' "$expected_primary" "$expected_signer")" ] || \
        return 1
    [ "$(/usr/bin/awk -F: '$1 == "pub" { print $4 }' <<<"$key_metadata")" = 22 ] || return 1
    [ "$(/usr/bin/awk -F: '$1 == "sub" { print $4 }' <<<"$key_metadata")" = 22 ] || return 1
    /usr/bin/awk -F: '
        $1 == "pub" || $1 == "sub" { section++; next }
        $1 == "pkd" {
            total++
            if (section < 1 || section > 2) exit 1
            if ($2 == "0" && $3 == "80" && $4 == "092B06010401DA470F01") oid[section]++
            else if ($2 == "1" && $3 == "263" && $4 ~ /^40[0-9A-F]+$/ && length($4) == 66) point[section]++
            else exit 1
        }
        END {
            if (section != 2 || total != 4 || oid[1] != 1 || oid[2] != 1 ||
                point[1] != 1 || point[2] != 1) exit 1
        }
    ' <<<"$key_metadata" || return 1

    primary_validity="$(/usr/bin/awk -F: '$1 == "pub" { print $2 }' <<<"$key_metadata")"
    subkey_validity="$(/usr/bin/awk -F: '$1 == "sub" { print $2 }' <<<"$key_metadata")"
    [ "$primary_validity" = - ] && [ "$subkey_validity" = - ] || return 1
    primary_caps="$(/usr/bin/awk -F: '$1 == "pub" { print $12 }' <<<"$key_metadata")"
    subkey_caps="$(/usr/bin/awk -F: '$1 == "sub" { print $12 }' <<<"$key_metadata")"
    [[ "$primary_caps" =~ ^[cCS]+$ ]] && [ "${primary_caps//[A-Z]/}" = c ] || return 1
    [[ "$subkey_caps" =~ ^[sCS]+$ ]] && [ "${subkey_caps//[A-Z]/}" = s ] || return 1
    primary_expiry="$(/usr/bin/awk -F: '$1 == "pub" { print $7 }' <<<"$key_metadata")"
    subkey_expiry="$(/usr/bin/awk -F: '$1 == "sub" { print $7 }' <<<"$key_metadata")"
    [ -z "$primary_expiry" ] || [ "$primary_expiry" = 0 ] || return 1
    [[ "$subkey_expiry" =~ ^[0-9]+$ ]] && \
        [ "$subkey_expiry" -gt "$(/usr/bin/date +%s)" ] || return 1
}

bootstrap_validate_public_certificate() {
    local public_key="$1"
    local inspection_home="$2"
    local expected_sha256="$3"
    local expected_primary="$4"
    local expected_signer="$5"
    local actual_digest key_metadata secret_metadata

    [ "$inspection_home" = "${BOOTSTRAP_LAUNCH_DIR}/.verification" ] || return 1
    [ "$(bootstrap_run_as_root /usr/bin/stat -Lc '%u:%g:%a' -- "$inspection_home")" = \
        '0:0:700' ] || return 1
    actual_digest="$(bootstrap_run_as_root /usr/bin/sha256sum --binary -- "$public_key")" || \
        return 1
    [ "${actual_digest%% *}" = "$expected_sha256" ] || return 1

    key_metadata="$(bootstrap_run_as_root /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C \
        PATH=/usr/bin GNUPGHOME="$inspection_home" /usr/bin/gpg --batch --no-options \
        --with-colons --with-subkey-fingerprint --with-key-data --show-keys -- \
        "$public_key" 2>/dev/null)" || return 1
    bootstrap_certificate_metadata_matches "$key_metadata" "$expected_primary" \
        "$expected_signer" || return 1

    bootstrap_run_as_root /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin \
        GNUPGHOME="$inspection_home" /usr/bin/gpg --batch --no-options --import -- \
        "$public_key" >/dev/null 2>&1 || return 1
    secret_metadata="$(bootstrap_run_as_root /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C \
        PATH=/usr/bin GNUPGHOME="$inspection_home" /usr/bin/gpg --batch --no-options \
        --with-colons --list-secret-keys 2>/dev/null)" || return 1
    [ "$(/usr/bin/awk -F: '$1 == "sec" || $1 == "ssb" { n++ } END { print n + 0 }' \
        <<<"$secret_metadata")" -eq 0 ]
}

bootstrap_validate_installer_signature() {
    local installer="$1"
    local signature="$2"
    local inspection_home="$3"
    local expected_primary="$4"
    local expected_signer="$5"
    local status_file="$6"
    local signature_status actual_signature valid_count

    [ "$status_file" = "${BOOTSTRAP_LAUNCH_DIR}/.verification/installer-signature.status" ] || \
        return 1
    if ! bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        umask 077
        installer="$1"
        signature="$2"
        inspection_home="$3"
        status_file="$4"
        [ -f "${installer}" ] && [ ! -L "${installer}" ]
        [ -f "${signature}" ] && [ ! -L "${signature}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${inspection_home}")" = "0:0:700" ]
        [ ! -e "${status_file}" ] && [ ! -L "${status_file}" ]
        /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin \
            GNUPGHOME="${inspection_home}" /usr/bin/gpg --batch --no-options \
            --status-fd=1 --verify "${signature}" "${installer}" \
            >"${status_file}" 2>/dev/null
        [ -f "${status_file}" ] && [ ! -L "${status_file}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h" -- "${status_file}")" = "0:0:600:1" ]
    ' _ "$installer" "$signature" "$inspection_home" "$status_file"; then
        return 1
    fi
    signature_status="$(bootstrap_run_as_root /usr/bin/cat -- "$status_file")" || return 1
    if /usr/bin/grep -Eq \
        '^\[GNUPG:\] (BADSIG|ERRSIG|EXPKEYSIG|EXPSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|NO_PUBKEY)\b' \
        <<<"$signature_status"; then
        return 1
    fi
    valid_count="$(/usr/bin/grep -c '^\[GNUPG:\] VALIDSIG ' <<<"$signature_status" || :)"
    [ "$valid_count" -eq 1 ] || return 1
    actual_signature="$(/usr/bin/awk '$2 == "VALIDSIG" { print toupper($3) ":" toupper($12) }' \
        <<<"$signature_status")"
    [ "$actual_signature" = "${expected_signer}:${expected_primary}" ]
}

bootstrap_prepare_root_verification_home() {
    local inspection_home="$1"

    [ "$inspection_home" = "${BOOTSTRAP_LAUNCH_DIR}/.verification" ] || return 1
    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        umask 077
        dir="$1"
        inspection_home="$2"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        [ "${inspection_home}" = "${dir}/.verification" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
        [ "$(/usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 -printf x | /usr/bin/wc -c)" -eq 6 ]
        [ ! -e "${inspection_home}" ] && [ ! -L "${inspection_home}" ]
        /usr/bin/mkdir -m 0700 -- "${inspection_home}"
        /usr/bin/chown 0:0 -- "${inspection_home}"
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${inspection_home}")" = "0:0:700" ]
    ' _ "$BOOTSTRAP_LAUNCH_DIR" "$inspection_home"
}

bootstrap_remove_root_verification_home() {
    local inspection_home="$1"

    [ "$inspection_home" = "${BOOTSTRAP_LAUNCH_DIR}/.verification" ] || return 1
    bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        dir="$1"
        inspection_home="$2"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        [ "${inspection_home}" = "${dir}/.verification" ]
        [ -d "${inspection_home}" ] && [ ! -L "${inspection_home}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${inspection_home}")" = "0:0:700" ]
        /usr/bin/env -i HOME=/nonexistent LANG=C LC_ALL=C PATH=/usr/bin \
            GNUPGHOME="${inspection_home}" /usr/bin/gpgconf --kill all >/dev/null 2>&1
        /usr/bin/find "${inspection_home}" -xdev -depth -delete
        [ ! -e "${inspection_home}" ]
        [ "$(/usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 -printf x | /usr/bin/wc -c)" -eq 6 ]
        if /usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 \
            \( ! -type f -o -links +1 -o ! -user root -o ! -group root -o ! -perm 0644 \) \
            -print -quit | /usr/bin/grep -q .; then
            exit 1
        fi
    ' _ "$BOOTSTRAP_LAUNCH_DIR" "$inspection_home"
}

bootstrap_seal_staged_snapshot() {
    local identity

    identity="$(bootstrap_run_as_root /usr/bin/bash --noprofile --norc -c '
        set -euo pipefail
        dir="$1"
        accepted_digest="$2"
        version="$3"
        [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
        [ -d "${dir}" ] && [ ! -L "${dir}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
        [ "$(/usr/bin/find "${dir}" -mindepth 1 -maxdepth 1 -printf x | /usr/bin/wc -c)" -eq 6 ]
        installer="${dir}/arch-linux-installer.sh"
        [ -f "${installer}" ] && [ ! -L "${installer}" ]
        [ "$(/usr/bin/stat -Lc "%u:%g:%a:%h" -- "${installer}")" = "0:0:644:1" ]
        /usr/bin/grep -qxF -- "readonly VERSION='"'"'${version}'"'"'" "${installer}"
        actual_digest="$(/usr/bin/sha256sum --binary -- "${installer}")"
        [ "${actual_digest%% *}" = "${accepted_digest}" ]
        /usr/bin/chmod 0700 -- "${installer}" "${dir}"
        [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
        identity="$(/usr/bin/stat -Lc "%d:%i:%u:%g:%a:%h:%s" -- "${installer}")"
        [[ "${identity}" =~ ^[0-9]+:[0-9]+:0:0:700:1:[1-9][0-9]*$ ]]
        printf "%s\n" "${identity}"
    ' _ "$BOOTSTRAP_LAUNCH_DIR" "$BOOTSTRAP_ACCEPTED_INSTALLER_SHA256" \
        "$BOOTSTRAP_VERSION")" || return 1
    [[ "$identity" =~ ^[0-9]+:[0-9]+:0:0:700:1:[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "$identity"
}

bootstrap_launch_installer() {
    local identity="$1"
    local term_value="${TERM:-linux}"

    [[ "$term_value" =~ ^[A-Za-z0-9._+-]{1,64}$ ]] || term_value='linux'
    BOOTSTRAP_LAUNCH_HANDED_OFF='true'
    printf 'Verified installer state directory: %s\n' "$BOOTSTRAP_LAUNCH_DIR"
    bootstrap_run_as_root /usr/bin/env -i \
        HOME=/root LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/usr/bin:/usr/sbin TERM="$term_value" \
        /usr/bin/bash --noprofile --norc -c '
            set -euo pipefail
            dir="$1"
            accepted_identity="$2"
            accepted_digest="$3"
            version="$4"
            [[ "${dir}" =~ ^/run/arch-linux-installer-launch\.[A-Za-z0-9]{10}$ ]]
            [ -d "${dir}" ] && [ ! -L "${dir}" ]
            [ "$(/usr/bin/stat -Lc "%u:%g:%a" -- "${dir}")" = "0:0:700" ]
            installer="${dir}/arch-linux-installer.sh"
            [ "$(/usr/bin/stat -Lc "%d:%i:%u:%g:%a:%h:%s" -- "${installer}")" = \
                "${accepted_identity}" ]
            actual_digest="$(/usr/bin/sha256sum --binary -- "${installer}")"
            [ "${actual_digest%% *}" = "${accepted_digest}" ]
            /usr/bin/grep -qxF -- "readonly VERSION='"'"'${version}'"'"'" "${installer}"
            cd -- "${dir}"
            exec /usr/bin/bash --noprofile --norc ./arch-linux-installer.sh
        ' _ "$BOOTSTRAP_LAUNCH_DIR" "$identity" "$BOOTSTRAP_ACCEPTED_INSTALLER_SHA256" \
        "$BOOTSTRAP_VERSION" </dev/tty
}

bootstrap_complete() {
    local mode="$1"
    local staged_identity="$2"

    if [ "$mode" = 'verify-only' ]; then
        bootstrap_cleanup_launch_dir || \
            bootstrap_fail 'cannot remove the verified root-owned staging directory'
        printf 'Verified Arch Linux Installer %s: sha256 %s\n' \
            "$BOOTSTRAP_VERSION" "$BOOTSTRAP_ACCEPTED_INSTALLER_SHA256"
        return 0
    fi
    [ "$mode" = 'launch' ] || bootstrap_fail 'internal bootstrap mode is invalid'
    bootstrap_launch_installer "$staged_identity"
}

bootstrap_require_environment() {
    local mode="$1"
    local command_path

    for command_path in \
        /usr/bin/awk /usr/bin/bash /usr/bin/cat /usr/bin/chmod /usr/bin/chown \
        /usr/bin/curl /usr/bin/date /usr/bin/env /usr/bin/find /usr/bin/gpg /usr/bin/gpgconf \
        /usr/bin/grep /usr/bin/head /usr/bin/mkdir /usr/bin/mktemp /usr/bin/sha256sum \
        /usr/bin/stat /usr/bin/uname /usr/bin/wc; do
        [ -x "$command_path" ] || bootstrap_fail "required command is unavailable: ${command_path}"
    done
    [ "$(/usr/bin/uname -s)" = Linux ] && [ "$(/usr/bin/uname -m)" = x86_64 ] || \
        bootstrap_fail 'release 1.0.0 supports Linux x86_64 only'
    if [ "$mode" = 'launch' ] && ! (: </dev/tty) 2>/dev/null; then
        bootstrap_fail 'an interactive terminal is required'
    fi
    if [ "$EUID" -ne 0 ]; then
        [ -x /usr/bin/sudo ] || bootstrap_fail 'run as root or install sudo for privilege staging'
        if ! /usr/bin/sudo -n -v >/dev/null 2>&1; then
            if ! (: </dev/tty) 2>/dev/null; then
                bootstrap_fail 'non-interactive sudo authority is unavailable'
            fi
            # The caller shell opens the controlling terminal; sudo must not consume the bootstrap pipe.
            # shellcheck disable=SC2024
            /usr/bin/sudo -v </dev/tty || bootstrap_fail 'sudo authentication failed'
        fi
    fi
}

bootstrap_main() {
    local mode='launch'
    local name size_limit inspection_home status_file staged_identity

    trap bootstrap_cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    case "$#" in
        0)
            ;;
        1)
            [ "$1" = '--verify-only' ] || bootstrap_fail 'usage: install.sh [--verify-only]'
            mode='verify-only'
            ;;
        *)
            bootstrap_fail 'usage: install.sh [--verify-only]'
            ;;
    esac
    bootstrap_require_environment "$mode"

    BOOTSTRAP_WORK_DIR="$(/usr/bin/mktemp -d -- \
        /tmp/arch-linux-installer-download.XXXXXXXXXX)" || \
        bootstrap_fail 'cannot create the private download directory'
    bootstrap_work_dir_path_is_valid "$BOOTSTRAP_WORK_DIR" || \
        bootstrap_fail 'download directory path is not exact'
    [ -d "$BOOTSTRAP_WORK_DIR" ] && [ ! -L "$BOOTSTRAP_WORK_DIR" ] || \
        bootstrap_fail 'download directory is not a real directory'
    /usr/bin/chmod 0700 -- "$BOOTSTRAP_WORK_DIR"
    [ "$(/usr/bin/stat -Lc '%u:%a' -- "$BOOTSTRAP_WORK_DIR")" = "${EUID}:700" ] || \
        bootstrap_fail 'download directory ownership is unsafe'

    for name in "${BOOTSTRAP_RELEASE_FILES[@]}"; do
        size_limit="$(bootstrap_asset_size_limit "$name")" || \
            bootstrap_fail 'release asset allowlist is invalid'
        bootstrap_download_asset "$name" "$BOOTSTRAP_WORK_DIR/$name" "$size_limit" || \
            bootstrap_fail "cannot download the immutable ${name} asset"
    done

    BOOTSTRAP_LAUNCH_DIR="$(bootstrap_run_as_root /usr/bin/mktemp -d -- \
        /run/arch-linux-installer-launch.XXXXXXXXXX)" || \
        bootstrap_fail 'cannot create the root-owned installer state directory'
    bootstrap_launch_dir_path_is_valid "$BOOTSTRAP_LAUNCH_DIR" || \
        bootstrap_fail 'root-owned installer state path is not exact'
    [ "$(bootstrap_run_as_root /usr/bin/stat -Lc '%u:%g:%a' -- \
        "$BOOTSTRAP_LAUNCH_DIR")" = '0:0:700' ] || \
        bootstrap_fail 'root-owned installer state directory metadata is unsafe'

    for name in "${BOOTSTRAP_RELEASE_FILES[@]}"; do
        bootstrap_stage_asset "$BOOTSTRAP_WORK_DIR/$name" "$name" || \
            bootstrap_fail "cannot capture ${name} in the root-owned snapshot"
    done
    bootstrap_open_staged_snapshot || bootstrap_fail 'root-owned release snapshot is incomplete'

    bootstrap_validate_installer_checksum \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh" \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh.sha256" || \
        bootstrap_fail 'installer checksum verification failed'
    bootstrap_run_as_root /usr/bin/grep -qxF -- \
        "readonly VERSION='${BOOTSTRAP_VERSION}'" \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh" || \
        bootstrap_fail 'installer version does not match immutable release 1.0.0'
    bootstrap_validate_fingerprint_file "$BOOTSTRAP_LAUNCH_DIR/primary-fingerprint" \
        "$BOOTSTRAP_PRIMARY_FINGERPRINT" || bootstrap_fail 'primary fingerprint mismatch'
    bootstrap_validate_fingerprint_file "$BOOTSTRAP_LAUNCH_DIR/signing-subkey-fingerprint" \
        "$BOOTSTRAP_SIGNING_SUBKEY_FINGERPRINT" || \
        bootstrap_fail 'signing-subkey fingerprint mismatch'

    inspection_home="$BOOTSTRAP_LAUNCH_DIR/.verification"
    bootstrap_prepare_root_verification_home "$inspection_home" || \
        bootstrap_fail 'cannot create the root-owned verification home'
    bootstrap_validate_public_certificate "$BOOTSTRAP_LAUNCH_DIR/arch-linux.gpg" \
        "$inspection_home" "$BOOTSTRAP_CERTIFICATE_SHA256" \
        "$BOOTSTRAP_PRIMARY_FINGERPRINT" "$BOOTSTRAP_SIGNING_SUBKEY_FINGERPRINT" || \
        bootstrap_fail 'public certificate verification failed'
    status_file="$inspection_home/installer-signature.status"
    bootstrap_validate_installer_signature "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh" \
        "$BOOTSTRAP_LAUNCH_DIR/arch-linux-installer.sh.sig" "$inspection_home" \
        "$BOOTSTRAP_PRIMARY_FINGERPRINT" "$BOOTSTRAP_SIGNING_SUBKEY_FINGERPRINT" \
        "$status_file" || bootstrap_fail 'detached installer signature verification failed'

    bootstrap_remove_root_verification_home "$inspection_home" || \
        bootstrap_fail 'cannot remove the root-owned verification state'
    staged_identity="$(bootstrap_seal_staged_snapshot)" || \
        bootstrap_fail 'cannot seal the verified root-owned installer snapshot'
    bootstrap_cleanup_work_dir || bootstrap_fail 'cannot remove the private download directory'
    bootstrap_complete "$mode" "$staged_identity"
}

if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
    bootstrap_main "$@"
fi
