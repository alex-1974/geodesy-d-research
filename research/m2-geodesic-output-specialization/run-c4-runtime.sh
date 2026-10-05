#!/usr/bin/env bash
set -euo pipefail

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$(cd "$repo/.." && pwd)/geodesy-d}"
dc="${DC:-ldc2}"
cpu="${GEODESIC_C4_CPU:-2}"
runs="${GEODESIC_C4_RUNS:-5}"

for tool in "$dc" taskset lscpu; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

[[ -r "$geodesy_repo/source/geodesy/internal/geodesic_area_series.d" ]] || {
    echo "error: geodesic_area_series.d not found at $geodesy_repo" >&2
    exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source_file="$repo/research/m2-geodesic-output-specialization/source/c4_runtime_probe.d"
binary="$tmp/geodesic-c4-runtime"

echo '=== geodesic C4 runtime environment ==='
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'branch:           %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:         %s\n' "$("$dc" --version | sed -n '1p')"

"$dc" \
    -release \
    -O3 \
    -enable-inlining \
    -mcpu=native \
    -I"$geodesy_repo/source" \
    "$source_file" \
    "$geodesy_repo/source/geodesy/internal/geodesic_area_series.d" \
    -of="$binary"

for ((run = 1; run <= runs; ++run)); do
    echo
    echo "=== process run $run/$runs on logical CPU $cpu ==="
    taskset -c "$cpu" "$binary"
done
