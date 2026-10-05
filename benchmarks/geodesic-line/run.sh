#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO to the geodesy-d checkout}"
dc="${DC:-ldc2}"
cpu="${GEODESIC_LINE_CPU:-2}"
process_runs="${GEODESIC_LINE_RUNS:-12}"

for tool in "$dc" taskset awk sort lscpu; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bench="$root/benchmarks/geodesic-line/source/app.d"
binary="$tmp/geodesic-line-benchmark"

mapfile -t geodesy_sources < <(
    find "$geodesy_repo/source/geodesy"         -type f         -name '*.d'         -print |
    sort
)

flags=(
    -release
    -O3
    -enable-inlining
    -mcpu=native
)

echo '=== geodesic line repeated-position benchmark ==='
printf 'research commit:    %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'geodesy-d commit:   %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'geodesy-d branch:   %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:           %s\n' "$("$dc" --version | sed -n '1p')"
printf 'CPU:                %s\n' "$(LC_ALL=C lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
printf 'CPU affinity:       logical CPU %s\n' "$cpu"
printf 'flags:              %s\n' "${flags[*]}"
printf 'process runs/mode:  %s\n' "$process_runs"

"$dc"     "${flags[@]}"     -I"$geodesy_repo/source"     "$bench"     "${geodesy_sources[@]}"     -of="$binary"

if [[ "${GEODESIC_LINE_BUILD_ONLY:-0}" == 1 ]]; then
    echo 'build: PASS'
    exit 0
fi

median_file() {
    local file="$1"
    sort -n "$file"         | awk '
            {v[NR]=$1}
            END {
                if (NR == 0) exit 1
                print v[int(NR/2)+1]
            }
          '
}

for mode in direct line; do
    values="$tmp/$mode.values"
    : > "$values"

    echo
    echo "=== $mode ==="

    for ((run=1; run<=process_runs; ++run)); do
        output="$(
            taskset -c "$cpu" "$binary" "$mode"
        )"

        value="$(
            awk -F= '/^median_ns_per_op=/ {print $2}' <<<"$output"
        )"

        [[ -n "$value" ]] || {
            echo "error: no median produced for $mode run $run" >&2
            exit 4
        }

        printf '%2d  %12.6f ns/op\n' "$run" "$value"
        printf '%s\n' "$value" >> "$values"
    done

    median="$(median_file "$values")"
    printf 'process_median_ns_per_op=%s\n' "$median"
done
