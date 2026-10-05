#!/usr/bin/env bash

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$(cd "$repo/.." && pwd)/geodesy-d}"
dc="${DC:-ldc2}"
objdump_tool="${OBJDUMP:-objdump}"
nm_tool="${NM:-nm}"

if [[ ! -r "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d" ]]; then
    echo "error: geodesy-d checkout not found at $geodesy_repo" >&2
    echo "       set GEODESY_D_REPO to the production checkout" >&2
    exit 2
fi

for tool in "$dc" "$objdump_tool" "$nm_tool"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

probe="$repo/research/m2-geodesic-output-specialization/source/codegen_probe.d"
object="$tmp/geodesic-output-specialization.o"

echo '=== geodesic output specialization codegen ==='
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'branch:           %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:         %s\n' "$("$dc" --version | sed -n '1p')"

"$dc"     -c     -release     -O3     -enable-inlining     -I"$geodesy_repo/source"     "$probe"     "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d"     "$geodesy_repo/source/geodesy/internal/geodesic_series.d"     -of="$object"

echo
echo '=== wrapper symbol sizes ==='
"$nm_tool"     --print-size     --size-sort     --radix=d     "$object" |
    grep 'probe_geodesic_length_' || true

echo
echo '=== wrapper assembly ==='
"$objdump_tool"     -d     --demangle     "$object" |
    sed -n         '/<probe_geodesic_length_distance>/,/<probe_geodesic_length_reduced>/p;
         /<probe_geodesic_length_reduced>/,/<probe_geodesic_length_scales>/p;
         /<probe_geodesic_length_scales>/,/<probe_geodesic_length_full>/p;
         /<probe_geodesic_length_full>/,$p'
