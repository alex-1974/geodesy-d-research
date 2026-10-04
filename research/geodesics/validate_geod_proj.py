#!/usr/bin/env python3
"""
GEO-D public geodesic interoperability validation against PROJ.

PROJ is an external validation dependency only.  It is not linked into
geodesy-d production code and is not a DUB/runtime dependency.

The PROJ geodesic C API is double-only.  Therefore:
- float public values are compared after public float representation and then
  losslessly promoted to double for PROJ;
- double values are compared directly;
- real uses a corpus generated in the binary64 subset so the represented
  public real inputs are exactly representable by the PROJ API.

Wide-real (>binary64) precision is qualified independently by GEO-C's
MPFR-512 gate.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
from pathlib import Path
import random
import shlex
import struct
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
PUBLIC_PROBE_SOURCE = ROOT / "research/geodesics/geod_proj_public_probe.d"
PROJ_PROBE_SOURCE = ROOT / "research/geodesics/proj_geodesic_probe.cpp"

SEED = 0x47454F44
FULL_CASES_PER_PROFILE = 2000
EXPECTED_PROJ_VERSION = "9.7.1"
MAX_FLATTENING = 0.01


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
    Profile("mid-f", 7_000_000.0, 0.005),
    Profile("max-f", 7_000_000.0, 0.01),
    Profile("unit-scale", 1.0, 1.0 / 298.257223563),
)

LIMITS = {
    "float": {
        "direct_endpoint": 1.0e-6,
        "direct_tangent": 1.0e-5,
        "inverse_distance": 2.0e-6,
        "inverse_tangent": 1.0e-5,
        "well_conditioned": 1.0e-5,
    },
    "double": {
        "direct_endpoint": 2.0e-10,
        "direct_tangent": 2.0e-10,
        "inverse_distance": 2.0e-10,
        "inverse_tangent": 2.0e-10,
        "well_conditioned": 1.0e-6,
    },
    "real": {
        "direct_endpoint": 2.0e-10,
        "direct_tangent": 2.0e-10,
        "inverse_distance": 2.0e-10,
        "inverse_tangent": 2.0e-10,
        "well_conditioned": 1.0e-6,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument(
        "--random-per-profile",
        type=int,
        default=FULL_CASES_PER_PROFILE,
    )
    return parser.parse_args()


def f32(value: float) -> float:
    return struct.unpack("!f", struct.pack("!f", value))[0]


def scalar_value(value: float, scalar: str) -> float:
    if scalar == "float":
        return f32(value)
    return float(value)


def profile_flattening(profile: Profile, scalar: str) -> float:
    """
    Return the flattening actually used by one public scalar profile.

    PROJ accepts binary64 values.  For public real, binary64(0.01) widens
    exactly to a value slightly greater than the more precise real-valued
    contract boundary 0.01.  The real interoperability profile therefore
    uses the immediately preceding binary64 value, which is the largest
    binary64 flattening strictly inside the supported real domain.

    float and double retain their normal represented 0.01 boundary value.
    """
    value = scalar_value(profile.f, scalar)

    if scalar == "real" and profile.f == MAX_FLATTENING:
        return math.nextafter(MAX_FLATTENING, 0.0)

    return value


def number(value: float) -> str:
    return format(value, ".17g")


def binary64_bits(value: float) -> int:
    """Return the exact IEEE-754 binary64 bit pattern of *value*."""
    return struct.unpack("!Q", struct.pack("!d", float(value)))[0]


def candidate_bits(value: float) -> str:
    """Serialize one candidate input as an exact binary64 bit pattern."""
    return str(binary64_bits(value))


def wrap_radians(value: float) -> float:
    result = math.remainder(value, 2.0 * math.pi)
    if result >= math.pi:
        result -= 2.0 * math.pi
    return result


def clamp_latitude(value: float) -> float:
    return max(-math.pi / 2.0, min(math.pi / 2.0, value))


def point_vector(lat: float, lon: float) -> tuple[float, float, float]:
    clat = math.cos(lat)
    return (
        clat * math.cos(lon),
        clat * math.sin(lon),
        math.sin(lat),
    )


def cross(
    a: tuple[float, float, float],
    b: tuple[float, float, float],
) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(
    a: tuple[float, float, float],
    b: tuple[float, float, float],
) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(value: tuple[float, float, float]) -> float:
    return math.sqrt(dot(value, value))


def vector_angle(
    a: tuple[float, float, float],
    b: tuple[float, float, float],
) -> float:
    return math.atan2(norm(cross(a, b)), dot(a, b))


def tangent_vector(
    lat: float,
    lon: float,
    azi: float,
) -> tuple[float, float, float]:
    slat = math.sin(lat)
    clat = math.cos(lat)
    slon = math.sin(lon)
    clon = math.cos(lon)
    sazi = math.sin(azi)
    cazi = math.cos(azi)

    north = (-slat * clon, -slat * slon, clat)
    east = (-slon, clon, 0.0)

    return (
        cazi * north[0] + sazi * east[0],
        cazi * north[1] + sazi * east[1],
        cazi * north[2] + sazi * east[2],
    )


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
    first = point_vector(lat1, lon1)
    second = point_vector(lat2, lon2)
    antipode_second = (-second[0], -second[1], -second[2])
    return vector_angle(first, antipode_second)


def build_public_probe(compiler: str) -> Path:
    output = Path(f"/tmp/geodesy-geod-proj-public-{compiler}")
    subprocess.run(
        [
            compiler,
            "-i",
            "-Isource",
            str(PUBLIC_PROBE_SOURCE),
            f"-of={output}",
        ],
        cwd=ROOT,
        check=True,
    )
    return output


def pkg_config(*args: str) -> str:
    completed = subprocess.run(
        ["pkg-config", *args, "proj"],
        text=True,
        capture_output=True,
        check=True,
    )
    return completed.stdout.strip()


def verify_proj() -> None:
    actual = pkg_config("--modversion")
    if actual != EXPECTED_PROJ_VERSION:
        raise SystemExit(
            f"unexpected PROJ version: expected {EXPECTED_PROJ_VERSION}, "
            f"got {actual}"
        )


def build_proj_probe() -> Path:
    output = Path("/tmp/geodesy-geod-proj-c-probe")
    flags = shlex.split(pkg_config("--cflags", "--libs"))

    subprocess.run(
        [
            "c++",
            "-std=c++17",
            "-O2",
            str(PROJ_PROBE_SOURCE),
            "-o",
            str(output),
            *flags,
        ],
        cwd=ROOT,
        check=True,
    )
    return output


def run_probe(
    executable: Path,
    args: list[str],
    payload: str,
) -> list[str]:
    completed = subprocess.run(
        [str(executable), *args],
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{executable} failed with {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    return [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]


def parse_candidate(
    lines: list[str],
    prefix: str,
    count: int,
) -> list[tuple[float, ...]]:
    rows = []
    for line in lines:
        fields = line.split()
        if len(fields) != count + 1 or fields[0] != prefix:
            raise RuntimeError(f"malformed candidate row: {line!r}")
        rows.append(tuple(float(value) for value in fields[1:]))
    return rows


def parse_proj(
    lines: list[str],
    prefix: str,
) -> list[tuple[float, float, float]]:
    rows = []
    for line in lines:
        fields = line.split()
        if len(fields) != 4 or fields[0] != prefix:
            raise RuntimeError(f"malformed PROJ row: {line!r}")
        rows.append(tuple(float(value) for value in fields[1:]))
    return rows


def fixed_direct_cases() -> list[DirectCase]:
    return [
        DirectCase("zero", 0.0, 0.0, 0.0, 0.0),
        DirectCase("equator-east", 0.0, 0.0, math.pi / 2.0, 0.15),
        DirectCase(
            "negative-distance",
            math.radians(23.0),
            math.radians(-41.0),
            math.radians(117.0),
            -0.6,
        ),
        DirectCase(
            "dateline",
            math.radians(3.0),
            math.radians(179.8),
            math.radians(91.0),
            0.03,
        ),
        DirectCase(
            "north-pole-start",
            math.pi / 2.0,
            math.radians(17.0),
            math.radians(90.0),
            0.2,
        ),
        DirectCase(
            "long",
            math.radians(-23.0),
            math.radians(17.0),
            math.radians(37.0),
            math.pi,
        ),
    ]


def fixed_inverse_cases() -> list[InverseCase]:
    return [
        InverseCase("coincident", 0.0, 0.0, 0.0, 0.0, False),
        InverseCase(
            "equator",
            0.0,
            0.0,
            0.0,
            math.radians(71.0),
        ),
        InverseCase(
            "meridian",
            math.radians(-41.0),
            math.radians(17.0),
            math.radians(52.0),
            math.radians(17.0),
        ),
        InverseCase(
            "near-antipodal-fixed",
            math.radians(12.0),
            math.radians(33.0),
            math.radians(-12.00001),
            math.radians(-147.00002),
        ),
        InverseCase(
            "exact-antipodal",
            0.0,
            0.0,
            0.0,
            -math.pi,
            False,
        ),
        InverseCase(
            "opposite-poles",
            math.pi / 2.0,
            math.radians(20.0),
            -math.pi / 2.0,
            math.radians(-70.0),
            False,
        ),
    ]


def make_direct_cases(
    profile_index: int,
    count: int,
) -> list[DirectCase]:
    rng = random.Random(SEED ^ 0xD1EC7000 ^ profile_index)
    cases = fixed_direct_cases()

    for index in range(count):
        ratio = rng.random()

        if ratio < 0.60:
            lat = math.radians(rng.uniform(-80.0, 80.0))
            lon = math.radians(rng.uniform(-180.0, 180.0))
            azi = math.radians(rng.uniform(-180.0, 180.0))
            distance = rng.uniform(-2.8, 2.8)
            tag = f"random-{index:05d}"
        elif ratio < 0.72:
            lat = math.radians(rng.uniform(-80.0, 80.0))
            lon = math.radians(rng.uniform(-180.0, 180.0))
            azi = math.radians(rng.uniform(-180.0, 180.0))
            distance = rng.uniform(-1.0e-6, 1.0e-6)
            tag = f"short-{index:05d}"
        elif ratio < 0.84:
            lat = math.radians(
                rng.choice((-1.0, 1.0))
                * rng.uniform(88.0, 89.999)
            )
            lon = math.radians(rng.uniform(-180.0, 180.0))
            azi = math.radians(rng.uniform(-180.0, 180.0))
            distance = rng.uniform(-1.0, 1.0)
            tag = f"polar-{index:05d}"
        elif ratio < 0.94:
            lat = math.radians(rng.uniform(-60.0, 60.0))
            lon = math.radians(
                rng.choice((-1.0, 1.0))
                * rng.uniform(179.0, 180.0)
            )
            azi = math.radians(rng.uniform(70.0, 110.0))
            if rng.random() < 0.5:
                azi = -azi
            distance = rng.uniform(0.01, 0.5)
            tag = f"dateline-{index:05d}"
        else:
            lat = math.radians(rng.uniform(-60.0, 60.0))
            lon = math.radians(rng.uniform(-180.0, 180.0))
            azi = math.radians(rng.uniform(-180.0, 180.0))
            distance = rng.uniform(2.8, 3.4)
            tag = f"half-scale-{index:05d}"

        cases.append(DirectCase(tag, lat, lon, azi, distance))

    return cases


def make_inverse_cases(
    profile_index: int,
    count: int,
    scalar: str,
) -> list[InverseCase]:
    rng = random.Random(SEED ^ 0x1A2B3000 ^ profile_index)
    cases = fixed_inverse_cases()

    for index in range(count):
        ratio = rng.random()

        if ratio < 0.58:
            lat1 = math.radians(rng.uniform(-80.0, 80.0))
            lon1 = math.radians(rng.uniform(-180.0, 180.0))
            lat2 = math.radians(rng.uniform(-80.0, 80.0))
            lon2 = math.radians(rng.uniform(-180.0, 180.0))
            tag = f"random-{index:05d}"
        elif ratio < 0.70:
            lat1 = math.radians(rng.uniform(-80.0, 80.0))
            lon1 = math.radians(rng.uniform(-180.0, 180.0))

            if scalar == "float":
                dlat = math.radians(
                    rng.choice((-1.0, 1.0))
                    * 10.0 ** rng.uniform(-4.5, -2.5)
                )
                dlon = math.radians(
                    rng.choice((-1.0, 1.0))
                    * 10.0 ** rng.uniform(-4.5, -2.5)
                )
            else:
                dlat = math.radians(rng.uniform(-6.0e-8, 6.0e-8))
                dlon = math.radians(rng.uniform(-6.0e-8, 6.0e-8))

            lat2 = clamp_latitude(lat1 + dlat)
            lon2 = wrap_radians(lon1 + dlon)
            tag = f"short-{index:05d}"
        elif ratio < 0.80:
            sign = rng.choice((-1.0, 1.0))
            lat1 = math.radians(sign * rng.uniform(88.0, 89.999))
            lon1 = math.radians(rng.uniform(-180.0, 180.0))
            lat2 = math.radians(rng.uniform(-70.0, 70.0))
            lon2 = math.radians(rng.uniform(-180.0, 180.0))
            tag = f"polar-{index:05d}"
        elif ratio < 0.87:
            lat1 = math.radians(rng.uniform(-60.0, 60.0))
            lon1 = math.radians(rng.uniform(170.0, 180.0))
            lat2 = math.radians(rng.uniform(-60.0, 60.0))
            lon2 = math.radians(rng.uniform(-180.0, -170.0))
            tag = f"dateline-{index:05d}"
        else:
            lat1_deg = rng.uniform(-70.0, 70.0)
            lon1_deg = rng.uniform(-180.0, 180.0)
            lat2_deg = -lat1_deg + rng.uniform(-2.0e-4, 2.0e-4)
            lon2_deg = lon1_deg + 180.0 + rng.uniform(-2.0e-4, 2.0e-4)

            lat1 = math.radians(lat1_deg)
            lon1 = math.radians(lon1_deg)
            lat2 = math.radians(max(-90.0, min(90.0, lat2_deg)))
            lon2 = wrap_radians(math.radians(lon2_deg))
            tag = f"near-antipodal-{index:05d}"

        cases.append(
            InverseCase(tag, lat1, lon1, lat2, lon2, True)
        )

    return cases


def candidate_direct(
    executable: Path,
    scalar: str,
    profile: Profile,
    cases: list[DirectCase],
) -> tuple[float, float, list[tuple[float, ...]]]:
    a = scalar_value(profile.a, scalar)
    f = profile_flattening(profile, scalar)

    payload = "".join(
        "D "
        f"{candidate_bits(a)} {candidate_bits(f)} "
        f"{candidate_bits(scalar_value(case.lat1, scalar))} "
        f"{candidate_bits(scalar_value(case.lon1, scalar))} "
        f"{candidate_bits(scalar_value(case.azi1, scalar))} "
        f"{candidate_bits(scalar_value(case.distance_over_a * a, scalar))}\n"
        for case in cases
    )

    rows = parse_candidate(
        run_probe(executable, [scalar], payload),
        "D",
        7,
    )

    if len(rows) != len(cases):
        raise RuntimeError("candidate Direct row-count mismatch")

    return a, f, rows


def candidate_inverse(
    executable: Path,
    scalar: str,
    profile: Profile,
    cases: list[InverseCase],
) -> tuple[float, float, list[tuple[float, ...]]]:
    a = scalar_value(profile.a, scalar)
    f = profile_flattening(profile, scalar)

    payload = "".join(
        "I "
        f"{candidate_bits(a)} {candidate_bits(f)} "
        f"{candidate_bits(scalar_value(case.lat1, scalar))} "
        f"{candidate_bits(scalar_value(case.lon1, scalar))} "
        f"{candidate_bits(scalar_value(case.lat2, scalar))} "
        f"{candidate_bits(scalar_value(case.lon2, scalar))}\n"
        for case in cases
    )

    rows = parse_candidate(
        run_probe(executable, [scalar], payload),
        "I",
        7,
    )

    if len(rows) != len(cases):
        raise RuntimeError("candidate Inverse row-count mismatch")

    return a, f, rows


def proj_direct(
    executable: Path,
    a: float,
    f: float,
    rows: list[tuple[float, ...]],
) -> list[tuple[float, float, float]]:
    payload = "".join(
        "D "
        f"{number(a)} {number(f)} "
        f"{number(row[0])} {number(row[1])} "
        f"{number(row[2])} {number(row[3])}\n"
        for row in rows
    )
    result = parse_proj(run_probe(executable, [], payload), "D")
    if len(result) != len(rows):
        raise RuntimeError("PROJ Direct row-count mismatch")
    return result


def proj_inverse(
    executable: Path,
    a: float,
    f: float,
    rows: list[tuple[float, ...]],
) -> list[tuple[float, float, float]]:
    payload = "".join(
        "I "
        f"{number(a)} {number(f)} "
        f"{number(row[0])} {number(row[1])} "
        f"{number(row[2])} {number(row[3])}\n"
        for row in rows
    )
    result = parse_proj(run_probe(executable, [], payload), "I")
    if len(result) != len(rows):
        raise RuntimeError("PROJ Inverse row-count mismatch")
    return result


def validate_direct_profile(
    public_probe: Path,
    proj_probe: Path,
    scalar: str,
    profile: Profile,
    cases: list[DirectCase],
) -> dict[str, float]:
    a, f, actual = candidate_direct(
        public_probe,
        scalar,
        profile,
        cases,
    )
    expected = proj_direct(proj_probe, a, f, actual)

    max_endpoint = 0.0
    max_tangent = 0.0

    for row, ref in zip(actual, expected):
        _, _, _, _, lat2, lon2, azi2 = row
        ref_lat2, ref_lon2, ref_azi2 = ref

        endpoint = vector_angle(
            point_vector(lat2, lon2),
            point_vector(ref_lat2, ref_lon2),
        )
        direction = tangent_error(
            lat2, lon2, azi2,
            ref_lat2, ref_lon2, ref_azi2,
        )

        max_endpoint = max(max_endpoint, endpoint)
        max_tangent = max(max_tangent, direction)

    return {
        "endpoint": max_endpoint,
        "tangent": max_tangent,
    }


def validate_inverse_profile(
    public_probe: Path,
    proj_probe: Path,
    scalar: str,
    profile: Profile,
    cases: list[InverseCase],
) -> dict[str, float]:
    limits = LIMITS[scalar]

    a, f, actual = candidate_inverse(
        public_probe,
        scalar,
        profile,
        cases,
    )
    expected = proj_inverse(proj_probe, a, f, actual)

    metrics = {
        "distance": 0.0,
        "ordinary_initial": 0.0,
        "ordinary_final": 0.0,
        "short_initial": 0.0,
        "short_final": 0.0,
        "antipodal_initial": 0.0,
        "antipodal_final": 0.0,
    }

    for case, row, ref in zip(cases, actual, expected):
        lat1, lon1, lat2, lon2, distance, azi1, azi2 = row
        ref_distance, ref_azi1, ref_azi2 = ref

        distance_error = abs(distance - ref_distance) / a
        metrics["distance"] = max(metrics["distance"], distance_error)

        if not case.azimuth_unique:
            continue

        initial = tangent_error(
            lat1, lon1, azi1,
            lat1, lon1, ref_azi1,
        )
        final = tangent_error(
            lat2, lon2, azi2,
            lat2, lon2, ref_azi2,
        )

        angular_length = abs(ref_distance) / a

        if case.tag.startswith("near-antipodal"):
            defect = antipodal_defect(lat1, lon1, lat2, lon2)
            metrics["antipodal_initial"] = max(
                metrics["antipodal_initial"],
                defect * initial,
            )
            metrics["antipodal_final"] = max(
                metrics["antipodal_final"],
                defect * final,
            )
        elif angular_length < limits["well_conditioned"]:
            metrics["short_initial"] = max(
                metrics["short_initial"],
                angular_length * initial,
            )
            metrics["short_final"] = max(
                metrics["short_final"],
                angular_length * final,
            )
        else:
            metrics["ordinary_initial"] = max(
                metrics["ordinary_initial"],
                initial,
            )
            metrics["ordinary_final"] = max(
                metrics["ordinary_final"],
                final,
            )

    return metrics


def update_max(
    aggregate: dict[str, float],
    current: dict[str, float],
) -> None:
    for key, value in current.items():
        aggregate[key] = max(aggregate.get(key, 0.0), value)


def audit_real_transport(
    public_probe: Path,
    count: int,
) -> None:
    """Prove that GEO-D real inputs stay in the exact binary64 subset."""
    values: set[int] = set()

    for profile_index, profile in enumerate(PROFILES):
        values.add(binary64_bits(profile.a))
        values.add(binary64_bits(profile_flattening(profile, "real")))

        for case in make_direct_cases(profile_index, count):
            values.add(binary64_bits(case.lat1))
            values.add(binary64_bits(case.lon1))
            values.add(binary64_bits(case.azi1))
            values.add(binary64_bits(case.distance_over_a * profile.a))

        for case in make_inverse_cases(profile_index, count, "real"):
            values.add(binary64_bits(case.lat1))
            values.add(binary64_bits(case.lon1))
            values.add(binary64_bits(case.lat2))
            values.add(binary64_bits(case.lon2))

    ordered = sorted(values)
    payload = "".join(f"B {bits}\n" for bits in ordered)
    lines = run_probe(public_probe, ["real"], payload)

    if len(lines) != len(ordered):
        raise RuntimeError(
            "real transport audit row-count mismatch: "
            f"{len(lines)} != {len(ordered)}"
        )

    mismatches = 0
    for expected_bits, line in zip(ordered, lines):
        fields = line.split()
        if len(fields) != 2 or fields[0] != "B":
            raise RuntimeError(f"malformed transport-audit row: {line!r}")

        actual_bits = int(fields[1])
        if actual_bits != expected_bits:
            mismatches += 1

    print(f"real transport audit unique binary64 inputs: {len(ordered)}")
    print(f"real transport audit mismatches: {mismatches}")

    if mismatches:
        raise SystemExit(
            "FAIL real transport: binary64 -> real -> binary64 changed bits"
        )

    print("real transport audit: PASS")


def validate_scalar(
    public_probe: Path,
    proj_probe: Path,
    scalar: str,
    count: int,
) -> None:
    limits = LIMITS[scalar]
    direct_total = 0
    inverse_total = 0

    direct_aggregate = {"endpoint": 0.0, "tangent": 0.0}
    inverse_aggregate: dict[str, float] = {}

    for profile_index, profile in enumerate(PROFILES):
        direct_cases = make_direct_cases(profile_index, count)
        inverse_cases = make_inverse_cases(profile_index, count, scalar)

        direct_metrics = validate_direct_profile(
            public_probe,
            proj_probe,
            scalar,
            profile,
            direct_cases,
        )
        inverse_metrics = validate_inverse_profile(
            public_probe,
            proj_probe,
            scalar,
            profile,
            inverse_cases,
        )

        direct_total += len(direct_cases)
        inverse_total += len(inverse_cases)
        update_max(direct_aggregate, direct_metrics)
        update_max(inverse_aggregate, inverse_metrics)

        print(
            f"{profile.name}: "
            f"D={len(direct_cases)} I={len(inverse_cases)} "
            f"D.end={direct_metrics['endpoint']:.3e} "
            f"I.dist={inverse_metrics['distance']:.3e}"
        )

    print()
    print(f"{scalar} total Direct:  {direct_total}")
    print(f"{scalar} total Inverse: {inverse_total}")
    print(
        f"{scalar} max Direct endpoint: "
        f"{direct_aggregate['endpoint']:.17g}"
    )
    print(
        f"{scalar} max Direct tangent: "
        f"{direct_aggregate['tangent']:.17g}"
    )

    for key in (
        "distance",
        "ordinary_initial",
        "ordinary_final",
        "short_initial",
        "short_final",
        "antipodal_initial",
        "antipodal_final",
    ):
        print(
            f"{scalar} max Inverse {key}: "
            f"{inverse_aggregate.get(key, 0.0):.17g}"
        )

    checks = (
        (
            direct_aggregate["endpoint"],
            limits["direct_endpoint"],
            "Direct endpoint",
        ),
        (
            direct_aggregate["tangent"],
            limits["direct_tangent"],
            "Direct tangent",
        ),
        (
            inverse_aggregate.get("distance", 0.0),
            limits["inverse_distance"],
            "Inverse distance",
        ),
        (
            inverse_aggregate.get("ordinary_initial", 0.0),
            limits["inverse_tangent"],
            "Inverse ordinary initial",
        ),
        (
            inverse_aggregate.get("ordinary_final", 0.0),
            limits["inverse_tangent"],
            "Inverse ordinary final",
        ),
        (
            inverse_aggregate.get("short_initial", 0.0),
            limits["inverse_tangent"],
            "Inverse short initial",
        ),
        (
            inverse_aggregate.get("short_final", 0.0),
            limits["inverse_tangent"],
            "Inverse short final",
        ),
        (
            inverse_aggregate.get("antipodal_initial", 0.0),
            limits["inverse_tangent"],
            "Inverse antipodal initial",
        ),
        (
            inverse_aggregate.get("antipodal_final", 0.0),
            limits["inverse_tangent"],
            "Inverse antipodal final",
        ),
    )

    for value, limit, label in checks:
        if value > limit:
            raise SystemExit(
                f"FAIL {scalar}: {label} {value} > {limit}"
            )

    print(f"{scalar}: PASS")


def main() -> int:
    args = parse_args()

    if args.random_per_profile <= 0:
        raise SystemExit("--random-per-profile must be > 0")

    verify_proj()
    public_probe = build_public_probe(args.compiler)
    proj_probe = build_proj_probe()

    full = args.random_per_profile >= FULL_CASES_PER_PROFILE

    print(f"PROJ: {EXPECTED_PROJ_VERSION}")
    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{SEED:08X}")
    print(
        "generated cases per profile/operation: "
        f"{args.random_per_profile}"
    )
    print("gate mode: " + ("FULL" if full else "SMOKE / NON-ACCEPTANCE"))
    print(
        "candidate input protocol: exact IEEE-754 binary64 bit patterns; "
        "angles are radians"
    )
    print(
        "real interop policy: binary64 bits -> double -> exact widening "
        "to D real; wide-real precision belongs to GEO-C"
    )
    print(
        "real max-f profile: nextDown(binary64(0.01)) = "
        f"{profile_flattening(PROFILES[6], 'real'):.17g}; "
        "this is the largest binary64 value inside the real f <= 0.01 domain"
    )
    audit_real_transport(public_probe, args.random_per_profile)
    print(
        "known semantic divergence: coincident/non-unique inverse azimuths "
        "are not normative and are excluded from azimuth gates"
    )

    for scalar in ("float", "double", "real"):
        print()
        print(f"=== scalar: {scalar} ===")
        validate_scalar(
            public_probe,
            proj_probe,
            scalar,
            args.random_per_profile,
        )

    if full:
        print()
        print("GEO-D PROJ public interoperability validation: PASS")
    else:
        print()
        print(
            "GEO-D PROJ interoperability smoke: PASS "
            "(not sufficient for acceptance)"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
