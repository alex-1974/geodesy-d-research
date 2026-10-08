#!/usr/bin/env python3
from __future__ import annotations

import math
import sys
from dataclasses import dataclass


@dataclass
class Case:
    a: float
    f: float
    p0x: float
    p0y: float
    radius: float
    delta: float
    expected_count: int
    points: list[tuple[int, float, float, int, float]]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    cases: dict[str, Case] = {}
    format_seen = False

    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")

        if fields[0] == "FORMAT":
            if fields[1:] != ["m5-106-r106.1", "1"]:
                fail(f"unexpected format line: {line}")
            format_seen = True
            continue

        if fields[0] == "CASE":
            if len(fields) != 9:
                fail(f"malformed CASE line: {line}")
            name = fields[1]
            if name in cases:
                fail(f"duplicate CASE: {name}")
            cases[name] = Case(
                a=float(fields[2]),
                f=float(fields[3]),
                p0x=float(fields[4]),
                p0y=float(fields[5]),
                radius=float(fields[6]),
                delta=float(fields[7]),
                expected_count=int(fields[8]),
                points=[],
            )
            continue

        if fields[0] == "POINT":
            if len(fields) != 7:
                fail(f"malformed POINT line: {line}")
            name = fields[1]
            if name not in cases:
                fail(f"POINT before CASE: {name}")
            cases[name].points.append(
                (
                    int(fields[2]),
                    float(fields[3]),
                    float(fields[4]),
                    int(fields[5]),
                    float(fields[6]),
                )
            )
            continue

        fail(f"unknown record: {line}")

    if not format_seen:
        fail("missing format header")

    required = {
        "wgs84_ordinary",
        "wgs84_symmetric_origin",
        "wgs84_near_parallel",
        "wgs84_polar",
        "wgs84_reverse",
        "wgs84_coincident_parallel",
        "wgs84_coincident_antiparallel",
        "sphere_ordinary",
        "sphere_near_parallel",
        "sphere_symmetric_origin",
        "sphere_coincident_parallel",
        "wgs84_boundary_outside",
        "wgs84_boundary_inside",
    }

    if set(cases) != required:
        fail(f"case set mismatch: {sorted(cases)}")

    for name, case in cases.items():
        if len(case.points) != case.expected_count:
            fail(
                f"{name}: expected {case.expected_count} points, "
                f"parsed {len(case.points)}"
            )

        previous_key: tuple[float, float, float] | None = None

        for expected_index, (index, x, y, coincidence, reported_rank) in enumerate(case.points):
            if index != expected_index:
                fail(f"{name}: non-contiguous index {index}, expected {expected_index}")
            if coincidence not in (-1, 0, 1):
                fail(f"{name}: invalid coincidence {coincidence}")
            if not all(math.isfinite(v) for v in (x, y, reported_rank)):
                fail(f"{name}: non-finite result")

            computed_rank = abs(x - case.p0x) + abs(y - case.p0y)
            rank_tol = max(1e-7, 64.0 * math.ulp(max(1.0, computed_rank)))

            if abs(computed_rank - reported_rank) > rank_tol:
                fail(
                    f"{name}: rank mismatch at {index}: "
                    f"{computed_rank} vs {reported_rank}"
                )
            if computed_rank > case.radius + rank_tol:
                fail(
                    f"{name}: point {index} outside radius: "
                    f"{computed_rank} > {case.radius}"
                )

            key = (reported_rank, x, y)
            if previous_key is not None and key < previous_key:
                fail(
                    f"{name}: non-canonical ordering at {index}: "
                    f"{key} < {previous_key}"
                )
            previous_key = key

        for i, (_, xi, yi, _, _) in enumerate(case.points):
            for _, xj, yj, _, _ in case.points[i + 1 :]:
                duplicate_distance = abs(xi - xj) + abs(yi - yj)
                if duplicate_distance <= case.delta:
                    fail(
                        f"{name}: duplicate points within delta: "
                        f"{duplicate_distance} <= {case.delta}"
                    )

        print(
            f"PASS {name:31s} count={len(case.points):3d} "
            f"radius={case.radius:.6f} delta={case.delta:.6f}"
        )

    outside = cases["wgs84_boundary_outside"]
    inside = cases["wgs84_boundary_inside"]

    if inside.expected_count <= outside.expected_count:
        fail(
            "boundary pair did not gain an intersection when radius "
            "moved across the Next rank"
        )

    for name in (
        "wgs84_coincident_parallel",
        "wgs84_coincident_antiparallel",
        "sphere_coincident_parallel",
    ):
        if not cases[name].points:
            fail(f"{name}: coincident corpus unexpectedly empty")
        if not any(p[3] != 0 for p in cases[name].points):
            fail(f"{name}: no coincidence marker in coincident corpus")

    print(
        "R106.1 REFERENCE CORPUS PASS: "
        f"{len(cases)} cases, "
        f"{sum(len(c.points) for c in cases.values())} points"
    )


if __name__ == "__main__":
    main()
