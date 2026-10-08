#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"
runs="${R69_5_RUNS:-3}"
rounds="${R69_5_ROUNDS:-2000}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp -a "$geodesy_repo/source" "$tmp/baseline-source"
python3 "$root/research/m5-69-prolate-performance-api/prepare_source.py"   "$geodesy_repo" "$tmp/candidate-source"

"$dc" -release -O3 -enable-inlining -mcpu=native -i   -I"$tmp/baseline-source"   "$root/research/m5-69-prolate-performance-api/source/benchmark.d"   -of="$tmp/baseline"

"$dc" -release -O3 -enable-inlining -mcpu=native -i   -I"$tmp/candidate-source"   "$root/research/m5-69-prolate-performance-api/source/benchmark.d"   -of="$tmp/candidate"

"$cxx" -O3 -march=native -DNDEBUG -std=c++17   -I"$geographiclib_root/include"   "$root/research/m5-69-prolate-performance-api/source/reference.cpp"   -L"$geographiclib_root/lib" -lGeographicLib   -o "$tmp/geographiclib"

for mode in direct inverse intersection_prepare; do
  python3 "$root/research/m5-69-prolate-performance-api/summarize.py"     "$tmp/baseline" "$mode" "0.0033528106647474805" "$rounds" "$runs" baseline-wgs84
  python3 "$root/research/m5-69-prolate-performance-api/summarize.py"     "$tmp/candidate" "$mode" "0.0033528106647474805" "$rounds" "$runs" candidate-wgs84
  LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"     python3 "$root/research/m5-69-prolate-performance-api/summarize.py"       "$tmp/candidate" "$mode" "-0.01" "$rounds" "$runs" candidate-prolate
  LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"     python3 "$root/research/m5-69-prolate-performance-api/summarize.py"       "$tmp/geographiclib" "$mode" "-0.01" "$rounds" "$runs" geographiclib-prolate
done
