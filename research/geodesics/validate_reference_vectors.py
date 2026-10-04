#!/usr/bin/env python3
"""
GEO-B fixed authoritative/high-precision reference-vector gate.

The numerical comparisons are performed inside the D probe so the decimal
reference values can be parsed directly into D `real`. Python intentionally
does not parse or round the high-precision reference fields.

This gate is PARTIAL GEO-B until a separately-provenanced high-precision
f=0.01 corpus is added.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "research/geodesics/reference_vectors_probe.d"
DATA = ROOT / "research/geodesics/data/geodtest_wgs84_subset.tsv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--compiler",
        default="dmd",
        help="D compiler used to build the probe (default: dmd)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    probe = Path(f"/tmp/geodesy-reference-vectors-{Path(args.compiler).name}")

    subprocess.run(
        [
            args.compiler,
            "-i",
            "-Isource",
            str(SOURCE),
            f"-of={probe}",
        ],
        cwd=ROOT,
        check=True,
    )

    completed = subprocess.run(
        [str(probe), str(DATA)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    print(completed.stdout, end="")

    if completed.stderr:
        print(completed.stderr, end="")

    if completed.returncode != 0:
        raise SystemExit(completed.returncode)

    marker = "GEO-B WGS84 RESULT: PASS (PARTIAL GEO-B)"

    if marker not in completed.stdout:
        raise SystemExit("GEO-B probe completed without PASS marker")


if __name__ == "__main__":
    main()

