#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
cxx="${CXX:-g++}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$cxx"   -O2   -std=c++17   -I"$geographiclib_root/include"   "$root/research/m5-46-segment-intersection/source/semantics.cpp"   -L"$geographiclib_root/lib"   -lGeographicLib   -o "$tmp/m5-46-semantics"

LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"   "$tmp/m5-46-semantics"
