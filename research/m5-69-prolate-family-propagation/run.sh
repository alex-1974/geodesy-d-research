#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:?set GEODESY_D_REPO}"
dc="${DC:-ldc2}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 "$root/research/m5-69-prolate-family-propagation/prepare_source.py"   "$geodesy_repo" "$tmp/source"

"$dc" -i -I"$tmp/source"   "$root/research/m5-69-prolate-family-propagation/source/validation.d"   -of="$tmp/validation"

"$tmp/validation"
