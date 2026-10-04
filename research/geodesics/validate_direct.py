#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import random
import subprocess
import sys


if len(sys.argv) == 1:
    SCALAR = "double"
elif len(sys.argv) == 2:
    SCALAR = sys.argv[1]
else:
    raise SystemExit(
        "usage: validate_direct.py [float|double|real]"
    )

ENDPOINT_LIMITS = {
    "float": 1.0e-6,
    "double": 2.0e-10,
    "real": 2.0e-10,
}

if SCALAR not in ENDPOINT_LIMITS:
    raise SystemExit(
        f"unsupported scalar: {SCALAR}"
    )

PROBE = Path(
    f"/tmp/geodesy-direct-probe-{SCALAR}"
)

ENDPOINT_LIMIT = ENDPOINT_LIMITS[SCALAR]

SEED = 0x47454F43

EXPECTED_ORACLE_VERSION = "GeodSolve: GeographicLib version 2.7"


@dataclass(frozen=True)
class Case:
    name: str
    a: float
    f: float
    lat1: float
    lon1: float
    azi1: float
    s12: float


@dataclass(frozen=True)
class Position:
    lat: float
    lon: float
    azi: float


def number(value: float) -> str:
    return format(value, ".17g")


def angle_number(value: float) -> str:
    """
    Emit decimal degrees without scientific notation for GeodSolve.
    """
    return format(value, ".20f")


def run(
    command: list[str],
    input_text: str,
) -> list[str]:
    completed = subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if completed.returncode != 0:
        error_lines = [
            line
            for line in completed.stdout.splitlines()
            if line.startswith("ERROR:")
        ]

        details = "\n".join(error_lines[:10])

        raise RuntimeError(
            "command failed with exit code "
            f"{completed.returncode}: {' '.join(command)}\n"
            f"stderr:\n{completed.stderr}\n"
            f"first ERROR lines:\n{details}"
        )

    lines = [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    return lines


def parse_positions(
    lines: list[str],
    expected: int,
    label: str,
) -> list[Position]:
    if len(lines) != expected:
        raise RuntimeError(
            f"{label}: expected {expected} output lines, "
            f"got {len(lines)}"
        )

    result: list[Position] = []

    for index, line in enumerate(lines):
        if line == "FAIL":
            raise RuntimeError(
                f"{label}: case {index} returned FAIL"
            )

        fields = line.split()

        if len(fields) != 3:
            raise RuntimeError(
                f"{label}: unexpected output: {line!r}"
            )

        result.append(
            Position(
                lat=float(fields[0]),
                lon=float(fields[1]),
                azi=float(fields[2]),
            )
        )

    return result


def direct_probe(cases: list[Case]) -> list[Position]:
    text = "".join(
        " ".join(
            (
                number(case.a),
                number(case.f),
                number(case.lat1),
                number(case.lon1),
                number(case.azi1),
                number(case.s12),
            )
        )
        + "\n"
        for case in cases
    )

    return parse_positions(
        run([str(PROBE)], text),
        len(cases),
        "geodesy-d",
    )


def group_indices(
    cases: list[Case],
) -> dict[tuple[float, float], list[int]]:
    groups: dict[tuple[float, float], list[int]] = {}

    for index, case in enumerate(cases):
        groups.setdefault(
            (case.a, case.f),
            [],
        ).append(index)

    return groups


def exact_direct(
    cases: list[Case],
) -> list[Position]:
    result: list[Position | None] = [None] * len(cases)

    for (a, f), indices in group_indices(cases).items():
        text = "".join(
            " ".join(
                (
                    number(cases[index].lat1),
                    number(cases[index].lon1),
                    number(cases[index].azi1),
                    number(cases[index].s12),
                )
            )
            + "\n"
            for index in indices
        )

        lines = run(
            [
                "GeodSolve",
                "-E",
                "-p",
                "15",
                "-e",
                number(a),
                number(f),
            ],
            text,
        )

        positions = parse_positions(
            lines,
            len(indices),
            "GeodesicExact direct",
        )

        for index, position in zip(
            indices,
            positions,
            strict=True,
        ):
            result[index] = position

    if any(value is None for value in result):
        raise RuntimeError("missing exact direct result")

    return [
        value
        for value in result
        if value is not None
    ]


def exact_endpoint_errors(
    cases: list[Case],
    actual: list[Position],
    expected: list[Position],
) -> list[float]:
    errors = [math.nan] * len(cases)

    for (a, f), indices in group_indices(cases).items():
        text = "".join(
            " ".join(
                (
                    angle_number(actual[index].lat),
                    angle_number(actual[index].lon),
                    angle_number(expected[index].lat),
                    angle_number(expected[index].lon),
                )
            )
            + "\n"
            for index in indices
        )

        lines = run(
            [
                "GeodSolve",
                "-E",
                "-i",
                "-p",
                "15",
                "-e",
                number(a),
                number(f),
            ],
            text,
        )

        if len(lines) != len(indices):
            raise RuntimeError(
                "GeodesicExact inverse: unexpected "
                "number of output lines"
            )

        for index, line in zip(
            indices,
            lines,
            strict=True,
        ):
            fields = line.split()

            if len(fields) != 3:
                raise RuntimeError(
                    "GeodesicExact inverse: "
                    f"unexpected output {line!r}"
                )

            surface_distance = float(fields[2])

            errors[index] = surface_distance / a

    return errors


def angular_difference_degrees(
    first: float,
    second: float,
) -> float:
    value = math.remainder(first - second, 360.0)

    if value == -180.0:
        return 180.0

    return value


def build_cases() -> list[Case]:
    wgs_f = 1.0 / 298.257223563

    profiles = (
        ("sphere", 6_371_000.0, 0.0),
        ("wgs84", 6_378_137.0, wgs_f),
        ("near-sphere", 6_378_137.0, 1.0e-6),
        ("mid-f", 7_000_000.0, 0.005),
        ("max-f", 7_000_000.0, 0.01),
        ("unit-scale", 1.0, wgs_f),
        ("large-scale", 1.0e9, wgs_f),
    )

    fixed_geometry = (
        ("zero", 0.0, 0.0, 0.0, 0.0),
        ("equator-east", 0.0, 0.0, 90.0, 0.15),
        ("equator-west", 0.0, 0.0, -90.0, 0.15),
        ("meridian-north", 0.0, 0.0, 0.0, 0.15),
        ("meridian-south", 0.0, 0.0, 180.0, 0.15),
        ("regional", 48.2082, 16.3738, 73.0, 0.08),
        ("mid-latitude", 45.0, 10.0, 33.0, 0.7),
        ("dateline", 10.0, 179.999, 95.0, 0.2),
        ("north-pole", 90.0, 45.0, 123.0, 0.01),
        ("south-pole", -90.0, -120.0, -45.0, 0.01),
        ("near-north-pole", 89.999999, 10.0, 170.0, 0.1),
        ("near-south-pole", -89.999999, -170.0, -10.0, 0.1),
        ("half-circumference", 0.0, 0.0, 45.0, math.pi),
        ("negative-half", 0.0, 0.0, 45.0, -math.pi),
        ("full-turn-plus", 25.0, -30.0, 123.0, 2.0 * math.pi + 0.2),
        ("full-turn-minus", -25.0, 130.0, -57.0, -2.0 * math.pi - 0.2),
        ("tiny-positive", 31.0, 12.0, 77.0, 1.0e-12),
        ("tiny-negative", -31.0, -12.0, -103.0, -1.0e-12),
    )

    cases: list[Case] = []

    for profile, a, f in profiles:
        for name, lat, lon, azi, distance_a in fixed_geometry:
            cases.append(
                Case(
                    name=f"{profile}:{name}",
                    a=a,
                    f=f,
                    lat1=lat,
                    lon1=lon,
                    azi1=azi,
                    s12=distance_a * a,
                )
            )

    rng = random.Random(SEED)

    for profile, a, f in profiles:
        for index in range(200):
            lat = rng.uniform(-90.0, 90.0)
            lon = rng.uniform(-180.0, 180.0)
            azi = rng.uniform(-180.0, 180.0)

            selector = rng.random()

            if selector < 0.15:
                magnitude = (
                    10.0 ** rng.uniform(-13.0, -4.0)
                ) * a
            elif selector < 0.30:
                magnitude = rng.uniform(0.0, 0.01) * a
            else:
                magnitude = rng.uniform(
                    0.0,
                    4.0 * math.pi,
                ) * a

            if rng.random() < 0.5:
                magnitude = -magnitude

            cases.append(
                Case(
                    name=f"{profile}:random-{index:03d}",
                    a=a,
                    f=f,
                    lat1=lat,
                    lon1=lon,
                    azi1=azi,
                    s12=magnitude,
                )
            )

    return cases


def verify_oracle() -> str:
    completed = subprocess.run(
        ["GeodSolve", "--version"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    version = completed.stdout.strip()

    if version != EXPECTED_ORACLE_VERSION:
        raise RuntimeError(
            "unexpected GeodSolve version:\n"
            f"  expected: {EXPECTED_ORACLE_VERSION}\n"
            f"  actual:   {version}"
        )

    return version


def main() -> int:
    if not PROBE.is_file():
        raise SystemExit(
            f"probe not found: {PROBE}"
        )

    oracle_version = verify_oracle()

    cases = build_cases()

    actual = direct_probe(cases)
    expected = exact_direct(cases)

    endpoint_errors = exact_endpoint_errors(
        cases,
        actual,
        expected,
    )

    azimuth_errors = [
        abs(
            math.radians(
                angular_difference_degrees(
                    actual[index].azi,
                    expected[index].azi,
                )
            )
        )
        for index in range(len(cases))
    ]

    worst_endpoint_index = max(
        range(len(cases)),
        key=endpoint_errors.__getitem__,
    )

    worst_azimuth_index = max(
        range(len(cases)),
        key=azimuth_errors.__getitem__,
    )

    worst = cases[worst_endpoint_index]

    print(f"oracle: {oracle_version}")
    print(f"scalar: {SCALAR}")
    print(f"cases: {len(cases)}")
    print(f"seed: 0x{SEED:08x}")
    print(
        "max normalized endpoint error: "
        f"{endpoint_errors[worst_endpoint_index]:.17g}"
    )
    print(
        "max endpoint separation: "
        f"{endpoint_errors[worst_endpoint_index] * worst.a:.17g}"
    )
    print(
        "max azimuth error [rad]: "
        f"{azimuth_errors[worst_azimuth_index]:.17g}"
    )

    print()
    print("worst endpoint case:")
    print(f"  name: {worst.name}")
    print(f"  a: {worst.a:.17g}")
    print(f"  f: {worst.f:.17g}")
    print(f"  lat1: {worst.lat1:.17g}")
    print(f"  lon1: {worst.lon1:.17g}")
    print(f"  azi1: {worst.azi1:.17g}")
    print(f"  s12: {worst.s12:.17g}")
    print(f"  actual: {actual[worst_endpoint_index]}")
    print(f"  exact:  {expected[worst_endpoint_index]}")

    print()
    print(
        f"{SCALAR} endpoint limit: "
        f"{ENDPOINT_LIMIT:.17g}"
    )

    if not all(
        math.isfinite(value)
        for value in endpoint_errors
    ):
        print("RESULT: FAIL (non-finite endpoint error)")
        return 1

    if max(endpoint_errors) > ENDPOINT_LIMIT:
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
