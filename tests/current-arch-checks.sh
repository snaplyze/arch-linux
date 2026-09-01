#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ ! -f /etc/arch-release ] || ! command -v makepkg >/dev/null 2>&1; then
    printf 'NOT_RUN_ENVIRONMENT: current Arch package environment is unavailable\n'
    exit 77
fi
python3 "$repo_root/repository/verify-package-metadata.py"
while IFS= read -r package || [ -n "$package" ]; do
    bash "$repo_root/repository/validate-package-sources.sh" --regenerate "$repo_root/packages/$package"
done <"$repo_root/repository/package-set"
printf 'current Arch source checks passed\n'
