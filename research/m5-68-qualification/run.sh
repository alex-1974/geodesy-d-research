#!/usr/bin/env bash
set -euo pipefail

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bridge="$repo/research/m5-68-qualification/source/reference_bridge.cpp"
probe="$repo/research/m5-68-qualification/source/validation.d"
bridge_o="$tmp/reference_bridge.o"
binary="$tmp/m5-68-validation"

"$cxx"     -O2     -std=c++17     -I"$geographiclib_root/include"     -c "$bridge"     -o "$bridge_o"

"$dc"     -release     -O2     -i     -I"$geodesy_repo/source"     "$probe"     "$bridge_o"     -L-L"$geographiclib_root/lib"     -L-lGeographicLib     -L-lstdc++     -of="$binary"

LD_LIBRARY_PATH="$geographiclib_root:${LD_LIBRARY_PATH:-}" LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"     stdbuf -oL -eL "$binary"
