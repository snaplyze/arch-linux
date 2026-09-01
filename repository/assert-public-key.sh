#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=repository/lib/common.sh
source "${script_dir}/lib/common.sh"

[ "$#" -eq 3 ] || { printf 'Usage: %s CERTIFICATE PRIMARY_FINGERPRINT SIGNING_FINGERPRINT\n' "$0" >&2; exit 2; }
repository_assert_public_certificate "$1" "$2" "$3"
printf 'public certificate checks passed\n'
