#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
cxx="${CXX:-g++}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$cxx" -O2 -std=c++17   -I"$geographiclib_root/include"   "$root/research/m5-69-prolate-reference-corpus/source/reference.cpp"   -L"$geographiclib_root/lib"   -lGeographicLib   -o "$tmp/reference"

LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"   "$tmp/reference" | tee "$tmp/reference.tsv"

python3 "$root/research/m5-69-prolate-reference-corpus/verify.py"   < "$tmp/reference.tsv"
