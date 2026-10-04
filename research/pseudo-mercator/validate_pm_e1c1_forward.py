#!/usr/bin/env python3

"""
PM-E1C1A — representation-aware forward differential characterization.

Research-only.

Compares the exact PM-E1B D kernel, through its PM-E1C0 driver, against:

1. a 120-decimal-digit independent analytical oracle;
2. correctly rounded public scalar output;
3. local PROJ webmerc for compatible double cases.

This step CHARACTERIZES numerical behaviour.
It deliberately does not yet select final accuracy budgets.
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal, getcontext
from pathlib import Path

import mpmath as mp


mp.mp.dps = 120
getcontext().prec = 80


SCALAR_PRECISION = {
    "float": 24,
    "double": 53,
    "real": 64,
}


@dataclass(frozen=True)
class Profile:
    name: str
    a: str
    lon0: str
    fe: str
    fn: str
    proj_compatible: bool


@dataclass(frozen=True)
class Case:
    name: str
    latitude: str
    delta_longitude: str | None = None
    absolute_longitude: str | None = None
    proj_policy_difference: bool = False


PROFILES = [
    Profile(
        "unit_zero",
        "1",
        "0",
        "0",
        "0",
        False,
    ),
    Profile(
        "wgs84_zero",
        "6378137",
        "0",
        "0",
        "0",
        True,
    ),
    Profile(
        "offset_p170",
        "6378137",
        "170",
        "500000",
        "-2000000",
        True,
    ),
    Profile(
        "offset_m170",
        "6378137",
        "-170",
        "-250000",
        "1250000",
        True,
    ),
    Profile(
        "offset_p179_75",
        "6378137",
        "179.75",
        "500000",
        "-2000000",
        True,
    ),
    Profile(
        "offset_m179_75",
        "6378137",
        "-179.75",
        "-250000",
        "1250000",
        True,
    ),
]


CASES = [
    Case(
        "origin",
        "0",
        "0",
    ),
    Case(
        "near_zero",
        "0.000000001",
        "0.000000001",
    ),
    Case(
        "mid_north",
        "45",
        "12.5",
    ),
    Case(
        "mid_south",
        "-45",
        "-37",
    ),
    Case(
        "webmercatorquad_north",
        "85.0511287798066",
        "0",
    ),
    Case(
        "webmercatorquad_south",
        "-85.0511287798066",
        "0",
    ),
    Case(
        "north_88",
        "88",
        "37",
    ),
    Case(
        "south_88",
        "-88",
        "-37",
    ),
    Case(
        "cross_east",
        "80",
        "170",
    ),
    Case(
        "cross_west",
        "-80",
        "-170",
    ),
    Case(
        "near_east_sheet",
        "12.345",
        "179.999999",
    ),
    Case(
        "near_west_sheet",
        "-12.345",
        "-179.999999",
    ),
    Case(
        "quarter_east",
        "0",
        "90",
    ),
    Case(
        "quarter_west",
        "0",
        "-90",
    ),
]


ZERO_ONLY_CASES = [
    Case(
        "plus_180_tie",
        "0",
        absolute_longitude="180",
        proj_policy_difference=True,
    ),
    Case(
        "minus_180_tie",
        "0",
        absolute_longitude="-180",
        proj_policy_difference=False,
    ),
]


def round_binary(x: mp.mpf, precision: int) -> mp.mpf:
    """
    Correctly round finite x to a binary floating-point significand of
    `precision` bits, ties-to-even.

    The corpus is far from scalar underflow/overflow, so exponent-range
    handling is intentionally not part of this research helper.
    """

    if x == 0:
        return mp.mpf("0")

    if not mp.isfinite(x):
        return x

    sign = -1 if x < 0 else 1
    value = abs(x)

    mantissa, exponent = mp.frexp(value)

    scaled = mantissa * mp.power(2, precision)

    floor_value = mp.floor(scaled)
    fraction = scaled - floor_value

    integer = int(floor_value)

    if fraction > mp.mpf("0.5"):
        integer += 1
    elif fraction == mp.mpf("0.5"):
        if integer & 1:
            integer += 1

    if integer == (1 << precision):
        integer >>= 1
        exponent += 1

    result = (
        mp.mpf(integer)
        * mp.power(
            2,
            exponent - precision,
        )
    )

    return result if sign > 0 else -result


def represented(value: str, scalar: str) -> mp.mpf:
    """
    Reconstruct the exact public binary scalar represented by a driver's
    sufficiently precise decimal rendering.
    """

    return round_binary(
        mp.mpf(value),
        SCALAR_PRECISION[scalar],
    )


def public_pi(scalar: str) -> mp.mpf:
    return round_binary(
        mp.pi,
        SCALAR_PRECISION[scalar],
    )


def semantic_longitude(
    value: mp.mpf,
    scalar: str,
) -> mp.mpf:
    """
    Mirror the PM-D public cardinal semantics when lifting public longitude
    into exact oracle arithmetic.
    """

    p_public = public_pi(scalar)
    hp_public = p_public / 2

    if value == 0:
        return mp.mpf("0")

    if value == p_public:
        return mp.pi

    if value == -p_public:
        return -mp.pi

    if value == hp_public:
        return mp.pi / 2

    if value == -hp_public:
        return -mp.pi / 2

    return value


def canonical_delta(
    longitude: mp.mpf,
    longitude0: mp.mpf,
) -> mp.mpf:
    delta = longitude - longitude0

    two_pi = 2 * mp.pi

    while delta >= mp.pi:
        delta -= two_pi

    while delta < -mp.pi:
        delta += two_pi

    if delta == 0:
        return mp.mpf("0")

    return delta


def output_spacing(
    x: mp.mpf,
    precision: int,
) -> mp.mpf | None:
    if x == 0:
        return None

    exponent = int(
        mp.floor(
            mp.log(
                abs(x),
                2,
            )
        )
    )

    return mp.power(
        2,
        exponent - (precision - 1),
    )


def decimal_wrap_longitude(
    longitude0: str,
    delta: str,
) -> str:
    value = (
        Decimal(longitude0)
        + Decimal(delta)
    )

    full = Decimal("360")
    half = Decimal("180")

    while value >= half:
        value -= full

    while value < -half:
        value += full

    return format(
        value,
        "f",
    )


def generate_requests():
    metadata = {}
    lines = []

    for scalar in (
        "float",
        "double",
        "real",
    ):
        for profile in PROFILES:
            cases = list(CASES)

            if profile.name in {
                "unit_zero",
                "wgs84_zero",
            }:
                cases += ZERO_ONLY_CASES

            for case in cases:
                if case.absolute_longitude is not None:
                    longitude = (
                        case.absolute_longitude
                    )
                else:
                    longitude = (
                        decimal_wrap_longitude(
                            profile.lon0,
                            case.delta_longitude,
                        )
                    )

                identifier = (
                    f"{scalar}__"
                    f"{profile.name}__"
                    f"{case.name}"
                )

                line = " ".join(
                    [
                        "F",
                        identifier,
                        scalar,
                        profile.a,
                        profile.lon0,
                        profile.fe,
                        profile.fn,
                        case.latitude,
                        longitude,
                    ]
                )

                lines.append(line)

                metadata[identifier] = {
                    "scalar": scalar,
                    "profile": profile,
                    "case": case,
                    "input_lat_deg":
                        case.latitude,
                    "input_lon_deg":
                        longitude,
                }

    return (
        "\n".join(lines) + "\n",
        metadata,
    )


def parse_driver_output(text: str):
    records = {}
    rejects = []
    errors = []

    for line in text.splitlines():
        if not line:
            continue

        fields = line.split("\t")

        kind = fields[0]

        if kind == "FOK":
            identifier = fields[1]
            scalar = fields[2]

            values = {}

            for item in fields[3:]:
                key, value = item.split(
                    "=",
                    1,
                )
                values[key] = value

            records[identifier] = (
                scalar,
                values,
            )

        elif kind == "REJECT":
            rejects.append(line)

        elif kind == "ERROR":
            errors.append(line)

        else:
            errors.append(
                "UNEXPECTED\t" + line
            )

    return records, rejects, errors


def run_driver(
    driver: Path,
    corpus: str,
) -> str:
    completed = subprocess.run(
        [str(driver)],
        input=corpus,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if completed.returncode != 0:
        print(
            completed.stderr,
            file=sys.stderr,
        )

        raise RuntimeError(
            f"D differential driver exited "
            f"{completed.returncode}"
        )

    return completed.stdout


def run_proj(
    profile: Profile,
    latitude_degrees: str,
    longitude_degrees: str,
):
    executable = shutil.which(
        "proj"
    )

    if executable is None:
        raise RuntimeError(
            "local `proj` executable not found"
        )

    command = [
        executable,
        "-f",
        "%.15f",
        "+proj=webmerc",
        f"+a={profile.a}",
        f"+b={profile.a}",
        f"+lon_0={profile.lon0}",
        f"+x_0={profile.fe}",
        f"+y_0={profile.fn}",
        "+units=m",
        "+no_defs",
    ]

    completed = subprocess.run(
        command,
        input=(
            f"{longitude_degrees} "
            f"{latitude_degrees}\n"
        ),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    if completed.returncode != 0:
        raise RuntimeError(
            "PROJ failed:\n"
            + completed.stderr
        )

    parts = (
        completed.stdout
        .strip()
        .split()
    )

    if len(parts) < 2:
        raise RuntimeError(
            "unexpected PROJ output: "
            + completed.stdout
        )

    return (
        mp.mpf(parts[0]),
        mp.mpf(parts[1]),
    )


def oracle_forward(
    scalar: str,
    values: dict[str, str],
):
    precision = (
        SCALAR_PRECISION[scalar]
    )

    a = represented(
        values["a"],
        scalar,
    )

    fe = represented(
        values["fe"],
        scalar,
    )

    fn = represented(
        values["fn"],
        scalar,
    )

    latitude = represented(
        values["lat_rad"],
        scalar,
    )

    longitude_public = represented(
        values["lon_rad"],
        scalar,
    )

    longitude0_public = represented(
        values["lon0_rad"],
        scalar,
    )

    longitude = semantic_longitude(
        longitude_public,
        scalar,
    )

    longitude0 = semantic_longitude(
        longitude0_public,
        scalar,
    )

    delta = canonical_delta(
        longitude,
        longitude0,
    )

    # Independent EPSG-literal northing form.
    #
    # Do not reuse the selected D formula:
    #
    #     asinh(tan(phi))
    #
    # This preserves analytical independence from PM-B/F2.
    q = mp.log(
        mp.tan(
            mp.pi / 4
            + latitude / 2
        )
    )

    exact_easting = (
        fe
        + a * delta
    )

    exact_northing = (
        fn
        + a * q
    )

    rounded_easting = round_binary(
        exact_easting,
        precision,
    )

    rounded_northing = round_binary(
        exact_northing,
        precision,
    )

    return {
        "a": a,
        "fe": fe,
        "fn": fn,
        "latitude": latitude,
        "longitude":
            longitude_public,
        "longitude0":
            longitude0_public,
        "delta": delta,
        "exact_e":
            exact_easting,
        "exact_n":
            exact_northing,
        "rounded_e":
            rounded_easting,
        "rounded_n":
            rounded_northing,
    }


def scientific(x: mp.mpf) -> str:
    return mp.nstr(
        x,
        18,
        min_fixed=0,
        max_fixed=0,
    )


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--driver",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--write-input",
        type=Path,
    )

    parser.add_argument(
        "--write-output",
        type=Path,
    )

    args = parser.parse_args()

    corpus, metadata = (
        generate_requests()
    )

    if args.write_input:
        args.write_input.write_text(
            corpus,
            encoding="utf-8",
        )

    output = run_driver(
        args.driver,
        corpus,
    )

    if args.write_output:
        args.write_output.write_text(
            output,
            encoding="utf-8",
        )

    records, rejects, errors = (
        parse_driver_output(output)
    )

    print(
        "=== PM-E1C1A FORWARD DIFFERENTIAL ==="
    )

    print(
        "requests:",
        len(metadata),
    )

    print(
        "FOK:",
        len(records),
    )

    print(
        "REJECT:",
        len(rejects),
    )

    print(
        "ERROR:",
        len(errors),
    )

    if rejects:
        print()
        print("=== REJECTS ===")
        for item in rejects:
            print(item)

    if errors:
        print()
        print("=== ERRORS ===")
        for item in errors:
            print(item)

    if len(records) != len(metadata) \
        or rejects \
        or errors:
        print(
            "FAIL: incomplete D forward corpus"
        )
        return 1

    statistics = defaultdict(
        lambda: {
            "count": 0,
            "rounded_e_matches": 0,
            "rounded_n_matches": 0,
            "max_e_abs": mp.mpf("0"),
            "max_n_abs": mp.mpf("0"),
            "max_e_round_ulp":
                mp.mpf("0"),
            "max_n_round_ulp":
                mp.mpf("0"),
            "max_e_total_ulp":
                mp.mpf("0"),
            "max_n_total_ulp":
                mp.mpf("0"),
            "worst_e": None,
            "worst_n": None,
        }
    )

    proj_count = 0
    proj_policy_skips = 0
    proj_max_dx = mp.mpf("0")
    proj_max_dy = mp.mpf("0")
    proj_worst_x = None
    proj_worst_y = None

    rounded_mismatches = []

    for identifier, metadata_item in (
        metadata.items()
    ):
        scalar, values = (
            records[identifier]
        )

        if scalar != metadata_item[
            "scalar"
        ]:
            raise RuntimeError(
                f"scalar mismatch for "
                f"{identifier}"
            )

        precision = (
            SCALAR_PRECISION[scalar]
        )

        oracle = oracle_forward(
            scalar,
            values,
        )

        d_e = represented(
            values["e"],
            scalar,
        )

        d_n = represented(
            values["n"],
            scalar,
        )

        e_abs = abs(
            d_e
            - oracle["exact_e"]
        )

        n_abs = abs(
            d_n
            - oracle["exact_n"]
        )

        e_round_delta = abs(
            d_e
            - oracle["rounded_e"]
        )

        n_round_delta = abs(
            d_n
            - oracle["rounded_n"]
        )

        e_spacing = output_spacing(
            oracle["rounded_e"],
            precision,
        )

        n_spacing = output_spacing(
            oracle["rounded_n"],
            precision,
        )

        if e_spacing is None:
            e_round_ulp = (
                mp.mpf("0")
                if e_round_delta == 0
                else mp.inf
            )

            e_total_ulp = (
                mp.mpf("0")
                if e_abs == 0
                else mp.inf
            )
        else:
            e_round_ulp = (
                e_round_delta
                / e_spacing
            )

            e_total_ulp = (
                e_abs
                / e_spacing
            )

        if n_spacing is None:
            n_round_ulp = (
                mp.mpf("0")
                if n_round_delta == 0
                else mp.inf
            )

            n_total_ulp = (
                mp.mpf("0")
                if n_abs == 0
                else mp.inf
            )
        else:
            n_round_ulp = (
                n_round_delta
                / n_spacing
            )

            n_total_ulp = (
                n_abs
                / n_spacing
            )

        stat = statistics[scalar]

        stat["count"] += 1

        if e_round_delta == 0:
            stat[
                "rounded_e_matches"
            ] += 1
        else:
            rounded_mismatches.append(
                (
                    identifier,
                    "E",
                    scalar,
                    e_round_ulp,
                    e_abs,
                )
            )

        if n_round_delta == 0:
            stat[
                "rounded_n_matches"
            ] += 1
        else:
            rounded_mismatches.append(
                (
                    identifier,
                    "N",
                    scalar,
                    n_round_ulp,
                    n_abs,
                )
            )

        if e_abs > stat["max_e_abs"]:
            stat["max_e_abs"] = e_abs
            stat["worst_e"] = identifier

        if n_abs > stat["max_n_abs"]:
            stat["max_n_abs"] = n_abs
            stat["worst_n"] = identifier

        if e_round_ulp \
            > stat["max_e_round_ulp"]:
            stat[
                "max_e_round_ulp"
            ] = e_round_ulp

        if n_round_ulp \
            > stat["max_n_round_ulp"]:
            stat[
                "max_n_round_ulp"
            ] = n_round_ulp

        if e_total_ulp \
            > stat["max_e_total_ulp"]:
            stat[
                "max_e_total_ulp"
            ] = e_total_ulp

        if n_total_ulp \
            > stat["max_n_total_ulp"]:
            stat[
                "max_n_total_ulp"
            ] = n_total_ulp

        profile = metadata_item[
            "profile"
        ]

        case = metadata_item[
            "case"
        ]

        if scalar == "double" \
            and profile.proj_compatible:
            if case.proj_policy_difference:
                proj_policy_skips += 1
            else:
                proj_e, proj_n = (
                    run_proj(
                        profile,
                        metadata_item[
                            "input_lat_deg"
                        ],
                        metadata_item[
                            "input_lon_deg"
                        ],
                    )
                )

                dx = abs(
                    d_e - proj_e
                )

                dy = abs(
                    d_n - proj_n
                )

                proj_count += 1

                if dx > proj_max_dx:
                    proj_max_dx = dx
                    proj_worst_x = (
                        identifier
                    )

                if dy > proj_max_dy:
                    proj_max_dy = dy
                    proj_worst_y = (
                        identifier
                    )

    print()
    print("=== HIGH-PRECISION ORACLE ===")

    for scalar in (
        "float",
        "double",
        "real",
    ):
        stat = statistics[scalar]

        print()
        print(scalar + ":")

        print(
            "  cases:",
            stat["count"],
        )

        print(
            "  correctly-rounded easting:",
            f'{stat["rounded_e_matches"]}/'
            f'{stat["count"]}',
        )

        print(
            "  correctly-rounded northing:",
            f'{stat["rounded_n_matches"]}/'
            f'{stat["count"]}',
        )

        print(
            "  max easting abs error:",
            scientific(
                stat["max_e_abs"]
            ),
            "worst=",
            stat["worst_e"],
        )

        print(
            "  max northing abs error:",
            scientific(
                stat["max_n_abs"]
            ),
            "worst=",
            stat["worst_n"],
        )

        print(
            "  max easting delta from "
            "correctly-rounded output [ulp]:",
            scientific(
                stat[
                    "max_e_round_ulp"
                ]
            ),
        )

        print(
            "  max northing delta from "
            "correctly-rounded output [ulp]:",
            scientific(
                stat[
                    "max_n_round_ulp"
                ]
            ),
        )

        print(
            "  max total easting oracle "
            "error [local output ulp]:",
            scientific(
                stat[
                    "max_e_total_ulp"
                ]
            ),
        )

        print(
            "  max total northing oracle "
            "error [local output ulp]:",
            scientific(
                stat[
                    "max_n_total_ulp"
                ]
            ),
        )

    print()
    print(
        "=== CORRECT-ROUNDING MISMATCHES ==="
    )

    if not rounded_mismatches:
        print(
            "none"
        )
    else:
        rounded_mismatches.sort(
            key=lambda item: (
                float(item[3])
                if mp.isfinite(item[3])
                else math.inf
            ),
            reverse=True,
        )

        print(
            "count:",
            len(rounded_mismatches),
        )

        for item in (
            rounded_mismatches[:30]
        ):
            identifier, axis, scalar, \
                ulp_delta, abs_error = item

            print(
                f"  {identifier} "
                f"axis={axis} "
                f"scalar={scalar} "
                f"rounded_delta_ulp="
                f"{scientific(ulp_delta)} "
                f"abs_error="
                f"{scientific(abs_error)}"
            )

    print()
    print("=== PROJ DOUBLE DIFFERENTIAL ===")

    print(
        "ordinary compatible cases:",
        proj_count,
    )

    print(
        "intentional policy skips:",
        proj_policy_skips,
    )

    print(
        "max |D-PROJ| easting:",
        scientific(
            proj_max_dx
        ),
        "m",
        "worst=",
        proj_worst_x,
    )

    print(
        "max |D-PROJ| northing:",
        scientific(
            proj_max_dy
        ),
        "m",
        "worst=",
        proj_worst_y,
    )

    print()
    print("=== PM-E1C1A RESULT ===")

    print(
        "CHARACTERIZATION COMPLETE"
    )

    print(
        "No final accuracy budget is selected "
        "by PM-E1C1A."
    )

    print(
        "Use these maxima to define the "
        "next explicit differential gate."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
