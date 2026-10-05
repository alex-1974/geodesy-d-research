#!/usr/bin/env bash
set -euo pipefail

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$(cd "$repo/.." && pwd)/geodesy-d}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT to a GeographicLib 2.7 install prefix}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bridge="$repo/research/m2-geodesic-output-specialization/source/area_reference_bridge.cpp"
probe="$repo/research/m2-geodesic-output-specialization/source/area_validation.d"
bridge_o="$tmp/area_reference_bridge.o"
binary="$tmp/geodesic-area-validation"

"$cxx" \
    -O2 \
    -std=c++17 \
    -I"$geographiclib_root/include" \
    -c "$bridge" \
    -o "$bridge_o"

"$dc" \
    -release \
    -O2 \
    -i \
    -I"$geodesy_repo/source" \
    "$probe" \
    "$bridge_o" \
    -L-L"$geographiclib_root/lib" \
    -L-lGeographicLib \
    -L-lstdc++ \
    -of="$binary"

LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}" \
    "$binary"
