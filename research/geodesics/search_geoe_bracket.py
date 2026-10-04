#!/usr/bin/env python3
"""
GEO-E targeted search for safeguarded bracket-midpoint fallback.

This is a research diagnostic, not an acceptance oracle. It exercises only the
documented production support domain 0 <= f <= 0.01 and searches specifically
for cases where the internal inverse solver rejects a Newton step and takes the
midpoint of the maintained bracket.

The companion GEO-E acceptance evidence remains:
- diagnostic/adversarial corpus with deterministic repetition;
- GeographicLib GeodesicExact differential validation.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import math
import random
import struct
import subprocess
import sys
from pathlib import Path


SEED = 0x47454F4542524143  # "GEOEBRAC"
DEFAULT_CASES = 250_000
DEFAULT_BATCH = 25_000


@dataclass(frozen=True)
class SearchCase:
    category: str
    a: float
    f: float
    lat1: float
    lon1: float
    lat2: float
    lon2: float


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def f32(value: float) -> float:
    return struct.unpack("!f", struct.pack("!f", float(value)))[0]


def binary64_bits(value: float) -> int:
    return struct.unpack("!Q", struct.pack("!d", float(value)))[0]


def scalar_value(value: float, scalar: str) -> float:
    if scalar == "float":
        return f32(value)
    return float(value)


def represented_flattening(value: float, scalar: str) -> float:
    value = min(max(value, 0.0), 0.01)
    represented = scalar_value(value, scalar)

    if scalar == "real" and represented >= 0.01:
        return math.nextafter(0.01, 0.0)

    # float(0.01) can lie above mathematical 0.01, but the public float path
    # is validated according to its represented public-float contract and is
    # already accepted by the production constructor. Keep the same policy as
    # the existing GEO-E/GEO-D scalarized harnesses.
    return represented


def wrap_pi(value: float) -> float:
    return (value + math.pi) % (2.0 * math.pi) - math.pi


def clamp_lat(value: float) -> float:
    margin = 1e-7
    return max(
        -math.pi / 2.0 + margin,
        min(math.pi / 2.0 - margin, value),
    )


def flattening_sample(rng: random.Random, index: int) -> float:
    """
    Bias heavily toward the upper supported flattening while still covering
    sphere/near-sphere/interior values.
    """
    selector = index % 10

    if selector == 0:
        return 0.0
    if selector == 1:
        return 1e-12
    if selector == 2:
        return 1e-8
    if selector == 3:
        return 1.0 / 298.257223563
    if selector == 4:
        return 0.005
    if selector == 5:
        return 0.009
    if selector == 6:
        return math.nextafter(0.01, 0.0)

    # Dense upper-edge sampling: [0.009, 0.01).
    return 0.009 + rng.random() * (0.001 - 1e-15)


def make_case(rng: random.Random, index: int) -> SearchCase:
    f = flattening_sample(rng, index)

    # Scale must not matter; rotate between terrestrial, unit, and large scale.
    scale_selector = index % 3
    if scale_selector == 0:
        a = 6_378_137.0
    elif scale_selector == 1:
        a = 1.0
    else:
        a = 1.0e9

    regime = index % 8

    if regime in (0, 1, 2):
        # Dense near-antipodal / astroid-transition search.
        lat1 = rng.uniform(-1.45, 1.45)
        lon1 = rng.uniform(-math.pi, math.pi)

        if regime == 0:
            dlat_mag = 10.0 ** rng.uniform(-15.0, -8.0)
            dlon_mag = 10.0 ** rng.uniform(-15.0, -7.0)
        elif regime == 1:
            dlat_mag = 10.0 ** rng.uniform(-10.0, -4.0)
            dlon_mag = 10.0 ** rng.uniform(-10.0, -3.0)
        else:
            dlat_mag = 10.0 ** rng.uniform(-7.0, -2.0)
            dlon_mag = 10.0 ** rng.uniform(-7.0, -2.0)

        dlat = (-1.0 if rng.getrandbits(1) else 1.0) * dlat_mag
        side = -1.0 if rng.getrandbits(1) else 1.0

        return SearchCase(
            f"antipodal-{regime}",
            a,
            f,
            lat1,
            lon1,
            clamp_lat(-lat1 + dlat),
            wrap_pi(lon1 + side * (math.pi - dlon_mag)),
        )

    if regime == 3:
        # Near-equatorial with a long longitude span.
        scale = 10.0 ** rng.uniform(-15.0, -4.0)
        lon1 = rng.uniform(-math.pi, math.pi)
        return SearchCase(
            "near-equatorial",
            a,
            f,
            rng.uniform(-1.0, 1.0) * scale,
            lon1,
            rng.uniform(-1.0, 1.0) * scale,
            wrap_pi(lon1 + rng.uniform(0.5, math.pi - 1e-12)),
        )

    if regime == 4:
        # Near-meridional.
        lon1 = rng.uniform(-math.pi, math.pi)
        dlon = (
            (-1.0 if rng.getrandbits(1) else 1.0)
            * 10.0 ** rng.uniform(-15.0, -4.0)
        )
        return SearchCase(
            "near-meridional",
            a,
            f,
            rng.uniform(-1.5, 1.5),
            lon1,
            rng.uniform(-1.5, 1.5),
            wrap_pi(lon1 + dlon),
        )

    if regime == 5:
        # Nearly polar.
        sign1 = -1.0 if rng.getrandbits(1) else 1.0
        sign2 = -1.0 if rng.getrandbits(1) else 1.0
        eps1 = 10.0 ** rng.uniform(-12.0, -3.0)
        eps2 = 10.0 ** rng.uniform(-12.0, -3.0)
        return SearchCase(
            "near-polar",
            a,
            f,
            sign1 * (math.pi / 2.0 - eps1),
            rng.uniform(-math.pi, math.pi),
            sign2 * (math.pi / 2.0 - eps2),
            rng.uniform(-math.pi, math.pi),
        )

    if regime == 6:
        # Nearly coincident at many scales.
        lat1 = rng.uniform(-1.5, 1.5)
        lon1 = rng.uniform(-math.pi, math.pi)
        radius = 10.0 ** rng.uniform(-15.0, -4.0)
        theta = rng.uniform(-math.pi, math.pi)
        return SearchCase(
            "near-coincident",
            a,
            f,
            lat1,
            lon1,
            clamp_lat(lat1 + radius * math.cos(theta)),
            wrap_pi(lon1 + radius * math.sin(theta)),
        )

    # Broad random supported-domain control population.
    return SearchCase(
        "global-random",
        a,
        f,
        rng.uniform(-math.pi / 2.0, math.pi / 2.0),
        rng.uniform(-math.pi, math.pi),
        rng.uniform(-math.pi / 2.0, math.pi / 2.0),
        rng.uniform(-math.pi, math.pi),
    )


def build_probe(compiler: str) -> Path:
    root = repo_root()
    source = root / "research/geodesics/geoe_inverse_probe.d"
    output = Path(f"/tmp/geodesy-geoe-bracket-{Path(compiler).name}")

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


def payload_row(case: SearchCase, scalar: str) -> str:
    values = (
        scalar_value(case.a, scalar),
        represented_flattening(case.f, scalar),
        scalar_value(case.lat1, scalar),
        scalar_value(case.lon1, scalar),
        scalar_value(case.lat2, scalar),
        scalar_value(case.lon2, scalar),
    )
    return " ".join(str(binary64_bits(value)) for value in values)


def parse_diagnostics(line: str):
    fields = line.split()
    if len(fields) != 9:
        raise RuntimeError(f"malformed diagnostic row: {line!r}")

    return {
        "iterations": int(fields[4]),
        "dispatch": int(fields[5]),
        "start": int(fields[6]),
        "brackets": int(fields[7]),
        "converged": int(fields[8]) != 0,
    }


def scan(
    executable: Path,
    scalar: str,
    count: int,
    batch_size: int,
):
    rng = random.Random(SEED)
    hits = []
    max_iterations = 0
    worst_iteration_case = None
    nonconverged = []
    examined = 0

    while examined < count:
        size = min(batch_size, count - examined)
        cases = [make_case(rng, examined + i) for i in range(size)]
        payload = "\n".join(payload_row(case, scalar) for case in cases) + "\n"

        completed = subprocess.run(
            [str(executable), scalar],
            input=payload,
            text=True,
            capture_output=True,
            check=True,
        )
        lines = completed.stdout.splitlines()

        if len(lines) != len(cases):
            raise SystemExit(
                f"{scalar}: output row mismatch "
                f"{len(lines)} != {len(cases)}"
            )

        for offset, (case, line) in enumerate(zip(cases, lines)):
            d = parse_diagnostics(line)
            absolute_index = examined + offset

            if d["iterations"] > max_iterations:
                max_iterations = d["iterations"]
                worst_iteration_case = (
                    absolute_index,
                    case,
                    d,
                )

            if not d["converged"]:
                nonconverged.append((absolute_index, case, d))

            if d["brackets"] > 0:
                hits.append((absolute_index, case, d, line))
                if len(hits) >= 20:
                    break

        examined += size

        if len(hits) >= 20:
            break

    return {
        "examined": examined,
        "hits": hits,
        "max_iterations": max_iterations,
        "worst": worst_iteration_case,
        "nonconverged": nonconverged,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="dmd")
    parser.add_argument("--cases", type=int, default=DEFAULT_CASES)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH)
    args = parser.parse_args()

    if args.cases < 1:
        raise SystemExit("--cases must be >= 1")
    if args.batch_size < 1:
        raise SystemExit("--batch-size must be >= 1")

    executable = build_probe(args.compiler)

    print(f"compiler: {args.compiler}")
    print(f"seed: 0x{SEED:016X}")
    print(f"target cases per scalar: {args.cases}")
    print("support domain: 0 <= f <= 0.01 only")
    print("search objective: bracketMidpointCount > 0")

    total = 0
    any_hits = False
    global_max_iterations = 0
    global_worst = None

    for scalar in ("float", "double", "real"):
        result = scan(
            executable,
            scalar,
            args.cases,
            args.batch_size,
        )
        total += result["examined"]

        if result["nonconverged"]:
            print()
            print(f"{scalar}: NON-CONVERGENCE DETECTED")
            for row in result["nonconverged"][:20]:
                print(row)
            return 1

        if result["max_iterations"] > global_max_iterations:
            global_max_iterations = result["max_iterations"]
            global_worst = (scalar, result["worst"])

        print(
            f"{scalar:6s} "
            f"examined={result['examined']:7d} "
            f"bracket_hits={len(result['hits']):3d} "
            f"max_iterations={result['max_iterations']:2d}"
        )

        if result["hits"]:
            any_hits = True
            print(f"{scalar}: first bracket hits:")
            for index, case, diagnostics, raw in result["hits"][:20]:
                print(
                    f"  index={index} "
                    f"category={case.category} "
                    f"a={case.a:.17g} f={case.f:.17g} "
                    f"lat1={case.lat1:.17g} lon1={case.lon1:.17g} "
                    f"lat2={case.lat2:.17g} lon2={case.lon2:.17g} "
                    f"diag={diagnostics}"
                )
                print(f"    raw={raw}")

    print()
    print(f"total examined: {total}")
    print(f"global max iterations: {global_max_iterations}")
    print(f"global worst iteration case: {global_worst}")
    print("non-convergence: 0")

    if any_hits:
        print("bracket midpoint fallback: OBSERVED")
    else:
        print("bracket midpoint fallback: NOT OBSERVED")

    print("GEO-E bracket trigger search: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
