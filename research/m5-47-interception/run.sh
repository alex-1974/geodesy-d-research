#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$cxx"     -O2     -std=c++17     -I"$geographiclib_root/include"     -c "$root/research/m5-47-interception/source/reference_bridge.cpp"     -o "$tmp/reference_bridge.o"

"$dc"     -release     -O     -i     -I"$geodesy_repo/source"     "$root/research/m5-47-interception/source/validation.d"     "$tmp/reference_bridge.o"     -L-L"$geographiclib_root/lib"     -L-lGeographicLib     -L-lstdc++     -of="$tmp/m5-47-interception"

LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"     "$tmp/m5-47-interception"
