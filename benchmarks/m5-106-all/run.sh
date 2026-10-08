#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"
cpu="${M5_106_CPU:-2}"
runs="${M5_106_RUNS:-12}"
rounds="${M5_106_ROUNDS:-8}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$dc" -release -O3 -enable-inlining -mcpu=native -i \
  -I"$geodesy_repo/source" \
  "$root/benchmarks/m5-106-all/source/geodesy_benchmark.d" \
  -of="$tmp/d-bench"

"$cxx" -O3 -march=native -DNDEBUG -std=c++17 \
  -I"$geographiclib_root/include" \
  "$root/benchmarks/m5-106-all/source/geographiclib_benchmark.cpp" \
  -L"$geographiclib_root/lib" \
  -lGeographicLib \
  -o "$tmp/cpp-bench"

median_file() {
  sort -n "$1" | awk '{v[NR]=$1} END {if(NR==0) exit 1; print v[int(NR/2)+1]}'
}

run_one() {
  local label="$1"
  local binary="$2"
  local values="$tmp/$label.values"
  : > "$values"

  echo "=== $label ==="

  for ((i=1;i<=runs;++i)); do
    output="$(
      LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}" \
      taskset -c "$cpu" "$binary" "$rounds"
    )"

    value="$(awk -F= '/^exact_ns_per_query=/ {print $2}' <<<"$output")"
    checksum="$(awk -F= '/^checksum=/ {print $2}' <<<"$output")"

    printf '%2d  %14.6f ns/query checksum=%s\n' \
      "$i" "$value" "$checksum"

    if [[ "$i" -eq 1 ]]; then
      awk '/^(shape\.|case\.|count_ns_per_query=|truncated_ns_per_query=|exact_ns_per_result=|exact_ns_per_tile=|total_results=|total_tiles=)/ {print}' <<<"$output"
    fi

    printf '%s\n' "$value" >> "$values"

    if [[ "$label" == "geodesy-d" ]]; then
      awk -F= '/^count_ns_per_query=/ {print $2}' <<<"$output" >> "$tmp/d.count.values"
      awk -F= '/^truncated_ns_per_query=/ {print $2}' <<<"$output" >> "$tmp/d.truncated.values"
      awk -F= '/^exact_ns_per_result=/ {print $2}' <<<"$output" >> "$tmp/d.result.values"
      awk -F= '/^exact_ns_per_tile=/ {print $2}' <<<"$output" >> "$tmp/d.tile.values"
    else
      awk -F= '/^exact_ns_per_result=/ {print $2}' <<<"$output" >> "$tmp/cpp.result.values"
    fi
  done

  median_file "$values"
}

echo "=== M5 #106 all-intersection performance/scaling ==="
printf 'research commit:  %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'D compiler:       %s\n' "$("$dc" --version | sed -n '1p')"
printf 'C++ compiler:     %s\n' "$("$cxx" --version | sed -n '1p')"
printf 'CPU affinity:     logical CPU %s\n' "$cpu"
printf 'process runs:     %s\n' "$runs"
printf 'rounds/case:      %s\n' "$rounds"

: > "$tmp/d.count.values"
: > "$tmp/d.truncated.values"
: > "$tmp/d.result.values"
: > "$tmp/d.tile.values"
: > "$tmp/cpp.result.values"

dmedian="$(run_one geodesy-d "$tmp/d-bench" | tee /dev/stderr | tail -n1)"
cmedian="$(run_one GeographicLib "$tmp/cpp-bench" | tee /dev/stderr | tail -n1)"

dcount="$(median_file "$tmp/d.count.values")"
dtrunc="$(median_file "$tmp/d.truncated.values")"
dresult="$(median_file "$tmp/d.result.values")"
dtile="$(median_file "$tmp/d.tile.values")"
cresult="$(median_file "$tmp/cpp.result.values")"

ratio="$(awk -v d="$dmedian" -v c="$cmedian" 'BEGIN{printf "%.6f",d/c}')"
delta="$(awk -v d="$dmedian" -v c="$cmedian" 'BEGIN{printf "%.4f",(d/c-1)*100}')"

echo
echo "=== summary ==="
printf 'geodesy_d_exact_process_median_ns_per_query=%s\n' "$dmedian"
printf 'geodesy_d_count_process_median_ns_per_query=%s\n' "$dcount"
printf 'geodesy_d_truncated_process_median_ns_per_query=%s\n' "$dtrunc"
printf 'geodesy_d_exact_process_median_ns_per_result=%s\n' "$dresult"
printf 'geodesy_d_exact_process_median_ns_per_tile=%s\n' "$dtile"
printf 'geographiclib_process_median_ns_per_query=%s\n' "$cmedian"
printf 'geographiclib_process_median_ns_per_result=%s\n' "$cresult"
printf 'geodesy_over_geographiclib_ratio=%s\n' "$ratio"
printf 'geodesy_delta_pct=%s\n' "$delta"
