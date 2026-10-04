#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import math
import random
import subprocess
import sys


@dataclass(frozen=True)
class Profile:
    name: str
    a: float
    f: float
    lat0: float
    lon0: float
    k0: float
    false_e: float
    false_n: float


PROFILES = (
    Profile(
        "WGS84_UTM_like",
        6_378_137.0,
        1.0 / 298.257223563,
        0.0,
        15.0,
        0.9996,
        500_000.0,
        0.0,
    ),
    Profile(
        "WGS84_k0_0_9",
        6_378_137.0,
        1.0 / 298.257223563,
        -35.0,
        15.0,
        0.9,
        -2_000_000.0,
        3_000_000.0,
    ),
    Profile(
        "WGS84_k0_1_1",
        6_378_137.0,
        1.0 / 298.257223563,
        49.0,
        15.0,
        1.1,
        2_000_000.0,
        -3_000_000.0,
    ),
    Profile(
        "Airy1830",
        6_377_563.396,
        1.0 / 299.3249646,
        49.0,
        -2.0,
        0.9996012717,
        400_000.0,
        -100_000.0,
    ),
    Profile(
        "Sphere6371",
        6_371_000.0,
        0.0,
        -35.0,
        20.0,
        0.9999,
        -500_000.0,
        700_000.0,
    ),
    Profile(
        "SyntheticF001",
        6_378_137.0,
        0.01,
        0.0,
        15.0,
        1.0,
        0.0,
        0.0,
    ),
)


STRUCTURED_LATITUDES = (
    -85.0,
    -80.0,
    -45.0,
    -1.0,
    0.0,
    1.0,
    45.0,
    80.0,
    85.0,
)

STRUCTURED_DLONGITUDES = (
    -60.0,
    -55.0,
    -35.0,
    -3.0,
    0.0,
    3.0,
    35.0,
    55.0,
    60.0,
)

RANDOM_SEED = 0x50465F50524F544F
RANDOM_CASES_PER_PROFILE = 2000

# These are prototype sanity bounds only. They are deliberately much looser
# than any eventual acceptance contract and merely catch a sign/formula error.
PROTOTYPE_GAMMA_SANITY_DEG = 0.1
PROTOTYPE_SCALE_REL_SANITY = 1.0e-3


def normalized_angle_error_deg(
    actual: float,
    reference: float,
) -> float:
    delta = math.remainder(
        actual - reference,
        360.0,
    )

    return abs(delta)


def make_points(
    profile: Profile,
    rng: random.Random,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []

    for latitude in STRUCTURED_LATITUDES:
        for delta_longitude in STRUCTURED_DLONGITUDES:
            points.append(
                (
                    latitude,
                    profile.lon0 + delta_longitude,
                )
            )

    for _ in range(RANDOM_CASES_PER_PROFILE):
        latitude = rng.uniform(-85.0, 85.0)
        delta_longitude = rng.uniform(-60.0, 60.0)

        points.append(
            (
                latitude,
                profile.lon0 + delta_longitude,
            )
        )

    return points


def input_text(
    points: list[tuple[float, float]],
) -> str:
    return "".join(
        f"{latitude:.17g} {longitude:.17g}\n"
        for latitude, longitude in points
    )


def run_d(
    executable: str,
    profile: Profile,
    points: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    command = [
        executable,
        f"{profile.a:.17g}",
        f"{profile.f:.17g}",
        f"{profile.lat0:.17g}",
        f"{profile.lon0:.17g}",
        f"{profile.k0:.17g}",
        f"{profile.false_e:.17g}",
        f"{profile.false_n:.17g}",
    ]

    process = subprocess.run(
        command,
        input=input_text(points),
        text=True,
        capture_output=True,
        check=False,
    )

    if process.returncode != 0:
        raise RuntimeError(
            f"D probe failed for {profile.name}:\n"
            f"{process.stderr}\n{process.stdout}"
        )

    rows = process.stdout.splitlines()

    if len(rows) != len(points):
        raise RuntimeError(
            f"D probe row count mismatch for {profile.name}: "
            f"{len(rows)} != {len(points)}"
        )

    results: list[tuple[float, float]] = []

    for index, row in enumerate(rows):
        fields = row.split()

        if not fields or fields[0] != "OK":
            raise RuntimeError(
                f"D probe rejected {profile.name} point "
                f"{index}: {points[index]} -> {row!r}"
            )

        if len(fields) != 3:
            raise RuntimeError(
                f"bad D probe output for {profile.name}: {row!r}"
            )

        gamma = float(fields[1])
        scale = float(fields[2])

        if (
            not math.isfinite(gamma)
            or not math.isfinite(scale)
            or scale <= 0.0
        ):
            raise RuntimeError(
                f"non-finite D factor result: {row!r}"
            )

        results.append((gamma, scale))

    return results


def normalized_longitude_difference_deg(
    longitude: float,
    longitude_of_origin: float,
) -> float:
    delta = longitude - longitude_of_origin

    while delta >= 180.0:
        delta -= 360.0

    while delta < -180.0:
        delta += 360.0

    return delta


def run_spherical_exact(
    profile: Profile,
    points: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    """Closed-form spherical Transverse Mercator factors.

    GeographicLib TransverseMercatorExact requires f > 0 and therefore
    cannot serve as the sphere oracle. For f == 0 use the exact spherical
    TM factor formulas instead.

    False easting, false northing, and the latitude-of-origin northing
    translation do not affect the local differential factors.
    """

    results: list[tuple[float, float]] = []

    for latitude_deg, longitude_deg in points:
        phi = math.radians(latitude_deg)

        delta_longitude_deg = (
            normalized_longitude_difference_deg(
                longitude_deg,
                profile.lon0,
            )
        )

        lam = math.radians(delta_longitude_deg)

        sin_phi = math.sin(phi)
        cos_phi = math.cos(phi)
        sin_lam = math.sin(lam)
        cos_lam = math.cos(lam)

        gamma = math.atan2(
            sin_lam * sin_phi,
            cos_lam,
        )

        denominator_squared = (
            1.0
            - (
                cos_phi
                * sin_lam
            ) ** 2
        )

        if not (
            math.isfinite(denominator_squared)
            and denominator_squared > 0.0
        ):
            raise RuntimeError(
                "invalid spherical TM factor denominator for "
                f"lat={latitude_deg:.17g} "
                f"lon={longitude_deg:.17g}"
            )

        scale = (
            profile.k0
            / math.sqrt(denominator_squared)
        )

        gamma_deg = math.degrees(gamma)

        if (
            not math.isfinite(gamma_deg)
            or not math.isfinite(scale)
            or scale <= 0.0
        ):
            raise RuntimeError(
                "non-finite spherical TM factor result for "
                f"lat={latitude_deg:.17g} "
                f"lon={longitude_deg:.17g}"
            )

        results.append(
            (
                gamma_deg,
                scale,
            )
        )

    return results


def run_geographiclib(
    profile: Profile,
    points: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    if profile.f == 0.0:
        return run_spherical_exact(
            profile,
            points,
        )
    command = [
        "TransverseMercatorProj",
        "-l",
        f"{profile.lon0:.17g}",
        "-k",
        f"{profile.k0:.17g}",
        "-e",
        f"{profile.a:.17g}",
        f"{profile.f:.17g}",
        "-p",
        "15",
    ]

    process = subprocess.run(
        command,
        input=input_text(points),
        text=True,
        capture_output=True,
        check=False,
    )

    if process.returncode != 0:
        raise RuntimeError(
            f"GeographicLib failed for {profile.name}:\n"
            f"{process.stderr}\n{process.stdout}"
        )

    rows = process.stdout.splitlines()

    if len(rows) != len(points):
        raise RuntimeError(
            f"GeographicLib row count mismatch for {profile.name}: "
            f"{len(rows)} != {len(points)}"
        )

    results: list[tuple[float, float]] = []

    for row in rows:
        fields = row.split()

        if len(fields) < 4:
            raise RuntimeError(
                f"bad GeographicLib output: {row!r}"
            )

        gamma = float(fields[2])
        scale = float(fields[3])

        if (
            not math.isfinite(gamma)
            or not math.isfinite(scale)
            or scale <= 0.0
        ):
            raise RuntimeError(
                f"non-finite GeographicLib factor result: {row!r}"
            )

        results.append((gamma, scale))

    return results


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: validate_d_factor_prototype.py D_PROBE",
            file=sys.stderr,
        )
        return 2

    executable = sys.argv[1]
    rng = random.Random(RANDOM_SEED)

    total_cases = 0

    global_gamma_error = 0.0
    global_gamma_label = ""

    global_scale_abs_error = 0.0
    global_scale_abs_label = ""

    global_scale_rel_error = 0.0
    global_scale_rel_label = ""

    print("=== PRIVATE D FACTOR PROTOTYPE ===")
    print(
        f"random seed=0x{RANDOM_SEED:016x} "
        f"random/profile={RANDOM_CASES_PER_PROFILE}"
    )

    for profile in PROFILES:
        points = make_points(profile, rng)

        actual = run_d(
            executable,
            profile,
            points,
        )

        reference = run_geographiclib(
            profile,
            points,
        )

        profile_gamma_error = 0.0
        profile_gamma_label = ""

        profile_scale_abs_error = 0.0
        profile_scale_abs_label = ""

        profile_scale_rel_error = 0.0
        profile_scale_rel_label = ""

        for index, (
            point,
            actual_factor,
            reference_factor,
        ) in enumerate(zip(points, actual, reference)):
            actual_gamma, actual_scale = actual_factor
            reference_gamma, reference_scale = reference_factor

            gamma_error = normalized_angle_error_deg(
                actual_gamma,
                reference_gamma,
            )

            scale_abs_error = abs(
                actual_scale - reference_scale
            )

            scale_rel_error = (
                scale_abs_error / reference_scale
            )

            label = (
                f"{profile.name}[{index}] "
                f"lat={point[0]:.12g} "
                f"lon={point[1]:.12g}"
            )

            if gamma_error > profile_gamma_error:
                profile_gamma_error = gamma_error
                profile_gamma_label = label

            if scale_abs_error > profile_scale_abs_error:
                profile_scale_abs_error = scale_abs_error
                profile_scale_abs_label = label

            if scale_rel_error > profile_scale_rel_error:
                profile_scale_rel_error = scale_rel_error
                profile_scale_rel_label = label

        total_cases += len(points)

        print()
        print(profile.name)
        print(
            "  cases: "
            f"{len(points)}"
        )
        print(
            "  max |delta gamma|: "
            f"{profile_gamma_error:.17g} deg"
        )
        print(
            "    at: "
            f"{profile_gamma_label}"
        )
        print(
            "  max |delta k|: "
            f"{profile_scale_abs_error:.17g}"
        )
        print(
            "    at: "
            f"{profile_scale_abs_label}"
        )
        print(
            "  max relative delta k: "
            f"{profile_scale_rel_error:.17g}"
        )
        print(
            "    at: "
            f"{profile_scale_rel_label}"
        )

        if profile_gamma_error > global_gamma_error:
            global_gamma_error = profile_gamma_error
            global_gamma_label = profile_gamma_label

        if profile_scale_abs_error > global_scale_abs_error:
            global_scale_abs_error = profile_scale_abs_error
            global_scale_abs_label = profile_scale_abs_label

        if profile_scale_rel_error > global_scale_rel_error:
            global_scale_rel_error = profile_scale_rel_error
            global_scale_rel_label = profile_scale_rel_label

    print()
    print("=== GLOBAL METRICS ===")
    print(f"cases={total_cases}")
    print(
        "max |delta gamma|="
        f"{global_gamma_error:.17g} deg"
    )
    print(f"  at: {global_gamma_label}")
    print(
        "max |delta k|="
        f"{global_scale_abs_error:.17g}"
    )
    print(f"  at: {global_scale_abs_label}")
    print(
        "max relative delta k="
        f"{global_scale_rel_error:.17g}"
    )
    print(f"  at: {global_scale_rel_label}")

    if global_gamma_error > PROTOTYPE_GAMMA_SANITY_DEG:
        print(
            "FAIL: prototype gamma error exceeds loose "
            "research sanity bound"
        )
        return 1

    if global_scale_rel_error > PROTOTYPE_SCALE_REL_SANITY:
        print(
            "FAIL: prototype scale error exceeds loose "
            "research sanity bound"
        )
        return 1

    print()
    print(
        "PASS: derivative prototype agrees with the Exact "
        "oracle within loose research sanity bounds"
    )
    print(
        "NOTE: these bounds are not projection-factor "
        "acceptance tolerances"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
