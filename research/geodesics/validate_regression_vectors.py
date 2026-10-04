#!/usr/bin/env python3
"""
GEO-B documented GeographicLib regression-vector gate.

Regression inputs are pinned from GeographicLib's official Python geodesic
test suite. Expected numerical results were regenerated with the qualified
GeographicLib 2.7 MPFR GeodesicExact oracle and committed as text.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "research/geodesics/regression_reference_probe.d"
DATA = (
    ROOT
    / "research/geodesics/data/geographiclib_regressions_mpfr.tsv"
)


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
    probe = Path(
        f"/tmp/geodesy-regression-reference-"
        f"{Path(args.compiler).name}"
    )

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

    marker = "GEO-B documented regressions: PASS"

    if marker not in completed.stdout:
        raise SystemExit(
            "documented regression probe completed without PASS marker"
        )


if __name__ == "__main__":
    main()
