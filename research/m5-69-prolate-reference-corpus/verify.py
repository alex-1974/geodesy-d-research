#!/usr/bin/env python3
from __future__ import annotations

import math
import sys

EXPECTED_DIRECT = {
    "mild_ordinary", "mild_polar", "mild_equatorial", "mild_long",
    "mild_reverse", "moderate_ordinary", "moderate_polar",
    "moderate_equatorial", "moderate_long", "strong_ordinary",
    "strong_polar", "strong_long",
}

EXPECTED_INVERSE = {
    "mild_ordinary", "mild_equatorial", "mild_polar",
    "mild_near_antipodal", "mild_near_antipodal_asym",
    "moderate_ordinary", "moderate_equatorial", "moderate_polar",
    "moderate_near_antipodal", "moderate_near_antipodal_asym",
    "strong_ordinary", "strong_equatorial", "strong_polar",
    "strong_near_antipodal", "strong_near_antipodal_asym",
}

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def finite(values):
    return all(math.isfinite(v) for v in values)

def check_lat(name: str, value: float) -> None:
    if not (-90.0 <= value <= 90.0):
        fail(f"{name}: latitude out of range: {value}")

def check_lon(name: str, value: float) -> None:
    if not (-180.0 <= value <= 180.0):
        fail(f"{name}: longitude out of canonical range: {value}")

def check_azi(name: str, value: float) -> None:
    if not (-180.0 <= value <= 180.0):
        fail(f"{name}: azimuth out of canonical range: {value}")

def main() -> None:
    direct = {}
    inverse = {}
    format_seen = False

    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")

        if fields[0] == "FORMAT":
            if fields[1:] != ["m5-69-r69.2", "1"]:
                fail(f"unexpected format: {line}")
            format_seen = True
            continue

        if fields[0] == "DIRECT":
            if len(fields) != 12:
                fail(f"malformed DIRECT line: {line}")
            name = fields[1]
            if name in direct:
                fail(f"duplicate DIRECT case: {name}")
            values = list(map(float, fields[2:]))
            direct[name] = values
            if not finite(values):
                fail(f"{name}: non-finite direct value")
            a, f, lat1, lon1, azi1, s12, lat2, lon2, azi2, a12 = values
            if not (a > 0.0 and f < 0.0 and f > -1.0):
                fail(f"{name}: invalid prolate model a={a} f={f}")
            check_lat(name, lat1)
            check_lat(name, lat2)
            check_lon(name, lon1)
            check_lon(name, lon2)
            check_azi(name, azi1)
            check_azi(name, azi2)
            if not (abs(a12) <= 360.0):
                fail(f"{name}: implausible direct arc {a12}")
            continue

        if fields[0] == "INVERSE":
            if len(fields) != 12:
                fail(f"malformed INVERSE line: {line}")
            name = fields[1]
            if name in inverse:
                fail(f"duplicate INVERSE case: {name}")
            values = list(map(float, fields[2:]))
            inverse[name] = values
            if not finite(values):
                fail(f"{name}: non-finite inverse value")
            a, f, lat1, lon1, lat2, lon2, s12, azi1, azi2, a12 = values
            if not (a > 0.0 and f < 0.0 and f > -1.0):
                fail(f"{name}: invalid prolate model a={a} f={f}")
            for lat in (lat1, lat2):
                check_lat(name, lat)
            for lon in (lon1, lon2):
                check_lon(name, lon)
            check_azi(name, azi1)
            check_azi(name, azi2)
            if not (s12 >= 0.0):
                fail(f"{name}: inverse distance negative: {s12}")
            if not (0.0 <= a12 <= 180.0 + 1e-12):
                fail(f"{name}: inverse arc out of range: {a12}")
            continue

        fail(f"unknown record: {line}")

    if not format_seen:
        fail("missing format header")
    if set(direct) != EXPECTED_DIRECT:
        fail(f"direct case set mismatch: {sorted(direct)}")
    if set(inverse) != EXPECTED_INVERSE:
        fail(f"inverse case set mismatch: {sorted(inverse)}")

    for prefix, expected_f in (
        ("mild_", -1.0 / 300.0),
        ("moderate_", -0.01),
        ("strong_", -0.05),
    ):
        for table_name, table in (("direct", direct), ("inverse", inverse)):
            selected = [v for k, v in table.items() if k.startswith(prefix)]
            if not selected:
                fail(f"{table_name}: no {prefix} cases")
            for values in selected:
                if abs(values[1] - expected_f) > 1e-15:
                    fail(
                        f"{table_name}: flattening mismatch "
                        f"{values[1]} vs {expected_f}"
                    )

    for name in (
        "mild_near_antipodal",
        "moderate_near_antipodal",
        "strong_near_antipodal",
        "mild_near_antipodal_asym",
        "moderate_near_antipodal_asym",
        "strong_near_antipodal_asym",
    ):
        s12 = inverse[name][6]
        if s12 < 15_000_000.0:
            fail(f"{name}: difficult inverse case unexpectedly short: {s12}")

    print(
        "R69.2 PROLATE REFERENCE CORPUS PASS: "
        f"{len(direct)} direct + {len(inverse)} inverse cases"
    )

if __name__ == "__main__":
    main()
