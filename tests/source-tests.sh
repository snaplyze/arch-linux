#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$repo_root"

mapfile -d '' shell_files < <(find . -type f -name '*.sh' -print0 | sort -z)
mapfile -d '' package_shell < <(find packages -type f \( -name PKGBUILD -o -name '*.install' -o -name update-compatibility \) -print0 | sort -z)
for file in "${shell_files[@]}" "${package_shell[@]}"; do bash -n -- "$file"; done
installer_version="$(bash arch-linux-installer.sh --version)"
[[ "$installer_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

bash tests/bootstrap-checks.sh
bash tests/static-checks.sh
bash tests/function-checks.sh
python3 tests/installer-boundary-checks.py
python3 tests/desktop-package-checks.py
python3 tests/installation-remediation-checks.py
python3 tests/volatile-fstab-checks.py
python3 tests/retained-multilib-checks.py
bash tests/vm/harness-checks.sh
python3 tests/vm/runtime-checks.py
python3 tests/vm/gnome51-input-checks.py
python3 tests/vm/desktop-functional-checks.py
python3 tests/vm/desktop-input-checks.py
python3 tests/vm/desktop-receipt-checks.py
timeout 60 gjs -m tests/vm/desktop-extension-observer-checks.js
timeout 60 env GIO_USE_VFS=local gjs -m tests/vm/desktop-service-runner-checks.js
timeout 60 env GIO_USE_VFS=local DESKTOP_SERVICE_PROBE_PRIVATE_BUS=1 \
    dbus-run-session -- gjs -m tests/vm/desktop-service-probe-checks.js
python3 tests/extension-evidence-checks.py
python3 tests/release-source-checks.py
python3 tests/actions-release-checks.py
python3 tests/actions-signing-checks.py
bash tests/marble-checks.sh
python3 tests/colloid-migration-checks.py
python3 tests/gtk4-session-checks.py
python3 tests/extension-session-checks.py
python3 tests/profile-extension-checks.py
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
