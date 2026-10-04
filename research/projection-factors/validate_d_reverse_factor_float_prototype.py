#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import random
import struct
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_d_factor_prototype as common
import validate_d_reverse_factor_prototype as reverse_common


@dataclass(frozen=True)
class FloatProfileInput:
    name: str
    a: float
    f: float
    lat0: float
    lon0: float
    k0: float
    false_e: float
    false_n: float


@dataclass(frozen=True)
class RepresentedProfile:
    name: str
    a: float
    f: float

    # Degree forms used by the GeographicLib CLI.
    lat0: float
    lon0: float

    k0: float
    false_e: float
    false_n: float

    # Actual Latitude!float / Longitude!float stored radians.
    lat0_rad: float
    lon0_rad: float


@dataclass(frozen=True)
class FloatProbeRow:
    easting: float
    northing: float

    # Degree values derived in Python/double from represented float radians.
    reverse_latitude: float
    reverse_longitude: float
    gamma_b: float
    scale_b: float
    gamma_a: float
    scale_a: float

    # Raw represented float values for bit/ULP comparison.
    gamma_b_rad_raw: float
    gamma_a_rad_raw: float


def f32(value: float) -> float:
    return struct.unpack(
        ">f",
        struct.pack(">f", float(value)),
    )[0]


def f32_bits(value: float) -> int:
    return struct.unpack(
        ">I",
        struct.pack(">f", f32(value)),
    )[0]


def ordered_f32(value: float) -> int:
    bits = f32_bits(value)

    if bits & 0x80000000:
        return 0x80000000 - (bits & 0x7FFFFFFF)

    return 0x80000000 + bits


def ulp_distance_f32(left: float, right: float) -> int:
    if left == right:
        return 0

    return abs(
        ordered_f32(left)
        - ordered_f32(right)
    )


def quantize_profile(profile) -> FloatProfileInput:
    return FloatProfileInput(
        name=profile.name,
        a=f32(profile.a),
        f=f32(profile.f),
        lat0=f32(profile.lat0),
        lon0=f32(profile.lon0),
        k0=f32(profile.k0),
        false_e=f32(profile.false_e),
        false_n=f32(profile.false_n),
    )


def build_cases(
    profile: FloatProfileInput,
    rng: random.Random,
) -> list[reverse_common.Case]:
    points: list[tuple[float, float]] = []

    for latitude in common.STRUCTURED_LATITUDES:
        for delta_longitude in common.STRUCTURED_DLONGITUDES:
            points.append(
                (
                    f32(latitude),
                    f32(profile.lon0 + delta_longitude),
                )
            )

    for _ in range(common.RANDOM_CASES_PER_PROFILE):
        latitude = rng.uniform(-85.0, 85.0)
        delta_longitude = rng.uniform(-60.0, 60.0)

        points.append(
            (
                f32(latitude),
                f32(profile.lon0 + delta_longitude),
            )
        )

    return [
        reverse_common.Case(
            index,
            latitude,
            longitude,
        )
        for index, (latitude, longitude)
        in enumerate(points)
    ]


def probe_command(
    binary: str,
    profile: FloatProfileInput,
) -> list[str]:
    return [
        binary,
        format(profile.a, ".17g"),
        format(profile.f, ".17g"),
        format(profile.lat0, ".17g"),
        format(profile.lon0, ".17g"),
        format(profile.k0, ".17g"),
        format(profile.false_e, ".17g"),
        format(profile.false_n, ".17g"),
    ]


def parse_profile_header(
    name: str,
    line: str,
) -> RepresentedProfile:
    fields = line.split()

    if len(fields) != 8 or fields[0] != "PROFILE":
        raise RuntimeError(
            f"{name}: bad probe PROFILE line {line!r}"
        )

    values = [
        float(value)
        for value in fields[1:]
    ]

    (
        a,
        flattening,
        lat0_rad,
        lon0_rad,
        k0,
        false_e,
        false_n,
    ) = values

    return RepresentedProfile(
        name=name,
        a=a,
        f=flattening,
        lat0=math.degrees(lat0_rad),
        lon0=math.degrees(lon0_rad),
        k0=k0,
        false_e=false_e,
        false_n=false_n,
        lat0_rad=lat0_rad,
        lon0_rad=lon0_rad,
    )


def verify_scalar_profile_roundtrip(
    requested: FloatProfileInput,
    represented: RepresentedProfile,
) -> None:
    checks = (
        ("a", requested.a, represented.a),
        ("f", requested.f, represented.f),
        ("k0", requested.k0, represented.k0),
        ("false_e", requested.false_e, represented.false_e),
        ("false_n", requested.false_n, represented.false_n),
    )

    for name, expected, actual in checks:
        if f32(expected) != f32(actual):
            raise RuntimeError(
                f"{requested.name}: represented {name} mismatch: "
                f"requested={expected:.17g} "
                f"actual={actual:.17g}"
            )


def run_probe(
    binary: str,
    profile: FloatProfileInput,
    cases: list[reverse_common.Case],
) -> tuple[RepresentedProfile, list[FloatProbeRow]]:
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

    if not lines:
        raise RuntimeError(
            f"{profile.name}: probe returned no output\n"
            f"stderr:\n{completed.stderr}"
        )

    represented = parse_profile_header(
        profile.name,
        lines[0],
    )

    verify_scalar_profile_roundtrip(
        profile,
        represented,
    )

    result_lines = lines[1:]

    if len(result_lines) != len(cases):
        raise RuntimeError(
            f"{profile.name}: probe returned "
            f"{len(result_lines)} case lines "
            f"for {len(cases)} cases\n"
            f"stderr:\n{completed.stderr}"
        )

    rows: list[FloatProbeRow] = []

    for case, line in zip(cases, result_lines):
        fields = line.split()

        if not fields or fields[0] != "OK":
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                f"probe result {line!r}"
            )

        if len(fields) != 9:
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                f"expected 9 output fields, "
                f"got {len(fields)}"
            )

        values = [
            float(value)
            for value in fields[1:]
        ]

        (
            easting,
            northing,
            reverse_lat_rad,
            reverse_lon_rad,
            gamma_b_rad,
            scale_b,
            gamma_a_rad,
            scale_a,
        ) = values

        rows.append(
            FloatProbeRow(
                easting=easting,
                northing=northing,
                reverse_latitude=math.degrees(
                    reverse_lat_rad),
                reverse_longitude=math.degrees(
                    reverse_lon_rad),
                gamma_b=math.degrees(
                    gamma_b_rad),
                scale_b=scale_b,
                gamma_a=math.degrees(
                    gamma_a_rad),
                scale_a=scale_a,
                gamma_b_rad_raw=gamma_b_rad,
                gamma_a_rad_raw=gamma_a_rad,
            )
        )

    return represented, rows


def print_profile_representation(
    requested: FloatProfileInput,
    represented: RepresentedProfile,
) -> None:
    print("  represented float profile:")
    print(
        f"    a={represented.a:.17g} "
        f"f={represented.f:.17g}"
    )
    print(
        f"    lat0 input={requested.lat0:.17g} deg "
        f"stored={represented.lat0_rad:.17g} rad "
        f"({represented.lat0:.17g} deg)"
    )
    print(
        f"    lon0 input={requested.lon0:.17g} deg "
        f"stored={represented.lon0_rad:.17g} rad "
        f"({represented.lon0:.17g} deg)"
    )
    print(
        f"    k0={represented.k0:.17g} "
        f"FE={represented.false_e:.17g} "
        f"FN={represented.false_n:.17g}"
    )


def max_int_with_label(
    profile,
    cases,
    values: list[int],
) -> tuple[int, str]:
    index = max(
        range(len(values)),
        key=values.__getitem__,
    )

    return (
        values[index],
        reverse_common.label(
            profile,
            cases[index],
        ),
    )



def oracle_ab_comparison_stats(
    rows: list[FloatProbeRow],
    oracle,
):
    gamma_b_better = 0
    gamma_a_better = 0
    gamma_tie = 0

    scale_b_better = 0
    scale_a_better = 0
    scale_tie = 0

    gamma_b_sum = 0.0
    gamma_a_sum = 0.0
    scale_b_rel_sum = 0.0
    scale_a_rel_sum = 0.0

    for row, reference in zip(rows, oracle):
        b_gamma_error = common.normalized_angle_error_deg(
            row.gamma_b,
            reference.gamma,
        )
        a_gamma_error = common.normalized_angle_error_deg(
            row.gamma_a,
            reference.gamma,
        )

        b_scale_rel = reverse_common.relative_error(
            row.scale_b,
            reference.scale,
        )
        a_scale_rel = reverse_common.relative_error(
            row.scale_a,
            reference.scale,
        )

        gamma_b_sum += b_gamma_error
        gamma_a_sum += a_gamma_error
        scale_b_rel_sum += b_scale_rel
        scale_a_rel_sum += a_scale_rel

        if b_gamma_error < a_gamma_error:
            gamma_b_better += 1
        elif a_gamma_error < b_gamma_error:
            gamma_a_better += 1
        else:
            gamma_tie += 1

        if b_scale_rel < a_scale_rel:
            scale_b_better += 1
        elif a_scale_rel < b_scale_rel:
            scale_a_better += 1
        else:
            scale_tie += 1

    count = len(rows)

    return {
        "gamma_b_better": gamma_b_better,
        "gamma_a_better": gamma_a_better,
        "gamma_tie": gamma_tie,
        "scale_b_better": scale_b_better,
        "scale_a_better": scale_a_better,
        "scale_tie": scale_tie,
        "gamma_b_mean": gamma_b_sum / count,
        "gamma_a_mean": gamma_a_sum / count,
        "scale_b_rel_mean": scale_b_rel_sum / count,
        "scale_a_rel_mean": scale_a_rel_sum / count,
    }



def candidate_ab_float_stats(
    profile,
    cases,
    rows: list[FloatProbeRow],
):
    gamma_ulps = [
        ulp_distance_f32(
            row.gamma_a_rad_raw,
            row.gamma_b_rad_raw,
        )
        for row in rows
    ]

    scale_ulps = [
        ulp_distance_f32(
            row.scale_a,
            row.scale_b,
        )
        for row in rows
    ]

    gamma_different = sum(
        f32_bits(row.gamma_a_rad_raw)
        != f32_bits(row.gamma_b_rad_raw)
        for row in rows
    )

    scale_different = sum(
        f32_bits(row.scale_a)
        != f32_bits(row.scale_b)
        for row in rows
    )

    return {
        "gamma_different": gamma_different,
        "scale_different": scale_different,
        "gamma_ulp": max_int_with_label(
            profile,
            cases,
            gamma_ulps,
        ),
        "scale_ulp": max_int_with_label(
            profile,
            cases,
            scale_ulps,
        ),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"usage: {sys.argv[0]} FLOAT_REVERSE_PROBE_BINARY",
            file=sys.stderr,
        )
        return 2

    binary = sys.argv[1]

    rng = random.Random(
        common.RANDOM_SEED
    )

    global_metrics = {}
    total_cases = 0

    global_gamma_different = 0
    global_scale_different = 0

    global_gamma_b_better = 0
    global_gamma_a_better = 0
    global_gamma_tie = 0

    global_scale_b_better = 0
    global_scale_a_better = 0
    global_scale_tie = 0

    global_gamma_b_error_sum = 0.0
    global_gamma_a_error_sum = 0.0
    global_scale_b_rel_sum = 0.0
    global_scale_a_rel_sum = 0.0

    global_gamma_ulp: tuple[int, str] | None = None
    global_scale_ulp: tuple[int, str] | None = None

    print("=== PRIVATE D REVERSE FACTOR FLOAT PROTOTYPE ===")
    print(
        f"random seed={common.RANDOM_SEED:#x} "
        f"random/profile={common.RANDOM_CASES_PER_PROFILE}"
    )
    print(
        "public scalar=float; "
        "oracle uses represented float profile and represented float E/N"
    )

    for original_profile in common.PROFILES:
        requested_profile = quantize_profile(
            original_profile
        )

        cases = build_cases(
            requested_profile,
            rng,
        )

        represented_profile, rows = run_probe(
            binary,
            requested_profile,
            cases,
        )

        print()
        print_profile_representation(
            requested_profile,
            represented_profile,
        )

        oracle = reverse_common.oracle_reverse(
            represented_profile,
            rows,
        )

        metrics = reverse_common.validate_profile(
            represented_profile,
            cases,
            rows,
            oracle,
        )

        reverse_common.update_global(
            global_metrics,
            metrics,
        )

        ab_stats = candidate_ab_float_stats(
            represented_profile,
            cases,
            rows,
        )

        oracle_stats = oracle_ab_comparison_stats(
            rows,
            oracle,
        )

        print("  A/B oracle comparison")
        print(
            "    gamma B-better/A-better/tie: "
            f"{oracle_stats['gamma_b_better']}/"
            f"{oracle_stats['gamma_a_better']}/"
            f"{oracle_stats['gamma_tie']}"
        )
        print(
            "    scale B-better/A-better/tie: "
            f"{oracle_stats['scale_b_better']}/"
            f"{oracle_stats['scale_a_better']}/"
            f"{oracle_stats['scale_tie']}"
        )
        print(
            "    mean |delta gamma| B/A: "
            f"{oracle_stats['gamma_b_mean']:.17g} / "
            f"{oracle_stats['gamma_a_mean']:.17g} deg"
        )
        print(
            "    mean relative |delta k| B/A: "
            f"{oracle_stats['scale_b_rel_mean']:.17g} / "
            f"{oracle_stats['scale_a_rel_mean']:.17g}"
        )

        print("  A/B binary32 result comparison")
        print(
            "    gamma bitwise-different cases: "
            f"{ab_stats['gamma_different']}/{len(rows)}"
        )
        print(
            "    scale bitwise-different cases: "
            f"{ab_stats['scale_different']}/{len(rows)}"
        )

        gamma_ulp, gamma_where = (
            ab_stats["gamma_ulp"]
        )
        scale_ulp, scale_where = (
            ab_stats["scale_ulp"]
        )

        print(
            f"    max gamma float ULP distance: {gamma_ulp}"
        )
        print(
            f"      at: {gamma_where}"
        )
        print(
            f"    max scale float ULP distance: {scale_ulp}"
        )
        print(
            f"      at: {scale_where}"
        )

        global_gamma_different += (
            ab_stats["gamma_different"]
        )
        global_scale_different += (
            ab_stats["scale_different"]
        )

        global_gamma_b_better += (
            oracle_stats["gamma_b_better"]
        )
        global_gamma_a_better += (
            oracle_stats["gamma_a_better"]
        )
        global_gamma_tie += (
            oracle_stats["gamma_tie"]
        )

        global_scale_b_better += (
            oracle_stats["scale_b_better"]
        )
        global_scale_a_better += (
            oracle_stats["scale_a_better"]
        )
        global_scale_tie += (
            oracle_stats["scale_tie"]
        )

        global_gamma_b_error_sum += (
            oracle_stats["gamma_b_mean"] * len(rows)
        )
        global_gamma_a_error_sum += (
            oracle_stats["gamma_a_mean"] * len(rows)
        )
        global_scale_b_rel_sum += (
            oracle_stats["scale_b_rel_mean"] * len(rows)
        )
        global_scale_a_rel_sum += (
            oracle_stats["scale_a_rel_mean"] * len(rows)
        )

        if (
            global_gamma_ulp is None
            or gamma_ulp > global_gamma_ulp[0]
        ):
            global_gamma_ulp = (
                gamma_ulp,
                gamma_where,
            )

        if (
            global_scale_ulp is None
            or scale_ulp > global_scale_ulp[0]
        ):
            global_scale_ulp = (
                scale_ulp,
                scale_where,
            )

        total_cases += len(cases)

    assert global_gamma_ulp is not None
    assert global_scale_ulp is not None

    print()
    print("=== GLOBAL FLOAT METRICS ===")
    print(f"cases={total_cases}")

    reverse_common.print_metric(
        "B max |delta gamma|",
        global_metrics["b_gamma"],
        " deg",
    )
    reverse_common.print_metric(
        "B max |delta k|",
        global_metrics["b_scale_abs"],
    )
    reverse_common.print_metric(
        "B max relative delta k",
        global_metrics["b_scale_rel"],
    )

    reverse_common.print_metric(
        "A max |delta gamma|",
        global_metrics["a_gamma"],
        " deg",
    )
    reverse_common.print_metric(
        "A max |delta k|",
        global_metrics["a_scale_abs"],
    )
    reverse_common.print_metric(
        "A max relative delta k",
        global_metrics["a_scale_rel"],
    )

    reverse_common.print_metric(
        "A/B max |delta gamma|",
        global_metrics["ab_gamma"],
        " deg",
    )
    reverse_common.print_metric(
        "A/B max |delta k|",
        global_metrics["ab_scale_abs"],
    )
    reverse_common.print_metric(
        "A/B max relative delta k",
        global_metrics["ab_scale_rel"],
    )

    reverse_common.print_metric(
        "public reverse max |delta latitude|",
        global_metrics["reverse_latitude"],
        " deg",
    )
    reverse_common.print_metric(
        "public reverse max |delta longitude|",
        global_metrics["reverse_longitude"],
        " deg",
    )

    print(
        "Oracle gamma B-better/A-better/tie: "
        f"{global_gamma_b_better}/"
        f"{global_gamma_a_better}/"
        f"{global_gamma_tie}"
    )
    print(
        "Oracle scale B-better/A-better/tie: "
        f"{global_scale_b_better}/"
        f"{global_scale_a_better}/"
        f"{global_scale_tie}"
    )
    print(
        "Mean |delta gamma| B/A: "
        f"{global_gamma_b_error_sum / total_cases:.17g} / "
        f"{global_gamma_a_error_sum / total_cases:.17g} deg"
    )
    print(
        "Mean relative |delta k| B/A: "
        f"{global_scale_b_rel_sum / total_cases:.17g} / "
        f"{global_scale_a_rel_sum / total_cases:.17g}"
    )

    print(
        "A/B gamma bitwise-different cases: "
        f"{global_gamma_different}/{total_cases}"
    )
    print(
        "A/B scale bitwise-different cases: "
        f"{global_scale_different}/{total_cases}"
    )
    print(
        "A/B max gamma float ULP distance: "
        f"{global_gamma_ulp[0]}"
    )
    print(
        f"  at: {global_gamma_ulp[1]}"
    )
    print(
        "A/B max scale float ULP distance: "
        f"{global_scale_ulp[0]}"
    )
    print(
        f"  at: {global_scale_ulp[1]}"
    )

    if (
        global_metrics["b_gamma"][0]
        > reverse_common.SANITY_GAMMA_DEG
        or global_metrics["b_scale_rel"][0]
        > reverse_common.SANITY_RELATIVE_SCALE
    ):
        print()
        print(
            "FAIL: float reverse candidate B exceeds "
            "loose research sanity bounds"
        )
        return 1

    print()
    print(
        "PASS: float reverse candidate B agrees with the "
        "independent oracle within loose research sanity bounds"
    )
    print(
        "NOTE: these bounds are characterization guards, "
        "not production acceptance tolerances"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
