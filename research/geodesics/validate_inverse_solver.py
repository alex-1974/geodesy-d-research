#!/usr/bin/env python3
"""
GEO-C differential validation for the internal canonical inverse solver.

Oracle:
    GeographicLib GeodSolve 2.7, exact mode (-E).

Scope:
    The D probe receives already-canonical reduced latitudes beta1/beta2 and
    lambda12.  The validator converts beta back to geodetic latitude only for
    the GeodSolve CLI oracle.

Important conditioning rule:
    Absolute azimuth error is not a stable metric as the endpoint separation
    approaches zero.  For angular length s/a < 1e-6, azimuth error is therefore
    diagnostic only; the gate uses the transverse angular error

        (s/a) * delta_azimuth

    instead.

GeodSolve CLI note:
    GeographicLib clamps -p to 10 + Math::extra_digits().  With the normal
    double build this means unit-scale distance output can itself be quantized
    at about 1e-10 absolute units.  The distance gate is intentionally wider
    than this CLI formatting floor, while Earth/large-scale profiles provide
    substantially finer normalized oracle resolution.
"""

from __future__ import annotations

import argparse
import math
import random
import subprocess
import sys
from pathlib import Path


EXPECTED_GEODSOLVE_VERSION = "GeodSolve: GeographicLib version 2.7"
SEED = 0x47454F49

DISTANCE_LIMIT = 2e-10
AZIMUTH_LIMIT = 2e-10
TRANSVERSE_LIMIT = 2e-10
WELL_CONDITIONED_MIN_ANGULAR_LENGTH = 1e-6

DEFAULT_GEODSOLVE = Path("/usr/bin/GeodSolve")
DEFAULT_PROBE = Path("/tmp/geodesy-inverse-solver-probe")


PROFILES = (
    ("sphere", 6_371_000.0, 0.0),
    ("wgs84", 6_378_137.0, 1.0 / 298.257223563),
    ("near-sphere", 6_378_137.0, 1e-6),
    ("mid-f", 7_000_000.0, 0.005),
    ("max-f", 7_000_000.0, 0.01),
    ("unit-scale", 1.0, 1.0 / 298.257223563),
    ("large-scale", 1e9, 1.0 / 298.257223563),
)


FIXED_CASES = (
    (-0.70, 0.25, 1.50, "regional"),
    (-1.20, -0.20, 2.10, "high-lat"),
    (-0.40, 0.10, 1.25, "mid"),
    (-0.20, -0.20 + 1e-10, 1e-10, "tiny"),
    (-0.10, 0.100001, math.pi - 1e-3, "outside-canonical"),
    (-0.60, 0.599999, math.pi - 1e-5, "near-antipodal-b"),
    (-1.00, 0.999990, math.pi - 3e-4, "near-antipodal-c"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--probe",
        type=Path,
        default=None,
        help="existing inverse solver probe binary; otherwise build with dmd",
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


def normalized_version_line(raw: str) -> str:
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

    actual = normalized_version_line(completed.stdout)

    if actual != EXPECTED_GEODSOLVE_VERSION:
        raise SystemExit(
            "unexpected GeodSolve version:\n"
            f"  expected: {EXPECTED_GEODSOLVE_VERSION}\n"
            f"  actual:   {actual}"
        )


def build_probe(compiler: str) -> Path:
    root = repo_root()
    source = root / "research/geodesics/inverse_solver_probe.d"

    command = [
        compiler,
        "-i",
        "-Isource",
        str(source),
        f"-of={DEFAULT_PROBE}",
    ]

    subprocess.run(
        command,
        cwd=root,
        check=True,
    )

    return DEFAULT_PROBE


def phi_from_beta(beta: float, f: float) -> float:
    f1 = 1.0 - f

    return math.atan2(
        math.sin(beta),
        f1 * math.cos(beta),
    )


def angle_difference(a: float, b: float) -> float:
    return math.atan2(
        math.sin(a - b),
        math.cos(a - b),
    )


def make_cases() -> dict[str, tuple[float, float, list[tuple[float, float, float, str]]]]:
    rng = random.Random(SEED)
    result = {}

    for name, a, f in PROFILES:
        cases = []

        for beta1, beta2, lambda12, tag in FIXED_CASES:
            if beta1 <= beta2 <= -beta1:
                cases.append(
                    (
                        beta1,
                        beta2,
                        lambda12,
                        tag,
                    )
                )

        for index in range(250):
            beta1 = rng.uniform(
                -1.45,
                -0.03,
            )

            beta2 = rng.uniform(
                beta1 + 1e-9,
                -beta1 - 1e-9,
            )

            if index < 40:
                lambda12 = (
                    math.pi
                    - 10.0 ** rng.uniform(-7.0, -2.0)
                )

                tag = (
                    f"random-near-antipodal-{index:03d}"
                )
            elif index < 70:
                lambda12 = (
                    10.0 ** rng.uniform(-10.0, -2.0)
                )

                tag = (
                    f"random-shortlon-{index:03d}"
                )
            else:
                lambda12 = rng.uniform(
                    0.01,
                    math.pi - 0.01,
                )

                tag = f"random-{index:03d}"

            cases.append(
                (
                    beta1,
                    beta2,
                    lambda12,
                    tag,
                )
            )

        result[name] = (
            a,
            f,
            cases,
        )

    return result


def run_probe(
    executable: Path,
    a: float,
    f: float,
    cases: list[tuple[float, float, float, str]],
) -> list[str]:
    payload = "".join(
        f"{a:.17g} {f:.17g} "
        f"{beta1:.17g} {beta2:.17g} {lambda12:.17g}\n"
        for beta1, beta2, lambda12, _ in cases
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


def run_oracle(
    geodsolve: Path,
    a: float,
    f: float,
    cases: list[tuple[float, float, float, str]],
) -> list[str]:
    payload = []

    for beta1, beta2, lambda12, _ in cases:
        phi1 = math.degrees(
            phi_from_beta(
                beta1,
                f,
            )
        )

        phi2 = math.degrees(
            phi_from_beta(
                beta2,
                f,
            )
        )

        lon2 = math.degrees(lambda12)

        payload.append(
            f"{phi1:.17f} 0 "
            f"{phi2:.17f} {lon2:.17f}\n"
        )

    completed = subprocess.run(
        [
            str(geodsolve),
            "-E",
            "-i",
            "-e",
            f"{a:.17g}",
            f"{f:.17g}",
            "-p",
            "10",
        ],
        input="".join(payload),
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
            f"GeodSolve returned {len(lines)} rows "
            f"for {len(cases)} cases\n"
            f"stderr:\n{completed.stderr}"
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

    max_normalized_distance = 0.0
    max_raw_azimuth = 0.0
    max_well_conditioned_azimuth = 0.0
    max_transverse = 0.0
    max_iterations = 0

    worst_distance = None
    worst_raw_azimuth = None
    worst_well_conditioned_azimuth = None
    worst_transverse = None
    worst_iterations = None

    for profile, (a, f, cases) in cases_by_profile.items():
        probe_lines = run_probe(
            probe,
            a,
            f,
            cases,
        )

        oracle_lines = run_oracle(
            args.geodsolve,
            a,
            f,
            cases,
        )

        for case, actual_line, oracle_line in zip(
            cases,
            probe_lines,
            oracle_lines,
        ):
            beta1, beta2, lambda12, tag = case

            actual_fields = actual_line.split()
            oracle_fields = oracle_line.split()

            if len(actual_fields) != 5:
                raise SystemExit(
                    f"{profile}:{tag}: malformed probe output: "
                    f"{actual_line!r}"
                )

            if len(oracle_fields) < 3:
                raise SystemExit(
                    f"{profile}:{tag}: malformed GeodSolve output: "
                    f"{oracle_line!r}"
                )

            s_actual = float(actual_fields[0])
            azi1_actual = float(actual_fields[1])
            azi2_actual = float(actual_fields[2])
            iterations = int(actual_fields[3])

            azi1_expected = math.radians(
                float(oracle_fields[0])
            )

            azi2_expected = math.radians(
                float(oracle_fields[1])
            )

            s_expected = float(
                oracle_fields[2]
            )

            normalized_distance_error = (
                abs(s_actual - s_expected)
                / a
            )

            azimuth_error = max(
                abs(
                    angle_difference(
                        azi1_actual,
                        azi1_expected,
                    )
                ),
                abs(
                    angle_difference(
                        azi2_actual,
                        azi2_expected,
                    )
                ),
            )

            angular_length = (
                abs(s_expected)
                / a
            )

            transverse_error = (
                angular_length
                * azimuth_error
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
                    beta1,
                    beta2,
                    lambda12,
                    s_expected,
                    s_actual,
                )

            if azimuth_error > max_raw_azimuth:
                max_raw_azimuth = azimuth_error

                worst_raw_azimuth = (
                    profile,
                    tag,
                    beta1,
                    beta2,
                    lambda12,
                    angular_length,
                    azi1_expected,
                    azi1_actual,
                    azi2_expected,
                    azi2_actual,
                )

            if (
                angular_length
                >= WELL_CONDITIONED_MIN_ANGULAR_LENGTH
                and azimuth_error
                    > max_well_conditioned_azimuth
            ):
                max_well_conditioned_azimuth = (
                    azimuth_error
                )

                worst_well_conditioned_azimuth = (
                    profile,
                    tag,
                    beta1,
                    beta2,
                    lambda12,
                    angular_length,
                    azi1_expected,
                    azi1_actual,
                    azi2_expected,
                    azi2_actual,
                )

            if transverse_error > max_transverse:
                max_transverse = transverse_error

                worst_transverse = (
                    profile,
                    tag,
                    beta1,
                    beta2,
                    lambda12,
                    angular_length,
                    azimuth_error,
                    transverse_error,
                )

            if iterations > max_iterations:
                max_iterations = iterations

                worst_iterations = (
                    profile,
                    tag,
                    beta1,
                    beta2,
                    lambda12,
                    iterations,
                )

    print(f"GeodSolve: {EXPECTED_GEODSOLVE_VERSION}")
    print(f"seed: 0x{SEED:08X}")
    print(f"cases: {total}")

    print(
        "max normalized distance error: "
        f"{max_normalized_distance:.17g}"
    )

    print(
        "max raw azimuth error rad: "
        f"{max_raw_azimuth:.17g}"
    )

    print(
        "max well-conditioned azimuth error rad: "
        f"{max_well_conditioned_azimuth:.17g}"
    )

    print(
        "max transverse angular error: "
        f"{max_transverse:.17g}"
    )

    print(
        f"max solver iterations: {max_iterations}"
    )

    print(
        f"worst distance: {worst_distance}"
    )

    print(
        f"worst raw azimuth: {worst_raw_azimuth}"
    )

    print(
        "worst well-conditioned azimuth: "
        f"{worst_well_conditioned_azimuth}"
    )

    print(
        f"worst transverse: {worst_transverse}"
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

    if (
        max_well_conditioned_azimuth
        > AZIMUTH_LIMIT
    ):
        raise SystemExit(
            "FAIL: well-conditioned azimuth error exceeds "
            f"{AZIMUTH_LIMIT} rad"
        )

    if max_transverse > TRANSVERSE_LIMIT:
        raise SystemExit(
            "FAIL: transverse angular error exceeds "
            f"{TRANSVERSE_LIMIT}"
        )

    print("PASS")

    return 0


if __name__ == "__main__":
    sys.exit(main())
