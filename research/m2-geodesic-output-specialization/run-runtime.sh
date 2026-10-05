#!/usr/bin/env bash
set -e

repo="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$(cd "$repo/.." && pwd)/geodesy-d}"
dc="${DC:-ldc2}"
cpu="${GEODESIC_OUTPUT_CPU:-2}"
runs="${GEODESIC_OUTPUT_RUNS:-7}"

if [[ ! -r "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d" ]]; then
    echo "error: geodesy-d checkout not found at $geodesy_repo" >&2
    exit 2
fi

for tool in "$dc" taskset lscpu; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

[[ "$runs" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: GEODESIC_OUTPUT_RUNS must be a positive integer" >&2
    exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

probe="$repo/research/m2-geodesic-output-specialization/source/codegen_probe.d"
bench="$repo/research/m2-geodesic-output-specialization/source/runtime_probe.d"
binary="$tmp/geodesic-output-specialization-runtime"

echo '=== geodesic output specialization runtime environment ==='
printf 'geodesy-d commit: %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'branch:           %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:         %s\n' "$("$dc" --version | sed -n '1p')"

cpu_model="$(
    LC_ALL=C lscpu |
        awk -F: '/Model name/ {
            gsub(/^[ \t]+/, "", $2)
            print $2
            exit
        }'
)"

printf 'CPU:              %s\n' "$cpu_model"
printf 'kernel:           %s\n' "$(uname -srmo)"
printf 'CPU affinity:     logical CPU %s\n' "$cpu"

governor="$(
    cat "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" 2>/dev/null ||
    echo unavailable
)"

scaling_min="$(
    cat "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_min_freq" 2>/dev/null ||
    echo unavailable
)"

scaling_max="$(
    cat "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq" 2>/dev/null ||
    echo unavailable
)"

no_turbo="$(
    cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null ||
    echo unavailable
)"

thread_siblings="$(
    cat "/sys/devices/system/cpu/cpu${cpu}/topology/thread_siblings_list" 2>/dev/null ||
    echo unavailable
)"

printf 'governor:         %s\n' "$governor"
printf 'scaling min kHz:  %s\n' "$scaling_min"
printf 'scaling max kHz:  %s\n' "$scaling_max"
printf 'intel no_turbo:   %s\n' "$no_turbo"
printf 'thread siblings:  %s\n' "$thread_siblings"

"$dc"     -release     -O3     -enable-inlining     -mcpu=native     -I"$geodesy_repo/source"     "$bench"     "$probe"     "$geodesy_repo/source/geodesy/internal/geodesic_lengths.d"     "$geodesy_repo/source/geodesy/internal/geodesic_series.d"     -of=for ((run = 1; run <= runs; ++run)); do
    echo
    echo "=== process run $run/$runs on logical CPU $cpu ==="
    taskset -c "$cpu" "$binary"
done

"$binary"
