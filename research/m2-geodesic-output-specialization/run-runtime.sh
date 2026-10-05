#!/usr/bin/env bash

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$(cd "$repo/.." && pwd)/geodesy-d}"
dc="${DC:-ldc2}"

if [[ ! -r "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d" ]]; then
    echo "error: geodesy-d checkout not found at $geodesy_repo" >&2
    exit 2
fi

command -v "$dc" >/dev/null 2>&1 || {
    echo "error: required compiler '$dc' not found" >&2
    exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

probe="$repo/research/m2-geodesic-output-specialization/source/codegen_probe.d"
bench="$repo/research/m2-geodesic-output-specialization/source/runtime_probe.d"
binary="$tmp/geodesic-output-specialization-runtime"

echo '=== geodesic output specialization runtime environment ==='
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'branch:           %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:         %s\n' "$("$dc" --version | sed -n '1p')"

"$dc"     -release     -O3     -enable-inlining     -mcpu=native     -I"$geodesy_repo/source"     "$bench"     "$probe"     "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d"     "$geodesy_repo/source/geodesy/internal/geodesic_series.d"     -of="$binary"

"$binary"
