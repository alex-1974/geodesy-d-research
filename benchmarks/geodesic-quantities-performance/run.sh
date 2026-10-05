#!/usr/bin/env bash
set -euo pipefail

# Benchmark output and numeric shell utilities must use a stable decimal point
# independent of the caller's locale (e.g. de_AT/de_DE use a decimal comma).
export LC_ALL=C

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO to the geodesy-d checkout}"
dc="${DC:-ldc2}"
cpu="${GEODESIC_QUANTITIES_CPU:-2}"
process_runs="${GEODESIC_QUANTITIES_RUNS:-12}"

command -v "$dc" >/dev/null
command -v taskset >/dev/null
command -v awk >/dev/null
command -v sort >/dev/null
command -v objdump >/dev/null

[[ "$process_runs" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: GEODESIC_QUANTITIES_RUNS must be a positive integer" >&2
    exit 2
}

bench_dir="$root/benchmarks/geodesic-quantities-performance"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

binary="$tmp/geodesic-quantities-performance"
probe_o="$tmp/codegen_probe.o"

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

echo '=== geodesic quantities performance gate ==='
printf 'research commit:    %s\n' "$(git -C "$root" rev-parse HEAD)"
printf 'geodesy-d commit:   %s\n' "$(git -C "$geodesy_repo" rev-parse HEAD)"
printf 'geodesy-d branch:   %s\n' "$(git -C "$geodesy_repo" branch --show-current)"
printf 'compiler:           %s\n' "$("$dc" --version | sed -n '1p')"
printf 'CPU:                %s\n' "$(LC_ALL=C lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
printf 'CPU affinity:       logical CPU %s\n' "$cpu"
printf 'flags:              %s\n' "${flags[*]}"
printf 'process runs/mode:  %s\n' "$process_runs"

echo
echo '=== build benchmark ==='

"$dc"     "${flags[@]}"     -I"$geodesy_repo/source"     "$bench_dir/source/app.d"     "${geodesy_sources[@]}"     -of="$binary"

echo
echo '=== build codegen probe ==='

"$dc"     "${flags[@]}"     -c     -I"$geodesy_repo/source"     "$bench_dir/source/codegen_probe.d"     "${geodesy_sources[@]}"     -of="$probe_o"

direct_lean_asm="$tmp/probe_direct_lean.asm"
inverse_lean_asm="$tmp/probe_inverse_lean.asm"

objdump -dr "$probe_o" \
    | awk '
        /<probe_direct_lean>:/ {capture=1}
        capture {print}
        capture && /^$/ {exit}
      ' > "$direct_lean_asm"

objdump -dr "$probe_o" \
    | awk '
        /<probe_inverse_lean>:/ {capture=1}
        capture {print}
        capture && /^$/ {exit}
      ' > "$inverse_lean_asm"

if grep -Eq 'geodesicDirectSignedArea|fillGeodesicC4x|fillGeodesicC4' "$direct_lean_asm"; then
    echo 'ERROR: lean direct probe references area/C4 machinery' >&2
    cat "$direct_lean_asm" >&2
    exit 3
fi

if grep -Eq 'geodesicSignedArea|geodesicDirectSignedArea|fillGeodesicC4x|fillGeodesicC4' "$inverse_lean_asm"; then
    echo 'ERROR: lean inverse probe references area/C4 machinery' >&2
    cat "$inverse_lean_asm" >&2
    exit 3
fi

echo 'codegen direct lean:  PASS (no area/C4 reference in probe symbol)'
echo 'codegen inverse lean: PASS (no area/C4 reference in probe symbol)'

if [[ "${GEODESIC_QUANTITIES_BUILD_ONLY:-0}" == 1 ]]; then
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

for mode in     direct-lean     direct-quantities     inverse-lean     inverse-quantities
do
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
            echo "$output" >&2
            exit 4
        }

        printf '%2d  %12.6f ns/op\n' "$run" "$value"
        printf '%s\n' "$value" >> "$values"
    done

    median="$(median_file "$values")"
    printf 'process_median_ns_per_op=%s\n' "$median"
done
