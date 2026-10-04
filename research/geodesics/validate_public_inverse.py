#!/usr/bin/env python3
"""
GEO-C validation of the public inverse geodesic API.

The probe exercises Geodesic!float, Geodesic!double, and Geodesic!real
through the public GeographicCoordinate/GeodesicInverseResult interface.

Oracle:
    GeographicLib GeodSolve 2.7 in exact mode (-E).

Checks:
    * inverse distance against GeodesicExact;
    * endpoint closure by exact direct reconstruction;
    * endpoint direction as an Earth-fixed 3D tangent vector;
    * GEO-A coincidence semantics (+0,+0,+0).

The Earth-fixed tangent metric is normative for endpoint direction because
raw local azimuth is coordinate-frame ill-conditioned near geographic poles.

For float, input values are quantized to the public scalar first and the
stored public coordinate values are then echoed by the D probe. The oracle is
fed those same semantic values, so constructor/input quantization is not
charged to the geodesic solver.

GeodSolve CLI precision is pinned to -p 10. GeographicLib clamps requested
precision to the build's supported maximum; for the ordinary double CLI this
also explains the ~5e-11 normalized unit-scale distance floor.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROBE = Path("/tmp/geodesy-public-inverse-probe")
DEFAULT_GEODSOLVE = Path("/usr/bin/GeodSolve")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--compiler",
        default="dmd",
        help="D compiler used to build the public probe (default: dmd)",
    )

    parser.add_argument(
        "--probe",
        type=Path,
        default=None,
        help="existing public inverse probe binary; skip compilation",
    )

    parser.add_argument(
        "--geodsolve",
        type=Path,
        default=DEFAULT_GEODSOLVE,
        help="GeodSolve executable",
    )

    return parser.parse_args()


def build_probe(compiler: str) -> Path:
    source = (
        ROOT
        / "research/geodesics/public_inverse_probe.d"
    )

    subprocess.run(
        [
            compiler,
            "-i",
            "-Isource",
            str(source),
            f"-of={DEFAULT_PROBE}",
        ],
        cwd=ROOT,
        check=True,
    )

    return DEFAULT_PROBE


args = parse_args()
probe = str(
    args.probe
    if args.probe is not None
    else build_probe(args.compiler)
)
geodsolve = str(args.geodsolve)

EXPECTED_VERSION = "GeodSolve: GeographicLib version 2.7"
SEED = 0x47454F50

PROFILES = (
    ("sphere", 6_371_000.0, 0.0),
    ("wgs84", 6_378_137.0, 1.0 / 298.257223563),
    ("near-sphere", 6_378_137.0, 1e-6),
    ("mid-f", 7_000_000.0, 0.005),
    ("max-f", 7_000_000.0, 0.01),
    ("unit-scale", 1.0, 1.0 / 298.257223563),
    ("large-scale", 1e9, 1.0 / 298.257223563),
)

LIMITS = {
    "float": {
        "distance": 2e-6,
        "closure": 2e-6,
        "tangent": 2e-6,
        "well_conditioned": 1e-5,
    },
    "double": {
        "distance": 2e-10,
        "closure": 2e-10,
        "tangent": 2e-10,
        "well_conditioned": 1e-6,
    },
    "real": {
        "distance": 2e-10,
        "closure": 2e-10,
        "tangent": 2e-10,
        "well_conditioned": 1e-6,
    },
}


def normalize_version(raw: str) -> str:
    line = raw.strip().splitlines()[0]
    executable, separator, suffix = line.partition(":")

    if not separator:
        return line

    return f"{executable.rsplit('/', 1)[-1]}:{suffix}"


version = subprocess.run(
    [geodsolve, "--version"],
    text=True,
    capture_output=True,
    check=True,
).stdout

actual_version = normalize_version(version)

if actual_version != EXPECTED_VERSION:
    raise SystemExit(
        "unexpected GeodSolve version:\n"
        f"  expected: {EXPECTED_VERSION}\n"
        f"  actual:   {actual_version}"
    )


def f32(value: float) -> float:
    return struct.unpack(
        "!f",
        struct.pack("!f", value),
    )[0]


def quantize(value: float, scalar: str) -> float:
    if scalar == "float":
        return f32(value)

    return float(value)


def wrap_degrees(value: float) -> float:
    result = math.remainder(value, 360.0)

    if result >= 180.0:
        result -= 360.0

    if result < -180.0:
        result += 360.0

    return result


def angle_difference(a: float, b: float) -> float:
    return math.atan2(
        math.sin(a - b),
        math.cos(a - b),
    )


def semantic_degrees(
    radians: float,
    scalar: str,
) -> float:
    """
    Convert a stored public angular value to degrees for GeodSolve.

    Snap public cardinal constants before generic conversion.  This preserves
    the library contract that, e.g., float(pi) denotes the exact antimeridian
    even though its binary value is not double(pi).
    """

    if scalar == "float":
        p = f32(math.pi)
        hp = f32(math.pi / 2.0)
    else:
        p = math.pi
        hp = math.pi / 2.0

    if radians == p:
        return 180.0

    if radians == -p:
        return -180.0

    if radians == hp:
        return 90.0

    if radians == -hp:
        return -90.0

    if radians == 0.0:
        return 0.0

    return math.degrees(radians)



def semantic_radians(
    radians: float,
    scalar: str,
) -> float:
    """
    Interpret stored public cardinal constants as their exact mathematical
    angles before geometric comparison.
    """

    if scalar == "float":
        p = f32(math.pi)
        hp = f32(math.pi / 2.0)
    else:
        p = math.pi
        hp = math.pi / 2.0

    if radians == p:
        return math.pi

    if radians == -p:
        return -math.pi

    if radians == hp:
        return math.pi / 2.0

    if radians == -hp:
        return -math.pi / 2.0

    if radians == 0.0:
        return 0.0

    return radians


def tangent_direction(
    latitude: float,
    longitude: float,
    azimuth: float,
):
    """
    Unit tangent direction in an Earth-fixed Cartesian frame.

    North/east are formed from geodetic latitude/longitude.  Comparing these
    3D vectors avoids the coordinate-frame singularity of raw azimuth near a
    geographic pole.
    """

    sin_lat = math.sin(latitude)
    cos_lat = math.cos(latitude)
    sin_lon = math.sin(longitude)
    cos_lon = math.cos(longitude)

    north = (
        -sin_lat * cos_lon,
        -sin_lat * sin_lon,
        cos_lat,
    )

    east = (
        -sin_lon,
        cos_lon,
        0.0,
    )

    cos_azi = math.cos(azimuth)
    sin_azi = math.sin(azimuth)

    return (
        cos_azi * north[0] + sin_azi * east[0],
        cos_azi * north[1] + sin_azi * east[1],
        cos_azi * north[2] + sin_azi * east[2],
    )


def tangent_direction_error(
    latitude1: float,
    longitude1: float,
    azimuth1: float,
    latitude2: float,
    longitude2: float,
    azimuth2: float,
) -> float:
    first = tangent_direction(
        latitude1,
        longitude1,
        azimuth1,
    )

    second = tangent_direction(
        latitude2,
        longitude2,
        azimuth2,
    )

    dx = first[0] - second[0]
    dy = first[1] - second[1]
    dz = first[2] - second[2]

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


def surface_closure_angle(
    latitude1: float,
    longitude1: float,
    latitude2: float,
    longitude2: float,
) -> float:
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


FIXED_CASES = (
    (20.0, 30.0, 20.0, 30.0, "coincident"),
    (20.0, 180.0, 20.0, -180.0, "coincident-antimeridian"),
    (90.0, -120.0, 90.0, 70.0, "north-pole-coincident"),
    (-90.0, 10.0, -90.0, 170.0, "south-pole-coincident"),
    (-60.0, 10.0, 40.0, 10.0, "meridian-north"),
    (60.0, 10.0, -40.0, 10.0, "meridian-south"),
    (-20.0, 10.0, 20.0, -170.0, "opposite-meridian"),
    (0.0, 10.0, 0.0, 40.0, "equator-east"),
    (0.0, 40.0, 0.0, 10.0, "equator-west"),
    (0.0, 179.9, 0.0, -179.8, "equator-dateline"),
    (48.20849, 16.37208, 40.7128, -74.0060, "vienna-new-york"),
    (-33.8688, 151.2093, 35.6762, 139.6503, "sydney-tokyo"),
    (30.0, 179.9, 31.0, -179.8, "dateline-general"),
    (-10.0, 0.0, 10.0001, 179.99427042204869, "near-antipodal-a"),
    (-35.0, 20.0, 34.9999, -160.0002, "near-antipodal-b"),
    (
        20.0,
        30.0,
        20.0 + math.degrees(1e-10),
        30.0 + math.degrees(1e-10),
        "tiny",
    ),
)

COINCIDENT_TAGS = {
    "coincident",
    "coincident-antimeridian",
    "north-pole-coincident",
    "south-pole-coincident",
}


rng = random.Random(SEED)

cases = list(FIXED_CASES)

for index in range(320):
    lat1 = rng.uniform(-90.0, 90.0)
    lon1 = rng.uniform(-180.0, 180.0)

    if index < 40:
        lat2 = -lat1 + rng.uniform(-0.0006, 0.0006)
        lat2 = max(-90.0, min(90.0, lat2))
        lon2 = wrap_degrees(
            lon1
            + 180.0
            + rng.uniform(-0.0006, 0.0006)
        )
        tag = f"random-near-antipodal-{index:03d}"

    elif index < 70:
        lat2 = max(
            -90.0,
            min(
                90.0,
                lat1
                + rng.uniform(-6e-8, 6e-8),
            ),
        )
        lon2 = wrap_degrees(
            lon1
            + rng.uniform(-6e-8, 6e-8)
        )
        tag = f"random-short-{index:03d}"

    elif index < 90:
        lat2 = rng.uniform(-90.0, 90.0)
        lon2 = lon1
        tag = f"random-meridian-{index:03d}"

    elif index < 110:
        lat1 = 0.0
        lat2 = 0.0
        lon2 = rng.uniform(-180.0, 180.0)
        tag = f"random-equator-{index:03d}"

    elif index < 130:
        lon1 = rng.uniform(170.0, 180.0)
        lon2 = rng.uniform(-180.0, -170.0)
        lat2 = rng.uniform(-90.0, 90.0)
        tag = f"random-dateline-{index:03d}"

    else:
        lat2 = rng.uniform(-90.0, 90.0)
        lon2 = rng.uniform(-180.0, 180.0)
        tag = f"random-{index:03d}"

    cases.append(
        (
            lat1,
            lon1,
            lat2,
            lon2,
            tag,
        )
    )


for scalar in ("float", "double", "real"):
    limits = LIMITS[scalar]

    total = 0
    max_normalized_distance = 0.0
    max_closure = 0.0
    max_raw_final_azimuth = 0.0
    max_tangent_direction = 0.0

    worst_distance = None
    worst_closure = None
    worst_raw_final_azimuth = None
    worst_tangent_direction = None

    for profile, a0, f0 in PROFILES:
        a = quantize(a0, scalar)
        f = quantize(f0, scalar)

        input_rows = []

        for (
            lat1,
            lon1,
            lat2,
            lon2,
            tag,
        ) in cases:
            qlat1 = quantize(lat1, scalar)
            qlon1 = quantize(lon1, scalar)
            qlat2 = quantize(lat2, scalar)
            qlon2 = quantize(lon2, scalar)

            input_rows.append(
                (
                    qlat1,
                    qlon1,
                    qlat2,
                    qlon2,
                    tag,
                )
            )

        probe_payload = "".join(
            f"{a:.17g} {f:.17g} "
            f"{lat1:.17g} {lon1:.17g} "
            f"{lat2:.17g} {lon2:.17g}\n"
            for lat1, lon1, lat2, lon2, _ in input_rows
        )

        probe_run = subprocess.run(
            [probe, scalar],
            input=probe_payload,
            text=True,
            capture_output=True,
            check=True,
        )

        probe_lines = [
            line
            for line in probe_run.stdout.splitlines()
            if line.strip()
        ]

        if len(probe_lines) != len(input_rows):
            raise SystemExit(
                f"{scalar}:{profile}: probe returned "
                f"{len(probe_lines)} rows for {len(input_rows)} cases"
            )

        actual_rows = []
        inverse_payload_parts = []

        for source, line in zip(input_rows, probe_lines):
            if line == "FAIL":
                raise SystemExit(
                    f"{scalar}:{profile}:{source[-1]} "
                    "public tryInverse returned false"
                )

            fields = line.split()

            if len(fields) != 7:
                raise SystemExit(
                    f"{scalar}:{profile}:{source[-1]} "
                    f"malformed probe output: {line!r}"
                )

            (
                lat1r,
                lon1r,
                lat2r,
                lon2r,
                distance,
                azi1,
                azi2,
            ) = map(float, fields)

            actual_rows.append(
                (
                    lat1r,
                    lon1r,
                    lat2r,
                    lon2r,
                    distance,
                    azi1,
                    azi2,
                    source[-1],
                )
            )

            inverse_payload_parts.append(
                f"{semantic_degrees(lat1r, scalar):.17g} "
                f"{semantic_degrees(lon1r, scalar):.17g} "
                f"{semantic_degrees(lat2r, scalar):.17g} "
                f"{semantic_degrees(lon2r, scalar):.17g}\n"
            )

        inverse_run = subprocess.run(
            [
                geodsolve,
                "-E",
                "-i",
                "-e",
                f"{a:.17g}",
                f"{f:.17g}",
                "-p",
                "10",
            ],
            input="".join(inverse_payload_parts),
            text=True,
            capture_output=True,
            check=True,
        )

        inverse_lines = [
            line
            for line in inverse_run.stdout.splitlines()
            if line.strip()
        ]

        if len(inverse_lines) != len(actual_rows):
            raise SystemExit(
                f"{scalar}:{profile}: inverse oracle returned "
                f"{len(inverse_lines)} rows for {len(actual_rows)} cases"
            )

        rows_with_oracle = []
        direct_payload_parts = []

        for actual, oracle_line in zip(
            actual_rows,
            inverse_lines,
        ):
            oracle_fields = oracle_line.split()

            if len(oracle_fields) < 3:
                raise SystemExit(
                    f"{scalar}:{profile}:{actual[-1]} "
                    f"malformed inverse oracle: {oracle_line!r}"
                )

            expected_distance = float(
                oracle_fields[2]
            )

            rows_with_oracle.append(
                actual
                + (expected_distance,)
            )

            (
                lat1r,
                lon1r,
                _,
                _,
                distance,
                azi1,
                _,
                _,
            ) = actual

            direct_payload_parts.append(
                f"{semantic_degrees(lat1r, scalar):.17g} "
                f"{semantic_degrees(lon1r, scalar):.17g} "
                f"{semantic_degrees(azi1, scalar):.17g} "
                f"{distance:.17g}\n"
            )

        direct_run = subprocess.run(
            [
                geodsolve,
                "-E",
                "-e",
                f"{a:.17g}",
                f"{f:.17g}",
                "-p",
                "10",
            ],
            input="".join(direct_payload_parts),
            text=True,
            capture_output=True,
            check=True,
        )

        direct_lines = [
            line
            for line in direct_run.stdout.splitlines()
            if line.strip()
        ]

        if len(direct_lines) != len(rows_with_oracle):
            raise SystemExit(
                f"{scalar}:{profile}: direct oracle returned "
                f"{len(direct_lines)} rows for "
                f"{len(rows_with_oracle)} cases"
            )

        for row, direct_line in zip(
            rows_with_oracle,
            direct_lines,
        ):
            (
                lat1r,
                lon1r,
                lat2r,
                lon2r,
                distance,
                azi1,
                azi2,
                tag,
                expected_distance,
            ) = row

            direct_fields = direct_line.split()

            if len(direct_fields) < 3:
                raise SystemExit(
                    f"{scalar}:{profile}:{tag} malformed "
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
                lat2r,
                lon2r,
            )

            angular_length = (
                abs(expected_distance)
                / a
            )

            target_latitude = semantic_radians(
                lat2r,
                scalar,
            )

            target_longitude = semantic_radians(
                lon2r,
                scalar,
            )

            target_azimuth2 = semantic_radians(
                azi2,
                scalar,
            )

            if angular_length == 0.0:
                raw_final_azimuth_error = 0.0
                tangent_error = 0.0
            else:
                raw_final_azimuth_error = abs(
                    angle_difference(
                        target_azimuth2,
                        reached_azimuth2,
                    )
                )

                tangent_error = tangent_direction_error(
                    target_latitude,
                    target_longitude,
                    target_azimuth2,
                    reached_latitude,
                    reached_longitude,
                    reached_azimuth2,
                )

            if tag in COINCIDENT_TAGS:
                if (
                    distance != 0.0
                    or azi1 != 0.0
                    or azi2 != 0.0
                    or math.copysign(1.0, distance) < 0.0
                    or math.copysign(1.0, azi1) < 0.0
                    or math.copysign(1.0, azi2) < 0.0
                ):
                    raise SystemExit(
                        f"{scalar}:{profile}:{tag}: "
                        "GEO-A coincidence is not (+0,+0,+0)"
                    )

            total += 1

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
                    expected_distance,
                    distance,
                    normalized_distance_error,
                )

            if closure > max_closure:
                max_closure = closure

                worst_closure = (
                    profile,
                    tag,
                    closure,
                    distance,
                    azi1,
                )

            if (
                angular_length
                >= limits["well_conditioned"]
                and raw_final_azimuth_error
                    > max_raw_final_azimuth
            ):
                max_raw_final_azimuth = (
                    raw_final_azimuth_error
                )

                worst_raw_final_azimuth = (
                    profile,
                    tag,
                    angular_length,
                    math.degrees(target_latitude),
                    target_azimuth2,
                    reached_azimuth2,
                    raw_final_azimuth_error,
                )

            if tangent_error > max_tangent_direction:
                max_tangent_direction = tangent_error

                worst_tangent_direction = (
                    profile,
                    tag,
                    angular_length,
                    math.degrees(target_latitude),
                    tangent_error,
                    closure,
                )

    print()
    print(f"scalar: {scalar}")
    print(f"cases: {total}")
    print(
        "max normalized distance error: "
        f"{max_normalized_distance:.17g}"
    )
    print(
        "max exact-direct closure angle: "
        f"{max_closure:.17g}"
    )
    print(
        "max raw well-conditioned final azimuth error rad: "
        f"{max_raw_final_azimuth:.17g}"
    )
    print(
        "max Earth-fixed tangent direction error rad: "
        f"{max_tangent_direction:.17g}"
    )
    print(f"worst distance: {worst_distance}")
    print(f"worst closure: {worst_closure}")
    print(
        "worst raw final azimuth: "
        f"{worst_raw_final_azimuth}"
    )
    print(
        "worst tangent direction: "
        f"{worst_tangent_direction}"
    )

    if (
        max_normalized_distance
        > limits["distance"]
    ):
        raise SystemExit(
            f"FAIL {scalar}: normalized distance error "
            f"exceeds {limits['distance']}"
        )

    if max_closure > limits["closure"]:
        raise SystemExit(
            f"FAIL {scalar}: exact-direct closure "
            f"exceeds {limits['closure']}"
        )

    if (
        max_tangent_direction
        > limits["tangent"]
    ):
        raise SystemExit(
            f"FAIL {scalar}: Earth-fixed tangent direction error "
            f"exceeds {limits['tangent']}"
        )

    print("PASS")

print()
print(EXPECTED_VERSION)
print(f"seed: 0x{SEED:08X}")
print("PUBLIC INVERSE RESULT: PASS")
