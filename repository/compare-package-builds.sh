#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [ "$#" -ne 2 ]; then
    printf 'Usage: %s BUILD_A BUILD_B\n' "$0" >&2
    exit 2
fi
"${script_dir}/verify-unsigned-build.sh" "$1"
"${script_dir}/verify-unsigned-build.sh" "$2"
if ! cmp --silent -- "$1/UNSIGNED-SHA256SUMS" "$2/UNSIGNED-SHA256SUMS"; then
    printf 'ADVISORY_MISMATCH: package hashes differ between independent builds.\n' >&2
    diff -u -- "$1/UNSIGNED-SHA256SUMS" "$2/UNSIGNED-SHA256SUMS" || true
    exit 1
fi
if ! cmp --silent -- "$1/BUILD-METADATA.json" "$2/BUILD-METADATA.json"; then
    printf 'ADVISORY_MISMATCH: build provenance differs between independent builds.\n' >&2
    diff -u -- "$1/BUILD-METADATA.json" "$2/BUILD-METADATA.json" || true
    exit 1
fi
printf 'advisory A+B comparison passed\n'
