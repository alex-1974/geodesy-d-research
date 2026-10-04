#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import random
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_d_factor_prototype as common


GEOGRAPHICLIB_EXE = "/usr/bin/TransverseMercatorProj"

SANITY_GAMMA_DEG = 0.1
SANITY_RELATIVE_SCALE = 1.0e-3


@dataclass(frozen=True)
class Case:
    index: int
    latitude: float
    longitude: float


@dataclass(frozen=True)
class ProbeRow:
    easting: float
    northing: float
    reverse_latitude: float
    reverse_longitude: float
    gamma_b: float
    scale_b: float
    gamma_a: float
    scale_a: float


@dataclass(frozen=True)
class OracleRow:
    latitude: float
    longitude: float
    gamma: float
    scale: float


def label(profile, case: Case) -> str:
    return (
        f"{profile.name}[{case.index}] "
        f"lat={case.latitude:.12g} "
        f"lon={case.longitude:.12g}"
    )


def build_cases(profile, rng: random.Random) -> list[Case]:
    points: list[tuple[float, float]] = []

    for latitude in common.STRUCTURED_LATITUDES:
        for delta_longitude in common.STRUCTURED_DLONGITUDES:
            points.append(
                (
                    latitude,
                    profile.lon0 + delta_longitude,
                )
            )

    for _ in range(common.RANDOM_CASES_PER_PROFILE):
        latitude = rng.uniform(-85.0, 85.0)
        delta_longitude = rng.uniform(-60.0, 60.0)
        points.append(
            (
                latitude,
                profile.lon0 + delta_longitude,
            )
        )

    return [
        Case(index, latitude, longitude)
        for index, (latitude, longitude)
        in enumerate(points)
    ]


def probe_command(binary: str, profile) -> list[str]:
    return [
        binary,
        repr(profile.a),
        repr(profile.f),
        repr(profile.lat0),
        repr(profile.lon0),
        repr(profile.k0),
        repr(profile.false_e),
        repr(profile.false_n),
    ]


def run_probe(
    binary: str,
    profile,
    cases: list[Case],
) -> list[ProbeRow]:
    input_text = "".join(
        f"{case.latitude:.17g} {case.longitude:.17g}\n"
        for case in cases
    )

    completed = subprocess.run(
        probe_command(binary, profile),
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    lines = [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if len(lines) != len(cases):
        raise RuntimeError(
            f"{profile.name}: probe returned {len(lines)} lines "
            f"for {len(cases)} cases\n"
            f"stderr:\n{completed.stderr}"
        )

    rows: list[ProbeRow] = []

    for case, line in zip(cases, lines):
        fields = line.split()

        if not fields or fields[0] != "OK":
            raise RuntimeError(
                f"{label(profile, case)}: "
                f"probe result {line!r}"
            )

        if len(fields) != 9:
            raise RuntimeError(
                f"{label(profile, case)}: "
                f"expected 9 output fields, got {len(fields)}"
            )

        values = [float(value) for value in fields[1:]]

        rows.append(
            ProbeRow(
                easting=values[0],
                northing=values[1],
                reverse_latitude=values[2],
                reverse_longitude=values[3],
                gamma_b=values[4],
                scale_b=values[5],
                gamma_a=values[6],
                scale_a=values[7],
            )
        )

    return rows


def geographiclib_base_command(profile) -> list[str]:
    return [
        GEOGRAPHICLIB_EXE,
        "-l",
        repr(profile.lon0),
        "-k",
        repr(profile.k0),
        "-e",
        repr(profile.a),
        repr(profile.f),
        "-p",
        "15",
    ]


def geographiclib_origin_y(profile) -> float:
    completed = subprocess.run(
        geographiclib_base_command(profile),
        input=f"{profile.lat0:.17g} {profile.lon0:.17g}\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    fields = completed.stdout.strip().split()

    if len(fields) < 4:
        raise RuntimeError(
            f"{profile.name}: bad GeographicLib origin output "
            f"{completed.stdout!r}"
        )

    return float(fields[1])


def geographiclib_reverse(
    profile,
    rows: list[ProbeRow],
) -> list[OracleRow]:
    origin_y = geographiclib_origin_y(profile)

    input_text = "".join(
        (
            f"{row.easting - profile.false_e:.17g} "
            f"{row.northing - profile.false_n + origin_y:.17g}\n"
        )
        for row in rows
    )

    command = [
        GEOGRAPHICLIB_EXE,
        "-r",
        "-l",
        repr(profile.lon0),
        "-k",
        repr(profile.k0),
        "-e",
        repr(profile.a),
        repr(profile.f),
        "-p",
        "15",
    ]

    completed = subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    lines = [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip()
    ]

    if len(lines) != len(rows):
        raise RuntimeError(
            f"{profile.name}: GeographicLib returned {len(lines)} "
            f"lines for {len(rows)} rows"
        )

    result: list[OracleRow] = []

    for line in lines:
        fields = line.split()

        if len(fields) < 4:
            raise RuntimeError(
                f"{profile.name}: bad GeographicLib reverse output "
                f"{line!r}"
            )

        result.append(
            OracleRow(
                latitude=float(fields[0]),
                longitude=float(fields[1]),
                gamma=float(fields[2]),
                scale=float(fields[3]),
            )
        )

    return result


def sphere_reverse(
    profile,
    rows: list[ProbeRow],
) -> list[OracleRow]:
    natural_scale = profile.a * profile.k0
    origin_xi = math.radians(profile.lat0)

    result: list[OracleRow] = []

    for row in rows:
        eta = (
            row.easting - profile.false_e
        ) / natural_scale

        xi = (
            (row.northing - profile.false_n)
            / natural_scale
            + origin_xi
        )

        sinh_eta = math.sinh(eta)
        cosh_eta = math.cosh(eta)

        sin_latitude = math.sin(xi) / cosh_eta
        sin_latitude = max(
            -1.0,
            min(1.0, sin_latitude),
        )

        latitude = math.asin(sin_latitude)
        delta_longitude = math.atan2(
            sinh_eta,
            math.cos(xi),
        )

        longitude = math.radians(profile.lon0) + delta_longitude
        longitude = math.remainder(
            longitude,
            2.0 * math.pi,
        )

        gamma = math.atan2(
            math.sin(delta_longitude) * math.sin(latitude),
            math.cos(delta_longitude),
        )

        q = (
            math.cos(latitude)
            * math.sin(delta_longitude)
        )

        scale = profile.k0 / math.sqrt(
            1.0 - q * q
        )

        result.append(
            OracleRow(
                latitude=math.degrees(latitude),
                longitude=math.degrees(longitude),
                gamma=math.degrees(gamma),
                scale=scale,
            )
        )

    return result


def oracle_reverse(
    profile,
    rows: list[ProbeRow],
) -> list[OracleRow]:
    if profile.f == 0.0:
        return sphere_reverse(profile, rows)

    return geographiclib_reverse(profile, rows)


def relative_error(actual: float, reference: float) -> float:
    if reference == 0.0:
        return abs(actual - reference)

    return abs(actual - reference) / abs(reference)


def max_with_label(
    profile,
    cases: list[Case],
    values: list[float],
) -> tuple[float, str]:
    index = max(
        range(len(values)),
        key=values.__getitem__,
    )

    return values[index], label(profile, cases[index])


def print_metric(
    title: str,
    metric: tuple[float, str],
    suffix: str = "",
) -> None:
    value, where = metric
    print(f"  {title}: {value:.17g}{suffix}")
    print(f"    at: {where}")


def validate_profile(
    profile,
    cases: list[Case],
    rows: list[ProbeRow],
    oracle: list[OracleRow],
):
    b_gamma = []
    b_scale_abs = []
    b_scale_rel = []

    a_gamma = []
    a_scale_abs = []
    a_scale_rel = []

    ab_gamma = []
    ab_scale_abs = []
    ab_scale_rel = []

    reverse_latitude = []
    reverse_longitude = []

    for row, reference in zip(rows, oracle):
        b_gamma.append(
            common.normalized_angle_error_deg(
                row.gamma_b,
                reference.gamma,
            )
        )
        b_scale_abs.append(
            abs(row.scale_b - reference.scale)
        )
        b_scale_rel.append(
            relative_error(
                row.scale_b,
                reference.scale,
            )
        )

        a_gamma.append(
            common.normalized_angle_error_deg(
                row.gamma_a,
                reference.gamma,
            )
        )
        a_scale_abs.append(
            abs(row.scale_a - reference.scale)
        )
        a_scale_rel.append(
            relative_error(
                row.scale_a,
                reference.scale,
            )
        )

        ab_gamma.append(
            common.normalized_angle_error_deg(
                row.gamma_a,
                row.gamma_b,
            )
        )
        ab_scale_abs.append(
            abs(row.scale_a - row.scale_b)
        )
        ab_scale_rel.append(
            relative_error(
                row.scale_a,
                row.scale_b,
            )
        )

        reverse_latitude.append(
            abs(
                row.reverse_latitude
                - reference.latitude
            )
        )
        reverse_longitude.append(
            common.normalized_angle_error_deg(
                row.reverse_longitude,
                reference.longitude,
            )
        )

    metrics = {
        "b_gamma": max_with_label(
            profile, cases, b_gamma),
        "b_scale_abs": max_with_label(
            profile, cases, b_scale_abs),
        "b_scale_rel": max_with_label(
            profile, cases, b_scale_rel),

        "a_gamma": max_with_label(
            profile, cases, a_gamma),
        "a_scale_abs": max_with_label(
            profile, cases, a_scale_abs),
        "a_scale_rel": max_with_label(
            profile, cases, a_scale_rel),

        "ab_gamma": max_with_label(
            profile, cases, ab_gamma),
        "ab_scale_abs": max_with_label(
            profile, cases, ab_scale_abs),
        "ab_scale_rel": max_with_label(
            profile, cases, ab_scale_rel),

        "reverse_latitude": max_with_label(
            profile, cases, reverse_latitude),
        "reverse_longitude": max_with_label(
            profile, cases, reverse_longitude),
    }

    print()
    print(profile.name)
    print(f"  cases: {len(cases)}")

    print("  B: post-policy working point vs oracle")
    print_metric(
        "max |delta gamma|",
        metrics["b_gamma"],
        " deg",
    )
    print_metric(
        "max |delta k|",
        metrics["b_scale_abs"],
    )
    print_metric(
        "max relative delta k",
        metrics["b_scale_rel"],
    )

    print("  A: public reverse -> forward factors vs oracle")
    print_metric(
        "max |delta gamma|",
        metrics["a_gamma"],
        " deg",
    )
    print_metric(
        "max |delta k|",
        metrics["a_scale_abs"],
    )
    print_metric(
        "max relative delta k",
        metrics["a_scale_rel"],
    )

    print("  A vs B")
    print_metric(
        "max |delta gamma|",
        metrics["ab_gamma"],
        " deg",
    )
    print_metric(
        "max |delta k|",
        metrics["ab_scale_abs"],
    )
    print_metric(
        "max relative delta k",
        metrics["ab_scale_rel"],
    )

    print("  public reverse position vs oracle")
    print_metric(
        "max |delta latitude|",
        metrics["reverse_latitude"],
        " deg",
    )
    print_metric(
        "max |delta longitude|",
        metrics["reverse_longitude"],
        " deg",
    )

    return metrics


def update_global(
    global_metrics,
    metrics,
):
    for key, candidate in metrics.items():
        current = global_metrics.get(key)

        if current is None or candidate[0] > current[0]:
            global_metrics[key] = candidate


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"usage: {sys.argv[0]} REVERSE_PROBE_BINARY",
            file=sys.stderr,
        )
        return 2

    binary = sys.argv[1]

    rng = random.Random(common.RANDOM_SEED)
    global_metrics = {}
    total_cases = 0

    print("=== PRIVATE D REVERSE FACTOR PROTOTYPE ===")
    print(
        f"random seed={common.RANDOM_SEED:#x} "
        f"random/profile={common.RANDOM_CASES_PER_PROFILE}"
    )

    for profile in common.PROFILES:
        cases = build_cases(profile, rng)
        rows = run_probe(binary, profile, cases)
        oracle = oracle_reverse(profile, rows)

        metrics = validate_profile(
            profile,
            cases,
            rows,
            oracle,
        )

        update_global(
            global_metrics,
            metrics,
        )

        total_cases += len(cases)

    print()
    print("=== GLOBAL METRICS ===")
    print(f"cases={total_cases}")

    print_metric(
        "B max |delta gamma|",
        global_metrics["b_gamma"],
        " deg",
    )
    print_metric(
        "B max |delta k|",
        global_metrics["b_scale_abs"],
    )
    print_metric(
        "B max relative delta k",
        global_metrics["b_scale_rel"],
    )

    print_metric(
        "A max |delta gamma|",
        global_metrics["a_gamma"],
        " deg",
    )
    print_metric(
        "A max relative delta k",
        global_metrics["a_scale_rel"],
    )

    print_metric(
        "A/B max |delta gamma|",
        global_metrics["ab_gamma"],
        " deg",
    )
    print_metric(
        "A/B max relative delta k",
        global_metrics["ab_scale_rel"],
    )

    if (
        global_metrics["b_gamma"][0] > SANITY_GAMMA_DEG
        or global_metrics["b_scale_rel"][0]
        > SANITY_RELATIVE_SCALE
    ):
        print()
        print(
            "FAIL: reverse candidate B exceeds loose "
            "research sanity bounds"
        )
        return 1

    print()
    print(
        "PASS: reverse candidate B agrees with the "
        "independent oracle within loose research sanity bounds"
    )
    print(
        "NOTE: these bounds are not projection-factor "
        "acceptance tolerances"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
