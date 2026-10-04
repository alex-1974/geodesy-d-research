#!/usr/bin/env python3
"""
Final GEO-C public-API differential validation against GeographicLib
GeodesicExact.

This is an acceptance orchestrator, not a replacement for the focused
research validators.  The internal inverse-solver/dispatcher validators remain
diagnostic and regression evidence.

The accepted full run uses ten ellipsoid/scale profiles and at least 4000
generated Direct plus 4000 generated Inverse cases per profile.  Together with
fixed cases this yields more than 40,000 Direct and 40,000 Inverse public-API
comparisons for each of float, double, and real.

The default GeodSolve executable is /usr/bin/GeodSolve.  It must report
GeographicLib 2.7 and is invoked with -E (GeodesicExact).

The bulk corpus is generated in Python binary64.  Its real run validates the
public real computation path over that broad corpus; inputs beyond binary64
precision are qualified separately by validate_geoc_wide_real.py against the
512-bit MPFR GeodesicExact oracle.

Inverse direction acceptance is conditioning-aware: ordinary cases use direct
angular direction error, very short cases use angular_length * direction_error,
and deliberately near-antipodal cases use antipodal_defect * direction_error.
Raw near-antipodal azimuth remains diagnostic because the inverse azimuth is
singularly conditioned at the antipodal cut locus.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
from pathlib import Path
import random
import struct
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
PROBE_SOURCE = ROOT / "research/geodesics/geoc_public_probe.d"
DEFAULT_PROBE = Path("/tmp/geodesy-geoc-public-probe")
DEFAULT_GEODSOLVE = Path("/usr/bin/GeodSolve")

EXPECTED_VERSION = "GeodSolve: GeographicLib version 2.7"
SEED = 0x47454F51

FULL_RANDOM_PER_PROFILE = 4000


@dataclass(frozen=True)
class Profile:
    name: str
    a: float
    f: float


@dataclass(frozen=True)
class DirectCase:
    tag: str
    lat1: float
    lon1: float
    azi1: float
    distance_over_a: float


@dataclass(frozen=True)
class InverseCase:
    tag: str
    lat1: float
    lon1: float
    lat2: float
    lon2: float
    azimuth_unique: bool = True


PROFILES = (
    Profile("sphere", 6_371_000.0, 0.0),
    Profile("wgs84", 6_378_137.0, 1.0 / 298.257223563),
    Profile("grs80", 6_378_137.0, 1.0 / 298.257222101),
    Profile("international-1924", 6_378_388.0, 1.0 / 297.0),
    Profile("airy-1830", 6_377_563.396, 1.0 / 299.3249646),
    Profile("near-sphere", 6_378_137.0, 1.0e-6),
    Profile("mid-f", 7_000_000.0, 0.005),
    Profile("max-f", 7_000_000.0, 0.01),
    Profile("unit-scale", 1.0, 1.0 / 298.257223563),
    Profile("large-scale", 1.0e9, 1.0 / 298.257223563),
)


LIMITS = {
    "float": {
        "direct_endpoint": 1.0e-6,
        "direct_tangent": 1.0e-5,
        "direct_raw_azimuth": 1.0e-5,
        "inverse_distance": 2.0e-6,
        "inverse_closure": 2.0e-6,
        "inverse_tangent": 1.0e-5,
        "inverse_raw_azimuth": 1.0e-5,
        "well_conditioned": 1.0e-5,
    },
    "double": {
        "direct_endpoint": 2.0e-10,
        "direct_tangent": 2.0e-10,
        "direct_raw_azimuth": 2.0e-10,
        "inverse_distance": 2.0e-10,
        "inverse_closure": 2.0e-10,
        "inverse_tangent": 2.0e-10,
        "inverse_raw_azimuth": 2.0e-10,
        "well_conditioned": 1.0e-6,
    },
    "real": {
        "direct_endpoint": 2.0e-10,
        "direct_tangent": 2.0e-10,
        "direct_raw_azimuth": 2.0e-10,
        "inverse_distance": 2.0e-10,
        "inverse_closure": 2.0e-10,
        "inverse_tangent": 2.0e-10,
        "inverse_raw_azimuth": 2.0e-10,
        "well_conditioned": 1.0e-6,
    },
}


DIRECT_FIXED = (
    DirectCase("zero", 0.0, 0.0, 0.0, 0.0),
    DirectCase("equator-east", 0.0, 0.0, 90.0, 0.15),
    DirectCase("equator-west", 0.0, 0.0, -90.0, 0.15),
    DirectCase("meridian-north", 0.0, 0.0, 0.0, 0.15),
    DirectCase("meridian-south", 0.0, 0.0, 180.0, 0.15),
    DirectCase("regional", 48.2082, 16.3738, 73.0, 0.08),
    DirectCase("dateline", 10.0, 179.999, 95.0, 0.2),
    DirectCase("north-pole", 90.0, 45.0, 123.0, 0.01),
    DirectCase("south-pole", -90.0, -120.0, -45.0, 0.01),
    DirectCase("near-north-pole", 89.999999, 10.0, 170.0, 0.1),
    DirectCase("near-south-pole", -89.999999, -170.0, -10.0, 0.1),
    DirectCase("half-circumference", 0.0, 0.0, 45.0, math.pi),
    DirectCase("negative-half", 0.0, 0.0, 45.0, -math.pi),
    DirectCase("tiny-positive", 31.0, 12.0, 77.0, 1.0e-12),
    DirectCase("tiny-negative", -31.0, -12.0, -103.0, -1.0e-12),
)


INVERSE_FIXED = (
    InverseCase("coincident", 20.0, 30.0, 20.0, 30.0, False),
    InverseCase(
        "coincident-antimeridian",
        20.0,
        180.0,
        20.0,
        -180.0,
        False,
    ),
    InverseCase(
        "north-pole-coincident",
        90.0,
        -120.0,
        90.0,
        70.0,
        False,
    ),
    InverseCase(
        "south-pole-coincident",
        -90.0,
        10.0,
        -90.0,
        170.0,
        False,
    ),
    InverseCase("meridian-north", -60.0, 10.0, 40.0, 10.0),
    InverseCase("meridian-south", 60.0, 10.0, -40.0, 10.0),
    InverseCase("equator-east", 0.0, 10.0, 0.0, 40.0),
    InverseCase("equator-west", 0.0, 40.0, 0.0, 10.0),
    InverseCase("equator-dateline", 0.0, 179.9, 0.0, -179.8),
    InverseCase(
        "vienna-new-york",
        48.20849,
        16.37208,
        40.7128,
        -74.0060,
    ),
    InverseCase(
        "sydney-tokyo",
        -33.8688,
        151.2093,
        35.6762,
        139.6503,
    ),
    InverseCase(
        "near-antipodal-a",
        -10.0,
        0.0,
        10.0001,
        179.99427042204869,
    ),
    InverseCase(
        "near-antipodal-b",
        -35.0,
        20.0,
        34.9999,
        -160.0002,
    ),
    InverseCase(
        "exact-antipodal-equator",
        0.0,
        0.0,
        0.0,
        180.0,
        False,
    ),
    InverseCase(
        "opposite-poles",
        90.0,
        20.0,
        -90.0,
        -160.0,
        False,
    ),
    InverseCase(
        "tiny",
        20.0,
        30.0,
        20.0 + math.degrees(1.0e-10),
        30.0 + math.degrees(1.0e-10),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--compiler",
        default="dmd",
        help="D compiler used for the public probe (default: dmd)",
    )
    parser.add_argument(
        "--geodsolve",
        type=Path,
        default=DEFAULT_GEODSOLVE,
        help="GeographicLib GeodSolve executable",
    )
    parser.add_argument(
        "--probe",
        type=Path,
        default=None,
        help="use an existing compiled public probe",
    )
    parser.add_argument(
        "--scalar",
        choices=("float", "double", "real", "all"),
        default="all",
    )
    parser.add_argument(
        "--random-per-profile",
        type=int,
        default=FULL_RANDOM_PER_PROFILE,
        help=(
            "generated Direct and Inverse cases per profile "
            f"(default: {FULL_RANDOM_PER_PROFILE})"
        ),
    )

    return parser.parse_args()


def normalize_version(raw: str) -> str:
    line = raw.strip().splitlines()[0]
    executable, separator, suffix = line.partition(":")

    if not separator:
        return line

    return f"{Path(executable).name}:{suffix}"


def verify_oracle(executable: Path) -> None:
    completed = subprocess.run(
        [str(executable), "--version"],
        text=True,
        capture_output=True,
        check=True,
    )

    actual = normalize_version(completed.stdout)

    if actual != EXPECTED_VERSION:
        raise SystemExit(
            "unexpected GeodSolve version:\n"
            f"  expected: {EXPECTED_VERSION}\n"
            f"  actual:   {actual}"
        )


def build_probe(compiler: str) -> Path:
    subprocess.run(
        [
            compiler,
            "-i",
            "-Isource",
            str(PROBE_SOURCE),
            f"-of={DEFAULT_PROBE}",
        ],
        cwd=ROOT,
        check=True,
    )

    return DEFAULT_PROBE


def f32(value: float) -> float:
    return struct.unpack("!f", struct.pack("!f", value))[0]


def scalar_value(value: float, scalar: str) -> float:
    if scalar == "float":
        return f32(value)

    return float(value)


def number(value: float) -> str:
    return format(value, ".17g")


def angle_number(value: float) -> str:
    return format(value, ".20f")


def rad_to_deg(value: float) -> float:
    return math.degrees(value)


def latitude_degrees_for_oracle(value: float) -> float:
    degrees = math.degrees(value)
    overshoot_limit = 1.0e-4

    if degrees > 90.0:
        if degrees <= 90.0 + overshoot_limit:
            return 90.0

        raise RuntimeError(
            f"candidate latitude exceeds +90 degrees: {degrees:.17g}"
        )

    if degrees < -90.0:
        if degrees >= -90.0 - overshoot_limit:
            return -90.0

        raise RuntimeError(
            f"candidate latitude exceeds -90 degrees: {degrees:.17g}"
        )

    return degrees


def wrap_degrees(value: float) -> float:
    result = math.remainder(value, 360.0)

    if result >= 180.0:
        result -= 360.0

    return result


def angle_difference(a: float, b: float) -> float:
    return math.remainder(a - b, 2.0 * math.pi)


def tangent_vector(
    latitude: float,
    longitude: float,
    azimuth: float,
) -> tuple[float, float, float]:
    slat = math.sin(latitude)
    clat = math.cos(latitude)
    slon = math.sin(longitude)
    clon = math.cos(longitude)
    sazi = math.sin(azimuth)
    cazi = math.cos(azimuth)

    north = (
        -slat * clon,
        -slat * slon,
        clat,
    )
    east = (
        -slon,
        clon,
        0.0,
    )

    return (
        cazi * north[0] + sazi * east[0],
        cazi * north[1] + sazi * east[1],
        cazi * north[2] + sazi * east[2],
    )


def vector_angle(
    first: tuple[float, float, float],
    second: tuple[float, float, float],
) -> float:
    dx = first[0] - second[0]
    dy = first[1] - second[1]
    dz = first[2] - second[2]
    chord = math.sqrt(dx * dx + dy * dy + dz * dz)
    chord = min(2.0, max(0.0, chord))
    return 2.0 * math.asin(chord / 2.0)


def tangent_error(
    lat_a: float,
    lon_a: float,
    azi_a: float,
    lat_b: float,
    lon_b: float,
    azi_b: float,
) -> float:
    return vector_angle(
        tangent_vector(lat_a, lon_a, azi_a),
        tangent_vector(lat_b, lon_b, azi_b),
    )


def antipodal_defect(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    # Spherical angular distance from point 2 to the antipode of point 1.
    clat1 = math.cos(lat1)
    clat2 = math.cos(lat2)

    first = (
        clat1 * math.cos(lon1),
        clat1 * math.sin(lon1),
        math.sin(lat1),
    )
    antipode_second = (
        -clat2 * math.cos(lon2),
        -clat2 * math.sin(lon2),
        -math.sin(lat2),
    )

    return vector_angle(first, antipode_second)


def raw_azimuth_well_conditioned(latitude: float) -> bool:
    return abs(math.cos(latitude)) >= 1.0e-7


def run_process(
    command: list[str],
    payload: str,
) -> list[str]:
    completed = subprocess.run(
        command,
        input=payload,
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

        details = "\n".join(error_lines[:20])

        raise RuntimeError(
            f"command failed ({completed.returncode}): "
            f"{' '.join(command)}\n"
            f"stderr:\n{completed.stderr}\n"
            f"stdout:\n{completed.stdout}\n"
            f"first ERROR lines:\n{details}"
        )

    lines = [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if any(line == "FAIL" for line in lines):
        raise RuntimeError(
            f"candidate probe reported FAIL: {' '.join(command)}"
        )

    return lines


def exact_command(
    geodsolve: Path,
    a: float,
    f: float,
    inverse: bool = False,
) -> list[str]:
    command = [
        str(geodsolve),
        "-E",
        "-e",
        number(a),
        number(f),
        "-p",
        "10",
    ]

    if inverse:
        command.insert(2, "-i")

    return command


def make_direct_cases(
    profile_index: int,
    count: int,
) -> list[DirectCase]:
    rng = random.Random(SEED ^ 0xD1EC7000 ^ profile_index)
    result = list(DIRECT_FIXED)

    for index in range(count):
        ratio = index / max(1, count)

        if ratio < 0.60:
            lat = rng.uniform(-89.9, 89.9)
            lon = rng.uniform(-180.0, 180.0)
            azi = rng.uniform(-180.0, 180.0)
            distance_a = rng.uniform(0.0, math.pi)

        elif ratio < 0.72:
            lat = rng.uniform(-89.0, 89.0)
            lon = rng.uniform(-180.0, 180.0)
            azi = rng.uniform(-180.0, 180.0)
            distance_a = 10.0 ** rng.uniform(-13.0, -3.0)

        elif ratio < 0.82:
            sign = -1.0 if rng.random() < 0.5 else 1.0
            offset = 10.0 ** rng.uniform(-8.0, -3.0)
            lat = sign * (90.0 - offset)
            lon = rng.uniform(-180.0, 180.0)
            azi = rng.uniform(-180.0, 180.0)
            distance_a = rng.uniform(0.0, 0.5)

        elif ratio < 0.90:
            lat = rng.uniform(-80.0, 80.0)
            lon = (
                rng.uniform(170.0, 180.0)
                if rng.random() < 0.5
                else rng.uniform(-180.0, -170.0)
            )
            azi = rng.uniform(-180.0, 180.0)
            distance_a = rng.uniform(0.0, math.pi)

        else:
            lat = rng.uniform(-80.0, 80.0)
            lon = rng.uniform(-180.0, 180.0)
            azi = rng.uniform(-180.0, 180.0)
            delta = 10.0 ** rng.uniform(-12.0, -3.0)
            distance_a = math.pi - delta

        if rng.random() < 0.5:
            distance_a = -distance_a

        result.append(
            DirectCase(
                f"random-{index:05d}",
                lat,
                lon,
                azi,
                distance_a,
            )
        )

    return result


def make_inverse_cases(
    profile_index: int,
    count: int,
    scalar: str,
) -> list[InverseCase]:
    rng = random.Random(SEED ^ 0x1A2B3000 ^ profile_index)
    result = list(INVERSE_FIXED)

    for index in range(count):
        ratio = index / max(1, count)

        if ratio < 0.60:
            lat1 = rng.uniform(-89.9, 89.9)
            lon1 = rng.uniform(-180.0, 180.0)
            lat2 = rng.uniform(-89.9, 89.9)
            lon2 = rng.uniform(-180.0, 180.0)
            tag = f"random-{index:05d}"

        elif ratio < 0.725:
            lat1 = rng.uniform(-89.0, 89.0)
            lon1 = rng.uniform(-180.0, 180.0)
            lat2 = max(
                -90.0,
                min(
                    90.0,
                    -lat1 + rng.uniform(-0.001, 0.001),
                ),
            )
            lon2 = wrap_degrees(
                lon1 + 180.0 + rng.uniform(-0.001, 0.001)
            )
            tag = f"near-antipodal-{index:05d}"

        elif ratio < 0.825:
            lat1 = rng.uniform(-89.0, 89.0)
            lon1 = rng.uniform(-180.0, 180.0)

            if scalar == "float":
                # Binary32 public coordinates need a larger, but still short,
                # separation to survive constructor/storage quantization.
                lat_delta = (
                    (-1.0 if rng.random() < 0.5 else 1.0)
                    * 10.0 ** rng.uniform(-4.5, -2.5)
                )
                lon_delta = (
                    (-1.0 if rng.random() < 0.5 else 1.0)
                    * 10.0 ** rng.uniform(-4.5, -2.5)
                )
            else:
                lat_delta = rng.uniform(-6.0e-8, 6.0e-8)
                lon_delta = rng.uniform(-6.0e-8, 6.0e-8)

            lat2 = max(
                -90.0,
                min(90.0, lat1 + lat_delta),
            )
            lon2 = wrap_degrees(lon1 + lon_delta)
            tag = f"short-{index:05d}"

        elif ratio < 0.90:
            if rng.random() < 0.5:
                lat1 = math.copysign(
                    90.0 - 10.0 ** rng.uniform(-8.0, -3.0),
                    -1.0 if rng.random() < 0.5 else 1.0,
                )
                lat2 = rng.uniform(-89.0, 89.0)
            else:
                lat1 = rng.uniform(-89.0, 89.0)
                lat2 = math.copysign(
                    90.0 - 10.0 ** rng.uniform(-8.0, -3.0),
                    -1.0 if rng.random() < 0.5 else 1.0,
                )

            lon1 = rng.uniform(-180.0, 180.0)
            lon2 = rng.uniform(-180.0, 180.0)
            tag = f"polar-{index:05d}"

        elif ratio < 0.95:
            lat1 = rng.uniform(-80.0, 80.0)
            lat2 = rng.uniform(-80.0, 80.0)
            lon1 = rng.uniform(170.0, 180.0)
            lon2 = rng.uniform(-180.0, -170.0)
            tag = f"dateline-{index:05d}"

        else:
            if rng.random() < 0.5:
                lat1 = rng.uniform(-89.0, 89.0)
                lat2 = rng.uniform(-89.0, 89.0)
                lon1 = rng.uniform(-180.0, 180.0)
                lon2 = lon1
                tag = f"meridian-{index:05d}"
            else:
                lat1 = 0.0
                lat2 = 0.0
                lon1 = rng.uniform(-180.0, 180.0)
                lon2 = rng.uniform(-180.0, 180.0)
                tag = f"equator-{index:05d}"

        result.append(
            InverseCase(
                tag,
                lat1,
                lon1,
                lat2,
                lon2,
                True,
            )
        )

    return result


def candidate_direct(
    probe: Path,
    scalar: str,
    profile: Profile,
    cases: list[DirectCase],
) -> list[tuple[float, ...]]:
    a = scalar_value(profile.a, scalar)
    f = scalar_value(profile.f, scalar)

    payload = "".join(
        (
            "D "
            f"{number(a)} {number(f)} "
            f"{number(scalar_value(case.lat1, scalar))} "
            f"{number(scalar_value(case.lon1, scalar))} "
            f"{number(scalar_value(case.azi1, scalar))} "
            f"{number(scalar_value(case.distance_over_a * a, scalar))}\n"
        )
        for case in cases
    )

    lines = run_process([str(probe), scalar], payload)

    if len(lines) != len(cases):
        raise RuntimeError(
            f"{scalar}:{profile.name}: candidate Direct returned "
            f"{len(lines)} rows for {len(cases)} cases"
        )

    rows: list[tuple[float, ...]] = []

    for line in lines:
        fields = line.split()

        if len(fields) != 8 or fields[0] != "D":
            raise RuntimeError(
                f"{scalar}:{profile.name}: malformed Direct row {line!r}"
            )

        rows.append(tuple(float(value) for value in fields[1:]))

    return rows


def candidate_inverse(
    probe: Path,
    scalar: str,
    profile: Profile,
    cases: list[InverseCase],
) -> list[tuple[float, ...]]:
    a = scalar_value(profile.a, scalar)
    f = scalar_value(profile.f, scalar)

    payload = "".join(
        (
            "I "
            f"{number(a)} {number(f)} "
            f"{number(scalar_value(case.lat1, scalar))} "
            f"{number(scalar_value(case.lon1, scalar))} "
            f"{number(scalar_value(case.lat2, scalar))} "
            f"{number(scalar_value(case.lon2, scalar))}\n"
        )
        for case in cases
    )

    lines = run_process([str(probe), scalar], payload)

    if len(lines) != len(cases):
        raise RuntimeError(
            f"{scalar}:{profile.name}: candidate Inverse returned "
            f"{len(lines)} rows for {len(cases)} cases"
        )

    rows: list[tuple[float, ...]] = []

    for line in lines:
        fields = line.split()

        if len(fields) != 8 or fields[0] != "I":
            raise RuntimeError(
                f"{scalar}:{profile.name}: malformed Inverse row {line!r}"
            )

        rows.append(tuple(float(value) for value in fields[1:]))

    return rows


def oracle_direct(
    geodsolve: Path,
    a: float,
    f: float,
    semantic_rows: list[tuple[float, ...]],
) -> list[tuple[float, float, float]]:
    payload = "".join(
        (
            f"{angle_number(latitude_degrees_for_oracle(row[0]))} "
            f"{angle_number(rad_to_deg(row[1]))} "
            f"{angle_number(rad_to_deg(row[2]))} "
            f"{number(row[3])}\n"
        )
        for row in semantic_rows
    )

    lines = run_process(
        exact_command(geodsolve, a, f, inverse=False),
        payload,
    )

    if len(lines) != len(semantic_rows):
        raise RuntimeError("GeodesicExact Direct row-count mismatch")

    result = []

    for line in lines:
        fields = line.split()

        if len(fields) < 3:
            raise RuntimeError(f"malformed GeodesicExact Direct row: {line}")

        result.append(
            (
                math.radians(float(fields[0])),
                math.radians(float(fields[1])),
                math.radians(float(fields[2])),
            )
        )

    return result


def oracle_inverse(
    geodsolve: Path,
    a: float,
    f: float,
    points: list[tuple[float, float, float, float]],
) -> list[tuple[float, float, float]]:
    payload = "".join(
        (
            f"{angle_number(latitude_degrees_for_oracle(lat1))} "
            f"{angle_number(rad_to_deg(lon1))} "
            f"{angle_number(latitude_degrees_for_oracle(lat2))} "
            f"{angle_number(rad_to_deg(lon2))}\n"
        )
        for lat1, lon1, lat2, lon2 in points
    )

    lines = run_process(
        exact_command(geodsolve, a, f, inverse=True),
        payload,
    )

    if len(lines) != len(points):
        raise RuntimeError("GeodesicExact Inverse row-count mismatch")

    result = []

    for line in lines:
        fields = line.split()

        if len(fields) < 3:
            raise RuntimeError(f"malformed GeodesicExact Inverse row: {line}")

        result.append(
            (
                math.radians(float(fields[0])),
                math.radians(float(fields[1])),
                float(fields[2]),
            )
        )

    return result


def direct_endpoint_errors(
    geodsolve: Path,
    a: float,
    f: float,
    candidate: list[tuple[float, ...]],
    expected: list[tuple[float, float, float]],
) -> list[float]:
    points = [
        (
            row[4],
            row[5],
            ref[0],
            ref[1],
        )
        for row, ref in zip(candidate, expected)
    ]

    inverse = oracle_inverse(geodsolve, a, f, points)
    return [abs(row[2]) / a for row in inverse]


def validate_direct_profile(
    geodsolve: Path,
    probe: Path,
    scalar: str,
    profile: Profile,
    profile_index: int,
    count: int,
) -> dict[str, float]:
    cases = make_direct_cases(profile_index, count)

    a = scalar_value(profile.a, scalar)
    f = scalar_value(profile.f, scalar)

    actual = candidate_direct(probe, scalar, profile, cases)
    expected = oracle_direct(geodsolve, a, f, actual)
    endpoint = direct_endpoint_errors(
        geodsolve,
        a,
        f,
        actual,
        expected,
    )

    max_endpoint = 0.0
    max_tangent = 0.0
    max_raw = 0.0

    for row, ref, endpoint_error in zip(actual, expected, endpoint):
        (
            _lat1,
            _lon1,
            _azi1,
            _distance,
            lat2,
            lon2,
            azi2,
        ) = row

        ref_lat2, ref_lon2, ref_azi2 = ref

        direction_error = tangent_error(
            lat2,
            lon2,
            azi2,
            ref_lat2,
            ref_lon2,
            ref_azi2,
        )

        max_endpoint = max(max_endpoint, endpoint_error)
        max_tangent = max(max_tangent, direction_error)

        if (
            raw_azimuth_well_conditioned(lat2)
            and raw_azimuth_well_conditioned(ref_lat2)
        ):
            max_raw = max(
                max_raw,
                abs(angle_difference(azi2, ref_azi2)),
            )

    return {
        "cases": float(len(cases)),
        "endpoint": max_endpoint,
        "tangent": max_tangent,
        "raw_azimuth": max_raw,
    }


def validate_inverse_profile(
    geodsolve: Path,
    probe: Path,
    scalar: str,
    profile: Profile,
    profile_index: int,
    count: int,
) -> dict[str, float]:
    cases = make_inverse_cases(profile_index, count, scalar)

    a = scalar_value(profile.a, scalar)
    f = scalar_value(profile.f, scalar)

    actual = candidate_inverse(probe, scalar, profile, cases)

    points = [
        (row[0], row[1], row[2], row[3])
        for row in actual
    ]

    oracle = oracle_inverse(geodsolve, a, f, points)

    closure_semantics: list[tuple[float, ...]] = []

    for row in actual:
        closure_semantics.append(
            (
                row[0],
                row[1],
                row[5],
                row[4],
                0.0,
                0.0,
                0.0,
            )
        )

    reached = oracle_direct(
        geodsolve,
        a,
        f,
        closure_semantics,
    )

    closure_points = [
        (
            reached_row[0],
            reached_row[1],
            row[2],
            row[3],
        )
        for reached_row, row in zip(reached, actual)
    ]

    closure_inverse = oracle_inverse(
        geodsolve,
        a,
        f,
        closure_points,
    )

    max_distance = 0.0
    max_closure = 0.0
    # Absolute tangent differences are diagnostic for all unique cases.
    # Near coincidence, inverse azimuth is intrinsically ill-conditioned, so
    # acceptance uses angular_length * direction_error instead.
    max_initial_tangent = 0.0
    max_final_tangent = 0.0
    max_initial_conditioned_tangent = 0.0
    max_final_conditioned_tangent = 0.0
    max_initial_short_transverse = 0.0
    max_final_short_transverse = 0.0
    max_initial_antipodal_conditioned = 0.0
    max_final_antipodal_conditioned = 0.0
    max_initial_raw = 0.0
    max_final_raw = 0.0
    worst_initial_tangent = None
    worst_final_tangent = None

    limits = LIMITS[scalar]

    for case, row, ref, closure in zip(
        cases,
        actual,
        oracle,
        closure_inverse,
    ):
        lat1, lon1, lat2, lon2, distance, azi1, azi2 = row
        ref_azi1, ref_azi2, ref_distance = ref

        distance_error = abs(distance - ref_distance) / a
        closure_error = abs(closure[2]) / a

        max_distance = max(max_distance, distance_error)
        max_closure = max(max_closure, closure_error)

        angular_length = abs(ref_distance) / a

        if not case.azimuth_unique or angular_length == 0.0:
            continue

        initial_direction = tangent_error(
            lat1,
            lon1,
            azi1,
            lat1,
            lon1,
            ref_azi1,
        )

        final_direction = tangent_error(
            lat2,
            lon2,
            azi2,
            lat2,
            lon2,
            ref_azi2,
        )

        initial_transverse = angular_length * initial_direction
        final_transverse = angular_length * final_direction

        if initial_direction > max_initial_tangent:
            max_initial_tangent = initial_direction
            worst_initial_tangent = (
                case.tag,
                angular_length,
                initial_direction,
                initial_transverse,
                azi1,
                ref_azi1,
            )

        if final_direction > max_final_tangent:
            max_final_tangent = final_direction
            worst_final_tangent = (
                case.tag,
                angular_length,
                final_direction,
                final_transverse,
                azi2,
                ref_azi2,
            )

        near_antipodal = case.tag.startswith("near-antipodal")

        if near_antipodal:
            defect = antipodal_defect(
                lat1,
                lon1,
                lat2,
                lon2,
            )
            max_initial_antipodal_conditioned = max(
                max_initial_antipodal_conditioned,
                defect * initial_direction,
            )
            max_final_antipodal_conditioned = max(
                max_final_antipodal_conditioned,
                defect * final_direction,
            )
        elif angular_length >= limits["well_conditioned"]:
            max_initial_conditioned_tangent = max(
                max_initial_conditioned_tangent,
                initial_direction,
            )
            max_final_conditioned_tangent = max(
                max_final_conditioned_tangent,
                final_direction,
            )
        else:
            max_initial_short_transverse = max(
                max_initial_short_transverse,
                initial_transverse,
            )
            max_final_short_transverse = max(
                max_final_short_transverse,
                final_transverse,
            )

        if (
            not near_antipodal
            and angular_length >= limits["well_conditioned"]
            and raw_azimuth_well_conditioned(lat1)
        ):
            max_initial_raw = max(
                max_initial_raw,
                abs(angle_difference(azi1, ref_azi1)),
            )

        if (
            not near_antipodal
            and angular_length >= limits["well_conditioned"]
            and raw_azimuth_well_conditioned(lat2)
        ):
            max_final_raw = max(
                max_final_raw,
                abs(angle_difference(azi2, ref_azi2)),
            )

    return {
        "cases": float(len(cases)),
        "distance": max_distance,
        "closure": max_closure,
        "initial_tangent": max_initial_tangent,
        "final_tangent": max_final_tangent,
        "initial_conditioned_tangent": max_initial_conditioned_tangent,
        "final_conditioned_tangent": max_final_conditioned_tangent,
        "initial_short_transverse": max_initial_short_transverse,
        "final_short_transverse": max_final_short_transverse,
        "initial_antipodal_conditioned": max_initial_antipodal_conditioned,
        "final_antipodal_conditioned": max_final_antipodal_conditioned,
        "initial_raw": max_initial_raw,
        "final_raw": max_final_raw,
        "worst_initial_tangent": worst_initial_tangent,
        "worst_final_tangent": worst_final_tangent,
    }


def check_finite(label: str, values: dict[str, object]) -> None:
    for key, value in values.items():
        if key == "cases" or key.startswith("worst_"):
            continue

        assert isinstance(value, float)

        if not math.isfinite(value):
            raise SystemExit(f"FAIL {label}: non-finite {key}: {value}")


def main() -> int:
    args = parse_args()

    if args.random_per_profile < 0:
        raise SystemExit("--random-per-profile must be >= 0")

    verify_oracle(args.geodsolve)

    probe = (
        args.probe
        if args.probe is not None
        else build_probe(args.compiler)
    )

    scalars = (
        ("float", "double", "real")
        if args.scalar == "all"
        else (args.scalar,)
    )

    full_gate = (
        args.random_per_profile >= FULL_RANDOM_PER_PROFILE
    )

    print(EXPECTED_VERSION)
    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{SEED:08X}")
    print(
        "generated cases per profile/operation: "
        f"{args.random_per_profile}"
    )
    print(
        "gate mode: "
        + ("FULL" if full_gate else "SMOKE / NON-ACCEPTANCE")
    )

    for scalar in scalars:
        limits = LIMITS[scalar]

        total_direct = 0
        total_inverse = 0

        aggregate_direct = {
            "endpoint": 0.0,
            "tangent": 0.0,
            "raw_azimuth": 0.0,
        }

        aggregate_inverse = {
            "distance": 0.0,
            "closure": 0.0,
            "initial_tangent": 0.0,
            "final_tangent": 0.0,
            "initial_conditioned_tangent": 0.0,
            "final_conditioned_tangent": 0.0,
            "initial_short_transverse": 0.0,
            "final_short_transverse": 0.0,
            "initial_antipodal_conditioned": 0.0,
            "final_antipodal_conditioned": 0.0,
            "initial_raw": 0.0,
            "final_raw": 0.0,
        }

        print()
        print(f"=== scalar: {scalar} ===")

        for profile_index, profile in enumerate(PROFILES):
            direct = validate_direct_profile(
                args.geodsolve,
                probe,
                scalar,
                profile,
                profile_index,
                args.random_per_profile,
            )

            inverse = validate_inverse_profile(
                args.geodsolve,
                probe,
                scalar,
                profile,
                profile_index,
                args.random_per_profile,
            )

            check_finite(
                f"{scalar}:{profile.name}:direct",
                direct,
            )
            check_finite(
                f"{scalar}:{profile.name}:inverse",
                inverse,
            )

            total_direct += int(direct["cases"])
            total_inverse += int(inverse["cases"])

            for key in aggregate_direct:
                aggregate_direct[key] = max(
                    aggregate_direct[key],
                    direct[key],
                )

            for key in aggregate_inverse:
                aggregate_inverse[key] = max(
                    aggregate_inverse[key],
                    inverse[key],
                )

            if inverse["worst_initial_tangent"] is not None:
                print(
                    f"  worst I.initial tangent: "
                    f"{inverse['worst_initial_tangent']}"
                )

            if inverse["worst_final_tangent"] is not None:
                print(
                    f"  worst I.final tangent: "
                    f"{inverse['worst_final_tangent']}"
                )

            print(
                f"{profile.name}: "
                f"D={int(direct['cases'])} "
                f"I={int(inverse['cases'])} "
                f"D.end={direct['endpoint']:.3e} "
                f"I.dist={inverse['distance']:.3e}"
            )

        print()
        print(f"{scalar} total Direct:  {total_direct}")
        print(f"{scalar} total Inverse: {total_inverse}")
        print(
            f"{scalar} max Direct endpoint: "
            f"{aggregate_direct['endpoint']:.17g}"
        )
        print(
            f"{scalar} max Direct tangent: "
            f"{aggregate_direct['tangent']:.17g}"
        )
        print(
            f"{scalar} max Direct raw final azimuth: "
            f"{aggregate_direct['raw_azimuth']:.17g}"
        )
        print(
            f"{scalar} max Inverse distance: "
            f"{aggregate_inverse['distance']:.17g}"
        )
        print(
            f"{scalar} max Inverse closure: "
            f"{aggregate_inverse['closure']:.17g}"
        )
        print(
            f"{scalar} max Inverse initial tangent: "
            f"{aggregate_inverse['initial_tangent']:.17g}"
        )
        print(
            f"{scalar} max Inverse final tangent: "
            f"{aggregate_inverse['final_tangent']:.17g}"
        )
        print(
            f"{scalar} max Inverse conditioned initial tangent: "
            f"{aggregate_inverse['initial_conditioned_tangent']:.17g}"
        )
        print(
            f"{scalar} max Inverse conditioned final tangent: "
            f"{aggregate_inverse['final_conditioned_tangent']:.17g}"
        )
        print(
            f"{scalar} max Inverse short initial transverse: "
            f"{aggregate_inverse['initial_short_transverse']:.17g}"
        )
        print(
            f"{scalar} max Inverse short final transverse: "
            f"{aggregate_inverse['final_short_transverse']:.17g}"
        )
        print(
            f"{scalar} max Inverse near-antipodal initial conditioned: "
            f"{aggregate_inverse['initial_antipodal_conditioned']:.17g}"
        )
        print(
            f"{scalar} max Inverse near-antipodal final conditioned: "
            f"{aggregate_inverse['final_antipodal_conditioned']:.17g}"
        )
        print(
            f"{scalar} max Inverse raw initial azimuth: "
            f"{aggregate_inverse['initial_raw']:.17g}"
        )
        print(
            f"{scalar} max Inverse raw final azimuth: "
            f"{aggregate_inverse['final_raw']:.17g}"
        )

        checks = (
            (
                aggregate_direct["endpoint"],
                limits["direct_endpoint"],
                "Direct endpoint",
            ),
            (
                aggregate_direct["tangent"],
                limits["direct_tangent"],
                "Direct final tangent",
            ),
            (
                aggregate_direct["raw_azimuth"],
                limits["direct_raw_azimuth"],
                "Direct raw final azimuth",
            ),
            (
                aggregate_inverse["distance"],
                limits["inverse_distance"],
                "Inverse distance",
            ),
            (
                aggregate_inverse["closure"],
                limits["inverse_closure"],
                "Inverse closure",
            ),
            (
                aggregate_inverse["initial_conditioned_tangent"],
                limits["inverse_tangent"],
                "Inverse conditioned initial tangent",
            ),
            (
                aggregate_inverse["final_conditioned_tangent"],
                limits["inverse_tangent"],
                "Inverse conditioned final tangent",
            ),
            (
                aggregate_inverse["initial_short_transverse"],
                limits["inverse_tangent"],
                "Inverse short initial transverse",
            ),
            (
                aggregate_inverse["final_short_transverse"],
                limits["inverse_tangent"],
                "Inverse short final transverse",
            ),
            (
                aggregate_inverse["initial_antipodal_conditioned"],
                limits["inverse_tangent"],
                "Inverse near-antipodal initial conditioned",
            ),
            (
                aggregate_inverse["final_antipodal_conditioned"],
                limits["inverse_tangent"],
                "Inverse near-antipodal final conditioned",
            ),
            (
                aggregate_inverse["initial_raw"],
                limits["inverse_raw_azimuth"],
                "Inverse raw initial azimuth",
            ),
            (
                aggregate_inverse["final_raw"],
                limits["inverse_raw_azimuth"],
                "Inverse raw final azimuth",
            ),
        )

        for actual, limit, label in checks:
            if actual > limit:
                raise SystemExit(
                    f"FAIL {scalar}: {label} {actual:.17g} "
                    f"> {limit:.17g}"
                )

        if full_gate:
            if total_direct < 40_000:
                raise SystemExit(
                    f"FAIL {scalar}: only {total_direct} Direct cases"
                )

            if total_inverse < 40_000:
                raise SystemExit(
                    f"FAIL {scalar}: only {total_inverse} Inverse cases"
                )

        print(f"{scalar}: PASS")

    if full_gate:
        print()
        print("GEO-C Exact public differential validation: PASS")
    else:
        print()
        print(
            "GEO-C smoke validation: PASS "
            "(not sufficient for GEO-C acceptance)"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
