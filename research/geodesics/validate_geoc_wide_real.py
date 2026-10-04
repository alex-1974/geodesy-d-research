#!/usr/bin/env python3
"""
GEO-C wide-real precision qualification.

This complements validate_geoc_exact.py.  The bulk GEO-C runner deliberately
uses a large fixed-seed corpus generated in Python binary64.  This validator
proves that the public Geodesic!real path also accepts and preserves inputs
which are not representable as binary64 and compares them against a 512-bit
MPFR GeographicLib GeodesicExact oracle without converting candidate or oracle
numeric results through Python float.

The corpus is intentionally ordinary/well-conditioned.  Singular and
near-singular behavior is covered by the bulk GEO-C runner and the focused
inverse validators.  This subgate is specifically a precision-path gate.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from decimal import Decimal, getcontext
import os
from pathlib import Path
import random
import subprocess
import sys


getcontext().prec = 80

ROOT = Path(__file__).resolve().parents[2]
PROBE_SOURCE = ROOT / "research/geodesics/geoc_public_probe.d"
DEFAULT_PROBE = Path("/tmp/geodesy-geoc-wide-real-probe")
DEFAULT_GEODSOLVE = Path(
    "/tmp/geographiclib-r2.7-build-mpfr-geob/tools/GeodSolve"
)

EXPECTED_VERSION = "GeodSolve: GeographicLib version 2.7"
SEED = 0x47454F52
FULL_CASES_PER_PROFILE = 250

PI = Decimal(
    "3.141592653589793238462643383279502884197169399375105820974944592307816406286"
)
DEG_PER_RAD = Decimal(180) / PI
RAD_PER_DEG = PI / Decimal(180)

# A deliberately stricter precision-path budget than the ordinary GEO-C
# double/real bulk budget.  GEO-B already demonstrated order-7 real errors
# around 1e-19 to 1e-18 on committed high-precision vectors.
LIMIT = Decimal("2e-16")


@dataclass(frozen=True)
class Profile:
    name: str
    a: Decimal
    f: Decimal


WGS_F = Decimal(1) / Decimal("298.257223563")
GRS80_F = Decimal(1) / Decimal("298.257222101")
AIRY_F = Decimal(1) / Decimal("299.3249646")

PROFILES = (
    Profile("sphere", Decimal("6371000"), Decimal(0)),
    Profile("wgs84", Decimal("6378137"), WGS_F),
    Profile("grs80", Decimal("6378137"), GRS80_F),
    Profile(
        "international-1924",
        Decimal("6378388"),
        Decimal(1) / Decimal("297"),
    ),
    Profile("airy-1830", Decimal("6377563.396"), AIRY_F),
    Profile("max-f", Decimal("7000000"), Decimal("0.01")),
    Profile("unit-scale", Decimal("1"), WGS_F),
    Profile("large-scale", Decimal("1000000000"), WGS_F),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument(
        "--geodsolve",
        type=Path,
        default=DEFAULT_GEODSOLVE,
    )
    parser.add_argument(
        "--probe",
        type=Path,
        default=None,
    )
    parser.add_argument(
        "--cases-per-profile",
        type=int,
        default=FULL_CASES_PER_PROFILE,
    )
    return parser.parse_args()


def normalize_version(raw: str) -> str:
    line = raw.strip().splitlines()[0]
    executable, separator, suffix = line.partition(":")
    if not separator:
        return line
    return f"{Path(executable).name}:{suffix}"


def mpfr_env() -> dict[str, str]:
    env = dict(os.environ)
    env["GEOGRAPHICLIB_DIGITS"] = "512"
    return env


def verify_oracle(executable: Path) -> None:
    if not executable.is_file():
        raise SystemExit(f"MPFR GeodSolve not found: {executable}")

    completed = subprocess.run(
        [str(executable), "--version"],
        text=True,
        capture_output=True,
        env=mpfr_env(),
        check=True,
    )
    actual = normalize_version(completed.stdout)
    if actual != EXPECTED_VERSION:
        raise SystemExit(
            "unexpected MPFR GeodSolve version:\n"
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


def fixed(value: Decimal) -> str:
    return format(value, "f")


def parse_decimal_row(line: str, prefix: str, count: int) -> tuple[Decimal, ...]:
    fields = line.split()
    if len(fields) != count + 1 or fields[0] != prefix:
        raise RuntimeError(f"malformed candidate row: {line!r}")
    return tuple(Decimal(value) for value in fields[1:])


def run(
    command: list[str],
    payload: str,
    *,
    env: dict[str, str] | None = None,
) -> list[str]:
    completed = subprocess.run(
        command,
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    return [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]


def geodsolve_command(
    executable: Path,
    profile: Profile,
    *,
    inverse: bool,
) -> list[str]:
    command = [
        str(executable),
        "-E",
        "-e",
        fixed(profile.a),
        fixed(profile.f),
        "-p",
        "30",
    ]
    if inverse:
        command.insert(2, "-i")
    return command


def rad_to_deg(value: Decimal) -> Decimal:
    return value * DEG_PER_RAD


def angle_diff_degrees(first: Decimal, second: Decimal) -> Decimal:
    full = Decimal(360)
    half = Decimal(180)
    diff = (first - second) % full
    if diff >= half:
        diff -= full
    return abs(diff)


def not_binary64(value: Decimal) -> bool:
    # str(float(...)) captures the semantic decimal value which a Python
    # binary64 roundtrip would feed back to the validator.
    return Decimal(str(float(value))) != value


def random_decimal(
    rng: random.Random,
    low_whole: int,
    high_whole: int,
    places: int = 18,
) -> Decimal:
    scale = 10 ** places
    raw = rng.randrange(low_whole * scale, high_whole * scale + 1)
    value = Decimal(raw) / Decimal(scale)

    # Ensure this input actually distinguishes the real path from binary64.
    if not not_binary64(value):
        value += Decimal(1) / Decimal(scale)

    return value


def direct_inputs(
    profile_index: int,
    count: int,
) -> list[tuple[Decimal, Decimal, Decimal, Decimal]]:
    rng = random.Random(SEED ^ 0xD1EC7100 ^ profile_index)
    result = []

    for _ in range(count):
        lat = random_decimal(rng, -70, 70)
        lon = random_decimal(rng, -175, 175)
        azi = random_decimal(rng, -179, 179)

        # 0.05 .. 2.50 semi-major axes, with > binary64 input precision.
        numerator = rng.randrange(50_000_000_000_000_001, 2_500_000_000_000_000_000)
        ratio = Decimal(numerator) / Decimal(10**18)
        distance = ratio * PROFILES[profile_index].a

        if not not_binary64(distance):
            distance += Decimal("1e-18") * PROFILES[profile_index].a

        result.append((lat, lon, azi, distance))

    return result


def inverse_inputs(
    profile_index: int,
    count: int,
) -> list[tuple[Decimal, Decimal, Decimal, Decimal]]:
    rng = random.Random(SEED ^ 0x1A2B3100 ^ profile_index)
    result = []

    while len(result) < count:
        lat1 = random_decimal(rng, -70, 70)
        lon1 = random_decimal(rng, -175, 175)
        lat2 = random_decimal(rng, -70, 70)
        lon2 = random_decimal(rng, -175, 175)

        # Keep this precision subgate ordinary and well-conditioned.
        if abs(lat1 - lat2) + abs(lon1 - lon2) < Decimal("1"):
            continue

        result.append((lat1, lon1, lat2, lon2))

    return result


def candidate_direct(
    probe: Path,
    profile: Profile,
    cases: list[tuple[Decimal, Decimal, Decimal, Decimal]],
) -> list[tuple[Decimal, ...]]:
    payload = "".join(
        "D "
        f"{fixed(profile.a)} {fixed(profile.f)} "
        f"{fixed(lat)} {fixed(lon)} {fixed(azi)} {fixed(distance)}\n"
        for lat, lon, azi, distance in cases
    )
    lines = run([str(probe), "real"], payload)
    if len(lines) != len(cases):
        raise RuntimeError("candidate Direct row-count mismatch")
    return [parse_decimal_row(line, "D", 7) for line in lines]


def candidate_inverse(
    probe: Path,
    profile: Profile,
    cases: list[tuple[Decimal, Decimal, Decimal, Decimal]],
) -> list[tuple[Decimal, ...]]:
    payload = "".join(
        "I "
        f"{fixed(profile.a)} {fixed(profile.f)} "
        f"{fixed(lat1)} {fixed(lon1)} {fixed(lat2)} {fixed(lon2)}\n"
        for lat1, lon1, lat2, lon2 in cases
    )
    lines = run([str(probe), "real"], payload)
    if len(lines) != len(cases):
        raise RuntimeError("candidate Inverse row-count mismatch")
    return [parse_decimal_row(line, "I", 7) for line in lines]


def oracle_direct(
    executable: Path,
    profile: Profile,
    semantic_rows: list[tuple[Decimal, ...]],
) -> list[tuple[Decimal, Decimal, Decimal]]:
    payload = "".join(
        f"{fixed(rad_to_deg(row[0]))} "
        f"{fixed(rad_to_deg(row[1]))} "
        f"{fixed(rad_to_deg(row[2]))} "
        f"{fixed(row[3])}\n"
        for row in semantic_rows
    )
    lines = run(
        geodsolve_command(executable, profile, inverse=False),
        payload,
        env=mpfr_env(),
    )
    if len(lines) != len(semantic_rows):
        raise RuntimeError("MPFR Direct row-count mismatch")
    result = []
    for line in lines:
        fields = line.split()
        if len(fields) < 3:
            raise RuntimeError(f"malformed MPFR Direct row: {line!r}")
        result.append(
            (Decimal(fields[0]), Decimal(fields[1]), Decimal(fields[2]))
        )
    return result


def oracle_inverse(
    executable: Path,
    profile: Profile,
    points_degrees: list[tuple[Decimal, Decimal, Decimal, Decimal]],
) -> list[tuple[Decimal, Decimal, Decimal]]:
    payload = "".join(
        f"{fixed(lat1)} {fixed(lon1)} {fixed(lat2)} {fixed(lon2)}\n"
        for lat1, lon1, lat2, lon2 in points_degrees
    )
    lines = run(
        geodsolve_command(executable, profile, inverse=True),
        payload,
        env=mpfr_env(),
    )
    if len(lines) != len(points_degrees):
        raise RuntimeError("MPFR Inverse row-count mismatch")
    result = []
    for line in lines:
        fields = line.split()
        if len(fields) < 3:
            raise RuntimeError(f"malformed MPFR Inverse row: {line!r}")
        result.append(
            (Decimal(fields[0]), Decimal(fields[1]), Decimal(fields[2]))
        )
    return result


def validate_direct(
    executable: Path,
    probe: Path,
    profile: Profile,
    cases: list[tuple[Decimal, Decimal, Decimal, Decimal]],
) -> tuple[Decimal, Decimal]:
    actual = candidate_direct(probe, profile, cases)
    expected = oracle_direct(executable, profile, actual)

    comparison_points = []
    for row, ref in zip(actual, expected):
        comparison_points.append(
            (
                rad_to_deg(row[4]),
                rad_to_deg(row[5]),
                ref[0],
                ref[1],
            )
        )

    separations = oracle_inverse(executable, profile, comparison_points)

    max_endpoint = Decimal(0)
    max_azimuth = Decimal(0)

    for row, ref, separation in zip(actual, expected, separations):
        endpoint = abs(separation[2]) / profile.a
        azimuth = (
            angle_diff_degrees(rad_to_deg(row[6]), ref[2])
            * RAD_PER_DEG
        )
        max_endpoint = max(max_endpoint, endpoint)
        max_azimuth = max(max_azimuth, azimuth)

    return max_endpoint, max_azimuth


def validate_inverse(
    executable: Path,
    probe: Path,
    profile: Profile,
    cases: list[tuple[Decimal, Decimal, Decimal, Decimal]],
) -> tuple[Decimal, Decimal, Decimal]:
    actual = candidate_inverse(probe, profile, cases)

    semantic_points = [
        (
            rad_to_deg(row[0]),
            rad_to_deg(row[1]),
            rad_to_deg(row[2]),
            rad_to_deg(row[3]),
        )
        for row in actual
    ]

    expected = oracle_inverse(executable, profile, semantic_points)

    max_distance = Decimal(0)
    max_initial = Decimal(0)
    max_final = Decimal(0)

    for row, ref in zip(actual, expected):
        distance = abs(row[4] - ref[2]) / profile.a
        initial = (
            angle_diff_degrees(rad_to_deg(row[5]), ref[0])
            * RAD_PER_DEG
        )
        final = (
            angle_diff_degrees(rad_to_deg(row[6]), ref[1])
            * RAD_PER_DEG
        )

        max_distance = max(max_distance, distance)
        max_initial = max(max_initial, initial)
        max_final = max(max_final, final)

    return max_distance, max_initial, max_final


def main() -> int:
    args = parse_args()

    if args.cases_per_profile <= 0:
        raise SystemExit("--cases-per-profile must be > 0")

    verify_oracle(args.geodsolve)

    probe = args.probe if args.probe is not None else build_probe(args.compiler)

    full = args.cases_per_profile >= FULL_CASES_PER_PROFILE

    print(EXPECTED_VERSION)
    print("oracle precision: MPFR 512 bits")
    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{SEED:08X}")
    print(f"cases/profile/operation: {args.cases_per_profile}")
    print("mode: " + ("FULL" if full else "SMOKE / NON-ACCEPTANCE"))
    print(f"wide-real limit: {LIMIT}")

    global_values = {
        "direct_endpoint": Decimal(0),
        "direct_azimuth": Decimal(0),
        "inverse_distance": Decimal(0),
        "inverse_initial": Decimal(0),
        "inverse_final": Decimal(0),
    }

    non_binary64_inputs = 0
    total_input_scalars = 0

    for index, profile in enumerate(PROFILES):
        direct_cases = direct_inputs(index, args.cases_per_profile)
        inverse_cases = inverse_inputs(index, args.cases_per_profile)

        for case in direct_cases:
            for value in case:
                total_input_scalars += 1
                non_binary64_inputs += int(not_binary64(value))

        for case in inverse_cases:
            for value in case:
                total_input_scalars += 1
                non_binary64_inputs += int(not_binary64(value))

        d_endpoint, d_azimuth = validate_direct(
            args.geodsolve,
            probe,
            profile,
            direct_cases,
        )
        i_distance, i_initial, i_final = validate_inverse(
            args.geodsolve,
            probe,
            profile,
            inverse_cases,
        )

        global_values["direct_endpoint"] = max(
            global_values["direct_endpoint"], d_endpoint
        )
        global_values["direct_azimuth"] = max(
            global_values["direct_azimuth"], d_azimuth
        )
        global_values["inverse_distance"] = max(
            global_values["inverse_distance"], i_distance
        )
        global_values["inverse_initial"] = max(
            global_values["inverse_initial"], i_initial
        )
        global_values["inverse_final"] = max(
            global_values["inverse_final"], i_final
        )

        print(
            f"{profile.name}: "
            f"D.end={d_endpoint:.3E} "
            f"D.azi={d_azimuth:.3E} "
            f"I.dist={i_distance:.3E} "
            f"I.azi1={i_initial:.3E} "
            f"I.azi2={i_final:.3E}"
        )

    print()
    print(
        "inputs not preserved by binary64 roundtrip: "
        f"{non_binary64_inputs}/{total_input_scalars}"
    )

    for name, value in global_values.items():
        print(f"max {name}: {value:.17E}")
        if value > LIMIT:
            raise SystemExit(
                f"FAIL wide-real: {name} {value} > {LIMIT}"
            )

    if non_binary64_inputs == 0:
        raise SystemExit("FAIL wide-real: corpus contains no >binary64 inputs")

    if full:
        print("GEO-C wide-real precision qualification: PASS")
    else:
        print(
            "GEO-C wide-real smoke: PASS "
            "(not sufficient for acceptance)"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
