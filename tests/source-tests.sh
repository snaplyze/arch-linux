#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$repo_root"

mapfile -d '' shell_files < <(find . -type f -name '*.sh' -print0 | sort -z)
mapfile -d '' package_shell < <(find packages -type f \( -name PKGBUILD -o -name '*.install' -o -name update-compatibility \) -print0 | sort -z)
for file in "${shell_files[@]}" "${package_shell[@]}"; do bash -n -- "$file"; done
test "$(bash arch-linux-installer.sh --version)" = '1.0.1'

bash tests/bootstrap-checks.sh
bash tests/static-checks.sh
bash tests/function-checks.sh
bash tests/marble-checks.sh
bash tests/package-checks.sh
python3 tests/docs-checks.py
python3 tests/portability-checks.py
python3 tests/secret-scan.py
python3 tests/agent-contract-checks.py
python3 tests/maintenance-checks.py
bash tests/repository-checks.sh

command -v shellcheck >/dev/null 2>&1 || {
    printf 'source test failed: shellcheck is required\n' >&2
    exit 1
}
shellcheck -x -P "$repo_root" "${shell_files[@]}" "${package_shell[@]}"
printf 'all required source tests passed\n'
