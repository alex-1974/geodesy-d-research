#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import math
import shutil
import subprocess


WGS84_A = 6_378_137.0
WGS84_F = 1.0 / 298.257223563

GAMMA_TOL_DEG = 1.0e-9
SCALE_TOL = 2.0e-12


@dataclass(frozen=True)
class FactorResult:
    easting: float
    northing: float
    convergence_deg: float
    point_scale: float


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def require_near(
    label: str,
    actual: float,
    expected: float,
    tolerance: float,
) -> None:
    delta = abs(actual - expected)

    if not math.isfinite(delta) or delta > tolerance:
        raise RuntimeError(
            f"{label}: actual={actual:.17g} "
            f"expected={expected:.17g} "
            f"delta={delta:.17g} "
            f"tolerance={tolerance:.17g}"
        )


def query(
    latitude_deg: float,
    longitude_deg: float,
    *,
    longitude_of_origin_deg: float = 15.0,
    central_scale: float = 0.9996,
    semi_major_axis: float = WGS84_A,
    flattening: float = WGS84_F,
) -> FactorResult:
    command = [
        "TransverseMercatorProj",
        "-l",
        f"{longitude_of_origin_deg:.17g}",
        "-k",
        f"{central_scale:.17g}",
        "-e",
        f"{semi_major_axis:.17g}",
        f"{flattening:.17g}",
        "-p",
        "15",
    ]

    process = subprocess.run(
        command,
        input=f"{latitude_deg:.17g} {longitude_deg:.17g}\n",
        text=True,
        capture_output=True,
        check=False,
    )

    if process.returncode != 0:
        raise RuntimeError(
            "TransverseMercatorProj failed:\n"
            + process.stderr
            + process.stdout
        )

    fields = process.stdout.strip().split()

    if len(fields) < 4:
        raise RuntimeError(
            "unexpected TransverseMercatorProj output: "
            + repr(process.stdout)
        )

    result = FactorResult(
        easting=float(fields[0]),
        northing=float(fields[1]),
        convergence_deg=float(fields[2]),
        point_scale=float(fields[3]),
    )

    require(
        all(
            math.isfinite(value)
            for value in (
                result.easting,
                result.northing,
                result.convergence_deg,
                result.point_scale,
            )
        ),
        f"non-finite GeographicLib result: {result}",
    )

    require(
        result.point_scale > 0.0,
        f"non-positive GeographicLib point scale: {result}",
    )

    return result


def check_central_meridian() -> int:
    checks = 0

    for latitude in (-80.0, -45.0, 0.0, 45.0, 80.0):
        result = query(latitude, 15.0)

        require_near(
            f"central convergence lat={latitude}",
            result.convergence_deg,
            0.0,
            GAMMA_TOL_DEG,
        )

        require_near(
            f"central scale lat={latitude}",
            result.point_scale,
            0.9996,
            SCALE_TOL,
        )

        checks += 2

    return checks


def check_equator() -> int:
    checks = 0

    for delta_longitude in (-60.0, -35.0, -3.0, 3.0, 35.0, 60.0):
        result = query(0.0, 15.0 + delta_longitude)

        require_near(
            f"equator convergence dlon={delta_longitude}",
            result.convergence_deg,
            0.0,
            GAMMA_TOL_DEG,
        )

        checks += 1

    return checks


def check_east_west_symmetry() -> int:
    checks = 0

    for latitude in (20.0, 45.0, 80.0):
        for delta_longitude in (3.0, 35.0, 55.0, 60.0):
            east = query(latitude, 15.0 + delta_longitude)
            west = query(latitude, 15.0 - delta_longitude)

            require_near(
                f"east/west convergence lat={latitude} "
                f"dlon={delta_longitude}",
                east.convergence_deg,
                -west.convergence_deg,
                GAMMA_TOL_DEG,
            )

            require_near(
                f"east/west scale lat={latitude} "
                f"dlon={delta_longitude}",
                east.point_scale,
                west.point_scale,
                SCALE_TOL,
            )

            checks += 2

    return checks


def check_north_south_symmetry() -> int:
    checks = 0

    for latitude in (20.0, 45.0, 80.0):
        for delta_longitude in (3.0, 35.0, 55.0, 60.0):
            north = query(latitude, 15.0 + delta_longitude)
            south = query(-latitude, 15.0 + delta_longitude)

            require_near(
                f"north/south convergence lat={latitude} "
                f"dlon={delta_longitude}",
                north.convergence_deg,
                -south.convergence_deg,
                GAMMA_TOL_DEG,
            )

            require_near(
                f"north/south scale lat={latitude} "
                f"dlon={delta_longitude}",
                north.point_scale,
                south.point_scale,
                SCALE_TOL,
            )

            checks += 2

    return checks


def check_central_scale_composition() -> int:
    checks = 0

    for latitude, longitude in (
        (0.0, 18.0),
        (45.0, 18.0),
        (45.0, 50.0),
        (80.0, 70.0),
    ):
        unit = query(
            latitude,
            longitude,
            central_scale=1.0,
        )

        scaled = query(
            latitude,
            longitude,
            central_scale=0.9996,
        )

        require_near(
            f"k0 convergence invariance lat={latitude} lon={longitude}",
            scaled.convergence_deg,
            unit.convergence_deg,
            GAMMA_TOL_DEG,
        )

        require_near(
            f"k0 scale composition lat={latitude} lon={longitude}",
            scaled.point_scale,
            unit.point_scale * 0.9996,
            SCALE_TOL,
        )

        checks += 2

    return checks


def characterize_examples() -> None:
    print("=== REPRESENTATIVE FACTORS ===")

    cases = (
        ("Vienna-like", 48.20849, 16.37208),
        ("UTM +3 deg", 45.0, 18.0),
        ("wide +35 deg", 45.0, 50.0),
        ("wide +55 deg", 80.0, 70.0),
        ("boundary +60 deg", 45.0, 75.0),
    )

    for label, latitude, longitude in cases:
        result = query(latitude, longitude)

        print(
            f"{label}: "
            f"lat={latitude:.8f} "
            f"lon={longitude:.8f} "
            f"gamma={result.convergence_deg:.15g} deg "
            f"k={result.point_scale:.17g}"
        )


def main() -> int:
    executable = shutil.which("TransverseMercatorProj")

    if executable is None:
        raise RuntimeError(
            "TransverseMercatorProj not found in PATH"
        )

    version = subprocess.run(
        [executable, "--version"],
        text=True,
        capture_output=True,
        check=False,
    )

    require(
        version.returncode == 0,
        "TransverseMercatorProj --version failed",
    )

    print("=== REFERENCE ===")
    print(version.stdout.strip() or version.stderr.strip())

    checks = 0
    checks += check_central_meridian()
    checks += check_equator()
    checks += check_east_west_symmetry()
    checks += check_north_south_symmetry()
    checks += check_central_scale_composition()

    print()
    characterize_examples()

    print()
    print("=== ACCEPTANCE ===")
    print(f"checks={checks}")
    print("PASS: GeographicLib TM factor characterization")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
