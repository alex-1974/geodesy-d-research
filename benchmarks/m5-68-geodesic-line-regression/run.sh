#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

baseline_repo="${GEODESY_D_BASELINE_REPO:?set GEODESY_D_BASELINE_REPO}"
candidate_repo="${GEODESY_D_CANDIDATE_REPO:?set GEODESY_D_CANDIDATE_REPO}"
dc="${DC:-ldc2}"
cpu="${M5_68_CPU:-2}"
process_runs="${M5_68_RUNS:-12}"
max_regression_pct="${M5_68_MAX_REGRESSION_PCT:-3.0}"

for tool in "$dc" taskset awk sort lscpu find; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool '$tool' not found" >&2
        exit 2
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bench="$root/benchmarks/geodesic-line/source/app.d"

flags=(
    -release
    -O3
    -enable-inlining
    -mcpu=native
)

compile_one() {
    local repo="$1"
    local binary="$2"

    mapfile -t sources < <(
        find "$repo/source/geodesy" -type f -name '*.d' -print | sort
    )

    "$dc"         "${flags[@]}"         -I"$repo/source"         "$bench"         "${sources[@]}"         -of="$binary"
}

echo '=== M5 #68 GeodesicLine hot-path regression benchmark ==='
printf 'research commit:     %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'baseline commit:     %s\n' "$(git -C "$baseline_repo" rev-parse HEAD)"
printf 'candidate commit:    %s\n' "$(git -C "$candidate_repo" rev-parse HEAD)"
printf 'compiler:            %s\n' "$("$dc" --version | sed -n '1p')"
printf 'CPU:                 %s\n' "$(LC_ALL=C lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
printf 'CPU affinity:        logical CPU %s\n' "$cpu"
printf 'flags:               %s\n' "${flags[*]}"
printf 'process runs/build:  %s\n' "$process_runs"
printf 'alarm threshold:     %s%%\n' "$max_regression_pct"

baseline_binary="$tmp/baseline"
candidate_binary="$tmp/candidate"

compile_one "$baseline_repo" "$baseline_binary"
compile_one "$candidate_repo" "$candidate_binary"

if [[ "${M5_68_BUILD_ONLY:-0}" == 1 ]]; then
    echo 'build: PASS'
    exit 0
fi

median_file() {
    local file="$1"
    sort -n "$file" |
        awk '
            {v[NR]=$1}
            END {
                if (NR == 0) exit 1
                print v[int(NR/2)+1]
            }
        '
}

run_build() {
    local label="$1"
    local binary="$2"
    local values="$tmp/$label.values"

    : > "$values"

    echo
    echo "=== $label ==="

    for ((run=1; run<=process_runs; ++run)); do
        output="$(taskset -c "$cpu" "$binary" line)"
        value="$(awk -F= '/^median_ns_per_op=/ {print $2}' <<<"$output")"

        [[ -n "$value" ]] || {
            echo "error: no median produced for $label run $run" >&2
            exit 4
        }

        printf '%2d  %12.6f ns/op\n' "$run" "$value"
        printf '%s\n' "$value" >> "$values"
    done

    median_file "$values"
}

baseline_median="$(run_build baseline "$baseline_binary" | tee /dev/stderr | tail -n 1)"
candidate_median="$(run_build candidate "$candidate_binary" | tee /dev/stderr | tail -n 1)"

delta_pct="$(
    awk -v b="$baseline_median" -v c="$candidate_median" '
        BEGIN { printf "%.4f", (c / b - 1.0) * 100.0 }
    '
)"

speed_ratio="$(
    awk -v b="$baseline_median" -v c="$candidate_median" '
        BEGIN { printf "%.6f", b / c }
    '
)"

echo
echo '=== summary ==='
printf 'baseline_process_median_ns_per_op=%s\n' "$baseline_median"
printf 'candidate_process_median_ns_per_op=%s\n' "$candidate_median"
printf 'candidate_delta_pct=%s\n' "$delta_pct"
printf 'baseline_over_candidate_ratio=%s\n' "$speed_ratio"

awk -v d="$delta_pct" -v limit="$max_regression_pct" '
    BEGIN {
        if (d > limit) {
            printf "REGRESSION FAIL: %.4f%% > %.4f%% alarm threshold\n", d, limit
            exit 1
        }
        printf "REGRESSION PASS: %.4f%% <= %.4f%% alarm threshold\n", d, limit
    }
'
