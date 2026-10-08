#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

CHECKS = [
    ("representation", "source/geodesy/ellipsoid.d",
     r"_flattening\s*>=\s*cast\(T\)\s*0"),
    ("representation", "source/geodesy/ellipsoid.d",
     r"flattening\s*<\s*0\s*\|\|\s*flattening\s*>=\s*1"),
    ("representation", "source/geodesy/ellipsoid.d",
     r"inverseFlattening\s*<=\s*1"),
    ("representation", "source/geodesy/ellipsoid.d",
     r"semiMinorAxis\s*>\s*semiMajorAxis"),
    ("admission", "source/geodesy/geodesic.d",
     r"_f\s*>=\s*cast\(W\)\s*0"),
    ("admission", "source/geodesy/geodesic.d",
     r"flattening\s*>\s*cast\(T\)\s*0\.01"),
    ("direct-kernel", "source/geodesy/geodesic.d",
     r"GeographicLib's >0\.01 Newton"),
    ("inverse-contract", "source/geodesy/internal/geodesic_inverse_dispatch.d",
     r"0 <= f <= 0\.01"),
    ("positive-evidence", "source/geodesy/internal/geodesic_inverse_dispatch.d",
     r"f\s*<=\s*zero"),
    ("inverse-contract", "source/geodesy/internal/geodesic_inverse_start.d",
     r"Prolate ellipsoids are intentionally outside"),
    ("positive-evidence", "source/geodesy/internal/geodesic_inverse_start.d",
     r"const W absF = fabs\(f\)"),
    ("area-kernel", "source/geodesy/internal/geodesic_area.d",
     r"e2 is\s*\n?\s*\*\s*non-negative"),
    ("area-kernel", "source/geodesy/internal/geodesic_area.d",
     r"sqrt\(e2\)"),
    ("area-kernel", "source/geodesy/internal/geodesic_area.d",
     r"atanh\(e\)"),
    ("intersection", "source/geodesy/geodesic_intersection.d",
     r"flattening\s*<\s*cast\(W\)\s*0"),
    ("intersection", "source/geodesy/geodesic_intersection.d",
     r"minimum conjugate spacing for oblate ellipsoids"),
]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("geodesy_repo", type=Path)
    args = parser.parse_args()

    root = args.geodesy_repo.resolve()
    failures = []

    for category, relative, pattern in CHECKS:
        path = root / relative
        if not path.is_file():
            failures.append(f"missing file: {relative}")
            continue

        text = path.read_text(encoding="utf-8")
        if not re.search(pattern, text, re.MULTILINE):
            failures.append(
                f"{category}: expected audit marker not found in "
                f"{relative}: {pattern}")

    if failures:
        print("R69.1 DOMAIN AUDIT FAIL")
        for item in failures:
            print(f"  - {item}")
        return 1

    print(
        "R69.1 DOMAIN AUDIT PASS: "
        f"{len(CHECKS)} classified markers")
    for category in sorted({item[0] for item in CHECKS}):
        count = sum(1 for item in CHECKS if item[0] == category)
        print(f"  {category}: {count}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
