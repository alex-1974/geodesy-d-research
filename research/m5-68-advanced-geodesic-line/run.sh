#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO to the geodesy-d checkout}"
dc="${DC:-ldc2}"

for tool in "$dc" find sort; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

probe="$root/research/m5-68-advanced-geodesic-line/source/layout_probe.d"
binary="$tmp/m5-68-layout-probe"

mapfile -t geodesy_sources < <(
    find "$geodesy_repo/source/geodesy" -type f -name '*.d' -print | sort
)

echo '=== M5 #68 advanced GeodesicLine layout probe ==='
printf 'research commit:  %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'compiler:         %s\n' "$("$dc" --version | sed -n '1p')"

"$dc"     -release     -O     -I"$geodesy_repo/source"     "$probe"     "${geodesy_sources[@]}"     -of="$binary"

"$binary"
