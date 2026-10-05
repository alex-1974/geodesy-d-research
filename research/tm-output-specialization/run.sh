#!/usr/bin/env bash
set -euo pipefail

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
dc="${DC:-ldc2}"
cpu="${TM_OUTPUT_CPU:-2}"
runs="${TM_OUTPUT_RUNS:-3}"

command -v "$dc" >/dev/null
command -v taskset >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

app="$repo/research/tm-output-specialization/source/app.d"
binary="$tmp/tm-output-specialization"

echo '=== TM output specialization environment ==='
printf 'commit:   %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'branch:   %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler: %s\n' "$("$dc" --version | sed -n '1p')"

"$dc" \
    -release \
    -O3 \
    -enable-inlining \
    -mcpu=native \
    -i \
    -I"$geodesy_repo/source" \
    "$app" \
    -of="$binary"

for ((run = 1; run <= runs; ++run)); do
    echo
    echo "=== process run $run/$runs ==="
    taskset -c "$cpu" "$binary"
done
