#!/usr/bin/env python3

from __future__ import annotations

import math
from pathlib import Path
import random
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_d_factor_prototype as common
import validate_d_reverse_factor_prototype as reverse_common
import validate_d_reverse_factor_float_prototype as float_common


# Keep FLOAT-R2 away from the nominal +/-60-degree sheet boundary.
# Boundary representation/policy is reserved for FLOAT-R3.
R2_RANDOM_MAX_DLONGITUDE = 59.0

R2_STRUCTURED_DLONGITUDES = tuple(
    value
    for value in common.STRUCTURED_DLONGITUDES
    if abs(value) < 60.0
)


def get_represented_profile(
    binary: str,
    requested: float_common.FloatProfileInput,
) -> float_common.RepresentedProfile:
    completed = subprocess.run(
        float_common.probe_command(
            binary,
            requested,
        ),
        input="",
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

    if len(lines) != 1:
        raise RuntimeError(
            f"{requested.name}: expected one PROFILE line, "
            f"got {len(lines)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )

    represented = float_common.parse_profile_header(
        requested.name,
        lines[0],
    )

    float_common.verify_scalar_profile_roundtrip(
        requested,
        represented,
    )

    return represented


def build_source_cases(
    profile: float_common.RepresentedProfile,
    rng: random.Random,
) -> list[reverse_common.Case]:
    points: list[tuple[float, float]] = []

    for latitude in common.STRUCTURED_LATITUDES:
        for delta_longitude in R2_STRUCTURED_DLONGITUDES:
            points.append(
                (
                    latitude,
                    profile.lon0 + delta_longitude,
                )
            )

    for _ in range(common.RANDOM_CASES_PER_PROFILE):
        latitude = rng.uniform(-85.0, 85.0)
        delta_longitude = rng.uniform(
            -R2_RANDOM_MAX_DLONGITUDE,
            R2_RANDOM_MAX_DLONGITUDE,
        )

        points.append(
            (
                latitude,
                profile.lon0 + delta_longitude,
            )
        )

    return [
        reverse_common.Case(
            index=index,
            latitude=latitude,
            longitude=longitude,
        )
        for index, (latitude, longitude)
        in enumerate(points)
    ]


def geographiclib_forward_projected(
    profile: float_common.RepresentedProfile,
    cases: list[reverse_common.Case],
) -> list[tuple[float, float]]:
    origin_y = reverse_common.geographiclib_origin_y(
        profile
    )

    input_text = "".join(
        f"{case.latitude:.17g} {case.longitude:.17g}\n"
        for case in cases
    )

    completed = subprocess.run(
        reverse_common.geographiclib_base_command(
            profile
        ),
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
            f"{profile.name}: GeographicLib forward returned "
            f"{len(lines)} rows for {len(cases)} cases"
        )

    result: list[tuple[float, float]] = []

    for case, line in zip(cases, lines):
        fields = line.split()

        if len(fields) < 4:
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                f"bad GeographicLib forward row {line!r}"
            )

        x = float(fields[0])
        y = float(fields[1])

        easting = float_common.f32(
            x + profile.false_e
        )

        northing = float_common.f32(
            y - origin_y + profile.false_n
        )

        if (
            not math.isfinite(easting)
            or not math.isfinite(northing)
        ):
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                "non-finite represented projected coordinate"
            )

        result.append(
            (easting, northing)
        )

    return result


def spherical_forward_projected(
    profile: float_common.RepresentedProfile,
    cases: list[reverse_common.Case],
) -> list[tuple[float, float]]:
    natural_scale = profile.a * profile.k0

    result: list[tuple[float, float]] = []

    for case in cases:
        latitude = math.radians(
            case.latitude
        )

        delta_longitude_deg = (
            common.normalized_longitude_difference_deg(
                case.longitude,
                profile.lon0,
            )
        )

        delta_longitude = math.radians(
            delta_longitude_deg
        )

        sin_phi = math.sin(latitude)
        cos_phi = math.cos(latitude)
        sin_lambda = math.sin(delta_longitude)
        cos_lambda = math.cos(delta_longitude)

        q = cos_phi * sin_lambda

        if not (
            math.isfinite(q)
            and abs(q) < 1.0
        ):
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                f"invalid spherical forward q={q!r}"
            )

        eta = math.atanh(q)

        xi = math.atan2(
            sin_phi,
            cos_phi * cos_lambda,
        )

        easting = float_common.f32(
            profile.false_e
            + natural_scale * eta
        )

        northing = float_common.f32(
            profile.false_n
            + natural_scale
            * (xi - profile.lat0_rad)
        )

        if (
            not math.isfinite(easting)
            or not math.isfinite(northing)
        ):
            raise RuntimeError(
                f"{reverse_common.label(profile, case)}: "
                "non-finite spherical projected coordinate"
            )

        result.append(
            (easting, northing)
        )

    return result


def independent_forward_projected(
    profile: float_common.RepresentedProfile,
    cases: list[reverse_common.Case],
) -> list[tuple[float, float]]:
    if profile.f == 0.0:
        return spherical_forward_projected(
            profile,
            cases,
        )

    return geographiclib_forward_projected(
        profile,
        cases,
    )


def run_projected_probe(
    binary: str,
    requested: float_common.FloatProfileInput,
    represented: float_common.RepresentedProfile,
    cases: list[reverse_common.Case],
    projected: list[tuple[float, float]],
) -> list[float_common.FloatProbeRow]:
    input_text = "".join(
        f"{easting:.17g} {northing:.17g}\n"
        for easting, northing in projected
    )

    completed = subprocess.run(
        float_common.probe_command(
            binary,
            requested,
        ),
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
            f"{represented.name}: projected probe returned no output"
        )

    echoed_profile = float_common.parse_profile_header(
        represented.name,
        lines[0],
    )

    if echoed_profile != represented:
        raise RuntimeError(
            f"{represented.name}: represented profile changed "
            "between profile handshake and projected run"
        )

    result_lines = lines[1:]

    if len(result_lines) != len(cases):
        raise RuntimeError(
            f"{represented.name}: projected probe returned "
            f"{len(result_lines)} rows for {len(cases)} cases"
        )

    rows: list[float_common.FloatProbeRow] = []

    for (
        case,
        expected_projected,
        line,
    ) in zip(cases, projected, result_lines):
        fields = line.split()

        if not fields or fields[0] != "OK":
            raise RuntimeError(
                f"{reverse_common.label(represented, case)}: "
                f"probe result {line!r}"
            )

        if len(fields) != 9:
            raise RuntimeError(
                f"{reverse_common.label(represented, case)}: "
                f"expected 9 fields, got {len(fields)}"
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

        expected_easting, expected_northing = (
            expected_projected
        )

        if (
            float_common.f32_bits(easting)
            != float_common.f32_bits(expected_easting)
            or float_common.f32_bits(northing)
            != float_common.f32_bits(expected_northing)
        ):
            raise RuntimeError(
                f"{reverse_common.label(represented, case)}: "
                "D probe did not preserve represented float E/N"
            )

        rows.append(
            float_common.FloatProbeRow(
                easting=easting,
                northing=northing,
                reverse_latitude=math.degrees(
                    reverse_lat_rad
                ),
                reverse_longitude=math.degrees(
                    reverse_lon_rad
                ),
                gamma_b=math.degrees(
                    gamma_b_rad
                ),
                scale_b=scale_b,
                gamma_a=math.degrees(
                    gamma_a_rad
                ),
                scale_a=scale_a,
                gamma_b_rad_raw=gamma_b_rad,
                gamma_a_rad_raw=gamma_a_rad,
            )
        )

    return rows


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"usage: {sys.argv[0]} FLOAT_PROJECTED_PROBE_BINARY",
            file=sys.stderr,
        )
        return 2

    binary = sys.argv[1]

    rng = random.Random(
        common.RANDOM_SEED ^ 0x5232
    )

    global_metrics = {}

    total_cases = 0

    gamma_b_better = 0
    gamma_a_better = 0
    gamma_tie = 0

    scale_b_better = 0
    scale_a_better = 0
    scale_tie = 0

    gamma_b_error_sum = 0.0
    gamma_a_error_sum = 0.0
    scale_b_rel_sum = 0.0
    scale_a_rel_sum = 0.0

    gamma_different = 0
    scale_different = 0

    max_gamma_ulp: tuple[int, str] | None = None
    max_scale_ulp: tuple[int, str] | None = None

    print(
        "=== PRIVATE D REVERSE FACTOR FLOAT PROJECTED PROTOTYPE ==="
    )
    print(
        f"random seed={(common.RANDOM_SEED ^ 0x5232):#x} "
        f"random/profile={common.RANDOM_CASES_PER_PROFILE}"
    )
    print(
        "E/N source=independent GeographicLib Exact "
        "or analytic sphere; represented as binary32"
    )
    print(
        "interior gate: structured +/-60 deg excluded; "
        "random |delta longitude| <= 59 deg"
    )

    for original_profile in common.PROFILES:
        requested = float_common.quantize_profile(
            original_profile
        )

        represented = get_represented_profile(
            binary,
            requested,
        )

        cases = build_source_cases(
            represented,
            rng,
        )

        projected = independent_forward_projected(
            represented,
            cases,
        )

        rows = run_projected_probe(
            binary,
            requested,
            represented,
            cases,
            projected,
        )

        oracle = reverse_common.oracle_reverse(
            represented,
            rows,
        )

        print()
        float_common.print_profile_representation(
            requested,
            represented,
        )

        metrics = reverse_common.validate_profile(
            represented,
            cases,
            rows,
            oracle,
        )

        reverse_common.update_global(
            global_metrics,
            metrics,
        )

        oracle_stats = (
            float_common.oracle_ab_comparison_stats(
                rows,
                oracle,
            )
        )

        ab_stats = float_common.candidate_ab_float_stats(
            represented,
            cases,
            rows,
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
        print(
            "    max gamma float ULP distance: "
            f"{ab_stats['gamma_ulp'][0]}"
        )
        print(
            f"      at: {ab_stats['gamma_ulp'][1]}"
        )
        print(
            "    max scale float ULP distance: "
            f"{ab_stats['scale_ulp'][0]}"
        )
        print(
            f"      at: {ab_stats['scale_ulp'][1]}"
        )

        count = len(rows)

        gamma_b_better += oracle_stats["gamma_b_better"]
        gamma_a_better += oracle_stats["gamma_a_better"]
        gamma_tie += oracle_stats["gamma_tie"]

        scale_b_better += oracle_stats["scale_b_better"]
        scale_a_better += oracle_stats["scale_a_better"]
        scale_tie += oracle_stats["scale_tie"]

        gamma_b_error_sum += (
            oracle_stats["gamma_b_mean"] * count
        )
        gamma_a_error_sum += (
            oracle_stats["gamma_a_mean"] * count
        )
        scale_b_rel_sum += (
            oracle_stats["scale_b_rel_mean"] * count
        )
        scale_a_rel_sum += (
            oracle_stats["scale_a_rel_mean"] * count
        )

        gamma_different += ab_stats["gamma_different"]
        scale_different += ab_stats["scale_different"]

        if (
            max_gamma_ulp is None
            or ab_stats["gamma_ulp"][0] > max_gamma_ulp[0]
        ):
            max_gamma_ulp = ab_stats["gamma_ulp"]

        if (
            max_scale_ulp is None
            or ab_stats["scale_ulp"][0] > max_scale_ulp[0]
        ):
            max_scale_ulp = ab_stats["scale_ulp"]

        total_cases += count

    assert max_gamma_ulp is not None
    assert max_scale_ulp is not None

    print()
    print("=== GLOBAL FLOAT-R2 METRICS ===")
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

    print(
        "Oracle gamma B-better/A-better/tie: "
        f"{gamma_b_better}/{gamma_a_better}/{gamma_tie}"
    )
    print(
        "Oracle scale B-better/A-better/tie: "
        f"{scale_b_better}/{scale_a_better}/{scale_tie}"
    )

    print(
        "Mean |delta gamma| B/A: "
        f"{gamma_b_error_sum / total_cases:.17g} / "
        f"{gamma_a_error_sum / total_cases:.17g} deg"
    )
    print(
        "Mean relative |delta k| B/A: "
        f"{scale_b_rel_sum / total_cases:.17g} / "
        f"{scale_a_rel_sum / total_cases:.17g}"
    )

    print(
        "A/B gamma bitwise-different cases: "
        f"{gamma_different}/{total_cases}"
    )
    print(
        "A/B scale bitwise-different cases: "
        f"{scale_different}/{total_cases}"
    )

    print(
        "A/B max gamma float ULP distance: "
        f"{max_gamma_ulp[0]}"
    )
    print(
        f"  at: {max_gamma_ulp[1]}"
    )

    print(
        "A/B max scale float ULP distance: "
        f"{max_scale_ulp[0]}"
    )
    print(
        f"  at: {max_scale_ulp[1]}"
    )

    if (
        global_metrics["b_gamma"][0]
        > reverse_common.SANITY_GAMMA_DEG
        or global_metrics["b_scale_rel"][0]
        > reverse_common.SANITY_RELATIVE_SCALE
    ):
        print()
        print(
            "FAIL: FLOAT-R2 candidate B exceeds "
            "loose research sanity bounds"
        )
        return 1

    print()
    print(
        "PASS: FLOAT-R2 candidate B agrees with the "
        "independent reverse oracle within loose research sanity bounds"
    )
    print(
        "NOTE: projected inputs were independently generated; "
        "no geodesy-d forward operation participated"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
