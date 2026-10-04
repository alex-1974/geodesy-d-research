#!/usr/bin/env python3

from __future__ import annotations

import math
import random
import re
import subprocess
from dataclasses import dataclass
from typing import Iterable, Sequence


SEED = 0x544F504F5F50524F  # "TOPO_PRO"
EPOCH = 2020.0

# PROJ oracle-qualification tolerances.
#
# These are NOT geodesy-d public accuracy contracts.
#
# Forward/topocentric-only operations are expected to agree with the
# independent analytical reference at approximately floating-point rounding
# level.  The reverse geographic path is additionally bounded by PROJ's own
# ECEF -> geodetic (`cart -I`) accuracy, so it is checked both against an
# absolute sanity ceiling and against the isolated cart-inverse baseline.
TOPO_LINEAR_TOL_M = 1.0e-6

REVERSE_LAT_ABS_TOL_RAD = 2.0e-11
REVERSE_LON_ABS_TOL_RAD = 1.0e-12
REVERSE_HEIGHT_ABS_TOL_M = 2.0e-4

REVERSE_LAT_PIPELINE_DELTA_TOL_RAD = 1.0e-13
REVERSE_LON_PIPELINE_DELTA_TOL_RAD = 1.0e-12
REVERSE_HEIGHT_PIPELINE_DELTA_TOL_M = 1.0e-6


@dataclass(frozen=True)
class Ellipsoid:
    name: str
    a: float
    rf: float | None

    @property
    def f(self) -> float:
        return 0.0 if self.rf is None else 1.0 / self.rf

    @property
    def e2(self) -> float:
        f = self.f
        return f * (2.0 - f)

    def proj_args(self) -> list[str]:
        if self.rf is None:
            return [
                f"+a={self.a:.17g}",
                f"+b={self.a:.17g}",
            ]

        return [
            f"+a={self.a:.17g}",
            f"+rf={self.rf:.17g}",
        ]


@dataclass(frozen=True)
class Geodetic:
    lat_deg: float
    lon_deg: float
    h: float


@dataclass(frozen=True)
class Vec3:
    x: float
    y: float
    z: float


ELLIPSOIDS = [
    Ellipsoid(
        "WGS84",
        6_378_137.0,
        298.257223563,
    ),
    Ellipsoid(
        "GRS80",
        6_378_137.0,
        298.257222101,
    ),
    Ellipsoid(
        "Airy1830",
        6_377_563.396,
        299.3249646,
    ),
    Ellipsoid(
        "Sphere6371",
        6_371_000.0,
        None,
    ),
]


ORIGINS = [
    Geodetic(0.0, 0.0, 0.0),
    Geodetic(48.20849, 16.37208, 171.0),
    Geodetic(-33.8688, 151.2093, 58.0),
    Geodetic(10.0, 179.75, 100.0),
    Geodetic(89.5, -45.0, 25.0),
]


def deg_to_rad(value: float) -> float:
    return math.radians(value)


def normalize_lon_deg(value: float) -> float:
    result = math.fmod(value + 180.0, 360.0)

    if result < 0.0:
        result += 360.0

    return result - 180.0


def angular_difference_rad(a: float, b: float) -> float:
    d = a - b
    return (d + math.pi) % (2.0 * math.pi) - math.pi


def geodetic_to_ecef(
    source: Geodetic,
    ellipsoid: Ellipsoid,
) -> Vec3:
    phi = deg_to_rad(source.lat_deg)
    lam = deg_to_rad(source.lon_deg)

    sin_phi = math.sin(phi)
    cos_phi = math.cos(phi)
    sin_lam = math.sin(lam)
    cos_lam = math.cos(lam)

    nu = ellipsoid.a / math.sqrt(
        1.0 - ellipsoid.e2 * sin_phi * sin_phi
    )

    return Vec3(
        (nu + source.h) * cos_phi * cos_lam,
        (nu + source.h) * cos_phi * sin_lam,
        ((1.0 - ellipsoid.e2) * nu + source.h) * sin_phi,
    )


def ecef_to_enu(
    source: Vec3,
    origin: Vec3,
    origin_lat_deg: float,
    origin_lon_deg: float,
) -> Vec3:
    phi = deg_to_rad(origin_lat_deg)
    lam = deg_to_rad(origin_lon_deg)

    sin_phi = math.sin(phi)
    cos_phi = math.cos(phi)
    sin_lam = math.sin(lam)
    cos_lam = math.cos(lam)

    dx = source.x - origin.x
    dy = source.y - origin.y
    dz = source.z - origin.z

    return Vec3(
        -dx * sin_lam
        + dy * cos_lam,

        -dx * sin_phi * cos_lam
        - dy * sin_phi * sin_lam
        + dz * cos_phi,

        dx * cos_phi * cos_lam
        + dy * cos_phi * sin_lam
        + dz * sin_phi,
    )


def enu_to_ecef(
    source: Vec3,
    origin: Vec3,
    origin_lat_deg: float,
    origin_lon_deg: float,
) -> Vec3:
    phi = deg_to_rad(origin_lat_deg)
    lam = deg_to_rad(origin_lon_deg)

    sin_phi = math.sin(phi)
    cos_phi = math.cos(phi)
    sin_lam = math.sin(lam)
    cos_lam = math.cos(lam)

    east = source.x
    north = source.y
    up = source.z

    return Vec3(
        origin.x
        - east * sin_lam
        - north * sin_phi * cos_lam
        + up * cos_phi * cos_lam,

        origin.y
        + east * cos_lam
        - north * sin_phi * sin_lam
        + up * cos_phi * sin_lam,

        origin.z
        + north * cos_phi
        + up * sin_phi,
    )


def max_component_error(a: Vec3, b: Vec3) -> float:
    return max(
        abs(a.x - b.x),
        abs(a.y - b.y),
        abs(a.z - b.z),
    )


def cct_version() -> str:
    proc = subprocess.run(
        ["cct", "--version"],
        text=True,
        capture_output=True,
        check=True,
    )

    return (proc.stdout or proc.stderr).strip()


def run_cct(
    operation_args: Sequence[str],
    rows: Sequence[Vec3],
    *,
    inverse: bool = False,
) -> list[Vec3]:
    command = [
        "cct",
        "-d",
        "15",
    ]

    if inverse:
        command.append("-I")

    command.extend(operation_args)

    payload = "".join(
        f"{row.x:.17g} {row.y:.17g} {row.z:.17g} {EPOCH:.1f}\n"
        for row in rows
    )

    proc = subprocess.run(
        command,
        input=payload,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "cct failed:\n"
            + " ".join(command)
            + "\n--- stderr ---\n"
            + proc.stderr
        )

    result: list[Vec3] = []

    for raw in proc.stdout.splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        fields = line.split()

        if len(fields) < 3:
            raise RuntimeError(
                f"unexpected cct output line: {raw!r}"
            )

        result.append(
            Vec3(
                float(fields[0]),
                float(fields[1]),
                float(fields[2]),
            )
        )

    if len(result) != len(rows):
        raise RuntimeError(
            f"cct row count mismatch: "
            f"expected {len(rows)}, got {len(result)}"
        )

    return result


def run_cct_geodetic(
    operation_args: Sequence[str],
    rows: Sequence[Geodetic],
) -> list[Vec3]:
    command = [
        "cct",
        "-d",
        "15",
        *operation_args,
    ]

    payload = "".join(
        f"{row.lon_deg:.17g} "
        f"{row.lat_deg:.17g} "
        f"{row.h:.17g} "
        f"{EPOCH:.1f}\n"
        for row in rows
    )

    proc = subprocess.run(
        command,
        input=payload,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "cct failed:\n"
            + " ".join(command)
            + "\n--- stderr ---\n"
            + proc.stderr
        )

    result: list[Vec3] = []

    for raw in proc.stdout.splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        fields = line.split()

        if len(fields) < 3:
            raise RuntimeError(
                f"unexpected cct output line: {raw!r}"
            )

        result.append(
            Vec3(
                float(fields[0]),
                float(fields[1]),
                float(fields[2]),
            )
        )

    if len(result) != len(rows):
        raise RuntimeError(
            f"cct row count mismatch: "
            f"expected {len(rows)}, got {len(result)}"
        )

    return result


def run_cct_geodetic_inverse(
    operation_args: Sequence[str],
    rows: Sequence[Vec3],
) -> list[Geodetic]:
    command = [
        "cct",
        "-I",
        "-d",
        "15",
        *operation_args,
    ]

    payload = "".join(
        f"{row.x:.17g} "
        f"{row.y:.17g} "
        f"{row.z:.17g} "
        f"{EPOCH:.1f}\n"
        for row in rows
    )

    proc = subprocess.run(
        command,
        input=payload,
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        raise RuntimeError(
            "cct failed:\n"
            + " ".join(command)
            + "\n--- stderr ---\n"
            + proc.stderr
        )

    result: list[Geodetic] = []

    for raw in proc.stdout.splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        fields = line.split()

        if len(fields) < 3:
            raise RuntimeError(
                f"unexpected cct output line: {raw!r}"
            )

        result.append(
            Geodetic(
                lat_deg=float(fields[1]),
                lon_deg=float(fields[0]),
                h=float(fields[2]),
            )
        )

    if len(result) != len(rows):
        raise RuntimeError(
            f"cct row count mismatch: "
            f"expected {len(rows)}, got {len(result)}"
        )

    return result


def structured_sources() -> list[Geodetic]:
    latitudes = [
        -89.5,
        -80.0,
        -45.0,
        -1.0,
        0.0,
        1.0,
        45.0,
        80.0,
        89.5,
    ]

    longitudes = [
        -179.999,
        -90.0,
        -1.0,
        0.0,
        1.0,
        90.0,
        179.999,
    ]

    heights = [
        -20_000.0,
        0.0,
        100.0,
        100_000.0,
    ]

    return [
        Geodetic(lat, lon, height)
        for lat in latitudes
        for lon in longitudes
        for height in heights
    ]


def random_sources(rng: random.Random, count: int) -> list[Geodetic]:
    result = []

    for _ in range(count):
        result.append(
            Geodetic(
                lat_deg=rng.uniform(-89.5, 89.5),
                lon_deg=rng.uniform(-180.0, 180.0),
                h=rng.uniform(-20_000.0, 100_000.0),
            )
        )

    return result


def local_sources(
    rng: random.Random,
    origin: Geodetic,
    count: int,
) -> list[Geodetic]:
    result = []

    for _ in range(count):
        lat = origin.lat_deg + rng.uniform(-0.1, 0.1)
        lat = max(-89.5, min(89.5, lat))

        lon = normalize_lon_deg(
            origin.lon_deg + rng.uniform(-0.1, 0.1)
        )

        result.append(
            Geodetic(
                lat_deg=lat,
                lon_deg=lon,
                h=origin.h + rng.uniform(-1_000.0, 1_000.0),
            )
        )

    return result


@dataclass
class Maxima:
    epsg9836_forward_m: float = 0.0
    epsg9836_reverse_m: float = 0.0
    epsg9837_forward_m: float = 0.0
    epsg9837_reverse_lat_rad: float = 0.0
    epsg9837_reverse_lon_rad: float = 0.0
    epsg9837_reverse_height_m: float = 0.0

    cart_inverse_lat_rad: float = 0.0
    cart_inverse_lon_rad: float = 0.0
    cart_inverse_height_m: float = 0.0

    epsg9837_vs_cart_lat_rad: float = 0.0
    epsg9837_vs_cart_lon_rad: float = 0.0
    epsg9837_vs_cart_height_m: float = 0.0

    witness_9837_reverse_lat: str = ""
    witness_9837_reverse_height: str = ""

    cases9836: int = 0
    cases9837: int = 0

    def merge(self, other: "Maxima") -> None:
        self.epsg9836_forward_m = max(
            self.epsg9836_forward_m,
            other.epsg9836_forward_m,
        )
        self.epsg9836_reverse_m = max(
            self.epsg9836_reverse_m,
            other.epsg9836_reverse_m,
        )
        self.epsg9837_forward_m = max(
            self.epsg9837_forward_m,
            other.epsg9837_forward_m,
        )
        if (
            other.epsg9837_reverse_lat_rad
            > self.epsg9837_reverse_lat_rad
        ):
            self.epsg9837_reverse_lat_rad = (
                other.epsg9837_reverse_lat_rad
            )
            self.witness_9837_reverse_lat = (
                other.witness_9837_reverse_lat
            )

        self.epsg9837_reverse_lon_rad = max(
            self.epsg9837_reverse_lon_rad,
            other.epsg9837_reverse_lon_rad,
        )

        if (
            other.epsg9837_reverse_height_m
            > self.epsg9837_reverse_height_m
        ):
            self.epsg9837_reverse_height_m = (
                other.epsg9837_reverse_height_m
            )
            self.witness_9837_reverse_height = (
                other.witness_9837_reverse_height
            )

        self.cart_inverse_lat_rad = max(
            self.cart_inverse_lat_rad,
            other.cart_inverse_lat_rad,
        )
        self.cart_inverse_lon_rad = max(
            self.cart_inverse_lon_rad,
            other.cart_inverse_lon_rad,
        )
        self.cart_inverse_height_m = max(
            self.cart_inverse_height_m,
            other.cart_inverse_height_m,
        )

        self.epsg9837_vs_cart_lat_rad = max(
            self.epsg9837_vs_cart_lat_rad,
            other.epsg9837_vs_cart_lat_rad,
        )
        self.epsg9837_vs_cart_lon_rad = max(
            self.epsg9837_vs_cart_lon_rad,
            other.epsg9837_vs_cart_lon_rad,
        )
        self.epsg9837_vs_cart_height_m = max(
            self.epsg9837_vs_cart_height_m,
            other.epsg9837_vs_cart_height_m,
        )

        self.cases9836 += other.cases9836
        self.cases9837 += other.cases9837


def validate_profile(
    ellipsoid: Ellipsoid,
    origin: Geodetic,
    sources: Sequence[Geodetic],
) -> Maxima:
    maxima = Maxima()

    origin_ecef = geodetic_to_ecef(origin, ellipsoid)

    source_ecef = [
        geodetic_to_ecef(source, ellipsoid)
        for source in sources
    ]

    reference_enu = [
        ecef_to_enu(
            source,
            origin_ecef,
            origin.lat_deg,
            origin.lon_deg,
        )
        for source in source_ecef
    ]

    ellipsoid_args = ellipsoid.proj_args()

    # ---------------------------------------------------------------
    # Isolated PROJ cart inverse baseline
    # ---------------------------------------------------------------

    op_cart = [
        "+proj=cart",
        *ellipsoid_args,
    ]

    proj_cart_inverse = run_cct_geodetic_inverse(
        op_cart,
        source_ecef,
    )

    for expected, actual in zip(
        sources,
        proj_cart_inverse,
    ):
        lat_error = abs(
            deg_to_rad(actual.lat_deg - expected.lat_deg)
        )

        lon_error = abs(
            angular_difference_rad(
                deg_to_rad(actual.lon_deg),
                deg_to_rad(expected.lon_deg),
            )
        )

        height_error = abs(actual.h - expected.h)

        maxima.cart_inverse_lat_rad = max(
            maxima.cart_inverse_lat_rad,
            lat_error,
        )
        maxima.cart_inverse_lon_rad = max(
            maxima.cart_inverse_lon_rad,
            lon_error,
        )
        maxima.cart_inverse_height_m = max(
            maxima.cart_inverse_height_m,
            height_error,
        )

    # ---------------------------------------------------------------
    # EPSG 9836
    # ---------------------------------------------------------------

    op9836 = [
        "+proj=topocentric",
        *ellipsoid_args,
        f"+X_0={origin_ecef.x:.17g}",
        f"+Y_0={origin_ecef.y:.17g}",
        f"+Z_0={origin_ecef.z:.17g}",
    ]

    proj_9836_forward = run_cct(
        op9836,
        source_ecef,
    )

    for expected, actual in zip(
        reference_enu,
        proj_9836_forward,
    ):
        maxima.epsg9836_forward_m = max(
            maxima.epsg9836_forward_m,
            max_component_error(expected, actual),
        )

    proj_9836_reverse = run_cct(
        op9836,
        reference_enu,
        inverse=True,
    )

    for expected, actual in zip(
        source_ecef,
        proj_9836_reverse,
    ):
        maxima.epsg9836_reverse_m = max(
            maxima.epsg9836_reverse_m,
            max_component_error(expected, actual),
        )

    maxima.cases9836 += len(sources)

    # ---------------------------------------------------------------
    # EPSG 9837
    # ---------------------------------------------------------------

    op9837 = [
        "+proj=pipeline",
        "+step",
        "+proj=cart",
        *ellipsoid_args,
        "+step",
        "+proj=topocentric",
        *ellipsoid_args,
        f"+lon_0={origin.lon_deg:.17g}",
        f"+lat_0={origin.lat_deg:.17g}",
        f"+h_0={origin.h:.17g}",
    ]

    proj_9837_forward = run_cct_geodetic(
        op9837,
        sources,
    )

    for expected, actual in zip(
        reference_enu,
        proj_9837_forward,
    ):
        maxima.epsg9837_forward_m = max(
            maxima.epsg9837_forward_m,
            max_component_error(expected, actual),
        )

    proj_9837_reverse = run_cct_geodetic_inverse(
        op9837,
        reference_enu,
    )

    for index, (expected, actual, cart_actual) in enumerate(zip(
        sources,
        proj_9837_reverse,
        proj_cart_inverse,
    )):
        lat_error = abs(
            deg_to_rad(actual.lat_deg - expected.lat_deg)
        )

        lon_error = abs(
            angular_difference_rad(
                deg_to_rad(actual.lon_deg),
                deg_to_rad(expected.lon_deg),
            )
        )

        height_error = abs(actual.h - expected.h)

        pipeline_lat_delta = abs(
            deg_to_rad(actual.lat_deg - cart_actual.lat_deg)
        )

        pipeline_lon_delta = abs(
            angular_difference_rad(
                deg_to_rad(actual.lon_deg),
                deg_to_rad(cart_actual.lon_deg),
            )
        )

        pipeline_height_delta = abs(
            actual.h - cart_actual.h
        )

        maxima.epsg9837_vs_cart_lat_rad = max(
            maxima.epsg9837_vs_cart_lat_rad,
            pipeline_lat_delta,
        )
        maxima.epsg9837_vs_cart_lon_rad = max(
            maxima.epsg9837_vs_cart_lon_rad,
            pipeline_lon_delta,
        )
        maxima.epsg9837_vs_cart_height_m = max(
            maxima.epsg9837_vs_cart_height_m,
            pipeline_height_delta,
        )

        witness = (
            f"ellipsoid={ellipsoid.name}; "
            f"origin="
            f"({origin.lat_deg:.15g},"
            f"{origin.lon_deg:.15g},"
            f"{origin.h:.15g}); "
            f"source="
            f"({expected.lat_deg:.15g},"
            f"{expected.lon_deg:.15g},"
            f"{expected.h:.15g}); "
            f"index={index}"
        )

        if lat_error > maxima.epsg9837_reverse_lat_rad:
            maxima.epsg9837_reverse_lat_rad = lat_error
            maxima.witness_9837_reverse_lat = witness

        maxima.epsg9837_reverse_lon_rad = max(
            maxima.epsg9837_reverse_lon_rad,
            lon_error,
        )

        if height_error > maxima.epsg9837_reverse_height_m:
            maxima.epsg9837_reverse_height_m = height_error
            maxima.witness_9837_reverse_height = witness

    maxima.cases9837 += len(sources)

    return maxima


def print_maxima(label: str, m: Maxima) -> None:
    print(label)
    print(f"  EPSG 9836 cases:              {m.cases9836}")
    print(f"  EPSG 9837 cases:              {m.cases9837}")
    print(
        "  9836 forward max component:  "
        f"{m.epsg9836_forward_m:.12e} m"
    )
    print(
        "  9836 reverse max component:  "
        f"{m.epsg9836_reverse_m:.12e} m"
    )
    print(
        "  9837 forward max component:  "
        f"{m.epsg9837_forward_m:.12e} m"
    )
    print(
        "  9837 reverse max latitude:   "
        f"{m.epsg9837_reverse_lat_rad:.12e} rad"
    )
    print(
        "  9837 reverse max longitude:  "
        f"{m.epsg9837_reverse_lon_rad:.12e} rad"
    )
    print(
        "  9837 reverse max height:     "
        f"{m.epsg9837_reverse_height_m:.12e} m"
    )

    print(
        "  cart inverse max latitude:   "
        f"{m.cart_inverse_lat_rad:.12e} rad"
    )
    print(
        "  cart inverse max longitude:  "
        f"{m.cart_inverse_lon_rad:.12e} rad"
    )
    print(
        "  cart inverse max height:     "
        f"{m.cart_inverse_height_m:.12e} m"
    )

    print(
        "  9837/cart paired lat delta:   "
        f"{m.epsg9837_vs_cart_lat_rad:.12e} rad"
    )
    print(
        "  9837/cart paired lon delta:   "
        f"{m.epsg9837_vs_cart_lon_rad:.12e} rad"
    )
    print(
        "  9837/cart paired h delta:     "
        f"{m.epsg9837_vs_cart_height_m:.12e} m"
    )

    if m.witness_9837_reverse_lat:
        print(
            "  9837 reverse latitude case: "
            f"{m.witness_9837_reverse_lat}"
        )

    if m.witness_9837_reverse_height:
        print(
            "  9837 reverse height case:   "
            f"{m.witness_9837_reverse_height}"
        )


def check_thresholds(m: Maxima) -> None:
    failures = []

    if m.epsg9836_forward_m > TOPO_LINEAR_TOL_M:
        failures.append("9836 forward")

    if m.epsg9836_reverse_m > TOPO_LINEAR_TOL_M:
        failures.append("9836 reverse")

    if m.epsg9837_forward_m > TOPO_LINEAR_TOL_M:
        failures.append("9837 forward")

    # Absolute PROJ reverse sanity limits.
    if (
        m.epsg9837_reverse_lat_rad
        > REVERSE_LAT_ABS_TOL_RAD
    ):
        failures.append("9837 reverse latitude absolute")

    if (
        m.epsg9837_reverse_lon_rad
        > REVERSE_LON_ABS_TOL_RAD
    ):
        failures.append("9837 reverse longitude absolute")

    if (
        m.epsg9837_reverse_height_m
        > REVERSE_HEIGHT_ABS_TOL_M
    ):
        failures.append("9837 reverse height absolute")

    # More important for oracle qualification: the topocentric pipeline must
    # not materially worsen PROJ's own isolated cart-inverse baseline.
    if (
        m.epsg9837_vs_cart_lat_rad
        > REVERSE_LAT_PIPELINE_DELTA_TOL_RAD
    ):
        failures.append("9837/cart paired latitude delta")

    if (
        m.epsg9837_vs_cart_lon_rad
        > REVERSE_LON_PIPELINE_DELTA_TOL_RAD
    ):
        failures.append("9837/cart paired longitude delta")

    if (
        m.epsg9837_vs_cart_height_m
        > REVERSE_HEIGHT_PIPELINE_DELTA_TOL_M
    ):
        failures.append("9837/cart paired height delta")

    if failures:
        raise SystemExit(
            "FAIL: PROJ oracle qualification exceeded "
            "research tolerance in: "
            + ", ".join(failures)
        )


def main() -> None:
    print("=== PROJ oracle qualification ===")
    print(cct_version())
    print(f"seed: 0x{SEED:016X}")
    print(
        "topocentric linear tolerance: "
        f"{TOPO_LINEAR_TOL_M:.3e} m"
    )
    print(
        "reverse latitude absolute ceiling: "
        f"{REVERSE_LAT_ABS_TOL_RAD:.3e} rad"
    )
    print(
        "reverse longitude absolute ceiling: "
        f"{REVERSE_LON_ABS_TOL_RAD:.3e} rad"
    )
    print(
        "reverse height absolute ceiling: "
        f"{REVERSE_HEIGHT_ABS_TOL_M:.3e} m"
    )
    print(
        "reverse latitude paired delta: "
        f"{REVERSE_LAT_PIPELINE_DELTA_TOL_RAD:.3e} rad"
    )
    print(
        "reverse longitude paired delta: "
        f"{REVERSE_LON_PIPELINE_DELTA_TOL_RAD:.3e} rad"
    )
    print(
        "reverse height paired delta: "
        f"{REVERSE_HEIGHT_PIPELINE_DELTA_TOL_M:.3e} m"
    )
    print()

    rng = random.Random(SEED)

    structured = structured_sources()
    global_random = random_sources(rng, 500)

    total = Maxima()

    for ellipsoid in ELLIPSOIDS:
        profile_maxima = Maxima()

        for origin in ORIGINS:
            sources = [
                *structured,
                *global_random,
                *local_sources(rng, origin, 100),
            ]

            current = validate_profile(
                ellipsoid,
                origin,
                sources,
            )

            profile_maxima.merge(current)

        print_maxima(
            f"=== {ellipsoid.name} ===",
            profile_maxima,
        )
        print()

        total.merge(profile_maxima)

    print_maxima("=== TOTAL ===", total)
    print()

    check_thresholds(total)

    print("PASS: PROJ topocentric oracle qualification")


if __name__ == "__main__":
    main()
