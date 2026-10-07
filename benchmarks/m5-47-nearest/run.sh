#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO to the #47 candidate checkout}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:?set GEOGRAPHICLIB_ROOT to GeographicLib 2.7 install}"
dc="${DC:-ldc2}"
cxx="${CXX:-g++}"
cpu="${M5_47_CPU:-2}"
runs="${M5_47_RUNS:-12}"

for tool in "$dc" "$cxx" taskset awk sort find; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapfile -t geodesy_sources < <(
    find "$geodesy_repo/source/geodesy" -type f -name '*.d' -print | sort
)

"$dc"     -release     -O3     -enable-inlining     -mcpu=native     -I"$geodesy_repo/source"     "$root/benchmarks/m5-47-nearest/source/geodesy_benchmark.d"     "${geodesy_sources[@]}"     -of="$tmp/geodesy-bench"

"$cxx"     -O3     -march=native     -DNDEBUG     -std=c++17     -I"$geographiclib_root/include"     "$root/benchmarks/m5-47-nearest/source/geographiclib_benchmark.cpp"     -L"$geographiclib_root/lib"     -lGeographicLib     -o "$tmp/geographiclib-bench"

median_file() {
    sort -n "$1" |
        awk '
            {v[NR]=$1}
            END {
                if (NR == 0) exit 1
                print v[int(NR/2)+1]
            }
        '
}

run_one() {
    local label="$1"
    local binary="$2"
    local values="$tmp/$label.values"

    : > "$values"
    echo "=== $label ==="

    for ((i=1; i<=runs; ++i)); do
        output="$(
            LD_LIBRARY_PATH="$geographiclib_root/lib:${LD_LIBRARY_PATH:-}"             taskset -c "$cpu" "$binary"
        )"

        value="$(awk -F= '/^ns_per_op=/ {print $2}' <<<"$output")"
        checksum="$(awk -F= '/^checksum=/ {print $2}' <<<"$output")"

        [[ -n "$value" ]] || {
            echo "error: missing ns_per_op from $label" >&2
            exit 4
        }

        printf '%2d  %12.6f ns/op checksum=%s\n' "$i" "$value" "$checksum"
        printf '%s\n' "$value" >> "$values"
    done

    median_file "$values"
}

echo '=== M5 #47 nearest-point performance ==='
printf 'research commit:  %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'D compiler:       %s\n' "$("$dc" --version | sed -n '1p')"
printf 'C++ compiler:     %s\n' "$("$cxx" --version | sed -n '1p')"
printf 'CPU affinity:     logical CPU %s\n' "$cpu"
printf 'process runs:     %s\n' "$runs"

d_median="$(run_one geodesy-d "$tmp/geodesy-bench" | tee /dev/stderr | tail -n 1)"
cpp_median="$(run_one GeographicLib "$tmp/geographiclib-bench" | tee /dev/stderr | tail -n 1)"

ratio="$(
    awk -v d="$d_median" -v c="$cpp_median" '
        BEGIN { printf "%.6f", d / c }
    '
)"

delta="$(
    awk -v d="$d_median" -v c="$cpp_median" '
        BEGIN { printf "%.4f", (d / c - 1.0) * 100.0 }
    '
)"

echo
echo '=== summary ==='
printf 'geodesy_d_process_median_ns_per_op=%s\n' "$d_median"
printf 'geographiclib_process_median_ns_per_op=%s\n' "$cpp_median"
printf 'geodesy_over_geographiclib_ratio=%s\n' "$ratio"
printf 'geodesy_delta_pct=%s\n' "$delta"
