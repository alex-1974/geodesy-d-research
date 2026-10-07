#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

geodesy_repo="${GEODESY_D_REPO:-$root/../geodesy-d}"
baseline_sha="${M5_68_BASELINE_SHA:-0d4da128bae12220cf6ea27391fadb3305a532bb}"
candidate_sha="${M5_68_CANDIDATE_SHA:-87771bde34a1cefed66634d8b4019f30e85ba561}"

[[ -d "$geodesy_repo/.git" ]] || {
    echo "error: geodesy-d checkout not found at $geodesy_repo" >&2
    echo "set GEODESY_D_REPO=/path/to/geodesy-d" >&2
    exit 2
}

git -C "$geodesy_repo" fetch origin --prune

for sha in "$baseline_sha" "$candidate_sha"; do
    git -C "$geodesy_repo" cat-file -e "$sha^{commit}" || {
        echo "error: commit $sha not available in geodesy-d checkout" >&2
        exit 3
    }
done

tmp="$(mktemp -d)"
baseline="$tmp/baseline"
candidate="$tmp/candidate"

cleanup() {
    git -C "$geodesy_repo" worktree remove --force "$baseline" >/dev/null 2>&1 || true
    git -C "$geodesy_repo" worktree remove --force "$candidate" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT

git -C "$geodesy_repo" worktree add --detach "$baseline" "$baseline_sha"
git -C "$geodesy_repo" worktree add --detach "$candidate" "$candidate_sha"

GEODESY_D_BASELINE_REPO="$baseline" GEODESY_D_CANDIDATE_REPO="$candidate"     bash "$root/benchmarks/m5-68-geodesic-line-regression/run.sh"
