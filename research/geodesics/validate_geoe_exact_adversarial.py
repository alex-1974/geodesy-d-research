#!/usr/bin/env python3
"""
GEO-E exact-oracle validation over the exact adversarial diagnostic corpus.

The corpus and scalarization rules are imported from validate_geoe_adversarial.
For every represented candidate case this validator checks:

1. shortest inverse distance against GeographicLib::GeodesicExact;
2. exact-direct endpoint closure using the candidate initial azimuth+distance;
3. final forward azimuth on that exact-direct candidate path where the endpoint
   and path are well conditioned.

This joins GEO-E path/convergence evidence and the independent oracle on the
same deterministic adversarial population.
"""

from __future__ import annotations

import argparse
import importlib.util
import math
from pathlib import Path
import struct
import subprocess
import sys


LIMITS = {
    "float": {
        "distance": 2.0e-6,
        "closure": 2.0e-6,
        "final": 2.0e-6,
    },
    "double": {
        "distance": 2.0e-10,
        "closure": 2.0e-10,
        "final": 2.0e-10,
    },
    "real": {
        "distance": 2.0e-10,
        "closure": 2.0e-10,
        "final": 2.0e-10,
    },
}

WELL_CONDITIONED_MIN_SIGMA = 1.0e-6
WELL_CONDITIONED_MIN_COS_LAT = 1.0e-6


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_adversarial_module():
    path = repo_root() / "research/geodesics/validate_geoe_adversarial.py"

    spec = importlib.util.spec_from_file_location(
        "geoe_adversarial_shared",
        path,
    )

    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def bits(value: float) -> int:
    return struct.unpack("!Q", struct.pack("!d", float(value)))[0]


def build_candidate_probe(compiler: str) -> Path:
    root = repo_root()
    source = root / "research/geodesics/geoe_inverse_probe.d"
    output = Path(
        f"/tmp/geodesy-geoe-exact-candidate-{Path(compiler).name}"
    )

    subprocess.run(
        [
            compiler,
            "-i",
            "-Isource",
            str(source),
            f"-of={output}",
        ],
        cwd=root,
        check=True,
    )

    return output


def build_exact_probe() -> Path:
    root = repo_root()
    source = root / "research/geodesics/geoe_exact_probe.cpp"
    output = Path("/tmp/geodesy-geoe-exact-oracle")

    subprocess.run(
        [
            "c++",
            "-std=c++17",
            "-O2",
            "-Wall",
            "-Wextra",
            "-pedantic",
            str(source),
            "-lGeographicLib",
            "-o",
            str(output),
        ],
        cwd=root,
        check=True,
    )

    return output


def run_process(command: list[str], payload: str) -> list[str]:
    completed = subprocess.run(
        command,
        input=payload,
        text=True,
        capture_output=True,
        check=True,
    )

    return completed.stdout.splitlines()


def angle_difference(a: float, b: float) -> float:
    return abs((a - b + math.pi) % (2.0 * math.pi) - math.pi)


def vector(latitude: float, longitude: float):
    cos_lat = math.cos(latitude)
    return (
        cos_lat * math.cos(longitude),
        cos_lat * math.sin(longitude),
        math.sin(latitude),
    )


def surface_angle(
    latitude1: float,
    longitude1: float,
    latitude2: float,
    longitude2: float,
) -> float:
    a = vector(latitude1, longitude1)
    b = vector(latitude2, longitude2)

    cross = (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )

    cross_norm = math.sqrt(sum(value * value for value in cross))
    dot = sum(x * y for x, y in zip(a, b))

    return math.atan2(cross_norm, dot)


def represented_case(shared, scalar: str, profile, case):
    _, a, f = profile

    return (
        shared.scalar_value(a, scalar),
        shared.profile_flattening(f, scalar),
        shared.scalar_value(case.lat1, scalar),
        shared.scalar_value(case.lon1, scalar),
        shared.scalar_value(case.lat2, scalar),
        shared.scalar_value(case.lon2, scalar),
    )


def candidate_payload(shared, scalar, profile, cases) -> str:
    _, a, f = profile
    return shared.payload_for(scalar, a, f, cases)


def parse_candidate(line: str):
    fields = line.split()

    if len(fields) != 9:
        raise RuntimeError(f"malformed candidate row: {line!r}")

    return {
        "distance": float(fields[0]),
        "azi1": float(fields[1]),
        "azi2": float(fields[2]),
        "sigma": float(fields[3]),
        "iterations": int(fields[4]),
        "dispatch": int(fields[5]),
        "start": int(fields[6]),
        "brackets": int(fields[7]),
        "converged": int(fields[8]) != 0,
    }


def exact_payload(shared, scalar, profile, cases, candidate_rows) -> str:
    rows = []

    for case, candidate_line in zip(cases, candidate_rows):
        candidate = parse_candidate(candidate_line)
        represented = represented_case(shared, scalar, profile, case)

        values = (
            *represented,
            candidate["distance"],
            candidate["azi1"],
            candidate["azi2"],
        )

        rows.append(" ".join(str(bits(value)) for value in values))

    return "\n".join(rows) + "\n"


def validate(
    shared,
    compiler: str,
    scalar: str,
    profile,
    cases,
    candidate_executable: Path,
    oracle_executable: Path,
):
    profile_name, represented_a_raw, _ = profile

    candidate_rows = run_process(
        [str(candidate_executable), scalar],
        candidate_payload(shared, scalar, profile, cases),
    )

    if len(candidate_rows) != len(cases):
        raise SystemExit(
            f"{compiler}/{scalar}/{profile_name}: "
            f"candidate rows {len(candidate_rows)} != {len(cases)}"
        )

    oracle_rows = run_process(
        [str(oracle_executable)],
        exact_payload(
            shared,
            scalar,
            profile,
            cases,
            candidate_rows,
        ),
    )

    if len(oracle_rows) != len(cases):
        raise SystemExit(
            f"{compiler}/{scalar}/{profile_name}: "
            f"oracle rows {len(oracle_rows)} != {len(cases)}"
        )

    limits = LIMITS[scalar]

    max_distance = 0.0
    max_closure = 0.0
    max_final = 0.0

    worst_distance = None
    worst_closure = None
    worst_final = None
    final_count = 0

    represented_a = shared.scalar_value(
        represented_a_raw,
        scalar,
    )

    for case, candidate_line, oracle_line in zip(
        cases,
        candidate_rows,
        oracle_rows,
    ):
        candidate = parse_candidate(candidate_line)
        oracle_fields = oracle_line.split()

        if len(oracle_fields) != 4:
            raise RuntimeError(
                f"malformed exact-oracle row: {oracle_line!r}"
            )

        exact_distance = float(oracle_fields[0])
        direct_lat2 = float(oracle_fields[1])
        direct_lon2 = float(oracle_fields[2])
        direct_azi2 = float(oracle_fields[3])

        represented = represented_case(
            shared,
            scalar,
            profile,
            case,
        )

        _, _, _, _, target_lat2, target_lon2 = represented

        values = (
            candidate["distance"],
            candidate["azi1"],
            candidate["azi2"],
            candidate["sigma"],
            exact_distance,
            direct_lat2,
            direct_lon2,
            direct_azi2,
        )

        if not all(math.isfinite(value) for value in values):
            raise SystemExit(
                f"FAIL non-finite value: "
                f"{compiler}/{scalar}/{profile_name}/{case.tag}"
            )

        if not candidate["converged"]:
            raise SystemExit(
                f"FAIL non-converged candidate: "
                f"{compiler}/{scalar}/{profile_name}/{case.tag}"
            )

        distance_error = (
            abs(candidate["distance"] - exact_distance)
            / represented_a
        )

        closure_error = surface_angle(
            direct_lat2,
            direct_lon2,
            target_lat2,
            target_lon2,
        )

        if distance_error > max_distance:
            max_distance = distance_error
            worst_distance = (
                case.tag,
                candidate["iterations"],
                candidate["brackets"],
                candidate["start"],
            )

        if closure_error > max_closure:
            max_closure = closure_error
            worst_closure = (
                case.tag,
                candidate["iterations"],
                candidate["brackets"],
                candidate["start"],
            )

        well_conditioned = (
            abs(candidate["sigma"]) >= WELL_CONDITIONED_MIN_SIGMA
            and abs(math.cos(target_lat2))
                >= WELL_CONDITIONED_MIN_COS_LAT
        )

        if well_conditioned:
            final_count += 1
            final_error = angle_difference(
                candidate["azi2"],
                direct_azi2,
            )

            if final_error > max_final:
                max_final = final_error
                worst_final = (
                    case.tag,
                    candidate["iterations"],
                    candidate["brackets"],
                    candidate["start"],
                )

    print(
        f"{compiler:4s} {scalar:6s} {profile_name:11s} "
        f"cases={len(cases):5d} "
        f"dist={max_distance:.3e} "
        f"closure={max_closure:.3e} "
        f"final={max_final:.3e} "
        f"final_n={final_count:5d}"
    )

    failures = []

    if max_distance > limits["distance"]:
        failures.append(
            f"distance {max_distance:.17g} > "
            f"{limits['distance']:.17g}; worst={worst_distance}"
        )

    if max_closure > limits["closure"]:
        failures.append(
            f"closure {max_closure:.17g} > "
            f"{limits['closure']:.17g}; worst={worst_closure}"
        )

    if max_final > limits["final"]:
        failures.append(
            f"final {max_final:.17g} > "
            f"{limits['final']:.17g}; worst={worst_final}"
        )

    if failures:
        raise SystemExit(
            f"FAIL {compiler}/{scalar}/{profile_name}:\n  "
            + "\n  ".join(failures)
        )

    return max_distance, max_closure, max_final


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument(
        "--cases-per-class",
        type=int,
        default=2000,
    )
    args = parser.parse_args()

    shared = load_adversarial_module()

    cases = shared.generate_cases(args.cases_per_class)
    candidate_executable = build_candidate_probe(args.compiler)
    oracle_executable = build_exact_probe()

    print("oracle: GeographicLib::GeodesicExact")
    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{shared.SEED:08X}")
    print(f"cases per adversarial class: {args.cases_per_class}")
    print(f"cases per scalar/profile: {len(cases)}")
    print("oracle corpus: identical GEO-E adversarial cases")

    global_distance = 0.0
    global_closure = 0.0
    global_final = 0.0
    total = 0

    for scalar in shared.SCALARS:
        for profile in shared.PROFILES:
            distance, closure, final = validate(
                shared,
                args.compiler,
                scalar,
                profile,
                cases,
                candidate_executable,
                oracle_executable,
            )

            total += len(cases)
            global_distance = max(global_distance, distance)
            global_closure = max(global_closure, closure)
            global_final = max(global_final, final)

    print()
    print(f"total exact-oracle comparisons: {total}")
    print(
        "max normalized distance error: "
        f"{global_distance:.17g}"
    )
    print(
        "max exact-direct closure angle: "
        f"{global_closure:.17g} rad"
    )
    print(
        "max well-conditioned final azimuth error: "
        f"{global_final:.17g} rad"
    )
    print("GEO-E identical-corpus exact-oracle validation: PASS")

    return 0


if __name__ == "__main__":
    sys.exit(main())
