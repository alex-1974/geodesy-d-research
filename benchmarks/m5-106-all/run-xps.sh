#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:-$root/../geodesy-d}"
geodesy_sha="${M5_106_GEODESY_SHA:-7f31cc90cd8ab7ba673d16aa2219ef4c7b540a96}"
geographiclib_root="${GEOGRAPHICLIB_ROOT:-}"
cpu="${M5_106_CPU:-2}"
runs="${M5_106_RUNS:-12}"
rounds="${M5_106_ROUNDS:-8}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="$root/benchmarks/m5-106-all/evidence"
out="${M5_106_EVIDENCE:-$evidence_dir/xps-$stamp.txt}"

mkdir -p "$evidence_dir"

[[ -d "$geodesy_repo/.git" ]] || {
  echo "error: geodesy-d checkout not found at $geodesy_repo" >&2
  echo "set GEODESY_D_REPO=/path/to/geodesy-d" >&2
  exit 2
}

git -C "$geodesy_repo" fetch origin --prune

git -C "$geodesy_repo" cat-file -e "$geodesy_sha^{commit}" || {
  echo "error: required geodesy-d commit $geodesy_sha is unavailable" >&2
  exit 6
}

tmp_root="$(mktemp -d)"
geodesy_worktree="$tmp_root/geodesy-d"

cleanup() {
  git -C "$geodesy_repo" worktree remove --force "$geodesy_worktree" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
}
trap cleanup EXIT

git -C "$geodesy_repo" worktree add --detach "$geodesy_worktree" "$geodesy_sha"

command -v ldc2 >/dev/null || {
  echo "error: ldc2 not found" >&2
  exit 3
}

command -v g++ >/dev/null || {
  echo "error: g++ not found" >&2
  exit 4
}

if [[ -z "$geographiclib_root" ]]; then
  if command -v pkg-config >/dev/null 2>&1 \
      && pkg-config --exists geographiclib; then
    geographiclib_root="$(pkg-config --variable=prefix geographiclib)"
  elif command -v GeographicLib-config >/dev/null 2>&1; then
    geographiclib_root="$(GeographicLib-config --prefix 2>/dev/null || true)"
  fi
fi

if [[ -z "$geographiclib_root" ]]; then
  for candidate in /usr /usr/local /opt/GeographicLib /opt/geographiclib; do
    if [[ -d "$candidate/include/GeographicLib" ]]; then
      geographiclib_root="$candidate"
      break
    fi
  done
fi

if [[ -z "$geographiclib_root" \
    || ! -d "$geographiclib_root/include/GeographicLib" ]]; then
  echo "error: GeographicLib headers were not found" >&2
  echo "searched pkg-config, GeographicLib-config, /usr, /usr/local and /opt" >&2
  echo "set GEOGRAPHICLIB_ROOT to a GeographicLib 2.7 install prefix" >&2
  exit 5
fi

{
  echo "=== M5 #106 XPS qualification evidence ==="
  printf 'timestamp_utc=%s\n' "$stamp"
  printf 'host=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -srmo)"
  printf 'cpu_model=%s\n' "$(lscpu | awk -F: '/Model name/ {sub(/^[[:space:]]+/,"",$2); print $2; exit}')"
  printf 'cpu_affinity=%s\n' "$cpu"
  printf 'process_runs=%s\n' "$runs"
  printf 'rounds_per_case=%s\n' "$rounds"
  printf 'research_commit=%s\n' "$(git -C "$root" rev-parse HEAD)"
  printf 'geodesy_d_commit=%s\n' "$(git -C "$geodesy_worktree" rev-parse HEAD)"
  printf 'geodesy_d_source_checkout=%s\n' "$geodesy_repo"
  printf 'geographiclib_root=%s\n' "$geographiclib_root"
  printf 'ldc=%s\n' "$(ldc2 --version | sed -n '1p')"
  printf 'gxx=%s\n' "$(g++ --version | sed -n '1p')"
  if command -v GeographicLib-config >/dev/null 2>&1; then
    printf 'geographiclib=%s\n' "$(GeographicLib-config --version 2>/dev/null || true)"
  fi
  echo
  GEODESY_D_REPO="$geodesy_worktree"   GEOGRAPHICLIB_ROOT="$geographiclib_root"   DC=ldc2   CXX=g++   M5_106_CPU="$cpu"   M5_106_RUNS="$runs"   M5_106_ROUNDS="$rounds"     bash "$root/benchmarks/m5-106-all/run.sh"
} | tee "$out"

echo
echo "evidence=$out"
