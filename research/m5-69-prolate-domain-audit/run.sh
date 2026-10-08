#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
geodesy_repo="${GEODESY_D_REPO:-$root/../geodesy-d}"

python3 "$root/research/m5-69-prolate-domain-audit/audit.py"   "$geodesy_repo"
