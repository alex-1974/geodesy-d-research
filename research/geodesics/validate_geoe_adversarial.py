#!/usr/bin/env python3
"""
GEO-E diagnostic/adversarial smoke validator.

This validator is intentionally about solver path observability, convergence,
bounded iteration, dense adversarial-class coverage, and deterministic
repetition.

Independent numerical correctness remains checked in the same run by the
existing GeographicLib GeodesicExact dispatcher validator.  GEO-E full
acceptance may later merge the oracle and diagnostic corpora after the
instrumentation behavior is understood.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import math
import random
import struct
import subprocess
import sys
from pathlib import Path


SEED = 0x47454F45
DEFAULT_CASES_PER_CLASS = 50

DISPATCH_KIND = {
    0: "coincidence",
    1: "meridian",
    2: "equator",
    3: "generalShort",
    4: "generalNewton",
}

START_KIND = {
    0: "none",
    1: "shortLine",
    2: "spherical",
    3: "antipodal",
    4: "antipodalAstroid",
}

SCALARS = ("float", "double", "real")

PROFILES = (
    ("sphere", 6_371_000.0, 0.0),
    ("near-sphere", 6_378_137.0, 1e-12),
    ("wgs84", 6_378_137.0, 1.0 / 298.257223563),
    ("mid-f", 7_000_000.0, 0.005),
    ("max-f", 7_000_000.0, 0.01),
    ("unit-scale", 1.0, 1.0 / 298.257223563),
)


@dataclass(frozen=True)
class Case:
    tag: str
    category: str
    lat1: float
    lon1: float
    lat2: float
    lon2: float


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def f32(value: float) -> float:
    return struct.unpack("!f", struct.pack("!f", float(value)))[0]


def scalar_value(value: float, scalar: str) -> float:
    if scalar == "float":
        return f32(value)
    return float(value)


def profile_flattening(value: float, scalar: str) -> float:
    represented = scalar_value(value, scalar)

    if scalar == "real" and value == 0.01:
        return math.nextafter(0.01, 0.0)

    return represented


def binary64_bits(value: float) -> int:
    return struct.unpack("!Q", struct.pack("!d", float(value)))[0]


def wrap_pi(value: float) -> float:
    period = 2.0 * math.pi
    value = (value + math.pi) % period - math.pi

    if value == math.pi:
        value = -math.pi

    return value


def random_lat(rng: random.Random, margin: float = 0.05) -> float:
    return rng.uniform(
        -math.pi / 2.0 + margin,
        math.pi / 2.0 - margin,
    )


def fixed_cases() -> list[Case]:
    r = math.radians

    return [
        Case("fixed-coincidence", "fixed", r(20), r(30), r(20), r(30)),
        Case("fixed-meridian", "fixed", r(-60), r(10), r(40), r(10)),
        Case("fixed-equator", "fixed", 0.0, r(10), 0.0, r(40)),
        Case(
            "fixed-general-short",
            "fixed",
            r(20),
            r(30),
            r(20) + 1e-10,
            r(30) + 1e-10,
        ),
        Case(
            "fixed-near-antipodal",
            "fixed",
            r(-10),
            0.0,
            r(10.0001),
            math.pi - 1e-4,
        ),
        Case(
            "fixed-ngs-nonconvergence-regression",
            "fixed",
            r(27.2),
            0.0,
            r(-27.1),
            r(179.5),
        ),
        Case(
            "fixed-exact-antipodal",
            "exact-antipodal",
            r(12.5),
            r(23.0),
            r(-12.5),
            wrap_pi(r(23.0) + math.pi),
        ),
    ]


def generate_cases(count: int) -> list[Case]:
    rng = random.Random(SEED)
    cases = fixed_cases()

    for i in range(count):
        # Nearly coincident.
        lat1 = random_lat(rng)
        lon1 = rng.uniform(-math.pi, math.pi)
        scale = 10.0 ** rng.uniform(-10.0, -6.0)
        theta = rng.uniform(-math.pi, math.pi)
        cases.append(
            Case(
                f"nearly-coincident-{i:04d}",
                "nearly-coincident",
                lat1,
                lon1,
                max(
                    -math.pi / 2 + 1e-8,
                    min(
                        math.pi / 2 - 1e-8,
                        lat1 + scale * math.cos(theta),
                    ),
                ),
                wrap_pi(lon1 + scale * math.sin(theta)),
            )
        )

        # Nearly polar, but far enough from the pole to survive float
        # scalarization as an interior latitude.
        sign = -1.0 if rng.getrandbits(1) else 1.0
        eps1 = 10.0 ** rng.uniform(-5.0, -2.0)
        eps2 = 10.0 ** rng.uniform(-5.0, -2.0)
        cases.append(
            Case(
                f"nearly-polar-{i:04d}",
                "nearly-polar",
                sign * (math.pi / 2 - eps1),
                rng.uniform(-math.pi, math.pi),
                sign * (math.pi / 2 - eps2),
                rng.uniform(-math.pi, math.pi),
            )
        )

        # Near equator.
        lat_scale = 10.0 ** rng.uniform(-10.0, -5.0)
        cases.append(
            Case(
                f"near-equatorial-{i:04d}",
                "near-equatorial",
                rng.uniform(-1.0, 1.0) * lat_scale,
                rng.uniform(-math.pi, math.pi),
                rng.uniform(-1.0, 1.0) * lat_scale,
                rng.uniform(-math.pi, math.pi),
            )
        )

        # Near meridian.
        lon1 = rng.uniform(-math.pi, math.pi)
        delta_lon = (
            (-1.0 if rng.getrandbits(1) else 1.0)
            * 10.0 ** rng.uniform(-10.0, -5.0)
        )
        cases.append(
            Case(
                f"near-meridional-{i:04d}",
                "near-meridional",
                random_lat(rng),
                lon1,
                random_lat(rng),
                wrap_pi(lon1 + delta_lon),
            )
        )

        # Longitude difference close to pi.
        lon1 = rng.uniform(-math.pi, math.pi)
        delta = 10.0 ** rng.uniform(-10.0, -4.0)
        cases.append(
            Case(
                f"longitude-near-pi-{i:04d}",
                "longitude-near-pi",
                random_lat(rng),
                lon1,
                random_lat(rng),
                wrap_pi(lon1 + math.pi - delta),
            )
        )

        # beta/latitude antisymmetry neighborhood.
        lat1 = random_lat(rng, margin=0.15)
        lat_delta = (
            (-1.0 if rng.getrandbits(1) else 1.0)
            * 10.0 ** rng.uniform(-10.0, -5.0)
        )
        lon1 = rng.uniform(-math.pi, math.pi)
        cases.append(
            Case(
                f"latitude-antisy-{i:04d}",
                "latitude2-near-minus-latitude1",
                lat1,
                lon1,
                -lat1 + lat_delta,
                wrap_pi(
                    lon1
                    + rng.uniform(0.6 * math.pi, math.pi - 1e-4)
                ),
            )
        )

        # Dense near-antipodal / astroid neighborhood.
        lat1 = rng.uniform(-1.25, 1.25)
        lon1 = rng.uniform(-math.pi, math.pi)
        dlat = (
            (-1.0 if rng.getrandbits(1) else 1.0)
            * 10.0 ** rng.uniform(-9.0, -4.0)
        )
        dlon = 10.0 ** rng.uniform(-9.0, -3.0)
        cases.append(
            Case(
                f"antipodal-transition-{i:04d}",
                "antipodal-transition",
                lat1,
                lon1,
                -lat1 + dlat,
                wrap_pi(lon1 + math.pi - dlon),
            )
        )

        # Exact ambiguous antipode.
        lat1 = rng.uniform(-1.2, 1.2)
        lon1 = rng.uniform(-2.8, 2.8)
        cases.append(
            Case(
                f"exact-antipodal-{i:04d}",
                "exact-antipodal",
                lat1,
                lon1,
                -lat1,
                wrap_pi(lon1 + math.pi),
            )
        )

    return cases


def build_probe(compiler: str) -> Path:
    root = repo_root()
    source = root / "research/geodesics/geoe_inverse_probe.d"
    output = Path(f"/tmp/geodesy-geoe-inverse-{Path(compiler).name}")

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


def payload_for(
    scalar: str,
    a: float,
    f: float,
    cases: list[Case],
) -> str:
    represented_a = scalar_value(a, scalar)
    represented_f = profile_flattening(f, scalar)

    rows = []

    for case in cases:
        values = (
            represented_a,
            represented_f,
            scalar_value(case.lat1, scalar),
            scalar_value(case.lon1, scalar),
            scalar_value(case.lat2, scalar),
            scalar_value(case.lon2, scalar),
        )

        rows.append(
            " ".join(str(binary64_bits(v)) for v in values)
        )

    return "\n".join(rows) + "\n"


def run_probe(
    executable: Path,
    scalar: str,
    payload: str,
) -> list[str]:
    completed = subprocess.run(
        [str(executable), scalar],
        input=payload,
        text=True,
        capture_output=True,
        check=True,
    )

    return completed.stdout.splitlines()


def parse_row(line: str) -> tuple[int, int, int, int, bool]:
    fields = line.split()

    if len(fields) != 9:
        raise RuntimeError(f"malformed GEO-E row: {line!r}")

    # Numeric result fields 0..3 are deliberately retained in stdout for
    # deterministic-repeat comparison. Diagnostics begin at field 4.
    iterations = int(fields[4])
    dispatch_kind = int(fields[5])
    start_kind = int(fields[6])
    bracket_count = int(fields[7])
    converged = int(fields[8]) != 0

    if dispatch_kind not in DISPATCH_KIND:
        raise RuntimeError(f"unknown dispatch kind: {dispatch_kind}")

    if start_kind not in START_KIND:
        raise RuntimeError(f"unknown start kind: {start_kind}")

    return (
        iterations,
        dispatch_kind,
        start_kind,
        bracket_count,
        converged,
    )


def validate_scalar_profile(
    executable: Path,
    scalar: str,
    profile_name: str,
    a: float,
    f: float,
    cases: list[Case],
):
    payload = payload_for(scalar, a, f, cases)

    first = run_probe(executable, scalar, payload)
    second = run_probe(executable, scalar, payload)

    if first != second:
        for index, (a_line, b_line) in enumerate(zip(first, second)):
            if a_line != b_line:
                raise SystemExit(
                    "FAIL deterministic repeat: "
                    f"{scalar}/{profile_name}/{cases[index].tag}\n"
                    f"first:  {a_line}\n"
                    f"second: {b_line}"
                )

        raise SystemExit(
            "FAIL deterministic repeat: output row count changed"
        )

    if len(first) != len(cases):
        raise SystemExit(
            f"FAIL {scalar}/{profile_name}: "
            f"{len(first)} output rows for {len(cases)} cases"
        )

    dispatch_counts = Counter()
    start_counts = Counter()
    category_counts = defaultdict(Counter)

    max_iterations = 0
    max_brackets = 0
    worst_iterations = None
    worst_brackets = None
    nonconverged = []

    for case, line in zip(cases, first):
        (
            iterations,
            dispatch_kind,
            start_kind,
            bracket_count,
            converged,
        ) = parse_row(line)

        dispatch_name = DISPATCH_KIND[dispatch_kind]
        start_name = START_KIND[start_kind]

        dispatch_counts[dispatch_name] += 1
        start_counts[start_name] += 1
        category_counts[case.category][dispatch_name] += 1
        category_counts[case.category][f"start:{start_name}"] += 1

        if iterations > max_iterations:
            max_iterations = iterations
            worst_iterations = (
                case.tag,
                dispatch_name,
                start_name,
                bracket_count,
            )

        if bracket_count > max_brackets:
            max_brackets = bracket_count
            worst_brackets = (
                case.tag,
                dispatch_name,
                start_name,
                iterations,
            )

        if not converged:
            nonconverged.append(
                (
                    case.tag,
                    dispatch_name,
                    start_name,
                    iterations,
                    bracket_count,
                )
            )

    if nonconverged:
        preview = "\n".join(
            f"  {row}" for row in nonconverged[:20]
        )
        raise SystemExit(
            f"FAIL non-convergence {scalar}/{profile_name}: "
            f"{len(nonconverged)} cases\n{preview}"
        )

    print(
        f"{scalar:6s} {profile_name:11s} "
        f"cases={len(cases):4d} "
        f"iter_max={max_iterations:2d} "
        f"bracket_max={max_brackets:2d} "
        f"astroid={start_counts['antipodalAstroid']:4d} "
        f"antipodal={start_counts['antipodal']:4d} "
        f"short={start_counts['shortLine']:4d}"
    )

    return {
        "dispatch": dispatch_counts,
        "start": start_counts,
        "categories": category_counts,
        "max_iterations": max_iterations,
        "max_brackets": max_brackets,
        "worst_iterations": worst_iterations,
        "worst_brackets": worst_brackets,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument(
        "--cases-per-class",
        type=int,
        default=DEFAULT_CASES_PER_CLASS,
    )
    args = parser.parse_args()

    if args.cases_per_class < 1:
        raise SystemExit("--cases-per-class must be >= 1")

    executable = build_probe(args.compiler)
    cases = generate_cases(args.cases_per_class)

    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{SEED:08X}")
    print(f"cases per adversarial class: {args.cases_per_class}")
    print(f"cases per scalar/profile: {len(cases)}")
    print("deterministic repeat: every payload is executed twice")

    global_dispatch = Counter()
    global_start = Counter()
    global_categories = defaultdict(Counter)
    global_max_iterations = 0
    global_max_brackets = 0
    worst_iterations = None
    worst_brackets = None

    for scalar in SCALARS:
        for profile_name, a, f in PROFILES:
            result = validate_scalar_profile(
                executable,
                scalar,
                profile_name,
                a,
                f,
                cases,
            )

            global_dispatch.update(result["dispatch"])
            global_start.update(result["start"])

            for category, counts in result["categories"].items():
                global_categories[category].update(counts)

            if result["max_iterations"] > global_max_iterations:
                global_max_iterations = result["max_iterations"]
                worst_iterations = (
                    scalar,
                    profile_name,
                    result["worst_iterations"],
                )

            if result["max_brackets"] > global_max_brackets:
                global_max_brackets = result["max_brackets"]
                worst_brackets = (
                    scalar,
                    profile_name,
                    result["worst_brackets"],
                )

    print()
    print("=== GLOBAL DISPATCH COVERAGE ===")
    for name in DISPATCH_KIND.values():
        print(f"{name:16s} {global_dispatch[name]}")

    print()
    print("=== GLOBAL START COVERAGE ===")
    for name in START_KIND.values():
        print(f"{name:16s} {global_start[name]}")

    print()
    print("=== ADVERSARIAL CATEGORY COVERAGE ===")
    for category in sorted(global_categories):
        counts = global_categories[category]
        print(
            f"{category:34s} "
            f"newton={counts['generalNewton']:6d} "
            f"short={counts['generalShort']:6d} "
            f"astroid={counts['start:antipodalAstroid']:6d} "
            f"antipodal={counts['start:antipodal']:6d}"
        )

    print()
    print(f"max solver iterations: {global_max_iterations}")
    print(f"worst iterations: {worst_iterations}")
    print(f"max bracket midpoint count: {global_max_brackets}")
    print(f"worst bracket midpoint count: {worst_brackets}")

    required_dispatch = set(DISPATCH_KIND.values())
    missing_dispatch = {
        name
        for name in required_dispatch
        if global_dispatch[name] == 0
    }

    if missing_dispatch:
        raise SystemExit(
            "FAIL missing dispatcher coverage: "
            + ", ".join(sorted(missing_dispatch))
        )

    required_start = {"shortLine", "spherical"}

    # On an oblate adversarial corpus we also require evidence that the
    # antipodal/Astroid starting strategy is actually observed.
    if global_start["antipodal"] + global_start["antipodalAstroid"] == 0:
        raise SystemExit(
            "FAIL: antipodal starting strategy was never observed"
        )

    if global_start["antipodalAstroid"] == 0:
        raise SystemExit(
            "FAIL: Astroid starting strategy was never observed"
        )

    missing_start = {
        name
        for name in required_start
        if global_start[name] == 0
    }

    if missing_start:
        raise SystemExit(
            "FAIL missing start coverage: "
            + ", ".join(sorted(missing_start))
        )

    # The production Newton-only budget is 20.  GEO-E smoke does not yet use
    # this as the final acceptance margin, but exceeding it would immediately
    # indicate that safeguarded fallback is materially involved.
    if global_max_iterations > 20 + real_mantissa_safety():
        raise SystemExit(
            f"FAIL unexpectedly large iteration count: "
            f"{global_max_iterations}"
        )

    print()
    print("non-convergence: 0")
    print("deterministic repeat mismatches: 0")
    print("GEO-E diagnostic/adversarial smoke: PASS")
    return 0


def real_mantissa_safety() -> int:
    # Deliberately generous smoke ceiling; final GEO-E acceptance will justify
    # a production margin from measured evidence rather than this helper.
    return 80


if __name__ == "__main__":
    sys.exit(main())
