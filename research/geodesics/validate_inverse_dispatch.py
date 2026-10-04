#!/usr/bin/env python3
"""
GEO-C differential validation for the full internal inverse dispatcher.

Oracle:
    GeographicLib GeodSolve 2.7 in exact mode (-E).

The validator checks three independent properties:

1. inverse distance against GeodesicExact;
2. endpoint closure by feeding the D result's azi1+s12 back through exact
   direct geodesics;
3. final azimuth against that same exact direct path.

The direct-closure check avoids treating a different but valid branch at
antipodal/multiple-solution degeneracies as an error.

GeodSolve CLI note:
    GeographicLib clamps -p to 10 + Math::extra_digits().  With the normal
    double build this means unit-scale distance output can itself be quantized
    at about 1e-10 absolute units.  The normalized distance gate is therefore
    intentionally wider than the Earth-scale numerical errors.
"""

from __future__ import annotations

import argparse
import math
import random
import subprocess
import sys
from pathlib import Path


EXPECTED_GEODSOLVE_VERSION = "GeodSolve: GeographicLib version 2.7"
SEED = 0x47454F44

DISTANCE_LIMIT = 2e-10
CLOSURE_LIMIT = 2e-10
FINAL_AZIMUTH_LIMIT = 2e-10
WELL_CONDITIONED_MIN_ANGULAR_LENGTH = 1e-6

DEFAULT_GEODSOLVE = Path("/usr/bin/GeodSolve")
DEFAULT_PROBE = Path("/tmp/geodesy-inverse-dispatch-probe")


PROFILES = (
    ("sphere", 6_371_000.0, 0.0),
    ("wgs84", 6_378_137.0, 1.0 / 298.257223563),
    ("near-sphere", 6_378_137.0, 1e-6),
    ("mid-f", 7_000_000.0, 0.005),
    ("max-f", 7_000_000.0, 0.01),
    ("unit-scale", 1.0, 1.0 / 298.257223563),
    ("large-scale", 1e9, 1.0 / 298.257223563),
)


def radians(degrees: float) -> float:
    return math.radians(degrees)


FIXED_CASES = (
    (
        radians(20),
        radians(30),
        radians(20),
        radians(30),
        "coincident",
    ),
    (
        radians(20),
        math.pi,
        radians(20),
        -math.pi,
        "coincident-antimeridian",
    ),
    (
        math.pi / 2,
        radians(-120),
        math.pi / 2,
        radians(70),
        "north-pole-coincident",
    ),
    (
        -math.pi / 2,
        radians(10),
        -math.pi / 2,
        radians(170),
        "south-pole-coincident",
    ),
    (
        radians(-60),
        radians(10),
        radians(40),
        radians(10),
        "meridian-north",
    ),
    (
        radians(60),
        radians(10),
        radians(-40),
        radians(10),
        "meridian-south",
    ),
    (
        radians(-20),
        radians(10),
        radians(20),
        radians(-170),
        "opposite-meridian",
    ),
    (
        0.0,
        radians(10),
        0.0,
        radians(40),
        "equator-east",
    ),
    (
        0.0,
        radians(40),
        0.0,
        radians(10),
        "equator-west",
    ),
    (
        0.0,
        radians(179.9),
        0.0,
        radians(-179.8),
        "equator-dateline",
    ),
    (
        radians(48.2),
        radians(16.37),
        radians(40.7),
        radians(-74.0),
        "vienna-new-york",
    ),
    (
        radians(-33.9),
        radians(151.2),
        radians(35.7),
        radians(139.7),
        "sydney-tokyo",
    ),
    (
        radians(30),
        radians(179.9),
        radians(31),
        radians(-179.8),
        "dateline-general",
    ),
    (
        radians(-10),
        0.0,
        radians(10.0001),
        math.pi - 1e-4,
        "near-antipodal-a",
    ),
    (
        radians(-35),
        radians(20),
        radians(34.9999),
        radians(-160.0002),
        "near-antipodal-b",
    ),
    (
        radians(20),
        radians(30),
        radians(20) + 1e-10,
        radians(30) + 1e-10,
        "tiny",
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--probe",
        type=Path,
        default=None,
        help="existing dispatch probe binary; otherwise build with D compiler",
    )

    parser.add_argument(
        "--geodsolve",
        type=Path,
        default=DEFAULT_GEODSOLVE,
        help="GeodSolve executable",
    )

    parser.add_argument(
        "--compiler",
        default="dmd",
        help="D compiler used when building the probe (default: dmd)",
    )

    return parser.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def normalize_version_line(raw: str) -> str:
    line = raw.strip().splitlines()[0]
    executable, separator, suffix = line.partition(":")

    if not separator:
        return line

    return f"{Path(executable).name}:{suffix}"


def verify_geodsolve(executable: Path) -> None:
    completed = subprocess.run(
        [str(executable), "--version"],
        text=True,
        capture_output=True,
        check=True,
    )

    actual = normalize_version_line(completed.stdout)

    if actual != EXPECTED_GEODSOLVE_VERSION:
        raise SystemExit(
            "unexpected GeodSolve version:\n"
            f"  expected: {EXPECTED_GEODSOLVE_VERSION}\n"
            f"  actual:   {actual}"
        )


def build_probe(compiler: str) -> Path:
    root = repo_root()

    source = (
        root
        / "research/geodesics/inverse_dispatch_probe.d"
    )

    subprocess.run(
        [
            compiler,
            "-i",
            "-Isource",
            str(source),
            f"-of={DEFAULT_PROBE}",
        ],
        cwd=root,
        check=True,
    )

    return DEFAULT_PROBE


def wrap_pi(value: float) -> float:
    return math.atan2(
        math.sin(value),
        math.cos(value),
    )


def angle_difference(a: float, b: float) -> float:
    return wrap_pi(a - b)


def surface_closure_angle(
    latitude1: float,
    longitude1: float,
    latitude2: float,
    longitude2: float,
) -> float:
    """
    Dimensionless endpoint closure using unit-sphere embedding.

    This is only an endpoint angular metric.  It remains well behaved at the
    poles because longitude is naturally suppressed by cos(latitude).
    """

    cos1 = math.cos(latitude1)
    cos2 = math.cos(latitude2)

    x1 = cos1 * math.cos(longitude1)
    y1 = cos1 * math.sin(longitude1)
    z1 = math.sin(latitude1)

    x2 = cos2 * math.cos(longitude2)
    y2 = cos2 * math.sin(longitude2)
    z2 = math.sin(latitude2)

    dx = x1 - x2
    dy = y1 - y2
    dz = z1 - z2

    chord = math.sqrt(
        dx * dx
        + dy * dy
        + dz * dz
    )

    chord = min(
        2.0,
        max(0.0, chord),
    )

    return 2.0 * math.asin(chord / 2.0)


def make_cases():
    rng = random.Random(SEED)
    result = {}

    for profile, a, f in PROFILES:
        cases = list(FIXED_CASES)

        for index in range(320):
            latitude1 = rng.uniform(
                -math.pi / 2,
                math.pi / 2,
            )

            longitude1 = rng.uniform(
                -math.pi,
                math.pi,
            )

            if index < 40:
                latitude2 = (
                    -latitude1
                    + rng.uniform(-1e-5, 1e-5)
                )

                latitude2 = max(
                    -math.pi / 2,
                    min(
                        math.pi / 2,
                        latitude2,
                    ),
                )

                longitude2 = wrap_pi(
                    longitude1
                    + math.pi
                    + rng.uniform(-1e-5, 1e-5)
                )

                tag = (
                    f"random-near-antipodal-{index:03d}"
                )

            elif index < 70:
                latitude2 = max(
                    -math.pi / 2,
                    min(
                        math.pi / 2,
                        latitude1
                        + rng.uniform(-1e-9, 1e-9),
                    ),
                )

                longitude2 = wrap_pi(
                    longitude1
                    + rng.uniform(-1e-9, 1e-9)
                )

                tag = f"random-short-{index:03d}"

            elif index < 90:
                latitude2 = rng.uniform(
                    -math.pi / 2,
                    math.pi / 2,
                )

                longitude2 = longitude1

                tag = f"random-meridian-{index:03d}"

            elif index < 110:
                latitude1 = 0.0
                latitude2 = 0.0

                longitude2 = rng.uniform(
                    -math.pi,
                    math.pi,
                )

                tag = f"random-equator-{index:03d}"

            elif index < 130:
                longitude1 = rng.uniform(
                    radians(170),
                    math.pi,
                )

                longitude2 = rng.uniform(
                    -math.pi,
                    radians(-170),
                )

                latitude2 = rng.uniform(
                    -math.pi / 2,
                    math.pi / 2,
                )

                tag = f"random-dateline-{index:03d}"

            else:
                latitude2 = rng.uniform(
                    -math.pi / 2,
                    math.pi / 2,
                )

                longitude2 = rng.uniform(
                    -math.pi,
                    math.pi,
                )

                tag = f"random-{index:03d}"

            cases.append(
                (
                    latitude1,
                    longitude1,
                    latitude2,
                    longitude2,
                    tag,
                )
            )

        result[profile] = (
            a,
            f,
            cases,
        )

    return result


def run_probe(
    executable: Path,
    a: float,
    f: float,
    cases,
):
    payload = "".join(
        f"{a:.17g} {f:.17g} "
        f"{lat1:.17g} {lon1:.17g} "
        f"{lat2:.17g} {lon2:.17g}\n"
        for lat1, lon1, lat2, lon2, _ in cases
    )

    completed = subprocess.run(
        [str(executable)],
        input=payload,
        text=True,
        capture_output=True,
        check=True,
    )

    lines = [
        line
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if len(lines) != len(cases):
        raise SystemExit(
            f"probe returned {len(lines)} rows "
            f"for {len(cases)} cases"
        )

    return lines


def run_inverse_oracle(
    executable: Path,
    a: float,
    f: float,
    cases,
):
    payload = "".join(
        f"{math.degrees(lat1):.17f} "
        f"{math.degrees(lon1):.17f} "
        f"{math.degrees(lat2):.17f} "
        f"{math.degrees(lon2):.17f}\n"
        for lat1, lon1, lat2, lon2, _ in cases
    )

    completed = subprocess.run(
        [
            str(executable),
            "-E",
            "-i",
            "-e",
            f"{a:.17g}",
            f"{f:.17g}",
            "-p",
            "10",
        ],
        input=payload,
        text=True,
        capture_output=True,
        check=True,
    )

    lines = [
        line
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if len(lines) != len(cases):
        raise SystemExit(
            f"inverse oracle returned {len(lines)} rows "
            f"for {len(cases)} cases"
        )

    return lines


def run_direct_oracle(
    executable: Path,
    a: float,
    f: float,
    cases,
    actual_rows,
):
    payload_parts = []

    for case, actual in zip(cases, actual_rows):
        latitude1, longitude1, _, _, _ = case

        distance, azimuth1, _, _, _, _, _ = actual

        payload_parts.append(
            f"{math.degrees(latitude1):.17f} "
            f"{math.degrees(longitude1):.17f} "
            f"{math.degrees(azimuth1):.17f} "
            f"{distance:.17g}\n"
        )

    completed = subprocess.run(
        [
            str(executable),
            "-E",
            "-e",
            f"{a:.17g}",
            f"{f:.17g}",
            "-p",
            "10",
        ],
        input="".join(payload_parts),
        text=True,
        capture_output=True,
        check=True,
    )

    lines = [
        line
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if len(lines) != len(cases):
        raise SystemExit(
            f"direct oracle returned {len(lines)} rows "
            f"for {len(cases)} cases"
        )

    return lines


def main() -> int:
    args = parse_args()

    verify_geodsolve(args.geodsolve)

    probe = (
        args.probe
        if args.probe is not None
        else build_probe(args.compiler)
    )

    cases_by_profile = make_cases()

    total = 0
    kind_counts = {}

    max_normalized_distance = 0.0
    max_closure = 0.0
    max_final_azimuth = 0.0
    max_iterations = 0

    worst_distance = None
    worst_closure = None
    worst_final_azimuth = None
    worst_iterations = None

    for profile, (a, f, cases) in cases_by_profile.items():
        probe_lines = run_probe(
            probe,
            a,
            f,
            cases,
        )

        inverse_lines = run_inverse_oracle(
            args.geodsolve,
            a,
            f,
            cases,
        )

        actual_rows = []

        for case, actual_line, inverse_line in zip(
            cases,
            probe_lines,
            inverse_lines,
        ):
            fields = actual_line.split()
            oracle_fields = inverse_line.split()

            if len(fields) != 6:
                raise SystemExit(
                    f"{profile}:{case[-1]} malformed "
                    f"probe output: {actual_line!r}"
                )

            if len(oracle_fields) < 3:
                raise SystemExit(
                    f"{profile}:{case[-1]} malformed "
                    f"inverse oracle: {inverse_line!r}"
                )

            actual_rows.append(
                (
                    float(fields[0]),
                    float(fields[1]),
                    float(fields[2]),
                    float(fields[3]),
                    int(fields[4]),
                    int(fields[5]),
                    float(oracle_fields[2]),
                )
            )

        direct_lines = run_direct_oracle(
            args.geodsolve,
            a,
            f,
            cases,
            actual_rows,
        )

        for case, actual, direct_line in zip(
            cases,
            actual_rows,
            direct_lines,
        ):
            (
                latitude1,
                longitude1,
                latitude2,
                longitude2,
                tag,
            ) = case

            (
                distance,
                azimuth1,
                azimuth2,
                sigma12,
                iterations,
                kind,
                expected_distance,
            ) = actual

            direct_fields = direct_line.split()

            if len(direct_fields) < 3:
                raise SystemExit(
                    f"{profile}:{tag} malformed "
                    f"direct oracle: {direct_line!r}"
                )

            reached_latitude = math.radians(
                float(direct_fields[0])
            )

            reached_longitude = math.radians(
                float(direct_fields[1])
            )

            reached_azimuth2 = math.radians(
                float(direct_fields[2])
            )

            normalized_distance_error = (
                abs(distance - expected_distance)
                / a
            )

            closure = surface_closure_angle(
                reached_latitude,
                reached_longitude,
                latitude2,
                longitude2,
            )

            angular_length = (
                abs(expected_distance)
                / a
            )

            if angular_length == 0.0:
                final_azimuth_error = 0.0
            else:
                final_azimuth_error = abs(
                    angle_difference(
                        azimuth2,
                        reached_azimuth2,
                    )
                )

            total += 1

            kind_counts[kind] = (
                kind_counts.get(kind, 0)
                + 1
            )

            if (
                normalized_distance_error
                > max_normalized_distance
            ):
                max_normalized_distance = (
                    normalized_distance_error
                )

                worst_distance = (
                    profile,
                    tag,
                    latitude1,
                    longitude1,
                    latitude2,
                    longitude2,
                    expected_distance,
                    distance,
                    kind,
                )

            if closure > max_closure:
                max_closure = closure

                worst_closure = (
                    profile,
                    tag,
                    latitude1,
                    longitude1,
                    latitude2,
                    longitude2,
                    closure,
                    kind,
                    iterations,
                )

            if (
                angular_length
                >= WELL_CONDITIONED_MIN_ANGULAR_LENGTH
                and final_azimuth_error
                    > max_final_azimuth
            ):
                max_final_azimuth = (
                    final_azimuth_error
                )

                worst_final_azimuth = (
                    profile,
                    tag,
                    angular_length,
                    azimuth2,
                    reached_azimuth2,
                    final_azimuth_error,
                    kind,
                )

            if iterations > max_iterations:
                max_iterations = iterations

                worst_iterations = (
                    profile,
                    tag,
                    latitude1,
                    longitude1,
                    latitude2,
                    longitude2,
                    iterations,
                    kind,
                )

    print(EXPECTED_GEODSOLVE_VERSION)
    print(f"seed: 0x{SEED:08X}")
    print(f"cases: {total}")
    print(f"dispatch kind counts: {kind_counts}")

    print(
        "max normalized distance error: "
        f"{max_normalized_distance:.17g}"
    )

    print(
        "max exact-direct closure angle: "
        f"{max_closure:.17g}"
    )

    print(
        "max well-conditioned final azimuth error rad: "
        f"{max_final_azimuth:.17g}"
    )

    print(
        f"max solver iterations: {max_iterations}"
    )

    print(
        f"worst distance: {worst_distance}"
    )

    print(
        f"worst closure: {worst_closure}"
    )

    print(
        f"worst final azimuth: {worst_final_azimuth}"
    )

    print(
        f"worst iterations: {worst_iterations}"
    )

    if (
        max_normalized_distance
        > DISTANCE_LIMIT
    ):
        raise SystemExit(
            "FAIL: normalized distance error exceeds "
            f"{DISTANCE_LIMIT}"
        )

    if max_closure > CLOSURE_LIMIT:
        raise SystemExit(
            "FAIL: exact-direct endpoint closure exceeds "
            f"{CLOSURE_LIMIT} rad"
        )

    if (
        max_final_azimuth
        > FINAL_AZIMUTH_LIMIT
    ):
        raise SystemExit(
            "FAIL: final azimuth error exceeds "
            f"{FINAL_AZIMUTH_LIMIT} rad"
        )

    print("PASS")

    return 0


if __name__ == "__main__":
    sys.exit(main())
