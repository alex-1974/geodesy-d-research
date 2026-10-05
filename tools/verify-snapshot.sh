#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo/SNAPSHOT_MANIFEST.tsv"

[[ -r "$manifest" ]] || {
    echo "error: missing $manifest" >&2
    exit 2
}

expected=0
failures=0

while IFS=$'\t' read -r path mode bytes blob; do
    [[ "$path" == \#* ]] && continue
    [[ -n "$path" ]] || continue

    expected=$((expected + 1))

    if [[ ! -f "$repo/$path" ]]; then
        echo "MISSING: $path" >&2
        failures=$((failures + 1))
        continue
    fi

    actual_blob="$(git -C "$repo" hash-object -- "$path")"
    actual_bytes="$(wc -c < "$repo/$path")"
    actual_mode="$(git -C "$repo" ls-files -s -- "$path" | awk '{print $1}')"

    if [[ "$actual_blob" != "$blob" || "$actual_bytes" != "$bytes" || "$actual_mode" != "$mode" ]]; then
        echo "MISMATCH: $path" >&2
        echo "  expected mode=$mode bytes=$bytes blob=$blob" >&2
        echo "  actual   mode=$actual_mode bytes=$actual_bytes blob=$actual_blob" >&2
        failures=$((failures + 1))
    fi
done < "$manifest"

if (( failures != 0 )); then
    echo "FAIL: snapshot verification found $failures problem(s)" >&2
    exit 1
fi

echo "PASS: snapshot verification covers $expected files"
