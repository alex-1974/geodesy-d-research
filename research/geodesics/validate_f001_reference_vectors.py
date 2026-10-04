#!/usr/bin/env python3
"""
GEO-B high-precision boundary-ellipsoid reference-vector gate.

The committed corpus was generated once with GeographicLib 2.7 GeodesicExact
built in variable-precision MPFR mode:

    GEOGRAPHICLIB_PRECISION=5
    GEOGRAPHICLIB_DIGITS=512

Runtime validation does not require GeographicLib or MPFR.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "research/geodesics/f001_reference_probe.d"
DATA = ROOT / "research/geodesics/data/geodtest_f001_mpfr.tsv"


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
        f"/tmp/geodesy-f001-reference-{Path(args.compiler).name}"
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

    if "GEO-B f=0.01 MPFR RESULT: PASS" not in completed.stdout:
        raise SystemExit("f=0.01 GEO-B probe completed without PASS marker")


if __name__ == "__main__":
    main()
